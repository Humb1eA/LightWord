import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            StudyView()
                .tabItem { Label("学习", systemImage: "rectangle.stack.fill") }

            VocabListView()
                .tabItem { Label("词本", systemImage: "book.closed.fill") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                store.persistIfNeeded()
            }
        }
        .task {
            if store.state.settings.reminderEnabled {
                ReminderScheduler.sync(settings: store.state.settings)
            }
        }
    }
}
