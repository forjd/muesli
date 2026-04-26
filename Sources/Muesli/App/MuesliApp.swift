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

                if let keyEquivalent = store.dictationHotKey.keyEquivalent {
                    Button("Toggle Dictation Paste") {
                        Task { await store.toggleDictationPaste() }
                    }
                    .keyboardShortcut(keyEquivalent, modifiers: store.dictationHotKey.eventModifiers)
                } else {
                    Button("Toggle Dictation Paste") {
                        Task { await store.toggleDictationPaste() }
                    }
                }
            }
        }

        Settings {
            SettingsView(store: store)
        }

        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Image(systemName: store.isRecording ? "mic.circle.fill" : "mic.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: TranscriptionStore?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyCancellable: AnyCancellable?
    private var isHotKeyDown = false
    private var hybridHoldTask: Task<Void, Never>?
    private var hybridHoldDidEngage = false
    private let hybridHoldThreshold: Duration = .milliseconds(350)
    private let dictationHotKeyID = EventHotKeyID(signature: OSType("MUSL".fourCharCode), id: 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installGlobalHotKeyHandler()
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

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
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
                appDelegate.handleDictationHotKey(eventKind: GetEventKind(event))
                return noErr
            },
            eventTypes.count,
            &eventTypes,
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

    private func handleDictationHotKey(eventKind: UInt32) {
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            guard !isHotKeyDown else { return }
            isHotKeyDown = true
            handleDictationHotKeyPressed()
        case UInt32(kEventHotKeyReleased):
            guard isHotKeyDown else { return }
            isHotKeyDown = false
            handleDictationHotKeyReleased()
        default:
            break
        }
    }

    private func handleDictationHotKeyPressed() {
        switch store?.dictationHotKeyMode ?? .toggle {
        case .toggle:
            toggleDictationPaste()
        case .pushToTalk:
            Task { @MainActor [weak self] in
                await self?.store?.startDictationPaste()
                if let store = self?.store, store.isRecording {
                    store.statusMessage = "Release \(store.dictationHotKey.label) to paste."
                }
            }
        case .hybrid:
            if store?.isRecording == true {
                cancelHybridHold()
                Task { @MainActor [weak self] in
                    await self?.store?.finishDictationPaste()
                }
                return
            }

            hybridHoldDidEngage = false
            Task { @MainActor [weak self] in
                await self?.store?.startDictationPaste()
            }
            hybridHoldTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: self?.hybridHoldThreshold ?? .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    self?.hybridHoldDidEngage = true
                    if let store = self?.store, store.isRecording {
                        store.statusMessage = "Release \(store.dictationHotKey.label) to paste."
                    }
                } catch {
                    return
                }
            }
        }
    }

    private func handleDictationHotKeyReleased() {
        switch store?.dictationHotKeyMode ?? .toggle {
        case .toggle:
            break
        case .pushToTalk:
            Task { @MainActor [weak self] in
                await self?.store?.finishDictationPaste()
            }
        case .hybrid:
            hybridHoldTask?.cancel()
            hybridHoldTask = nil
            guard hybridHoldDidEngage else { return }
            hybridHoldDidEngage = false
            Task { @MainActor [weak self] in
                await self?.store?.finishDictationPaste()
            }
        }
    }

    private func cancelHybridHold() {
        hybridHoldTask?.cancel()
        hybridHoldTask = nil
        hybridHoldDidEngage = false
    }

}

private extension String {
    var fourCharCode: FourCharCode {
        utf8.reduce(0) { result, character in
            (result << 8) + FourCharCode(character)
        }
    }
}
