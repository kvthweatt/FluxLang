import ast, re, sys

##
#
# Helper tool for locating where allocations are not respecting type alignment in the AST
#
##

ALLOCATION_PATTERNS = [
    r'builder\.alloca\(',
    r'ir\.GlobalVariable\(',
    r'builder\.gep\(',
    # Add more patterns
]

def audit_file(filepath):
    with open(filepath) as f:
        content = f.read()
    
    findings = []
    for pattern in ALLOCATION_PATTERNS:
        matches = re.finditer(pattern, content, re.MULTILINE)
        for match in matches:
            line_num = content[:match.start()].count('\n') + 1
            # Extract surrounding context
            findings.append([f"Line {line_num}: " + content[match.start():match.end()]])
    
    return findings

if __name__ == "__main__":
    findings = audit_file(sys.argv[1])
    for finding in findings:
        print(finding[0])
    print(f"Found {len(findings)} locations which require allocation alignment correction.")