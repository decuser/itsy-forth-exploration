; =======================================
;  itsy64.asm - 64 bit port of itsy Forth
; =======================================

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

sigint_orig:   resq 1    ; stores original SIGINT handler pointer
sigact:        resb 16   ; minimal sigaction structure for installing handler
termios_orig:  resb 44   ; saved original terminal settings
termios_raw:   resb 44   ; modified terminal settings for raw mode


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
    sub qword [dp], 8            ; decrement data stack pointer
    mov [dp], rax                ; store value at new top
    ret

pop_dp:
    mov rax, [dp]                ; load value from top
    add qword [dp], 8            ; increment data stack pointer
    ret

; Return stack operations (RAX holds return address)
push_rp:
    sub qword [rp], 8           ; decrement return stack pointer
    mov [rp], rax               ; store return address
    ret

pop_rp:
    mov rax, [rp]               ; load return address
    add qword [rp], 8           ; increment return stack pointer
    ret

; Print message at RSI with length RDX
print_msg:
    mov rax, 1                  ; syscall: write
    mov rdi, 1                  ; stdout
    syscall
    ret

; ---
; Linux x86-64 syscall helpers 
; ---

; Minimal routines for Forth-style I/O and terminal control:
; sigint_handler: 
;   restores terminal and exits if Ctrl-C is pressed 
;
; install_sigint_handler:
;   sys_rt_sigaction (rax=13), rdi=SIGINT, rsi=new sigaction ptr,
;   rdx=old sigaction ptr, r10=sigsetsize; handles Ctrl-C to restore
;   terminal and exit
;
; set_raw_mode:
;   sys_ioctl (rax=16), rdi=stdin fd(0), rsi=termios struct ptr,
;   rdx=TCSETS; enables raw input mode for single-character reads
;
; restore_cooked_mode:
;   sys_ioctl (rax=16), rdi=stdin fd(0), rsi=original termios ptr,
;   rdx=TCSETS; restores original terminal settings
;
; getchar:
;   sys_read (rax=0), rdi=0(stdin), rsi=buffer, rdx=1; reads one byte
;   from stdin into rax
;
; outchar:
;   sys_write (rax=1), rdi=1(stdout), rsi=buffer, rdx=1; writes one byte
;   from rax to stdout
;
; exit_program:
;   sys_exit (rax=60), rdi=exit_code; exits with code in rdi


; Restore terminal settings on Ctrl-C and exit cleanly
sigint_handler:
    call restore_cooked_mode
    mov rax, 60        ; SYS_exit
    xor rdi, rdi       ; exit code 0
    syscall

; Installs a handler for SIGINT (Ctrl-C) that invokes sigint_handler
install_sigint_handler:
    mov rax, 13              ; syscall: rt_sigaction
    mov rdi, 2               ; SIGINT
    lea rsi, [sigact]        ; new sigaction struct
    lea rdx, [sigint_orig]   ; save old handler
    mov r10, 8               ; sigset size (bytes)
    syscall
    ret

; Switches terminal to raw mode by disabling canonical input and echo,
; and configuring VMIN/VTIME for single-character reads.
set_raw_mode:
    ; get current settings
    mov rax, 16            ; syscall: ioctl
    mov rdi, 0             ; stdin
    mov rsi, 0x5401        ; TCGETS
    lea rdx, [termios_orig]
    syscall

    ; copy original to raw buffer
    lea rsi, [termios_orig]
    lea rdi, [termios_raw]
    mov rcx, 44
.copy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .copy

    ; disable ICANON (offset 12 = c_lflag)
    mov ax, [termios_raw + 12]
    and ax, 0xFFFD        ; clear ICANON
    mov [termios_raw + 12], ax

    ; set VMIN=1, VTIME=0 (offsets 22, 23 in c_cc)
    mov byte [termios_raw + 22], 1
    mov byte [termios_raw + 23], 0

    ; apply modified settings
    mov rax, 16            ; syscall: ioctl
    mov rdi, 0             ; stdin
    mov rsi, 0x5402        ; TCSETS
    lea rdx, [termios_raw]
    syscall
    ret

; Restores the terminal to its original (cooked) settings
; saved before raw mode was enabled.
restore_cooked_mode:
    mov rax, 16            ; syscall: ioctl
    mov rdi, 0             ; stdin
    mov rsi, 0x5402        ; TCSETS
    lea rdx, [termios_orig]
    syscall
    ret

; Reads a single byte from stdin into rax using a temporary stack buffer.
getchar:
    mov rax, 0              ; syscall: read
    mov rdi, 0              ; stdin
    lea rsi, [rsp-8]        ; temporary buffer on stack
    mov rdx, 1              ; read 1 byte
    syscall
    movzx rax, byte [rsp-8] ; return character in rax
    ret

; Writes the low 8 bits of rax to stdout using a temporary stack buffer.
outchar:
    mov rax, 1            ; syscall: write
    mov rdi, 1            ; stdout
    lea rsi, [rsp-8]      ; temporary buffer on stack
    mov [rsp-8], al       ; store byte to buffer
    mov rdx, 1            ; write 1 byte
    syscall
    ret

; Exits the program with the code in rdi.
exit_program:
    mov rax, 60        ; syscall: exit
    syscall

; -------------------------------------------------------------------
; Program entry point
; -------------------------------------------------------------------
; Enables raw mode and installs SIGINT handler at start,
; prints the welcome banner, then enters a test loop that
; reads a character, echoes it, and exits on 'q'.

_start:

    call set_raw_mode     ; enable raw mode at program start
    call install_sigint_handler ; ensure Ctrl-C restores terminal

    ; display the welcome banner
    mov rsi, banner
    mov rdx, banner_len
    call print_msg

; test harness to test helper calls
.loop:
    call getchar      ; read one character into rax
    cmp al, 'q'
    je .quit
    call outchar      ; echo character
    jmp .loop

.quit:
    call restore_cooked_mode   ; restore terminal first
    mov al, 13     ; carriage return
    call outchar
    mov al, 10     ; newline
    call outchar
    mov rdi, 0
    call exit_program




