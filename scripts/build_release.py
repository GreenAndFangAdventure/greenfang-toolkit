"""Build the release zip (when not given one), addon-manifest.json and SHA256SUMS.txt.
GF-001-D16. Contract: docs/contracts/addon-manifest.md.

    python scripts/build_release.py --out dist                    # local: builds the zip itself
    python scripts/build_release.py --zip .release/X.zip --tag v0.10.0 --out dist   # CI: packager's zip

The local zip has the same layout the BigWigs packager produces from .pkgmeta:
one GreenFangToolkit/ folder with the TOC, the .lua files, LICENSE and CHANGELOG.md.
Standard library only.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ADDON = "GreenFangToolkit"
ADDON_DIR = os.path.join(ROOT, "addon", ADDON)
CONFIG = os.path.join(ROOT, "scripts", "release-config.json")
REPO = "GreenAndFangAdventure/greenfang-toolkit"
MANIFEST_SCHEMA = 1
FIXED_TIME = (2026, 1, 1, 0, 0, 0)   # zip entry times, so the same tree gives the same sha256


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def toc_fields():
    out = {}
    with open(os.path.join(ADDON_DIR, ADDON + ".toc"), encoding="utf-8-sig") as f:
        for line in f:
            m = re.match(r"##\s*([\w-]+):\s*(.*?)\s*$", line)
            if m:
                out[m.group(1)] = m.group(2)
    return out


def addon_files():
    """Files that go into the zip, as (path inside zip, path on disk)."""
    toc = os.path.join(ADDON_DIR, ADDON + ".toc")
    listed = [ADDON + ".toc"]
    with open(toc, encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                listed.append(line.replace("\\", "/"))
    files = [(ADDON + "/" + p, os.path.join(ADDON_DIR, p)) for p in listed]
    files.append((ADDON + "/LICENSE", os.path.join(ADDON_DIR, "LICENSE")))
    files.append((ADDON + "/CHANGELOG.md", os.path.join(ROOT, "CHANGELOG.md")))
    for inside, disk in files:
        if not os.path.isfile(disk):
            sys.exit("missing file for the zip: " + inside)
    return files


def build_zip(path):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for inside, disk in addon_files():
            with open(disk, "rb") as f:
                data = f.read()
            info = zipfile.ZipInfo(inside, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)


def zip_hashes(path):
    files = {}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            files[info.filename] = sha256(z.read(info))
    roots = {name.split("/")[0] for name in files}
    if roots != {ADDON}:
        sys.exit("zip must contain exactly one top folder %s/, found %s" % (ADDON, sorted(roots)))
    if ADDON + "/" + ADDON + ".toc" not in files:
        sys.exit("zip has no %s/%s.toc" % (ADDON, ADDON))
    return dict(sorted(files.items()))


def channel_of(tag):
    if not tag:
        return "dev"
    low = tag.lower()
    if "alpha" in low:
        return "alpha"
    if "beta" in low:
        return "beta"
    return "release"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", help="an existing zip (from the packager); built here when omitted")
    ap.add_argument("--tag", default=os.environ.get("GITHUB_REF_NAME") if os.environ.get("GITHUB_REF_TYPE") == "tag" else None)
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    ap.add_argument("--released", help="ISO time; default now (UTC)")
    args = ap.parse_args()

    toc = toc_fields()
    version = toc.get("Version")
    tag = args.tag or ("v" + version)
    channel = channel_of(args.tag)
    with open(CONFIG, encoding="utf-8") as f:
        config = json.load(f)
    min_sync = config.get("minGFSync")
    if channel == "release" and not min_sync:
        sys.exit("scripts/release-config.json: minGFSync must be set before a release (rollout order site -> GF Sync -> AddOn)")

    os.makedirs(args.out, exist_ok=True)
    name = "%s-%s.zip" % (ADDON, version)
    target = os.path.join(args.out, name)
    if args.zip:
        if os.path.abspath(args.zip) != os.path.abspath(target):
            shutil.copyfile(args.zip, target)
    else:
        build_zip(target)
    with open(target, "rb") as f:
        data = f.read()
    digest = sha256(data)
    files = zip_hashes(target)

    released = args.released or datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    project_id = toc.get("X-Curse-Project-ID")
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "addon": ADDON,
        "displayName": toc.get("Title", ADDON),
        "version": version,
        "tag": tag,
        "channel": channel,
        "interface": int(toc.get("Interface", "0")),
        "released": released,
        "url": "https://github.com/%s/releases/download/%s/%s" % (REPO, tag, name),
        "sha256": digest,
        "size": len(data),
        "minGFSync": min_sync,
        "savedVariablesSchema": config.get("savedVariablesSchema"),
        "changelog": "https://github.com/%s/releases/tag/%s" % (REPO, tag),
        "curseforge": {"projectId": int(project_id)} if project_id and project_id.isdigit() else None,
        "files": files,
    }
    with open(os.path.join(args.out, "addon-manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    with open(os.path.join(args.out, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("%s  %s\n" % (digest, name))
    # Release notes for the GitHub Release: this version's CHANGELOG section.
    with open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"^##\s+%s\b.*?(?=^##\s|\Z)" % re.escape(version), text, re.M | re.S)
    notes = (m.group(0).strip() if m else "## " + version) + "\n\nSHA-256：`%s`\n" % digest
    with open(os.path.join(args.out, "RELEASE_NOTES.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(notes)
    print("built %s (%d bytes, sha256 %s, %d files, channel %s)" % (name, len(data), digest, len(files), channel))
    return 0


if __name__ == "__main__":
    sys.exit(main())
