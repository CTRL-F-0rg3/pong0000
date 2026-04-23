// src/compiler/semantic.rs  —  type checker + scope manager + lifetime verifier

use crate::compiler::ast::{Node, BinOp, UnOp};
use std::collections::HashMap;

// ---- types ----
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Ty { I64, I32, I8, F32, Bool, Str, Void, Ptr(Box<Ty>), Unknown, Error }
impl std::fmt::Display for Ty {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Ty::I64       => write!(f, "i64"),
            Ty::I32       => write!(f, "i32"),
            Ty::I8        => write!(f, "i8"),
            Ty::F32       => write!(f, "f32"),
            Ty::Bool      => write!(f, "bool"),
            Ty::Str       => write!(f, "str"),
            Ty::Void      => write!(f, "void"),
            Ty::Ptr(t)    => write!(f, "*{}", t),
            Ty::Unknown   => write!(f, "?"),
            Ty::Error     => write!(f, "!"),
        }
    }
}
fn is_numeric(t: &Ty) -> bool { matches!(t, Ty::I64 | Ty::I32 | Ty::I8 | Ty::F32) }

// ---- errors ----
#[derive(Debug, Clone)]
pub struct SemError { pub msg: String }
impl std::fmt::Display for SemError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(f, "{}", self.msg) }
}

// ---- variable info ----
#[derive(Debug, Clone)]
struct VarInfo { ty: Ty, lifetime: u64, scope_depth: u64 }

// ---- checker ----
pub struct Checker {
    scopes:     Vec<HashMap<String, VarInfo>>,
    errors:     Vec<SemError>,
    fn_name:    String,
    fn_lifetime: u64,
    in_unsafe:  bool,
    depth:      u64,
}

impl Checker {
    pub fn new() -> Self {
        Self {
            scopes:      vec![HashMap::new()],
            errors:      Vec::new(),
            fn_name:     String::new(),
            fn_lifetime: 0,
            in_unsafe:   false,
            depth:       0,
        }
    }

    fn push(&mut self) { self.scopes.push(HashMap::new()); self.depth += 1; }
    fn pop (&mut self) { self.scopes.pop(); if self.depth > 0 { self.depth -= 1; } }

    fn define(&mut self, name: &str, info: VarInfo) {
        if let Some(scope) = self.scopes.last_mut() {
            scope.insert(name.to_owned(), info);
        }
    }

    fn lookup(&self, name: &str) -> Option<(Ty, u64, u64)> {
        for scope in self.scopes.iter().rev() {
            if let Some(v) = scope.get(name) {
                return Some((v.ty.clone(), v.lifetime, v.scope_depth));
            }
        }
        None
    }

    fn err(&mut self, msg: impl Into<String>) {
        let ctx = self.fn_name.clone();
        let m   = msg.into();
        self.errors.push(SemError { msg: if ctx.is_empty() { m } else { format!("{} (in {})", m, ctx) } });
    }

    // ---- public ----
    pub fn check_all(&mut self, nodes: &[Node]) { for n in nodes { self.check(n); } }
    pub fn errors(self) -> Vec<SemError> { self.errors }

    // ---- core ----
    fn check(&mut self, node: &Node) -> Ty {
        match node {
            Node::Function { name, lifetime, params, body } => {
                let prev_fn  = std::mem::replace(&mut self.fn_name, name.clone());
                let prev_lt  = self.fn_lifetime;
                self.fn_lifetime = *lifetime;
                self.push();
                for p in params {
                    self.define(p, VarInfo { ty: Ty::Unknown, lifetime: *lifetime, scope_depth: self.depth });
                }
                self.check(body);
                self.pop();
                self.fn_name    = prev_fn;
                self.fn_lifetime = prev_lt;
                Ty::Void
            }

            Node::Block(stmts) => {
                self.push();
                let mut last = Ty::Void;
                for s in stmts { last = self.check(s); }
                self.pop();
                last
            }

            Node::Unsafe(stmts) => {
                let prev = self.in_unsafe;
                self.in_unsafe = true;
                self.push();
                let mut last = Ty::Void;
                for s in stmts { last = self.check(s); }
                self.pop();
                self.in_unsafe = prev;
                last
            }

            Node::Let { name, init } => {
                // duplicate in current scope?
                if self.scopes.last().map(|s| s.contains_key(name.as_str())).unwrap_or(false) {
                    self.err(format!("duplicate definition of `{}`", name));
                }
                let ty = self.check(init);
                self.define(name, VarInfo { ty: ty.clone(), lifetime: self.fn_lifetime, scope_depth: self.depth });
                ty
            }

            Node::Return(expr) => {
                expr.as_ref().map(|e| self.check(e)).unwrap_or(Ty::Void)
            }

            Node::If { cond, then_br, else_br } => {
                let ct = self.check(cond);
                if ct != Ty::Bool && ct != Ty::Unknown {
                    self.err(format!("if condition must be bool, got `{}`", ct));
                }
                self.push(); let tt = self.check(then_br); self.pop();
                if let Some(eb) = else_br {
                    self.push(); let et = self.check(eb); self.pop();
                    if tt != et && tt != Ty::Void && et != Ty::Void {
                        self.err(format!("if branches have different types: `{}` vs `{}`", tt, et));
                    }
                }
                tt
            }

            Node::While { cond, body } => {
                let ct = self.check(cond);
                if ct != Ty::Bool && ct != Ty::Unknown {
                    self.err(format!("while condition must be bool, got `{}`", ct));
                }
                self.push(); self.check(body); self.pop();
                Ty::Void
            }

            Node::BinOp { op, left, right } => self.check_binop(*op, left, right),
            Node::UnOp  { op, operand }     => self.check_unop(*op, operand),

            Node::Call { name, args } => {
                for a in args { self.check(a); }
                // raw-pointer ops are only allowed in unsafe
                if (name == "ptr_read" || name == "ptr_write") && !self.in_unsafe {
                    self.err(format!("`{}` is only allowed inside an unsafe block", name));
                }
                Ty::Unknown
            }

            Node::Chain { left, right } => {
                self.check(left); self.check(right)
            }

            Node::Ident(name) => {
                match self.lookup(name) {
                    Some((ty, lifetime, decl_depth)) => {
                        // lifetime check: variable must not outlive its declared scope
                        if lifetime > 0 && self.depth > decl_depth + lifetime {
                            self.err(format!(
                                "lifetime violation: `{}` declared with lifetime={} at depth={} but used at depth={}",
                                name, lifetime, decl_depth, self.depth
                            ));
                        }
                        ty
                    }
                    None => {
                        self.err(format!("undefined variable `{}`", name));
                        Ty::Error
                    }
                }
            }

            Node::Int(_)   => Ty::I64,
            Node::Bool(_)  => Ty::Bool,
            Node::Error(m) => { eprintln!("  [parse node error] {}", m); Ty::Error }
        }
    }

    fn check_binop(&mut self, op: BinOp, left: &Node, right: &Node) -> Ty {
        let lt = self.check(left);
        let rt = self.check(right);
        if lt == Ty::Unknown || rt == Ty::Unknown { return Ty::Unknown; }
        match op {
            BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod => {
                if !is_numeric(&lt) {
                    self.err(format!("operator `{}` requires numeric operands, left is `{}`", op.symbol(), lt));
                    return Ty::Error;
                }
                if lt != rt {
                    self.err(format!("type mismatch in `{}`: `{}` vs `{}`", op.symbol(), lt, rt));
                    return Ty::Error;
                }
                lt
            }
            BinOp::Eq | BinOp::Neq | BinOp::Lt | BinOp::Gt | BinOp::Le | BinOp::Ge => {
                if lt != rt { self.err(format!("cannot compare `{}` with `{}`", lt, rt)); }
                Ty::Bool
            }
            BinOp::And | BinOp::Or => {
                if lt != Ty::Bool { self.err(format!("`&&`/`||` requires bool, left is `{}`",  lt)); }
                if rt != Ty::Bool { self.err(format!("`&&`/`||` requires bool, right is `{}`", rt)); }
                Ty::Bool
            }
            BinOp::Assign => {
                if lt != rt { self.err(format!("assignment type mismatch: `{}` = `{}`", lt, rt)); }
                lt
            }
        }
    }

    fn check_unop(&mut self, op: UnOp, operand: &Node) -> Ty {
        let t = self.check(operand);
        match op {
            UnOp::Neg => {
                if !is_numeric(&t) && t != Ty::Unknown {
                    self.err(format!("unary `-` requires numeric, got `{}`", t));
                }
                t
            }
            UnOp::Not => {
                if t != Ty::Bool && t != Ty::Unknown {
                    self.err(format!("unary `!` requires bool, got `{}`", t));
                }
                Ty::Bool
            }
        }
    }
}

pub fn check(nodes: &[Node]) -> Vec<SemError> {
    let mut c = Checker::new();
    c.check_all(nodes);
    c.errors()
}
