# Gobokeys consolidation + idempotent installer — Design

Date: 2026-06-30

## Problem

This repo currently holds an **old** personalised XKB layout (`xkb/symbols/gobo` plus
bundled copies of system files: `us`, `latin`, `no`, `level3`, `stdin.xkm`, and old
`evdev.*` rules). The user has since switched to a new layout that lives in
`~/JottaSync/Gobokeys/`.

The chosen active layout is **`us_no`** — a Norwegian overlay on a US base, with
CapsLock acting as AltGr (`ISO_Level3_Shift`) and accented characters on levels 3/4.
(`us_macos_caps`, a macOS-style CapsLock→Option variant, also exists in JottaSync but
is **not** the layout in use; it is kept only for reference.)

A custom XKB layout on this system has two parts:

1. **A standalone symbol file** — `us_no` placed in `/usr/share/X11/xkb/symbols/us_no`.
   Standalone files survive OS / `xkeyboard-config` package updates.
2. **Registration in the rules files** — a `<layout>` entry in
   `/usr/share/X11/xkb/rules/evdev.xml` and a line in `evdev.lst` so the layout appears
   in pickers and can be selected by name. **These get clobbered by OS updates.**

Confirmed drift on the live machine (`fraggle`): both symbol files are still installed
(Sep 2025), but the system `evdev.xml` was rewritten by an OS update on **2026-06-21**
and the `us_no` registration is **gone**. `evdev.extras.xml` never contained any gobo
entries.

## Goals

1. Consolidate the new `us_no` layout into this repo as the source of truth.
2. Archive the old layout content rather than deleting it.
3. Provide an installer script that, on any machine, re-applies **only the necessary
   patches** — never overwriting the OS's evolving rules files wholesale — and is safe to
   re-run.

## Non-goals

- Patching `evdev.extras.xml` (no gobo entries needed there).
- Registering / installing `us_macos_caps` (kept for reference only).
- Any Niri/Waybar/compositor config changes.

## Repo structure (after consolidation)

```
gobokeys/
├── README.md                   # rewritten: describes us_no + install usage
├── install.sh                  # installer / patcher
├── symbols/
│   └── us_no                   # the layout symbol file (source of truth)
├── rules/
│   └── us_no.layout.xml         # the <layout> registration snippet (configItem block)
├── docs/superpowers/specs/      # this design doc
└── archive/                     # old content, preserved out of the way
    ├── gobo-symbols
    ├── us, latin, no, level3, stdin.xkm
    ├── old-rules/               # old evdev.xml / evdev.lst / evdev.extras.xml (+ backups)
    └── us_macos_caps            # unused macOS-style variant, reference only
```

The registration snippet is kept as a **separate file** (`rules/us_no.layout.xml`) rather
than embedded in the script, so the layout metadata is editable independently of the
patch logic. The `evdev.lst` line is short and embedded in the script.

## Layout registration data

`rules/us_no.layout.xml` (the block injected under `<layoutList>` in evdev.xml):

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

`evdev.lst` line (under the `! layout` section):

```
  us_no           English (Gobokeys)
```

## Patching mechanism

Structure-aware, idempotent injection. Implemented in Python 3 (stdlib only — always
present on Arch) for the XML, driven by `install.sh`.

- **`evdev.xml`** (real XML): parse with `xml.etree.ElementTree`. Search `<layoutList>`
  for an existing `<layout>` whose `<configItem>/<name>` text equals `us_no`. If absent,
  append the snippet block and write the tree back; if present, no-op. Matching on
  structure/content (not line numbers) makes this robust to OS reformatting.
- **`evdev.lst`** (plain columnar list): ensure a line whose first token is `us_no`
  exists within the `! layout` section; insert if missing. Idempotent via exact-token
  match.
- **`evdev.extras.xml`**: not touched.

Rejected alternatives:
- **Sentinel-comment text insertion** — simpler but fragile against reformatting.
- **Shipping full patched copies to overwrite** — the brittle approach being moved away
  from; loses OS updates.

## install.sh behavior

Modes:

- **`install` (default)**:
  1. Copy `symbols/us_no` → `/usr/share/X11/xkb/symbols/us_no` (via sudo), overwriting.
  2. Back up `evdev.xml` and `evdev.lst` to `*.gobokeys.bak` (once, if no backup exists).
  3. Idempotently patch `evdev.xml` and `evdev.lst` as above.
  4. Log each action taken or skipped.
- **`--check` (dry-run)**: for each of the 3 targets (symbol file, evdev.xml entry,
  evdev.lst line) report `present` / `missing`. No writes. Exit non-zero if anything is
  missing.
- **`--activate`**: after install, run `localectl set-x11-keymap us_no`. Note: on this
  Wayland/Niri machine the compositor reads xkb settings from `locale1`, so `localectl`
  is the correct lever.

Properties:

- Idempotent / safe to re-run.
- Requires root for writes (re-invokes via sudo or instructs the user); `--check` needs
  no privileges.
- Paths to the system xkb dir are variables at the top of the script (default
  `/usr/share/X11/xkb`).

## Testing

`--check` on the live machine is the built-in acceptance test:

- Before: symbol file `present`, evdev.xml `missing`, evdev.lst `missing` (matches the
  confirmed drift).
- After `install`: a second `--check` reports all `present`.
- Re-running `install` makes no further changes (idempotency).
- `setxkbmap us_no` (or the system layout picker showing "English (Gobokeys)") confirms
  the registration is live.
