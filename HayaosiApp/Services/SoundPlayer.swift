import AVFoundation

/// 効果音の再生。設定(効果音トグル)でON/OFFでき、マナーモード時は鳴らない(.ambient)
/// 音源は Resources/Sounds/ のWAV(正弦波合成の自前音源。同名ファイルの差し替えで変更可)
@MainActor
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case button = "se_button"          // 決定・画面遷移
        case correct = "se_correct"        // 正解(ピンポン)
        case wrong = "se_wrong"            // 不正解(ブブー)
        case timeUp = "se_timeup"          // 時間切れ
        case fanfare = "se_fanfare"        // リザルト
        case matchStart = "se_match_start"  // 対戦開始の合図
    }

    static let shared = SoundPlayer()
    static let enabledKey = "soundEffectsEnabled"

    private let engine: SoundPlayerEngine

    private init() {
        engine = SoundPlayerEngine(resourceNames: Effect.allCases.map(\.rawValue))
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func play(_ effect: Effect) {
        guard isEnabled else { return }
        engine.play(resourceName: effect.rawValue)
    }
}

/// `AVAudioPlayer`の生成と操作を同じ直列キューに閉じ込め、UIを音声準備で待たせない。
private final class SoundPlayerEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.n.HayaosiApp.sound-player", qos: .userInitiated)
    private let readinessLock = NSLock()
    private var isReady = false
    private var players: [String: AVAudioPlayer] = [:]

    init(resourceNames: [String]) {
        queue.async { [weak self] in
            self?.prepare(resourceNames: resourceNames)
        }
    }

    func play(resourceName: String) {
        readinessLock.lock()
        let ready = isReady
        readinessLock.unlock()

        // 準備前の操作を待たせたり、遅れて古い効果音を鳴らしたりしない。
        guard ready else { return }

        queue.async { [weak self] in
            guard let player = self?.players[resourceName] else { return }
            player.currentTime = 0
            player.play()
        }
    }

    private func prepare(resourceNames: [String]) {
        do {
            // 他アプリの音楽と共存し、消音スイッチに従う
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            print("オーディオセッションの設定に失敗: \(error)")
        }

        var preparedPlayers: [String: AVAudioPlayer] = [:]
        for resourceName in resourceNames {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "wav") else {
                print("効果音ファイルが見つかりません: \(resourceName).wav")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                preparedPlayers[resourceName] = player
            } catch {
                print("効果音の読み込みに失敗(\(resourceName)): \(error)")
            }
        }

        players = preparedPlayers
        readinessLock.lock()
        isReady = true
        readinessLock.unlock()
    }
}
