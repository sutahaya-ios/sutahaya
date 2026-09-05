# Firebase セットアップ手順(人間作業)

通信対戦・フレンド機能を動かすための初期設定。**この作業が終わるまでも、一人練習・復習・CPU対戦はオフラインで動作する**(フレンド・オンライン系のUIはサンプルデータ表示になる)。

対戦画面そのものの動作確認は、Firebaseを待たずに**対戦タブ →「ひとりで(CPU対戦)」**で通しでできる。

## 1. FirebaseプロジェクトとiOSアプリ

2人とも**既存の同じFirebaseプロジェクト `hayaosiapp`**を使う。Firebaseプロジェクトを分けると、Auth・Firestore・Realtime Databaseも別になり、2台で通信対戦できなくなる。

同じFirebaseプロジェクト内に、実機署名で使うBundle IDごとのiOSアプリを登録する。

| 用途 | Bundle ID | Apple Team |
|---|---|---|
| 本番・TestFlight・App Store | `com.n.HayaosiApp` | 代表者の有料Team |
| 共同開発者の実機検証 | `com.n.HayaosiApp.dev.tokiya`など本番と異なる値 | 共同開発者のPersonal Team |

1. Firebase Consoleでプロジェクト `hayaosiapp` を開く
2. 本番担当は、既存iOSアプリのBundle IDが `com.n.HayaosiApp` であることを確認する
3. 共同開発者は プロジェクトの設定 → 全般 → マイアプリ → アプリを追加 → iOS を開き、`Config/local.xcconfig` の `APP_BUNDLE_IDENTIFIER` と**完全に同じ**開発用Bundle IDを登録する
4. 各iOSアプリから、それぞれに対応する `GoogleService-Info.plist` をダウンロードする

Bundle IDが異なっても、同じFirebaseプロジェクト内のiOSアプリなら、既存の匿名認証・Firestore・Realtime Databaseと公開済みセキュリティルールを共有できる。

## 2. 機能の有効化(コンソール)

| 機能 | 手順 | 用途 |
|---|---|---|
| Authentication | Sign-in method → **匿名** を有効化 | ニックネームだけで利用開始 |
| Realtime Database | データベースを作成(ロケーションは asia-southeast1 など近場)。**「ロックモードで開始」を選び、下の §4 のルールを貼る** | ルーム同期・早押し判定 |
| Cloud Firestore | データベースを作成(asia-northeast1 推奨)。同じく**ロックモード**で作り §4 のルールを貼る | ユーザープロフィール・フレンド・招待 |
| Cloud Functions | Blazeプランを有効にし、§4 の `sendRoomInvite` を公開する | Realtime Databaseのhostを検証した招待作成 |

**テストモードで作らないこと。** テストモードは30日後に全拒否へ切り替わり、ある日突然アプリが動かなくなって原因が分かりにくい。ロックモードで作って §4 のルールを貼れば最初から動く。

**注意:** Realtime Database を作成した**後に** plist をダウンロードし直すこと(`DATABASE_URL` が含まれている必要がある。無い場合はアプリの対戦タブ(オンライン)に「Realtime Databaseの設定が見つかりません」と表示される)。

## 3. plistの管理と配置

> ⚠️ **`GoogleService-Info.plist` は git では渡せません。**
> `.gitignore` に入れているため、`git add` すると `The following paths are ignored by one of your .gitignore files` となってステージに乗らず、そのままコミットしても「変更なし」で終わります。
> **赤いエラーが出ないので「コミットできない/pushできない」と誤解しやすい箇所です。** 環境や権限の問題ではありません。

各開発者は、自分の実効Bundle IDに対応するplistを使う。本番用と開発用は同じファイルではない。

1. Firebase Consoleで自分が使うBundle IDのiOSアプリを開く
2. plistをダウンロードする(**Realtime Database作成後**のものを使い、`DATABASE_URL` が含まれることを確認する)
3. 下記へ `GoogleService-Info.plist` という名前で配置して `xcodegen generate` を実行する

```
HayaosiApp/Resources/GoogleService-Info.plist
```

配置後、plist内の `BUNDLE_ID` が `Config/local.xcconfig` で指定した開発用Bundle ID、または共有既定値の本番Bundle IDと一致することを確認する。不一致のまま実行するとFirebase初期化や通信機能が失敗する。

リポジトリで管理する運用に変えたい場合は `.gitignore` から外す必要がある。plistの中身はアプリに埋め込まれて配布されるクライアント識別子であり秘密情報ではないため技術的には可能だが、**本番用と開発用をGit経由で上書きし合う**ため、現在は管理外を維持する。

## 4. セキュリティルール

本格ルールは2026年8月17日にFirestore・Realtime Databaseの本番環境へ公開済み。暫定の「認証済みなら全ルームを読み書き可」ルールへ戻さない。

Bundle IDごとにFirebase iOSアプリを追加しても、セキュリティルールは同じFirebaseプロジェクト内で共有される。共同開発者用iOSアプリの追加だけを理由に、ルールを再作成・緩和・再公開する必要はない。

### 4-1. ルールファイルとローカル自動テスト

本格ルールの目標仕様は、リポジトリ内の次のファイルで管理する。

- `database.rules.json`: Realtime Database。待機中の部屋は参加前のコード確認を許可し、対戦開始後は参加者だけが読める。ゲーム進行と得点はホストだけが更新できる
- `firestore.rules`: `users` と `friendCodes` の一覧取得を禁止し、フレンド申請は受信側と送信側の控えを同時作成する。承認時だけ双方のフレンド文書を同時作成できる。ルーム招待のクライアント直接作成は禁止し、受信者のaccept/cancelだけ許可する
- `functions/index.js`: callable function `sendRoomInvite`。認証済みユーザーがRealtime Database上の現在のhostかと双方のフレンド関係を検証し、canonical inviteをAdmin SDKで作成する
- `firebase.json`: 上記ルールとLocal Emulator Suiteの設定
- `FirebaseRulesTests/rules.test.js`: 許可する操作と拒否する操作の自動テスト
- `FirebaseFunctionsTests/sendRoomInvite.test.js`: host招待、guest拒否、再招待、cooldown、accepting leaseの自動テスト

テストは実在するFirebaseプロジェクトではなく、`demo-hayaosiapp` というローカル専用IDを使う。本番データ・課金・公開中のルールには影響しない。

初回だけ依存関係を入れる:

```bash
npm install
npm install --prefix functions
```

ルールテストを実行する:

```bash
npm run test:firebase-rules
npm run test:firebase-functions
```

`firestore.rules` は `friendCodes/{code}` と招待の `fromUID`、`database.rules.json` は現在の回答・得点更新経路を前提にしている。ルール変更時はアプリ側の通信経路と不整合がないか確認し、Local Emulatorの全テストを通す。

本番公開は外部状態を変更するため、差分・テスト結果・Swift側の対応を確認し、担当者の明示的な許可を得た後にだけ行う。招待経路の公開時は、旧クライアントを先に拒否しないようFunctionsを先に公開し、成功後にFirestore Rulesを公開する。

```bash
firebase deploy --project hayaosiapp --only functions:sendRoomInvite
firebase functions:artifacts:setpolicy --project hayaosiapp --location asia-northeast1 --days 1 --force
firebase deploy --project hayaosiapp --only firestore:rules
```

Artifact Registryのcleanup policyは、Functionの動作に不要な過去のデプロイ用コンテナを1日後に削除し、保存料金の蓄積を防ぐ。

## 5. 動作確認

1. Simulatorまたは実機2台でアプリを起動
2. フレンドタブでマイコードが表示されればAuth+Firestore疎通OK
3. ルーム作成→もう1台でコード入力→ロビーに2人表示されればRealtime DB疎通OK
4. 対戦開始→選択肢を回答→リザルトまで通し確認(**要件の技術検証スパイク:実機2台で体感遅延を確認すること**)

## データ構造(実装済み)

```
Realtime Database:
rooms/{4桁コード}
  ├─ hostID, status(waiting/playing/finished/closed), createdAt
  ├─ settings { questionCount, timeLimit, genre,
  │             wordCategory(junior_high/high_school), wordDifficulty(1〜5) }
  ├─ players/{uid} { nickname, score, joinedAt }
  ├─ questions [ { id, text, choices[4], answer } ]  ← 開始時にホストが配信
  └─ game { questionIndex, phase(question/reveal/finished), startedAt, startDelayMS(1問目のみ),
            answers/{uid} { choice, ts, visibleCount }   ← 選択肢を押した瞬間の記録
            failed/{uid}: true                            ← 誤答済みで再回答不可
            reveal { correctAnswer, correctIDs[] }        ← 時間終了時に確定した正解者順 }

Firestore:
users/{uid} { nickname, friendCode, icon, bio, createdAt }
  ├─ friends/{friendUid} { nickname, friendCode, icon, bio, addedAt }
  ├─ friendRequests/{senderUid} { fromUID, fromNickname, fromFriendCode, createdAt }
  ├─ sentFriendRequests/{receiverUid} { toUID, toNickname, toFriendCode, createdAt }
  └─ invites/{roomInstanceID}_{senderUID}
       { roomCode, roomInstanceID, fromUID, fromNickname, generation,
         status(pending/accepting/cancelled), createdAt }
```

招待は `sendRoomInvite` だけが作成する。Realtime Databaseの `rooms/{roomCode}` に保存された `hostID` と `roomInstanceID` を検証するため、guestがUIを改造しても招待は作成されない。同じルーム・送信者・受信者の招待は同じcanonical documentをgeneration更新して再利用する。

`icon` はアプリ内の絵文字プリセットまたは空文字、`bio` は140文字以内。プロフィール同期対応前に作成済みのフレンド文書には両フィールドが無い場合があるため、フレンド一覧を開いた時に各 `users/{friendUid}` を1回ずつ取得して最新表示へ補完する。常時監視とフレンド文書への書き戻しは行わない。

フレンドコード入力時は、相手の `friendRequests/{自分のuid}` と自分の `sentFriendRequests/{相手のuid}` を同じバッチで作成する。これにより受信者は「受信中」、送信者は「送信済み」の一覧で相手名を確認できる。受信者が承認すると、Firestoreのバッチ処理で双方の `friends` を作成し、申請と送信側の控えを同時に削除する。拒否時も申請と控えを同時に削除し、フレンド文書は作らない。

送信控えの導入前に作られた片側だけの申請は、送信者が同じフレンドコードを再入力すると欠けている側だけを補完する。既存文書の更新や申請の重複作成は行わない。

## 既知の制約(v1.0スコープ)

- 進行の権威はホスト端末(ホストが落ちるとルーム解散)
- questionsに正答を含めて配信するため、通信を覗けば正答が見える(v1.5でCloud Functions採点を検討)
- 使い終わったルームはDBに残る(Sparkプラン内では実害なし。定期削除は将来対応)
- ルーム満員判定は非トランザクション(同時入室で9人になる可能性が理論上ある)
