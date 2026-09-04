# HayaosiApp プロジェクトコンテキスト

最終整理日: 2026-09-05

この文書は、長期間のCodex会話に蓄積していたプロジェクト前提をGitHub上へ引き継ぐための共通入口である。詳細構造は `ARCHITECTURE.md`、設計判断と廃止方針は `DECISIONS.md`、担当領域は `WORKSTREAMS.md` を参照する。

## プロダクト

- App Store表示名: **スタはや**
- 目的: 英単語等の学習を、文字送り型の早押し対戦と一人学習で継続しやすくする
- 対応OS: iOS 17以上
- 主要タブ: 対戦 / 学習 / マイページ
- 公開主体: たける側の有料Apple Developer Individual Team

## 技術構成

- UI: SwiftUI
- ローカル永続化: SwiftData
- 状態管理: Observationを中心としたSwiftの状態管理
- プロジェクト生成: XcodeGen
- バックエンド: Firebase Authentication / Cloud Firestore / Realtime Database / Cloud Functions
- 収益化: Google Mobile Ads / StoreKitサブスクリプション
- テスト: Swiftのロジックテスト、Firebase Security RulesのEmulatorテスト、通信機能の実機確認

## Apple DeveloperとBundle ID

- 本番Bundle IDは `com.n.HayaosiApp`
- 本番Team IDは `LL98RL72H4`
- 本番Archive、TestFlight、App Store公開は、たける側の有料Individual Teamから行う
- トキヤ側はPersonal Teamと開発用Bundle IDを使用する
- 開発者固有のBundle IDとTeamは、git管理外の `Config/local.xcconfig` で上書きする
- `.xcodeproj`はXcodeGen生成物であり、恒久編集しない
- `project.yml`を共有プロジェクト設定の正とする

この分離を採用した理由は、Apple Developer ProgramのIndividual Teamでは共同開発者をチームメンバーとして招待できないためである。2人が同じSigningを共有する方式、秘密鍵を共有する方式、CSRから代表者が証明書を発行する方式は採用しない。

過去にトキヤ側のPersonal Teamで本番Bundle IDを実機署名し、Apple側でBundle ID予約の衝突が起きた。本番Bundle IDをPersonal Teamで再署名・再登録してはならない。

## Firebase構成

- Firebase Project IDは `hayaosiapp`
- 本番Bundle IDと開発用Bundle IDは、同じFirebase Project内の別iOS Appとして登録する
- 各開発者は実効Bundle IDに対応した `GoogleService-Info.plist` を使用する
- `GoogleService-Info.plist`はgit管理外であり、共有・上書きしない
- Realtime Databaseを使うplistには `DATABASE_URL` が必要
- Bundle IDが異なっていても同じFirebaseリソースを使うため、2台の実機間で通信対戦できる

Firebaseの役割分担:

- Authentication: 匿名サインイン
- Firestore: プロフィール、フレンドコード、申請、フレンド、招待
- Realtime Database: ルーム、参加者、問題、回答、得点、対戦進行
- Cloud Functions: hostの真正性を検証したルーム招待作成。サーバー採点・問題秘匿化は将来候補

Firebase設定が存在しない場合も、CPU対戦とローカル学習は動作できる設計を維持する。

## 現在の担当範囲

最新の担当体制は次のとおり。過去の担当記録と衝突する場合はこちらを優先する。

- トキヤ: 対戦タブUI
- トキヤ: Firebase
- トキヤ: Security
- トキヤ: Debug / 実機検証
- 00 Architectureスレッド: 全体設計、領域横断判断、仕様衝突の整理、リリース判断の補助

UI全般を一律に別担当とみなさない。少なくとも**対戦タブUIはトキヤ担当**である。

## 絶対に守る制約

- 他人・ユーザーの未コミット差分を破壊、上書き、削除しない
- 他担当者が作業中と宣言している対象を勝手に編集しない
- 本番Bundle ID、Signing、Team、Certificateを勝手に変更しない
- `project.yml`を正とし、生成された`.xcodeproj`を恒久編集しない
- 開発者固有のBundle ID、Team、Firebase plistを共有ファイルへ書かない
- Firebase本番環境やSecurity Rulesを、影響確認なしに変更しない
- 新規依存を事前確認なく追加しない
- commit / push / mergeはユーザーが明示した場合だけ行う
- APIキー、秘密鍵、認証情報、ローカル設定をGitへ追加しない
- CPU対戦がFirebaseなしで完結する境界を壊さない

これらは毎タスク調査する項目ではなく、常時守る禁止条件である。

## Codexの共通原則

1. ユーザーの最新指示と常時禁止事項を確認する
2. 指定された対象ファイルを直接確認する
3. 必要な場合だけSTATUSの該当部分と短いGit状態を確認する
4. 最小差分で作業する
5. 変更対象のdiffと、リスクに応じた最小検証を1回行う

読み取り・質問・説明では、STATUS全文、MODULE_MAP、README、要件定義、Git状態を無条件に確認しない。STRICT作業、Git同期、競合可能性が高い共有ファイルだけ安全確認を広げる。

## 現在の主な保留事項

- 3人・3台での通信対戦完走確認
- ホストの一時切断と本当の退出を正しく区別できるかの実機確認
- Cloud Functionsによるサーバー採点・問題秘匿化
- 使用済みRTDBルームの自動削除
- ルーム満員判定の原子化
- App Checkの導入時期
- App Store ConnectのSupport URL、カテゴリ、コンテンツ権利、スクリーンショット等の最終確認
- App Store公開URL確定後のアプリ内リンク更新

## 情報の優先順位

1. ユーザーの最新の明示指示
2. この文書、`DECISIONS.md`、`WORKSTREAMS.md`
3. `STATUS.md`の最新状態・作業中宣言
4. 現行コードと `project.yml` の実装詳細
5. 旧要件定義や過去会話

判断不能な食い違いは、旧文書へ合わせて変更せず「要確認」として00 Architectureへ戻す。

## この文書の限界

この初版は、巨大Codexスレッドから救出済みの情報だけで作成した。作成時にリポジトリ全体監査、最新mainとの比較、Build、Testは行っていない。ローカル未コミット差分やSTATUSとの食い違いは、各作業の必要範囲で確認する。
