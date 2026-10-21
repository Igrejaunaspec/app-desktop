import Foundation

struct Perfil {
    var dados: [String: JSON]
    var id: String { dados["id"]?.string ?? "" }
    var nome: String { dados["nome"]?.string ?? "" }
    func tem(_ campo: String) -> Bool { dados["admin"]?.bool == true || dados[campo]?.bool == true }
    var admin: Bool { dados["admin"]?.bool == true }
}

struct Pasta: Identifiable, Hashable {
    var dados: [String: JSON]
    var id: String { dados["id"]?.string ?? "" }
    var nome: String { dados["nome"]?.string ?? "" }
    var paiId: String? { dados["pasta_pai_id"]?.string }
    var aba: String { dados["aba"]?.string ?? "culto" }
}

struct Roteiro: Identifiable, Hashable {
    var dados: [String: JSON]
    var id: String { dados["id"]?.string ?? "" }
    var nome: String { dados["nome"]?.string ?? "(sem nome)" }
    var culto: String { dados["culto"]?.string ?? "sabado" }
    var pastaId: String? { dados["pasta_id"]?.string }
    var qtdItens: Int { dados["dados"]?["rows"]?.array?.count ?? 0 }
    var atualizadoEm: String {
        guard let s = dados["atualizado_em"]?.string else { return "" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return "" }
        return d.formatted(date: .numeric, time: .shortened)
    }
    var atualizadoPor: String { dados["atualizado_por"]?.string ?? "" }
}

/// Colunas de cada culto (iguais às do site).
struct Coluna: Hashable { let k: String; let t: String; let area: Bool; let largura: CGFloat? }
enum Colunas {
    static func de(_ culto: String) -> [Coluna] {
        culto == "sexta" ? [
            Coluna(k: "horario", t: "Horário", area: false, largura: 70),
            Coluna(k: "tempo", t: "Duração", area: false, largura: 80),
            Coluna(k: "momento", t: "Roteiro", area: true, largura: nil),
            Coluna(k: "obs", t: "OBS", area: true, largura: nil),
            Coluna(k: "gc", t: "GC", area: false, largura: 110),
            Coluna(k: "audio", t: "Áudio", area: false, largura: 130),
        ] : [
            Coluna(k: "horario", t: "Horário", area: false, largura: 70),
            Coluna(k: "tempo", t: "Tempo", area: false, largura: 80),
            Coluna(k: "momento", t: "Momento", area: true, largura: nil),
            Coluna(k: "participante", t: "Participante", area: true, largura: 170),
            Coluna(k: "obs", t: "Obs.", area: true, largura: nil),
        ]
    }
}
