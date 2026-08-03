# Security Genie labs — build your own

This repo can be used two ways. Pick deliberately.

| | **Build your own** (this directory) | **Use ours** (repo root) |
|---|---|---|
| What you do | Write your own `AGENTS.md`, your own skills, your own MCP wiring, against a spec | `./install.sh` and start working |
| You end with | A genie you understand and can extend, shaped like your practice | A working genie in about two minutes |
| Good for | The workshop; anyone who will maintain or extend this | Getting value today; a customer engagement next week |
| Time | ~3 hours across 4 labs | 2 minutes |

**The workshop runs the left column.** The right column — `AGENTS.md`,
`skills/`, `hooks/`, `docs/` — is the **reference implementation**. It is one
defensible set of answers, not the answer. Diverging from it deliberately is a
pass; matching it by copying is not.

## How each lab works

Every lab has the same four parts:

1. **Goal** — what capability the genie gains, and why a CE needs it.
2. **Spec** — the requirements your build must satisfy. Requirements, not steps.
3. **Acceptance test** — a prompt you run against *your* genie, and the
   properties the answer must have. Self-gradeable. This is the real deliverable.
4. **Compare** — the reference file to read **after** you pass, plus the
   design decisions in it worth arguing with.

Read *Compare* last. Reading it first turns the lab into transcription and you
will not learn where the sharp edges are.

## Ground rules

- **Do not copy `skills/` into your build.** Read it after each lab. If your
  version is better, say so — the reference has been wrong before.
- **Cite or mark `(VERIFY)`.** The single most damaging failure mode in this
  domain is a confidently invented IAM role or org-policy constraint. Every lab
  is graded partly on whether your genie hedges honestly.
- **Read-only against anything you did not create.** Labs 1–3 touch no cloud
  state. Lab 4 creates state only in a disposable project you own.
- **No real customer data, ever** — not in prompts, not in GTI lookups, not in
  the example app.

## The labs

| # | Lab | Time | Builds |
|---|---|---|---|
| 1 | [Harness and MCP](lab-1-harness-and-mcp.md) | 30 min | Persona + operating rules, gcloud/SecOps/GTI MCP, guard hook |
| 2 | [Architecture and IaC skills](lab-2-architecture-and-iac-skills.md) | 45 min | Well-architected, GCMVSP, Terraform least-privilege review + generation |
| 3 | [Conversation skills](lab-3-conversation-skills.md) | 45 min | Jargon translator, objection handling |
| 4 | [Genie at work](lab-4-genie-at-work.md) | 60 min | End-to-end on a flawed architecture → smoke-tested IaC → handover pack |

Labs are cumulative — lab 4 uses everything from 1–3.

## Setup (before lab 1)

```bash
gcloud --version && node --version && python3 --version && uv --version
gcloud auth login
gcloud auth application-default login
```

You need: a GCP project you can read, and for lab 4 the ability to create a
disposable project (or one pre-created by the facilitator). Python 3.11+ for the
SecOps/GTI MCP servers. Full setup, including credentials for SecOps and GTI:
[`../docs/gcp-setup.md`](../docs/gcp-setup.md).

Start your build in a clean directory — not this repo, so you are not tempted:

```bash
mkdir ~/my-security-genie && cd ~/my-security-genie && git init
```

## Which agent

Any of Claude Code, Antigravity (`agy`), Codex, or Gemini CLI. The labs are
written agent-neutrally; where a path differs, the table in
[`../docs/facilitator-guide.md`](../docs/facilitator-guide.md) has the mapping.
Working in a pair on two different agents is a good idea — the differences in
where skills live and when they trigger are half the lesson.

## Self-assessment

At the end, score your build:

| Property | How you know |
|---|---|
| Skills trigger without being named | You asked a natural question and the right skill loaded |
| Findings carry evidence | Every finding has `file:line` or a resource ID |
| Uncertainty is marked | The genie wrote `(VERIFY)` at least once, correctly |
| It refuses to change state | It stopped and asked before `terraform apply` |
| A colleague can run it | Someone else cloned your repo and got the same behavior |

Five out of five is the bar. Four means one specific thing to fix, and you know
which.
