import SwiftUI

@main
struct IgrejaApp: App {
    @StateObject private var supa = Supabase.shared
    @StateObject private var estado = EstadoApp()

    var body: some Scene {
        WindowGroup("Igreja UNASP EC") {
            Group {
                if supa.sessao == nil { LoginView() }
                else { PrincipalView() }
            }
            .environmentObject(estado)
            .environmentObject(supa)
            .frame(minWidth: 900, minHeight: 560)
            .tint(Tema.destaque)
        }
        .windowToolbarStyle(.unified)
    }
}

struct LoginView: View {
    @EnvironmentObject var supa: Supabase
    @State private var email = ""
    @State private var senha = ""
    @State private var erro: String?
    @State private var carregando = false

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Igreja Adventista UNASP EC").font(.title2.bold())
            Text("Entre com o mesmo e-mail e senha do site").foregroundStyle(.secondary)
            TextField("E-mail", text: $email).textContentType(.username)
            SecureField("Senha", text: $senha).textContentType(.password).onSubmit(entrar)
            if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            Button(action: entrar) {
                if carregando { ProgressView().controlSize(.small) } else { Text("Entrar").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            .disabled(email.isEmpty || senha.isEmpty || carregando)
            Link("Esqueci minha senha", destination: Config.site).font(.callout)
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func entrar() {
        carregando = true; erro = nil
        Task {
            do { try await supa.entrar(email: email.trimmingCharacters(in: .whitespaces), senha: senha) }
            catch { self.erro = error.localizedDescription }
            carregando = false
        }
    }
}

struct PrincipalView: View {
    @EnvironmentObject var estado: EstadoApp
    @EnvironmentObject var supa: Supabase
    @State private var secao: Secao? = .sabado

    var body: some View {
        NavigationSplitView {
            List(selection: $secao) {
                ForEach(["Culto", "Agenda da igreja", "Administração"], id: \.self) { g in
                    let itens = Secao.allCases.filter { $0.grupo == g && estado.pode($0) }
                    if !itens.isEmpty {
                        Section(g) {
                            ForEach(itens, id: \.self) { s in Label(s.nome, systemImage: s.icone).tag(s) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(estado.perfil?.nome.isEmpty == false ? estado.perfil!.nome : (supa.sessao?.email ?? ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Sair") { supa.sair(); estado.perfil = nil }.controlSize(.small)
                }.padding(10)
            }
        } detail: {
            if estado.perfil == nil { ProgressView("Carregando…") }
            else if let s = secao {
                if s == .sexta || s == .sabado { ListaRoteirosView(culto: s.rawValue).id(s) }
                else { SiteView(secao: s).id(s) }
            } else { Text("Escolha uma seção ao lado").foregroundStyle(.secondary) }
        }
        .task { await estado.carregarPerfil() }
        .alert("Erro", isPresented: .constant(estado.erro != nil)) { Button("OK") { estado.erro = nil } } message: { Text(estado.erro ?? "") }
    }
}
