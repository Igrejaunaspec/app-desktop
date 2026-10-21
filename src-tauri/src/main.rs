// Programa de computador do APP IGREJA UNASP EC.
// Ele só abre o site oficial numa janela própria: não guarda senhas,
// chaves nem dados dentro do programa. Tudo continua protegido pelo servidor.
// Links para outros sites (ex.: Escala) abrem no navegador padrão do computador.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::webview::NewWindowResponse;
use tauri::{WebviewUrl, WebviewWindowBuilder};

const SITE: &str = "https://igrejaunaspec.com/";

// endereços que podem abrir dentro da janela do programa
fn eh_do_app(url: &tauri::Url) -> bool {
    match url.host_str() {
        Some(h) => h == "igrejaunaspec.com" || h.ends_with(".igrejaunaspec.com") || h.ends_with(".supabase.co"),
        None => matches!(url.scheme(), "about" | "blob" | "data"),
    }
}

fn abrir_no_navegador(url: &tauri::Url) {
    if matches!(url.scheme(), "http" | "https" | "mailto" | "tel") {
        let _ = tauri_plugin_opener::open_url(url.as_str(), None::<&str>);
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(SITE.parse().unwrap()))
                .title("Igreja UNASP EC")
                .inner_size(1280.0, 820.0)
                .min_inner_size(380.0, 500.0)
                .center()
                // botões que abrem nova aba/janela (window.open, target=_blank)
                .on_new_window(|url, _| {
                    abrir_no_navegador(&url);
                    NewWindowResponse::Deny
                })
                // links que tentariam trocar a página do programa por outro site
                .on_navigation(|url| {
                    if eh_do_app(url) { true } else { abrir_no_navegador(url); false }
                })
                .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("erro ao abrir o programa");
}
