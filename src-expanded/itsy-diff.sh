#!/bin/bash

cat itsy.lst | cut -c8-35 | grep -v '^\s*$' > itsy.lst.clean
cat ../src/itsy.lst | cut -c8-35 | grep -v '^\s*$' > itsy.o.lst.clean
cmp -s itsy.o.lst.clean itsy.lst.clean || meld itsy.o.lst.clean itsy.lst.clean
