import XCTest

final class SubscriptionConfigurationTests: XCTestCase {
    func test_月額の広告非表示商品を読み込める() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let configurationURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Config/Subscription.storekit")
        let configurationData = try Data(contentsOf: configurationURL)
        let configuration = try JSONDecoder().decode(
            StoreKitConfiguration.self,
            from: configurationData
        )

        let subscriptionGroup = try XCTUnwrap(configuration.subscriptionGroups.onlyElement)
        let product = try XCTUnwrap(subscriptionGroup.subscriptions.onlyElement)
        let localization = try XCTUnwrap(product.localizations.onlyElement)

        XCTAssertEqual(product.productID, "com.n.HayaosiApp.premium.monthly")
        XCTAssertEqual(product.recurringSubscriptionPeriod, "P1M")
        XCTAssertEqual(product.type, "RecurringSubscription")
        XCTAssertEqual(localization.locale, "ja")
        XCTAssertEqual(localization.displayName, "広告非表示")
        XCTAssertEqual(localization.description, "広告を表示しません")
    }
}

private struct StoreKitConfiguration: Decodable {
    let subscriptionGroups: [SubscriptionGroup]
}

private struct SubscriptionGroup: Decodable {
    let subscriptions: [SubscriptionProduct]
}

private struct SubscriptionProduct: Decodable {
    let productID: String
    let recurringSubscriptionPeriod: String
    let type: String
    let localizations: [ProductLocalization]
}

private struct ProductLocalization: Decodable {
    let description: String
    let displayName: String
    let locale: String
}

private extension Collection {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
