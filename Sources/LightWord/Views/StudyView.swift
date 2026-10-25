import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
            }
            .navigationTitle("学习")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle:
            IdleView()

        case .studying:
            if let item = store.currentItem {
                Group {
                    if store.isQuizMode(item) {
                        QuizCardView(item: item, options: store.options)
                    } else {
                        FlipCardView(item: item)
                    }
                }
                .id(item.id)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            } else {
                IdleView()
            }

        case .summary:
            SessionSummaryView()
        }
    }
}

// MARK: - Idle / start screen

private struct IdleView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ring
                VStack(spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    store.startSession()
                } label: {
                    Text(store.hasWork ? "开始学习" : "今日已完成")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            store.hasWork ? Theme.accent : Theme.cellEmpty,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .foregroundStyle(store.hasWork ? Color.white : Color.secondary)
                }
                .disabled(!store.hasWork)
                .padding(.top, 4)

                HStack(spacing: 10) {
                    metric("待复习", "\(store.dueCount)")
                    metric("已学", "\(store.state.learnedCount)")
                    metric("连续", "\(store.streak) 天")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }

    private var ring: some View {
        let goal = max(store.state.settings.dailyNewWords, 1)
        let done = min(store.state.log.newCount, goal)
        let progress = Double(done) / Double(goal)

        return ZStack {
            Circle()
                .stroke(Theme.cellEmpty, lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(done)/\(goal)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("今日新词")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .animation(.easeOut(duration: 0.3), value: progress)
    }

    private var title: String {
        store.hasWork ? "开始今天的学习" : "今天的任务完成了"
    }

    private var subtitle: String {
        if store.hasWork {
            return "新词 \(store.freshRemaining) 个 · 复习 \(store.dueCount) 个 · 连续 \(store.streak) 天"
        }
        return "连续 \(store.streak) 天 · 明天再来学新词"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
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
