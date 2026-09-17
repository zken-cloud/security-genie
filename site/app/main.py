"""Security Genie workshop hub — served at https://$SITE_HOST (see site/deploy.sh)

Two gates protect this site:

  Gate 1 (IAP)   Identity-Aware Proxy on the load balancer backend, granted only
                 to domain:$IAP_DOMAIN. Handled entirely outside this process —
                 by the time a request arrives here it has already passed IAP.
  Gate 2 (token) The shared workshop token, checked below. IAP proves *who* you
                 are; the token proves you are *in the workshop*.

Gate 2 is deliberately not an authentication system. It is a shared secret that
keeps the material behind a deliberate act, layered on top of real authentication.
Do not add anything to this site that would matter if the token leaked.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import re
import secrets
import time
from pathlib import Path

import markdown
from flask import (
    Flask,
    Response,
    abort,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

CONTENT_ROOT = Path(os.environ.get("CONTENT_ROOT", "/app/content"))
WORKSHOP_TOKEN = os.environ.get("WORKSHOP_TOKEN", "")
COOKIE_MAX_AGE = 12 * 60 * 60  # one workshop day

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.environ.get("SESSION_SECRET") or secrets.token_urlsafe(32),
    SESSION_COOKIE_NAME="__Host-sg",
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_SAMESITE="Lax",
    PERMANENT_SESSION_LIFETIME=COOKIE_MAX_AGE,
    MAX_CONTENT_LENGTH=16 * 1024,
)

# ---------------------------------------------------------------------------
# Content map: URL slug -> (repo-relative source file, nav title, section)
# ---------------------------------------------------------------------------

PAGES: dict[str, tuple[str, str, str]] = {
    "labs": ("labs/README.md", "Overview", "Build your own"),
    "lab-1": ("labs/lab-1-harness-and-mcp.md", "Lab 1 · Harness & MCP", "Build your own"),
    "lab-2": ("labs/lab-2-architecture-and-iac-skills.md", "Lab 2 · Architecture & IaC", "Build your own"),
    "lab-3": ("labs/lab-3-conversation-skills.md", "Lab 3 · Conversations", "Build your own"),
    "lab-4": ("labs/lab-4-genie-at-work.md", "Lab 4 · Genie at work", "Build your own"),
    "setup": ("docs/gcp-setup.md", "MCP & credentials setup", "Reference"),
    "harness": ("AGENTS.md", "The harness (AGENTS.md)", "Reference"),
    "readme": ("README.md", "Repo overview", "Reference"),
    "facilitator": ("docs/facilitator-guide.md", "Facilitator guide", "Reference"),
    "smoke-test": ("docs/smoke-test-runbook.md", "Smoke-test runbook", "Reference"),
    "handover-deployment": ("docs/handover/DEPLOYMENT-GUIDE-template.md", "Deployment guide template", "Handover templates"),
    "handover-architecture": ("docs/handover/ARCHITECTURE-template.md", "Architecture doc template", "Handover templates"),
    "example": ("examples/flawed-agent-app/README.md", "Flawed app (exercise target)", "Reference"),
}

SKILL_ORDER = [
    "security-faq",
    "threat-model",
    "security-review",
    "well-architected-review",
    "gcmvsp-review",
    "terraform-least-privilege-review",
    "terraform-secure-generator",
    "sast-scan",
    "security-jargon-translator",
    "security-objection-handling",
]

# repo-relative source path -> slug, for rewriting inter-document links
_SOURCE_TO_SLUG = {src: slug for slug, (src, _t, _s) in PAGES.items()}


def _nav() -> list[tuple[str, list[tuple[str, str]]]]:
    sections: dict[str, list[tuple[str, str]]] = {}
    for slug, (_src, title, section) in PAGES.items():
        sections.setdefault(section, []).append((slug, title))
    order = ["Build your own", "Reference", "Handover templates"]
    return [(s, sections[s]) for s in order if s in sections]


def _rewrite_links(html: str, source: str) -> str:
    """Point markdown links at site routes; mark off-site links as external."""
    base = Path(source).parent

    def repl(match: re.Match[str]) -> str:
        href = match.group(1)
        if href.startswith(("http://", "https://", "#", "mailto:")):
            return f'href="{href}" rel="noopener noreferrer"'
        target, _, anchor = href.partition("#")
        if not target:
            return match.group(0)
        try:
            resolved = os.path.normpath(base / target)
        except ValueError:
            return match.group(0)
        slug = _SOURCE_TO_SLUG.get(resolved)
        if slug:
            suffix = f"#{anchor}" if anchor else ""
            return f'href="{url_for("page", slug=slug)}{suffix}"'
        skill = re.match(r"^skills/([a-z0-9-]+)/SKILL\.md$", resolved)
        if skill:
            return f'href="{url_for("skill", name=skill.group(1))}"'
        # A real file in the repo that this site does not publish.
        return f'href="{url_for("index")}" data-unpublished="{resolved}"'

    return re.sub(r'href="([^"]+)"', repl, html)


def _render(source: str) -> tuple[str, str]:
    """Render a repo markdown file to (title, html). Path is map-controlled."""
    path = (CONTENT_ROOT / source).resolve()
    if not path.is_relative_to(CONTENT_ROOT.resolve()) or not path.is_file():
        abort(404)
    text = path.read_text(encoding="utf-8")
    md = markdown.Markdown(extensions=["extra", "toc", "sane_lists", "admonition"])
    html = md.convert(text)
    title = next((line[2:].strip() for line in text.splitlines() if line.startswith("# ")), source)
    return title, _rewrite_links(html, source)


def _skills() -> list[dict[str, str]]:
    out = []
    for name in SKILL_ORDER:
        path = CONTENT_ROOT / "skills" / name / "SKILL.md"
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        m = re.search(r"^description:\s*(.+?)$", text, re.MULTILINE)
        desc = m.group(1).strip() if m else ""
        out.append({"name": name, "description": desc.split(". Use when")[0] + "."})
    return out


# ---------------------------------------------------------------------------
# Gate 2 — the workshop token
# ---------------------------------------------------------------------------


def _token_ok(candidate: str) -> bool:
    if not WORKSHOP_TOKEN:
        return False
    return hmac.compare_digest(candidate.strip().lower().encode(), WORKSHOP_TOKEN.strip().lower().encode())


def _admitted() -> bool:
    if not session.get("admitted"):
        return False
    # Bind the cookie to the token in force, so rotating the token evicts everyone.
    fingerprint = hashlib.sha256(WORKSHOP_TOKEN.encode()).hexdigest()[:16]
    return hmac.compare_digest(session.get("tfp", ""), fingerprint)


def _iap_email() -> str:
    """Identity asserted by IAP. Display only — never an authorisation decision.

    X-Goog-Authenticated-User-Email is trustworthy only because Cloud Run
    ingress is restricted to the load balancer, so no client can set it
    directly. Anything security-relevant must verify the signed JWT in
    X-Goog-IAP-JWT-Assertion instead.
    """
    raw = request.headers.get("X-Goog-Authenticated-User-Email", "")
    return raw.split(":", 1)[1] if ":" in raw else raw


@app.before_request
def gate() -> Response | None:
    if request.endpoint in {"healthz", "gate_page", "static"}:
        return None
    if not _admitted():
        return redirect(url_for("gate_page", next=request.path))
    return None


@app.after_request
def headers(resp: Response) -> Response:
    resp.headers.setdefault(
        "Content-Security-Policy",
        "default-src 'none'; style-src 'self'; img-src 'self' data:; "
        "form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
    )
    resp.headers.setdefault("X-Content-Type-Options", "nosniff")
    resp.headers.setdefault("Referrer-Policy", "no-referrer")
    resp.headers.setdefault("X-Frame-Options", "DENY")
    resp.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
    resp.headers.setdefault("Cache-Control", "no-store")
    return resp


@app.route("/gate", methods=["GET", "POST"])
def gate_page():
    error = None
    nxt = request.values.get("next", "/")
    if not nxt.startswith("/") or nxt.startswith("//"):
        nxt = "/"
    if request.method == "POST":
        if _token_ok(request.form.get("token", "")):
            session.permanent = True
            session["admitted"] = True
            session["tfp"] = hashlib.sha256(WORKSHOP_TOKEN.encode()).hexdigest()[:16]
            return redirect(nxt)
        time.sleep(0.5)  # blunt the guessing rate; not a substitute for a real limiter
        error = "That is not the token."
    elif _admitted():
        return redirect(nxt)
    return render_template("gate.html", error=error, next=nxt, email=_iap_email()), (
        401 if error else 200
    )


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("gate_page"))


@app.route("/healthz")
def healthz():
    return Response("ok", mimetype="text/plain")


@app.route("/")
def index():
    return render_template("index.html", nav=_nav(), skills=_skills(), email=_iap_email())


@app.route("/p/<slug>")
def page(slug: str):
    if slug not in PAGES:
        abort(404)
    source, title, _section = PAGES[slug]
    _doc_title, html = _render(source)
    return render_template(
        "page.html", nav=_nav(), title=title, body=html, source=source, email=_iap_email()
    )


@app.route("/skill/<name>")
def skill(name: str):
    if name not in SKILL_ORDER:
        abort(404)
    title, html = _render(f"skills/{name}/SKILL.md")
    return render_template(
        "page.html",
        nav=_nav(),
        title=title,
        body=html,
        source=f"skills/{name}/SKILL.md",
        email=_iap_email(),
    )


@app.errorhandler(404)
def not_found(_e):
    return render_template("404.html", nav=_nav(), email=_iap_email()), 404


if __name__ == "__main__":  # pragma: no cover - container entrypoint uses gunicorn
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
