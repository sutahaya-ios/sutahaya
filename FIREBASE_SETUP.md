# Firebase セットアップ手順(人間作業)

通信対戦・フレンド機能を動かすための初期設定。**この作業が終わるまでも、一人練習・復習・CPU対戦はオフラインで動作する**(フレンド・オンライン系のUIはサンプルデータ表示になる)。

対戦画面そのものの動作確認は、Firebaseを待たずに**対戦タブ →「ひとりで(CPU対戦)」**で通しでできる。

## 1. Firebaseプロジェクト作成

1. https://console.firebase.google.com で新規プロジェクト作成(名前は任意、Analyticsは不要)
2. iOSアプリを追加:バンドルID **`com.n.HayaosiApp`**
3. `GoogleService-Info.plist` をダウンロード

## 2. 機能の有効化(コンソール)

| 機能 | 手順 | 用途 |
|---|---|---|
| Authentication | Sign-in method → **匿名** を有効化 | ニックネームだけで利用開始 |
| Realtime Database | データベースを作成(ロケーションは asia-southeast1 など近場)。**「ロックモードで開始」を選び、下の §4 のルールを貼る** | ルーム同期・早押し判定 |
| Cloud Firestore | データベースを作成(asia-northeast1 推奨)。同じく**ロックモード**で作り §4 のルールを貼る | ユーザープロフィール・フレンド・招待 |

**テストモードで作らないこと。** テストモードは30日後に全拒否へ切り替わり、ある日突然アプリが動かなくなって原因が分かりにくい。ロックモードで作って §4 のルールを貼れば最初から動く。

**注意:** Realtime Database を作成した**後に** plist をダウンロードし直すこと(`DATABASE_URL` が含まれている必要がある。無い場合はアプリの対戦タブ(オンライン)に「Realtime Databaseの設定が見つかりません」と表示される)。

## 3. plistの受け渡しと配置

> ⚠️ **`GoogleService-Info.plist` は git では渡せません。**
> `.gitignore` に入れているため、`git add` すると `The following paths are ignored by one of your .gitignore files` となってステージに乗らず、そのままコミットしても「変更なし」で終わります。
> **赤いエラーが出ないので「コミットできない/pushできない」と誤解しやすい箇所です。** 環境や権限の問題ではありません。

受け渡しは**ファイルを直接送る**(Slack・LINE・メール・AirDropなど何でもよい):

1. Firebase担当が plist をダウンロードする(**Realtime Databaseを作成した後に**。`DATABASE_URL` が必要)
2. アプリ担当へファイルとして送る
3. 受け取った側が下記に配置して `xcodegen generate` を実行する

```
HayaosiApp/Resources/GoogleService-Info.plist
```

リポジトリで管理する運用に変えたい場合は `.gitignore` から外す必要がある。plistの中身はアプリに埋め込まれて配布されるクライアント識別子であり秘密情報ではないため技術的には可能だが、**git履歴に永久に残る**ため、開発用と本番用でFirebaseプロジェクトを分けるときに厄介になる。方針の変更は人間が判断する。

## 4. セキュリティルール

> ⚠️ **以下は「開発中に動かすための暫定ルール」であり、リリースブロッカーです。**
> 認証済みなら誰でも読み書きできるため、現状は**他人のルームのスコアを書き換えられる**。
> v1.0公開前に §4-1 の強化を必ず終えること(担当:TOKIYA-YAMAMOTO氏。`STATUS.md` の「次のタスク」2番)。

### Realtime Database(ルール タブに貼り付け)

```json
{
  "rules": {
    "rooms": {
      "$roomId": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    }
  }
}
```

### Firestore(ルール タブに貼り付け)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == uid;
      match /friends/{friendUid} {
        allow read, write: if request.auth.uid == uid;
      }
      match /invites/{inviteId} {
        allow read, delete: if request.auth.uid == uid;
        allow create: if request.auth != null;
      }
    }
  }
}
```

### 4-1. リリース前に必要な強化(未着手)

| # | 対象 | 現状の問題 | 対応案 |
|---|---|---|---|
| 1 | `rooms/{roomId}`(RTDB) | 認証済みなら誰でも書ける。他人の試合のスコア・進行を書き換え可能 | `players` に自分のuidがある人だけ書き込み可にする。`players/{uid}` は本人のみ、`game` はホストのみ |
| 2 | `users/{uid}`(Firestore) | **フレンドコード検索を `users` コレクションへのクエリで実装しているため `list` を許可せざるを得ず、全ユーザーのニックネームとフレンドコードが列挙できる** | `friendCodes/{code} → { uid }` の逆引きコレクションを作り、検索はそこを1件 `get` する方式へ変更。`users` は `get` のみ許可し `list` を禁止する。副産物としてフレンドコードの一意性もトランザクションで保証できる(現状は同時生成で理論上重複しうる) |
| 3 | `users/{uid}/invites` | 認証済みなら誰にでも招待を作れる(スパム招待が可能) | 送信元がフレンド関係にあることを条件に加える、または招待にレート制限を入れる |

※ #2 はアプリ側(`AuthService` / `FriendService`)の変更も伴うため、着手前に `STATUS.md` の「作業中宣言」で調整すること。

## 5. 動作確認

1. Simulatorまたは実機2台でアプリを起動
2. フレンドタブでマイコードが表示されればAuth+Firestore疎通OK
3. ルーム作成→もう1台でコード入力→ロビーに2人表示されればRealtime DB疎通OK
4. 対戦開始→早押し→回答→リザルトまで通し確認(**要件の技術検証スパイク:実機2台で体感遅延を確認すること**)

## データ構造(実装済み)

```
Realtime Database:
rooms/{4桁コード}
  ├─ hostID, status(waiting/playing/finished/closed), createdAt
  ├─ settings { questionCount, timeLimit, genre, style(progressive_choice/speed) }
  ├─ players/{uid} { nickname, score, joinedAt }
  ├─ questions [ { id, text, choices[4], answer } ]  ← 開始時にホストが配信
  └─ game { questionIndex, phase(question/reveal/finished), startedAt,
            answers/{uid} { choice, ts, visibleCount }   ← 文字送り型(標準)。押した瞬間の記録
            buzz { winner, queue/{uid}: ts, failed/{uid} }, answer   ← 速答型
            reveal }

Firestore:
users/{uid} { nickname, friendCode, createdAt }
  ├─ friends/{friendUid} { nickname, friendCode, addedAt }
  └─ invites/{autoId} { roomCode, fromNickname, createdAt }
```

## 既知の制約(v1.0スコープ)

- 進行の権威はホスト端末(ホストが落ちるとルーム解散)
- questionsに正答を含めて配信するため、通信を覗けば正答が見える(v1.5でCloud Functions採点を検討)
- 使い終わったルームはDBに残る(Sparkプラン内では実害なし。定期削除は将来対応)
- ルーム満員判定は非トランザクション(同時入室で9人になる可能性が理論上ある)
