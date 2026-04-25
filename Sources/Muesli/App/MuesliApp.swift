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
                .onAppear {
                    appDelegate.configure(store: store)
                }
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

                Button("Toggle Dictation Paste") {
                    Task { await store.toggleDictationPaste() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: TranscriptionStore?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installShortcutMonitors()
        installStatusItem()
    }

    func configure(store: TranscriptionStore) {
        self.store = store
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func installShortcutMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcut(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleShortcut(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "d" else {
            return false
        }

        Task { @MainActor [weak self] in
            await self?.store?.toggleDictationPaste()
        }
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "Muesli")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() {
        Task { @MainActor [weak self] in
            await self?.store?.toggleDictationPaste()
        }
    }
}
