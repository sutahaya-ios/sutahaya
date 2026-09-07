import SwiftUI

/// SPIの資料解釈で使う表。画像ではなく行列から描くので、文字サイズとダークモードに追従する
struct QuestionTableView: View {
    private static let cornerRadius: CGFloat = 10

    let table: QuestionTable

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !table.caption.isEmpty {
                Text(table.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 列が多い表は横に伸びるため、はみ出したぶんだけ横スクロールさせる
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                            cellText(cell, isHeader: true)
                        }
                    }
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                                // 各行の先頭は項目名なので、数値の列と区別して左寄せにする
                                cellText(cell, isHeader: false, isLeading: index == 0)
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(Color(.separator))
                )
            }
        }
    }

    private func cellText(_ text: String, isHeader: Bool, isLeading: Bool = false) -> some View {
        Text(text)
            .font(.footnote)
            .fontWeight(isHeader || isLeading ? .semibold : .regular)
            .monospacedDigit()
            .frame(minWidth: 56, alignment: isHeader || isLeading ? .leading : .trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
    }
}

#Preview {
    QuestionTableView(table: QuestionTable(
        caption: "3店舗の売上(万円)",
        header: ["", "4月", "5月", "6月"],
        rows: [
            ["A店", "120", "150", "130"],
            ["B店", "90", "110", "140"],
            ["C店", "130", "140", "150"],
        ]
    ))
    .padding()
}
