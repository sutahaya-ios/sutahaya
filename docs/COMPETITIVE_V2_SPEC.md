# Competitive Mode v2.0 Specification

- Status: Phase A-2 Competitive Core Local / Emulator complete candidate
- Last updated: 2026-10-06
- Scope: Competitive Mode v2.0 only
- Implementation status: Phase A-1 complete / Phase A-2 Production Cloud verification pending

## この文書の位置づけ

この文書は、Competitive Mode v2.0 の契約と設計判断を管理する Single Source of Truth（SSOT）である。

- 現行のフレンドバトルは `docs/ARCHITECTURE.md` と既存実装を正とする。
- Competitive Mode は現行フレンドバトルと別のAPI、状態、Rules、保存領域を持つ。
- Competitiveのゲームルールと回答体験は現行フレンドバトルを基準とし、主な変更点は判定主体をhost/clientからServerへ移すことである。
- Competitive Mode に関して既存文書とこの文書が矛盾する場合は、この文書を優先する。
- この文書の論理リソース名は契約を説明するための仮称であり、Firebase pathやFirestore collection名を確定するものではない。
- Phase 0 ではアプリコード、Firebase Schema、Rules、Functions、UIを変更しない。

### 判断状態

- **確定**: 後続Phaseが守る契約。変更にはこの文書の更新が必要。
- **暫定**: Phase Aの計測または検証で最終決定する。
- **未決定**: プロダクト判断が必要。Open Questionsで管理する。

---

## 1. Goals / Non-goals

### 1.1 Goals

Competitive Modeは、以下を満たす4人制オンライン対戦として実装する。

1. ランダムマッチングで常に4枠の対戦を成立させる。
2. score、正誤、順位、勝者、回答受付順、回答時間、MMR、rating差分、NPC結果をサーバーが確定する。
3. クライアントは操作の意図（Intent）のみを送信し、確定値を直接書き込まない。
4. 1試合内の全イベントに、再現可能な単一の論理順序を与える。
5. 低ランク帯では不足枠をNPCで補い、上位帯では人間のみで対戦する。
6. プレイヤー評価値は1種類の非公開MMRに統一する。
7. 通常帯ではMMRから導出したTierを表示し、Rating Zoneでは数値Ratingを表示する。
8. Season、Top 20 leaderboard、直近5試合の履歴を提供する。
9. 再送、重複実行、一時切断、サーバー再起動があっても、試合とsettlementを安全に収束させる。
10. 現行フレンドバトルを壊さず、Competitive固有の信頼境界を維持する。
11. 各Playerが同じ問題へ独立して1回回答し、正解者の回答受付順に得点する現行フレンドバトルのProduct ruleを維持する。

### 1.2 Non-goals

Phase 0および初期Competitive実装では、以下を目的にしない。

- 現行フレンドバトルのhost-authoritative方式の全面置換
- 現行 `OnlineBattleSession`、`RoomState`、`rooms` schemaの大規模再設計
- 外部辞書、画面認識、改造端末による自動解答の完全防止
- 全世界・全リージョン対応を前提にした分散合意
- 観戦、リプレイ、トーナメント、チーム戦
- 端末間の完全に同一なアニメーション時刻の保証
- Phase 0での本番deploy、Matchmaking、Rating、Rank UI、Leaderboard、Season、Production NPCの実装
- 無関係なリファクタリングやFirebase pathの全面共通化

### 1.3 現行モードとの分離

- 現行フレンドバトルは、host端末が問題進行と得点を確定し、RTDBへ同期する既存方式を維持する。
- Competitive Modeでは、現行のようにクライアントがRTDBの対戦状態へ直接書き込む設計を採用しない。
- Competitive Modeでも、最初の回答者が他Playerをlockしない。各Playerは同じ問題へ独立して1回だけ回答できる。
- 共用してよいのは、Firebase非依存の表示部品、問題表示、音、pure battle logicなど、信頼境界を越えない部品に限る。
- Competitiveのサーバー確定値を既存のhost-authoritativeモデルへ変換する場合は、専用adapterを境界に置く。既存型をそのまま権威データモデルとして再利用しない。

### 1.4 維持する現行Product rule

現行フレンドバトルの `BattleAnswerAcceptance`、`BattleScoring`、`OnlineBattleSession`、`OnlineBattleSession+Host` を基準とし、Competitiveでも次を維持する。

- 1試合は20問とする。
- 各active Playerは1問につき1回だけ、他Playerから独立して回答する。正解・不正解のどちらでも再回答はできない。
- 回答受付区間は問題開始時刻以上かつdeadline以下とする。
- 受理済み回答はServer-ownedの受付情報で早い順に並べ、正解者だけをその順に順位付けする。誤答は正解順位を消費しない。
- 正解は1位20点、2位10点、3位5点、4位以降1点、誤答は-10点、無回答は0点とする。
- 権威受付時刻が完全に同じ場合は、試合開始時に固定したroster/slot順をtie-breakに使う。近接時刻を同着扱いにする追加thresholdは未決定とする。
- 問題開始時のscoreを基準に受理済み回答集合から得点を再計算し、retryや再評価で二重加点しない。最終順位は合計score降順で、同点Playerは同順位とする。
- 全active Playerが回答済み、またはdeadline到達で問題を閉じる。当該問題へ参加しないNPCは「全員回答済み」の判定から除外する。
- NPCも参加する場合は、人間と同じ受理済み回答集合・正誤・得点ロジックへ入れる。
- 次問題開始時は前問題の回答済み状態、回答集合、結果表示状態を残さない。

---

## 2. Trust Boundary

### 2.1 基本原則

Competitive Modeでは、iOSアプリ、Simulator、改造client、通信内容を信頼しない。Firebase Authで得たUIDも「誰が送ったか」を示すだけであり、score、時刻、正誤、権限の正当性を証明しない。

| 対象 | 信頼 | 扱い |
| --- | --- | --- |
| 画面入力、端末時計、client送信時刻 | 信頼しない | UX・計測の参考値のみ |
| Firebase Auth UID | 認証済み主体として利用 | session、roster、所有権と照合する |
| App Check / App Attest | 正規アプリらしさの補助 | 認証やゲーム判定の代替にしない |
| Client Intent payload | 信頼しない | allowlist、型、長さ、state、所有権、epochを検証する |
| Server clock | 権威時刻 | deadline、回答受付順、lease、回答時間に使用する |
| Ordering Authorityのcommit順 | 試合内の権威順序 | `serverSequence` を採番する |
| Server-owned question bank | 秘密情報 | 正解や内部IDを問題中のclientへ送らない |
| Public match projection | 読取用の確定表示 | clientからのwriteを禁止する |
| Settlement record | Rating更新の根拠 | immutableかつ冪等に適用する |

### 2.2 Clientから送ってよいもの

- Intent種別
- client生成の一意な `intentId`
- serverから払い出された `sessionId`、`sessionEpoch`、`matchId`、ticket
- 操作対象を示すopaque ID（例: `questionId`、`answerId`）
- clientの対応 `protocolVersion` とapp build情報
- 再接続時の最後に観測した `serverSequence`

### 2.3 Clientから送ってはいけない確定値

- score、score delta、rank、winner
- correctness、correct answer、failed判定
- answerOrder、acceptedAt、responseTime
- MMR、ratingDelta、Tier、leaderboard順位
- NPCの行動、得点、正誤、強さ
- session state、lease期限、serverSequence
- match state、question deadline、settlement status

### 2.4 Serverだけが確定するもの

Serverは認証、App Check、protocol、session fence、match state、roster、deadline、重複、rate limitを検証した後に、Intentの採用・拒否と結果を確定する。client表示はserverの公開projectionに従い、local optimistic stateを最終結果として扱わない。

---

## 3. Client Intent

### 3.1 共通Envelope

すべてのIntentは論理的に次の情報を持つ。

```text
IntentEnvelope
  intentId: UUID
  type: IntentType
  protocolVersion: String
  clientBuild: String
  sessionId: OpaqueID?
  sessionEpoch: Int?
  matchId: OpaqueID?
  questionId: OpaqueID?
  lastSeenServerSequence: Int?
  payload: TypeSpecificPayload
```

- UIDはpayloadから受け取らず、認証contextから取得する。
- client timestampは権威判定に使用しない。送信しても診断用に限定する。
- `intentId` はsession内で一意にする。同じIntentの再送は同じ結果を返し、状態を二重更新しない。
- `sessionEpoch` が最新値と一致しないIntentは `STALE_SESSION_EPOCH` で拒否する。
- payloadはIntentごとのallowlist、型、列挙値、byte数で検証する。未知フィールドは拒否または無視のどちらかに統一し、Phase Aで契約テストを固定する。

### 3.2 Intent一覧

| Intent | clientが送る最小情報 | Server検証 | 成功時 |
| --- | --- | --- | --- |
| `joinQueue` | queue種別、protocol | active session不在、対応version、ban/rate limit | sessionを作成しQUEUEDへ |
| `cancelQueue` | sessionId、epoch | QUEUED本人、match未確定 | IDLEへ戻す |
| `joinMatch` | assignment ticket、sessionId、epoch | ticket署名/期限、roster、WAITING_PLAYERS | slotを接続済みにする |
| `ready` | matchId、sessionId、epoch | roster本人、WAITING_PLAYERS | readyを記録する |
| `submitAnswer` | matchId、questionId、answerId | QUESTION_OPEN、roster本人、当該問題で未回答、deadline内、answerId有効 | ServerがそのPlayerの回答を1回だけ受理し、正誤・受付時刻・得点を確定。ほかのPlayerはlockしない |
| `leave` | sessionId、epoch、matchId? | session所有者、現在state | 開始前cancelまたは開始後forfeit |
| `reconnect` | sessionId、epoch、matchId、lastSeenSequence | lease/grace、roster、fence | snapshotと欠落後の状態を返す |
| `heartbeat` | sessionId、epoch、matchId? | session所有者、rate limit | Serverがleaseを延長する |

`heartbeat` はゲーム結果を変えるIntentではないが、session leaseを維持するため同じ認証・fencing契約を通す。

### 3.3 Intent応答

```text
IntentAck
  intentId
  status: ACCEPTED | REJECTED | DUPLICATE
  serverSequence?
  publicStateVersion?
  rejectionCode?
  retryable: Bool
```

- `ACCEPTED` は「ServerがIntentを順序へcommitした」を意味する。client表示への反映完了とは限らない。
- `DUPLICATE` は最初の処理結果を参照し、新しい結果を作らない。
- `REJECTED` は機械判定可能な安定したcodeを持つ。生のbackend errorをclientへ返さない。
- UXはackだけで確定表示せず、原則としてpublic projectionの `serverSequence` 到達で確定する。

### 3.4 主な拒否code

- `UNAUTHENTICATED`
- `APP_CHECK_REQUIRED`
- `PROTOCOL_UNSUPPORTED`
- `UPGRADE_REQUIRED`
- `INVALID_PAYLOAD`
- `RATE_LIMITED`
- `STALE_SESSION_EPOCH`
- `SESSION_NOT_ACTIVE`
- `NOT_MATCH_MEMBER`
- `INVALID_MATCH_STATE`
- `QUESTION_MISMATCH`
- `ALREADY_ANSWERED`
- `DEADLINE_EXCEEDED`
- `DUPLICATE_INTENT`
- `MATCH_ALREADY_FINISHED`

---

## 4. Server-owned Result

### 4.1 試合中の権威データ

Serverは少なくとも以下を所有する。

- roster、slot、human/NPC区分
- match stateとstate version
- `serverSequence`
- countdown、questionのdeadline
- 問題のcanonical ID、correct answer、選択肢対応
- Playerごとの回答受付可否、回答済み状態、server受付時刻
- 問題内で一度だけ受理された回答集合とcanonicalな回答順
- correctness、score delta、total score
- question result、最終rank、winner
- disconnect、grace、forfeit状態
- NPCの反応、回答、正誤、得点

### 4.2 公開Projection

clientが読む状態は、Server内部状態から生成したsanitized projectionとする。

- 対戦中に公開してよい: display name、avatar用公開値、slot、接続状態の粗い表現、score、公開state、残り時間の基準、prompt、choices、Playerごとの回答済み状態。
- 問題確定前に公開しない: correct answer、内部question ID、正解index、出題seed、NPCの将来行動、MMR。
- `QUESTION_RESULT` 以後に、答え合わせに必要な正解表示を公開してよい。
- `MATCH_FINISHED` ではscoreとrankを公開するが、MMR更新結果はsettlement確定後に公開する。

### 4.3 最終結果

最終結果は、match内のcanonical resultとsettlement resultを分ける。

- `MatchResult`: matchId、roster snapshot、outcome（COMPLETED / ABORTED）、final scores、ranks、winner、forfeit/abort reason、finishedAt、configVersion。ABORTEDではrank/winnerを確定しない。
- `SettlementResult`: settlementId、settlementVersion、MMR before/delta/after、season、history/leaderboard反映状態。
- MatchResultは一度確定したら変更しない。
- SettlementResultの適用処理は再実行可能だが、同じsettlementを二重加算しない。
- Server faultによるABORTED matchはMMR、敗北数、leaderboardへ競技結果として適用しない。

---

## 5. Match State Machine

### 5.1 状態遷移

```text
CREATED
  -> WAITING_PLAYERS
  -> COUNTDOWN
  -> QUESTION_OPEN
       -> QUESTION_RESULT    (全active Player回答済み、またはdeadline到達)
  -> NEXT_QUESTION
       -> QUESTION_OPEN ...
       -> MATCH_FINISHED
  -> SETTLEMENT_PENDING
  -> SETTLED
```

異常終了は自由なstate上書きではなく、Server eventとして同じOrdering Authorityを通し、forfeitまたはabort理由をMatchResultに残す。Server側障害によるabortはPlayerの敗北やMMR penaltyとして扱わない。

### 5.2 CREATED

- **Server保持**: matchId、seasonId、protocol/config version、作成時刻、候補roster、matchmaking ticket。
- **公開**: 原則なし。
- **許可Intent**: なし。matchmaking内部eventのみ。
- **拒否**: clientからの全match Intent。
- **Timeout**: 作成処理が完了しない場合はmatchをabortし、確保済みhumanをqueueへ安全に戻す。
- **遷移**: 4枠の候補rosterとWAITING用deadlineをcommitして `WAITING_PLAYERS`。

### 5.3 WAITING_PLAYERS

- **Server保持**: 4枠roster、assignment ticket、接続/ready、session fence、参加deadline。
- **公開**: 参加済みslot、display用player情報、ready状態、待機期限。MMRは公開しない。
- **許可Intent**: `joinMatch`、`ready`、`reconnect`、`leave`、`heartbeat`。
- **拒否**: `submitAnswer`、roster外のjoin、期限切れticket。
- **Timeout**: 未参加・未ready playerをno-show扱いにする。開始前のためMMR penaltyは付けず、matchをabortして残りhumanを再queueすることを初期方針とする。
- **遷移**: Queue/WAITING中はキャンセル可能とする。4枠が確定し、必要なhumanが参加・readyして `COUNTDOWN` を開始するcommitを、Competitive Matchへのcommitment boundaryとする。

### 5.4 COUNTDOWN

- **Server保持**: immutable roster snapshot、startAt、最初のquestion参照、全deadline基準時刻。
- **公開**: roster、countdown基準、接続状態、公開設定。
- **許可Intent**: `reconnect`、`leave`、`heartbeat`。
- **拒否**: `submitAnswer`、roster変更、ready取消。
- **Timeout**: startAt到達をServer timer eventとして処理する。clientのanimation完了を待たない。
- **遷移**: 最初の問題をsanitized projectionへcommitして `QUESTION_OPEN`。COUNTDOWN以後の明示的leaveは原則forfeit。通信断・app終了は即時forfeitにせず `RECONNECTING` とし、grace超過時だけforfeitにする。Server側障害はPlayerのforfeitにしない。

### 5.5 QUESTION_OPEN

- **Server保持**: canonical question、correct answer、active Player集合、Playerごとの回答済み状態、受理済み回答、`questionOpenedAt`、`questionDeadline`、採点設定。
- **公開**: match固有でopaqueな `questionId`、prompt、opaque `answerId`付きchoices、deadline基準、score、Playerごとの回答済み状態。correct answerは非公開。
- **許可Intent**: 未回答humanの `submitAnswer(answerId)`、全Playerの `reconnect`、`leave`、`heartbeat`。
- **受付**: 各active Playerにつき1回答だけをServerが受理する。最初のPlayerが回答しても他Playerをlockせず、正解・不正解にかかわらずそのPlayerだけが当該問題で回答済みになる。
- **拒否**: 同一Playerの2回目の回答、自由入力、未知answerId、roster外、問題不一致、deadline後回答。
- **採点**: 受理済み回答をauthoritativeな受付順へ並べ、正解者だけをその順に20 / 10 / 5 / 4位以降1点、誤答は-10点、無回答は0点とする。誤答は正解順位を消費しない。同一の権威受付時刻なら、開始時に固定したroster/slot順をtie-breakに使う。
- **途中反映**: 現行体験を維持するため、Serverは受理済み回答集合と問題開始時scoreから途中scoreを再計算して公開できる。ただし最終的な回答集合・順序・得点はquestion closeで確定し、再送で二重加点しない。
- **Timeout**: 最初の `questionOpenedAt` を基準とする `questionDeadline` 到達をServer timer eventとして確定し、延長・再設定しない。
- **遷移**: 全active Player（当該問題へ参加しないNPCを除く）が回答済み、またはdeadline到達で、canonicalな回答集合・正誤・得点を閉じて `QUESTION_RESULT`。回答のたびにはphaseを変えない。

### 5.6 QUESTION_RESULT

- **Server保持**: closedな回答集合、authoritativeな回答順、各回答のcorrectness、correct answer、score delta、total scores、question result sequence。
- **公開**: 回答者ごとの結果、正解、score delta、total scores、結果表示期限。
- **許可Intent**: `reconnect`、`leave`、`heartbeat`。
- **拒否**: `submitAnswer`、結果変更要求。
- **Timeout**: result表示期限をServer timer eventで処理する。
- **遷移**: 残り問題ありなら `NEXT_QUESTION`、終了条件成立なら `MATCH_FINISHED`。

### 5.7 NEXT_QUESTION

- **Server保持**: 前問題のclosed marker、次question参照、Playerごとの回答済み状態reset、score snapshot。
- **公開**: transition状態と現在score。次問題の秘密情報はまだ公開しない。
- **許可Intent**: `reconnect`、`leave`、`heartbeat`。
- **拒否**: `submitAnswer`。
- **Timeout**: 内部準備のretry deadline。失敗時は同じnext-question eventを冪等retryする。
- **遷移**: 次問題のpublic payloadとdeadlineを同一commitで作り `QUESTION_OPEN`。終了条件なら `MATCH_FINISHED`。

### 5.8 MATCH_FINISHED

- **Server保持**: immutable MatchResult、最終score/rank/winner/forfeit、settlement作成状態。
- **公開**: COMPLETEDなら最終score、rank、winner、settlement待ち表示。ABORTEDなら中止理由の安全な表示と、敗北・MMR penaltyが発生しないこと。
- **許可Intent**: `reconnect`、結果read。新しいgameplay Intentは不可。
- **拒否**: `submitAnswer`、score/rank変更、同一matchへの再参加。
- **Timeout**: settlement作成のretryを起動する。
- **遷移**: deterministicなsettlementIdとcanonical SettlementResultを作成して `SETTLEMENT_PENDING`。

### 5.9 SETTLEMENT_PENDING

- **Server保持**: canonical SettlementResult、各projectionの適用状況、retry count、last error。
- **公開**: 結果と「Rating反映中」。内部error詳細は公開しない。
- **許可Intent**: 結果read、session終了確認、reconnect。gameplay Intentは不可。
- **拒否**: clientによるMMR/履歴/leaderboard更新。
- **Timeout**: retry policyに従い未完了componentを再実行する。人手調査が必要な状態はdead-letter相当へ記録するが、二重加算しない。
- **遷移**: 必須componentがすべて同じsettlementId/versionを適用したら `SETTLED`。

### 5.10 SETTLED

- **Server保持**: 完了settlement、適用証跡、保持期限。
- **公開**: final rank、rating delta、表示TierまたはRating、直近履歴への反映結果。
- **許可Intent**: readのみ。新しいqueue参加は新しいsessionとして扱う。
- **拒否**: このmatchへの全mutation。
- **Timeout**: retention policyに従ってhot stateをcleanupする。監査記録は別policyで保持する。
- **遷移**: terminal。

### 5.11 State Machine不変条件

- stateはServerだけが進め、`serverSequence` とstate versionは単調増加し、過去versionへ巻き戻さない。
- state遷移、`serverSequence` 増分、canonical event/outboxは同じ原子的境界で確定する。
- questionIndex変更時は前問題のanswers/answered状態/resultを同時に閉じ、次問題へ持ち越さない。
- clientが古いstateを見て送ったIntentは、処理時のServer stateで再検証する。
- timer、NPC、disconnectもclient Intentと同じOrdering Authorityを通る。
- 回答受付、duplicate拒否、deadline、正誤、回答順、score、question closeはServer Stateだけを正とし、client側の表示やlocal lockだけで確定しない。
- 1Playerの回答は他Playerの回答受付可否を変更しない。

---

## 6. Event Ordering

### 6.1 Ordering Authority

各matchは、回答受付、deadlineとの競合、question close、採点を確定する論理的なOrdering Authorityを持つ。これは常に1つのprocessを起動し続けるという意味ではない。各回答を同じmatch rootのCASへ直列化する方式と、Playerごとに独立受付してquestion close時にcanonical orderingを確定する方式のどちらが適切かは、修正後のProduct ruleに対するPhase A検証後に決める。

順序の基準は次の通り。

1. clientが送信を開始した時刻ではない。
2. Function/Containerが処理を開始・終了した時刻ではない。
3. network到着の推測時刻ではない。
4. **Serverが確定した不変の受付時刻・ordering key・tie-break**を権威順序とする。具体的なprimitiveは未決定とする。

### 6.2 `serverSequence`

- match作成時に0から開始し、match stateとpublic projectionのversionを単調増加させる。
- client Intent、server timer、NPC action、disconnect expiry、forfeitを同じsequence空間へ入れる。
- 同じ `intentId` のretryではsequenceを増やさない。
- public projectionにも最新sequenceを含め、古いprojectionで新しい状態を上書きしない。
- 拒否Intentは、Ordering Authorityへ到達してstate依存で拒否された場合に監査sequenceまたは関連sequenceを残す。認証前の拒否はmatch sequenceへ入れずsecurity logへ記録する。
- 各回答へ即座に連番を付けること自体はProduct要件ではない。全回答を1つのmatch-root CASで `1, 2, 3, 4` と採番するか、Player別受付後にquestion closeでcanonical orderを確定するかは未決定とする。
- どちらの方式でも、受理済み回答は不変のServer-owned受付情報を持ち、再送で二重登録されず、同じ入力から回答順・得点・監査結果を再構築できなければならない。

### 6.3 原子的commitの内容

1回のauthority commitで少なくとも以下を一体として確定する。

- stateBefore / stateAfter
- 次の `serverSequence`
- accepted/rejected outcome
- accepted answer、answered状態、score、deadline等のcanonical state差分
- dedup用 `intentId` 結果
- event recordまたは確実に再送できるoutbox marker

副作用（通知、analytics、履歴、leaderboard）はtransaction callback内で実行しない。commit後にoutbox/eventを冪等処理する。

### 6.4 同時回答

- 4人が同時に回答しても、各Playerの最初の有効な `submitAnswer` をそれぞれ1回受理する。最初の回答を理由に後続Playerを拒否しない。
- 同一Playerの同一 `intentId` 再送は元の結果を返し、別 `intentId` による2回目の回答は `ALREADY_ANSWERED` で拒否する。
- clientの端末時計や表示上の早さで回答順を決めない。Serverが確定した受付情報でcanonical orderを作る。
- 正解者のうちcanonical orderが早いPlayerから20 / 10 / 5 / 1点を付け、誤答は-10点、無回答は0点とする。誤答は正解順位を消費しない。
- authoritativeな受付時刻が完全に同じ場合は開始時のroster/slot順で決める。近接した回答を同着扱いにする追加thresholdの有無はOpen Questionとする。
- answer受付とdeadline/question closeが競合しても、各回答が受理か期限後拒否のどちらか一方へ確定し、close後に回答集合やscoreが変化しないことを必須とする。

### 6.5 Timer / NPC / Disconnect event

- timer eventはdeterministic IDを持ち、重複起動しても1回だけ状態を進める。問題全体のdeadlineは `timer:{matchId}:{questionId}:question` のように識別する。Player別の回答権timeoutは持たない。
- NPC eventもdeterministic IDを持ち、人間Intentと同じstate/deadline検証を受ける。
- disconnect expiryもleaseを再確認してからcommitする。直前にreconnect済みなら拒否する。
- server instanceの停止後、別instanceが同じeventをretryできる。

### 6.6 Public Projectionの順序

- projection updateは `serverSequence` の大きいものだけを適用する。
- canonical stateとpublic projectionを同じtransactionに置けないbackendでは、outboxを正としてprojectionを再構築可能にする。
- clientはsequenceの欠落または逆行を検知した場合、差分推測ではなくsnapshotを再取得する。

---

## 7. Backend Candidates

### 7.1 製品に依存しない確定構造

Phase 0では、次の4層を確定し、Firebase/Google Cloud製品の最終選定はPhase Aの計測後に行う。

1. **Intent Ingress**: Auth/App Check/protocol/inputを検証する。
2. **Per-match Ordering Authority**: Server側のatomic boundaryで回答受付、deadline/close競合、canonical orderを一意に確定する。全回答を1つのCASへ直列化するかは未決定。
3. **Public Projection**: participant clientがread/listenするsanitized状態。client writeは禁止。
4. **Durable Settlement Store**: MMR、Season、history、leaderboard、auditを冪等反映する。

### 7.2 Candidate比較

| Candidate | Ingress / Ordering | 長所 | 主なリスク | Phase Aで測ること |
| --- | --- | --- | --- | --- |
| A. Functions 2nd gen + RTDB transaction | Callable/HTTPで受付、RTDB transaction/CASで受付またはcloseを確定し、RTDB listenerへ公開 | 現行Firebase資産とiOS SDKを活用しやすい。4人へのfan-outが単純 | cold start、transaction retry、match root肥大化、Functions完了とprojection反映差 | warm/cold p50/p95、4同時回答、Player別dedup、deadline/close競合、listener収束 |
| B. Cloud Run HTTP + RTDB transaction | Cloud Runで受付、Aと同じRTDB authority | instance/concurrency/実行環境の制御幅が大きい | Auth/App Check検証を明示実装、運用面増加、RTDBがbottleneckならAとの差が小さい | 認証込みlatency、instance跨ぎ、min instance有無、コスト |
| C. Server-owned per-match sequencer prototype | 単一の論理sequencerがmatch eventを直列処理し、durable fence/CASでownershipを保護する | ordering処理そのものの最小latencyと複雑性を測れる | actor ownership、instance移動、復旧、永続化をProduction水準にすると複雑 | 同時回答の独立受付、Server受付→確定p50/p95、prototype実装量、障害時の限界 |
| D. Functions/Cloud Run + Firestore transaction | HTTP受付、match aggregateをFirestore transactionで更新、projectionをlisten | settlement/auditとのデータモデルを揃えやすい。commit時刻で直列化できる | 高競合docのcontention、listener遅延、event蓄積方法 | 4同時回答contention、p50/p95、retry/error率、projection遅延 |
| E. Queue / Pub/Sub ordering key | audit / settlement等の非同期処理をordering keyで処理 | workload平準化、retry、非同期処理に強い | 追加hop、at-least-once重複、backlog | 非同期処理の重複、redelivery、backlog時挙動。回答受付のhot pathでは比較しない |

### 7.3 Phase Aの推奨検証順

Phase A前半では、少なくとも次の3方式を同じIntentと計測条件で比較する。

1. Candidate A: Functions 2nd gen + RTDB transaction。
2. Candidate D: Functions/Cloud Run + Firestore transaction。
3. Candidate C: Server-owned per-match sequencerの小規模prototype。

Candidate CではProduction WebSocket基盤を完成させない。単一の論理Ordering Authorityで同時回答を処理した場合のlatency、Player別dedup、実装・復旧の複雑性を測る。Candidate BはIngressや実行環境差を分離して測る必要がある場合に追加する。Candidate Eは回答受付のhot pathから外し、settlement、audit、再試行pipelineの候補としてのみ評価する。

これは採用決定ではない。BackendはPhase Aの実測、運用複雑性、費用、障害復旧を合わせて決定する。

### 7.4 小規模Latency Spike

UIと本番schemaを作る前に、非本番環境で4client harnessを用意し、同一のIntent contractで候補を比較する。

計測点:

1. client intent send
2. server ingress receive
3. authority transaction/CAS start
4. authority commit
5. public projection publish
6. 各client projection receive

集計:

- client send → server receive のp50/p95
- server receive → authority commit のp50/p95
- authority commit → 各client receive のp50/p95
- end-to-endのp50/p95
- warm / cold、min instance有無、4人同時、duplicate、retry、instance分散を分ける
- error率、transaction retry回数、client間の最大反映差も記録する

暫定Engineering target:

- Server intent受付 → ordering確定: **p95 150ms以内を理想値**として測る。
- Client送信 → 確定結果がclientへ反映されるRound Trip: **p95 300ms程度以内**を暫定目標として測る。
- 両区間ともp50とp95を記録し、warm/coldや競合条件を分けて比較する。
- これらは最終SLA・保証値ではなく、Backend比較とbottleneck特定の基準である。
- 実測値、ordering一意性、実装複雑性、費用、障害復旧を合わせて最終Architectureを判断する。

機能的な合格条件:

- 4人の有効な同時回答がPlayerごとに1件ずつ受理される
- 同一Playerのduplicate/retryが二重回答・二重加点にならない
- deadline直前回答とquestion closeの競合で、受理済み回答集合・正誤・得点が一意に確定する
- canonicalな回答順から現行ルールと同じ20 / 10 / 5 / 1、誤答-10、無回答0を再現できる
- `serverSequence` が単調増加
- duplicate Intentで二重更新しない
- stale epochを拒否する
- reconnect後に全clientが同じsnapshotへ収束する
- private correct answerがclient payloadへ混入しない

Productionで保証する最終latency、latency compensation方式・上限、near-tie threshold、min instance等の具体値は未決定とする。

### 7.5 Region

- Ingress、Ordering Authority、公開projection、主要databaseは可能な限り同一または近接regionに配置する。
- 現行Functionsの `asia-northeast1` を理由だけにCompetitiveのregionを固定しない。実際のRTDB/Firestore location、利用者分布、計測結果を確認して決める。
- 異なるregionをまたぐ構成は、latency spikeと障害時挙動を確認せず採用しない。

### 7.6 Cost Guardrail

- 初期段階のFirebase / Server費用は月3,000円程度を目安とする。これはHard capではない。
- Security Invariantsを費用だけを理由に弱めない。
- minInstances、常時稼働Server、専用sequencer等により月3,000円を大きく超える可能性があるArchitectureは、採用前のArchitecture Decision Gateで見積根拠と効果をユーザーへ報告する。

### 7.7 Phase A-1 Architecture Decision（2026-09-30）

Phase A-1のlocal / actual Cloud Spikeとユーザーレビューを根拠に、Phase A-2のbackend baselineとして次を正式採用する。これはProduction Ready宣言ではなく、Production Security、failure recovery、公開projection等はPhase A-2で設計・検証する。

- Firebase Functions 2nd genをCompetitive IntentのIngressとServer処理に使用する。
- Firebase Realtime Databaseをauthoritative match stateの中心に使用する。
- ClientはIntentだけを送信し、正誤、得点、順位、deadline、resultを確定しない。
- 回答はPlayer別create-only領域`answers/{playerId}`へ各Player1件だけ保存する。
- 回答時刻のAuthorityはRTDB Server timestampとし、Client timestampとFunction instance clockを使用しない。
- `QUESTION_RESULT`確定時にServerがcanonical ordering、正誤、得点、resultを確定する。
- 完全同timestampは試合開始時に固定したparticipant順で決定する。
- 回答順位のために全回答へglobal sequenceを即時CAS採番しない。

actual Cloud Independent Answer Spikeでは、Tokyo Macから`asia-southeast1`のFunctions / RTDBを使用し、4 Function instance、40 measured round、160 answer Intentを検証した。40/40 round、160/160 answer受付、欠損・overwrite・他Player干渉・normal contention retryはいずれも0だった。warm latencyはT1→T2 p50 77.829ms / p95 96.307ms、T0→T3 p50 176.653ms / p95 197.892msだった。deadline / close、duplicate / retry、canonical ordering、代表scoreも一意に収束した。詳細証拠は`COMPETITIVE_V2_BACKEND_SPIKE.md`を正とする。

Client contractはRTDBの物理path / schemaへ直接依存させない。Clientから見える境界は`submitAnswer Intent → Competitive Backend → authoritative result`とし、Functions / RTDBはServer実装詳細へ閉じ込める。将来backendを変更してもClient Intent、Match State Machine、Product rule、Question contractを可能な限り維持できるadapter境界を置く。

Candidate Cは否定・削除せずfallbackとして保持する。Firebase方式でlatency、contention、persistent state、realtime projection、費用、SecurityのProduction要件を満たせない場合に再検討するが、現時点では実装・Cloud Spikeを行わない。

---

## 8. Question Security

### 8.1 Server-only Question Bank

- Competitiveは専用のServer-side Question Bankを使用する。端末同梱データを試合判定の権威sourceとして読まない。
- 既存の英単語・SPIコンテンツ自体は、権利と品質を確認したうえで可能な限り変換・再利用する。ただし、Competitive用のcanonical ID、version、選択肢対応、correct answerはServer-side Question Bankへ取り込む。
- Rulesでclient readを拒否し、server credentialだけが読む。
- 問題中のclientへcanonical ID、正解index、正解文字列、seedを送らない。
- serverは出題時にmatch固有のopaque `questionId`（内部ではquestion instanceを表す）とopaque `answerId` を生成する。

### 8.2 Clientへ公開する内容

`QUESTION_OPEN` では、現在問題のcontentとして次だけを公開する。

- match固有でopaqueな `questionId`
- prompt
- 表示順が確定したchoices（各choiceはopaque `answerId` と表示文字列を持つ）

進行に必要なdeadline、公開score、非秘密category等は別metadataとして配信できるが、回答受付中に `correctAnswer`、正解index、canonical question IDを配信しない。

Server基準のanswer deadlineと表示に必要な非秘密metadataを除き、question contentを追加配信しない。

`submitAnswer` は `answerId` だけを送り、serverが内部mappingで正誤を判定する。

### 8.3 結果公開

- correct answerは `QUESTION_RESULT` 以後、答え合わせに必要な範囲で公開する。
- 監査用canonical IDはpublic projectionへ含めない。
- event logに正解情報を残す場合も、participantが直接読めるlogと分離する。

### 8.4 端末同梱word bankのreverse lookupリスク

現行アプリには英単語データに加えてSPI問題JSONも同梱され、問題文、選択肢、正解、解説を端末内で読める。これらとCompetitive問題が同一なら、promptからlocal dataを逆引きされる可能性がある。opaque IDだけではこの攻撃を防げない。

また、現行フレンドバトルの `RoomState.QuestionPayload` は進行上必要な `answer` を全参加clientへ配る契約である。このpayloadは現行モード専用として維持し、Competitiveのquestion payloadやserver判定には再利用しない。

初期方針:

- Competitive corpusとcontent versionはserver側で管理する。
- client assetのrow IDや固定順をCompetitive payloadへ再利用しない。
- 選択肢順とanswerIdをmatch/questionごとに変える。
- 出題頻度、異常に短い回答、正答率等をserver側で監査できるようにする。

外部辞書、OCR、改造端末、手動協力を含む自動解答の完全防止はNon-goalである。防ぐ対象は、payloadからの正解漏えい、clientによる正誤指定、静的IDの単純逆引き、replayである。

### 8.5 未決定事項

- 既存英単語/SPIからCompetitive bankへ変換・再利用する具体範囲と権利確認
- Server-side Question Bankの更新・review・rollback方法
- 問題の重複回避期間
- content version更新中のactive match取り扱い

---

## 9. Hidden MMR

### 9.1 単一評価値

- player/seasonごとにserver-ownedのMMRを1つだけ持つ。
- Rank PointとRatingを別々に増減させる二重評価は作らない。
- Tier、Rating Zone、leaderboard順位は同じMMRから導出する表示またはprojectionである。
- clientからMMRをwriteできない。

### 9.2 表示

- Rating Zone未満: exact MMRを隠し、configVersionに固定された閾値から表示Tierを導出する。
- Rating Zone: exact MMRを数値Ratingとして表示する。
- APIは権限とzoneに応じたsanitized displayを返す。通常帯のclientへhidden MMRを送らない。
- Top 20 leaderboardはRating Zoneを基本対象とし、seasonとtie-break ruleを固定する。

### 9.3 更新

- MMR更新は `SETTLEMENT_PENDING` 以後だけ行う。
- SettlementResultに `mmrBefore`、`ratingDelta`、`mmrAfter`、formula/configVersionを固定する。
- reconnect、画面再表示、履歴取得で再計算しない。
- 同じsettlementIdをplayerへ再適用してもMMRは1回分しか変化しない。

### 9.4 未決定事項

- 初期MMR、provisional match数
- Tier境界とRating Zone境界
- 4人順位からdeltaを求める式
- forfeit penalty
- Season reset/carry-over
- leaderboardの同率順位規則

これらは1つのversioned configとしてserver側で固定し、active match途中に変更しない。

---

## 10. NPC Policy

### 10.1 Matchmaking方針

- 4枠に満たない低ランク帯ではserver-owned NPCを投入できる。
- 最下位帯は短い待ち時間または即時補充を許可する。
- 中間帯はhumanを優先し、設定された待機時間後にのみNPCを補充する。
- 上位TierとRating Zoneはhuman 4人のみとし、NPCを投入しない。
- 境界、待機時間、許容NPC数はversioned matchmaking configで管理する。

### 10.2 Server ownership

- NPCのprofile、strength、擬似MMR、反応時間、answer、correctness、scoreはserverが生成する。
- NPC eventは人間Intentと同じOrdering Authorityを通し、未来の行動をclientへ送らない。
- NPCも各問1回だけ独立回答し、人間と同じauthoritative orderingと20 / 10 / 5 / 1、誤答-10、無回答0の得点規則を使う。
- NPCは実UID、client session、leaderboard entry、player history、永続MMRを持たない。
- public projectionではNPCであることを明示する。

### 10.3 MMRへの影響

- humanの結果はNPC数に応じてrating deltaを減衰できる。
- NPC入り試合を通常の4-human試合より高い価値にしない。
- 減衰式はsettlement configへversion固定し、client計算にしない。
- NPC自身にはsettlementを作らない。

### 10.4 再利用境界

現行のFirebase非依存NPCロジックは、決定論的入力とServer RNG seedを受け取れるpure moduleとして利用できる場合に限り再利用候補とする。iOS端末がNPC結果を生成してserverへ送る設計は採用しない。

---

## 11. Session / Lease / Epoch

### 11.1 Session State

1 UIDにつきactive Competitive sessionは最大1つとする。

```text
IDLE -> QUEUED -> MATCHED -> PLAYING -> RECONNECTING -> FINISHED -> IDLE
```

実装上は遷移を短絡できるが、sessionの権威状態はserverが管理する。

### 11.2 Session fields

```text
CompetitiveSession
  uid
  sessionId
  sessionEpoch
  state
  matchId?
  leaseExpiresAt
  lastHeartbeatAt
  protocolVersion
  configVersion?
  updatedAt
```

- `sessionId`: sessionごとの予測困難なID。
- `sessionEpoch`: UIDごとに単調増加するfencing token。
- `leaseExpiresAt`: server clockで設定する期限。clientは直接延長値を書けない。
- `matchId`: MATCHED以後にserverが設定する。

### 11.3 Session作成とfencing

- `joinQueue` はUIDのsession recordをtransaction/CASで検証する。
- 有効なactive sessionがある場合は二重作成せず、既存sessionへの復帰情報を返す。
- 期限切れsessionを置き換えるときはepochを増やす。
- 全IntentがsessionId/epochを照合し、旧端末や遅延packetを拒否する。
- matchとsessionのepochをroster snapshotにも固定し、match途中の別sessionが同じslotを奪えないようにする。

### 11.4 永久lock防止

- leaseは有限で、server cleanup/reconciliationが期限切れsessionを回収できる。
- cleanupが一度失敗しても、次回 `joinQueue` がserver側で安全に期限切れを判定できる。
- clientの明示leaveだけにlock解除を依存しない。
- session終了とsettlement失敗を分離し、settlement retry中でも永久に新規queueを禁止しない。

### 11.5 Phase B Identity / Matchmaking実装契約

Competitiveのcanonical identityはFirebase Auth UIDとする。Anonymous Authも同じUIDで利用でき、将来Sign in with Apple等へ**linkしてUIDを維持する**限り、match、rating、historyのownership移行は不要である。別UIDの既存accountへsign-inする場合の統合policyは後続Identity Gateとし、Phase B schemaはUID以外をownership keyにしない。

Phase Bの物理pathは次を基準とする。

```text
competitiveV2/matchmaking/private/profiles/{uid}
competitiveV2/matchmaking/private/queue/{uid}
competitiveV2/matchmaking/private/pendingMatches/{matchId}
competitiveV2/matchmaking/public/{uid}
competitiveV2/matches/{matchId}
```

- `private`全体はAdmin SDK専用で、client read/writeを許可しない。
- `public/{uid}`は認証済み本人だけがreadでき、queue全体、他UID、hidden matchmaking値、session auditは公開しない。
- profileはaccount type/status、最新epoch、current session、protocol、server-owned matchmaking bucketだけを持つ。MMR、visible rank、season/historyはまだ持たせない。
- Phase B暫定queue leaseは5分とする。これはProduct保証値ではなく、heartbeat/reconnect実装時にversioned configへ移す。
- `joinQueue`の同一`intentId`再送は同じsessionへ収束する。新しいjoin IntentはQueue中だけepochを増やして旧sessionをfenceし、`MATCH_FOUND`以後は`ACTIVE_MATCH_EXISTS`で拒否する。
- `cancelQueue`は同じsessionId/epochの`QUEUED`だけを終了できる。match claim後は`MATCH_ALREADY_ASSIGNED`とし、commitment boundary以後のforfeitには読み替えない。

Matchmakingは`competitiveMatchmaking` callableの`joinQueue`受理後に必要最小限のattemptを実行する。常時server、scheduled polling、Pub/Sub hot pathは使用しない。

Atomic claimは`competitiveV2/matchmaking` rootのRTDB transactionで、4 UIDのsession fence確認、queue removal、`MATCH_FOUND`、active match、assignment ticket、pending match manifestを一度に確定する。Phase A-2 matchは別pathのため、claim後に同じ`matchId`へcreate-if-absentで作成し、最後に各projectionを`WAITING_PLAYERS`へ進める。Functionが途中失敗してもpending manifestから同じmatchを再作成・finalizeでき、別matchへ同じUIDをclaimできない二段階idempotent構造とする。Match作成は既存Competitive Coreのfactory/state machineを再利用し、別Battle engineを作らない。

現Phase Bでは全Playerを同一の暫定bucketへ入れる。将来MMRをServer-owned profile値からbucket/search rangeへ入力できる境界は維持するが、client指定MMR/rankはcontractで拒否する。

費用はqueue操作ごとのcallable invocationとRTDB transaction/read/writeだけで、minInstances、常時worker、scheduled pollingを追加しない。概算上、4人成立あたりjoin 4 invocation、各join/session transaction、matchmaking attempt、match create 1回、finalize 1回である。初期トラフィックでは月3,000円目安と矛盾しないが、単一bucketのmatchmaking root transactionは利用者増加時にshard化判断が必要である。

---

## 12. Disconnect / Reconnect

### 12.1 検出

disconnect判定はclientの自己申告だけに依存しない。次を組み合わせる。

- serverが受理したheartbeat / Intent activity
- server-owned lease
- transport disconnect signal（利用backendが提供する場合）
- deadline時点での再検証

### 12.2 Grace

- transport切断、heartbeat欠落、またはapp終了を検出しても即時敗北にせず、sessionを `RECONNECTING` としてgrace期間を与える。
- grace中もmatchのServer clockと他playerの進行を止めない。
- 再接続時はsessionId、epoch、matchIdを検証し、最新snapshotとsequenceを返す。
- grace内に戻れば同じslotへ復帰する。
- grace超過はserver eventとしてOrdering Authorityへ投入し、開始後はforfeit、開始前はno-show/abort扱いとする。

### 12.3 Explicit leave

- Queue中およびcommitment boundary前のleaveはqueue/match cancelとして扱い、原則MMR penaltyなし。
- 4枠確定後にCOUNTDOWNを開始するcommitment boundary以後の明示的leaveは原則forfeit。
- client UIは開始後の退出結果を明示するが、clientが「penaltyなし」を指定できない。
- app終了・network lossは明示的leaveと同一扱いにせず、`RECONNECTING` とgraceを経由する。

### 12.4 Server側障害

- Ordering Authority、database、projection等のServer側障害はPlayerのleaveやforfeitとして記録しない。
- 継続不能ならmatchをServer faultとしてabortし、Playerへ敗北・MMR penaltyを適用しない。
- 部分的に進んだstateはcanonical event/outboxから復旧し、復旧不能時もclient申告値で結果を補完しない。

### 12.5 未決定値

- heartbeat間隔
- lease長
- reconnect grace長
- 未回答Playerが問題中に切断した場合、deadlineとreconnect graceのどちらを優先するか
- match継続可能な残human数

これらはlatency spikeと実機network testの結果を踏まえて決める。

---

## 13. Settlement

### 13.1 方針

分散storage全体での「厳密に1回だけ実行」を前提にしない。canonical settlementを1件作り、各反映先へ**少なくとも1回retryしても、結果は1回分だけ適用される**設計にする。

### 13.2 Identity

- `settlementId`: `matchId` と `settlementVersion` から決まるdeterministic ID。
- `settlementVersion`: settlement schema/計算契約のversion。
- `configVersion`: MMR、NPC減衰、forfeit等の計算設定。
- MatchResultから同じSettlementResultを再構築できる。

### 13.3 適用対象

COMPLETED matchでは次を適用する。

- 各human playerのMMR
- 表示Tier / Rating Zone projection
- season stats
- 直近試合history
- Top 20 leaderboard projection
- audit / anomaly data

NPCにはMMR、history、leaderboardを適用しない。

Server faultによるABORTED matchは、監査と障害記録だけを残し、MMR、敗北数、通常の対戦history、leaderboardへ適用しない。

### 13.4 冪等適用

- 各player recordは最後に適用したsettlement、または適用済みsettlement markerを持つ。
- 更新transactionで `settlementId/version` を比較し、適用済みなら成功扱いで終了する。
- history itemはsettlementIdをdocument/item IDとして重複を防ぐ。
- leaderboardはMMR/season recordから再構築できるderived projectionとする。
- audit eventもdeterministic IDで重複を防ぐ。

### 13.5 Status

```text
SettlementStatus
  CREATED
  PLAYER_RATINGS_APPLIED
  HISTORY_APPLIED
  LEADERBOARD_APPLIED
  AUDIT_RECORDED
  COMPLETED
  RETRYABLE_ERROR
  MANUAL_REVIEW_REQUIRED
```

実装ではcomponent別statusを持ち、順番が前後しても最終的に全必須componentが完了すればよい。clientへは内部errorではなく、pending/completedと確定済み結果だけを返す。

### 13.6 Last 5 history

- UIは直近5試合を表示する。
- 保存件数を5件に切り詰めるか、より長く保持してqueryで5件返すかはretention/privacy方針と合わせて決める。
- historyはserver-createdで、clientから追加・順位変更できない。

---

## 14. Logging

### 14.1 Event Log fields

競技判定の監査eventは少なくとも次を持つ。

- `eventId`
- `eventType`
- `matchId`
- `serverSequence`
- `intentId`（client Intentの場合）
- `sessionId` と `sessionEpoch`
- `playerId` またはNPC ID
- `stateBefore` / `stateAfter`
- `questionId`
- `accepted` / `rejectionCode`
- `serverReceivedAt`
- `authorityCommittedAt`
- `projectionPublishedAt`
- `protocolVersion` / `serverVersion` / `configVersion`
- `region` / backend candidate識別子
- retry count、cold/warm等の診断属性

scoreや回答内容は監査に必要な最小限とし、public logとprivate auditを分離する。

### 14.2 禁止するlog

- Auth token、refresh token
- App Check / App Attest raw token
- Secret、API key、service credential
- email、電話番号等の不要な個人情報
- 問題中にclientから読める場所へのcorrect answer
- clientへそのまま返すbackend stack trace

UIDはpseudonymous identifierとしてもアクセス制御・保持期限の対象にする。分析用途では可能なら別のpseudonymous IDへ変換する。

### 14.3 Retention / TTL

- active matchのhot event/outbox: settlementと再接続に必要な短期保持。
- competitive audit: dispute、不正調査、障害解析に必要な期間。
- raw latency trace: 集計後に短期TTL。
- aggregate metrics: 個人を特定しない形で長期保持可能。
- manual review record: accessを限定し、削除手続きを定義する。

具体的な保持日数、ユーザーデータ削除時の扱い、法務/プライバシー要件は未決定とする。TTL削除は即時性をsession lease判定へ利用せず、論理的なexpiryをserverが判定する。

### 14.4 Observability

- p50/p95 end-to-end latency
- Intent accept/reject/duplicate率
- state別滞在時間
- transaction/CAS retry率
- disconnect/reconnect/forfeit率
- settlement pending時間とretry率
- protocol mismatch、App Check failure、rate limit
- 問題ごとの異常な正答率・回答時間（不正検知用）

---

## 15. Protocol Version

### 15.1 Version種別

- `protocolVersion`: client/server間のIntent、ack、projection契約。
- `serverVersion`: 実行backendのdeploy/build識別子。
- `configVersion`: matchmaking、state timeout、MMR、NPC、問題content等の設定snapshot。
- `settlementVersion`: settlement schemaと適用アルゴリズム。

### 15.2 Compatibility

- Serverは対応するprotocol rangeとminimum supported versionを持つ。
- 互換性のないclientは `PROTOCOL_UNSUPPORTED` または `UPGRADE_REQUIRED` で拒否する。
- 古いclientのためにSecurity RulesやServer validationを緩めない。
- additiveなoptional fieldとbreaking changeを区別する。
- active matchは開始時のprotocol/config versionを最後までpinし、deploy途中で判定が変わらないようにする。

### 15.3 Rollout

- 新旧server versionが同時稼働しても、同じprotocol/configに対して同じ判定になる契約テストを持つ。
- breaking protocolはserverが両versionを扱える移行期間を設けるか、minimum versionを明示的に上げる。
- clientに未知stateを黙って通常stateとして扱わせない。安全なエラーと再取得へ移行する。

---

## 16. Security Invariants

以下はCompetitive Modeの実装・Rules・運用で常に守る。

1. 全IntentにFirebase Authを要求し、UIDは認証contextから取得する。
2. App Checkを導入し、本番iOSはApp Attestを基本候補とする。Debug providerは非本番だけで使用する。
3. App Checkは段階的にmonitor → 観測 → enforceし、正規clientを遮断しないことを確認してから強制する。
4. Competitive match、score、rank、correctness、MMR、settlementへのclient direct writeを禁止する。
5. clientは自分が参加するmatchのsanitized public projectionだけを読む。
6. question bank、correct answer、NPC future action、private auditはclient readを拒否する。
7. Intentごとにstate、ownership、session epoch、question、deadline、payload size、列挙値を検証する。
8. `intentId` とdeterministic server event IDでreplay/duplicateを防ぐ。
9. UID/session/device/IP等の適切な単位でrate limitを行う。IPはprivacy要件を確認して必要最小限にする。
10. server clockだけをdeadline、response time、leaseの権威にする。
11. session epochをfencing tokenとして使用し、旧sessionからの遅延Intentを拒否する。
12. server credentialとsecretはSecret Manager等の管理領域に置き、アプリbundle、repo、logへ含めない。
13. Production logにtoken、secret、個人情報、問題中の正解を出さない。
14. Rulesはdeny by defaultとし、公開が必要なpath/fieldだけを許可する。
15. collection/list queryは上限、index、paginationを持ち、無制限read/writeを許さない。
16. active match、session、queue、settlementにreconciliation/cleanup経路を持ち、永久lockを作らない。
17. 旧client互換性を理由に、新しいSecurity境界を迂回するlegacy write pathを作らない。
18. Server/Admin SDKがRulesを迂回することを前提に、backend code自体で同等以上のauthorizationを行う。
19. match stateとevent/outboxの原子性、projectionのsequence単調性を維持する。
20. Security invariantを満たさないbackend candidateは、latencyが良くても採用しない。

---

## 17. Open Questions

### 17.1 Phase A-1で解決済み

1. Backend baselineはFunctions 2nd gen + RTDB中心のCandidate A系を採用した。
2. 回答はPlayer別に独立受付し、question close時にcanonical orderを確定する。回答順位用のglobal sequence即時CASは使用しない。
3. Candidate Cはfallbackとして保持し、現時点では追加Cloud Spikeを行わない。

### 17.2 Phase A-2 Production Cloud / Phase B以降で技術検証して決める

1. Functions Ingressをcallable / HTTPのどちらで公開し、Auth UID / authorizationをどう検証するか。
2. App Check / App Attestのmonitor、観測、enforce手順とreplay protection対象Intent。
3. private question dataとRTDB public projectionの物理path / schema / listener contract。
4. answer write成功後にFunctionがresponse前に失敗した場合の冪等ack、retry、reconciliation。
5. region、min instances、concurrency、COUNTDOWN中warm-up、retry/backoff。
6. HTTP acknowledgementからpublic projection反映までのend-to-end latency。
7. latency compensation方式・上限とnear-tie threshold。Client自己申告時刻はAuthorityにしない。
8. heartbeat間隔、lease長、reconnect graceの具体秒数。
9. 未回答Playerの切断時にquestion deadlineとreconnect graceをどう組み合わせるか。
10. authority eventとprojectionの保存・compaction方法。
11. 実match trafficを使ったFunctions / RTDB / logging / egress費用と月3,000円目安との差。
12. Phase B暫定5分queue lease、heartbeat間隔、期限切れsession回収の最終値。
13. hidden MMR導入時のbucket数、search range拡大、global matchmaking transactionのshard単位。
14. Anonymous UIDを既存linked accountへ統合する場合のProduct policy。credential linkでUIDを維持する通常経路はschema変更不要。

### 17.3 Phase C前にプロダクト判断が必要

1. Hidden MMR計算式、初期MMR、provisional期間。
2. Tier境界とRating Zone境界。
3. Bronze/SilverそれぞれのNPC投入待機時間、search range拡大、最大NPC数。
4. NPC数別のMMR減衰式。
5. Season期間とSoft reset方式/carry-over。
6. Top 20 leaderboardの同率順位規則。
7. last 5以外のhistory保持件数。

### 17.4 Phase D前に運用判断が必要

1. audit/raw trace/historyの保持日数と削除policy。
2. 不正疑いのmanual reviewとappeal手順。
3. alert閾値、on-call/障害時のCompetitive停止方法。
4. minimum protocol versionを上げるrollout手順。
5. 自動scale上限、budget alert、費用超過時の停止方法。

---

## 18. Phase A-D Split

### Phase A-1: Architecture Spike（完了）

目的はbackendを実測で選ぶこと。Production機能は作らない。

- Functions 2nd gen + RTDB transactionの4client latency spike
- Functions/Cloud Run + Firestore transactionの4client latency spike
- Server-owned per-match sequencerの小規模prototype。Production WebSocket基盤は作らない
- 4人の独立した同時回答、Player別duplicate、deadline/close競合、stale epoch、reconnect、instance分散の検証
- p50/p95、retry率、コスト、運用複雑性を同条件で比較
- Server受付 → ordering確定p95 150ms以内、client Round Trip p95 300ms程度以内という暫定Engineering targetとの差を記録
- Backend decision recordの作成

既実施のFirst-winner SpikeはRTDB CASのcontention、correctness、latency、retry、Cloud挙動を示す技術資料として保持するが、Production Competitiveの回答モデルを直接再現していない。修正後のProduct ruleに対するArchitecture判断の根拠としては、4人の独立回答と採点closeを扱う追加検証が必要である。

Phase A-1完了結果:

- [x] Candidate A系（Functions 2nd gen + RTDB中心）をPhase A-2のbaselineとして採用した。
- [x] 4人の有効回答、duplicate/retry、deadline/close、canonical ordering、得点のlocal / actual Cloud証拠を記録した。
- [x] answer acknowledgementのT1→T2 / T0→T3 p50/p95と暫定targetとの差を記録した。
- [x] Candidate Cをfallbackとして保持し、現時点で追加検証しないと決定した。

### Phase A-2: Competitive Core（Production検証済み）

目的は、固定された人間4人の1試合をserver-authoritativeに20問最後まで通し、Clientからbackend実装を隠す契約境界とSecurity・復旧・projectionの骨格を確定することである。

- Intent envelope、ack、error code、protocol/config versioning
- Firebase Auth UIDとroster / session / ownershipのServer検証。Client指定playerIdを信用しない
- 固定4 Playerの `WAITING_PLAYERS → COUNTDOWN → 20 Questions → MATCH_FINISHED`
- 各Playerの独立回答、Player別create-only受付、canonical ordering、正誤、score、最終順位のServer判定
- Server-only test Question Bankと、prompt / choices / match state / resultだけを含むpublic projectionの分離
- 同じevent / 既存accepted answerを識別するidempotent answer API
- deadline / all-answered closeと、answer / close競合の一意な収束
- 4 Clientが同じpublic projectionをRealtimeに観測する経路
- App Check / App Attestを追加できる境界。単独のSecurity Boundaryにはしない
- backend-neutralな `CompetitiveService → Intent → Backend → authoritative projection` 境界
- Local / Emulatorでは20問完走、Rules、Security Gate、scoring parity、Realtime projectionを検証済み
- Production Cloudでcold / warm、T0〜T4、実Rules / Functions、4 Client同期、4人×20問を検証済み

Phase A-2完了条件:

- [x] 固定4 PlayerがLocal / Emulatorで20問を完走する。
- [x] Auth / authorization、private/public data境界、duplicate/retry、deadline closeをcontractとtestで確認する。
- [x] 現行フレンドバトルとのscoring parityと4 ClientのRealtime projection一致を確認する。
- [x] Production Cloudでcold / warmとpublic projectionを含むT0〜T4 latencyを記録する。
- [x] Production Rules / Functionsを隔離E2Eで確認し、一般公開前のSecurity Gateへ引き継ぐ。

**Production Performance Release Blocker:** 4人同時answer時、match root transactionの競合/retryによりT1→T2がp50約702ms、p95約1,143msとなった。ordering fidelityは40/40 round、pair 240/240一致、inversion 0である。Architecture Decision Gateではないが、一般公開前にtransaction範囲の局所最適化と同条件の再測定を必須とする。Matchmaking処理は別root/callableに分離し、answer hot pathへ混ぜない。

Matchmaking、Hidden MMR、Rank、Production NPC、Settlement、Season、LeaderboardはPhase A-2へ含めない。

### Phase B: Identity / Matchmaking Foundation

目的は、Phase A-2のCompetitive Coreをユーザー向けのIdentity、queue、match assignment、再接続経路へ接続することである。

- canonical identityはFirebase Auth UID。Anonymous Authを維持し、将来のlinked-only policyはUIDを維持するcredential linkで後付けする
- Server-owned minimal profile、one UID = one active session、session epoch fencing
- `NOT_QUEUED → QUEUED → MATCH_FOUND → WAITING_PLAYERS → COUNTDOWN`のqueue lifecycle
- callable join時のrandom matchmaking、4 Human確定、Phase A-2 match assignment
- matchmaking root transactionによる4 Player atomic claimと、pending manifestによるidempotent match finalize
- clientは`joinQueue` / `cancelQueue` Intentと本人用projectionだけを使用し、UID/MMR/rank/matchId/participantsを指定しない
- reconnect grace、forfeit詳細、heartbeat運用、MMR/Rank/NPC/Settlementは後続Phaseへ残す

Phase Bでは本格MMR、Season、Leaderboard、Production NPCをまだ有効化しない。

### Phase C: Rating / NPC / Season / Leaderboard

- 単一hidden MMR、Tier、Rating Zone
- Tier別NPC補充、server-owned NPC action
- NPC数に応じたrating delta
- Season、Top 20 leaderboard、直近5試合history
- settlementの全projection
- プロダクトバランスsimulationと負荷検証

### Phase D: Security / Operations / Production Rollout

- App Check/App Attest enforcement
- Rules deny-by-defaultとread scopeの最終化
- rate limit、abuse detection、manual review
- load、chaos、duplicate、cold start、regional failure検証
- log/TTL/privacy/deletion運用
- protocol minimum versionと段階rollout
- dashboard、alert、kill switch、reconciliation
- 本番deploy前Security reviewとE2E

Phase Dのgateを通るまで、Competitiveを本番利用可能として扱わない。

---

## 参考資料

- [Firebase Realtime Database transactions](https://firebase.google.com/docs/database/admin/save-data)
- [Cloud Functions 2nd gen concurrency and scaling](https://firebase.google.com/docs/functions/manage-functions)
- [Firebase callable functions and automatic Auth/App Check token handling](https://firebase.google.com/docs/functions/callable)
- [Cloud Run WebSockets](https://docs.cloud.google.com/run/docs/triggering/websockets)
- [Firestore transaction contention and serializability](https://firebase.google.com/docs/firestore/transaction-data-contention)
- [Pub/Sub ordered delivery](https://docs.cloud.google.com/pubsub/docs/ordering)
- [Firebase App Check for custom backends](https://firebase.google.com/docs/app-check/custom-resource-backend)
- [Firestore TTL behavior](https://firebase.google.com/docs/firestore/ttl)

---

## Phase 0 Exit Check

- [x] Server authoritativeとTrust Boundaryを定義した。
- [x] 現行フレンドバトルの独立回答・得点規則をCompetitiveのProduct rule基準として定義した。
- [x] Client IntentとServer-owned Resultを分離した。
- [x] Match State Machineとstate別の許可/拒否/timeoutを定義した。
- [x] 単一Ordering Authorityと `serverSequence` の条件を定義した。
- [x] Backend候補、比較軸、latency spikeを定義した。
- [x] Question security、hidden MMR、NPC policyを定義した。
- [x] Session/lease/epochとdisconnect/reconnectを定義した。
- [x] Idempotent settlement、logging、protocol、security invariantsを定義した。
- [x] 未決定事項をPhase別に分離した。
- [x] Phase A-Dの責務とgateを定義した。
- [x] Competitive本実装、deploy、現行フレンドバトル変更を行っていない。
