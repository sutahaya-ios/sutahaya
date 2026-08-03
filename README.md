# HayaosiApp

勉強系早押し対戦iOSアプリ(仮称)。詳細は [要件定義書](要件定義書_勉強系早押し対戦アプリ.md) / [CLAUDE.md](CLAUDE.md) / [STATUS.md](STATUS.md) を参照。

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

通信対戦・フレンド機能を使う場合は [FIREBASE_SETUP.md](FIREBASE_SETUP.md) の手順で `GoogleService-Info.plist` を配置する(無くても一人練習・復習・ボット対戦はオフラインで動作する)。

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
