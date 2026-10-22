# HayaosiApp 開発ステータス
> 運用ルール:
> - 更新日は各見出しに書く(冒頭に最終更新日を置くと必ず本文とズレるため置かない)
> - **このファイルの上限は150行**(超えるとフックが警告する)。超えたら「最新更新」の古い日付の項目から `STATUS_ARCHIVE.md` へ移す。現在フェーズ・作業中宣言・次のタスク・決定事項メモは移動対象外
> - 過去の経緯を調べるときだけ `STATUS_ARCHIVE.md` を読む

現在フェーズ:**v1.0.1(4)を審査へ提出済み(2026年10月16日)。審査結果待ち**
- v1.0.0は2026年10月7日に公開済み。1.0.1は却下対応ではなく通常のアップデート
- 内容:問題切替時の回答世代ずれ修正(トキヤ)、対戦リザルトの表彰台、正誤フィードバックの○×、VS形式の開始画面と和太鼓の効果音、一人練習の問題数・制限時間の設定、一人練習への全画面広告、日本語の対応言語宣言
- 提出物はアプリ本体とスクリーンショット5枚の6件。買い切り課金は1.0.0で承認済みのため再提出なし。リリース方法は自動リリース
- **公開後にAdMobのapp-ads.txt「アップデートを確認」を押す。** マーケティングURL`https://sutahaya-ios.github.io/`がストアへ反映されるのは公開後のため、それまで確認は通らない
- **AdMobのアプリ承認は「要審査」のまま。** 承認されるまで広告配信が制限される
- 実機2台での通信対戦検証はトキヤが実施済み(2026年9月6日・たける報告)。**同時押しでの進行停止・切断・再入室の個別結果はここに未記入。トキヤが追記すること**

---
## リリース計画

**2026年9月6日にv1.0.0を審査へ提出した。** 8/11公開の計画は2026年8月7日に延期を決めていた(当時の日割り計画は `STATUS_ARCHIVE.md` を参照)。

### 申請素材の状況(2026年9月6日・提出時点ですべて完了)

| 項目 | 内容 |
|---|---|
| アプリ名 | 「スタはや」/ サブタイトル「友達と早押し勉強対戦」。J-PlatPatでの商標確認済み(2026年8月22日・たける) |
| App ID | `6800718737`。`Services/AppLinks.swift` の `appStoreURL` に反映済み |
| カテゴリ | プライマリ=教育 / セカンダリ=ゲーム |
| 年齢制限指定 | 4+ |
| 価格・配信国 | 無料 / 日本のみ(2026年8月24日決定。EEA向け同意フォーム(UMP)が未実装のため) |
| プライバシーポリシー・サポートURL | https://sutahaya-ios.github.io/app-privacy/ |
| Appのプライバシー | AdMob由来を含む5データタイプを申告(製品の操作・広告データ・デバイスID・おおよその位置情報・診断)。GoogleのApp store data disclosureと突き合わせ済み |
| スクリーンショット | 6.9インチ(1320x2868)を5枚。Simulatorで撮影し見出しを合成。6.5インチ以下は自動流用される |
| 課金アイテム | 「広告非表示(月額)」300円。初回のためバージョン1.0.0と同時提出 |
| アイコン | 鉛筆型早押しボタン画像(名称変更前に用意したものをそのまま使用) |
| Apple Developer Program | 有効(チーム `<本番Team ID>`) |

---
## 担当分担(2026年8月8日 変更)

| 担当 | 範囲 |
|---|---|
| **たける(Claude含む)** | 大枠UI・対戦体験、英単語の分類・データ管理とボリューム拡充、効果音・ボイス |
| **TOKIYA-YAMAMOTO** | バックエンド全般、追加テスト、既存バグの改善、通信対戦の実機検証 |
---
## 作業中宣言(着手前にここへ記入 → 完了したら消して「最新更新」へ)
| 担当 | 対象ファイル | 内容 | 開始日 |
|---|---|---|---|
| たける(Claude含む) | `Models/WordClassification.swift`・`Models/Question.swift`・`Models/QuizTypes.swift`と、`WordCategory`を参照する28ファイル(Views/Study配下、Views/Battle配下、Services/CategoryProficiencySummary.swift ほか) | **ver2のSPI追加**。`WordCategory`を`StudyCategory`へリネームし、`Genre`にSPIを足す。`Question`へ解説と表データを持たせる。**共有ファイルへ広く触るため、この期間は上記に触らないでほしい**(LINEでも連絡済み) | 2026年9月7日 |
| TOKIYA-YAMAMOTO(Codex) | `database.rules.json`・`HayaosiApp/Services/Competitive/CompetitiveService.swift`・`functions/competitive/handlers.js`・Competitive Phase C/Rules関連テスト | **Production Gateで判明したpresence deleteのsession fence迂回を最小修正**。Client deleteを拒否し、online/offline tombstoneを現行session fenceで検証する。Production deployは行わない | 2026年10月23日 |
---
## 最新更新(2026年8月25日〜10月22日)
- TOKIYA-YAMAMOTO(Codex, 2026年10月22日): **Competitive v2 Phase E Client/UI MVPをLocal実装**。対戦ホームのランク戦入口、Server projection由来のTier/Rating・公開Stats、Queue/NPC補充check、4人20問画面、表示問題に固定した回答送信、Reconnect/Forfeit、結果・昇降格・再戦、Room A/B stale guardを追加。通常Tierのhidden MMRと回答受付中の正解は非公開。Backend Unit 49件、Swift XCTest 10件、Phase D-2 Emulator 2件、Simulator Debug Build/起動が成功。**ユーザー操作E2E・Production deploy/E2Eは別Gate**
- TOKIYA-YAMAMOTO(Codex, 2026年10月22日): **Competitive v2 Phase D-2をLocal / Emulatorまで実装**。正式difficulty 1〜5とTier別range、既存英単語5951問から生成するServer Question Bank、human平均MMR由来の20問重複なし出題、correct answer非公開、正式MMR/tier・loss multiplier・human数weight・Rating Battle昇降格gate、Bronze 5秒/Silver 10秒NPC fill・Gold以上human-onlyを追加。Backend Unit 49件、Swift XCTest 3件、Phase D-2 Emulator 2件(4構成×20問、Security/冪等性含む)、Simulator Debug Buildが成功。基準commit `e28db9c`をmainへpush済み。**Production deploy/Cloud E2Eとbalance simulationは別Gate**
- TOKIYA-YAMAMOTO(Codex, 2026年10月21日): **Competitive v2 Phase CをLocal / Emulatorまで実装**。15秒Reconnect grace、明示Forfeit、Room A/B active-session fencing、Bronze queueの5秒後NPC補充、Server-owned NPC回答、1〜4 humanの全構成で20問完走、core-only settlement/session・presence解放を追加。Core Unit 11件、Matchmaking Unit 11件、Swift XCTest 3件、Core Emulator 4件、Phase C Emulator 2件、Simulator Debug Buildが成功。RTDB Emulatorの既知内部例外でCore初回のみ失敗したが同条件再実行は成功。基準commit `9de7e6f`をmainへpush済み。**Production deployは未実施。Phase A-2 Performance Release BlockerはCloud再測定まで維持**
- TOKIYA-YAMAMOTO(Codex, 2026年10月20日): **Competitive v2 Phase B.5をLocal / Emulatorまで実装**。4人同時回答がmatch root全体のtransactionで競合していたため、既存answer inboxのPlayer/Question別create-only transactionへ分離し、all-answered時だけ1回root reconcileする構造へ変更。Server timestamp、1人1回答、duplicate/session fencing、deadline、20/10/5/1・誤答-10・無回答0、Realtime projection、settlement scoreを維持。Core Unit 7件、Matchmaking Unit 8件、Core Emulator 4件・20問80回答が成功。Local T1→T2はBefore p50 57.205ms / p95 105.834msからAfter p50 19.402ms / p95 39.003ms、answer/intent claim retry 0件。Rules・Swift・本番環境は未変更。**Production Performance Release BlockerはCloud同条件再測定まで維持**
- Codex(2026年10月13日): **対戦の中央フィードバックを緑の○・赤の×へ変更**。`BattleView.swift`で自分の正解確定時にも表示し、100pt・1.2秒で消去。既存レイアウト・選択肢・再回答不可の案内は維持。Simulator向けビルドと採点関連15テスト成功。**実画面での表示・タイミングは未検証**(Computer Useの操作権限なし)。
- Codex(2026年10月13日): **対戦結果へA案の表彰台と下端固定ボタンを実装、解説画面をカード形式へ変更**。同順位・ボタン表示条件・広告と再戦処理を維持。Simulator向けビルドと同順位の既存1テスト成功。本番Viewを一時撮影アプリに組み込み、固定データで8人結果・表付き長文解説のダーク表示を確認。**本番フローでの再戦・復習・解説シート開閉とライト表示は未検証**(Computer Useの操作権限なし)。A案採用を`docs/DECISIONS.md`へ記録し、指定どおりモック依頼書を削除。
- Codex(2026年10月13日): **一人練習に案1の常設設定カードを実装**。問題数と1問の制限時間をメニューで選択し、ランダム練習に反映。学習専用のAppStorageで問題数を共通保存、時間は教材別に保存し、対戦設定とは分離。復習は従来の一覧へ遷移する。Simulator向けビルド・QuizSessionの10テスト成功。**設定操作・再起動後の保持・練習への遷移と実表示は未検証**(Computer Useの操作権限なし)。
- Codex(2026年10月11日): カテゴリ学習画面のリングを選択レベルの**習得率**(全問題のうち一度以上正解した問題の割合)へ変更。未挑戦も「0%・習得率」を表示。ビルドと習得率の関連3テスト成功。**画面表示は未検証**(Computer Useの操作権限なし)。
- Codex(2026年10月11日): **ユーザー承認済みモックに合わせてカテゴリ学習画面を簡素化**。`CategoryHeatmapView.swift`を青い正答率リング・レベル選択・復習/ランダム練習の2ボタンへ変更。ランダム練習は選択レベルを対象とし、復習は既存のカテゴリ別一覧へ遷移する。Simulator向けビルドと関連18テスト成功。**画面表示・レベル選択から練習/復習への操作は未検証**(Computer Useの操作権限なし)。
- Claude(たける側): **教材追加シートをカード全体のタップで追加・解除できる形へ変更**。下部の「＋ 追加」ボタンをやめ、カードを押すたびに追加と解除が切り替わる。追加済みは右上のチェックと教材色の枠線で示す。ボタンが無くなる分カードを低くし、高さを揃えるため近日カード下部の「乞うご期待」も外した(「近日」バッジは残る)。Simulator向けビルド成功、iPhone 17 Proのダークで追加・解除の両方と全9枚が1画面に収まることを確認。**ライトモードは未検証**
- Claude(たける側): **スプラッシュ画面をアプリアイコンの鉛筆だけの表示へ刷新**。青丸+稲妻・アプリ名・説明文をやめ、クリーム地の中央にアイコンの鉛筆(`AppIcon.png`から地色を抜いて切り出した`SplashPencil`)だけを置いた。背景は`SplashBackground`でライト・ダーク共通に固定。動きは従来と同じフェードインのみ。Simulator向けビルド成功、iPhone 17 Proのダークで鉛筆が中央に出ることを確認。**表示が短く、完全に表示された状態は未検証**(フェードイン途中の1枚のみ)。**システムの起動画面は未変更**のためダークでは黒→クリームと切り替わる。直すには`project.yml`の変更が必要
- TOKIYA-YAMAMOTO(Codex): **Competitive v2 Phase B Identity / MatchmakingをLocal / Emulatorまで実装・検証**。Firebase Auth UIDをcanonical identityとし、Anonymous Authを維持したままserver-owned profile、sessionId/sessionEpoch fencing、本人限定public projection、retry-safeな`joinQueue`/`cancelQueue`、4人atomic claim、pending manifestからの再開、Phase A-2 match生成・参加・終了時session解放まで追加。Unit 14件、Rules/Auth/Functions/RTDB Emulator 5件、Simulator Build、関連Swift XCTest 3件が成功し、4→1、8→2、12→3(Unit)、concurrent claim、duplicate/retry、stale epoch、Security Gate B、Phase A-2接続を確認。現在Java Runtimeは利用不可だが、Phase B実装後のEmulator証拠は現差分でも有効。既存`rooms`とPhase B前のCompetitive RulesはHEADから不変で、回帰証拠を再利用。Production deploy/data変更なし。Phase A-2のanswer transaction Performance Release Blockerは維持
- Claude(たける側): **広告非表示を自動更新サブスクから買い切り(非消耗型)へ変更**(ガイドライン3.1.2の却下対応)。`productID`を`com.n.HayaosiApp.removeads`へ差し替え、`Config/Subscription.storekit`の`subscriptionGroups`を空にして非消耗型商品へ置き換えた。権利判定は`Transaction.currentEntitlements`のまま、サブスク専用の`isUpgraded`条件を外し、`isSubscribed`を`hasRemovedAds`へ改名(`AdsService`・`SubscriptionView`が追従)。購入画面から自動更新の説明とサブスク文言を消し、価格の「／月」表記を外した。**利用規約・プライバシーポリシーの導線と「購入を復元」は残している**(非消耗型でも復元は必須)。iPhone 17 Simulatorで全123テスト成功(StoreKit設定のテストを買い切り用に書き換え、自動更新サブスクを含まないことの検証を1件追加)。**購入フロー自体のSimulator確認は未検証**。StoreKit設定ファイルはXcodeのRun経由でないと効かないため、マイページ→プレミアムで価格表示・購入・復元・広告消失を人間が確認する必要がある。価格は500円(たけるが決定)。`Config/Subscription.storekit`へ反映済みで、App Store Connect側にも同額を設定する
- Claude(たける側): **v1.0.0をApp Storeへ提出**(2026年9月6日)。対戦ホームの2つのモードボタンから説明文を、学習ホームから見出し「学習メニュー」を削除し、学習タブのスクロールをマイページと同じinlineタイトル+ツールバーの形へ揃えた(41a0772・104ec4b)。App Store Connectの入力一式とスクリーンショット5枚を用意し、Archive作成からアップロードまで実施。**「オンライン対戦」ボタンが押しても「準備中」画面しか出さずガイドライン2.1(App Completeness)に触れる懸念があったため、たけるが「近日」バッジ付きの押せない表示へ変更(0d11a35)**
- Codex統合担当: **SwiftData旧ストアの上書き移行とRelease Smoke Testを完了**。`BattleRecord`追加直前の旧版を専用Simulatorへ入れて`Question`・`AnswerRecord`・`ReviewItem`・`DailyStudyTime`を保存し、アプリ領域を削除せず現行版へ上書きした。現行版は正常起動し、旧データ4種類を値まで保持したまま、新しい`BattleRecord`の保存・再取得にも成功。現行HEADのRelease版はSimulator・物理iPhone向けbuild、両端末へのinstall・launch、開発用署名でのArchiveに成功し、ユーザーが両端末で起動・Auth・主要画面・Firebase接続・フレンドバトル最低限正常系を確認済み。本番Bundle ID `com.n.HayaosiApp`・チーム`<本番Team ID>`のArchiveは、このMacのXcodeに同チームのAccountが無いため署名前に停止したが、リリース作業はユーザーの担当外なので今回の完了条件から除外。アプリコード変更なし
- Codex統合担当: **リリース前Security監査と最小修正を実施**。改造guestが初期score・joinedAt・回答時刻を偽装できるRTDB契約と、同一IDが複数slotを先取りできる問題をRulesで拒否し、nickname・回答payloadにも既存上限を追加。アプリはnicknameをFirestore/RTDB境界で正規化し、Firebase詳細エラーをDebugビルドだけへ集約した。Rules Emulator 39件、Simulator向けDebug/Release Build、入力正規化テスト3件、`git diff --check`成功。追跡ファイルに秘密鍵・実API keyは検出なし。変更後RTDB Rulesは本番`hayaosiapp`へdeploy済みで、REST readbackとローカルのJSONが完全一致。**本番Rules適用後、物理iPhone＋Simulatorでルーム作成→NPC追加→guest参加→双方3問以上回答→得点・順位反映→退出までE2E成功。Functions依存には利用経路外を含むmoderate advisory 7件が残る**
- Codex統合担当: **既存NPCをフレンドルームの空き枠へ追加できる統合を実装**。オンラインhostのメンバー末尾だけに「NPC追加」枠を出し、既存`NPCManagementView`・`CPUProfile`・`CPUAnswerStrategy`をローカル/オンラインで共用。NPCも既存`players`と0〜7固定`playerSlots`へ保存し、host端末だけが回答を予定・送信するため全参加者で表示・得点・正誤を共有する。アプリ側とRTDB Rulesの両方でhost限定・待機中限定・人間＋NPC最大8人を保証。Simulator Build、既存CPU回帰＋採点34件、Rules Emulator 38件、`git diff --check`成功。RTDB Rulesは本番`hayaosiapp`へdeploy済み。**2026年9月6日、本番Rules適用後に物理iPhone＋SimulatorでNPC追加・guest参加・対戦同期・退出E2Eを確認済み**
- Codex統合担当: **ルーム入室前の対戦詳細設定画面を廃止**。フレンド対戦の「ルーム作成」は保存済み設定(未保存・不正値は既存既定値)でオンラインルームを直接作成し、「NPCと対戦」も同じ設定でNPC未参加のローカルロビーへ直接入る。NPCはロビー内で追加でき、ルーム内の設定変更・host権限・同期処理は維持。`RoomCreateView`からルーム作成責務を外して設定編集専用にした。Simulator向けBuildと関連テスト24件成功、`git diff --check`成功。**実在Firebaseでの直接ルーム作成と、現行buildでの画面遷移E2Eは未確認**
- Codex統合担当: **対戦詳細設定の戻り先固定とオンラインguestへの設定同期を修正**。ロビーの「変更」が退出処理を呼んでHomeへ戻っていた経路を、同じ`BattleSession`上へ設定画面をpushして完了時にpopする構造へ変更。オンラインhostは待機中の`rooms/{code}/settings`だけを更新し、Picker変更を順序保証付きで即時writeするためguestの既存room listenerへ共有される。CPUルームも同じsession・参加者・NPCを維持して設定だけ更新する。友達側のNPC管理と最新4分割設定UIを保持して競合解消し、`xcodegen generate`、関連Simulatorテスト32件成功。遷移とルーム維持は物理iPhone＋Simulatorでユーザー確認済み。**最新4分割UIへ統合後の即時同期E2Eは未再確認**
- Claude(たける側): **対戦設定を4分割セレクタへ刷新し、用語をジャンル/レベルへ統一**(たけるの指示で今回もClaudeが実装まで担当)。`Form`のメニュー4つで選択肢が見えなかったため、ロビーの設定カードと同じ並び・同じSF Symbolsの4分割(ジャンル/レベル/問題数/制限時間)をタップで切り替え、選んだ項目の選択肢だけをチップで出す`BattleSettingsSelector`を新設した。出題の種類は`Genre`を「モード」としてカード外のセグメントに置き、1種類でも将来の追加に備える。収録数のフッター2行は削除し、「この設定で出せる問題◯語」の1行に置き換えて、設定した問題数を下回るときだけ数字を警告色にする。表示文字列だけ「カテゴリ→ジャンル」「難易度→レベル」に統一し(`WordClassificationPicker`経由でCPU対戦設定にも反映、学習タブの1文言も追従)、型名`Genre`/`WordCategory`とデータは未変更
  - 検証:`xcodegen generate`とSimulator向けビルド成功。iPhone 17 Proのダークで、4項目のタップ切り替え、★3選択でカードの値と語数が300語→452語へ追従することを確認。**ライトモードと、ルーム作成側の実際のルーム発行(Firebase接続が必要)は未検証**
- Claude(たける側): **対戦ホームを「プロフィール＋習得率」構成へ再編**(たけるの指示で今回もClaudeが実装まで担当)。「スタはや」ロゴとヒーロー`BattleHomeHero`を廃止し、ツールバー左へ`AvatarCircle`と名前を置いて遊び方ボタンと同じ高さに揃えた。アイコンは既存`ProfileDetailView`(対戦実績)を開き、名前はその場で編集してキーボードの確定キーで保存する(空欄は既定の「ゲスト」へ戻し12文字で打ち止め、確定時に`AuthService.updateProfileIfSignedIn`で同期)。上部は選択中のカテゴリ・難易度の習得率カードにし、「変更」は既存`RoomCreateView(mode: .editPreferences)`へ繋いだ。集計は学習記録と同じ`CategoryProficiencySummary`を使い、難易度の絞り込みと表示文言を集計側へ集約。**学習記録はカテゴリ全体、対戦ホームは★別のため数字は一致しない**
  - 検証:Simulator向けビルド成功。iPhone 17 Proのダークで、名前編集→確定キー保存(UserDefaults反映)、アイコンからの実績表示、「変更」でTOEIC単語★1へ切り替えるとカードが1語/400語へ追従することを確認。**ライトモードと実招待でのoverlay不動は未検証**。ダークでの見え方以外は未確認
- Codex統合担当: **TASK 3「ホスト以外も招待できる」を完了**。ロビーの招待UIと送信処理をhostに限定し、callable Function `sendRoomInvite`がRTDBの`hostID`・`roomInstanceID`・waiting状態とFirestoreの相互フレンド関係を検証してcanonical inviteを作成する。Firestore Rulesはクライアントからの招待create/reinviteを拒否し、recipientのclaim/finalize/rollbackは維持。Functions Emulator 6件、Rules Emulator 37件、Simulator Swiftテスト109件、物理iPhone向けbuildに成功。本番`hayaosiapp`でFunctionが東京リージョン・Node.js 22のACTIVE、Firestore Rules公開済み、古いコンテナは1日後に自動削除。物理iPhone＋Simulatorでhostの招待送信→guestの受信・参加→2人ロビーと、guestに招待欄が表示されないことをE2E確認済み。改造guestのbackend拒否はFunctions Emulatorで確認済み
- Claude(たける側): **対戦ホームの復習帯を削除し、広告バナー設置と主操作の下端固定へ再構成**(たけるの指示で今回もClaudeが実装まで担当)。「最近の復習が対戦に反映されます」は実装と食い違っていたため撤去した(**復習→対戦の反映は元から無い**。対戦→復習は`ResultRecorder`経由で従来どおり動く)。未使用になった`BattleReviewBand`も削除。`BattleHubView`はScrollViewをやめてロゴ→ヒーロー→`Spacer`のVStackにし、2つの対戦ボタンは`BattleLobbyView`と同じ`safeAreaInset(edge:.bottom)`で下端へ固定、その下に`MyPageView`と同形の`AdBannerView`を置いた。ボタンとバナーの間隔は20pt。`AdBannerView`は購読中に高さ0になるためバナー用の余白は確保していない。招待overlay・ヒーロー・ボタンの見た目・タブ構成は未変更
  - 検証:`xcodegen generate`とSimulator向けビルド成功。iPhone 17 Proのダークで、復習帯の消失・テスト広告バナーの表示・ボタンとバナーの20pt間隔・ヒーローが中央付近に残ることを確認。**ライトモードと、実招待でのoverlay不動は未検証**。ダークでヒーローの雲が黒い塊に見える既知の見え方は今回未対応
- Codex(たける側): **対戦ホームを「蒼天」UIへ刷新し、独立したひとり対戦をフレンド対戦へ統合**。セマンティックカラーの空・雲とSF Symbolsの盾/稲妻/王冠/交差剣による非操作ヒーロー、同格のオンライン/フレンドCTA、復習帯へ整理。招待は通常レイアウト外の通知型overlayで最新1件を表示し、10秒または上スワイプで端末表示だけ閉じ、正式導線のフレンド対戦>招待には残す。フレンド対戦は既存`OnlineModeMenuView`へルーム作成/コード参加/招待/NPC対戦を集約。ローカル`CPUBattleSession`は選択した既存`CPUProfile`で初期化し、ホストが待機中にNPCを追加・削除でき、合計8人を超えない。既存`cpuCount:` initと共通ロビー/進行/採点は維持し、Firebase/オンラインルームは未変更。`CPUBattleSessionTests`全件とSimulator向けbuild成功、iPhone 17 Proでホームをライト/ダーク確認。**全国マッチング本体は既存未実装のため準備中画面まで。実在招待の10秒/スワイプ/一覧残存とNPC管理の画面操作は実機未検証**
- Codex統合担当: **ルーム作成がFirebase障害で止まる経路を修正**。本番RTDB Rulesが要求する`roomInstanceID`・`playerSlots`・hostの`slot`を含む新schemaと、main上の旧クライアントpayloadに版ずれがあったため、関連する通信対戦実装・Rules・テストを同時にGitへ反映する。また、RTDBルーム作成に不要なFirestoreプロフィール・`friendCodes`索引の準備をFirebase Authenticationから分離し、プロフィール側のpermission deniedがあっても認証済みuidでルームを作成できるようにした。Rules Emulator 43件成功、未完成の未追跡UIモックをビルド対象から除外したSimulator向けbuild成功。修正版をiPhone 17 Simulatorへinstallし、一時XCUITestで**実在Firebaseの「ルーム作成」タップからルームID・host 1/8表示までE2E成功**。同時間帯にpermission denied等のFirebaseエラーは検出されなかった。**物理iPhone回帰と本番deployは今回未実施**
- Codex(たける側): **実装済みスプラッシュをiPhone 15 Pro Simulator(iOS 17.4)で確認**。xcodegen実行後のSimulator向けビルドは成功。データ投入済みの再起動では、稲妻マーク・「スタはや」・「勉強系早押し対戦」が表示され、録画のフレーム確認でフェード開始まで約0.7〜0.8秒あり、その後タブ画面へクロスフェードすることを確認。ライト/ダークとも背景・文字・マークの色は問題なし。スクリーンショットは`docs/screenshots/splash-light.png`と`splash-dark.png`の2枚。**初回のデータ投入中は背景だけが表示され、ロゴと文字は描画されないままタブ画面へ切り替わるため、初回起動の表示要件は未達**。既知のメインスレッド占有中に`SplashView`の出現アニメーションが進まず、初期opacity 0のフレームが保持される見え方。依頼どおりソース修正・テスト実行は行っていない
- Codex(たける側): **高校英単語の統合・ターゲット1900追加をJSONへ反映し、データ依存で古くなった分類テスト2か所を修正**。変換ツールの`--write`実行で差分は`high_school.json`のみ、2194語から2998語へ更新。中学1510語・TOEIC1443語は変更なし。読み飛ばしはターゲット1400=638語・1900=1063語・金のフレーズ=557語、高校内訳は★1:699 / ★2:700 / ★3:762 / ★4:418 / ★5:419。`QuestionSeeder.dataVersion`は11。高校ID接頭辞テストを`hs1_`/`hs2_`/`hs3_`対応にし、旧ID移行テストは`loadEntries()`から高校`benefit`のIDを取得して比較するよう変更。指定の`WordClassificationTests`全11件成功
- Codex(たける側): **TOEIC金のフレーズで、同一カテゴリの先行語と同じシート内の既出語を検証・ID採番前に読み飛ばすよう変換ツールを変更し、生成JSONへ反映**。source単位のフラグは金だけ有効にし、比較は小文字化・前後空白除去したwordのみで行う。実行時は`--write`の有無にかかわらず読み飛ばした件数と語一覧を表示する。銀の許容難易度へ3を追加。`--write`で`junior_high.json`と`toeic.json`へ反映し、`QuestionSeeder.dataVersion`を10へ更新。再実行で3カテゴリとも変更なし、入力エラー0件、金から557語を読み飛ばし、中学1510語・高校183語・TOEIC1443語、TOEIC内訳★1:400 / ★2:300 / ★3:301 / ★4:157 / ★5:285を確認。全88テスト中86件成功。収録データのカテゴリ内ID・単語重複なしを含む今回関連テストは成功したが、旧ID移行テスト1件の2検証は、旧固定値`benefit = jh_0001`が生成後に中学`jh_1367`・TOEIC`tc1_0463`の2カテゴリへ存在するため失敗
- Claude(たける側): **プロフィールカードのタップで詳細画面を開き、戦績を区分別に表示**(たけるの指示で今回もClaudeが実装まで担当)。**新規SwiftDataモデル `BattleRecord`(順位・参加人数・得点・区分)を追加**し、`HayaosiAppApp` のスキーマへ登録した。集計は `Services/BattleStatsSummary.swift`(`ProfileBattleStats` を `FriendProfileCard` から移設)。保存は `BattleSession` の `saveBattleRecord(matchType:context:)` を新設し、CPU・オンライン双方の `saveResultsIfNeeded` の重複ガード内から呼ぶ。**たけるの判断でCPU対戦もフレンド戦へ合算する**(区分を分けたくなったら `BattleMatchType` に1ケース足すだけで済む)。**ランダムマッチは機能自体が未実装なので、区分の枠と集計だけ用意し書き込み経路は作っていない**。UIは3指標を `Views/Components/BattleStatsRow.swift` へ切り出し、`ProfileDetailView` で区分別カード+学習記録の入口を出す。カードからは学習記録の行を外し、ヘッダと戦績を `NavigationLink` にした。**フレンドコード行をリンクの外に残したのは、中のコピー・シェアボタンとタップが競合するため**。`FriendProfileCard` の未使用だった `Footer` ジェネリクスと専用initは削除
  - 検証:xcodegen実行、Simulator向けビルド成功。`BattleStatsSummaryTests` 3件成功(他クラスは未実行)。iPhone 17 Simulatorでライト/ダーク両方を確認し、CPU対戦(中学英単語★1・4問)を通してフレンド戦が0→1件、3位のため1位回数0・1位率0.0%へ更新されること、ランダムマッチが0件表示のままであることを確認。**オンライン対戦での記録は実機2台が必要なため未検証**
- Codex(たける側): **英単語の品詞へ助動詞を追加**。`PartOfSpeech.auxiliary`を代名詞・接続詞・前置詞と同じ少数機能語グループへ加え、変換ツールの許容品詞・グループ表示、作業用Excelの使い方、コーディング規約と決定事項を8品詞へ追従。既存データの品詞と問題データは未変更。`xcodegen generate`、`WordClassificationTests`全11件、Simulator向けビルドは成功。`python3 word_bank/word_bank_to_json.py`は実行したが、手元の作業用Excelに既存の未入力行が残っているため6284件の入力エラーで未達。全テストとSimulator画面確認は指示どおり未実施
- TOKIYA-YAMAMOTO(Codex): **招待accept直後のRTDB一時offlineエラーを修正**。`joinRoom()`は`.info/connected`を最大3秒だけ待ってからroomを取得し、Firebase Coreが返す「接続前・active listenerなし・cacheなし」の一時offlineだけ250ms後に1回再試行する。招待claim開始前からjoin完了までを6秒に制限して10秒claim leaseへ余白を残し、期限超過・join失敗・finalize失敗では参加状態をcleanupして可能なら同じclaimをrollbackする。permission denied・room不存在・roomInstance不一致はoffline retryしない。固定slot・同一UIDの冪等join・Rules schemaは維持。関連Swiftテスト11件とアプリコンパイル成功。**一時切断を再現する実機accept回帰は未実施**
- TOKIYA-YAMAMOTO(Codex): **TASK 2 招待ライフサイクルの実装を完了**。ルーム作成ごとの`roomInstanceID`、recipient配下のcanonical invite、generation付き10秒再招待、30秒logical expiry、`pending→accepting→accepted` claim transaction、claim ID付き期限内rollback、document ID+generation単位の「あとで」を追加。RTDB参加は0〜7の固定枠とplayerをatomicにclaim/releaseし、同一UIDの再接続ではslot・score・joinedAtを書き換えない。client deleteを廃止し、acceptedとRTDB退出を分離。03 Securityで固定8枠とrollback proofのRules契約も反映済み。対象Swiftテスト8件・アプリコンパイル・Rules Emulator 43件（skip 0）に成功。**本番FirebaseへのRules deployと実機での再招待・競合回帰は未実施**
- TOKIYA-YAMAMOTO(Codex): **対戦ホームを添付デザインに沿った直接操作型UIへ刷新**。前回設定をローカル保存し、初回は既定値を使って設定画面を挟まずルーム作成、4桁コード参加、CPU対戦、招待参加ができる。設定は「変更」から編集可能。作成・参加中の二重操作を防ぎ、失敗時はロビーへ遷移しない。招待の「あとで」はFirebase上の招待を削除せず端末上だけで閉じ、参加成功後のみ既存招待を削除する。招待データ構造を変更していないため、カードの人数は招待者1名を既知人数として表示する。待機ロビー・Firebase・Rules・対戦ロジック・下部タブは変更なし。XcodeGen生成、関連テスト4件、Simulator向けbuildに成功し、iPhone 17 Pro Simulatorで対戦ホームの最終表示を確認。**実在Firebaseでのルーム作成・コード参加・招待参加と各失敗時の画面操作は未検証**
- Claude(たける側): **制限時間バーを滑らかなミント表示にし、単語練習の「次の問題へ」を廃止**(たけるの指示で今回はClaudeが実装まで担当)。`Views/Components/TimerBarStyle.swift`へバーの色・更新間隔・警告色の閾値を集約し、対戦・練習の両方から参照する。バーの段差は**更新頻度そのものが10fpsだったこと**が原因で、`.linear`での補間では消えなかった。対戦は`TimelineView(.periodic(by: 0.1))`を`.animation`へ変えて画面のリフレッシュレートで引き直し、練習は`tick`の間隔を0.1秒から1/60秒へ変えて表示と判定を同じ値で動かす。補間指定と`.id`は不要になったため削除した。対戦の`tickInterval`は文字送り専用として0.1秒のまま残している。**警告色の閾値を`min(5秒, 制限時間×0.3)`へ変更**:既定の制限時間が5秒のため固定5秒では常時赤になり、ミントがほとんど見えなかった。これに伴い参照が消えた`BattleAnimation.urgentThreshold`を削除。練習は正誤表示のあと自動で次へ進む(正解0.7秒・不正解1.6秒)よう`.task(id:)`で待ち、「次の問題へ/結果を見る」ボタンを廃止。**選択肢の`.disabled`が正答の緑・誤答の赤を消していた不具合も修正**(`.allowsHitTesting`へ変更。`QuizSession.select`側に既存のガードがあるため状態は動かない)。ボタン廃止で参照が消えた`QuizSession.isLastQuestion`も削除した
  - 検証:xcodegen実行、Simulator向けビルド成功。iPhone 17 Proでライト/ダーク両方を確認。練習は不正解時に正答が緑・選んだ誤答が赤で表示され、ボタンを押さずに次問へ進むこと、時間切れでも正答が緑になることを確認。ダークでCPU対戦(中学英単語★1・4問)をロビーからリザルトまで通し、バーがミントで段差なく減ることを確認。**滑らかさはSimulatorの録画をフレーム単位で計測して確認**:練習は24フレーム中23回、対戦は19回バー幅が変化し(3〜9pxずつ)、毎フレーム更新されている。`QuizSessionTests`10件成功、他のテストクラスは未実行
- Codex(たける側): **英単語4択の誤答候補を意味要素単位で重複除外**。「、」「・」をカッコ外だけで分割し、全角・半角スペースと空要素を除いた集合に共通要素があれば候補から外す。カッコ内の区切りと活用差は維持し、候補が3件未満でも集まった分だけ使う。既存端末へ再投入するため`QuestionSeeder.dataVersion`を9へ更新。指定の`QuestionSeederDistractorTests` 5件成功、Simulator向けビルド成功。全テストとSimulator画面確認は指示どおり未実施
- Codex(たける側): **学習タブをピン留め式「マイボード」へ刷新**。初期状態は空で、`pinnedStudyCategories`へ追加順のカテゴリrawValue配列を保存する。2列カードにアイコン・説明・習得率を表示し、編集時は遷移を止めて左上の赤いマイナスから解除できる。追加シートは実装済み3教材を先に並べ、追加後も閉じずに「追加済み」へ切替。未実装教材は`UpcomingMaterial`へ分離し、英検・数学・漢検・SPIを淡色の非操作カードとして表示する。Viewはボード・追加シート・各カードへ分割。xcodegen実行、Simulator向けビルド成功。iPhone 17 Simulatorで学習タブ→教材を追加→中学英単語を追加→閉じる→マイボード表示を確認し、近日カードの「乞うご期待」がButtonではないこともアクセシビリティ要素で確認。ユニットテストは指示どおり未実行
- TOKIYA-YAMAMOTO(Codex): **待機中のルーム画面を添付デザインへ刷新し、通常の全画面遷移へ調整**。ルームIDと共有、参加人数と横並びメンバー、ホスト表示、4項目の対戦設定カード、ホストの設定変更、画面下へ固定した対戦開始ボタンを白背景・青アクセント・角丸カードで再構成。オンラインメニューをシートから通常のNavigation遷移へ変更し、左上の戻るで退出して前画面へ戻る経路を維持。ルームIDをsemiboldへ少し細くし、主要セクションの縦余白だけを広げた。ルームの最大8人、フレンド招待、ホスト/ゲスト権限、Firebase・同期・対戦開始処理は変更なし。プレイヤー画像はルームデータに無いためイニシャル表示。Simulator向けbuild成功。iPhone 17 Pro Simulatorで全画面表示、戻るボタン、ルームID、余白を確認。**共有・設定変更・対戦開始のタップ操作は未検証**
- Codex(たける側): **問題0件のカテゴリ・難易度を選んだ際の案内を追加**。共通カードにカテゴリ名・星と「この範囲の問題は順次追加しています」「他の難易度を選んでください」を表示し、CPU対戦・ルーム作成では開始ボタン自体を出さず、ルーム作成処理にも0件ガードを追加。学習ヒートマップでは0件セルをタップ不可のまま、該当難易度をまとめてグリッド下へ表示する。収録データテストは各難易度の存在を必須とせず、カテゴリごとの1語以上・ID/単語重複なしだけを維持。Simulator向けビルド成功、全75テスト成功。iPhone 17 SimulatorでCPU対戦・ルーム作成のTOEIC ★2に案内が表示され、開始ボタンが存在しないことを確認
- TOKIYA-YAMAMOTO(Codex): **Codex開発フローをFAST/NORMAL/STRICTの3段階へ整理**。`docs/MODULE_MAP.md`を最小探索の起点として追加し、`scripts/preflight.sh`でorigin/mainとの差・未commit変更・作業中宣言・競合可能性、`scripts/verify.sh`でリスク別のbuild・関連テスト・Rulesテスト、`scripts/finish-task.sh`で差分確認と人間向けGitコマンド表示を自動化。スクリプトはcommit・pushを実行しない。`CLAUDE.md`と`docs/CODING.md`を最小探索・変更リスクに応じた検証へ更新。Bash構文、help、fetchを省略したpreflight、FAST/NORMAL/STRICTのdry-runに成功。GitHub ActionsはPrivateリポジトリのmacOS実行時間を消費し得るため未追加
- TOKIYA-YAMAMOTO(Codex): **実機2台PvPで2問目以降の回答権が相手の回答まで復帰しない不具合、端末間の進行差、同時押し反復時の誤ったホスト退出判定を修正**。Firebaseサーバーの共有開始時刻を端末のローカル時計で比較していたため、時計差が回答可否・文字送り・残り時間・ホストタイマーの差として現れていた。RTDBの`.info/serverTimeOffset`を観測し、開始合図を含む全時間判定をFirebase補正時刻に統一。回答権は短周期に再評価し、問題切替時に送信中・送信エラー・前問の誤答演出を解除。さらに、一時的な接続断でも`onDisconnect`が即座に`closed`を書き込むため、生存中のホストは再接続時に監視を再登録して直前状態を復元し、参加者は3秒後も`closed`のままの場合だけ退出として扱うようにした。明示退出は復元対象外。`failed`・`answers`の問題番号による前問除外と問題送り時の削除、得点・回答順、Firebase構造・ルールは維持。PvPリザルトでは「間違えた問題を復習」を非表示にしたが、学習履歴・復習リストへの保存は維持。Simulator向けbuildと`HostDisconnectPolicyTests`・`BattleStartTimingTests`・`BattleScoringTests`・`CPUBattleSessionTests`の計34件に成功。**修正版の実機2台で1〜3問目を双方が回答できること、表示進行が揃うこと、同時押し反復時にルームが維持されること、実際のホスト切断時だけルームが終了すること、PvP終了後に一人学習の復習リストへ誤答が残ることは未検証**
---

## 次のタスク(優先順)

### 担当:たける側(Claude含む)— コンテンツ・大枠UI・対戦体験

1. **対戦画面UIの強化**:対戦中はタブバーを隠し、対戦画面の演出・情報配置を改善する。効果音・ボイスも追加・差し替えする
2. **英単語のボリューム拡充(2026年8月26日 方針更新)**:`word_bank/`配下の担当xlsxへ、たける・トキヤが直接入力し、変換ツールで各JSONへ反映する。現データはテスト用なので順次刷新し、各カテゴリのdifficulty 1〜5を充実させる
   - **高校英単語はターゲット1200/1400/1900を基準に難易度を設計**。難易度1・2=ターゲット1200、3=ターゲット1400、4・5=ターゲット1900。3シートを`word_bank_high_school.xlsx`へまとめて管理する(git管理外、直接送付)
   - **著作権に注意**:ターゲットシリーズの収録語彙・配列は旺文社の編集著作物。収録語を丸ごと転記する行為はその複製にあたるリスクがある(商用アプリのため実務上のリスクとして認識しておく)
   - 動詞・名詞など複数の品詞を持つ単語は、posは出題用の1つに絞り、meaning欄へ`(動)〜/(名)〜`の形で両方の意味を書く(2エントリに分割しない。分割するとposのグループ化が崩れ、出題の誤答選択肢が壊れるため)
3. **単語詳細画面(保留)**:単語帳のように1単語を詳しく見る画面で、複数品詞の意味を並べて説明できるようにしたい(たけるの発案、2026年8月25日)。今のmeaningは1文字列のみで品詞別に分かれていないため、着手する場合はデータ構造(Excel列・JSONスキーマ)とSwiftUI画面の両方を設計し直す必要がある。優先度は英単語のボリューム拡充より低い
4. **対戦結果の保存 →「直近の対戦」表示**:対戦タブに順位・正答数を出す
5. **習熟度の可視化(v1.1)**:`visibleCount`を `AnswerRecord` へ保存し、学習タブに苦手順の一覧を出す
6. **英単語JSON更新の自動検知(保留)**:開発第一段階は `QuestionSeeder.dataVersion` を手動で増やす現方式を継続する。単語更新が本格化して運用負担になった段階で、JSONのハッシュ比較による自動再投入を検討する

### 担当:TOKIYA-YAMAMOTO — テスト・バグ改善・オンライン本番対応

1. **実機2台検証の結果をSTATUS.mdへ記入**:同時押し・切断・再入室・ホスト切断それぞれの結果を残す(検証自体は2026年9月6日に実施済み)
2. **Firebase本格ルールの実機整合性確認**:Firestore・RTDBとも本番公開済み。実機2台の通信対戦で拒否や進行停止がないか確認し、不整合があればルールとテストを同時に修正する
3. **対戦の追加テストと既存バグの改善**:`CPUBattleSession`を含む進行ロジックの不足ケースを追加し、発見した不具合を修正する
4. 通信対戦検証後の切断・再入室・遅延対策
5. Cloud Functions採点(v1.5準備):採点のサーバー移行。着手前に作業中宣言必須

### 担当:未定

1. ルーム自動削除(使用済みルームがRTDBに残る) / 入力式回答(v1.5)

---

## 決定事項メモ(実装詳細の正はここ)

- **ver2はSPI(言語・非言語)の追加から着手する**。`Genre`(出題の種類)と`StudyCategory`(出題範囲)の2階層を保ち、文字送りの有無は`Genre`から、既定の制限時間は`StudyCategory`から引く(SPI言語=60秒/非言語=120秒)。SPIは5択・シャッフルなし・解説必須で、誤答はJSONに明示する(英単語の自動生成は使えない)。図表は表だけver2で対応。データ形式の正は `docs/SPI_DATA_SCHEMA.md`
- プロジェクト管理はXcodeGen(pbxprojの手編集・コンフリクトを避けるため。2人開発と相性が良い)
- 誤答選択肢はJSONに持たせず、品詞別の誤答グループからシード時に決定的に自動生成する。動詞・名詞・形容詞・副詞は個別、少数の代名詞・接続詞・前置詞・助動詞だけを共通グループにする(データ作成コスト削減)
- 復習リスト:不正解で登録・回数加算、正解すると自動で外れる(「克服したら卒業」方式)
- ニックネームは `@AppStorage("nickname")` が正。サインイン済みなら `users/{uid}` に自動同期
- 問題データ更新時は `QuestionSeeder.dataVersion` を上げると次回起動時に再投入される
- 英単語は**カテゴリと難易度を分離**する。現在のカテゴリは `junior_high` / `high_school` / `toeic` の3つで、各カテゴリに `difficulty: 1...5` がある。大学英語は作らず、TOEFL・英検・IELTSは将来必要になった時に別カテゴリとして追加する
- 正データは `Resources/junior_high.json` / `Resources/high_school.json` / `Resources/toeic.json`。IDは中学=`jh_####`、高校ターゲット1200=`hs1_####`、1400=`hs2_####`、1900=`hs3_####`、TOEIC銀=`tc1_####`、TOEIC金=`tc2_####`。同じカテゴリ内の単語重複は禁止し、カテゴリをまたぐ重複は許可する。`word_bank/`へgit管理外の入力xlsx 3ファイルと`word_bank_to_json.py`をまとめ、同ツールでJSON差分を確認して反映する
- カテゴリ・難易度選択は一人練習・CPU対戦・オンライン対戦に対応。オンラインはRTDBの `settings.wordCategory` / `settings.wordDifficulty` で共有し、旧ルームで両方が無い場合だけ全問題を対象にする
- 対戦中はタブバーを隠し、問題と対戦状況へ集中できる画面にする。試合開始前はCPU・オンライン共通の開始合図を1問目の前だけ表示し、時間は `BattleRules` で管理する
- バックエンド全般(Firebase/Auth/DB/セキュリティルール/Cloud Functions等)は原則としてTOKIYA-YAMAMOTO氏が担当する。たける側の機能で変更が必要な場合は、独断で実装せず担当間で調整する
- 通信対戦の進行権威はホスト端末(v1.0)。Cloud Functions採点はv1.5で検討
- 対戦の出題はホストが端末内の問題からシャッフルしてRTDBに配信(全員同じ選択肢順)
- フレンドは申請を相手が承認した時に双方へ登録する相互承認方式。申請時は相手の `friendRequests` と自分の `sentFriendRequests` を同じバッチで作成し、承認・拒否時も同時に削除する。ルーム招待はhost検証済みCloud Functionが相手の `invites` サブコレクションに書き込む
- 対戦ルール定数は `Services/Battle/BattleRules.swift`、文字送りの間隔は `ProgressiveReveal.characterInterval` が唯一の出典(ドキュメントに数値を書かない)
- **対戦は文字送り型のみ**:問題文を1文字ずつ表示し、4択は全員に最初から見せる。選択肢タップが回答となる。正解者内の回答時刻順で+20/+10/+5/4位以降+1、不正解−10、無回答0
- **得点は回答のたびに、その時点で確定したぶんを反映する**(発表まで待たせない)。毎回ゼロから計算し直して問題開始時の得点へ置き直すので二重加算しない。発表へ進むのは「制限時間切れ」か「回答しうる全員が答え終えた」時。CPU対戦では参加を見送ったCPUを待ち対象に含めない
- 文字送りの表示量は経過時間だけから計算する(`ProgressiveReveal`)。端末間で表示を同期する通信は持たない。全文表示になるのは発表時
- 回答時に「選択肢・時刻・表示文字数(`visibleCount`)」を記録する。学習履歴への保存はタスク6で対応予定
- 共有設定の本番Bundle IDは `com.n.HayaosiApp`。署名(`DEVELOPMENT_TEAM`)と共同開発者用Bundle ID(`APP_BUNDLE_IDENTIFIER`)は `Config/local.xcconfig`(git管理外)で各自が指定し、本番設定を上書きしてcommitしない
- テストはロジックのみ(`Tests/`)。通信層はユニットテスト対象外にし、実機の通し確認で担保する
- 文書の役割:要件定義書=スコープと意図の正 / 本節=実装詳細の正 / `STATUS_ARCHIVE.md`=完了した過去記録
- 広告非表示はStoreKit 2の買い切り1本(非消耗型`com.n.HayaosiApp.removeads`・500円)。自動更新サブスクはガイドライン3.1.2で却下されたため使わない。v1.0では広告非表示だけを提供し、日本語→英語モード・問題パック解放は将来対応
