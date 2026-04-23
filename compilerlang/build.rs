use std::path::PathBuf;
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let asm_dir  = manifest.join("src/asm");
    let out_dir  = PathBuf::from(std::env::var("OUT_DIR").unwrap());

    let asm_files = ["lexer", "parser"];
    let mut obj_files: Vec<PathBuf> = Vec::new();

    for name in &asm_files {
        let src = asm_dir.join(format!("{}.asm", name));
        let obj = out_dir.join(format!("{}.o",   name));
        println!("cargo:rerun-if-changed={}", src.display());

        let status = Command::new("nasm")
            .args([
                "-f", "elf64",
                "-g", "-F", "dwarf",
                "--reproducible",
                &src.to_string_lossy(),
                "-o", &obj.to_string_lossy(),
            ])
            .status()
            .expect("nasm not found");

        if !status.success() {
            panic!("NASM failed on {}.asm", name);
        }
        obj_files.push(obj);
    }

    let lib = out_dir.join("libcompiler_asm.a");
    let mut ar_args = vec!["crus".to_string(), lib.to_string_lossy().to_string()];
    for obj in &obj_files { ar_args.push(obj.to_string_lossy().to_string()); }

    Command::new("ar").args(&ar_args).status().expect("ar not found");

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=compiler_asm");
}
