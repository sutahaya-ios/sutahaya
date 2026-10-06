# Competitive v2 Phase A-2 Production Cloud E2E Runbook

## 状態と境界

- この文書とdriverの作成時点ではProduction環境を変更していない。
- 対象projectは `hayaosiapp`、Functions regionは `asia-southeast1`、RTDBは `asia-southeast1`。
- deploy対象はRTDB Rulesと `competitiveIntent` / `competitiveReconcileMatch` の2 Functionだけ。
- `sendRoomInvite`、`rooms/`、既存Friend Battle、既存ユーザーデータは対象外。
- `enforceAppCheck: false` を維持する。App Check enforcement、一般公開用rate limit、一般公開時のreconcile triggerは別Security / Architecture Gateとする。
- Cloud E2Eではdriverがreconcileを明示的に呼ぶ。Production trigger方式はここでは決めない。

## E2E driver

review-only（network writeなし）:

```sh
npm run competitive:cloud-e2e:review
```

実行には、ユーザーがProduction deployとCloud E2Eを別途明示許可した後、次をruntimeだけへ渡す。

- Application Default Credentials: Admin SDKによる専用match作成、custom token発行、cleanup用
- `COMPETITIVE_V2_E2E_API_KEY`
- `COMPETITIVE_V2_E2E_AUTH_DOMAIN=hayaosiapp.firebaseapp.com`
- `COMPETITIVE_V2_E2E_DATABASE_URL=https://hayaosiapp-default-rtdb.asia-southeast1.firebasedatabase.app`
- `COMPETITIVE_V2_E2E_PROJECT_ID=hayaosiapp`
- `COMPETITIVE_V2_E2E_TEST_UIDS`: 明示許可済みの既存専用Auth UIDを4件、comma区切り
- `COMPETITIVE_V2_E2E_ALLOW_PRODUCTION=ALLOW_ISOLATED_COMPETITIVE_V2_CLOUD_E2E`

password、ID token、refresh token、custom tokenはファイルへ保存せず、表示もしない。driverはAdmin SDKが生成したcustom tokenをメモリ内だけで使用する。専用Auth userの作成はdriverの責務外。

実行command:

```sh
node scripts/competitive-v2-cloud-e2e.cjs --execute
```

driverはランダムな `competitiveV2/matches/e2e-a2-<timestamp>-<uuid>` だけを作成し、4 clientでpublic projectionを監視する。20問完走、独立回答、得点、deadline/all-answered、duplicate/retry、各種拒否、private read拒否、最終scoreを検証する。終了・失敗のどちらでも、作成したmatchと対応する `competitiveV2/clocks/<matchId>` だけを削除し、削除後readbackに成功しなければ失敗とする。

## T0〜T4とcold / warm

- T0: driverがcallableを送る直前のmonotonic clock
- T1: Function handler入口のmonotonic clock
- T2: authoritative transaction完了後、ack作成時のmonotonic clock
- T3: driverがcallable ackを受け取った時刻
- T4: 同じ `publicStateVersion` を4 clientすべてが観測したうち最も遅い時刻

T1→T2、T0→T3、T0→T4のmin / p50 / p95 / maxを出力する。T1/T2とRTDB server timestampは観測専用であり、Client時刻を競技Authorityには使用しない。Function instanceごとのID、instance内invocation番号、instance ageを記録し、最初の呼び出しとwarm回答、複数instance発生を区別する。`minInstances` は0のまま変更しない。

## deploy直前readback Gate

Production変更の許可後、deployの直前に次をrepo外の一時ファイルへ保存する。

```sh
firebase functions:list --project hayaosiapp --json
firebase database:get /.settings/rules --project hayaosiapp --instance hayaosiapp-default-rtdb --output /tmp/hayaosiapp-predeploy-rules.json
```

必須確認:

1. Preflight時と比べ、第三者によるProduction Functions / Rules変更がない。
2. Production Rules readbackとlocal差分がCompetitive名前空間の追加だけで、既存 `rooms/` 契約を変更しない。
3. deploy予定revision、対象2 Functions、Rules差分を再確認する。
4. `sendRoomInvite` がdeploy対象へ含まれていない。

第三者変更、想定外差分、readback失敗があればdeployせず停止する。readbackファイルはrepoへ追加しない。

## deploy順と片側失敗

1. readback Gateを通す。
2. Client readを先に許可するadditiveなRTDB Rulesをdeployする。
3. Rulesを再readbackし、既存RulesとCompetitive Rulesを確認する。
4. 次の2 Functionsだけをtarget deployする。
5. Functions一覧を再readbackし、region / runtime / 対象名を確認する。
6. 許可済みの4 test usersを使いCloud E2Eを1回実行する。

実行予定command:

```sh
firebase deploy --project hayaosiapp --only database
firebase deploy --project hayaosiapp --only functions:competitiveIntent,functions:competitiveReconcileMatch
```

- Rules deployだけ成功しFunctionsが失敗: Competitive client導線は未公開なのでE2Eを開始せず停止する。必要ならpre-deploy Rulesを復元する。
- Functionsだけが存在する異常状態: driverを実行せず、2 Functionsを削除するかRulesを復元してから再レビューする。
- 片側失敗時に追加deploy、schema変更、別Function deployへ拡大しない。

## rollback

Rollback anchorは、このRunbook、Rules、2 Functionsを含むPhase A-2 commit hashと、deploy直前に保存したProduction Rules readbackである。

```sh
firebase functions:delete competitiveIntent competitiveReconcileMatch --project hayaosiapp --region asia-southeast1
firebase deploy --project hayaosiapp --only database
```

Rules rollback時は、保存済みpre-deploy Rulesをreviewして `database.rules.json` へ復元したうえで上記database deployを行う。削除対象test dataは、driverが報告した正確な `<matchId>` に対する次の2 pathだけとする。

- `competitiveV2/matches/<matchId>`
- `competitiveV2/clocks/<matchId>`

rollback後はFunctions一覧とRulesを再readbackし、Competitive Functionsがないこと、既存Friend Battleの最小正常系に影響がないことを確認する。Production変更のrollbackも、実行前に改めてユーザー許可を得る。
