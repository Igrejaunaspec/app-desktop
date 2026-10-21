import Foundation

/// Endereço e chave PÚBLICA do banco (a mesma que o site usa).
/// Essa chave não dá acesso a nada sozinha: quem decide o que cada pessoa vê
/// são as regras de segurança (RLS) do banco, depois do login.
enum Config {
    static let supabaseURL = URL(string: "https://sxzvdnwytbdhycwzbxji.supabase.co")!
    static let supabaseKey = "sb_publishable_6rOzgGXVgobnNb-sy4rx9A_SGjR3v0r"
    static let site = URL(string: "https://igrejaunaspec.com/")!
}
