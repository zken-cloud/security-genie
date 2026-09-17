# Security Genie — Facilitator Guide

For anyone running the Security Genie workshop or rolling the harness out to a
team. Part 1 explains what was built and *why* — teach the reasoning, not just
the mechanics. Part 2 covers deploying and extending the skills on the harness.

## Running it as an open workshop

The workshop runs **build-your-own**, not follow-along. [`../labs/`](../labs/)
holds four labs; each gives participants a **spec** and a **self-gradeable
acceptance test**, and points at this repo's implementation only in a *Compare*
section at the end.

Why: a participant who transcribes `skills/security-review/SKILL.md` cannot
extend it next month. One who wrote their own version and then read ours knows
which decisions were forced and which were taste.

Your job as facilitator shifts accordingly:

- **Do not demo the solution first.** Set the spec, circulate, unblock.
- **Grade against acceptance tests, not against our files.** A participant whose
  skill is structured differently but passes the test has passed. Say so out
  loud early — people assume divergence is failure.
- **Collect the divergences.** The reference has been wrong before; the labs
  invite argument with specific decisions (listed in each *Compare* section) and
  that is where the best material for the next iteration comes from.
- **Protect labs 4's last 15 minutes.** Smoke test and handover are what
  participants actually ship, and they are what gets cut when steps 1–3 run long.

Participants who need a working genie for a customer next week should
`./install.sh` and skip the labs — say this at the start so nobody feels they are
in the wrong room.

## How the harness fits together (design rationale)

- **One canonical instruction file.** `AGENTS.md` holds the persona and
  operating rules once; `CLAUDE.md` and `GEMINI.md` are two-line adapters that
  import it. Reason: four agents, one source of truth — edit the rules in one
  place and every agent follows.
- **Skills are portable `SKILL.md` files.** The cross-agent skill standard
  (YAML frontmatter `name` + `description`, markdown body) is discovered by
  Claude Code, Codex, Gemini CLI, and Antigravity from their own directories.
  We keep one canonical copy in `skills/` and symlink/copy it into
  `.claude/skills`, `.agents/skills`, `.gemini/skills`. Reason: skills should
  survive an agent switch — no vendor lock-in for workshop material.
- **The `description` field is the trigger.** Agents decide whether to load a
  skill from its description, so every description names the task *and* the
  phrases a user would actually say. When a skill fails to fire in a session,
  the description is the first thing to fix.
- **Evidence before opinion.** Every review skill gathers evidence first
  (read-only gcloud MCP for live environments, files for IaC) and every finding
  must cite `file:line` or a resource ID. Reason: a security review that
  hallucinates findings destroys trust with a customer faster than no review.
- **`(VERIFY)` instead of invention.** Skills instruct the agent to mark
  uncertain role/constraint names rather than fabricate plausible ones. Reason:
  models confidently invent IAM role names and org-policy constraint IDs;
  making uncertainty explicit is cheaper than a wrong fix in a customer project.
- **Hooks are a backstop, not a boundary.** `AGENTS.md` tells the agent to be
  read-only; the guard hook *enforces* it mid-turn for the dangerous cases
  (`rm -rf`, installs, pipe-to-shell, `terraform apply/destroy`, sudo,
  destructive git). Reason: instructions drift under long contexts and
  sub-agents; a deterministic pre-exec check does not. Teach participants that
  hooks are defense-in-depth, not a sandbox — a determined prompt-injection can
  still write files with allowed commands.

## Part 1 — The skills and why they exist

| Skill | One-liner | Exists because |
|---|---|---|
| `security-faq` | Fast, defensible answers to recurring GCP security questions | CEs answer the same ~15 questions on every engagement; a position cheat sheet + verification commands keep answers consistent and checkable |
| `threat-model` | STRIDE-per-element over GCP trust boundaries | GCP incidents are almost always boundary crossings (internet edge, project, VPC SC, CI/CD, identities) — the cheat sheet focuses attention there instead of generic lists |
| `security-review` | Read-only audit of Terraform, designs, or live projects | The bread-and-butter deliverable; a domain checklist grounded in real misconfigs plus a severity rubric forces prioritization over laundry lists |
| `well-architected-review` | Google Cloud Architecture Framework assessment with 1–5 maturity scores | The business-level conversation opener; scores turn "your architecture has issues" into a roadmap an exec can fund. Defers deep security findings to `security-review` so the two never diverge |
| `gcmvsp-review` | Conformance to the Google Cloud Minimum Viable Secure Platform — 60 Office-of-the-CISO controls, six domains, Basic/Intermediate/Advanced | Customers increasingly ask "do we meet Google's own baseline", which is a *binary conformance* question that a maturity score cannot answer. The skill is built around one risk: the model does not know the 60 controls and will invent them fluently, so it is forced to fetch the live checklist and to distinguish `Not verified` from `Not met` |
| `terraform-least-privilege-review` | Pattern-matched IAM audit (P1–P10) with minimal-diff fixes | IAM is the #1 source of GCP findings; the same ten violations recur on every project, so they're codified as grep-able patterns with ready remediations |
| `terraform-secure-generator` | Secure-by-default Terraform + security decision log | Flagging flaws is half the job; the generator produces the *fix* artifact and a decision log that doubles as handover documentation |
| `sast-scan` | Semgrep / Checkov / Trivy / tfsec wrapper + triage | Automates the breadth pass, and — just as important — teaches that scanners are not reviews: the mandatory "Not covered" section is the lesson (the example proves it: semgrep misses the planted SQLi) |
| `security-jargon-translator` | Translates security terms per audience | Customer conversations fail on vocabulary, not facts; per-audience framing (exec = money/risk, engineer = mechanism, auditor = control/evidence) keeps translations accurate instead of dumbed-down |
| `security-objection-handling` | Prep sheets for customer security objections | Objections are predictable (residency, CLOUD Act, "cloud is less secure", cost) — a library plus the acknowledge→clarify→respond→trade-offs→next-step framework beats improvising, and the honest-limits section builds trust |

**What good output looks like.** Each skill's Output section defines a strict
template (findings tables with severity/evidence/remediation/reference, prep
sheets, scored roadmaps). During the workshop, grade participants' agent output
against those templates — deviation usually means the skill wasn't loaded.

**Common facilitation pitfalls.**

- Agent answers from memory instead of loading the skill → check the skill is
  actually installed (see Part 2), then name it explicitly once ("use the
  security-review skill") to teach the trigger.
- Agent skips evidence gathering on live questions → confirm MCP is connected
  (`claude mcp list` / `gemini mcp list` / `codex mcp list`) and the right
  gcloud profile is active (`scripts/gcp-use.sh list`).
- Findings without `file:line` evidence → send them back; the skills forbid it.

## Part 2 — Deploying skills on the harness

### Where everything lives, per agent

| Agent | Harness file | Project skills | MCP config | Guard hook |
|---|---|---|---|---|
| Claude Code | `CLAUDE.md` → `AGENTS.md` | `.claude/skills/` | `.mcp.json` | `.claude/settings.json` (`PreToolUse`) |
| Antigravity (`agy`) | `AGENTS.md` (native) | `.agents/skills/` | `.gemini/settings.json` / global `~/.gemini/antigravity/mcp_config.json` | `.gemini/settings.json` (`BeforeTool`, VERIFY for your agy version) |
| Codex | `AGENTS.md` (native) | `.agents/skills/` (project) / `~/.codex/skills` | `.codex/config.toml` (trusted projects) | `~/.codex/hooks.json` (experimental — `[features] hooks = true`) |
| Gemini CLI | `GEMINI.md` → `AGENTS.md` | `.gemini/skills/` or `.agents/skills/` | `.gemini/settings.json` | `.gemini/settings.json` (`BeforeTool`) |

### Install scenarios

```bash
./install.sh --agent all --target /path/to/repo   # a customer/workshop repo
./install.sh --agent claude                       # one agent only
./install.sh --agent all --global                 # every repo, for your user
./install.sh --link --target /path/to/repo        # symlinks: edit skills/ once, live everywhere
```

- **Project vs global.** Project scope for workshops and customer repos
  (travels with the repo, per-customer MCP settings). Global for a CE's daily
  driver so the genie is available everywhere.
- **Updates.** Re-running `install.sh` replaces installed skill copies but
  never clobbers existing config files — it prints a merge hint instead. Use
  `--link` during skill development so edits propagate instantly.
- **Settings are merge-safe by design.** `install.sh` won't overwrite an
  existing `.claude/settings.json` / `.gemini/settings.json`; merge the
  `hooks` and `mcpServers` blocks by hand from `hooks/`.

### Deploying and testing the guard hook

1. Install (above) — the guard script lands in the agent's hooks dir and the
   settings snippet registers it.
2. Verify the ruleset: `python3 hooks/dangerous_command_guard.py --selftest`
   (43 cases, exits non-zero on any misfire).
3. Simulate a hook call exactly as the agent runtime would:

   ```bash
   echo '{"tool_input":{"command":"rm -rf /"}}' | python3 .claude/hooks/dangerous_command_guard.py; echo "exit=$?"   # 2 = blocked
   echo '{"tool_input":{"command":"terraform plan"}}' | python3 .claude/hooks/dangerous_command_guard.py; echo "exit=$?"   # 0 = allowed
   ```

4. End-to-end: ask the agent to "delete everything and reinstall" in a test
   repo and watch it get blocked and ask for consent instead.
5. Limitations to state aloud: the guard fails open on unparseable input (a
   hook bug must never wedge a session); it pattern-matches shell commands, so
   it cannot catch danger expressed through allowed commands (e.g. writing a
   file with a heredoc); Codex support is experimental. Treat it as a speed
   bump that forces a consent conversation — which is exactly the requirement.

### Authoring a new skill

1. `mkdir skills/<name>` — directory name must equal the frontmatter `name`.
2. Frontmatter: `description` in 1–2 sentences naming the task **and** the
   user phrases that should trigger it. This is the single most important line.
3. Body sections in order: When to use / Inputs (≤3 questions) / Workflow
   (evidence first) / domain content / Output format (fenced template) /
   Guardrails. Keep 90–150 lines; dense beats long.
4. Rules: GCP-accurate names with `(VERIFY)` on anything uncertain; no invented
   role/constraint/rule IDs; read-only unless the skill exists to write code.
5. Add a row to the skills table in `AGENTS.md` and `README.md`, then re-run
   `install.sh` (or nothing, with `--link`).

### Running the flawed-architecture exercise

`examples/flawed-agent-app/` is the workshop target ("customer-provided" Acme
support agent: Cloud Run, Cloud SQL, HTTP LB, public bucket, bastion).

1. Participants run the skills in order: `sast-scan` →
   `terraform-least-privilege-review` → `security-review` → `threat-model` →
   fix with `terraform-secure-generator`.
2. Score against `examples/flawed-agent-app/EXPECTED-FINDINGS.md` — 27 planted
   flaws (7 Critical / 9 High / 9 Medium / 2 Low) with the expected catcher per
   row. Score substance, not row-count matches; scanners and skills overlap.
3. Talking point built into the example: semgrep catches the `eval` and
   `shell=True` but **not** the SQL injection or env-fallback password —
   concrete proof for the "SAST is breadth, not depth" guardrail.
4. Optional capstone: deploy the *fixed* Terraform to a smoke-test project
   (never the flawed version — it is deliberately exploitable).

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Skill never triggers | Not installed for this agent/scope, or weak `description` — fix description, re-install |
| MCP tools missing | Wrong config file for the agent, untrusted project (Codex), or `npx`/Node unavailable — see `docs/gcp-setup.md` |
| Answers about the wrong GCP project | ADC is global, not per-profile — re-run `scripts/gcp-use.sh <profile> --adc` and re-confirm identity |
| Hook never fires | Settings file not merged, wrong event name for the agent version (`PreToolUse` vs `BeforeTool`), or Codex feature flag off |
| Hook blocks a legitimate command | Ruleset too broad for your context — edit `hooks/dangerous_command_guard.py` (it's 200 lines of readable Python) and re-run `--selftest` |

## Appendix — mapping to the 4-session program

| # | Session | Min | Lab | Outcome |
|---|---|---|---|---|
| 1 | Building the genie + connecting to GCP via MCP | 30 | [lab 1](../labs/lab-1-harness-and-mcp.md) | Harness contract, **gcloud + SecOps + GTI MCP**, multi-account credentials, guard hook |
| 2 | Upgrade part 1 — architecture & IaC | 45 | [lab 2](../labs/lab-2-architecture-and-iac-skills.md) | `well-architected-review`, **`gcmvsp-review`**, `terraform-least-privilege-review`, `terraform-secure-generator` |
| 3 | Upgrade part 2 — customer conversations | 45 | [lab 3](../labs/lab-3-conversation-skills.md) | `security-jargon-translator`, `security-objection-handling`, objection role-play |
| 4 | Putting the genie to work | 60 | [lab 4](../labs/lab-4-genie-at-work.md) | Flawed architecture → review → fixed IaC → **smoke test in a real project** → **handover pack** |

Business framing to state at the top of each session — participants engage
differently when they hear it:

- Sessions 2: *a platform engineer handles a security architecture review and
  produces sample code without engaging a platform security specialist.*
- Session 3: *a platform engineer handles the customer's security team directly.*

Session-specific facilitator notes:

- **Session 1** now includes two MCP servers with real credentials. Have
  participants export `CHRONICLE_*` and `VT_APIKEY` **before** the session — key
  provisioning is the single most common cause of a session-1 overrun. If GTI
  keys are not available, run the lab with gcloud + SecOps and demo GTI yourself;
  the lesson (indicator lookups are a third-party disclosure) still lands.
- **Session 2** is the longest per minute. If time is short, cut depth on
  `well-architected-review` rather than `gcmvsp-review` — GCMVSP carries the
  hallucination lesson, and its adversarial test ("list all 60 controls from
  memory", which must be refused) is the most memorable moment in the program.
- **Session 4** requires each participant to be able to create a disposable
  project and link billing, or to have one pre-created. Verify this **a week
  ahead**; it is the thing that silently blocks the capstone. Budget alerts on
  every smoke-test project. See [`smoke-test-runbook.md`](smoke-test-runbook.md)
  and the templates in [`handover/`](handover/).
- Expect `terraform apply` to be blocked by the guard hook in session 4. That is
  the lab working. Do not pre-emptively disable the hook.
