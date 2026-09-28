import XCTest
@testable import HayaosiApp

/// 配布するSPIの問題データが、出題に必要な形を満たしているか検証する
final class SPIQuestionDataTests: XCTestCase {
    private var questions: [Question] { QuestionSeeder.loadSPIQuestions() }

    func test_SPIの各カテゴリに問題がある() {
        for category in Genre.spi.categories {
            XCTAssertFalse(
                questions.filter { $0.category == category }.isEmpty,
                "\(category.displayName)の問題が読み込めていない"
            )
        }
    }

    func test_IDが重複せずカテゴリごとの接頭辞で始まる() {
        let identifiers = questions.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "問題IDが重複している")

        for question in questions {
            let prefix = question.category == .spiVerbal ? "spi_v_" : "spi_n_"
            XCTAssertTrue(
                question.id.hasPrefix(prefix),
                "\(question.id) は \(prefix) で始まるべき"
            )
        }
    }

    func test_選択肢は5つで正解を含み重複しない() {
        for question in questions {
            XCTAssertEqual(question.choices.count, 5, "\(question.id) の選択肢が5つでない")
            XCTAssertEqual(
                Set(question.choices).count,
                question.choices.count,
                "\(question.id) の選択肢が重複している"
            )
            XCTAssertTrue(
                question.choices.contains(question.answer),
                "\(question.id) の正解が選択肢に無い"
            )
        }
    }

    func test_解説が空でない() {
        for question in questions {
            XCTAssertFalse(question.explanation.isEmpty, "\(question.id) に解説が無い")
        }
    }

    func test_表を持つ問題は行ごとの列数がヘッダーと揃っている() {
        for question in questions {
            guard let table = question.table else { continue }
            XCTAssertFalse(table.header.isEmpty, "\(question.id) の表にヘッダーが無い")
            for row in table.rows {
                XCTAssertEqual(
                    row.count,
                    table.header.count,
                    "\(question.id) の表の列数がヘッダーと違う"
                )
            }
        }
    }

    func test_SPIはジャンルがspiで文字送りもシャッフルもしない() {
        for question in questions {
            XCTAssertEqual(question.genre, .spi)
        }
        XCTAssertFalse(Genre.spi.usesProgressiveReveal)
        XCTAssertFalse(Genre.spi.shufflesChoices)
    }
}
