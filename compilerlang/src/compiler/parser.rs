// src/compiler/parser.rs  —  Pratt parser consuming Vec<RawToken> from ASM lexer

use crate::compiler::ffi::{RawToken, read_symbol, tok::*};
use crate::compiler::ast::{Node, BinOp, UnOp};

// ---- error ----
#[derive(Debug, Clone)]
pub struct ParseError { pub msg: String, pub pos: usize }
impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "parse error at token {}: {}", self.pos, self.msg)
    }
}
type PR<T> = Result<T, ParseError>;

// ---- priority levels ----
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
        OP_ASSIGN                            => PREC_ASSIGN,
        OP_OR                                => PREC_OR,
        OP_AND                               => PREC_AND,
        OP_EQ | OP_NEQ                       => PREC_EQUAL,
        OP_LT | OP_GT | OP_LE | OP_GE       => PREC_COMPARE,
        OP_ADD | OP_SUB                      => PREC_ADD,
        OP_MUL | OP_DIV | OP_MOD            => PREC_MUL,
        SYM_DOT | SYM_LPAREN                 => PREC_CALL,
        _                                    => PREC_NONE,
    }
}

// ---- cursor ----
struct P<'a> {
    toks: &'a [RawToken],
    sym:  &'a [u8],
    pos:  usize,
}
impl<'a> P<'a> {
    fn new(toks: &'a [RawToken], sym: &'a [u8]) -> Self { Self { toks, sym, pos: 0 } }
    fn id(&self)   -> u64 { self.toks.get(self.pos).map(|t| t.id).unwrap_or(0) }
    fn val(&self)  -> u64 { self.toks.get(self.pos).map(|t| t.value).unwrap_or(0) }
    fn id2(&self)  -> u64 { self.toks.get(self.pos+1).map(|t| t.id).unwrap_or(0) }
    fn eof(&self)  -> bool { self.pos >= self.toks.len() }
    fn adv(&mut self) { if !self.eof() { self.pos += 1; } }
    fn eat(&mut self, id: u64) -> bool {
        if self.id() == id { self.adv(); true } else { false }
    }
    fn expect(&mut self, id: u64, what: &str) -> PR<()> {
        if self.id() == id { self.adv(); Ok(()) }
        else { Err(ParseError { msg: format!("expected {}, got id={}", what, self.id()), pos: self.pos }) }
    }
    fn sym_str(&self, addr: u64) -> String { read_symbol(self.sym, addr).to_owned() }
    fn err(&self, msg: impl Into<String>) -> ParseError { ParseError { msg: msg.into(), pos: self.pos } }

    // skip a balanced pair like { } or ( )
    fn skip_balanced(&mut self, open: u64, close: u64) {
        if self.id() == open { self.adv(); } else { return; }
        let mut d = 1;
        while !self.eof() && d > 0 {
            let t = self.id(); self.adv();
            if t == open  { d += 1; }
            if t == close { d -= 1; }
        }
    }

    // ===== program =====
    fn program(&mut self) -> PR<Vec<Node>> {
        let mut items = Vec::new();
        while !self.eof() {
            self.eat(KW_PUB);
            match self.id() {
                KW_FN     => items.push(self.function()?),
                KW_STRUCT => { self.adv(); self.skip_balanced(SYM_LBRACE, SYM_RBRACE); }
                0         => break,
                _         => { self.adv(); }
            }
        }
        Ok(items)
    }

    // ===== fn name(lifetime?, params*) -> T? { body } =====
    fn function(&mut self) -> PR<Node> {
        self.expect(KW_FN, "fn")?;
        if self.id() != T_IDENTIFIER {
            return Err(self.err(format!("expected function name, got id={}", self.id())));
        }
        let name = self.sym_str(self.val()); self.adv();
        self.expect(SYM_LPAREN, "(")?;

        let mut lifetime = 0u64;
        let mut params   = Vec::new();

        // optional lifetime (first integer literal)
        if self.id() == L_INT {
            lifetime = self.val(); self.adv();
            self.eat(SYM_COMMA);
        }
        // named params
        while self.id() != SYM_RPAREN && !self.eof() {
            if self.id() == T_IDENTIFIER {
                params.push(self.sym_str(self.val())); self.adv();
            } else { self.adv(); }
            self.eat(SYM_COMMA);
        }
        self.expect(SYM_RPAREN, ")")?;
        if self.eat(SYM_ARROW) { self.adv(); } // skip return type
        let body = self.block()?;
        Ok(Node::Function { name, lifetime, params, body: Box::new(body) })
    }

    // ===== { stmts* } =====
    fn block(&mut self) -> PR<Node> {
        self.expect(SYM_LBRACE, "{")?;
        let mut stmts = Vec::new();
        while self.id() != SYM_RBRACE && !self.eof() {
            if let Some(s) = self.statement()? { stmts.push(s); }
        }
        self.expect(SYM_RBRACE, "}")?;
        Ok(Node::Block(stmts))
    }

    // ===== unsafe { stmts* } =====
    fn unsafe_block(&mut self) -> PR<Node> {
        self.expect(KW_UNSAFE, "unsafe")?;
        self.expect(SYM_LBRACE, "{")?;
        let mut stmts = Vec::new();
        while self.id() != SYM_RBRACE && !self.eof() {
            if let Some(s) = self.statement()? { stmts.push(s); }
        }
        self.expect(SYM_RBRACE, "}")?;
        Ok(Node::Unsafe(stmts))
    }

    // ===== statement dispatch =====
    fn statement(&mut self) -> PR<Option<Node>> {
        match self.id() {
            KW_LET    => Ok(Some(self.let_stmt()?)),
            KW_RETURN => Ok(Some(self.return_stmt()?)),
            KW_IF     => Ok(Some(self.if_stmt()?)),
            KW_WHILE  => Ok(Some(self.while_stmt()?)),
            KW_FOR    => Ok(Some(self.for_stmt()?)),
            KW_UNSAFE => Ok(Some(self.unsafe_block()?)),
            SYM_SEMI  => { self.adv(); Ok(None) }
            _         => Ok(Some(self.expr_stmt()?)),
        }
    }

    // let NAME = EXPR ;
    fn let_stmt(&mut self) -> PR<Node> {
        self.expect(KW_LET, "let")?;
        if self.id() != T_IDENTIFIER {
            return Err(self.err("expected variable name after let"));
        }
        let name = self.sym_str(self.val()); self.adv();
        self.expect(OP_ASSIGN, "=")?;
        let init = self.expr(PREC_NONE)?;
        self.eat(SYM_SEMI);
        Ok(Node::Let { name, init: Box::new(init) })
    }

    // return EXPR? ;
    fn return_stmt(&mut self) -> PR<Node> {
        self.expect(KW_RETURN, "return")?;
        if self.id() == SYM_SEMI || self.id() == SYM_RBRACE {
            self.eat(SYM_SEMI);
            return Ok(Node::Return(None));
        }
        let e = self.expr(PREC_NONE)?;
        self.eat(SYM_SEMI);
        Ok(Node::Return(Some(Box::new(e))))
    }

    // if EXPR BLOCK (else (if | BLOCK))?
    fn if_stmt(&mut self) -> PR<Node> {
        self.expect(KW_IF, "if")?;
        let cond    = self.expr(PREC_NONE)?;
        let then_br = self.block()?;
        let else_br = if self.eat(KW_ELSE) {
            if self.id() == KW_IF { Some(Box::new(self.if_stmt()?)) }
            else                  { Some(Box::new(self.block()?))   }
        } else { None };
        Ok(Node::If { cond: Box::new(cond), then_br: Box::new(then_br), else_br })
    }

    // while EXPR BLOCK
    fn while_stmt(&mut self) -> PR<Node> {
        self.expect(KW_WHILE, "while")?;
        let cond = self.expr(PREC_NONE)?;
        let body = self.block()?;
        Ok(Node::While { cond: Box::new(cond), body: Box::new(body) })
    }

    // for NAME in EXPR BLOCK  (simplified — maps to while)
    fn for_stmt(&mut self) -> PR<Node> {
        self.expect(KW_FOR, "for")?;
        let name = if self.id() == T_IDENTIFIER { let n = self.sym_str(self.val()); self.adv(); n } else { "_".into() };
        if self.id() == T_IDENTIFIER { self.adv(); } // skip "in"
        let iter = self.expr(PREC_NONE)?;
        let body = self.block()?;
        Ok(Node::While {
            cond: Box::new(Node::Bool(true)),
            body: Box::new(Node::Block(vec![
                Node::Let { name, init: Box::new(iter) },
                body,
            ])),
        })
    }

    // EXPR ;
    fn expr_stmt(&mut self) -> PR<Node> {
        let e = self.expr(PREC_NONE)?;
        self.eat(SYM_SEMI);
        Ok(e)
    }

    // ===== Pratt expression parser =====
    fn expr(&mut self, min_prec: u8) -> PR<Node> {
        let mut left = self.prefix()?;
        loop {
            let prec = infix_prec(self.id());
            if prec <= min_prec { break; }
            let op_id = self.id(); self.adv();

            // postfix dot chain
            if op_id == SYM_DOT {
                left = self.dot_rhs(left)?;
                continue;
            }
            // right-assoc assign, else left-assoc
            let rp = if op_id == OP_ASSIGN { PREC_NONE } else { prec };
            let right = self.expr(rp)?;
            if let Some(op) = BinOp::from_tok(op_id) {
                left = Node::BinOp { op, left: Box::new(left), right: Box::new(right) };
            }
        }
        Ok(left)
    }

    fn prefix(&mut self) -> PR<Node> {
        let id = self.id(); let val = self.val();
        match id {
            L_INT => { self.adv(); Ok(Node::Int(val as i64)) }
            L_TRUE  => { self.adv(); Ok(Node::Bool(true))  }
            L_FALSE => { self.adv(); Ok(Node::Bool(false)) }
            T_IDENTIFIER => {
                let name = self.sym_str(val); self.adv();
                if self.id() == SYM_LPAREN {
                    self.adv();
                    let args = self.arg_list()?;
                    self.expect(SYM_RPAREN, ")")?;
                    Ok(Node::Call { name, args })
                } else {
                    Ok(Node::Ident(name))
                }
            }
            SYM_LPAREN => {
                self.adv();
                let e = self.expr(PREC_NONE)?;
                self.expect(SYM_RPAREN, ")")?;
                Ok(e)
            }
            OP_SUB => {
                self.adv();
                let op = self.expr(PREC_UNARY)?;
                Ok(Node::UnOp { op: UnOp::Neg, operand: Box::new(op) })
            }
            OP_NOT => {
                self.adv();
                let op = self.expr(PREC_UNARY)?;
                Ok(Node::UnOp { op: UnOp::Not, operand: Box::new(op) })
            }
            SYM_LBRACE => self.block(),
            KW_UNSAFE  => self.unsafe_block(),
            _ => {
                self.adv();
                Ok(Node::Error(format!("unexpected token id={}", id)))
            }
        }
    }

    fn dot_rhs(&mut self, left: Node) -> PR<Node> {
        if self.id() != T_IDENTIFIER { return Err(self.err("expected identifier after '.'")); }
        let name = self.sym_str(self.val()); self.adv();
        let right = if self.id() == SYM_LPAREN {
            self.adv();
            let args = self.arg_list()?;
            self.expect(SYM_RPAREN, ")")?;
            Node::Call { name, args }
        } else { Node::Ident(name) };
        Ok(Node::Chain { left: Box::new(left), right: Box::new(right) })
    }

    fn arg_list(&mut self) -> PR<Vec<Node>> {
        let mut args = Vec::new();
        while self.id() != SYM_RPAREN && !self.eof() {
            args.push(self.expr(PREC_ASSIGN)?);
            if !self.eat(SYM_COMMA) { break; }
        }
        Ok(args)
    }
}

// ---- public API ----
pub fn parse(tokens: &[RawToken], sym_table: &[u8]) -> Result<Vec<Node>, ParseError> {
    P::new(tokens, sym_table).program()
}
