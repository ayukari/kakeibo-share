# 費用と無料枠の限界

「完全に無料」とは言えません。無料枠で始められますが、下の上限と、ストアの登録料が別にかかります。数字は 2026-10 時点で調べたもので、変わることがあります（使う前に各社の料金ページで確かめる）。

## サーバー（Supabase Free）
| 項目 | 上限 | 家族・知人での目安 |
|---|---|---|
| DB 容量 | 500 MB | 1 件 約 1 KB として数十万件。数家族なら何年ももつ |
| 月間アクティブユーザー | 50,000 | 問題なし |
| 通信量（egress） | 5 GB/月 | 問題なし |
| プロジェクト数 | 2 | |
| 一時停止 | 1 週間使われないと停止 | 毎週誰かが開けば止まらない。止まったらダッシュボードで再開 |
| バックアップ | なし | 手で取る（docs/backup-restore.md） |
| 標準のメール送信 | 組織のメンバーだけ・1 時間に数通 | **実用にならない → 独自 SMTP が必要** |

有料（Pro）は月 25 ドル〜。自動バックアップと一時停止なしが付く。

## メール（登録の確認・パスワード再設定）の無料の候補
| サービス | 無料枠 | メモ |
|---|---|---|
| Resend | 月 3,000 通・1 日 100 通・ドメイン 1 つ | SMTP あり。設定がかんたん |
| Brevo | 1 日 300 通 | SMTP リレーあり。無料はフッターに Brevo の表示が入るという情報あり（要確認） |

どちらも**送信元のドメイン**（例: 自分のドメイン）の DNS 設定（SPF・DKIM）が必要。ドメインは年 1,000〜2,000 円ほど。
この規模（確認とパスワード再設定だけ）なら、どちらの無料枠にも十分おさまる。**採用: Resend**（2026-10-28 社長が一任。SMTP の設定が少なく、フッターの広告表示がない）。

## ビルド（iOS はクラウドの Mac）
GitHub Actions: 公開リポジトリは無料。非公開リポジトリは Free プランで月 2,000 分、macOS は 10 倍で数えるので **実質 約 200 分/月**。iOS のビルドとテスト 1 回 10〜15 分として月 10 回強。
家計簿のコードを公開リポジトリに置くかどうかは社長の判断（秘密はコードに入っていないので、公開しても接続先のキーは漏れない設計）。

## ストア（別にかかる）
| | 費用 | |
|---|---|---|
| Google Play | 登録 25 ドル（1 回） | 新しい個人アカウントは公開前に 12 人以上・14 日間のテストが必要 |
| Apple Developer Program | 年 99 ドル | 家族・知人だけなら TestFlight（最大 1 万人・90 日ごとに更新）で配れる |
| ストアを使わない | Android は APK を直接渡せる（0 円）。iOS は実質できない | |

## 調べた先
- Resend の無料枠: https://wpmailsmtp.com/resend-review/ ・ https://automationatlas.io/answers/resend-free-tier-explained-2026/
- Brevo の無料枠: https://sendlayer.com/blog/best-free-smtp-servers/ ・ https://dreamlit.ai/blog/brevo-review
- GitHub Actions: https://docs.github.com/en/billing/concepts/product-billing/github-actions ・ https://cicdpipelinecost.com/github-actions-pricing
- Supabase の無料枠: IMPLEMENTATION_PLAN.md の調査
