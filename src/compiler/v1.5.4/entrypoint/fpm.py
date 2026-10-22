#!/usr/bin/env python3
"""
fpm - Flux Package Manager

Copyright (C) 2026 Karac V. Thweatt

Downloads and manages Flux standard library and third-party packages.

Usage:
    fpm install <package>       Install a specific package
    fpm install --stdlib        Install the full standard library
    fpm install --all           Install everything (stdlib + registered packages)
    fpm search <term>           Search packages by name or description
    fpm list                    List installed packages
    fpm list --available        List all available packages
    fpm remove <package>        Remove an installed package
    fpm update <package>        Update a package to latest
    fpm update --all            Update all installed packages
    fpm check                   Validate installed dependencies and file presence
    fpm info <package>          Show package details
    fpm init                    Create a package.json for an existing project
    fpm create                  Interactively scaffold a new Flux package
    fpm fixdeps <pack>          Auto-fix dependencies from source imports
    fpm fixdeps <pack> --check  Dry-run: show what fixdeps would change
    fpm addsource <url>         Add a remote package source
    fpm removesource <url>      Remove a package source
    fpm sources                 List configured sources
    fpm publish <package>       Publish a local package to the fpm server
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error
import urllib.parse
import shutil
from pathlib import Path
from typing import Optional

# ─── Constants ────────────────────────────────────────────────────────────────

# Resolve project root: prefer FLUXC_SRCDIR env var (set by fxc.py), fall back
# to a sibling-of-this-script heuristic so fpm can also be run standalone.
FLUXC_SRCDIR    = Path(os.environ.get("FLUXC_SRCDIR", Path(__file__).parent)).resolve()

FPM_DIR         = FLUXC_SRCDIR / ".fpm"
STDLIB_DIR      = FLUXC_SRCDIR / "src" / "stdlib"
PACKAGES_DIR    = FPM_DIR / "packages"
REGISTRY_FILE   = FPM_DIR / "registry.json"
INSTALLED_FILE  = FPM_DIR / "installed.json"
SOURCES_FILE    = FPM_DIR / "sources.json"
SOURCE_CACHE_FILE = FPM_DIR / "source-cache.json"
SOURCE_CACHE_TTL  = 3600  # seconds before a cached index is considered stale
STDLIB_BASE_URL = "https://raw.githubusercontent.com/kvthweatt/FluxLang/main/src/stdlib"
FPM_USER_AGENT  = "FluxPackageManager-1.0.0"
FPM_SERVER_PORT = 8080

# Loaded from STDLIB_DIR/package.json at startup — do not hardcode here
STDLIB_PACKAGES = {}


# ─── Stdlib helpers ───────────────────────────────────────────────────────────

def load_stdlib_json() -> dict:
    """Read STDLIB_DIR/package.json and return the packages dict."""
    stdlib_json = STDLIB_DIR / "package.json"
    if not stdlib_json.exists():
        print(f"WARNING: stdlib package.json not found at {stdlib_json}")
        return {}
    with open(stdlib_json) as f:
        data = json.load(f)
    packages = {}
    for name, pkg in data.get("packages", {}).items():
        entry = dict(pkg)
        entry.setdefault("path", "")
        packages[name] = entry
    return packages


def fetch_remote_stdlib_json() -> dict:
    """Fetch the stdlib package.json from GitHub and return the packages dict."""
    url = f"{STDLIB_BASE_URL}/package.json"
    require_https(url)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": FPM_USER_AGENT}), timeout=15) as response:
            data = json.loads(response.read().decode("utf-8"))
        packages = {}
        for name, pkg in data.get("packages", {}).items():
            entry = dict(pkg)
            entry.setdefault("path", "")
            packages[name] = entry
        return packages
    except urllib.error.HTTPError as e:
        print(f"  ERROR: HTTP {e.code} fetching remote stdlib package.json")
        return {}
    except urllib.error.URLError as e:
        print(f"  ERROR: Could not reach GitHub — {e.reason}")
        return {}


def is_stdlib_package(name: str) -> bool:
    return name in STDLIB_PACKAGES


def get_stdlib_files(pkg: dict) -> list[Path]:
    """Return a list of resolved stdlib Paths for a package (handles entry and entries)."""
    sub_path = pkg.get("path", "")
    if "entries" in pkg:
        base = STDLIB_DIR / sub_path if sub_path else STDLIB_DIR
        return [base / filename for filename in pkg["entries"].values()]
    entry = pkg["entry"]
    if sub_path:
        return [STDLIB_DIR / sub_path / entry]
    return [STDLIB_DIR / entry]


def stdlib_installed_entry(name: str) -> dict:
    pkg   = STDLIB_PACKAGES[name]
    files = get_stdlib_files(pkg)
    rec = {
        "version": pkg["version"],
        "path":    pkg.get("path", ""),
        "files":   [str(f) for f in files],
        "source":  "stdlib"
    }
    if "entries" in pkg:
        rec["entries"] = pkg["entries"]
    else:
        rec["entry"] = pkg["entry"]
        rec["file"]  = str(files[0])
    return rec


# ─── Version constraint parsing ───────────────────────────────────────────────

def parse_version(version_str: str) -> tuple:
    """Parse a version string like '1.2.3' into a comparable tuple."""
    try:
        return tuple(int(x) for x in version_str.strip().split("."))
    except ValueError:
        return (0, 0, 0)


def check_version_constraint(installed_version: str, constraint: str) -> bool:
    """
    Check if an installed version satisfies a constraint string.
    Supports:
      '1.0.0'            exact match
      '>1.0.0'           strictly greater
      '<1.0.0'           strictly less
      '>=1.0.0'          greater or equal
      '<=1.0.0'          less or equal
      '>1.0.0 <2.0.0'   range (space-separated, all parts must pass)
      '^1.2.3'           compatible: >=1.2.3 <2.0.0 (major locked)
      '~=1.2.3'          compatible release: >=1.2.3 <1.3.0 (minor locked)
    """
    installed = parse_version(installed_version)
    parts = constraint.strip().split()

    def evaluate(part: str) -> bool:
        if part.startswith("~="):
            # Compatible release: >= specified, < next minor
            # ~=1.2.3 means >=1.2.3, <1.3.0  (minor is locked, patch can vary)
            base = parse_version(part[2:])
            # Upper bound: increment the second-to-last component, drop the last
            if len(base) >= 2:
                upper = base[:-1][:-1] + (base[-2] + 1,)
            else:
                upper = (base[0] + 1,)
            return installed >= base and installed < upper
        elif part.startswith("^"):
            # Caret: >= specified, < next major
            base = parse_version(part[1:])
            upper = (base[0] + 1,)
            return installed >= base and installed < upper
        elif part.startswith(">="):
            return installed >= parse_version(part[2:])
        elif part.startswith("<="):
            return installed <= parse_version(part[2:])
        elif part.startswith(">"):
            return installed > parse_version(part[1:])
        elif part.startswith("<"):
            return installed < parse_version(part[1:])
        else:
            return installed == parse_version(part)

    return all(evaluate(p) for p in parts)


# ─── HTTP helpers ─────────────────────────────────────────────────────────────

def require_https(url: str):
    """
    Abort with a clear error if url is not HTTPS.
    fpm only ever communicates over encrypted connections.
    """
    if not url.lower().startswith("https://"):
        print(f"  ERROR: Refusing to connect over plain HTTP: {url}")
        print("  All fpm sources must use HTTPS.")
        sys.exit(1)


def download_file(url: str, dest: Path) -> bool:
    """Download a file from a URL to a destination path. Returns True on success."""
    require_https(url)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": FPM_USER_AGENT}), timeout=15) as response:
            dest.parent.mkdir(parents=True, exist_ok=True)
            with open(dest, "wb") as f:
                f.write(response.read())
        return True
    except urllib.error.HTTPError as e:
        print(f"  ERROR: HTTP {e.code} fetching {url}")
        return False
    except urllib.error.URLError as e:
        print(f"  ERROR: Could not reach {url} — {e.reason}")
        return False


# ─── Installed package tracking ───────────────────────────────────────────────

def load_installed() -> dict:
    """Load installed.json and overlay stdlib packages so they are always known."""
    installed = {}
    if INSTALLED_FILE.exists():
        with open(INSTALLED_FILE) as f:
            installed = json.load(f)
    for name in STDLIB_PACKAGES:
        installed[name] = stdlib_installed_entry(name)
    return installed


def save_installed(installed: dict):
    FPM_DIR.mkdir(parents=True, exist_ok=True)
    # Don't persist stdlib entries — they are always regenerated from package.json
    to_save = {k: v for k, v in installed.items() if v.get("source") != "stdlib"}
    with open(INSTALLED_FILE, "w") as f:
        json.dump(to_save, f, indent=2)


# ─── Sources ──────────────────────────────────────────────────────────────────
#
# sources.json format:
# {
#   "UTTCex": {
#     "source-owner": "Karac Thweatt",
#     "source-url":   "https://www.uttcex.net/flux/fpm/public"
#   },
#   ...
# }
#
# Each source exposes a packages.json at <source-url>/packages.json:
# {
#   "test-pack1": "https://fluxpacks.site.com/test-pack1/package.json",
#   "test-pack2": "https://fluxpacks.site.com/test-pack2/package.json"
# }
#
# Each package.json URL points to an individual package manifest.

def load_sources() -> dict:
    """Load sources.json — dict of {name: {source-owner, source-url}}."""
    if SOURCES_FILE.exists():
        with open(SOURCES_FILE) as f:
            return json.load(f)
    return {}


def save_sources(sources: dict):
    FPM_DIR.mkdir(parents=True, exist_ok=True)
    with open(SOURCES_FILE, "w") as f:
        json.dump(sources, f, indent=2)


def fetch_packages_index(base_url: str) -> dict:
    """
    Fetch <base_url>/packages.json — the index for a source.
    Returns {pkg_name: package_json_url} or {} on failure.
    """
    base_url = base_url.rstrip("/")
    url = f"{base_url}/packages.json"
    require_https(url)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": FPM_USER_AGENT}), timeout=15) as response:
            data = json.loads(response.read().decode("utf-8"))
        if not isinstance(data, dict):
            print(f"  ERROR: {url} did not return a JSON object.")
            return {}
        return data
    except urllib.error.HTTPError as e:
        print(f"  ERROR: HTTP {e.code} fetching {url}")
        return {}
    except urllib.error.URLError as e:
        print(f"  ERROR: Could not reach {url} — {e.reason}")
        return {}


def fetch_package_manifest(pkg_name: str, pkg_json_url: str, source_name: str) -> Optional[dict]:
    """
    Fetch an individual package.json URL and return the package metadata dict,
    or None on failure.
    """
    require_https(pkg_json_url)
    try:
        with urllib.request.urlopen(urllib.request.Request(pkg_json_url, headers={"User-Agent": FPM_USER_AGENT}), timeout=15) as response:
            data = json.loads(response.read().decode("utf-8"))
        # package.json may be wrapped in {"packages": {name: {...}}} or be the
        # metadata dict directly — handle both.
        if "packages" in data:
            inner = data["packages"]
            pkg = inner.get(pkg_name) or next(iter(inner.values()), None)
        else:
            pkg = data
        if not isinstance(pkg, dict):
            print(f"  ERROR: Unexpected format in {pkg_json_url}")
            return None
        pkg = dict(pkg)
        pkg.setdefault("path", "")
        pkg["_source_url"]  = pkg_json_url
        pkg["_source_name"] = source_name
        return pkg
    except urllib.error.HTTPError as e:
        print(f"  ERROR: HTTP {e.code} fetching {pkg_json_url}")
        return None
    except urllib.error.URLError as e:
        print(f"  ERROR: Could not reach {pkg_json_url} — {e.reason}")
        return None


def fetch_source(source_name: str, source_info: dict) -> dict:
    """
    Given a source entry from sources.json, fetch its packages.json index and
    then fetch each individual package manifest.
    Returns {pkg_name: metadata_dict}.
    """
    base_url = source_info.get("source-url", "").rstrip("/")
    if not base_url:
        print(f"  ERROR: Source '{source_name}' has no 'source-url'.")
        return {}
    if not base_url.lower().startswith("https://"):
        print(f"  ERROR: Source '{source_name}' uses plain HTTP ({base_url}).")
        print("  Edit sources.json and change the URL to HTTPS, then retry.")
        return {}

    index = fetch_packages_index(base_url)
    if not index:
        return {}

    packages = {}
    for pkg_name, pkg_json_url in index.items():
        manifest = fetch_package_manifest(pkg_name, pkg_json_url, source_name)
        if manifest is not None:
            packages[pkg_name] = manifest
    return packages


def cmd_addsource(args, sources: dict):
    print("\n╔══════════════════════════════════════════╗")
    print("║      fpm addsource — Source Wizard       ║")
    print("╚══════════════════════════════════════════╝")
    print("  Press Ctrl-C at any time to abort.\n")

    # ── Step 1: Source name ───────────────────────────────────────────────────
    _divider("Step 1 of 3 — Source Name")
    print("  A short identifier for this source (e.g. UTTCex, fluxpacks).")
    print("  Used with 'fpm removesource <name>'.\n")
    name = ""
    while not name:
        name = _ask("Source name", "")
        if not name:
            print("  Source name is required.")
        elif name in sources:
            print(f"  '{name}' is already configured ({sources[name]['source-url']}).")
            if _ask_yn("  Overwrite it?", default=False):
                break
            name = ""

    # ── Step 2: Owner ─────────────────────────────────────────────────────────
    _divider("Step 2 of 3 — Owner")
    print("  The name of the person or organization hosting this source.")
    print("  This is displayed in 'fpm sources' so users know who to trust.\n")
    owner = ""
    while not owner:
        owner = _ask("Owner name", "")
        if not owner:
            print("  Owner is required — source hosts must identify themselves.")

    # ── Step 3: URL ───────────────────────────────────────────────────────────
    _divider("Step 3 of 3 — Source URL")
    print("  The base URL of the source. fpm will fetch <url>/packages.json")
    print("  to verify the source before saving.\n")
    url = ""
    index = {}
    while not url:
        raw = _ask("Source URL", "")
        if not raw:
            print("  URL is required.")
            continue
        raw = raw.rstrip("/")
        if not raw.lower().startswith("https://"):
            print("  ERROR: Source URLs must use HTTPS. Plain HTTP is not allowed.")
            continue
        print(f"\n  Verifying {raw}/packages.json...")
        index = fetch_packages_index(raw)
        if not index:
            print(f"  ERROR: Could not fetch a valid packages.json from that URL.")
            if not _ask_yn("  Try a different URL?", default=True):
                print("  Aborted.")
                return
        else:
            url = raw

    # ── Confirm ───────────────────────────────────────────────────────────────
    _divider("Summary")
    print(f"  Name:     {name}")
    print(f"  Owner:    {owner}")
    print(f"  URL:      {url}")
    print(f"  Packages: {len(index)} available ({', '.join(sorted(index.keys()))})")

    _divider()
    if not _ask_yn("Add this source?", default=True):
        print("  Cancelled.")
        return

    sources[name] = {"source-owner": owner, "source-url": url}
    save_sources(sources)
    print(f"\n✔  Source '{name}' added.")
    print(f"   Run 'fpm install <package>' to install any of the available packages.")


def cmd_removesource(args, sources: dict):
    name = args.name
    if name not in sources:
        print(f"  Not found: '{name}'")
        print(f"  Run 'fpm sources' to see configured sources.")
        return
    removed_url = sources.pop(name)["source-url"]
    save_sources(sources)
    print(f"  Removed source: '{name}' ({removed_url})")


def cmd_listsources(sources: dict):
    if not sources:
        print("No sources configured.")
        print("  Add one with: fpm addsource <name> <url>")
        return
    print(f"Configured sources ({len(sources)}):\n")
    for name, info in sources.items():
        owner = info.get("source-owner", "")
        url   = info.get("source-url", "")
        owner_str = f"  (owner: {owner})" if owner else ""
        print(f"  {name:<20} {url}{owner_str}")


# ─── Registry ─────────────────────────────────────────────────────────────────

def load_source_cache() -> dict:
    """Load the on-disk source cache, returning {} if missing or corrupt."""
    if not SOURCE_CACHE_FILE.exists():
        return {}
    try:
        with open(SOURCE_CACHE_FILE) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save_source_cache(cache: dict):
    FPM_DIR.mkdir(parents=True, exist_ok=True)
    with open(SOURCE_CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=2)


def load_registry(refresh: bool = False) -> dict:
    """
    Load stdlib + fpm_registry.json + all configured sources.

    Source index data is cached in source-cache.json and only re-fetched when:
      - refresh=True  (e.g. 'fpm update', 'fpm install', 'fpm addsource')
      - the cache entry is older than SOURCE_CACHE_TTL seconds
      - the cache entry is missing for a configured source
    """
    import time
    registry = dict(STDLIB_PACKAGES)

    # Local registry file
    if REGISTRY_FILE.exists():
        with open(REGISTRY_FILE) as f:
            local_reg = json.load(f)
        registry.update(local_reg)

    sources = load_sources()
    if not sources:
        return registry

    cache     = load_source_cache()
    now       = time.time()
    cache_dirty = False

    for source_name, source_info in sources.items():
        entry     = cache.get(source_name, {})
        cached_at = entry.get("cached_at", 0)
        stale     = (now - cached_at) > SOURCE_CACHE_TTL

        if refresh or stale or "packages" not in entry:
            pkgs = fetch_source(source_name, source_info)
            if pkgs:
                cache[source_name] = {"cached_at": now, "packages": pkgs}
                cache_dirty = True
            else:
                # Network failed — fall back to stale cache if available
                if "packages" in entry:
                    print(f"  WARNING: Could not reach source '{source_name}', using cached index.")
                    pkgs = entry["packages"]
                else:
                    pkgs = {}
        else:
            pkgs = entry.get("packages", {})

        registry.update(pkgs)

    if cache_dirty:
        save_source_cache(cache)

    return registry


# ─── Dependency resolution ────────────────────────────────────────────────────

def resolve_dependencies(package_name: str, registry: dict, installed: dict,
                          resolved: list = None, seen: set = None) -> list:
    """
    Recursively resolve dependencies for a package.
    Returns ordered list of package names to install (dependencies first).
    """
    if resolved is None:
        resolved = []
    if seen is None:
        seen = set()

    if package_name in seen:
        return resolved
    seen.add(package_name)

    if package_name not in registry:
        print(f"  WARNING: Package '{package_name}' not found in registry.")
        return resolved

    pkg = registry[package_name]
    for dep_name, constraint in pkg.get("dependencies", {}).items():
        if dep_name in installed:
            if not check_version_constraint(installed[dep_name]["version"], constraint):
                print(f"  WARNING: Installed '{dep_name}' v{installed[dep_name]['version']} "
                      f"does not satisfy '{constraint}' required by '{package_name}'.")
                print(f"    Run: fpm update {dep_name}")
        else:
            resolve_dependencies(dep_name, registry, installed, resolved, seen)

    if package_name not in resolved:
        resolved.append(package_name)

    return resolved


# ─── Core install/update logic ────────────────────────────────────────────────

def install_package(package_name: str, registry: dict, installed: dict,
                    force: bool = False) -> bool:
    """Download and register a third-party package. Returns True on success."""
    if package_name not in registry:
        print(f"  ERROR: '{package_name}' not found in registry.")
        return False

    pkg     = registry[package_name]
    version = pkg["version"]

    if package_name in installed and not force:
        installed_ver = installed[package_name]["version"]
        print(f"  Already installed: {package_name} v{installed_ver}  (use --force to reinstall)")
        return True

    source_url = pkg.get("_source_url", "")

    def make_url(base: str, filename: str) -> str:
        base = base.rstrip("/")
        if base.endswith(".json"):
            base = base.rsplit("/", 1)[0]
        return f"{base}/{filename}"

    def try_download(filename: str, dest: Path) -> bool:
        candidate_urls = []
        if source_url:
            candidate_urls.append(make_url(source_url, filename))
        candidate_urls.append(make_url(STDLIB_BASE_URL, filename))
        for url in candidate_urls:
            if download_file(url, dest):
                return True
            print(f"  Trying next source...")
        return False

    pkg_dir = PACKAGES_DIR / package_name
    print(f"  Downloading {package_name} v{version}...")

    # Always download package.json alongside the source files
    try_download("package.json", pkg_dir / "package.json")

    if "entries" in pkg:
        # Multi-file package
        downloaded_files = {}
        for label, filename in pkg["entries"].items():
            dest = pkg_dir / filename
            if not try_download(filename, dest):
                print(f"  ERROR: Could not download '{filename}' for '{package_name}' from any source.")
                return False
            downloaded_files[label] = str(dest)
            print(f"  Installed:  {filename} -> {dest}")

        installed[package_name] = {
            "version": version,
            "entries": pkg["entries"],
            "files":   list(downloaded_files.values()),
            "source":  "remote"
        }
    else:
        # Single-file package
        entry = pkg["entry"]
        dest  = pkg_dir / entry
        if not try_download(entry, dest):
            print(f"  ERROR: Could not download '{package_name}' from any source.")
            return False

        installed[package_name] = {
            "version": version,
            "entry":   entry,
            "file":    str(dest),
            "files":   [str(dest)],
            "source":  "remote"
        }
        print(f"  Installed:  {package_name} v{version} -> {dest}")

    return True


def update_stdlib_package(name: str, remote_pkg: dict, installed: dict) -> bool:
    """
    Compare local vs remote version for a stdlib package.
    Download and overwrite file(s) in STDLIB_DIR if remote is newer.
    Also updates the local package.json to reflect the new version.
    """
    local_version  = STDLIB_PACKAGES.get(name, {}).get("version", "0.0.0")
    remote_version = remote_pkg.get("version", "0.0.0")

    if parse_version(remote_version) <= parse_version(local_version):
        print(f"  Up to date: {name} v{local_version}")
        return True

    print(f"  Updating {name}: v{local_version} -> v{remote_version}")

    sub_path = remote_pkg.get("path", "")

    def base_url():
        return f"{STDLIB_BASE_URL}/{sub_path}" if sub_path else STDLIB_BASE_URL

    def base_dest():
        return STDLIB_DIR / sub_path if sub_path else STDLIB_DIR

    if "entries" in remote_pkg:
        for label, filename in remote_pkg["entries"].items():
            url  = f"{base_url()}/{filename}"
            dest = base_dest() / filename
            if not download_file(url, dest):
                return False
            print(f"  Updated:    {filename} -> {dest}")
    else:
        entry = remote_pkg["entry"]
        url   = f"{base_url()}/{entry}"
        dest  = base_dest() / entry
        if not download_file(url, dest):
            return False
        print(f"  Updated:    {name} v{remote_version} -> {dest}")

    # Update in-memory STDLIB_PACKAGES and installed record
    STDLIB_PACKAGES[name] = remote_pkg
    installed[name] = stdlib_installed_entry(name)

    # Persist new version to local package.json
    stdlib_json_path = STDLIB_DIR / "package.json"
    if stdlib_json_path.exists():
        with open(stdlib_json_path) as f:
            data = json.load(f)
        if name in data.get("packages", {}):
            data["packages"][name]["version"] = remote_version
            with open(stdlib_json_path, "w") as f:
                json.dump(data, f, indent=2)

    return True


# ─── Commands ─────────────────────────────────────────────────────────────────

def cmd_install(args, registry: dict, installed: dict):
    force = getattr(args, "force", False)

    if args.stdlib:
        targets = list(STDLIB_PACKAGES.keys())
        print(f"Installing full Flux standard library ({len(targets)} packages)...\n")
    elif args.all:
        targets = list(registry.keys())
        print(f"Installing all available packages ({len(targets)})...\n")
    elif args.package:
        targets = args.package
        print(f"Resolving dependencies for: {', '.join(targets)}\n")
        resolved = []
        seen = set()
        for name in targets:
            resolve_dependencies(name, registry, installed, resolved, seen)
        targets = resolved
    else:
        print("ERROR: Specify a package name, --stdlib, or --all.")
        return

    success = 0
    failed  = 0
    for name in targets:
        if is_stdlib_package(name):
            print(f"  Stdlib:   {name} is part of the Flux standard library (always available)")
            success += 1
            continue
        if install_package(name, registry, installed, force=force):
            success += 1
        else:
            failed += 1

    save_installed(installed)
    print(f"\nDone. {success} installed, {failed} failed.")


def cmd_remove(args, registry: dict, installed: dict):
    for name in args.package:
        if is_stdlib_package(name):
            print(f"  Protected: {name} is part of the Flux standard library and cannot be removed.")
            continue
        if name not in installed:
            print(f"  Not installed: {name}")
            continue
        # Use the "path" field (actual subdir) not the package name
        pkg_subdir = installed[name].get("path") or name
        pkg_dir = PACKAGES_DIR / pkg_subdir if pkg_subdir else PACKAGES_DIR / name
        if pkg_dir.exists():
            shutil.rmtree(pkg_dir)
        del installed[name]
        print(f"  Removed: {name}")
    save_installed(installed)


def cmd_update(args, registry: dict, installed: dict):
    # Determine which packages the user wants to update
    if args.all or not args.package:
        targets = list(installed.keys())
    else:
        targets = args.package

    # registry was already loaded with refresh=True from main()
    remote_registry = registry

    # ── Fetch remote stdlib if any stdlib targets ─────────────────────────────
    stdlib_targets = [n for n in targets if is_stdlib_package(n)]
    remote_stdlib: dict = {}
    if stdlib_targets:
        print("  Fetching remote stdlib package.json...")
        remote_stdlib = fetch_remote_stdlib_json()
        if not remote_stdlib:
            print("  WARNING: Could not fetch remote stdlib package.json.")

    # ── Update each target ────────────────────────────────────────────────────
    success = 0
    skipped = 0
    failed  = 0

    for name in targets:
        if name not in installed:
            print(f"  Skipping '{name}': not installed  (use: fpm install {name})")
            skipped += 1
            continue

        if is_stdlib_package(name):
            if name not in remote_stdlib:
                print(f"  Not found:  '{name}' not in remote stdlib package.json")
                failed += 1
                continue
            if update_stdlib_package(name, remote_stdlib[name], installed):
                success += 1
            else:
                failed += 1

        elif name in remote_registry:
            remote_pkg     = remote_registry[name]
            remote_version = remote_pkg.get("version", "0.0.0")
            local_version  = installed[name].get("version", "0.0.0")

            if parse_version(remote_version) <= parse_version(local_version):
                print(f"  Up to date: {name} v{local_version}")
                skipped += 1
                continue

            print(f"  Updating {name}: v{local_version} -> v{remote_version}")
            # Merge remote metadata into registry so install_package can find it
            registry[name] = remote_pkg
            if install_package(name, registry, installed, force=True):
                success += 1
            else:
                failed += 1

        elif name in registry:
            # Fallback: no remote source data, try with existing registry entry
            print(f"  Updating {name} (no remote version info available)...")
            if install_package(name, registry, installed, force=True):
                success += 1
            else:
                failed += 1

        else:
            print(f"  Not found: '{name}' is not in any configured source.")
            failed += 1

    save_installed(installed)
    print(f"\nUpdate complete. {success} updated, {skipped} skipped, {failed} failed.")


def cmd_search(args, registry: dict, installed: dict):
    """Search available packages by name or description substring."""
    term = args.term.lower()
    matches = {
        name: pkg for name, pkg in registry.items()
        if term in name.lower() or term in pkg.get("description", "").lower()
    }
    if not matches:
        print(f"  No packages found matching '{args.term}'.")
        return
    print(f"  Search results for '{args.term}' ({len(matches)} found):\n")
    for name, pkg in sorted(matches.items()):
        desc   = pkg.get("description", "")
        marker = " [installed]" if name in installed else ""
        src    = pkg.get("_source_name", "stdlib" if name in STDLIB_PACKAGES else "local")
        print(f"  {name:<30} v{pkg['version']:<10} {desc}{marker}")
        if pkg.get("dependencies"):
            deps = ", ".join(pkg["dependencies"].keys())
            print(f"  {'':30} deps: {deps}")


def cmd_list(args, registry: dict, installed: dict):
    if args.available:
        print(f"Available packages ({len(registry)}):\n")
        for name, pkg in sorted(registry.items()):
            desc   = pkg.get("description", "")
            marker = " [installed]" if name in installed else ""
            print(f"  {name:<30} v{pkg['version']:<10} {desc}{marker}")
    else:
        if not installed:
            print("No packages installed. Run: fpm install --stdlib")
            return
        print(f"Installed packages ({len(installed)}):\n")
        for name, pkg in sorted(installed.items()):
            source = pkg.get("source", "remote")
            tag    = "[stdlib]" if source == "stdlib" else "[local]" if source == "local" else "[remote]"
            print(f"  {name:<30} v{pkg['version']}  {tag}")


def cmd_info(args, registry: dict, installed: dict):
    for name in args.package:
        pkg = registry.get(name)
        if not pkg:
            print(f"  '{name}' not found in registry.")
            continue

        print(f"\n  Package:      {name}")
        print(f"  Version:      {pkg['version']}")
        print(f"  Description:  {pkg.get('description', 'N/A')}")
        if "entries" in pkg:
            print(f"  Entries:")
            for label, filename in pkg["entries"].items():
                print(f"    {label}: {filename}")
        else:
            print(f"  Entry:        {pkg['entry']}")
        deps = pkg.get("dependencies", {})
        if deps:
            print(f"  Dependencies:")
            for dep, constraint in deps.items():
                print(f"    {dep}  {constraint}")
        else:
            print(f"  Dependencies: none")

        if name in installed:
            source = installed[name].get("source", "remote")
            tag    = "stdlib" if source == "stdlib" else "local" if source == "local" else "remote"
            files  = installed[name].get("files", [installed[name].get("file", "?")])
            if len(files) == 1:
                print(f"  Status:       installed [{tag}] -> {files[0]}")
            else:
                print(f"  Status:       installed [{tag}]")
                for f in files:
                    print(f"                -> {f}")
        else:
            print(f"  Status:       not installed")


# ─── Dependency checker ──────────────────────────────────────────────────────

def cmd_check(args, registry: dict, installed: dict):
    """
    Validate that every installed package's declared dependencies are satisfied.
    Also warns about installed packages whose source files are missing on disk.
    """
    issues = 0
    checked = 0

    for name, rec in sorted(installed.items()):
        if rec.get("source") == "stdlib":
            continue  # stdlib is always present

        checked += 1
        pkg_deps = rec.get("dependencies", {})

        # ── Dependency satisfaction ───────────────────────────────────────────
        for dep_name, constraint in pkg_deps.items():
            if dep_name not in installed:
                print(f"  MISSING DEP  {name}: requires '{dep_name}' ({constraint}) — not installed")
                print(f"               Run: fpm install {dep_name}")
                issues += 1
            elif not check_version_constraint(installed[dep_name]["version"], constraint):
                have = installed[dep_name]["version"]
                print(f"  BAD VERSION  {name}: requires '{dep_name}' {constraint}, "
                      f"have v{have}")
                print(f"               Run: fpm update {dep_name}")
                issues += 1

        # ── File presence ─────────────────────────────────────────────────────
        files = rec.get("files", [])
        if rec.get("file") and not files:
            files = [rec["file"]]
        missing_files = [f for f in files if not Path(f).exists()]
        if missing_files:
            for mf in missing_files:
                print(f"  MISSING FILE {name}: {mf}")
            print(f"               Run: fpm install --force {name}")
            issues += 1

    if issues == 0:
        print(f"  ✔  All {checked} third-party package(s) look healthy.")
    else:
        print(f"\n  {issues} issue(s) found across {checked} package(s).")


# ─── Package creation wizard ──────────────────────────────────────────────────

def _ask(prompt: str, default: str = "") -> str:
    """Prompt the user for input, returning default if they press Enter."""
    suffix = f" [{default}]" if default else ""
    try:
        val = input(f"  {prompt}{suffix}: ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\n\nAborted.")
        sys.exit(0)
    return val if val else default


def _ask_yn(prompt: str, default: bool = True) -> bool:
    """Yes/no prompt. Returns bool."""
    choices = "Y/n" if default else "y/N"
    raw = _ask(f"{prompt} ({choices})", "")
    if not raw:
        return default
    return raw.lower().startswith("y")


def _divider(title: str = ""):
    width = 60
    if title:
        pad = (width - len(title) - 2) // 2
        print(f"\n{'─' * pad} {title} {'─' * (width - pad - len(title) - 2)}")
    else:
        print(f"\n{'─' * width}")


def _collect_entries(existing_registry: dict) -> tuple[bool, dict]:
    """
    Ask whether the package is single-file or multi-file.
    Returns (is_multi, entry_or_entries_dict).
    For single-file: entries_dict == {"entry": "<filename>"}
    For multi-file:  entries_dict == {"entries": {label: filename, ...}}
    """
    multi = _ask_yn("Does this package contain multiple .fx files?", default=False)
    if not multi:
        entry = _ask("Entry filename (e.g. mypackage.fx)", "mypackage.fx")
        if not entry.endswith(".fx"):
            entry += ".fx"
        return False, {"entry": entry}

    print("\n  Enter each entry label and filename. Leave label blank to finish.")
    entries: dict = {}
    idx = 1
    while True:
        label = _ask(f"  Entry {idx} label (e.g. core, utils)")
        if not label:
            if not entries:
                print("  At least one entry is required.")
                continue
            break
        fname = _ask(f"  Entry {idx} filename", f"{label}.fx")
        if not fname.endswith(".fx"):
            fname += ".fx"
        entries[label] = fname
        idx += 1
    return True, {"entries": entries}


def _collect_dependencies(registry: dict) -> dict:
    """Interactively build a dependencies dict {pkg_name: version_constraint}."""
    deps: dict = {}
    print("\n  Add dependencies one at a time. Leave package name blank to finish.")
    while True:
        name = _ask("  Dependency name")
        if not name:
            break
        if name not in registry and registry:
            print(f"  WARNING: '{name}' is not in the current registry — adding anyway.")
        constraint = _ask(f"  Version constraint for '{name}'", ">=1.0.0")
        deps[name] = constraint
    return deps


def _generate_boilerplate(pkg_name: str, description: str,
                           is_multi: bool, entry_info: dict) -> dict[str, str]:
    """
    Return a dict of {filename: source_code} for every .fx file in the package.
    """
    header = (
        f"// {pkg_name}.fx - {description}\n"
        f"// Generated by fpm create\n\n"
        f"#import \"standard.fx\";\n\n"
        f"using standard::io::console;\n\n"
        f"namespace {pkg_name.replace("-","_")}\n{{\n"
    )
    footer = "\n};\n"
    body = (
        "    // TODO: implement your package here\n"
        "    def main() -> int\n"
        "    {\n"
        "        print(\"Hello from " + pkg_name + "!\\0\");\n"
        "        return 0;\n"
        "    };\n"
    )

    files: dict[str, str] = {}
    if not is_multi:
        filename = entry_info["entry"]
        files[filename] = header + body + footer
    else:
        for label, filename in entry_info["entries"].items():
            label_body = (
                f"    // TODO: implement '{label}' functionality here\n"
                f"    def {label}_init() -> void\n"
                "    {\n"
                f"        print(\"{pkg_name.replace("-","_")}::{label} loaded!\\0\");\n"
                "    };\n"
            )
            files[filename] = header + label_body + footer
    return files


def cmd_init(args, registry: dict):
    """
    Scaffold a package.json for an existing directory of .fx files.
    Does not generate any source files — just the manifest.
    """
    print("\n╔════════════════════════════════════════════╗")
    print("║        fpm init — Package Init Wizard         ║")
    print("╚════════════════════════════════════════════╝")
    print("  Creates a package.json for an existing project. Press Ctrl-C to abort.\n")

    # Target directory
    target_str = _ask("Package directory", str(Path.cwd()))
    target     = Path(target_str).expanduser().resolve()
    if not target.exists():
        print(f"  ERROR: Directory does not exist: {target}")
        return

    # Discover .fx files
    fx_files = sorted(target.glob("*.fx"))
    if not fx_files:
        print(f"  No .fx files found in {target}. Are you in the right directory?")
        if not _ask_yn("  Continue anyway?", default=False):
            return

    print(f"  Found {len(fx_files)} .fx file(s):")
    for f in fx_files:
        print(f"    {f.name}")

    _divider("Metadata")
    name        = _ask("Package name", target.name.lower().replace(" ", "-"))
    version     = _ask("Version", "1.0.0")
    description = _ask("Short description", f"A Flux package called {name}")
    author      = _ask("Author name / email", "")
    license_    = _ask("License", "MIT")

    _divider("Entries")
    is_multi, entry_info = _collect_entries(registry)

    _divider("Dependencies")
    deps = _collect_dependencies(registry)

    # Build and write package.json
    pkg_entry: dict = {
        "version":     version,
        "description": description,
        "path":        "",
    }
    if author:
        pkg_entry["author"] = author
    pkg_entry["license"] = license_
    if is_multi:
        pkg_entry["entries"] = entry_info["entries"]
    else:
        pkg_entry["entry"] = entry_info["entry"]
    if deps:
        pkg_entry["dependencies"] = deps

    out = target / "package.json"
    if out.exists() and not _ask_yn(f"  {out} already exists. Overwrite?", default=False):
        print("  Cancelled.")
        return

    with open(out, "w") as f:
        json.dump({"packages": {name: pkg_entry}}, f, indent=2)
    print(f"\n✔  Created {out}")

    if _ask_yn("Register in local fpm registry?", default=True):
        FPM_DIR.mkdir(parents=True, exist_ok=True)
        local_reg: dict = {}
        if REGISTRY_FILE.exists():
            with open(REGISTRY_FILE) as f:
                local_reg = json.load(f)
        local_reg[name] = pkg_entry
        with open(REGISTRY_FILE, "w") as f:
            json.dump(local_reg, f, indent=2)
        print(f"  Registered '{name}' in {REGISTRY_FILE}")


def cmd_create(args, registry: dict):
    """Interactive wizard to scaffold a new Flux package."""
    print("\n╔══════════════════════════════════════════╗")
    print("║       fpm create — Package Wizard        ║")
    print("╚══════════════════════════════════════════╝")
    print("  Press Ctrl-C at any time to abort.\n")

    # ── Step 1: Basic metadata ────────────────────────────────────────────────
    _divider("Step 1 of 5 — Basic Info")
    name = ""
    while not name:
        name = _ask("Package name (lowercase, no spaces)", "")
        if not name:
            print("  Package name is required.")
        elif " " in name or any(c.isupper() for c in name):
            print("  Use lowercase letters, digits, hyphens or underscores only.")
            name = ""
        else:
            # Check for collision in registry and on disk
            existing_location = None
            if name in registry:
                src = registry[name].get("source", "registry")
                existing_location = f"already exists in the registry (source: {src})"
            elif (PACKAGES_DIR / name).exists():
                existing_location = f"already exists on disk at {PACKAGES_DIR / name}"

            if existing_location:
                print(f"\n  WARNING: A package named '{name}' {existing_location}.")
                print(f"  Creating it will overwrite the existing package.")
                if not _ask_yn("  Continue anyway?", default=False):
                    name = ""  # loop and ask for a different name

    version    = _ask("Version", "1.0.0")
    description = _ask("Short description", f"A Flux package called {name}")
    author     = _ask("Author name / email", "")
    license_   = _ask("License", "MIT")

    # ── Step 2: Entry files ───────────────────────────────────────────────────
    _divider("Step 2 of 5 — Entry Files")
    is_multi, entry_info = _collect_entries(registry)

    # ── Step 3: Optional sub-path ─────────────────────────────────────────────
    _divider("Step 3 of 5 — Package Path")
    print("  If your package lives in a subdirectory (e.g. 'net/http'),")
    print("  enter it here. Leave blank for the package root.")
    sub_path = _ask("Sub-path", "")

    # ── Step 4: Dependencies ──────────────────────────────────────────────────
    _divider("Step 4 of 5 — Dependencies")
    deps = _collect_dependencies(registry)

    # ── Step 5: Output location ───────────────────────────────────────────────
    _divider("Step 5 of 5 — Output Location")
    # Default to FLUXC_SRCDIR/.fpm/packages/<name> so the compiler can find
    # the package immediately without any extra configuration.
    default_out = str(PACKAGES_DIR / name)
    out_dir_str = _ask("Where to create the package directory", default_out)
    out_dir     = Path(out_dir_str).expanduser().resolve()

    # ── Confirm ───────────────────────────────────────────────────────────────
    _divider("Summary")
    print(f"  Name:        {name}")
    print(f"  Version:     {version}")
    print(f"  Description: {description}")
    if author:
        print(f"  Author:      {author}")
    print(f"  License:     {license_}")
    if sub_path:
        print(f"  Sub-path:    {sub_path}")
    if is_multi:
        print(f"  Entries:")
        for lbl, fn in entry_info["entries"].items():
            print(f"    {lbl}: {fn}")
    else:
        print(f"  Entry:       {entry_info['entry']}")
    if deps:
        print(f"  Dependencies:")
        for d, c in deps.items():
            print(f"    {d}  {c}")
    else:
        print(f"  Dependencies: none")
    print(f"  Output dir:  {out_dir}")

    _divider()
    if not _ask_yn("Create this package?", default=True):
        print("  Cancelled.")
        return

    # ── Write files ───────────────────────────────────────────────────────────
    out_dir.mkdir(parents=True, exist_ok=True)

    # Build package.json entry
    pkg_entry: dict = {
        "version":     version,
        "description": description,
        "path":        sub_path,
    }
    if author:
        pkg_entry["author"] = author
    pkg_entry["license"] = license_
    if is_multi:
        pkg_entry["entries"] = entry_info["entries"]
    else:
        pkg_entry["entry"] = entry_info["entry"]
    if deps:
        pkg_entry["dependencies"] = deps

    package_json = {"packages": {name: pkg_entry}}
    pkg_json_path = out_dir / "package.json"
    with open(pkg_json_path, "w") as f:
        json.dump(package_json, f, indent=2)
    print(f"\n  Created: {pkg_json_path}")

    # Write .fx boilerplate files
    fx_files = _generate_boilerplate(name, description, is_multi, entry_info)
    for filename, source in fx_files.items():
        dest = out_dir / filename
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "w") as f:
            f.write(source)
        print(f"  Created: {dest}")

    # Optionally register in the local fpm registry
    _divider()
    if _ask_yn("Register this package in your local fpm registry?", default=True):
        FPM_DIR.mkdir(parents=True, exist_ok=True)
        local_reg: dict = {}
        if REGISTRY_FILE.exists():
            with open(REGISTRY_FILE) as f:
                local_reg = json.load(f)
        local_reg[name] = pkg_entry
        with open(REGISTRY_FILE, "w") as f:
            json.dump(local_reg, f, indent=2)
        print(f"  Registered '{name}' in {REGISTRY_FILE}")

    editor = os.environ.get("EDITOR") or os.environ.get("VISUAL") or (
        "notepad" if sys.platform == "win32" else "vi"
    )
    print(f"\n✔  Package '{name}' created at {out_dir}")
    print(f"   Next steps:")
    print(f"     cd {out_dir}")
    if is_multi:
        for fn in entry_info["entries"].values():
            print(f"     {editor} {fn}")
    else:
        print(f"     {editor} {entry_info['entry']}")
    print(f"   When ready, share package.json so others can add it via:")
    print(f"     fpm addsource <url-to-your-package.json>")


# ─── Publish ──────────────────────────────────────────────────────────────────

def cmd_publish(args):
    """
    Publish a local package to a named source's fpm server on port 8080.
    Looks up the source in sources.json to get the base URL, then PUTs
    the package.json and all .fx files to <host>:8080/publish/<n>/<file>.
    """
    name        = args.package
    source_name = args.source
    sources     = load_sources()

    if source_name not in sources:
        print(f"  ERROR: Source '{source_name}' not found.")
        print(f"  Run 'fpm sources' to see configured sources.")
        return

    base_url = sources[source_name].get("source-url", "").rstrip("/")
    parsed   = urllib.parse.urlparse(base_url)
    # Preserve the path prefix so sources hosted under a sub-path still work.
    # e.g. https://example.com/flux/fpm  ->  https://example.com:8080/flux/fpm
    server   = f"{parsed.scheme}://{parsed.hostname}:{FPM_SERVER_PORT}{parsed.path.rstrip('/')}"

    pkg_dir  = PACKAGES_DIR / name
    manifest = pkg_dir / "package.json"

    if not pkg_dir.exists():
        print(f"  ERROR: Package directory not found: {pkg_dir}")
        print(f"  Create the package first with: fpm create")
        return
    if not manifest.exists():
        print(f"  ERROR: No package.json found in {pkg_dir}")
        return

    print(f"\n  Publishing '{name}' to {source_name} ({server}) ...\n")

    # Read package.json to find exactly which files to upload
    with open(manifest) as mf:
        pkg_data = json.load(mf)
    pkg_meta = pkg_data.get("packages", {}).get(name, pkg_data)
    sub_path = pkg_meta.get("path", "")
    base_dir = pkg_dir / sub_path if sub_path else pkg_dir

    files_to_upload = [manifest]  # always include package.json
    if "entries" in pkg_meta:
        for filename in pkg_meta["entries"].values():
            files_to_upload.append(base_dir / filename)
    elif "entry" in pkg_meta:
        files_to_upload.append(base_dir / pkg_meta["entry"])

    success = 0
    failed  = 0
    for f in files_to_upload:
        if not f.exists():
            print(f"  ERROR: File not found: {f}")
            failed += 1
            continue
        rel   = f.relative_to(pkg_dir).as_posix()
        url   = f"{server}/publish/{name}/{rel}"
        data  = f.read_bytes()
        ctype = "application/json" if f.suffix == ".json" else "text/plain"
        req   = urllib.request.Request(
            url, data=data, method="PUT",
            headers={"User-Agent": FPM_USER_AGENT, "Content-Type": ctype}
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                print(f"  ✔  {rel}  ({resp.status})")
                success += 1
        except urllib.error.HTTPError as e:
            print(f"  ERROR: HTTP {e.code} uploading {rel}")
            failed += 1
        except urllib.error.URLError as e:
            print(f"  ERROR: Could not reach server — {e.reason}")
            failed += 1

    print(f"\n  Done. {success} file(s) uploaded, {failed} failed.")


# ─── Fix Dependencies ─────────────────────────────────────────────────────────

def _scan_imports(fx_path: Path) -> list[str]:
    """
    Parse a .fx file and return a list of imported filenames.
    Handles both single and multi-import forms:
        #import "math.fx";
        #import "math.fx", "vectors.fx";
    Correctly skips // line comments and /* ... */ block comments so that
    commented-out imports are not registered as real dependencies.
    """
    import re
    filenames = []
    pattern = re.compile(r'#import\s+((?:(?:"[^"]+"|<[^>]+>)\s*,\s*)*(?:"[^"]+"|<[^>]+>))')
    try:
        text = fx_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return filenames

    in_block_comment = False
    for line in text.splitlines():
        if in_block_comment:
            if "*/" in line:
                line = line[line.index("*/") + 2:]
                in_block_comment = False
            else:
                continue

        if "/*" in line:
            before = line[:line.index("/*")]
            rest   = line[line.index("/*") + 2:]
            if "*/" in rest:
                line = before + rest[rest.index("*/") + 2:]
            else:
                in_block_comment = True
                line = before

        if "//" in line:
            line = line[:line.index("//")]

        stripped = line.strip()
        if not stripped:
            continue
        m = pattern.search(stripped)
        if m:
            for match in re.findall(r'"([^"]+)"|<([^>]+)>', m.group(1)):
                fn = match[0] or match[1]
                filenames.append(fn)
    return filenames
def _build_filename_to_package_map(packages: dict) -> dict[str, str]:
    """
    Build a reverse map: entry filename -> package name.
    e.g. {"math.fx": "flux-math", "vectors.fx": "flux-vectors", ...}
    Handles both single-entry and multi-entry packages.
    """
    mapping = {}
    for pkg_name, pkg in packages.items():
        if "entries" in pkg:
            for fn in pkg["entries"].values():
                mapping[fn] = pkg_name
        elif "entry" in pkg:
            mapping[pkg["entry"]] = pkg_name
    return mapping


def cmd_fixdeps(args, registry: dict, installed: dict):
    """
    Scan each package's .fx source file(s) for #import directives and
    rewrite the 'dependencies' field in package.json to match what is
    actually imported, using the versions already listed in the registry.

    Resolution order for pack_name:
      1. stdlib package.json  (top-level "pack" field or a packages key)
      2. Locally installed third-party package  (PACKAGES_DIR/<name>/package.json)
      3. Local fpm registry file  (REGISTRY_FILE)
    """
    pack_name = args.pack_name  # e.g. "flux-stdlib" or "flux-hotpatch-framework"

    # ── Locate package.json ───────────────────────────────────────────────────

    stdlib_json_path = STDLIB_DIR / "package.json"
    json_path = None
    root = None
    packages = None
    wrap_key = None

    # 1. Check stdlib package.json
    if stdlib_json_path.exists():
        with open(stdlib_json_path) as f:
            candidate = json.load(f)
        top_pack = candidate.get("pack", "")
        pkgs = candidate.get("packages", candidate)
        if pack_name == top_pack or pack_name in pkgs:
            json_path = stdlib_json_path
            root = candidate
            if "packages" in candidate:
                packages = candidate["packages"]
                wrap_key = "packages"
            else:
                packages = candidate
                wrap_key = None

    # 2. Check locally installed third-party packages
    if json_path is None:
        # The "path" field in the package metadata is the actual subdirectory
        # name under PACKAGES_DIR (e.g. "fhf"), which may differ from pack_name.
        # Peek at the registry and installed records to find it; fall back to pack_name.
        _pkg_meta = registry.get(pack_name) or installed.get(pack_name) or {}
        _pkg_subdir = _pkg_meta.get("path") or pack_name
        installed_pkg_json = PACKAGES_DIR / _pkg_subdir / "package.json"
        if installed_pkg_json.exists():
            with open(installed_pkg_json) as f:
                candidate = json.load(f)
            # A per-package package.json may be a bare metadata dict or wrapped
            # in {"packages": {pack_name: {...}}}.
            if "packages" in candidate and pack_name in candidate["packages"]:
                json_path = installed_pkg_json
                root = candidate
                packages = candidate["packages"]
                wrap_key = "packages"
            else:
                # Treat the whole file as a single-package bare dict; wrap it
                # so the rest of the function can work uniformly.
                json_path = installed_pkg_json
                root = {pack_name: candidate}
                packages = root
                wrap_key = None

    # 3. Fall back to the fpm registry file
    if json_path is None and REGISTRY_FILE.exists():
        with open(REGISTRY_FILE) as f:
            candidate = json.load(f)
        pkgs = candidate.get("packages", candidate)
        if pack_name in pkgs:
            json_path = REGISTRY_FILE
            root = candidate
            if "packages" in candidate:
                packages = candidate["packages"]
                wrap_key = "packages"
            else:
                packages = candidate
                wrap_key = None

    if json_path is None:
        # Build a helpful list of places we looked
        _pkg_meta2 = registry.get(pack_name) or installed.get(pack_name) or {}
        _pkg_subdir2 = _pkg_meta2.get("path") or pack_name
        installed_pkg_json = PACKAGES_DIR / _pkg_subdir2 / "package.json"
        print(f"  ERROR: '{pack_name}' was not found in any known package source.")
        print(f"  Checked:")
        print(f"    stdlib  : {stdlib_json_path}")
        print(f"    installed: {installed_pkg_json}")
        print(f"    registry: {REGISTRY_FILE}")
        print(f"  If the package is installed, try 'fpm list' to verify.")
        return

    # ── Determine source root for .fx files ────────────────────────────────────────
    # stdlib packages live under STDLIB_DIR.
    # Third-party packages: .fpm/packages/<name>/ only holds the downloaded
    # manifest, not the source files. The actual .fx sources live in the
    # project root (FLUXC_SRCDIR), optionally under a sub_path.
    try:
        json_path.relative_to(STDLIB_DIR)
        is_stdlib = True
        src_root = STDLIB_DIR
    except ValueError:
        is_stdlib = False
        src_root = json_path.parent  # PACKAGES_DIR/<path-subdir>

    # ── Build filename → package-name reverse map ─────────────────────────────
    # Build reverse map from all known packages so cross-package imports resolve
    fn_to_pkg = _build_filename_to_package_map(packages)
    fn_to_pkg.update(_build_filename_to_package_map(registry))
    fn_to_pkg.update(_build_filename_to_package_map(installed))
    # Let local packages dict win (override registry/installed for same filenames)
    fn_to_pkg.update(_build_filename_to_package_map(packages))

    # ── Scan each package ─────────────────────────────────────────────────────
    print(f"\n  fixdeps — scanning packages in '{json_path}'\n")

    changed_count = 0
    skipped_count = 0

    for pkg_name, pkg in packages.items():
        sub_path = pkg.get("path", "")

        # Collect the .fx file(s) to scan
        if "entries" in pkg:
            base = src_root / sub_path if sub_path else src_root
            fx_files = [base / fn for fn in pkg["entries"].values()]
        else:
            entry = pkg.get("entry", "")
            if not entry:
                continue
            base = src_root / sub_path if sub_path else src_root
            fx_files = [base / entry]

        # Gather all imports across all files for this package
        imported_filenames: set[str] = set()
        for fx_path in fx_files:
            if fx_path.exists():
                for fn in _scan_imports(fx_path):
                    # Resolve relative paths (e.g. "../types.fx") against the
                    # importing file's directory, then express the result relative
                    # to src_root so it matches the bare filenames in fn_to_pkg.
                    if fn.startswith("..") or fn.startswith("./"):
                        try:
                            resolved = (fx_path.parent / fn).resolve()
                            fn = str(resolved.relative_to(src_root.resolve()))
                            fn = fn.replace("\\", "/")
                        except ValueError:
                            pass  # outside src_root -- keep as-is, will be unknown
                    imported_filenames.add(fn)
            else:
                print(f"  WARNING: Source file not found, skipping scan: {fx_path}")

        if not imported_filenames:
            # No imports found — clear deps only if there were some before
            old_deps = pkg.get("dependencies", {})
            if old_deps:
                print(f"  {pkg_name}: no imports found — clearing {list(old_deps.keys())}")
                pkg["dependencies"] = {}
                changed_count += 1
            else:
                skipped_count += 1
            continue

        # Map filenames → package names, skip self-imports and unknowns
        new_deps: dict[str, str] = {}
        unknown_imports: list[str] = []
        for fn in sorted(imported_filenames):
            dep_pkg_name = fn_to_pkg.get(fn)
            if dep_pkg_name is None:
                # Fall back to bare filename in case the resolved relative path
                # includes subdirectory prefixes not present in the package map
                # (e.g. "builtins/file_object_raw.fx" -> "file_object_raw.fx").
                dep_pkg_name = fn_to_pkg.get(fn.split("/")[-1])
            if dep_pkg_name is None:
                unknown_imports.append(fn)
                continue
            if dep_pkg_name == pkg_name:
                continue  # self-import, ignore
            # Look up version: local packages dict first, then registry, then installed
            if dep_pkg_name in packages:
                dep_version = packages[dep_pkg_name]["version"]
            elif dep_pkg_name in registry:
                dep_version = registry[dep_pkg_name]["version"]
            elif dep_pkg_name in installed:
                dep_version = installed[dep_pkg_name]["version"]
            else:
                unknown_imports.append(fn)
                continue
            new_deps[dep_pkg_name] = f">={dep_version}"

        old_deps = pkg.get("dependencies", {})

        if unknown_imports:
            print(f"  {pkg_name}: unrecognized import(s) (no matching package): "
                  f"{', '.join(unknown_imports)}")

        if new_deps == old_deps:
            skipped_count += 1
            continue

        # Show a diff-style summary
        added   = {k: v for k, v in new_deps.items() if k not in old_deps}
        removed = {k: v for k, v in old_deps.items() if k not in new_deps}
        updated = {k: v for k, v in new_deps.items()
                   if k in old_deps and old_deps[k] != v}

        print(f"  {pkg_name}:")
        for k, v in added.items():
            print(f"    + {k}: {v}")
        for k, v in removed.items():
            print(f"    - {k} (was {v})")
        for k, v in updated.items():
            print(f"    ~ {k}: {old_deps[k]} → {v}")

        pkg["dependencies"] = new_deps
        changed_count += 1

    # ── Write back (or dry-run report) ───────────────────────────────────────
    if changed_count == 0:
        print(f"  All {skipped_count} package(s) already up-to-date. Nothing to write.")
        return

    if getattr(args, "check", False):
        print(f"\n  --check mode: {changed_count} package(s) would be updated, "
              f"{skipped_count} unchanged. Nothing written.")
        return

    if wrap_key:
        root[wrap_key] = packages
    else:
        root = packages

    with open(json_path, "w") as f:
        json.dump(root, f, indent=2)
        f.write("\n")

    # Sync installed.json so fpm list / dependency resolution see fresh deps
    for pkg_name, pkg in packages.items():
        if pkg_name in installed:
            installed[pkg_name]["dependencies"] = pkg.get("dependencies", {})
    save_installed(installed)

    print(f"\n✔  Updated {changed_count} package(s), "
          f"{skipped_count} unchanged.")
    print(f"   Written to: {json_path}")


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        prog="fpm",
        description="Flux Package Manager"
    )
    subparsers = parser.add_subparsers(dest="command")

    # install
    p_install = subparsers.add_parser("install", help="Install packages")
    p_install.add_argument("package", nargs="*", help="Package name(s) to install")
    p_install.add_argument("--stdlib", action="store_true", help="Install full standard library")
    p_install.add_argument("--all",    action="store_true", help="Install all available packages")
    p_install.add_argument("--force",  action="store_true", help="Reinstall even if already installed")

    # remove
    p_remove = subparsers.add_parser("remove", help="Remove installed packages")
    p_remove.add_argument("package", nargs="+", help="Package name(s) to remove")

    # update
    p_update = subparsers.add_parser("update", help="Update installed packages")
    p_update.add_argument("package", nargs="*", help="Package name(s) to update")
    p_update.add_argument("--all", action="store_true", help="Update all installed packages")

    # check
    subparsers.add_parser("check", help="Validate installed package dependencies and files")

    # init
    subparsers.add_parser("init", help="Create a package.json for an existing project")

    # create
    subparsers.add_parser("create", help="Interactively scaffold a new Flux package")

    # addsource
    subparsers.add_parser("addsource", help="Interactively add a named package source")

    # removesource
    p_remsrc = subparsers.add_parser("removesource", help="Remove a package source by name")
    p_remsrc.add_argument("name", help="Source name to remove")

    # sources
    subparsers.add_parser("sources", help="List configured sources")

    # publish
    p_publish = subparsers.add_parser("publish", help="Publish a local package to the fpm server")
    p_publish.add_argument("package", help="Package name to publish")
    p_publish.add_argument("--source", required=True, help="Named source to publish to (from fpm sources)")

    # fixdeps
    p_fixdeps = subparsers.add_parser(
        "fixdeps",
        help="Scan .fx source files and fix dependencies in package.json"
    )
    p_fixdeps.add_argument(
        "pack_name",
        help="Pack name to fix (e.g. flux-stdlib)"
    )
    p_fixdeps.add_argument(
        "--check", action="store_true",
        help="Dry run: report what would change without writing anything"
    )

    # search
    p_search = subparsers.add_parser("search", help="Search packages by name or description")
    p_search.add_argument("term", help="Search term")

    # list
    p_list = subparsers.add_parser("list", help="List packages")
    p_list.add_argument("--available", action="store_true", help="Show all available packages")

    # info
    p_info = subparsers.add_parser("info", help="Show package details")
    p_info.add_argument("package", nargs="+", help="Package name(s)")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    FPM_DIR.mkdir(parents=True, exist_ok=True)
    PACKAGES_DIR.mkdir(parents=True, exist_ok=True)

    # Load stdlib from package.json — must happen before everything else
    STDLIB_PACKAGES.update(load_stdlib_json())

    sources   = load_sources()
    registry  = load_registry(refresh=args.command in ("install", "update", "addsource"))
    installed = load_installed()

    if args.command == "install":
        cmd_install(args, registry, installed)
    elif args.command == "check":
        cmd_check(args, registry, installed)
    elif args.command == "init":
        cmd_init(args, registry)
    elif args.command == "create":
        cmd_create(args, registry)
    elif args.command == "remove":
        cmd_remove(args, registry, installed)
    elif args.command == "update":
        cmd_update(args, registry, installed)
    elif args.command == "search":
        cmd_search(args, registry, installed)
    elif args.command == "list":
        cmd_list(args, registry, installed)
    elif args.command == "info":
        cmd_info(args, registry, installed)
    elif args.command == "addsource":
        cmd_addsource(args, sources)
    elif args.command == "removesource":
        cmd_removesource(args, sources)
    elif args.command == "sources":
        cmd_listsources(sources)
    elif args.command == "publish":
        cmd_publish(args)
    elif args.command == "fixdeps":
        cmd_fixdeps(args, registry, installed)


if __name__ == "__main__":
    main()