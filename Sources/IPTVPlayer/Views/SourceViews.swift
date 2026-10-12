import SwiftUI
import UniformTypeIdentifiers

struct SourceFormView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let source: Source?

    private enum Mode: String, CaseIterable { case xtream = "Xtream Codes", m3u = "Lista M3U" }

    @State private var mode: Mode = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var m3uAddress = ""
    @State private var pickingFile = false
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source == nil ? "Adicionar fonte" : "Editar fonte").font(.title2.weight(.bold))
                Text("Os dados ficam guardados apenas neste Mac.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 24)

            Form {
                Picker("Tipo", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Section {
                    TextField("Nome", text: $name, prompt: Text(mode == .xtream ? "A minha TV" : "Lista"))
                }

                switch mode {
                case .xtream:
                    Section {
                        TextField("Servidor", text: $server, prompt: Text("http://servidor.com:8080"))
                        TextField("Utilizador", text: $username)
                        SecureField("Password", text: $password)
                    } footer: {
                        Text("Os dados fornecidos pelo teu fornecedor de IPTV.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .m3u:
                    Section {
                        HStack {
                            TextField("Endereço", text: $m3uAddress, prompt: Text("https://… ou ficheiro local"))
                            Button("Escolher…") { pickingFile = true }
                        }
                    } footer: {
                        Text("Se a lista vier de um servidor Xtream (get.php?username=…), é convertida automaticamente para ter filmes, séries e guia de programação.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                if checking {
                    ProgressView().controlSize(.small)
                    Text("A verificar…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(source == nil ? "Adicionar" : "Guardar") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || checking)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(width: 480)
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: m3uTypes) { result in
            if case .success(let url) = result {
                m3uAddress = url.absoluteString
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
            }
        }
        .onAppear(perform: fill)
    }

    private var m3uTypes: [UTType] {
        [UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8"), .plainText, .data].compactMap { $0 }
    }

    private var isValid: Bool {
        switch mode {
        case .xtream: !server.trimmed.isEmpty && !username.trimmed.isEmpty && !password.isEmpty
        case .m3u: URL(string: m3uAddress.trimmed)?.scheme != nil
        }
    }

    private func fill() {
        guard let source else { return }
        name = source.name
        switch source.kind {
        case .xtream(let s, let u, let p):
            mode = .xtream
            server = s.absoluteString
            username = u
            password = p
        case .m3u(let url):
            mode = .m3u
            m3uAddress = url.absoluteString
        }
    }

    private func save() async {
        error = nil
        var kind: SourceKind
        switch mode {
        case .xtream:
            var address = server.trimmed
            if !address.contains("://") { address = "http://" + address }
            guard let url = URL(string: address), url.host() != nil else {
                error = "O endereço do servidor não é válido."
                return
            }
            kind = .xtream(server: url, username: username.trimmed, password: password)
        case .m3u:
            guard let url = URL(string: m3uAddress.trimmed) else { return }
            kind = xtreamFromM3U(url) ?? .m3u(url: url)
        }

        if case .xtream(let server, let username, let password) = kind {
            checking = true
            defer { checking = false }
            do {
                _ = try await XtreamClient(server: server, username: username, password: password, sourceID: UUID()).accountInfo()
            } catch {
                self.error = error.localizedDescription
                return
            }
        }

        let fallbackName: String = switch kind {
        case .xtream(let server, _, _): server.host() ?? "IPTV"
        case .m3u(let url): url.isFileURL ? url.deletingPathExtension().lastPathComponent : (url.host() ?? "Lista M3U")
        }
        let finalName = name.trimmed.isEmpty ? fallbackName : name.trimmed

        if var source {
            source.name = finalName
            source.kind = kind
            library.update(source)
        } else {
            library.add(Source(name: finalName, kind: kind))
        }
        dismiss()
    }

    /// `http://host:port/get.php?username=u&password=p&type=m3u_plus` → Xtream account.
    private func xtreamFromM3U(_ url: URL) -> SourceKind? {
        guard url.lastPathComponent == "get.php",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let user = comps.queryItems?.first(where: { $0.name == "username" })?.value,
              let pass = comps.queryItems?.first(where: { $0.name == "password" })?.value else { return nil }
        var base = URLComponents()
        base.scheme = comps.scheme
        base.host = comps.host
        base.port = comps.port
        guard let server = base.url else { return nil }
        return .xtream(server: server, username: user, password: pass)
    }
}

struct ManageSourcesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Source?
    @State private var deleting: Source?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fontes").font(.title2.weight(.bold)).padding(24)
            List {
                ForEach(library.sources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: isXtream(source) ? "server.rack" : "list.bullet.rectangle")
                            .frame(width: 28)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(source.name).font(.headline)
                            Text(source.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { editing = source } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Editar")
                        Button { deleting = source } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Remover")
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button("Adicionar fonte…") {
                    dismiss()
                    library.isAddingSource = true
                }
                Spacer()
                Button("Concluído") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 520)
        .sheet(item: $editing) { SourceFormView(source: $0) }
        .confirmationDialog("Remover “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Remover", role: .destructive) {
                if let deleting { library.remove(deleting) }
            }
        }
    }

    private func isXtream(_ source: Source) -> Bool {
        if case .xtream = source.kind { return true }
        return false
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
