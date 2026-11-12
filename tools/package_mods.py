"""Builds one release zip per mod, each holding a single folder named after the mod.

    python tools/package_mods.py [--out dist] [--index] [mod folder ...]

Run it from the MnB-Mods folder. With no mod folders named, every folder that has a
mod.json is packed. `PerfKit.zip` holds `PerfKit/mod.json`, `PerfKit/qm.toml` and so on,
so extracting it into the game's `Mods` folder gives `Mods/PerfKit/`.

--index also writes qm-release-index.json next to the zips (the GitHub release workflow
uploads it with them). Every zip is checked after it is written; a zip without the single
mod-named folder stops the build.
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
import zipfile

# Never packed: editor, OS and build leftovers.
SKIP_NAMES = {"Thumbs.db", "desktop.ini", ".DS_Store", "__pycache__"}
SKIP_SUFFIXES = (".zip", ".pyc", ".tmp", ".bak")


def mod_folders(root):
    return sorted(
        d for d in os.listdir(root)
        if not d.startswith(".") and os.path.isfile(os.path.join(root, d, "mod.json"))
    )


def packed(name):
    return not (name.startswith(".") or name in SKIP_NAMES or name.endswith(SKIP_SUFFIXES))


def build(root, folder, out_dir):
    src = os.path.join(root, folder)
    zip_path = os.path.join(out_dir, folder + ".zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(src, folder + "/")
        for dirpath, dirnames, filenames in os.walk(src):
            dirnames[:] = sorted(d for d in dirnames if packed(d))
            rel = os.path.relpath(dirpath, root).replace(os.sep, "/")
            if dirpath != src:
                zf.write(dirpath, rel + "/")
            for name in sorted(filter(packed, filenames)):
                zf.write(os.path.join(dirpath, name), rel + "/" + name)
    return zip_path


def check(zip_path, folder):
    """The zip's entries all sit under `<folder>/`, with mod.json at `<folder>/mod.json`."""
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        stray = [n for n in names if not n.startswith(folder + "/")]
        if stray:
            raise SystemExit(f"{zip_path}: entries outside {folder}/: {stray[:5]}")
        if folder + "/mod.json" not in names:
            raise SystemExit(f"{zip_path}: no {folder}/mod.json")
        return json.loads(zf.read(folder + "/mod.json").decode("utf-8"))


def write_index(out_dir, built):
    index = {
        "schema_version": 1,
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "repository": os.environ.get("GITHUB_REPOSITORY", "Gamiseus/MnB-Mods"),
        "release_tag": os.environ.get("GITHUB_REF_NAME", "latest"),
        "mods": {},
    }
    for zip_path, meta in built:
        with open(zip_path, "rb") as f:
            data = f.read()
        index["mods"][meta["id"]] = {
            "id": meta["id"],
            "name": meta.get("name", meta["id"]),
            "version": meta.get("version", "1.0.0"),
            "asset_name": os.path.basename(zip_path),
            "sha256": hashlib.sha256(data).hexdigest(),
            "size_bytes": len(data),
            "game_version": meta.get("game_version"),
        }
    path = os.path.join(out_dir, "qm-release-index.json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(index, f, indent=2)
        f.write("\n")
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mods", nargs="*", help="mod folders to pack (default: every folder with a mod.json)")
    ap.add_argument("--out", default="dist", help="output folder (default: dist)")
    ap.add_argument("--index", action="store_true", help="also write qm-release-index.json")
    args = ap.parse_args()

    root = os.getcwd()
    folders = args.mods or mod_folders(root)
    if not folders:
        print("No mod folders found; run this from the MnB-Mods folder.", file=sys.stderr)
        return 1
    os.makedirs(args.out, exist_ok=True)

    built = []
    for folder in folders:
        folder = folder.rstrip("/\\")
        if not os.path.isfile(os.path.join(root, folder, "mod.json")):
            print(f"{folder}: no mod.json, not a mod folder", file=sys.stderr)
            return 1
        zip_path = build(root, folder, args.out)
        meta = check(zip_path, folder)
        built.append((zip_path, meta))
        print(f"{zip_path}: {folder}/ {meta.get('id')} {meta.get('version')}")
    if args.index:
        print(write_index(args.out, built))
    return 0


if __name__ == "__main__":
    sys.exit(main())
