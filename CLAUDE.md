# HayaosiApp プロジェクト設定

## プロジェクト概要
勉強系早押し対戦iOSアプリ **「マナビート」**(App Storeでの表示名)。要件は `要件定義書_勉強系早押し対戦アプリ.md`、最新の進捗は `STATUS.md` を参照。

**リポジトリ名・ターゲット名・Bundle ID(`com.n.HayaosiApp`)は `HayaosiApp` のまま**変更しない(App Store上で別アプリ扱いになるため。要件 §10 #1)。表示名だけが「マナビート」。

コンセプト:「勉強版みんはや」— 英単語・資格・SPIの勉強を、友達との早押し対戦で楽しく継続できるアプリ。

## 技術スタック
- iOSアプリ:Swift / SwiftUI、iOS 17+、SwiftData(学習履歴・復習リスト・ローカル問題データ)
- Firebase(SPM: firebase-ios-sdk 12+):匿名Auth / Realtime Database=ルーム同期・早押し判定 / Firestore=プロフィール・フレンド・招待
- **`GoogleService-Info.plist` は未コミット(人間作業)**。無くてもビルド・オフライン機能は動く。セットアップ手順は `FIREBASE_SETUP.md`

## ディレクトリ構成
フォルダの役割だけを規約にする(ファイル名の列挙は陳腐化するのでしない)。

```
/Users/n/HayaosiApp/
├── project.yml               # XcodeGen定義(ターゲット・ビルド設定はここが正)
├── Config/                   # ビルド設定ファイル(署名。local.xcconfigはgit管理外=各自の環境)
├── HayaosiApp.xcodeproj/     # 生成物。手編集禁止
├── HayaosiApp/
│   ├── App/                  # エントリポイント
│   ├── Models/               # SwiftDataモデル・enum
│   ├── Services/             # 出題エンジン・データ投入・結果記録などのロジック
│   │   ├── Battle/           # 対戦の共通部分(BattleSession / BattleRules)とボット対戦(ローカル)
│   │   └── Online/           # Firebase層(認証・フレンド・ルーム状態・対戦セッション)
│   ├── Views/<機能名>/        # 画面(Root=タブ / Home / Practice / Quiz / Review / Room / Battle / Friend / Settings / Components)
│   ├── Resources/            # 問題データJSON・効果音(Sounds/se_*.wav)・GoogleService-Info.plist(git管理外)
│   └── Assets.xcassets/      # 画像・色
├── Tests/                    # ユニットテスト(HayaosiAppTestsターゲット)
└── *.md                      # ドキュメント(要件定義書 / STATUS など)
```

配置ルール:
- データモデル → `Models/`、ロジック・共有状態 → `Services/`、UI → `Views/<機能名>/`
- 新機能・新Viewは最初から機能別フォルダに分ける(1ファイルに詰め込まない)
- 対戦ルールの定数(人数・得点・各制限時間)は `Services/Battle/BattleRules.swift` に集約する。**Firebaseに依存しないものを `Online/` に置かない**(ボット対戦はオフラインで完結する必要がある)
- 効果音は `Resources/Sounds/se_*.wav`。正弦波合成の自作(著作権フリー)で、**同名ファイルを差し替えれば音が変わる**(コード変更不要)

## XcodeGen運用(重要)
- `.xcodeproj` は生成物。**pbxprojを直接編集しない**
- .swiftファイルやリソースを追加・削除したら `xcodegen generate` を実行(フォルダ内のファイルは自動で取り込まれる)
- **`git pull` で相手が .swift やリソースを増減させていた場合も `xcodegen generate` が必要**。忘れると「相手が追加したファイルがXcodeに現れない」「ビルドが落ちる」になる
- ターゲット設定の変更は `project.yml` を編集 → `xcodegen generate`
- **署名(`DEVELOPMENT_TEAM`)は `project.yml` に書かない**。開発者ごとに違うため `Config/local.xcconfig`(git管理外)で与える。手順は `README.md`。Simulatorビルドは署名不要なのでこのファイルが無くても動く

## コーディング規約(Swift)
- グローバルCLAUDE.mdの「コード品質」「書いてはいけないコード」を守る
- SwiftUIのモダンな書き方を使う(`@State`, `@Observable`, `@Query` など)
- force unwrap(`!`)禁止 → `guard let` / `if let` / `??` を使う
- `try?` でエラーを握りつぶさない(特に `modelContext.save()`)。失敗時は最低限ログを出す
- View は小さく分割する(1ファイル1Viewが理想)。body が長くなったら別 struct に抽出
- 命名は英語、コメントは日本語OK
- 出題エンジン(`QuizSession`)は練習・対戦で共通利用する。対戦固有の分岐を安易に入れず、通信層は分離して設計する
- マジックナンバーは定数化する。対戦ルールの数値は `BattleRules` が唯一の出典(UIの表示文にも直接書かない)

## テスト方針
- 対象は**ロジックのみ**:出題エンジン(`QuizSession`)・対戦進行(`BotBattleSession`)・データ投入(`QuestionSeeder`)。UIテストは書かない(費用対効果が低い)
- 置き場所は `Tests/`。ファイル名は `<対象>Tests.swift`
- 通信(`Services/Online/`)はFirebase実機依存なのでユニットテストの対象外。実機での通し確認で担保する
- ロジックを直したら、まずテストで再現 → 修正 の順で進める

## 2人開発ルール(必須)
1. **着手前に `STATUS.md` の「作業中宣言」に記入**(担当・対象ファイル・内容)する。完了したら宣言を消し「最新更新」に結果を記録する
   - **相手に見えるのはpushした時点から**なので、数時間以上かかる作業・`Models/`や`project.yml`を触る作業では、宣言だけを先にコミット&pushする
   - コミットの判断は人間が持つ。**Claudeは勝手にコミットしない**ため、pushされないまま作業が続くことがある。その場合は宣言を消さずに残し、コミット時にまとめて反映する(消してしまうと宣言が一度も共有されない)
2. **同じファイルを同時に編集しない**。他の開発者が宣言中のファイルには触らない
3. 大きな変更(リネーム・ファイル移動・`project.yml`変更・SwiftDataモデル変更)は、事前に編集対象ファイルを明示して相手の合意を取る
4. 競合しそうな場合は実装前に確認する
5. `Models/` と `project.yml` は影響範囲が広いので、特に事前宣言を徹底する

### ブランチ・コミット
- `main` に直接コミットしてよい(2人・小規模のため)。ただし**作業開始前に必ず `git pull --rebase && xcodegen generate` する**(自動では降りてこないので手で取る)
- 1コミット=1つの意味のある変更。コミットメッセージは `feat:` / `fix:` / `docs:` / `refactor:` / `test:` + 日本語の要約(例:`feat: 対戦画面に問題文の逐次表示を追加`)
- 相手の作業と衝突しそうな大きめの変更だけ `feat/<内容>` ブランチを切る

## 担当分担
- **たける側(Claude含む)**:iOSアプリのコード全般(`HayaosiApp/`)、ドキュメント、Simulator検証、実機実行
- **TOKIYA-YAMAMOTO氏**:Firebaseプロジェクト本体(コンソール設定・セキュリティルール・Cloud Functions)。詳細は `STATUS.md` の「次のタスク」
- Firebaseコンソールの設定値やセキュリティルールをアプリ側の都合で勝手に前提変更しない。必要な場合は `STATUS.md` に依頼として書く

## ビルド・検証の分担
- **Claude**:コード編集、`xcodegen generate`、Simulatorでのビルド・テスト・**実際に動かしての確認**まで
  ```bash
  cd /Users/n/HayaosiApp && xcodegen generate
  env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project /Users/n/HayaosiApp/HayaosiApp.xcodeproj -scheme HayaosiApp \
    -destination 'generic/platform=iOS Simulator' build
  ```
  ```bash
  # ロジックを触ったらテストも回す(機種名は環境にあるものへ。確認: xcrun simctl list devices available)
  env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project /Users/n/HayaosiApp/HayaosiApp.xcodeproj -scheme HayaosiApp \
    -destination 'platform=iOS Simulator,name=iPhone 17' test
  ```
- **人間**:実機実行、実機での音・振動の確認、Firebaseプロジェクト作成・コンソール操作、Archive・TestFlight配信

**ビルドが通っただけで「できた」と報告しない。** 対戦・練習の画面を触る変更は、Simulatorで起動して1試合通す(下記)ところまで確認する。

- Simulator操作には `xcode-select` がXcode本体を指している必要がある(`xcode-select -p` で確認。コマンドラインツールを指している場合、ビルドは `DEVELOPER_DIR` 指定で通るが**アプリの操作ができない**)
- 環境要因で動作確認ができない場合は、**「未検証」を `STATUS.md` と報告の両方に明記する**。黙って省略しない。何が確認できて何ができていないかを分けて書く

## 開発の進め方
- 現在フェーズ・最優先タスク・担当は **`STATUS.md` が正**(ここには書かない=二重管理を避ける)。スコープは要件定義書 §4
- **対戦画面の開発・検証はボット対戦を使う**(Firebase未設定でもオフラインで完結する)
  - ルームタブ → 「ボット対戦」→ 出題形式・問題数・制限時間・ボット数を設定 → ロビー → 対戦 → リザルト、まで1試合通せる
  - **出題形式(速答型/文字送り型)を切り替えて両方見る**。文字送り型は制限時間を長め(20〜30秒)にすると表示の進み方が観察しやすい。速答型なら制限時間10秒・問題数5・ボット1体が最速
  - 現状ボットは問題文の表示量に関係なく1〜7秒で押すため、文字送り型では人間が押す前に取られやすい(調整はSTATUSの次のタスク)
  - フレンド・ルームタブはFirebase未設定時はサンプルデータで表示される(「サンプル表示中」バナー付き)
- 変更したら `STATUS.md` に記録する(開発者間の共有台帳)
