# fpm — Flux Package Manager

`fpm` downloads and manages the Flux standard library and third-party packages, and comes included in the language.

---

## Dependencies:
```
import os
import sys
import json
import argparse
import urllib.request
import urllib.error
import shutil
from pathlib import Path
from typing import Optional
```

---

## Directory Layout

| Path | Purpose |
|------|---------|
| `~/Flux/.fpm/` | fpm working directory |
| `~/Flux/.fpm/packages/` | Installed third-party packages |
| `~/Flux/.fpm/registry.json` | Local registry cache |
| `~/Flux/.fpm/installed.json` | Installed package records |
| `~/Flux/.fpm/sources.json` | Configured remote sources |
| `~/Flux/src/stdlib/` | Standard library files |
| `~/Flux/src/stdlib/package.json` | Stdlib package manifest |

---

## Commands

### `fpm install`

Install one or more packages.

```bash
fpm install <package> [<package> ...]   # Install specific package(s)
fpm install --stdlib                    # Install the full standard library
fpm install --all                       # Install everything (stdlib + all registered packages)
fpm install <package> --force           # Reinstall even if already installed
```

Dependencies are resolved automatically and installed in the correct order. If a dependency version constraint is not satisfied by what's already installed, fpm will warn you and suggest running `fpm update`.

Standard library packages are protected and cannot be removed.

---

### `fpm remove`

Remove one or more installed packages.

```bash
fpm remove <package> [<package> ...]
```

---

### `fpm update`

Update installed packages to their latest versions.

```bash
fpm update <package> [<package> ...]   # Update specific package(s)
fpm update --all                       # Update everything installed
```

For stdlib packages, fpm fetches the remote `package.json` from GitHub and downloads any files with a newer version number, updating the local manifest.

---

### `fpm list`

List packages.

```bash
fpm list                  # Show installed packages
fpm list --available      # Show all packages in the registry
```

Each entry shows the package name, version, and source tag (`[stdlib]`, `[local]`, or `[remote]`).

---

### `fpm info`

Show details about a package.

```bash
fpm info <package> [<package> ...]
```

Displays the version, description, entry file, dependencies, and installation status.

---

### `fpm addsource`

Add a remote package source. A source is a URL pointing to a `package.json` file in the same format as the stdlib manifest.

```bash
fpm addsource <url>
```

fpm will fetch the source immediately to validate it and display the packages it provides. The URL is saved to `sources.json` and consulted on every subsequent operation.

---

### `fpm removesource`

Remove a previously added source.

```bash
fpm removesource <url>
```

---

### `fpm sources`

List all configured remote sources.

```bash
fpm sources
```

---

## Package Resolution

When installing a named package, fpm:

1. Resolves the full dependency tree recursively.
2. Checks whether each dependency is already installed and satisfies the required version constraint. If not, it warns and suggests `fpm update`.
3. Installs dependencies first, then the requested package.

When downloading a package file, fpm tries source URLs in this order:

1. The source URL the package was discovered from (third-party sources).
2. The official Flux stdlib base URL as a fallback.

---

## Package Manifest Format

Both the stdlib and third-party sources use the same `package.json` format:

```json
{
  "pack": "flux-fpm",
  "version": "1.0.0",
  "author": "Karac V. Thweatt",
  "license": "MIT",
  "repository": "https://github.com/kvthweatt/Flux",
  "base_url": "https://raw.githubusercontent.com/kvthweatt/Flux/main/src/stdlib",
  "packages":
  {
    "fpm":
    {
      "version": "1.0.0",
      "entries":
      {
        "main": "fpm.fx"
      }
      "path": "",
      "description": "Flux Package Manager",
      "dependencies":
      {
        "flux-types": ">=1.0.0",
        "flux-memory": ">=1.0.0",
        "flux-allocators": ">=1.0.0",
        "flux-string-utilities": ">=1.0.0",
        "flux-sys": ">=1.0.0",
        "flux-io": ">=1.0.0",
        "flux-ffifio": ">=1.0.0"
      }
    }
  }
}
```

### Version Constraints

Dependencies support the following constraint syntax:

| Syntax | Meaning |
|--------|---------|
| `1.0.0` | Exact version |
| `>1.0.0` | Greater than |
| `>=1.0.0` | Greater than or equal |
| `<2.0.0` | Less than |
| `<=2.0.0` | Less than or equal |
| `>=1.0.0 <2.0.0` | Range (space-separated, all must pass) |