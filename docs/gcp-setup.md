# GCP setup: MCP servers + multi-account credentials

The Security Genie connects to three MCP servers:

| Server | Package | Gives the agent |
|---|---|---|
| **gcloud** | [`@google-cloud/gcloud-mcp`](https://github.com/googleapis/gcloud-mcp) (npm) | Read-only inspection of any GCP project via the local `gcloud` CLI |
| **SecOps** | [`google-secops-mcp`](https://pypi.org/project/google-secops-mcp/) (PyPI, from [google/mcp-security](https://github.com/google/mcp-security)) | Google SecOps (Chronicle): UDM search, detections, alerts, IoC matches |
| **GTI** | [`gti-mcp`](https://pypi.org/project/gti-mcp/) (PyPI, same repo) | Google Threat Intelligence / VirusTotal: file, domain, IP, URL reputation and threat-actor context |

`gcloud` answers *"what is deployed and how is it configured"*. SecOps answers
*"what happened in this environment"*. GTI answers *"is this indicator known-bad,
and who uses it"*. A threat model or security review that cites all three is
evidence-backed in a way none of them is alone.

Whatever identity `gcloud` is configured with is the identity the agent gets —
which is why credential hygiene matters.

## Prerequisites

```bash
gcloud --version          # Google Cloud CLI
node --version            # Node 18+ (for npx — gcloud MCP)
uv --version              # uv/uvx (for the SecOps and GTI servers)
python3 --version         # Python 3.11+ required by both Python servers
gcloud auth login
gcloud auth application-default login
```

`uv` install (no sudo, no pipe-to-shell — the guard hook blocks that pattern on
purpose): follow <https://docs.astral.sh/uv/getting-started/installation/>, or
`pipx install uv`.

Smoke-test each server:

```bash
npx -y @google-cloud/gcloud-mcp --help
uvx --from google-secops-mcp secops_mcp --help
uvx --from gti-mcp gti_mcp --help
```

## MCP config per agent

The repo ships ready-to-use project-level configs holding all three servers —
identical except for file format (and the Codex secret caveat below):

| Agent | Project config | User-level config |
|---|---|---|
| Claude Code | `.mcp.json` (repo root) | `claude mcp add gcloud -- npx -y @google-cloud/gcloud-mcp` |
| Gemini CLI | `.gemini/settings.json` | `npx @google-cloud/gcloud-mcp init --agent=gemini-cli` |
| Antigravity (`agy`) | `.gemini/settings.json` (project, when supported) or import into global | `~/.gemini/antigravity/mcp_config.json` |
| Codex | `.codex/config.toml` (trusted projects only) | `~/.codex/config.toml` |

The server block, in every format, is:

```
command: npx
args:    ["-y", "@google-cloud/gcloud-mcp"]
env:     CLOUDSDK_ACTIVE_CONFIG_NAME = <profile>   # optional, pins the gcloud profile
```

Notes:

- Codex reads project config only for **trusted** projects; otherwise merge the
  `[mcp_servers.gcloud]` block into `~/.codex/config.toml`.
- Antigravity's global MCP config lives at `~/.gemini/antigravity/mcp_config.json`
  (same `mcpServers` JSON shape as `.mcp.json`). Copy the `gcloud` entry there
  for user-level availability.
- Verify after setup with `claude mcp list`, `gemini mcp list`, or
  `codex mcp list` respectively.
- Other official Google Cloud MCP servers (observability, Cloud Run, databases,
  ...) can be added the same way if you need them; `gcloud` alone covers the
  IaC- and config-level workflows in this pack.

## SecOps MCP and GTI MCP

Both ship from [google/mcp-security](https://github.com/google/mcp-security).
The repo also contains `scc` (Security Command Center) and `secops-soar`
servers — not wired up here, but they install the same way if you want them.

### Credentials each server needs

| Server | Variable | Where to get it |
|---|---|---|
| SecOps | `CHRONICLE_PROJECT_ID` | The GCP project your SecOps instance is bound to |
| SecOps | `CHRONICLE_CUSTOMER_ID` | SecOps UUID — SecOps UI → **Settings → Profile** (VERIFY the exact menu path for your UI version) |
| SecOps | `CHRONICLE_REGION` | `us`, `europe`, `asia-southeast1`, … — must match your instance |
| GTI | `VT_APIKEY` | Google Threat Intelligence / VirusTotal API key — <https://www.virustotal.com/gui/my-apikey> |

SecOps authenticates with **ADC**, so it inherits the same identity discipline as
the gcloud server. The reviewing identity needs Chronicle API read access — e.g.
`roles/chronicle.viewer` (VERIFY against your SecOps deployment; role names
differ between bring-your-own-project and Google-managed instances).

GTI authenticates with a **bare API key**, which is why it is treated
differently everywhere below.

### Never commit the GTI key

The repo configs reference variables, they do not contain values. Export them in
your shell (or a `direnv`/`.env` file that is git-ignored) before starting the
agent:

```bash
export CHRONICLE_PROJECT_ID=your-secops-project
export CHRONICLE_CUSTOMER_ID=01234567-abcd-4321-1234-0123456789ab
export CHRONICLE_REGION=us
export VT_APIKEY=...            # never echo this, never paste it in chat
```

- **Claude Code** — `.mcp.json` expands `${VAR}` and `${VAR:-default}`, so the
  committed file stays clean.
- **Gemini CLI / Antigravity** — `.gemini/settings.json` expands `$VAR` (VERIFY
  for your CLI version; if it does not, configure these two servers in the
  user-level config instead of the project one).
- **Codex** — `.codex/config.toml` does **not** expand variables (VERIFY). The
  committed file therefore configures `secops` with `REPLACE_ME` placeholders
  and leaves `gti` commented out. Put the real values in `~/.codex/config.toml`.

A leaked VT key is a real incident: it is a bearer credential with your quota and
your submission history attached. If one is ever pasted into a repo, rotate it
in the GTI UI first, then clean history.

### The invocation, in every format

```
gcloud    command: npx   args: ["-y", "@google-cloud/gcloud-mcp"]
secops    command: uvx   args: ["--from", "google-secops-mcp", "secops_mcp"]
gti       command: uvx   args: ["--from", "gti-mcp", "gti_mcp"]
```

`uvx` downloads and caches the package on first run, so no repo clone is needed.
If you prefer running from a clone (useful when you want to read the tool
source — recommended at least once, since you are about to let an agent call it):

```bash
git clone https://github.com/google/mcp-security
# command: uv   args: ["--directory", "<clone>/server/gti/gti_mcp", "run", "server.py"]
```

### Read-only posture

The gcloud server is constrained by the reviewing identity's IAM. SecOps and GTI
are **read/query oriented** but confirm for yourself before connecting them to a
customer tenant — inspect the tool list on first connect (`claude mcp list`, then
ask the agent to enumerate its SecOps tools) and treat anything that creates or
closes cases as out of bounds for review work. The `secops-soar` server, which
does have action tools, is deliberately not configured in this pack.

### GTI hygiene during a workshop

GTI lookups are **not private**. Submitting a customer's file hash, internal
domain, or IP to VirusTotal is a disclosure to a third-party corpus. During the
workshop use lab-supplied indicators only. In a real engagement, get explicit
written permission before enriching customer indicators, and prefer hash lookups
over file uploads.

## Multi-account credential management

### Model

- **Named gcloud configurations** are the profile mechanism. One per
  customer/account/environment, e.g. `acme-prod`, `acme-dev`, `globex-sandbox`.
- Each configuration pins an **account** and a default **project**.
- **ADC (Application Default Credentials) is a single global file** — it does
  *not* follow the active configuration. This is the #1 cause of "agent looked
  at the wrong customer".

### Create a profile

```bash
gcloud config configurations create acme-prod
gcloud config set account you@example.com      --configuration=acme-prod
gcloud config set project  acme-prod-123       --configuration=acme-prod
gcloud auth login                              --configuration=acme-prod
```

### Switch profiles

```bash
scripts/gcp-use.sh list                    # profiles + current identity
source scripts/gcp-use.sh acme-prod        # activate + export CLOUDSDK_ACTIVE_CONFIG_NAME
source scripts/gcp-use.sh acme-prod --adc  # also refresh ADC (browser)
```

`CLOUDSDK_ACTIVE_CONFIG_NAME` makes `gcloud` — and therefore the MCP server —
use that profile in the current shell. The MCP configs in this repo also accept
it as an `env` pin.

### ADC: two workable patterns

1. **User ADC, refreshed on switch** — run `gcloud auth application-default
   login` (or `scripts/gcp-use.sh <profile> --adc`) after every profile switch.
   Simple; easy to forget.
2. **Impersonated service account per customer** (recommended for real work):

   ```bash
   gcloud auth application-default login \
     --impersonate-service-account=sec-review@acme-prod-123.iam.gserviceaccount.com
   ```

   Your user needs `roles/iam.serviceAccountTokenCreator` on that SA. ADC then
   consistently acts as the review SA until you reset it
   (`gcloud auth application-default login` again or delete
   `~/.config/gcloud/application_default_credentials.json`).

Either way: **state the account and project in every review report**, and when
in doubt re-check:

```bash
gcloud config get-value account
gcloud config get-value project
gcloud auth list --filter=status:ACTIVE
```

## Troubleshooting

- `npx -y @google-cloud/gcloud-mcp --help` fails → Node/npm missing or proxy
  blocks the registry.
- `uvx` not found → install `uv` (see Prerequisites); `uvx` ships with it.
- SecOps/GTI server starts then immediately exits → almost always a missing env
  var. Check the agent's MCP log, then `echo ${VT_APIKEY:+set}` /
  `echo ${CHRONICLE_CUSTOMER_ID:+set}` (prints `set` without leaking the value).
- SecOps connects but every query returns empty → `CHRONICLE_REGION` does not
  match your instance, or ADC lacks Chronicle API access.
- GTI returns 401/403 → key wrong, revoked, or quota exhausted. Rotate rather
  than debug if the key has ever touched a shared machine.
- `uvx` needs Python 3.11+; on an older default interpreter pass
  `uvx --python 3.11 --from gti-mcp gti_mcp`.
- MCP "Connected" but answers are about the wrong project → active
  configuration or ADC mismatch; run `scripts/gcp-use.sh list`.
- Codex ignores `.codex/config.toml` → project not trusted, or server was added
  to project config while the CLI only watches the user file; merge into
  `~/.codex/config.toml`.
- Permission-denied errors from the agent are usually correct behavior: the
  review identity needs viewer-level roles (e.g. `roles/viewer`,
  `roles/iam.securityReviewer`, `roles/logging.viewer`) on the target.
