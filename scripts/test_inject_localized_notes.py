import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

SCRIPT = os.path.join(os.path.dirname(__file__), "inject-localized-notes.py")
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <item>
      <title>0.2.3</title>
      <sparkle:version>5</sparkle:version>
      <description><![CDATA[<p>English 0.2.3</p>]]></description>
      <enclosure url="https://example.com/Tutti-0.2.3.zip" sparkle:edSignature="a" length="1"/>
    </item>
    <item>
      <title>0.3.2</title>
      <sparkle:version>6</sparkle:version>
      <description><![CDATA[<p>English 0.3.2</p>]]></description>
      <enclosure url="https://example.com/Tutti-0.3.2.zip" sparkle:edSignature="b" length="2"/>
    </item>
  </channel>
</rss>
"""


def descriptions(item):
    return item.findall("description")


def item_for(root, title):
    for it in root.iter("item"):
        if it.findtext("title") == title:
            return it
    return None


class InjectTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.appcast = os.path.join(self.dir, "appcast.xml")
        with open(self.appcast, "w", encoding="utf-8") as f:
            f.write(FIXTURE)
        self.zh_hans = os.path.join(self.dir, "zh-Hans.html")
        with open(self.zh_hans, "w", encoding="utf-8") as f:
            f.write("<p>简体说明</p>")

    def run_inject(self, *args):
        return subprocess.run(
            [sys.executable, SCRIPT, self.appcast, *args],
            capture_output=True, text=True,
        )

    def test_injects_localized_description_into_matching_item(self):
        r = self.run_inject("0.3.2", f"zh-Hans={self.zh_hans}")
        self.assertEqual(r.returncode, 0, r.stderr)
        root = ET.parse(self.appcast).getroot()
        target = item_for(root, "0.3.2")
        langs = {d.get(XML_LANG): d.text for d in descriptions(target)}
        self.assertIn(None, langs)                      # English fallback kept
        self.assertIn("zh-Hans", langs)                 # localized added
        self.assertIn("简体说明", langs["zh-Hans"])

    def test_does_not_touch_other_items(self):
        self.run_inject("0.3.2", f"zh-Hans={self.zh_hans}")
        root = ET.parse(self.appcast).getroot()
        other = item_for(root, "0.2.3")
        self.assertEqual(len(descriptions(other)), 1)
        self.assertIsNone(descriptions(other)[0].get(XML_LANG))

    def test_idempotent(self):
        self.run_inject("0.3.2", f"zh-Hans={self.zh_hans}")
        self.run_inject("0.3.2", f"zh-Hans={self.zh_hans}")
        root = ET.parse(self.appcast).getroot()
        target = item_for(root, "0.3.2")
        zh = [d for d in descriptions(target) if d.get(XML_LANG) == "zh-Hans"]
        self.assertEqual(len(zh), 1)

    def test_preserves_sparkle_prefix(self):
        self.run_inject("0.3.2", f"zh-Hans={self.zh_hans}")
        with open(self.appcast, encoding="utf-8") as f:
            text = f.read()
        self.assertIn("sparkle:version", text)
        self.assertNotIn("ns0:", text)

    def test_missing_version_fails(self):
        r = self.run_inject("9.9.9", f"zh-Hans={self.zh_hans}")
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
