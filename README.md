# HayaosiApp

勉強系早押し対戦iOSアプリ(仮称)。詳細は [要件定義書](要件定義書_勉強系早押し対戦アプリ.md) / [CLAUDE.md](CLAUDE.md) / [STATUS.md](STATUS.md) を参照。

## セットアップ(clone後に最初にやること)

`.xcodeproj` はgit管理外(XcodeGenで生成するため)。clone後は以下を実行:

```bash
brew install xcodegen   # 未インストールの場合
cd HayaosiApp
xcodegen generate
open HayaosiApp.xcodeproj
```

通信対戦・フレンド機能を使う場合は [FIREBASE_SETUP.md](FIREBASE_SETUP.md) の手順で `GoogleService-Info.plist` を配置する(無くても一人練習・復習はオフラインで動作する)。

## ビルド確認(Simulator)

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project HayaosiApp.xcodeproj -scheme HayaosiApp \
  -destination 'generic/platform=iOS Simulator' build
```

## 開発ルール

2人開発のため [CLAUDE.md](CLAUDE.md) の「2人開発ルール」を必ず守ること(作業前に [STATUS.md](STATUS.md) へ宣言、同一ファイル同時編集禁止)。
