import SwiftUI

struct ListaRoteirosView: View {
    let culto: String
    @State private var roteiros: [Roteiro] = []
    @State private var pastas: [Pasta] = []
    @State private var aba = UserDefaults.standard.string(forKey: "abaRoteiros") ?? "culto"
    @State private var carregando = true
    @State private var erro: String?
    @State private var abertos: Set<String> = []
    @State private var editando: Roteiro?
    @State private var novaPastaNome = ""
    @State private var criandoPasta = false

    static let abas: [(v: String, n: String, i: String)] = [("culto", "Culto de Sábado", "building.columns"), ("eventos", "Eventos", "calendar"), ("ja", "JA", "flame")]
    var comAbas: Bool { culto == "sabado" }

    var body: some View {
        Group {
            if let r = editando {
                EditorRoteiroView(roteiro: r) { editando = nil; Task { await carregar() } }
            } else { lista }
        }
    }

    var lista: some View {
        VStack(alignment: .leading, spacing: 0) {
            if comAbas {
                Picker("", selection: $aba) {
                    ForEach(Self.abas, id: \.v) { a in Label(a.n, systemImage: a.i).tag(a.v) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                .padding([.horizontal, .top], 16)
                .onChange(of: aba) { v in UserDefaults.standard.set(v, forKey: "abaRoteiros") }
            }
            if carregando { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let erro { Text(erro).foregroundStyle(.red).padding() }
            else {
                List {
                    ForEach(raizes) { p in pastaView(p, nivel: 0) }
                    let soltos = roteiros.filter { r in r.pastaId == nil || !pastas.contains { $0.id == r.pastaId } }
                    if !comAbas || aba == "culto" {
                        if !soltos.isEmpty {
                            Section(pastas.isEmpty ? "" : "Sem pasta") { ForEach(soltos) { linha($0) } }
                        }
                    }
                    if raizes.isEmpty && (comAbas && aba != "culto" || soltos.isEmpty) {
                        Text("Nada aqui ainda. Crie com “Nova pasta” ou “Novo roteiro”.").foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }
        }
        .navigationTitle(culto == "sabado" ? "Roteiros" : "Culto de Sexta")
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await carregar() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                Button { criandoPasta = true } label: { Label("Nova pasta", systemImage: "folder.badge.plus") }
                Button { Task { await novoRoteiro() } } label: { Label("Novo roteiro", systemImage: "plus") }.keyboardShortcut("n")
            }
        }
        .alert("Nova pasta", isPresented: $criandoPasta) {
            TextField("Nome da pasta", text: $novaPastaNome)
            Button("Criar") { Task { await criarPasta() } }
            Button("Cancelar", role: .cancel) { novaPastaNome = "" }
        }
        .task { await carregar() }
    }

    var raizes: [Pasta] {
        pastas.filter { p in p.paiId == nil || !pastas.contains { $0.id == p.paiId } }
            .filter { !comAbas || $0.aba == aba }
            .sorted { $0.nome.localizedCompare($1.nome) == .orderedAscending }
    }

    func total(_ p: Pasta) -> Int {
        roteiros.filter { $0.pastaId == p.id }.count + pastas.filter { $0.paiId == p.id }.reduce(0) { $0 + total($1) }
    }

    func pastaView(_ p: Pasta, nivel: Int) -> AnyView {
        let subs = pastas.filter { $0.paiId == p.id }.sorted { $0.nome.localizedCompare($1.nome) == .orderedAscending }
        let itens = roteiros.filter { $0.pastaId == p.id }
        let binding = Binding(get: { abertos.contains(p.id) }, set: { if $0 { abertos.insert(p.id) } else { abertos.remove(p.id) } })
        return AnyView(DisclosureGroup(isExpanded: binding) {
            if nivel < 20 { ForEach(subs) { pastaView($0, nivel: nivel + 1) } }
            ForEach(itens) { linha($0) }
        } label: {
            HStack {
                Label(p.nome, systemImage: binding.wrappedValue ? "folder.fill" : "folder").font(.headline)
                Spacer()
                Text("\(total(p)) \(total(p) == 1 ? "roteiro" : "roteiros")").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { ids, _ in Task { await mover(ids, para: p.id) }; return true }
            .contextMenu {
                if comAbas && nivel == 0 {
                    Menu("Mover para a aba") {
                        ForEach(Self.abas, id: \.v) { a in Button(a.n) { Task { await moverPastaAba(p, a.v) } } }
                    }
                }
            }
        })
    }

    func linha(_ r: Roteiro) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.nome).font(.body.weight(.semibold))
                Text("\(r.qtdItens) \(r.qtdItens == 1 ? "item" : "itens") · atualizado \(r.atualizadoEm)\(r.atualizadoPor.isEmpty ? "" : " por " + r.atualizadoPor)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir") { editando = r }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editando = r }
        .draggable(r.id)
    }

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

    func mover(_ ids: [String], para pasta: String) async {
        for id in ids {
            _ = try? await Supabase.shared.api("roteiros?id=eq.\(id.urlq)", metodo: "PATCH", corpo: .object(["pasta_id": .string(pasta)]), prefer: "return=minimal")
        }
        abertos.insert(pasta)
        await carregar()
    }

    func moverPastaAba(_ p: Pasta, _ nova: String) async {
        _ = try? await Supabase.shared.api("pastas?id=eq.\(p.id.urlq)", metodo: "PATCH", corpo: .object(["aba": .string(nova)]), prefer: "return=minimal")
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

    func novoRoteiro() async {
        let corpo: JSON = .object(["culto": .string(culto), "nome": .string("Novo roteiro"), "publicado": .bool(true),
                                   "dados": .object(["title": .string("Novo roteiro"), "rows": .array([Editor.linhaVazia()])])])
        do {
            let r = try await Supabase.shared.api("roteiros", metodo: "POST", corpo: corpo)
            if let o = r.array?.first?.object { editando = Roteiro(dados: o) }
        } catch { erro = error.localizedDescription }
    }
}
