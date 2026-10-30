import SwiftUI
import Supabase

@main
struct KakeiboApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

// アプリ全体の状態（ログイン・開いているグループ・自分のメンバー情報）
@MainActor @Observable
final class AppState {
    let repo: Repo
    var signedIn: Bool? = nil          // nil = 確認中
    var expired = false
    var groups: Loadable<[KGroup]> = .loading
    var current: KGroup?
    var me: Member?
    var members: [Member] = []
    var toast: String?
    private static let lastGroupKey = "last_group"   // 端末に残すのは最後に開いたグループの ID だけ

    init(repo: Repo) { self.repo = repo }

    func watchSession() async {
        for await change in repo.client.auth.authStateChanges {
            switch change.event {
            case .signedOut:
                signedIn = false; current = nil; me = nil; members = []
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .passwordRecovery:
                if let s = change.session, !s.isExpired { signedIn = true } else { signedIn = false; expired = change.event == .initialSession && change.session != nil }
            default: break
            }
        }
    }

    func loadGroups() async {
        groups = .loading
        do {
            let gs = try await repo.groups()
            groups = .ready(gs)
            let last = current?.id ?? UserDefaults.standard.string(forKey: Self.lastGroupKey)
            if let pick = gs.first(where: { $0.id == last }) { await select(pick) } else { current = nil }
        } catch { groups = .failed(Repo.map(error)) }
    }

    func select(_ g: KGroup?) async {
        current = g
        UserDefaults.standard.set(g?.id, forKey: Self.lastGroupKey)
        if g != nil { await refreshMembers() }
    }

    func refreshMembers() async {
        guard let g = current else { return }
        do {
            members = try await repo.members(g.id)
            me = members.first { $0.userId?.lowercased() == repo.userId && $0.status == "active" }
            if me?.role != "viewer" { try? await repo.generateDue(g.id); try? await repo.generateDueSavings(g.id) }   // 期日の来た定期取引と先取り貯金を作る（何度呼んでも二重にならない）
        } catch {}
    }

    func signOut() async {
        try? await repo.signOut()
        current = nil; me = nil; members = []; signedIn = false
    }

    func can(_ min: String) -> Bool { roleRank(me?.role) >= roleRank(min) }
}

struct RootView: View {
    @State private var app: AppState? = Repo.create().map { AppState(repo: $0) }

    var body: some View {
        if let app {
            LockGate { SessionGate(app: app) }
        } else {
            VStack(spacing: 12) {
                Text("接続先が設定されていません").font(.title2.bold())
                Text("このビルドには Supabase の URL と anon キーが入っていません。ios/Config/Secrets.xcconfig に書いてビルドし直してください（docs/setup-ios.md）。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}

private struct SessionGate: View {
    @Bindable var app: AppState
    var body: some View {
        Group {
            switch app.signedIn {
            case .none: ProgressView()
            case .some(true): GroupGate(app: app)
            case .some(false): AuthView(repo: app.repo, expired: app.expired)
            }
        }
        .task { await app.watchSession() }
        .toast($app.toast)
    }
}

private struct GroupGate: View {
    @Bindable var app: AppState
    var body: some View {
        Group {
            if let g = app.current { MainTabView(app: app, group: g).id(g.id) } else { GroupSelectView(app: app) }
        }
        .task { await app.loadGroups() }
    }
}
