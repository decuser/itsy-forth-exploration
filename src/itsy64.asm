; =======================================
;  itsy64.asm - 64 bit port of itsy Forth
; =======================================

; Memory layout
; Address (hex)
; 0x0000 ─────────────────────────────┐
;                                     │
;       Dictionary (grows upward)     │
;                                     │
;       Latest entry → HEAD → ...     │
;                                     │
;                                     │
; 0xFE00 ─────────────────────────────┤
;                                     │
;       Return Stack (grows downward) │
;       rp points here initially      │
;       Each element: 8 bytes         │
;                                     │
; 0xFF00 ─────────────────────────────┤
;                                     │
;       Data Stack (grows downward)   │
;       dp points here initially      │
;       Each element: 8 bytes         │
;                                     │
;0xFFFF ──────────────────────────────┘
;

; TODO
; Address Interpreter
; This interpreter fetches and executes CFAs in threaded code. It
; repeatedly reads the next code field address (CFA) from a word’s threaded
; sequence and jumps to execute that code. This loop is the core of Forth’s
; indirect-threaded execution model.

; Dictionary entries

; Text Interpreter
; This interpreter parses input, finds words, executes or compiles
; Handles input strings from the user or program, searches the dictionary
; for each word, and either executes it immediately or compiles it into a
; new definition depending on the current state.

; ------------------
; Version constants - enough for homegrown project
; ------------------
major_version  equ 0
minor_version  equ 1
patch_version  equ 0

; -------------------------------------------------------------------
; Dictionary Entry Macro - used to build dictionary entries
; -------------------------------------------------------------------
; Defines the layout and construction of dictionary entries used by the
; Forth system. Each entry links to the previous one, stores its name and
; execution semantics, and includes an optional data field.
;
; Layout (64-bit fields unless noted):
;   LFA (link)   - pointer to previous dictionary entry
;   NFA (name)   - length-prefixed ASCII name
;   CFA (code)   - execution handler selector: PRIMITIVE | COLON | CONSTANT | VARIABLE
;   DFA (data)   - initial value or pointer; VARIABLES reside in writable memory
;
; Dictionary grows upward from dict_base, with HEAD pointing to the latest entry.
;
; Example usage:
;   DICT_ENTRY HEAD, 'dup', PRIMITIVE, NO_DFA
;   DICT_ENTRY dup, 'swap', PRIMITIVE, NO_DFA
;   DICT_ENTRY swap, 'rot', PRIMITIVE, NO_DFA
;   DICT_ENTRY rot, 'myvar', VARIABLE, 0
;   DICT_ENTRY myvar, 'myconst', CONSTANT, 123
;   DICT_ENTRY myconst, 'mycolon', COLON, NO_DFA

%macro DICT_ENTRY 4
    dw %1                          ; link field (LFA)
    db %2 + %2:len, %2             ; name field (NFA), length-prefixed
    %if %3 = PRIMITIVE
        dq $+2                     ; code field (CFA), points to primitive code
    %elif %3 = COLON
        dq docolon                 ; CFA points to colon handler
    %elif %3 = CONSTANT
        dq doconst                 ; CFA points to constant handler
    %elif %3 = VARIABLE
        dq dovar                   ; CFA points to variable handler
    %endif
    dw %4                          ; data field (DFA)
%endmacro

; -------------------------------------------------------------------
; Memory model design decisions
; -------------------------------------------------------------------
; Using a 16-bit virtual address space for dictionary and stacks
; within a 64-bit ELF64 environment. Memory is a single flat segment
; containing code, dictionary entries, and stack space.
;
; Growth directions:
; - Dictionary: upward from 0x0000
; - Data stack: downward from 0xFF00
; - Return stack: downward from 0xFE00
;
; This layout simplifies early development and allows expansion without
; changing allocation logic. Address calculations for words and runtime
; structures remain straightforward.

; -------------------------------------------------------------------
; Stacks and runtime data structures (bss and rodata)
; -------------------------------------------------------------------
; This implementation uses two software-managed stacks: a data stack and a return stack.
; The data stack holds operands, while the return stack holds return addresses, making
; nested word execution and colon definitions simpler. The hardware stack is left for
; CPU operations like interrupts and CALL/RET, keeping system control flow separate
; from Forth’s threaded execution.

section .bss

orig_termios resb 44        ; termios struct for saving original settings
raw_termios  resb 44        ; termios struct for raw settings

; Program stack pointers
dp:      resq 1    ; current data stack pointer
rp:      resq 1    ; current return stack pointer
latest:  resq 1    ; address of the most recent dictionary entry

; Program stack base addresses
dict_base         equ 0x0000  ; start of dictionary space
data_stack_base   equ 0xFF00  ; start of data stack
return_stack_base equ 0xFE00  ; start of return stack

section .rodata

; Static strings and constants used by the program. The banner is displayed
; at startup and its length is computed for use with write syscalls.
banner: db "ITSY64 v", major_version + '0', ".", minor_version + '0', ".", patch_version + '0', 10
banner_len: equ $ - banner


; -------------------------------------------------------------------
; Code begins (text)
; -------------------------------------------------------------------
section .text
global _start

; ---
; Pure assembly helpers
; ---

; Data stack operations (RAX holds value)
push_dp:
    mov rbx, [dp]       ; load current top of data stack
    sub rbx, 8          ; move down (stack grows downward)
    mov [rbx], rax      ; store value at new top
    mov [dp], rbx       ; update stack pointer
    ret

pop_dp:
    mov rbx, [dp]       ; load current top
    mov rax, [rbx]      ; read value
    add rbx, 8          ; move pointer up
    mov [dp], rbx       ; update stack pointer
    ret

; Return stack operations (RAX holds return address)
push_rp:
    mov rbx, [rp]       ; load current top of return stack
    sub rbx, 8
    mov [rbx], rax
    mov [rp], rbx
    ret

pop_rp:
    mov rbx, [rp]
    mov rax, [rbx]
    add rbx, 8
    mov [rp], rbx
    ret

; Print message at RSI with length RDX
print_msg:
    mov rax, 1          ; syscall: write
    mov rdi, 1          ; stdout
    syscall
    ret

; ---
; Linux x86-64 syscall helpers 
; ---

; Minimal routines for Forth-style I/O and terminal control:
;
; set_raw_mode:
;   Uses ioctl (rax=16) with TCSETS (esi=0x5402) on stdin (rdi=0) to apply
;   a modified termios struct that disables ICANON and ECHO, enabling
;   raw single-character input.
;
; restore_original_mode:
;   Uses ioctl (rax=16) with TCSETS on stdin to restore the saved
;   original termios settings.
;
; getchar:
;   Uses read (rax=0) on stdin (rdi=0) to read one byte into a temporary
;   buffer, then returns the character in al (zero-extended in rax).
;
; outchar:
;   Uses write (rax=1) on stdout (rdi=1) to write the low 8 bits of rax
;   (al) to a temporary buffer and output one byte.
;
; exit_program:
;   Uses exit (rax=60) with the code in rdi to terminate the program.

; ---
; _copy_orig_to_raw
; ---
; Retrieves the current terminal settings into orig_termios using
; the TCGETS ioctl, then copies the structure to raw_termios.
; Used as the basis for enabling raw mode.

_copy_orig_to_raw:

    ; Get current terminal attributes into orig_termios
    ; tcgetattr(0, &orig_termios)
    mov rax, 16             ; syscall number: ioctl
    mov rdi, 0              ; fd = stdin
    mov esi, 0x5401         ; TCGETS
    lea rdx, [orig_termios]
    syscall

    ; Copy orig_termios to raw_termios (44-byte termios struct)
    lea rsi, [orig_termios]
    lea rdi, [raw_termios]
    mov rcx, 44
    rep movsb
    ret

; ---
; set_raw_mode
; ---
; Copies the current terminal settings, clears ICANON and ECHO in
; c_lflag to enable raw mode, and applies the modified settings
; using the TCSETS ioctl.

set_raw_mode:
    call _copy_orig_to_raw

    ; modify raw_termios for raw mode
    ; Clear ICANON and ECHO in c_lflag
    mov rax, [raw_termios + 12]  ; c_lflag offset
    and rax, ~(0x00002 | 0x00008)
    mov [raw_termios + 12], rax

    ; ------------------------
    ; tcsetattr(0, &raw_termios)
    mov rax, 16                     ; syscall: ioctl
    mov rdi, 0                      ; fd = stdin
    mov esi, 0x5402                 ; TCSETS
    lea rdx, [raw_termios]
    syscall
    ret

; ---
; restore_original_mode
; ---
; Restores the saved terminal settings from orig_termios using
; the TCSETS ioctl.

restore_original_mode:
    ; restore original settings
    mov rax, 16                 ; syscall: ioctl
    mov rdi, 0                  ; fd = stdin
    mov esi, 0x5402             ; TCSETS
    lea rdx, [orig_termios]
    syscall
    ret

; ---
; getchar
; ---
; Reads a single byte from stdin using a temporary stack buffer.
; Returns the character in al (zero-extended in rax).

getchar:
    sub rsp, 16             ; align stack and reserve space
    mov rax, 0              ; sys_read
    mov rdi, 0              ; fd = stdin
    lea rsi, [rsp+8]        ; temporary buffer
    mov rdx, 1              ; read 1 byte
    syscall
    movzx rax, byte [rsp+8] ; return character in rax
    add rsp, 16
    ret


; ---
; outchar
; ---
; Writes the low 8 bits of rax (al) to stdout using a temporary
; stack buffer.

outchar:
    sub rsp, 16             ; align stack and reserve space
    mov [rsp+8], al         ; store byte in temp buffer
    mov rax, 1              ; syscall: write
    mov rdi, 1              ; fd = stdout
    lea rsi, [rsp+8]        ; buffer address
    mov rdx, 1              ; write 1 byte
    syscall
    add rsp, 16
    ret

; ---
; exit_program
; ---
; Exits the program using the value in rdi as the exit code.
exit_program:
    mov rax, 60        ; syscall: exit
    syscall

; -------------------------------------------------------------------
; Program entry point
; -------------------------------------------------------------------
; Enables raw mode at startup, then enters a loop that
; reads a character into al, echoes it, and exits on 'q'.

_start:
    
    call set_raw_mode

.loop:
    call getchar            ; returns char in al
    cmp al, 'q'             ; exit on 'q'
    je .exit
    call outchar            ; writes al to stdout


    jmp .loop

.exit:
    call restore_original_mode

    ; exit
    mov rdi, 0
    jmp exit_program        ; sys_exit



