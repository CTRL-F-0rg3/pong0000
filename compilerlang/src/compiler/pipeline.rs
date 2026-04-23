// src/compiler/pipeline.rs  —  ASM-lex -> Rust-parse -> semantic -> forth

use crate::compiler::ffi::{RawToken, lex_source};
use crate::compiler::ast::Node;
use crate::compiler::{parser, semantic, forth};

const MAX_TOKS: usize = 8192;
const MAX_SYM:  usize = 65536;

pub struct CompileResult {
    pub tokens:   Vec<RawToken>,
    pub n_tokens: usize,
    pub sym_table: Vec<u8>,
    pub ast:      Vec<Node>,
    pub errors:   Vec<semantic::SemError>,
    pub forth:    Vec<String>,
}
impl CompileResult {
    pub fn ok(&self) -> bool { self.errors.is_empty() }
}

#[derive(Debug)]
pub enum CompileError {
    Empty,
    Lex(String),
    Parse(parser::ParseError),
}
impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty    => write!(f, "empty input"),
            Self::Lex(s)   => write!(f, "lex error: {}", s),
            Self::Parse(e) => write!(f, "{}", e),
        }
    }
}

pub fn compile(src: &str) -> Result<CompileResult, CompileError> {
    if src.trim().is_empty() { return Err(CompileError::Empty); }

    // null-terminate
    let mut bytes = src.as_bytes().to_vec();
    bytes.push(0);

    let mut tokens    = vec![RawToken::default(); MAX_TOKS];
    let mut sym_table = vec![0u8; MAX_SYM];

    let sym_base = sym_table.as_ptr() as u64;
    let mut sym_ptr = sym_base;

    // Stage 1: ASM lexer
    let n = unsafe {
        lex_source(bytes.as_ptr(), tokens.as_mut_ptr(), sym_table.as_mut_ptr(), &mut sym_ptr)
    } as usize;
    if n == 0 { return Err(CompileError::Lex("no tokens produced".into())); }

    let sym_used = (sym_ptr - sym_base) as usize;

    // Stage 2: Rust parser
    let ast = parser::parse(&tokens[..n], &sym_table)
        .map_err(CompileError::Parse)?;

    // Stage 3: Semantic analysis
    let errors = semantic::check(&ast);

    // Stage 4: Forth codegen
    let forth = forth::generate(&ast);

    sym_table.truncate(sym_used + 1);

    Ok(CompileResult {
        tokens: tokens[..n].to_vec(), n_tokens: n,
        sym_table, ast, errors, forth,
    })
}
