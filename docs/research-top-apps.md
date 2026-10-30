# 先人調査: Google Play の上位の家計簿アプリ（2026-10-30）

Google Play で「家計簿」を検索した上位から、ダウンロード数の多いアプリと、共有家計簿の代表を選び、
ストアの説明文と画面写真を見た。数字はストアの表示（2026-10-30 時点）。

| アプリ | ダウンロード | 評価 | 種類 |
|---|---|---|---|
| らくな家計簿（Realbyte） | 1,000 万+ | 4.4 | 手入力。資産（現金・銀行・カード）つき |
| シンプル家計簿 MoneyNote（Komorebi） | 100 万+（累計 800 万人と記載） | 4.8（7.9 万件） | 手入力・通信なし。「家計簿」検索 1 位 |
| 家計簿くふう Zaim | 100 万+ | 4.1 | 手入力・レシート・口座連携 |
| OsidOri（家計簿共有アプリ） | 10 万+（利用者 90 万人と記載） | 4.4 | 夫婦・カップルの共有家計簿 |
| マネーフォワード ME | 上位（説明は口座連携が中心） | 4.2 | 口座連携が中心 |

## 見えた共通の作り

### 入力（どのアプリもいちばん力を入れている）
- 一番上に「支出 / 収入」の切り替え。その下に日付（左右の矢印で前日・翌日）、メモ、金額。
- **カテゴリはアイコンのタイル（4 列）を押して選ぶ**。プルダウンではない。（MoneyNote・OsidOri・らくな家計簿）
- **電卓つきのキーボード**（MoneyNote が特徴として前面に出している。数字が大きく押しやすい）。
- 下に大きな「入力する」ボタン。

### カレンダー
- 日ごとの金額が入ったカレンダー＋下にその日の明細（MoneyNote・らくな家計簿・OsidOri）。
- MoneyNote は「カレンダーから直接入力・削除」できる。
- 月の始まり日・締め日（給料日始まり）を変えられる（MoneyNote・OsidOri）。

### レポート
- **カテゴリの内訳は円グラフ（ドーナツ）**が標準（MoneyNote・らくな家計簿・OsidOri）。
- 上に「収入・支出・収支」の 3 つの数字。前月比。

### 固定費
- 繰り返しの選択肢が多い。MoneyNote は「土日祝日の場合は前の平日／後の平日」も選べる。
- レビューでは「この月だけ除外」の要望（国保の 4・5 月など）。

### 共有（OsidOri）
- 「共有ページ」と「個人ページ」を分けられる。個人の明細から選んで共有にも出せる。
- **精算・割り勘は金額だけでなく割合（6:4 など）でも設定**できる。
- ふたりの目標貯金。メンバーの顔（アイコン）が出る。
- 家計のタイプ（定額を出し合う・費目ごとに担当・収入をまとめてお小遣い制）を説明で案内している。

### 安心
- **パスコードロック**（MoneyNote は無料で提供と明記）。
- CSV 出力、バックアップ。

## このアプリとの差と、今回入れたもの

| 項目 | 上位アプリ | このアプリ（前） | 今回 |
|---|---|---|---|
| カテゴリの選び方 | アイコンのタイル | プルダウン | **タイル（4 列）に変更** |
| 金額の入力 | 電卓つきの大きなキー | 端末のキーボード | **電卓キーボードを追加**（＋−×÷、00、消す） |
| 日付 | 左右の矢印 | 日付の選択画面 | **前日・翌日の矢印を追加** |
| 割り勘 | 金額・割合（6:4） | 均等・金額 | **割合（%）を追加** |
| 内訳のグラフ | ドーナツ | 横棒 | **ドーナツを追加**（横棒も残す） |
| カレンダーから入力 | あり | なし | **「この日に記録する」を追加** |
| ロック | パスコード | なし | **端末のロック（指紋・顔・暗証番号）を追加** |
| 共有と個人 | 分けられる | 「自分だけ」の記録・目標あり | 既にあり |
| 目標貯金・精算 | あり | あり | 既にあり |
| 締め日（給料日始まり） | あり | なし | 未（DB の集計の作り直しが要るので次の候補） |
| 口座・財布ごとの残高 | あり | 支払い方法のみ | 未（次の候補） |
| 固定費の土日の前倒し・除外月 | あり（MoneyNote） | なし | 未（次の候補） |
| レシート・口座連携 | あり | なし（方針として入れない） | 入れない |

## 見たもの
- https://play.google.com/store/search?q=家計簿&c=apps&hl=ja
- https://play.google.com/store/apps/details?id=com.komorebi.kakeibo
- https://play.google.com/store/apps/details?id=com.realbyteapps.moneymanagerfree
- https://play.google.com/store/apps/details?id=inc.osidori
- https://play.google.com/store/apps/details?id=net.zaim.android

# 先人調査 2: GitHub の公開ソースの家計簿・割り勘アプリ（2026-10-30、15 分）

| リポジトリ | ★ | 種類 |
|---|---|---|
| maybe-finance/maybe | 54k | 個人の資産管理 |
| actualbudget/actual | 29.8k | 封筒式の予算（余りを翌月に回す） |
| firefly-iii/firefly-iii | 25k | 自前サーバーの家計簿（定期・ルール・貯金箱） |
| mayswind/ezbookkeeping | 5.8k | 自前サーバーの家計簿 |
| jameskokoska/Cashew | 4.8k | スマホの予算アプリ |
| Ivy-Apps/ivy-wallet | 3.1k | Kotlin・Compose のスマホ家計簿 |
| spliit-app/spliit | 3k | グループの割り勘 |
| rarfell/dimeApp | 1.9k | SwiftUI のスマホ家計簿 |
| oss-apps/split-pro | 1.4k | グループの割り勘 |
| mtotschnig/MyExpenses | 1.2k | Android の家計簿 |

## 見えた共通の作り

- **割り勘の分け方**: split-pro は「均等・割合・口数（share）・金額・調整」。spliit も均等ではない分け方に対応している。
- **探す**: spliit、Cashew、ezbookkeeping、Firefly III のどれにも検索がある。Cashew は日付・カテゴリ・金額でも絞り込める。
- **ロック**: Cashew、Dime、MyExpenses は生体認証か端末のロックで守る。前回の調査で取り入れ済み。
- **定期の記録、目標・貯金箱、CSV、精算の提案**: Firefly III、Cashew、spliit などにある。このアプリには取り入れ済み。
- **予算の余りを翌月に回す**（Actual の rollover）と、**返金をマイナスの支出として扱う**（split-pro）: サーバーの集計も変えて取り入れた（下の表）。

## 今回入れたもの

| 機能 | 参考 | このアプリ |
|---|---|---|
| 割り勘の「割合」 | split-pro（割合と口数） | 合計 100% の縛りをやめた。60:40 の % でも、大人 2・子ども 1 の口数でも同じ欄で分けられる |
| 一覧の検索 | spliit、Cashew | メモ・カテゴリに加えて、払った人と金額（1,200 や ¥1200 も可）でも探せる |
| 返金 | split-pro（マイナスの支出） | 支出に「返金」の印を付ける。金額は正のまま持ち、集計・予算・立替と負担では引く。割り勘つきの返金は、分担した人の負担も同じ割合で減る |
| 予算の繰り越し | Actual Budget（rollover） | 予算ごとに「余りを翌月に回す」を選べる。余りは翌月に足し、使いすぎは翌月から引く。繰り越さない月があれば、そこから数え直す。繰り越す予算の余りは、貯金の「予算の余り」には出さない（二重に使わないため） |

# 先人調査 3: 貯金箱の見せ方（2026-10-30）

- Google Play で「貯金箱」を検索した上位は、Simple piggy bank（100 万+）と「貯金箱：目標管理で楽しく貯金」（50 万+）。どちらも、目的ごとの貯金箱・達成率（%）・グラフで進み具合を見せる。App Store の「超シンプル『貯金箱』」は、紙幣と硬貨ごとの額を数える。
- 降ってくる動きは、紙吹雪の部品として有名な Konfetti（Android、★3.4k）と ConfettiSwiftUI（★2.5k）と同じ考え方にした: 1 枚ずつ重力のように加速して落ち、底で少しはねる。始まる時間を少しずつずらす。
- 硬貨とお札の絵: 財務省の FAQ によると、日本銀行券や貨幣に紛らわしい外観のものは通貨及証券模造取締法で禁止されており、図柄の似せ方・大きさ・「見本」の文字などを総合して判断される。そのため、肖像や実際の図柄は描かず、色と形だけで表した（10円 = 赤みのある銅色、100円 = 銀白色、500円 = 外側が金色・内側が銀色の 2 色、千円札 = 青系、万札 = 茶系。お札は枠と透かしの楕円だけ）。色は造幣局・財務省の素材の説明（青銅・白銅・バイカラー・クラッド）に合わせた。

| 機能 | このアプリ |
|---|---|
| 目標の貯金箱 | 目標ごとの箱に、貯まった額で中身が変わる: 1 万円未満は 10円玉、1 万円から 100円玉、3 万円から 500円玉、10 万円から千円札、50 万円から万札。箱の満ち具合は目標に対する割合で、25・50・75・100% の目盛り付き |
| 段階のバッジ | 5 段階を並べて、届いた段階は濃く、今の段階は太字。「あと ¥40,000 で千円札に変わります」と次の段階までの額を出す |
| 降ってくる動き | 画面を開くと、置き場所の真上から 1 枚ずつ降って積もる（約 1.8 秒）。端末の「動きを減らす」設定のときは、はじめから積んだ形で出す |

参考: [財務省 FAQ（通貨の模造）](https://www.mof.go.jp/faq/currency/07af.htm)・[財務省 貨幣の一覧](https://www.mof.go.jp/policy/currency/coin/general_coin/list.htm)・[Konfetti](https://github.com/DanielMartinus/Konfetti)・[ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI)

# 先人調査 4: タダで使える硬貨・お札・札束の素材（2026-10-30）

| 素材 | ライセンス | 中身 | 公開リポジトリに入れられるか |
|---|---|---|---|
| [いらすとや](https://www.irasutoya.com/p/faq.html) | 無料（著作権は放棄していない）。広告や課金のあるアプリは商用扱いで 1 作品 20 点まで。クレジット不要。色の変更は可 | [日本の硬貨（1・5・10・50・100・500円）](https://www.irasutoya.com/2019/04/blog-post_303.html)、[札束](https://www.irasutoya.com/2016/04/blog-post_3.html)、[新紙幣](https://www.irasutoya.com/2024/07/blog-post.html) | 要注意。「素材としての再配布」が禁止なので、誰でも画像を取り出せる公開リポジトリに置くのは避けたい |
| [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji)（★10k） | MIT（ライセンス文を同梱すれば自由） | 立体の硬貨（金色、建物の柄）、帯付きの札束（¥）、お金の袋。平面の SVG もあり、色を変えられる | 可 |
| [Quaternius の 3D モデル（Poly Pizza）](https://poly.pizza/search/coin) | CC0（権利放棄。表記も不要） | 積んだ硬貨（Coin Piles・Coins）、硬貨の袋。ローポリの 3D | 可（アプリでは画像に描き出して使う） |
| [Kenney](https://kenney.nl/assets/platformer-kit) | CC0 | ゲーム用の硬貨のアイコン・3D | 可 |
| [Twemoji](https://github.com/jdecked/twemoji) | CC-BY 4.0（表記が必要） | 🪙 💴 💰 | 可（表記を入れる） |
| [OpenMoji](https://github.com/hfg-gmuend/openmoji) | CC-BY-SA 4.0（同じライセンスで配る義務） | 🪙 💴 💰 | 避けたい（アプリの素材全体に条件が及ぶ） |
| [LottieFiles](https://help.lottiefiles.com/hc/en-us/articles/900002438343-Can-I-use-a-free-animation-on-Lottiefiles-for-commercial-business-use) | 無料の動きは Lottie Simple License（商用可）。作品ごとに条件の確認が必要 | 硬貨が落ちる動きなど | 作品による |

- 本物の硬貨・お札の写真や、それに近い絵は避ける（[財務省 FAQ](https://www.mof.go.jp/faq/currency/07af.htm)）。いらすとやの硬貨・お札は、デフォルメした絵。

# 先人調査 5: 3DCG の硬貨・札束（2026-10-30）

## 無料の 3D モデル

| 置き場所 | モデル | ライセンス | 見た目 | 使えるか |
|---|---|---|---|---|
| [Sketchfab](https://sketchfab.com/models/7605cd1ccf42498f8cd02b3f758c1643) | 100 Yen Coin（AlsGraphics、320 面） | CC-BY（表記が必要） | 昔の 100 円玉をそのまま写した見た目 | 避ける（本物に近い） |
| [Sketchfab](https://sketchfab.com/models/1998b42922be4cbbb752de8b307bdaf4) | Money Stacks（3D_Crackhouse、♥365） | CC-BY | ドル札の束。本物の札の絵柄 | 避ける（本物の札の絵・ドル） |
| [Sketchfab](https://sketchfab.com/models/632cf7dbc59a496283d1a6092dc6f9b0) | Low Poly Stack of Money（40 面） | CC-BY | ドル札の束 | 同上（形だけなら使えるが、自作と変わらない） |
| [Sketchfab](https://sketchfab.com/models/5e661adf11f24a76bb9538b536002bb3) | Pile of coins（gnarlypotato、♥254） | CC-BY | 金貨の山 | 表記を入れれば可。日本の硬貨らしさはない |
| [Poly Pizza / Quaternius](https://poly.pizza/m/9OWkKczINo) | Coin Piles・Coins・Coin Bag | CC0 | ローポリの金貨 | 可。日本の硬貨らしさはない |
| [Poly Haven](https://polyhaven.com/models) | （硬貨・お札はなし。Cash Register だけ） | CC0 | — | — |

- 札束のモデルは、ほぼ全部がドル札の写真を貼ったもの。日本の札束で、本物に似ていない無料モデルは見つからなかった。

## 結論: Blender で自作して、画像に描き出す

- 手元の Blender 5.2 で、硬貨と札束を一から作るスクリプトを書いた（`tools/render3d/coins3d.py`）。図柄は描かず、色・金属の質感・形だけ。自作なのでライセンスの心配がなく、公開リポジトリに置ける。
  - 10円 = 青銅、100円 = 白銅、500円 = 外側が金色・内側が銀色。縁の盛り上がりと面取りで立体感を出す。
  - 千円札・万札 = 10 枚を少しずつずらして重ね、白い帯と透かしの楕円。
- 動かし方の候補:
  1. 描き出した画像を、今の「降ってくる」動きにそのまま使う（軽い。Android と iOS で同じ見た目）。回転のコマ（数枚）も描き出せば、くるくる回りながら落ちる。
  2. アプリの中で 3D を動かす: Android は [SceneView](https://github.com/SceneView/sceneview-android)（Apache-2.0、★1.4k。Google の [Filament](https://github.com/google/filament) の上）、iOS は標準の SceneKit・RealityKit（物理演算あり）。本物の物理で落とせるが、アプリが重くなり、Android と iOS で作りが別々になる。
