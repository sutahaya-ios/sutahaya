import AVFoundation

/// 効果音の再生。設定(効果音トグル)でON/OFFでき、マナーモード時は鳴らない(.ambient)
/// 音源は Resources/Sounds/ のWAV(正弦波合成の自前音源。同名ファイルの差し替えで変更可)
@MainActor
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case buzz = "se_buzz"              // 早押し(回答権確定)
        case correct = "se_correct"        // 正解(ピンポン)
        case wrong = "se_wrong"            // 不正解(ブブー)
        case timeUp = "se_timeup"          // 時間切れ
        case questionStart = "se_question" // 出題
        case fanfare = "se_fanfare"        // リザルト
    }

    static let shared = SoundPlayer()
    static let enabledKey = "soundEffectsEnabled"

    private var players: [Effect: AVAudioPlayer] = [:]

    private init() {
        do {
            // 他アプリの音楽と共存し、消音スイッチに従う
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            print("オーディオセッションの設定に失敗: \(error)")
        }
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else {
                print("効果音ファイルが見つかりません: \(effect.rawValue).wav")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[effect] = player
            } catch {
                print("効果音の読み込みに失敗(\(effect.rawValue)): \(error)")
            }
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func play(_ effect: Effect) {
        guard isEnabled, let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }
}
