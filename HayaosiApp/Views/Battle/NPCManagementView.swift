import SwiftUI

/// ホストが待機中ルームに、既存プロファイルのNPCを追加・削除する共通UI。
struct NPCManagementView: View {
    let session: any NPCManageableBattleSession

    @Environment(\.dismiss) private var dismiss

    private var availableProfiles: [CPUProfile] {
        let joinedIDs = Set(session.cpuProfiles.map(\.id))
        return CPUProfile.roster.filter { !joinedIDs.contains($0.id) }
    }

    private var memberCount: Int {
        session.state?.players.count ?? 1
    }

    var body: some View {
        List {
            Section("参加中 \(memberCount)/\(BattleRules.maxPlayers)") {
                if session.cpuProfiles.isEmpty {
                    Text("NPCはいません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.cpuProfiles) { profile in
                        HStack(spacing: 12) {
                            AvatarCircle(
                                name: profile.nickname,
                                icon: "",
                                size: 42,
                                color: .accentColor
                            )
                            profileDescription(profile)
                            Spacer()
                            if session.isHost {
                                Button(role: .destructive) {
                                    session.removeCPU(id: profile.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(SoundButtonStyle())
                                .accessibilityLabel("\(profile.nickname)を削除")
                            }
                        }
                    }
                }
            }

            if session.isHost {
                Section("NPCを追加") {
                    if memberCount >= BattleRules.maxPlayers {
                        Label("\(BattleRules.maxPlayers)人まで参加できます", systemImage: "person.3.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableProfiles) { profile in
                            Button {
                                session.addCPU(profile)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 42, height: 42)
                                    profileDescription(profile)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SoundButtonStyle())
                        }
                    }
                }
            }
        }
        .navigationTitle("NPC管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    dismiss()
                }
            }
        }
    }

    private func profileDescription(_ profile: CPUProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(profile.nickname)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(profile.strengthDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
