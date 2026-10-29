import SwiftUI

// ログイン・新規登録・パスワード再設定（メールの 6 桁のコードで。アプリへのリンクは使わない）
struct AuthView: View {
    enum Mode { case login, signUp, verifySignUp, resetRequest, resetVerify, newPassword }
    let repo: Repo
    var expired = false
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var code = ""
    @State private var error: String?
    @State private var info: String?
    @State private var busy = false

    private var title: String {
        switch mode {
        case .login: "ログイン"; case .signUp: "新規登録"; case .verifySignUp: "メールの確認"
        case .resetRequest: "パスワードを忘れたとき"; case .resetVerify: "確認コードの入力"; case .newPassword: "新しいパスワード"
        }
    }
    private var buttonTitle: String {
        switch mode {
        case .login: "ログイン"; case .signUp: "登録する"; case .verifySignUp, .resetVerify: "確認する"
        case .resetRequest: "コードを送る"; case .newPassword: "パスワードを変える"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if [.login, .signUp, .resetRequest].contains(mode) {
                        TextField("メールアドレス", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("email")
                    }
                    if mode == .signUp { TextField("表示名（グループの人に見える名前）", text: $name).accessibilityIdentifier("name") }
                    if [.login, .signUp, .newPassword].contains(mode) {
                        SecureField(mode == .login ? "パスワード" : "パスワード（8 文字以上）", text: $password)
                            .textContentType(mode == .login ? .password : .newPassword).accessibilityIdentifier("password")
                    }
                    if [.verifySignUp, .resetVerify].contains(mode) {
                        Text("\(email) に届いた 6 桁のコードを入れてください。").font(.footnote).foregroundStyle(.secondary)
                        TextField("確認コード", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    }
                } header: { Text(title) }

                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("authError") }
                if let info { Text(info).foregroundStyle(Color.income) }

                Section {
                    Button { submit() } label: {
                        HStack { Spacer(); if busy { ProgressView() } else { Text(buttonTitle).bold() }; Spacer() }.frame(minHeight: 44)
                    }.disabled(busy).accessibilityIdentifier("submit")
                    switch mode {
                    case .login:
                        Button("はじめての方は新規登録") { mode = .signUp; error = nil }
                        Button("パスワードを忘れたとき") { mode = .resetRequest; error = nil }
                    case .newPassword: EmptyView()
                    default: Button("ログインに戻る") { mode = .login; error = nil }
                    }
                }
                if mode == .signUp {
                    Text("メールアドレスとパスワードは Supabase の認証で管理されます（パスワードはハッシュにして保存され、平文では残りません）。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("共有家計簿")
        }
        .onAppear { if expired { error = "ログインの期限が切れました。もう一度ログインしてください" } }
    }

    private func run(_ block: @escaping () async throws -> Void) {
        error = nil; info = nil; busy = true
        Task { @MainActor in
            do { try await block() } catch { self.error = Repo.map(error).userMessage }
            busy = false
        }
    }

    private func submit() {
        switch mode {
        case .login:
            if let e = Validate.email(email) ?? (password.isEmpty ? "パスワードを入れてください" : nil) { error = e; return }
            run { try await repo.signIn(email: email, password: password) }
        case .signUp:
            if let e = Validate.email(email) ?? Validate.displayName(name) ?? Validate.password(password) { error = e; return }
            run {
                let hasSession = try await repo.signUp(email: email, password: password, displayName: name)
                if !hasSession { mode = .verifySignUp; info = "確認のメールを送りました" }
            }
        case .verifySignUp:
            if code.count < 6 { error = "コードを入れてください"; return }
            run { try await repo.verifySignUp(email: email, code: code) }
        case .resetRequest:
            if let e = Validate.email(email) { error = e; return }
            run { try await repo.sendReset(email: email); mode = .resetVerify; info = "再設定のコードを送りました（届かないときは迷惑メールも確かめてください）" }
        case .resetVerify:
            if code.count < 6 { error = "コードを入れてください"; return }
            run { try await repo.verifyReset(email: email, code: code); mode = .newPassword; password = "" }
        case .newPassword:
            if let e = Validate.password(password) { error = e; return }
            run { try await repo.changePassword(password); info = "パスワードを変えました" }
        }
    }
}

// グループの選択・作成・招待コードでの参加
struct GroupSelectView: View {
    @Bindable var app: AppState
    @State private var newName = ""
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("家計簿を選ぶ") {
                    LoadableView(state: app.groups, retry: { await app.loadGroups() }, isEmpty: { $0.isEmpty }, empty: {
                        Text("まだ参加している家計簿はありません。作るか、招待コードで参加してください。").foregroundStyle(.secondary)
                    }) { gs in
                        ForEach(gs) { g in Button(g.name) { Task { await app.select(g) } }.frame(minHeight: 44) }
                    }
                }
                Section("新しく作る") {
                    TextField("家計簿の名前（例: うちの家計簿）", text: $newName)
                    Button("作る") {
                        if let e = Validate.groupName(newName) { error = e; return }
                        run { let g = try await app.repo.createGroup(newName); newName = ""; await app.loadGroups(); await app.select(g) }
                    }.disabled(busy)
                }
                Section("招待コードで参加する") {
                    TextField("招待コード（12 文字）", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("参加する") {
                        let c = code.uppercased().filter { $0.isLetter || $0.isNumber }
                        if c.count < 12 { error = "招待コードは 12 文字です"; return }
                        run {
                            if try await app.repo.acceptInvitation(c) == nil { error = "招待コードが正しくないか、期限切れか、使える回数をこえています" }
                            else { code = ""; await app.loadGroups() }
                        }
                    }.disabled(busy)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("ログアウト", role: .destructive) { Task { await app.signOut() } }
            }
            .navigationTitle("共有家計簿")
        }
    }

    private func run(_ block: @escaping () async throws -> Void) {
        error = nil; busy = true
        Task { @MainActor in
            do { try await block() } catch { self.error = Repo.map(error).userMessage }
            busy = false
        }
    }
}
