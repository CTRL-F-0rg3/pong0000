// src/compiler/forth.rs  —  AST -> Forth code generator

use crate::compiler::ast::{Node, BinOp, UnOp};

pub struct Emitter {
    out:   Vec<String>,
    label: usize,
}

impl Emitter {
    pub fn new() -> Self { Self { out: Vec::new(), label: 0 } }

    fn w(&mut self, s: impl Into<String>) { self.out.push(s.into()); }

    fn fresh(&mut self) -> usize { let n = self.label; self.label += 1; n }

    pub fn emit_all(&mut self, nodes: &[Node]) {
        for n in nodes { self.node(n); self.w("\n"); }
    }

    pub fn finish(self) -> Vec<String> { self.out }

    fn node(&mut self, n: &Node) {
        match n {
            Node::Function { name, lifetime, params, body } => {
                self.w(format!("\\ fn {}  [lifetime={}]", name, lifetime));
                self.w(format!(": {}", name));
                if params.is_empty() { self.w("( -- )"); }
                else { self.w(format!("( {} -- )", params.join(" "))); }
                // pop params from stack into local variables, right to left
                for p in params.iter().rev() {
                    self.w(format!("VARIABLE {}", p));
                    self.w(format!("{} !", p));
                }
                self.node(body);
                self.w(";");
            }

            Node::Block(stmts) | Node::Unsafe(stmts) => {
                for s in stmts { self.node(s); }
            }

            Node::Let { name, init } => {
                self.node(init);
                self.w(format!("VARIABLE {}", name));
                self.w(format!("{} !", name));
            }

            Node::Return(expr) => {
                if let Some(e) = expr { self.node(e); } else { self.w("0"); }
                self.w("EXIT");
            }

            Node::If { cond, then_br, else_br } => {
                self.node(cond);
                self.w("IF");
                self.node(then_br);
                if let Some(eb) = else_br { self.w("ELSE"); self.node(eb); }
                self.w("THEN");
            }

            Node::While { cond, body } => {
                self.w("BEGIN");
                self.node(cond);
                self.w("WHILE");
                self.node(body);
                self.w("REPEAT");
            }

            Node::BinOp { op, left, right } => {
                if *op == BinOp::Assign {
                    self.node(right);
                    if let Node::Ident(name) = left.as_ref() {
                        self.w(format!("{} !", name));
                    }
                    return;
                }
                self.node(left);
                self.node(right);
                let word = match op {
                    BinOp::Add  => "+",   BinOp::Sub => "-",  BinOp::Mul => "*",
                    BinOp::Div  => "/",   BinOp::Mod => "MOD",
                    BinOp::Eq   => "=",   BinOp::Neq => "<>",
                    BinOp::Lt   => "<",   BinOp::Gt  => ">",
                    BinOp::Le   => "<=",  BinOp::Ge  => ">=",
                    BinOp::And  => "AND", BinOp::Or  => "OR",
                    BinOp::Assign => unreachable!(),
                };
                self.w(word);
            }

            Node::UnOp { op, operand } => {
                self.node(operand);
                match op { UnOp::Neg => self.w("NEGATE"), UnOp::Not => self.w("NOT") }
            }

            Node::Call { name, args } => {
                for a in args { self.node(a); }
                self.w(name);
            }

            Node::Chain { left, right } => {
                // self is first arg on stack
                self.node(left);
                match right.as_ref() {
                    Node::Call { name, args } => { for a in args { self.node(a); } self.w(name); }
                    other => self.node(other),
                }
            }

            Node::Int(n)   => self.w(n.to_string()),
            Node::Bool(b)  => self.w(if *b { "-1" } else { "0" }),
            Node::Ident(n) => self.w(format!("{} @", n)),
            Node::Error(m) => self.w(format!("\\ ERROR: {}", m)),
        }
    }
}

pub fn generate(nodes: &[Node]) -> Vec<String> {
    let mut e = Emitter::new();
    e.emit_all(nodes);
    e.finish()
}
