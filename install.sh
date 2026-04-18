#!/usr/bin/env bash
# Mapickii Skill — Install Script
#
# Install or update Mapickii Skill with a single command:
#
#   curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.0/install.sh | bash
#   wget -qO- https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.0/install.sh | bash
#
# Options (via environment variables):
#   MAPICKII_VERSION=v1.0.0  bash -c "$(curl -fsSL ...)"   # Install specific version
#   MAPICKII_LOCAL=1         bash -c "$(curl -fsSL ...)"   # Install to current project only
#   MAPICKII_REPO=owner/repo bash -c "$(curl -fsSL ...)"   # Override source repo

set -e

# -- Config --------------------------------------------------------------------

REPO="${MAPICKII_REPO:-mapick-ai/mapickii}"
VERSION="${MAPICKII_VERSION:-latest}"
LOCAL_MODE="${MAPICKII_LOCAL:-0}"

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

# -- Platform definitions ------------------------------------------------------

TOOL_NAMES=("Claude Code" "Gemini CLI" "OpenCode" "Codex" "QwenCode" "OpenClaw")
TOOL_COMMANDS=("claude" "gemini" "opencode" "codex" "qwencode" "claw")
TOOL_ALT_COMMANDS=("claude-code" "" "" "codex-cli" "" "openclaw")
TOOL_SKILL_DIRS=(
  "${HOME}/.claude/skills"       # Claude Code
  "${HOME}/.gemini/skills"       # Gemini CLI
  "${HOME}/.opencode/skills"     # OpenCode
  "${HOME}/.codex/skills"        # Codex
  "${HOME}/.qwencode/skills"     # QwenCode
  "${HOME}/.openclaw/skills"     # OpenClaw
)

# -- Detect installed tools ----------------------------------------------------

detect_tool() {
  local idx="$1"
  local cmd="${TOOL_COMMANDS[$idx]}"
  local alt="${TOOL_ALT_COMMANDS[$idx]}"
  DETECTED_PATH=""

  if command -v "${cmd}" &>/dev/null; then
    DETECTED_PATH="$(command -v "${cmd}")"
    return 0
  fi

  if [[ -n "${alt}" ]] && command -v "${alt}" &>/dev/null; then
    DETECTED_PATH="$(command -v "${alt}")"
    return 0
  fi

  return 1
}

DETECTED_INDICES=()
DETECTED_LABELS=()
DETECTED_PATHS=()

info "Detecting AI coding tools..."
echo ""

for i in "${!TOOL_NAMES[@]}"; do
  name="${TOOL_NAMES[$i]}"
  cmd="${TOOL_COMMANDS[$i]}"
  alt="${TOOL_ALT_COMMANDS[$i]}"

  if detect_tool "$i"; then
    echo -e "  ${GREEN}✓${NC} ${BOLD}${name}${NC}  ${DIM}(${DETECTED_PATH})${NC}"
    DETECTED_INDICES+=("$i")
    DETECTED_LABELS+=("${name}")
    DETECTED_PATHS+=("${DETECTED_PATH}")
  else
    label="${cmd}"
    [[ -n "${alt}" ]] && label="${cmd} / ${alt}"
    echo -e "  ${DIM}✗ ${name}  (${label} not found)${NC}"
  fi
done

echo ""

if [[ ${#DETECTED_INDICES[@]} -eq 0 ]]; then
  error "No supported AI coding tools detected.

  Supported tools:
    - Claude Code    (claude)
    - Gemini CLI     (gemini)
    - OpenCode       (opencode)
    - Codex          (codex)
    - QwenCode       (qwencode)
    - OpenClaw       (claw / openclaw)

  Please install at least one tool and retry."
fi

# -- Interactive selection -----------------------------------------------------

if [[ "${LOCAL_MODE}" == "1" ]]; then
  info "Mode: local project (install to current directory)"
else
  info "Mode: global (install to home directory)"
fi
echo ""

echo -e "${BOLD}Select tools to install Mapickii Skill:${NC}"
echo ""

for n in "${!DETECTED_INDICES[@]}"; do
  num=$((n + 1))
  idx="${DETECTED_INDICES[$n]}"
  name="${TOOL_NAMES[$idx]}"
  path="${DETECTED_PATHS[$n]}"
  if [[ "${LOCAL_MODE}" == "1" ]]; then
    target="$(pwd)/.claude/skills"
  else
    target="${TOOL_SKILL_DIRS[$idx]}"
  fi
  echo -e "  ${CYAN}[${num}]${NC} ${BOLD}${name}${NC}"
  echo -e "      ${DIM}Path: ${path}${NC}"
  echo -e "      ${DIM}Install to: ${target}/mapickii/${NC}"
done

if [[ ${#DETECTED_INDICES[@]} -gt 1 ]]; then
  echo ""
  echo -e "  ${CYAN}[a]${NC} ${BOLD}Install all${NC}"
fi

echo ""
echo -e "  ${DIM}[q] Quit${NC}"
echo ""

printf "Choose (enter numbers, comma-separated for multiple, e.g. 1,3): "
read -r CHOICE </dev/tty 2>/dev/null || read -r CHOICE 2>/dev/null || CHOICE=""

if [[ "${CHOICE}" == "q" || "${CHOICE}" == "Q" || -z "${CHOICE}" ]]; then
  info "Cancelled."
  exit 0
fi

# -- Parse selection -----------------------------------------------------------

SELECTED_INDICES=()

if [[ "${CHOICE}" == "a" || "${CHOICE}" == "A" ]]; then
  SELECTED_INDICES=("${DETECTED_INDICES[@]}")
else
  IFS=',' read -ra NUMS <<< "${CHOICE}"
  for num in "${NUMS[@]}"; do
    num=$(echo "${num}" | tr -d '[:space:]')
    if ! [[ "${num}" =~ ^[0-9]+$ ]]; then
      error "Invalid input: ${num}"
    fi
    arr_idx=$((num - 1))
    if [[ ${arr_idx} -lt 0 || ${arr_idx} -ge ${#DETECTED_INDICES[@]} ]]; then
      error "Number out of range: ${num} (valid: 1-${#DETECTED_INDICES[@]})"
    fi
    SELECTED_INDICES+=("${DETECTED_INDICES[$arr_idx]}")
  done
fi

if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
  error "No tools selected."
fi

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

# -- Install to each selected tool ---------------------------------------------

INSTALL_COUNT=0

for idx in "${SELECTED_INDICES[@]}"; do
  name="${TOOL_NAMES[$idx]}"

  if [[ "${LOCAL_MODE}" == "1" ]]; then
    target_dir="$(pwd)/.claude/skills/mapickii"
  else
    target_dir="${TOOL_SKILL_DIRS[$idx]}/mapickii"
  fi
  target_scripts="${target_dir}/scripts"

  echo ""
  info "Installing to ${BOLD}${name}${NC} ..."

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

  if [[ -f "${target_dir}/SKILL.md" ]] && [[ -f "${target_scripts}/shell.sh" ]]; then
    ok "${name} installed successfully"
    echo -e "    ${DIM}${target_dir}/SKILL.md${NC}"
    echo -e "    ${DIM}${target_scripts}/shell.sh${NC}"
    INSTALL_COUNT=$((INSTALL_COUNT + 1))
  else
    warn "${name} installation failed"
  fi
done

# -- Summary -------------------------------------------------------------------

echo ""
echo -e "${DIM}────────────────────────────────────────${NC}"
echo ""

if [[ ${INSTALL_COUNT} -gt 0 ]]; then
  ok "Done! ${INSTALL_COUNT}/${#SELECTED_INDICES[@]} tools installed"
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
else
  error "All installations failed."
fi
