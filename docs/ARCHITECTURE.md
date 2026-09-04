# HayaosiApp アーキテクチャ

最終整理日: 2026-09-05

## 全体構造

```text
SwiftUI Views
    ↓
Battle / Quiz / Profile等のService
    ├─ SwiftData（問題・回答履歴・復習・学習時間）
    └─ Online層
         ├─ Firebase Anonymous Auth
         ├─ Firestore（プロフィール・フレンド・招待）
         └─ Realtime Database（通信対戦）
```

`Services/Battle/`はFirebase非依存を維持し、CPU対戦がオフラインで完結できるようにする。Firebase固有処理は`Services/Online/`へ置く。CPU対戦とオンライン対戦は共通のBattleSession抽象と対戦画面を使う。

## アプリ層

- App: 起動、Firebaseの条件付き初期化、SwiftDataコンテナ、広告・サブスク開始
- Models: SwiftDataモデルと学習・問題分類の値型
- Services: 出題、履歴、集計、対戦、通信、広告、サブスク
- Views: 対戦、学習、マイページ等の機能別SwiftUI
- Resources: 単語JSON、効果音、端末固有Firebase plist

SwiftData schemaを変更すると既存ユーザーの履歴へ影響する。プロパティ追加ではOptionalまたはデフォルト値を検討し、上書きインストールによる移行確認が必要である。

## 対戦アーキテクチャ

### 共通ルール

- 問題文を時間経過で徐々に表示する
- 選択肢は常時表示する
- 選択肢タップが早押しと回答を兼ねる
- 各プレイヤーは1問につき1回回答できる
- 誤答による回答不能は現在問題だけに限定する
- 正解順位の得点は `+20 / +10 / +5 / 4位以降+1`
- 誤答は`-10`、無回答は0
- 制限時間終了、または回答可能な全員の回答完了で正解発表する

対戦ルールの定数は共通ロジックを唯一の出典とし、ViewやFirebase層へ数値を重複させない。

### CPU対戦

- Firebaseを使用しない
- オンラインと同じルーム状態モデルと画面を使用する
- CPUの回答判断は進行・UIから分離する
- 学習履歴と復習リストへ一人学習として保存する

### オンライン対戦

- v1.0はホスト端末が進行と採点の権威を持つ
- ホストが問題を選択・配信し、採点、得点更新、正解発表、次問移行を行う
- 回答順はFirebaseサーバータイムスタンプを基準にする
- 各端末の表示とタイマーはFirebaseサーバー時刻offsetで補正する
- 回答とfailed状態は問題番号に紐付け、遅延した前問データを次問へ混ぜない
- 次問移行時にanswers、failed、revealを明示的にクリアする

ホスト権威を採用した理由は、v1.0で採点をCloud Functions化する複雑さと期限を避けるためである。正解データがクライアントへ配信されるため不正耐性には限界があり、採点のサーバー権威化は将来課題である。

### ホスト切断

- ホストの明示退出ではルームを終了する
- Firebaseの`onDisconnect`は一時通信断でも動作し得る
- 一時切断と本当の退出を区別するため、参加者側で短い猶予を設け、ホスト復帰時は直前状態へ戻す方針
- この方針は実機での最終確認が必要

## 対戦UIフロー

対戦ホームから直接、次を操作する。

- ルーム作成
- 4桁コード参加
- CPU対戦
- 対戦招待への参加
- 招待を「あとで」にする

ルーム作成は前回設定をローカル保存して再利用する。通常フローではオンライン中間画面と毎回の全画面設定画面を挟まない。「あとで」は招待文書を削除せず、その端末のホーム表示だけを隠す。

待機ロビーは全画面で、ルームID、共有、参加者、ホスト表示、対戦設定、開始操作を表示する。対戦開始はホストだけが行い、ゲストは待機する。

PvPリザルトでは復習ボタンを表示しないが、誤答情報はローカルへ保存し、後から一人学習・復習画面で利用できる。CPU対戦ではリザルトから直接復習できる。

## Firebaseデータ境界

### Firestore

- `users/{uid}`: ニックネーム、フレンドコード、アイコン、自己紹介
- `friendCodes/{code}`: コードからuidへの索引
- `users/{uid}/friendRequests`: 受信申請
- `users/{uid}/sentFriendRequests`: 送信済み申請
- `users/{uid}/friends`: 相互フレンド
- `users/{uid}/invites`: ルーム招待

フレンド承認では双方のfriends文書を同じバッチで作る。プロフィールとフレンドコード索引も整合性を保つため原子的に作成する。

既存フレンドの最新プロフィールは、常時監視や一括移行をせず、フレンド一覧表示時に必要分だけ取得する。Firestore読み取り量を増やしすぎないための判断である。

### Cloud Functions

- `sendRoomInvite`: Realtime Databaseのhost、room instance、waiting状態とFirestoreの相互フレンド関係を検証し、canonical inviteを作成する

招待はクライアントからFirestoreへ直接作成せず、hostの真正性をサーバー側で確認する。対戦の問題配信・採点・進行は引き続きホスト端末が担当する。

### Realtime Database

```text
rooms/{roomCode}
├─ hostID
├─ status
├─ createdAt
├─ settings
├─ players/{uid}
├─ questions
└─ game
   ├─ questionIndex
   ├─ phase
   ├─ startedAt / startDelayMS
   ├─ answers/{uid}
   │  └─ questionIndex / choice / ts / visibleCount
   ├─ failed/{uid}
   │  └─ questionIndex
   └─ reveal
```

回答・failedに問題番号を持たせるのは、遅延書き込みや前問のスナップショットが次問の回答権を奪う不具合を防ぐためである。

## Security境界

- ホストだけがstatus、settings、questions、game、scoreを更新する
- 参加者はwaiting中に限り自分のplayer情報を追加する
- 参加者は自分の回答だけを書き、同じ問題での再回答を禁止する
- Firestoreは所有者・申請相手・相互フレンド関係を検証する
- コレクション全件列挙ではなく、必要文書の直接取得を基本とする
- 暫定的な`auth != null`だけの全面read/writeへ戻さない

Security Rulesとクライアントpayloadは一体で変更する。拒否を強めるだけでなく、正常ユーザーの書き込みを拒否しないことも要件である。

## SigningとFirebase plistの分離

```text
共有Git設定
├─ project.yml
├─ Config/Signing.xcconfig
└─ ソースコード

各開発者のローカル設定（git管理外）
├─ Config/local.xcconfig
└─ HayaosiApp/Resources/GoogleService-Info.plist
```

たける側は本番Bundle ID＋有料Team、トキヤ側は開発用Bundle ID＋Personal Teamを使う。双方は同じFirebase Projectへ接続する。

## 既知の技術的負債

- 正解を含む問題データが参加者端末へ配信される
- 使用済みRTDBルームの自動削除がない
- ルーム満員判定が完全には原子的でない
- App Check未導入
- ホスト一時切断の復旧は実機最終確認が必要
- Firebaseセットアップ文書の古いデータ図が現行payloadとずれている可能性がある

## 検証境界

- 純粋ロジック: Swiftユニットテスト
- Security Rules: Firebase Emulatorテスト
- 通信同期・切断・実機固有挙動: 複数実機
- 音、振動、Apple Signing、TestFlight、Firebase Console公開状態: 人間による確認
