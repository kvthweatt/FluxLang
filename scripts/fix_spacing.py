import sys
from pathlib import Path

def normalize_file(path: Path):
    # Read full text preserving raw newline structure
    text = path.read_text(encoding="utf-8", errors="ignore")

    # Split by newline
    lines = text.splitlines()

    # Take every other line starting from index 0
    corrected = lines[::2]

    # Join back with newline
    new_text = "\n".join(corrected) + "\n"

    # Overwrite file
    path.write_text(new_text, encoding="utf-8")

def main():
    if len(sys.argv) < 2:
        print("Usage: python fix_spacing.py <file1> [file2 ...]")
        sys.exit(1)

    for file_arg in sys.argv[1:]:
        p = Path(file_arg)
        if not p.exists():
            print(f"Skipping missing file: {p}")
            continue

        normalize_file(p)
        print(f"Normalized: {p}")

if __name__ == "__main__":
    main()
