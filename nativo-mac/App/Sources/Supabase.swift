import Foundation
import Security

struct Sessao: Codable {
    var access_token: String
    var refresh_token: String
    var expira_em: Date
    var email: String
    var userId: String
}

enum ErroApp: LocalizedError {
    case msg(String)
    var errorDescription: String? { if case .msg(let m) = self { return m }; return nil }
}

/// Guarda o login no Chaveiro do Mac (criptografado pelo próprio macOS), nunca em arquivo comum.
enum Chaveiro {
    static let servico = "com.igrejaunaspec.mac.sessao"
    static func salvar(_ s: Sessao) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        apagar()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico,
                                kSecAttrAccount as String: "sessao", kSecValueData as String: d,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func ler() -> Sessao? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico,
                                kSecAttrAccount as String: "sessao", kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(Sessao.self, from: d)
    }
    static func apagar() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico]
        SecItemDelete(q as CFDictionary)
    }
}

/// Conversa com o Supabase (login e tabelas), do mesmo jeito que o site.
@MainActor
final class Supabase: ObservableObject {
    static let shared = Supabase()
    @Published var sessao: Sessao? = Chaveiro.ler()

    private func pedir(_ url: URL, metodo: String, corpo: Data?, token: String?, prefer: String?) async throws -> (Data, Int) {
        var r = URLRequest(url: url)
        r.httpMethod = metodo
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        r.httpBody = corpo
        r.timeoutInterval = 20
        let (d, resp) = try await URLSession.shared.data(for: r)
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func lerSessao(_ d: Data) throws -> Sessao {
        guard let j = try? JSONDecoder().decode(JSON.self, from: d),
              let at = j["access_token"]?.string, let rt = j["refresh_token"]?.string else {
            throw ErroApp.msg("Resposta inesperada do login.")
        }
        let exp = j["expires_in"]?.number ?? 3600
        return Sessao(access_token: at, refresh_token: rt, expira_em: Date().addingTimeInterval(exp - 60),
                      email: j["user"]?["email"]?.string ?? "", userId: j["user"]?["id"]?.string ?? "")
    }

    func entrar(email: String, senha: String) async throws {
        let url = Config.supabaseURL.appendingPathComponent("auth/v1/token").appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        let corpo = try JSONEncoder().encode(["email": email, "password": senha])
        let (d, st) = try await pedir(url, metodo: "POST", corpo: corpo, token: nil, prefer: nil)
        guard st == 200 else { throw ErroApp.msg("E-mail ou senha incorretos.") }
        let s = try lerSessao(d)
        sessao = s; Chaveiro.salvar(s)
    }

    func sair() { sessao = nil; Chaveiro.apagar() }

    private func tokenValido() async throws -> String {
        guard var s = sessao else { throw ErroApp.msg("Entre de novo.") }
        if Date() >= s.expira_em {
            let url = Config.supabaseURL.appendingPathComponent("auth/v1/token").appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
            let (d, st) = try await pedir(url, metodo: "POST", corpo: try JSONEncoder().encode(["refresh_token": s.refresh_token]), token: nil, prefer: nil)
            guard st == 200 else { sair(); throw ErroApp.msg("Sua sessão expirou. Entre de novo.") }
            s = try lerSessao(d); sessao = s; Chaveiro.salvar(s)
        }
        return s.access_token
    }

    /// Chamada às tabelas (mesmo formato do `api()` do site).
    @discardableResult
    func api(_ caminho: String, metodo: String = "GET", corpo: JSON? = nil, prefer: String = "return=representation") async throws -> JSON {
        let token = try await tokenValido()
        guard let url = URL(string: Config.supabaseURL.absoluteString + "/rest/v1/" + caminho) else { throw ErroApp.msg("Endereço inválido.") }
        let dados = try corpo.map { try JSONEncoder().encode($0) }
        let (d, st) = try await pedir(url, metodo: metodo, corpo: dados, token: token, prefer: prefer)
        if !(200..<300).contains(st) {
            let j = try? JSONDecoder().decode(JSON.self, from: d)
            let det = j?["message"]?.string ?? j?["hint"]?.string ?? ""
            if st == 401 || st == 403 { throw ErroApp.msg("Você não tem permissão para isso. " + det) }
            throw ErroApp.msg(det.isEmpty ? "Erro \(st) ao falar com o banco." : det)
        }
        if d.isEmpty { return .null }
        return (try? JSONDecoder().decode(JSON.self, from: d)) ?? .null
    }
}

extension String {
    var urlq: String { addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self }
}
