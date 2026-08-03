# Acme Corp support agent — flawed example architecture

> **WARNING: This architecture is deliberately insecure.**
> It exists for security-review practice only. **Never deploy it as-is**
> to any GCP project. If you deploy anything, deploy the *fixed* version
> (exercise step 5–6) to a disposable smoke-test project, and tear it down
> afterwards.

This directory contains a "customer-provided" architecture for the
**Acme Corp support agent**: an LLM-backed support-agent service. It was
written in good faith by a careless team and is full of realistic
mistakes. Your job is to find them, explain them, and fix them.

## Architecture

```
                        ┌─────────── Internet ───────────┐
                        │                                │
              HTTP :80 (no TLS anywhere)      TCP 22/3389 from 0.0.0.0/0
                        │                                │
                        v                                v
              ┌───────────────────┐          ┌────────────────────────┐
              │ External HTTP LB  │          │ Bastion VM (e2-micro)  │
              │ (no Cloud Armor)  │          │ external IP, serial    │
              └─────────┬─────────┘          │ port on, default SA    │
                        │                    └────────────────────────┘
                        v
              ┌───────────────────┐    DB_HOST = public IP
              │ Cloud Run "agent" │───────────────┐
              │ FastAPI + LLM     │               │
              │ ingress=all       │               v
              │ allUsers invoker  │    ┌────────────────────────┐
              │ default compute SA│    │ Cloud SQL Postgres 15  │
              │ DB password in    │    │ public IP, authorized  │
              │ plaintext env var │    │ networks 0.0.0.0/0,    │
              └─────────┬─────────┘    │ no SSL required,       │
                        │              │ backups off            │
                        v              └────────────────────────┘
              ┌───────────────────┐
              │ GCS bucket        │    allUsers: roles/storage.objectViewer
              │ "<pid>-agent-     │
              │  exports"         │
              └───────────────────┘
```

## Layout

- `terraform/` — the full infrastructure as the customer wrote it
  (hashicorp/google `~> 6.0`, `terraform validate`-clean)
- `app/` — the agent service: FastAPI (`main.py`), `requirements.txt`,
  `Dockerfile`

## Exercise

Work through the repo skills in this order (see the skills table in the
top-level `AGENTS.md`):

1. **`sast-scan`** — run the scanners over this directory: Semgrep on
   `app/`, Checkov/Trivy/tfsec on `terraform/` and `app/Dockerfile`.
   Triage what they find.
2. **`terraform-least-privilege-review`** — audit `terraform/` for IAM
   least-privilege violations.
3. **`security-review`** — a full read-only review of the Terraform and
   the app. Catch what the scanners missed.
4. **`threat-model`** — model the architecture: trust boundaries,
   STRIDE per element, and which findings chain together into real
   attack paths.
5. **Fix it with `terraform-secure-generator`** — regenerate the stack
   as secure-by-default, least-privilege Terraform.
6. **Optional:** deploy the **fixed** version to a disposable smoke-test
   GCP project, verify it works, then tear it down.

## Facilitator key

`EXPECTED-FINDINGS.md` lists every planted flaw with expected severity
and which tool or skill should catch it. Facilitators use it to score
completeness — if you're doing the exercise, don't read it first.
