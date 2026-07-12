# HayaosiApp 開発ステータス

最終更新:2026年7月12日

現在フェーズ:**v1.0(通信対戦)クライアント実装済み・バックエンド未着手** — TOKIYA-YAMAMOTO氏がFirebaseバックエンド一式(コンソール設定→セキュリティルール→Cloud Functions)を担当

---

## 作業中宣言(着手前にここへ記入 → 完了したら消して「最新更新」へ)

| 担当 | 対象ファイル | 内容 | 開始日 |
|---|---|---|---|
| (なし) | | | |

---

## 最新更新(2026年7月12日)

- Claude(たける側): **フレンド・ルームタブのUI刷新**(UI構想3案から選定:フレンド=プロフィールカード型、ルーム=2大カード+招待バナー型)。
  - フレンドタブ:自分の「会員証」風プロフィールカード(アバター・ニックネーム・コード・コピー/シェアボタン)+フレンドのアバターグリッド(色はuidから決定的に選択)+破線「追加」タイル→コード入力シート。削除は長押しコンテキストメニュー
  - ルームタブ:フレンドからの招待をオレンジのバナーとして最上部に表示(参加/却下ボタン付き)。作成・参加カードは従来どおり
  - 新規ファイル:`Views/Components/AvatarCircle.swift` / `Views/Friend/FriendProfileCard.swift` / `Views/Friend/AddFriendSheet.swift`。Simulatorビルド成功。※Firebase未設定のため実表示確認はXcodeプレビュー(`#Preview`)または設定後に実施
- Claude: **GitHub化**。`saikyo-app-team` 組織にPrivateリポジトリ [HayaosiApp](https://github.com/saikyo-app-team/HayaosiApp) を作成しinitial commitをpush。`.xcodeproj`は引き続きgit管理外(XcodeGenで生成)のため、clone後の手順を`README.md`に追記。もう一人の開発者もこのリポジトリをcloneして参加できる状態
- Claude: **実機ビルドエラーを修正**。原因は署名チーム未設定(「Signing for "HayaosiApp" requires a development team」)。`project.yml` に `DEVELOPMENT_TEAM: LL98RL72H4`(Buffitoと同じチーム)を追加して再生成し、実機向けビルド(自動署名)成功を確認
- Claude: **タブバー化・フレンド機能・通信対戦を実装**。
  - **タブ構成**:`RootTabView` を新設し、ホーム(一人練習+成績サマリ)/ルーム/フレンド/復習/設定 の5タブに再編。旧スタブ(`LobbyView`・モック`BattleView`)は削除
  - **Firebase導入**:SPMで firebase-ios-sdk 12+(Auth / Database / Firestore)を追加。`GoogleService-Info.plist` が無くてもビルド・オフライン機能は動作し、オンライン系タブにはセットアップ案内を表示(`OnlineService.configureIfPossible`)。**人間作業の手順は `FIREBASE_SETUP.md`**
  - **フレンド機能**(`AuthService` / `FriendService`):匿名サインイン+6桁フレンドコード自動発行(users/{uid})、コード入力でフレンド追加(片方向)、一覧・削除、ロビーからのルーム招待送信と、ルームタブでの招待受信→参加
  - **通信対戦**(`OnlineBattleSession` + `+Host.swift` / `RoomState`):4桁コードのルーム作成・入室(2〜8人)、ロビー同期、早押しはRTDBトランザクションで先着1名を原子的に確定+押下順キュー保持、正解+1/不正解−1、誤答時は次の押下者へ回答権移行(全員誤答なら制限時間を仕切り直し)、出題タイムアウト、回答10秒制限、正解発表3秒→次問、リザルト(同点同順位)、ホストの再戦、切断時のonDisconnect処理(ホスト切断=ルーム解散)。進行の権威はホスト端末
  - **対戦結果の学習履歴反映**:自分が関与した問題の正誤を `AnswerRecord`(mode: battle)と復習リストへ保存
  - Simulatorビルド成功・起動確認済み(タブ表示・ホーム画面・問題データ100問)。**通信対戦の実動作は未検証(Firebase未設定のため)**

## 過去の更新(2026年7月12日・初期構築)

- Claude: プロジェクト初期構築。①開発ドキュメント(CLAUDE.md / AGENTS.md / STATUS.md)を作成 ②XcodeGen構成(`project.yml`、iOS 17+・iPhone専用・SwiftData)③v0.5の骨組みを実装:SwiftDataモデル(`Question` / `AnswerRecord` / `ReviewItem`)、出題エンジン`QuizSession`(練習・対戦共通。制限時間・正誤判定・フェーズ管理)、英単語100問(`Resources/english_words.json`。初回起動時に自動投入、誤答選択肢は同品詞の他単語から自動生成)、画面一式(ホーム/練習設定/出題/リザルト/復習リスト/設定)④v1.0用スタブ画面(ルーム作成・ルーム参加・待機ロビー・対戦UIモック。通信なし、「v1.0で実装予定」を画面に明記)。Simulatorビルド成功を確認済み

## 次のタスク(優先順)

### 担当:TOKIYA-YAMAMOTO — オンライン機能バックエンド一式

現状、iOSアプリ側(Swiftクライアント)からのFirebase連携コードは実装済み(`HayaosiApp/Services/Online/`)。
バックエンド側(Firebaseプロジェクト本体の設定・運用)が未着手のため、以下を担当してほしい。

1. **Firebaseコンソール設定(最優先)**:`FIREBASE_SETUP.md` の手順どおりに、プロジェクト作成〜匿名Auth/Realtime Database/Firestoreの有効化〜`GoogleService-Info.plist`の配置まで。これが終わらないとオンライン機能(ルーム対戦・フレンド)が一切動かない
   - 完了後、実機2台で早押しの体感遅延を検証(要件 §11-1 技術検証スパイク。目標:押下→判定反映 概ね500ms以内)
2. **セキュリティルールの本格設計**:`FIREBASE_SETUP.md` に暫定ルール(認証済みなら誰でも読み書き可)を置いてあるが、v1.0リリース前に以下へ強化する
   - `rooms/{roomId}`:ルーム参加者(`players`に自分のuidがある人)のみ書き込み可にする
   - `users/{uid}/friends`・`users/{uid}/invites`:バリデーション追加(不正なfriendCode書き込み防止など)
   - 対象:Firebaseコンソールのルールタブ(コード変更ではない)
3. **Cloud Functions開発(v1.5に向けた準備)**:現状は採点・進行制御をホスト端末(クライアント)が権威として行っている(`OnlineBattleSession+Host.swift`)。これはチート耐性が低く、`questions`に正答をそのまま配信しているため通信を覗けば正答が見える問題もある。以下をCloud Functions(TypeScript)に移す設計・実装を進めてほしい
   - 採点処理(正解判定・スコア加算)をサーバー側で行う
   - 問題データの配信時に正答をクライアントへ送らない(採点はサーバーのみが知っている状態にする)
   - 早押しの先着判定は現状RTDBトランザクションで実装済み(`OnlineBattleSession.buzz()`)なので、ここは維持でよい
   - 着手前に `project.yml`・Firebase構成への追加(Functionsディレクトリ新設)が必要なため、STATUS.mdの「作業中宣言」に記入してから着手すること

### 担当:未定(Claude or 別メンバー)

4. 通信対戦の実動作検証後の調整(切断・再入室、遅延対策、同時押しの体感) — 上記1完了後に着手
5. UI磨き込み(アニメーション、ハプティクス、効果音など)
6. 英単語データの品質見直し・拡充(現在100問)
7. 入力式回答の正誤判定ルール検討(要件 §10-2)
8. アプリ名・アイコン決定(要件 §10-1)
9. ルーム自動削除(使用済みルームがRTDBに残り続ける対応)

## 決定事項メモ

- プロジェクト管理はXcodeGen(pbxprojの手編集・コンフリクトを避けるため。2人開発と相性が良い)
- 誤答選択肢はJSONに持たせず、同品詞の他単語の意味からシード時に決定的に自動生成(データ作成コスト削減)
- 復習リスト:不正解で登録・回数加算、正解すると自動で外れる(「克服したら卒業」方式)
- ニックネームは `@AppStorage("nickname")` が正。サインイン済みなら `users/{uid}` に自動同期(設定画面で変更時も反映)
- 問題データ更新時は `QuestionSeeder.dataVersion` を上げると次回起動時に再投入される
- 通信対戦の進行権威はホスト端末(v1.0)。Cloud Functions採点はv1.5で検討
- 対戦の出題はホストが端末内の問題からシャッフルしてRTDBに配信(全員同じ選択肢順)
- フレンドは片方向フォロー方式(相互承認なし)。招待は相手の `invites` サブコレクションに書き込む
- 対戦ルール定数(人数上限・±1点・回答10秒・発表3秒など)は `BattleRules` に集約
