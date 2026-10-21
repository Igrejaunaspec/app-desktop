// Programa de computador do APP IGREJA UNASP EC.
// Ele só abre o site oficial numa janela própria: não guarda senhas,
// chaves nem dados dentro do programa. Tudo continua protegido pelo servidor.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("erro ao abrir o programa");
}
