import SwiftUI
import LocalAuthentication

// アプリのロック（上位の家計簿アプリの「パスコードロック」と同じ役目）。
// 暗証番号を自前で持たず、端末の Face ID・Touch ID・パスコードで解除する。設定は端末だけに保存
enum AppLock {
    static let key = "kakeibo.lockEnabled"
    static let relockAfter: TimeInterval = 60   // 1 分以上ほかのアプリに行ったら、戻ったときにもう一度ロック

    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    static func unlock() async -> (ok: Bool, message: String?) {
        let ctx = LAContext()
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "共有家計簿のロックを解除します")
            return (ok, nil)
        } catch let e as LAError where e.code == .userCancel || e.code == .systemCancel || e.code == .appCancel {
            return (false, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// ロックが有効なら、解除するまで中身を出さない
struct LockGate<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @AppStorage(AppLock.key) private var enabled = false
    @Environment(\.scenePhase) private var phase
    @State private var locked = UserDefaults.standard.bool(forKey: AppLock.key)
    @State private var leftAt: Date?
    @State private var message: String?

    var body: some View {
        Group {
            if locked && enabled {
                VStack(spacing: 12) {
                    Text("ロック中").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.kInk)
                    Text("家計簿を見るには、Face ID・Touch ID・パスコードで解除してください。").foregroundStyle(Color.kSub).multilineTextAlignment(.center)
                    if let message { Text(message).foregroundStyle(Color.kDanger).multilineTextAlignment(.center) }
                    Button { Task { await tryUnlock() } } label: {
                        Text("ロックを解除する").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kAccentInk).frame(maxWidth: .infinity, minHeight: 52).background(Color.kAccent, in: buttonShape)
                    }.buttonStyle(.plain).padding(.top, 8)
                }
                .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.kBg)
                .task { await tryUnlock() }
            } else { content() }
        }
        .onChange(of: phase) {
            switch phase {
            case .background: leftAt = Date()
            case .active: if enabled, let t = leftAt, Date().timeIntervalSince(t) >= AppLock.relockAfter { locked = true }; leftAt = nil
            default: break
            }
        }
    }

    @MainActor private func tryUnlock() async {
        let r = await AppLock.unlock()
        if r.ok { locked = false; message = nil } else { message = r.message }
    }
}

// 設定の行: アプリにロックをかける
struct LockToggle: View {
    @AppStorage(AppLock.key) private var enabled = false
    @Binding var message: String?
    var body: some View {
        Toggle(isOn: Binding(get: { enabled }, set: { on in
            if on && !AppLock.available { message = "端末にパスコード（Face ID・Touch ID）を設定してから、もう一度ためしてください"; return }
            enabled = on; message = on ? "ロックを有効にしました。次に開いたときから使えます" : "ロックを切りました"
        })) {
            VStack(alignment: .leading) { Text("アプリにロックをかける"); FaintText("開くとき・1 分以上はなれたあとに、Face ID・Touch ID・パスコードで解除します") }
        }
    }
}
