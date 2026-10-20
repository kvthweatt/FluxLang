import os
import re
import sys

STDLIB = os.path.join(".", "src", "stdlib")
TARGETS = ["examples", "tests"]

# Every .fx file name found anywhere under the stdlib directory
names = set()
for root, _, files in os.walk(STDLIB):
    for f in files:
        if f.endswith(".fx"):
            names.add(f)

if not names:
    sys.exit("No stdlib files found under " + STDLIB + " (run from the compiler root)")

quoted = re.compile(r'"([^"\\\n]+\.fx)"')

def fix_line(line):
    # Only touch #import lines
    if not line.lstrip().startswith("#import"):
        return line
    return quoted.sub(
        lambda m: "<" + m.group(1) + ">" if m.group(1) in names else m.group(0),
        line,
    )

changed_files = 0
changed_lines = 0

for target in TARGETS:
    for root, _, files in os.walk(target):
        for f in files:
            if not f.endswith(".fx"):
                continue
            path = os.path.join(root, f)
            with open(path, "r", encoding="utf-8", newline="") as fh:
                lines = fh.readlines()
            new = [fix_line(l) for l in lines]
            n = sum(1 for a, b in zip(lines, new) if a != b)
            if n:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.writelines(new)
                changed_files += 1
                changed_lines += n
                print(path + ": " + str(n) + " line(s)")

print("Done: " + str(changed_lines) + " line(s) in " + str(changed_files) + " file(s)")