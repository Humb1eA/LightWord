import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberRow(
                        title: "每日新词",
                        value: store.state.settings.dailyNewWords,
                        range: 5...50,
                        step: 1,
                        onChange: store.setDailyNewWords
                    )

                    NumberRow(
                        title: "每日复习上限",
                        value: store.state.settings.dailyReviewCap,
                        range: 10...200,
                        step: 10,
                        onChange: store.setDailyReviewCap
                    )

                    Toggle("复习用选择题", isOn: boolBinding({ store.state.settings.quizInReview }, store.setQuizInReview))
                    Toggle("自动朗读", isOn: boolBinding({ store.state.settings.autoPlay }, store.setAutoPlay))
                    Toggle("触感反馈", isOn: boolBinding({ store.state.settings.haptics }, store.setHaptics))
                } header: {
                    Text("学习计划")
                } footer: {
                    Text("「每日新词」只统计没学过的词；复习按遗忘曲线从到期词里挑。")
                }

                Section {
                    Toggle("每日提醒", isOn: boolBinding({ store.state.settings.reminderEnabled }, store.setReminder))

                    if store.state.settings.reminderEnabled {
                        DatePicker(
                            "提醒时间",
                            selection: Binding(
                                get: { store.reminderDate },
                                set: { store.setReminderTime($0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("首次开启时系统会询问通知权限。")
                }

                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text("重置全部学习进度")
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("学习记录保存在 App 沙盒内，卸载 App 会一并删除。")
                }

                Section {
                    settingRow("词库", "\(store.book.name) · \(store.book.words.count) 词")
                    settingRow("已学单词", "\(store.state.learnedCount)")
                    settingRow("版本", appVersion)
                    settingRow("Bundle ID", Bundle.main.bundleIdentifier ?? "-")
                } header: {
                    Text("关于")
                } footer: {
                    Text("本 App 通过自签安装，免费开发者证书 7 天有效。到期后图标变灰、点开闪退，用电脑重新签名安装即可，App 内的学习进度会保留在设备上。")
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("重置全部学习进度？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置", role: .destructive) { store.resetProgress() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有单词的记忆等级、连续天数都会被清空，无法恢复。")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func settingRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func intBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(get: get, set: set)
    }

    private func boolBinding(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: set)
    }
}

/// Plain -/+ control. Avoids depending on `Stepper`'s overloaded initialisers,
/// which are easy to get wrong when the app cannot be compiled locally.
private struct NumberRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 14) {
                button("minus.circle", enabled: value - step >= range.lowerBound) {
                    onChange(max(value - step, range.lowerBound))
                }

                Text("\(value)")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 34, alignment: .center)

                button("plus.circle", enabled: value + step <= range.upperBound) {
                    onChange(min(value + step, range.upperBound))
                }
            }
            .foregroundStyle(Theme.accent)
        }
    }

    private func button(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .opacity(enabled ? 1 : 0.3)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "minus.circle" ? "减少" : "增加")
    }
}
