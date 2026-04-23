// src/compiler/ffi.rs  —  FFI bridge: Rust <-> ASM lexer
// Every constant here MUST match lexer.asm exactly.

#[allow(dead_code)]
pub mod tok {
    pub const T_IDENTIFIER: u64 = 1;
    pub const KW_UNSAFE:    u64 = 2;   // "unsafe" keyword
    pub const L_INT:        u64 = 20;
    pub const L_STR:        u64 = 22;
    pub const L_TRUE:       u64 = 23;
    pub const L_FALSE:      u64 = 24;
    pub const OP_ASSIGN:    u64 = 30;
    pub const OP_ADD:       u64 = 31;
    pub const OP_SUB:       u64 = 32;
    pub const OP_MUL:       u64 = 33;
    pub const OP_DIV:       u64 = 34;
    pub const OP_MOD:       u64 = 35;
    pub const OP_EQ:        u64 = 40;
    pub const OP_NEQ:       u64 = 41;
    pub const OP_LT:        u64 = 42;
    pub const OP_GT:        u64 = 43;
    pub const OP_LE:        u64 = 44;
    pub const OP_GE:        u64 = 45;
    pub const OP_AND:       u64 = 46;
    pub const OP_OR:        u64 = 47;
    pub const OP_NOT:       u64 = 48;
    pub const KW_IF:        u64 = 50;
    pub const KW_ELSE:      u64 = 51;
    pub const KW_WHILE:     u64 = 52;
    pub const KW_FOR:       u64 = 53;
    pub const KW_FN:        u64 = 54;
    pub const KW_RETURN:    u64 = 55;
    pub const KW_LET:       u64 = 56;
    pub const KW_PUB:       u64 = 57;
    pub const KW_IMPORT:    u64 = 58;
    pub const KW_STRUCT:    u64 = 59;
    pub const KW_AS:        u64 = 60;
    pub const SYM_LPAREN:   u64 = 70;
    pub const SYM_RPAREN:   u64 = 71;
    pub const SYM_LBRACE:   u64 = 72;
    pub const SYM_RBRACE:   u64 = 73;
    pub const SYM_LBRACKET: u64 = 74;
    pub const SYM_RBRACKET: u64 = 75;
    pub const SYM_COMMA:    u64 = 76;
    pub const SYM_COLON:    u64 = 77;
    pub const SYM_SEMI:     u64 = 78;
    pub const SYM_DOT:      u64 = 79;
    pub const SYM_ARROW:    u64 = 80;
    pub const SYM_AMP:      u64 = 81;
}

/// Raw token as emitted by the ASM lexer: [id: u64, value: u64]
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct RawToken {
    pub id:    u64,
    pub value: u64,
}

#[link(name = "compiler_asm", kind = "static")]
extern "C" {
    /// Lex null-terminated `src` into `token_out`.
    /// `sym_table` is the symbol-table buffer; `sym_ptr_inout` is updated.
    /// Returns number of tokens produced.
    pub fn lex_source(
        src:           *const u8,
        token_out:     *mut RawToken,
        sym_table:     *mut u8,
        sym_ptr_inout: *mut u64,
    ) -> u64;
}

/// Read a null-terminated symbol from sym_table at byte address `addr`.
pub fn read_symbol<'a>(sym_table: &'a [u8], addr: u64) -> &'a str {
    let base = sym_table.as_ptr() as u64;
    if addr < base || addr >= base + sym_table.len() as u64 {
        return "<oob>";
    }
    let off = (addr - base) as usize;
    let end = sym_table[off..].iter().position(|&b| b == 0).unwrap_or(0);
    std::str::from_utf8(&sym_table[off..off + end]).unwrap_or("<utf8>")
}
