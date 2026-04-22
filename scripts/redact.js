#!/usr/bin/env node
/**
 * Mapickii redaction engine — regex-only PII stripping
 * Usage: node redact.js "text with secrets"
 *        echo "text" | node redact.js
 */

const fs = require('fs');

const RULES = [
  // Provider-specific API keys
  [/\bsk-ant-[a-zA-Z0-9_-]{20,}/g, '[API_KEY_ANTHROPIC]'],
  [/\bsk_(test|live)_[a-zA-Z0-9]{24,}/g, '[API_KEY_STRIPE]'],
  [/\bglm-[a-zA-Z0-9_-]{20,}/g, '[API_KEY_GLM]'],
  [/\bghp_[a-zA-Z0-9]{36,}/g, '[TOKEN_GITHUB]'],
  [/\bgho_[a-zA-Z0-9]{36,}/g, '[TOKEN_GITHUB]'],
  [/\bghu_[a-zA-Z0-9]{36,}/g, '[TOKEN_GITHUB]'],
  [/\bghs_[a-zA-Z0-9]{36,}/g, '[TOKEN_GITHUB]'],
  [/\bAKIA[0-9A-Z]{16}/g, '[AWS_KEY]'],
  [/\bxox[bposr]-[a-zA-Z0-9-]{10,}/g, '[SLACK_TOKEN]'],
  [/\borg-[a-zA-Z0-9]{20,}/g, '[OPENAI_ORG]'],
  
  // Generic API keys
  [/\bsk-[a-zA-Z0-9]{20,}/g, '[API_KEY_OPENAI]'],
  
  // JWT
  [/\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}/g, '[JWT]'],
  
  // PEM private keys
  [/-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----/g, '[PRIVATE_KEY]'],
  
  // SSH keys
  [/ssh-(rsa|ed25519|dss|ecdsa)\s+[A-Za-z0-9+/=]{100,}/g, '[SSH_KEY]'],
  
  // URL query tokens
  [/[?&](token|key|secret|password|auth|api_key|apiKey)=([^\s&]+)/g, '$1=[REDACTED]'],
  
  // DB connection strings
  [/(postgres|postgresql|mysql|mongodb)(?:\+srv)?:\/\/[^\s]+/g, '[DB_CONNECTION]'],
  
  // Email
  [/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, '[EMAIL]'],
  
  // Credit card
  [/\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, '[CARD]'],
  
  // Phone
  [/\b\+?\d{1,3}[\s-]?\(?\d{2,4}\)?[\s-]?\d{3,4}[\s-]?\d{4}\b/g, '[PHONE]'],
  
  // Password in config
  [/(password|passwd|pwd)\s*=\s*["']?([^"'\s&]+)/gi, '$1=[REDACTED]'],
];

function redact(text) {
  let result = text;
  RULES.forEach(([pattern, replacement]) => {
    result = result.replace(pattern, replacement);
  });
  return result;
}

const input = process.argv[2] || fs.readFileSync(0, 'utf8');
console.log(redact(input));