# HayaosiApp プロジェクト設定

## 概要
勉強系早押し対戦iOSアプリ **「マナビート」**(App Storeでの表示名。**リポジトリ名・ターゲット名・Bundle ID `com.n.HayaosiApp` は変更しない** — App Store上で別アプリ扱いになるため)。
Swift / SwiftUI・iOS 17+・SwiftData。Firebase(匿名Auth / RTDB=ルーム同期・早押し判定 / Firestore=プロフィール・フレンド・招待)。

文書の役割:**スコープと意図=要件定義書 / 進捗・宣言・実装詳細=STATUS.md / 完了した過去=STATUS_ARCHIVE.md**。

## 読み込みガイド(必要な時だけ読む。常時読むのはこのファイルとSTATUS.mdだけ)

| 状況 | 読むファイル |
|---|---|
| **Swiftを書く・レビューする** | **`docs/CODING.md`(規約・命名・テスト方針・SwiftData移行の注意)** |
| Firebaseの設定・データ構造・セキュリティルール | `FIREBASE_SETUP.md` |
| clone直後のセットアップ / push・認証で詰まった | `README.md` |
| 過去の経緯・完了した作業を調べる | `STATUS_ARCHIVE.md` |

## ディレクトリ構成
フォルダの役割だけを規約にする(ファイル名の列挙は陳腐化するのでしない)。

```
/Users/n/HayaosiApp/
├── project.yml               # XcodeGen定義(ターゲット・ビルド設定はここが正)
├── Config/                   # 署名設定(local.xcconfigはgit管理外=各自の環境)
├── HayaosiApp.xcodeproj/     # 生成物。手編集禁止
├── HayaosiApp/
│   ├── App/                  # エントリポイント
│   ├── Models/               # SwiftDataモデル・enum
│   ├── Services/             # ロジック(出題エンジン・集計・データ投入など)
│   │   ├── Battle/           # 対戦の共通部分(Firebase非依存)とCPU対戦
│   │   └── Online/           # Firebase層(認証・フレンド・ルーム状態・対戦セッション)
│   ├── Views/<機能名>/        # 画面(Root=タブ / Battle=対戦フロー一式 / Study / MyPage / Practice / Quiz / Review / Friend / Settings / Creation / Components)
│   ├── Resources/            # 問題データJSON・効果音・GoogleService-Info.plist(git管理外)
│   └── Assets.xcassets/
├── Tests/                    # ユニットテスト(ロジックのみ)
├── docs/                     # 随時読み込むナレッジ(CODING.md など)
└── *.md                      # 要件定義書 / STATUS / STATUS_ARCHIVE / README / FIREBASE_SETUP
```

配置ルール:
- データモデル → `Models/`、ロジック・共有状態 → `Services/`、UI → `Views/<機能名>/`
- 新機能・新Viewは最初から機能別フォルダに分ける(1ファイルに詰め込まない)
- **1つの画面フロー(対戦)のViewは1フォルダにまとめる**。入口が違っても遷移先が同じならフォルダを分けない
- **`GoogleService-Info.plist` はgit管理外**。`git pull` では届かず、`git add` しても無言で無視される(「コミットできない」と誤解されやすい)。受け渡しはファイルを直接送る(`FIREBASE_SETUP.md` §3)

## XcodeGen運用(重要)
- `.xcodeproj` は生成物。**pbxprojを直接編集しない**
- .swiftファイルやリソースを追加・削除したら `xcodegen generate`
- **`git pull` で相手がファイルを増減させていた場合も `xcodegen generate` が必要**(忘れるとビルドが落ちる)
- ターゲット設定の変更は `project.yml` を編集 → `xcodegen generate`
- 署名(`DEVELOPMENT_TEAM`)は `project.yml` に書かず `Config/local.xcconfig`(git管理外)で各自が指定。無くてもSimulatorビルドは通る

## 2人開発ルール(必須)
1. **着手前に `STATUS.md` の「作業中宣言」に記入**し、完了したら消して「最新更新」に結果を記録する
   - **STATUS.md の上限は150行**。超えたら「最新更新」の古い項目から `STATUS_ARCHIVE.md` へ移す(超過はフックが自動警告する)
   - 相手に見えるのはpushした時点から。長い作業・`Models/`や`project.yml`を触る作業は宣言だけ先にコミット&push
   - コミットの判断は人間が持つ。**Claudeは勝手にコミットしない**。pushされないまま作業が続く場合は宣言を残す
2. **同じファイルを同時に編集しない**。他の開発者が宣言中のファイルには触らない
3. 大きな変更(リネーム・ファイル移動・`project.yml`・SwiftDataモデル)は、事前に対象ファイルを明示して相手の合意を取る
4. `main` に直接コミットしてよいが、**作業開始前に必ず `git pull --rebase && xcodegen generate`**
5. コミットは `feat:` / `fix:` / `docs:` / `refactor:` / `test:` + 日本語要約。1コミット=1つの意味のある変更

## 担当分担
- **たける側(Claude含む)**:大枠のUI・対戦形式・ゲーム性。ドキュメント、Simulator検証、実機実行
- **TOKIYA-YAMAMOTO氏**:細かいUI(効果音・ボイス・単語データ拡充)、Firebaseプロジェクト本体
- Firebaseコンソールの設定をアプリ側の都合で勝手に前提変更しない。必要なら `STATUS.md` に依頼として書く

## ビルド・検証
```bash
cd /Users/n/HayaosiApp && xcodegen generate
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/n/HayaosiApp/HayaosiApp.xcodeproj -scheme HayaosiApp \
  -destination 'generic/platform=iOS Simulator' build
```
```bash
# ロジックを触ったらテストも回す(機種名は環境にあるものへ)
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/n/HayaosiApp/HayaosiApp.xcodeproj -scheme HayaosiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- **ビルドが通っただけで「できた」と報告しない。** 対戦・練習の画面を触ったら、Simulatorで1試合通す:対戦タブ →「ひとりで(CPU対戦)」→ ロビー → 対戦 → リザルト。対戦形式(文字送り型/即答型)は両方見る
- Simulator操作には `xcode-select` がXcode本体を指している必要がある(ビルドは `DEVELOPER_DIR` 指定で通るが操作ができない)
- 環境要因で確認できない場合は**「未検証」を STATUS.md と報告の両方に明記**する。黙って省略しない
- 実機実行・音や振動の確認・Firebaseコンソール操作・TestFlight配信は人間の担当
