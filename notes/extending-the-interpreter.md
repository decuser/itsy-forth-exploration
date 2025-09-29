# Extending the Itsy Forth Interpreter

This note documents the modifications and extensions made to John Metcalf's *itsy* Forth interpreter in the `itsy-forth-exploration` project.

## Added Word: `bye`

### Purpose

`bye` is a system exit primitive that allows the user to terminate the interpreter safely, from any point where the system is waiting for input.

### Implementation

**Assembly Note**  

The final label is moved to just before the definition being added to the existing chain. final: marks the beginning of the last word's definition. The `bye` word is defined as a dictionary entry with its CFA pointing to a simple DOS termination instruction:

```
final:                                  ; start of the last word's dictionary 
header

                                        ; bye
lfa_bye:          dw lfa_interpret
nfa_bye:          db 3,'bye'
cfa_bye:          dw $+2

                    int 20h             ; terminate program, does not jump to next
```

**Forth Note**
`bye` is callable directly from the Forth interpreter. It does not rely on the inner or outer interpreter loops, so it safely exits the program without affecting the system state.

### Usage

When the interpreter is waiting for input, simply type:

```
bye
```

The interpreter terminates cleanly. This does not require marking `bye` as an immediate word.

---

## Notes on Further Extensions

Future extensions could include:

* Handling additional control signals such as `^C` for interrupting execution.
* Adding new primitive or colon words for enhanced functionality, e.g., file I/O, math operations, or stack manipulation.
* Comparing the word set with other Forth systems like JonesForth or eForth to identify minimal useful word sets.

