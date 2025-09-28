# ---------------------------------------------------------------------
# strip.py
# ---------------------------------------------------------------------
# Utility to extract only the operative assembly instructions from
# a Forth source file (itsy.asm), removing comments, labels, directives
# (db, dw), and blank lines. Produces a clean listing suitable for
# diffing or analysis of instruction sequences.
# ---------------------------------------------------------------------
# Run from src: python ../tools/strip.py itsy.asm

#!/usr/bin/env python

import re, sys

def process_line(line):
    line = line.strip()
    if not line:
        return None
    if line.startswith(';'):
        return None
    in_quote = False
    new_line = ""
    for c in line:
        if c == '"':
            in_quote = not in_quote
        if c == ';' and not in_quote:
            break
        new_line += c
    line = new_line.rstrip()
    line = re.sub(r'^\s*\w+:\s*', '', line)
    if line.lower().startswith(('db','dw')):
        return None
    return line if line else None

def main():
    if len(sys.argv) > 1:
        f = open(sys.argv[1], 'r')
    else:
        f = sys.stdin
    for line in f:
        result = process_line(line)
        if result is not None:
            print(result)
    if f is not sys.stdin:
        f.close()

if __name__ == "__main__":
    main()

