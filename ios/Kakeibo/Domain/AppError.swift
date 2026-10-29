import Foundation

// エラーの分類（両 OS で同じ。tests/vectors/errors.json）
enum ErrorKind: String { case Network, Unauthorized, Forbidden, NotFound, Conflict, Validation, Server }

struct AppError: Error, Equatable {
    let kind: ErrorKind
    var key: String = ""
    var field: String? = nil

    var userMessage: String { AppError.message(kind, key) }

    static func fromCode(_ code: String?, message: String?, hint: String?, http: Int?) -> AppError {
        let kind: ErrorKind
        switch code {
        case "KB401": kind = .Unauthorized
        case "KB403", "42501": kind = .Forbidden
        case "KB404": kind = .NotFound
        case "KB409": kind = .Conflict
        case "KB422", "22P02", "23514": kind = .Validation
        default:
            switch http {
            case 401: kind = .Unauthorized
            case 403: kind = .Forbidden
            case 404: kind = .NotFound
            case 409: kind = .Conflict
            case 400, 422: kind = .Validation
            default: kind = .Server
            }
        }
        return AppError(kind: kind, key: message ?? "", field: (hint?.isEmpty == false) ? hint : nil)
    }

    static let keys: [String: String] = [
        "amount_invalid": "金額は 1〜999,999,999 円の整数で入れてください",
        "date_invalid": "日付が範囲外です",
        "memo_too_long": "メモは 500 文字までです",
        "category_invalid": "カテゴリを選び直してください",
        "payer_invalid": "支払った人を選び直してください",
        "split_sum_mismatch": "分担の合計が金額と合いません",
        "split_member_invalid": "分担するメンバーを選び直してください",
        "split_required": "分担するメンバーを選んでください",
        "conflict": "ほかの人が先に変更しました。最新の内容を読み直してください",
        "already_member": "すでにこのグループのメンバーです",
        "too_many_attempts": "試した回数が多すぎます。15 分ほど待ってください",
        "owner_must_transfer": "オーナーは、先にオーナーをほかの人に譲ってください",
        "settlement_exceeds_balance": "精算の金額が、未精算の残りより多くなっています",
        "settlement_not_pending": "この精算は、すでに確認か取り消しがされています",
        "category_name_taken": "同じ名前のカテゴリがあります",
        "group_name_length": "グループ名は 1〜40 文字で入れてください",
        "invitation_invalid": "招待コードが正しくないか、期限切れです",
        "use_transfer_ownership": "オーナーにするときは「オーナーを譲る」を使ってください",
        "invalid_credentials": "メールアドレスかパスワードが違います",
        "email_not_confirmed": "メールの確認がまだです。届いたコードを入れてください",
        "otp_expired": "コードが違うか、期限が切れています",
        "user_already_exists": "このメールアドレスはもう登録されています",
        "email_exists": "このメールアドレスはもう登録されています",
        "weak_password": "パスワードが弱すぎます。長くするか、文字の種類を増やしてください",
        "over_email_send_rate_limit": "メールの送信が多すぎます。しばらく待ってからためしてください",
        "over_request_rate_limit": "操作が多すぎます。しばらく待ってからためしてください",
    ]

    static func message(_ kind: ErrorKind, _ key: String) -> String {
        if let m = keys[key] { return m }
        switch kind {
        case .Network: return "通信できませんでした。電波を確かめて、もう一度ためしてください（保存はされていません）"
        case .Unauthorized: return "ログインの期限が切れました。もう一度ログインしてください"
        case .Forbidden: return "この操作をする権限がありません"
        case .NotFound: return "見つかりませんでした。削除されたかもしれません"
        case .Conflict: return "ほかの人が先に変更しました。読み直してください"
        case .Validation: return "入力を確かめてください"
        case .Server: return "サーバーでエラーが起きました。時間をおいてためしてください"
        }
    }
}
