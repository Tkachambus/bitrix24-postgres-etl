"""Fail the build if the repository contains secrets or corporate identifiers.

Run locally:  python scripts/check_secrets.py
Used in CI before tests, so nothing sensitive can be pushed unnoticed.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SKIP_DIRS = {".git", "__pycache__", ".venv", "venv", ".pytest_cache", ".ruff_cache"}
TEXT_SUFFIXES = {
    ".py", ".sql", ".md", ".txt", ".yml", ".yaml", ".json", ".toml",
    ".cfg", ".ini", ".example", ".sh", ".ps1", ".html", ".css", ".js",
}

# Что ищем. Всё в нижнем регистре: сравнение идёт по тексту в нижнем регистре.
PATTERNS = {
    "corporate name": r"\br4s\b",
    "internal db name": r"datawarehouse",
    "internal domain": r"bitrix24\.ru",
    "personal machine": r"msi raider",
    "private ip": r"\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b",
    "phone number": r"\+7[\s\-]?\(?\d{3}\)?[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}",
    "openai key": r"sk-[a-z0-9]{20,}",
    "github token": r"gh[pousr]_[a-z0-9]{20,}",
    "aws key": r"akia[0-9a-z]{16}",
    "private key": r"begin (rsa |openssh |ec )?private key",
    "password in url": r"://[^/\s:]+:[^@\s/]+@",
}

# Разрешённые демо-значения (локальная БД из docker-compose).
ALLOW = (
    "demo_password",
    "postgres:postgres@",
    "integration_writer:demo_password@",
    "user:pass@host",
    "demo-token",
    "example.com",
)

FORBIDDEN_FILES = {".env", "cookies.txt"}
FORBIDDEN_SUFFIXES = {".pem", ".key", ".pfx", ".p12", ".zip", ".pdf", ".pyc"}


def is_text(path: Path) -> bool:
    return path.suffix.lower() in TEXT_SUFFIXES or path.name == ".env.example"


def main() -> int:
    problems: list[str] = []

    for path in ROOT.rglob("*"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if not path.is_file():
            continue

        rel = path.relative_to(ROOT)
        if path.name == "check_secrets.py":
            # В самом сканере лежат строки-паттерны, их не проверяем.
            continue
        if path.name in FORBIDDEN_FILES:
            problems.append(f"{rel}: forbidden file")
            continue
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            problems.append(f"{rel}: forbidden file type")
            continue
        if path.stat().st_size > 5 * 1024 * 1024:
            problems.append(f"{rel}: file larger than 5 MB")
            continue
        if not is_text(path):
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        lowered = text.lower()

        for name, pattern in PATTERNS.items():
            for match in re.finditer(pattern, lowered):
                snippet = lowered[max(0, match.start() - 40): match.end() + 40]
                if any(allowed in snippet for allowed in ALLOW):
                    continue
                problems.append(f"{rel}: {name} near {snippet!r}")

    if problems:
        print("SECRET SCAN FAILED:")
        for problem in problems:
            print("  -", problem)
        return 1

    print("secret scan: clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
