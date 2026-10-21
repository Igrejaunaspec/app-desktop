import SwiftUI

struct EditorRoteiroView: View {
    @StateObject private var ed: Editor
    let voltar: () -> Void
    let colunas: [Coluna]
    @FocusState private var focado: String?

    init(roteiro: Roteiro, voltar: @escaping () -> Void) {
        _ed = StateObject(wrappedValue: Editor(roteiro))
        self.voltar = voltar
        colunas = Colunas.de(roteiro.culto)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Nome do roteiro", text: Binding(get: { ed.nome }, set: { ed.renomear($0) }))
                    .textFieldStyle(.plain).font(.title2.bold())
                Spacer()
                Text(ed.status).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            cabecalho
            List {
                ForEach(Array(ed.linhas.enumerated()), id: \.element["_id"]) { i, _ in linha(i) }
                    .onMove { ed.mover($0, $1) }
            }
            .listStyle(.plain)
        }
        .navigationTitle(ed.nome)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { ed.fechar(); voltar() } label: { Label("Voltar", systemImage: "chevron.left") }
            }
            ToolbarItemGroup {
                Button { ed.desfazer() } label: { Label("Desfazer", systemImage: "arrow.uturn.backward") }.keyboardShortcut("z")
                Button { ed.refazer() } label: { Label("Refazer", systemImage: "arrow.uturn.forward") }.keyboardShortcut("z", modifiers: [.command, .shift])
                Button { ed.adicionarLinha(depois: nil) } label: { Label("Adicionar linha", systemImage: "plus") }.keyboardShortcut(.return, modifiers: .command)
                Button { Task { await ed.salvar() } } label: { Label("Salvar", systemImage: "square.and.arrow.down") }.keyboardShortcut("s")
            }
        }
        .onDisappear { ed.fechar() }
    }

    var cabecalho: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 14)
            ForEach(colunas, id: \.k) { c in
                Text(c.t).font(.caption.bold()).foregroundStyle(.secondary)
                    .frame(width: c.largura, alignment: .leading).frame(maxWidth: c.largura == nil ? .infinity : nil, alignment: .leading)
            }
            Color.clear.frame(width: 50)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
        .background(.bar)
    }

    func linha(_ i: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).frame(width: 14).padding(.top, 5)
            ForEach(colunas, id: \.k) { c in
                let chave = "\(i)-\(c.k)"
                TextField("", text: Binding(get: { ed.valor(i, c.k) }, set: { ed.mudar(i, c.k, $0) }), axis: c.area ? .vertical : .horizontal)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(c.area ? 1...12 : 1...1)
                    .focused($focado, equals: chave)
                    .onKeyPress(.upArrow) { pular(i, c.k, -1) }
                    .onKeyPress(.downArrow) { pular(i, c.k, 1) }
                    .frame(width: c.largura).frame(maxWidth: c.largura == nil ? .infinity : nil)
            }
            HStack(spacing: 2) {
                Button { ed.adicionarLinha(depois: i) } label: { Image(systemName: "plus") }.help("Inserir linha abaixo")
                Button { ed.remover(i) } label: { Image(systemName: "xmark") }.help("Remover (Cmd+Z volta)")
            }
            .buttonStyle(.borderless).frame(width: 50)
        }
        .padding(.vertical, 2)
    }

    /// setas ↑ ↓ pulam para a mesma coluna da linha de cima/baixo
    func pular(_ i: Int, _ k: String, _ d: Int) -> KeyPress.Result {
        let alvo = i + d
        guard alvo >= 0, alvo < ed.linhas.count else { return .ignored }
        if colunas.first(where: { $0.k == k })?.area == true {
            let v = ed.valor(i, k)
            if v.contains("\n") { return .ignored } // texto com várias linhas: deixa a seta andar dentro do texto
        }
        focado = "\(alvo)-\(k)"
        return .handled
    }
}
