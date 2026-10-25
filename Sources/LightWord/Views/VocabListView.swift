import SwiftUI

struct VocabListView: View {
    @EnvironmentObject private var store: AppStore

    @State private var query = ""
    @State private var starredOnly = false

    private var entries: [AppStore.VocabEntry] {
        store.vocabulary(query: query, starredOnly: starredOnly)
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text(emptyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(entries) { entry in
                            NavigationLink {
                                WordDetailView(wordID: entry.word.id)
                            } label: {
                                row(entry)
                            }
                        }
                    } header: {
                        Text("共 \(entries.count) 词 · 数字为记忆等级")
                            .font(.caption2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "搜索单词或释义")
            .navigationTitle("词本")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        starredOnly.toggle()
                    } label: {
                        Image(systemName: starredOnly ? "star.fill" : "star")
                    }
                    .accessibilityLabel("只看收藏")
                }
            }
        }
    }

    private var emptyText: String {
        if !query.isEmpty { return "没有匹配「\(query)」的单词" }
        if starredOnly { return "还没有收藏的单词，点单词详情右上角的星标收藏" }
        return "还没有学过的单词，去「学习」页开始吧"
    }

    private func row(_ entry: AppStore.VocabEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.word.text)
                        .font(.body.weight(.semibold))
                    if entry.state.starred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(entry.word.primaryMeaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("\(entry.state.box)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accentSoft, in: Circle())
        }
        .padding(.vertical, 2)
    }
}
