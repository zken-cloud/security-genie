# Lab 3 — Conversation skills (45 min)

## Goal

**Handle the customer's security team without a platform security CE in the
room.** Labs 1–2 made the genie good at artifacts. This lab makes it useful in
the meeting where the artifact gets accepted or rejected.

Two skills: translating security language for a specific audience, and preparing
for objections you can predict.

## Why these are harder than they look

The failure mode is not "the agent lacks facts". It is that generic LLM output
in a security conversation is *confidently agreeable* — it validates the
customer's framing, oversells GCP, and skips the honest limitation. That loses
the room, because the security team's job is to find the thing you glossed over.

Both skills below are mostly guardrails against your own agent's helpfulness.

---

## Part A — Security jargon translator (20 min)

### Spec

Translate security and compliance terms into accurate plain language, **tailored
to a named audience**.

Support at least four audiences, because the same fact needs a different frame:

| Audience | Cares about | Wrong register looks like |
|---|---|---|
| Executive | Money, risk, timeline, who is accountable | Mechanism detail they cannot act on |
| Software engineer | Mechanism, what changes in their code, what breaks | Risk language with no implementation |
| Auditor / regulator | The control, the evidence, the standard it maps to | Confident claims with no artifact |
| Customer business stakeholder | What it means for their users and contract | Internal jargon and product names |

Requirements:

- **Accurate, not dumbed down.** If simplifying makes it wrong, the skill must
  keep the precision and explain the term. "Encrypted at rest" does not mean
  "nobody can read it", and an exec who later learns that will not trust you again.
- **Preserve caveats.** Simplification is where hedges get dropped. The hedge is
  often the only load-bearing part.
- Ask for the audience if it is not stated, or state the assumption loudly.
- Output should be usable **as-is** — a paste-ready paragraph, not advice about
  how to write one.

### Design question

An exec asks "are we encrypted?" The true answer is layered: at rest by default
with Google-managed keys, in transit inside and outside Google's network, CMEK
optional, key access still governed by IAM, and encryption does not stop a
compromised identity from reading data.

How much of that fits in an executive answer without becoming false by omission?
Decide, and write the rule into your skill. This is the whole skill in one
question.

### Acceptance test

```
Explain to a CFO what "we use customer-managed encryption keys" means and
whether it reduces our risk.
```

Passes if: no unexplained jargon, it names what CMEK actually changes (key
control and revocation, audit visibility), and it is **honest that CMEK does not
protect against a compromised identity with data access** — the thing a CFO
would otherwise assume they bought. Fails if it is enthusiastic and vague.

Then the same term for an auditor:

```
Same thing, for an ISO 27001 auditor.
```

The content must shift to control and evidence — which key, which rotation
period, which log proves it — not just tone.

---

## Part B — Security objection handling (25 min)

### Spec

Produce a **conversation prep sheet** for a specific objection: what to say, what
proof to bring, what to concede, and what happens next.

Build a library of the objections that actually recur:

- "Public cloud is inherently less secure than our data centre"
- "Data residency rules forbid this"
- "The US CLOUD Act means we cannot use a US provider"
- "Google can read our data" / "you train on our data"
- "IAM is too complex for our team to operate safely"
- "Our regulator will not allow it"
- "We would be locked in"
- "Shared responsibility means the gaps are ours"

Structure each response: **acknowledge → clarify → respond → trade-offs → next
step.**

- *Acknowledge* — the concern is usually rational. Skipping this is why prep
  sheets fail in the room.
- *Clarify* — one question that separates the stated objection from the real
  one. "Data residency" often means "our DPO has not signed off", which is a
  completely different conversation.
- *Respond* — the substantive answer, with a **named** proof point: a specific
  product, control, certification, or doc. Not "Google has strong security".
- *Trade-offs* — the honest limitation. Mandatory.
- *Next step* — something concrete and small: a doc to send, a workshop, an
  architecture session.

Requirements:

- **An honest-limits section is mandatory in every response.** A prep sheet with
  no concessions reads as marketing and gets discounted entirely — including the
  parts that were true. Ceding the accurate point is what buys the rest.
- **Never invent** a certification, a compliance mapping, a customer reference,
  or a contractual term. Mark `(VERIFY)` and point at where to check. Getting a
  compliance claim wrong in front of an auditor is unrecoverable.
- Distinguish **technical** objections (answerable with architecture) from
  **commercial or political** ones (a lock-in objection is rarely about
  portability). Your skill should name which it is, because architecture answers
  do not resolve political objections.

### Design question

The CLOUD Act objection is legally real, partially, and the honest answer is
uncomfortable. Does your skill hand the CE a confident rebuttal, or an accurate
"here is what is true, here is what is mitigated, here is what remains"?

If you choose the confident rebuttal, expect the customer's counsel to have read
more than your agent has.

### Acceptance test

```
Prep me: the customer's CISO says "moving to GCP means Google can read our data,
and the CLOUD Act means the US government can compel it."
```

Passes if it: separates the two claims (they are different — one technical, one
legal), names specific controls with real product names for the first (CMEK,
Key Access Justifications, Access Transparency, Confidential Computing — each
marked `(VERIFY)` if the agent is not certain), is **honest** that no control
makes a lawful order disappear while explaining what narrows exposure, and ends
with a concrete next step. Fails if it invents a legal guarantee, or if the
honest-limits section is absent or hollow.

Now role-play. Have a colleague push back twice on the weakest point. The prep
sheet is only good if it survives the second question.

---

## Compare

| Yours | Reference |
|---|---|
| Jargon translator | [`../skills/security-jargon-translator/SKILL.md`](../skills/security-jargon-translator/SKILL.md) |
| Objection handling | [`../skills/security-objection-handling/SKILL.md`](../skills/security-objection-handling/SKILL.md) |

Decisions worth arguing with:

- **Honest limits are structurally mandatory**, not encouraged — a template slot
  the agent must fill. Templates are the only reliable way to stop a model from
  being agreeable. Does yours enforce it or just ask for it?
- The reference keeps **per-audience framing rules** (exec = money/risk,
  engineer = mechanism, auditor = control/evidence) rather than a single "explain
  simply" instruction. More to maintain, much less drift.
- Objection responses **require a named proof point**. This forces `(VERIFY)`
  markers into the output, which feels weaker on the page and is far stronger in
  the room.

## Done when

- [ ] Translator handles four audiences with genuinely different content
- [ ] It preserved a caveat that a naive simplification would have dropped
- [ ] Objection prep sheets always contain honest limits
- [ ] No invented certifications, legal claims, or customer references
- [ ] A prep sheet survived a colleague pushing back twice

Next: [Lab 4 — Genie at work](lab-4-genie-at-work.md)
