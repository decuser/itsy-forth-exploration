; termloop.asm
; nasm -f elf64 termloop2.asm -o termloop2.o && ld termloop2.o -o termloop2

section .bss
orig_termios resb 44      ; termios struct for saving original settings
raw_termios  resb 44      ; termios struct for raw settings
c resb 1

section .text
global _start

_copy_orig_to_raw:

    ; ------------------------
    ; tcgetattr(0, &orig_termios)
    mov rax, 16             ; syscall number: ioctl
    mov rdi, 0              ; fd = stdin
    mov esi, 0x5401         ; TCGETS
    lea rdx, [orig_termios]
    syscall

    ; copy to raw_termios
    lea rsi, [orig_termios]
    lea rdi, [raw_termios]
    mov rcx, 44
    rep movsb
    ret

set_raw_mode:
    call _copy_orig_to_raw

    ; modify raw_termios for raw mode
    ; clear ICANON, ECHO
    mov rax, [raw_termios + 12]  ; c_lflag offset
    and rax, ~(0x00002 | 0x00008)
    mov [raw_termios + 12], rax

    ; ------------------------
    ; tcsetattr(0, &raw_termios)
    mov rax, 16
    mov rdi, 0
    mov esi, 0x5402             ; TCSETS
    lea rdx, [raw_termios]
    syscall
    ret

restore_original_mode:
    ; restore original settings
    mov rax, 16
    mov rdi, 0
    mov esi, 0x5402         ; TCSETS
    lea rdx, [orig_termios]
    syscall
    ret

getchar:
    ; read 1 byte
    mov rax, 0              ; sys_read
    mov rdi, 0              ; stdin
    lea rsi, [c]
    mov rdx, 1
    syscall
    ret

outchar:
    ; echo byte
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    lea rsi, [c]
    mov rdx, 1
    syscall
    ret

_start:
    
    call set_raw_mode

.loop:
    call getchar            ; in: byte in [c]
    call outchar            ; out: byte in [c]


    cmp byte [c], 'q'       ; check for 'q' in [c]
    je .exit
    jmp .loop

.exit:
    call restore_original_mode

    ; exit
    mov rax, 60             ; sys_exit
    xor rdi, rdi
    syscall

