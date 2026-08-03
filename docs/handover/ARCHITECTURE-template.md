# Architecture — `<workload name>`

> Template for the *as-built* architecture document in the session-4 handover
> pack. As-built means: after the smoke test, describing what actually deployed.
> If the design changed during the smoke test, this document describes the new
> shape and §8 records why.

| | |
|---|---|
| Workload | `<name>` |
| Version / commit | `<git sha>` |
| Author | `<name, role>` |
| Date | `<YYYY-MM-DD>` |
| Status | `<as-built / proposed>` |
| Data classification | `<public / internal / confidential / restricted>` |

## 1. Purpose and scope

`<What the workload does, who uses it, what it is not. Two paragraphs maximum.>`

In scope: `<...>`
Out of scope: `<...>`

## 2. Context

| | |
|---|---|
| Users / actors | `<who, authenticating how>` |
| Upstream dependencies | `<systems it calls>` |
| Downstream consumers | `<systems that call it>` |
| Compliance regime | `<PCI DSS / HIPAA / SOC 2 / ISO 27001 / none>` |
| Availability target | `<SLO>` |
| RTO / RPO | `<...>` |

## 3. Component view

```
<ASCII or Mermaid diagram. Show trust boundaries explicitly — internet edge,
project boundary, VPC boundary, VPC-SC perimeter. A diagram without boundaries
is a picture, not an architecture document.>
```

| Component | GCP service | Identity it runs as | Ingress | Egress |
|---|---|---|---|---|

## 4. Trust boundaries and data flows

| # | Flow | From → To | Crosses boundary | Transport | AuthN / AuthZ | Data classification |
|---|---|---|---|---|---|---|
| 1 | | | | TLS 1.2+ | | |

For each boundary crossing, name the control that enforces it — not the
intention. "Cloud Run ingress is `internal-and-cloud-load-balancing`" is a
control; "only the LB should reach it" is an intention.

## 5. Identity and access

| Principal | Type | Roles | Scope | Justification |
|---|---|---|---|---|

- Human access path: `<how a human reaches prod, and through what approval>`
- Workload identity: `<per-service SAs; state explicitly that no SA keys exist,
  or list every key and why it exists>`
- Break-glass: `<account, storage, alerting on use>`

## 6. Data

| Data store | Contents | Classification | Encryption | Retention | Backup |
|---|---|---|---|---|---|

- Encryption at rest: `<Google-managed / CMEK — name the key ring and rotation
  period if CMEK>`
- Encryption in transit: `<...>`
- Secrets: `<Secret Manager paths — paths only, never values>`
- PII / regulated data handling: `<what, where, and how it is minimised>`

## 7. Security controls

Map controls to the risks they address. Reference the review that found the risk.

| # | Control | Implements | Enforced by | Evidence |
|---|---|---|---|---|
| 1 | | `<finding ID / threat ID>` | `<org policy, IAM, firewall, code>` | `<file:line or resource ID>` |

Detection and response:

| Signal | Source | Routed to | Alert |
|---|---|---|---|

## 8. Design decisions

| # | Decision | Alternatives considered | Rationale | Trade-off accepted |
|---|---|---|---|---|

Include the decisions the **smoke test forced**. Those are the ones the customer
most needs — they are the difference between the design and reality.

## 9. Residual risks

| # | Risk | Severity | Mitigation in place | Residual owner | Review date |
|---|---|---|---|---|---|

Carry forward anything the `security-review` or `threat-model` output left open.
A handover with an empty residual-risk table is not credible — say "none
identified" only if you mean it and state what you looked for.

## 10. Operational ownership

| Area | Owner | Escalation |
|---|---|---|

## 11. References

- Deployment guide: `<link>`
- Security decision log: `<link>`
- Threat model: `<link>`
- Security review findings: `<link>`
- IaC: `<repo path / module version>`
