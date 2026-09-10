# 開発環境のセットアップ

このリポジトリで実際に開発する人向けの手順書。アプリの概要と設計は [README](../README.md) を参照。

## 前提

- macOS + Xcode 16以降(iOS 17以降がターゲット)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.38以降
- **`xcode-select` がXcode本体を指していること**。`xcode-select -p` が `/Library/Developer/CommandLineTools` を返す場合は切り替える(Simulatorの起動・操作ができない)

  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

## clone後に最初にやること

`.xcodeproj` はgit管理外(XcodeGenで生成するため)。clone後は以下を実行:

```bash
cd sutahaya   # リポジトリのルート(project.yml がある階層。中の同名フォルダではない)
brew install xcodegen   # 未インストールの場合
xcodegen generate
open HayaosiApp.xcodeproj
```

Simulatorで動かすだけならここまでで完了する(一人練習・復習・CPU対戦はオフラインで動作する)。

## 署名(実機ビルドをする場合)

```bash
cp Config/local.xcconfig.sample Config/local.xcconfig
```

コピーした `Config/local.xcconfig` はgit管理外なので、開発者ごとに別の値を持てる。

- **代表者(本番・リリース担当):** 自分の `DEVELOPMENT_TEAM` だけを設定する。Bundle IDは共有の既定値のまま
- **共同開発者(Personal Teamで実機検証):** 自分の `DEVELOPMENT_TEAM` に加え、Firebaseへ登録した開発用Bundle IDを `APP_BUNDLE_IDENTIFIER = <本番Bundle ID>.dev.<名前>` のように設定する

チームIDは Xcode → Settings → Accounts → チーム名の右側(10桁)で確認する。開発用Bundle IDは本番用と別のアプリとして署名されるが、同じFirebaseプロジェクトへ登録すれば2台の通信対戦に同じAuth・Firestore・Realtime Databaseを使用できる。

Apple Developer ProgramのIndividual Teamは共同開発者をチームメンバーとして招待できないため、この「開発者ごとにBundle IDを分ける」方式を採っている。背景は [docs/DECISIONS.md](DECISIONS.md)。

## Firebase

通信対戦・フレンド機能を使う場合は [FIREBASE_SETUP.md](../FIREBASE_SETUP.md) の手順で `GoogleService-Info.plist` を配置する。

**このファイルはgit管理外なので `git pull` では降りてきません。** 各自が実効Bundle IDに一致するplistを配置する。代表者用と共同開発者用を取り違えるとFirebase初期化に失敗する(理由と手順は [FIREBASE_SETUP.md](../FIREBASE_SETUP.md) §3)。

## ビルド・テスト(Simulator)

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project HayaosiApp.xcodeproj -scheme HayaosiApp \
  -destination 'generic/platform=iOS Simulator' build
```

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project HayaosiApp.xcodeproj -scheme HayaosiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

機種名は自分の環境にあるものに置き換える(一覧:`xcrun simctl list devices available`)。

Firebase Security RulesのテストはEmulatorで実行する:

```bash
npm install && npm test
```

## 日々の作業(相手の変更を取り込む)

**自動では降りてこない。** 作業を始める前に自分で取り込む:

```bash
git pull --rebase && xcodegen generate
```

`.xcodeproj` はgit管理外なので、相手が `.swift` やリソースを追加・削除していた場合は `xcodegen generate` まで必要(忘れると「追加されたファイルがXcodeに出てこない」「ビルドが落ちる」)。

相手が何を変えたかは次のコマンドで見る:

```bash
git fetch && git log --oneline --stat HEAD..origin/main
```

`git pull` を常にrebaseにしておくと、無駄なマージコミットが増えない(1回だけ設定):

```bash
git config pull.rebase true
```

## GitHubの認証(pushできない場合)

GitHub CLI で認証するのが最短:

```bash
brew install gh && gh auth login && gh auth setup-git
```

権限があるかを、コミットせずに確認できる:

```bash
git push --dry-run
```

### エラー文で切り分け

| エラー | 原因 | 対処 |
|---|---|---|
| `denied to <別のアカウント名>` | 別アカウントの資格情報が残っている | 下のコマンドで消してから再認証 |
| `Repository not found` | 未認証、またはURL違い | `git remote -v` を確認 → 再認証 |
| `Support for password authentication was removed` | パスワードで認証しようとしている | `gh auth login`、またはPAT(classic・`repo`スコープ) |
| `Permission denied (publickey)` | SSHだが鍵が未登録 | 下のSSH手順 |
| `! [rejected] main -> main (fetch first)` | 相手が先にpushしていて自分のローカルが遅れている(正常な挙動) | `git pull --rebase` してから push |
| **赤いエラーが出ず「変更なし」で終わる** | ファイルが `.gitignore` で除外されている | `git status --ignored` で確認。`GoogleService-Info.plist` は**意図的に管理外**([FIREBASE_SETUP.md](../FIREBASE_SETUP.md) §3) |

古い資格情報を消す(macOS):

```bash
printf 'protocol=https\nhost=github.com\n\n' | git credential-osxkeychain erase
```

SSHに切り替える(トークンの期限切れがなく長期的に安定):

```bash
ssh-keygen -t ed25519 -C "github" && gh ssh-key add ~/.ssh/id_ed25519.pub && git remote set-url origin git@github.com:sutahaya-ios/sutahaya.git && ssh -T git@github.com
```

**Xcodeから push する場合は別管理**。Xcode → Settings → Accounts に自分のGitHubアカウントを追加する(パスワードではなく `repo` スコープ付きのPATを使う)。ターミナルで通っていてもXcode側は通らない。

## 開発ルール

2人開発のため [CLAUDE.md](../CLAUDE.md) の「2人開発ルール」に従う(作業前に [STATUS.md](../STATUS.md) へ宣言してpush、同一ファイル同時編集禁止)。
