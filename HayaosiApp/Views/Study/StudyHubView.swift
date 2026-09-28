import SwiftUI
import SwiftData

/// 学習タブ。ピン留めした教材から学習内容を選ぶ入口
struct StudyHubView: View {
    @AppStorage("pinnedStudyCategories") private var pinnedCategoriesJSON = "[]"
    @Query private var records: [AnswerRecord]
    @Query private var questions: [Question]

    @State private var isEditingBoard = false
    @State private var isShowingMaterialSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PinnedStudyBoardView(
                    categories: pinnedCategories,
                    records: records,
                    questions: questions,
                    isEditing: isEditingBoard,
                    onUnpin: unpin
                )

                addMaterialButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("学習")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditingBoard ? "完了" : "編集") {
                    withAnimation {
                        isEditingBoard.toggle()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { AdBannerView() }
        .sheet(isPresented: $isShowingMaterialSheet) {
            StudyMaterialAddSheet(pinnedCategories: pinnedCategoriesBinding)
        }
    }

    private var addMaterialButton: some View {
        Button {
            isShowingMaterialSheet = true
        } label: {
            Label("教材を追加", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var pinnedCategories: [StudyCategory] {
        guard let data = pinnedCategoriesJSON.data(using: .utf8) else {
            return []
        }

        do {
            let rawValues = try JSONDecoder().decode([String].self, from: data)
            var includedRawValues = Set<String>()
            return rawValues.compactMap { rawValue in
                guard includedRawValues.insert(rawValue).inserted else {
                    return nil
                }
                return StudyCategory(rawValue: rawValue)
            }
        } catch {
            print("ピン留め教材の読み込みに失敗: \(error)")
            return []
        }
    }

    private var pinnedCategoriesBinding: Binding<[StudyCategory]> {
        Binding(
            get: { pinnedCategories },
            set: storePinnedCategories
        )
    }

    private func unpin(_ category: StudyCategory) {
        storePinnedCategories(pinnedCategories.filter { $0 != category })
    }

    private func storePinnedCategories(_ categories: [StudyCategory]) {
        do {
            let data = try JSONEncoder().encode(categories.map(\.rawValue))
            guard let json = String(data: data, encoding: .utf8) else {
                print("ピン留め教材を文字列へ変換できませんでした")
                return
            }
            pinnedCategoriesJSON = json
        } catch {
            print("ピン留め教材の保存に失敗: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        StudyHubView()
    }
    .modelContainer(
        for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self],
        inMemory: true
    )
}
