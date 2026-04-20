#!/usr/bin/env python3
"""Mapickii redaction engine — regex-only PII stripping (V1).

Usage:
    echo "my key is sk-ant-abc123..." | python3 redact.py
    python3 redact.py "text with sk-ant-abc123"

No API calls. No network. Pure stdlib. Runs <1ms on typical input.

Rules are ordered MOST SPECIFIC FIRST. Example: sk-ant-abc would match both
the provider-specific sk-ant-* pattern and the generic sk-* OpenAI pattern.
If the generic ran first, Anthropic keys would be mislabeled as OpenAI.
"""
import sys
import re


RULES = [
    # ── Provider-specific API keys (must be BEFORE generic sk-* rule) ──
    (re.compile(r"sk-ant-[a-zA-Z0-9_-]{20,}"), "[API_KEY_ANTHROPIC]"),
    (re.compile(r"sk_(test|live)_[a-zA-Z0-9]{24,}"), "[API_KEY_STRIPE]"),
    (re.compile(r"glm-[a-zA-Z0-9_-]{20,}"), "[API_KEY_GLM]"),
    # GitHub token family (personal access / OAuth / user-to-server / server-to-server)
    (re.compile(r"ghp_[a-zA-Z0-9]{36,}"), "[TOKEN_GITHUB]"),
    (re.compile(r"gho_[a-zA-Z0-9]{36,}"), "[TOKEN_GITHUB]"),
    (re.compile(r"ghu_[a-zA-Z0-9]{36,}"), "[TOKEN_GITHUB]"),
    (re.compile(r"ghs_[a-zA-Z0-9]{36,}"), "[TOKEN_GITHUB]"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "[AWS_KEY]"),
    (re.compile(r"xox[bposr]-[a-zA-Z0-9-]{10,}"), "[SLACK_TOKEN]"),
    (re.compile(r"org-[a-zA-Z0-9]{20,}"), "[OPENAI_ORG]"),

    # ── Generic API keys (AFTER specific ones above) ──
    (re.compile(r"\bsk-[a-zA-Z0-9]{20,}"), "[API_KEY_OPENAI]"),

    # ── JWT ──
    (re.compile(r"\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}"), "[JWT]"),

    # ── PEM private keys + SSH keys ──
    (re.compile(r"-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----"), "[PRIVATE_KEY]"),
    (re.compile(r"ssh-(rsa|ed25519|dss|ecdsa)\s+[A-Za-z0-9+/=]{100,}"), "[SSH_KEY]"),

    # ── URL query params containing tokens/secrets ──
    # Order: put this BEFORE DB connection string so URLs like
    # https://api.example/v1?token=abc get scrubbed at the token=abc part.
    (re.compile(r"([?&](?:token|key|secret|password|auth|api_key|apiKey))=([^\s&]+)"),
     r"\1=[REDACTED]"),

    # ── DB connection strings (with credentials embedded) ──
    (re.compile(r"(postgres|postgresql|mysql|mongodb)(?:\+srv)?://[^\s]+"), "[DB_CONNECTION]"),

    # ── Chinese national ID (18 digits, YYYYMMDD in middle, last char 0-9 or X) ──
    # Placed BEFORE CARD rule so 18-digit IDs don't get mis-matched as Visa/Master.
    (re.compile(r"[1-9]\d{5}(?:18|19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx]"),
     "[CN_ID]"),

    # ── Chinese mobile (11 digits, 1[3-9]X{9}) ──
    # Placed BEFORE generic PHONE so CN numbers get the precise tag.
    (re.compile(r"\b1[3-9]\d{9}\b"), "[CN_PHONE]"),

    # ── Email ──
    (re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"), "[EMAIL]"),

    # ── Credit card (Visa / MC / AmEx / Discover) ──
    (re.compile(
        r"\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"),
     "[CARD]"),

    # ── International phone (catch-all; after CN_PHONE) ──
    (re.compile(r"\b\+?\d{1,3}[\s-]?\(?\d{2,4}\)?[\s-]?\d{3,4}[\s-]?\d{4}\b"), "[PHONE]"),

    # ── password=value in env / config lines (generic fallback) ──
    (re.compile(r"(?i)(password|passwd|pwd)\s*=\s*[\"']?([^\"'\s&]+)"), r"\1=[REDACTED]"),
]


def redact(text: str) -> str:
    """Apply all rules in declared order. Idempotent: running twice = same output."""
    for pattern, replacement in RULES:
        text = pattern.sub(replacement, text)
    return text


def main() -> int:
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])
    else:
        text = sys.stdin.read()
    sys.stdout.write(redact(text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
