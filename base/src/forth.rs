// src/compiler/forth.rs
// Transpiler AST → kod Forth.
// Strategia: każde wyrażenie zostawia wartość na stosie.
// Instrukcje sterujące używają standardowych słów Forth: IF ELSE THEN, BEGIN WHILE REPEAT.

use crate::compiler::ast::{Node, BinOp, UnOp};

// ============================================================================
// EMITER KODU FORTH
// ============================================================================
pub struct ForthEmitter {
    output: Vec<String>,
    label_counter: usize,
}

impl ForthEmitter {
    pub fn new() -> Self {
        Self { output: Vec::new(), label_counter: 0 }
    }

    fn emit(&mut self, s: impl Into<String>) {
        self.output.push(s.into());
    }

    fn fresh_label(&mut self) -> usize {
        let n = self.label_counter;
        self.label_counter += 1;
        n
    }

    pub fn code(&self) -> String {
        self.output.join(" ")
    }

    pub fn lines(&self) -> Vec<&str> {
        self.output.iter().map(|s| s.as_str()).collect()
    }

    // =========================================================================
    // TOP LEVEL
    // =========================================================================
    pub fn emit_program(&mut self, nodes: &[Node]) {
        for node in nodes {
            self.emit_node(node);
            self.emit("\n");
        }
    }

    // =========================================================================
    // GŁÓWNA DYSPOZYCJA
    // =========================================================================
    fn emit_node(&mut self, node: &Node) {
        match node {
            Node::Function { name, lifetime, params, body } =>
                self.emit_function(name, *lifetime, params, body),

            Node::Block(stmts) => {
                for s in stmts { self.emit_node(s); }
            }

            Node::Let { name, init } => {
                // Wylicz inicjalizator → wartość na stosie
                self.emit_node(init);
                // Forth: utwórz zmienną i zapisz
                // ( val -- )
                self.emit(format!("VARIABLE {}", name));
                self.emit(format!("{} !", name));  // ! = store
            }

            Node::Return(expr) => {
                if let Some(e) = expr {
                    self.emit_node(e);
                } else {
                    self.emit("0");
                }
                self.emit("EXIT");
            }

            Node::If { cond, then_br, else_br } =>
                self.emit_if(cond, then_br, else_br.as_deref()),

            Node::While { cond, body } =>
                self.emit_while(cond, body),

            Node::BinOp { op, left, right } =>
                self.emit_binop(*op, left, right),

            Node::UnOp { op, operand } =>
                self.emit_unop(*op, operand),

            Node::Call { name, args } =>
                self.emit_call(name, args),

            Node::Chain { left, right } =>
                self.emit_chain(left, right),

            Node::Int(n)  => self.emit(n.to_string()),
            Node::Bool(b) => self.emit(if *b { "-1" } else { "0" }),  // Forth: -1=true, 0=false
            Node::Ident(n) => {
                // Odczyt zmiennej: zmienna @ (@ = fetch)
                self.emit(format!("{} @", n));
            }

            Node::Error(msg) => {
                self.emit(format!("\\ ERROR: {}", msg));
            }

            _ => {
                self.emit("\\ (unimplemented node)");
            }
        }
    }

    // =========================================================================
    // FUNKCJA → słowo Forth  : name ( params -- ) body ;
    // =========================================================================
    fn emit_function(&mut self, name: &str, lifetime: u64, params: &[String], body: &Node) {
        self.emit(format!("\\ fn {}  lifetime={}", name, lifetime));
        self.emit(format!(": {}", name));

        // Stack comment: ( param1 param2 -- result )
        if !params.is_empty() {
            self.emit(format!("( {} -- )", params.join(" ")));
        } else {
            self.emit("( -- )");
        }

        // Wciągnij parametry ze stosu do zmiennych lokalnych (od prawej do lewej)
        for param in params.iter().rev() {
            self.emit(format!("VARIABLE {} {} !", param, param));
        }

        self.emit_node(body);
        self.emit(";");
        self.emit("\n");
    }

    // =========================================================================
    // IF / ELSE / THEN
    // Forth: <cond> IF <then> ELSE <else> THEN
    // =========================================================================
    fn emit_if(&mut self, cond: &Node, then_br: &Node, else_br: Option<&Node>) {
        self.emit_node(cond);
        self.emit("IF");
        self.emit_node(then_br);
        if let Some(eb) = else_br {
            self.emit("ELSE");
            self.emit_node(eb);
        }
        self.emit("THEN");
    }

    // =========================================================================
    // WHILE
    // Forth: BEGIN <cond> WHILE <body> REPEAT
    // =========================================================================
    fn emit_while(&mut self, cond: &Node, body: &Node) {
        self.emit("BEGIN");
        self.emit_node(cond);
        self.emit("WHILE");
        self.emit_node(body);
        self.emit("REPEAT");
    }

    // =========================================================================
    // OPERATORY BINARNE
    // Forth: odwrotna notacja polska — najpierw operandy, potem operator
    // a + b  →  a b +
    // a == b →  a b =
    // =========================================================================
    fn emit_binop(&mut self, op: BinOp, left: &Node, right: &Node) {
        // Przypisanie jest wyjątkiem: x = expr  →  expr x !
        if op == BinOp::Assign {
            self.emit_node(right);
            if let Node::Ident(name) = left {
                self.emit(format!("{} !", name));
            }
            return;
        }

        self.emit_node(left);
        self.emit_node(right);

        let word = match op {
            BinOp::Add  => "+",
            BinOp::Sub  => "-",
            BinOp::Mul  => "*",
            BinOp::Div  => "/",
            BinOp::Mod  => "MOD",
            BinOp::Eq   => "=",
            BinOp::Neq  => "<>",
            BinOp::Lt   => "<",
            BinOp::Gt   => ">",
            BinOp::Le   => "<=",
            BinOp::Ge   => ">=",
            BinOp::And  => "AND",
            BinOp::Or   => "OR",
            BinOp::Assign => unreachable!(),
        };
        self.emit(word);
    }

    // =========================================================================
    // OPERATORY UNARNE
    // =========================================================================
    fn emit_unop(&mut self, op: UnOp, operand: &Node) {
        self.emit_node(operand);
        match op {
            UnOp::Neg => self.emit("NEGATE"),
            UnOp::Not => self.emit("NOT"),    // Forth: bitwise NOT, dla bool OK
        }
    }

    // =========================================================================
    // WYWOŁANIE FUNKCJI
    // Forth: najpierw argumenty na stos, potem nazwa
    // f(a, b)  →  a b f
    // =========================================================================
    fn emit_call(&mut self, name: &str, args: &[Node]) {
        for a in args { self.emit_node(a); }
        self.emit(name);
    }

    // =========================================================================
    // CHAIN a.b(c)  →  a c b  (self jest pierwszym argumentem)
    // =========================================================================
    fn emit_chain(&mut self, left: &Node, right: &Node) {
        // Prawa strona to zwykle Call — wstrzyknij `left` jako pierwszy argument
        self.emit_node(left);
        match right {
            Node::Call { name, args } => {
                for a in args { self.emit_node(a); }
                self.emit(name);
            }
            _ => self.emit_node(right),
        }
    }
}

// ============================================================================
// PUBLICZNY INTERFEJS
// ============================================================================
pub fn generate(nodes: &[Node]) -> String {
    let mut emitter = ForthEmitter::new();
    emitter.emit_program(nodes);
    emitter.code()
}

/// Wersja z podziałem na linie — łatwiejsza do debugowania i wypisania
pub fn generate_lines(nodes: &[Node]) -> Vec<String> {
    let mut emitter = ForthEmitter::new();
    emitter.emit_program(nodes);
    emitter.output
}
