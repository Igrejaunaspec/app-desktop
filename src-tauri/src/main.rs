// Programa de computador do APP IGREJA UNASP EC.
// Ele só abre o site oficial numa janela própria: não guarda senhas,
// chaves nem dados dentro do programa. Tudo continua protegido pelo servidor.
// Links para outros sites (ex.: Escala) abrem no navegador padrão do computador.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::webview::NewWindowResponse;
use tauri::{WebviewUrl, WebviewWindowBuilder};

// No Mac, a janela do programa não mostra sozinha as caixas "confirmar"/"aviso" do site
// (ex.: "Excluir esta coluna?"). Este script faz o site pedir essas caixas ao programa,
// que mostra a caixa nativa do Mac e devolve a resposta.
#[cfg(target_os = "macos")]
const DIALOGOS_JS: &str = r#"
(function(){
  function pedir(tipo, msg){
    try{
      var x = new XMLHttpRequest();
      x.open('POST', 'dialogo://localhost/' + tipo, false);
      x.send(String(msg == null ? '' : msg));
      return x.responseText === '1';
    }catch(e){ return true; }
  }
  window.alert = function(m){ pedir('aviso', m); };
  window.confirm = function(m){ return pedir('confirmar', m); };
  window.prompt = function(m, v){ pedir('aviso', (m || '') + (v ? '\n\n' + v : '')); return null; };
})();
"#;

const SITE: &str = "https://igrejaunaspec.com/";

// Sai do login sozinho depois de 1 hora SEM USO no programa (sem mexer mouse/teclado).
// Também vale se o programa ficou fechado mais de 1 hora: ao abrir, pede o login de novo.
// Só existe no programa; o site no navegador continua igual.
const SAIDA_AUTOMATICA_JS: &str = r#"
(function(){
  if(location.hostname.indexOf('igrejaunaspec.com') === -1) return;
  var LIMITE = 60 * 60 * 1000, CHAVE = 'roteiroEditor.sessao', USO = 'programa.ultimoUso', ultimo = 0;
  function agora(){ return Date.now(); }
  function lerUso(){ try{ return Number(localStorage.getItem(USO)) || 0; }catch(e){ return 0; } }
  function marcar(){ var t = agora(); if(t - ultimo < 5000) return; ultimo = t; try{ localStorage.setItem(USO, String(t)); }catch(e){} }
  function sair(){ try{ localStorage.removeItem(CHAVE); localStorage.setItem(USO, String(agora())); }catch(e){} location.reload(); }
  try{ if(localStorage.getItem(CHAVE) && lerUso() && agora() - lerUso() > LIMITE){ sair(); return; } }catch(e){}
  marcar();
  ['mousemove','mousedown','keydown','wheel','touchstart'].forEach(function(ev){ addEventListener(ev, marcar, { passive:true, capture:true }); });
  setInterval(function(){ try{ if(localStorage.getItem(CHAVE) && agora() - lerUso() > LIMITE) sair(); }catch(e){} }, 30000);
})();
"#;

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
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .register_uri_scheme_protocol("dialogo", |_ctx, req| {
            use rfd::{MessageButtons, MessageDialog, MessageDialogResult, MessageLevel};
            let msg = String::from_utf8_lossy(req.body()).to_string();
            let confirmar = req.uri().path().ends_with("confirmar");
            let r = MessageDialog::new()
                .set_title("Igreja UNASP EC")
                .set_description(&msg)
                .set_level(MessageLevel::Info)
                .set_buttons(if confirmar { MessageButtons::OkCancel } else { MessageButtons::Ok })
                .show();
            let ok = !confirmar || matches!(r, MessageDialogResult::Ok | MessageDialogResult::Yes);
            tauri::http::Response::builder()
                .header("Access-Control-Allow-Origin", "*")
                .header("Content-Type", "text/plain")
                .body(if ok { b"1".to_vec() } else { b"0".to_vec() })
                .unwrap()
        })
        .setup(|app| {
            let janela = WebviewWindowBuilder::new(app, "main", WebviewUrl::External(SITE.parse().unwrap()))
                .title("Igreja UNASP EC")
                // deixa o próprio site cuidar de arrastar e soltar (ex.: roteiro para dentro da pasta)
                .disable_drag_drop_handler()
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
                ;
            let janela = janela.initialization_script(SAIDA_AUTOMATICA_JS);
            #[cfg(target_os = "macos")]
            let janela = janela.initialization_script(DIALOGOS_JS);
            janela.build()?;
            // procura versão nova do programa ao abrir
            let h = app.handle().clone();
            tauri::async_runtime::spawn(async move { procurar_atualizacao(h).await; });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("erro ao abrir o programa");
}

// Atualização automática: confere no GitHub se há versão nova, pergunta e instala.
// O pacote só é aceito se tiver a assinatura da chave da igreja (protege contra versões falsas).
async fn procurar_atualizacao(app: tauri::AppHandle) {
    use tauri_plugin_updater::UpdaterExt;
    let Ok(atualizador) = app.updater() else { return };
    let Ok(Some(nova)) = atualizador.check().await else { return };
    let versao = nova.version.clone();
    let sim = rfd::AsyncMessageDialog::new()
        .set_title("Igreja UNASP EC")
        .set_description(format!("Há uma versão nova do programa ({versao}).\n\nAtualizar agora? Leva poucos segundos e o programa reabre sozinho."))
        .set_buttons(rfd::MessageButtons::YesNo)
        .show()
        .await;
    if !matches!(sim, rfd::MessageDialogResult::Yes) { return; }
    if nova.download_and_install(|_, _| {}, || {}).await.is_ok() {
        app.restart();
    } else {
        rfd::AsyncMessageDialog::new()
            .set_title("Igreja UNASP EC")
            .set_description("Não consegui atualizar agora. Tente de novo mais tarde.")
            .show()
            .await;
    }
}
