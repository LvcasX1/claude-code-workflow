#!/usr/bin/env bash
# setup.sh — Claude Code agentic workflow setup
# Assumes Claude Code CLI is already installed. Run once; re-running skips steps already done.
set -euo pipefail

if [[ ! -t 0 ]]; then
  echo "This script requires an interactive terminal (stdin is not a TTY)."
  exit 1
fi

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

INSTALLED=()

# ── Helpers ───────────────────────────────────────────────────────────────────
step()   { echo -e "\n${BOLD}── $1 ──────────────────────────────────────────────${RESET}"; }
ok()     { echo -e "  ${GREEN}✓${RESET} $1"; }
info()   { echo -e "  → $1"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET} $1"; }
fail()   { echo -e "  ${RED}✗${RESET} $1" >&2; exit 1; }

prompt_yn() {
  local question="$1" default="${2:-n}" prompt answer
  if [[ "$default" == "y" ]]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
  read -rp "  $question $prompt " answer </dev/tty
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# Prompt for a secret value (no echo). Label goes to stderr so command substitution
# captures only the value.
prompt_secret() {
  local label="$1" value
  printf "  %s: " "$label" >&2
  read -rs value </dev/tty
  printf "\n" >&2
  printf '%s' "$value"
}

plugin_installed() {
  claude plugin list 2>/dev/null | grep -qi "$1" || return 1
}

mcp_registered() {
  claude mcp get "$1" &>/dev/null || return 1
}

# ── Section 1: Prerequisites ──────────────────────────────────────────────────
step "Prerequisites"

if command -v git &>/dev/null; then
  ok "git found"
else
  warn "git not found (recommended but not required by this script)"
fi

NODE_OK=false
if command -v node &>/dev/null; then
  ok "node found ($(node --version))"
  NODE_OK=true
else
  warn "node not found — CCStatusLine will be skipped if node is unavailable"
fi

if ! command -v claude &>/dev/null; then
  echo ""
  echo -e "  ${RED}✗${RESET} claude not found"
  echo ""
  echo "  Install Claude Code first, then re-run this script:"
  case "$(uname -s)" in
    Darwin|Linux)
      echo "    curl -fsSL https://claude.ai/install.sh | sh"
      ;;
    CYGWIN*|MINGW*|MSYS*)
      echo "    winget install Anthropic.ClaudeCode"
      ;;
    *)
      echo "    https://claude.ai/download"
      ;;
  esac
  echo ""
  exit 1
fi

CLAUDE_VER=$(claude --version 2>/dev/null || echo "unknown version")
ok "claude found ($CLAUDE_VER)"

# ── Section 2: Plugins ────────────────────────────────────────────────────────
step "Plugins"

# Superpowers (required — enforces the structured workflow)
if plugin_installed "superpowers"; then
  ok "Superpowers already installed"
else
  info "Installing Superpowers..."
  claude plugin install superpowers@claude-plugins-official
  ok "Superpowers installed"
  INSTALLED+=("Superpowers")
fi

# Caveman (optional — reduces token usage 22-87% via compact syntax)
echo ""
if plugin_installed "caveman"; then
  ok "Caveman already installed"
elif prompt_yn "Caveman reduces token usage 22-87% via compact syntax. Install it?"; then
  info "Installing Caveman..."
  claude plugin install caveman@caveman
  ok "Caveman installed"
  INSTALLED+=("Caveman")
fi

# ── Section 3: MCP Servers ────────────────────────────────────────────────────
step "MCP Servers"

# Detect already-registered MCPs
CTX7_DONE=""; FIGMA_DONE=""; CODA_DONE=""; GH_DONE=""
mcp_registered "context7" && CTX7_DONE="[✓ configured]" || true
mcp_registered "figma"    && FIGMA_DONE="[✓ configured]" || true
mcp_registered "coda"     && CODA_DONE="[✓ configured]"  || true
mcp_registered "github"   && GH_DONE="[✓ configured]"    || true

echo ""
echo "  Select MCPs to configure (space-separated numbers, or Enter to skip):"
echo ""
printf "    1) Context7  — live library docs, version-aware         %s\n" "$CTX7_DONE"
printf "    2) Figma     — design file access                       %s\n" "$FIGMA_DONE"
printf "    3) Coda      — document read/write                      %s\n" "$CODA_DONE"
printf "    4) GitHub    — PRs, issues, repos                       %s\n" "$GH_DONE"
echo ""
read -rp "  > " selection </dev/tty || selection=""

MCP_LABELS=()

for num in $selection; do
  case "$num" in
    1)
      if [[ -n "$CTX7_DONE" ]]; then
        ok "Context7 already configured"
      else
        key=$(prompt_secret "Context7 API key (from context7.com)")
        info "Registering Context7..."
        claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key "$key"
        ok "Context7 registered"
        MCP_LABELS+=("Context7")
      fi
      ;;
    2)
      if [[ -n "$FIGMA_DONE" ]]; then
        ok "Figma already configured"
      else
        key=$(prompt_secret "Figma personal access token")
        info "Registering Figma..."
        claude mcp add --scope user figma -- npx -y @figma/mcp-server --figma-api-key "$key"
        ok "Figma registered"
        MCP_LABELS+=("Figma")
      fi
      ;;
    3)
      if [[ -n "$CODA_DONE" ]]; then
        ok "Coda already configured"
      else
        key=$(prompt_secret "Coda API token")
        info "Registering Coda..."
        claude mcp add --scope user coda -- npx -y coda-mcp --api-key "$key"
        ok "Coda registered"
        MCP_LABELS+=("Coda")
      fi
      ;;
    4)
      if [[ -n "$GH_DONE" ]]; then
        ok "GitHub already configured"
      else
        token=$(prompt_secret "GitHub personal access token")
        info "Registering GitHub MCP..."
        claude mcp add --scope user -e GITHUB_PERSONAL_ACCESS_TOKEN="$token" github -- npx -y @modelcontextprotocol/server-github
        ok "GitHub registered"
        MCP_LABELS+=("GitHub")
      fi
      ;;
    *)
      warn "Unknown selection '$num' — skipping"
      ;;
  esac
done

if [[ ${#MCP_LABELS[@]} -gt 0 ]]; then
  INSTALLED+=("MCPs: $(IFS=', '; echo "${MCP_LABELS[*]}")")
fi

# ── Section 4: CCStatusLine ───────────────────────────────────────────────────
step "CCStatusLine"

echo ""
if command -v ccstatusline &>/dev/null; then
  ok "CCStatusLine already installed"
elif ! $NODE_OK; then
  warn "node not found — skipping CCStatusLine"
elif prompt_yn "CCStatusLine shows model, context, and git state in your terminal. Install it?"; then
  info "Installing CCStatusLine..."
  npm install -g ccstatusline
  ok "CCStatusLine installed"

  if [[ -f "config/ccstatusline.json" ]]; then
    info "Copying config..."
    mkdir -p "$HOME/.config/ccstatusline"
    cp config/ccstatusline.json "$HOME/.config/ccstatusline/config.json"
    ok "Config copied → ~/.config/ccstatusline/config.json"
  fi

  echo ""
  echo "  Activate in Claude Code with: /statusline"
  INSTALLED+=("CCStatusLine")
fi

# ── Section 5: Verification & Summary ────────────────────────────────────────
step "Verification"

echo ""
if [[ -t 1 ]]; then
  info "Running claude doctor..."
  echo ""
  claude doctor || true
else
  info "Skipping claude doctor (not a TTY)"
  echo ""
  info "Installed MCPs:"
  claude mcp list 2>/dev/null || true
  echo ""
  info "Installed plugins:"
  claude plugin list 2>/dev/null || true
fi

# Build summary
echo ""
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │  Setup complete!                                             │"

if [[ ${#INSTALLED[@]} -gt 0 ]]; then
  echo "  │                                                              │"
  for item in "${INSTALLED[@]}"; do
    printf "  │  %-62s│\n" "  $item"
  done
fi

echo "  │                                                              │"
echo "  │  Next steps:                                                 │"
echo "  │    claude          — start a session                         │"
echo "  │    /mcp            — verify MCP connections                  │"
echo "  │    /find-skills    — verify plugins                          │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo ""
