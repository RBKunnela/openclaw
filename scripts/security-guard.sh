#!/usr/bin/env bash
# security-guard.sh — Scan the repo for banned extensions, risky packages,
# and suspicious patterns that should not exist in this fork.
# Exit code: 0 = clean, 1 = findings detected.

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

findings=0

heading() { echo -e "\n${BOLD}── $1 ──${RESET}"; }

fail() {
  echo -e "  ${RED}✗${RESET} $1"
  findings=$((findings + 1))
}

warn() {
  echo -e "  ${YELLOW}!${RESET} $1"
  findings=$((findings + 1))
}

pass() {
  echo -e "  ${GREEN}✓${RESET} $1"
}

# ── 1. Banned extension directories ─────────────────────────────────────────
heading "Banned extension directories"

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

banned_found=0
for dir in "${BANNED_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    fail "Directory exists: $dir"
    banned_found=1
  fi
done
if [ "$banned_found" -eq 0 ]; then
  pass "No banned extension directories found"
fi

# ── 2. Native binary packages in package.json files ─────────────────────────
heading "Native binary packages"

RISKY_PACKAGES=(
  "@lancedb/lancedb"
  "@matrix-org/matrix-sdk-crypto-nodejs"
  "authenticate-pam"
  "nostr-tools"
  "@nicolo-ribaudo/chokidar-2"
)

pkg_found=0
while IFS= read -r -d '' pjson; do
  for pkg in "${RISKY_PACKAGES[@]}"; do
    if grep -q "\"$pkg\"" "$pjson" 2>/dev/null; then
      # Allow it in onlyBuiltDependencies (that's just the allowlist, not an install)
      # but flag it in dependencies/devDependencies
      if grep -A1 "\"dependencies\"" "$pjson" | grep -q "$pkg" 2>/dev/null ||
         grep -A1 "\"devDependencies\"" "$pjson" | grep -q "$pkg" 2>/dev/null; then
        fail "Risky native package '$pkg' found in $pjson"
        pkg_found=1
      fi
    fi
  done
done < <(find . -name "package.json" -not -path "*/node_modules/*" -print0)
if [ "$pkg_found" -eq 0 ]; then
  pass "No risky native packages in dependencies"
fi

# ── 3. Auto-start patterns ──────────────────────────────────────────────────
heading "Auto-start patterns in extensions"

# Note: `enabled: true` is normal channel config — only flag setInterval in
# plugin manifests or top-level extension entry points (not in test files).
autostart_found=0
while IFS= read -r -d '' extfile; do
  if grep -nE 'setInterval\s*\(' "$extfile" 2>/dev/null | head -5; then
    warn "setInterval found in: $extfile"
    autostart_found=1
  fi
done < <(find extensions/ \( -name "*.ts" -o -name "*.js" \) -not -name "*.test.*" -not -name "*.spec.*" 2>/dev/null | tr '\n' '\0')
if [ "$autostart_found" -eq 0 ]; then
  pass "No suspicious auto-start patterns in extensions"
fi

# ── 4. Private key handling ─────────────────────────────────────────────────
heading "Private key patterns in source"

# Use word-boundary-aware patterns to avoid false positives like "updateMask=".
privkey_found=0
while IFS= read -r -d '' srcfile; do
  if grep -nPi '\b(privateKey|secretKey|PRIVATE_KEY)\b' "$srcfile" 2>/dev/null | grep -vE '(\.test\.|\.spec\.|mock|fixture|example)' | head -5; then
    warn "Private key pattern in: $srcfile"
    privkey_found=1
  fi
done < <(find extensions/ \( -name "*.ts" -o -name "*.js" \) -not -name "*.test.*" -not -name "*.spec.*" 2>/dev/null | tr '\n' '\0')
if [ "$privkey_found" -eq 0 ]; then
  pass "No private key patterns in extensions"
fi

# ── 5. onlyBuiltDependencies audit ──────────────────────────────────────────
heading "onlyBuiltDependencies in root package.json"

EXPECTED_BUILT_DEPS=(
  "@lydell/node-pty"
  "@matrix-org/matrix-sdk-crypto-nodejs"
  "@napi-rs/canvas"
  "@whiskeysockets/baileys"
  "authenticate-pam"
  "esbuild"
  "node-llama-cpp"
  "protobufjs"
  "sharp"
)

if [ -f "package.json" ]; then
  # Extract onlyBuiltDependencies entries
  built_deps=$(node -e "
    const pkg = require('./package.json');
    const deps = pkg.pnpm?.onlyBuiltDependencies || [];
    deps.forEach(d => console.log(d));
  " 2>/dev/null || true)

  unexpected=0
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    is_expected=0
    for expected in "${EXPECTED_BUILT_DEPS[@]}"; do
      if [ "$dep" = "$expected" ]; then
        is_expected=1
        break
      fi
    done
    if [ "$is_expected" -eq 0 ]; then
      warn "Unexpected onlyBuiltDependencies entry: $dep"
      unexpected=1
    fi
  done <<< "$built_deps"

  if [ "$unexpected" -eq 0 ]; then
    pass "onlyBuiltDependencies matches expected list"
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
if [ "$findings" -gt 0 ]; then
  echo -e "${RED}${BOLD}Security guard found $findings issue(s).${RESET}"
  exit 1
else
  echo -e "${GREEN}${BOLD}Security guard: all clear.${RESET}"
  exit 0
fi
