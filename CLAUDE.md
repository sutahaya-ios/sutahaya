# HayaosiApp プロジェクト設定

## プロジェクト概要
勉強系早押し対戦iOSアプリ(名称未定・仮称HayaosiApp)。要件は `要件定義書_勉強系早押し対戦アプリ.md`、最新の進捗は `STATUS.md` を参照。

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
├── HayaosiApp.xcodeproj/     # 生成物。手編集禁止
├── HayaosiApp/
│   ├── App/                  # エントリポイント
│   ├── Models/               # SwiftDataモデル・enum
│   ├── Services/             # 出題エンジン・データ投入・結果記録などのロジック
│   │   └── Online/           # Firebase層(認証・フレンド・ルーム状態・対戦セッション)
│   ├── Views/<機能名>/        # 画面(Root=タブ / Home / Practice / Quiz / Review / Room / Battle / Friend / Settings / Components)
│   ├── Resources/            # 問題データJSON・GoogleService-Info.plist(git管理外)
│   └── Assets.xcassets/      # 画像・色
└── *.md                      # ドキュメント(要件定義書 / STATUS など)
```

配置ルール:
- データモデル → `Models/`、ロジック・共有状態 → `Services/`、UI → `Views/<機能名>/`
- 新機能・新Viewは最初から機能別フォルダに分ける(1ファイルに詰め込まない)

## XcodeGen運用(重要)
- `.xcodeproj` は生成物。**pbxprojを直接編集しない**
- .swiftファイルやリソースを追加・削除したら `xcodegen generate` を実行(フォルダ内のファイルは自動で取り込まれる)
- ターゲット設定の変更は `project.yml` を編集 → `xcodegen generate`

## コーディング規約(Swift)
- グローバルCLAUDE.mdの「コード品質」「書いてはいけないコード」を守る
- SwiftUIのモダンな書き方を使う(`@State`, `@Observable`, `@Query` など)
- force unwrap(`!`)禁止 → `guard let` / `if let` / `??` を使う
- `try?` でエラーを握りつぶさない(特に `modelContext.save()`)。失敗時は最低限ログを出す
- View は小さく分割する(1ファイル1Viewが理想)。body が長くなったら別 struct に抽出
- 命名は英語、コメントは日本語OK
- 出題エンジン(`QuizSession`)は練習・対戦で共通利用する。対戦固有の分岐を安易に入れず、通信層は分離して設計する

## 2人開発ルール(必須)
1. **着手前に `STATUS.md` の「作業中宣言」に記入**(担当・対象ファイル・内容)。完了したら宣言を消し「最新更新」に結果を記録する
2. **同じファイルを同時に編集しない**。他の開発者が宣言中のファイルには触らない
3. 大きな変更(リネーム・ファイル移動・`project.yml`変更・SwiftDataモデル変更)は、事前に編集対象ファイルを明示して相手の合意を取る
4. 競合しそうな場合は実装前に確認する
5. `Models/` と `project.yml` は影響範囲が広いので、特に事前宣言を徹底する

## ビルド・検証の分担
- **Claude**:コード編集、`xcodegen generate`、Simulatorビルド検証まで
  ```bash
  cd /Users/n/HayaosiApp && xcodegen generate
  env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project /Users/n/HayaosiApp/HayaosiApp.xcodeproj -scheme HayaosiApp \
    -destination 'generic/platform=iOS Simulator' build
  ```
- **人間**:実機実行、Firebaseプロジェクト作成・コンソール操作、Archive・TestFlight配信

## 開発の進め方
- 現在フェーズ:v1.0(通信対戦)実装済み・**実機検証待ち**。スコープは要件定義書 §4 を参照
- 最優先タスク:Firebaseセットアップ(`FIREBASE_SETUP.md`)→ 実機2台での早押し検証(技術検証スパイク)
- 変更したら `STATUS.md` に記録する(開発者間の共有台帳)
