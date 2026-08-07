/// 内部の識別名を変えず、ユーザー向け表示だけを「CPU」に統一する
enum BattlePlayerDisplayName {
    private static let cpuIdentifierPrefix = "bot-"
    private static let internalCPUName = "ボット"
    private static let publicCPUName = "CPU"

    static func text(for player: RoomState.Player) -> String {
        guard player.id.hasPrefix(cpuIdentifierPrefix) else { return player.nickname }
        return player.nickname.replacingOccurrences(of: internalCPUName, with: publicCPUName)
    }
}
