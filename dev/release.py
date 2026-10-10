# Builds the release zip: Wowstagram-<version>.zip in dev/release, with
# what players need and nothing else (the same as .pkgmeta: no dev folder,
# TODO, README, CURSEFORGE, git files).
#   python dev/release.py
import os, re, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SKIP_DIRS = {"dev", ".git"}
SKIP_FILES = {".gitignore", ".gitattributes", ".pkgmeta", "TODO.md", "README.md", "CURSEFORGE.md"}

toc = open(os.path.join(ROOT, "Wowstagram.toc"), encoding="utf8").read()
version = re.search(r"## Version: (\S+)", toc).group(1)
out_dir = os.path.join(HERE, "release")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, "Wowstagram-%s.zip" % version)
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder, dirs, files in os.walk(ROOT):
        rel = os.path.relpath(folder, ROOT)
        dirs[:] = [d for d in dirs if not (rel == "." and d in SKIP_DIRS)]
        for f in files:
            if rel == "." and f in SKIP_FILES:
                continue
            path = os.path.join(folder, f)
            z.write(path, os.path.join("Wowstagram", os.path.relpath(path, ROOT)))
            n += 1
print("%s: %d files, %.0f KB" % (out, n, os.path.getsize(out) / 1024))
