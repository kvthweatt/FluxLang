"""
Flux Language - Windows Setup Wizard
scripts/setup.py

Run this from the repo root or directly from the scripts/ folder.
Requires Python 3.13+ and an internet connection.
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

APP_NAME    = "Flux Language"
APP_VERSION = "0.1.0"

# Direct download URLs
URLS = {
    "python": "https://www.python.org/ftp/python/3.13.13/python-3.13.13-amd64.exe",
    "msys2":  "https://github.com/msys2/msys2-installer/releases/download/2026-03-22/msys2-x86_64-20260322.exe",
    # LLVM installed via winget — no direct URL needed
    # VS is a redirect bootstrapper — opened in browser
    "vs":     "https://c2rsetup.officeapps.live.com/c2r/downloadVS.aspx?sku=community&channel=stable&version=VS18&source=VSLandingPage&cid=2500:fa55c5a4026a4d2d9741802b0c59cdaa",
}

LICENSE_TEXT = """\
Flux Language — License Agreement
==================================

[PLACEHOLDER LICENSE TEXT]

This software is provided "as is", without warranty of any kind, express or
implied. The authors are not liable for any claim, damages, or other liability
arising from the use of this software.

By continuing you agree to these terms and acknowledge the following:

  • This installer will download and install third-party software on your
    behalf. Each component is subject to its own license agreement.

  • Components installed include: Python, LLVM/Clang, and optionally
    MSYS2 and Visual Studio Build Tools.

  • The FLUXC_SRCDIR environment variable will be set to the location of
    this repository so the Flux compiler can be invoked from anywhere.

  • No data is collected or transmitted beyond what is required to
    download the above components from their official sources.

[Replace this block with your actual license before distribution]
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

# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------

def _run(cmd: list[str]) -> tuple[bool, str]:
    """Run a subprocess quietly. Returns (success, stdout)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return r.returncode == 0, r.stdout.strip()
    except Exception:
        return False, ""


def detect_python() -> Optional[str]:
    ok, out = _run([sys.executable, "--version"])
    return out if ok else None


def detect_clang() -> Optional[str]:
    for name in ("clang", "clang-21", "clang++"):
        ok, out = _run([name, "--version"])
        if ok:
            return out.splitlines()[0]
    return None


def detect_llc() -> Optional[str]:
    ok, out = _run(["llc", "--version"])
    if ok:
        return out.splitlines()[0]
    # Try MSYS2 path
    msys2_llc = Path(r"C:\msys64\mingw64\bin\llc.exe")
    if msys2_llc.exists():
        ok, out = _run([str(msys2_llc), "--version"])
        if ok:
            return out.splitlines()[0] + " (MSYS2)"
    return None


def detect_llvmlite() -> Optional[str]:
    try:
        import llvmlite
        return llvmlite.__version__
    except ImportError:
        return None


def detect_msvc() -> Optional[str]:
    """Return a description string if any MSVC installation is found."""
    # Check env var set by VS Developer Command Prompt
    if os.environ.get("VCINSTALLDIR"):
        return f"Found via VCINSTALLDIR: {os.environ['VCINSTALLDIR']}"
    # Registry scan for VS 2017+ (vswhere is the canonical tool)
    vswhere_paths = [
        r"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe",
        r"C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe",
    ]
    for vsp in vswhere_paths:
        if Path(vsp).exists():
            ok, out = _run([vsp, "-latest", "-property", "installationPath"])
            if ok and out:
                return f"Visual Studio at {out}"
    # Fallback: check cl.exe in PATH
    ok, out = _run(["cl.exe"])
    if ok or "Microsoft" in out:
        return "cl.exe found in PATH"
    return None


def detect_fluxc_srcdir() -> str:
    """Guess the repo root from this script's location."""
    here = Path(__file__).resolve()
    # If we're in scripts/, go up one level
    if here.parent.name.lower() == "scripts":
        return str(here.parent.parent)
    return str(here.parent)

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
        self.geometry("720x560")
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
            "fluxc_srcdir":   tk.StringVar(value=detect_fluxc_srcdir()),
            # detection results (filled in on components page)
            "det": {},
        }

        self._pages: list[tk.Frame] = []
        self._idx = 0

        # Header bar (persistent)
        self._build_header()

        # Page container
        self._container = tk.Frame(self, bg=BG)
        self._container.pack(fill="both", expand=True, padx=0, pady=0)

        # Nav bar (persistent)
        self._build_nav()

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
        w, h = 720, 560
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

        self._btn_back = self._nav_btn(btn_frame, "← Back", self._go_back)
        self._btn_back.pack(side="left", padx=(0, 8))

        self._btn_next = self._nav_btn(btn_frame, "Next →", self._go_next, primary=True)
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
            text="Finish" if last else "Next →",
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
    SUBTITLE = "Welcome"

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
            ("Python 3.13+",        "Runs the Flux compiler"),
            ("LLVM/Clang v21",      "Compiles IR to native code"),
            ("MSVC / Build Tools",  "Linker and Windows SDK"),
            ("llvmlite 0.44.0",     "Python → LLVM bindings"),
            ("FLUXC_SRCDIR",        "Environment variable pointing to this repo"),
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
    SUBTITLE = "License Agreement"

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
    SUBTITLE = "Select Components"

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

        # Pre-tick install boxes based on what's missing
        app.state["install_python"].set(det["python"] is None)
        app.state["install_llvm"].set(det["clang"] is None or det["llc"] is None)
        app.state["install_msys2"].set(det["llc"] is None)
        app.state["install_pip"].set(det["llvmlite"] is None)
        # MSVC handled on its own page

        grid = tk.Frame(self, bg=BG)
        grid.pack(fill="x", padx=PAD)

        components = [
            ("Python 3.13+",    "install_python", det["python"],
             "Required to run the compiler"),
            ("LLVM + Clang v21","install_llvm",   det["clang"],
             "Compiles IR; also provides lld-link"),
            ("MSYS2 (llc)",     "install_msys2",  det["llc"],
             "Only needed if LLVM package omits llc"),
            ("llvmlite 0.44.0 (pip)", "install_pip", det["llvmlite"],
             "Python ↔ LLVM bindings"),
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
                tk.Label(top, text="  Not found — will install",
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


class MSVCPage(tk.Frame):
    SUBTITLE = "MSVC / Build Tools"

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
                ("build_tools",  "Visual Studio Build Tools (recommended — lightweight)"),
                ("vs_community", "Visual Studio Community (full IDE)"),
                ("skip",         "Skip — I will configure MSVC manually"),
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
    SUBTITLE = "Installing"

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app
        self._done = False

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
            steps.append(("Python 3.13+",     self._install_python))
        if st["install_llvm"].get():
            steps.append(("LLVM + Clang v21", self._install_llvm))
        if st["install_msys2"].get():
            steps.append(("MSYS2 (llc)",      self._install_msys2))
        if st["install_msvc"].get():
            steps.append(("VS Build Tools",   self._install_msvc))
        if st["install_pip"].get():
            steps.append(("llvmlite (pip)",   self._install_llvmlite))
        if st["set_env"].get():
            steps.append(("Environment vars", self._set_env_vars))

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
        self._log_msg("\nAll steps finished. Click Next → to complete setup.")

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

    def _install_llvm(self):
        self._log_msg("  Running: winget install LLVM.LLVM")
        self._set_step(0.1, "winget install LLVM.LLVMâ¦")
        ok, out = _run(["winget", "install", "LLVM.LLVM",
                        "--accept-source-agreements", "--accept-package-agreements"])
        self._log_msg(out or ("  OK" if ok else "  winget returned non-zero"))
        self._set_step(1.0, "")
        if not ok:
            raise RuntimeError("winget install LLVM.LLVM failed â see log above")

    def _install_msys2(self):
        self._download_and_run(URLS["msys2"], "MSYS2",
                               ["install", "--root", r"C:\msys64", "--confirm-command"])
        msys2_bash = Path(r"C:\msys64\usr\bin\bash.exe")
        if msys2_bash.exists():
            self._log_msg("  Installing mingw-w64-x86_64-llvm via pacman…")
            subprocess.run([
                str(msys2_bash), "--login", "-c",
                "pacman -S --noconfirm mingw-w64-x86_64-llvm"
            ], check=True)
        else:
            self._log_msg("  MSYS2 bash not found at expected path — run pacman manually.", FG_ERR)

    def _install_msvc(self):
        # VS cannot be silently installed â open the browser bootstrapper
        self._log_msg("  Opening Visual Studio download page in your browserâ¦")
        self._log_msg("  Install the Desktop development with C++ workload,")
        self._log_msg("  or add MSVC v143 + Windows SDK under Individual Components.")
        import webbrowser
        webbrowser.open(URLS["vs"])
        self._set_step(1.0, "")

    def _install_llvmlite(self):
        self._log_msg("  Running: pip install llvmlite==0.44.0")
        self._set_step(0.3, "pip install llvmlite==0.44.0")
        ok, out = _run([sys.executable, "-m", "pip", "install",
                        "llvmlite==0.44.0", "--quiet"])
        self._log_msg(out or ("  OK" if ok else "  pip returned non-zero"))
        self._set_step(1.0, "")
        if not ok:
            raise RuntimeError("pip install failed — see log above")

    def _set_env_vars(self):
        srcdir = self.app.state["fluxc_srcdir"].get()
        self._log_msg(f"  Setting FLUXC_SRCDIR = {srcdir}")
        self._set_user_env("FLUXC_SRCDIR", srcdir)
        # Also append MSYS2 llc path if we installed MSYS2
        if self.app.state["install_msys2"].get():
            msys2_bin = r"C:\msys64\mingw64\bin"
            self._log_msg(f"  Appending {msys2_bin} to user PATH")
            self._append_user_path(msys2_bin)

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
            current, _ = winreg.QueryValueEx(key, "PATH")
        except FileNotFoundError:
            current = ""
        if new_dir.lower() not in current.lower():
            updated = current.rstrip(";") + ";" + new_dir
            winreg.SetValueEx(key, "PATH", 0, winreg.REG_EXPAND_SZ, updated)
        winreg.CloseKey(key)

    def validate(self) -> bool:
        if not self._done:
            messagebox.showwarning("Installing",
                "Please wait for installation to complete.", parent=self.app)
            return False
        return True


class FinishPage(tk.Frame):
    SUBTITLE = "Setup Complete"

    def __init__(self, parent, app: WizardApp):
        super().__init__(parent, bg=BG)
        self.app = app

        tk.Label(self, text="Setup Complete",
                 font=("Consolas", 18, "bold"), bg=BG, fg=FG_OK
                 ).pack(anchor="w", padx=PAD, pady=(PAD, 8))

        tk.Label(self,
                 text="Flux has been configured on your system.\n"
                      "Open a new terminal to pick up the updated environment variables.",
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
            "cd C:\\path\\to\\Flux",
            "python fxc.py examples\\hello.fx",
            "build\\hello.exe",
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