; ╔═╗                              
; ║ ║                              
; ║ ║    ╔═════╗ ╔╗╔╗ ╔═════╗ ╔══╗ 
; ║ ║ ╔╗ ║ ╔═╗ ║ ╚╬╬╝ ║ ╔═╗ ║ ║ ╔╝ 
; ║ ╚═╝║ ║ ║═══╣ ╔╬╬╗ ║ ║═══╣ ║ ║  
; ╚════╝ ╚═════╝ ╚╝╚╝ ╚═════╝ ╚═╝

section .data

    ; ========================================================================
    ; SYSTEM TYPÓW
    ; ========================================================================
    T_I8          equ 10
    T_I32         equ 11
    T_I64         equ 12
    T_F32         equ 13
    T_STR         equ 14
    T_BOOL        equ 15
    T_VOID        equ 16
    T_PTR         equ 17
    T_IDENTIFIER  equ 1        ; Identyfikator użytkownika (nie słowo kluczowe)


    ; ========================================================================
    ; LITERAŁY
    ; ========================================================================
    L_INT         equ 20
    L_FLOAT       equ 21
    L_STR         equ 22
    L_TRUE        equ 23
    L_FALSE       equ 24

    ; ========================================================================
    ; OPERATORY POJEDYNCZE I ZŁOŻONE
    ; ========================================================================
    OP_ASSIGN     equ 30    ; =
    OP_ADD        equ 31    ; +
    OP_SUB        equ 32    ; -
    OP_MUL        equ 33    ; *
    OP_DIV        equ 34    ; /
    OP_MOD        equ 35    ; %
    OP_EQ         equ 40    ; ==
    OP_NEQ        equ 41    ; !=
    OP_LT         equ 42    ; <
    OP_GT         equ 43    ; >
    OP_LE         equ 44    ; <=
    OP_GE         equ 45    ; >=
    OP_AND        equ 46    ; &&
    OP_OR         equ 47    ; ||
    OP_NOT        equ 48    ; !
    
    ; ========================================================================
    ; SŁOWA KLUCZOWE
    ; ========================================================================
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
    KW_TRUE       equ 23    ; "true"  → dzieli stałą z L_TRUE
    KW_FALSE      equ 24    ; "false" → dzieli stałą z L_FALSE
    KW_UNSAFE   equ 2
    ; ========================================================================
    ; SYMBOLE I INTERPUNKCJA
    ; ========================================================================
    SYM_LPAREN    equ 70    ; (
    SYM_RPAREN    equ 71    ; )
    SYM_LBRACE    equ 72    ; {
    SYM_RBRACE    equ 73    ; }
    SYM_LBRACKET  equ 74    ; [
    SYM_RBRACKET  equ 75    ; ]
    SYM_COMMA     equ 76    ; ,
    SYM_COLON     equ 77    ; :
    SYM_SEMI      equ 78    ; ;
    SYM_DOT       equ 79    ; .
    SYM_ARROW     equ 80    ; ->
    SYM_AMP       equ 81    ; &

    ; ========================================================================
    ; TABLICA SŁÓW KLUCZOWYCH (pary: tekst_z_null, ID)
    ; Format: db "słowo", 0, <ID jako bajt>
    ; Sentinel: db 0 (puste słowo = koniec tabeli)
    ; ========================================================================
    kw_table:
        db "if",     0 ; offset +0
        db KW_IF       ; ID
        db "else",   0
        db KW_ELSE
        db "while",  0
        db KW_WHILE
        db "for",    0
        db KW_FOR
        db "fn",     0
        db KW_FN
        db "return", 0
        db KW_RETURN
        db "let",    0
        db KW_LET
        db "pub",    0
        db KW_PUB
        db "import", 0
        db KW_IMPORT
        db "struct", 0
        db KW_STRUCT
        db "as",     0
        db KW_AS
        db "true",   0
        db KW_TRUE
        db "false",  0
        db KW_FALSE
        db 0           ; ← sentinel: koniec tabeli

    ; Przykładowy kod źródłowy do testu
    source_code db "pub fn main(2) { let x = 125 // komentarz", 10
                db "if x == 125 { return x } }", 0

section .bss

    ; ========================================================================
    ; 1. BUFOR WEJŚCIOWY
    ; ========================================================================
    source_buffer    resb 65536
    source_size      resq 1

    ; ========================================================================
    ; 2. STRUMIEŃ TOKENÓW  [ID:8B | VALUE:8B] na token
    ; ========================================================================
    token_stream     resb 32768    ; miejsce na 2048 tokenów
    token_count      resq 1

    ; ========================================================================
    ; 3. TABLICA SYMBOLI — surowe nazwy (null-terminated)
    ; ========================================================================
    symbol_table     resb 32768
    symbol_ptr       resq 1

    ; ========================================================================
    ; 4. BUFOR ROBOCZY — tymczasowe słowo podczas skanowania identyfikatora
    ; ========================================================================
    word_buf         resb 256
    word_len         resq 1

    ; ========================================================================
    ; 5. STOS VM
    ; ========================================================================
    data_stack       resq 256
    stack_ptr        resq 1

section .text
    global _start

; ============================================================================
; MAKRA POMOCNICZE
; Emit token (ID w rbx, VALUE w rcx) do [rdi], przesuwa rdi, inkrementuje r12
; ============================================================================
%macro EMIT_TOKEN 0
    mov  qword [rdi],     rbx   ; ID
    mov  qword [rdi + 8], rcx   ; VALUE / adres
    add  rdi, 16
    inc  r12
%endmacro

; ============================================================================
; PUNKT WEJŚCIA
; ============================================================================
_start:
    ; Inicjalizacja
    mov  qword [symbol_ptr], symbol_table
    mov  rsi, source_code          ; RSI = czytamy stąd
    mov  rdi, token_stream         ; RDI = piszemy tutaj
    xor  r12, r12                  ; R12 = licznik tokenów

; ============================================================================
; GŁÓWNA PĘTLA DISPATCHERA
; ============================================================================
main_loop:
    movzx rax, byte [rsi]          ; Pobierz bieżący znak

    ; Koniec łańcucha (NULL) → koniec leksowania
    test  al, al
    jz    end_lexing

    ; --- Białe znaki: spacja, tab (\t=9), CR (\r=13), LF (\n=10) ---
    cmp   al, ' '
    je    skip_char
    cmp   al, 9
    je    skip_char
    cmp   al, 13
    je    skip_char
    cmp   al, 10
    je    skip_char

    ; --- Komentarz // ---
    cmp   al, '/'
    je    check_comment_or_div

    ; --- Cyfra 0-9 ---
    cmp   al, '0'
    jl    check_single_symbols
    cmp   al, '9'
    jle   handle_number

    ; --- Litery i podkreślenie (identyfikatory / słowa kluczowe) ---
check_identifier_start:
    cmp   al, 'A'
    jl    check_single_symbols
    cmp   al, 'Z'
    jle   handle_identifier
    cmp   al, 'a'
    jl    check_single_symbols
    cmp   al, 'z'
    jle   handle_identifier
    cmp   al, '_'
    je    handle_identifier

; --- Symbole pojedyncze i złożone ---
check_single_symbols:
    cmp   al, '('
    je    .emit_lparen
    cmp   al, ')'
    je    .emit_rparen
    cmp   al, '{'
    je    .emit_lbrace
    cmp   al, '}'
    je    .emit_rbrace
    cmp   al, '['
    je    .emit_lbracket
    cmp   al, ']'
    je    .emit_rbracket
    cmp   al, ','
    je    .emit_comma
    cmp   al, ':'
    je    .emit_colon
    cmp   al, ';'
    je    .emit_semi
    cmp   al, '.'
    je    .emit_dot
    cmp   al, '%'
    je    .emit_mod
    cmp   al, '*'
    je    .emit_mul
    cmp   al, '+'
    je    .emit_add
    cmp   al, '&'
    je    check_and
    cmp   al, '|'
    je    check_or
    cmp   al, '='
    je    check_eq
    cmp   al, '!'
    je    check_neq
    cmp   al, '<'
    je    check_le
    cmp   al, '>'
    je    check_ge
    cmp   al, '-'
    je    check_arrow_or_sub

    ; Nieznany znak — pomijamy
    inc   rsi
    jmp   main_loop

.emit_lparen:
    mov rbx, SYM_LPAREN  ; xor rcx,rcx jest OK — VALUE nieużywane
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_rparen:
    mov rbx, SYM_RPAREN
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_lbrace:
    mov rbx, SYM_LBRACE
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_rbrace:
    mov rbx, SYM_RBRACE
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_lbracket:
    mov rbx, SYM_LBRACKET
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_rbracket:
    mov rbx, SYM_RBRACKET
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_comma:
    mov rbx, SYM_COMMA
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_colon:
    mov rbx, SYM_COLON
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_semi:
    mov rbx, SYM_SEMI
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_dot:
    mov rbx, SYM_DOT
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_mod:
    mov rbx, OP_MOD
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_mul:
    mov rbx, OP_MUL
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

.emit_add:
    mov rbx, OP_ADD
    xor rcx, rcx
    inc rsi
    EMIT_TOKEN
    jmp main_loop

; ============================================================================
; SYMBOLE ZŁOŻONE — każdy sprawdza następny znak (peek)
; ============================================================================

; && lub &
check_and:
    inc   rsi
    cmp   byte [rsi], '&'
    jne   .single_amp
    inc   rsi
    mov   rbx, OP_AND
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop
.single_amp:
    mov   rbx, SYM_AMP
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop

; || lub błąd (pojedyncze | nie istnieje w tej składni — pomijamy)
check_or:
    inc   rsi
    cmp   byte [rsi], '|'
    jne   .skip_pipe
    inc   rsi
    mov   rbx, OP_OR
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop
.skip_pipe:
    ; Pojedyncze | — nieznany operator, ignorujemy
    jmp   main_loop

; == lub =
check_eq:
    inc   rsi
    cmp   byte [rsi], '='
    jne   .single_assign
    inc   rsi
    mov   rbx, OP_EQ
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop
.single_assign:
    mov   rbx, OP_ASSIGN
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop

; != lub !
check_neq:
    inc   rsi
    cmp   byte [rsi], '='
    jne   .single_not
    inc   rsi
    mov   rbx, OP_NEQ
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop
.single_not:
    mov   rbx, OP_NOT
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop

; <= lub <
check_le:
    inc   rsi
    cmp   byte [rsi], '='
    jne   .single_lt
    inc   rsi
    mov   rbx, OP_LE
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop
.single_lt:
    mov   rbx, OP_LT
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop

; >= lub >
check_ge:
    inc   rsi
    cmp   byte [rsi], '='
    jne   .single_gt
    inc   rsi
    mov   rbx, OP_GE
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop
.single_gt:
    mov   rbx, OP_GT
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop

; -> lub -
check_arrow_or_sub:
    inc   rsi
    cmp   byte [rsi], '>'
    jne   .single_sub
    inc   rsi
    mov   rbx, SYM_ARROW
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop
.single_sub:
    mov   rbx, OP_SUB
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop

; ============================================================================
; KOMENTARZE  // ... \n
; Wywoływane gdy bieżący znak to '/'.
; Sprawdzamy następny: jeśli też '/' → ignorujemy do końca linii.
; Jeśli nie → emitujemy OP_DIV.
; ============================================================================
check_comment_or_div:
    inc   rsi                      ; RSI wskazuje na drugi znak po '/'
    cmp   byte [rsi], '/'
    jne   .emit_div

.skip_line:
    ; Pomijamy znaki aż do \n (10) lub NULL (0)
    movzx rax, byte [rsi]
    test  al, al
    jz    end_lexing               ; EOF w trakcie komentarza → koniec
    cmp   al, 10                   ; \n
    je    .comment_done
    inc   rsi
    jmp   .skip_line

.comment_done:
    inc   rsi                      ; Konsumujemy sam \n
    jmp   main_loop

.emit_div:
    ; Nie był to komentarz — emitujemy OP_DIV (RSI już minął '/')
    mov   rbx, OP_DIV
    xor   rcx, rcx
    EMIT_TOKEN
    jmp   main_loop

; ============================================================================
; POMIŃ BIAŁY ZNAK
; ============================================================================
skip_char:
    inc   rsi
    jmp   main_loop

; ============================================================================
; OBSŁUGA LICZB  (L_INT)
; Poprawka: kończy się na KAŻDYM znaku nie-cyfrowym (w tym nawiasie),
; nie konsumuje tego znaku — wróci do dispatchera, który obsłuży go normalnie.
; ============================================================================
handle_number:
    xor   rbx, rbx                 ; RBX = akumulowana wartość
.num_loop:
    movzx rax, byte [rsi]
    cmp   al, '0'
    jl    .num_done
    cmp   al, '9'
    jg    .num_done
    sub   rax, '0'
    imul  rbx, rbx, 10
    add   rbx, rax
    inc   rsi
    jmp   .num_loop
.num_done:
    ; RSI NADAL wskazuje na znak po liczbie (np. ')') — dispatcher go obsłuży
    mov   rcx, rbx                 ; VALUE = obliczona liczba
    mov   rbx, L_INT               ; ID = L_INT (20)
    EMIT_TOKEN
    jmp   main_loop

; ============================================================================
; OBSŁUGA IDENTYFIKATORÓW I SŁÓW KLUCZOWYCH
; 1. Kopiuj słowo do word_buf
; 2. Sprawdź czy to słowo kluczowe (keyword_match)
; 3. Jeśli nie — sprawdź deduplikację w symbol_table, wstaw jeśli nowe
; ============================================================================
handle_identifier:
    ; --- Krok 1: skopiuj słowo do word_buf ---
    mov   r9, word_buf             ; R9 = wskaźnik zapisu w buforze
    xor   r8, r8                   ; R8 = długość słowa
.copy_word:
    movzx rax, byte [rsi]
    ; Słowo kończy się: spacja, tab, CR, LF, NULL lub symbol interpunkcyjny
    cmp   al, ' '
    jbe   .copy_done               ; ≤ ' ' (obejmuje ASCII 0..32)
    ; Sprawdź czy to symbol który powinien zakończyć identyfikator
    cmp   al, '('
    je    .copy_done
    cmp   al, ')'
    je    .copy_done
    cmp   al, '{'
    je    .copy_done
    cmp   al, '}'
    je    .copy_done
    cmp   al, '['
    je    .copy_done
    cmp   al, ']'
    je    .copy_done
    cmp   al, ','
    je    .copy_done
    cmp   al, ';'
    je    .copy_done
    cmp   al, ':'
    je    .copy_done
    cmp   al, '.'
    je    .copy_done
    cmp   al, '+'
    je    .copy_done
    cmp   al, '-'
    je    .copy_done
    cmp   al, '*'
    je    .copy_done
    cmp   al, '/'
    je    .copy_done
    cmp   al, '='
    je    .copy_done
    cmp   al, '!'
    je    .copy_done
    cmp   al, '<'
    je    .copy_done
    cmp   al, '>'
    je    .copy_done
    cmp   al, '&'
    je    .copy_done
    cmp   al, '|'
    je    .copy_done
    ; Znak należy do identyfikatora — kopiuj
    mov   [r9], al
    inc   r9
    inc   r8
    inc   rsi
    jmp   .copy_word
.copy_done:
    mov   byte [r9], 0             ; NULL-terminate word_buf
    mov   [word_len], r8

    ; Zabezpieczenie: puste słowo (długość 0) — pomijamy
    test  r8, r8
    jz    main_loop

    ; --- Krok 2: sprawdź czy to słowo kluczowe ---
    call  keyword_match            ; Zwraca RAX = ID lub 0 (nie znaleziono)
    test  rax, rax
    jnz   .emit_keyword

    ; --- Krok 3: identyfikator — wyszukaj/wstaw w symbol_table ---
    call  symtab_lookup_or_insert  ; Zwraca RAX = adres w symbol_table
    mov   rbx, T_IDENTIFIER
    mov   rcx, rax
    EMIT_TOKEN
    jmp   main_loop

.emit_keyword:
    mov   rbx, rax
    xor   rcx, rcx                 ; Słowa kluczowe nie mają VALUE
    EMIT_TOKEN
    jmp   main_loop

; ============================================================================
; PODPROCEDURA: keyword_match
; Wejście:  word_buf zawiera NULL-terminated słowo (długość w word_len)
; Wyjście:  RAX = ID słowa kluczowego, lub 0 jeśli nie znaleziono
; Używa: R10 (wskaźnik po tabeli), R11 (wskaźnik po word_buf), R14, R15
; ============================================================================
keyword_match:
    push  r10
    push  r11
    push  r14
    push  r15
    mov   r10, kw_table            ; R10 = bieżąca pozycja w tabeli

.kw_next_entry:
    cmp   byte [r10], 0            ; Sentinel — koniec tabeli
    je    .kw_not_found

    ; Porównaj word_buf z bieżącym wpisem
    mov   r11, word_buf            ; R11 = bieżąca pozycja w word_buf
    mov   r14, r10                 ; R14 = kopia wskaźnika do wpisu w tabeli

.kw_cmp_loop:
    movzx r15, byte [r14]          ; Znak z tabeli
    movzx rax, byte [r11]          ; Znak z word_buf
    cmp   r15b, al
    jne   .kw_mismatch
    test  r15b, r15b               ; Oba NULL → dopasowanie
    jz    .kw_match
    inc   r14
    inc   r11
    jmp   .kw_cmp_loop

.kw_match:
    ; R14 wskazuje na NULL-terminator wpisu, zaraz za nim ID
    inc   r14
    movzx rax, byte [r14]          ; RAX = ID
    pop   r15
    pop   r14
    pop   r11
    pop   r10
    ret

.kw_mismatch:
    ; Przesuń R10 za bieżący wpis: znajdź koniec stringa (NULL) + 1 bajt ID
.skip_entry:
    cmp   byte [r10], 0
    je    .skip_id
    inc   r10
    jmp   .skip_entry
.skip_id:
    add   r10, 2                   ; +1 za NULL, +1 za bajt ID
    jmp   .kw_next_entry

.kw_not_found:
    xor   rax, rax
    pop   r15
    pop   r14
    pop   r11
    pop   r10
    ret

; ============================================================================
; PODPROCEDURA: symtab_lookup_or_insert
; Wejście:  word_buf = NULL-terminated słowo
; Wyjście:  RAX = adres istniejącego lub nowo wstawionego wpisu w symbol_table
; Używa:    R10, R11, R13, R14, R15
; Gwarancja: każda unikalna nazwa ma dokładnie jeden adres w tablicy symboli.
; ============================================================================
symtab_lookup_or_insert:
    push  r10
    push  r11
    push  r13
    push  r14
    push  r15

    mov   r13, symbol_table        ; R13 = początek tablicy symboli
    mov   r14, [symbol_ptr]        ; R14 = koniec (wolna przestrzeń)

    ; Iteruj po wszystkich wpisach w tabeli symboli
    ; Każdy wpis to NULL-terminated string
.lookup_loop:
    cmp   r13, r14                 ; Dotarliśmy do końca tablicy → nie znaleziono
    jae   .insert_new

    ; Porównaj r13 z word_buf
    mov   r10, r13
    mov   r11, word_buf
.cmp_sym_loop:
    movzx r15, byte [r10]
    movzx rax, byte [r11]
    cmp   r15b, al
    jne   .sym_mismatch
    test  r15b, r15b               ; Oba NULL → pasuje
    jz    .sym_found
    inc   r10
    inc   r11
    jmp   .cmp_sym_loop

.sym_found:
    mov   rax, r13                 ; RAX = adres istniejącego wpisu
    pop   r15
    pop   r14
    pop   r13
    pop   r11
    pop   r10
    ret

.sym_mismatch:
    ; Przesuń R13 za bieżący wpis (do następnego NULL+1)
.skip_sym:
    cmp   byte [r13], 0
    je    .sym_next
    inc   r13
    jmp   .skip_sym
.sym_next:
    inc   r13                      ; Pomiń sam NULL
    jmp   .lookup_loop

.insert_new:
    ; Nowe słowo — wstaw do tablicy symboli
    mov   r10, [symbol_ptr]        ; R10 = miejsce zapisu
    mov   rax, r10                 ; RAX = adres nowego wpisu (wynik)
    mov   r11, word_buf
.copy_to_sym:
    movzx r15, byte [r11]
    mov   [r10], r15b
    inc   r10
    inc   r11
    test  r15b, r15b               ; Kopiuj włącznie z NULL
    jnz   .copy_to_sym
    mov   [symbol_ptr], r10        ; Zaktualizuj wskaźnik wolnego miejsca

    pop   r15
    pop   r14
    pop   r13
    pop   r11
    pop   r10
    ret

; ============================================================================
; KONIEC LEKSOWANIA
; ============================================================================
end_lexing:
    mov   [token_count], r12

    ; Wyjście z procesu (Linux syscall 60)
    mov   rax, 60
    xor   rdi, rdi
    syscall


; ================================================
; ╔═════╗                                 
; ║ ╔═╗ ║                                 
; ║ ╚═╝ ║ ╔════╗  ╔══╗ ╔═══╗ ╔═════╗ ╔══╗ 
; ║ ╔═══╝ ║ ╔╗ ║  ║ ╔╝ ║ ══╣ ║ ╔═╗ ║ ║ ╔╝ 
; ║ ║     ║ ╚╝ ╚╗ ║ ║  ╠══ ║ ║ ║═══╣ ║ ║  
; ╚═╝     ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═╝
; ============================================================================
; PARSER v1.0 — x86-64 Linux NASM
; Czyta token_stream (wyprodukowany przez lexer_v2), buduje węzły AST
; w ast_arena. Obsługuje: fn, let, return, if/else, while, wyrażenia
; binarne z priorytetami (Pratt), łańcuchy kropkowe (a.b()), lifetime.
;
; REJESTR R15 = kursor tokenów (wskaźnik na bieżący token w token_stream)
; REJESTR R14 = wskaźnik następnego wolnego węzła w ast_arena
;
; WĘZEŁ AST = 48 bajtów:
;   +0  type     (QWORD) — NODE_* poniżej
;   +8  left     (QWORD) — wskaźnik lewego potomka (adres w ast_arena)
;   +16 right    (QWORD) — wskaźnik prawego potomka
;   +24 value    (QWORD) — dla NODE_INT: liczba; dla NODE_BINOP: op
;   +32 sym_addr (QWORD) — dla NODE_IDENT/NODE_FN: adres w symbol_table
;   +40 lifetime (QWORD) — dla NODE_FN: wartość L_V z nagłówka
; ============================================================================

; ============================================================================
; ŁĄCZONE STAŁE Z LEXERA (muszą być zgodne z lexer_v2.asm)
; ============================================================================

; Typy tokenów
T_IDENTIFIER  equ 1
L_INT         equ 20
L_STR         equ 22
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

; ============================================================================
; TYPY WĘZŁÓW AST
; ============================================================================
NODE_FN       equ 1    ; definicja funkcji
NODE_BLOCK    equ 2    ; blok { instrukcji }
NODE_LET      equ 3    ; let x = expr
NODE_ASSIGN   equ 4    ; x = expr
NODE_RETURN   equ 5    ; return expr
NODE_IF       equ 6    ; if cond { } else { }
NODE_WHILE    equ 7    ; while cond { }
NODE_CALL     equ 8    ; wywołanie funkcji: f(args)
NODE_INT      equ 9    ; literał całkowity
NODE_IDENT    equ 10   ; identyfikator (zmienna)
NODE_BINOP    equ 11   ; operacja binarna: left OP right
NODE_UNOP     equ 12   ; operacja unarna: OP right
NODE_CHAIN    equ 13   ; łańcuch kropkowy: left.right
NODE_BOOL     equ 14   ; true / false
NODE_STR      equ 15   ; literał string
NODE_ARG_LIST equ 16   ; lista argumentów (linked list przez right)
NODE_NULL     equ 0    ; pusty węzeł (brak potomka)

; Rozmiar jednego węzła
AST_NODE_SIZE equ 48

; Priorytety operatorów (dla Pratt parsera)
; Wyższy = wiąże mocniej (najpierw)
PREC_NONE     equ 0
PREC_ASSIGN   equ 1    ; =
PREC_OR       equ 2    ; ||
PREC_AND      equ 3    ; &&
PREC_EQUAL    equ 4    ; == !=
PREC_COMPARE  equ 5    ; < > <= >=
PREC_ADD      equ 6    ; + -
PREC_MUL      equ 7    ; * / %
PREC_UNARY    equ 8    ; ! -  (prefix)
PREC_CALL     equ 9    ; () .  (postfix)

; ============================================================================
; Błędy parsera (kody wyjścia)
; ============================================================================
ERR_EXPECTED_IDENT  equ 1
ERR_EXPECTED_LPAREN equ 2
ERR_EXPECTED_RPAREN equ 3
ERR_EXPECTED_LBRACE equ 4
ERR_EXPECTED_RBRACE equ 5
ERR_EXPECTED_SEMI   equ 6
ERR_EXPECTED_ASSIGN equ 7
ERR_UNEXPECTED_EOF  equ 8
ERR_EXPECTED_INT    equ 9

section .bss
    ; Strumień tokenów (wypełniany przez lexer)
    ; extern token_stream, token_count

    ; AST Arena — tu lądują węzły
    ast_arena        resb 131072    ; 128KB = ~2730 węzłów po 48B
    ast_node_count   resq 1         ; liczba zaalokowanych węzłów

    ; Korzeń AST (adres pierwszego NODE_FN lub NODE_BLOCK)
    ast_root         resq 1

    ; Bufor błędu parsera
    parse_error_code resq 1
    parse_error_tok  resq 1         ; adres tokena przy którym wystąpił błąd

section .text

; ============================================================================
; MAKRA POMOCNICZE
; ============================================================================

; Pobierz ID bieżącego tokena → RAX
%macro TOKEN_ID 0
    mov rax, [r15]
%endmacro

; Pobierz VALUE bieżącego tokena → RAX
%macro TOKEN_VAL 0
    mov rax, [r15 + 8]
%endmacro

; Przesuń kursor na następny token
%macro ADVANCE 0
    add r15, 16
%endmacro

; ============================================================================
; ALOKACJA WĘZŁA AST
; Wejście:  RDI = type (NODE_*)
; Wyjście:  RAX = adres nowego węzła, wszystkie pola wyzerowane
; Niszczy:  RCX, RDI
; ============================================================================
ast_alloc:
    push  rbx
    mov   rbx, r14                 ; Zapisz adres nowego węzła
    ; Zeruj 48 bajtów
    mov   qword [r14],      0
    mov   qword [r14 + 8],  0
    mov   qword [r14 + 16], 0
    mov   qword [r14 + 24], 0
    mov   qword [r14 + 32], 0
    mov   qword [r14 + 40], 0
    ; Zapisz typ
    mov   qword [r14], rdi
    ; Przesuń wskaźnik areny
    add   r14, AST_NODE_SIZE
    inc   qword [ast_node_count]
    mov   rax, rbx                 ; Zwróć adres węzła
    pop   rbx
    ret

; ============================================================================
; RAPORTOWANIE BŁĘDU — wypisz kod i zakończ
; ============================================================================
parse_error:
    mov   [parse_error_code], rdi
    mov   [parse_error_tok],  r15
    mov   rax, 60
    syscall                        ; exit(error_code)

; ============================================================================
; PUNKT WEJŚCIA PARSERA
; Zakłada że R15 = token_stream (ustaw przed wywołaniem)
; Zakłada że R14 = ast_arena     (ustaw przed wywołaniem)
; ============================================================================
parse_program:
    ; Inicjalizacja
    mov   qword [ast_node_count], 0

.top_loop:
    TOKEN_ID
    test  rax, rax
    jz    .program_done            ; TOKEN_ID == 0 → EOF

    cmp   rax, KW_PUB
    je    .skip_pub                ; "pub" → zignoruj, dalej

    cmp   rax, KW_FN
    je    .do_fn

    ; Nieznany token na poziomie programu — pomijamy
    ADVANCE
    jmp   .top_loop

.skip_pub:
    ADVANCE
    jmp   .top_loop

.do_fn:
    call  parse_function
    ; RAX = adres NODE_FN
    mov   [ast_root], rax          ; Zapisz korzeń (ostatnia fn wygrywa — można zmienić na listę)
    jmp   .top_loop

.program_done:
    ret

; ============================================================================
; PARSE_FUNCTION
; Aktualny token: KW_FN
; Produkuje: NODE_FN
;   left     = NODE_BLOCK (ciało)
;   value    = liczba argumentów
;   sym_addr = adres nazwy funkcji w symbol_table
;   lifetime = L_V (liczba z nawiasu, lub 0)
; ============================================================================
parse_function:
    push  rbp
    mov   rbp, rsp
    push  rbx
    push  r13

    ADVANCE                        ; Konsumuj KW_FN

    ; --- Oczekuj identyfikatora (nazwa funkcji) ---
    TOKEN_ID
    cmp   rax, T_IDENTIFIER
    jne   .err_name
    TOKEN_VAL
    mov   r13, rax                 ; R13 = adres nazwy w symbol_table
    ADVANCE

    ; --- Alokuj NODE_FN ---
    mov   rdi, NODE_FN
    call  ast_alloc
    mov   rbx, rax                 ; RBX = adres NODE_FN
    mov   qword [rbx + 32], r13    ; sym_addr = nazwa funkcji

    ; --- Oczekuj '(' ---
    TOKEN_ID
    cmp   rax, SYM_LPAREN
    jne   .err_lparen
    ADVANCE

    ; --- Parsuj listę parametrów fn(lifetime, arg1, arg2, ...) ---
    ; Pierwsza liczba to lifetime (L_V), reszta to identyfikatory argumentów
    xor   r13, r13                 ; R13 = licznik argumentów
    mov   qword [rbx + 40], 0     ; lifetime = 0 domyślnie

    TOKEN_ID
    cmp   rax, SYM_RPAREN
    je    .params_done             ; Puste nawiasy fn()

    ; Czy pierwszy element to liczba (lifetime)?
    cmp   rax, L_INT
    jne   .parse_params_no_lifetime

    TOKEN_VAL
    mov   qword [rbx + 40], rax    ; lifetime = wartość L_INT
    ADVANCE

    ; Sprawdź czy po lifetime jest przecinek i argumenty
    TOKEN_ID
    cmp   rax, SYM_COMMA
    jne   .params_done_check_rparen
    ADVANCE                        ; Konsumuj ','

.parse_params_no_lifetime:
.parse_param_loop:
    TOKEN_ID
    cmp   rax, SYM_RPAREN
    je    .params_done
    test  rax, rax
    jz    .err_rparen

    ; Każdy argument to identyfikator — rejestrujemy go w NODE_ARG_LIST
    ; (uproszczenie: liczymy tylko, pełna lista argumentów to TODO dla generatora kodu)
    cmp   rax, T_IDENTIFIER
    jne   .skip_param
    inc   r13
.skip_param:
    ADVANCE

    ; Przecinek między argumentami
    TOKEN_ID
    cmp   rax, SYM_COMMA
    jne   .params_done_check_rparen
    ADVANCE
    jmp   .parse_param_loop

.params_done_check_rparen:
    TOKEN_ID
    cmp   rax, SYM_RPAREN
    jne   .err_rparen

.params_done:
    mov   qword [rbx + 24], r13    ; value = liczba argumentów
    ADVANCE                        ; Konsumuj ')'

    ; --- Opcjonalny typ zwrotny: -> TYPE (konsumujemy bez analizy) ---
    TOKEN_ID
    cmp   rax, SYM_ARROW
    jne   .no_return_type
    ADVANCE                        ; Konsumuj '->'
    ADVANCE                        ; Konsumuj typ (identyfikator)
.no_return_type:

    ; --- Parsuj ciało funkcji ---
    call  parse_block
    mov   qword [rbx + 8], rax     ; left = NODE_BLOCK

    mov   rax, rbx
    pop   r13
    pop   rbx
    pop   rbp
    ret

.err_name:
    mov   rdi, ERR_EXPECTED_IDENT
    jmp   parse_error
.err_lparen:
    mov   rdi, ERR_EXPECTED_LPAREN
    jmp   parse_error
.err_rparen:
    mov   rdi, ERR_EXPECTED_RPAREN
    jmp   parse_error

; ============================================================================
; PARSE_BLOCK
; Aktualny token: SYM_LBRACE  '{'
; Produkuje: NODE_BLOCK
;   left  = pierwsza instrukcja (lista przez right)
;   right = nie używane (do dyspozycji)
; Instrukcje są łączone jako linked list: każda instr.right → następna
; ============================================================================
parse_block:
    push  rbx
    push  r13
    push  r12

    ; Oczekuj '{'
    TOKEN_ID
    cmp   rax, SYM_LBRACE
    jne   .err_lbrace
    ADVANCE

    ; Alokuj NODE_BLOCK
    mov   rdi, NODE_BLOCK
    call  ast_alloc
    mov   rbx, rax                 ; RBX = NODE_BLOCK

    xor   r13, r13                 ; R13 = głowa listy (pierwsze dziecko)
    xor   r12, r12                 ; R12 = poprzednia instrukcja (do linkowania)

.stmt_loop:
    TOKEN_ID
    test  rax, rax
    jz    .err_rbrace              ; EOF bez '}'
    cmp   rax, SYM_RBRACE
    je    .block_done

    call  parse_statement          ; RAX = węzeł instrukcji
    test  rax, rax
    jz    .stmt_loop               ; NULL = instrukcja pominięta

    ; Linkuj do listy
    test  r13, r13
    jnz   .not_first
    mov   r13, rax                 ; Pierwsza instrukcja → głowa
    mov   qword [rbx + 8], rax    ; NODE_BLOCK.left = głowa
    jmp   .link_done
.not_first:
    mov   qword [r12 + 16], rax   ; poprzednia.right = nowa (linked list)
.link_done:
    mov   r12, rax                 ; Zapamiętaj poprzednią
    jmp   .stmt_loop

.block_done:
    ADVANCE                        ; Konsumuj '}'
    mov   rax, rbx
    pop   r12
    pop   r13
    pop   rbx
    ret

.err_lbrace:
    mov   rdi, ERR_EXPECTED_LBRACE
    jmp   parse_error
.err_rbrace:
    mov   rdi, ERR_EXPECTED_RBRACE
    jmp   parse_error

; ============================================================================
; PARSE_STATEMENT
; Dispatch na podstawie ID bieżącego tokena.
; Wyjście: RAX = węzeł, lub 0 (jeśli ';' lub puste)
; ============================================================================
parse_statement:
    TOKEN_ID

    cmp   rax, KW_LET
    je    parse_let

    cmp   rax, KW_RETURN
    je    parse_return

    cmp   rax, KW_IF
    je    parse_if

    cmp   rax, KW_WHILE
    je    parse_while

    cmp   rax, SYM_SEMI
    je    .empty_stmt

    ; Wyrażenie jako instrukcja (np. wywołanie funkcji, przypisanie)
    call  parse_expr_stmt
    ret

.empty_stmt:
    ADVANCE
    xor   rax, rax
    ret

; ============================================================================
; PARSE_LET
; let IDENT = EXPR ;
; Produkuje: NODE_LET
;   sym_addr = adres IDENT
;   left     = NODE wynikowy z EXPR (wartość inicjalizatora)
; ============================================================================
parse_let:
    push  rbx

    ADVANCE                        ; Konsumuj 'let'

    ; Oczekuj identyfikatora
    TOKEN_ID
    cmp   rax, T_IDENTIFIER
    jne   .err_ident
    TOKEN_VAL
    mov   rbx, rax                 ; RBX = sym_addr
    ADVANCE

    ; Alokuj NODE_LET
    push  rbx
    mov   rdi, NODE_LET
    call  ast_alloc
    pop   rbx
    push  rax                      ; [rsp] = adres NODE_LET

    mov   qword [rax + 32], rbx    ; sym_addr

    ; Oczekuj '='
    TOKEN_ID
    cmp   rax, OP_ASSIGN
    jne   .err_assign
    ADVANCE

    ; Parsuj wyrażenie
    mov   rdi, PREC_NONE
    call  parse_expr               ; RAX = węzeł wyrażenia
    mov   rbx, rax

    pop   rax                      ; Odtwórz adres NODE_LET
    mov   qword [rax + 8], rbx     ; left = wyrażenie

    ; Oczekuj ';'
    TOKEN_ID
    cmp   rax, SYM_SEMI
    jne   .err_semi
    ADVANCE

    pop   rbx
    ret

.err_ident:
    mov   rdi, ERR_EXPECTED_IDENT
    jmp   parse_error
.err_assign:
    mov   rdi, ERR_EXPECTED_ASSIGN
    jmp   parse_error
.err_semi:
    mov   rdi, ERR_EXPECTED_SEMI
    jmp   parse_error

; ============================================================================
; PARSE_RETURN
; return EXPR ;
; Produkuje: NODE_RETURN
;   left = wyrażenie zwracane (lub NULL jeśli brak)
; ============================================================================
parse_return:
    push  rbx

    ADVANCE                        ; Konsumuj 'return'

    mov   rdi, NODE_RETURN
    call  ast_alloc
    mov   rbx, rax

    ; Sprawdź czy jest wyrażenie (nie ';')
    TOKEN_ID
    cmp   rax, SYM_SEMI
    je    .no_expr

    mov   rdi, PREC_NONE
    call  parse_expr
    mov   qword [rbx + 8], rax     ; left = wyrażenie

    TOKEN_ID
    cmp   rax, SYM_SEMI
    jne   .err_semi
.no_expr:
    ADVANCE                        ; Konsumuj ';'

    mov   rax, rbx
    pop   rbx
    ret

.err_semi:
    mov   rdi, ERR_EXPECTED_SEMI
    jmp   parse_error

; ============================================================================
; PARSE_IF
; if EXPR { BLOCK } (else { BLOCK })?
; Produkuje: NODE_IF
;   left     = warunek (wyrażenie)
;   right    = then-block (NODE_BLOCK)
;   sym_addr = else-block (NODE_BLOCK) lub NULL
; ============================================================================
parse_if:
    push  rbx

    ADVANCE                        ; Konsumuj 'if'

    mov   rdi, NODE_IF
    call  ast_alloc
    mov   rbx, rax

    ; Warunek
    mov   rdi, PREC_NONE
    call  parse_expr
    mov   qword [rbx + 8], rax     ; left = warunek

    ; Then-block
    call  parse_block
    mov   qword [rbx + 16], rax    ; right = then-block

    ; Opcjonalny else
    TOKEN_ID
    cmp   rax, KW_ELSE
    jne   .no_else
    ADVANCE                        ; Konsumuj 'else'

    ; else może być: blok LUB kolejny if
    TOKEN_ID
    cmp   rax, KW_IF
    je    .else_if
    call  parse_block
    jmp   .else_done
.else_if:
    call  parse_if
.else_done:
    mov   qword [rbx + 32], rax    ; sym_addr = else-block

.no_else:
    mov   rax, rbx
    pop   rbx
    ret

; ============================================================================
; PARSE_WHILE
; while EXPR { BLOCK }
; Produkuje: NODE_WHILE
;   left  = warunek
;   right = ciało (NODE_BLOCK)
; ============================================================================
parse_while:
    push  rbx

    ADVANCE                        ; Konsumuj 'while'

    mov   rdi, NODE_WHILE
    call  ast_alloc
    mov   rbx, rax

    mov   rdi, PREC_NONE
    call  parse_expr
    mov   qword [rbx + 8], rax     ; left = warunek

    call  parse_block
    mov   qword [rbx + 16], rax    ; right = ciało

    mov   rax, rbx
    pop   rbx
    ret

; ============================================================================
; PARSE_EXPR_STMT
; Wyrażenie jako instrukcja (np. wywołanie funkcji).
; Konsumuje opcjonalne ';' na końcu.
; ============================================================================
parse_expr_stmt:
    push  rbx

    mov   rdi, PREC_NONE
    call  parse_expr
    mov   rbx, rax

    TOKEN_ID
    cmp   rax, SYM_SEMI
    jne   .no_semi
    ADVANCE
.no_semi:
    mov   rax, rbx
    pop   rbx
    ret

; ============================================================================
; PARSE_EXPR — PRATT PARSER
; Wejście: RDI = minimalny priorytet (PREC_*)
; Wyjście: RAX = węzeł wyrażenia
;
; Pratt parser:
;  1. Parsuj lewostronny (prefix) — liczba, identyfikator, (, !
;  2. Pętla: sprawdź priorytet następnego operatora
;     Jeśli wyższy niż min_prec → parsuj jako infix i powtórz
;     Jeśli niższy → zwróć to co mamy
; ============================================================================
parse_expr:
    push  rbp
    mov   rbp, rsp
    push  rbx
    push  r13
    push  r12
    push  r11

    mov   r11, rdi                 ; R11 = min_prec

    ; -----------------------------------------------------------------------
    ; PREFIX (lewa strona wyrażenia)
    ; -----------------------------------------------------------------------
    TOKEN_ID

    ; Liczba całkowita
    cmp   rax, L_INT
    je    .prefix_int

    ; Boolean true/false
    cmp   rax, L_TRUE
    je    .prefix_true
    cmp   rax, L_FALSE
    je    .prefix_false

    ; Identyfikator lub wywołanie funkcji
    cmp   rax, T_IDENTIFIER
    je    .prefix_ident

    ; Wyrażenie w nawiasach ( expr )
    cmp   rax, SYM_LPAREN
    je    .prefix_group

    ; Unarny minus
    cmp   rax, OP_SUB
    je    .prefix_neg

    ; Unarny NOT
    cmp   rax, OP_NOT
    je    .prefix_not

    ; Nieoczekiwany token — zwróć NULL (błąd miękki)
    xor   rax, rax
    jmp   .expr_done

.prefix_int:
    TOKEN_VAL
    mov   r13, rax                 ; R13 = wartość liczby
    ADVANCE
    mov   rdi, NODE_INT
    call  ast_alloc
    mov   qword [rax + 24], r13    ; value = liczba
    mov   rbx, rax
    jmp   .infix_loop

.prefix_true:
    ADVANCE
    mov   rdi, NODE_BOOL
    call  ast_alloc
    mov   qword [rax + 24], 1      ; value = 1
    mov   rbx, rax
    jmp   .infix_loop

.prefix_false:
    ADVANCE
    mov   rdi, NODE_BOOL
    call  ast_alloc
    mov   qword [rax + 24], 0      ; value = 0
    mov   rbx, rax
    jmp   .infix_loop

.prefix_ident:
    TOKEN_VAL
    mov   r13, rax                 ; R13 = sym_addr
    ADVANCE

    ; Sprawdź czy po identyfikatorze jest '(' → wywołanie funkcji
    TOKEN_ID
    cmp   rax, SYM_LPAREN
    je    .call_expr

    ; Zwykły identyfikator
    mov   rdi, NODE_IDENT
    call  ast_alloc
    mov   qword [rax + 32], r13    ; sym_addr
    mov   rbx, rax
    jmp   .infix_loop

.call_expr:
    ; NODE_CALL: sym_addr = nazwa, left = lista argumentów
    ADVANCE                        ; Konsumuj '('
    mov   rdi, NODE_CALL
    call  ast_alloc
    mov   rbx, rax
    mov   qword [rbx + 32], r13    ; sym_addr = nazwa funkcji
    call  parse_arg_list           ; RAX = NODE_ARG_LIST (lub NULL)
    mov   qword [rbx + 8], rax     ; left = argumenty
    ; Konsumuj ')'
    TOKEN_ID
    cmp   rax, SYM_RPAREN
    jne   .skip_rparen_call
    ADVANCE
.skip_rparen_call:
    jmp   .infix_loop

.prefix_group:
    ADVANCE                        ; Konsumuj '('
    mov   rdi, PREC_NONE
    call  parse_expr
    mov   rbx, rax
    TOKEN_ID
    cmp   rax, SYM_RPAREN
    jne   .skip_rparen_group
    ADVANCE
.skip_rparen_group:
    jmp   .infix_loop

.prefix_neg:
    ADVANCE
    mov   rdi, PREC_UNARY
    call  parse_expr
    push  rax
    mov   rdi, NODE_UNOP
    call  ast_alloc
    pop   rcx
    mov   qword [rax + 16], rcx    ; right = operand
    mov   qword [rax + 24], OP_SUB ; op = unarny minus
    mov   rbx, rax
    jmp   .infix_loop

.prefix_not:
    ADVANCE
    mov   rdi, PREC_UNARY
    call  parse_expr
    push  rax
    mov   rdi, NODE_UNOP
    call  ast_alloc
    pop   rcx
    mov   qword [rax + 16], rcx
    mov   qword [rax + 24], OP_NOT
    mov   rbx, rax
    jmp   .infix_loop

    ; -----------------------------------------------------------------------
    ; INFIX LOOP — operatory binarne i postfiksowe (., ())
    ; -----------------------------------------------------------------------
.infix_loop:
    TOKEN_ID
    call  get_infix_prec           ; RAX = priorytet bieżącego tokena
    cmp   rax, r11
    jle   .expr_done               ; Priorytet ≤ min → oddaj kontrolę

    ; Zapamiętaj operator i jego priorytet
    mov   r12, rax                 ; R12 = priorytet operatora
    TOKEN_ID
    mov   r13, rax                 ; R13 = ID tokena (operator)
    ADVANCE                        ; Konsumuj operator

    ; --- Operator DOT (łańcuch kropkowy) ---
    cmp   r13, SYM_DOT
    je    .infix_dot

    ; --- Wywołanie przez '(' po wyrażeniu (rzadkie, ale możliwe) ---
    ; (obsługujemy w prefix_ident wcześniej)

    ; --- Standardowy operator binarny ---
    ; Parsuj prawą stronę z priorytetem r12 (lewostronny: r12, prawostronny: r12-1)
    ; Wszystkie nasze operatory są lewostronnie asocjatywne, oprócz OP_ASSIGN
    cmp   r13, OP_ASSIGN
    je    .infix_right_assoc
    mov   rdi, r12                 ; Lewostronny: prawy operand z tym samym priorytetem
    jmp   .parse_right

.infix_right_assoc:
    mov   rdi, PREC_NONE           ; Prawostronny: prawy operand z priorytetem 0
    jmp   .parse_right

.parse_right:
    push  rbx
    push  r13
    call  parse_expr               ; RAX = prawy operand
    pop   r13
    pop   rbx

    push  rax                      ; Zachowaj prawy operand
    mov   rdi, NODE_BINOP
    call  ast_alloc
    pop   rcx
    mov   qword [rax + 8],  rbx    ; left = lewy operand
    mov   qword [rax + 16], rcx    ; right = prawy operand
    mov   qword [rax + 24], r13    ; value = operator (OP_*)
    mov   rbx, rax
    jmp   .infix_loop

.infix_dot:
    ; left.right → NODE_CHAIN
    ; Prawy operand to identyfikator (lub kolejne wywołanie)
    TOKEN_ID
    cmp   rax, T_IDENTIFIER
    jne   .expr_done               ; Błąd: po '.' musi być identyfikator

    TOKEN_VAL
    mov   r12, rax                 ; sym_addr prawej strony
    ADVANCE

    ; Sprawdź czy po identyfikatorze jest '(' → call
    TOKEN_ID
    cmp   rax, SYM_LPAREN
    jne   .dot_ident

    ; a.b(args) → NODE_CHAIN: left=a, right=NODE_CALL(b)
    ADVANCE
    mov   rdi, NODE_CALL
    call  ast_alloc
    push  rax
    mov   qword [rax + 32], r12    ; sym_addr = b
    call  parse_arg_list
    mov   r13, rax                 ; args
    pop   rax
    mov   qword [rax + 8], r13     ; CALL.left = args
    TOKEN_ID
    cmp   rax, SYM_RPAREN
    jne   .skip_rparen_dot
    ADVANCE
.skip_rparen_dot:
    push  rax
    mov   rdi, NODE_CHAIN
    call  ast_alloc
    pop   rcx
    mov   qword [rax + 8],  rbx    ; left = lewy operand (a)
    mov   qword [rax + 16], rcx    ; right = NODE_CALL(b)
    mov   rbx, rax
    jmp   .infix_loop

.dot_ident:
    ; a.b → NODE_CHAIN: left=a, right=NODE_IDENT(b)
    mov   rdi, NODE_IDENT
    call  ast_alloc
    mov   qword [rax + 32], r12
    push  rax
    mov   rdi, NODE_CHAIN
    call  ast_alloc
    pop   rcx
    mov   qword [rax + 8],  rbx
    mov   qword [rax + 16], rcx
    mov   rbx, rax
    jmp   .infix_loop

.expr_done:
    mov   rax, rbx

    pop   r11
    pop   r12
    pop   r13
    pop   rbx
    pop   rbp
    ret

; ============================================================================
; PARSE_ARG_LIST
; Parsuje listę argumentów wewnątrz nawiasów (bez samych nawiasów).
; Wyjście: RAX = NODE_ARG_LIST (głowa linked list) lub NULL
; Linked list: każdy ARG.right → następny ARG
; ============================================================================
parse_arg_list:
    push  rbx
    push  r12
    push  r13

    xor   rbx, rbx                 ; głowa listy
    xor   r12, r12                 ; poprzedni węzeł

.arg_loop:
    TOKEN_ID
    test  rax, rax
    jz    .args_done
    cmp   rax, SYM_RPAREN
    je    .args_done

    ; Parsuj jeden argument jako wyrażenie
    mov   rdi, PREC_ASSIGN         ; Zatrzymaj na przecinku (prec=1 > 0 dla przecinka)
    call  parse_expr
    test  rax, rax
    jz    .args_done

    ; Owiń w NODE_ARG_LIST
    push  rax
    mov   rdi, NODE_ARG_LIST
    call  ast_alloc
    pop   rcx
    mov   qword [rax + 8], rcx     ; left = wyrażenie argumentu

    test  rbx, rbx
    jnz   .not_first_arg
    mov   rbx, rax                 ; Pierwsza głowa
    jmp   .link_arg
.not_first_arg:
    mov   qword [r12 + 16], rax    ; poprzedni.right = nowy
.link_arg:
    mov   r12, rax

    ; Przecinek między argumentami
    TOKEN_ID
    cmp   rax, SYM_COMMA
    jne   .args_done
    ADVANCE
    jmp   .arg_loop

.args_done:
    mov   rax, rbx
    pop   r13
    pop   r12
    pop   rbx
    ret

; ============================================================================
; GET_INFIX_PREC
; Wejście:  bieżący token wskazywany przez R15
; Wyjście:  RAX = priorytet jako operator infix (0 = nie jest operatorem infix)
; Nie niszczy R15 ani żadnego innego rejestru poza RAX.
; ============================================================================
get_infix_prec:
    mov   rax, [r15]               ; ID tokena

    cmp   rax, OP_ASSIGN
    je    .prec_assign
    cmp   rax, OP_OR
    je    .prec_or
    cmp   rax, OP_AND
    je    .prec_and
    cmp   rax, OP_EQ
    je    .prec_equal
    cmp   rax, OP_NEQ
    je    .prec_equal
    cmp   rax, OP_LT
    je    .prec_compare
    cmp   rax, OP_GT
    je    .prec_compare
    cmp   rax, OP_LE
    je    .prec_compare
    cmp   rax, OP_GE
    je    .prec_compare
    cmp   rax, OP_ADD
    je    .prec_add
    cmp   rax, OP_SUB
    je    .prec_add
    cmp   rax, OP_MUL
    je    .prec_mul
    cmp   rax, OP_DIV
    je    .prec_mul
    cmp   rax, OP_MOD
    je    .prec_mul
    cmp   rax, SYM_DOT
    je    .prec_call
    cmp   rax, SYM_LPAREN
    je    .prec_call

    xor   rax, rax                 ; 0 = nie operator infix
    ret

.prec_assign:   mov rax, PREC_ASSIGN   ; 1
    ret
.prec_or:       mov rax, PREC_OR       ; 2
    ret
.prec_and:      mov rax, PREC_AND      ; 3
    ret
.prec_equal:    mov rax, PREC_EQUAL    ; 4
    ret
.prec_compare:  mov rax, PREC_COMPARE  ; 5
    ret
.prec_add:      mov rax, PREC_ADD      ; 6
    ret
.prec_mul:      mov rax, PREC_MUL      ; 7
    ret
.prec_call:     mov rax, PREC_CALL     ; 9
    ret