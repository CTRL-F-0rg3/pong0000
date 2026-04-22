// src/compiler/semantic.rs
// Analiza semantyczna: type checker + scope manager + lifetime verifier.
// Przechodzi po drzewie Node i zbiera błędy zamiast panikować.

use crate::compiler::ast::{Node, BinOp, UnOp};
use std::collections::HashMap;

// ============================================================================
// SYSTEM TYPÓW
// ============================================================================
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Type {
    I8, I32, I64,
    F32,
    Bool,
    Str,
    Void,
    Ptr(Box<Type>),
    Unknown,     // przed inferencją
    Error,       // po błędzie
}

impl std::fmt::Display for Type {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Type::I8       => write!(f, "i8"),
            Type::I32      => write!(f, "i32"),
            Type::I64      => write!(f, "i64"),
            Type::F32      => write!(f, "f32"),
            Type::Bool     => write!(f, "bool"),
            Type::Str      => write!(f, "str"),
            Type::Void     => write!(f, "void"),
            Type::Ptr(t)   => write!(f, "*{}", t),
            Type::Unknown  => write!(f, "?"),
            Type::Error    => write!(f, "!"),
        }
    }
}

// ============================================================================
// BŁĘDY SEMANTYCZNE
// ============================================================================
#[derive(Debug, Clone)]
pub struct SemanticError {
    pub kind:    ErrorKind,
    pub context: String,
}

#[derive(Debug, Clone)]
pub enum ErrorKind {
    UndefinedVariable(String),
    TypeMismatch { expected: Type, got: Type },
    LifetimeViolation { var: String, declared: u64, used_at: u64 },
    InvalidBinOp { op: BinOp, left: Type, right: Type },
    ReturnTypeMismatch { expected: Type, got: Type },
    UnsafeOutsideBlock(String),
    DuplicateDefinition(String),
}

impl std::fmt::Display for SemanticError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.kind {
            ErrorKind::UndefinedVariable(n) =>
                write!(f, "undefined variable `{}`  (in {})", n, self.context),
            ErrorKind::TypeMismatch { expected, got } =>
                write!(f, "type mismatch: expected `{}`, got `{}`  (in {})", expected, got, self.context),
            ErrorKind::LifetimeViolation { var, declared, used_at } =>
                write!(f, "lifetime violation: `{}` declared with lifetime={} but used at depth {}  (in {})",
                    var, declared, used_at, self.context),
            ErrorKind::InvalidBinOp { op, left, right } =>
                write!(f, "invalid binary op `{:?}` on `{}` and `{}`  (in {})", op, left, right, self.context),
            ErrorKind::ReturnTypeMismatch { expected, got } =>
                write!(f, "return type mismatch: expected `{}`, got `{}`  (in {})", expected, got, self.context),
            ErrorKind::UnsafeOutsideBlock(op) =>
                write!(f, "unsafe operation `{}` outside unsafe block  (in {})", op, self.context),
            ErrorKind::DuplicateDefinition(n) =>
                write!(f, "duplicate definition of `{}`  (in {})", n, self.context),
        }
    }
}

// ============================================================================
// WPIS W TABLICY SYMBOLI (zakres)
// ============================================================================
#[derive(Debug, Clone)]
pub struct VarInfo {
    pub ty:       Type,
    pub lifetime: u64,     // L_V z deklaracji lub 0
    pub depth:    u64,     // głębokość zakresu przy deklaracji
    pub mutable:  bool,
}

// ============================================================================
// ZAKRES (Scope)
// ============================================================================
struct Scope {
    vars:  HashMap<String, VarInfo>,
    depth: u64,
}

// ============================================================================
// KONTEKST ANALIZY
// ============================================================================
pub struct Checker {
    scopes:      Vec<Scope>,
    errors:      Vec<SemanticError>,
    current_fn:  Option<String>,
    fn_lifetime: u64,          // lifetime bieżącej funkcji
    in_unsafe:   bool,
    scope_depth: u64,
}

impl Checker {
    pub fn new() -> Self {
        Self {
            scopes:      vec![Scope { vars: HashMap::new(), depth: 0 }],
            errors:      Vec::new(),
            current_fn:  None,
            fn_lifetime: 0,
            in_unsafe:   false,
            scope_depth: 0,
        }
    }

    // ---- Zakres ----

    fn push_scope(&mut self) {
        self.scope_depth += 1;
        self.scopes.push(Scope { vars: HashMap::new(), depth: self.scope_depth });
    }

    fn pop_scope(&mut self) {
        self.scopes.pop();
        if self.scope_depth > 0 { self.scope_depth -= 1; }
    }

    fn define(&mut self, name: &str, info: VarInfo) {
        if let Some(scope) = self.scopes.last_mut() {
            scope.vars.insert(name.to_owned(), info);
        }
    }

    fn lookup(&self, name: &str) -> Option<&VarInfo> {
        for scope in self.scopes.iter().rev() {
            if let Some(info) = scope.vars.get(name) {
                return Some(info);
            }
        }
        None
    }

    // ---- Błąd ----

    fn error(&mut self, kind: ErrorKind) {
        let ctx = self.current_fn.clone().unwrap_or_else(|| "<top>".into());
        self.errors.push(SemanticError { kind, context: ctx });
    }

    // =========================================================================
    // GŁÓWNE PRZEJŚCIE
    // =========================================================================
    pub fn check_program(&mut self, nodes: &[Node]) {
        for node in nodes {
            self.check_node(node);
        }
    }

    fn check_node(&mut self, node: &Node) -> Type {
        match node {
            Node::Function { name, lifetime, params, body } =>
                self.check_function(name, *lifetime, params, body),

            Node::Block(stmts) => {
                self.push_scope();
                let mut last = Type::Void;
                for s in stmts { last = self.check_node(s); }
                self.pop_scope();
                last
            }

            Node::Let { name, init } => {
                // Sprawdź duplikat w bieżącym zakresie
                if let Some(scope) = self.scopes.last() {
                    if scope.vars.contains_key(name.as_str()) {
                        self.error(ErrorKind::DuplicateDefinition(name.clone()));
                    }
                }
                let ty = self.check_node(init);
                self.define(name, VarInfo {
                    ty:       ty.clone(),
                    lifetime: self.fn_lifetime,
                    depth:    self.scope_depth,
                    mutable:  true,
                });
                ty
            }

            Node::Return(expr) => {
                let got = expr.as_ref().map(|e| self.check_node(e)).unwrap_or(Type::Void);
                // (typ zwrotny jest na razie Unknown — sprawdzamy w przyszłości)
                got
            }

            Node::If { cond, then_br, else_br } => {
                let ct = self.check_node(cond);
                if ct != Type::Bool && ct != Type::Unknown {
                    self.error(ErrorKind::TypeMismatch {
                        expected: Type::Bool, got: ct,
                    });
                }
                self.push_scope();
                let tt = self.check_node(then_br);
                self.pop_scope();
                if let Some(eb) = else_br {
                    self.push_scope();
                    let et = self.check_node(eb);
                    self.pop_scope();
                    // Gałęzie muszą mieć ten sam typ (ignorujemy Void)
                    if tt != et && tt != Type::Void && et != Type::Void {
                        self.error(ErrorKind::TypeMismatch {
                            expected: tt.clone(), got: et,
                        });
                    }
                }
                tt
            }

            Node::While { cond, body } => {
                let ct = self.check_node(cond);
                if ct != Type::Bool && ct != Type::Unknown {
                    self.error(ErrorKind::TypeMismatch {
                        expected: Type::Bool, got: ct,
                    });
                }
                self.push_scope();
                self.check_node(body);
                self.pop_scope();
                Type::Void
            }

            Node::BinOp { op, left, right } =>
                self.check_binop(*op, left, right),

            Node::UnOp { op, operand } =>
                self.check_unop(*op, operand),

            Node::Call { name, args } => {
                for a in args { self.check_node(a); }
                // Bez sygnatury funkcji zwracamy Unknown (rozwiązywane w etapie 3)
                let _ = name;
                Type::Unknown
            }

            Node::Chain { left, right } => {
                self.check_node(left);
                self.check_node(right)
            }

            Node::Ident(name) => {
                // Klonuj potrzebne dane zanim pożyczymy self mutably
                let found = self.lookup(name).map(|info| {
                    (info.ty.clone(), info.lifetime, info.depth)
                });
                if let Some((ty, lifetime, depth)) = found {
                    if lifetime > 0 && self.scope_depth > depth + lifetime {
                        self.error(ErrorKind::LifetimeViolation {
                            var:      name.clone(),
                            declared: lifetime,
                            used_at:  self.scope_depth,
                        });
                    }
                    ty
                } else {
                    self.error(ErrorKind::UndefinedVariable(name.clone()));
                    Type::Error
                }
            }

            Node::Int(_)  => Type::I64,
            Node::Bool(_) => Type::Bool,

            Node::Error(msg) => {
                // Błąd parsera — przekaż dalej jako diagnostykę
                eprintln!("  [parse error node] {}", msg);
                Type::Error
            }

            _ => Type::Unknown,
        }
    }

    // ---- Funkcja ----
    fn check_function(&mut self, name: &str, lifetime: u64, params: &[String], body: &Node) -> Type {
        let prev_fn  = self.current_fn.replace(name.to_owned());
        let prev_lt  = self.fn_lifetime;
        self.fn_lifetime = lifetime;

        self.push_scope();
        // Zarejestruj parametry z Unknown typem (inference w przyszłości)
        for p in params {
            self.define(p, VarInfo {
                ty: Type::Unknown, lifetime, depth: self.scope_depth, mutable: false,
            });
        }
        self.check_node(body);
        self.pop_scope();

        self.fn_lifetime = prev_lt;
        self.current_fn  = prev_fn;
        Type::Void
    }

    // ---- Operacje binarne ----
    fn check_binop(&mut self, op: BinOp, left: &Node, right: &Node) -> Type {
        let lt = self.check_node(left);
        let rt = self.check_node(right);

        // Jeśli Unknown — inferencja, nie błąd
        if lt == Type::Unknown || rt == Type::Unknown { return Type::Unknown; }

        match op {
            // Arytmetyka: oba muszą być liczbami
            BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod => {
                if !is_numeric(&lt) {
                    self.error(ErrorKind::InvalidBinOp { op, left: lt.clone(), right: rt.clone() });
                    return Type::Error;
                }
                if lt != rt {
                    self.error(ErrorKind::TypeMismatch { expected: lt.clone(), got: rt.clone() });
                    return Type::Error;
                }
                lt
            }

            // Porównania → bool
            BinOp::Eq | BinOp::Neq | BinOp::Lt | BinOp::Gt | BinOp::Le | BinOp::Ge => {
                if lt != rt {
                    self.error(ErrorKind::TypeMismatch { expected: lt, got: rt });
                }
                Type::Bool
            }

            // Logika: oba bool
            BinOp::And | BinOp::Or => {
                if lt != Type::Bool {
                    self.error(ErrorKind::TypeMismatch { expected: Type::Bool, got: lt.clone() });
                }
                if rt != Type::Bool {
                    self.error(ErrorKind::TypeMismatch { expected: Type::Bool, got: rt.clone() });
                }
                Type::Bool
            }

            // Przypisanie: typy muszą pasować
            BinOp::Assign => {
                if lt != rt {
                    self.error(ErrorKind::TypeMismatch { expected: lt.clone(), got: rt });
                }
                lt
            }
        }
    }

    // ---- Operacje unarne ----
    fn check_unop(&mut self, op: UnOp, operand: &Node) -> Type {
        let t = self.check_node(operand);
        match op {
            UnOp::Neg => {
                if !is_numeric(&t) && t != Type::Unknown {
                    self.error(ErrorKind::TypeMismatch { expected: Type::I64, got: t.clone() });
                }
                t
            }
            UnOp::Not => {
                if t != Type::Bool && t != Type::Unknown {
                    self.error(ErrorKind::TypeMismatch { expected: Type::Bool, got: t.clone() });
                }
                Type::Bool
            }
        }
    }

    // ---- Wyniki ----
    pub fn into_errors(self) -> Vec<SemanticError> { self.errors }
    pub fn errors(&self)    -> &[SemanticError]    { &self.errors }
    pub fn has_errors(&self) -> bool               { !self.errors.is_empty() }
}

fn is_numeric(t: &Type) -> bool {
    matches!(t, Type::I8 | Type::I32 | Type::I64 | Type::F32)
}

// ============================================================================
// PUBLICZNY INTERFEJS
// ============================================================================
pub fn check(nodes: &[Node]) -> Vec<SemanticError> {
    let mut checker = Checker::new();
    checker.check_program(nodes);
    checker.into_errors()
}
