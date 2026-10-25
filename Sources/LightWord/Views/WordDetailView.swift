import SwiftUI

struct WordDetailView: View {
    @EnvironmentObject private var store: AppStore

    let wordID: String

    private var word: Word? { store.word(id: wordID) }
    private var card: CardState? { store.cardState(for: wordID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let word {
                    headline(word)
                    meanings(word)
                    examples(word)
                    schedule
                } else {
                    Text("未找到该单词")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(word?.text ?? "单词")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleStar(wordID: wordID)
                } label: {
                    Image(systemName: (card?.starred ?? false) ? "star.fill" : "star")
                        .foregroundStyle((card?.starred ?? false) ? Color.yellow : Theme.accent)
                }
                .accessibilityLabel("收藏")
            }
        }
    }

    private func headline(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.text)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 12) {
                if !word.phonetic.isEmpty {
                    Text("/\(word.phonetic)/")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button {
                    SpeechService.shared.say(word.text)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("朗读").font(.caption)
                    }
                    .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("朗读单词")
            }
        }
        .padding(.bottom, 2)
    }

    private func meanings(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(word.meanings, id: \.self) { meaning in
                Text(meaning)
                    .font(.title3.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 16)
    }

    @ViewBuilder
    private func examples(_ word: Word) -> some View {
        if !word.examples.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("例句")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 4) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 16)
        }
    }

    @ViewBuilder
    private var schedule: some View {
        if let card, !card.isNew {
            VStack(alignment: .leading, spacing: 6) {
                Text("记忆等级 \(card.box) / \(Scheduler.maxBox)")
                Text("下次复习：\(Formatting.dueString(card.due))")
                Text("累计复习 \(card.reps) 次 · 遗忘 \(card.lapses) 次")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 14)
        }
    }
}
