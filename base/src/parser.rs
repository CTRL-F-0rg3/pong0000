// src/compiler/parser.rs
// Pratt parser w czystym Rust.
// Wejście: &[RawToken] z ASM lexera
// Wyjście: Vec<Node> (lista top-level deklaracji)

use crate::compiler::ffi::{RawToken, read_symbol, tok::*};
use crate::compiler::ast::{Node, BinOp, UnOp};

// ============================================================================
// BŁĘDY PARSERA
// ============================================================================
#[derive(Debug, Clone)]
pub struct ParseError {
    pub msg: String,
    pub pos: usize,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ParseError at token {}: {}", self.pos, self.msg)
    }
}

type PResult<T> = Result<T, ParseError>;

// ============================================================================
// KURSOR TOKENÓW
// ============================================================================
struct Parser<'a> {
    tokens:    &'a [RawToken],
    sym_table: &'a [u8],
    pos:       usize,
}

impl<'a> Parser<'a> {
    fn new(tokens: &'a [RawToken], sym_table: &'a [u8]) -> Self {
        Self { tokens, sym_table, pos: 0 }
    }

    // ---- Peek / advance ----

    fn peek(&self) -> u64 {
        self.tokens.get(self.pos).map(|t| t.id).unwrap_or(0)
    }

    fn peek_val(&self) -> u64 {
        self.tokens.get(self.pos).map(|t| t.value).unwrap_or(0)
    }

    fn peek2(&self) -> u64 {
        self.tokens.get(self.pos + 1).map(|t| t.id).unwrap_or(0)
    }

    fn advance(&mut self) -> &RawToken {
        let t = &self.tokens[self.pos];
        self.pos += 1;
        t
    }

    fn is_eof(&self) -> bool {
        self.pos >= self.tokens.len()
    }

    // ---- Expect helpers ----

    fn expect(&mut self, id: u64, desc: &str) -> PResult<&RawToken> {
        if self.peek() == id {
            Ok(self.advance())
        } else {
            Err(self.err(format!("expected {}, got token id={}", desc, self.peek())))
        }
    }

    fn eat(&mut self, id: u64) -> bool {
        if self.peek() == id { self.advance(); true } else { false }
    }

    fn err(&self, msg: String) -> ParseError {
        ParseError { msg, pos: self.pos }
    }

    // ---- Symbol helper ----

    fn sym(&self, addr: u64) -> String {
        read_symbol(self.sym_table, addr).to_owned()
    }

    // =========================================================================
    // TOP-LEVEL
    // =========================================================================
    fn parse_program(&mut self) -> PResult<Vec<Node>> {
        let mut items = Vec::new();
        while !self.is_eof() {
            self.eat(KW_PUB); // optional pub
            match self.peek() {
                KW_FN     => items.push(self.parse_function()?),
                KW_STRUCT => items.push(self.parse_struct()?),
                _         => { self.advance(); } // skip unknown top-level
            }
        }
        Ok(items)
    }

    // =========================================================================
    // FUNKCJA: fn name(lifetime?, params) -> RetType? { body }
    // =========================================================================
    fn parse_function(&mut self) -> PResult<Node> {
        self.expect(KW_FN, "fn")?;

        // Nazwa funkcji
        if self.peek() != T_IDENTIFIER {
            return Err(self.err(format!("expected function name, got {}", self.peek())));
        }
        let name_addr = self.peek_val();
        let name = self.sym(name_addr);
        self.advance();

        self.expect(SYM_LPAREN, "(")?;

        // Lifetime: pierwsza liczba całkowita w nawiasach
        let mut lifetime = 0u64;
        let mut params   = Vec::new();

        if self.peek() == L_INT {
            lifetime = self.peek_val();
            self.advance();
            self.eat(SYM_COMMA);
        }

        // Pozostałe parametry — identyfikatory
        while self.peek() != SYM_RPAREN && !self.is_eof() {
            if self.peek() == T_IDENTIFIER {
                let paddr = self.peek_val();
                params.push(self.sym(paddr));
                self.advance();
            } else {
                self.advance(); // pomiń nieznane
            }
            self.eat(SYM_COMMA);
        }
        self.expect(SYM_RPAREN, ")")?;

        // Opcjonalny typ zwrotny: -> TYPE
        if self.eat(SYM_ARROW) {
            self.advance(); // pomiń typ zwrotny (na razie)
        }

        let body = self.parse_block()?;

        Ok(Node::Function { name, lifetime, params, body: Box::new(body) })
    }

    // =========================================================================
    // STRUCT: struct Name { fields }
    // =========================================================================
    fn parse_struct(&mut self) -> PResult<Node> {
        self.expect(KW_STRUCT, "struct")?;
        // Uproszczenie: parsuj nazwę + pomiń ciało
        if self.peek() == T_IDENTIFIER { self.advance(); }
        if self.peek() == SYM_LBRACE {
            self.skip_balanced(SYM_LBRACE, SYM_RBRACE);
        }
        // Zwróć pusty blok (struct support w etapie 2)
        Ok(Node::Block(vec![]))
    }

    // =========================================================================
    // BLOK: { stmt* }
    // =========================================================================
    fn parse_block(&mut self) -> PResult<Node> {
        self.expect(SYM_LBRACE, "{")?;
        let mut stmts = Vec::new();
        while self.peek() != SYM_RBRACE && !self.is_eof() {
            if let Some(s) = self.parse_statement()? {
                stmts.push(s);
            }
        }
        self.expect(SYM_RBRACE, "}")?;
        Ok(Node::Block(stmts))
    }

    // =========================================================================
    // INSTRUKCJA
    // =========================================================================
    fn parse_statement(&mut self) -> PResult<Option<Node>> {
        match self.peek() {
            KW_LET    => Ok(Some(self.parse_let()?)),
            KW_RETURN => Ok(Some(self.parse_return()?)),
            KW_IF     => Ok(Some(self.parse_if()?)),
            KW_WHILE  => Ok(Some(self.parse_while()?)),
            KW_FOR    => Ok(Some(self.parse_for()?)),
            SYM_SEMI  => { self.advance(); Ok(None) }
            _         => Ok(Some(self.parse_expr_stmt()?)),
        }
    }

    // let NAME = EXPR ;
    fn parse_let(&mut self) -> PResult<Node> {
        self.expect(KW_LET, "let")?;
        if self.peek() != T_IDENTIFIER {
            return Err(self.err("expected variable name after let".into()));
        }
        let name = self.sym(self.peek_val());
        self.advance();
        self.expect(OP_ASSIGN, "=")?;
        let init = self.parse_expr(PREC_NONE)?;
        self.eat(SYM_SEMI);
        Ok(Node::Let { name, init: Box::new(init) })
    }

    // return EXPR? ;
    fn parse_return(&mut self) -> PResult<Node> {
        self.expect(KW_RETURN, "return")?;
        if self.peek() == SYM_SEMI || self.peek() == SYM_RBRACE {
            self.eat(SYM_SEMI);
            return Ok(Node::Return(None));
        }
        let expr = self.parse_expr(PREC_NONE)?;
        self.eat(SYM_SEMI);
        Ok(Node::Return(Some(Box::new(expr))))
    }

    // if EXPR BLOCK (else (if BLOCK | BLOCK))?
    fn parse_if(&mut self) -> PResult<Node> {
        self.expect(KW_IF, "if")?;
        let cond    = self.parse_expr(PREC_NONE)?;
        let then_br = self.parse_block()?;
        let else_br = if self.eat(KW_ELSE) {
            if self.peek() == KW_IF {
                Some(Box::new(self.parse_if()?))
            } else {
                Some(Box::new(self.parse_block()?))
            }
        } else {
            None
        };
        Ok(Node::If {
            cond:    Box::new(cond),
            then_br: Box::new(then_br),
            else_br,
        })
    }

    // while EXPR BLOCK
    fn parse_while(&mut self) -> PResult<Node> {
        self.expect(KW_WHILE, "while")?;
        let cond = self.parse_expr(PREC_NONE)?;
        let body = self.parse_block()?;
        Ok(Node::While { cond: Box::new(cond), body: Box::new(body) })
    }

    // for NAME in EXPR BLOCK  (uproszczone)
    fn parse_for(&mut self) -> PResult<Node> {
        self.expect(KW_FOR, "for")?;
        let name = if self.peek() == T_IDENTIFIER {
            let n = self.sym(self.peek_val()); self.advance(); n
        } else { "_".into() };
        // pomiń "in"
        if self.peek() == T_IDENTIFIER { self.advance(); }
        let iter = self.parse_expr(PREC_NONE)?;
        let body = self.parse_block()?;
        // Modelujemy jako while z iteratorem (uproszczone)
        Ok(Node::While {
            cond: Box::new(Node::Bool(true)),
            body: Box::new(Node::Block(vec![
                Node::Let { name, init: Box::new(iter) },
                body,
            ])),
        })
    }

    // EXPR ;
    fn parse_expr_stmt(&mut self) -> PResult<Node> {
        let e = self.parse_expr(PREC_NONE)?;
        self.eat(SYM_SEMI);
        Ok(e)
    }

    // =========================================================================
    // PRATT PARSER — wyrażenia z priorytetami
    // =========================================================================
    fn parse_expr(&mut self, min_prec: u8) -> PResult<Node> {
        let mut left = self.parse_prefix()?;

        loop {
            let prec = infix_prec(self.peek());
            if prec <= min_prec { break; }

            let op_id = self.peek();
            self.advance();

            // Obsługa postfiksowego . (chain/call)
            if op_id == SYM_DOT {
                left = self.parse_dot_rhs(left)?;
                continue;
            }

            // Wywołanie jako infix: expr(args) — rzadkie, ale możliwe
            if op_id == SYM_LPAREN {
                let args = self.parse_arg_list()?;
                self.expect(SYM_RPAREN, ")")?;
                // Owiń lewą stronę w Call
                let name = match &left {
                    Node::Ident(n) => n.clone(),
                    _ => "<expr>".into(),
                };
                left = Node::Call { name, args };
                continue;
            }

            // Prawo- lub lewostronny
            let right_prec = if op_id == OP_ASSIGN { PREC_NONE } else { prec };
            let right = self.parse_expr(right_prec)?;

            if let Some(op) = BinOp::from_raw(op_id) {
                left = Node::BinOp {
                    op,
                    left:  Box::new(left),
                    right: Box::new(right),
                };
            }
        }

        Ok(left)
    }

    // PREFIX: literały, identyfikatory, wywołania, nawiasy, unarny
    fn parse_prefix(&mut self) -> PResult<Node> {
        let id  = self.peek();
        let val = self.peek_val();

        match id {
            // Liczba całkowita
            L_INT => {
                self.advance();
                Ok(Node::Int(val as i64))
            }

            // Bool
            L_TRUE  => { self.advance(); Ok(Node::Bool(true))  }
            L_FALSE => { self.advance(); Ok(Node::Bool(false)) }

            // Identyfikator lub wywołanie
            T_IDENTIFIER => {
                let name = self.sym(val);
                self.advance();

                if self.peek() == SYM_LPAREN {
                    // Wywołanie: f(args)
                    self.advance();
                    let args = self.parse_arg_list()?;
                    self.expect(SYM_RPAREN, ")")?;
                    Ok(Node::Call { name, args })
                } else {
                    Ok(Node::Ident(name))
                }
            }

            // Wyrażenie w nawiasach
            SYM_LPAREN => {
                self.advance();
                let e = self.parse_expr(PREC_NONE)?;
                self.expect(SYM_RPAREN, ")")?;
                Ok(e)
            }

            // Unarny minus
            OP_SUB => {
                self.advance();
                let operand = self.parse_expr(PREC_UNARY)?;
                Ok(Node::UnOp { op: UnOp::Neg, operand: Box::new(operand) })
            }

            // Unarny NOT
            OP_NOT => {
                self.advance();
                let operand = self.parse_expr(PREC_UNARY)?;
                Ok(Node::UnOp { op: UnOp::Not, operand: Box::new(operand) })
            }

            // Blok jako wyrażenie
            SYM_LBRACE => self.parse_block(),

            _ => {
                // Pomiń nieznany token zamiast panikowac
                self.advance();
                Ok(Node::Error(format!("unexpected token id={}", id)))
            }
        }
    }

    // Prawa strona `.` : identyfikator lub wywołanie
    fn parse_dot_rhs(&mut self, left: Node) -> PResult<Node> {
        if self.peek() != T_IDENTIFIER {
            return Err(self.err("expected identifier after '.'".into()));
        }
        let name = self.sym(self.peek_val());
        self.advance();

        let right = if self.peek() == SYM_LPAREN {
            self.advance();
            let args = self.parse_arg_list()?;
            self.expect(SYM_RPAREN, ")")?;
            Node::Call { name, args }
        } else {
            Node::Ident(name)
        };

        Ok(Node::Chain { left: Box::new(left), right: Box::new(right) })
    }

    // Lista argumentów (bez zewnętrznych nawiasów)
    fn parse_arg_list(&mut self) -> PResult<Vec<Node>> {
        let mut args = Vec::new();
        while self.peek() != SYM_RPAREN && !self.is_eof() {
            args.push(self.parse_expr(PREC_ASSIGN)?);
            if !self.eat(SYM_COMMA) { break; }
        }
        Ok(args)
    }

    // Pomiń zbalansowany blok ( ... ) lub { ... }
    fn skip_balanced(&mut self, open: u64, close: u64) {
        if self.peek() == open { self.advance(); } else { return; }
        let mut depth = 1;
        while !self.is_eof() && depth > 0 {
            let t = self.advance().id;
            if t == open  { depth += 1; }
            if t == close { depth -= 1; }
        }
    }
}

// ============================================================================
// PRIORYTETY OPERATORÓW
// ============================================================================
const PREC_NONE:    u8 = 0;
const PREC_ASSIGN:  u8 = 1;
const PREC_OR:      u8 = 2;
const PREC_AND:     u8 = 3;
const PREC_EQUAL:   u8 = 4;
const PREC_COMPARE: u8 = 5;
const PREC_ADD:     u8 = 6;
const PREC_MUL:     u8 = 7;
const PREC_UNARY:   u8 = 8;
const PREC_CALL:    u8 = 9;

fn infix_prec(id: u64) -> u8 {
    match id {
        OP_ASSIGN                    => PREC_ASSIGN,
        OP_OR                        => PREC_OR,
        OP_AND                       => PREC_AND,
        OP_EQ | OP_NEQ               => PREC_EQUAL,
        OP_LT | OP_GT | OP_LE | OP_GE => PREC_COMPARE,
        OP_ADD | OP_SUB              => PREC_ADD,
        OP_MUL | OP_DIV | OP_MOD    => PREC_MUL,
        SYM_DOT | SYM_LPAREN        => PREC_CALL,
        _                            => PREC_NONE,
    }
}

// ============================================================================
// PUBLICZNY INTERFEJS
// ============================================================================
pub fn parse(tokens: &[RawToken], sym_table: &[u8]) -> Result<Vec<Node>, ParseError> {
    let mut p = Parser::new(tokens, sym_table);
    p.parse_program()
}
