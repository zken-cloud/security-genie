# Build context is the REPO ROOT, so the workshop markdown can be baked in:
#   docker build -f site/Dockerfile -t security-genie-site .
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    CONTENT_ROOT=/app/content

WORKDIR /app

COPY site/app/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY site/app/main.py ./main.py
COPY site/app/templates ./templates
COPY site/app/static ./static

# Workshop content, rendered at request time from the repo's own markdown so the
# site cannot drift from the material. Copied file-by-file: the exercise app's
# Terraform is deliberately vulnerable and must not end up in a running image.
COPY AGENTS.md README.md ./content/
COPY labs ./content/labs
COPY docs ./content/docs
COPY skills ./content/skills
COPY examples/flawed-agent-app/README.md ./content/examples/flawed-agent-app/README.md

# Non-root, read-only-friendly. Nothing in the image needs to be writable.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin genie \
 && chown -R root:root /app && chmod -R a-w /app
USER 10001

EXPOSE 8080

# Single worker, threaded: this is a static-content site behind two gates, and
# Flask's signed-cookie session needs no shared state between workers.
CMD exec gunicorn --bind ":${PORT:-8080}" --workers 1 --threads 8 \
    --timeout 30 --access-logfile - --error-logfile - main:app
