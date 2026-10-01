# Competitive v2 Phase A-1 Candidate A actual Cloud Spike Plan

- Status: **Independent Answer Model actual Cloud Spike完了 / Phase A-1完了**
- Candidate A系: **Phase A-2のBackend baselineとして正式採用**
- Phase A-2: 未着手
- Production Rules / schema: 変更なし
- SSOT: [`COMPETITIVE_V2_SPEC.md`](COMPETITIVE_V2_SPEC.md) / [`COMPETITIVE_V2_BACKEND_SPIKE.md`](COMPETITIVE_V2_BACKEND_SPIKE.md)

## 0. actual Cloud実行・cleanup状態（2026-09-29〜30）

許可された専用resourceだけでactual Cloud測定を完了した。

- 測定時Secret `COMPETITIVE_V2_SPIKE_TOKEN`: versions 1 / 2 / 3がENABLED。両Functionはversion 3を参照
- 測定時`competitiveV2OrderingSpikeAControl` / `competitiveV2OrderingSpikeAOrder`: `asia-southeast1`でACTIVE
- 測定時IAM: 上記2Functionだけ`invoker: "public"`。既存Functionは変更なし
- token guard: tokenなし=401、不正token=401、正しいtoken=200
- Order validation: valid CAS成功、`MALFORMED_REQUEST` / `UNKNOWN_MATCH`拒否成功
- 実行: `cloud-a-20260929-02`、warmup 5 round、測定40 round、各4 concurrent、160 Intent
- cleanup: runId配下を削除し、CLI readbackが`null`であることを確認済み
- RTDB / Firestore Rules、schema、`rooms/`、既存Function `sendRoomInvite`: 変更なし
- Artifact Registry cleanup policy: 未設定警告が出たが、今回の許可範囲外なので変更なし

2026-09-29のfollow-upで、同じ2FunctionをFirst-winner lock実装へ更新した。Secretはversion 3を継続利用し、追加rotationはしていない。`cloud-a-first-winner-20260929-02`で5 warmup / 40 measured round × 4 concurrentを実行し、40 winner / 120 loser、winner collision 0、overwrite 0を確認した。warm T1→T2 p95は98.681ms、T0→T3 p95は299.275ms。preflight / measuredの両runIdをcleanupし、readback `null`を確認済みである。詳細は`COMPETITIVE_V2_BACKEND_SPIKE.md` §19を参照する。

winner ordering fidelity follow-upでは、同条件の40 warm roundでearliest T1とwinnerが21/40一致した。19 mismatchはすべて同一Function instance内かつ1.306〜8.214ms差で、10ms超は0だった。測定runIdはcleanupし、readback `null`を確認済みである。T1は観測値に限定し、client timestampやT1をAuthorityへ採用していない。

2026-09-30に同じ2FunctionをIndependent Answer Modelへ更新した。Order FunctionだけSpike限定で`concurrency=1`とし、`minInstances=0`、`maxInstances=4`は維持した。10 warmup後、40 measured round × 4 concurrentを4 instanceで実行し、160/160 answer受理、answer/close contention retry 0を確認した。deadline race 12件はすべてServer deadline後として拒否され、ack / result不一致とresult確定後の変更は0だった。詳細は`COMPETITIVE_V2_BACKEND_SPIKE.md` §23を参照する。

Architecture Decision後、Spike Function 2本と対応public endpointを削除し、Secret versions 1 / 2 / 3を破棄した。最後のactive version破棄後にSecret本体も削除された。`firebase functions:list`では既存`sendRoomInvite`だけが残り、`functions:secrets:get COMPETITIVE_V2_SPIKE_TOKEN`は404 `not found`となることを確認した。前回の4-way sequence、First-winner lock、winner fidelity、Independent Answerのsource / driver /結果は比較・再現証拠としてrepo内に残しているが、`functions/index.js`からSpike exportを除去した。

Secret値はsource、diff、ログ、文書へ保存していない。versions 1 / 2 / 3の値も記録していない。

### Preflight中の修正

public invoker設定後、最初の条件付きPUTが`RTDB_CAS_HTTP_400`となった。Cloud用handlerだけに追加していた`print=silent`を除き、Local harnessとFirebase公式の条件付きPUT例と同じrequestへ戻した。再rotation・両Function redeploy後はpreflightと本測定が成功した。

### Actual Cloud latency（ms）

| 区間 | min | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| T1→T2 | 33.030 | 108.122 | 260.739 | 832.531 |
| T0→T2（clock差を含む近似） | 282.816 | 377.321 | 534.231 | 1,101.531 |
| T0→T3 | 178.157 | 281.517 | 443.380 | 1,037.974 |
| RTDB CAS内訳 | 32.944 | 108.037 | 260.634 | 832.439 |

warm access token取得はp95 0.087msであり、T1→T2のtailはほぼRTDB CASで占められた。

最初の有効Order invocationはT1→T2 245.438ms、T0→T3 444.717msだった。ただしdeployment rolloutでinstanceが13.782秒前に起動済みだったため、これは初回token取得を含む「deploy後初回」であり、platform cold start全体を含む純粋なcold測定ではない。

### Ordering / retry

- 40/40 round成功、sequence collision 0、sequence gap 0
- 160 Intent、CAS attempt 355、contention retry 195
- duplicate eventは元sequence 1を返し再登録なし
- duplicate playerは`DUPLICATE_PLAYER_BUZZ`
- 同一eventの同時retryは`accepted` / `duplicate`で、永続sequenceは1
- stale / malformed / unknown matchを各境界で拒否

## 1. Candidate B sanity check

Local harnessのCandidate Bを一度だけ再確認した。

- 明示的な`setTimeout`、sleep、固定delayはない。
- T1はHTTP handler入口、T2は`firestore.runTransaction`完了直後であり、約4.9秒へ別工程を誤って含めていない。
- 各roundのstate resetは計測前に完了している。
- 4 concurrent requestが同じ1 documentを更新し、SDK transactionは`maxAttempts: 10`でcontention時にcallbackを再実行する。
- 160 Intentでcallback 318回、retry 158回という既存結果と整合する。

したがって、明らかな計測不具合は見つからなかった。約4.9秒はLocal Emulator上のsingle-document contentionとSDK retry/backoffを含む値と判断し、Candidate Bの追加研究は行わない。この値をactual Cloudの値としては扱わない。

## 2. Cloud Spike構成

既存アプリ、既存フレンドバトル、`rooms/`、Firestore、Production Rulesには接続しない。

| Resource | 専用設定 |
| --- | --- |
| Function | `competitiveV2OrderingSpikeAOrder` |
| Control Function | `competitiveV2OrderingSpikeAControl` |
| Runtime | Cloud Functions 2nd gen / Node.js 22 |
| Region | `asia-southeast1` |
| RTDB | 既存`hayaosiapp-default-rtdb`、location=`asia-southeast1` |
| RTDB path | `__spikes/competitiveV2OrderingA/{runId}/matches/{matchId}` |
| Driver | `spikes/competitive-v2-backend-ordering/cloud-a-independent-answer-driver.cjs` |
| 認可 | 専用Secret `COMPETITIVE_V2_SPIKE_TOKEN` |
| Scale上限 | `minInstances=0`、`maxInstances=4`、OrderのみSpike限定`concurrency=1` |

FunctionとRTDBを同一regionへ置くため、Functions→RTDBに意図したregion間通信はない。test driverは東京のローカルMacから実行し、そのInternet往復はT0→T3へ含める。既存`sendRoomInvite`の`asia-northeast1`配置は変更しない。

Control FunctionとOrdering Functionを分離している。ControlでMatchを初期化してもOrdering Functionはwarmにならないため、deploy後の最初の単発Ordering requestをcold start込みのprobeとして記録できる。大量の人工cold startは作らない。

## 3. 測定と検証

時点は次のとおり。

- T0: driverがHTTP request送信を開始
- T1: Ordering Function handler入口
- T2: RTDB ETag CASによるdecision確定
- T3: driverがHTTP responseをparseして利用可能

Independent Answer driverは次をJSONで出力する。

- T1→T2、T0→T3のmin / p50 / p95 / max
- T1→T2の内訳としてaccess token取得時間とRTDB時間
- warm measured sampleとcold invocation該当数
- Function instance IDとrequest分散
- 4 concurrent independent answer × 40 measured round
- Player別create-only、overwrite、duplicate、CAS retry数
- deadline前後、answer / close競合、result immutability
- canonical ordering、exact tie、代表score
- Function region、RTDB host、driver実行元

T1→T2とT0→T3はmonotonic clockで測る。percentileはLocal Spikeと同じnearest-rankを使う。

## 4. Production影響

- `firebase deploy --only`の対象は新規Function 2本だけ。既存Functionを更新しない。
- RTDB Rules / Firestore Rules / indexes / schemaはdeployしない。
- Admin credentialで専用`__spikes` pathだけを読み書きする。現在のRulesでは未定義root pathのclient read/writeは拒否される。
- App binaryと既存clientはFunction名もSpike pathも参照しない。
- test payloadはA〜Dの合成playerだけで、個人データは扱わない。
- Secret照合、4KiB payload上限、`maxInstances=4`で公開endpointの誤用範囲を抑える。

同じFirebase Production projectのRTDBとCloud Functionsを使うため、負荷と課金の影響が完全なゼロではない。ただし既存データへの論理的な書込みはない。

## 5. 費用影響

measured normal pathの実測では、1問 / 4 PlayerあたりFunction 5 invocation、RTDB 9 read / 6 write、contention retry 0だった。20問ではFunction 100 invocation、RTDB 180 read / 120 writeとなる。setup、status確認、public projection、Auth/App Check、logging、異常retryは含まない。

`minInstances=0`なので待機中instance料金は持たない。Cloud Functions/Cloud Run、Cloud Build、Artifact Registry、RTDB、Secret Manager、Loggingは実使用量に応じて課金され得るが、この単発Spikeの想定量は小さい。無料枠・Cloud credit内を保証するものではない。

## 6. deploy / 実行

ユーザー承認後、Secret rotation、専用2Functionのdeploy、preflight、driverを同じ一時process内で実行した。

専用tokenをSecret Managerへ登録する。tokenはGit、shell history、結果JSONへ保存しない。同じshellでdriverまで実行する。

```sh
read -s COMPETITIVE_V2_SPIKE_TOKEN
export COMPETITIVE_V2_SPIKE_TOKEN
printf '%s' "$COMPETITIVE_V2_SPIKE_TOKEN" | ./node_modules/.bin/firebase functions:secrets:set COMPETITIVE_V2_SPIKE_TOKEN --project hayaosiapp --data-file -
```

新規Function 2本だけをdeployする。

```sh
./node_modules/.bin/firebase deploy --project hayaosiapp --only functions:competitiveV2OrderingSpikeAControl,functions:competitiveV2OrderingSpikeAOrder
```

deploy出力の2 URLと、Secretへ登録した同じtokenを環境変数へ設定してdriverを実行する。結果はrepo外の`/tmp`へ保存する。

```sh
export COMPETITIVE_V2_SPIKE_CONTROL_URL='<control function URL>'
export COMPETITIVE_V2_SPIKE_ORDER_URL='<order function URL>'
export COMPETITIVE_V2_SPIKE_RUN_ID='cloud-a-independent-20260930-01'
export COMPETITIVE_V2_SPIKE_TEST_ORIGIN='Tokyo-JP-local-Mac'
node spikes/competitive-v2-backend-ordering/cloud-a-independent-answer-driver.cjs
```

driverは成功・失敗にかかわらず、既定でその`runId`配下のRTDB dataをcleanupする。調査のため一時保持する場合だけ`COMPETITIVE_V2_SPIKE_KEEP_DATA=1`を指定する。

## 7. cleanup

driverが途中停止してdataが残った場合は、同じURL/token/runIdでcleanup-onlyを実行する。

```sh
COMPETITIVE_V2_SPIKE_CLEANUP_ONLY=1 node spikes/competitive-v2-backend-ordering/cloud-a-independent-answer-driver.cjs
```

Architecture Decision後、Functionを先に削除し、その後Secretの全versionを破棄する次の順序でcleanupを完了した。

```sh
./node_modules/.bin/firebase functions:delete competitiveV2OrderingSpikeAControl competitiveV2OrderingSpikeAOrder --region asia-southeast1 --project hayaosiapp
./node_modules/.bin/firebase functions:secrets:destroy COMPETITIVE_V2_SPIKE_TOKEN@1 --project hayaosiapp
./node_modules/.bin/firebase functions:secrets:destroy COMPETITIVE_V2_SPIKE_TOKEN@2 --project hayaosiapp
./node_modules/.bin/firebase functions:secrets:destroy COMPETITIVE_V2_SPIKE_TOKEN@3 --project hayaosiapp
```

Function削除により、対応するCloud Run serviceとpublic invokerも除去された。削除対象はSpike専用resourceだけである。Cloud LoggingはGoogle Cloudの通常retentionに従う。

## 8. Architecture Decision

2026-09-30のユーザーレビューで、Candidate A系をPhase A-2のBackend baselineとして正式採用した。Production Ready宣言ではなく、Auth / authorization、App Check、private question / public projection、failure recovery、cold start、Realtime projection latency、費用はPhase A-2の必須課題とする。Candidate Cはfallbackとして保持するが、現時点では実装・Cloud Spikeを行わない。
