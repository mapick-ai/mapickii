#!/usr/bin/env bash
# Mapickii Skill — Install Script (V1: OpenClaw only)
#
# Install or update Mapickii Skill with a single command:
#
#   curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.1/install.sh | bash
#   wget -qO- https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.1/install.sh | bash
#
# Options (via environment variables):
#   MAPICKII_VERSION=v1.0.0  bash -c "$(curl -fsSL ...)"   # Install specific version
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

# -- Download files to temp dir ------------------------------------------------

BRANCH="${VERSION}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

echo ""
echo -e "${DIM}────────────────────────────────────────${NC}"
echo ""
info "Downloading Mapickii Skill (${VERSION})..."

TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

mkdir -p "${TMP_DIR}/scripts"

curl -fsSL "${RAW_BASE}/SKILL.md" -o "${TMP_DIR}/SKILL.md" \
  || error "Failed to download SKILL.md"

curl -fsSL "${RAW_BASE}/scripts/shell.sh" -o "${TMP_DIR}/scripts/shell.sh" \
  || error "Failed to download scripts/shell.sh"

chmod +x "${TMP_DIR}/scripts/shell.sh"

ok "Download complete"

# -- Install to OpenClaw -------------------------------------------------------

target_dir="${HOME}/.openclaw/skills/mapickii"
target_scripts="${target_dir}/scripts"

echo ""
info "Installing to ${BOLD}OpenClaw${NC} ..."

# Preserve user-editable CONFIG.md across upgrades
BACKUP_CONFIG=""
if [[ -f "${target_dir}/CONFIG.md" ]]; then
  BACKUP_CONFIG="$(mktemp)"
  cp "${target_dir}/CONFIG.md" "${BACKUP_CONFIG}"
fi

if [[ -f "${target_dir}/SKILL.md" ]]; then
  warn "Existing installation found, overwriting..."
  rm -rf "${target_dir}"
fi

mkdir -p "${target_scripts}"

cp "${TMP_DIR}/SKILL.md" "${target_dir}/SKILL.md"
cp "${TMP_DIR}/scripts/shell.sh" "${target_scripts}/shell.sh"
chmod +x "${target_scripts}/shell.sh"

# Restore user config if present
if [[ -n "${BACKUP_CONFIG}" ]]; then
  cp "${BACKUP_CONFIG}" "${target_dir}/CONFIG.md"
  rm -f "${BACKUP_CONFIG}"
  echo -e "    ${DIM}Restored: CONFIG.md${NC}"
fi

if [[ ! -f "${target_dir}/SKILL.md" ]] || [[ ! -f "${target_scripts}/shell.sh" ]]; then
  error "Installation failed (files missing after copy)."
fi

ok "OpenClaw installed successfully"
echo -e "    ${DIM}${target_dir}/SKILL.md${NC}"
echo -e "    ${DIM}${target_scripts}/shell.sh${NC}"

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
