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
