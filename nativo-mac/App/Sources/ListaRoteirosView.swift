import SwiftUI

struct ListaRoteirosView: View {
    let culto: String
    @State private var roteiros: [Roteiro] = []
    @State private var pastas: [Pasta] = []
    @State private var aba = UserDefaults.standard.string(forKey: "abaRoteiros") ?? "culto"
    @State private var carregando = true
    @State private var erro: String?
    @State private var abertos: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "pastasAbertas") ?? [])
    @State private var editando: Roteiro?
    @State private var novaPastaNome = ""
    @State private var criandoPasta = false
    @State private var busca = ""
    @State private var alvoSoltar: String?

    static let abas: [(v: String, n: String, i: String)] = [("culto", "Culto de Sábado", "building.columns"), ("eventos", "Eventos", "calendar"), ("ja", "JA", "flame")]
    var comAbas: Bool { culto == "sabado" }
    var titulo: String { culto == "sabado" ? "Roteiros" : "Culto de Sexta" }

    var body: some View {
        if let r = editando {
            EditorRoteiroView(roteiro: r) { editando = nil; Task { await carregar() } }
        } else { lista }
    }

    // MARK: tela
    var lista: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cabecalho
                if comAbas { seletorAbas }
                if carregando { ProgressView().frame(maxWidth: .infinity).padding(40) }
                else if let erro { Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                else if !busca.isEmpty { resultadosBusca }
                else { conteudo }
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(titulo)
        .searchable(text: $busca, placement: .toolbar, prompt: "Buscar roteiro")
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await carregar() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }.help("Atualizar")
                Button { criandoPasta = true } label: { Label("Nova pasta", systemImage: "folder.badge.plus") }.help("Nova pasta")
                Button { Task { await novoRoteiro() } } label: { Label("Novo roteiro", systemImage: "square.and.pencil") }
                    .help("Novo roteiro (Cmd+N)").keyboardShortcut("n")
            }
        }
        .alert("Nova pasta", isPresented: $criandoPasta) {
            TextField("Nome da pasta", text: $novaPastaNome)
            Button("Criar") { Task { await criarPasta() } }
            Button("Cancelar", role: .cancel) { novaPastaNome = "" }
        }
        .task { await carregar() }
    }

    var cabecalho: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).font(.largeTitle.bold())
                Text("\(roteiros.count) roteiros · \(pastas.count) pastas · disponíveis para o programa do culto")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await novoRoteiro() } } label: { Label("Novo roteiro", systemImage: "plus") }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    var seletorAbas: some View {
        HStack(spacing: 6) {
            ForEach(Self.abas, id: \.v) { a in
                let on = aba == a.v
                Button { withAnimation(.easeOut(duration: 0.15)) { aba = a.v }; UserDefaults.standard.set(a.v, forKey: "abaRoteiros") } label: {
                    HStack(spacing: 6) {
                        Image(systemName: a.i)
                        Text(a.n)
                        Text("\(raizes(a.v).count)").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(on ? Color.white.opacity(0.25) : Color.primary.opacity(0.08)))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(Capsule().fill(on ? Tema.azul : Color.primary.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(alvoSoltar == "aba-" + a.v ? Tema.dourado : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, id.hasPrefix("pasta:") else { return false }
                    Task { await moverPastaAba(String(id.dropFirst(6)), a.v) }; return true
                } isTargeted: { alvoSoltar = $0 ? "aba-" + a.v : (alvoSoltar == "aba-" + a.v ? nil : alvoSoltar) }
            }
        }
    }

    @ViewBuilder var conteudo: some View {
        let rz = raizes(aba)
        let soltos = roteiros.filter { r in r.pastaId == nil || !pastas.contains { $0.id == r.pastaId } }
        let mostraSoltos = (!comAbas || aba == "culto") && !soltos.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rz) { pastaView($0, nivel: 0) }
        }
        if mostraSoltos {
            VStack(alignment: .leading, spacing: 8) {
                if !rz.isEmpty { Text("SEM PASTA").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 6) }
                ForEach(soltos) { linha($0) }
            }
        }
        if rz.isEmpty && !mostraSoltos {
            VStack(spacing: 10) {
                Image(systemName: "folder").font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("Nada nesta aba ainda").font(.headline)
                Text("Crie uma pasta, ou arraste uma pasta de outra aba até o nome desta aba.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(50)
        }
    }

    var resultadosBusca: some View {
        let t = busca.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let achados = roteiros.filter { $0.nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(t) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(achados.count) resultado(s)").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(achados) { linha($0, mostrarPasta: true) }
        }
    }

    // MARK: pastas e roteiros
    func raizes(_ a: String) -> [Pasta] {
        pastas.filter { p in p.paiId == nil || !pastas.contains { $0.id == p.paiId } }
            .filter { !comAbas || $0.aba == a }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    func total(_ p: Pasta) -> Int {
        roteiros.filter { $0.pastaId == p.id }.count + pastas.filter { $0.paiId == p.id }.reduce(0) { $0 + total($1) }
    }

    func pastaView(_ p: Pasta, nivel: Int) -> AnyView {
        let subs = pastas.filter { $0.paiId == p.id }.sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
        let itens = roteiros.filter { $0.pastaId == p.id }
        let aberta = abertos.contains(p.id)
        let n = total(p)
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            Cartao(destaque: alvoSoltar == p.id) {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(aberta ? 90 : 0))
                    Image(systemName: aberta ? "folder.fill" : "folder.fill").font(.title2)
                        .foregroundStyle(nivel == 0 ? Tema.dourado : Tema.azulClaro)
                    Text(p.nome).font(.headline)
                    Spacer()
                    Text("\(n) \(n == 1 ? "roteiro" : "roteiros")").font(.callout).foregroundStyle(.secondary)
                }
            }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.18)) { if aberta { abertos.remove(p.id) } else { abertos.insert(p.id) } }
                UserDefaults.standard.set(Array(abertos), forKey: "pastasAbertas")
            }
            .draggable("pasta:" + p.id)
            .dropDestination(for: String.self) { ids, _ in
                let rs = ids.filter { !$0.hasPrefix("pasta:") }
                guard !rs.isEmpty else { return false }
                Task { await mover(rs, para: p.id) }; return true
            } isTargeted: { alvoSoltar = $0 ? p.id : (alvoSoltar == p.id ? nil : alvoSoltar) }
            .contextMenu {
                if comAbas && nivel == 0 {
                    Menu("Mover para a aba") {
                        ForEach(Self.abas, id: \.v) { a in Button(a.n) { Task { await moverPastaAba(p.id, a.v) } } }
                    }
                }
            }
            if aberta {
                VStack(alignment: .leading, spacing: 8) {
                    if nivel < 20 { ForEach(subs) { pastaView($0, nivel: nivel + 1) } }
                    ForEach(itens) { linha($0) }
                    if subs.isEmpty && itens.isEmpty {
                        Text("Pasta vazia — arraste um roteiro até ela.").font(.callout).foregroundStyle(.secondary).padding(.leading, 6)
                    }
                }
                .padding(.leading, 22)
                .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 2).padding(.leading, 8) }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        })
    }

    func linha(_ r: Roteiro, mostrarPasta: Bool = false) -> some View {
        Cartao {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill").font(.title3).foregroundStyle(Tema.destaque.opacity(0.8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.nome).font(.body.weight(.semibold))
                    HStack(spacing: 6) {
                        Text("\(r.qtdItens) \(r.qtdItens == 1 ? "item" : "itens")")
                        Text("·")
                        Text("atualizado \(r.atualizadoEm)")
                        if !r.atualizadoPor.isEmpty { Text("por \(r.atualizadoPor)").lineLimit(1) }
                        if mostrarPasta, let pid = r.pastaId, let p = pastas.first(where: { $0.id == pid }) {
                            Label(p.nome, systemImage: "folder").labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .onTapGesture { editando = r }
        .draggable(r.id)
        .contextMenu {
            Button("Abrir") { editando = r }
            Button("Duplicar") { Task { await duplicar(r) } }
            if r.pastaId != nil { Button("Tirar da pasta") { Task { await mover([r.id], para: nil) } } }
        }
    }

    // MARK: banco
    func carregar() async {
        do {
            async let a = Supabase.shared.api("roteiros?culto=eq.\(culto)&select=*&order=atualizado_em.desc")
            async let b = Supabase.shared.api("pastas?culto=eq.\(culto)&select=*&order=criado_em.asc")
            let (ra, pb) = try await (a, b)
            roteiros = (ra.array ?? []).compactMap { $0.object.map(Roteiro.init) }
            pastas = (pb.array ?? []).compactMap { $0.object.map(Pasta.init) }
            erro = nil
        } catch { erro = error.localizedDescription }
        carregando = false
    }

    func mover(_ ids: [String], para pasta: String?) async {
        for id in ids {
            _ = try? await Supabase.shared.api("roteiros?id=eq.\(id.urlq)", metodo: "PATCH", corpo: .object(["pasta_id": pasta.map { .string($0) } ?? .null]), prefer: "return=minimal")
        }
        if let pasta { abertos.insert(pasta) }
        await carregar()
    }

    func moverPastaAba(_ id: String, _ nova: String) async {
        _ = try? await Supabase.shared.api("pastas?id=eq.\(id.urlq)", metodo: "PATCH", corpo: .object(["aba": .string(nova)]), prefer: "return=minimal")
        await carregar()
    }

    func criarPasta() async {
        let nome = novaPastaNome.trimmingCharacters(in: .whitespaces); novaPastaNome = ""
        guard !nome.isEmpty else { return }
        var corpo: [String: JSON] = ["culto": .string(culto), "nome": .string(nome)]
        if comAbas && aba != "culto" { corpo["aba"] = .string(aba) }
        do { try await Supabase.shared.api("pastas", metodo: "POST", corpo: .object(corpo)); await carregar() }
        catch { erro = error.localizedDescription }
    }

    func duplicar(_ r: Roteiro) async {
        var corpo: [String: JSON] = ["culto": .string(r.culto), "nome": .string(r.nome + " (cópia)"), "publicado": .bool(true)]
        corpo["dados"] = r.dados["dados"] ?? .object([:])
        corpo["titulo"] = r.dados["titulo"] ?? .null
        if let p = r.pastaId { corpo["pasta_id"] = .string(p) }
        do { try await Supabase.shared.api("roteiros", metodo: "POST", corpo: .object(corpo)); await carregar() }
        catch { erro = error.localizedDescription }
    }

    func novoRoteiro() async {
        let corpo: JSON = .object(["culto": .string(culto), "nome": .string("Novo roteiro"), "publicado": .bool(true),
                                   "dados": .object(["title": .string("Novo roteiro"), "rows": .array([Editor.linhaVazia()])])])
        do {
            let r = try await Supabase.shared.api("roteiros", metodo: "POST", corpo: corpo)
            if let o = r.array?.first?.object { editando = Roteiro(dados: o) }
        } catch { erro = error.localizedDescription }
    }
}
