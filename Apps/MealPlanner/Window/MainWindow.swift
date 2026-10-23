import SwiftUI

/// The main window: sections in the sidebar, each with its own screen.
struct MainWindow: View {
    static let id = "main"

    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(
                selection: Binding<AppModel.Section?>(
                    get: { model.section }, set: { section in section.map { model.section = $0 } })
            ) {
                ForEach(AppModel.Section.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            SectionScreen(section: model.section, database: model.database)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.canvas))
        }
        .navigationTitle(model.section.title)
        .containerBackground(Color(.canvas), for: .window)
        .alert(
            model.problem?.title ?? "",
            isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } }),
            presenting: model.problem
        ) { _ in
            Button("Понятно") { model.problem = nil }
        } message: { problem in
            Text(problem.message)
        }
    }
}
