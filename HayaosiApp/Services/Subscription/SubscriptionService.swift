import Foundation
import Observation
import StoreKit

enum SubscriptionPurchaseOutcome {
    case purchased
    case pending
    case cancelled
}

/// StoreKit 2の商品取得・購入・復元と、広告非表示の権利状態を管理する。
@MainActor
@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()
    static let productID = "com.n.HayaosiApp.premium.monthly"

    private(set) var isSubscribed = false
    private(set) var hasLoadedEntitlements = false
    private(set) var product: Product?
    private(set) var isLoadingProduct = false
    private(set) var productLoadErrorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private var hasStarted = false

    private init() {}

    /// アプリ起動後に一度だけ呼び、現在の権利確認と取引更新の監視を開始する。
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        observeTransactionUpdates()
        await refreshEntitlements()
    }

    func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        productLoadErrorMessage = nil
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: [Self.productID])
            guard let product = products.first else {
                throw SubscriptionServiceError.productNotFound
            }
            self.product = product
        } catch {
            productLoadErrorMessage = error.localizedDescription
            print("[Subscription] 商品情報の取得に失敗: \(error.localizedDescription)")
        }
    }

    func purchase() async throws -> SubscriptionPurchaseOutcome {
        if product == nil {
            await loadProduct()
        }
        guard let product else { throw SubscriptionServiceError.productNotFound }

        switch try await product.purchase() {
        case .success(let verificationResult):
            let transaction = try verified(verificationResult)
            await refreshEntitlements()
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    private func observeTransactionUpdates() {
        transactionUpdatesTask = Task { [weak self] in
            for await verificationResult in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                await self.handleTransactionUpdate(verificationResult)
            }
        }
    }

    private func handleTransactionUpdate(_ verificationResult: VerificationResult<Transaction>) async {
        switch verificationResult {
        case .verified(let transaction):
            guard transaction.productID == Self.productID else { return }
            await refreshEntitlements()
            await transaction.finish()
        case .unverified(let transaction, let error):
            guard transaction.productID == Self.productID else { return }
            print("[Subscription] 取引の検証に失敗: \(error.localizedDescription)")
            await refreshEntitlements()
        }
    }

    func refreshEntitlements() async {
        var hasActiveSubscription = false

        for await verificationResult in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else {
                continue
            }
            hasActiveSubscription = true
            break
        }

        isSubscribed = hasActiveSubscription
        hasLoadedEntitlements = true
    }

    private func verified<T>(_ verificationResult: VerificationResult<T>) throws -> T {
        switch verificationResult {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}

private enum SubscriptionServiceError: LocalizedError {
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "商品情報を取得できませんでした。時間をおいて、もう一度お試しください。"
        }
    }
}
