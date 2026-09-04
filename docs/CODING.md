# コーディング規約・ナレッジ(Swift実装上の規約確認が必要なときに読む)

CLAUDE.md には守るべきルールだけを置き、コードを書くときの規約と手順はこのファイルに集約している。

## ディレクトリ構成

フォルダの役割だけを規約にする(ファイル名の列挙は陳腐化するのでしない)。

```
├── project.yml               # XcodeGen定義(ターゲット・ビルド設定はここが正)
├── Config/                   # 署名設定(local.xcconfigはgit管理外=各自の環境)
├── HayaosiApp.xcodeproj/     # 生成物。手編集禁止・git管理外
├── HayaosiApp/
│   ├── App/                  # エントリポイント
│   ├── Models/               # SwiftDataモデル・enum
│   ├── Services/             # ロジック(出題エンジン・集計・データ投入など)
│   │   ├── Battle/           # 対戦の共通部分(Firebase非依存)とCPU対戦
│   │   └── Online/           # Firebase層(認証・フレンド・ルーム状態・対戦セッション)
│   ├── Views/<機能名>/        # 画面(機能ごとにフォルダを分ける)
│   ├── Resources/            # 単語データJSON・効果音・GoogleService-Info.plist(git管理外)
│   └── Assets.xcassets/
├── word_bank/                # 作業用xlsx(git管理外)・単語JSON変換ツール
├── Tests/                    # ユニットテスト(ロジックのみ)
└── docs/                     # 随時読み込むナレッジ(このファイルなど)
```

配置のルールは CLAUDE.md「置き場所のルール」が正。

## ビルド・テスト

リポジトリのルートで実行する。

検証が必要なNORMAL / STRICT作業では、必要に応じて次を使う。FASTでは標準実行しない。

```bash
scripts/verify.sh NORMAL --only-testing HayaosiAppTests/QuizSessionTests
scripts/verify.sh STRICT
```

- FASTは対象diffだけで終えてよい。コンパイルや表示確認が必要なときだけ個別に実行する
- NORMALは対象テストを `--only-testing`で指定する。関連ユニットテストが存在しない場合だけ `--no-tests` を明示する
- STRICTは指定がなければSwiftの全テストを行う。Rules差分がある場合はFirebase Emulatorテストも行う
- ファイル増減・`project.yml`変更・pull後は、先に `xcodegen generate` を行う(`verify.sh --xcodegen` でも可)
- 実装途中に全テストを繰り返さない。実装完成後に必要分を実行し、失敗した対象だけ再実行する
- 使い方の確認は `scripts/verify.sh --help`。`scripts/finish-task.sh` はcommit準備・push前確認・他開発者への引き渡し・大規模タスク・ユーザー指定時だけ使う

個別の原因調査やスクリプトが使えない場合の直接コマンド:

```bash
xcodegen generate && env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project HayaosiApp.xcodeproj -scheme HayaosiApp -destination 'generic/platform=iOS Simulator' build
```

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project HayaosiApp.xcodeproj -scheme HayaosiApp -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- 機種名は環境によって違う。`xcrun simctl list devices available` で確認する。**一覧にあっても xcodebuild が解決できない機種がある**(古いランタイムの端末)ので、失敗したら新しい機種で試す
- Simulatorの操作には `xcode-select` がXcode本体を指している必要がある(ビルドは `DEVELOPER_DIR` 指定で通るが操作はできない)

## Swift規約

- グローバルCLAUDE.mdの「コード品質」「書いてはいけないコード」を守る
- SwiftUIのモダンな書き方を使う(`@State`, `@Observable`, `@Query` など)
- force unwrap(`!`)禁止 → `guard let` / `if let` / `??` を使う
- `try?` でエラーを握りつぶさない(特に `modelContext.save()`)。失敗時は最低限ログを出す
- View は小さく分割する(1ファイル1Viewが理想)。body が長くなったら別 struct に抽出
- 命名は英語、コメントは日本語OK。コメントは「意図・制約・なぜそうしたか」だけを書く
- マジックナンバーは定数化する。ただし**やりすぎない**:`":"` や `"\n"` のような自明な文字列まで定数にすると逆に読みにくい。定数にするのは「後から調整したい値」「複数箇所で使う値」だけ
- 対戦ルールの数値は `Services/Battle/BattleRules.swift`、文字送りの間隔は `ProgressiveReveal.characterInterval` が唯一の出典(UIの表示文にも直接書かない)

## 命名の規約

- **View名は役割で付ける。通信の有無を名前に入れない**(共用Viewに `Online` を付けると、CPU対戦でも使われた時に名前が嘘になる。オンライン専用が本質のもの=`OnlineBattleSession` 等は除く)
- **UIに出す言葉とコード内の名前を一致させる**(UIが「CPU」ならコードも `CPU`)。表示だけ変換するシムは移行期の一時措置とし、恒久化しない
- **用語やUI構成を変えたら、同じ作業の中でコード名・フォルダ・ドキュメント・コメントを追従させる**。片方だけ変えると二重語彙になり、以後すべての検索が二度手間になる

## アーキテクチャの意図

- 出題エンジン(`QuizSession`)は練習・対戦で共通利用する。対戦固有の分岐を安易に入れず、通信層は分離して設計する
- `Services/Battle/` はFirebase非依存を保つ(CPU対戦はオフラインで完結する必要がある)。**Firebaseに依存しないものを `Services/Online/` に置かない**

## テスト方針

- 対象は**ロジックのみ**:出題エンジン(`QuizSession`)・対戦進行(`CPUBattleSession`)・集計・データ投入(`QuestionSeeder`)。UIテストは書かない(費用対効果が低い)
- 置き場所は `Tests/`。ファイル名は `<対象>Tests.swift`
- 通信(`Services/Online/`)はFirebase実機依存なのでユニットテストの対象外。実機での通し確認で担保する
- ロジックを直したら、まずテストで再現 → 修正 の順で進める

## リソースのナレッジ

- 効果音は `Resources/Sounds/se_*.wav`。正弦波合成の自作(著作権フリー)で、**同名ファイルを差し替えれば音が変わる**(コード変更不要)
- 問題データを更新したら `QuestionSeeder.dataVersion` を上げる(次回起動時に再投入される)
- **英単語を増やす手順**:`word_bank/`の担当xlsxへ追記し、`python3 word_bank/word_bank_to_json.py`で確認後に`--write`でJSONへ反映し、`QuestionSeeder.dataVersion`を上げる。
  - 必須項目は `id` / `word` / `meaning` / `pos` / `difficulty`。難易度は整数の1〜5にする。**カテゴリはJSONに持たせない**(ファイル名で決まるため、読み込み時に付与する)
  - IDは中学=`jh_####`、高校ターゲット1200=`hs1_####`、1400=`hs2_####`、1900=`hs3_####`、TOEIC銀のフレーズ=`tc1_####`、金のフレーズ=`tc2_####`。同じカテゴリ内ではIDと単語(大文字小文字を無視)を重複させない。カテゴリをまたぐ同じ単語は登録してよい
  - 品詞は `PartOfSpeech` の8種のみ(動詞 / 名詞 / 形容詞 / 副詞 / 代名詞 / 接続詞 / 前置詞 / 助動詞)。誤答グループは動詞・名詞・形容詞・副詞を個別にし、少数の代名詞・接続詞・前置詞・助動詞だけを共通化する
  - 4択の誤答を同じグループから3語選ぶため、使用する誤答グループは全カテゴリを通して4語以上登録する
- SwiftDataモデル(`Models/`)にプロパティを足すときは Optional かデフォルト値付きにし、**アプリを削除せず上書きインストールで移行を確認する**(ユーザーの学習履歴が飛ぶ事故を防ぐ)
