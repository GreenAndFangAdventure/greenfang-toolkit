"""Build the 找物品 item catalog (GF-009-12): addon/GreenFangToolkit/SupplyCatalogData.lua.

One data file in the main AddOn: ItemID, zhTW name, item class / subclass and
the native icon number of every tradeable item the 調貨所 can list, packed as
one long string per item class. SupplyCatalog.lua decodes it the first time
找物品 → 全部 opens. Item details and whether an item may be listed are still
asked from the Forever client.

    python -I scripts/build_item_catalog.py --item Item.csv --sparse ItemSparse.zhTW.csv \
        --build 1.60.1.71139 [--scan GreenFangToolkit.lua] [--source TEXT] [--out FILE] [--missing FILE]
    python -I scripts/build_item_catalog.py --selftest

Inputs: DB2 table exports (CSV with a header row) for one Forever client build:
    Item.csv              ID, ClassID, SubclassID, IconFileDataID
    ItemSparse.zhTW.csv   ID, Display_lang (zhTW), Bonding, OverallQualityID, ItemLevel
    --scan (optional)     the owner's GreenFangToolkit_Dev SavedVariables file
                          (GreenFangToolkit_Dev.lua) after /gftkdev catalogscan:
                          GreenFangToolkitDevDB.catalogScan / .catalogSample .got =
                          { [ItemID] = { name, classID, subclassID, bindType, quality,
                          itemLevel, icon } } (the game client's own answers for IDs
                          the export has no name for). Only those tables are read;
                          each run's locale must be zhTW and its client build --build.
Only these columns are read. The exports and the SavedVariables file are never
committed.

Included (everything else is left out):
    Bonding 1 (bind on pickup), 4 (quest item) and 5: never (cannot be traded).
    Weapons / armour (ClassID 2, 4): quality 2-5 and item level >= 5 (no grey or
    white gear).
    Other classes: quality >= 1, or quality 0 for trade goods / reagents / quest.
    Names without any CJK character (OLD / Deprecated placeholders, untranslated
    names) are left out.
GF-009-13: the scan list (every Item row with no name: no ItemSparse row, or a
name without CJK) and a ~20 ID sample go to the dev-only AddOn
addon/GreenFangToolkit_Dev/CatalogScanData.lua (--dev-out), never into the
guild release.

Data source and terms: the item names, classes and icon file IDs are Blizzard
Entertainment's game data, read from the Forever client's DB2 tables Item and
ItemSparse (zhTW) as exported by wago.tools (https://wago.tools/db2), build
1.60.1.71139. They are Blizzard's, not ours: the AddOn's MIT licence covers our
code, not this data. It is shipped only inside the free AddOn, so that the
AddOn can find items by name, as AddOns commonly embed game data under
Blizzard's UI Add-On Development Policy (free of charge, readable code).
wago.tools is a third-party mirror and is not affiliated with Blizzard. See
docs/research/GF-009-13-catalog-source.md.

Update: export Item and ItemSparse (zhTW) again for the new Forever build, rerun
with --build (and --scan once the owner has scanned), commit
SupplyCatalogData.lua and the missing list, and run tests/addon/run_lupa.py.
The file header records the build, source and counts. Standard library only.
"""
import argparse
import csv
import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DEFAULT_OUT = os.path.join(ROOT, "addon", "GreenFangToolkit", "SupplyCatalogData.lua")
DEFAULT_DEV_OUT = os.path.join(ROOT, "addon", "GreenFangToolkit_Dev", "CatalogScanData.lua")
DEFAULT_MISSING = os.path.join(ROOT, "docs", "research", "GF-009-12-catalog-missing.tsv")
NO_TRADE = {1, 4, 5}
GEAR = {2, 4}
LOW_OK = {5, 7, 12}     # quality 0 still kept for these classes
SCHEMA = 2
B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
TERMS = ("Blizzard Entertainment game data (Item, ItemSparse DB2), not covered by the AddOn's MIT licence; "
         "shipped only inside the free AddOn. See docs/research/GF-009-13-catalog-source.md.")
SAMPLE_KNOWN = (2841, 7975, 289334)   # 青銅錠, 設計圖：秘銀短褲, a Forever item
SAMPLE_INVALID = (98765432, 99999999)  # no such item


def _int(v, default=None):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return default


def _rows(text):
    for row in csv.DictReader(io.StringIO(text)):
        yield {(k or "").strip(): v for k, v in row.items()}


def has_cjk(s):
    return any("㐀" <= ch <= "鿿" or "豈" <= ch <= "﫿" for ch in s)


def keep(cls, bonding, quality, level):
    """None when the item goes into the catalog, else why not."""
    if bonding in NO_TRADE:
        return "no_trade"
    if cls in GEAR:
        return None if 2 <= quality <= 5 and level >= 5 else "filtered"
    return None if quality >= 1 or cls in LOW_OK else "filtered"


# --------------------------------------------------------------------------
# A small reader for Lua table literals (the SavedVariables file).
# --------------------------------------------------------------------------

_TOKEN = re.compile(r'''\s*(?:(--\[\[.*?\]\])|(--[^\n]*)|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|([A-Za-z_][A-Za-z0-9_]*)|(\S))''', re.S)
_ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\n": "\n"}


def _unquote(s):
    out, i, body = [], 0, s[1:-1]
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 1 < len(body):
            nx = body[i + 1]
            if nx.isdigit():
                m = re.match(r"\d{1,3}", body[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + len(m.group(0))
                continue
            out.append(_ESC.get(nx, nx))
            i += 2
            continue
        out.append(ch)
        i += 1
    raw = "".join(out)
    try:
        return raw.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return raw


def _tokens(text):
    for m in _TOKEN.finditer(text):
        if m.group(1) or m.group(2):
            continue
        if m.group(3) is not None:
            yield ("str", m.group(3))
        elif m.group(4) is not None:
            yield ("num", m.group(4))
        elif m.group(5) is not None:
            yield ("name", m.group(5))
        elif m.group(6) is not None:
            yield ("sym", m.group(6))


class _Parser:
    def __init__(self, text):
        self.t = list(_tokens(text))
        self.i = 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def value(self):
        kind, v = self.take()
        if kind == "str":
            return _unquote(v)
        if kind == "num":
            return float(v) if any(c in v for c in ".eE") else int(v)
        if kind == "name":
            return {"true": True, "false": False, "nil": None}.get(v, v)
        if kind == "sym" and v == "{":
            return self.table()
        raise ValueError("unexpected %r" % (v,))

    def table(self):
        out, n = {}, 1
        while True:
            kind, v = self.peek()
            if kind is None:
                raise ValueError("unterminated table")
            if kind == "sym" and v == "}":
                self.take()
                return out
            if kind == "sym" and v in ",;":
                self.take()
                continue
            if kind == "sym" and v == "[":
                self.take()
                key = self.value()
                assert self.take() == ("sym", "]")
                assert self.take() == ("sym", "=")
                out[key] = self.value()
            elif kind == "name" and self.peek(1) == ("sym", "="):
                self.take()
                self.take()
                out[v] = self.value()
            else:
                out[n] = self.value()
                n += 1


SCAN_RUNS = ("catalogScan", "catalogSample")


def read_scan(text):
    """({ItemID: (name, classID, subclassID, bind, quality, ilvl, icon)}, [run meta]) from
    the GreenFangToolkit_Dev SavedVariables file (GreenFangToolkitDevDB)."""
    m = re.search(r"^\s*GreenFangToolkitDevDB\s*=\s*", text, re.M)
    if not m:
        raise ValueError("no GreenFangToolkitDevDB in the file")
    p = _Parser(text[m.end():])
    assert p.take() == ("sym", "{")
    db = p.table()
    out, runs = {}, []
    for key in SCAN_RUNS:
        scan = db.get(key)
        if not isinstance(scan, dict):
            continue
        runs.append({"run": key, "locale": scan.get("locale"), "build": scan.get("build"),
                     "list": scan.get("list"), "done": scan.get("finished")})
        for k, rec in (scan.get("got") or {}).items():
            if not isinstance(k, int) or not isinstance(rec, dict):
                continue
            name = rec.get(1)
            if not isinstance(name, str) or not name:
                continue
            vals = [rec.get(i) for i in range(2, 8)]
            if not all(isinstance(x, int) for x in vals):
                continue
            out[k] = (name,) + tuple(vals)
    return out, runs


def check_runs(runs, build):
    """None when every run was made by a zhTW client of this build, else why not."""
    if not runs:
        return "no catalogScan / catalogSample run in the file"
    for r in runs:
        if r["locale"] != "zhTW":
            return "%s: locale %s, not zhTW" % (r["run"], r["locale"])
        if r["build"] != build or r["list"] not in (None, build):
            return "%s: client build %s (list %s), not %s" % (r["run"], r["build"], r["list"], build)
    return None


# --------------------------------------------------------------------------

def select(item_csv, sparse_csv, scanned=None):
    """(entries, missing, scan_ids, stats). entries: [(id, name, classID, subclassID, icon)]."""
    scanned = scanned or {}
    sparse = {}
    for row in _rows(sparse_csv):
        i = _int(row.get("ID"))
        if i is None:
            continue
        sparse[i] = ((row.get("Display_lang") or "").strip(), _int(row.get("Bonding"), 0),
                     _int(row.get("OverallQualityID"), 0), _int(row.get("ItemLevel"), 0))
    entries, missing, scan_ids = [], [], []
    stats = {"item_rows": 0, "sparse_rows": len(sparse), "no_sparse": 0, "no_trade": 0, "filtered": 0,
             "missing_name": 0, "missing_icon": 0, "from_scan": 0, "scanned": len(scanned), "included": 0}
    for row in _rows(item_csv):
        i = _int(row.get("ID"))
        cls, sub = _int(row.get("ClassID")), _int(row.get("SubclassID"), 0)
        if i is None or cls is None:
            continue
        stats["item_rows"] += 1
        icon = _int(row.get("IconFileDataID"), 0) or 0
        s = sparse.get(i)
        named = s is not None and bool(s[0]) and has_cjk(s[0])
        from_scan = False
        if not named:
            # Scan only what could still get in: no ItemSparse row, or a
            # tradeable row whose name has no CJK.
            if s is None or keep(cls, s[1], s[2], s[3]) is None:
                scan_ids.append(i)
            sc = scanned.get(i)
            if sc and has_cjk(sc[0]):
                name, cls, sub, bonding, quality, level = sc[0], sc[1], sc[2], sc[3], sc[4], sc[5]
                icon = sc[6] or icon
                from_scan = True
            elif s is None:
                stats["no_sparse"] += 1
                continue
            else:
                name, bonding, quality, level = s
        else:
            name, bonding, quality, level = s
        why = keep(cls, bonding, quality, level)
        if why:
            stats[why] += 1
            continue
        if not name or not has_cjk(name):
            stats["missing_name"] += 1
            missing.append((i, cls, "name"))
            continue
        if icon <= 0:
            stats["missing_icon"] += 1
            icon = 0
        if from_scan:
            stats["from_scan"] += 1
        entries.append((i, name, cls, sub, icon))
    entries.sort(key=lambda e: (e[2], e[3], e[1].encode("utf-8"), e[0]))
    stats["included"] = len(entries)
    stats["scan_list"] = len(scan_ids)
    return entries, sorted(missing), sorted(set(scan_ids)), stats


def b36(n):
    if n == 0:
        return "0"
    out = ""
    while n:
        n, r = divmod(n, 36)
        out = B36[r] + out
    return out


def pack_ids(ids):
    """Sorted IDs as base-36 gaps joined by commas (decoded by SupplyCatalog.lua)."""
    out, last = [], 0
    for i in ids:
        out.append(b36(i - last))
        last = i
    return ",".join(out)


def long_string(body):
    level = 0
    while ("]" + "=" * level + "]") in body:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + body + "]" + eq + "]"


def clean(name):
    return name.replace("\t", " ").replace("\r", " ").replace("\n", " ")


def render_data(entries, build, source, locale="zhTW"):
    groups = {}
    for e in entries:
        groups.setdefault(e[2], []).append(e)
    by_class = " ".join("%d:%d" % (c, len(groups[c])) for c in sorted(groups))
    out = [
        "-- SupplyCatalogData (GF-009-12): the 找物品 item catalog. Written by",
        "-- scripts/build_item_catalog.py; do not edit by hand.",
        "-- Forever client build %s, locale %s, source: %s." % (build, locale, source),
        "-- Terms: %s" % TERMS,
        "-- %d items; by ClassID %s." % (len(entries), by_class),
        "-- groups[ClassID]: one record per line, ItemID<TAB>SubclassID<TAB>icon file ID (0 = none)<TAB>zhTW name.",
        "-- Decoded by SupplyCatalog.lua the first time 找物品 → 全部 opens; item details and",
        "-- whether an item may be listed come from the game client.",
        "local _, ns = ...",
        "ns.SupplyCatalogData = {",
        "  v = %d," % SCHEMA,
        '  build = "%s",' % build,
        '  locale = "%s",' % locale,
        "  n = %d," % len(entries),
        "  groups = {",
    ]
    for c in sorted(groups):
        body = "".join("%d\t%d\t%d\t%s\n" % (e[0], e[3], e[4], clean(e[1])) for e in groups[c])
        out.append("    [%d] = %s," % (c, long_string(body)))
    out += ["  },", "}", ""]
    return "\n".join(out)


def pick_sample(entries, scan_ids):
    """About 20 IDs for the owner's first check: known catalog items, a spread of
    the scan list, and IDs that do not exist."""
    have = {e[0] for e in entries}
    known = [i for i in SAMPLE_KNOWN if i in have]
    ids = sorted(have)
    for k in (1, 2, 3):
        if len(known) >= 6 or not ids:
            break
        i = ids[len(ids) * k // 4]
        if i not in known:
            known.append(i)
    spread = []
    if scan_ids:
        step = max(1, len(scan_ids) // 12)
        spread = scan_ids[::step][:12]
    return sorted(set(known) | set(spread) | set(SAMPLE_INVALID))


def render_dev(scan_ids, sample_ids, build, locale="zhTW"):
    return "\n".join([
        "-- CatalogScanData (GF-009-13): the dev-only scan list for /gftkdev catalogscan.",
        "-- Written by scripts/build_item_catalog.py; do not edit by hand. Not in the guild release.",
        "-- Forever client build %s, locale %s. scan: %d IDs with no name in the export;" % (build, locale, len(scan_ids)),
        "-- sample: %d IDs (catalog items, part of the scan list, IDs that do not exist). Base-36 gaps." % len(sample_ids),
        "local _, D = ...",
        "D.scanData = {",
        '  build = "%s",' % build,
        '  locale = "%s",' % locale,
        '  scan = "%s",' % pack_ids(scan_ids),
        '  sample = "%s",' % pack_ids(sample_ids),
        "}", ""])


def render_missing(missing, build):
    out = ["# GF-009-12 catalog: tradeable items left out, build %s. ItemID, ClassID, reason." % build,
           "# name = no zhTW name in the export or the scan (OLD / Deprecated placeholders or untranslated)."]
    out += ["%d\t%d\t%s" % m for m in missing]
    return "\n".join(out) + "\n"


def selftest():
    item = ("ID,ClassID,SubclassID,IconFileDataID\n"
            "1,7,7,100\n2,9,2,200\n3,4,1,300\n4,4,1,301\n5,12,0,0\n6,2,15,302\n7,15,0,303\n8,9,1,304\n"
            "9,0,0,305\n10,4,2,306\n11,7,5,307\n12,9,4,0\n13,4,1,0\n")
    sparse = ("ID,Description_lang,Display_lang,Bonding,OverallQualityID,ItemLevel\n"
              '1,x,銅錠,0,1,10\n2,x,"設計圖：""秘銀""短褲]]",0,2,42\n3,x,綠甲,2,2,20\n4,x,拾綁甲,1,3,55\n'
              "5,x,任務物,4,1,1\n6,x,灰刀,0,0,30\n7,x,OLDThing,0,1,1\n8,x,拾綁圖,1,2,40\n"
              "9,x,藥水,0,1,5\n10,x,紫甲,2,4,60\n")
    entries, missing, scan_ids, stats = select(item, sparse)
    ids = [e[0] for e in entries]
    assert sorted(ids) == [1, 2, 3, 9, 10], ids
    assert missing == [(7, 15, "name")], missing
    assert scan_ids == [7, 11, 12, 13], scan_ids  # 7: OLD name; 11-13: no ItemSparse row
    assert stats["no_sparse"] == 3 and stats["no_trade"] == 3 and stats["filtered"] == 1, stats
    text = render_data(entries, "test", "selftest")
    assert '設計圖："秘銀"短褲]]' in text and "[=[" in text and "OLDThing" not in text
    assert "scan" not in text.split("ns.SupplyCatalogData")[1] and "Blizzard" in text
    dev = render_dev(scan_ids, pick_sample(entries, scan_ids), "test")
    assert 'scan = "7,4,1,1"' in dev, dev
    assert "sample = " in dev
    # The scan fills 11 (material, an escaped name) and 12 (recipe); 13 is white gear (left out).
    sv = ('GreenFangToolkitDevDB = {\n["catalogScan"] = {\n["locale"] = "zhTW",\n["build"] = "test",\n["list"] = "test",\n["got"] = {\n'
          '[11] = {\n"\\233\\138\\133\\231\\159\\179", -- [1]\n7, -- [2]\n5, -- [3]\n0, -- [4]\n1, -- [5]\n10, -- [6]\n555, -- [7]\n},\n'
          '[12] = {"圖樣：測試", 9, 4, 0, 2, 30, 0},\n[13] = {"白甲", 4, 1, 2, 1, 20, 1},\n'
          '[99] = {"沒有這列", 7, 5, 0, 1, 1, 1},\n},\n},\n["other"] = { a = 1, "x" },\n}\n')
    scanned, runs = read_scan(sv)
    assert scanned[11] == ("銅石", 7, 5, 0, 1, 10, 555), scanned[11]
    assert check_runs(runs, "test") is None, runs
    assert check_runs(runs, "1.60.1.71139") is not None
    assert check_runs([dict(runs[0], locale="enUS")], "test") is not None
    assert check_runs([], "test") is not None
    entries, missing, scan_ids, stats = select(item, sparse, scanned)
    ids = sorted(e[0] for e in entries)
    assert ids == [1, 2, 3, 9, 10, 11, 12], ids
    assert stats["from_scan"] == 2 and stats["filtered"] == 2, stats
    assert [e for e in entries if e[0] == 11][0] == (11, "銅石", 7, 5, 555)
    print("selftest ok:", stats)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--item")
    ap.add_argument("--sparse")
    ap.add_argument("--build")
    ap.add_argument("--scan")
    ap.add_argument("--source", default="wago.tools DB2 CSV export (Item, ItemSparse zhTW)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--missing", default=DEFAULT_MISSING)
    ap.add_argument("--dev-out", default=DEFAULT_DEV_OUT)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if not (a.item and a.sparse and a.build):
        ap.error("--item, --sparse and --build are required")
    with open(a.item, encoding="utf-8-sig", newline="") as f:
        item_text = f.read()
    with open(a.sparse, encoding="utf-8-sig", newline="") as f:
        sparse_text = f.read()
    scanned, source = {}, a.source
    if a.scan:
        with open(a.scan, encoding="utf-8-sig", errors="replace") as f:
            scanned, runs = read_scan(f.read())
        problem = check_runs(runs, a.build)
        if problem:
            sys.exit("scan not used: " + problem)
        source += "; names for %d IDs from the owner's client (/gftkdev catalogscan)" % len(scanned)
    entries, missing, scan_ids, stats = select(item_text, sparse_text, scanned)
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(render_data(entries, a.build, source))
    os.makedirs(os.path.dirname(a.dev_out), exist_ok=True)
    with open(a.dev_out, "w", encoding="utf-8", newline="\n") as f:
        f.write(render_dev(scan_ids, pick_sample(entries, scan_ids), a.build))
    os.makedirs(os.path.dirname(a.missing), exist_ok=True)
    with open(a.missing, "w", encoding="utf-8", newline="\n") as f:
        f.write(render_missing(missing, a.build))
    by_class = {}
    for e in entries:
        by_class[e[2]] = by_class.get(e[2], 0) + 1
    stats["by_class"] = dict(sorted(by_class.items()))
    stats["data_bytes"] = os.path.getsize(a.out)
    print("wrote", a.out, stats)
    return 0


if __name__ == "__main__":
    sys.exit(main())
