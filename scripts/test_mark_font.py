"""The sidebar wordmark font must stay a two-glyph cut. A full LXGW WenKai is 25.8 MB, and an unrenamed copy breaks
the OFL's Reserved Font Names. Parsed by hand so CI needs no fontTools.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARK = ROOT / "Resources/Fonts/MiaoYanMark.ttf"
RESERVED = ("LXGW", "霞鹜", "霞鶩", "落霞孤鹜", "落霞孤鶩", "WenKai")


def tables(data):
    count = struct.unpack(">H", data[4:6])[0]
    out = {}
    for i in range(count):
        tag, _, offset, length = struct.unpack(">4sIII", data[12 + 16 * i : 28 + 16 * i])
        out[tag.decode("latin-1")] = data[offset : offset + length]
    return out


def mapped_code_points(cmap):
    points = set()
    count = struct.unpack(">H", cmap[2:4])[0]
    for i in range(count):
        offset = struct.unpack(">I", cmap[8 + 8 * i : 12 + 8 * i])[0]
        sub = cmap[offset:]
        fmt = struct.unpack(">H", sub[:2])[0]
        if fmt == 4:
            segs = struct.unpack(">H", sub[6:8])[0] // 2
            ends = struct.unpack(f">{segs}H", sub[14 : 14 + 2 * segs])
            starts = struct.unpack(f">{segs}H", sub[16 + 2 * segs : 16 + 4 * segs])
            for start, end in zip(starts, ends):
                if start != 0xFFFF:
                    points.update(range(start, end + 1))
        elif fmt == 12:
            groups = struct.unpack(">I", sub[12:16])[0]
            for g in range(groups):
                start, end, _ = struct.unpack(">III", sub[16 + 12 * g : 28 + 12 * g])
                points.update(range(start, end + 1))
    return points


def names(name):
    count, string_offset = struct.unpack(">HH", name[2:6])
    out = {}
    for i in range(count):
        platform, _, _, name_id, length, offset = struct.unpack(">6H", name[6 + 12 * i : 18 + 12 * i])
        raw = name[string_offset + offset : string_offset + offset + length]
        out.setdefault(name_id, []).append(raw.decode("utf-16-be" if platform in (0, 3) else "latin-1"))
    return out


class MarkFontGateTests(unittest.TestCase):
    def setUp(self):
        self.data = MARK.read_bytes()
        self.tables = tables(self.data)

    def test_it_stays_a_two_glyph_cut(self):
        self.assertLess(len(self.data), 8 * 1024, "MiaoYanMark.ttf grew past 8 KB; cut it to 妙言 again")
        self.assertEqual(struct.unpack(">H", self.tables["maxp"][4:6])[0], 3, ".notdef, 妙 and 言 only")
        self.assertEqual(mapped_code_points(self.tables["cmap"]), {ord("妙"), ord("言")})

    def test_it_is_renamed_and_keeps_its_licence(self):
        records = names(self.tables["name"])
        for name_id in (1, 3, 4, 6, 16):
            for value in records.get(name_id, []):
                self.assertFalse(any(word in value for word in RESERVED), f"name ID {name_id} keeps {value!r}")
        self.assertTrue(any("LXGW" in value for value in records[0]), "the copyright record stays")
        self.assertTrue(any("Open Font License" in value for value in records[13]), "the licence record stays")


if __name__ == "__main__":
    unittest.main()
