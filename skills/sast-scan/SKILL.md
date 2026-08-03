---
name: sast-scan
description: Run open-source SAST — Semgrep for application code, Checkov/Trivy/tfsec for Terraform — and triage the results into verified, severity-rated findings. Use when asked to "scan this code", "run semgrep", "checkov this Terraform", "SAST this repo", or as the automated breadth pass before a manual security review.
---

# SAST Scan

Automated breadth pass over application code and Terraform using open-source static analyzers, followed by human-style triage: dedupe, confirm reachability, rate severity, and hand verified findings into the review skills.

## When to use

- The user asks to scan code or Terraform: "run semgrep on this", "checkov the infra", "SAST this repo".
- As step zero of a `security-review` or `terraform-least-privilege-review` — scanner output is candidate findings, never the finished review.
- Not for: business-logic, authorization-flow, or architecture analysis — SAST does not cover those; say so.

## Inputs

Ask at most these, then proceed with stated assumptions:

1. Targets: code directories and/or Terraform directories. Default: auto-detect — `.tf` files present means Terraform; both when the repo has both.
2. Tool preference (semgrep / checkov / trivy / tfsec). Default: whatever `scripts/run-sast.sh` finds installed.
3. Baseline: full scan, or diff against a previous report? Default: full scan.

## Workflow

1. Identify targets: application code, Terraform, and container files (Dockerfiles — Checkov and Trivy cover those too).
2. Run `scripts/run-sast.sh [--code DIR] [--terraform DIR]`; it detects installed tools and refuses system-wide installs. If no scanner is installed, install into an isolated environment only (pipx / venv / docker) or ask the user. Semgrep `p/*` registry configs need network access — offline, use local rules or another tool.
3. Code scan: `semgrep scan --config p/security-audit --config p/secrets --metrics=off`; add the dominant language pack (e.g. `p/python`, `p/javascript`) for depth.
4. Terraform scan: `checkov -d DIR --framework terraform`, else `trivy config DIR`, else `tfsec DIR`, else `semgrep --config p/terraform`.
5. Triage every result:
   - Dedupe across tools by `file:line` — one underlying issue is one finding, with all tool/rule IDs recorded.
   - Confirm reachability from code context: dead code, test-only paths, already-mitigated patterns are downgraded or marked false positive — with a written justification.
   - Rate severity with the harness rubric (Critical = public exploit path to data/credentials ... Low = hygiene).
6. Correlate with what changes severity: public exposure, data sensitivity, and — when available — live state via read-only gcloud MCP tools.
7. If the user asked for a full review, feed verified findings into `security-review` (and `terraform-least-privilege-review` for IAM) instead of reporting raw scanner output.

## Tool notes

- **Semgrep** — OSS engine, runs locally. `p/*` configs are fetched from the registry (network). Always `--metrics=off`; never `semgrep login` or push a customer's code to a SaaS dashboard without explicit approval.
- **Checkov** — Terraform, Dockerfile, Kubernetes, and more. `--compact` for readable output, `--soft-fail` so findings don't break the run. Use `--skip-check` only with a recorded justification.
- **Trivy** — `trivy config DIR` covers Terraform, Dockerfiles, Kubernetes; also the successor home of the tfsec ruleset (VERIFY current upstream status).
- **tfsec** — still widespread; fine as a second opinion alongside checkov/trivy.
- Exit codes vary by tool; findings are not a build failure unless the user wires CI that way.

## Output format

```markdown
# SAST Scan: <target>
- Tools run: <semgrep x.y + configs | checkov x.y | ...> | Targets: <dirs>
- Date: <YYYY-MM-DD>

## Summary
| Critical | High | Medium | Low | False positives |
|---|---|---|---|---|
| <n> | <n> | <n> | <n> | <n> |

## Findings
| ID | Tool:Rule | Severity | Finding | Evidence | Assessment | Remediation | Reference |
|---|---|---|---|---|---|---|---|
| SAST-01 | semgrep:python.lang.security.audit.sqli | Critical | <title> | app/main.py:42 | TP — reachable from POST /query | <fix> | <rule doc / CWE> |

## False positives
- <tool:rule at file:line> — <justification>

## Not covered
- <business logic, authz flows, runtime config, dependencies/CVEs (needs SCA), ...>
```

## Guardrails

- Breadth, not depth: scanners find patterns, not exploit paths. Every scan ends with the "Not covered" list — never present scanner output as a complete review.
- Confirm before reporting: an unverified scanner hit is a candidate, not a finding. Read the surrounding code first.
- No scanner auto-remediation (`semgrep --autofix`, checkov `--fix` style flags) on user code without an explicit ask.
- Local-only analysis: `--metrics=off` for semgrep; no uploading code or findings to external dashboards.
- Install tools only into isolated environments (pipx / venv / docker) — never system pip.
- Quote real rule IDs from tool output; never invent plausible-looking ones.
- Never print secret values a secrets scanner surfaces — reference `file:line` and the secret type only.
