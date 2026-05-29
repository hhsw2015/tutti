#!/usr/bin/env python3
"""Inject localized <description xml:lang="..."> elements into a Sparkle appcast.

Usage:
    inject-localized-notes.py <appcast.xml> <version> <lang>=<html-file> ...

Finds the <item> whose <enclosure url=...> contains "Tutti-<version>.zip" and
adds (or replaces) a <description xml:lang="<lang>"> child holding the HTML read
from each file. The unqualified <description> (English) stays as the fallback
for every other language.
"""
import sys
import xml.etree.ElementTree as ET

XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

# Keep generated prefixes stable so the appcast stays human-diffable and tools
# expecting `sparkle:` keep working.
ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def find_item(root, version):
    needle = "Tutti-%s.zip" % version
    for item in root.iter("item"):
        enc = item.find("enclosure")
        if enc is not None and needle in enc.get("url", ""):
            return item
    return None


def inject(appcast_path, version, lang_files):
    tree = ET.parse(appcast_path)
    root = tree.getroot()
    item = find_item(root, version)
    if item is None:
        sys.exit("No <item> with enclosure for Tutti-%s.zip in %s"
                 % (version, appcast_path))
    for lang, html_path in lang_files.items():
        with open(html_path, encoding="utf-8") as f:
            html = f.read()
        node = next((d for d in item.findall("description")
                     if d.get(XML_LANG) == lang), None)
        if node is None:
            node = ET.SubElement(item, "description")
            node.set(XML_LANG, lang)
        node.text = html
    tree.write(appcast_path, encoding="UTF-8", xml_declaration=True)


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    appcast, version = argv[1], argv[2]
    lang_files = {}
    for pair in argv[3:]:
        lang, sep, path = pair.partition("=")
        if not sep or not lang or not path:
            sys.exit("Bad lang=file argument: %s" % pair)
        lang_files[lang] = path
    inject(appcast, version, lang_files)


if __name__ == "__main__":
    main(sys.argv)
