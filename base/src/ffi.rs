// src/compiler/ffi.rs
// Mostek FFI między Rustem a modułami asemblerowymi.
// Wszystkie stałe MUSZĄ być identyczne z lexer.asm i parser.asm.

// ============================================================================
// STAŁE TOKENÓW
// ============================================================================
pub mod tok {
    pub const T_IDENTIFIER: u64 = 1;
    pub const L_INT:         u64 = 20;
    pub const L_STR:         u64 = 22;
    pub const L_TRUE:        u64 = 23;
    pub const L_FALSE:       u64 = 24;
    pub const OP_ASSIGN:     u64 = 30;
    pub const OP_ADD:        u64 = 31;
    pub const OP_SUB:        u64 = 32;
    pub const OP_MUL:        u64 = 33;
    pub const OP_DIV:        u64 = 34;
    pub const OP_MOD:        u64 = 35;
    pub const OP_EQ:         u64 = 40;
    pub const OP_NEQ:        u64 = 41;
    pub const OP_LT:         u64 = 42;
    pub const OP_GT:         u64 = 43;
    pub const OP_LE:         u64 = 44;
    pub const OP_GE:         u64 = 45;
    pub const OP_AND:        u64 = 46;
    pub const OP_OR:         u64 = 47;
    pub const OP_NOT:        u64 = 48;
    pub const KW_IF:         u64 = 50;
    pub const KW_ELSE:       u64 = 51;
    pub const KW_WHILE:      u64 = 52;
    pub const KW_FOR:        u64 = 53;
    pub const KW_FN:         u64 = 54;
    pub const KW_RETURN:     u64 = 55;
    pub const KW_LET:        u64 = 56;
    pub const KW_PUB:        u64 = 57;
    pub const KW_IMPORT:     u64 = 58;
    pub const KW_STRUCT:     u64 = 59;
    pub const KW_AS:         u64 = 60;
    pub const SYM_LPAREN:    u64 = 70;
    pub const SYM_RPAREN:    u64 = 71;
    pub const SYM_LBRACE:    u64 = 72;
    pub const SYM_RBRACE:    u64 = 73;
    pub const SYM_LBRACKET:  u64 = 74;
    pub const SYM_RBRACKET:  u64 = 75;
    pub const SYM_COMMA:     u64 = 76;
    pub const SYM_COLON:     u64 = 77;
    pub const SYM_SEMI:      u64 = 78;
    pub const SYM_DOT:       u64 = 79;
    pub const SYM_ARROW:     u64 = 80;
    pub const SYM_AMP:       u64 = 81;
}

// ============================================================================
// TYPY WĘZŁÓW AST
// ============================================================================
pub mod node {
    pub const NODE_FN:       u64 = 1;
    pub const NODE_BLOCK:    u64 = 2;
    pub const NODE_LET:      u64 = 3;
    pub const NODE_ASSIGN:   u64 = 4;
    pub const NODE_RETURN:   u64 = 5;
    pub const NODE_IF:       u64 = 6;
    pub const NODE_WHILE:    u64 = 7;
    pub const NODE_CALL:     u64 = 8;
    pub const NODE_INT:      u64 = 9;
    pub const NODE_IDENT:    u64 = 10;
    pub const NODE_BINOP:    u64 = 11;
    pub const NODE_UNOP:     u64 = 12;
    pub const NODE_CHAIN:    u64 = 13;
    pub const NODE_BOOL:     u64 = 14;
    pub const NODE_ARG_LIST: u64 = 16;
    pub const AST_NODE_SIZE: usize = 48;
}

// ============================================================================
// SUROWY WIDOK NA WĘZEŁ AST (48 bajtów = 6 × u64)
// repr(C) gwarantuje zgodność z układem w pamięci z asemblera.
// ============================================================================
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RawNode {
    pub kind:     u64,   // +0  NODE_*
    pub left:     u64,   // +8  adres lewego potomka (wskaźnik w ast_arena)
    pub right:    u64,   // +16 adres prawego potomka
    pub value:    u64,   // +24 literał lub kod operatora
    pub sym_addr: u64,   // +32 adres w symbol_table
    pub lifetime: u64,   // +40 L_V z nagłówka fn
}

// ============================================================================
// SUROWY TOKEN (16 bajtów = 2 × u64)
// ============================================================================
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct RawToken {
    pub id:    u64,
    pub value: u64,
}

// ============================================================================
// DEKLARACJE FUNKCJI ASEMBLEROWYCH
// ============================================================================
#[link(name = "compiler_asm", kind = "static")]
extern "C" {
    /// Leksuje `src` (null-terminated), zapisuje tokeny do `token_out`,
    /// aktualizuje tablicę symboli przez `sym_ptr_inout`.
    /// Zwraca liczbę tokenów.
    pub fn lex_source(
        src:          *const u8,
        token_out:    *mut RawToken,
        sym_table:    *mut u8,
        sym_ptr_inout: *mut u64,
    ) -> u64;

    /// Parsuje `token_count` tokenów z `tokens`, buduje AST w `ast_arena`.
    /// Przez `ast_out_count` przekazuje liczbę zbudowanych węzłów.
    /// Zwraca wskaźnik (adres w ast_arena) korzenia, 0 = błąd.
    pub fn parse_tokens(
        tokens:        *const RawToken,
        token_count:   u64,
        ast_arena:     *mut RawNode,
        ast_out_count: *mut u64,
    ) -> u64;
}

// ============================================================================
// POMOCNICZE: odczyt symbolu z tablicy (null-terminated string)
// ============================================================================
/// Bezpieczny odczyt nazwy z surowej tablicy symboli.
/// `sym_table` to &[u8], `addr` to adres zwrócony przez lexer.
pub fn read_symbol<'a>(sym_table: &'a [u8], addr: u64) -> &'a str {
    let base = sym_table.as_ptr() as u64;
    if addr < base || addr >= base + sym_table.len() as u64 {
        return "<invalid>";
    }
    let offset = (addr - base) as usize;
    let slice = &sym_table[offset..];
    let end = slice.iter().position(|&b| b == 0).unwrap_or(slice.len());
    std::str::from_utf8(&slice[..end]).unwrap_or("<utf8_err>")
}
