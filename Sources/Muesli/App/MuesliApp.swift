import AppKit
import Carbon.HIToolbox
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
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let dictationHotKeyID = EventHotKeyID(signature: OSType("MUSL".fourCharCode), id: 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installGlobalHotKey()
        installStatusItem()
    }

    func configure(store: TranscriptionStore) {
        self.store = store
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
    }

    private func installGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.id == 1 else { return noErr }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                appDelegate.toggleDictationPaste()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &hotKeyHandler
        )

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | shiftKey),
            dictationHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            Task { @MainActor [weak self] in
                self?.store?.statusMessage = "Could not register Command-Shift-D hotkey."
            }
        }
    }

    private func toggleDictationPaste() {
        Task { @MainActor [weak self] in
            await self?.store?.toggleDictationPaste()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "Muesli")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() {
        toggleDictationPaste()
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        utf8.reduce(0) { result, character in
            (result << 8) + FourCharCode(character)
        }
    }
}
