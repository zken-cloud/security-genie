"""Local smoke test for the workshop hub: both gates, all routes, link rewriting."""
import os, sys, pathlib, shutil, tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]

# Test fixture only. The live workshop token lives in Secret Manager and is
# deliberately not in this repo — the app reads it from WORKSHOP_TOKEN.
TOKEN = "test-token-not-the-live-one"

# Mirror the Dockerfile's content layout.
content = pathlib.Path(tempfile.mkdtemp()) / "content"
content.mkdir(parents=True)
for f in ["AGENTS.md", "README.md"]:
    shutil.copy(REPO / f, content / f)
for d in ["labs", "docs", "skills"]:
    shutil.copytree(REPO / d, content / d)
(content / "examples/flawed-agent-app").mkdir(parents=True)
shutil.copy(REPO / "examples/flawed-agent-app/README.md",
            content / "examples/flawed-agent-app/README.md")

os.environ["CONTENT_ROOT"] = str(content)
os.environ["WORKSHOP_TOKEN"] = TOKEN
os.environ["SESSION_SECRET"] = "test-only-not-a-real-secret"
sys.path.insert(0, str(REPO / "site/app"))

import main  # noqa: E402

app = main.app
app.config["TESTING"] = True
fails = []


def check(name, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"  [{detail}]" if detail and not cond else ""))
    if not cond:
        fails.append(name)


print("\n== Gate 2 behaviour ==")
with app.test_client() as c:
    r = c.get("/")
    check("un-gated / redirects to /gate", r.status_code == 302 and "/gate" in r.headers["Location"], f"{r.status_code}")
    r = c.get("/p/lab-1")
    loc = r.headers.get("Location", "")
    check("un-gated deep link redirects, preserving next",
          r.status_code == 302 and "/gate?next=" in loc and "lab-1" in loc, loc)
    r = c.get("/healthz")
    check("/healthz un-gated 200", r.status_code == 200 and r.data == b"ok", f"{r.status_code}")
    r = c.get("/gate")
    check("/gate renders", r.status_code == 200 and b"Workshop token" in r.data, f"{r.status_code}")
    r = c.post("/gate", data={"token": "wrong"})
    check("wrong token rejected (401)", r.status_code == 401 and b"not the token" in r.data, f"{r.status_code}")
    r = c.get("/")
    check("still gated after bad token", r.status_code == 302, f"{r.status_code}")

with app.test_client() as c:
    r = c.post("/gate", data={"token": TOKEN}, follow_redirects=False)
    check("correct token admits (302 -> /)", r.status_code == 302 and r.headers["Location"] == "/", f"{r.status_code} {r.headers.get('Location')}")
    r = c.get("/")
    check("home renders after gate", r.status_code == 200 and b"Security Genie" in r.data, f"{r.status_code}")
    check("home lists gcmvsp skill", b"gcmvsp-review" in r.data)
    check("home shows 4 sessions", r.data.count(b"<td>") >= 16)

    r = c.post("/gate", data={"token": TOKEN.upper() + "  "})
    check("token is case/whitespace tolerant", r.status_code == 302)

    print("\n== Open-redirect protection ==")
    r = c.post("/gate", data={"token": TOKEN, "next": "//evil.example"})
    check("protocol-relative next rejected", r.headers["Location"] == "/", r.headers.get("Location", ""))
    r = c.post("/gate", data={"token": TOKEN, "next": "https://evil.example"})
    check("absolute next rejected", r.headers["Location"] == "/", r.headers.get("Location", ""))
    r = c.post("/gate", data={"token": TOKEN, "next": "/p/lab-4"})
    check("relative next honoured", r.headers["Location"] == "/p/lab-4", r.headers.get("Location", ""))

    print("\n== All content routes render ==")
    for slug in main.PAGES:
        r = c.get(f"/p/{slug}")
        ok = r.status_code == 200 and b"<h1" in r.data
        check(f"/p/{slug}", ok, f"{r.status_code}")
    for name in main.SKILL_ORDER:
        r = c.get(f"/skill/{name}")
        check(f"/skill/{name}", r.status_code == 200, f"{r.status_code}")

    print("\n== Link rewriting ==")
    r = c.get("/p/labs")
    body = r.get_data(as_text=True)
    check("lab links rewritten to /p/", 'href="/p/lab-1"' in body, "")
    check("docs link rewritten", 'href="/p/setup"' in body, "")
    check("no raw .md hrefs remain", '.md"' not in body, [l for l in body.split('href="')[1:] if l.split('"')[0].endswith(".md")][:3])
    r = c.get("/p/lab-2")
    body = r.get_data(as_text=True)
    check("skill link -> /skill/", 'href="/skill/gcmvsp-review"' in body)
    check("external links keep rel=noopener", 'rel="noopener noreferrer"' in body)
    r = c.get("/p/harness")
    check("AGENTS.md renders tables", b"<table>" in r.data)

    print("\n== Security headers ==")
    r = c.get("/")
    h = r.headers
    check("CSP present, default-src none", "default-src 'none'" in h.get("Content-Security-Policy", ""))
    check("frame-ancestors none", "frame-ancestors 'none'" in h.get("Content-Security-Policy", ""))
    check("nosniff", h.get("X-Content-Type-Options") == "nosniff")
    check("HSTS", "max-age=31536000" in h.get("Strict-Transport-Security", ""))
    check("no-store", h.get("Cache-Control") == "no-store")
    check("referrer-policy", h.get("Referrer-Policy") == "no-referrer")

    print("\n== 404 + logout ==")
    check("unknown slug 404s", c.get("/p/nope").status_code == 404)
    check("unknown skill 404s", c.get("/skill/nope").status_code == 404)
    check("path traversal blocked", c.get("/p/../../etc/passwd").status_code in (301, 308, 404))
    r = c.get("/logout")
    check("logout redirects to gate", r.status_code == 302 and "/gate" in r.headers["Location"])
    check("logout clears admission", c.get("/").status_code == 302)

print("\n== Token rotation evicts sessions ==")
with app.test_client() as c:
    c.post("/gate", data={"token": TOKEN})
    check("admitted", c.get("/").status_code == 200)
    main.WORKSHOP_TOKEN = "a-new-token"
    check("old cookie rejected after rotation", c.get("/").status_code == 302)
main.WORKSHOP_TOKEN = TOKEN

print("\n== Empty token config fails closed ==")
main.WORKSHOP_TOKEN = ""
with app.test_client() as c:
    r = c.post("/gate", data={"token": ""})
    check("empty token never admits", r.status_code == 401, f"{r.status_code}")
main.WORKSHOP_TOKEN = TOKEN

print("\n== IAP header parsing ==")
with app.test_client() as c:
    c.post("/gate", data={"token": TOKEN})
    r = c.get("/", headers={"X-Goog-Authenticated-User-Email": "accounts.google.com:someone@google.com"})
    check("IAP email displayed, prefix stripped", b"someone@google.com" in r.data and b"accounts.google.com:" not in r.data)

print()
if fails:
    print(f"FAILED ({len(fails)}): " + ", ".join(fails))
    sys.exit(1)
print("All checks passed.")
