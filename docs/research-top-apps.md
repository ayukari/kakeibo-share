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

## 取り入れたもの（2026-10-30）

- 貯金箱の中身を、Blender で作った 3D の画像に変えた（`tools/render3d/money_sprites.py` で描き出し。Android は `res/drawable-nodpi/money_t{段階}_f{コマ}.png`、iOS は `Resources/Money`）。段階ごとに 8 コマで、0 コマ目が置いた姿、1〜7 コマ目は 45° ずつ回した姿。
- 降ってくるとき、1 枚ずつ 1 回転半しながら落ち、着いたときに置いた姿になる。札束の表と裏は札の色、あいだは紙の縁の色。

# 先人調査 6: 物理エンジン（2026-10-30）

貯金箱の硬貨・札束を、本物の物理（重力・ぶつかり・積み重なり）で落とすための候補。★と最終更新は GitHub（2026-10-30 時点）。

## 2D（箱を正面から見た今の絵にそのまま合う）

| エンジン | ライセンス | ★ / 更新 | Android | iOS | 向き不向き |
|---|---|---|---|---|---|
| [Box2D v3.2](https://github.com/erincatto/box2d)（C17） | MIT | 10.5k / 2026-10 | [box2d-jni](https://github.com/fabmax/box2d-jni)（MIT、Maven Central に Android 用 AAR。v3.2.0 の全 API）か、NDK で自分でビルド | C のソースを Xcode に入れて Swift から直接呼ぶ | 「たくさんの物の山」向けに最適化、端末をまたいで同じ結果（決定論的）、眠り（止まった物の計算を省く）。両 OS で同じ動きにできる |
| [boks2d](https://github.com/joaomcl/boks2d) | MIT | 33 / 2026-03 | Kotlin Multiplatform | Kotlin/Native | Box2D を両 OS で 1 つのコードから。まだ 0.1 で若い |
| SpriteKit の物理（Apple 標準） | — | — | — | `SpriteView` で SwiftUI に埋め込める | 追加の部品なし。数百個の硬貨でも十分。iOS 26 で SwiftUI を重ねたときに遅くなる報告あり（[Apple のフォーラム](https://developer.apple.com/forums/thread/804973)） |
| UIKit Dynamics（Apple 標準） | — | — | — | `UIDynamicAnimator` | 重力とぶつかりだけの簡単なもの。積み重なりは苦手 |
| [dyn4j](https://github.com/dyn4j/dyn4j)（Java だけ） | BSD-3 | 541 / 2026-07 | ネイティブのライブラリが要らない | — | Compose 用のラッパー [ComposePhysicsLayout](https://github.com/KlassenKonstantin/ComposePhysicsLayout)（Apache-2.0、2023 年で止まっている・試作扱い） |
| [JBox2D](https://github.com/jbox2d/jbox2d)（Box2D の古い Java 版） | BSD-2 | 1.2k / 2024-09 | [PhysicsLayout](https://github.com/Jawnnypoo/PhysicsLayout)（View 用） | — | 元の Box2D v2 系。新しい v3 の改良（山の安定）がない |
| [Rapier](https://github.com/dimforge/rapier)（Rust） | Apache-2.0 | 6.0k / 2026-10 | Rust を NDK でビルド | Rust を iOS 用にビルド | 2D・3D とも。両 OS のビルドの手間が大きい |
| [matter.js](https://github.com/liabru/matter-js) | MIT | 18.6k | — | — | Web 用。アプリには向かない |

## 3D（アプリの中で 3D のまま動かす場合）

| エンジン | ライセンス | ★ | メモ |
|---|---|---|---|
| [Jolt Physics](https://github.com/jrouwe/JoltPhysics) | MIT | 11.9k | 最近のゲームで使われる 3D の物理。描画は別に要る（Android は [Filament](https://github.com/google/filament)・[SceneView](https://github.com/SceneView/sceneview-android)） |
| [Bullet](https://github.com/bulletphysics/bullet3) | zlib | 14.8k | 古くからの定番 |
| [PhysX](https://github.com/NVIDIA-Omniverse/PhysX) | BSD-3 | 4.8k | NVIDIA。重い |
| SceneKit・RealityKit の物理（Apple 標準） | — | — | iOS だけ |

3D のまま動かすと、描画と物理の両方を両 OS で別々に組むことになり、アプリも重くなる。

## おすすめ

1. **Box2D v3.2 を両 OS で使う**: Android は box2d-jni（AAR）、iOS は C のソースをそのまま入れる。同じエンジン・同じ設定なので、両 OS で同じ積もり方になる。硬貨は角の丸い横長の箱（置いた硬貨の形）、札束は箱として落とし、描くのは今の 3D の画像（体の傾きに合わせて回す。回っている速さに合わせてコマを進める）。
2. 手間を減らすなら: Android は dyn4j、iOS は SpriteKit。ただし両 OS で動きが少しずつ違う。
- どちらでも: 落とす枚数は目標に対する割合で決める（100% で箱がいっぱい）。止まったら計算を止める（電池を使わない）。「動きを減らす」設定のときは、計算を一気に進めて積もった形だけ出す。端末を傾けると中身が転がる、貯金を記録したときに 1 枚ずつ足す、なども物理なら自然にできる。

## 取り入れたもの: 物理と、貯金額どおりの枚数（2026-10-30）

- 箱の中身は貯金額どおりの枚数（2 万円なら 100円玉 200 枚、20 万円なら千円札 200 枚）。中身 1 枚の大きさは、目標額ちょうどの枚数で箱がいっぱいになるように決める。だから満ち具合が目標に対する割合になる。目盛りは「目標の何割の枚数を積んだ高さか」。
- 物理は Box2D v3.2（MIT）。Android は box2d-jni（MIT、`de.fabmax.box2d-jni:box2d-jni-android`）、iOS は Box2D 公式の Swift Package。どちらも同じ作りの `CoinWorld`（Kotlin と Swift）で、同じ数値・同じ並び。
  - 中身は角の丸い横長の箱。投入口から 1 枚ずつ（多くても 1.2 秒で全部）落とし、回っている速さで 3D の絵のコマを進める。止まったら計算をやめる。
  - 端末を傾けると重力の向きが変わって転がる（Android は重力センサー、iOS は CoreMotion）。貯金を記録すると増えた分だけ落ち、取り崩すと上から減る。
  - 「動きを減らす」設定のときは、計算を一気に進めて積もった形だけ出す。動かす枚数の上限は 1,200 枚（それより多いときは枚数を文字で出す）。
- 物理の確かめ: `android/physicspreview`（PC で同じ `CoinWorld.kt` を動かし、止まること・箱からあふれないこと・枚数を確かめ、途中と最後の絵を描き出す）と、iOS の `PhysicsTests`。
- お札は 1 枚ずつ、作り込んだ 3D（`tools/render3d/bill.py`）: 波打つ地紋、花びら状のロゼット、交差する波の飾り枠、透かしの楕円、額面の数字、「KAKEIBO SHARE」の小さな文字、紙のたわみ。紙の繊維は ambientCG「Paper 001」（CC0）。肖像・実際の図柄・「日本銀行券」の文字は描かない。
- 調べたお札の 3D モデル（Poly Pizza の Dollar・Money など、CC-BY）は板に絵を貼っただけのもので、作り込みには使えなかった。Sketchfab のモデルはダウンロードにログインが要る。
