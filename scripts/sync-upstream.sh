#!/usr/bin/env bash
# sync-upstream.sh — Safely cherry-pick upstream commits while enforcing
# banned-extension removal and security guardrails.
#
# Usage:
#   scripts/sync-upstream.sh                  # interactive: list & pick
#   scripts/sync-upstream.sh <commit>         # cherry-pick a single commit
#   scripts/sync-upstream.sh <from>..<to>     # cherry-pick a range

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"
SECURITY_GUARD="$ROOT_DIR/scripts/security-guard.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

BANNED_DIRS=(
  extensions/nostr
  extensions/matrix
  extensions/memory-lancedb
  extensions/diagnostics-otel
  extensions/msteams
  extensions/twitch
  extensions/tlon
  extensions/voice-call
  extensions/phone-control
)

# ── Helpers ──────────────────────────────────────────────────────────────────

die() { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }

ensure_upstream() {
  if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
    echo -e "${YELLOW}Remote '$UPSTREAM_REMOTE' not found. Adding it...${RESET}"
    git remote add "$UPSTREAM_REMOTE" "https://github.com/openclaw/openclaw.git"
  fi
}

fetch_upstream() {
  echo -e "${BOLD}Fetching $UPSTREAM_REMOTE/$UPSTREAM_BRANCH...${RESET}"
  git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH" --no-tags
}

# Remove any files from banned extension dirs that may have been introduced
# by a cherry-pick. Amends the cherry-pick commit if removals are needed.
scrub_banned_files() {
  local removed=()

  for dir in "${BANNED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
      removed+=("$dir")
      git rm -rf --quiet "$dir" 2>/dev/null || true
    fi
  done

  if [ "${#removed[@]}" -gt 0 ]; then
    echo -e "  ${YELLOW}Scrubbed banned paths:${RESET}"
    for r in "${removed[@]}"; do
      echo "    • $r"
    done
    git commit --amend --no-edit --quiet
  fi
}

run_security_guard() {
  if [ -x "$SECURITY_GUARD" ]; then
    echo -e "\n${BOLD}Running security guard...${RESET}"
    if ! bash "$SECURITY_GUARD"; then
      echo -e "${RED}Security guard found issues after cherry-pick.${RESET}"
      echo "Review and fix before continuing."
      return 1
    fi
  else
    echo -e "${YELLOW}Security guard script not found/executable, skipping.${RESET}"
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

ensure_upstream
fetch_upstream

# Determine the merge base with upstream
MERGE_BASE=$(git merge-base HEAD "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || true)
if [ -z "$MERGE_BASE" ]; then
  die "Cannot find merge base with $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
fi

# Count new upstream commits
NEW_COMMITS=$(git rev-list --count "$MERGE_BASE..$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")

echo -e "\n${BOLD}Upstream has ${GREEN}$NEW_COMMITS${RESET}${BOLD} new commit(s) since last sync.${RESET}"

if [ "$NEW_COMMITS" -eq 0 ]; then
  echo "Already up to date."
  exit 0
fi

# If args provided, cherry-pick directly
if [ $# -gt 0 ]; then
  TARGET="$1"

  echo -e "\n${BOLD}Cherry-picking: ${TARGET}${RESET}"

  if ! git cherry-pick --no-commit "$TARGET" 2>/dev/null; then
    echo -e "${RED}Cherry-pick conflict. Resolve manually, then run:${RESET}"
    echo "  git cherry-pick --continue"
    echo "  scripts/sync-upstream.sh   # re-run to scrub & verify"
    exit 1
  fi

  # Scrub banned files from the working tree before committing
  for dir in "${BANNED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
      git rm -rf --quiet "$dir" 2>/dev/null || true
      echo -e "  ${YELLOW}Removed banned: $dir${RESET}"
    fi
  done

  git commit --no-edit --quiet 2>/dev/null || true

  run_security_guard
  echo -e "\n${GREEN}${BOLD}Cherry-pick applied successfully.${RESET}"
  exit 0
fi

# Interactive mode: list commits and let user pick
echo -e "\n${BOLD}Recent upstream commits:${RESET}\n"
git log --oneline --no-merges "$MERGE_BASE..$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" | head -30

echo -e "\n${BOLD}Usage:${RESET}"
echo "  scripts/sync-upstream.sh <commit-hash>        # single commit"
echo "  scripts/sync-upstream.sh <from>..<to>          # range"
echo ""
echo "Each cherry-pick will automatically scrub banned extensions and"
echo "run the security guard."
