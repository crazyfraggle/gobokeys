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
