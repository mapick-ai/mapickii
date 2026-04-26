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


# ── V1 PR-13 TC-8A.3: code-block whitelist + meta-topic heuristics ──
#
# Whitelist layers (priority, short-circuit):
#   1. Global disable (handled by shell.sh `_redact` via CONFIG `redact_disabled`)
#   2. Text structure: ``` ... ``` blocks and `inline` code passed through
#   3. Meta-topic context: regex / format / validation / "how to detect X" →
#      skip corresponding rule family so discussion isn't mangled
#
# All three run in Python (this file). Disabled flag is checked by shell
# before invoking redact.py, so Python code never sees a true value for it.

CODE_BLOCK_RE = re.compile(r"```[\s\S]*?```|`[^`\n]+`", re.MULTILINE)

# If any of these context signals are present in a text chunk, skip the
# named rule family. Regex literal (?i) is case-insensitive.
META_TOPIC_PATTERNS = {
    "email": re.compile(r"(?i)\b(regex|regexp|正则|正则表达式|format|格式|validation|验证|检测|pattern)\b"),
    "api_key": re.compile(r"(?i)(how\s+to|如何).*\b(key|密钥|token|format|格式)\b"),
    "credit_card": re.compile(r"(?i)(card\s*format|卡号格式|validation|luhn|mod.10|check\s*digit)"),
    "phone": re.compile(r"(?i)(phone\s*format|手机号格式|国际区号|e\.164)"),
}

# Which rule replacement strings belong to which meta-topic family.
# If the topic signal is present, these replacements' corresponding rules
# are skipped.
META_TOPIC_TO_REPLACEMENTS = {
    "email": {"[EMAIL]"},
    "api_key": {"[API_KEY_ANTHROPIC]", "[API_KEY_STRIPE]", "[API_KEY_GLM]", "[API_KEY_OPENAI]", "[TOKEN_GITHUB]"},
    "credit_card": {"[CARD]"},
    "phone": {"[PHONE]", "[CN_PHONE]"},
}


def _apply_rules(chunk: str, skip_families: set) -> str:
    """Apply rules to a single non-code chunk, honoring the skip set."""
    # Collect all replacement strings to skip (from META_TOPIC_TO_REPLACEMENTS)
    skip_replacements = set()
    for family in skip_families:
        skip_replacements.update(META_TOPIC_TO_REPLACEMENTS.get(family, set()))

    for pattern, replacement in RULES:
        # replacement might be a group backref like r"\1=[REDACTED]" —
        # check if any skip label occurs in the literal replacement string
        if any(sk in replacement for sk in skip_replacements):
            continue
        public_replacement = (
            "[REDACTED]"
            if replacement.startswith("[") and replacement.endswith("]")
            else replacement
        )
        chunk = pattern.sub(public_replacement, chunk)
    return chunk


def _detect_meta_topics(text: str) -> set:
    """Return the set of meta-topic families signaled in text."""
    found = set()
    for family, pattern in META_TOPIC_PATTERNS.items():
        if pattern.search(text):
            found.add(family)
    return found


def redact(text: str, code_block_aware: bool = True) -> str:
    """Apply redaction rules. Idempotent: running twice = same output.

    V1 PR-13: when code_block_aware=True (default), ``` fences and `inline`
    code are passed through untouched, and meta-topic context signals skip
    the corresponding rule family.
    """
    if not code_block_aware:
        return _apply_rules(text, set())

    # Detect meta-topics from the whole text first
    skip_families = _detect_meta_topics(text)

    # Split on code fences and inline code; apply rules only to non-code chunks
    parts = []
    last_end = 0
    for m in CODE_BLOCK_RE.finditer(text):
        if m.start() > last_end:
            parts.append(_apply_rules(text[last_end:m.start()], skip_families))
        parts.append(m.group(0))  # code block / inline code passed through as-is
        last_end = m.end()
    if last_end < len(text):
        parts.append(_apply_rules(text[last_end:], skip_families))
    return "".join(parts)


def main() -> int:
    if len(sys.argv) > 1 and not sys.argv[1].startswith("--"):
        text = " ".join(sys.argv[1:])
    else:
        text = sys.stdin.read()

    # Flag to disable code-aware mode (for debugging / strict redaction)
    code_aware = "--no-code-aware" not in sys.argv
    sys.stdout.write(redact(text, code_block_aware=code_aware))
    return 0


if __name__ == "__main__":
    sys.exit(main())
