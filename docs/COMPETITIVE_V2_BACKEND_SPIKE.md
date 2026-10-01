# Competitive v2 Phase A-1 Backend / Per-match Ordering Spike

- Status: Phase A-1 complete; Candidate A系をPhase A-2 baselineとして**正式採用**
- Executed: 2026-09-28
- Interpretation updated: 2026-09-30
- SSOT: [`COMPETITIVE_V2_SPEC.md`](COMPETITIVE_V2_SPEC.md)
- actual Cloud follow-up: [`COMPETITIVE_V2_CLOUD_SPIKE_PLAN.md`](COMPETITIVE_V2_CLOUD_SPIKE_PLAN.md)（Candidate Aの隔離Spike実施・測定済み）
- Production deploy: None
- Production data / Rules changes: None

## Product rule correction（2026-09-30）

Production Competitiveの回答モデルは、現行フレンドバトルと同じく「各Playerが同じ問題へ独立して1回回答し、正解者をauthoritativeな受付順に採点する」方式である。最初の回答者が他PlayerをlockするFirst-winner exclusive方式は採用しない。

このため、本書のFirst-winner Lock / Winner Ordering FidelityはProduction Product ruleを直接再現したSpikeではない。結果は削除せず、RTDB CASのcontention、winner一意性、duplicate/retry耐性、latency、cold start、Cloud上の挙動を理解する技術資料として保持する。

4-way sequence assignmentも、複数同時request時のCAS contentionと一意な連番を示す技術資料である。payloadはhistoricalな`buzz` contractであり、Playerごとの独立回答、deadline/close競合、正誤、20 / 10 / 5 / 1点、誤答-10点、無回答0点を検証していない。全回答へ即座に`1, 2, 3, 4`のsequenceを付ける必要があるかも未決定である。

したがって、後段にあるCandidate AのFirst-winner前提の評価・推奨はこの修正により失効した。その後、Independent Answer Modelのlocal / actual Cloud追加検証とユーザーレビューを行い、最新Decisionは§24で確定した。

## 1. Purpose

当時のFirst-winner前提に基づき、4人CompetitiveのbuzzをFunction/Container instanceの完了順ではなく、1 Matchにつき1つの論理的Ordering Authorityで一意に並べる方式を比較した。

判断材料は次の5点に限定した。

1. 4人同時buzzのordering一意性
2. duplicate / retry / contention
3. T0〜T3 latency
4. 将来のSecurity強化可能性
5. Cost、運用複雑性、後戻りコスト

このSpikeはCompetitive本体、Production Backend、WebSocket基盤、正式Architectureを実装・確定するものではない。

## 2. Test Environment

| 項目 | 条件 |
| --- | --- |
| 実行元 | 同一Mac上のlocal test driver |
| Platform | macOS / Darwin 25.6.0 arm64 |
| Node | v24.14.0 |
| Firebase CLI | 15.26.0 |
| Project | `demo-hayaosiapp`（demo project） |
| RTDB | Database Emulator `127.0.0.1:9100` |
| Firestore | Firestore Emulator `127.0.0.1:8180` |
| DB location / Region | local Emulatorのため該当なし |
| Ingress | 同一processのlocal HTTP loopback |
| Functions / Cloud Run | 未deploy、runtime overhead未計測 |
| Concurrency | 4 requests |
| Startup相当 | 各候補1 round × 4 Intent |
| Warmup | 各候補5 rounds × 4 Intent（集計外） |
| Warm測定 | 各候補40 rounds × 4 Intent = 160 Intent |
| Percentile | nearest-rank |

Emulator結果はProduction latencyではない。特にFunctions 2nd gen / Cloud Runのnetwork、cold start、instance concurrency、実DB region間通信は含まない。

## 3. Methodology

共通のlocal HTTP handlerへ次のIntentを送った。

```text
matchId: spike-match
playerId: A | B | C | D
eventId: unique ID
sessionId: session-{playerId}
sessionEpoch: 1
buzz: true
```

各round前に同一のMatch stateを作り、A〜Dの4 requestを`Promise.all`でほぼ同時送信した。Spikeではordering primitiveそのものを比較するため、4つのunique buzzすべてをeventとして順序付け、`serverSequence = 1, 2, 3, 4`を与えた。

この測定時点では、最初の有効buzzだけが回答権を得るState Machineを前提としていた。この前提は2026-09-30のProduct rule correctionで失効した。現在のProduction想定では4人の有効な独立回答を各1件受理するが、このSpikeはanswer payload、正誤、採点、deadline closeを検証していない。

### Measurement points

- T0: test driverがHTTP request送信を開始
- T1: local Server handlerへrequestが到達
- T2: Ordering Authorityがcommit/直列処理を確定
- T3: HTTP responseをtest driverがparseして結果を利用可能

計測値:

- T1 → T2: Server内部Ordering latency
- T0 → T2: Client送信からOrdering確定
- T0 → T3: Client送信から結果利用可能

T3はこのSpikeではHTTP responseである。ProductionのRTDB/Firestore public projection listener反映時間は含まない。

### Common validation

- 同一`eventId`再送は元のsequenceを返し、再加算しない
- 同一Playerの別event buzzを拒否
- sessionId/epoch不一致を`STALE_SESSION`で拒否
- malformed / oversized fieldを拒否
- unknown matchを拒否し、自動作成しない

## 4. Candidate A — Functions 2nd gen + RTDB CAS

### Ordering Authority

1 Match rootに対するRTDB ETag compare-and-set（CAS）が論理的Authorityである。

1. match rootをETag付きでread
2. state、session、duplicateを検証
3. `serverSequence + 1`とevent/dedup stateを同じmatch rootへ構成
4. `If-Match: {etag}`付き条件write
5. HTTP 412なら最新stateをreadしてretry

複数Function instanceが存在しても、最終的なCAS成功順だけがorderingを決める。instanceの開始・完了順は使わない。

### Observation

- 40/40 measured roundsでsequence `[1, 2, 3, 4]`が重複なく成立した。
- 160 IntentでCAS attempt 400、contention retry 240。
- 4同時writeでは理論どおり1 round当たり概ね`1 + 2 + 3 + 4 = 10` attemptsになった。
- warm T1→T2 p95は10.440ms、T0→T3 p95は10.906msだった。
- Startup相当T0→T3 p95は60.301msだった。

### RTDB Admin transactionに関する補足

最初はAdmin SDK transaction callbackを試したが、Emulatorで存在済みpathにも初回`null`が渡された。未知Matchを誤作成しない安全側実装がtransactionをabortしたため、今回の比較対象は仕様で許容されているETag CASへ切り替えた。

これはRTDB transaction方式が不可能という結論ではない。Production実装でAdmin transactionを使う場合、callbackが`null`から開始し得る前提と、Match存在確認を安全に両立する設計が必要である。

## 5. Candidate B — Functions / Cloud Run + Firestore transaction

### Ordering Authority

1 Matchを表す1 Firestore documentへのtransaction commit順が論理的Authorityである。

1. transaction内でmatch documentをread
2. state、session、duplicateを検証
3. `serverSequence + 1`とevent/dedup stateを同じdocumentへwrite
4. contention時はFirestore SDKがtransaction callbackをretry

Function/Container instanceの完了順は使わない。

### Observation

- 40/40 measured roundsでsequence `[1, 2, 3, 4]`が重複なく成立した。
- 160 Intentでtransaction callback 318回、contention retry 158回。
- warm T1→T2 p50は3,028.113ms、p95は4,905.910ms、最大7,275.689msだった。
- warm T0→T3 p95は4,906.903ms、最大7,279.627msだった。
- Startup相当T0→T3 p95は3,406.379msだった。

Firestore Emulatorの単一document transaction競合ではretry backoffがtail latencyへ直接現れた。これはlocal Emulatorの結果であり実Cloud値へ外挿できないが、この方式を回答受付のhot pathへ採用するには実Cloudで反証が必要である。

## 6. Candidate C — Server-owned per-match sequencer

### Ordering Authority

1 Matchにつき1つのin-process serial queueが論理的Authorityである。

1. HTTP handlerがIntentをmatch queueへ投入
2. queueが1件ずつstateを検証
3. `serverSequence + 1`、event、dedup stateを同じauthority stateへ反映
4. 次eventを処理

Persistent connectionやWebSocketは使っていない。orderingを成立させるだけならHTTPでも検証できた。

### Observation

- 単一Authorityでは40/40 measured roundsでsequence `[1, 2, 3, 4]`が重複なく成立した。
- warm T1→T2 p50は0.016ms、p95は0.032msだった。
- warm T0→T3 p95は0.978msだった。
- transaction retryは不要だった。

### Scaling negative control

同じ`matchId`を2つの独立sequencerへ同時に持たせたところ、両方が`serverSequence = 1`を発行した。

したがってProductionでhorizontal scalingするには少なくとも次が必要になる。

- match → authority instanceのrouting
- authority ownershipを守るlease / fencing token
- instance終了時のstate checkpoint / event replay
- duplicate instanceの検出と停止
- reconnect時のroute再解決

In-memory stateだけではinstance終了時にsequence、dedup、session stateを失う。Candidate Cの低latencyは、これらのProduction要件をまだ含まない値である。

## 7. Ordering Authority Comparison

| Candidate | Authority | Horizontal instances | Instance終了 |
| --- | --- | --- | --- |
| A | RTDB match rootのCAS成功順 | DB CASが競合を直列化 | retry元が変わってもstate継続可能 |
| B | Firestore match documentのtransaction commit順 | DB transactionが競合を直列化 | retry元が変わってもstate継続可能 |
| C | 単一process内のmatch queue | routing + lease/fencingなしでは破綻 | durable checkpoint/replayなしではstate消失 |

3候補とも、複数Function instanceの「処理完了順」を競技順として使っていない。

## 8. Concurrency Results

| Candidate | Measured rounds | Concurrent Intent | Unique `1...4` | Sequence collision |
| --- | ---: | ---: | ---: | ---: |
| A | 40 | 160 | 40/40 | 0 |
| B | 40 | 160 | 40/40 | 0 |
| C（single authority） | 40 | 160 | 40/40 | 0 |
| C（2 independent authorities negative control） | 1 | 2 | 失敗 | 1組が両方sequence 1 |

Tie rule、latency compensation、Production state transitionは今回実装していない。特に、修正後Product ruleのPlayer別独立回答とquestion closeはこの結果に含まれない。

## 9. Duplicate / Retry Results

| Check | A | B | C |
| --- | --- | --- | --- |
| 同一eventId再送 | 元sequence 1を返し再加算なし | 同左 | 同左 |
| 同一Playerの別event | `DUPLICATE_PLAYER_BUZZ` | 同左 | 同左 |
| stale session/epoch | `STALE_SESSION` | 同左 | 同左 |
| malformed | `MALFORMED_REQUEST` | 同左 | 同左 |
| oversized field | `MALFORMED_REQUEST` | 同左 | 同左 |
| unknown match | `UNKNOWN_MATCH`、自動作成なし | 同左 | 同左 |
| Measured contention retry | 240 / 160 Intent | 158 / 160 Intent | 0 |

Harnessの`playerId`は比較用入力である。Productionでは認証contextのUIDからPlayerを導出し、payloadの自己申告IDを信頼しない。

## 10. Latency p50 / p95

### Warm measured latency（ms）

| Candidate | T1→T2 p50 | T1→T2 p95 | T0→T2 p50 | T0→T2 p95 | T0→T3 p50 | T0→T3 p95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A | 5.107 | 10.440 | 5.425 | 10.797 | 5.533 | 10.906 |
| B | 3,028.113 | 4,905.910 | 3,029.908 | 4,906.545 | 3,030.573 | 4,906.903 |
| C | 0.016 | 0.032 | 0.250 | 0.737 | 0.435 | 0.978 |

### Warm min / max（ms）

| Candidate | T1→T2 min | T1→T2 max | T0→T3 min | T0→T3 max |
| --- | ---: | ---: | ---: | ---: |
| A | 1.350 | 13.038 | 1.595 | 13.422 |
| B | 2,015.839 | 7,275.689 | 2,017.568 | 7,279.627 |
| C | 0.011 | 0.056 | 0.327 | 1.311 |

### 暫定Engineering targetとの比較

| Candidate | T1→T2 p95 ≤ 150ms | T0→T3 p95 ≈ 300ms以内 |
| --- | --- | --- |
| A | local Emulatorでは達成 | local Emulatorでは達成 |
| B | local Emulatorでは未達 | local Emulatorでは未達 |
| C | single-process prototypeでは達成 | single-process prototypeでは達成 |

これはSLA判定ではない。A/Cの実Cloud達成やBの実Cloud未達を証明する結果ではない。

## 11. Cold Start / Tail Latency

### Startup相当（最初の4 request、ms）

| Candidate | T1→T2 p50 | T1→T2 p95 | T0→T3 p50 | T0→T3 p95 |
| --- | ---: | ---: | ---: | ---: |
| A | 47.675 | 57.179 | 50.483 | 60.301 |
| B | 3,251.134 | 3,404.679 | 3,253.240 | 3,406.379 |
| C | 0.029 | 0.193 | 1.274 | 1.410 |

これはSDK接続、local Emulator、JIT等を含む「startup相当」であり、Functions 2nd gen / Cloud Runのcold startではない。

Warm tailではAのT0→T3最大13.422ms、Bは7,279.627ms、Cは1.311msだった。Bは平均値ではなくcontention retryのtailが主要リスクとなった。

実Cloud cold/warmを判断するには隔離されたsmall deployが必要である。必要な範囲は「同一Intent handler、Candidate A/Bのauthority処理、専用spike namespace、少数request」に限定できる。Production Rules変更やCompetitive本体は不要である。

## 12. Security Extensibility

| Security requirement | A | B | C |
| --- | --- | --- | --- |
| Auth UIDとPlayer一致 | IngressでUIDから導出可能 | 同左 | Authority入口で可能 |
| 他人として回答不可 | session/rosterをCAS内検証可能 | transaction内検証可能 | queue処理内で可能 |
| duplicate event | eventIdをauthority stateでdedup | 同左 | 単一Authorityでは同左 |
| duplicate Player event | Player別stateで拒否 | 同左 | 単一Authorityでは同左 |
| malformed / size | Ingressでallowlist/size制限可能 | 同左 | 同左 |
| stale session | sessionId/epochを同一commitで検証 | 同左 | durable authority stateが必要 |
| rate limit | Functions/API入口で可能 | Functions/Cloud Run入口で可能 | router/authority入口で可能 |
| App Check / App Attest | Functionsで検証可能 | Functions/Cloud Runで検証可能 | public ingressで検証可能 |
| replay protection | eventId + epochで可能 | 同左 | durable dedupなしでは再起動後に失う |

A/Bはclient direct writeを禁止し、server credentialだけがauthority stateを書けばSecurity境界を維持できる。CもSecurity検証自体は可能だが、restart/horizontal scalingを跨ぐdedup、session fencing、rate limit stateの永続化が追加で必要になる。

## 13. Cost Characteristics

実Cloudを使っていないため金額は未測定。

### Candidate A

- 既存Functions/RTDB資産を再利用しやすい。
- CAS contentionでread/write attemptが増える。今回4同時で1 Intent当たり平均1.5 retryだった。
- Spikeはmatch root全体をPUTしている。Productionでevent履歴を無制限に同じrootへ増やすとbandwidthとretry costが増えるため、bounded dedup / event compactionが必要。

### Candidate B

- Firestoreのmatch document readとtransaction retryが増える。
- 単一hot documentのcontentionはlatencyだけでなくread operation増加要因になる。
- Settlement等のdurable modelと揃えやすいが、回答受付のhot pathに対する費用対効果は実Cloud確認が必要。

### Candidate C

- DB round tripなしの処理自体は最小。
- Productionではinstance稼働、routing、ownership store、checkpoint/event log、障害復旧が必要。
- 常駐/min instanceやpersistent connectionを選ぶ場合はidle costを別途比較する必要がある。

## 14. Operational Complexity

| Candidate | Complexity | 主な運用対象 |
| --- | --- | --- |
| A | LOW〜MEDIUM | Function scaling、RTDB contention、bounded state、reconciliation |
| B | MEDIUM | Function/Cloud Run、Firestore contention/index、retry tail、document growth |
| C | HIGH | match routing、ownership lease/fence、checkpoint、instance drain、recovery |

Candidate Cではpersistent connectionはorderingの必須条件ではなかった。WebSocketを採用するかはpublic state配信、reconnect、費用を含む別判断である。

## 15. Migration / Reversal Cost

Client protocol、Match State Machine、Question API、Intent envelopeをAuthority adapterから独立させれば、3候補間で維持できる。

| 採用後に別方式へ変更 | Overall | 主な作り直し |
| --- | --- | --- |
| A → B | MEDIUM | RTDB state/CAS、projection、retry、Firestore schema |
| A → C | MEDIUM〜HIGH | routing、process ownership、fencing、checkpoint/replay |
| B → A | MEDIUM | Firestore transaction/schema、RTDB projection/CAS |
| B → C | MEDIUM〜HIGH | transaction authorityをactor ownershipへ置換 |
| C → A/B | HIGH | actor routing/ownership/connection運用を撤去し、DB authorityへ再構成 |

現在はSpike codeだけなので、現時点での後戻りコストはLOW。Phase A-2以降でCandidate固有のschemaやclient transportを直接結合すると急増する。

## 16. Pros / Cons

### Candidate A

**Pros**

- 一意なorderingをDB CASで説明しやすい
- local contention下で暫定targetを十分下回った
- instance終了やhorizontal scalingでもAuthorityをDBへ残せる
- 現行Firebase/RTDB知識を再利用しやすい

**Cons**

- contention分だけCAS retryが増える
- match root肥大化でlatency/costが悪化し得る
- Functions cold startとactual region latencyは未測定
- Admin transactionを選ぶ場合は初回`null`契約を安全に扱う必要がある

### Candidate B

**Pros**

- transaction commitをAuthorityとして説明しやすい
- durable result/settlementとmodelを揃えやすい
- Security検証とidempotencyをtransactionへ含められる

**Cons**

- local Emulatorの単一document contentionでp95約4.9秒
- retry backoffが回答受付のtail latencyへ直結
- hot documentのoperation数と費用が増え得る

### Candidate C

**Pros**

- 単一Authority内のorderingが最も明快
- DB round tripなしのprototype latencyは最小
- complexなmatch state transitionをserial codeで書きやすい

**Cons**

- horizontal scalingにはrouting + lease/fencingが必須
- instance終了時のdurability/recoveryを別途作る必要がある
- Production化すると実装・運用範囲が大きい
- 未完成のままではduplicate authorityにより競技結果が壊れる

## 17. Remaining Uncertainty

1. deployment rolloutで事前起動されていない純粋なplatform cold start
2. RTDB public projection listenerを含むT0→T3
3. App Check/Auth検証を含むIngress overhead
4. Player別独立回答とquestion closeへpublic projection / Auth / App Checkを加えた場合のend-to-end latency
5. Candidate Aのbounded state/compaction後のcontention
6. Candidate Bの実Cloud contentionがEmulator結果とどの程度異なるか
7. Candidate Cのrouting/fencing/durable recovery込みlatencyと費用
8. authoritative ordering、latency compensation、near-tie threshold

### Actual Cloud measurementを行う場合

- **なぜ必要か**: serverless cold start、actual region/network、public projectionをlocal Emulatorから推定できないため。
- **deploy範囲**: 隔離したnon-production projectまたは明確なspike endpoint/pathにCandidate A/Bの最小handlerだけ。Competitive本体、Production Rules、UIは含めない。
- **分かること**: warm/cold T0→T3、actual contention tail、region差、Auth/App Check overhead。
- **費用影響**: 少数invocationとDB operation。min instancesを使う比較はidle costが発生するため別途承認が必要。
- **既存環境への影響**: 別projectが最小。同一projectの場合も専用namespace、専用認可、削除可能なspike resourceに限定する。

Local比較の実行時点ではdeployしていなかった。Candidate Aのactual Cloud follow-upは次節のとおり完了した。

## 18. Candidate A Actual Cloud Result

- Executed: 2026-09-29
- Driver: Tokyo local Mac
- Functions / RTDB: `asia-southeast1`
- Runtime: Functions 2nd gen / Node.js 22、`minInstances=0`、`maxInstances=4`、`concurrency=20`
- Isolation: `__spikes/competitiveV2OrderingA/cloud-a-20260929-02`
- Warmup: 5 rounds × 4 concurrent
- Measured: 40 rounds × 4 concurrent = 160 Intent
- IAM: Spike専用2Functionだけpublic invoker。専用Secret token guardを維持
- Secret: rotation済み。両Functionはversion 3を参照（値は未記録）
- Production Rules / schema / existing Functions changes: None
- Cleanup: runId配下を削除済み

### Security preflight

| Check | Result |
| --- | --- |
| tokenなし | Function token guardでHTTP 401 |
| 不正token | Function token guardでHTTP 401 |
| 正しいtoken | Control / OrderともHTTP 200 |
| malformed | `MALFORMED_REQUEST` |
| unknown match | `UNKNOWN_MATCH` |
| stale session | `STALE_SESSION` |

### Warm latency（ms）

| 区間 | min | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| T1→T2 | 33.030 | 108.122 | 260.739 | 832.531 |
| T0→T2（近似） | 282.816 | 377.321 | 534.231 | 1,101.531 |
| T0→T3 | 178.157 | 281.517 | 443.380 | 1,037.974 |
| RTDB CAS | 32.944 | 108.037 | 260.634 | 832.439 |

T0→T2はdriver/server間のwall clock差を含む。T1→T2とT0→T3はmonotonic clockである。warm access token取得はp95 0.087msで、server-side tailはほぼRTDB CASが占めた。

deploy後最初の有効Order invocationはT1→T2 245.438ms、T0→T3 444.717msだった。ただしdeployment rolloutでinstanceはrequestの13.782秒前に起動済みだったため、container startup全体を含む純粋なcold start値ではない。

### Ordering / retry

- 40/40 roundsでsequence `[1, 2, 3, 4]`が一意に成立
- sequence collision 0、gap 0
- CAS attempt 355 / 160 Intent、contention retry 195
- duplicate eventは元sequenceを返し再加算なし
- duplicate playerは拒否
- 同一eventのconcurrent retryは1 event / sequence 1だけを永続化
- malformed / stale / unknown match拒否成功

### Localとの差とtarget

| 指標 | Local A | Actual Cloud A | 倍率 |
| --- | ---: | ---: | ---: |
| T1→T2 p50 | 5.107 | 108.122 | 21.17x |
| T1→T2 p95 | 10.440 | 260.739 | 24.97x |
| T0→T3 p50 | 5.533 | 281.517 | 50.88x |
| T0→T3 p95 | 10.906 | 443.380 | 40.65x |

- T1→T2 p95は暫定理想150msを110.739ms超過した。
- T0→T3 p95は暫定目標300msを143.380ms超過した。
- p50 T0→T3は281.517msで暫定目標内だが、tailと最大値が大きい。
- 最大の問題は4 concurrent CAS contention時のRTDB round-trip tailであり、warm時も最大1秒前後になった点である。

Actual Cloud結果だけではCandidate Aの正式採用を推奨しない。暫定targetは絶対要件ではないが両p95を超えた。後続のFirst-winner測定ではCAS writeを1件へ減らしたが、その方式は現在のProduction Product ruleではない。修正後モデルで必要なPlayer別独立受付とquestion closeの構成は、この結果だけから決定できない。

## 19. Candidate A First-winner Lock Cloud Spike

- Executed: 2026-09-29
- Driver: Tokyo local Mac
- Functions / RTDB: `asia-southeast1`
- Runtime: Functions 2nd gen / Node.js 22、`minInstances=0`、`maxInstances=4`、`concurrency=20`
- Isolation: `__spikes/competitiveV2OrderingA/cloud-a-first-winner-20260929-02`
- Warmup: 5 rounds × 4 concurrent
- Measured: 40 rounds × 4 concurrent = 160 Intent
- Model: `QUESTION_OPEN`ごとに最初の有効buzz 1件だけをCASでwinner確定し、後続3件は`BUZZ_ALREADY_LOCKED`で拒否
- Secret: 既存version 3を継続利用し、rotationなし
- Production Rules / schema / existing Functions changes: None
- Cleanup: preflight / measuredの両runIdを削除し、CLI readback `null`を確認済み

前節の4-way sequence assignmentとは別測定である。今回は後続Playerへsequence 2〜4を永続化せず、winner確定の1 state transitionだけを保存した。

### Winner correctness / safety

- 40/40 roundでaccepted winner exactly 1、loser exactly 3
- winner collision 0、winner overwrite 0
- 永続化されたwinner eventは各round 1件、`serverSequence=1` / `stateVersion=1`
- winner eventのretryは元decisionをduplicateとして返し、同一eventのconcurrent retryも永続event 1件
- loser eventのretryは`BUZZ_ALREADY_LOCKED`のままでwinnerを変更しない
- stale session / malformed / unknown matchを拒否
- test-only Control helperで、A不正解後にAをlocked outして再openし、元の`questionOpenedAt` / `questionDeadline`を維持したままBが次のwinnerになれることを確認した。Production Match State Machineは実装していない

### Warm latency（ms）

| 区間 | min | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| T1→T2 | 35.348 | 79.006 | 98.681 | 799.810 |
| T0→T2（近似） | 159.042 | 213.198 | 266.378 | 939.810 |
| T0→T3 | 182.725 | 238.356 | 299.275 | 1,009.619 |
| RTDB CAS / decision read | 35.283 | 78.943 | 98.522 | 799.715 |

160 Intentはすべてwarm sampleで、測定中の新規instance初回invocationは0だった。T0→T2はdriver/server間のwall clock差を含む近似値である。

### Winner / loser latency（ms）

| 対象 | T1→T2 p50 | T1→T2 p95 | T0→T3 p50 | T0→T3 p95 |
| --- | ---: | ---: | ---: | ---: |
| winner 40件 | 48.655 | 60.661 | 210.221 | 253.371 |
| loser 120件 | 83.296 | 101.673 | 243.571 | 300.178 |

loserは競合負け後の再readで既存winnerを確認するため、winnerよりT1→T2 p95が41.012ms、T0→T3 p95が46.807ms長かった。overall T0→T3 p95は299.275msで暫定目標内だが、loser単独p95は300.178msで0.178ms上回った。

### Cold sample

deploy直後のpreflightはOrder instanceの初回invocationで、instance ageはT1時点64msだった。1 sampleのみで、T1→T2 1,909.008ms、T0→T2近似5,504.008ms、T0→T3 5,465.239ms、access token 115.654ms、RTDB CAS 1,792.450msだった。cold startを含む初回体験はwarm targetを大幅に超えるため、Production方針決定後も別途扱う必要がある。

### CAS contention / previous model comparison

- conditional RTDB PUT: 156回、平均3.9回 / round
- decision loop: 276回
- HTTP 412 contention retry: 116回

| 指標 | 4-way sequence | First-winner lock | 差 |
| --- | ---: | ---: | ---: |
| CAS attempt | 355 | 156 | 199減（56.1%減） |
| contention retry | 195 | 116 | 79減（40.5%減） |
| T1→T2 p95 | 260.739ms | 98.681ms | 162.058ms改善（62.2%減） |
| T0→T3 p95 | 443.380ms | 299.275ms | 144.105ms改善（32.5%減） |

T1→T2 p95は理想150msを51.319ms下回り、T0→T3 p95は暫定300msを0.725ms下回った。最大値は約0.8秒 / 1.0秒であり、tailが消えたわけではない。

### Evaluation

**First-winner CAS primitive単体では十分有望**という技術評価である。winner一意性とretry安全性を保ったまま両p95が暫定target内へ改善したが、Production Product ruleの評価ではない。

現在必要な4人の独立回答、Player別duplicate、deadline/close競合、canonical ordering、採点を検証していないため、この結果からCandidate Aの正式採用やCandidate C検証の要否は判断しない。cold sample、最大tail、public projection / Auth / App Checkを含まない点も残る。

## 20. Candidate A Winner Ordering Fidelity

- Executed: 2026-09-29
- Driver: Tokyo local Mac
- Functions / RTDB: `asia-southeast1`
- Runtime: Functions 2nd gen / Node.js 22、`minInstances=0`、`maxInstances=4`、`concurrency=20`
- Isolation: `__spikes/competitiveV2OrderingA/cloud-a-winner-fidelity-20260929-01`
- Warmup: 5 rounds × 4 concurrent
- Measured: 40 warm rounds × 4 concurrent = 160 Intent
- Cleanup: runId配下を削除し、CLI readback `null`を確認済み

Function handler入口で`performance.timeOrigin + performance.now()`による高分解能T1を記録し、既存responseへ追加した。各requestのplayerId、T1、winner / loser、Function instance ID、winner lock結果をdriver側で集計した。観測用のRTDB writeは追加していない。client timestampは取得・使用しておらず、競技Authorityは引き続きRTDB CASである。

### Result

- earliest T1がactual winner: 21 / 40 round（52.5%）
- mismatch: 19 / 40 round
- exact T1 tie: 0 round

| mismatch winner T1 − earliest T1 | min | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| gap（ms） | 1.306 | 4.722 | 8.214 | 8.214 |

指定閾値は重複を含む累積件数である。

| Bucket | 件数 |
| --- | ---: |
| 10ms以内 | 19 |
| 20ms以内 | 19 |
| 30ms以内 | 19 |
| 50ms以内 | 19 |
| 50ms超 | 0 |
| 100ms超 | 0 |

排他的bucketでも`0〜10ms`が19件で、`10〜20ms`、`20〜30ms`、`30〜50ms`、`50〜100ms`、`100ms超`はすべて0件だった。

### Function instanceとの関連

- 測定に使われたdistinct Order instance: 1
- single-instance round: 40、うちmismatch 19
- multi-instance round: 0
- mismatchでearliest requestとwinnerが同一instance: 19
- mismatchで別instance: 0

今回のmismatchはすべて同一instance内であり、cross-instance clock差では説明されない。一方、複数instance間のwall clockは完全に共通の公平時計ではないため、この測定はcross-instance fidelityを証明しない。T1は観測値であり、client timestampと同様に競技Authorityへ採用しない。

### Evaluation

**Historical First-winner評価ではB（Near-tieでは不確実だが許容可能）**だった。一致率は52.5%で、全19 mismatchが8.214ms以内、10msを超えるinversionは0だった。

現在のProduct ruleではwinnerを1人へlockしないため、このA/B/C評価をProduction Architectureの採用判定へ使わない。ただし、Function入口時刻とRTDB CAS commit順がnear-tieで一致しないこと、複数instanceのclock比較に限界があることは、独立回答のauthoritative orderingを設計する際にも再利用できる観測である。Tie threshold自体はこのSpikeでは決定しない。

## 21. Historical Recommendation Before Independent Answer Spike

### Provisional result: Product rule correctionによりArchitecture評価を再開する

Candidate A、B、Cのいずれも正式採用しない。First-winner前提で行ったCandidate A推奨は失効した。

既存結果から再利用できる証拠:

1. RTDB CASは複数request間で一意なcommitとretry安全性を作れる。
2. duplicate、stale session、malformed、unknown matchをAuthority境界で拒否できた。
3. 4-way CASのcontention量とlatency、First-winner CASのlatency/cold tailをactual Cloudで観測した。
4. Function入口時刻とCAS commit順は10ms未満のnear-tieで入れ替わり得る。
5. First-winner測定ではwarm T1→T2 p95 98.681ms、T0→T3 p95 299.275msだったが、独立回答モデルの性能値として転用できない。

新たに必要な証拠:

1. 4人の有効な独立回答を各Player1件ずつ受理できること。
2. 同一Playerのduplicate/retryが二重回答・二重加点にならないこと。
3. deadline直前回答とquestion closeの競合が、一意な受理済み回答集合へ収束すること。
4. canonical orderingから20 / 10 / 5 / 1、誤答-10、無回答0を再現できること。
5. 全員回答済みとdeadlineの両経路で同じ結果へ収束し、public projectionまでのlatencyが許容範囲にあること。
6. 全回答をmatch-root CASで即時採番する必要があるか、Player別受付後のcloseで十分かを比較できること。

### Observation

- Candidate AのCAS correctness、latency、cold/tail観測は有効だが、corrected Product ruleへの適合性は未検証。
- Candidate Bはordering correctnessを満たすが、local contention tailが回答受付のhot pathには大きな懸念。
- Candidate Cはlocalで最速だが、低latency値にrouting/durability/failoverが含まれていない。
- 全回答に単一連番を即時付与すること自体はProduct要件ではなく、必要なordering primitiveを先に再定義する必要がある。

### Proposed change

Phase A-2へはまだ進まない。新しいSpikeもこの文書更新では開始しない。次の比較を行う場合もClient Intent / ack / State Machineをbackend-neutralに保つ。

### Open question

独立回答の受付・close・採点をどのprimitiveで確定するか。Candidate C actual Cloud比較の要否も、修正後要件に対するCandidate Aの設計案と追加検証結果が出るまで判断しない。

## Architecture Decision Gate

**該当する。正式Backend選択前に停止する。**

1. **今後決める必要があること**: 独立回答を一度だけ受理し、deadline/closeとauthoritative orderingを確定するBackend primitive。
2. **現時点の判断**: Candidate Aは未採用。Candidate C検証の要否も未決定。
3. **Player体験**: 全Playerが独立回答し、正解者の回答順で得点する現行フレンドバトル方式を維持する。
4. **Security**: Clientは結果を決めず、Serverが回答受付、duplicate、deadline、正誤、ordering、score、match resultを確定する。
5. **Cost**: 初期目安は月3,000円程度。Hard capではないが、minInstances、常時Server等で大きく超える可能性がある場合は採用前に報告する。
6. **保留可能か**: 可能。既存Spikeを技術資料として保存し、Production schema/transportを作らなければ後戻りコストはLOWのまま。

Backendはこの文書では正式採用しない。Phase A-2、Production deploy、Competitive本体実装へ進まない。

## 22. Independent Answer Model Spike

- Executed: 2026-09-30
- Environment: Tokyo local Mac / Node.js / RTDB Emulator `127.0.0.1:9100`
- Project: `demo-hayaosiapp`
- Warmup: 各model 5 rounds × 4 concurrent（集計外）
- Measured: 各model 40 rounds × 4 concurrent = 160 answer Intent
- Deadline race: 40 rounds
- Production deploy / Rules / schema changes: None
- Cleanup: 専用path削除後、readback `null`を確認

これはlocal Emulator Spikeであり、Functions 2nd genのcold start、実region間network、Auth/App Check、public projection listenerは含まない。Candidate Aの正式採用証拠ではない。

### 22.1 Spike上のdata model

比較対象は次の2方式とした。

1. **Global Sequence CAS**: question root全体をETag CASし、各回答時にglobal sequenceを即時採番する。旧4-way sequence方式に相当する比較用model。
2. **Independent Close Order**: `matches/{matchId}/answers/{uid}` をPlayerごとのcreate-only領域とし、`If-Match: null_etag`で最初の1件だけ保存する。各answer同士は同じfieldを更新しない。`QUESTION_RESULT`確定時だけquestion rootをETag CASし、canonical orderとscoreを固定する。

Independent modelのanswer recordは`questionId / answerId / eventId / sessionId / sessionEpoch / RTDB Server timestamp`だけを持つ。Player IDは認証context相当のheaderからServerが取得し、payloadのPlayer ID、correctness、response rank、score delta、response timeは受け付けない。

### 22.2 Canonical ordering

Independent modelではRTDB Server timestampの昇順を回答順とし、完全に同一timestampの場合は試合開始時に固定したparticipant order（A、B、C、D）をtie-breakにした。Client timestampとFunction instance clockは競技Authorityに使用しない。

closeはquestion rootのETag CASで行う。answer child writeがcloseと重なった場合、close側のparent ETagが無効化されてretryする。closeが先に確定した場合、answer handlerはpost-write readでresultへの採用有無を確認し、未採用として拒否する。確定済みresultは後続answerで変更しない。

### 22.3 4 concurrent answer latency

単位はms。T1→T2はlocal Server受付からanswer判定確定、T0→T3はlocal driver送信からack利用可能まで。

| Model | 区間 | min | p50 | p95 | max |
| --- | --- | ---: | ---: | ---: | ---: |
| Global Sequence CAS | T1→T2 | 0.771 | 5.080 | 20.424 | 39.280 |
| Global Sequence CAS | T0→T3 | 1.022 | 5.433 | 23.033 | 41.284 |
| Independent Close Order | T1→T2 | 1.123 | 1.601 | 9.710 | 51.112 |
| Independent Close Order | T0→T3 | 1.340 | 1.882 | 10.143 | 53.440 |

Independent modelは160/160 answerを各Player1件ずつ受理した。p95はGlobal Sequence CASよりT1→T2で10.714ms、T0→T3で12.890ms短かった。これはlocal Emulator比較でありactual Cloudへ外挿しない。

### 22.4 Contention / retry

40 measured roundsのanswer受付とcloseを集計した。setup / cleanupは除外した。

| Model | answer read | answer write attempt | accepted write | contention retry | close read/write/retry |
| --- | ---: | ---: | ---: | ---: | ---: |
| Global Sequence CAS | 400 | 400 | 160 | 240 | 40 / 40 / 0 |
| Independent Close Order | 320 | 160 | 160 | 0 | 40 / 40 / 0 |

Global Sequence CASは1 answer当たり平均2.5 CAS attempt、1.5 contention retryだった。Independent modelはPlayer別pathのため、4 concurrent answer間のcontention retryは0だった。question closeのroot CASは両modelとも40/40で1 attemptだった。

### 22.5 Duplicate / Security checks

次をすべてpassした。

- 同一eventId retryは元結果を返し、新規answerを作らない
- 同一Playerの別eventIdによる2回答目を拒否
- 同一eventIdのconcurrent retryは1 accepted / 1 duplicate、保存answerは1件
- stale question、wrong session、unknown answerIdを拒否
- payloadへ`correct` / `scoreDelta`を追加した要求をmalformedとして拒否
- payloadで他Playerを指定する要求を拒否し、保存先uidは認証context相当から導出
- QUESTION_RESULT確定後のanswerを拒否し、result / score / orderingを変更しない

### 22.6 Deadline / close race

- deadline前answer: acceptedとなりresultへ含まれた
- deadline後answer: rejectedとなりresultから除外された
- result確定後answer: rejected、result不変
- answerとdeadline closeを近接実行した40 rounds: accepted 38、rejected 2
- 40/40でanswer ackと最終resultの採用有無が一致し、中間状態や二重判定は0
- 遅延answer後も40/40で保存済みresultのreadbackが不変

このSpikeでは、Server受付時刻だけで採用を決めず、Player別writeの確定とroot close CASの線形化順も含めてaccepted / rejectedを一意にした。

### 22.7 Close condition / score rule

全員回答ではdeadline前に`QUESTION_RESULT`へcloseし、一部未回答ではdeadline closeを使用した。次をすべて再現した。

| Case | Result |
| --- | --- |
| A correct earliest / B wrong / C correct second / D no answer | A +20 / B -10 / C +10 / D 0 |
| 正解1人 | +20、他3人 -10 |
| 正解4人 | +20 / +10 / +5 / +1 |
| 全員誤答 | 全員 -10 |
| 全員無回答 | 全員 0 |
| exact同timestamp | participant order A / B / C / Dで20 / 10 / 5 / 1 |

誤答はcorrect rankを消費せず、Client指定のcorrectnessやscoreを使用していない。

### 22.8 Immediate global sequenceの必要性

現行Product ruleを満たすために、各answerへ即座にglobal sequenceを付ける必要はない。必要なのは、Playerごとの最初の有効answerを一度だけ保存し、close時にServer-owned timestampとdeterministic tie-breakからcanonical orderを再構築できることである。

match state / projection全体の`serverSequence`は引き続き利用できるが、score順位のために全answerを同じCASへ直列化する必要はない。この判断はSpike上の設計評価であり、Production schemaの確定ではない。

### 22.9 Cost characteristics

このSpikeのIndependent modelをそのまま数えると、全員回答した1 question当たり次のoperationだった。

- Function相当: answer 4 + close 1 = 5 invocation
- RTDB: answer 8 read + 4 write、close 1 read + 1 write = 9 read / 5 write
- contention retry: 0

20 questionsでは概算100 invocation、180 read、100 writeとなる。setup、public projection listener、Auth/App Check、logging、reconciliation、異常retryは含まない。4人目answer処理内へcloseを統合すればinvocationを減らせる可能性はあるが、今回は測定していない。

このoperation数自体は月3,000円程度という初期目安と明らかに不整合ではない。ただし利用match数、egress、log、cold対策、minInstancesを含むactual Cloud費用は未測定であり、金額を保証しない。

### 22.10 Candidate A系Architecture評価

**Local evidenceでは有望だが、正式採用しない。** Player別create-only answerとroot close CASの組み合わせは、4人独立回答、duplicate、deadline race、canonical ordering、現行score ruleを再現し、旧match-root global sequence CASよりcontentionを減らした。

正式判断前に残る確認:

1. actual Functions 2nd gen + RTDBでのp50/p95/cold/tail
2. 複数Function instanceでのRTDB Server timestampとclose race
3. Auth/App Check、private question data、public projectionを含むend-to-end
4. Function失敗・answer write成功後のack retryとreconciliation
5. Production Rules/schemaを確定する前のSecurity review

現時点でCandidate Cの追加Cloud検証を必須とは判断しない。Candidate A系がactual Cloudでdeadline/close correctness、latency、費用、復旧要件を満たさない場合、またはより強い一括sequencing保証が必要になった場合に再評価する。

### 22.11 Architecture Decision Gate

**該当する。** Client Intent / ack / public projectionをRTDBの物理pathへ直接結合すると、将来Server sequencerへ移行する際の作り直しが大きくなる。Phase A-2前に、backend-neutralなcontractとadapter境界を維持したままCandidate A系を採用するかユーザーレビューが必要である。

この文書ではCandidate Aを正式採用せず、Candidate C、Phase A-2、Production implementationへ進まない。

## 23. Independent Answer Model Actual Cloud Spike

- Executed: 2026-09-30
- Driver: Tokyo local Mac
- Functions / RTDB: `asia-southeast1`
- Runtime: Cloud Functions 2nd gen / Node.js 22
- Warmup: 10 rounds × 4 concurrent（集計外）
- Measured: 40 rounds × 4 concurrent = 160 answer Intent
- Deadline race: 12 rounds
- Order Function: Spike限定で`concurrency=1`、`minInstances=0`、`maxInstances=4`
- Production Rules / schema / `rooms/` / Friend Battle: 変更なし
- Cleanup: `cloud-a-independent-20260930-01`配下を削除し、CLI readback `null`を確認

Local §22と同じPlayer別create-only modelを、既存のSpike専用Function名、Secret、RTDB namespaceでactual Cloud実行した。測定時点では正式採用前であり、その後のDecisionは§24に記録する。

### 23.1 Data model / multiple instances

回答は`matches/{matchId}/answers/{playerId}`へ`If-Match: null_etag`でcreate-only保存し、Player IDはSpike認証context相当のheaderからServerが導出した。answer recordは`questionId / answerId / eventId / sessionId / sessionEpoch / RTDB Server timestamp`だけを保持する。correctness、rank、score、client timestampは受け付けない。

40/40 round、160/160 answerを受理し、各roundでA〜Dがそれぞれ1件だけ保存された。answer欠損、overwrite、他Playerへの干渉、ordering異常は0だった。4つのOrder Function instanceへ各40 requestずつ分散した。warmupでinstanceが作られたため、measured 160件にplatform cold invocationは含まれない。

### 23.2 Duplicate / deadline / close correctness

- 同一eventのsequential retry: 元answerを返し、追加保存なし
- 同一Playerの別event: `DUPLICATE_ANSWER`
- 同一eventのconcurrent retry: 1 accepted / 1 duplicate、条件付きwrite競合1回、保存1件
- stale question / wrong session / forged result fields / payloadでの他Player指定: すべて拒否
- deadlineより明確に前: acceptedかつresultへ収録
- deadlineより明確に後: `DEADLINE_EXCEEDED`かつresultから除外
- deadline付近でanswerとcloseを並行実行: 12/12 rejected、ackとresultの不一致0
- result確定後のlate answer: 12/12 rejected、canonical order / score / resultの変化0
- close CAS contention retry: 0

deadline Authorityはanswer保存時とclose時のRTDB Server timestampである。Client timestampとFunction instance clockは判定に使用しない。closeはquestion rootのETag CASで線形化し、answer ackは確定済みresultへの収録有無、またはServer timestampとdeadlineの比較から一意に決定した。deadline付近の12件は東京からの往復を含むため全件がServer到達時点で期限後になったが、accepted/rejectedと最終resultの整合は全件で維持された。

### 23.3 Canonical ordering / score

QUESTION_RESULT確定時にRTDB Server timestamp昇順でcanonical orderを構築し、完全同timestampはparticipant orderで決定した。Client timestamp、Function clock、duplicateはorderingへ使用しない。

- exact tie: A / B / C / D、score 20 / 10 / 5 / 1
- 代表ケース A correct earliest / B wrong / C correct second / D unanswered: A +20 / B -10 / C +10 / D 0

誤答Bは正解順位を消費しなかった。

### 23.4 Actual Cloud latency（ms）

measured 160 answerはすべてwarm sampleである。

| 区間 | min | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| T1→T2 | 53.691 | 77.829 | 96.307 | 227.645 |
| T0→T3 | 151.098 | 176.653 | 197.892 | 321.163 |
| RTDB処理内訳 | 53.549 | 77.700 | 96.164 | 227.485 |

T0→T3のmaxは321.163msだったがp95は197.892msであり、独立回答のackとして明確な体感上の不足は観測しなかった。minInstancesは0のままで、cold tailは今回のmeasured setでは評価していない。

### 23.5 Operation / cost

measured normal pathでは、160 answerに320 read / 160 write、40 closeに40 read / 80 writeを使用し、contention retryは0だった。closeのwrite 2件はRTDB Server clock取得1件とquestion root CAS 1件である。

| Scope | Function invocation | RTDB read | RTDB write attempt | Contention retry |
| --- | ---: | ---: | ---: | ---: |
| 1 question / 4 Player | 5 | 9 | 6 | 0 |
| 1 match / 20 questions | 100 | 180 | 120 | 0 |

setup、status read、public projection listener、Auth/App Check、logging、異常retryはこの概算に含まない。このoperation量は初期運用目安の月3,000円程度と明らかに不整合ではないが、match数とegressを含む月額Traffic modelを作っていないため金額は保証しない。

### 23.6 Evaluation / Architecture Decision Gate

**Candidate A系評価: A（Phase A-2の基盤候補として十分有望）。** Independent create-only answer、Server deadline、root close CAS、canonical ordering、Product score ruleはactual Cloudの複数instance下で成立し、通常4 concurrent answerのDB contention retryは0だった。

今回の結果だけを理由にCandidate CのCloud検証は不要と判断する。Architecture Decision Gateには次が残る。

1. Auth / App Check、private question data、public projectionを含むProduction contract
2. answer write成功後のFunction失敗、ack retry、reconciliation方針
3. cold start / rollout時tailと監視方針
4. 実利用match数、egress、loggingを含む月額費用見積り
5. backend-neutral contract / adapter境界を維持したProduction schema

測定完了時点ではSpike Function 2本、Secret version 3、public invokerをArchitecture review用に保持した。新しいSecret versionやCloud resourceは作成していない。Decision後のcleanup結果は§24に記録する。

## 24. Architecture Decision（2026-09-30）

Phase A-1のlocal / actual Cloud Independent Answer Spikeとユーザーレビューを根拠に、**Candidate A系をPhase A-2のCompetitive Backend baselineとして正式採用する**。これはProduction Ready宣言ではない。

採用baseline:

- Firebase Functions 2nd gen + Firebase Realtime Database
- Server-authoritative、ClientはIntentのみ送信
- `answers/{playerId}`へのPlayer別create-only answer
- RTDB Server timestampを回答時刻Authorityに使用
- question close時にServerがcanonical ordering、正誤、得点、resultを確定
- 完全同timestampはparticipant順
- 回答順位用global sequenceの即時CASは使用しない

Client contractはRTDBの物理path / schemaへ直接依存させない。`submitAnswer Intent → Competitive Backend → authoritative result`を境界とし、Functions / RTDBはServer実装詳細としてadapterの内側へ置く。

Candidate Cはfallbackとして記録を維持する。Firebase方式がlatency、contention、persistent state、realtime projection、費用、SecurityのProduction要件を満たせない場合に再検討するが、現時点では実装・Cloud Spikeを行わない。

Phase A-1は完了とする。Phase A-2ではAuth / authorization、App Check / App Attest、private question / public projection、idempotent answer APIとfailure recovery、cold start、Realtime projection latency、実trafficに基づく費用を必須課題として扱う。Phase A-2実装はこのDecision commitには含めない。

Architecture Decision後、Spike専用Cloud Function `competitiveV2OrderingSpikeAControl` / `competitiveV2OrderingSpikeAOrder`、対応public endpoint、Secret `COMPETITIVE_V2_SPIKE_TOKEN` versions 1 / 2 / 3を削除した。`firebase functions:list`では既存Production Function `sendRoomInvite`だけが残り、Secret metadata取得は404 `not found`となることを確認した。Production Rules、`rooms/`、schema、既存Functionは変更していない。repo上のSpike source / driver /結果文書は再現証拠として保持するが、`functions/index.js`からSpike exportを除去した。

## Reproduction

```bash
FIREBASE_CLI_DISABLE_UPDATE_CHECK=true \
node_modules/.bin/firebase emulators:exec \
  --project demo-hayaosiapp \
  --only firestore,database \
  "node spikes/competitive-v2-backend-ordering/run.cjs"
```

Harnessは両Emulator環境変数がない場合に即終了するため、本番DBへfallbackしない。

Independent Answer Model Spike:

```bash
FIREBASE_CLI_DISABLE_UPDATE_CHECK=true \
node_modules/.bin/firebase emulators:exec \
  --project demo-hayaosiapp \
  --only database \
  "node spikes/competitive-v2-backend-ordering/independent-answer-run.cjs"
```

このHarnessはRTDB Emulator環境変数がない場合に即終了し、専用pathを実行終了時にcleanupする。
