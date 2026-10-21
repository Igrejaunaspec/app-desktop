import SwiftUI

/// Cores da igreja (as mesmas do site): azul-marinho e dourado.
enum Tema {
    static let azul = Color(red: 0x1D/255, green: 0x3A/255, blue: 0x5C/255)
    static let azulClaro = Color(red: 0x4A/255, green: 0x7B/255, blue: 0xB5/255)
    static let dourado = Color(red: 0xE2/255, green: 0xA3/255, blue: 0x3B/255)
    /// cor de destaque que funciona no modo claro e no escuro
    static let destaque = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x6A/255, green: 0x9B/255, blue: 0xD8/255, alpha: 1)
            : NSColor(red: 0x1D/255, green: 0x3A/255, blue: 0x5C/255, alpha: 1)
    })
}

/// Cartão com cantos arredondados, fundo leve e realce ao passar o mouse.
struct Cartao<C: View>: View {
    var destaque = false
    @ViewBuilder var conteudo: C
    @State private var sobre = false
    var body: some View {
        conteudo
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(sobre || destaque ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(destaque ? Tema.dourado : Color.primary.opacity(0.08), lineWidth: destaque ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { sobre = $0 }
            .animation(.easeOut(duration: 0.12), value: sobre)
    }
}
