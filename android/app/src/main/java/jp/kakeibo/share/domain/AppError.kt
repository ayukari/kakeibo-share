package jp.kakeibo.share.domain

// エラーの分類（両 OS で同じ。docs/spec-common.md の表）。サーバーの SQLSTATE（KB401 など）と HTTP の状態から決める
enum class ErrorKind { Network, Unauthorized, Forbidden, NotFound, Conflict, Validation, Server }

class AppError(val kind: ErrorKind, val key: String = "", val field: String? = null, cause: Throwable? = null) : Exception(key, cause) {
    val userMessage: String get() = messageFor(kind, key)

    companion object {
        fun fromCode(code: String?, message: String?, hint: String?, httpStatus: Int?): AppError {
            val kind = when (code) {
                "KB401" -> ErrorKind.Unauthorized
                "KB403", "42501" -> ErrorKind.Forbidden
                "KB404" -> ErrorKind.NotFound
                "KB409" -> ErrorKind.Conflict
                "KB422", "22P02", "23514" -> ErrorKind.Validation
                else -> when (httpStatus) {
                    401 -> ErrorKind.Unauthorized
                    403 -> ErrorKind.Forbidden
                    404 -> ErrorKind.NotFound
                    409 -> ErrorKind.Conflict
                    400, 422 -> ErrorKind.Validation
                    else -> ErrorKind.Server
                }
            }
            return AppError(kind, message.orEmpty(), hint?.takeIf { it.isNotBlank() })
        }

        private val keys = mapOf(
            "amount_invalid" to "金額は 1〜999,999,999 円の整数で入れてください",
            "date_invalid" to "日付が範囲外です",
            "memo_too_long" to "メモは 500 文字までです",
            "category_invalid" to "カテゴリを選び直してください",
            "payer_invalid" to "支払った人を選び直してください",
            "split_sum_mismatch" to "分担の合計が金額と合いません",
            "split_member_invalid" to "分担するメンバーを選び直してください",
            "split_required" to "分担するメンバーを選んでください",
            "conflict" to "ほかの人が先に変更しました。最新の内容を読み直してください",
            "already_member" to "すでにこのグループのメンバーです",
            "too_many_attempts" to "試した回数が多すぎます。15 分ほど待ってください",
            "owner_must_transfer" to "オーナーは、先にオーナーをほかの人に譲ってください",
            "settlement_exceeds_balance" to "精算の金額が、未精算の残りより多くなっています",
            "settlement_not_pending" to "この精算は、すでに確認か取り消しがされています",
            "category_name_taken" to "同じ名前のカテゴリがあります",
            "group_name_length" to "グループ名は 1〜40 文字で入れてください",
            "invitation_invalid" to "招待コードが正しくないか、期限切れです",
            "use_transfer_ownership" to "オーナーにするときは「オーナーを譲る」を使ってください",
            // 認証（Supabase Auth の error_code）
            "invalid_credentials" to "メールアドレスかパスワードが違います",
            "email_not_confirmed" to "メールの確認がまだです。届いたコードを入れてください",
            "otp_expired" to "コードが違うか、期限が切れています",
            "user_already_exists" to "このメールアドレスはもう登録されています",
            "email_exists" to "このメールアドレスはもう登録されています",
            "weak_password" to "パスワードが弱すぎます。長くするか、文字の種類を増やしてください",
            "over_email_send_rate_limit" to "メールの送信が多すぎます。しばらく待ってからためしてください",
            "over_request_rate_limit" to "操作が多すぎます。しばらく待ってからためしてください",
        )

        fun messageFor(kind: ErrorKind, key: String): String = keys[key] ?: when (kind) {
            ErrorKind.Network -> "通信できませんでした。電波を確かめて、もう一度ためしてください（保存はされていません）"
            ErrorKind.Unauthorized -> "ログインの期限が切れました。もう一度ログインしてください"
            ErrorKind.Forbidden -> "この操作をする権限がありません"
            ErrorKind.NotFound -> "見つかりませんでした。削除されたかもしれません"
            ErrorKind.Conflict -> "ほかの人が先に変更しました。読み直してください"
            ErrorKind.Validation -> "入力を確かめてください"
            ErrorKind.Server -> "サーバーでエラーが起きました。時間をおいてためしてください"
        }
    }
}
