import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: MarkdownModel
    @State private var dropIsTargeted = false

    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                MarkdownWebView(
                    markdown: model.markdown,
                    title: model.fileName,
                    appearanceMode: model.appearanceMode,
                    fontScale: model.fontScale
                )
                    .ignoresSafeArea(.container, edges: .bottom)

                if dropIsTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
        }
        .onReceive(refreshTimer) { _ in
            model.reloadIfChanged()
        }
        .onDrop(of: [.fileURL], isTargeted: $dropIsTargeted) { providers in
            loadDroppedFile(from: providers)
        }
        .alert("Markdown Viewer", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                model.presentOpenPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)

            Button {
                model.cycleAppearanceMode()
            } label: {
                Label(model.appearanceMode.label, systemImage: model.appearanceMode.icon)
            }
            .help("Toggle appearance (\(model.appearanceMode.label))")

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.fileName)
                    .font(.headline)
                    .lineLimit(1)
                if let fileURL = model.fileURL {
                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Open or drop a .md file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func loadDroppedFile(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }

            if let url {
                Task { @MainActor in
                    model.open(url)
                }
            }
        }
        return true
    }
}

struct OpenRecentMenu: View {
    let model: MarkdownModel
    @ObservedObject private var recents = RecentFiles.shared

    var body: some View {
        Menu("Open Recent") {
            if recents.urls.isEmpty {
                Text("No Recent Documents")
            } else {
                ForEach(recents.urls, id: \.path) { url in
                    Button(url.lastPathComponent) {
                        model.open(url)
                    }
                }
                Divider()
                Button("Clear Menu") {
                    recents.clear()
                }
            }
        }
    }
}
