#!/usr/bin/env python3
import re, sys

def process_line(line):
    # Skip lines that are empty or contain only whitespace

    line = line.strip()
    if not line:    
        line = None

    if line is not None and line.startswith(';'):
        line = None

    if line is not None:
        in_quote = False
        new_line = ""
        for c in line:
            if c == '"':          # toggle quote state
                in_quote = not in_quote
            if c == ';' and not in_quote:
                break             # found comment outside quotes
            new_line += c
        if in_quote:
            pass # print(f"Warning: unterminated quote in line: {line}", file=sys.stderr)
        line = new_line.rstrip()
    
    # Remove labels at the start of a line (e.g., "label:")  
    if line is not None:
        # print(f"Before removing label: {line!r}", file=sys.stderr)
        line = re.sub(r'^\s*\w+:\s*', '', line)
        # print(f"After removing label:  {line!r}", file=sys.stderr)

    if line is not None:
        line = None if line.lstrip().lower().startswith('db') else line

    if line is not None:
        line = None if line.lstrip().lower().startswith('dw') else line
    

    if line is not None and line == "":
        line = None


    return line

def main():
    with open("itsy.asm", "r") as f:
        for line in f:
            result = process_line(line)
            if result is not None:
                print(result)

if __name__ == "__main__":
    main()

