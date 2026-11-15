#!/usr/bin/env python3
"""Builds the Cydia (APT) repository and the OTA feed for the GitHub Pages site, standard library only.

    python scripts/make-cydia-repo.py SITE_DIR [new.deb ...] [--notes "text"]

- copies the given packages into SITE_DIR/cydia/debs/ (packages already there are kept: older versions stay
  installable);
- writes SITE_DIR/cydia/Packages, Packages.gz, Packages.bz2 and Release (what Cydia reads);
- writes SITE_DIR/update.json for the app's OTA update (newest vn.tubemini.io: version, URL, SHA-256, size, notes).

Cydia source to add on the iPad: https://tubemini.github.io/cydia/
"""
import bz2
import gzip
import hashlib
import io
import json
import shutil
import sys
import tarfile
import time
from pathlib import Path

BASE_URL = "https://tubemini.github.io"
APP_PACKAGE = "vn.tubemini.io"


def control_of(deb: Path) -> dict:
    """The control fields of a .deb (ar archive → control.tar.gz → ./control)."""
    data = deb.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        raise ValueError(f"{deb}: not a .deb")
    pos = 8
    while pos + 60 <= len(data):
        header = data[pos:pos + 60]
        name = header[:16].decode().strip().rstrip("/")
        size = int(header[48:58].decode().strip())
        body = data[pos + 60:pos + 60 + size]
        pos += 60 + size + (size % 2)
        if name.startswith("control.tar"):
            with tarfile.open(fileobj=io.BytesIO(body)) as tar:
                member = next(m for m in tar.getmembers() if m.name.lstrip("./") == "control")
                text = tar.extractfile(member).read().decode("utf-8")
            fields, key = {}, None
            for line in text.splitlines():
                if line.startswith((" ", "\t")) and key:
                    fields[key] += "\n" + line
                elif ":" in line:
                    key, value = line.split(":", 1)
                    fields[key.strip()] = value.strip()
            return fields
    raise ValueError(f"{deb}: no control.tar")


def version_key(v: str):
    """Debian-ish ordering, good enough for 0.5.0-1 style versions."""
    main, _, rev = v.partition("-")
    return [int(x) if x.isdigit() else x for x in main.split(".")] + [int(rev) if rev.isdigit() else 0]


def main():
    args = sys.argv[1:]
    notes = None
    if "--notes" in args:
        i = args.index("--notes")
        notes = args[i + 1]
        del args[i:i + 2]
    if not args:
        sys.exit(__doc__)
    site = Path(args[0])
    repo = site / "cydia"
    debs_dir = repo / "debs"
    debs_dir.mkdir(parents=True, exist_ok=True)
    for deb in map(Path, args[1:]):
        shutil.copy2(deb, debs_dir / deb.name)

    entries, newest = [], None
    for deb in sorted(debs_dir.glob("*.deb")):
        fields = control_of(deb)
        blob = deb.read_bytes()
        fields["Filename"] = f"debs/{deb.name}"
        fields["Size"] = str(len(blob))
        fields["MD5sum"] = hashlib.md5(blob).hexdigest()
        fields["SHA1"] = hashlib.sha1(blob).hexdigest()
        fields["SHA256"] = hashlib.sha256(blob).hexdigest()
        entries.append(fields)
        if fields.get("Package") == APP_PACKAGE and (newest is None or version_key(fields["Version"]) > version_key(newest["Version"])):
            newest = fields

    order = ["Package", "Name", "Version", "Architecture", "Description", "Maintainer", "Author", "Section", "Depends",
             "Homepage", "Depiction", "Icon", "Filename", "Size", "MD5sum", "SHA1", "SHA256"]
    blocks = []
    for f in entries:
        keys = [k for k in order if k in f] + [k for k in f if k not in order]
        blocks.append("".join(f"{k}: {f[k]}\n" for k in keys))
    packages = "\n".join(blocks).encode("utf-8")
    (repo / "Packages").write_bytes(packages)
    (repo / "Packages.gz").write_bytes(gzip.compress(packages, 9, mtime=0))
    (repo / "Packages.bz2").write_bytes(bz2.compress(packages, 9))

    release = [
        "Origin: TubeMini",
        "Label: TubeMini",
        "Suite: stable",
        f"Version: {newest['Version'] if newest else '0'}",
        "Codename: ios",
        "Architectures: iphoneos-arm",
        "Components: main",
        "Description: TubeMini — YouTube cho iPad iOS 6",
        f"Date: {time.strftime('%a, %d %b %Y %H:%M:%S UTC', time.gmtime())}",
    ]
    for algo, title in ((hashlib.md5, "MD5Sum"), (hashlib.sha256, "SHA256")):
        release.append(f"{title}:")
        for name in ("Packages", "Packages.gz", "Packages.bz2"):
            blob = (repo / name).read_bytes()
            release.append(f" {algo(blob).hexdigest()} {len(blob)} {name}")
    (repo / "Release").write_text("\n".join(release) + "\n", encoding="utf-8")

    if newest:
        if notes is None:
            # Republishing without --notes keeps the notes of the same version
            try:
                old = json.loads((site / "update.json").read_text(encoding="utf-8"))
                notes = old.get("notes", "") if old.get("package_version") == newest["Version"] else ""
            except (OSError, ValueError):
                notes = ""
        feed = {
            "version": newest["Version"].split("-")[0],
            "package_version": newest["Version"],
            "url": f"{BASE_URL}/cydia/{newest['Filename']}",
            "sha256": newest["SHA256"],
            "size": int(newest["Size"]),
            "notes": notes,
        }
        (site / "update.json").write_text(json.dumps(feed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(entries)} package(s) in {repo}; newest {APP_PACKAGE}: {newest['Version'] if newest else '-'}")


if __name__ == "__main__":
    main()
