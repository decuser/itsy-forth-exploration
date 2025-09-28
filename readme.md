**1. Project Title**

`itsy-forth-exploration`

**2. Summary / What this project shows**

A clear, annotated exploration of John Metcalf’s *itsy* Forth, demonstrating how the interpreter works at the assembly and Forth level. Includes expanded macros and commentary for readability, while producing a byte-identical binary to the original source.

**3. Motivation / Objectives**

* Understand Forth as a language and stack-oriented design
* Learn low-level assembly in a practical context
* Explore interpreter implementation techniques
* Provide thorough documentation and commentary

**4. Attribution / Sources**

* Original *itsy* Forth by John Metcalf
* Inspired by Mike Adams's excellent source commentary

**5. Project Structure**

```
.
├── build
├── notes
├── resources
│   ├── adams-commentary
│   │   └── src
│   ├── metcalf-blogposts
│   │   └── images
│   └── metcalf-original
│       └── src
├── src
└── tools
```

**6. Usage / Building / Running**

* Tested and built with nasm 2.16.03 on Debian 13.1 Trixie.
* Also tested and built with nasm 2.07 inside DOSBox.
* The source assembles with nasm on Linux, Windows, or macOS using `-f bin` to produce a DOS `.COM` binary. The resulting program runs in a DOS-compatible environment such as DOSBox or DOSEMU.

Example:

```
nasm -f bin -l itsy.lst -o itsy.com itsy.asm   # produces listing and binary
nasm -f bin -o itsy.com itsy.asm               # produces only binary
```

* Scripts for cleaning and diffing assembly are in `tools/`
* `python ../tools/strip.py itsy.asm` extracts instruction sequences
* `../tools/itsy-diff.sh` compares cleaned instruction sequences of your modified source against the original, launching `meld` if differences are detected. Giving you an easy way to find modifications that effect binary equality of the resulting binary.

**7. Development / Next Steps**

* Port to 64-bit Linux
* Expand dictionary with additional primitive words
* Explore building higher-level words in pure Forth


