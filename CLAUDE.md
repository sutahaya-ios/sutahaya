# HayaosiApp 開発ルール

勉強系早押し対戦iOSアプリ **「スタはや」**(App Storeでの表示名)。

**このファイルはルールだけを置く。** 手順・現状・構成の説明は書かず、下の表の行き先へ移す。

| 知りたいこと | 読むファイル |
|---|---|
| 何を作るか・なぜそう決めたか | `要件定義書_勉強系早押し対戦アプリ.md` |
| 進捗・作業中宣言・実装詳細の決定 | `STATUS.md`(完了分は `STATUS_ARCHIVE.md`) |
| 機能から関連ファイルを探す | `docs/MODULE_MAP.md` |
| Swiftの規約・命名・テスト方針・ビルド/テストコマンド・ディレクトリ構成 | `docs/CODING.md` |
| clone後のセットアップ・署名・push認証 | `docs/DEVELOPMENT.md` |
| Firebaseの設定・データ構造・セキュリティルール | `FIREBASE_SETUP.md` |

このファイルはリポジトリを初めて扱うとき、または更新されたときに確認する。通常タスクごとに運用文書一式を読み直さない。

**標準リポジトリパス:** `/Users/yamahontomarenari/Documents/GitHub/HayaosiApp`

このパスが利用可能な間は、プロジェクト一覧・`Documents/GitHub`・iCloud Driveを再探索しない。実際に利用不能になった場合だけ保存場所を確認する。

## 通常タスクの標準フロー

1. ユーザーの指示と下記の常時禁止事項を確認する
2. 指定された対象ファイルを直接確認する
3. 編集する場合のみ、必要に応じて `STATUS.md` の該当部分と `git status --short` を確認する
4. 最小差分で実装する
5. 変更対象だけ `git diff -- <対象ファイル>` で確認し、リスクに応じた最小検証を1回実施する

上記以外を標準工程にしない。`STATUS.md` は競合確認・作業中宣言が必要な編集時だけ該当部分を読み、全文再読しない。読み取り・質問・説明では原則読まない。`docs/MODULE_MAP.md` は対象の場所が分からない場合だけ、`docs/CODING.md` はSwift実装上の規約確認が必要な場合だけ使う。README、要件・設計文書も依頼に直接必要な場合だけ読む。

## 作業レベルと検証

- **FAST**:UI・文言・軽いデータ変更。直接関係するファイルだけ確認する。原則としてpreflight・finish-task・Test・全体探索・無関係な文書確認は行わず、対象diffと必要な場合だけ最終表示を確認する
- **NORMAL**:通常の機能追加・ローカルロジック変更。関連ファイルと直接依存を確認し、必要な関連テストまたはbuildを完成後に1回行う
- **STRICT**:Firebase/Auth/Rules/通信対戦/SwiftData schema/`project.yml`。必要範囲を広めに確認し、関連テストを十分に行う。影響範囲が広い場合だけ全テストを行う
- 指定がなければ作業者が内部で簡潔に分類し、通常は分類報告を独立工程にしない。実装途中に全テストを繰り返さず、完成後に必要分だけ実行し、失敗箇所だけ修正・再実行する
- `scripts/verify.sh` は必要な検証をまとめたい場合の補助。`scripts/finish-task.sh` はcommit準備・push前確認・他開発者への引き渡し・大規模タスク・ユーザー指定時だけ使う

説明・調査・文書・文言・コンパイルへ影響しない軽微UIは、原則Build/Test不要。通常Swiftロジックは必要に応じて関連Build/Test、Firebase transaction・対戦同期・Security・Auth・`project.yml`は十分に検証する。同じBuild/Testを結果が変わる根拠なく繰り返さない。

## Firebase変更の再発防止

- Firebase機能を変更する前に、実際の処理チェーンを明示する。例:`Firestore claim → RTDB read → RTDB join → Firestore finalize`
- 「参加できない」等の複数段階処理では、原因判定より先に失敗段階を特定する。最低限、Firebase product、operation、path、error codeを区別して記録する
- 同じ画面・同じユーザー向けエラーでも原因が同じとは仮定せず、段階ごとのログと実データで判定する
- 処理チェーンの各段階について、失敗、部分成功、retry、timeout、idempotency(同じ操作を繰り返しても結果が壊れない性質)を確認する
- Rulesとの契約は設計上のschemaだけで判断せず、Swift SDKが実際に送信するpath・payload・操作単位を正として照合する
- バグAの調査中に別のバグBを発見して修正しても、バグAはOPENのままとする。B修正後は必ずAの元の再現手順へ戻る
- 修正後は新規テストだけでなく、最初に報告された元症状の再現手順を最新ビルドで再実行する。Unit Test、Emulator、Build、deploy成功だけでは元Issueを完了扱いにしない
- 最終判定は、元のユーザー操作を最新ビルドで入口から結果までend-to-end成功させた結果で行う。未実施なら「修正実装済み・元症状未確認」とし、Issueを閉じない
- FirestoreとRTDBなど複数DBを跨ぐ操作は、片方だけ成功した部分成功状態を列挙し、rollback・cleanup・再実行のいずれかで安全に回復できることを必須とする

## 常時禁止事項

- 他人・ユーザーの未コミット変更を破壊、上書き、削除しない
- 他担当者が作業中と宣言している対象を勝手に編集しない
- Bundle ID / Signing / Team / Certificateを勝手に変更しない
- `project.yml`を正とし、生成された`.xcodeproj`を恒久編集しない
- Firebase本番環境 / Security Rulesを必要な確認なしに変更しない
- 新規依存を事前確認なく追加しない
- commit / push / mergeはユーザーが明示した場合だけ行う
- 秘密情報・git管理外のローカル設定をGitへ追加しない
- 編集した対象のdiffを最低1回確認する

これらは毎回調査するチェックリストではなく、常時守る禁止条件として扱う。

## 変えてはいけないもの

- **ターゲット名・共有設定の本番Bundle ID `com.n.HayaosiApp`**(App Store上で別アプリ扱いになる。リポジトリ名 `sutahaya` とは一致しないが、これは意図的)。共同開発者の実機検証に限り、git管理外の `Config/local.xcconfig` で開発用Bundle IDへ上書きしてよい。開発用の値を `project.yml` や共有ファイルへcommitしない
- **`.xcodeproj`**:XcodeGenの生成物で **git管理外**(コンフリクトしない)。手編集しない。ファイル・リソースを増減したら `xcodegen generate`。**`git pull` の後も必要**(忘れるとビルドが落ちる)
- **`GoogleService-Info.plist` / `Config/local.xcconfig`**:git管理外。`git add` しても無言で無視される。各自の実効Bundle IDに対応するFirebase plistと署名設定を置き、相手の値を共有ファイルへ転記しない(`FIREBASE_SETUP.md` §3)

## Git

- 通常の編集は開始時の `git status --short` と終了時の対象ファイルdiffだけでよい。読み取り・質問・説明ではgit確認も原則不要
- `scripts/preflight.sh` は push / pull / merge / rebase / branch操作 / origin同期、共有ファイルの競合可能性が高い作業、Firebase本番・Rules・`project.yml`・Signing / Bundle ID等のSTRICT作業だけに使う。通常タスクで `git fetch` しない
- `git fetch`、origin/main確認、mainとの差分、`git log`、全リポジトリdiff、branch履歴、過去commit探索は必要な場合だけ行う
- **`main` へ直接コミットする。ブランチは使わない**(担当が分かれていて衝突が起きにくいため。App Store申請と並行開発が始まったら見直す)
- コミットは `feat:` / `fix:` / `docs:` / `refactor:` / `test:` + 日本語要約。1コミット=1つの意味のある変更
- **コミット・pushの判断は人間が持つ。Claudeは勝手にコミットしない**
- **このリポジトリは公開されている。** 秘密情報、Team ID、他人の個人情報を新たに書き込まない
- コンフリクトしたら相手の変更を消さない。特に単語データJSONは**両者の追加語を残して**マージする(消えても気付きにくい)

## 2人開発ルール(必須)

1. 長い作業、競合可能性が高い共有ファイル、STRICT・大きな変更では、着手前に `STATUS.md` の「作業中宣言」の該当部分を確認して記入する。局所的なFAST変更や読み取り作業では不要
   - 相手に見えるのはpushしてから。長い作業は**宣言だけ先にpush**する
   - **STATUS.md は150行まで**。超えたら古い項目から `STATUS_ARCHIVE.md` へ移す(フックが警告する)
2. **宣言中のファイルは触らない**(同じファイルを同時に編集しない)
3. 大きな変更(SwiftDataモデル・`project.yml`・リネーム・ファイル移動)は、**対象ファイルを列挙してSTATUS.mdに宣言し、相手の返事を待ってから着手**する
4. バックエンド(Firebase / Auth / DB / セキュリティルール / Cloud Functions)は担当を越えて前提や実装を変えない。必要なことは `STATUS.md` に依頼として書く
5. **担当分担の正は `STATUS.md`**(変動するのでここには書かない)

## 完了の定義

- **ビルドが通っただけで「できた」と報告しない**
- 作業レベルに応じて必要最小限の検証を1回行う。FASTの見た目調整でBuild・対戦1試合・全テストを標準化しない
- 対戦・練習の画面運用や進行を変えたNORMAL/STRICTは、Simulatorで必要な経路を確認する。通信対戦の実機固有部分は未検証と明記する
- ロジックを触ったら関連テストを回す(コマンドは `docs/CODING.md`)
- 環境要因で確認できなかったら、**「未検証」をSTATUS.mdと報告の両方に明記**する。黙って省略しない
- 実機実行・音や振動の確認・Firebaseコンソール操作・TestFlight配信は**人間の担当**

### Simulator確認時のスクリーンショット(トークン節約)

- **タップ先を探す目的では撮らない**。座標の特定はアクセシビリティツリー(read_page/find等)を使う
- **見た目の変更を伴うときだけ、最終状態を撮る(上限2枚:結果1枚+異常系があれば1枚)**。途中経過は撮らない
- **ロジックのみの変更(表示に関わらない)では撮らない**。ビルドとテストで完了とする
- **複数試合を通しで確認するような重い検証**(CPU対戦を10問完走 等)は、実装側が「ここまで実装した、通しで見てください」で止め、**確認はたけるが自分のSimulatorで行う**

## 置き場所のルール

- データモデル → `Models/` / ロジック・共有状態 → `Services/` / UI → `Views/<機能名>/`
- `Services/Battle/` はFirebase非依存を保つ(CPU対戦がオフラインで完結するため)。Firebase依存は `Services/Online/` へ
- **1つの画面フロー(対戦)のViewは1フォルダにまとめる**。入口が違っても遷移先が同じならフォルダを分けない
- 新機能は最初から機能別フォルダに分ける(1ファイルに詰め込まない)
