#!/usr/bin/env bash
# deploy.sh — build and deploy the Security Genie workshop hub.
#
# Reproduces the live deployment of security-genie.cedemo.app end to end:
# Cloud Run (LB-only ingress) -> serverless NEG -> backend service with IAP
# -> HTTPS load balancer with a Google-managed cert -> DNS.
#
# Idempotent: every resource is created only if absent, so re-running after a
# partial failure is safe. Run from the REPO ROOT — the image bakes in the
# workshop markdown and needs it in the build context.
#
#   ./site/deploy.sh              # build + deploy app only (the common case)
#   ./site/deploy.sh --infra      # also create/verify LB, cert, IAP, DNS
#
# Requires: gcloud authenticated with rights to deploy Cloud Run, manage
# compute LB resources and IAP in $PROJECT, and edit DNS in $DNS_PROJECT.
set -euo pipefail

PROJECT="${PROJECT:-zken-genai}"
REGION="${REGION:-us-central1}"
NAME="${NAME:-security-genie}"
SERVICE="${SERVICE:-security-genie-site}"
DOMAIN="${DOMAIN:-security-genie.cedemo.app}"
DNS_PROJECT="${DNS_PROJECT:-waap-demo-323809}"
DNS_ZONE="${DNS_ZONE:-cedemo-app}"
IAP_DOMAIN="${IAP_DOMAIN:-google.com}"
AR_REPO="${AR_REPO:-security-genie}"
TAG="${TAG:-$(date +%Y%m%d-%H%M%S)}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${AR_REPO}/${SERVICE}:${TAG}"
SA="${SERVICE}@${PROJECT}.iam.gserviceaccount.com"

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
have() { "$@" >/dev/null 2>&1; }

[[ -f AGENTS.md && -d site ]] || { echo "Run from the repo root." >&2; exit 1; }

# --------------------------------------------------------------------------
log "Prerequisites (APIs, service account, secrets)"

gcloud services enable run.googleapis.com compute.googleapis.com \
  secretmanager.googleapis.com iap.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com --project="$PROJECT" >/dev/null

have gcloud iam service-accounts describe "$SA" --project="$PROJECT" || \
  gcloud iam service-accounts create "$SERVICE" \
    --display-name="Security Genie workshop hub (Cloud Run)" --project="$PROJECT"

# Gate-2 token. Change it by adding a new secret version — the app binds
# sessions to a token fingerprint, so rotating evicts everyone automatically.
if ! have gcloud secrets describe "${NAME}-workshop-token" --project="$PROJECT"; then
  read -rsp "Workshop token (gate 2): " TOKEN; echo
  printf '%s' "$TOKEN" | gcloud secrets create "${NAME}-workshop-token" \
    --replication-policy=automatic --data-file=- --project="$PROJECT"
  unset TOKEN
fi

# Flask session-signing key. Rotating this invalidates all sessions.
if ! have gcloud secrets describe "${NAME}-session-secret" --project="$PROJECT"; then
  python3 -c "import secrets;print(secrets.token_urlsafe(48),end='')" \
    | gcloud secrets create "${NAME}-session-secret" \
        --replication-policy=automatic --data-file=- --project="$PROJECT"
fi

# Per-secret access, not a project-wide grant.
for s in "${NAME}-workshop-token" "${NAME}-session-secret"; do
  gcloud secrets add-iam-policy-binding "$s" \
    --member="serviceAccount:${SA}" --role=roles/secretmanager.secretAccessor \
    --project="$PROJECT" >/dev/null
done

# --------------------------------------------------------------------------
log "Build image  ($IMAGE)"

have gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" --project="$PROJECT" || \
  gcloud artifacts repositories create "$AR_REPO" --repository-format=docker \
    --location="$REGION" --description="Security Genie workshop hub" --project="$PROJECT"

# NB: --source deploy would pick Buildpacks; the Dockerfile lives in site/.
gcloud builds submit --config=site/cloudbuild.yaml \
  --substitutions=_IMAGE="$IMAGE" --project="$PROJECT" .

# --------------------------------------------------------------------------
log "Deploy Cloud Run"

# ingress=internal-and-cloud-load-balancing is load-bearing: it is what makes
# the run.app URL unreachable, so IAP cannot be bypassed and the
# X-Goog-Authenticated-User-Email header cannot be spoofed by a client.
gcloud run deploy "$SERVICE" \
  --image="$IMAGE" --project="$PROJECT" --region="$REGION" \
  --service-account="$SA" \
  --ingress=internal-and-cloud-load-balancing \
  --no-allow-unauthenticated \
  --set-secrets="WORKSHOP_TOKEN=${NAME}-workshop-token:latest,SESSION_SECRET=${NAME}-session-secret:latest" \
  --memory=512Mi --cpu=1 --min-instances=0 --max-instances=4 \
  --concurrency=80 --timeout=60 \
  --labels=app=security-genie,purpose=workshop

if [[ "${1:-}" != "--infra" ]]; then
  log "Done (app only). Re-run with --infra to verify LB/IAP/DNS."
  exit 0
fi

# --------------------------------------------------------------------------
log "Load balancer, certificate, IAP, DNS"

have gcloud compute addresses describe "${NAME}-ip" --global --project="$PROJECT" || \
  gcloud compute addresses create "${NAME}-ip" --global --ip-version=IPV4 --project="$PROJECT"
IP="$(gcloud compute addresses describe "${NAME}-ip" --global --project="$PROJECT" --format='value(address)')"

have gcloud compute network-endpoint-groups describe "${NAME}-neg" --region="$REGION" --project="$PROJECT" || \
  gcloud compute network-endpoint-groups create "${NAME}-neg" --region="$REGION" \
    --network-endpoint-type=serverless --cloud-run-service="$SERVICE" --project="$PROJECT"

if ! have gcloud compute backend-services describe "${NAME}-backend" --global --project="$PROJECT"; then
  gcloud compute backend-services create "${NAME}-backend" --global \
    --load-balancing-scheme=EXTERNAL_MANAGED --protocol=HTTP --project="$PROJECT"
  gcloud compute backend-services add-backend "${NAME}-backend" --global \
    --network-endpoint-group="${NAME}-neg" --network-endpoint-group-region="$REGION" \
    --project="$PROJECT"
fi

# DNS before the certificate: managed certs validate over HTTP against the
# domain, so provisioning stays stuck until the A record resolves.
if ! gcloud dns record-sets describe "${DOMAIN}." --type=A --zone="$DNS_ZONE" \
      --project="$DNS_PROJECT" >/dev/null 2>&1; then
  gcloud dns record-sets create "${DOMAIN}." --type=A --ttl=300 \
    --rrdatas="$IP" --zone="$DNS_ZONE" --project="$DNS_PROJECT"
fi

have gcloud compute ssl-certificates describe "${NAME}-cert" --global --project="$PROJECT" || \
  gcloud compute ssl-certificates create "${NAME}-cert" --global \
    --domains="$DOMAIN" --project="$PROJECT"

have gcloud compute url-maps describe "${NAME}-urlmap" --global --project="$PROJECT" || \
  gcloud compute url-maps create "${NAME}-urlmap" --default-service="${NAME}-backend" \
    --global --project="$PROJECT"

have gcloud compute target-https-proxies describe "${NAME}-https-proxy" --global --project="$PROJECT" || \
  gcloud compute target-https-proxies create "${NAME}-https-proxy" \
    --url-map="${NAME}-urlmap" --ssl-certificates="${NAME}-cert" --global --project="$PROJECT"

have gcloud compute forwarding-rules describe "${NAME}-https-fr" --global --project="$PROJECT" || \
  gcloud compute forwarding-rules create "${NAME}-https-fr" --address="${NAME}-ip" \
    --global --target-https-proxy="${NAME}-https-proxy" --ports=443 \
    --load-balancing-scheme=EXTERNAL_MANAGED --project="$PROJECT"

# Port 80 redirects; it never serves content.
if ! have gcloud compute url-maps describe "${NAME}-redirect" --global --project="$PROJECT"; then
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
name: ${NAME}-redirect
defaultUrlRedirect:
  httpsRedirect: true
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
  stripQuery: false
EOF
  gcloud compute url-maps import "${NAME}-redirect" --source="$tmp" --global \
    --quiet --project="$PROJECT"
  rm -f "$tmp"
fi

have gcloud compute target-http-proxies describe "${NAME}-http-proxy" --global --project="$PROJECT" || \
  gcloud compute target-http-proxies create "${NAME}-http-proxy" \
    --url-map="${NAME}-redirect" --global --project="$PROJECT"

have gcloud compute forwarding-rules describe "${NAME}-http-fr" --global --project="$PROJECT" || \
  gcloud compute forwarding-rules create "${NAME}-http-fr" --address="${NAME}-ip" \
    --global --target-http-proxy="${NAME}-http-proxy" --ports=80 \
    --load-balancing-scheme=EXTERNAL_MANAGED --project="$PROJECT"

# ---- Gate 1 -------------------------------------------------------------
# IAP must use a CUSTOM OAuth client. With the Google-managed client, browser
# sign-in fails with "Error code 11" while every command-line check still looks
# healthy. Create the client in the Console (see site/README.md), then either
# export these two vars or run site/set-iap-oauth-client.sh afterwards.
if [[ -n "${IAP_OAUTH_CLIENT_ID:-}" && -n "${IAP_OAUTH_CLIENT_SECRET:-}" ]]; then
  gcloud compute backend-services update "${NAME}-backend" --global \
    --iap="enabled,oauth2-client-id=${IAP_OAUTH_CLIENT_ID},oauth2-client-secret=${IAP_OAUTH_CLIENT_SECRET}" \
    --project="$PROJECT"
else
  gcloud compute backend-services update "${NAME}-backend" --global \
    --iap=enabled --project="$PROJECT"
  existing="$(gcloud compute backend-services describe "${NAME}-backend" --global \
    --project="$PROJECT" --format='value(iap.oauth2ClientId)')"
  if [[ -z "$existing" ]]; then
    echo "WARNING: IAP is using the Google-managed OAuth client. Browser sign-in" >&2
    echo "         will fail with Error code 11. Run site/set-iap-oauth-client.sh." >&2
  fi
fi

gcloud iap web add-iam-policy-binding --resource-type=backend-services \
  --service="${NAME}-backend" --member="domain:${IAP_DOMAIN}" \
  --role=roles/iap.httpsResourceAccessor --project="$PROJECT" >/dev/null

# Only the IAP service agent may invoke Cloud Run — never allUsers. This is
# what stops a direct-to-Cloud-Run request from skipping gate 1.
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
gcloud run services add-iam-policy-binding "$SERVICE" --region="$REGION" \
  --project="$PROJECT" --role=roles/run.invoker \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-iap.iam.gserviceaccount.com" >/dev/null

log "Status"
gcloud compute ssl-certificates describe "${NAME}-cert" --global --project="$PROJECT" \
  --format='value(managed.status)'
cat <<EOF

  URL   https://${DOMAIN}
  IP    ${IP}
  Gate1 IAP, domain:${IAP_DOMAIN}
  Gate2 workshop token (secret ${NAME}-workshop-token)

A managed certificate takes 15-30 minutes to go ACTIVE after DNS resolves.
Until then the domain returns a TLS error; that is expected, not a failure.
EOF
