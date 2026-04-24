#!/usr/bin/env bash
# Mapickii Skill — Install Script (V1: OpenClaw only)
#
# Install or update Mapickii Skill with a single command:
#
#   curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/v0.0.12/install.sh | bash
#   wget -qO- https://raw.githubusercontent.com/mapick-ai/mapickii/v0.0.12/install.sh | bash
#
# Options (via environment variables):
#   MAPICKII_VERSION=v0.0.12  bash -c "$(curl -fsSL ...)"   # Install specific version
#   MAPICKII_REPO=owner/repo bash -c "$(curl -fsSL ...)"   # Override source repo

set -e

# -- Config --------------------------------------------------------------------

REPO="${MAPICKII_REPO:-mapick-ai/mapickii}"
VERSION="${MAPICKII_VERSION:-latest}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Banner --------------------------------------------------------------------

echo ""
echo -e "${CYAN}"
echo '  ╔══════════════════════════════════════════╗'
echo '  ║                                          ║'
echo '  ║           M A P I C K I I                ║'
echo '  ║       Mapick Intelligent Butler          ║'
echo '  ║                                          ║'
echo '  ╚══════════════════════════════════════════╝'
echo -e "${NC}"

# -- Resolve version -----------------------------------------------------------

if [[ "${VERSION}" == "latest" ]]; then
  info "Fetching latest version..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') || true

  if [[ -z "${VERSION}" ]]; then
    warn "Cannot fetch latest release, falling back to main branch"
    VERSION="main"
  fi
fi

info "Version: ${VERSION}"

# -- Detect OpenClaw -----------------------------------------------------------

OPENCLAW_PATH=""
if command -v claw &>/dev/null; then
  OPENCLAW_PATH="$(command -v claw)"
elif command -v openclaw &>/dev/null; then
  OPENCLAW_PATH="$(command -v openclaw)"
fi

if [[ -z "${OPENCLAW_PATH}" ]]; then
  error "OpenClaw not detected.

  Mapickii V1 only supports OpenClaw. Install OpenClaw first:
    https://openclaw.io

  Then retry this script."
fi

ok "OpenClaw detected: ${OPENCLAW_PATH}"

# -- Detect runtime (Node.js preferred, Python3 fallback) ----------------------

HAS_NODE=0
HAS_PY3=0
command -v node    &>/dev/null && HAS_NODE=1
command -v python3 &>/dev/null && HAS_PY3=1

if [[ "${HAS_NODE}" -eq 1 ]]; then
  ok "Node.js detected: $(node --version)"
elif [[ "${HAS_PY3}" -eq 1 ]]; then
  warn "Node.js not found; Python3 fallback will be used ($(python3 --version 2>&1))"
else
  warn "Neither Node.js nor Python3 detected."
  warn "Mapickii commands will not run until you install Node.js (>=18) or Python3."
fi

# -- Download tarball ----------------------------------------------------------

REF="${VERSION}"
TARBALL_URL="https://github.com/${REPO}/archive/${REF}.tar.gz"

echo ""
echo -e "${DIM}────────────────────────────────────────${NC}"
echo ""
info "Downloading Mapickii Skill (${VERSION})..."

TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

# Download to file first (curl --retry needs a clean restart point; piping into
# tar makes retries useless because tar has already consumed partial data).
TARBALL="${TMP_DIR}/mapickii.tar.gz"
if ! curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused \
     "${TARBALL_URL}" -o "${TARBALL}"; then
  error "Failed to download ${TARBALL_URL} (after 3 retries)"
fi

if ! tar -xzf "${TARBALL}" -C "${TMP_DIR}" --strip-components=1; then
  error "Failed to extract tarball (file may be corrupt: ${TARBALL})"
fi

rm -f "${TARBALL}"

ok "Download complete"

# -- Install to OpenClaw -------------------------------------------------------

target_dir="${HOME}/.openclaw/skills/mapickii"

echo ""
info "Installing to ${BOLD}OpenClaw${NC} ..."

# Preserve user-editable CONFIG.md across upgrades
BACKUP_CONFIG=""
if [[ -f "${target_dir}/CONFIG.md" ]]; then
  BACKUP_CONFIG="$(mktemp)"
  cp "${target_dir}/CONFIG.md" "${BACKUP_CONFIG}"
fi

if [[ -d "${target_dir}" ]]; then
  warn "Existing installation found, overwriting..."
  rm -rf "${target_dir}"
fi

mkdir -p "${target_dir}"

# Copy runtime files (Skill payload, not repo boilerplate).
# Keep this list in sync with what SKILL.md references.
INSTALL_ITEMS=(SKILL.md package.json scripts reference prompts)
for item in "${INSTALL_ITEMS[@]}"; do
  if [[ -e "${TMP_DIR}/${item}" ]]; then
    cp -R "${TMP_DIR}/${item}" "${target_dir}/"
  fi
done

# Ensure entry scripts are executable
for exe in scripts/shell scripts/shell.js scripts/shell.sh scripts/redact.js scripts/redact.py; do
  [[ -f "${target_dir}/${exe}" ]] && chmod +x "${target_dir}/${exe}"
done

# Restore user config if present
if [[ -n "${BACKUP_CONFIG}" ]]; then
  cp "${BACKUP_CONFIG}" "${target_dir}/CONFIG.md"
  rm -f "${BACKUP_CONFIG}"
  echo -e "    ${DIM}Restored: CONFIG.md${NC}"
fi

if [[ ! -f "${target_dir}/SKILL.md" ]] || [[ ! -f "${target_dir}/scripts/shell" ]]; then
  error "Installation failed (required files missing after copy)."
fi

ok "OpenClaw installed successfully"
echo -e "    ${DIM}${target_dir}/${NC}"

# -- Summary -------------------------------------------------------------------

echo ""
echo -e "${DIM}────────────────────────────────────────${NC}"
echo ""

ok "Done!"
echo ""
echo -e "  ${GREEN}Version${NC}: ${VERSION}"
echo ""
echo -e "  ${BLUE}Get started:${NC}"
echo "    /mapickii                View status overview"
echo "    /mapickii status         Detailed status"
echo "    /mapickii clean          Clean up zombies"
echo "    /mapickii bundle         Browse bundles"
echo "    /mapickii daily          Daily report"
echo ""
echo -e "  ${CYAN}More info: https://github.com/${REPO}${NC}"
echo ""
