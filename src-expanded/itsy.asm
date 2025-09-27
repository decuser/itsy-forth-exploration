; assemble time variable for the head of the linked list of words
%define head 0

; immediate mask
immediate equ 080h

; Format of the linked list entries

;  LFA         =  LINK FIELD ADDRESS: a pointer to the next DEA
;  NFA         =  NAME FIELD ADDRESS: a pointer to a name buffer
;  CFA         =  CODE FIELD ADDRESS : a pointer to executable code
;  DFA         =  DATA FIELD ADDRESS : a pointer to data, empty for primitives

; macros during dev
%macro header 4
%%head dw head
%define head %%head
%strlen %%count %1
db %3 + %%count,%1
cfa_ %+ %2 dw %4
%endmacro

%macro primitive 2-3 0
header %1,%2,%3,$+2
%endmacro

%macro colon 2-3 0
header %1,%2,%3,docolon
%endmacro

%macro constant 3
header %1,%2,0,doconst
dfa_ %+ %2 dw %3
%endmacro

%macro variable 3
header %1,%2,0,dovar
dfa_ %+ %2 dw %3
%endmacro

; this is a dos com, set origin to 100h and just to 
                    org 0100h
                    jmp cfa_abort+2

; -------------------
; Forth Variables
; -------------------
 
; | Name  | Description                                          |
; | ----- | ---------------------------------------------------- |
; | state | Current interpreter state                            |
; | >in   | Input buffer index / current parse position          |
; | #tib  | Number of characters in the input buffer             |
; | dp    | Data pointer for dictionary or memory allocation     |
; | base  | Numeric base for number parsing/output               |
; | last  | Most recently compiled word or last dictionary entry |

; forth word - state
lfa_state:          dw 0
nfa_state:          db 5,'state'
cfa_state:          dw dovar
dfa_state:          dw 0

; forth word - >in
lfa_to_in:          dw lfa_state
nfa_to_in:          db 3,'>in'
cfa_to_in:          dw  dovar
dfa_to_in:          dw 0

; forth word - #tib
lfa_ntib:           dw lfa_to_in
nfa_ntib:           db 4,'#tib'
cfa_ntib:           dw  dovar
dfa_ntib:           dw 0

; forth word - dp
lfa_dp:             dw lfa_ntib
nfa_dp:             db 2,'dp'
cfa_dp:             dw  dovar
dfa_dp:             dw freemem

; forth word - base
lfa_base:           dw lfa_dp
nfa_base:           db 4,'base'
cfa_base:           dw  dovar
dfa_base:           dw 10

; forth word - last
lfa_last:           dw lfa_base
nfa_last:           db 4,'last'
cfa_last:           dw  dovar
dfa_last:           dw final

; forth word - tib
lfa_tib:            dw lfa_last
nfa_tib:            db 3,'tib'
cfa_tib:            dw  doconst
dfa_tib:            dw 32768

;----------------------------------------------------
; System Foundational Primitives
;   Needed to initialize the Forth environment and 
;   support early runtime operations
;----------------------------------------------------
; -------------------
; Abort Primitive - Forth System Initialization Word
; -------------------

; forth word - abort (primitive)
lfa_abort:          dw lfa_tib      ; prev-link
nfa_abort:          db 5,'abort'    ; name len+string
cfa_abort:          dw $+2          ; xt

                    mov ax,word[dfa_ntib]
                    mov word[dfa_to_in],ax
                    xor bp,bp
                    mov word[dfa_state],bp
                    mov sp,-256
                    mov si,cfa_interpret+2
                    jmp next

; -------------------
; Compilation Primitives - Forth Dictionary Storage and Literal Embedding Words
; -------------------

; forth word - comma (primitive)
lfa_comma:          dw lfa_abort    ; prev-link
nfa_comma:          db 1,','        ; name len+string
cfa_comma:          dw $+2          ; xt

                    mov di,word[dfa_dp]
                    xchg ax,bx
                    stosw
                    mov word[dfa_dp],di
                    pop bx
                    jmp next

; forth word - lit (primitive)
lfa_lit:            dw lfa_comma    ; prev-link
nfa_lit:            db 3,'lit'      ; name len+string
cfa_lit:            dw $+2          ; xt

                    push bx
                    lodsw
                    xchg ax,bx
                    jmp next

; -------------------
; Stack Primitives - Forth Stack Manipulation Words
; -------------------

; forth word - rot (primitive)
lfa_rot:            dw lfa_lit      ; prev-link
nfa_rot:            db 3,'rot'      ; name len+string
cfa_rot:            dw $+2          ; xt

                    pop dx
                    pop ax
                    push dx
                    push bx
                    xchg ax,bx
                    jmp next

; forth word - drop (primitive)
lfa_drop:           dw lfa_rot      ; prev-link
nfa_drop:           db 4,'drop'     ; name len+string
cfa_drop:           dw $+2          ; xt

                    pop bx
                    jmp next

; forth word - dupe (primitive)
lfa_dup:            dw lfa_drop     ; prev-link
nfa_dup:            db 3,'dup'      ; name len+string
cfa_dup:            dw $+2          ; xt

                    push bx
                    jmp next

; forth word - swap (primitive)
lfa_swap:           dw lfa_dup      ; prev-link
nfa_swap:           db 4,'swap'     ; name len+string
cfa_swap:           dw $+2          ; xt

                    pop ax
                    push bx
                    xchg ax,bx
                    jmp next

; LEFT OFF HERE!
; set defined head to last primitive expanded during dev
%define head lfa_swap

; -------------------
; Math and Logic Primitives - Forth Arithmetic and Logical Words
; -------------------

        primitive '+',plus
        pop ax
        add bx,ax
        jmp next

        primitive '=',equals
        pop ax
        sub bx,ax
        sub bx,1
        sbb bx,bx
        jmp next

; -------------------
; Memory Access Primitives - Forth Peek and Poke Words
; -------------------

        primitive '@',fetch
        mov bx,word[bx]
        jmp next

        primitive '!',store 
        pop word[bx]
        pop bx
        jmp next

;----------------------------------------------------
; Inner Interpreter - Forth Fetch-and-Execute loop
;----------------------------------------------------

next    lodsw
        xchg di,ax
        jmp word[di]

;----------------------------------------------------
; Interpreter-Dependent Primitives
;   Rely on the inner interpreter being in place to
;   execute via code field addresses
;----------------------------------------------------

; -------------------
; Colon Flow Control Primitives - Forth Conditional and Unconditional Execution Words
; -------------------

        primitive '0branch',zero_branch
        lodsw
        test bx,bx
        jne zerob_z
        xchg ax,si
zerob_z pop bx
        jmp next

        primitive 'branch',branch
        mov si,word[si]
        jmp next

        primitive 'execute',execute
        mov di,bx
        pop bx
        jmp word[di]

        primitive 'exit',exit
        mov si,word[bp]
        inc bp
        inc bp
        jmp next

; -------------------
; String Primitives - Forth String Words
; -------------------

        primitive 'count',count
        inc bx
        push bx
        mov bl,byte[bx-1]
        mov bh,0
        jmp next

        primitive '>number',to_number
        pop di
        pop cx
        pop ax
to_numl test bx,bx
        je to_numz
        push ax
        mov al,byte[di]
        cmp al,'a'
        jc to_nums
        sub al,32
to_nums cmp al,'9'+1
        jc to_numg
        cmp al,'A'
        jc to_numh
        sub al,7
to_numg sub al,48
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
to_numz push ax
to_numh push cx
        push di
        jmp next

; -----------------------
; Terminal I/O Primitives - Forth I/O Words
; -----------------------

        primitive 'accept',accept
        pop di
        xor cx,cx
acceptl call getchar
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
acceptn cmp al,13
        je acceptz
        cmp cx,bx
        jne accepts
acceptb mov al,7
        call outchar
        jmp acceptl
accepts stosb
        inc cx
        call outchar
        jmp acceptl
acceptz jcxz acceptb
        mov al,13
        call outchar
        mov al,10
        call outchar
        mov bx,cx
        jmp next

        primitive 'word',word
        mov di,word[dfa_dp]
        push di
        mov dx,bx
        mov bx,word[dfa_tib]
        mov cx,bx
        add bx,word[dfa_to_in]
        add cx,word[dfa_ntib]
wordf   cmp cx,bx
        je wordz
        mov al,byte[bx]
        inc bx
        cmp al,dl
        je wordf
wordc   inc di
        mov byte[di],al
        cmp cx,bx
        je wordz
        mov al,byte[bx]
        inc bx
        cmp al,dl
        jne wordc
wordz   mov byte[di+1],32
        mov ax,word[dfa_dp]
        xchg ax,di
        sub ax,di
        mov byte[di],al
        sub bx,word[dfa_tib]
        mov word[dfa_to_in],bx
        pop bx
        jmp next

        primitive 'emit',emit
        xchg ax,bx
        call outchar
        pop bx
        jmp next

getchar mov ah,7
        int 021h
        mov ah,0
        ret

outchar xchg ax,dx
        mov ah,2
        int 021h
        ret

; -----------------------
; Search Primitive - Forth Dictionary Lookup Word
; -----------------------

        primitive 'find',find
        mov di,dfa_last
findl   push di
        push bx
        mov cl,byte[bx]
        mov ch,0
        inc cx
findc   mov al,byte[di+2]
        and al,07Fh
        cmp al,byte[bx]
        je findm
        pop bx
        pop di
        mov di,word[di]
        test di,di
        jne findl
findnf  push bx
        xor bx,bx
        jmp next
findm   inc di
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
findi   and ax,31
        add di,ax
        inc di
        push di
        jmp next

; -----------------------
; Colon Definitions - Forth Colon Start and End Words
; -----------------------

        colon ':',colon
        dw cfa_lit,-1,cfa_state,cfa_store,cfa_create
        dw cfa_do_semi_code
docolon dec bp
        dec bp
        mov word[bp],si
        lea si,[di+2]
        jmp next

        colon ';',semicolon,immediate
        dw cfa_lit,cfa_exit,cfa_comma,cfa_lit,0,cfa_state
        dw cfa_store,cfa_exit

; -----------------------
; Create and Code Definitions - Forth Low-Level Colon Words
; -----------------------

        colon 'create',create
        dw cfa_dp,cfa_fetch,cfa_last,cfa_fetch,cfa_comma
        dw cfa_last,cfa_store,cfa_lit,32,cfa_word,cfa_count
        dw cfa_plus,cfa_dp,cfa_store,cfa_lit,0,cfa_comma
        dw cfa_do_semi_code
dovar   push bx
        lea bx,[di+2]
        jmp next

        primitive '(;code)',do_semi_code
        mov di,word[dfa_last]
        mov al,byte[di+2]
        and ax,31
        add di,ax
        mov word[di+3],si
        mov si,word[bp]
        inc bp
        inc bp
        jmp next

; -----------------------
; Constant Definition - Forth Constant Word
; -----------------------

        colon 'constant',constant
        dw cfa_create,cfa_comma,cfa_do_semi_code
doconst push bx
        mov bx,word[di+2]
        jmp next

; -----------------------
; Outer Interpreter – Forth REPL (Process input, execute words, handle control flow)
; -----------------------

final:
        colon 'interpret',interpret
interpt dw cfa_ntib,cfa_fetch,cfa_to_in,cfa_fetch
        dw cfa_equals,cfa_zero_branch,intpar,cfa_tib
        dw cfa_lit,50,cfa_accept,cfa_ntib,cfa_store
        dw cfa_lit,0,cfa_to_in,cfa_store
intpar  dw cfa_lit,32,cfa_word,cfa_find,cfa_dup
        dw cfa_zero_branch,intnf,cfa_state,cfa_fetch
        dw cfa_equals,cfa_zero_branch,intexc,cfa_comma
        dw cfa_branch,intdone
intexc  dw cfa_execute,cfa_branch,intdone
intnf   dw cfa_dup,cfa_rot,cfa_count,cfa_to_number
        dw cfa_zero_branch,intskip,cfa_state,cfa_fetch
        dw cfa_zero_branch,intnc,cfa_last,cfa_fetch,cfa_dup
        dw cfa_fetch,cfa_last,cfa_store,cfa_dp,cfa_store
intnc   dw cfa_abort
intskip dw cfa_drop, cfa_drop, cfa_state, cfa_fetch
        dw cfa_zero_branch,intdone,cfa_lit,cfa_lit,cfa_comma
        dw cfa_comma
intdone dw cfa_branch,interpt

freemem:

