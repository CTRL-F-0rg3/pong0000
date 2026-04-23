// src/compiler/ast.rs  —  High-level AST nodes

use crate::compiler::ffi::tok::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinOp {
    Add, Sub, Mul, Div, Mod,
    Eq, Neq, Lt, Gt, Le, Ge,
    And, Or,
    Assign,
}

impl BinOp {
    pub fn from_tok(id: u64) -> Option<Self> {
        match id {
            OP_ADD    => Some(Self::Add),
            OP_SUB    => Some(Self::Sub),
            OP_MUL    => Some(Self::Mul),
            OP_DIV    => Some(Self::Div),
            OP_MOD    => Some(Self::Mod),
            OP_EQ     => Some(Self::Eq),
            OP_NEQ    => Some(Self::Neq),
            OP_LT     => Some(Self::Lt),
            OP_GT     => Some(Self::Gt),
            OP_LE     => Some(Self::Le),
            OP_GE     => Some(Self::Ge),
            OP_AND    => Some(Self::And),
            OP_OR     => Some(Self::Or),
            OP_ASSIGN => Some(Self::Assign),
            _         => None,
        }
    }
    pub fn symbol(&self) -> &'static str {
        match self {
            Self::Add    => "+",  Self::Sub => "-",  Self::Mul => "*",
            Self::Div    => "/",  Self::Mod => "%",
            Self::Eq     => "==", Self::Neq => "!=", Self::Lt  => "<",
            Self::Gt     => ">",  Self::Le  => "<=", Self::Ge  => ">=",
            Self::And    => "&&", Self::Or  => "||",
            Self::Assign => "=",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnOp { Neg, Not }

#[derive(Debug, Clone)]
pub enum Node {
    /// fn name(lifetime?, params*) { body }
    Function { name: String, lifetime: u64, params: Vec<String>, body: Box<Node> },
    /// { stmts* }
    Block(Vec<Node>),
    /// unsafe { stmts* }
    Unsafe(Vec<Node>),
    /// let name = expr
    Let { name: String, init: Box<Node> },
    /// return expr?
    Return(Option<Box<Node>>),
    /// if cond { then } (else { else_br })?
    If { cond: Box<Node>, then_br: Box<Node>, else_br: Option<Box<Node>> },
    /// while cond { body }
    While { cond: Box<Node>, body: Box<Node> },
    /// name(args*)
    Call { name: String, args: Vec<Node> },
    /// left.right  or  left.method(args)
    Chain { left: Box<Node>, right: Box<Node> },
    /// left OP right
    BinOp { op: BinOp, left: Box<Node>, right: Box<Node> },
    /// OP operand
    UnOp { op: UnOp, operand: Box<Node> },
    /// integer literal
    Int(i64),
    /// bool literal
    Bool(bool),
    /// variable reference
    Ident(String),
    /// parse-error placeholder (soft error)
    Error(String),
}

// ---- pretty-printer ----
pub fn print_ast(node: &Node, depth: usize) {
    let pad = "  ".repeat(depth);
    match node {
        Node::Function { name, lifetime, params, body } => {
            let lt = if *lifetime > 0 { format!("  lifetime={}", lifetime) } else { String::new() };
            let ps = if params.is_empty() { String::new() } else { format!("  params=[{}]", params.join(", ")) };
            println!("{}fn {}{}{}", pad, name, lt, ps);
            print_ast(body, depth + 1);
        }
        Node::Block(stmts) => {
            println!("{}{{", pad);
            for s in stmts { print_ast(s, depth + 1); }
            println!("{}}}", pad);
        }
        Node::Unsafe(stmts) => {
            println!("{}unsafe {{", pad);
            for s in stmts { print_ast(s, depth + 1); }
            println!("{}}}", pad);
        }
        Node::Let { name, init } => {
            println!("{}let {} =", pad, name);
            print_ast(init, depth + 1);
        }
        Node::Return(e) => {
            println!("{}return", pad);
            if let Some(x) = e { print_ast(x, depth + 1); }
        }
        Node::If { cond, then_br, else_br } => {
            println!("{}if", pad);
            print_ast(cond,    depth + 1);
            print_ast(then_br, depth + 1);
            if let Some(e) = else_br { print_ast(e, depth + 1); }
        }
        Node::While { cond, body } => {
            println!("{}while", pad);
            print_ast(cond, depth + 1);
            print_ast(body, depth + 1);
        }
        Node::Call { name, args } => {
            println!("{}call {}({} args)", pad, name, args.len());
            for a in args { print_ast(a, depth + 1); }
        }
        Node::Chain { left, right } => {
            println!("{}chain", pad);
            print_ast(left,  depth + 1);
            print_ast(right, depth + 1);
        }
        Node::BinOp { op, left, right } => {
            println!("{}{}", pad, op.symbol());
            print_ast(left,  depth + 1);
            print_ast(right, depth + 1);
        }
        Node::UnOp { op, operand } => {
            let s = match op { UnOp::Neg => "-", UnOp::Not => "!" };
            println!("{}unary {}", pad, s);
            print_ast(operand, depth + 1);
        }
        Node::Int(n)    => println!("{}Int({})",   pad, n),
        Node::Bool(b)   => println!("{}Bool({})",  pad, b),
        Node::Ident(s)  => println!("{}Ident({})", pad, s),
        Node::Error(m)  => println!("{}ERROR: {}", pad, m),
    }
}
