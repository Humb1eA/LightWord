import SwiftUI

/// Tap-to-reveal card: the word first, the meaning only when the user asks for
/// it. This is the "新词" half of the session and the fallback for reviews when
/// multiple choice is switched off.
struct FlipCardView: View {
    @EnvironmentObject private var store: AppStore

    let item: SessionItem

    @State private var revealed = false

    var body: some View {
        VStack(spacing: 14) {
            progressLine
            card
            actions
        }
        .onAppear {
            if store.state.settings.autoPlay {
                SpeechService.shared.say(item.word.text)
            }
        }
    }

    private var progressLine: some View {
        HStack {
            Text(item.kind == .fresh ? "新词" : "复习")
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
        .padding(.top, 4)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button {
                    SpeechService.shared.say(item.word.text)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("朗读单词")
            }

            Text(item.word.text)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if !item.word.phonetic.isEmpty {
                Text("/\(item.word.phonetic)/")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if revealed {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(item.word.meanings, id: \.self) { meaning in
                        Text(meaning)
                            .font(.title3.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(item.word.examples.enumerated()), id: \.offset) { _, example in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(example.en)
                                .font(.callout)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                            Text(example.zh)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("轻触卡片查看释义")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
        .card(cornerRadius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.cellEmpty.opacity(0.7), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { reveal() }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if revealed {
                HStack(spacing: 12) {
                    Button {
                        grade(false)
                    } label: {
                        pill("不认识", tint: Theme.bad, filled: false)
                    }
                    Button {
                        grade(true)
                    } label: {
                        pill("认识", tint: Theme.accent, filled: true)
                    }
                }
            } else {
                Button {
                    reveal()
                } label: {
                    pill("显示释义", tint: Theme.accent, filled: true)
                }
            }
        }
    }

    private func reveal() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            revealed = true
        }
    }

    private func grade(_ correct: Bool) {
        if store.state.settings.haptics { Haptics.tap() }
        store.submit(correct: correct)
    }

    private func pill(_ title: String, tint: Color, filled: Bool) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                filled ? tint : Color.clear,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(filled ? Color.clear : tint, lineWidth: 1.5)
            )
            .foregroundStyle(filled ? Color.white : tint)
    }
}
