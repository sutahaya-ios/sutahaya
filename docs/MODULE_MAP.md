# モジュールマップ

変更対象の場所が分からない場合だけ使う検索起点。ユーザーが対象ファイル・View・機能を十分に指定している場合は読まない。詳細設計はコードと `STATUS.md` の該当部分を正とする。

| 機能 | 最初に見る場所 | 主な関連テスト・設定 |
|---|---|---|
| 起動・ルート遷移 | `HayaosiApp/App/`, `HayaosiApp/Views/Root/` | `project.yml` |
| 問題・学習・復習 | `Services/QuizSession.swift`, `Services/ResultRecorder.swift`, `Views/Quiz/`, `Views/Study/`, `Views/Review/` | `Tests/QuizSessionTests.swift`, `Tests/ResultRecorderTests.swift`, `Tests/ReviewListFilterTests.swift` |
| CPU対戦・共通対戦ルール | `Services/Battle/`, `Views/Battle/` | `Tests/CPUBattleSessionTests.swift`, `Tests/BattleScoringTests.swift`, `Tests/BattleStartTimingTests.swift`, `Tests/ProgressiveRevealTests.swift` |
| 通信対戦・ルーム | `Services/Online/OnlineBattleSession*.swift`, `Services/Online/Models/RoomState.swift`, `Views/Battle/` | `database.rules.json`, `FirebaseRulesTests/rules.test.js` |
| 認証・フレンド・招待 | `Services/Online/AuthService.swift`, `Services/Online/FriendService.swift`, `Views/Friend/` | `firestore.rules`, `FirebaseRulesTests/rules.test.js` |
| マイページ・設定 | `Views/MyPage/`, `Views/Settings/` | 直接依存するServiceのテスト |
| SwiftData・データモデル | `HayaosiApp/Models/`, `Services/QuestionSeeder.swift` | 関連する`Tests/`、上書きインストールで移行確認 |
| 英単語データ | `HayaosiApp/Resources/*.json`, `Models/WordEntry.swift`, `Services/QuestionSeeder.swift` | `Tests/WordClassificationTests.swift` |
| 広告・サブスク | `Services/Ads/`, `Services/Subscription/` | `Tests/InterstitialScheduleTests.swift`, `Tests/SubscriptionConfigurationTests.swift`, `project.yml`, `Config/Info.plist` |
| Firebase構成・Rules | `firebase.json`, `firestore.rules`, `database.rules.json`, `FIREBASE_SETUP.md` | `package.json`, `FirebaseRulesTests/` |
| XcodeGen・署名 | `project.yml`, `Config/`, `README.md` | `.gitignore`。`.xcodeproj`は生成物のため調査・手編集しない |

見つからない場合だけ `rg "型名|表示文言|データキー" HayaosiApp Tests` で探索範囲を広げる。
