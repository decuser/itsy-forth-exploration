; ==========================================================================
; Itsy 16-bit DOS COM Forth - Introduction / Overview
; --------------------------------------------------------------------------
; Itsy is a classical, indirect-threaded Forth interpreter for 16-bit DOS.
; It implements a single flat memory model where code and data coexist. The
; system is centered on a dictionary of linked entries, each holding a name,
; flags, a code field, and optional data. Execution is driven by two interpreters:
;   - Text interpreter: parses input, searches the dictionary, and manages
;     compilation versus immediate execution.
;   - Address interpreter (address): dispatches words by fetching their code field
;     addresses and jumping indirectly, forming the core of the threading
;     model.
;
; The interpreter is fully self-extending: new words can be defined at
; runtime, primitives and assembly routines coexist seamlessly, and the
; dictionary serves as both program and environment. Register assignments
; and small helper routines support efficient stack handling, colon
; definitions, and dictionary access. This overview frames the architecture
; detailed below.
; ==========================================================================

;; ==========================================================================
; Itsy 16-bit DOS COM Forth - Architecture, Dictionary, and Core Routines
; --------------------------------------------------------------------------
; -----------------------
; Dictionary Structure
; -----------------------
; The dictionary is a linked list of headers, each containing a name,
; flags, a code field, and a data field. Threaded code is stored as a
; sequence of addresses pointing to the code fields of previously defined
; words. In Itsy, SI is the instruction pointer, fetching each cell that
; points to a dictionary code field.

; -----------------------
; Dictionary Words
; -----------------------
; Each entry in the dictionary represents a Forth word: a variable,
; constant, primitive, or colon definition. Words are self-describing
; and contain four main fields:
;   LFA - link field address, pointer to the previous dictionary entry
;   NFA - name field address, pointer to the word’s name string
;   CFA - code field address, pointer to executable code (primitive or colon handler)
;   DFA - data field address, pointer to associated data or value (if applicable)
;
; Colon definitions store a sequence of CFA addresses forming threaded
; code. Primitives, variables, and constants each have short handlers
; that execute their behavior and then return to the address interpreter.
; This structure allows traversal, execution, and runtime modification
; of the dictionary.

; -----------------------
; Implemented Dictionary Words
; -----------------------
;   state   >in       #tib      dp        base     last
;   tib     abort     ,         lit       rot      drop
;   dup     swap      +         =         @        !
;   0branch branch    execute   exit      count    >number
;   accept  word       emit      find       :        ;
;   (;code) constant  interpret

; -----------------------
; Address Interpreter (next)
; -----------------------
; Execution passes through a single address interpreter loop labeled `next`.
; This loop uses LODSW at SI to fetch the next code field, moves it to DI,
; and jumps indirectly via `jmp word[di]`. All words, primitive or colon-
; defined, are dispatched through this loop, defining the indirect threading
; model.

; -----------------------
; Register Usage
; -----------------------
;   SI  - instruction pointer
;   DI  - current code field pointer
;   BX  - top of parameter stack
;   SP  - hardware stack for remaining stack items
;   BP  - software return stack pointer for colon definitions

; -----------------------
; Colon Definitions
; -----------------------
; Colon definitions invoke `docolon`, which pushes the old SI onto BP,
; sets SI to the new definition’s threaded code, and jumps to `next`.
; `exit` restores SI from BP to resume the caller’s execution.

; -----------------------
; Code Field Routines
; -----------------------
; Each dictionary entry’s code field points to a short routine:
;   - Primitives perform a single machine operation and jump to `next`.
;   - Colon definitions invoke `docolon`.
;   - Variables and constants use `dovar` and `doconst` to push addresses
;     or values before returning to `next`.

; -----------------------
; Text Interpreter
; -----------------------
; The text interpreter reads input, tokenizes it with `word`, searches
; the dictionary via `find`, and either executes or compiles based on
; the current state stored in `state`. Memory is a single flat segment:
; the dictionary grows upward, stacks grow downward, matching the COM file
; model.

; -----------------------
; Memory Layout & Self-Extending Behavior
; -----------------------
; Definitions, variables, and primitives exist alongside executable code.
; New Forth words can execute additional assembly instructions. Program
; flow is closely tied to memory layout, initialization, and runtime code
; generation. The dictionary functions as both program and environment.

; -----------------------
; Architectural Assumptions
; -----------------------
; Indirect threading is used; threaded code holds code field addresses, not
; machine code; one shared interpreter loop exists; parameter and return
; stacks are distinct; memory is flat. These assumptions follow early
; assembly-based Forths and are reflected in Itsy’s design.

; -----------------------
; Core Helper Routines
; -----------------------
;   getchar   - read a character from input
;   outchar   - write a character to output
;   docolon   - execute a colon-defined word
;   dovar     - handle variable access
;   doconst   - handle constant access
;   next      - address interpreter loop

;
; These components together form the complete Itsy Forth system.
; ==========================================================================

; -------------------------------------
; -- Program Entry Point
; -------------------------------------

; -----------------------
; Assembly Note
; -----------------------
; Sets the program entry point at 0100h for a DOS COM file.
; Immediately jumps to the code field of the 'abort' routine (CFA).
; This jump also serves to initialize the interpreter and memory state
; before execution enters the main address interpreter loop.

; -----------------------
; Forth Note
; -----------------------
; At Forth level, this corresponds to performing any initial setup and
; clearing the interpreter state. The 'abort' word is used to reset
; or terminate execution safely, ensuring the system starts in a
; known, consistent state.

org 0100h
jmp cfa_abort+2     ; jump to abort code start (initialize the program)


; -------------------------------------
; -- Forth Variables: all Forth words
; -------------------------------------

; -----------------------
; Assembly Note
; -----------------------
; This section sets up Forth variables as dictionary entries.
; Each variable allocates memory for LFA, NFA, CFA, and DFA fields.
; The assembler initializes links (LFA), names (NFA), and default values
; (DFA). DP points to free memory for the next entry. BX is used as a
; temporary pointer during initialization.

; -----------------------
; Forth Note
; -----------------------
; These entries correspond to Forth variables referenced at runtime:
;   state   >in   #tib   dp   base   last
; They can be fetched or stored using Forth primitives (FETCH, STORE),
; manipulated on the parameter stack, and accessed in colon definitions.

                                        ; state
lfa_state:          dw 0
nfa_state:          db 5,'state'
cfa_state:          dw dovar
dfa_state:          dw 0

                                        ; to_in [>in]
lfa_to_in:          dw lfa_state
nfa_to_in:          db 3,'>in'
cfa_to_in:          dw  dovar
dfa_to_in:          dw 0

                                        ; ntib [#tib]
lfa_ntib:           dw lfa_to_in
nfa_ntib:           db 4,'#tib'
cfa_ntib:           dw  dovar
dfa_ntib:           dw 0

                                        ; dp
lfa_dp:             dw lfa_ntib
nfa_dp:             db 2,'dp'
cfa_dp:             dw  dovar
dfa_dp:             dw freemem

                                        ; base
lfa_base:           dw lfa_dp
nfa_base:           db 4,'base'
cfa_base:           dw  dovar
dfa_base:           dw 10

                                        ; last
lfa_last:           dw lfa_base
nfa_last:           db 4,'last'
cfa_last:           dw  dovar
dfa_last:           dw final

                                        ; tib
lfa_tib:            dw lfa_last
nfa_tib:            db 3,'tib'
cfa_tib:            dw  doconst
dfa_tib:            dw 32768

; ------------------------------
; -- Forth Note - Dictionary Chain
; ------------------------------
; The chain so far contains the dictionary head followed by the
; core Forth variables:
;
; 0 <- state <- >in <- #tib <- dp <- base <- last <- tib
;
; This establishes the initial environment for the interpreter and
; supports later word lookups and compilation.
;
; Each entry points to the previous one, forming a linked list that
; supports dictionary traversal for lookup and compilation. This shows
; the incremental setup of the Forth environment prior to defining
; runtime primitives.

; -------------------------------------
; -- System Primitives: all Forth words
; -------------------------------------
; The following entries define foundational primitives required to initialize
; the Forth environment and support early runtime operations.

; -----------------------
; Assembly Note
; -----------------------
; This section creates the core Forth primitives in assembly. Each
; primitive is formed with a dictionary header (LFA, NFA, CFA). The
; code field (CFA) points to the assembly-language routine implementing
; the primitive, which is usually a jump two bytes ahead to the actual
; routine. The routines are straight assembly instructions and each
; ends with `jmp next` to return control to the address interpreter. The
; data field (DFA) is unused for primitives; it is used only for
; variables or constants. DP tracks free memory for dictionary entries.

; -----------------------
; Forth Note
; -----------------------
; These primitives are foundational and somewhat special because they
; can be defined before the address interpreter loop exists. While they
; ultimately rely on `next` for control transfer, their machine
; routines themselves do not depend on the address interpreter being
; fully established. They include stack operations (DUP, DROP, SWAP,
; ROT), arithmetic (+, =), memory access (@, !), flow control
; (BRANCH, 0BRANCH, EXIT), I/O (EMIT, ACCEPT), and mechanisms to
; define new words (LIT, COLON, CONSTANT, VARIABLE). Primitives have no
; associated data; variables and constants populate DFA to hold their
; value or address.


; ---------
; -- Dictionary Word: abort
; -- System Initialization Primitive
; ---------

; -----------------------
; Assembly Note
; -----------------------
; This code builds the primitive `abort` entry in the dictionary. A
; header is formed with LFA pointing to the previous word, NFA holding
; the name, and CFA pointing two bytes ahead to the following assembly
; implementation. The routine itself initializes core interpreter
; state (state, >in, SP, SI) and jumps to the address interpreter loop.

; -----------------------
; Forth Note
; -----------------------
; abort is a special primitive required to bootstrap the system.
; It sets up initial stack and interpreter state so subsequent Forth
; words can execute. Though it precedes the fully defined address
; interpreter, it relies on next to dispatch execution of other words.
; abort is also callable by Forth user programs to reset the interpreter
; state and exit a running definition safely.

                                        ; abort
lfa_abort:          dw lfa_tib
nfa_abort:          db 5,'abort'
cfa_abort:          dw $+2

                    mov ax,word[dfa_ntib]       ; load value in #tib (0 to start)
                    mov word[dfa_to_in],ax      ; Sets >in the value in #tib
                    xor bp,bp                   ; clear bp (used to move 0 into state)
                    mov word[dfa_state],bp      ; sets state to 0 (enter interpret mode)
                    mov sp,-256                 ; reserves a 256-byte stack from top of segment           
                    mov si,cfa_interpret+2      ; set si to interpreter code start
                    jmp next                    ; jump to address interpreter’s dispatch loop

; ---------
; -- Dictionary Words: comma [,] , lit
; -- Compilation Primitives
; ---------

; -----------------------
; Assembly Note
; -----------------------
; `comma` builds a threaded code cell in the dictionary by storing
; the value in AX (swapped with BX) at the current dictionary pointer.
; The dictionary pointer is then updated, and execution returns to
; the address interpreter via `jmp next`.

; -----------------------
; Forth Note
; -----------------------
; `comma` (`,`) is a compilation primitive used by colon definitions
; to append a cell to the threaded code of the currently compiling word.
; It operates directly on the dictionary and does not execute code itself.

                                        ; comma [,]
lfa_comma:          dw lfa_abort
nfa_comma:          db 1,','
cfa_comma:          dw $+2

                    mov di,word[dfa_dp]
                    xchg ax,bx
                    stosw
                    mov word[dfa_dp],di
                    pop bx
                    jmp next

; -----------------------
; Assembly Note
; -----------------------
; `lit` fetches the next word-sized literal from the dictionary using
; LODSW, pushes BX to preserve the top of the parameter stack, swaps AX/BX,
; and returns to the address interpreter via `jmp next`. This creates a
; runtime literal for subsequent execution.

; -----------------------
; Forth Note
; -----------------------
; `lit` is a compilation primitive that pushes a literal value onto the
; parameter stack when executed. It is typically invoked by colon definitions
; to embed constants directly in threaded code.

                                        ; lit
lfa_lit:            dw lfa_comma
nfa_lit:            db 3,'lit'
cfa_lit:            dw $+2

                    push bx
                    lodsw
                    xchg ax,bx
                    jmp next

; ---------
; -- Dictionary Words: rot, drop, dup, swap
; -- Stack Primitives
; ---------

; -----------------------
; -- Assembly Note - stack primitives
; -----------------------
; Each primitive is implemented as a short assembly routine.
; `rot` pops two items off the parameter stack (BX/SP), rearranges
; them, and pushes them back in rotated order. `drop` pops the top
; item. `dup` pushes a copy of the top item. `swap` exchanges the
; top two items. Each routine ends with `jmp next` to return to the
; address interpreter loop.

; -----------------------
; -- Forth Note - stack primitives
; -----------------------
; These stack primitives manipulate the parameter stack directly.
; They are fundamental to word execution and composition, forming
; the basis for arithmetic, logic, and control flow in Forth.

; -----------------------
; -- Assembly Note - rot
; -----------------------
; Implements rot in straight x86 assembly: pops two values into
; registers, pushes them back in rotated order, then swaps AX/BX.
; Ends with jmp next to continue address interpreter dispatch.

; -----------------------
; -- Forth Note - rot
; -----------------------
; `rot` rearranges the top three items of the parameter stack. In
; Forth code, it allows manipulation of stack order for arithmetic
; or data access.

                                        ; rot
lfa_rot:            dw lfa_lit
nfa_rot:            db 3,'rot'
cfa_rot:            dw $+2

                    pop dx
                    pop ax
                    push dx
                    push bx
                    xchg ax,bx
                    jmp next

; -----------------------
; -- Assembly Note - drop
; -----------------------
; Implements `drop` by popping the top item off the parameter stack
; into BX, effectively discarding it. Ends with `jmp next` to resume
; address interpreter dispatch.

; ---------------------
; -- Forth Note - drop
; ---------------------
; `drop` removes the top stack item. It’s one of the most basic
; stack manipulation words and is used pervasively in Forth code.

                                        ; drop
lfa_drop:           dw lfa_rot
nfa_drop:           db 4,'drop'
cfa_drop:           dw $+2

                    pop bx
                    jmp next

; -----------------------
; -- Assembly Note - dup
; -----------------------
; Implements `dup` by pushing BX, which holds the top of the parameter
; stack, creating a duplicate of the top item. Ends with `jmp next`.

; ---------------------
; -- Forth Note - dup
; ---------------------
; `dup` duplicates the top stack item. It’s a core stack operation used
; frequently in arithmetic, control structures, and data handling.

                                        ; dup
lfa_dup:            dw lfa_drop
nfa_dup:            db 3,'dup'
cfa_dup:            dw $+2

                    push bx
                    jmp next

; ------------------------
; -- Assembly Note - swap
; ------------------------
; Implements `swap` by popping the second stack item into AX, pushing
; the top item (BX), then exchanging AX and BX. This flips the top
; two stack items. Ends with `jmp next`.

; ----------------------
; -- Forth Note - swap
; ----------------------
; `swap` exchanges the top two stack items. It is a fundamental
; stack manipulation word, often paired with `dup` and `rot`.

                                        ; swap
lfa_swap:           dw lfa_dup
nfa_swap:           db 4,'swap'
cfa_swap:           dw $+2

                    pop ax
                    push bx
                    xchg ax,bx
                    jmp next

; ---------
; -- Dictionary Words: plus [+], equals [=]
; -- Math and Logic Primitives
; ---------

; ------------------------------
; -- Assembly Note - Math and Logic Primitives
; ------------------------------
; Math and logic primitives are implemented with short inlined assembly
; sequences that operate directly on the parameter stack using AX and BX.
; Arithmetic words like `+` modify BX in place, while logic words like `=`
; perform comparisons and set BX to true (-1) or false (0). Each ends with
; `jmp next` to return to the address interpreter.

; ----------------------------
; -- Forth Note - Math and Logic Primitives
; ----------------------------
; These primitives provide the core arithmetic and comparison operations
; needed by Forth programs. They manipulate values on the parameter stack
; and return results in the standard Forth fashion, supporting control
; structures, calculations, and decision-making.

; ------------------------
; -- Assembly Note - plus
; ------------------------
; Implements `+` by popping the second stack item into AX, adding it
; to BX (top of stack), and leaving the result in BX. Ends with
; `jmp next` to resume interpretation.

; ----------------------
; -- Forth Note - plus
; ----------------------
; `+` adds the top two stack items and pushes the result. It’s a core
; arithmetic primitive used throughout Forth code.

                                        ; plus [+]
lfa_plus:           dw lfa_swap
nfa_plus:           db 1,'+'
cfa_plus:           dw $+2

                    pop ax
                    add bx,ax
                    jmp next

; --------------------------
; -- Assembly Note - equals
; --------------------------
; Implements `=` by popping the second stack item into AX and comparing
; it with BX. Sets BX to true (-1) if equal, or false (0) if not. Ends
; with `jmp next`.

; ------------------------
; -- Forth Note - equals
; ------------------------
; `=` compares the top two stack items and pushes a true flag (-1) if
; they are equal, or false (0) otherwise. This is a basic logical
; primitive used in conditionals and branching.

                                        ; equals [=]
lfa_equals:         dw lfa_plus
nfa_equals:         db 1,'='
cfa_equals:         dw $+2

                    pop ax
                    sub bx,ax
                    sub bx,1
                    sbb bx,bx
                    jmp next

; ---------
; -- Dictionary Words: fetch [@], store [!]
; -- Memory Access Primitives
; ---------

; -----------------------
; -- Assembly Note - Memory Access Primitives
; -----------------------
; These primitives implement direct memory fetch and store using the
; address on the parameter stack. `fetch` loads the 16-bit value at
; the address in BX into BX. `store` writes the top of stack to the
; address in BX, then pops the address itself. Both end with `jmp next`.

; -----------------------
; -- Forth Note - Memory Access Primitives
; -----------------------
; `@` and `!` provide the fundamental mechanism for reading and writing
; memory in Forth. `@` replaces the top stack item (an address) with the
; contents of that address. `!` takes a value and an address from the stack
; and stores the value into that address. They are low-level building blocks
; for variables, constants, and user data structures.

; -----------------------
; -- Assembly Note - fetch [@]
; -----------------------
; Loads the 16-bit word at [BX] into BX. This replaces the address on top
; of the stack with the fetched value. Ends with `jmp next`.

; -----------------------
; -- Forth Note - fetch [@]
; -----------------------
; Takes an address from the stack and replaces it with the contents of
; that address.

                                        ; fetch [!]
lfa_fetch:          dw lfa_equals
nfa_fetch:          db 1,'@'
cfa_fetch:          dw $+2

                    mov bx,word[bx]
                    jmp next

; -----------------------
; -- Assembly Note - store [!]
; -----------------------
; Pops the top of stack into [BX], then pops the address itself into BX.
; This stores the value at the specified address, then discards the address.
; Ends with `jmp next`.

; -----------------------
; -- Forth Note - store [!]
; -----------------------
; Takes a value and an address from the stack and stores the value at
; the address. The address and value are both consumed.

                                        ; store [!]
lfa_store:          dw lfa_fetch
nfa_store:          db 1,'!'
cfa_store:          dw $+2

                    pop word[bx]
                    pop bx
                    jmp next

; ------------------------------
; -- Forth Note - Word Chain after Core Primitives
; ------------------------------
; The dictionary now includes the head, core variables, and the
; foundational primitives required to bootstrap the address interpreter:
;
;   0 <- state <- to_in [>in] <- ntib [#tib] <- dp <- base <- last <- tib
;
; Each entry links to the previous one, forming a chain that supports
; early lookup and compilation. This setup allows the address interpreter
; to begin executing once defined and provides the minimal environment
; for primitive operations.

; -------------------------------------
; -- Address Interpreter (next)
; -- Executes compiled word addresses
; -------------------------------------

; --------------------------------------------------------------------
; This is the classic indirect threaded Forth address interpreter, called “next.”
; Each Forth word’s definition consists of a list of code field addresses (cfa).
; next repeatedly fetches the next cfa and executes the code it points to.
;
; Each word’s code executes, then typically returns to next to process the next cfa.
; This dispatch loop is the core of the Forth execution model.
;
; Startup behavior:
;   si is initialized to cfa_interpret+2 and execution jumps to next.
;   This skips fetching interpret’s own cfa.
;   The first lodsw fetches the cfa of the first word in interpret’s thread
;   and jumps to it, entering the address interpreter loop directly.
;
; The next routine appears here among the word definitions because it is
; part of the runtime environment and is referenced like any other word.
; Placing it here allows references to its address to be resolved during the build
; and ensures it participates in the threaded code sequence.
; --------------------------------------------------------------------

next:               lodsw               ; load word at [si] into ax, increment si by 2
                    xchg di,ax          ; di now holds the fetched cfa
                    jmp word[di]        ; indirect jump to the cfa

; -------------------------------------
; -- Interpreter-Dependent Primitives
; -- Require the address interpreter to execute via cfa
; -------------------------------------

; ------------------------------
; -- Assembly Note - Interpreter-Dependent Primitives
; ------------------------------
; These primitives are implemented as standard threaded-code routines that
; assume the address interpreter is active. They use indirect jumps through
; code field addresses to transfer control, relying on the interpreter’s
; fetch-and-dispatch loop rather than executing standalone machine code.

; ----------------------------
; -- Forth Note - Interpreter-Dependent Primitives
; ----------------------------
; These words form part of the core runtime and require the address interpreter
; to be running. They rely on `next` to fetch and execute the code field
; addresses of subsequent words, integrating tightly with the interpreter’s
; control flow.


; ---------
; -- Dictionary words: zero_branch [0branch], branch, execute, exit
; -- Colon Flow Control Primitives
; ---------

; ------------------------------
; -- Assembly Note - Colon Flow Control Primitives
; ------------------------------
; These primitives manage control flow within colon definitions. `0branch`
; conditionally skips ahead by a 16-bit offset if the top of stack is zero.
; `branch` always jumps ahead by the given offset. `execute` transfers control
; to the cfa on the stack, and `exit` returns to the caller by restoring the
; interpreter’s instruction pointer. Each uses direct manipulation of SI and
; indirect jumps to integrate with the threaded execution model.

; ----------------------------
; -- Forth Note - Colon Flow Control Primitives
; ----------------------------
; These primitives implement the basic control structures used in colon
; definitions. `0branch` and `branch` handle conditional and unconditional
; jumps within a thread. `execute` allows computed transfers of control,
; and `exit` returns from a colon definition. Together they enable looping,
; branching, and dynamic execution flow in Forth programs.

; ------------------------------
; -- Assembly Note - zero_branch
; ------------------------------
; Fetches a 16-bit offset from the thread, tests BX, and if zero updates SI.
; Otherwise continues execution. Ends with `jmp next` to return to the address interpreter.

; ----------------------------
; -- Forth Note - zero_branch
; ----------------------------
; Implements conditional branching in colon definitions. Skips the following code
; if the top of stack is false (0), supporting if-then and loop constructs.

                                        ; zero_branch [0branch]
lfa_zero_branch:    dw lfa_store
nfa_zero_branch:    db 7,'0branch'
cfa_zero_branch:    dw $+2

                    lodsw
                    test bx,bx
                    jne zerob_z
                    xchg ax,si
zerob_z:            pop bx
                    jmp next

; ------------------------------
; -- Assembly Note - branch
; ------------------------------
; Loads a 16-bit offset from the thread and updates SI unconditionally.
; Ends with `jmp next` to continue address interpreter dispatch.

; ----------------------------
; -- Forth Note - branch
; ----------------------------
; Implements unconditional branching in colon definitions, used for loops and jumps.

                                        ; branch
lfa_branch:         dw lfa_zero_branch
nfa_branch:         db 6,'branch'
cfa_branch:         dw $+2

                    mov si,word[si]
                    jmp next

; ------------------------------
; -- Assembly Note - execute
; ------------------------------
; Loads the CFA from the top of stack (BX) into DI, pops BX, and jumps to that CFA.
; This allows one word to invoke another dynamically at runtime.

; ----------------------------
; -- Forth Note - execute
; ----------------------------
; Performs indirect execution of any Forth word. Supports higher-order programming
; and dynamic execution within colon definitions.


                                        ; execute
lfa_execute:        dw lfa_branch
nfa_execute:        db 7,'execute'
cfa_execute:        dw $+2

                    mov di,bx
                    pop bx
                    jmp word[di]

; ------------------------------
; -- Assembly Note - exit
; ------------------------------
; Restores SI from the return stack via BP, increments BP twice, and jumps to `next`.
; Returns control from a colon definition back to the calling context.

; ----------------------------
; -- Forth Note - exit
; ----------------------------
; Ends execution of a colon definition and returns to the calling word.
; Essential for structured control flow in Forth programs.

                                        ; exit
lfa_exit:           dw lfa_execute
nfa_exit:           db 4,'exit'
cfa_exit:           dw $+2

                    mov si,word[bp]
                    inc bp
                    inc bp
                    jmp next

; ---------
; -- Dictionary words: count, to_number [>number]
; -- String Primitives
; ---------

; ------------------------------
; -- Assembly Note - String Primitives
; ------------------------------
; String primitives manipulate memory addresses and counters to handle
; Forth strings. `count` loads the length-prefixed string and pushes its
; address and length. `>number` converts character sequences into numeric
; values, updating the parameter stack. Each ends with `jmp next`.

; ----------------------------
; -- Forth Note - String Primitives
; ----------------------------
; These primitives provide basic string handling: `count` accesses strings
; by address and length, while `>number` parses numeric input from text,
; supporting input conversion and numeric operations in Forth programs.

; -----------------------
; -- Assembly Note - count
; -----------------------
; `count` increments BX, pushes it on the stack, and loads the string
; length into BL/BH registers. Ends with `jmp next` to continue execution.

; -----------------------
; -- Forth Note - count
; -----------------------
; Provides the address and length of a counted string. Used for reading
; words or tokens from the input buffer for further processing.

                                        ; count
lfa_count:          dw lfa_exit
nfa_count:          db 5,'count'
cfa_count:          dw $+2

                    inc bx
                    push bx
                    mov bl,byte[bx-1]
                    mov bh,0
                    jmp next

; -----------------------
; -- Assembly Note - >number
; -----------------------
; `>number` converts a sequence of characters at DI into a numeric value,
; updating AX/CX/DX and the parameter stack. Implements numeric parsing
; directly in assembly. Ends with `jmp next`.

; -----------------------
; -- Forth Note - >number
; -----------------------
; Converts a string of digits into a number and pushes it on the stack.
; Supports decimal input and integrates with standard Forth numeric words.

                                        ; to_number [>number]
lfa_to_number:      dw lfa_count
nfa_to_number:      db 7,'>number'
cfa_to_number:      dw $+2

                    pop di
                    pop cx
                    pop ax
to_numl:            test bx,bx
                    je to_numz
                    push ax
                    mov al,byte[di]
                    cmp al,'a'
                    jc to_nums
                    sub al,32
to_nums:            cmp al,'9'+1
                    jc to_numg
                    cmp al,'A'
                    jc to_numh
                    sub al,7
to_numg:            sub al,48
                    mov ah,0
                    cmp al,byte[dfa_base]
                    jnc to_numh
                    xchg ax,dx
                    pop ax
                    push dx
                    xchg ax,cx
                    mul word[dfa_base]
                    xchg ax,cx
                    mul word[dfa_base]
                    add cx,dx
                    pop dx
                    add ax,dx
                    dec bx
                    inc di
                    jmp to_numl
to_numz:            push ax
to_numh:            push cx
                    push di
                    jmp next

; ---------
; -- Dictionary words: accept, word, emit
; -- Terminal I/O Primitives
; -----------------------

; ------------------------------
; -- Assembly Note - Terminal I/O Primitives
; ------------------------------
; The terminal I/O primitives are implemented in straight x86 assembly.
; `accept` reads a line of characters from input, handles backspaces,
; updates the buffer pointer (>in) and character count (#tib), and echoes
; characters to the terminal. `word` extracts a token from the input buffer,
; copying it to dictionary space and terminating with a space. `emit` writes
; a character from the stack to the terminal via `outchar`. Each primitive
; ends with `jmp next` to continue the address interpreter loop.

; ------------------------------
; -- Forth Note - Terminal I/O Primitives
; ------------------------------
; These primitives provide the Forth environment with basic interaction
; facilities. `accept` allows user input for programs, `word` tokenizes
; input for interpretation or compilation, and `emit` outputs characters.
; Together, they enable reading, parsing, and writing text in Forth programs,
; forming the foundation for interactive use.

; ------------------------------
; -- Assembly Note - accept
; ------------------------------
; Implements the `accept` primitive in straight x86 assembly. It reads a
; line of input from the user, handles backspace, updates the input buffer
; pointer (>in) and character count (#tib), and echoes typed characters.
; Control characters like carriage return and bell are processed correctly.
; Ends with `jmp next` to return to the address interpreter loop.

; ------------------------------
; -- Forth Note - accept
; ------------------------------
; `accept` reads a line of text into the input buffer for further processing.
; It updates the buffer pointer (>in) and character count (#tib). Programs
; and the text interpreter rely on it to fetch user input for interpretation
; or compilation.

                                        ; accept
lfa_accept:         dw lfa_to_number
nfa_accept:         db 6,'accept'
cfa_accept:         dw $+2

                    pop di
                    xor cx,cx
acceptl:            call getchar
                    cmp al,8
                    jne acceptn
                    jcxz acceptb
                    call outchar
                    mov al,' '
                    call outchar
                    mov al,8
                    call outchar
                    dec cx
                    dec di
                    jmp acceptl
acceptn:            cmp al,13
                    je acceptz
                    cmp cx,bx
                    jne accepts
acceptb:            mov al,7
                    call outchar
                    jmp acceptl
accepts:            stosb
                    inc cx
                    call outchar
                    jmp acceptl
acceptz:            jcxz acceptb
                    mov al,13
                    call outchar
                    mov al,10
                    call outchar
                    mov bx,cx
                    jmp next

; ------------------------------
; -- Assembly Note - word
; ------------------------------
; `word` is implemented entirely in x86 assembly. It scans the input
; buffer starting at `>in` in the terminal input area, copies characters
; up to a delimiter into the dictionary at `dp`, and updates `>in` to
; point past the consumed input. Ends with `jmp next` to return control
; to the address interpreter.

; ------------------------------
; -- Forth Note - word
; ------------------------------
; This primitive reads the next space-delimited token from the input
; buffer. Forth programs use it to parse words for interpretation or
; compilation. It handles buffer management and updates `>in`, making
; subsequent primitives aware of the current input position.

                                        ; word
lfa_word:           dw lfa_accept
nfa_word:           db 4,'word'
cfa_word:           dw $+2

                    mov di,word[dfa_dp]
                    push di
                    mov dx,bx
                    mov bx,word[dfa_tib]
                    mov cx,bx
                    add bx,word[dfa_to_in]
                    add cx,word[dfa_ntib]
wordf:              cmp cx,bx
                    je wordz
                    mov al,byte[bx]
                    inc bx
                    cmp al,dl
                    je wordf
wordc:              inc di
                    mov byte[di],al
                    cmp cx,bx
                    je wordz
                    mov al,byte[bx]
                    inc bx
                    cmp al,dl
                    jne wordc
wordz:              mov byte[di+1],32
                    mov ax,word[dfa_dp]
                    xchg ax,di
                    sub ax,di
                    mov byte[di],al
                    sub bx,word[dfa_tib]
                    mov word[dfa_to_in],bx
                    pop bx
                    jmp next

; ------------------------------
; -- Assembly Note - emit
; ------------------------------
; `emit` swaps AX/BX to place the character in AL, then calls DOS
; interrupt 21h function 2 to write the character to the standard
; output. Returns to the address interpreter with `jmp next`. Uses
; `getchar` and `outchar` as low-level I/O helpers.

; ------------------------------
; -- Forth Note - emit
; ------------------------------
; Outputs a single character from the parameter stack to the
; terminal. Forth programs call `emit` to display characters or
; produce text output; it operates on the top of the parameter stack.

                                        ; emit
lfa_emit:           dw lfa_word
nfa_emit:           db 4,'emit'
cfa_emit:           dw $+2

                    xchg ax,bx
                    call outchar
                    pop bx
                    jmp next

getchar:            mov ah,7
                    int 021h
                    mov ah,0
                    ret

outchar:            xchg ax,dx
                    mov ah,2
                    int 021h
                    ret

; ---------
; -- Dictionary word: find
; -- Search Primitive
; -----------------------

; ------------------------------
; -- Assembly Note - find
; ------------------------------
; Implements dictionary search for a given name. Traverses linked
; headers starting at last, compares characters case-insensitively,
; sets BX to indicate success (1) or failure (0). On success, DI points
; to the word’s CFA. Returns to next for further execution.

; ------------------------------
; -- Forth Note - find
; ------------------------------
; `find` is a Forth word that searches the dictionary for a given name.
; When called by the text interpreter, it determines whether input
; matches an existing definition. On success, the word can be executed
; or compiled; on failure, the search result signals undefined input.

                                        ; find
lfa_find:           dw lfa_emit
nfa_find:           db 4,'find'
cfa_find:           dw $+2

                    mov di,dfa_last
findl:              push di
                    push bx
                    mov cl,byte[bx]
                    mov ch,0
                    inc cx
findc:              mov al,byte[di+2]
                    and al,07Fh
                    cmp al,byte[bx]
                    je findm
                    pop bx
                    pop di
                    mov di,word[di]
                    test di,di
                    jne findl
findnf:             push bx
                    xor bx,bx
                    jmp next
findm:              inc di
                    inc bx
                    loop findc
                    pop bx
                    pop di
                    mov bx,1
                    inc di
                    inc di
                    mov al,byte[di]
                    test al,080h
                    jne findi
                    neg bx
findi:              and ax,31
                    add di,ax
                    inc di
                    push di
                    jmp next

; ------------------------------
; -- Forth Note - Complete Word Chain (Pre-Text Interpreter)
; ------------------------------
; The dictionary now contains the head, core variables, and all
; implemented primitives, including flow control, string, and
; terminal I/O words. The address interpreter (`next`) is fully
; available, allowing these words to execute via their code field
; addresses (cfa):
;
;   0 <- state <- to_in [>in] <- ntib [#tib] <- dp <- base <- last <- tib
;   <- abort <- comma [,] <- lit <- rot <- drop <- dup <- swap <- plus [+]
;   <- equals [=] <- fetch [@] <- store [!]
;   <- zero_branch [0branch] <- branch <- execute <- exit <- count
;   <- to_number [>number] <- accept <- word <- emit <- find
;
; Each entry links to the previous one, forming a complete dictionary
; chain that supports lookup, compilation, and execution of all
; primitives before the text interpreter is fully active.

; -----------------------
; Colon Definitions
; -- Words for composing other forth words
; -----------------------

; ---------
; -- Dictionary words: colon [:] (colon word), semicolon [;] (colon word)
; -- Composition Delimiters - user facing
; ---------

                                        ; colon [:]
lfa_colon:          dw lfa_find
nfa_colon:          db 1,':'
cfa_colon:          dw docolon

                    dw cfa_lit,-1,cfa_state,cfa_store,cfa_create
                    dw cfa_semicode
docolon:            dec bp
                    dec bp
                    mov word[bp],si
                    lea si,[di+2]
                    jmp next

                                        ; semicolon [;]
lfa_semicolon:      dw lfa_colon
nfa_semicolon:      db 080H+1,';'       ; immediate+name len+string
cfa_semicolon:      dw docolon

                    dw cfa_lit,cfa_exit,cfa_comma,cfa_lit,0,cfa_state
                    dw cfa_store,cfa_exit

; ---------
; -- Dictionary words: create (colon word), semicode [(;code)] (primitive)
; -- Low-level Composition functions
; ---------
; These primitives support the implementation of colon definitions and other
; composed words. While they can be invoked directly, they are intended for
; internal use, enabling the creation of new dictionary entries and execution
; of arbitrary code sequences.

                                        ; create
lfa_create:         dw lfa_semicolon
nfa_create:         db 6,'create'
cfa_create:         dw docolon

                    dw cfa_dp,cfa_fetch,cfa_last,cfa_fetch,cfa_comma
                    dw cfa_last,cfa_store,cfa_lit,32,cfa_word,cfa_count
                    dw cfa_plus,cfa_dp,cfa_store,cfa_lit,0,cfa_comma
                    dw cfa_semicode
dovar:              push bx
                    lea bx,[di+2]
                    jmp next

                                            ; semicode [(;code)]
lfa_semicode:       dw lfa_create
nfa_semicode:       db 7,'(;code)'
cfa_semicode:       dw $+2

                    mov di,word[dfa_last]
                    mov al,byte[di+2]
                    and ax,31
                    add di,ax
                    mov word[di+3],si
                    mov si,word[bp]
                    inc bp
                    inc bp
                    jmp next

; ---------
; -- Dictionary word: constant (colon word)
; -- Constant Definition
; ---------
; Defines a dictionary entry representing a constant value.

                                        ; constant
lfa_constant:       dw lfa_semicode
nfa_constant:       db 8,'constant'
cfa_constant:       dw docolon

                    dw cfa_create,cfa_comma,cfa_semicode
doconst:            push bx
                    mov bx,word[di+2]
                    jmp next

; -------------------------------------
; -- Text Interpreter (interpret)
; -- Core Forth REPL (Process Input, Execute Words, Handle Control Flow)
; -------------------------------------
; The text interpreter is implemented as an ordinary Forth word whose cfa is the first
; executed when the system starts. si is preloaded with cfa_interpret+2, and control jumps
; to next, which begins executing the threaded code of interpret just like any other word.
; interpret reads input, parses words, manages state (compile vs interpret), and dispatches
; execution through next. It drives the interactive Forth environment.

; ---------
; -- Dictionary Word: interpret (Colon word)
; -- Implements the Text Interpreter
; ---------

final:                                  ; start of the last word's dictionary header

                                        ; interpret
lfa_interpret:      dw lfa_constant
nfa_interpret:      db 9,'interpret'
cfa_interpret:      dw docolon

; ---------
; Text Interpreter Thread: interpt (interpret)
;
; Entry point of the text interpreter.
; Reads input into the buffer, sets #tib to the number of characters read,
; and initializes >in for parsing. Prepares the system to scan and interpret words.
; ---------
interpt:            
                    ; Fetch the value of the input buffer length and
                    ; the current position index within it.
                    dw cfa_ntib,cfa_fetch,cfa_to_in,cfa_fetch

                    ; Compare the input buffer length with the current index
                    ; If they are not equal, more text remains to be processed
                    ; go get it
                    dw cfa_equals,cfa_zero_branch,intpar,cfa_tib

                    ; Push 50 onto the stack to tell accept to read up to 50 characters.
                    ; Store the actual number of characters read into #tib.
                    dw cfa_lit,50,cfa_accept,cfa_ntib,cfa_store

                    ; Reset >in to 0 to start reading from the beginning of the input buffer.
                    dw cfa_lit,0,cfa_to_in,cfa_store

; ---------
; Parser and immediate word handler: intpar (parser)
;
; This code handles scanning the input buffer for the next word,
; checks if it exists in the dictionary, determines whether it is
; immediate, and executes it or compiles its CFA.
; ---------
intpar:
                    ; Push a space (ascii 32) onto the stack as delimiter.
                    ; Use the word primitive to scan the input buffer up to that character.
                    ; After parsing a string, use find to see if it matches a dictionary entry.
                    ; Duplicate the result flag for further processing.
                    dw cfa_lit,32,cfa_word,cfa_find,cfa_dup

                    ; If the flag from 'find' is zero, the string doesn't match any defined word.
                    ; Otherwise, we have a word match - fetch the interpreter state (interpret/compile)
                    ; to see whether to interpret or compile it.
                    dw cfa_zero_branch,intnf,cfa_state,cfa_fetch

                    ; If the found word is immediate jump to execute it; 
                    ; otherwise, compile its CFA into the dictionary.
                    dw cfa_equals,cfa_zero_branch,intexc,cfa_comma

                    ; and jump to the end of the interpreter loop, skipping any remaining 
                    ; checks or compilation steps.
                    dw cfa_branch,intdone

; ---------
; Immediate word executor: intexc (execute immediate)
;
; This code handles the case when a word is marked as immediate.
; It executes the word’s CFA right away, bypassing compilation,
; and then jumps to the end of the interpreter loop.
; ---------
intexc:
                    ; Execute its CFA immediately, then skip the remaining
                    ; interpreter steps and jump to the end of the loop.
                    dw cfa_execute,cfa_branch,intdone

; ---------
; Number parsing and compilation handling: intnf (not found / number check)
;
; This code handles the case where the scanned string is not a dictionary word.
; It prepares for >number conversion by duplicating and rotating the string,
; splits the counted string into length and text, and attempts numeric conversion.
;
; If the conversion succeeds, control jumps to continue processing (intskip).
; If it fails, the code checks whether we are interpreting or compiling.
; For compilation, it manages the LFA of the current word and restores
; the previous 'last' word in the dictionary to maintain dictionary consistency.
; ---------

intnf:
                    ; It wasn't a word, is it as a number?
                    ; Duplicate and rotate the string, split length from text,
                    ; and call >number for conversion.
                    dw cfa_dup,cfa_rot,cfa_count,cfa_to_number

                    ; If >number succeeded (0 from 0branch), continue.
                    ; Otherwise, check interpreter state to handle conversion error.
                    dw cfa_zero_branch,intskip,cfa_state,cfa_fetch

                    ; if state is 0, we're intrepreting, jump directly
                    ; to the conversion error handler, otherwise get the
                    ; lfa of the word we were trying to compile and set
                    ; aside a copy of it
                    dw cfa_zero_branch,intnc,cfa_last,cfa_fetch,cfa_dup

                    ; then restore the dictionary pointer to point to the end of the word we just compiled,
                    ; ensuring the dictionary remains consistent for subsequent words
                    dw cfa_fetch,cfa_last,cfa_store,cfa_dp,cfa_store

; ---------
; Number Conversion Error Handler: intnc (conversion failure)
;
; This code is reached whenever a numeric conversion fails, regardless
; of whether the system is in interpretation or compilation mode.
; It calls the abort routine to reset the interpreter state and ensure
; the system remains consistent.
; ---------
intnc:
                    ; Handle failed numeric conversion: reset the system by calling abort.
                    dw cfa_abort

; ---------
; Post-Number Conversion Handler: intskip (successful conversion)
;
; This code handles the stack cleanup and compilation after a successful
; numeric conversion. It drops the temporary values returned by >number,
; leaving the converted single-precision number on the stack.
; If interpreting, it jumps to continue processing.
; If compiling, it encodes the literal by storing its CFA and the number
; into the dictionary for later execution.
; ---------
intskip:
                    ; Success, drop the temporary address and high word from >number
                    ; leave the converted number on the stack
                    ; check interpreter state to decide next action.
                    dw cfa_drop, cfa_drop, cfa_state, cfa_fetch

                    ; If interpreting, jump to continue. Otherwise, encode the literal into the dictionary.  
                    dw cfa_zero_branch,intdone,cfa_lit,cfa_lit,cfa_comma  

                    ; Store the converted number into the current word in the dictionary.  
                    dw cfa_comma

; ---------
; Text Interpreter Continuation: intdone
;
; Marks the end of a single iteration of the text interpreter.
; Unconditionally jumps back to interpt to fetch and process the next word
; from the input buffer, continuing the REPL loop.
; ---------
intdone:
                    ; Jump back to the start of the text interpreter loop.
                    dw cfa_branch,interpt

; ------------------------------
; -- Forth Note - Final Word Chain
; ------------------------------
; The dictionary now includes all core variables, primitives, and
; high-level words, completing the Forth environment for execution:
;
;   0 <- state <- to_in [>in] <- ntib [#tib] <- dp <- base <- last <- tib
;   <- abort <- comma [,] <- lit <- rot <- drop <- dup <- swap <- plus [+]
;   <- equals [=] <- fetch [@] <- store [!]
;   <- zero_branch [0branch] <- branch <- execute <- exit <- count
;   <- to_number [>number] <- accept <- word <- emit <- find
;   <- colon [:] <- semicolon [;] <- create [(;code)] <- constant
;   <- interpret
;
; With the text interpreter now defined, this final chain fully supports
; lookup, compilation, execution, and runtime extension of all Forth words.


freemem:


