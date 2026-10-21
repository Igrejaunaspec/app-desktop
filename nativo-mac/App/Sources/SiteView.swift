import SwiftUI
import WebKit

/// Seções que ainda não foram refeitas em nativo: mostra o site dentro do app.
struct SiteView: View {
    let secao: Secao
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "info.circle")
                Text("\(secao.nome) ainda abre a versão do site (a versão nativa está a caminho).")
                Spacer()
                Link("Abrir no navegador", destination: Config.site)
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            Web(url: Config.site)
        }
        .navigationTitle(secao.nome)
    }
}

struct Web: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.load(URLRequest(url: url))
        return w
    }
    func updateNSView(_ v: WKWebView, context: Context) {}
}
