import AppKit
import SwiftUI
import MixerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ES9MixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = MixerStore()

    var body: some Scene {
        WindowGroup("ES-9 Mixer") {
            ContentView().environmentObject(store)
        }
        .defaultSize(width: 1400, height: 1050)
        .commands {
            CommandGroup(replacing: .newItem) {}
            MixerCommands(store: store)
        }
    }
}

struct MixerCommands: Commands {
    @ObservedObject var store: MixerStore

    private var unavailable: Bool {
        store.busy || store.showMIDI || store.flashSlot != nil
    }

    var body: some Commands {
        CommandMenu("Session") {
            Button("Ouvrir…", action: store.openSession)
                .keyboardShortcut("o")
                .disabled(unavailable)
            Button("Enregistrer sous…", action: store.saveSession)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(unavailable)
            Divider()
            Button("Restaurer une sauvegarde ES-9…", action: store.restoreBackup)
                .disabled(unavailable || store.esInput == 0 || store.esOutput == 0)
        }
        CommandMenu("ES-9") {
            Button(store.active ? "Mode Direct" : "Mode Démonstration") {}
                .disabled(true)
            Toggle("MUTE ALL", isOn: Binding(
                get: { store.session.muteAll },
                set: { value in
                    if value != store.session.muteAll { store.toggleMuteAll() }
                }
            ))
            .disabled(unavailable)
            Divider()
            Button("Configurer MIDI…") { store.showMIDI = true }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(unavailable)
            Divider()
            if store.active {
                Button("Vérifier", action: store.verifyHardware)
                    .disabled(unavailable)
                Menu("Mémoriser") {
                    Button("Avec USB…") { store.flashSlot = 1 }
                    Button("Sans ordinateur…") { store.flashSlot = 0 }
                }
                .disabled(unavailable)
                Button("Suspendre", action: store.suspend)
                    .disabled(unavailable)
            } else {
                Button("Activer sur l’ES-9", action: store.activate)
                    .disabled(unavailable || store.esInput == 0 || store.esOutput == 0)
            }
        }
        CommandMenu("Launch Control") {
            Picker("Banque", selection: Binding(get: { store.bank }, set: store.changeBank)) {
                ForEach(ControllerBank.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.inline)
            .disabled(unavailable)
        }
        CommandMenu("Affichage") {
            Picker("Vue", selection: $store.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .disabled(unavailable)
        }
    }
}
