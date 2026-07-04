import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(filenameExtension: "md") ?? .plainText
}

@main
struct PrettyMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MarkdownModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear {
                    OpenFileRouter.install { url in
                        model.open(url)
                    }
                }
                .onOpenURL { url in
                    OpenFileRouter.open(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                OpenRecentMenu(model: model)
            }

            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    model.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    model.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    model.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        OpenFileRouter.open(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.forEach { OpenFileRouter.open(URL(fileURLWithPath: $0)) }
        sender.reply(toOpenOrPrint: .success)
    }
}
