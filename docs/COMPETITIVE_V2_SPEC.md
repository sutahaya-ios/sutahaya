# Competitive Mode v2.0 Phase 0 Specification

- Status: Phase 0 design baseline
- Last updated: 2026-09-28
- Scope: Competitive Mode v2.0 only
- Implementation status: Not started

## この文書の位置づけ

この文書は、Competitive Mode v2.0 の契約と設計判断を管理する Single Source of Truth（SSOT）である。

- 現行のフレンドバトルは `docs/ARCHITECTURE.md` と既存実装を正とする。
- Competitive Mode は現行フレンドバトルと別のAPI、状態、Rules、保存領域を持つ。
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
2. score、正誤、順位、勝者、buzz順、回答時間、MMR、rating差分、NPC結果をサーバーが確定する。
3. クライアントは操作の意図（Intent）のみを送信し、確定値を直接書き込まない。
4. 1試合内の全イベントに、再現可能な単一の論理順序を与える。
5. 低ランク帯では不足枠をNPCで補い、上位帯では人間のみで対戦する。
6. プレイヤー評価値は1種類の非公開MMRに統一する。
7. 通常帯ではMMRから導出したTierを表示し、Rating Zoneでは数値Ratingを表示する。
8. Season、Top 20 leaderboard、直近5試合の履歴を提供する。
9. 再送、重複実行、一時切断、サーバー再起動があっても、試合とsettlementを安全に収束させる。
10. 現行フレンドバトルを壊さず、Competitive固有の信頼境界を維持する。

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
- 共用してよいのは、Firebase非依存の表示部品、問題表示、音、pure battle logicなど、信頼境界を越えない部品に限る。
- Competitiveのサーバー確定値を既存のhost-authoritativeモデルへ変換する場合は、専用adapterを境界に置く。既存型をそのまま権威データモデルとして再利用しない。

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
| Server clock | 権威時刻 | deadline、buzz順、lease、回答時間に使用する |
| Ordering Authorityのcommit順 | 試合内の権威順序 | `serverSequence` を採番する |
| Server-owned question bank | 秘密情報 | 正解や内部IDを問題中のclientへ送らない |
| Public match projection | 読取用の確定表示 | clientからのwriteを禁止する |
| Settlement record | Rating更新の根拠 | immutableかつ冪等に適用する |

### 2.2 Clientから送ってよいもの

- Intent種別
- client生成の一意な `intentId`
- serverから払い出された `sessionId`、`sessionEpoch`、`matchId`、ticket
- 操作対象を示すopaque ID（例: `questionInstanceId`、`answerId`）
- clientの対応 `protocolVersion` とapp build情報
- 再接続時の最後に観測した `serverSequence`

### 2.3 Clientから送ってはいけない確定値

- score、score delta、rank、winner
- correctness、correct answer、failed判定
- buzzOrder、acceptedAt、responseTime
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
  questionInstanceId: OpaqueID?
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
| `buzz` | matchId、questionInstanceId | QUESTION_OPEN、回答資格、deadline前、未buzz | Ordering Authorityが採用/拒否 |
| `submitAnswer` | matchId、questionInstanceId、answerId | ANSWERING、active responder本人、deadline前、answerId有効 | Serverが正誤と得点を確定 |
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
- `NOT_ACTIVE_RESPONDER`
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
- countdown、question、answerのdeadline
- 問題のcanonical ID、correct answer、選択肢対応
- buzz採用者、buzz順、server受信時刻
- active responder、回答受付可否
- correctness、score delta、total score
- question result、最終rank、winner
- disconnect、grace、forfeit状態
- NPCの反応、回答、正誤、得点

### 4.2 公開Projection

clientが読む状態は、Server内部状態から生成したsanitized projectionとする。

- 対戦中に公開してよい: display name、avatar用公開値、slot、接続状態の粗い表現、score、公開state、残り時間の基準、prompt、choices、buzz結果。
- 問題確定前に公開しない: correct answer、内部question ID、正解index、出題seed、NPCの将来行動、MMR。
- `QUESTION_RESULT` 以後に、答え合わせに必要な正解表示を公開してよい。
- `MATCH_FINISHED` ではscoreとrankを公開するが、MMR更新結果はsettlement確定後に公開する。

### 4.3 最終結果

最終結果は、match内のcanonical resultとsettlement resultを分ける。

- `MatchResult`: matchId、roster snapshot、final scores、ranks、winner、forfeit、finishedAt、configVersion。
- `SettlementResult`: settlementId、settlementVersion、MMR before/delta/after、season、history/leaderboard反映状態。
- MatchResultは一度確定したら変更しない。
- SettlementResultの適用処理は再実行可能だが、同じsettlementを二重加算しない。

---

## 5. Match State Machine

### 5.1 状態遷移

```text
CREATED
  -> WAITING_PLAYERS
  -> COUNTDOWN
  -> QUESTION_OPEN
  -> BUZZ_LOCKED
  -> ANSWERING
  -> QUESTION_RESULT
  -> NEXT_QUESTION
       -> QUESTION_OPEN ...
       -> MATCH_FINISHED
  -> SETTLEMENT_PENDING
  -> SETTLED
```

異常終了は自由なstate上書きではなく、Server eventとして同じOrdering Authorityを通し、forfeitまたはabort理由をMatchResultに残す。

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
- **拒否**: `buzz`、`submitAnswer`、roster外のjoin、期限切れticket。
- **Timeout**: 未参加・未ready playerをno-show扱いにする。開始前のためMMR penaltyは付けず、matchをabortして残りhumanを再queueすることを初期方針とする。
- **遷移**: 4枠が確定し、必要なhumanが参加・readyしたら `COUNTDOWN`。このcommitを競技上の参加確定境界とする。

### 5.4 COUNTDOWN

- **Server保持**: immutable roster snapshot、startAt、最初のquestion参照、全deadline基準時刻。
- **公開**: roster、countdown基準、接続状態、公開設定。
- **許可Intent**: `reconnect`、`leave`、`heartbeat`。
- **拒否**: `buzz`、`submitAnswer`、roster変更、ready取消。
- **Timeout**: startAt到達をServer timer eventとして処理する。clientのanimation完了を待たない。
- **遷移**: 最初の問題をsanitized projectionへcommitして `QUESTION_OPEN`。COUNTDOWN以後のleaveまたはgrace超過は原則forfeit。

### 5.5 QUESTION_OPEN

- **Server保持**: canonical question、correct answer、eligible players、openAt、buzzDeadline、採点設定。
- **公開**: opaque `questionInstanceId`、prompt、opaque `answerId`付きchoices、deadline基準、score。
- **許可Intent**: eligible humanの `buzz`、`reconnect`、`leave`、`heartbeat`。
- **拒否**: `submitAnswer`、重複buzz、資格のないplayer、問題不一致、deadline後buzz。
- **Timeout**: buzzなし結果をServer timer eventとして確定する。
- **遷移**: 最初にOrdering Authorityへcommitされた有効buzzで `BUZZ_LOCKED`。buzzなしは `QUESTION_RESULT`。

### 5.6 BUZZ_LOCKED

- **Server保持**: accepted buzz、responder、buzzSequence、answerDeadline、残りeligible players。
- **公開**: buzz採用playerと入力開始に必要な状態。内部処理が短い場合もversionを持つ。
- **許可Intent**: `reconnect`、`leave`、`heartbeat`。
- **拒否**: 追加 `buzz`、まだ開始されていない `submitAnswer`。
- **Timeout**: 通常は即時遷移のため独立timeoutを持たない。遷移失敗は同一eventのretryで回復する。
- **遷移**: responderとanswerDeadlineを同一commitで固定し `ANSWERING`。

### 5.7 ANSWERING

- **Server保持**: active responder、valid answerIds、correct answer、answerDeadline、採点規則。
- **公開**: responder、回答中表示、残り時間。correct answerは非公開。
- **許可Intent**: active responderの `submitAnswer(answerId)`、全playerの `reconnect`、`leave`、`heartbeat`。
- **拒否**: responder以外の回答、自由入力、未知answerId、問題不一致、deadline後回答、二重回答。
- **Timeout**: 未回答を不正解/失敗としてServer eventで確定する。
- **遷移**: 正解は `QUESTION_RESULT`。不正解後に同じ問題を再openするか直ちに結果へ進むかは未決定で、`wrongAnswerPolicy` をconfigに固定して分岐する。

### 5.8 QUESTION_RESULT

- **Server保持**: accepted answer、correctness、correct answer、score delta、total scores、question result sequence。
- **公開**: 正解、回答者、正誤、score delta、total scores、結果表示期限。
- **許可Intent**: `reconnect`、`leave`、`heartbeat`。
- **拒否**: `buzz`、`submitAnswer`、結果変更要求。
- **Timeout**: result表示期限をServer timer eventで処理する。
- **遷移**: 残り問題ありなら `NEXT_QUESTION`、終了条件成立なら `MATCH_FINISHED`。

### 5.9 NEXT_QUESTION

- **Server保持**: 前問題のclosed marker、次question参照、eligible reset、score snapshot。
- **公開**: transition状態と現在score。次問題の秘密情報はまだ公開しない。
- **許可Intent**: `reconnect`、`leave`、`heartbeat`。
- **拒否**: `buzz`、`submitAnswer`。
- **Timeout**: 内部準備のretry deadline。失敗時は同じnext-question eventを冪等retryする。
- **遷移**: 次問題のpublic payloadとdeadlineを同一commitで作り `QUESTION_OPEN`。終了条件なら `MATCH_FINISHED`。

### 5.10 MATCH_FINISHED

- **Server保持**: immutable MatchResult、最終score/rank/winner/forfeit、settlement作成状態。
- **公開**: 最終score、rank、winner、settlement待ち表示。
- **許可Intent**: `reconnect`、結果read。新しいgameplay Intentは不可。
- **拒否**: `buzz`、`submitAnswer`、score/rank変更、同一matchへの再参加。
- **Timeout**: settlement作成のretryを起動する。
- **遷移**: deterministicなsettlementIdとcanonical SettlementResultを作成して `SETTLEMENT_PENDING`。

### 5.11 SETTLEMENT_PENDING

- **Server保持**: canonical SettlementResult、各projectionの適用状況、retry count、last error。
- **公開**: 結果と「Rating反映中」。内部error詳細は公開しない。
- **許可Intent**: 結果read、session終了確認、reconnect。gameplay Intentは不可。
- **拒否**: clientによるMMR/履歴/leaderboard更新。
- **Timeout**: retry policyに従い未完了componentを再実行する。人手調査が必要な状態はdead-letter相当へ記録するが、二重加算しない。
- **遷移**: 必須componentがすべて同じsettlementId/versionを適用したら `SETTLED`。

### 5.12 SETTLED

- **Server保持**: 完了settlement、適用証跡、保持期限。
- **公開**: final rank、rating delta、表示TierまたはRating、直近履歴への反映結果。
- **許可Intent**: readのみ。新しいqueue参加は新しいsessionとして扱う。
- **拒否**: このmatchへの全mutation。
- **Timeout**: retention policyに従ってhot stateをcleanupする。監査記録は別policyで保持する。
- **遷移**: terminal。

### 5.13 State Machine不変条件

- stateはServerだけが進め、巻き戻さない。
- state遷移、`serverSequence` 増分、canonical event/outboxは同じ原子的境界で確定する。
- questionIndex変更時は前問題のbuzz/answer/failed相当のactive stateを同時に閉じる。
- clientが古いstateを見て送ったIntentは、処理時のServer stateで再検証する。
- timer、NPC、disconnectもclient Intentと同じOrdering Authorityを通る。

---

## 6. Event Ordering

### 6.1 Ordering Authority

各matchは、1つの論理的なOrdering Authorityを持つ。これは常に1つのprocessを起動し続けるという意味ではなく、複数instanceから同時に処理されても、最終的に1か所のtransaction/CAS（compare-and-swap）で順序を決めるという意味である。

順序の基準は次の通り。

1. clientが送信を開始した時刻ではない。
2. Function/Containerが処理を開始・終了した時刻ではない。
3. network到着の推測時刻ではない。
4. **Ordering Authorityへの有効なcommit順**を権威順序とする。

### 6.2 `serverSequence`

- match作成時に0から開始し、matchへ影響するaccepted eventごとに単調増加する。
- client Intent、server timer、NPC action、disconnect expiry、forfeitを同じsequence空間へ入れる。
- 同じ `intentId` のretryではsequenceを増やさない。
- public projectionにも最新sequenceを含め、古いprojectionで新しい状態を上書きしない。
- 拒否Intentは、Ordering Authorityへ到達してstate依存で拒否された場合に監査sequenceまたは関連sequenceを残す。認証前の拒否はmatch sequenceへ入れずsecurity logへ記録する。

### 6.3 原子的commitの内容

1回のauthority commitで少なくとも以下を一体として確定する。

- stateBefore / stateAfter
- 次の `serverSequence`
- accepted/rejected outcome
- score、responder、deadline等のcanonical state差分
- dedup用 `intentId` 結果
- event recordまたは確実に再送できるoutbox marker

副作用（通知、analytics、履歴、leaderboard）はtransaction callback内で実行しない。commit後にoutbox/eventを冪等処理する。

### 6.4 同時buzz

- 4人が同時にbuzzしても、最初にauthority commitへ成功した有効Intentだけを採用する。
- transaction/CAS retry時は最新stateを再評価し、すでに `BUZZ_LOCKED` なら後続を拒否する。
- clientの端末時計や表示上の早さで勝者を決めない。
- 採用結果、responder、sequence、Server timestampを同じcommitで固定する。

### 6.5 Timer / NPC / Disconnect event

- timer eventは `timer:{matchId}:{questionInstanceId}:{kind}` のようなdeterministic IDを持ち、重複起動しても1回だけ状態を進める。
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
2. **Per-match Ordering Authority**: transaction/CASで唯一の順序を決める。
3. **Public Projection**: participant clientがread/listenするsanitized状態。client writeは禁止。
4. **Durable Settlement Store**: MMR、Season、history、leaderboard、auditを冪等反映する。

### 7.2 Candidate比較

| Candidate | Ingress / Ordering | 長所 | 主なリスク | Phase Aで測ること |
| --- | --- | --- | --- | --- |
| A. Functions 2nd gen + RTDB transaction | Callable/HTTPで受付、match rootのRTDB transactionで採番、RTDB listenerへ公開 | 現行Firebase資産とiOS SDKを活用しやすい。4人へのfan-outが単純 | cold start、transaction retry、match root肥大化、Functions完了とprojection反映差 | warm/cold p50/p95、4同時buzz、transaction retry、listener収束 |
| B. Cloud Run HTTP + RTDB transaction | Cloud Runで受付、Aと同じRTDB authority | instance/concurrency/実行環境の制御幅が大きい | Auth/App Check検証を明示実装、運用面増加、RTDBがbottleneckならAとの差が小さい | 認証込みlatency、instance跨ぎ、min instance有無、コスト |
| C. Cloud Run WebSocket actor + durable CAS | persistent connection、per-match actor、外部storeでfencing/復旧 | 低遅延な双方向制御とpushを設計しやすい | 接続再確立、instance移動、actor ownership、外部状態同期、運用コストが最も複雑 | reconnect、instance終了、ownership移譲、同時接続、障害復旧 |
| D. Functions/Cloud Run + Firestore transaction | HTTP受付、match aggregateをFirestore transactionで更新、projectionをlisten | settlement/auditとのデータモデルを揃えやすい。commit時刻で直列化できる | 高競合docのcontention、listener遅延、event蓄積方法 | 4同時buzz contention、p50/p95、retry/error率、projection遅延 |
| E. Queue / Pub/Sub ordering key | matchIdをordering keyにしてconsumerで直列処理 | workload平準化、retry、非同期処理に強い | 追加hop、at-least-once重複、interactive pathの遅延 | end-to-end latency、重複、redelivery、backlog時挙動 |

### 7.3 Phase Aの推奨検証順

1. Candidate Aを最小baselineとして測る。
2. 同じauthority contractでCandidate Dを比較する。
3. ingress制御が必要な場合にCandidate Bを比較する。
4. A/B/Dが決定したp95予算を満たせない場合のみCandidate Cを試す。
5. Candidate Eは初期のbuzz/answer経路の第一候補にせず、settlement、audit、再試行pipelineの候補として評価する。

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

機能的な合格条件:

- 同時buzzでacceptedが必ず1件
- `serverSequence` が単調増加
- duplicate Intentで二重更新しない
- stale epochを拒否する
- reconnect後に全clientが同じsnapshotへ収束する
- private correct answerがclient payloadへ混入しない

数値のp95合格値と、min instance等に許容する月額費用は未決定であり、Phase A開始前に決める。

### 7.5 Region

- Ingress、Ordering Authority、公開projection、主要databaseは可能な限り同一または近接regionに配置する。
- 現行Functionsの `asia-northeast1` を理由だけにCompetitiveのregionを固定しない。実際のRTDB/Firestore location、利用者分布、計測結果を確認して決める。
- 異なるregionをまたぐ構成は、latency spikeと障害時挙動を確認せず採用しない。

---

## 8. Question Security

### 8.1 Server-only Question Bank

- Competitive用question bank、canonical question ID、correct answer、選択肢対応はserver-onlyとする。
- Rulesでclient readを拒否し、server credentialだけが読む。
- 問題中のclientへcanonical ID、正解index、正解文字列、seedを送らない。
- serverは出題時にmatch固有のopaque `questionInstanceId` とopaque `answerId` を生成する。

### 8.2 Clientへ公開する内容

`QUESTION_OPEN` では次だけを公開する。

- `questionInstanceId`
- prompt
- 表示順が確定したchoices
- 各choiceのopaque `answerId`
- buzz/answer deadlineのServer基準
- 表示に必要なcategory等の非秘密情報

`submitAnswer` は `answerId` だけを送り、serverが内部mappingで正誤を判定する。

### 8.3 結果公開

- correct answerは `QUESTION_RESULT` 以後、答え合わせに必要な範囲で公開する。
- 監査用canonical IDはpublic projectionへ含めない。
- event logに正解情報を残す場合も、participantが直接読めるlogと分離する。

### 8.4 端末同梱word bankのreverse lookupリスク

現行アプリに同梱したword bankとCompetitive問題が同一なら、promptからlocal dataを逆引きされる可能性がある。opaque IDだけではこの攻撃を防げない。

初期方針:

- Competitive corpusとcontent versionはserver側で管理する。
- client assetのrow IDや固定順をCompetitive payloadへ再利用しない。
- 選択肢順とanswerIdをmatch/questionごとに変える。
- 出題頻度、異常に短い回答、正答率等をserver側で監査できるようにする。

外部辞書、OCR、改造端末、手動協力を含む自動解答の完全防止はNon-goalである。防ぐ対象は、payloadからの正解漏えい、clientによる正誤指定、静的IDの単純逆引き、replayである。

### 8.5 未決定事項

- Competitive corpusの供給元、権利、更新方法
- 現行学習データとの問題共有範囲
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

- NPCのprofile、strength、擬似MMR、反応時間、buzz、answer、correctness、scoreはserverが生成する。
- NPC eventは人間Intentと同じOrdering Authorityを通し、未来の行動をclientへ送らない。
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

---

## 12. Disconnect / Reconnect

### 12.1 検出

disconnect判定はclientの自己申告だけに依存しない。次を組み合わせる。

- serverが受理したheartbeat / Intent activity
- server-owned lease
- transport disconnect signal（利用backendが提供する場合）
- deadline時点での再検証

### 12.2 Grace

- transport切断またはheartbeat欠落後、sessionを `RECONNECTING` としてgrace期間を与える。
- grace中もmatchのServer clockと他playerの進行を止めない。
- 再接続時はsessionId、epoch、matchIdを検証し、最新snapshotとsequenceを返す。
- grace内に戻れば同じslotへ復帰する。
- grace超過はserver eventとしてOrdering Authorityへ投入し、開始後はforfeit、開始前はno-show/abort扱いとする。

### 12.3 Explicit leave

- WAITING_PLAYERSまでのleaveはqueue/match cancelとして扱い、原則MMR penaltyなし。
- COUNTDOWN commit以後のleaveは原則forfeit。
- client UIは開始後の退出結果を明示するが、clientが「penaltyなし」を指定できない。
- app kill、network loss、explicit leaveで同じ結果にするか、意図的leaveを即時forfeitにするかはserver policyで固定する。

### 12.4 未決定値

- heartbeat間隔
- lease長
- reconnect grace長
- 回答中に切断したresponderの扱い
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

- 各human playerのMMR
- 表示Tier / Rating Zone projection
- season stats
- 直近試合history
- Top 20 leaderboard projection
- audit / anomaly data

NPCにはMMR、history、leaderboardを適用しない。

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
- `questionInstanceId`
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

### 17.1 Phase A開始前にユーザー判断が必要

1. **不正解後の進行**: 同じ問題を残playerへ再openするか、1buzzで問題を終了するか。
2. **Latency目標**: client sendから全client反映までの許容p95。目標達成のためのmin instance等の月額費用上限。
3. **Competitive question corpus**: 現行client同梱データと分けるか、供給元・権利・更新責任をどうするか。
4. **退出の競技ルール**: COUNTDOWN以後の即時forfeit、切断grace後forfeit、回答中切断の扱い。

### 17.2 Phase A/Bで技術検証して決める

1. Ordering AuthorityをRTDB transaction、Firestore transaction、Cloud Run actorのどれで実現するか。
2. Intent ingressをFunctions 2nd gen callable/HTTPとCloud Runのどちらにするか。
3. public projectionをRTDB listenerとFirestore listenerのどちらにするか。
4. region、min instances、concurrency、retry/backoff。
5. heartbeat、lease、reconnect graceの具体値。
6. authority eventとprojectionの保存・compaction方法。
7. App Check replay protectionをどのIntentに要求するか。

### 17.3 Phase C前にプロダクト判断が必要

1. 初期MMR、provisional期間、Tier/Rating Zone境界、delta式。
2. Tier別queue wait、search range拡大、NPC投入条件、最大NPC数。
3. NPC数別のMMR減衰式。
4. Season長、reset/carry-over、Top 20 tie-breaker。
5. last 5以外のhistory保持件数。

### 17.4 Phase D前に運用判断が必要

1. audit/raw trace/historyの保持日数と削除policy。
2. 不正疑いのmanual reviewとappeal手順。
3. alert閾値、on-call/障害時のCompetitive停止方法。
4. minimum protocol versionを上げるrollout手順。
5. 本番費用上限と自動scale上限。

---

## 18. Phase A-D Split

### Phase A: Architecture Spike / Contract Skeleton

目的はbackendを実測で選び、契約を固定すること。Production機能を作らない。

- Intent envelope、ack、error code、public projectionのschema draft
- MatchAggregateと `serverSequence` の最小contract
- Auth/App Check検証を含む非本番Ingress skeleton
- Candidate A/Dを中心とした4client latency spike。必要に応じB/Cを追加
- 同時buzz、duplicate、stale epoch、reconnect、instance分散の検証
- private answer非公開のpayload inspection
- p50/p95、retry率、コスト、運用複雑性の比較記録
- Backend decision recordの作成

Phase A完了条件:

- Ordering Authorityの採用方式が決まっている。
- Intent → authority commit → public projectionのp50/p95が記録されている。
- 同時buzzでacceptedが1件、全clientが同じsequenceへ収束する。
- 採用方式がSecurity Invariantsを満たす見込みを示せる。
- Phase Bで使うprotocol/config versioningが確定している。

### Phase B: Competitive Match Core

目的は人間4人の1試合をserver-authoritativeに最後まで通すこと。

- Session/lease/epoch
- 4-human WAITING → COUNTDOWN → questions → MATCH_FINISHED
- buzz/answer/timer/score/rankのServer判定
- question bankとsanitized payload
- disconnect/reconnect/forfeit
- canonical MatchResult
- idempotent Settlement skeleton
- Emulator/integration test、Simulator + physical iPhoneの最小E2E

Phase Bでは本格MMR、Season、Leaderboard、Production NPCをまだ有効化しない。

### Phase C: Matchmaking / Rating / NPC / Season

- random matchmakingとsearch range
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
