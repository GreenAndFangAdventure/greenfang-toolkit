"""Release checks for GreenFangToolkit (GF-001-D16).

    python scripts/release_checks.py version [--tag v0.10.0]
        The TOC "## Version:" must be a plain version, CHANGELOG.md must have a
        "## <version>" heading, and the tag (if given, or GITHUB_REF_NAME on a
        tag build) must be "v<version>" or "v<version>-<suffix>".

    python scripts/release_checks.py scan [--root DIR] [--report FILE]
        Leak scan of every file under DIR (default: the files git tracks, or
        every file when DIR has no .git). Fails on:
          - e-mail addresses other than the public allowlist (the guild
            address, GitHub and Anthropic noreply addresses)
          - local user paths (C:\\Users\\<name>, /home/<name>, /Users/<name>)
          - WoW player GUIDs other than the fake test ones (server id 0000/1/1234)
          - token-like secrets (gitleaks-style rules)
          - files that must never be public (git bundles, patches, real
            SavedVariables, images without a license note)
        Extra private words (for example a local account name) can be given in
        the environment variable GF_PRIVATE_TERMS, comma separated. They are
        never written to the report, only counted.

Standard library only; runs on Windows and in GitHub Actions.
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TOC = "addon/GreenFangToolkit/GreenFangToolkit.toc"

ALLOWED_EMAILS = {
    "greenandfang.adventure@gmail.com",                          # guild address (D-017)
    "301290318+greenandfangadventure@users.noreply.github.com",  # org noreply
    "noreply@anthropic.com",                                     # Co-Authored-By trailer
    "noreply@github.com",
}
# Placeholders used in docs; never real addresses.
PLACEHOLDER_EMAIL = re.compile(r"@example\.(com|org|net)$", re.I)

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
# Windows (C:\Users\<name>, C:/Users/<name>), Git Bash (/c/Users/<name>), Linux and macOS homes.
# "/users/" in lower case is left alone: it is common in URLs (Discord API etc.).
USER_PATH = re.compile(
    r"((?i:[A-Z]:[\\/]+Users[\\/]+)|(?i:(?<!\w)/[A-Z]/Users/)|(?<![\w.])/home/|(?<![\w.])/Users/)"
    r"([^\\/\s\"'`<>%$*{}()\[\]|?]+)")
USER_PATH_OK = {"public", "default", "all users", "runner", "<name>", "<user>", "<使用者>", "user", "username"}
GUID = re.compile(r"Player-(\d+)-([0-9A-Fa-f]{6,8})\b")
GUID_OK_SERVERS = {"0000", "1", "1234"}

SECRET_RULES = [
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY")),
    ("GitHub token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{60,}")),
    ("AWS key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("Discord bot token", re.compile(r"\b[MNO][A-Za-z\d_-]{23,25}\.[A-Za-z\d_-]{6}\.[A-Za-z\d_-]{27,38}\b")),
    ("Discord webhook", re.compile(r"discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]{30,}")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("Cloudflare/CurseForge-style token assignment",
     re.compile(r"(?i)\b(?:api[_-]?(?:key|token)|secret|password|passwd|cf_api_token|token)\b\s*[:=]\s*[\"']?[A-Za-z0-9_\-/+=]{24,}")),
]
# A value that is only a reference (${{ secrets.X }}, $env:X, <...>) is fine.
SECRET_REFERENCE = re.compile(r"secrets\.|\$\{|\$env:|<[^>]+>|os\.environ|getenv")

FORBIDDEN_FILES = [
    (re.compile(r"\.bundle$", re.I), "git bundle (contains other repos' commits and identities)"),
    (re.compile(r"\.patch$", re.I), "git patch (From: header carries the author identity)"),
    (re.compile(r"(^|/)WTF/|(^|/)SavedVariables/", re.I), "real game data"),
    (re.compile(r"\.(env|key|pem|pfx|p12)$|(^|/)\.dev\.vars$", re.I), "secret file"),
]
IMAGE = re.compile(r"\.(png|jpe?g|gif|tga|blp|bmp|webp|ico|psd|ttf|otf)$", re.I)
LICENSE_NOTE = "ASSETS-LICENSE.md"
TEXT_LIMIT = 4 * 1024 * 1024


def tracked_files(root):
    if os.path.isdir(os.path.join(root, ".git")) or os.path.isfile(os.path.join(root, ".git")):
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True).stdout
        return [p for p in out.decode("utf-8").split("\0") if p]
    files = []
    for d, dirs, names in os.walk(root):
        dirs[:] = [x for x in dirs if x != ".git"]
        for n in names:
            files.append(os.path.relpath(os.path.join(d, n), root).replace("\\", "/"))
    return sorted(files)


def read_text(path):
    with open(path, "rb") as f:
        data = f.read(TEXT_LIMIT + 1)
    if b"\0" in data[:8192]:
        return None
    return data.decode("utf-8", errors="replace")


def scan(root, private_terms):
    findings = []   # (rule, file, line, detail)
    files = tracked_files(root)
    image_dirs_with_note = {os.path.dirname(p) for p in files if os.path.basename(p) == LICENSE_NOTE}
    for rel in files:
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            continue
        for pat, why in FORBIDDEN_FILES:
            if pat.search(rel):
                findings.append(("forbidden file", rel, 0, why))
        if IMAGE.search(rel):
            d = os.path.dirname(rel)
            if not any(d == n or d.startswith(n + "/") for n in image_dirs_with_note):
                findings.append(("asset without license note", rel, 0,
                                 "binary asset; add %s next to it or leave it out" % LICENSE_NOTE))
            continue
        text = read_text(full)
        if text is None:
            continue
        lower_terms = [t.lower() for t in private_terms]
        for n, line in enumerate(text.splitlines(), 1):
            for m in EMAIL.finditer(line):
                addr = m.group(0).lower().rstrip(".")
                if addr in ALLOWED_EMAILS:
                    continue
                if PLACEHOLDER_EMAIL.search(addr):
                    continue
                rule = "e-mail (gmail)" if addr.endswith("@gmail.com") else "e-mail"
                findings.append((rule, rel, n, mask(addr)))
            for m in USER_PATH.finditer(line):
                who = m.group(2).strip().lower()
                if who in USER_PATH_OK:
                    continue
                findings.append(("local user path", rel, n, m.group(1) + "<…>"))
            for m in GUID.finditer(line):
                if m.group(1) in GUID_OK_SERVERS:
                    continue
                findings.append(("player GUID", rel, n, "Player-%s-…" % m.group(1)))
            for name, pat in SECRET_RULES:
                for m in pat.finditer(line):
                    if SECRET_REFERENCE.search(line):
                        continue
                    findings.append(("secret: " + name, rel, n, m.group(0)[:6] + "…"))
            if lower_terms:
                low = line.lower()
                for i, t in enumerate(lower_terms):
                    if t and t in low:
                        findings.append(("private term", rel, n, "GF_PRIVATE_TERMS #%d" % (i + 1)))
    return files, findings


def mask(addr):
    return "…@" + addr.partition("@")[2]


def write_report(path, root, files, findings):
    lines = ["# 公開前掃描報告", "", "- 掃描位置：`%s`" % root, "- 檔案數：%d" % len(files),
             "- 發現：%d 項" % len(findings), ""]
    if findings:
        lines += ["| 規則 | 檔案 | 行 | 說明 |", "|---|---|---|---|"]
        for rule, rel, n, detail in findings:
            lines.append("| %s | `%s` | %s | %s |" % (rule, rel, n or "", detail.replace("|", "\\|")))
    else:
        lines.append("沒有發現問題。")
    lines += ["", "## 掃描的檔案", ""] + ["- `%s`" % f for f in files]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def toc_version(root):
    with open(os.path.join(root, TOC), encoding="utf-8-sig") as f:
        for line in f:
            m = re.match(r"##\s*Version:\s*(\S+)", line)
            if m:
                return m.group(1)
    return None


def check_version(root, tag):
    errors = []
    v = toc_version(root)
    if not v or not re.fullmatch(r"\d+\.\d+\.\d+", v):
        errors.append("TOC Version must be x.y.z, got %r" % v)
    changelog = os.path.join(root, "CHANGELOG.md")
    if not os.path.isfile(changelog):
        errors.append("CHANGELOG.md is missing")
    elif v:
        with open(changelog, encoding="utf-8") as f:
            text = f.read()
        if not re.search(r"^##\s+%s(\s|（|\(|$)" % re.escape(v), text, re.M):
            errors.append("CHANGELOG.md has no '## %s' section" % v)
    if tag:
        m = re.fullmatch(r"v(\d+\.\d+\.\d+)(?:-([0-9A-Za-z.]+))?", tag)
        if not m:
            errors.append("tag %r is not v<x.y.z>[-suffix]" % tag)
        elif m.group(1) != v:
            errors.append("tag %s does not match TOC Version %s" % (tag, v))
    return v, errors


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    pv = sub.add_parser("version")
    pv.add_argument("--tag")
    pv.add_argument("--root", default=ROOT)
    ps = sub.add_parser("scan")
    ps.add_argument("--root", default=ROOT)
    ps.add_argument("--report")
    args = ap.parse_args()

    if args.cmd == "version":
        tag = args.tag
        if tag is None and os.environ.get("GITHUB_REF_TYPE") == "tag":
            tag = os.environ.get("GITHUB_REF_NAME")
        v, errors = check_version(args.root, tag)
        for e in errors:
            print("version check: " + e)
        if not errors:
            print("version check: ok, %s%s" % (v, (" (tag %s)" % tag) if tag else ""))
        return 1 if errors else 0

    terms = [t.strip() for t in os.environ.get("GF_PRIVATE_TERMS", "").split(",") if t.strip()]
    files, findings = scan(args.root, terms)
    for rule, rel, n, detail in findings:
        print("%s: %s:%s %s" % (rule, rel, n, detail))
    print("leak scan: %d files, %d findings" % (len(files), len(findings)))
    if args.report:
        write_report(args.report, args.root, files, findings)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
