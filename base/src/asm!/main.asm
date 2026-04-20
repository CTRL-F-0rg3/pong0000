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
