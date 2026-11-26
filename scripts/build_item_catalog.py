"""Build the 找物品 item catalog (GF-009-12): addon/GreenFangToolkit_Catalog/.

A LoadOnDemand AddOn with one data file: ItemID, zhTW name, item class /
subclass and the native icon number, for every tradeable item the 調貨所 can
list. The main AddOn loads it only when 找物品 → 全部 opens. Item details and
whether an item may be listed are still asked from the Forever client.

    python -I scripts/build_item_catalog.py --item Item.csv --sparse ItemSparse.zhTW.csv \
        --build 1.60.1.71139 [--source TEXT] [--out-dir DIR] [--missing FILE]
    python -I scripts/build_item_catalog.py --selftest

Inputs: DB2 table exports (CSV with a header row) for one Forever client build:
    Item.csv              ID, ClassID, SubclassID, IconFileDataID
    ItemSparse.zhTW.csv   ID, Display_lang (zhTW), Bonding, OverallQualityID, ItemLevel
Only these columns are read. The exports themselves are never committed.

Included (everything else is left out):
    Bonding 1 (bind on pickup), 4 (quest item) and 5: never (cannot be traded).
    Weapons / armour (ClassID 2, 4): quality 2-5 and item level >= 5.
    Other classes: quality >= 1, or quality 0 for trade goods / reagents / quest.
    Names without any CJK character (OLD / Deprecated placeholders, untranslated
    names) go to the missing list (ItemID, ClassID and reason only), not into
    the catalog; once a zhTW name exists a rebuild adds them.

Update: export Item and ItemSparse (zhTW) again for the new Forever build, rerun
with --build, commit the two generated catalog files and the missing list, and
run tests/addon/run_lupa.py. The header of CatalogData.lua records the build,
source and counts. Standard library only.
"""
import argparse
import csv
import io
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ADDON = "GreenFangToolkit_Catalog"
DEFAULT_DIR = os.path.join(ROOT, "addon", ADDON)
DEFAULT_MISSING = os.path.join(ROOT, "docs", "research", "GF-009-12-catalog-missing.tsv")
INTERFACE = "16001"
GLOBAL = "GreenFangToolkit_CatalogData"
NO_TRADE = {1, 4, 5}
GEAR = {2, 4}
LOW_OK = {5, 7, 12}     # quality 0 still kept for these classes
SCHEMA = 1


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


def select(item_csv, sparse_csv):
    """(entries, missing, stats). entries: [(id, name, classID, subclassID, icon)]."""
    sparse = {}
    for row in _rows(sparse_csv):
        i = _int(row.get("ID"))
        if i is None:
            continue
        sparse[i] = ((row.get("Display_lang") or "").strip(), _int(row.get("Bonding"), 0),
                     _int(row.get("OverallQualityID"), 0), _int(row.get("ItemLevel"), 0))
    entries, missing = [], []
    stats = {"item_rows": 0, "sparse_rows": len(sparse), "no_sparse": 0, "no_trade": 0, "filtered": 0,
             "missing_name": 0, "missing_icon": 0, "included": 0}
    for row in _rows(item_csv):
        i = _int(row.get("ID"))
        cls, sub = _int(row.get("ClassID")), _int(row.get("SubclassID"), 0)
        if i is None or cls is None:
            continue
        stats["item_rows"] += 1
        s = sparse.get(i)
        if s is None:
            stats["no_sparse"] += 1
            continue
        name, bonding, quality, level = s
        if bonding in NO_TRADE:
            stats["no_trade"] += 1
            continue
        if cls in GEAR:
            keep = 2 <= quality <= 5 and level >= 5
        else:
            keep = quality >= 1 or cls in LOW_OK
        if not keep:
            stats["filtered"] += 1
            continue
        if not name or not has_cjk(name):
            stats["missing_name"] += 1
            missing.append((i, cls, "name"))
            continue
        icon = _int(row.get("IconFileDataID"), 0) or 0
        if icon <= 0:
            stats["missing_icon"] += 1
            icon = 0
        entries.append((i, name, cls, sub, icon))
    entries.sort(key=lambda e: (e[2], e[3], e[1].encode("utf-8"), e[0]))
    stats["included"] = len(entries)
    return entries, sorted(missing), stats


def lua_string(s):
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            continue
        elif ord(ch) < 32:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def _numbers(values, per=20):
    return ["    " + ",".join(str(v) for v in values[k:k + per]) + "," for k in range(0, len(values), per)]


def render_data(entries, build, source, locale="zhTW"):
    counts = {}
    for e in entries:
        counts[e[2]] = counts.get(e[2], 0) + 1
    by_class = " ".join("%d:%d" % (c, counts[c]) for c in sorted(counts))
    out = [
        "-- GreenFangToolkit_Catalog (GF-009-12): the 找物品 item catalog. Written by",
        "-- scripts/build_item_catalog.py; do not edit by hand.",
        "-- Forever client build %s, locale %s, source: %s." % (build, locale, source),
        "-- %d items; by ClassID %s." % (len(entries), by_class),
        "-- Fields: ItemID, zhTW name, ClassID*100+SubclassID, icon file ID (0 = none).",
        "-- Item details and whether an item may be listed come from the game client.",
        "%s = {" % GLOBAL,
        "  v = %d," % SCHEMA,
        "  build = %s," % lua_string(build),
        "  locale = %s," % lua_string(locale),
        "  n = %d," % len(entries),
        "  id = {",
    ]
    out += _numbers([e[0] for e in entries])
    out += ["  },", "  kind = {"]
    out += _numbers([e[2] * 100 + e[3] for e in entries])
    out += ["  },", "  icon = {"]
    out += _numbers([e[4] for e in entries])
    out += ["  },", "  name = {"]
    line = []
    for e in entries:
        line.append(lua_string(e[1]))
        if len(line) == 10:
            out.append("    " + ",".join(line) + ",")
            line = []
    if line:
        out.append("    " + ",".join(line) + ",")
    out += ["  },", "}", ""]
    return "\n".join(out)


def render_toc(build, n):
    return "\n".join([
        "## Interface: %s" % INTERFACE,
        "## Title: 綠皮冒險工具箱｜物品目錄",
        "## Notes: 調貨所「找物品」用的物品目錄（隨選載入）",
        "## Author: 綠皮與獠牙冒險事務所",
        "## LoadOnDemand: 1",
        "## Dependencies: GreenFangToolkit",
        "## X-Catalog-Build: %s" % build,
        "## X-Catalog-Items: %d" % n,
        "## X-License: MIT",
        "",
        "CatalogData.lua",
        "",
    ])


def render_missing(missing, build):
    out = ["# GF-009-12 catalog: tradeable items left out, build %s. ItemID, ClassID, reason." % build,
           "# name = no zhTW name in the export (OLD / Deprecated placeholders or untranslated)."]
    out += ["%d\t%d\t%s" % m for m in missing]
    return "\n".join(out) + "\n"


def selftest():
    item = ("ID,ClassID,SubclassID,IconFileDataID\n"
            "1,7,7,100\n2,9,2,200\n3,4,1,300\n4,4,1,301\n5,12,0,0\n6,2,15,302\n7,15,0,303\n8,9,1,304\n"
            "9,0,0,305\n10,4,2,306\n11,7,5,307\n")
    sparse = ("ID,Description_lang,Display_lang,Bonding,OverallQualityID,ItemLevel\n"
              '1,x,銅錠,0,1,10\n2,x,"設計圖：""秘銀""短褲",0,2,42\n3,x,綠甲,2,2,20\n4,x,拾綁甲,1,3,55\n'
              "5,x,任務物,4,1,1\n6,x,灰刀,0,0,30\n7,x,OLDThing,0,1,1\n8,x,拾綁圖,1,2,40\n"
              "9,x,藥水,0,1,5\n10,x,紫甲,2,4,60\n")
    entries, missing, stats = select(item, sparse)
    ids = [e[0] for e in entries]
    assert sorted(ids) == [1, 2, 3, 9, 10], ids
    assert missing == [(7, 15, "name")], missing
    assert stats["no_sparse"] == 1 and stats["no_trade"] == 3 and stats["filtered"] == 1, stats
    text = render_data(entries, "test", "selftest")
    assert '"設計圖：\\"秘銀\\"短褲"' in text and "OLDThing" not in text and "x," not in text
    assert render_toc("test", 5).count("## LoadOnDemand: 1") == 1
    print("selftest ok:", stats)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--item")
    ap.add_argument("--sparse")
    ap.add_argument("--build")
    ap.add_argument("--source", default="wago.tools DB2 CSV export (Item, ItemSparse zhTW)")
    ap.add_argument("--out-dir", default=DEFAULT_DIR)
    ap.add_argument("--missing", default=DEFAULT_MISSING)
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
    entries, missing, stats = select(item_text, sparse_text)
    os.makedirs(a.out_dir, exist_ok=True)
    data_path = os.path.join(a.out_dir, "CatalogData.lua")
    with open(data_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(render_data(entries, a.build, a.source))
    with open(os.path.join(a.out_dir, ADDON + ".toc"), "w", encoding="utf-8", newline="\n") as f:
        f.write(render_toc(a.build, len(entries)))
    os.makedirs(os.path.dirname(a.missing), exist_ok=True)
    with open(a.missing, "w", encoding="utf-8", newline="\n") as f:
        f.write(render_missing(missing, a.build))
    by_class = {}
    for e in entries:
        by_class[e[2]] = by_class.get(e[2], 0) + 1
    stats["by_class"] = dict(sorted(by_class.items()))
    stats["data_bytes"] = os.path.getsize(data_path)
    print("wrote", data_path, stats)
    return 0


if __name__ == "__main__":
    sys.exit(main())
