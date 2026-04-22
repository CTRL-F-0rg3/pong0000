// src/main.rs — ztac: kompilator języka ZTA
mod compiler;

use compiler::pipeline::compile_source;
use compiler::ast::print_ast;
use std::env;
use std::fs;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();

    let (source, filename) = if args.len() < 2 {
        eprintln!("Użycie: ztac <plik.zta> [--ast] [--forth] [--all]");
        eprintln!("Uruchamiam przykład wbudowany...\n");
        (EXAMPLE_SOURCE.to_string(), "<builtin>".to_string())
    } else {
        match fs::read_to_string(&args[1]) {
            Ok(s)  => (s, args[1].clone()),
            Err(e) => { eprintln!("Błąd odczytu {}: {}", args[1], e); process::exit(1); }
        }
    };

    let show_ast   = args.iter().any(|a| a == "--ast"   || a == "--all");
    let show_forth = args.iter().any(|a| a == "--forth" || a == "--all");
    let show_toks  = args.iter().any(|a| a == "--tokens"|| a == "--all");

    println!("=== {} ===", filename);
    println!("{}\n", source.trim());

    match compile_source(&source) {
        Err(e) => { eprintln!("Błąd kompilacji: {}", e); process::exit(1); }
        Ok(result) => {

            // ---- Tokeny ----
            if show_toks {
                println!("=== Tokeny: {} ===", result.n_tokens);
                print_tokens(&result.tokens[..result.n_tokens], &result.sym_table);
                println!();
            }

            // ---- AST ----
            if show_ast {
                println!("=== AST: {} węzłów top-level ===", result.ast.len());
                for node in &result.ast { print_ast(node, 0); }
                println!();
            }

            // ---- Błędy semantyczne ----
            if result.has_errors() {
                println!("=== Błędy semantyczne: {} ===", result.semantic_errors.len());
                for e in &result.semantic_errors { println!("  ⚠ {}", e); }
                println!();
            } else {
                println!("✓ Analiza semantyczna: brak błędów");
            }

            // ---- Kod Forth ----
            if show_forth || !show_ast {
                println!("\n=== Kod Forth ===");
                print_forth(&result.forth_code);
            }
        }
    }
}

fn print_tokens(tokens: &[compiler::ffi::RawToken], sym_table: &[u8]) {
    use compiler::ffi::{tok::*, read_symbol};
    for (i, t) in tokens.iter().enumerate() {
        let name = match t.id {
            T_IDENTIFIER => format!("IDENT({})", read_symbol(sym_table, t.value)),
            L_INT        => format!("INT({})",   t.value),
            L_TRUE       => "true".into(),
            L_FALSE      => "false".into(),
            KW_FN        => "fn".into(),
            KW_LET       => "let".into(),
            KW_RETURN    => "return".into(),
            KW_IF        => "if".into(),
            KW_ELSE      => "else".into(),
            KW_WHILE     => "while".into(),
            KW_FOR       => "for".into(),
            KW_PUB       => "pub".into(),
            KW_STRUCT    => "struct".into(),
            OP_ADD       => "+".into(),
            OP_SUB       => "-".into(),
            OP_MUL       => "*".into(),
            OP_DIV       => "/".into(),
            OP_MOD       => "%".into(),
            OP_EQ        => "==".into(),
            OP_NEQ       => "!=".into(),
            OP_LT        => "<".into(),
            OP_GT        => ">".into(),
            OP_LE        => "<=".into(),
            OP_GE        => ">=".into(),
            OP_AND       => "&&".into(),
            OP_OR        => "||".into(),
            OP_NOT       => "!".into(),
            OP_ASSIGN    => "=".into(),
            SYM_LPAREN   => "(".into(),
            SYM_RPAREN   => ")".into(),
            SYM_LBRACE   => "{".into(),
            SYM_RBRACE   => "}".into(),
            SYM_SEMI     => ";".into(),
            SYM_DOT      => ".".into(),
            SYM_COMMA    => ",".into(),
            SYM_ARROW    => "->".into(),
            other        => format!("TOK({})", other),
        };
        print!("{}", name);
        if (i + 1) % 12 == 0 { println!(); } else { print!(" "); }
    }
    println!();
}

fn print_forth(code: &str) {
    // Ładne wypisanie — każde słowo kluczowe Forth na nowej linii
    let mut indent = 0i32;
    for word in code.split_whitespace() {
        match word {
            ":" => {
                println!();
                print!("{}", word);
                indent = 1;
            }
            ";" => {
                println!();
                println!("{}", word);
                indent = 0;
            }
            "IF" | "BEGIN" | "WHILE" => {
                println!();
                print!("{}{}", "  ".repeat(indent as usize), word);
                indent += 1;
            }
            "ELSE" => {
                indent -= 1;
                println!();
                print!("{}{}", "  ".repeat(indent as usize), word);
                indent += 1;
            }
            "THEN" | "REPEAT" => {
                indent -= 1;
                println!();
                print!("{}{}", "  ".repeat(indent.max(0) as usize), word);
            }
            "\n" => println!(),
            w if w.starts_with('\\') => {
                println!();
                print!("{}", w);
            }
            w => print!(" {}", w),
        }
    }
    println!();
}

const EXAMPLE_SOURCE: &str = r#"
pub fn main(2) {
    let x = 125;
    let y = x + 10;
    if x == 125 {
        return y;
    } else {
        return 0;
    }
}

fn add(a, b) {
    return a + b;
}

fn fizzbuzz(n) {
    let i = 1;
    while i <= n {
        if i % 15 == 0 {
            let msg = 0;
        } else {
            if i % 3 == 0 {
                let msg = 0;
            } else {
                let msg = i;
            }
        }
        let i = i + 1;
    }
}
"#;
