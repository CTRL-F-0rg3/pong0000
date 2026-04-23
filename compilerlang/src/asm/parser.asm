; parser.asm — stub (parser is implemented in Rust, see src/compiler/parser.rs)
; This file exists so build.rs can compile it without errors.
; It exports no symbols used by Rust code.
section .text
    global _asm_parser_version
_asm_parser_version:
    mov rax, 1
    ret
