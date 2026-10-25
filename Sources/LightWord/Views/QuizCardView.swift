import SwiftUI

/// Four-option quiz used for due reviews. Options are prepared by `AppStore`
/// once per card, never inside `body`, so they do not reshuffle on redraw.
struct QuizCardView: View {
    @EnvironmentObject private var store: AppStore

    let item: SessionItem
    let options: [Word]

    @State private var pickedID: String?

    private var answered: Bool { pickedID != nil }
    private var pickedCorrect: Bool { pickedID == item.id }

    var body: some View {
        VStack(spacing: 14) {
            header
            optionList
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, 4)
        .onAppear {
            if store.state.settings.autoPlay {
                SpeechService.shared.say(item.word.text)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("复习 · 选出正确释义")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("剩余 \(store.sessionRemaining)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.word.text)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Button {
                    SpeechService.shared.say(item.word.text)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("朗读单词")
                Spacer()
            }

            if !item.word.phonetic.isEmpty {
                Text("/\(item.word.phonetic)/")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private var optionList: some View {
        VStack(spacing: 10) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    pick(option)
                } label: {
                    optionRow(option, letter: letter(index))
                }
                .buttonStyle(.plain)
                .disabled(answered)
            }
        }
    }

    private func optionRow(_ option: Word, letter: String) -> some View {
        HStack(spacing: 12) {
            Text(letter)
                .font(.caption.weight(.bold))
                .foregroundStyle(optionTint(option))
                .frame(width: 26, height: 26)
                .background(optionTint(option).opacity(0.12), in: Circle())

            Text(option.primaryMeaning)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if answered, option.id == item.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            } else if answered, option.id == pickedID {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.bad)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor(option), lineWidth: 1.5)
        )
    }

    private func optionTint(_ option: Word) -> Color {
        if answered, option.id == item.id { return Theme.good }
        if answered, option.id == pickedID { return Theme.bad }
        return Theme.accent
    }

    private func borderColor(_ option: Word) -> Color {
        guard answered else { return Color.clear }
        if option.id == item.id { return Theme.good }
        if option.id == pickedID { return Theme.bad }
        return Color.clear
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if answered {
                Text(pickedCorrect ? "答对了" : "正确答案：\(item.word.primaryMeaning)")
                    .font(.footnote)
                    .foregroundStyle(pickedCorrect ? Theme.good : Theme.bad)
                    .multilineTextAlignment(.center)

                Button {
                    store.submit(correct: pickedCorrect)
                } label: {
                    Text("继续")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .foregroundStyle(.white)
                }
            } else {
                Text("点选你认为正确的释义")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 20)
            }
        }
        .padding(.bottom, 4)
    }

    private func pick(_ option: Word) {
        guard !answered else { return }
        pickedID = option.id
        if store.state.settings.haptics {
            option.id == item.id ? Haptics.success() : Haptics.tap()
        }
    }

    private func letter(_ index: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F"]
        return index < letters.count ? letters[index] : "?"
    }
}
