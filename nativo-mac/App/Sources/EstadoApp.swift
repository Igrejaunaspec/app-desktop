import Foundation
import SwiftUI

enum Secao: String, Hashable, CaseIterable {
    case sexta, sabado, homiletico, escala, calendario, agendamentos, pastoral, minhaagenda, youtube, pessoas
    var nome: String {
        switch self {
        case .sexta: "Culto de Sexta"; case .sabado: "Roteiros"; case .homiletico: "Homilético"; case .escala: "Escala"
        case .calendario: "Calendário"; case .agendamentos: "Agendamentos"; case .pastoral: "Agenda Pastoral"
        case .minhaagenda: "Minha agenda"; case .youtube: "YouTube"; case .pessoas: "Pessoas"
        }
    }
    var icone: String {
        switch self {
        case .sexta, .sabado: "book"; case .homiletico: "mic"; case .escala: "list.clipboard"
        case .calendario: "calendar"; case .agendamentos: "doc.text"; case .pastoral: "calendar.badge.clock"
        case .minhaagenda: "person.crop.circle"; case .youtube: "play.rectangle"; case .pessoas: "person.2"
        }
    }
    var grupo: String {
        switch self {
        case .sexta, .sabado, .homiletico, .escala: "Culto"
        case .calendario, .agendamentos, .pastoral, .minhaagenda: "Agenda da igreja"
        case .youtube, .pessoas: "Administração"
        }
    }
    /// Seções já feitas em versão nativa; as outras abrem o site dentro do app por enquanto.
    var nativa: Bool { self == .sexta || self == .sabado }
}

@MainActor
final class EstadoApp: ObservableObject {
    @Published var perfil: Perfil?
    @Published var erro: String?

    func carregarPerfil() async {
        guard let id = Supabase.shared.sessao?.userId else { return }
        do {
            let j = try await Supabase.shared.api("perfis?id=eq.\(id)&select=*")
            if let o = j.array?.first?.object { perfil = Perfil(dados: o) }
        } catch { erro = error.localizedDescription }
    }

    func pode(_ s: Secao) -> Bool {
        guard let p = perfil else { return false }
        switch s {
        case .sexta: return p.tem("acesso_sexta")
        case .sabado: return p.tem("acesso_sabado")
        case .homiletico: return p.tem("acesso_homiletico")
        case .escala: return p.tem("acesso_escala")
        case .calendario: return p.tem("acesso_calendario") || p.tem("acesso_calendario_ver")
        case .agendamentos: return p.tem("acesso_agendamentos")
        case .pastoral: return p.tem("acesso_pastoral") || p.tem("acesso_pastoral_secretaria")
        case .minhaagenda: return p.tem("acesso_agenda_pessoal")
        case .youtube: return p.tem("acesso_youtube")
        case .pessoas: return p.admin
        }
    }
}
