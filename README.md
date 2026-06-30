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
