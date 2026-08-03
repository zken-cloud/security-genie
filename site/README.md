# security-genie.cedemo.app — the workshop hub

The participant-facing site for the Security Genie workshop. It renders this
repo's own markdown, so the site cannot drift from the material: labs, skills,
setup guide, facilitator guide, smoke-test runbook and handover templates all
come from the files next to it.

**Live:** <https://security-genie.cedemo.app>

## Two gates

| | Gate | Enforced by | Grants |
|---|---|---|---|
| 1 | **Identity-Aware Proxy** | Load balancer backend service | `domain:google.com` → `roles/iap.httpsResourceAccessor` |
| 2 | **Workshop token** | The app ([`app/main.py`](app/main.py)) | Anyone with the shared token |

Gate 1 is real authentication and authorisation. Gate 2 is a shared secret that
puts the material behind a deliberate act — it is **not** an authentication
system, and nothing on this site should matter if the token leaks.

The layering only works because of one setting: Cloud Run ingress is
`internal-and-cloud-load-balancing`, and the only `run.invoker` is the IAP
service agent. Without that, the `*.run.app` URL would serve the site with gate 1
skipped entirely, and the `X-Goog-Authenticated-User-Email` header the app
displays could be set by any client. **If you change ingress or add
`allUsers` as invoker, you have removed gate 1.**

## Architecture

```
  browser
    │  https://security-genie.cedemo.app        A → 8.232.118.254
    ▼
  Global external ALB (EXTERNAL_MANAGED)
    ├── :80  security-genie-http-proxy  → 301 redirect to HTTPS
    └── :443 security-genie-https-proxy → Google-managed cert
          │
          ▼
      security-genie-backend  ◀── GATE 1: IAP, domain:google.com
          │
          ▼
      security-genie-neg (serverless NEG, us-central1)
          │
          ▼
      Cloud Run: security-genie-site
        ingress: internal-and-cloud-load-balancing
        invoker: service-<num>@gcp-sa-iap.iam.gserviceaccount.com  (only)
        SA:      security-genie-site@zken-genai.iam.gserviceaccount.com
        secrets: WORKSHOP_TOKEN, SESSION_SECRET (Secret Manager)
          │
          ▼
      Flask app  ◀── GATE 2: workshop token → signed __Host- session cookie
```

Resources (project `zken-genai`, region `us-central1`; DNS in
`waap-demo-323809`, zone `cedemo-app`):

| Kind | Name |
|---|---|
| Cloud Run service | `security-genie-site` |
| Service account | `security-genie-site@zken-genai.iam.gserviceaccount.com` |
| Secrets | `security-genie-workshop-token`, `security-genie-session-secret` |
| Static IP | `security-genie-ip` — `8.232.118.254` |
| Serverless NEG | `security-genie-neg` |
| Backend service | `security-genie-backend` (IAP enabled) |
| URL maps | `security-genie-urlmap`, `security-genie-redirect` |
| Proxies | `security-genie-https-proxy`, `security-genie-http-proxy` |
| Forwarding rules | `security-genie-https-fr` (443), `security-genie-http-fr` (80) |
| Certificate | `security-genie-cert` (Google-managed) |
| Artifact Registry | `security-genie` |

## Deploy

From the **repo root** — the image bakes in the workshop markdown and needs it
in the build context:

```bash
./site/deploy.sh            # build + deploy the app (the common case)
./site/deploy.sh --infra    # also create/verify LB, cert, IAP, DNS
```

The script is idempotent: every resource is created only if absent, so
re-running after a partial failure is safe.

Content changed? Just re-run `./site/deploy.sh` — the markdown is copied into
the image at build time and rendered per request.

## Local development

```bash
python3 -m venv .venv && .venv/bin/pip install -r site/app/requirements.txt
CONTENT_ROOT="$PWD" WORKSHOP_TOKEN=any-local-value \
  .venv/bin/python site/app/main.py      # http://localhost:8080
```

`CONTENT_ROOT="$PWD"` points the renderer at the repo itself, so edits to labs
and skills show up on refresh. Gate 1 does not exist locally; the app shows no
IAP identity, which is the correct behaviour.

## Tests

```bash
.venv/bin/python site/tests/smoke_test.py
```

51 checks: gate-2 admission and rejection, open-redirect protection on the
`next` parameter, every content route, markdown link rewriting, security
headers, path traversal, session eviction on token rotation, fail-closed on
empty token config, and IAP header parsing. Run it before every deploy.

## IAP requires a custom OAuth client (Error code 11)

**Do not let IAP use the Google-managed OAuth client.** If you do, sign-in
reaches `https://security-genie.cedemo.app/?gcp-iap-mode=AUTHENTICATING&…` and
fails with:

> There was a problem with your request. Please reference
> https://cloud.google.com/iap/docs/faq#error_codes. **Error code 11**

Every other layer looks healthy — cert `ACTIVE`, DNS resolving, IAP IAM binding
present, `curl` returning `302` to `accounts.google.com`. Command-line checks
cannot detect this; only a completed browser sign-in can.

### Create the client

1. Console → **APIs & Services → Credentials** in `zken-genai`.
2. **Create credentials → OAuth client ID → Application type: Web application.**
   Name it after the site (`Security Genie`), matching the existing
   `CM CI Lab` / `CM Demo App` clients.
3. Create it, copy the **client ID**, then **edit** the client and add the
   authorized redirect URI:
   `https://iap.googleapis.com/v1/oauth/clientIds/<CLIENT_ID>:handleRedirect`
4. Apply it — the secret is prompted for, never passed as an argument:

   ```bash
   ./site/set-iap-oauth-client.sh <CLIENT_ID>
   ```

   Or export `IAP_OAUTH_CLIENT_ID` / `IAP_OAUTH_CLIENT_SECRET` before
   `./site/deploy.sh --infra`.

### Two traps

- **`gcloud iap oauth-clients create` is not a shortcut.** It still responds
  despite its turndown warning, but fails with `FAILED_PRECONDITION: Brand's
  Application type must be set to Internal`. **Do not flip the brand to
  Internal to satisfy it** — this project is in the `zken.altostrat.com` org, and
  Internal restricts sign-in to *that* org, locking out the `@google.com` users
  the site is granted to. Use the Console and leave the brand External.
- One client per site. Reusing another site's client mixes up consent screens
  and redirect URIs.

### Two more things that cost time

- **The secret cannot be fetched for you.** `gcloud iap oauth-clients describe`
  no longer returns the `secret` field. Use the prompt or file form of
  `set-iap-oauth-client.sh`; never pass it as an argument (process list).
- **The edge lags the API by ~1 minute.** Right after the update the backend
  reports the new client while the 302 still advertises the old one. Confirm the
  switchover before retrying sign-in:

  ```bash
  curl -s -o /dev/null -w '%{redirect_url}\n' https://security-genie.cedemo.app/ \
    | sed -E 's/^(.*client_id=[^&]*)&.*/\1/'
  ```

## Verification record — 2026-08-03

Run against the live deployment by `admin@zken.altostrat.com`.

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Managed certificate active | `gcloud compute ssl-certificates describe security-genie-cert --global` | `ACTIVE` |
| 2 | DNS resolves to the LB | `security-genie.cedemo.app` | `8.232.118.254` |
| 3 | Port 80 redirects to HTTPS | `curl -I http://security-genie.cedemo.app/` | `301` → `https://…` |
| 4 | **Gate 1 challenges anonymous users** | `curl https://security-genie.cedemo.app/` | `302` → `accounts.google.com` (IAP) |
| 5 | **Gate 1 cannot be bypassed via `run.app`** | `curl https://security-genie-site-…run.app/` | `403` |
| 6 | **Spoofed IAP identity header rejected** | same, with `X-Goog-Authenticated-User-Email` | `403` |
| 7 | IAP grants only `domain:google.com` | `gcloud iap web get-iam-policy` | one binding, `roles/iap.httpsResourceAccessor` |
| 8 | Sole Cloud Run invoker is the IAP service agent | `gcloud run services get-iam-policy` | no `allUsers`/`allAuthenticatedUsers` |
| 9 | Ingress is LB-only | `gcloud run services describe` | `internal-and-cloud-load-balancing` |
| 10 | No secrets in the image or repo | `gcloud run services describe` | `WORKSHOP_TOKEN`, `SESSION_SECRET` from Secret Manager |
| 11 | Gate-2 logic (51 checks) | `python3 site/tests/smoke_test.py` | all pass |
| 12 | IAP uses a **custom** OAuth client | `gcloud compute backend-services describe security-genie-backend --global` | `163236863044-qg3gkt1…` (was blank → Error code 11) |
| 13 | Edge serves that client in the OAuth 302 | `curl -o /dev/null -w '%{redirect_url}'` | `client_id=163236863044-qg3gkt1…` |

**Not verified from the command line:** the gate-2 form on the *live* URL. Doing
so requires completing IAP's browser sign-in as a `@google.com` account, which
`admin@zken.altostrat.com` is not — that account is correctly denied by check 7.
Gate-2 logic is covered by check 11 against the same code, but the first
`@google.com` visitor should confirm the end-to-end path: sign in with Google,
land on the token page, wrong token rejected, the live token admits.

The live token is **not in this repo**. It lives in Secret Manager
(`security-genie-workshop-token`) and reaches the app only as an environment
variable at runtime.

**This gap bit us.** The first browser sign-in failed with IAP **Error code 11**
(Google-managed OAuth client — see the section above), despite all eleven checks
above passing. Checks 1–11 verify that IAP is *engaged*; none of them verifies
that the OAuth flow *completes*. Treat a browser sign-in as a mandatory
twelfth check on every IAP site.

## Rotating the workshop token

```bash
printf 'newtoken' | gcloud secrets versions add security-genie-workshop-token \
  --data-file=- --project=zken-genai
gcloud run services update security-genie-site --region=us-central1 \
  --project=zken-genai --update-secrets=WORKSHOP_TOKEN=security-genie-workshop-token:latest
```

Sessions are bound to a fingerprint of the token in force, so rotating it
**evicts everyone immediately** — no need to also rotate the session secret.

## Security decisions

| Decision | Why |
|---|---|
| Ingress `internal-and-cloud-load-balancing`, IAP service agent as sole invoker | The only thing preventing gate-1 bypass via the `run.app` URL |
| Dedicated service account | Not the default compute SA; the app needs no GCP permissions beyond reading its two secrets |
| Per-secret `secretAccessor`, not project-wide | Least privilege; the SA cannot read other secrets in the project |
| Secrets in Secret Manager, injected as env vars | No token in the image, the repo, or `gcloud` history |
| `__Host-` cookie prefix, `HttpOnly`, `Secure`, `SameSite=Lax` | Cookie cannot be set by a subdomain or over plain HTTP |
| Session bound to token fingerprint | Rotation is an actual revocation, not just a new door |
| `hmac.compare_digest` for token comparison | Constant-time; avoids a timing oracle on a shared secret |
| `next` restricted to same-site relative paths | The gate would otherwise be an open redirect |
| CSP `default-src 'none'`, no JS, no external requests | Nothing to inject and nothing to exfiltrate to |
| Non-root UID 10001, read-only image tree | Standard container hardening |
| `noindex, nofollow` | Belt and braces behind IAP |
| `max-instances=4`, `MAX_CONTENT_LENGTH=16 KiB` | Cost and abuse ceiling on a site that serves static text |

**Honest limits.** The 0.5 s delay on a wrong token is not a rate limiter — a
determined attacker who is already inside gate 1 can grind it. That is accepted:
gate 2 defends against accidental sharing, not against a Google employee who has
decided to brute-force a workshop site. If this ever hosts anything sensitive,
replace gate 2 with an IAP IAM group rather than hardening the token.

## Adding a page

1. Add the markdown to the repo (`labs/`, `docs/`, …).
2. Add an entry to `PAGES` in [`app/main.py`](app/main.py):
   `"slug": ("path/from/repo/root.md", "Nav title", "Section")`.
3. If the Dockerfile does not already copy that directory into `/app/content`,
   add it — file-by-file, deliberately. The exercise app's Terraform is
   vulnerable by design and must never land in a running image.
4. `python3 site/tests/smoke_test.py`, then `./site/deploy.sh`.

Links between markdown files are rewritten to site routes automatically, and
`skills/<name>/SKILL.md` links resolve to `/skill/<name>`. A link to a repo file
the site does not publish falls back to the home page rather than 404ing.
