// ztac — ZTA lang compiler entry point
mod compiler;
use compiler::pipeline::compile;
use compiler::ast::print_ast;
use compiler::ffi::{tok::*, read_symbol};
use std::{env, fs, process};

fn main() {
    let args: Vec<String> = env::args().collect();
    let show_ast   = args.iter().any(|a| a=="--ast"   || a=="--all");
    let show_toks  = args.iter().any(|a| a=="--tokens" || a=="--all");
    let show_forth = args.iter().any(|a| a=="--forth"  || a=="--all");

    let (src, name) = if args.len() < 2 {
        eprintln!("usage: ztac <file.zta> [--ast] [--forth] [--tokens] [--all]");
        eprintln!("running built-in example...\n");
        (EXAMPLE.to_string(), "<builtin>".to_string())
    } else {
        match fs::read_to_string(&args[1]) {
            Ok(s)  => (s, args[1].clone()),
            Err(e) => { eprintln!("cannot open {}: {}", args[1], e); process::exit(1); }
        }
    };

    println!("=== {} ===\n{}\n", name, src.trim());

    match compile(&src) {
        Err(e) => { eprintln!("compile error: {}", e); process::exit(1); }
        Ok(r)  => {
            if show_toks {
                println!("=== tokens: {} ===", r.n_tokens);
                for (i, t) in r.tokens[..r.n_tokens].iter().enumerate() {
                    let s = tok_name(t.id, t.value, &r.sym_table);
                    print!("{}", s);
                    if (i+1) % 10 == 0 { println!(); } else { print!(" "); }
                }
                println!("\n");
            }

            if show_ast {
                println!("=== AST ({} top-level nodes) ===", r.ast.len());
                for n in &r.ast { print_ast(n, 0); }
                println!();
            }

            if r.ok() {
                println!("✓ semantic: no errors");
            } else {
                println!("=== semantic errors: {} ===", r.errors.len());
                for e in &r.errors { println!("  ⚠  {}", e); }
            }

            if show_forth || (!show_ast && !show_toks) {
                println!("\n=== forth output ===");
                print_forth(&r.forth);
            }
        }
    }
}

fn tok_name(id: u64, val: u64, sym: &[u8]) -> String {
    match id {
        T_IDENTIFIER => format!("IDENT({})", read_symbol(sym, val)),
        KW_UNSAFE    => "unsafe".into(),
        L_INT        => format!("INT({})", val),
        L_TRUE       => "true".into(),   L_FALSE  => "false".into(),
        KW_FN        => "fn".into(),     KW_LET   => "let".into(),
        KW_RETURN    => "return".into(), KW_IF    => "if".into(),
        KW_ELSE      => "else".into(),   KW_WHILE => "while".into(),
        KW_FOR       => "for".into(),    KW_PUB   => "pub".into(),
        KW_STRUCT    => "struct".into(),
        OP_ADD=>"+" .into(), OP_SUB=>"-".into(), OP_MUL=>"*".into(),
        OP_DIV=>"/" .into(), OP_MOD=>"%".into(),
        OP_EQ =>"==".into(), OP_NEQ=>"!=".into(),
        OP_LT =>"<" .into(), OP_GT =>">".into(),
        OP_LE =>"<=".into(), OP_GE =>">=".into(),
        OP_AND=>"&&".into(), OP_OR =>"||".into(), OP_NOT=>"!".into(),
        OP_ASSIGN=>"=".into(),
        SYM_LPAREN=>"(".into(), SYM_RPAREN=>")".into(),
        SYM_LBRACE=>"{".into(), SYM_RBRACE=>"}".into(),
        SYM_SEMI  =>";".into(), SYM_DOT   =>".".into(),
        SYM_COMMA =>",".into(), SYM_ARROW =>"->".into(),
        other => format!("?{}", other),
    }
}

fn print_forth(words: &[String]) {
    let mut indent = 0i32;
    for w in words {
        match w.as_str() {
            ":" => { println!(); print!("{}", w); indent = 1; }
            ";" => { println!(); println!("{}", w); println!(); indent = 0; }
            "IF" | "BEGIN" | "WHILE" => {
                println!(); print!("{}{}", "  ".repeat(indent as usize), w); indent += 1;
            }
            "ELSE" => {
                indent -= 1;
                println!(); print!("{}{}", "  ".repeat(indent.max(0) as usize), w); indent += 1;
            }
            "THEN" | "REPEAT" => {
                indent -= 1;
                println!(); print!("{}{}", "  ".repeat(indent.max(0) as usize), w);
            }
            "\n" => println!(),
            w if w.starts_with('\\') => { println!(); print!("{}", w); }
            w => print!(" {}", w),
        }
    }
    println!();
}

const EXAMPLE: &str = r#"
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

fn safe_demo(n) {
    let result = 0;
    unsafe {
        let raw = ptr_read(n);
        result = raw;
    }
    return result;
}
"#;
