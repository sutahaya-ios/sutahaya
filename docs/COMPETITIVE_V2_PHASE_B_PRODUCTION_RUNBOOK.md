# Competitive v2 Phase B Production Deploy / E2E Runbook

## 状態と適用範囲

- Phase B基準commitは c0299954d75a8dd0f3f7cc7745ceb906eaeae6f6。
- Phase A-2 rollback基準commitは c4009fb3e778541a40d812f410eac6ab9d1ce57d。
- このRunbookとdriverの準備時点ではProductionへdeploy・data write・Auth user作成を行っていない。
- 対象projectは hayaosiapp、Competitive FunctionsとRTDBのregionは asia-southeast1。
- deploy対象は database.rules.json、competitiveReconcileMatch、competitiveMatchmakingだけ。
- competitiveIntent、sendRoomInvite、rooms、Friend Battle、App Check、IAM、minInstancesは変更しない。
- Phase A-2の20問、scoring、deadline、retry、Security、realtime projectionの既存Production証拠を再利用する。

## Localでのdriver確認

review-onlyはSDK接続、ADC利用、Production read/writeを行わない。

    npm run competitive:phase-b-cloud-e2e:review
    npm run test:competitive-phase-b-cloud-e2e-driver
    node --check scripts/competitive-v2-phase-b-cloud-e2e.cjs

driver本体:

- scripts/competitive-v2-phase-b-cloud-e2e.cjs
- scripts/competitive-v2-phase-b-cloud-e2e.test.js

## Runtime input

Production実行は別途ユーザーがdeployとE2Eを許可した後だけ行う。値はshellのruntime environmentだけへ渡し、source、docs、ログ、artifactへ保存しない。

- impersonation Application Default Credentials
- COMPETITIVE_V2_PHASE_B_E2E_API_KEY
- COMPETITIVE_V2_PHASE_B_E2E_AUTH_DOMAIN=hayaosiapp.firebaseapp.com
- COMPETITIVE_V2_PHASE_B_E2E_DATABASE_URL=https://hayaosiapp-default-rtdb.asia-southeast1.firebasedatabase.app
- COMPETITIVE_V2_PHASE_B_E2E_PROJECT_ID=hayaosiapp
- COMPETITIVE_TEST_UID_1
- COMPETITIVE_TEST_UID_2
- COMPETITIVE_TEST_UID_3
- COMPETITIVE_TEST_UID_4
- COMPETITIVE_V2_PHASE_B_E2E_ALLOW_PRODUCTION=ALLOW_ISOLATED_COMPETITIVE_V2_PHASE_B_CLOUD_E2E

4 UIDは既存の専用Competitive Auth test usersを指定する。driverは最初にAdmin Auth getUserで4 userの存在を確認してからcustom tokenをメモリ内だけで生成する。存在しないuserの作成、IAM変更、ADC変更は行わない。tokenやUID一覧は結果へ出力しない。

ADCが利用できない、custom token署名権限がない、test userが存在しない場合は、権限変更やuser作成を試みず停止する。

## Production deploy直前readback Gate

実行当日にProductionを再取得する。

    firebase functions:list --project hayaosiapp --json
    firebase database:get /.settings/rules \
      --project hayaosiapp \
      --instance hayaosiapp-default-rtdb \
      --output /tmp/hayaosiapp-phase-b-predeploy-rules.json
    chmod 600 /tmp/hayaosiapp-phase-b-predeploy-rules.json

次を確認する。

1. Production Rulesがpreflight結果から変化していない。
2. competitiveIntent、competitiveReconcileMatch、sendRoomInviteのrevision/configに想定外変更がない。
3. competitiveMatchmakingがまだ存在しない。
4. local Rulesとの差分がcompetitiveV2/matchmakingのadditiveな追加だけ。
5. local HEADが許可されたE2E準備commitで、database.rules.jsonとfunctionsの内容がPhase B基準commit c0299954d75a8dd0f3f7cc7745ceb906eaeae6f6から変化していない。
6. deploy commandにcompetitiveIntentとsendRoomInviteが含まれない。

想定外差分、readback失敗、第三者更新があればdeployせず停止する。snapshotはGitへ追加しない。

## Deploy順

### Step 1: RTDB Rules

    firebase deploy --project hayaosiapp --only database

deploy後にRulesを再readbackし、次を確認する。

- matchmaking/publicは本人だけread可能でClient write不可。
- matchmaking/privateはClient read/write不可。
- roomsと既存Phase A-2 Rulesがpre-deploy snapshotと同一。

### Step 2: competitiveReconcileMatch

    firebase deploy --project hayaosiapp \
      --only functions:competitiveReconcileMatch

FunctionがACTIVEで、asia-southeast1、Node.js 22、256MiB、timeout 30秒、minInstances 0、App Check enforcement falseであることをreadbackする。

### Step 3: Phase A-2最小smoke

更新したreconcileについて、専用random matchだけでCREATEDからWAITING_PLAYERSへのrepresentative reconcile、4-client public projection、private read拒否を確認する。20問は再実行しない。

    node scripts/competitive-v2-phase-b-cloud-e2e.cjs --phase-a-smoke

smokeは作成した正確なmatchとclockだけをfinallyで削除し、readbackで不存在を確認する。

### Step 4: competitiveMatchmaking

    firebase deploy --project hayaosiapp \
      --only functions:competitiveMatchmaking

FunctionがACTIVEで、region/runtime/memory/timeout/minInstances/App Checkが計画どおりであることをreadbackする。competitiveIntentとsendRoomInviteのrevisionが変化していないことも確認する。

### Step 5: Phase B Production E2E

    node scripts/competitive-v2-phase-b-cloud-e2e.cjs --execute

## E2E isolation Gate

driverはProduction writeより先に以下を確認する。

- 4 test UIDのprivate profile、queue、public projectionがすべて不存在。
- global matchmaking queueが空。
- pendingMatchesが空。
- run-scoped sentinel pathが不存在。

何か存在すれば上書き・削除せず停止する。Competitiveが一般公開前であることを前提に、global queueへ別userがいる状態では実行しない。

driverが触るのはcompetitiveV2以下の次のexact pathだけ。

- 4 test UIDのqueue/profile/public
- run-scoped private sentinel profile
- Serverが4 test usersから生成した2 match
- 対応するpending matchとclock

rooms、Friend Battle、一般userのprofile、Auth userは触らない。

## E2E flow

### 1. Representative Security / Retry

- unauthenticated joinQueueを拒否。
- UID、MMR、Rank、matchIdをClient payloadで指定するとINVALID_PAYLOAD。
- 同一intentIdのjoinQueue再送はDUPLICATEかつ元のsessionを維持。
- 同じintentIdを別payload/typeで再送するとINTENT_REPLAY_MISMATCH。
- 2回目の新規joinQueueはsessionEpochを進め、queue entryは1件へ収束。
- stale session / epochによるcancelを拒否。
- 他Playerがsession値を流用してcancelしても対象queueが変化しない。
- cancelQueue再送はDUPLICATEでretry-safe。

### 2. Release-test match

4 userを順にjoinQueueする。

- 各userがQUEUEDを観測。
- 4人目で4 humanをatomic claim。
- 各userがMATCH_FOUNDと、同じmatchIdのWAITING_PLAYERSを観測。
- transient pending manifestとactual matchのUID/sessionEpoch/assignmentTicketが一致。
- actual matchはparticipant 4件、UID重複なし。
- 対象4 queue entryが消える。
- profileのactive matchが同じmatchId。
- pending manifestがfinalize後に消える。
- MATCH_FOUND後のcancelはMATCH_ALREADY_ASSIGNED。
- MATCH_FOUND後のjoinQueueはACTIVE_MATCH_EXISTS。
- 他人のpublic projection、private profile/queue read、participants直接writeを拒否。

### 3. Session release

WAITING_PLAYERS中に1 test playerが正規のleaveを送り、専用matchをMATCH_FINISHEDへ進める。その後reconcileを呼び、Phase Bで追加したrelease処理を通す。

確認:

- 対象4 profileのsession stateがFINISHED。
- active matchを示すmatchIdがnull。
- queue entryなし。
- 本人用projectionがNOT_QUEUED。
- 別matchIdを持つrun-scoped sentinel profileが完全一致のまま。

一般userをsentinelには使用しない。

### 4. Core-bridge match

解放済みの同じ4 test usersを再度queueし、別の1 matchを作る。

    QUEUED
    MATCH_FOUND / WAITING_PLAYERS
    joinMatch
    ready
    COUNTDOWN
    QUESTION_OPEN

ここまででPhase BからPhase A-2 Coreへの主要接続を確認する。20問Battleは再実行しない。

## T0〜T4

- T0: 4人目のjoinQueue送信直前のdriver monotonic clock。
- T1: competitiveMatchmaking入口。
- T2: atomic match claim確定。
- T3: 4人目のHTTP ack利用可能時刻。
- T4: 4 client全員が同じmatch assignment projectionを観測した最終時刻。

driverはT0→T3とT0→T4を測定する。T1→T2はdeployed Function ackが正確なtimingを返す場合だけ記録する。現在のPhase B Function contractはT1/T2をackへ公開していないため、driverは値を推測せずNOT_EXPOSED_BY_CURRENT_FUNCTIONと記録する。今回のE2EはPerformance Gateではなく、Production logicへ計測だけの恒久変更を加えない。

## Failure-safe cleanup

isolation Gate通過後だけcleanupをarmする。成功・失敗のどちらでもfinally相当で、まず4 test profileとpending manifestを再読し、今回の4 UIDだけからなるmatchIdを収集する。

削除対象:

- matchmaking/private/queue/{testUid} 4件
- matchmaking/private/profiles/{testUid} 4件
- matchmaking/public/{testUid} 4件
- matchmaking/private/profiles/{runScopedSentinel}
- matchmaking/private/pendingMatches/{exactMatchId}
- matches/{exactMatchId}
- clocks/{exactMatchId}

match/pendingの上限をdriver側で4件に制限し、Firebase unsafe key、competitiveV2 root、matchmaking rootなど広いpathを拒否する。test userと非test userが混在するpending matchを検出した場合は広域削除せず停止する。

削除後は全exact pathをreadbackし、不存在でなければE2E失敗として報告する。Auth test usersは削除しない。

## Partial deploy failure

### A. Rules成功、reconcile失敗

- competitiveMatchmakingはdeployしない。
- E2Eを開始しない。
- Production Functions / Rulesをreadbackして停止。
- 必要なら別承認後、pre-deploy Rules snapshotを復元。

### B. Rulesとreconcile成功、Phase A-2 smoke失敗

- competitiveMatchmakingはdeployしない。
- 追加修正deployを行わず、Functionログとsmokeのexact match状態を保存して停止。
- 別承認後にreconcileとRulesをrollback。

### C. Rulesとreconcile成功、matchmaking失敗

- 新規Matchmaking受付は存在しない。
- 既存Phase A-2は継続可能。
- 追加Functionをdeployせず、readbackして停止。

### D. matchmaking成功後、E2E失敗

- 場当たり的な追加deploy、Rules緩和、IAM変更を行わない。
- exact test data cleanupを実行。
- observation、error code、失敗stepを報告して停止。
- rollbackは別承認後に実施。

## Rollback

rollbackにもユーザーの明示許可が必要。mainをreset/rebaseせず、Phase A-2 commitを一時ディレクトリへ展開してdeployする。

1. 新規受付を止める。

    firebase functions:delete competitiveMatchmaking \
      --region asia-southeast1 \
      --project hayaosiapp \
      --force

2. driverが記録したexact test pathsだけcleanupし、readbackする。

3. c4009fb3e778541a40d812f410eac6ab9d1ce57dをmktempの一時ディレクトリへgit archiveで展開する。そこからcompetitiveReconcileMatchだけをdeployする。

    firebase deploy --project hayaosiapp \
      --only functions:competitiveReconcileMatch

4. deploy直前に保存したRules snapshotを一時展開先のdatabase.rules.jsonへ置き、databaseだけをdeployする。現在のmain上のdatabase.rules.jsonは上書きしない。

    firebase deploy --project hayaosiapp --only database

5. Functions一覧とRulesをreadbackする。

6. competitiveMatchmaking不存在、competitiveReconcileMatchがPhase A-2版、Rulesがsnapshotと一致、competitiveIntent/sendRoomInviteが不変であることを確認する。

7. 必要な場合だけPhase A-2 smokeとFriend Battle最小正常系を確認する。

force push、git reset、rebase、merge commitは不要。

## 判定

成功条件:

- 4 existing Auth test usersだけを使用。
- exactly 1 matchずつ作成され、他userをclaimしない。
- security/retry代表caseが期待どおり。
- session releaseが対象4 userだけへ作用。
- 2試合目がQUESTION_OPENまで接続。
- exact cleanup readback成功。
- competitiveIntent、sendRoomInvite、rooms、Friend Battleへ変更なし。

失敗時はPhase BをProduction検証済みにせず、失敗stepとactual payload/error codeを記録して停止する。
