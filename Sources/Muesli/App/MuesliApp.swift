import AppKit
import SwiftUI

@main
struct MuesliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TranscriptionStore()

    var body: some Scene {
        WindowGroup("Muesli", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 920, minHeight: 580)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button(store.isRecording ? "Stop Recording" : "Start Recording") {
                    Task { await store.toggleRecording() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Transcribe Latest Recording") {
                    Task { await store.transcribeLatestRecording() }
                }
                .keyboardShortcut("t", modifiers: [.command])
                .disabled(store.latestRecordingURL == nil || store.isBusy)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
