import StoreKit
import SwiftUI

/// 広告非表示サブスクリプションの状態確認・購入・復元を行う画面。
struct SubscriptionView: View {
    @State private var isProcessing = false
    @State private var resultMessage: String?

    private var subscriptionService: SubscriptionService { .shared }

    var body: some View {
        List {
            statusSection
            productSection
            restoreSection
        }
        .navigationTitle("プレミアム")
        .task {
            await subscriptionService.start()
            await subscriptionService.loadProduct()
        }
        .alert("プレミアム", isPresented: resultMessageIsPresented) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var statusSection: some View {
        Section("現在の状態") {
            if !subscriptionService.hasLoadedEntitlements {
                ProgressView("購入状態を確認中…")
            } else if subscriptionService.isSubscribed {
                Label("広告非表示を利用中", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("バナー広告と全画面広告は表示されません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("無料プラン", systemImage: "person.crop.circle")
                Text("バナー広告と全画面広告が表示されます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var productSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(subscriptionService.product?.displayName ?? "広告非表示")
                    .font(.headline)
                Text(subscriptionService.product?.description ?? "広告を表示しません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if subscriptionService.isSubscribed {
                Label("購入済み", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let product = subscriptionService.product {
                Button {
                    purchase()
                } label: {
                    HStack {
                        Text("購入する")
                        Spacer()
                        Text("\(product.displayPrice)／月")
                    }
                }
                .disabled(isProcessing)
            } else if subscriptionService.isLoadingProduct {
                ProgressView("商品情報を読み込み中…")
            } else {
                if let errorMessage = subscriptionService.productLoadErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("商品情報を再読み込み", systemImage: "arrow.clockwise") {
                    Task { await subscriptionService.loadProduct() }
                }
            }
        } header: {
            Text("広告非表示")
        } footer: {
            Text("購入はApple IDに請求され、解約しない限り毎月自動更新されます。管理・解約はApp Storeのサブスクリプション設定から行えます。")
        }
    }

    private var restoreSection: some View {
        Section {
            Button("購入を復元", systemImage: "arrow.clockwise.circle") {
                restorePurchases()
            }
            .disabled(isProcessing)
        } footer: {
            Text("以前購入したサブスクリプションが反映されない場合にお試しください。")
        }
    }

    private var resultMessageIsPresented: Binding<Bool> {
        Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )
    }

    private func purchase() {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                switch try await subscriptionService.purchase() {
                case .purchased:
                    resultMessage = "購入が完了しました。広告は表示されません。"
                case .pending:
                    resultMessage = "購入は承認待ちです。承認後に自動で反映されます。"
                case .cancelled:
                    break
                }
            } catch {
                resultMessage = "購入を完了できませんでした。\n\(error.localizedDescription)"
            }
        }
    }

    private func restorePurchases() {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                try await subscriptionService.restorePurchases()
                resultMessage = subscriptionService.isSubscribed
                    ? "購入を復元しました。広告は表示されません。"
                    : "復元できる購入は見つかりませんでした。"
            } catch {
                resultMessage = "購入を復元できませんでした。\n\(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
}
