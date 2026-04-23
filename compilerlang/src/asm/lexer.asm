; =============================================================================
; lexer.asm  —  ZTA lang lexer  (PIE-safe, FFI-ready)
; extern "C": lex_source(src, token_out, sym_table, sym_ptr_inout) -> u64
;
; SysV AMD64 ABI:
;   RDI = src  (null-terminated source)
;   RSI = token_out  (*mut RawToken  [id:u64, val:u64])
;   RDX = sym_table  (*mut u8)
;   RCX = sym_ptr_inout (*mut u64)  — updated on return
; Returns RAX = number of tokens emitted
; =============================================================================
global lex_source

; --- token ids (must match ffi.rs / parser.rs) ---
T_IDENTIFIER  equ 1
KW_UNSAFE     equ 2
L_INT         equ 20
L_TRUE        equ 23
L_FALSE       equ 24
OP_ASSIGN     equ 30
OP_ADD        equ 31
OP_SUB        equ 32
OP_MUL        equ 33
OP_DIV        equ 34
OP_MOD        equ 35
OP_EQ         equ 40
OP_NEQ        equ 41
OP_LT         equ 42
OP_GT         equ 43
OP_LE         equ 44
OP_GE         equ 45
OP_AND        equ 46
OP_OR         equ 47
OP_NOT        equ 48
KW_IF         equ 50
KW_ELSE       equ 51
KW_WHILE      equ 52
KW_FOR        equ 53
KW_FN         equ 54
KW_RETURN     equ 55
KW_LET        equ 56
KW_PUB        equ 57
KW_IMPORT     equ 58
KW_STRUCT     equ 59
KW_AS         equ 60
SYM_LPAREN    equ 70
SYM_RPAREN    equ 71
SYM_LBRACE    equ 72
SYM_RBRACE    equ 73
SYM_LBRACKET  equ 74
SYM_RBRACKET  equ 75
SYM_COMMA     equ 76
SYM_COLON     equ 77
SYM_SEMI      equ 78
SYM_DOT       equ 79
SYM_ARROW     equ 80
SYM_AMP       equ 81

section .data
kw_table:
    db "if",     0, KW_IF
    db "else",   0, KW_ELSE
    db "while",  0, KW_WHILE
    db "for",    0, KW_FOR
    db "fn",     0, KW_FN
    db "return", 0, KW_RETURN
    db "let",    0, KW_LET
    db "pub",    0, KW_PUB
    db "import", 0, KW_IMPORT
    db "struct", 0, KW_STRUCT
    db "as",     0, KW_AS
    db "true",   0, L_TRUE
    db "false",  0, L_FALSE
    db "unsafe", 0, KW_UNSAFE
    db 0

section .bss
    word_buf  resb 256

section .text

; emit macro: write [id, 0] into token buffer
%macro EMIT1 1
    mov   qword [r14],     %1
    mov   qword [r14 + 8], 0
    add   r14, 16
    inc   rbx
%endmacro

; ---- lex_source ----
lex_source:
    push  rbp
    push  rbx
    push  r12
    push  r13
    push  r14
    push  r15

    mov   r15, rdi          ; source cursor
    mov   r14, rsi          ; token write ptr
    mov   r13, rdx          ; sym_table base
    mov   r12, [rcx]        ; sym_ptr (current end)
    push  rcx               ; save &sym_ptr_inout
    xor   rbx, rbx          ; token count

.loop:
    movzx rax, byte [r15]
    test  al, al
    jz    .done
    cmp   al, ' '
    je    .skip
    cmp   al, 9
    je    .skip
    cmp   al, 13
    je    .skip
    cmp   al, 10
    je    .skip
    cmp   al, '/'
    je    .slash
    cmp   al, '0'
    jl    .syms
    cmp   al, '9'
    jle   .num
    cmp   al, 'A'
    jl    .syms
    cmp   al, 'Z'
    jle   .ident
    cmp   al, 'a'
    jl    .syms
    cmp   al, 'z'
    jle   .ident
    cmp   al, '_'
    je    .ident
.syms:
    cmp   al, '('
    je    .c70
    cmp   al, ')'
    je    .c71
    cmp   al, '{'
    je    .c72
    cmp   al, '}'
    je    .c73
    cmp   al, '['
    je    .c74
    cmp   al, ']'
    je    .c75
    cmp   al, ','
    je    .c76
    cmp   al, ':'
    je    .c77
    cmp   al, ';'
    je    .c78
    cmp   al, '.'
    je    .c79
    cmp   al, '%'
    je    .c35
    cmp   al, '*'
    je    .c33
    cmp   al, '+'
    je    .c31
    cmp   al, '&'
    je    .and
    cmp   al, '|'
    je    .or
    cmp   al, '='
    je    .eq
    cmp   al, '!'
    je    .neq
    cmp   al, '<'
    je    .lt
    cmp   al, '>'
    je    .gt
    cmp   al, '-'
    je    .minus
    inc   r15
    jmp   .loop

; single-char symbols
.c70: EMIT1 SYM_LPAREN
    inc r15
    jmp .loop
.c71: EMIT1 SYM_RPAREN
    inc r15
    jmp .loop
.c72: EMIT1 SYM_LBRACE
    inc r15
    jmp .loop
.c73: EMIT1 SYM_RBRACE
    inc r15
    jmp .loop
.c74: EMIT1 SYM_LBRACKET
    inc r15
    jmp .loop
.c75: EMIT1 SYM_RBRACKET
    inc r15
    jmp .loop
.c76: EMIT1 SYM_COMMA
    inc r15
    jmp .loop
.c77: EMIT1 SYM_COLON
    inc r15
    jmp .loop
.c78: EMIT1 SYM_SEMI
    inc r15
    jmp .loop
.c79: EMIT1 SYM_DOT
    inc r15
    jmp .loop
.c35: EMIT1 OP_MOD
    inc r15
    jmp .loop
.c33: EMIT1 OP_MUL
    inc r15
    jmp .loop
.c31: EMIT1 OP_ADD
    inc r15
    jmp .loop

; compound symbols
.and:
    inc r15
    cmp byte [r15], '&'
    jne .and_single
    inc r15
    EMIT1 OP_AND
    jmp .loop
.and_single:
    EMIT1 SYM_AMP
    jmp .loop

.or:
    inc r15
    cmp byte [r15], '|'
    jne .loop
    inc r15
    EMIT1 OP_OR
    jmp .loop

.eq:
    inc r15
    cmp byte [r15], '='
    jne .eq_single
    inc r15
    EMIT1 OP_EQ
    jmp .loop
.eq_single:
    EMIT1 OP_ASSIGN
    jmp .loop

.neq:
    inc r15
    cmp byte [r15], '='
    jne .not_single
    inc r15
    EMIT1 OP_NEQ
    jmp .loop
.not_single:
    EMIT1 OP_NOT
    jmp .loop

.lt:
    inc r15
    cmp byte [r15], '='
    jne .lt_single
    inc r15
    EMIT1 OP_LE
    jmp .loop
.lt_single:
    EMIT1 OP_LT
    jmp .loop

.gt:
    inc r15
    cmp byte [r15], '='
    jne .gt_single
    inc r15
    EMIT1 OP_GE
    jmp .loop
.gt_single:
    EMIT1 OP_GT
    jmp .loop

.minus:
    inc r15
    cmp byte [r15], '>'
    jne .sub_single
    inc r15
    EMIT1 SYM_ARROW
    jmp .loop
.sub_single:
    EMIT1 OP_SUB
    jmp .loop

; comment or div
.slash:
    inc r15
    cmp byte [r15], '/'
    jne .div
.comment:
    movzx rax, byte [r15]
    test al, al
    jz .done
    cmp al, 10
    je .skip
    inc r15
    jmp .comment
.div:
    EMIT1 OP_DIV
    jmp .loop

.skip:
    inc r15
    jmp .loop

; ---- integer literal ----
.num:
    xor rax, rax
.num_l:
    movzx rdx, byte [r15]
    cmp dl, '0'
    jl .num_done
    cmp dl, '9'
    jg .num_done
    sub rdx, '0'
    imul rax, rax, 10
    add rax, rdx
    inc r15
    jmp .num_l
.num_done:
    mov qword [r14],     L_INT
    mov qword [r14 + 8], rax
    add r14, 16
    inc rbx
    jmp .loop

; ---- identifier / keyword ----
.ident:
    lea   r9, [rel word_buf]
    xor   r8, r8
.ident_cp:
    movzx rax, byte [r15]
    cmp al, ' '
    jbe .ident_done
    cmp al, '('
    je .ident_done
    cmp al, ')'
    je .ident_done
    cmp al, '{'
    je .ident_done
    cmp al, '}'
    je .ident_done
    cmp al, '['
    je .ident_done
    cmp al, ']'
    je .ident_done
    cmp al, ','
    je .ident_done
    cmp al, ';'
    je .ident_done
    cmp al, '+'
    je .ident_done
    cmp al, '-'
    je .ident_done
    cmp al, '*'
    je .ident_done
    cmp al, '/'
    je .ident_done
    cmp al, '='
    je .ident_done
    cmp al, '!'
    je .ident_done
    cmp al, '<'
    je .ident_done
    cmp al, '>'
    je .ident_done
    cmp al, '&'
    je .ident_done
    cmp al, '|'
    je .ident_done
    cmp al, '.'
    je .ident_done
    cmp al, ':'
    je .ident_done
    mov [r9], al
    inc r9
    inc r8
    inc r15
    jmp .ident_cp
.ident_done:
    mov byte [r9], 0
    test r8, r8
    jz .loop
    call kw_match
    test rax, rax
    jnz .emit_kw
    call sym_insert
    mov qword [r14],     T_IDENTIFIER
    mov qword [r14 + 8], rax
    add r14, 16
    inc rbx
    jmp .loop
.emit_kw:
    mov qword [r14],     rax
    mov qword [r14 + 8], 0
    add r14, 16
    inc rbx
    jmp .loop

.done:
    pop rcx
    mov [rcx], r12          ; update sym_ptr
    mov rax, rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; kw_match: word_buf -> RAX=id or 0
; ============================================================
kw_match:
    push r10
    push r11
    lea  r10, [rel kw_table]
.kw_try:
    cmp  byte [r10], 0
    je   .kw_fail
    lea  r11, [rel word_buf]
.kw_cmp:
    movzx rax, byte [r10]
    movzx rdx, byte [r11]
    cmp  al, dl
    jne  .kw_skip
    test al, al
    jz   .kw_hit
    inc  r10
    inc  r11
    jmp  .kw_cmp
.kw_hit:
    inc  r10
    movzx rax, byte [r10]
    pop  r11
    pop  r10
    ret
.kw_skip:
.kw_find0:
    cmp byte [r10], 0
    je  .kw_next
    inc r10
    jmp .kw_find0
.kw_next:
    add r10, 2
    jmp .kw_try
.kw_fail:
    xor rax, rax
    pop r11
    pop r10
    ret

; ============================================================
; sym_insert: word_buf -> RAX=address in sym_table (dedup)
; ============================================================
sym_insert:
    push r10
    push r11
    mov  r10, r13           ; scan start
    mov  r11, r12           ; scan end
.scan:
    cmp  r10, r11
    jae  .new_entry
    push r10
    lea  rax, [rel word_buf]
.cmp:
    movzx rdx, byte [r10]
    movzx rcx, byte [rax]
    cmp  dl, cl
    jne  .mismatch
    test dl, dl
    jz   .found
    inc  r10
    inc  rax
    jmp  .cmp
.found:
    pop  rax
    pop  r11
    pop  r10
    ret
.mismatch:
    pop  r10
.skip_entry:
    cmp  byte [r10], 0
    je   .next_entry
    inc  r10
    jmp  .skip_entry
.next_entry:
    inc  r10
    jmp  .scan
.new_entry:
    mov  rax, r12
    lea  r10, [rel word_buf]
.copy:
    movzx rdx, byte [r10]
    mov  [r12], dl
    inc  r12
    inc  r10
    test dl, dl
    jnz  .copy
    pop  r11
    pop  r10
    ret
