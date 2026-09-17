# Security Genie

A portable security-specialist harness + skill pack for common coding agents — **Claude Code**, **Google Antigravity (`agy`)**, **OpenAI Codex**, and **Gemini CLI**. Drop it into a repo (or install it globally) and the agent becomes a Google Cloud platform security specialist that can:

- answer commonly asked security questions,
- threat-model architectures,
- run security reviews and well-architected (Google Cloud Architecture Framework) reviews,
- assess conformance to the Google Cloud Minimum Viable Secure Platform (GCMVSP) checklist,
- audit Terraform IAM for least privilege and generate secure-by-default Terraform,
- translate security jargon and prepare for customer security objections,
- work against live GCP environments via the official [`gcloud` MCP server](https://github.com/googleapis/gcloud-mcp), plus the [SecOps and GTI MCP servers](https://github.com/google/mcp-security) for detection history and threat intelligence, with sane multi-account credential handling.

## Two ways to use this repo

| | **Build your own** | **Use ours** |
|---|---|---|
| Start at | [`labs/`](labs/) | [Quickstart](#quickstart) below |
| You do | Write your own harness, skills, and MCP wiring against a spec, then compare | `./install.sh` |
| You get | A genie you understand and can extend | A working genie in ~2 minutes |
| Time | ~3 hours, 4 labs | 2 minutes |

The workshop runs the **left** column. Everything at the repo root —
`AGENTS.md`, `skills/`, `hooks/`, `docs/` — is the **reference implementation**:
one defensible set of answers, not the answer. Each lab hands you a spec and a
self-gradeable acceptance test, and points at the reference only afterwards.

## Layout

```
AGENTS.md                 # canonical harness: persona, operating principles, skill index
CLAUDE.md / GEMINI.md     # thin adapters that import AGENTS.md
.mcp.json                 # Claude Code MCP config (gcloud + SecOps + GTI)
.gemini/settings.json     # Gemini CLI / Antigravity MCP config
.codex/config.toml        # Codex project MCP config
skills/<name>/SKILL.md    # portable agent skills (cross-agent SKILL.md standard)
labs/                     # build-your-own workshop track (4 labs, spec + acceptance test)
scripts/gcp-use.sh        # multi-account gcloud profile switcher
scripts/run-sast.sh       # SAST wrapper: Semgrep (code) + Checkov/Trivy/tfsec (Terraform)
hooks/                    # pre-exec guard hook + per-agent settings (blocks dangerous commands)
install.sh                # installs harness + skills into agent-specific locations
docs/gcp-setup.md         # MCP servers (gcloud/SecOps/GTI) + multi-account credential guide
docs/facilitator-guide.md # facilitator guide: skills rationale + deployment
docs/smoke-test-runbook.md # proving generated IaC deploys, in a disposable project
docs/handover/            # deployment-guide and architecture doc templates
examples/flawed-agent-app/ # deliberately insecure GCP architecture for practicing the skills
site/                     # the workshop hub (Cloud Run + IAP), served at <SITE_HOST>
```

## Quickstart

Prereqs: `gcloud` CLI authenticated (`gcloud auth login && gcloud auth application-default login`) and Node.js/npm for `npx`.

From this directory:

- **Claude Code** — works out of the box: reads `CLAUDE.md` → `AGENTS.md`, discovers skills via `.claude/skills`, and picks up the project `.mcp.json` (approve it when prompted).
- **Antigravity (`agy`)** — reads `AGENTS.md` natively, discovers skills via `.agents/skills`. Add the MCP server from `.gemini/settings.json` to your Antigravity MCP config (see `docs/gcp-setup.md`).
- **Codex** — reads `AGENTS.md` natively; mark the project trusted so `.codex/config.toml` (gcloud MCP) loads.
- **Gemini CLI** — reads `GEMINI.md` → `AGENTS.md`, MCP via `.gemini/settings.json`.

To install into another repo or globally:

```bash
./install.sh                          # all agents, current directory
./install.sh --agent claude           # Claude Code only
./install.sh --agent codex --target ~/work/customer-repo
./install.sh --agent all --global     # user-level (all repos)
./install.sh --link                   # symlink skills instead of copying
```

## Skills

| Skill | Trigger |
|---|---|
| `security-faq` | "Is data encrypted at rest by default?", "VPC SC vs private Google access?" |
| `threat-model` | "Threat-model this architecture" (diagram, Terraform, or live project) |
| `security-review` | "Review this Terraform / project / design for security issues" |
| `well-architected-review` | "Assess this workload against the Google Cloud Architecture Framework" |
| `gcmvsp-review` | "GCMVSP gap analysis", "are we meeting Google's security baseline?" |
| `terraform-least-privilege-review` | "Audit this Terraform IAM for least privilege" |
| `terraform-secure-generator` | "Generate secure Terraform for <workload>" |
| `sast-scan` | "Run semgrep on this repo", "checkov this Terraform", "SAST before review" |
| `security-jargon-translator` | "Explain this to the CFO / an auditor / the customer's dev team" |
| `security-objection-handling` | "Customer says cloud is less secure than on-prem — prep me" |

## GCP access & multi-account credentials

Three MCP servers: `@google-cloud/gcloud-mcp` (what is deployed), `google-secops-mcp` (what happened), `gti-mcp` (is this indicator known-bad). The last two come from [google/mcp-security](https://github.com/google/mcp-security) and run via `uvx`; they need `CHRONICLE_*` and `VT_APIKEY` environment variables, which the committed configs reference but never contain.

Multi-account work is handled with named gcloud configurations:

```bash
scripts/gcp-use.sh list                 # show profiles and current identity
source scripts/gcp-use.sh acme-prod     # switch profile in this shell
```

Full setup — including per-agent MCP config locations, ADC caveats, and service-account impersonation — is in [`docs/gcp-setup.md`](docs/gcp-setup.md).

## Guardrails baked into the harness

- Read-only by default: no resource or IAM changes without an explicit ask.
- Pre-exec guard hooks block dangerous shell commands mid-turn (`rm -rf`, package installs, pipe-to-shell, `terraform apply/destroy`, destructive git, sudo) until the user consents — see `hooks/` and the [facilitator guide](docs/facilitator-guide.md).
- Evidence before opinion: inspect live state via gcloud MCP before answering environment-specific questions; state assumptions otherwise.
- No secrets in output, ever; findings cite severity, evidence, remediation, and a reference.
