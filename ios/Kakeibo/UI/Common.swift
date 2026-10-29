import SwiftUI

// ---------- 読み込みの状態（読み込み中・データなし・通信エラーを必ず出す） ----------
enum Loadable<T> {
    case loading
    case ready(T)
    case failed(AppError)
}

// 読み込みと操作をまとめた ViewModel。失敗を成功に見せない
@MainActor @Observable
final class Loader<T> {
    var state: Loadable<T> = .loading
    var message: String?
    var busy = false
    private let load: () async throws -> T

    init(_ load: @escaping () async throws -> T) { self.load = load }

    func reload() async {
        if case .ready = state {} else { state = .loading }
        do { state = .ready(try await load()) } catch { state = .failed(Repo.map(error)) }
    }

    // 書き込みの操作。成功したら読み直す。失敗はエラー文を出す（入力は画面に残る）
    @discardableResult
    func act(_ success: String?, reloadAfter: Bool = true, _ block: () async throws -> Void) async -> Bool {
        if busy { return false }
        busy = true
        defer { busy = false }
        do {
            try await block()
            if let success { message = success }
            if reloadAfter { await reload() }
            return true
        } catch {
            message = Repo.map(error).userMessage
            return false
        }
    }
}

struct LoadableView<T, Content: View, Empty: View>: View {
    let state: Loadable<T>
    let retry: () async -> Void
    var isEmpty: (T) -> Bool = { _ in false }
    @ViewBuilder var empty: () -> Empty
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(40).accessibilityLabel("読み込み中")
        case .failed(let e):
            ErrorBox(error: e, retry: retry)
        case .ready(let v):
            if isEmpty(v) { empty() } else { content(v) }
        }
    }
}

extension LoadableView where Empty == EmptyView {
    init(state: Loadable<T>, retry: @escaping () async -> Void, @ViewBuilder content: @escaping (T) -> Content) {
        self.state = state; self.retry = retry; self.empty = { EmptyView() }; self.content = content
    }
}

struct ErrorBox: View {
    let error: AppError
    let retry: () async -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text(error.kind == .Forbidden ? "アクセスできません" : "読み込めませんでした").font(.headline)
            Text(error.userMessage).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if error.kind != .Forbidden { Button("もう一度読み込む") { Task { await retry() } }.buttonStyle(.bordered).frame(minHeight: 44) }
        }
        .frame(maxWidth: .infinity).padding(24)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyBox: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(28)
    }
}

struct MoneyText: View {
    let yen: Int64
    var big = false
    var signed = false
    var color: Color? = nil
    var body: some View {
        Text((signed && yen > 0 ? "+" : "") + Money.format(yen))
            .font(big ? .system(size: 30, weight: .bold) : .body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color ?? .primary)
    }
}

struct MonthBar: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { month = Money.addMonths(month, -1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("前の月")
            Text(Money.monthLabel(month)).font(.headline).frame(maxWidth: .infinity)
            Button { month = Money.addMonths(month, 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("次の月")
                .disabled(month >= Money.monthStart(Money.todayJST()))
        }
    }
}

// 金額の入力欄（数字キーボード）
struct AmountField: View {
    let label: String
    @Binding var text: String
    var error: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text("¥"); TextField(label, text: $text).keyboardType(.numberPad) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}

let roleNames = ["owner": "オーナー", "admin": "管理者", "member": "メンバー", "viewer": "閲覧のみ"]
func roleRank(_ r: String?) -> Int {
    switch r { case "owner": 4; case "admin": 3; case "member": 2; case "viewer": 1; default: 0 }
}

extension Color {
    static let income = Color(red: 0.05, green: 0.46, blue: 0.34)
    static let over = Color(red: 0.71, green: 0.14, blue: 0.09)
}

// 操作の結果を画面の下に少しだけ出す
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = message {
                Text(m).padding(.horizontal, 16).padding(.vertical, 10).background(.thinMaterial, in: Capsule()).padding(.bottom, 24)
                    .accessibilityAddTraits(.isStaticText)
                    .task(id: m) { try? await Task.sleep(for: .seconds(3)); if message == m { message = nil } }
            }
        }
    }
}
extension View { func toast(_ m: Binding<String?>) -> some View { modifier(ToastModifier(message: m)) } }
