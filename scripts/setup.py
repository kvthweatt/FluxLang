"""
Flux Language - Windows Setup Wizard
scripts/setup.py

Run this from the repo root or directly from the scripts/ folder.
Requires Python 3.10+ (3.13+ recommended) and an internet connection.

What it sets up, in the order the Flux compiler needs it:
  1. Python and the llvmlite package (the compiler runs on Python)
  2. LLVM 21+ (llc, opt, clang, lld-link)
  3. MSYS2 only if the LLVM package has no llc
  4. MSVC (lld-link takes kernel32.lib, ucrt.lib and friends from the Windows SDK)
  5. FLUXC_SRCDIR and PATH
  6. A developer prompt launcher (scripts/flux_dev_prompt.bat)
  7. The Python compiler (v1.5.4), copied from src/compiler/v1.5.4 if missing
  8. Bootstrap: python fxc.py fxc.fx
"""

import os
import sys
import subprocess
import threading
import urllib.request
import tempfile
import winreg
import shutil
import ctypes
import re
from pathlib import Path
from typing import Optional

try:
    import tkinter as tk
    from tkinter import ttk, messagebox, filedialog
except ImportError:
    print("ERROR: tkinter is not available. Please install Python with tkinter support.")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

APP_NAME    = "Flux Systems Programming Language"
APP_VERSION = "2.0.8"

# Direct download URLs
URLS = {
    "python": "https://www.python.org/ftp/python/3.13.13/python-3.13.13-amd64.exe",
    "msys2":  "https://github.com/msys2/msys2-installer/releases/download/2026-03-22/msys2-x86_64-20260322.exe",
    # LLVM installed via winget - no direct URL needed
    # VS is a redirect bootstrapper - opened in browser
    "vs":     "https://c2rsetup.officeapps.live.com/c2r/downloadVS.aspx?sku=community&channel=stable&version=VS18&source=VSLandingPage&cid=2500:fa55c5a4026a4d2d9741802b0c59cdaa",
}

LICENSE_TEXT = """\

                             Flux Compiler License
                             Version 1.0, May 2026

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work.

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

      "Flux Compiler" shall refer to the entirety of this software package,
      including the compiler, standard library, configuration files, examples,
      and tests.
      For the purposes of this License, references to "the Flux Compiler"
      include any Derivative Works defined in Section 1, in whole or in part.


   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, and distribute the Work
      and such Derivative Works in Source or Object form. You may not
      sublicense or re-sell the Flux Compiler.
      For the purposes of this License, 'sell' or 're-sell' includes
      distributing the Flux Compiler as part of any paid product, service,
      subscription, or bundle, regardless of whether the Flux Compiler
      itself is separately itemized or charged for.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

      Copyright [2026] [Karac Von Thweatt]

   Licensed under the Flux Compiler License (based on Apache License 2.0 with modifications).
   This is not the original Apache License. A copy of the original Apache License 2.0
   is available at http://www.apache.org/licenses/LICENSE-2.0.
"""

# Colours / fonts
BG          = "#0f0f0f"
BG2         = "#1a1a1a"
BG3         = "#252525"
ACCENT      = "#c8a96e"        # warm gold
ACCENT2     = "#7eafc8"        # steel blue
FG          = "#e8e8e8"
FG_DIM      = "#888888"
FG_ERR      = "#e05c5c"
FG_OK       = "#6ec87e"
FONT_BODY   = ("Consolas", 10)
FONT_TITLE  = ("Consolas", 22, "bold")
FONT_HEAD   = ("Consolas", 12, "bold")
FONT_SMALL  = ("Consolas", 9)
FONT_MONO   = ("Consolas", 9)

PAD = 20

LLVM_BIN       = Path(r"C:\Program Files\LLVM\bin")
MSYS2_BIN      = Path(r"C:\msys64\mingw64\bin")
MIN_LLVM_MAJOR = 21
LLVMLITE_SPEC  = "llvmlite>=0.43.0"
PY_COMPILER_VERSION = "1.5.4"
# Python compiler files that live in <FLUXC_SRCDIR>\\src\\compiler
PY_COMPILER_CORE = [
    "fast.py", "fasync.py", "fc.py", "fcodegen.py", "fconfig.py", "fdce.py",
    "feffects.py", "ferrors.py", "flexer.py", "flogger.py", "fmacros.py",
    "fmodules.py", "fparser.py", "fpreprocess.py", "ftypesys.py", "fvmcodegen.py",
]
# Python compiler files that live in <FLUXC_SRCDIR>
PY_COMPILER_ENTRY = ["fxc.py"]
VSWHERE_PATHS  = [
    r"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe",
    r"C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe",
]

# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------

def _run(cmd: list[str], timeout: int = 10) -> tuple[bool, str]:
    """Run a subprocess quietly. Returns (success, stdout). Only for quick probes."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode == 0, r.stdout.strip()
    except Exception:
        return False, ""


def _run_long(cmd, log, cwd=None, env=None, shell=False) -> int:
    """Run a long task with no timeout, streaming each output line to log()."""
    p = subprocess.Popen(cmd, cwd=cwd, env=env, shell=shell,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace")
    for line in p.stdout:
        line = line.rstrip()
        if line:
            log("  " + line)
    return p.wait()


def _major(text: str) -> int:
    """First 'version N' / 'N.x' number in a tool's version banner, or 0."""
    m = re.search(r"version\s+(\d+)", text) or re.search(r"(\d+)\.\d+", text)
    return int(m.group(1)) if m else 0


def _tool_candidates(name: str) -> list[str]:
    return [name, str(LLVM_BIN / (name + ".exe")), str(MSYS2_BIN / (name + ".exe"))]


def detect_python() -> Optional[str]:
    """Python as the compiler will see it: the first `python` on PATH."""
    exe = shutil.which("python")
    if not exe:
        return None
    ok, out = _run([exe, "--version"])
    return out if ok else None


def detect_clang() -> Optional[str]:
    for name in ("clang", "clang-21"):
        for cand in _tool_candidates(name):
            ok, out = _run([cand, "--version"])
            if ok:
                return out.splitlines()[0]
    return None


def detect_llc() -> Optional[str]:
    for cand in _tool_candidates("llc"):
        ok, out = _run([cand, "--version"])
        if ok:
            tag = " (MSYS2)" if "msys64" in cand.lower() else ""
            line = next((l.strip() for l in out.splitlines() if "version" in l), out.splitlines()[0])
            return line + tag
    return None


def llvm_outdated(banner: Optional[str]) -> bool:
    return banner is not None and 0 < _major(banner) < MIN_LLVM_MAJOR


def detect_llvmlite() -> Optional[str]:
    """llvmlite version as seen by this interpreter (the one that will run fxc.py)."""
    try:
        import llvmlite
        return llvmlite.__version__
    except ImportError:
        return None


def find_vswhere() -> Optional[str]:
    for vsp in VSWHERE_PATHS:
        if Path(vsp).exists():
            return vsp
    return None


def _vs_install_paths() -> list[str]:
    """Every Visual Studio / Build Tools install root we can find, newest first."""
    roots = []
    vswhere = find_vswhere()
    if vswhere:
        # No -requires filter: component ids differ between VS versions. We check
        # for the toolset on disk instead. -prerelease also lists preview builds.
        ok, out = _run([vswhere, "-all", "-prerelease", "-products", "*",
                        "-property", "installationPath"], timeout=30)
        if ok:
            roots += [l.strip() for l in out.splitlines() if l.strip()]
    # Fallback: scan the standard locations in case vswhere is missing or silent
    for pf in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
        if not pf:
            continue
        vs = Path(pf) / "Microsoft Visual Studio"
        if vs.is_dir():
            for ver in sorted(vs.iterdir(), reverse=True):
                if ver.is_dir():
                    roots += [str(ed) for ed in sorted(ver.iterdir()) if ed.is_dir()]
    seen, out = set(), []
    for r in roots:
        if r.lower() not in seen:
            seen.add(r.lower())
            out.append(r)
    return out


def _has_toolset(root: str) -> bool:
    msvc = Path(root) / "VC" / "Tools" / "MSVC"
    return msvc.is_dir() and any(msvc.iterdir())


def detect_msvc() -> Optional[str]:
    """Return a description string if the MSVC x64 toolset is installed."""
    if os.environ.get("VCINSTALLDIR"):
        return f"Found via VCINSTALLDIR: {os.environ['VCINSTALLDIR']}"
    for root in _vs_install_paths():
        if _has_toolset(root):
            return f"Visual Studio at {root}"
    return None


def find_vcvars() -> Optional[str]:
    """Path to vcvars64.bat, which sets LIB/INCLUDE so lld-link can find the Windows SDK."""
    for root in _vs_install_paths():
        cand = Path(root) / "VC" / "Auxiliary" / "Build" / "vcvars64.bat"
        if cand.exists():
            return str(cand)
    return None


def refresh_process_path():
    """Pick up PATH changes made by installers that ran during this session."""
    parts = []
    for hive, sub in ((winreg.HKEY_LOCAL_MACHINE,
                       r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"),
                      (winreg.HKEY_CURRENT_USER, r"Environment")):
        try:
            with winreg.OpenKey(hive, sub) as k:
                val, _ = winreg.QueryValueEx(k, "Path")
                parts.append(os.path.expandvars(val))
        except OSError:
            pass
    parts.append(os.environ.get("PATH", ""))
    for extra in (LLVM_BIN, MSYS2_BIN):
        if extra.exists():
            parts.append(str(extra))
    seen, out = set(), []
    for chunk in ";".join(parts).split(";"):
        key = chunk.strip().lower()
        if key and key not in seen:
            seen.add(key)
            out.append(chunk.strip())
    os.environ["PATH"] = ";".join(out)


def detect_fluxc_srcdir() -> str:
    """Guess the repo root from this script's location."""
    here = Path(__file__).resolve()
    # If we're in scripts/, go up one level
    root = here.parent.parent if here.parent.name.lower() == "scripts" else here.parent
    return str(root)


def missing_py_compiler(srcdir: str) -> list[str]:
    """Relative paths of Python compiler files that are not installed under srcdir."""
    root = Path(srcdir)
    miss = [f"src\\compiler\\{n}" for n in PY_COMPILER_CORE
            if not (root / "src" / "compiler" / n).is_file()]
    miss += [n for n in PY_COMPILER_ENTRY if not (root / n).is_file()]
    return miss


def py_compiler_bundle(srcdir: str) -> tuple[Path, Path]:
    base = Path(srcdir) / "src" / "compiler" / f"v{PY_COMPILER_VERSION}"
    return base / "core", base / "entrypoint"


def valid_srcdir(path: str) -> bool:
    """FLUXC_SRCDIR must be an existing directory (this release ships no Python compiler)."""
    return Path(path).is_dir()

# ---------------------------------------------------------------------------
# Download helper
# ---------------------------------------------------------------------------

def download_file(url: str, dest: Path, progress_cb=None) -> Path:
    """Download *url* to *dest*, calling progress_cb(fraction) periodically."""
    def reporthook(block_num, block_size, total_size):
        if progress_cb and total_size > 0:
            fraction = min(1.0, block_num * block_size / total_size)
            progress_cb(fraction)
    urllib.request.urlretrieve(url, dest, reporthook)
    if progress_cb:
        progress_cb(1.0)
    return dest

# ---------------------------------------------------------------------------
# Wizard pages (each is a frame factory)
# ---------------------------------------------------------------------------

class WizardApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"{APP_NAME} Setup")
        self.configure(bg=BG)
        self.resizable(False, False)
        self.geometry("760x720")
        self.minsize(760, 640)
        self._center()

        # Shared state
        self.state = {
            "agree":          tk.BooleanVar(value=False),
            "install_python": tk.BooleanVar(value=True),
            "install_llvm":   tk.BooleanVar(value=True),
            "install_msys2":  tk.BooleanVar(value=False),
            "install_msvc":   tk.BooleanVar(value=False),
            "install_pip":    tk.BooleanVar(value=True),
            "set_env":        tk.BooleanVar(value=True),
            "make_launcher":  tk.BooleanVar(value=True),
            "have_pycompiler": tk.BooleanVar(value=False),
            "bootstrap":      tk.BooleanVar(value=True),
            "py_removed":     False,   # True once the copied Python compiler files were removed
            "fluxc_srcdir":   tk.StringVar(value=detect_fluxc_srcdir()),
            # detection results (filled in on components page)
            "det": {},
        }

        self._pages: list[tk.Frame] = []
        self._idx = 0

        # Header bar (persistent)
        self._build_header()

        # Nav bar (persistent). Packed before the page container so the
        # container cannot push the Back/Next buttons out of the window.
        self._build_nav()

        # Page container
        self._container = tk.Frame(self, bg=BG)
        self._container.pack(fill="both", expand=True, padx=0, pady=0)

        self._pages = [
            WelcomePage,
            LicensePage,
            ComponentsPage,
            MSVCPage,
            InstallPage,
            FinishPage,
        ]
        self._show_page(0)

    def _center(self):
        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        w, h = 760, min(720, sh - 80)   # stay inside small screens and the taskbar
        self.geometry(f"{w}x{h}+{(sw-w)//2}+{(sh-h)//2}")

    def _build_header(self):
        hdr = tk.Frame(self, bg=BG2, height=64)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)

        # Vertical accent bar
        accent_bar = tk.Frame(hdr, bg=ACCENT, width=4)
        accent_bar.pack(side="left", fill="y")

        inner = tk.Frame(hdr, bg=BG2)
        inner.pack(side="left", fill="both", expand=True, padx=16, pady=10)

        tk.Label(inner, text=APP_NAME, font=FONT_TITLE,
                 bg=BG2, fg=ACCENT).pack(anchor="w")
        self._subtitle_var = tk.StringVar(value="Setup Wizard")
        tk.Label(inner, textvariable=self._subtitle_var, font=FONT_SMALL,
                 bg=BG2, fg=FG_DIM).pack(anchor="w")

    def _build_nav(self):
        nav = tk.Frame(self, bg=BG2, height=52)
        nav.pack(fill="x", side="bottom")
        nav.pack_propagate(False)

        sep = tk.Frame(nav, bg=ACCENT, height=1)
        sep.pack(fill="x", side="top")

        btn_frame = tk.Frame(nav, bg=BG2)
        btn_frame.pack(side="right", padx=PAD, pady=10)

        self._btn_back = self._nav_btn(btn_frame, "<- Back", self._go_back)
        self._btn_back.pack(side="left", padx=(0, 8))

        self._btn_next = self._nav_btn(btn_frame, "Next ->", self._go_next, primary=True)
        self._btn_next.pack(side="left")

        cancel = self._nav_btn(btn_frame, "Cancel", self.destroy)
        cancel.pack(side="left", padx=(16, 0))

    def _nav_btn(self, parent, text, cmd, primary=False):
        bg   = ACCENT  if primary else BG3
        fg   = "#0f0f0f" if primary else FG
        abg  = "#e0c07e" if primary else "#333333"
        b = tk.Button(parent, text=text, command=cmd,
                      bg=bg, fg=fg, activebackground=abg, activeforeground=fg,
                      font=FONT_BODY, relief="flat", bd=0,
                      padx=14, pady=6, cursor="hand2")
        return b

    def _show_page(self, idx: int):
        for w in self._container.winfo_children():
            w.destroy()
        self._idx = idx
        page_cls = self._pages[idx]
        page = page_cls(self._container, self)
        page.pack(fill="both", expand=True)

        # Update subtitle
        self._subtitle_var.set(page.SUBTITLE if hasattr(page, "SUBTITLE") else "")

        # Nav state
        self._btn_back.config(state="normal" if idx > 0 else "disabled")
        last = idx == len(self._pages) - 1
        self._btn_next.config(
            text="Finish" if last else "Next ->",
            command=self.destroy if last else self._go_next
        )

    def _go_next(self):
        page = self._container.winfo_children()[0]
        if hasattr(page, "validate") and not page.validate():
            return
        if hasattr(page, "on_leave"):
            page.on_leave()
        # Skip MSVCPage if MSVC already found and user okayed
        next_idx = self._idx + 1
        if next_idx < len(self._pages):
            self._show_page(next_idx)

    def _go_back(self):
        if self._idx > 0:
            self._show_page(self._idx - 1)

# ---------------------------------------------------------------------------
# Individual pages
# ---------------------------------------------------------------------------

def _scrollable_text(parent, text, height=12, **kwargs) -> tk.Text:
    frame = tk.Frame(parent, bg=BG3)
    frame.pack(fill="both", expand=True, **kwargs)
    sb = ttk.Scrollbar(frame)
    sb.pack(side="right", fill="y")
    t = tk.Text(frame, wrap="word", height=height,
                bg=BG3, fg=FG, font=FONT_MONO, relief="flat",
                yscrollcommand=sb.set, state="normal",
                selectbackground=ACCENT, selectforeground="#0f0f0f",
                insertbackground=ACCENT)
    t.pack(side="left", fill="both", expand=True)
    sb.config(command=t.yview)
    t.insert("end", text)
    t.config(state="disabled")
    return t


def _section(parent, title):
    tk.Label(parent, text=title, font=FONT_HEAD,
             bg=BG, fg=ACCENT).pack(anchor="w", pady=(0, 6))


def _status_dot(parent, detected: bool) -> tk.Label:
    color = FG_OK if detected else FG_ERR
    sym   = "●" if detected else "○"
    return tk.Label(parent, text=sym, font=FONT_BODY, bg=BG, fg=color)


class WelcomePage(tk.Frame):
    SUBTITLE = ""

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app

        tk.Label(self, text="Welcome to the Flux\nLanguage Installer",
                 font=("Consolas", 18, "bold"), bg=BG, fg=FG,
                 justify="left").pack(anchor="w", padx=PAD, pady=(PAD, 8))

        tk.Label(self,
                 text="This wizard will set up everything you need to\n"
                      "compile and run Flux programs on Windows.",
                 font=FONT_BODY, bg=BG, fg=FG_DIM, justify="left"
                 ).pack(anchor="w", padx=PAD, pady=(0, PAD))

        # Info box
        box = tk.Frame(self, bg=BG2)
        box.pack(fill="x", padx=PAD, pady=(0, PAD))
        tk.Frame(box, bg=ACCENT, width=4).pack(side="left", fill="y")
        inner = tk.Frame(box, bg=BG2)
        inner.pack(fill="both", padx=12, pady=12)

        items = [
            ("Python 3.10+",        "Runs the Flux compiler"),
            ("LLVM & Clang v21+",   "llc, opt and lld-link"),
            ("MSVC / Build Tools",  "Windows SDK libraries for linking"),
            ("llvmlite",            "Python -> LLVM IR bindings"),
            ("FLUXC_SRCDIR",        "Environment variable pointing to this repo"),
            ("Python compiler",     f"v{PY_COMPILER_VERSION}, copied in if missing, then bootstrapped"),
        ]
        for name, desc in items:
            row = tk.Frame(inner, bg=BG2)
            row.pack(anchor="w", pady=1)
            tk.Label(row, text=f"  {name:<22}", font=FONT_BODY,
                     bg=BG2, fg=ACCENT).pack(side="left")
            tk.Label(row, text=desc, font=FONT_BODY,
                     bg=BG2, fg=FG_DIM).pack(side="left")

        tk.Label(self,
                 text="Click Next to review the license agreement.",
                 font=FONT_SMALL, bg=BG, fg=FG_DIM
                 ).pack(anchor="w", padx=PAD, pady=(PAD, 0))


class LicensePage(tk.Frame):
    SUBTITLE = ""

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app

        tk.Label(self, text="License Agreement", font=FONT_HEAD,
                 bg=BG, fg=FG).pack(anchor="w", padx=PAD, pady=(PAD, 4))
        tk.Label(self, text="Please read the following agreement carefully.",
                 font=FONT_SMALL, bg=BG, fg=FG_DIM).pack(anchor="w", padx=PAD, pady=(0, 8))

        _scrollable_text(self, LICENSE_TEXT, height=14, padx=PAD)

        agree_frame = tk.Frame(self, bg=BG)
        agree_frame.pack(anchor="w", padx=PAD, pady=(10, 0))

        cb = tk.Checkbutton(agree_frame,
                             text="I have read and agree to the license agreement",
                             variable=app.state["agree"],
                             bg=BG, fg=FG, selectcolor=BG3,
                             activebackground=BG, activeforeground=ACCENT,
                             font=FONT_BODY, cursor="hand2")
        cb.pack(side="left")

    def validate(self) -> bool:
        if not self.app.state["agree"].get():
            messagebox.showwarning("License",
                "You must accept the license agreement to continue.",
                parent=self.app)
            return False
        return True


class ComponentsPage(tk.Frame):
    SUBTITLE = ""

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app

        tk.Label(self, text="Components", font=FONT_HEAD,
                 bg=BG, fg=FG).pack(anchor="w", padx=PAD, pady=(PAD, 2))
        tk.Label(self,
                 text="Detected components are shown. Uncheck anything you want to manage manually.",
                 font=FONT_SMALL, bg=BG, fg=FG_DIM, wraplength=660, justify="left"
                 ).pack(anchor="w", padx=PAD, pady=(0, 10))

        # Run detection
        det = app.state["det"]
        det["python"]    = detect_python()
        det["clang"]     = detect_clang()
        det["llc"]       = detect_llc()
        det["llvmlite"]  = detect_llvmlite()
        det["msvc"]      = detect_msvc()
        if llvm_outdated(det["clang"]) or llvm_outdated(det["llc"]):
            det["clang"] = det["llc"] = None   # too old: reinstall LLVM

        # Pre-tick install boxes based on what's missing
        app.state["install_python"].set(det["python"] is None)
        app.state["install_llvm"].set(det["clang"] is None or det["llc"] is None)
        app.state["install_msys2"].set(False)   # decided after the LLVM step, only if llc is still missing
        app.state["install_pip"].set(det["llvmlite"] is None)
        # MSVC handled on its own page

        grid = tk.Frame(self, bg=BG)
        grid.pack(fill="x", padx=PAD)

        components = [
            ("Python 3.10+",    "install_python", det["python"],
             "Required to run the compiler"),
            ("LLVM + Clang v21+","install_llvm",   det["clang"],
             "Compiles IR; also provides lld-link"),
            ("MSYS2 (llc)",     "install_msys2",  det["llc"],
             "Used only if the LLVM package has no llc"),
            ("llvmlite (pip)", "install_pip", det["llvmlite"],
             "Python <-> LLVM bindings"),
        ]

        for i, (label, key, detected, hint) in enumerate(components):
            row = tk.Frame(grid, bg=BG2)
            row.pack(fill="x", pady=3)
            tk.Frame(row, bg=ACCENT if not detected else FG_DIM, width=3).pack(side="left", fill="y")

            inner = tk.Frame(row, bg=BG2)
            inner.pack(fill="both", expand=True, padx=10, pady=8)

            top = tk.Frame(inner, bg=BG2)
            top.pack(fill="x")

            _status_dot(top, detected is not None).pack(side="left")
            tk.Label(top, text=f"  {label}", font=FONT_BODY,
                     bg=BG2, fg=FG).pack(side="left")

            if detected:
                tk.Label(top, text=f"  ✓  {detected[:60]}",
                         font=FONT_SMALL, bg=BG2, fg=FG_OK).pack(side="left")
                tk.Label(inner, text=hint, font=FONT_SMALL,
                         bg=BG2, fg=FG_DIM).pack(anchor="w", padx=14)
            else:
                tk.Label(top, text="  Not found - will install",
                         font=FONT_SMALL, bg=BG2, fg=FG_ERR).pack(side="left")

                cb_row = tk.Frame(inner, bg=BG2)
                cb_row.pack(anchor="w", padx=10)
                tk.Checkbutton(cb_row, text="Install automatically",
                               variable=app.state[key],
                               bg=BG2, fg=FG, selectcolor=BG3,
                               activebackground=BG2, activeforeground=ACCENT,
                               font=FONT_SMALL, cursor="hand2").pack(side="left")

        # FLUXC_SRCDIR
        tk.Label(self, text="FLUXC_SRCDIR", font=FONT_HEAD,
                 bg=BG, fg=FG).pack(anchor="w", padx=PAD, pady=(14, 2))
        row = tk.Frame(self, bg=BG)
        row.pack(fill="x", padx=PAD)
        entry = tk.Entry(row, textvariable=app.state["fluxc_srcdir"],
                         font=FONT_BODY, bg=BG3, fg=FG, insertbackground=ACCENT,
                         relief="flat", width=52)
        entry.pack(side="left", ipady=5, padx=(0, 8))

        def browse():
            d = filedialog.askdirectory(title="Select Flux repo root", parent=self.app)
            if d:
                app.state["fluxc_srcdir"].set(d)

        tk.Button(row, text="Browse…", command=browse,
                  bg=BG3, fg=FG, activebackground="#333", font=FONT_SMALL,
                  relief="flat", padx=10, pady=4, cursor="hand2").pack(side="left")

        tk.Checkbutton(self,
                       text="Set FLUXC_SRCDIR as a user environment variable",
                       variable=app.state["set_env"],
                       bg=BG, fg=FG, selectcolor=BG3,
                       activebackground=BG, activeforeground=ACCENT,
                       font=FONT_SMALL, cursor="hand2").pack(anchor="w", padx=PAD, pady=(6, 0))
        # Python compiler question
        have = not missing_py_compiler(app.state["fluxc_srcdir"].get())
        app.state["have_pycompiler"].set(have)
        tk.Label(self, text=f"Do you already have the Python version of Flux v{PY_COMPILER_VERSION} installed?",
                 font=FONT_BODY, bg=BG, fg=FG).pack(anchor="w", padx=PAD, pady=(14, 0))
        rb = tk.Frame(self, bg=BG)
        rb.pack(anchor="w", padx=PAD)
        for text, val in (("Yes", True),
                          (f"No - copy it from src\\compiler\\v{PY_COMPILER_VERSION}", False)):
            tk.Radiobutton(rb, text=text, variable=app.state["have_pycompiler"], value=val,
                           bg=BG, fg=FG, selectcolor=BG3, activebackground=BG,
                           activeforeground=ACCENT, font=FONT_SMALL,
                           cursor="hand2").pack(side="left", padx=(0, 16))
        py_lbl = tk.Label(self, text="", font=FONT_SMALL, bg=BG)
        py_lbl.pack(anchor="w", padx=PAD)

        def refresh_py(*_):
            miss = missing_py_compiler(app.state["fluxc_srcdir"].get())
            app.state["have_pycompiler"].set(not miss)
            py_lbl.config(text="Detected: all compiler files present." if not miss
                          else f"Detected: {len(miss)} compiler file(s) missing.",
                          fg=FG_OK if not miss else FG_ERR)
        refresh_py()
        app.state["fluxc_srcdir"].trace_add("write", refresh_py)

        tk.Checkbutton(self,
                       text="Create scripts\\flux_dev_prompt.bat (a prompt with the MSVC environment loaded)",
                       variable=app.state["make_launcher"],
                       bg=BG, fg=FG, selectcolor=BG3,
                       activebackground=BG, activeforeground=ACCENT,
                       font=FONT_SMALL, cursor="hand2").pack(anchor="w", padx=PAD)
        tk.Checkbutton(self,
                       text="Bootstrap the compiler when done (python fxc.py fxc.fx)",
                       variable=app.state["bootstrap"],
                       bg=BG, fg=FG, selectcolor=BG3,
                       activebackground=BG, activeforeground=ACCENT,
                       font=FONT_SMALL, cursor="hand2").pack(anchor="w", padx=PAD)


class MSVCPage(tk.Frame):
    SUBTITLE = ""

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app

        det_msvc = app.state["det"].get("msvc")

        tk.Label(self, text="Visual Studio / MSVC", font=FONT_HEAD,
                 bg=BG, fg=FG).pack(anchor="w", padx=PAD, pady=(PAD, 4))

        if det_msvc:
            # Already present
            status_frame = tk.Frame(self, bg=BG2)
            status_frame.pack(fill="x", padx=PAD, pady=(0, 12))
            tk.Frame(status_frame, bg=FG_OK, width=4).pack(side="left", fill="y")
            inner = tk.Frame(status_frame, bg=BG2)
            inner.pack(fill="both", padx=12, pady=12)
            tk.Label(inner, text="● MSVC installation detected",
                     font=FONT_BODY, bg=BG2, fg=FG_OK).pack(anchor="w")
            tk.Label(inner, text=det_msvc, font=FONT_SMALL,
                     bg=BG2, fg=FG_DIM).pack(anchor="w")

            tk.Label(self,
                     text="An existing Visual Studio or Build Tools installation was found.\n"
                          "You can skip this step, or customize your installation.",
                     font=FONT_BODY, bg=BG, fg=FG, wraplength=660, justify="left"
                     ).pack(anchor="w", padx=PAD, pady=(0, 16))

            btn_row = tk.Frame(self, bg=BG)
            btn_row.pack(anchor="w", padx=PAD)

            tk.Button(btn_row, text="Skip (use existing)",
                      command=lambda: app._go_next(),
                      bg=BG3, fg=FG, activebackground="#333",
                      font=FONT_BODY, relief="flat", padx=14, pady=6,
                      cursor="hand2").pack(side="left", padx=(0, 10))

            tk.Button(btn_row, text="Open VS Installer to customize",
                      command=self._open_vs_installer,
                      bg=ACCENT2, fg="#0f0f0f", activebackground="#a0cce0",
                      font=FONT_BODY, relief="flat", padx=14, pady=6,
                      cursor="hand2").pack(side="left")

        else:
            # Not found
            status_frame = tk.Frame(self, bg=BG2)
            status_frame.pack(fill="x", padx=PAD, pady=(0, 12))
            tk.Frame(status_frame, bg=FG_ERR, width=4).pack(side="left", fill="y")
            inner = tk.Frame(status_frame, bg=BG2)
            inner.pack(fill="both", padx=12, pady=12)
            tk.Label(inner, text="○ No MSVC installation detected",
                     font=FONT_BODY, bg=BG2, fg=FG_ERR).pack(anchor="w")
            tk.Label(inner,
                     text="MSVC provides the linker (link.exe) and Windows SDK required to produce executables.",
                     font=FONT_SMALL, bg=BG2, fg=FG_DIM, wraplength=600, justify="left"
                     ).pack(anchor="w")

            tk.Label(self,
                     text="Choose an installation option below.\n"
                          "The installer will download and launch the appropriate setup.",
                     font=FONT_BODY, bg=BG, fg=FG, wraplength=660, justify="left"
                     ).pack(anchor="w", padx=PAD, pady=(0, 12))

            opts = tk.Frame(self, bg=BG)
            opts.pack(fill="x", padx=PAD)

            self._msvc_choice = tk.StringVar(value="build_tools")

            choices = [
                ("build_tools",  "Visual Studio Build Tools (recommended - lightweight)"),
                ("vs_community", "Visual Studio Community (full IDE)"),
                ("skip",         "Skip - I will configure MSVC manually"),
            ]
            for val, label in choices:
                rb = tk.Radiobutton(opts, text=label,
                                    variable=self._msvc_choice, value=val,
                                    bg=BG, fg=FG, selectcolor=BG3,
                                    activebackground=BG, activeforeground=ACCENT,
                                    font=FONT_BODY, cursor="hand2")
                rb.pack(anchor="w", pady=3)

            app.state["install_msvc"].set(True)

            note = (
                "Note: The VS installer is interactive and runs separately.\n"
                "When prompted, select the 'Desktop development with C++' workload\n"
                "or add MSVC v143 and the Windows SDK under Individual Components."
            )
            tk.Label(self, text=note, font=FONT_SMALL,
                     bg=BG, fg=FG_DIM, justify="left", wraplength=660
                     ).pack(anchor="w", padx=PAD, pady=(14, 0))

    def _open_vs_installer(self):
        vs_installer = r"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe"
        if Path(vs_installer).exists():
            subprocess.Popen([vs_installer])
        else:
            messagebox.showinfo("VS Installer",
                "Could not find the Visual Studio Installer at the expected path.\n"
                "Please open it manually from the Start Menu.",
                parent=self.app)


class InstallPage(tk.Frame):
    SUBTITLE = ""

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app
        self._done = False
        self._copied: list[Path] = []      # exactly the files this installer copied
        self._backups: dict[Path, Path] = {}   # copied path -> backup of a file it overwrote
        self._bootstrapped = False

        tk.Label(self, text="Installing Components",
                 font=FONT_HEAD, bg=BG, fg=FG).pack(anchor="w", padx=PAD, pady=(PAD, 4))
        tk.Label(self,
                 text="Please wait while the selected components are downloaded and installed.",
                 font=FONT_SMALL, bg=BG, fg=FG_DIM).pack(anchor="w", padx=PAD, pady=(0, 10))

        # Overall bar
        self._overall_label = tk.Label(self, text="Starting...",
                                       font=FONT_BODY, bg=BG, fg=FG)
        self._overall_label.pack(anchor="w", padx=PAD)

        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Flux.Horizontal.TProgressbar",
                         troughcolor=BG3, background=ACCENT,
                         darkcolor=ACCENT, lightcolor=ACCENT, bordercolor=BG3)

        self._overall_bar = ttk.Progressbar(self, style="Flux.Horizontal.TProgressbar",
                                             length=660, mode="determinate")
        self._overall_bar.pack(padx=PAD, pady=(4, 10))

        # Step bar
        self._step_label = tk.Label(self, text="",
                                    font=FONT_SMALL, bg=BG, fg=FG_DIM)
        self._step_label.pack(anchor="w", padx=PAD)

        self._step_bar = ttk.Progressbar(self, style="Flux.Horizontal.TProgressbar",
                                          length=660, mode="determinate")
        self._step_bar.pack(padx=PAD, pady=(2, 8))

        # Log
        log_frame = tk.Frame(self, bg=BG3)
        log_frame.pack(fill="both", expand=True, padx=PAD, pady=(0, 4))
        sb = ttk.Scrollbar(log_frame)
        sb.pack(side="right", fill="y")
        self._log = tk.Text(log_frame, height=8, bg=BG3, fg=FG_DIM,
                            font=FONT_MONO, relief="flat", state="disabled",
                            yscrollcommand=sb.set)
        self._log.pack(side="left", fill="both", expand=True)
        sb.config(command=self._log.yview)

        # Disable nav during install
        app._btn_next.config(state="disabled")
        app._btn_back.config(state="disabled")

        # Start install thread
        t = threading.Thread(target=self._run_install, daemon=True)
        t.start()

    def _log_msg(self, msg: str, color=FG_DIM):
        def _do():
            self._log.config(state="normal")
            self._log.insert("end", msg + "\n")
            self._log.see("end")
            self._log.config(state="disabled")
        self.after(0, _do)

    def _set_overall(self, fraction: float, label: str):
        def _do():
            self._overall_bar["value"] = fraction * 100
            self._overall_label.config(text=label)
        self.after(0, _do)

    def _set_step(self, fraction: float, label: str):
        def _do():
            self._step_bar["value"] = fraction * 100
            self._step_label.config(text=label)
        self.after(0, _do)

    def _run_install(self):
        st = self.app.state
        steps = []

        if st["install_python"].get():
            steps.append(("Python",           self._install_python))
        if st["install_llvm"].get():
            steps.append(("LLVM + Clang",     self._install_llvm))
        # MSYS2 is a fallback: it runs only if llc is still missing after the LLVM step
        steps.append(("MSYS2 (llc, if needed)", self._install_msys2))
        if st["install_msvc"].get():
            steps.append(("VS Build Tools",   self._install_msvc))
        if st["install_pip"].get():
            steps.append(("llvmlite (pip)",   self._install_llvmlite))
        if st["set_env"].get():
            steps.append(("Environment vars", self._set_env_vars))
        if st["make_launcher"].get():
            steps.append(("Developer prompt", self._make_launcher))
        steps.append(("Python compiler", self._install_py_compiler))
        if st["bootstrap"].get():
            steps.append(("Bootstrap compiler", self._bootstrap))
            steps.append(("Remove copied Python files", self._remove_copied))

        total = max(len(steps), 1)
        for i, (name, fn) in enumerate(steps):
            self._set_overall(i / total, f"Step {i+1}/{total}: {name}")
            self._log_msg(f"\n[{name}]")
            try:
                fn()
                self._log_msg(f"  ✓ Done.", FG_OK)
            except Exception as e:
                self._log_msg(f"  ✗ Error: {e}", FG_ERR)

        self._set_overall(1.0, "Installation complete.")
        self._set_step(1.0, "")
        self._done = True
        self.after(0, lambda: self.app._btn_next.config(state="normal"))
        self._log_msg("\nAll steps finished. Click Next -> to complete setup.")

    # ── Individual step implementations ──────────────────────────────────────

    def _download_and_run(self, url: str, label: str, args: list[str] = None):
        self._log_msg(f"  Downloading {label}…")
        tmp = Path(tempfile.mkdtemp()) / Path(url).name
        def progress(f):
            self._set_step(f * 0.8, f"Downloading {label}: {int(f*100)}%")
        download_file(url, tmp, progress)
        self._log_msg(f"  Running {label} installer…")
        self._set_step(0.9, f"Running {label} installer…")
        cmd = [str(tmp)] + (args or [])
        subprocess.run(cmd, check=True)
        self._set_step(1.0, "")

    def _install_python(self):
        self._download_and_run(URLS["python"], "Python 3.13",
                               ["/quiet", "InstallAllUsers=0", "PrependPath=1"])
        refresh_process_path()

    def _install_llvm(self):
        self._log_msg("  Running: winget install LLVM.LLVM")
        self._set_step(0.1, "winget install LLVM.LLVM...")
        rc = _run_long(["winget", "install", "LLVM.LLVM", "--accept-source-agreements",
                        "--accept-package-agreements"], self._log_msg)
        self._set_step(1.0, "")
        refresh_process_path()
        # winget returns non-zero when the package is already installed; judge by the tool
        if detect_clang() is None:
            raise RuntimeError(f"clang not found after winget (exit code {rc}) - see log above")
        if LLVM_BIN.exists():
            self._append_user_path(str(LLVM_BIN))

    def _install_msys2(self):
        refresh_process_path()
        banner = detect_llc()
        if banner and not llvm_outdated(banner):
            self._log_msg(f"  llc already available ({banner}) - skipping MSYS2.")
            return
        if llvm_outdated(banner):
            self._log_msg(f"  Found {banner}, which is older than LLVM {MIN_LLVM_MAJOR}.")
        self._log_msg("  llc not found in the LLVM package, installing it through MSYS2.")
        msys2_bash = Path(r"C:\msys64\usr\bin\bash.exe")
        if not msys2_bash.exists():
            self._download_and_run(URLS["msys2"], "MSYS2",
                                   ["install", "--root", r"C:\msys64",
                                    "--confirm-command", "--accept-messages"])
        if not msys2_bash.exists():
            raise RuntimeError("MSYS2 bash not found at C:\\msys64 - install llvm with pacman manually")
        rc = _run_long([str(msys2_bash), "--login", "-c",
                        "pacman -S --noconfirm mingw-w64-x86_64-llvm"], self._log_msg)
        if rc != 0:
            raise RuntimeError(f"pacman exited with code {rc}")
        self._append_user_path(str(MSYS2_BIN))
        refresh_process_path()

    def _install_msvc(self):
        # VS cannot be silently installed - open the browser bootstrapper
        self._log_msg("  Opening Visual Studio download page in your browser...")
        self._log_msg("  Install the Desktop development with C++ workload,")
        self._log_msg("  or add MSVC v143 + Windows SDK under Individual Components.")
        import webbrowser
        webbrowser.open(URLS["vs"])
        self._set_step(1.0, "")

    def _install_llvmlite(self):
        py = shutil.which("python") or sys.executable
        self._log_msg(f"  Running: {py} -m pip install {LLVMLITE_SPEC}")
        self._set_step(0.3, f"pip install {LLVMLITE_SPEC}")
        rc = _run_long([py, "-m", "pip", "install", LLVMLITE_SPEC], self._log_msg)
        self._set_step(1.0, "")
        if rc != 0:
            raise RuntimeError("pip install failed - see log above")

    def _set_env_vars(self):
        srcdir = self.app.state["fluxc_srcdir"].get()
        if not valid_srcdir(srcdir):
            raise RuntimeError(f"{srcdir} is not a directory - choose the Flux root")
        self._log_msg(f"  Setting FLUXC_SRCDIR = {srcdir}")
        self._set_user_env("FLUXC_SRCDIR", srcdir)
        os.environ["FLUXC_SRCDIR"] = srcdir

    def _make_launcher(self):
        """Write scripts\\flux_dev_prompt.bat: cmd with vcvars64 loaded, in the repo root."""
        srcdir = Path(self.app.state["fluxc_srcdir"].get())
        vcvars = find_vcvars()
        if not vcvars:
            self._log_msg("  Visual Studio C++ tools not found - no launcher written.")
            self._log_msg("  Install them, then open 'x64 Native Tools Command Prompt for VS'.")
            return
        out = srcdir / "scripts" / "flux_dev_prompt.bat"
        out.parent.mkdir(exist_ok=True)
        out.write_text(
            "@echo off\r\n"
            f'call "{vcvars}"\r\n'
            f'set "FLUXC_SRCDIR={srcdir}"\r\n'
            f'cd /d "{srcdir}"\r\n'
            "cmd /k\r\n", encoding="ascii")
        self._log_msg(f"  Wrote {out}")

    def _install_py_compiler(self):
        srcdir = self.app.state["fluxc_srcdir"].get()
        if not self.app.state["have_pycompiler"].get():
            core, entry = py_compiler_bundle(srcdir)
            for d in (core, entry):
                if not d.is_dir():
                    raise RuntimeError(f"{d} not found - cannot install the Python compiler")
            dst_core = Path(srcdir) / "src" / "compiler"
            dst_core.mkdir(parents=True, exist_ok=True)
            for src, dst in ((core, dst_core), (entry, Path(srcdir))):
                for f in sorted(src.iterdir()):
                    if f.is_file():
                        target = dst / f.name
                        if target.exists():
                            bak = Path(tempfile.mkdtemp()) / f.name
                            shutil.copy2(target, bak)
                            self._backups[target] = bak
                        shutil.copy2(f, target)
                        self._copied.append(target)
                        self._log_msg(f"  Copied {f.name} -> {dst}")
        miss = missing_py_compiler(srcdir)
        if miss:
            raise RuntimeError("Python compiler incomplete, missing: " + ", ".join(miss))
        self._log_msg(f"  Python compiler v{PY_COMPILER_VERSION} is complete.")

    def _bootstrap(self):
        """python fxc.py fxc.fx, run inside the MSVC environment so lld-link finds the SDK."""
        srcdir = self.app.state["fluxc_srcdir"].get()
        miss = missing_py_compiler(srcdir)
        if miss or not (Path(srcdir) / "fxc.fx").is_file():
            raise RuntimeError("cannot bootstrap: Python compiler or fxc.fx is missing")
        refresh_process_path()
        ok, _ = _run(["python", "-c", "import llvmlite"])
        if not ok:
            raise RuntimeError("llvmlite is not installed for the python on PATH")
        vcvars = find_vcvars()
        if vcvars:
            cmd = f'call "{vcvars}" >nul && python fxc.py fxc.fx'
        else:
            self._log_msg("  No vcvars64.bat found, building without the MSVC environment.")
            cmd = "python fxc.py fxc.fx"
        env = dict(os.environ, FLUXC_SRCDIR=srcdir, PYTHONDONTWRITEBYTECODE="1")
        prefix = f'call "{vcvars}" >nul && ' if vcvars else ""
        stage1 = Path(srcdir) / "build" / "fxc" / "fxc.exe"
        stage2 = Path(srcdir) / "build" / "fxc2" / "fxc2.exe"

        self._log_msg("  Stage 1: python fxc.py fxc.fx")
        self._set_step(0.1, "Stage 1: python fxc.py fxc.fx (a few minutes)")
        rc = _run_long(["cmd", "/c", prefix + "python fxc.py fxc.fx"],
                       self._log_msg, cwd=srcdir, env=env)
        if rc != 0 or not stage1.exists():
            raise RuntimeError(f"stage 1 failed (exit code {rc}); Python compiler files were kept")
        self._log_msg(f"  Built {stage1}")

        self._log_msg("  Stage 2: build\\fxc\\fxc.exe fxc.fx -o fxc2.exe")
        self._set_step(0.6, "Stage 2: recompiling with build\\fxc\\fxc.exe")
        rc = _run_long(["cmd", "/c", prefix + r"build\fxc\fxc.exe fxc.fx -o fxc2.exe"],
                       self._log_msg, cwd=srcdir, env=env)
        if rc != 0 or not stage2.exists():
            raise RuntimeError(f"stage 2 failed (exit code {rc}); Python compiler files were kept")
        self._log_msg(f"  Built {stage2}")
        self._set_step(1.0, "")
        self._bootstrapped = True

    def _remove_copied(self):
        """Delete only the files this run copied, and only after a successful bootstrap."""
        if not self._copied:
            self._log_msg("  Nothing was copied by this installer - nothing to remove.")
            return
        if not self._bootstrapped:
            self._log_msg("  Bootstrap did not succeed - keeping the copied files.")
            return
        for f in self._copied:
            try:
                bak = self._backups.get(f)
                if bak is not None:
                    shutil.copy2(bak, f)       # we overwrote one of the user's files: put it back
                    self._log_msg(f"  Restored your original {f.name}")
                else:
                    f.unlink()
                    self._log_msg(f"  Removed {f}")
            except FileNotFoundError:
                pass
            except OSError as e:
                self._log_msg(f"  Could not clean up {f}: {e}", FG_ERR)
        self._copied.clear()
        self._backups.clear()
        self.app.state["py_removed"] = True

    @staticmethod
    def _set_user_env(name: str, value: str):
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                             r"Environment", 0, winreg.KEY_SET_VALUE)
        winreg.SetValueEx(key, name, 0, winreg.REG_EXPAND_SZ, value)
        winreg.CloseKey(key)
        # Broadcast WM_SETTINGCHANGE so open shells pick it up
        HWND_BROADCAST = 0xFFFF
        WM_SETTINGCHANGE = 0x001A
        ctypes.windll.user32.SendMessageTimeoutW(
            HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", 2, 5000, None)

    @staticmethod
    def _append_user_path(new_dir: str):
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                             r"Environment", 0,
                             winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE)
        try:
            current, _ = winreg.QueryValueEx(key, "Path")
        except FileNotFoundError:
            current = ""
        if new_dir.lower() not in [p.strip().lower() for p in current.split(";")]:
            updated = (current.rstrip(";") + ";" if current else "") + new_dir
            winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, updated)
        winreg.CloseKey(key)

    def validate(self) -> bool:
        if not self._done:
            messagebox.showwarning("Installing",
                "Please wait for installation to complete.", parent=self.app)
            return False
        return True


class FinishPage(tk.Frame):
    SUBTITLE = ""

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app

        tk.Label(self, text="Setup Complete",
                 font=("Consolas", 18, "bold"), bg=BG, fg=FG_OK
                 ).pack(anchor="w", padx=PAD, pady=(PAD, 8))

        tk.Label(self,
                 text="Flux has been configured on your system.\n"
                      "Open a new terminal to pick up the updated environment variables.\n"
                      "Compile from scripts\\flux_dev_prompt.bat or a Developer Command Prompt for VS, "
                      "which set the LIB path that lld-link needs.",
                 font=FONT_BODY, bg=BG, fg=FG, wraplength=660, justify="left"
                 ).pack(anchor="w", padx=PAD, pady=(0, PAD))

        # Quick-start box
        box = tk.Frame(self, bg=BG2)
        box.pack(fill="x", padx=PAD)
        tk.Frame(box, bg=ACCENT, width=4).pack(side="left", fill="y")
        inner = tk.Frame(box, bg=BG2)
        inner.pack(fill="both", padx=12, pady=12)
        tk.Label(inner, text="Quick start", font=FONT_HEAD,
                 bg=BG2, fg=ACCENT).pack(anchor="w")

        cmds = [
            "cd /d " + app.state["fluxc_srcdir"].get(),
            *(["build\\fxc\\fxc.exe examples\\helloworld.fx"]
              if app.state["py_removed"] else
              ["python fxc.py fxc.fx                  (bootstrap, once)",
               "python fxc.py examples\\helloworld.fx"]),
            "build\\helloworld\\helloworld.exe",
        ]
        for cmd in cmds:
            tk.Label(inner, text=f"  > {cmd}", font=FONT_MONO,
                     bg=BG3, fg=FG).pack(anchor="w", fill="x", pady=1, padx=4)

        tk.Label(self,
                 text="If you encounter issues, run with --log-level 4 --log-timestamp\n"
                      "for detailed output, or consult docs\\.",
                 font=FONT_SMALL, bg=BG, fg=FG_DIM, justify="left", wraplength=660
                 ).pack(anchor="w", padx=PAD, pady=(PAD, 0))

        srcdir = app.state["fluxc_srcdir"].get()
        tk.Label(self,
                 text=f"FLUXC_SRCDIR = {srcdir}",
                 font=FONT_MONO, bg=BG, fg=FG_DIM
                 ).pack(anchor="w", padx=PAD, pady=(8, 0))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def _is_admin() -> bool:
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        return False


if __name__ == "__main__":
    if sys.platform != "win32":
        print("This setup script is for Windows only.")
        sys.exit(1)

    app = WizardApp()
    app.mainloop()