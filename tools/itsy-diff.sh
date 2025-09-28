#!/bin/bash

# Ensure build directory exists
mkdir -p ../build

# Clean listings
cat itsy.lst | cut -c8-35 | grep -v '^\s*$' > ../build/itsy.lst.clean
cat ../resources/metcalf-original/src/itsy.lst | cut -c8-35 | grep -v '^\s*$' > ../build/itsy.o.lst.clean

# Compare and launch meld if different
cmp -s ../build/itsy.o.lst.clean ../build/itsy.lst.clean || meld ../build/itsy.o.lst.clean ../build/itsy.lst.clean

