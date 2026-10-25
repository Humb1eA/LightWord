import SwiftUI

struct SessionSummaryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 6) {
                Text("本轮完成")
                    .font(.title2.weight(.bold))
                Text("今天已学 \(store.state.log.newCount) 个新词 · 复习 \(store.state.log.reviewCount) 个")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                stat("\(store.sessionAnswered)", "作答")
                stat("\(store.sessionAccuracy)%", "正确率")
                stat("\(store.streak) 天", "连续")
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                store.finishSummary()
            } label: {
                Text("完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card(cornerRadius: 14)
    }
}
