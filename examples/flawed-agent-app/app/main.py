"""Acme support agent service.

FastAPI wrapper for the support-agent backend: looks up customer notes
in Postgres and exposes the "agent tools" used by the LLM pipeline
(calculator, plus a shell helper for debugging).
"""

import os
import subprocess
import traceback

import psycopg2
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Acme Support Agent", version="0.3.1")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_NAME = os.environ.get("DB_NAME", "agent")
DB_USER = os.environ.get("DB_USER", "agent")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "sup3rsecret-fallback")


class QueryRequest(BaseModel):
    user: str
    question: str


class ShellRequest(BaseModel):
    command: str


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
    )


def lookup_notes(user: str) -> list[str]:
    conn = get_connection()
    try:
        cur = conn.cursor()
        query = f"SELECT note FROM support_notes WHERE username = '{user}'"
        cur.execute(query)
        return [row[0] for row in cur.fetchall()]
    finally:
        conn.close()


def calculator(expression: str):
    """Agent tool: evaluate a calculator expression."""
    return eval(expression)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/query")
def query(req: QueryRequest):
    try:
        result = {"user": req.user, "notes": lookup_notes(req.user)}
        if req.question.startswith("calc:"):
            result["calculation"] = calculator(req.question[len("calc:"):])
        return result
    except Exception:
        return {"error": traceback.format_exc()}


@app.post("/admin/run-shell")
def run_shell(req: ShellRequest):
    """Ops helper, only enabled in debug mode."""
    if not os.environ.get("DEBUG"):
        return {"error": "not found"}
    completed = subprocess.run(
        req.command, shell=True, capture_output=True, text=True, timeout=30
    )
    return {"stdout": completed.stdout, "stderr": completed.stderr}
