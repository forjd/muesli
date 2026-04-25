import AppKit
import Carbon.HIToolbox
import Combine
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
                .keyboardShortcut(store.dictationHotKey.keyEquivalent, modifiers: store.dictationHotKey.eventModifiers)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: TranscriptionStore?
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyCancellable: AnyCancellable?
    private let dictationHotKeyID = EventHotKeyID(signature: OSType("MUSL".fourCharCode), id: 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installGlobalHotKeyHandler()
        installStatusItem()
    }

    func configure(store: TranscriptionStore) {
        self.store = store
        registerGlobalHotKey(store.dictationHotKey)
        hotKeyCancellable = store.$dictationHotKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] hotKey in
                self?.registerGlobalHotKey(hotKey)
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
    }

    private func installGlobalHotKeyHandler() {
        guard hotKeyHandler == nil else { return }

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
    }

    private func registerGlobalHotKey(_ hotKey: DictationHotKey) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            dictationHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            Task { @MainActor [weak self] in
                self?.store?.statusMessage = "Could not register \(hotKey.label) hotkey."
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
