import Foundation
import SwiftUI

/// Edição de um roteiro, compatível com a edição ao vivo do site:
/// cada célula guarda quando foi mudada (_t) e por quem (_a); linhas apagadas vão para "apagadas";
/// ao salvar, junta com o que está no banco (vale a mudança mais recente de cada célula).
@MainActor
final class Editor: ObservableObject {
    static let meuCliente = "mac" + String(UUID().uuidString.prefix(6)).lowercased()
    @Published var linhas: [[String: JSON]] = []
    @Published var nome: String
    @Published var status = ""
    @Published var foco: String?

    let id: String
    let culto: String
    private var outrosDados: [String: JSON] = [:]
    private var apagadas: Set<String> = []
    private var ordemT: Double = 0
    private var relogio: Double = 0
    private var timerSalvar: Task<Void, Never>?
    private var timerBuscar: Task<Void, Never>?
    private var sujo = false
    private var salvando = false
    private var desfazerPilha: [[[String: JSON]]] = []
    private var refazerPilha: [[[String: JSON]]] = []

    static func linhaVazia() -> JSON {
        .object(["_id": .string(novoId()), "horario": .string(""), "tempo": .string("5 min"), "momento": .string(""),
                 "participante": .string(""), "obs": .string(""), "gc": .string(""), "audio": .string(""), "color": .string("")])
    }
    static func novoId() -> String { "r" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 0..<46656), radix: 36) }

    init(_ r: Roteiro) {
        id = r.id; culto = r.culto; nome = r.nome
        aplicarDoBanco(r.dados["dados"]?.object ?? [:])
        if linhas.isEmpty { linhas = [Self.linhaVazia().object!] }
        timerBuscar = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await self?.buscarDoBanco()
            }
        }
    }
    func fechar() { timerBuscar?.cancel(); if sujo { Task { await salvar() } } }

    private func aplicarDoBanco(_ d: [String: JSON]) {
        outrosDados = d.filter { !["rows", "apagadas", "ordemT"].contains($0.key) }
        apagadas = Set(d["apagadas"]?.array?.compactMap { $0.string } ?? [])
        ordemT = d["ordemT"]?.number ?? 0
        linhas = (d["rows"]?.array ?? []).enumerated().compactMap { i, v in
            guard var o = v.object else { return nil }
            if o["_id"]?.string == nil { o["_id"] = .string("p\(i)") }
            return o
        }
    }

    private func agora() -> Double { relogio = max(Date().timeIntervalSince1970 * 1000, relogio + 1); return relogio }

    // MARK: edição
    func valor(_ i: Int, _ k: String) -> String { i < linhas.count ? (linhas[i][k]?.string ?? "") : "" }
    func mudar(_ i: Int, _ k: String, _ v: String) {
        guard i < linhas.count, valor(i, k) != v else { return }
        guardarDesfazer()
        linhas[i][k] = .string(v)
        var t = linhas[i]["_t"]?.object ?? [:]; t[k] = .number(agora()); linhas[i]["_t"] = .object(t)
        var a = linhas[i]["_a"]?.object ?? [:]; a[k] = .string(Self.meuCliente); linhas[i]["_a"] = .object(a)
        marcarSujo()
    }
    func adicionarLinha(depois i: Int?) {
        guardarDesfazer()
        let nova = Self.linhaVazia().object!
        if let i, i < linhas.count { linhas.insert(nova, at: i + 1) } else { linhas.append(nova) }
        ordemT = agora(); marcarSujo()
    }
    func remover(_ i: Int) {
        guard i < linhas.count else { return }
        guardarDesfazer()
        if let id = linhas[i]["_id"]?.string { apagadas.insert(id) }
        linhas.remove(at: i)
        if linhas.isEmpty { linhas = [Self.linhaVazia().object!] }
        ordemT = agora(); marcarSujo()
        status = "Item removido — Cmd+Z para voltar"
    }
    func mover(_ de: IndexSet, _ para: Int) {
        guardarDesfazer(); linhas.move(fromOffsets: de, toOffset: para); ordemT = agora(); marcarSujo()
    }

    private func guardarDesfazer() { desfazerPilha.append(linhas); if desfazerPilha.count > 100 { desfazerPilha.removeFirst() }; refazerPilha.removeAll() }
    func desfazer() {
        guard let ant = desfazerPilha.popLast() else { return }
        refazerPilha.append(linhas)
        voltarPara(ant)
    }
    func refazer() {
        guard let prox = refazerPilha.popLast() else { return }
        desfazerPilha.append(linhas)
        voltarPara(prox)
    }
    /// volta o estado carimbando as células como mudança nova (assim vence no salvamento)
    private func voltarPara(_ alvo: [[String: JSON]]) {
        let t = agora()
        let idsAlvo = Set(alvo.compactMap { $0["_id"]?.string })
        linhas.compactMap { $0["_id"]?.string }.filter { !idsAlvo.contains($0) }.forEach { apagadas.insert($0) }
        idsAlvo.forEach { apagadas.remove($0) }
        let atuais = Dictionary(uniqueKeysWithValues: linhas.compactMap { l in l["_id"]?.string.map { ($0, l) } })
        linhas = alvo.map { var l = $0
            if let id = l["_id"]?.string, let c = atuais[id] {
                var tt = l["_t"]?.object ?? [:]
                for (k, v) in l where !k.hasPrefix("_") && c[k] != v { tt[k] = .number(t) }
                l["_t"] = .object(tt)
            }
            return l }
        ordemT = t; marcarSujo()
    }

    private func marcarSujo() {
        sujo = true; status = "alterações não salvas…"
        timerSalvar?.cancel()
        timerSalvar = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled { await self?.salvar() }
        }
    }

    // MARK: juntar com o banco (mesma regra do site)
    private func juntar(_ remoto: [[String: JSON]], ordemRemota: Double) -> [[String: JSON]] {
        var R: [String: [String: JSON]] = [:]
        remoto.forEach { if let id = $0["_id"]?.string { R[id] = $0 } }
        let L = Set(linhas.compactMap { $0["_id"]?.string })
        var out: [[String: JSON]] = []
        for l in linhas {
            guard let id = l["_id"]?.string, !apagadas.contains(id) else { continue }
            guard let r = R[id] else { out.append(l); continue }
            var m = l
            var mt = l["_t"]?.object ?? [:], ma = l["_a"]?.object ?? [:]
            let campos = Set(l.keys).union(r.keys).filter { !$0.hasPrefix("_") }
            for k in campos {
                let tl = l["_t"]?[k]?.number ?? 0, tr = r["_t"]?[k]?.number ?? 0
                relogio = max(relogio, tr)
                if tr > tl { m[k] = r[k] ?? .string(""); mt[k] = .number(tr); if let a = r["_a"]?[k] { ma[k] = a } }
            }
            m["_t"] = .object(mt); m["_a"] = .object(ma)
            out.append(m)
        }
        for (i, r) in remoto.enumerated() {
            guard let id = r["_id"]?.string, !L.contains(id), !apagadas.contains(id) else { continue }
            var pos = 0
            if i > 0 { for j in stride(from: i - 1, through: 0, by: -1) {
                if let ant = remoto[j]["_id"]?.string, let k = out.firstIndex(where: { $0["_id"]?.string == ant }) { pos = k + 1; break } } }
            out.insert(r, at: min(pos, out.count))
        }
        if ordemRemota > ordemT {
            relogio = max(relogio, ordemRemota)
            var pos: [String: Int] = [:]; remoto.enumerated().forEach { if let id = $1["_id"]?.string { pos[id] = $0 } }
            var res = out.filter { pos[$0["_id"]?.string ?? ""] != nil }.sorted { pos[$0["_id"]!.string!]! < pos[$1["_id"]!.string!]! }
            for (i, x) in out.enumerated() where pos[x["_id"]?.string ?? ""] == nil {
                var p = 0
                if i > 0 { for j in stride(from: i - 1, through: 0, by: -1) {
                    if let k = res.firstIndex(where: { $0["_id"]?.string == out[j]["_id"]?.string }) { p = k + 1; break } } }
                res.insert(x, at: min(p, res.count))
            }
            ordemT = ordemRemota
            return res
        }
        return out
    }

    private func lerBanco() async -> [String: JSON]? {
        guard let j = try? await Supabase.shared.api("roteiros?id=eq.\(id.urlq)&select=nome,dados"), let o = j.array?.first?.object else { return nil }
        return o
    }

    private func juntarBanco(_ o: [String: JSON]) {
        let d = o["dados"]?.object ?? [:]
        (d["apagadas"]?.array ?? []).compactMap { $0.string }.forEach { apagadas.insert($0) }
        let remoto = (d["rows"]?.array ?? []).enumerated().compactMap { i, v -> [String: JSON]? in
            guard var r = v.object else { return nil }; if r["_id"]?.string == nil { r["_id"] = .string("p\(i)") }; return r }
        let juntas = juntar(remoto, ordemRemota: d["ordemT"]?.number ?? 0)
        if juntas != linhas { linhas = juntas }
        for (k, v) in d where !["rows", "apagadas", "ordemT"].contains(k) && outrosDados[k] == nil { outrosDados[k] = v }
    }

    func buscarDoBanco() async {
        guard !salvando, let o = await lerBanco() else { return }
        juntarBanco(o)
    }

    func salvar() async {
        guard !salvando else { marcarSujo(); return }
        salvando = true; status = "salvando…"
        defer { salvando = false }
        if let o = await lerBanco() { juntarBanco(o) }
        let vazias: (([String: JSON]) -> Bool) = { r in ["momento", "obs", "participante", "gc", "audio"].allSatisfy { (r[$0]?.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty } }
        var dados = outrosDados
        dados["rows"] = .array(linhas.filter { !vazias($0) }.map { .object($0) })
        dados["apagadas"] = .array(apagadas.sorted().map { .string($0) })
        dados["ordemT"] = .number(ordemT)
        dados["title"] = .string(outrosDados["title"]?.string ?? nome)
        let corpo: JSON = .object(["nome": .string(nome), "dados": .object(dados)])
        do {
            try await Supabase.shared.api("roteiros?id=eq.\(id.urlq)", metodo: "PATCH", corpo: corpo, prefer: "return=minimal")
            sujo = false
            status = "salvo às " + Date().formatted(date: .omitted, time: .shortened)
        } catch { status = "erro ao salvar: " + error.localizedDescription }
    }

    func renomear(_ n: String) { nome = n; marcarSujo() }
}
