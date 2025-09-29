org 0100h
jmp cfa_abort+2     ; jump to abort code start (initialize the program)
lfa_state:          dw 0
nfa_state:          db 5,'state'
cfa_state:          dw dovar
dfa_state:          dw 0
lfa_to_in:          dw lfa_state
nfa_to_in:          db 3,'>in'
cfa_to_in:          dw  dovar
dfa_to_in:          dw 0
lfa_ntib:           dw lfa_to_in
nfa_ntib:           db 4,'#tib'
cfa_ntib:           dw  dovar
dfa_ntib:           dw 0
lfa_dp:             dw lfa_ntib
nfa_dp:             db 2,'dp'
cfa_dp:             dw  dovar
dfa_dp:             dw freemem
lfa_base:           dw lfa_dp
nfa_base:           db 4,'base'
cfa_base:           dw  dovar
dfa_base:           dw 10
lfa_last:           dw lfa_base
nfa_last:           db 4,'last'
cfa_last:           dw  dovar
dfa_last:           dw final
lfa_tib:            dw lfa_last
nfa_tib:            db 3,'tib'
cfa_tib:            dw  doconst
dfa_tib:            dw 32768
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
lfa_comma:          dw lfa_abort
nfa_comma:          db 1,','
cfa_comma:          dw $+2
                    mov di,word[dfa_dp]
                    xchg ax,bx
                    stosw
                    mov word[dfa_dp],di
                    pop bx
                    jmp next
lfa_lit:            dw lfa_comma
nfa_lit:            db 3,'lit'
cfa_lit:            dw $+2
                    push bx
                    lodsw
                    xchg ax,bx
                    jmp next
lfa_rot:            dw lfa_lit
nfa_rot:            db 3,'rot'
cfa_rot:            dw $+2
                    pop dx
                    pop ax
                    push dx
                    push bx
                    xchg ax,bx
                    jmp next
lfa_drop:           dw lfa_rot
nfa_drop:           db 4,'drop'
cfa_drop:           dw $+2
                    pop bx
                    jmp next
lfa_dup:            dw lfa_drop
nfa_dup:            db 3,'dup'
cfa_dup:            dw $+2
                    push bx
                    jmp next
lfa_swap:           dw lfa_dup
nfa_swap:           db 4,'swap'
cfa_swap:           dw $+2
                    pop ax
                    push bx
                    xchg ax,bx
                    jmp next
lfa_plus:           dw lfa_swap
nfa_plus:           db 1,'+'
cfa_plus:           dw $+2
                    pop ax
                    add bx,ax
                    jmp next
lfa_equals:         dw lfa_plus
nfa_equals:         db 1,'='
cfa_equals:         dw $+2
                    pop ax
                    sub bx,ax
                    sub bx,1
                    sbb bx,bx
                    jmp next
lfa_fetch:          dw lfa_equals
nfa_fetch:          db 1,'@'
cfa_fetch:          dw $+2
                    mov bx,word[bx]
                    jmp next
lfa_store:          dw lfa_fetch
nfa_store:          db 1,'!'
cfa_store:          dw $+2
                    pop word[bx]
                    pop bx
                    jmp next
lfa_zero_branch:    dw lfa_store
nfa_zero_branch:    db 7,'0branch'
cfa_zero_branch:    dw $+2
                    lodsw
                    test bx,bx
                    jne zerob_z
                    xchg ax,si
zerob_z:            pop bx
                    jmp next
lfa_branch:         dw lfa_zero_branch
nfa_branch:         db 6,'branch'
cfa_branch:         dw $+2
                    mov si,word[si]
                    jmp next
lfa_execute:        dw lfa_branch
nfa_execute:        db 7,'execute'
cfa_execute:        dw $+2
                    mov di,bx
                    pop bx
                    jmp word[di]
lfa_exit:           dw lfa_execute
nfa_exit:           db 4,'exit'
cfa_exit:           dw $+2
                    mov si,word[bp]
                    inc bp
                    inc bp
                    jmp next
lfa_count:          dw lfa_exit
nfa_count:          db 5,'count'
cfa_count:          dw $+2
                    inc bx
                    push bx
                    mov bl,byte[bx-1]
                    mov bh,0
                    jmp next
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
lfa_emit:           dw lfa_word
nfa_emit:           db 4,'emit'
cfa_emit:           dw $+2
                    xchg ax,bx
                    call outchar
                    pop bx
                    jmp next
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
lfa_semicolon:      dw lfa_colon
nfa_semicolon:      db 080H+1,';'       ; immediate+name len+string
cfa_semicolon:      dw docolon
                    dw cfa_lit,cfa_exit,cfa_comma,cfa_lit,0,cfa_state
                    dw cfa_store,cfa_exit
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
lfa_constant:       dw lfa_semicode
nfa_constant:       db 8,'constant'
cfa_constant:       dw docolon
                    dw cfa_create,cfa_comma,cfa_semicode
doconst:            push bx
                    mov bx,word[di+2]
                    jmp next
final:                                  ; start of the last word's dictionary header
lfa_interpret:      dw lfa_constant
nfa_interpret:      db 9,'interpret'
cfa_interpret:      dw docolon
interpt:            
                    dw cfa_ntib,cfa_fetch,cfa_to_in,cfa_fetch
                    dw cfa_equals,cfa_zero_branch,intpar,cfa_tib
                    dw cfa_lit,50,cfa_accept,cfa_ntib,cfa_store
                    dw cfa_lit,0,cfa_to_in,cfa_store
intpar:
                    dw cfa_lit,32,cfa_word,cfa_find,cfa_dup
                    dw cfa_zero_branch,intnf,cfa_state,cfa_fetch
                    dw cfa_equals,cfa_zero_branch,intexc,cfa_comma
                    dw cfa_branch,intdone
intexc:
                    dw cfa_execute,cfa_branch,intdone
intnf:
                    dw cfa_dup,cfa_rot,cfa_count,cfa_to_number
                    dw cfa_zero_branch,intskip,cfa_state,cfa_fetch
                    dw cfa_zero_branch,intnc,cfa_last,cfa_fetch,cfa_dup
                    dw cfa_fetch,cfa_last,cfa_store,cfa_dp,cfa_store
intnc:
                    dw cfa_abort
intskip:
                    dw cfa_drop, cfa_drop, cfa_state, cfa_fetch
                    dw cfa_zero_branch,intdone,cfa_lit,cfa_lit,cfa_comma  
                    dw cfa_comma
intdone:
                    dw cfa_branch,interpt
next:               lodsw               ; load word at [si] into ax, increment si by 2
                    xchg di,ax          ; di now holds the fetched cfa
                    jmp word[di]        ; indirect jump to the cfa
getchar:            mov ah,7
                    int 021h
                    mov ah,0
                    ret
outchar:            xchg ax,dx
                    mov ah,2
                    int 021h
                    ret
freemem:

