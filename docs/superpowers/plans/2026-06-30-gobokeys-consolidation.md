# Gobokeys Consolidation + Idempotent Installer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate the new `us_no` XKB layout into this repo and ship an idempotent installer that re-applies only the necessary patches (symbol file + rules registration) on any machine, surviving OS updates to the rules files.

**Architecture:** A restructured repo with `symbols/us_no` (source of truth), a `rules/us_no.layout.xml` registration snippet, and `install.sh`. The installer copies the symbol file and idempotently patches `/usr/share/X11/xkb/rules/evdev.xml` and `evdev.lst`. XML handling lives in `lib/patch_evdev_xml.py`: **detection** parses the XML (structure-aware), while **insertion** is a surgical text insert immediately before the final `</layoutList>` so the rest of the 250 KB system file — DOCTYPE, comments, formatting — is preserved untouched. (This refines the spec's "ElementTree write-back" to avoid round-trip damage to the DOCTYPE/formatting; detection is still structure-aware.) An `XKB_BASE` env override points the script at a fixture dir so the whole thing is testable without root.

**Tech Stack:** Bash, Python 3 stdlib (`xml.etree.ElementTree`), `localectl`. Tests are a plain bash harness driving the installer against a temp fixture.

---

## File Structure

- `install.sh` — CLI orchestration: `install` (default), `--check`, `--activate`. Honors `XKB_BASE`.
- `lib/patch_evdev_xml.py` — `check` / `patch` modes for the evdev.xml `<layout>` entry.
- `symbols/us_no` — the layout symbol file (copied from `~/JottaSync/Gobokeys/us_no`).
- `rules/us_no.layout.xml` — the `<layout>` registration snippet injected into evdev.xml.
- `tests/fixtures/evdev.xml`, `tests/fixtures/evdev.lst` — minimal rules files lacking `us_no`.
- `tests/test_install.sh` — bash test harness (check → install → re-check → idempotency).
- `archive/` — old layout content moved out of the repo root.
- `README.md` — rewritten for the new layout + install usage.

---

## Task 1: Restructure repo (archive old, add new source files)

**Files:**
- Create: `archive/` (move old content in)
- Create: `symbols/us_no`, `rules/us_no.layout.xml`
- Modify: repo layout via `git mv` / copies

- [ ] **Step 1: Archive the old layout content**

```bash
cd /home/gobo/Source/gobokeys
mkdir -p archive/old-rules
git mv xkb/symbols/gobo archive/gobo-symbols
git mv xkb/symbols/us xkb/symbols/latin xkb/symbols/no xkb/symbols/level3 xkb/symbols/stdin.xkm archive/
git mv xkb/rules/evdev.xml xkb/rules/evdev.lst xkb/rules/evdev.extras.xml archive/old-rules/
# remove now-empty xkb tree
rmdir xkb/symbols xkb/rules xkb 2>/dev/null || true
```

Expected: `xkb/` is gone, files now under `archive/`.

- [ ] **Step 2: Copy the new layout symbol file in as source of truth**

```bash
mkdir -p symbols rules lib tests/fixtures
cp ~/JottaSync/Gobokeys/us_no symbols/us_no
cp ~/JottaSync/Gobokeys/us_macos_caps archive/us_macos_caps   # unused variant, reference only
```

Expected: `symbols/us_no` exists and matches the JottaSync source (`cmp -s symbols/us_no ~/JottaSync/Gobokeys/us_no` → exit 0).

- [ ] **Step 3: Create the rules registration snippet**

Create `rules/us_no.layout.xml`:

```xml
<layout>
  <configItem>
    <name>us_no</name>
    <shortDescription>us_no</shortDescription>
    <description>English (Gobokeys) - Gobo's Norwegian overlay</description>
    <languageList>
      <iso639Id>eng</iso639Id>
      <iso639Id>nor</iso639Id>
    </languageList>
  </configItem>
</layout>
```

- [ ] **Step 4: Verify and commit**

Run: `git add -A && git status --short`
Expected: old files shown as renamed into `archive/`, new `symbols/us_no` + `rules/us_no.layout.xml` added.

```bash
git commit -m "Restructure: archive old layout, add us_no source + registration snippet"
```

---

## Task 2: Create test fixtures and a failing test harness

**Files:**
- Create: `tests/fixtures/evdev.xml`, `tests/fixtures/evdev.lst`
- Create: `tests/test_install.sh`

- [ ] **Step 1: Create the evdev.xml fixture (no us_no, with DOCTYPE to prove preservation)**

Create `tests/fixtures/evdev.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xkbConfigRegistry SYSTEM "xkb.dtd">
<xkbConfigRegistry version="1.1">
  <layoutList>
    <layout>
      <configItem>
        <name>us</name>
        <shortDescription>en</shortDescription>
        <description>English (US)</description>
      </configItem>
    </layout>
    <layout>
      <configItem>
        <name>no</name>
        <shortDescription>no</shortDescription>
        <description>Norwegian</description>
      </configItem>
    </layout>
  </layoutList>
</xkbConfigRegistry>
```

- [ ] **Step 2: Create the evdev.lst fixture (no us_no)**

Create `tests/fixtures/evdev.lst`:

```
! model
  pc105           Generic 105-key PC

! layout
  us              English (US)
  no              Norwegian

! variant
  intl            us: English (US, intl., with dead keys)
```

- [ ] **Step 3: Write the test harness**

Create `tests/test_install.sh`:

```bash
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
```

- [ ] **Step 4: Run the harness to confirm it fails (no install.sh yet)**

Run: `bash tests/test_install.sh`
Expected: FAIL — `install.sh` does not exist, assertions fail / non-zero exit.

- [ ] **Step 5: Commit**

```bash
git add tests/ && git commit -m "Add test fixtures and installer test harness"
```

---

## Task 3: Implement the evdev.xml patch helper

**Files:**
- Create: `lib/patch_evdev_xml.py`

- [ ] **Step 1: Write the helper**

Create `lib/patch_evdev_xml.py`:

```python
#!/usr/bin/env python3
"""Idempotently detect/insert a <layout> registration in an evdev.xml rules file.

Detection parses the XML (structure-aware). Insertion is a surgical text insert
immediately before the final </layoutList> close tag, so the rest of the file --
DOCTYPE, comments, formatting -- is preserved.

Usage:
  patch_evdev_xml.py check <xml> <name>            # exit 0 if present, 1 if missing
  patch_evdev_xml.py patch <xml> <name> <snippet>  # insert if missing (idempotent)
"""
import sys
import xml.etree.ElementTree as ET


def is_present(xml_path, name):
    root = ET.parse(xml_path).getroot()
    for layout in root.iter("layout"):
        ci = layout.find("configItem")
        if ci is None:
            continue
        n = ci.find("name")
        if n is not None and (n.text or "").strip() == name:
            return True
    return False


def insert(xml_path, snippet_path):
    with open(snippet_path, encoding="utf-8") as f:
        snippet = f.read().strip("\n")
    block = "\n".join(("  " + ln) if ln.strip() else ln
                      for ln in snippet.splitlines())
    with open(xml_path, encoding="utf-8") as f:
        content = f.read()
    idx = content.rfind("</layoutList>")
    if idx == -1:
        sys.exit("error: no </layoutList> in %s" % xml_path)
    with open(xml_path, "w", encoding="utf-8") as f:
        f.write(content[:idx] + block + "\n" + content[idx:])


def main(argv):
    if len(argv) < 3:
        sys.exit("usage: patch_evdev_xml.py {check|patch} <xml> <name> [snippet]")
    mode, xml_path, name = argv[0], argv[1], argv[2]
    if mode == "check":
        sys.exit(0 if is_present(xml_path, name) else 1)
    if mode == "patch":
        if is_present(xml_path, name):
            print("evdev.xml: already registered")
            return
        if len(argv) < 4:
            sys.exit("patch requires a snippet path")
        insert(xml_path, argv[3])
        print("evdev.xml: inserted %s registration" % name)
        return
    sys.exit("unknown mode: %s" % mode)


if __name__ == "__main__":
    main(sys.argv[1:])
```

- [ ] **Step 2: Smoke-test the helper directly against the fixture**

```bash
W=$(mktemp -d); cp tests/fixtures/evdev.xml "$W/e.xml"
python3 lib/patch_evdev_xml.py check "$W/e.xml" us_no; echo "check before: $?"   # expect 1
python3 lib/patch_evdev_xml.py patch "$W/e.xml" us_no rules/us_no.layout.xml      # expect "inserted"
python3 lib/patch_evdev_xml.py check "$W/e.xml" us_no; echo "check after: $?"     # expect 0
python3 lib/patch_evdev_xml.py patch "$W/e.xml" us_no rules/us_no.layout.xml      # expect "already registered"
grep -c "<name>us_no</name>" "$W/e.xml"   # expect 1
grep -c "<!DOCTYPE" "$W/e.xml"            # expect 1
rm -rf "$W"
```

Expected: check before → 1, check after → 0, second patch is a no-op, exactly one entry, DOCTYPE intact.

- [ ] **Step 3: Commit**

```bash
git add lib/patch_evdev_xml.py && git commit -m "Add idempotent evdev.xml patch helper"
```

---

## Task 4: Implement install.sh

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write the installer**

Create `install.sh`:

```bash
#!/usr/bin/env bash
# Gobokeys installer: idempotently install the us_no layout + register it in the
# system XKB rules. Safe to re-run. Honors XKB_BASE for testing.
set -euo pipefail

XKB_BASE="${XKB_BASE:-/usr/share/X11/xkb}"
SYMBOLS_DIR="$XKB_BASE/symbols"
RULES_DIR="$XKB_BASE/rules"
EVDEV_XML="$RULES_DIR/evdev.xml"
EVDEV_LST="$RULES_DIR/evdev.lst"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SYMBOL="$SCRIPT_DIR/symbols/us_no"
SRC_LAYOUT_XML="$SCRIPT_DIR/rules/us_no.layout.xml"
XML_HELPER="$SCRIPT_DIR/lib/patch_evdev_xml.py"

LAYOUT_NAME="us_no"
LST_LINE="  us_no           English (Gobokeys)"

SUDO=""
need_sudo() {
  if [[ ! -w "$SYMBOLS_DIR" || ! -w "$EVDEV_XML" || ! -w "$EVDEV_LST" ]]; then
    SUDO="sudo"
  fi
}

symbol_present() { [[ -f "$SYMBOLS_DIR/us_no" ]]; }
xml_present()    { python3 "$XML_HELPER" check "$EVDEV_XML" "$LAYOUT_NAME"; }
lst_present()    { awk '$1=="us_no"{f=1} END{exit f?0:1}' "$EVDEV_LST"; }

backup_once() {
  local f="$1"
  if [[ -f "$f" && ! -f "$f.gobokeys.bak" ]]; then
    $SUDO cp "$f" "$f.gobokeys.bak"
    echo "backup: $f -> $f.gobokeys.bak"
  fi
}

install_symbol() {
  $SUDO install -Dm644 "$SRC_SYMBOL" "$SYMBOLS_DIR/us_no"
  echo "symbols/us_no: installed"
}

patch_lst() {
  if lst_present; then echo "evdev.lst: already registered"; return; fi
  local tmp; tmp="$(mktemp)"
  awk -v line="$LST_LINE" '
    { print }
    /^! layout/ && !done { print line; done=1 }
  ' "$EVDEV_LST" > "$tmp"
  $SUDO cp "$tmp" "$EVDEV_LST"; rm -f "$tmp"
  echo "evdev.lst: inserted us_no registration"
}

cmd_check() {
  local missing=0
  if symbol_present; then echo "symbols/us_no:           present"
  else echo "symbols/us_no:           MISSING"; missing=1; fi
  if xml_present;    then echo "evdev.xml registration:  present"
  else echo "evdev.xml registration:  MISSING"; missing=1; fi
  if lst_present;    then echo "evdev.lst registration:  present"
  else echo "evdev.lst registration:  MISSING"; missing=1; fi
  return $missing
}

cmd_install() {
  need_sudo
  install_symbol
  backup_once "$EVDEV_XML"
  backup_once "$EVDEV_LST"
  $SUDO python3 "$XML_HELPER" patch "$EVDEV_XML" "$LAYOUT_NAME" "$SRC_LAYOUT_XML"
  patch_lst
  echo "done. Run '$0 --check' to verify, or '$0 --activate' to switch to it now."
}

cmd_activate() {
  echo "activating us_no via localectl..."
  localectl set-x11-keymap us_no
  echo "active. (Wayland/Niri reads xkb settings from locale1.)"
}

case "${1:-install}" in
  --check)    cmd_check ;;
  --activate) cmd_install; cmd_activate ;;
  install|"") cmd_install ;;
  -h|--help)  echo "usage: $0 [install|--check|--activate]" ;;
  *) echo "usage: $0 [install|--check|--activate]" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x install.sh
```

- [ ] **Step 3: Run the test harness — expect all green**

Run: `bash tests/test_install.sh`
Expected: every line prints `ok   - ...`, harness exits 0.

- [ ] **Step 4: Commit**

```bash
git add install.sh && git commit -m "Add idempotent installer (install / --check / --activate)"
```

---

## Task 5: Rewrite README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README contents**

Overwrite `README.md`:

```markdown
# Gobokeys — `us_no` XKB layout

A personalised keyboard layout: a US base with a Norwegian overlay. Accented
characters live on levels 3/4, and **CapsLock acts as AltGr** (`ISO_Level3_Shift`).
Registered as **`us_no`** / "English (Gobokeys)".

## Layout

`symbols/us_no` is the source of truth. It is a standalone XKB symbol file installed
to `/usr/share/X11/xkb/symbols/us_no`, plus a registration entry in the system rules
(`evdev.xml`, `evdev.lst`) so the layout is selectable by name.

## Install

```sh
./install.sh            # install symbol file + register in the XKB rules (uses sudo)
./install.sh --check    # report what's installed / missing (no changes, no root)
./install.sh --activate # install, then switch the machine to us_no via localectl
```

The installer is **idempotent** and safe to re-run. It only *adds* the `us_no`
registration to the system rules files — it never overwrites them — so it survives OS
updates to `xkeyboard-config` (which periodically rewrite `evdev.xml` and wipe custom
registrations, while leaving the standalone symbol file intact). Originals are backed
up to `*.gobokeys.bak` before first modification.

On Wayland/Niri the compositor reads xkb settings from `locale1`, so `--activate`
uses `localectl set-x11-keymap us_no`.

## Repo layout

- `symbols/us_no` — the layout (source of truth)
- `rules/us_no.layout.xml` — the `<layout>` registration snippet injected into evdev.xml
- `lib/patch_evdev_xml.py` — idempotent evdev.xml detect/insert helper
- `install.sh` — installer
- `tests/` — fixture-based test harness (`bash tests/test_install.sh`)
- `archive/` — the previous "gobo" layout and an unused `us_macos_caps` variant, kept
  for reference
```

- [ ] **Step 2: Commit**

```bash
git add README.md && git commit -m "Rewrite README for us_no layout + installer"
```

---

## Task 6: Live-machine verification (integration)

**Files:** none (runs against the real system)

- [ ] **Step 1: Dry-run check against the real system**

Run: `./install.sh --check`
Expected (matches confirmed drift on `fraggle`): `symbols/us_no: present`,
`evdev.xml registration: MISSING`, `evdev.lst registration: MISSING`, exit code 1.

- [ ] **Step 2: Install for real**

Run: `./install.sh` (will prompt for sudo)
Expected: symbol installed, backups created for evdev.xml/evdev.lst, both registrations inserted.

- [ ] **Step 3: Re-check — expect all green and idempotent**

Run: `./install.sh --check`
Expected: all three `present`, exit 0.

Run: `./install.sh` again
Expected: "already registered" for both rules files; no duplicates.

Confirm no duplicate entries:
Run: `grep -c '<name>us_no</name>' /usr/share/X11/xkb/rules/evdev.xml`
Expected: `1`

- [ ] **Step 4: Confirm the layout resolves**

Run: `setxkbmap -print us_no >/dev/null 2>&1 && echo OK`
Expected: `OK` (xkbcomp resolves the named layout). Optionally verify it appears in the
system layout picker as "English (Gobokeys)".

- [ ] **Step 5: Final commit (if any tracked files changed)**

No repo files should change in this task; it is verification only. If `tests/` or docs
needed a tweak from what you observed, commit it with a descriptive message.
```
