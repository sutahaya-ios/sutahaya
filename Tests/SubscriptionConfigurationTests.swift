import XCTest

final class SubscriptionConfigurationTests: XCTestCase {
    func test_買い切りの広告非表示商品を読み込める() throws {
        let configuration = try loadConfiguration()

        let product = try XCTUnwrap(configuration.products.onlyElement)
        let localization = try XCTUnwrap(product.localizations.onlyElement)

        XCTAssertEqual(product.productID, "com.n.HayaosiApp.removeads")
        XCTAssertEqual(product.type, "NonConsumable")
        XCTAssertEqual(localization.locale, "ja")
        XCTAssertEqual(localization.displayName, "広告非表示")
        XCTAssertEqual(localization.description, "広告を表示しません")
    }

    /// 自動更新サブスクはガイドライン3.1.2で却下されたため、設定へ戻さない
    func test_自動更新サブスクを含まない() throws {
        let configuration = try loadConfiguration()

        XCTAssertTrue(configuration.subscriptionGroups.isEmpty)
        XCTAssertTrue(configuration.nonRenewingSubscriptions.isEmpty)
    }

    private func loadConfiguration() throws -> StoreKitConfiguration {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let configurationURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Config/Subscription.storekit")
        let configurationData = try Data(contentsOf: configurationURL)
        return try JSONDecoder().decode(StoreKitConfiguration.self, from: configurationData)
    }
}

private struct StoreKitConfiguration: Decodable {
    let products: [StoreKitProduct]
    let subscriptionGroups: [StoreKitSubscriptionGroup]
    let nonRenewingSubscriptions: [StoreKitProduct]
}

private struct StoreKitProduct: Decodable {
    let productID: String
    let type: String
    let localizations: [StoreKitProductLocalization]
}

private struct StoreKitSubscriptionGroup: Decodable {
    let subscriptions: [StoreKitProduct]
}

private struct StoreKitProductLocalization: Decodable {
    let description: String
    let displayName: String
    let locale: String
}

private extension Collection {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
