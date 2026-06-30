#!/usr/bin/env bash
# Drives install.sh against a throwaway XKB_BASE fixture. No root required.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
fail=0
pass() { echo "ok   - $1"; }
die()  { echo "FAIL - $1"; fail=1; }

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/symbols" "$WORK/rules"
  cp "$SCRIPT_DIR/fixtures/evdev.xml" "$WORK/rules/evdev.xml"
  cp "$SCRIPT_DIR/fixtures/evdev.lst" "$WORK/rules/evdev.lst"
  export XKB_BASE="$WORK"
}
teardown() { rm -rf "$WORK"; }

# 1. --check on a clean fixture: everything missing, non-zero exit
setup
if XKB_BASE="$WORK" "$REPO/install.sh" --check >/dev/null 2>&1; then
  die "--check should exit non-zero when nothing is installed"
else
  pass "--check exits non-zero on clean fixture"
fi

# 2. install: symbol copied, both rules patched
XKB_BASE="$WORK" "$REPO/install.sh" install >/dev/null 2>&1
[[ -f "$WORK/symbols/us_no" ]] && pass "symbol installed" || die "symbol not installed"
grep -q "Gobokeys" "$WORK/rules/evdev.xml" && pass "evdev.xml patched" || die "evdev.xml not patched"
grep -qE '^\s*us_no\s' "$WORK/rules/evdev.lst" && pass "evdev.lst patched" || die "evdev.lst not patched"

# 3. DOCTYPE preserved (proves we did not ElementTree-round-trip the file)
grep -q "<!DOCTYPE xkbConfigRegistry" "$WORK/rules/evdev.xml" \
  && pass "DOCTYPE preserved" || die "DOCTYPE lost"

# 4. --check now passes
if XKB_BASE="$WORK" "$REPO/install.sh" --check >/dev/null 2>&1; then
  pass "--check exits zero after install"
else
  die "--check should exit zero after install"
fi

# 5. idempotency: re-install adds no duplicate entries
XKB_BASE="$WORK" "$REPO/install.sh" install >/dev/null 2>&1
xcount=$(grep -c "<name>us_no</name>" "$WORK/rules/evdev.xml")
lcount=$(grep -cE '^\s*us_no\s' "$WORK/rules/evdev.lst")
[[ "$xcount" -eq 1 ]] && pass "evdev.xml has exactly one us_no" || die "evdev.xml duplicated us_no ($xcount)"
[[ "$lcount" -eq 1 ]] && pass "evdev.lst has exactly one us_no" || die "evdev.lst duplicated us_no ($lcount)"

# 6. resulting evdev.xml is still well-formed XML
python3 -c "import xml.etree.ElementTree as ET; ET.parse('$WORK/rules/evdev.xml')" \
  && pass "patched evdev.xml is well-formed" || die "patched evdev.xml is malformed"

teardown
exit $fail
