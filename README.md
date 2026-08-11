# スタはや(リポジトリ名:HayaosiApp)

勉強系早押し対戦iOSアプリ。App Storeでの表示名は「スタはや」、リポジトリ名・ターゲット名・Bundle IDは `HayaosiApp` のままです(変更するとApp Store上で別アプリ扱いになるため)。詳細は [要件定義書](要件定義書_勉強系早押し対戦アプリ.md) / [CLAUDE.md](CLAUDE.md) / [STATUS.md](STATUS.md) を参照。

## 前提

- macOS + Xcode 16以降(iOS 17以降がターゲット)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.38以降
- **`xcode-select` がXcode本体を指していること**。`xcode-select -p` が `/Library/Developer/CommandLineTools` を返す場合は切り替える(Simulatorの起動・操作ができない)

  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

## セットアップ(clone後に最初にやること)

`.xcodeproj` はgit管理外(XcodeGenで生成するため)。clone後は以下を実行:

```bash
cd HayaosiApp   # リポジトリのルート(project.yml がある階層。中の同名フォルダではない)
brew install xcodegen   # 未インストールの場合
xcodegen generate
open HayaosiApp.xcodeproj
```

**実機ビルドをする場合**は署名の設定が必要(Simulatorだけなら不要):

```bash
cp Config/local.xcconfig.sample Config/local.xcconfig
```

コピーした `Config/local.xcconfig` の `DEVELOPMENT_TEAM` を自分のチームIDに書き換える(Xcode → Settings → Accounts → チーム名の右の10桁)。このファイルはgit管理外なので、開発者ごとに別の値を持てる。

通信対戦・フレンド機能を使う場合は [FIREBASE_SETUP.md](FIREBASE_SETUP.md) の手順で `GoogleService-Info.plist` を配置する(無くても一人練習・復習・CPU対戦はオフラインで動作する)。

**このファイルはgit管理外なので `git pull` では降りてきません。** Firebase担当からファイルを直接受け取ってください(理由と手順は [FIREBASE_SETUP.md](FIREBASE_SETUP.md) §3)。

## GitHubの認証(初回のみ・pushできない場合)

このリポジトリは **非公開のOrganizationリポジトリ**(`saikyo-app-team/HayaosiApp`)。プライベートリポジトリでは**認証が通っていないと403ではなく404 `Repository not found` が返る**ため、「リポジトリが無い」と表示されて権限問題に見えるが、実際は認証の問題であることが多い。

GitHub CLI で認証するのが最短:

```bash
brew install gh
```

```bash
gh auth login
```

GitHub.com → **HTTPS** → ブラウザで認証(**このリポジトリに招待されている自分のアカウント**で)。続けて git 側の認証ヘルパーを設定する:

```bash
gh auth setup-git
```

権限があるかを、コミットせずに確認できる:

```bash
git push --dry-run
```

### それでも失敗する場合(エラー文で切り分け)

| エラー | 原因 | 対処 |
|---|---|---|
| `denied to <別のアカウント名>` | 別アカウントの資格情報が残っている | 下のコマンドで消してから再認証 |
| `Repository not found` | 未認証、またはURL違い | `git remote -v` を確認 → 再認証 |
| `Support for password authentication was removed` | パスワードで認証しようとしている | `gh auth login`、またはPAT(classic・`repo`スコープ) |
| `Permission denied (publickey)` | SSHだが鍵が未登録 | 下のSSH手順 |
| `! [rejected] main -> main (fetch first)` | 相手が先にpushしていて自分のローカルが遅れている(正常な挙動) | `git pull --rebase` してから push |
| **赤いエラーが出ず「変更なし」で終わる** | ファイルが `.gitignore` で除外されている | `git status --ignored` で確認。`GoogleService-Info.plist` は**意図的に管理外**([FIREBASE_SETUP.md](FIREBASE_SETUP.md) §3) |

古い資格情報を消す(macOS):

```bash
printf 'protocol=https\nhost=github.com\n\n' | git credential-osxkeychain erase
```

SSHに切り替える(トークンの期限切れがなく長期的に安定):

```bash
ssh-keygen -t ed25519 -C "github" && gh ssh-key add ~/.ssh/id_ed25519.pub && git remote set-url origin git@github.com:saikyo-app-team/HayaosiApp.git && ssh -T git@github.com
```

**Xcodeから push する場合は別管理**。Xcode → Settings → Accounts に自分のGitHubアカウントを追加する(パスワードではなく `repo` スコープ付きのPATを使う)。ターミナルで通っていてもXcode側は通らないので、ここで詰まる人が多い。

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

pushの通知が欲しい場合は、GitHubのリポジトリページ右上 Watch → **All Activity** にしておく。変更の意図・次のタスクは [STATUS.md](STATUS.md) に書く運用。

なお `git pull` を常にrebaseにしておくと、無駄なマージコミットが増えない(1回だけ設定):

```bash
git config pull.rebase true
```

## ビルド・テスト(Simulator)

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project HayaosiApp.xcodeproj -scheme HayaosiApp \
  -destination 'generic/platform=iOS Simulator' build
```

機種名は自分の環境にあるものに置き換える(一覧:`xcrun simctl list devices available`)。

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project HayaosiApp.xcodeproj -scheme HayaosiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## 開発ルール

2人開発のため [CLAUDE.md](CLAUDE.md) の「2人開発ルール」を必ず守ること(作業前に [STATUS.md](STATUS.md) へ宣言してpush、同一ファイル同時編集禁止)。
