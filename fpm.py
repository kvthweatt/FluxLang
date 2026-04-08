#!/usr/bin/env python3
"""
fpm - Flux Package Manager

Copyright (C) 2026 Karac V. Thweatt

Downloads and manages Flux standard library and third-party packages.

Usage:
    fpm install <package>       Install a specific package
    fpm install --stdlib        Install the full standard library
    fpm install --all           Install everything (stdlib + registered packages)
    fpm list                    List installed packages
    fpm list --available        List all available packages
    fpm remove <package>        Remove an installed package
    fpm update <package>        Update a package to latest
    fpm update --all            Update all installed packages
    fpm info <package>          Show package details
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error
import shutil
from pathlib import Path
from typing import Optional

# ─── Constants ────────────────────────────────────────────────────────────────

FPM_DIR         = Path.home() / "Flux" / ".fpm"
STDLIB_DIR      = Path.home() / "Flux" / "src" / "stdlib"
PACKAGES_DIR    = FPM_DIR / "packages"
REGISTRY_FILE   = FPM_DIR / "registry.json"
INSTALLED_FILE  = FPM_DIR / "installed.json"
SOURCES_FILE    = FPM_DIR / "sources.json"
STDLIB_BASE_URL = "https://raw.githubusercontent.com/kvthweatt/FluxLang/main/src/stdlib"

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
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
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
    Supports: '1.0.0' (exact), '>1.0.0', '<1.0.0', '>=1.0.0', '<=1.0.0',
              '>1.0.0 <2.0.0' (range), '>=1.0.0 <2.0.0' (inclusive range)
    """
    installed = parse_version(installed_version)
    parts = constraint.strip().split()

    def evaluate(part):
        if part.startswith(">="):
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

def download_file(url: str, dest: Path) -> bool:
    """Download a file from a URL to a destination path. Returns True on success."""
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
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

def load_sources() -> list:
    """Load sources.json — list of remote package.json URLs."""
    if SOURCES_FILE.exists():
        with open(SOURCES_FILE) as f:
            return json.load(f)
    return []


def save_sources(sources: list):
    FPM_DIR.mkdir(parents=True, exist_ok=True)
    with open(SOURCES_FILE, "w") as f:
        json.dump(sources, f, indent=2)


def fetch_source(url: str) -> dict:
    """Fetch a remote package.json from a source URL and return its packages dict."""
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            data = json.loads(response.read().decode("utf-8"))
        packages = {}
        for name, pkg in data.get("packages", {}).items():
            entry = dict(pkg)
            entry.setdefault("path", "")
            entry["_source_url"] = url  # track which source this came from
            packages[name] = entry
        return packages
    except urllib.error.HTTPError as e:
        print(f"  ERROR: HTTP {e.code} fetching source {url}")
        return {}
    except urllib.error.URLError as e:
        print(f"  ERROR: Could not reach {url} — {e.reason}")
        return {}


def cmd_addsource(args, sources: list):
    url = args.url
    if url in sources:
        print(f"  Already added: {url}")
        return
    print(f"  Fetching {url}...")
    packages = fetch_source(url)
    if not packages:
        print(f"  ERROR: Could not fetch or parse package.json from {url}")
        return
    sources.append(url)
    save_sources(sources)
    print(f"  Added source: {url}")
    print(f"  Provides {len(packages)} package(s): {', '.join(sorted(packages.keys()))}")


def cmd_removesource(args, sources: list):
    url = args.url
    if url not in sources:
        print(f"  Not found: {url}")
        return
    sources.remove(url)
    save_sources(sources)
    print(f"  Removed source: {url}")


def cmd_listsources(sources: list):
    if not sources:
        print("No sources configured.")
        print("  Add one with: fpm addsource <url>")
        return
    print(f"Configured sources ({len(sources)}):\n")
    for url in sources:
        print(f"  {url}")


# ─── Registry ─────────────────────────────────────────────────────────────────

def load_registry() -> dict:
    """Load stdlib + fpm_registry.json + all configured sources."""
    registry = dict(STDLIB_PACKAGES)
    # Legacy registry file
    if REGISTRY_FILE.exists():
        with open(REGISTRY_FILE) as f:
            registry.update(json.load(f))
    # All configured sources
    for url in load_sources():
        packages = fetch_source(url)
        registry.update(packages)
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
        pkg_dir = PACKAGES_DIR / name
        if pkg_dir.exists():
            shutil.rmtree(pkg_dir)
        del installed[name]
        print(f"  Removed: {name}")
    save_installed(installed)


def cmd_update(args, registry: dict, installed: dict):
    if args.all or not args.package:
        targets = list(installed.keys())
    else:
        targets = args.package

    stdlib_targets = [n for n in targets if is_stdlib_package(n)]
    remote_stdlib  = {}
    if stdlib_targets:
        print("  Fetching remote stdlib package.json...")
        remote_stdlib = fetch_remote_stdlib_json()
        if not remote_stdlib:
            print("  WARNING: Could not fetch remote stdlib package.json.")

    success = 0
    failed  = 0
    for name in targets:
        if is_stdlib_package(name):
            if name not in remote_stdlib:
                print(f"  Not found:  {name} not in remote stdlib package.json")
                failed += 1
                continue
            if update_stdlib_package(name, remote_stdlib[name], installed):
                success += 1
            else:
                failed += 1
        elif name not in installed:
            print(f"  Not installed: {name}  (use: fpm install {name})")
        else:
            print(f"  Updating {name}...")
            if install_package(name, registry, installed, force=True):
                success += 1
            else:
                failed += 1

    save_installed(installed)
    print(f"\nUpdate complete. {success} updated, {failed} failed.")


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

    # addsource
    p_addsrc = subparsers.add_parser("addsource", help="Add a package source URL")
    p_addsrc.add_argument("url", help="URL to a remote package.json")

    # removesource
    p_remsrc = subparsers.add_parser("removesource", help="Remove a package source URL")
    p_remsrc.add_argument("url", help="URL to remove")

    # sources
    subparsers.add_parser("sources", help="List configured sources")

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
    registry  = load_registry()
    installed = load_installed()

    if args.command == "install":
        cmd_install(args, registry, installed)
    elif args.command == "remove":
        cmd_remove(args, registry, installed)
    elif args.command == "update":
        cmd_update(args, registry, installed)
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


if __name__ == "__main__":
    main()