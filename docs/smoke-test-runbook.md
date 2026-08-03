# Smoke-test runbook — proving the fixed IaC actually deploys

Session 4 ends with a handover pack. A deployment guide nobody has executed is a
guess. This runbook is how you turn generated Terraform into evidence, in a
throwaway project, without deploying anything exploitable.

**Hard rule: you smoke-test the *fixed* Terraform. Never the flawed original.**
`examples/flawed-agent-app/` contains a public bucket, an open bastion, and a
SQL-injectable app. Deploying it puts a real vulnerable service on the internet
under your org's name.

## 0. Guard-hook expectations

`terraform apply` and `terraform destroy` are blocked by
`hooks/dangerous_command_guard.py`. This is intentional and it is the teaching
moment: the agent must stop and ask you before it changes cloud state. Two
sanctioned ways through:

1. **You run the apply** — the agent prepares the plan, explains the diff, and
   you execute it. Preferred for the workshop.
2. **You consent explicitly** — tell the agent to proceed for a named command in
   a named project. Consent is per-command, not a standing grant.

Never disable the hook to make an exercise flow faster. If it fires, that is the
exercise working.

## 1. Create a disposable project

```bash
PROJECT_ID="sg-smoke-$(whoami)-$(date +%m%d)"       # short-lived, obviously scratch
BILLING_ACCOUNT="<your billing account ID>"
REGION="us-central1"

gcloud projects create "$PROJECT_ID"
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
gcloud config set project "$PROJECT_ID"
```

Requirements before you start:

- Your own sandbox or a designated workshop folder — **never** a customer
  project, never a shared demo project that other people depend on.
- Permission to create projects and link billing. If you do not have it, ask the
  facilitator for a pre-created project rather than borrowing one.
- A billing budget with an alert. Cloud SQL and a load balancer are not free and
  the whole point is that you will forget this project exists.

Enable only what the module needs:

```bash
gcloud services enable \
  compute.googleapis.com run.googleapis.com sqladmin.googleapis.com \
  secretmanager.googleapis.com artifactregistry.googleapis.com \
  servicenetworking.googleapis.com iam.googleapis.com --project="$PROJECT_ID"
```

## 2. Remote state, not local

```bash
gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${PROJECT_ID}-tfstate"
gsutil versioning set on "gs://${PROJECT_ID}-tfstate"
```

Point the `backend "gcs"` block at it. Rationale worth saying out loud:
Terraform state contains generated passwords and resource metadata in plaintext.
A local `terraform.tfstate` in a workshop repo is a credential leak waiting for
a `git add -A`. Confirm `*.tfstate*` is git-ignored before the first apply.

## 3. Static gates before any apply

Run these first; they are free and they catch most of what a plan would.

```bash
terraform fmt -check -recursive
terraform init
terraform validate
scripts/run-sast.sh <terraform-dir>          # Checkov / Trivy / tfsec
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json    # machine-readable for review
```

Have the agent review `tfplan.json` before you apply — that is a
`security-review` pass on the *plan*, and it catches things the HCL review
missed (e.g. a module default that materialises as a public IP).

Gate: **zero Critical/High from the SAST pass, or a written exception per
finding.** Do not apply through a Critical.

## 4. Apply

```bash
terraform apply tfplan
```

Expect this to fail the first time or three. Common, real causes:

| Symptom | Cause |
|---|---|
| `Error 403: ... API has not been used` | Missing `gcloud services enable` for a transitively required API |
| Cloud SQL private IP hangs then fails | Service Networking VPC peering not created, or created in the wrong order |
| `Error creating Connector` | Serverless VPC Access connector CIDR overlaps an existing subnet |
| IAM binding "does not exist" | Service account created in the same apply — needs `depends_on` or a data source |
| Org policy violation on external IP / resource location | The sandbox inherits org constraints; this is a *finding about the module's portability*, record it |

Every failure is handover content. The customer will hit the same ones.

## 5. Verify the security properties, not just `Apply complete`

`terraform apply` succeeding proves the syntax. It does not prove the controls
work. Verify the claims the security decision log makes — at minimum:

```bash
# Cloud Run must not be publicly invokable
gcloud run services get-iam-policy <svc> --region="$REGION" --project="$PROJECT_ID"
# expect: no allUsers / allAuthenticatedUsers

# Direct hit on the run.app URL should fail if ingress is LB-only
curl -s -o /dev/null -w '%{http_code}\n' "$(gcloud run services describe <svc> \
  --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')"

# Cloud SQL must have no public IP and require TLS
gcloud sql instances describe <inst> --project="$PROJECT_ID" \
  --format='value(settings.ipConfiguration.ipv4Enabled,settings.ipConfiguration.requireSsl)'

# Buckets must be uniform-access and non-public
gcloud storage buckets describe gs://<bucket> --project="$PROJECT_ID" \
  --format='value(iamConfiguration.uniformBucketLevelAccess.enabled)'
gcloud storage buckets get-iam-policy gs://<bucket> --project="$PROJECT_ID"

# No service account keys should exist
for sa in $(gcloud iam service-accounts list --project="$PROJECT_ID" --format='value(email)'); do
  gcloud iam service-accounts keys list --iam-account="$sa" \
    --managed-by=user --project="$PROJECT_ID"
done

# No primitive roles at project level
gcloud projects get-iam-policy "$PROJECT_ID" --format=json \
  | grep -E 'roles/(owner|editor|viewer)' || echo "no primitive roles"
```

Record each check as pass/fail with its output. **That table is the deliverable** —
it is what lets the customer trust the module without re-reviewing it.

Then re-run the review skills against the live project and confirm the findings
that started the exercise are gone:

```
Use the security-review skill against project $PROJECT_ID.
Compare against examples/flawed-agent-app/EXPECTED-FINDINGS.md — which of the
27 planted findings are closed, and which reappeared in the fixed version?
```

## 6. Tear down — same session, no exceptions

```bash
terraform destroy
gcloud projects delete "$PROJECT_ID"
```

`terraform destroy` is guard-blocked too; consent explicitly. Deleting the
project is the belt-and-braces step because `destroy` misses anything created
outside Terraform (that stray `gcloud services enable`, a console click, the
state bucket).

Verify nothing survives:

```bash
gcloud projects describe "$PROJECT_ID" --format='value(lifecycleState)'   # DELETE_REQUESTED
```

Projects sit in `DELETE_REQUESTED` for ~30 days and can be undeleted — so also
confirm the billing link is gone if cost matters.

Checklist before you close the laptop:

- [ ] `terraform destroy` completed or project deleted
- [ ] State bucket removed
- [ ] No SA keys were created; if any were, they are deleted **and** rotated
- [ ] DNS records / certs pointed at the smoke test removed
- [ ] Verification outputs saved into the handover pack (secrets redacted)

## 7. What goes into the handover

The smoke test produces three of the four handover artifacts. Templates:
[`handover/DEPLOYMENT-GUIDE-template.md`](handover/DEPLOYMENT-GUIDE-template.md),
[`handover/ARCHITECTURE-template.md`](handover/ARCHITECTURE-template.md).

| Artifact | Sourced from |
|---|---|
| Fixed IaC | `terraform-secure-generator`, now proven to apply |
| Deployment guide | This run — real prerequisites, real error modes, real order |
| Architecture doc | `threat-model` + `security-review` output, updated to as-built |
| Security decision log | `terraform-secure-generator`, amended with what the smoke test forced you to change |

If the smoke test changed the Terraform, the decision log must say so. The delta
between "what we designed" and "what actually deployed" is the most useful page
in the pack.
