# Firebase セットアップ手順(人間作業)

通信対戦・フレンド機能を動かすための初期設定。**この作業が終わるまでも、一人練習・復習はオフラインで動作する**(オンライン系タブに案内が表示されるだけ)。

## 1. Firebaseプロジェクト作成

1. https://console.firebase.google.com で新規プロジェクト作成(名前は任意、Analyticsは不要)
2. iOSアプリを追加:バンドルID **`com.n.HayaosiApp`**
3. `GoogleService-Info.plist` をダウンロード

## 2. 機能の有効化(コンソール)

| 機能 | 手順 | 用途 |
|---|---|---|
| Authentication | Sign-in method → **匿名** を有効化 | ニックネームだけで利用開始 |
| Realtime Database | データベースを作成(ロケーションは asia-southeast1 など近場) | ルーム同期・早押し判定 |
| Cloud Firestore | データベースを作成(asia-northeast1 推奨) | ユーザープロフィール・フレンド・招待 |

**注意:** Realtime Database を作成した**後に** plist をダウンロードし直すこと(`DATABASE_URL` が含まれている必要がある。無い場合はアプリのルームタブに「Realtime Databaseの設定が見つかりません」と表示される)。

## 3. plistの配置

```
HayaosiApp/Resources/GoogleService-Info.plist
```

に置いて `xcodegen generate` を実行(.gitignore 済みなのでコミットされない)。

## 4. セキュリティルール

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

※ v1.0リリース前にルールの絞り込み(ルーム参加者のみ書き込み可、バリデーション等)を再検討する。

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
  ├─ settings { questionCount, timeLimit, genre }
  ├─ players/{uid} { nickname, score, joinedAt }
  ├─ questions [ { id, text, choices[4], answer } ]  ← 開始時にホストが配信
  └─ game { questionIndex, phase(question/reveal/finished), startedAt,
            buzz { winner, queue/{uid}: ts, failed/{uid} }, answer, reveal }

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
