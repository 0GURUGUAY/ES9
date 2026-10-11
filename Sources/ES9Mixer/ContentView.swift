import SwiftUI
import MixerCore

struct ContentView: View {
    @EnvironmentObject var store: MixerStore
    @State private var confirmJacksOnly = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
            ViewSidebar()
            Divider()
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(title).font(.headline)
                        Toggle("Routage verrouillé", isOn: Binding(
                            get: { store.session.routingLocked }, set: store.setRoutingLocked
                        )).toggleStyle(.checkbox)
                        Text("Déverrouiller uniquement pour changer les liaisons.")
                            .font(.caption).foregroundStyle(.secondary)
                        if store.displayMode == .matrix {
                            Button("Jacks uniquement") { confirmJacksOnly = true }
                                .disabled(store.session.routingLocked)
                        }
                    }
                    switch store.displayMode {
                    case .matrix:
                        RoutingMatrixView()
                    case .console:
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(0..<14) { ChannelStrip(index: $0) }
                        }
                    case .strip:
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(0..<store.stripInputs.count, id: \.self) { InputStripView(slot: $0) }
                            StripOutputsView().padding(.leading, 10)
                        }
                    }
                    if store.displayMode != .strip {
                        Text("SORTIES · GÉNÉRAL · CASQUE").font(.headline)
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(0..<8) { OutputStrip(index: $0) }
                            master
                            headphones
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .disabled(store.busy)
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if store.busy { ProgressView().controlSize(.small) }
                    Label(store.active ? "Direct" : "Démo",
                          systemImage: store.active ? "cable.connector" : "desktopcomputer")
                        .foregroundStyle(store.active ? .green : .orange)
                        .font(.caption)
                    Text(store.status)
                    Spacer()
                    Text(store.dspLabel)
                        .monospacedDigit()
                        .foregroundStyle(store.dspUsage == nil ? Color.secondary : Color.cyan)
                        .help(store.dspStatus)
                }
                if store.dspUsage == nil {
                    Text(store.dspStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("SOLO cumulatif ; MUTE prioritaire. SOLO sorties : jacks uniquement. Niveaux audio non disponibles par MIDI : aucun vu-mètre simulé.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("USB direct : 1–2 → Général ; 3–4 → Casque ; 9–16 → Jacks 1–8. Additionné au mix analogique, hors faders, mutes, solos et Écoute. Régler le niveau dans VCV.")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.pickupMessage.isEmpty {
                    Text(store.pickupMessage).font(.caption).foregroundStyle(.cyan)
                }
            }.padding()
            if store.session.muteAll {
                Text("MUTE ALL actif — entrées analogiques coupées sur le général, le casque et les jacks. USB direct inchangé.")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 1000, minHeight: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $store.showMIDI) { MIDISetupView() }
        .alert("Erreur", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Couper tous les envois au général ?", isPresented: $confirmJacksOnly) {
            Button("Jacks uniquement") { store.useJacksOnly() }
        } message: {
            Text("Le mix analogique du général et son écoute casque deviendront silencieux ; les retours USB directs resteront actifs. Les liaisons jack et leurs niveaux sont conservés. Les huit sorties de chaque mélangeur seront disponibles pour la matrice.")
        }
        .confirmationDialog("Mémoriser les réglages actuels dans l’ES-9 ?",
                            isPresented: Binding(get: { store.flashSlot != nil }, set: { if !$0 { store.flashSlot = nil } })) {
            Button("Mémoriser \(store.flashSlot == 0 ? "sans ordinateur" : "avec USB")") {
                if let slot = store.flashSlot { store.saveFlash(UInt8(slot)) }
                store.flashSlot = nil
            }
        } message: {
            Text("Cela remplace le contenu de cette mémoire permanente. Les réglages ont déjà été appliqués au module.")
        }
    }

    private var title: String {
        switch store.displayMode {
        case .console: return "ENTRÉES"
        case .matrix: return "MATRICE · 14 ENTRÉES × 8 SORTIES JACK"
        case .strip: return "STRIP · ENTRÉES " + store.stripInputs.map { String($0 + 1) }.joined(separator: " · ")
        }
    }

    private var master: some View {
        VStack(spacing: 12) {
            Text("GÉNÉRAL").font(.headline)
            Text("Stéréo L / R").foregroundStyle(.secondary)
            Image(systemName: store.session.masterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.largeTitle).foregroundStyle(store.session.masterMuted ? Color.red : Color.cyan)
                .frame(height: 65)
            VerticalFader(value: Binding(get: { store.session.master }, set: store.setMaster), tint: .cyan)
            Text(Channel.decibels(store.session.master)).monospacedDigit()
            Button("MUTE", action: store.toggleMasterMute)
                .tint(store.session.masterMuted ? .red : .gray)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Mute général")
                .accessibilityValue(store.session.masterMuted ? "Activé" : "Désactivé")
                .help("Couper uniquement le mix analogique du général. Casque, jacks et USB direct inchangés.")
            Text("Agit uniquement sur\nle général stéréo").font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(width: 130, height: 400)
        .background(store.session.masterMuted ? Color.red.opacity(0.18) : Color.cyan.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var headphones: some View {
        VStack(spacing: 12) {
            Text("CASQUE").font(.headline)
            Text("Général · avant master").font(.caption).foregroundStyle(.secondary)
            Toggle("Écoute", isOn: Binding(
                get: { store.session.headphonesEnabled }, set: store.setHeadphonesEnabled
            ))
            Image(systemName: "headphones").font(.largeTitle).foregroundStyle(.cyan)
            VerticalFader(value: Binding(
                get: { store.session.headphonesLevel }, set: store.setHeadphonesLevel
            ), tint: .cyan).disabled(!store.session.headphonesEnabled)
            Text(Session.headphonesDecibels(store.session.headphonesLevel)).monospacedDigit()
            Text("Gain jusqu’à +12 dB.\nBaisser le volume physique\navant d’activer l’écoute.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(width: 150, height: 400)
        .background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Left column for switching quickly between the three views.
struct ViewSidebar: View {
    @EnvironmentObject var store: MixerStore

    var body: some View {
        VStack(spacing: 8) {
            connectButton
            Divider().frame(width: 64).padding(.vertical, 4)
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                let selected = store.displayMode == mode
                Button { store.displayMode = mode } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.symbol).font(.title2)
                        Text(mode.rawValue.uppercased()).font(.caption2.bold())
                    }
                    .frame(width: 64, height: 56)
                    .foregroundStyle(selected ? Color.black : Color.primary)
                    .background(selected ? Color.cyan : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Vue \(mode.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help("Afficher la vue \(mode.rawValue)")
            }
            Spacer()
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
    }

    private var portsMissing: Bool { store.esInput == 0 || store.esOutput == 0 }

    private var connectButton: some View {
        Button {
            if store.active { store.suspend() }
            else if portsMissing { store.showMIDI = true }
            else { store.activate() }
        } label: {
            VStack(spacing: 4) {
                if store.busy {
                    ProgressView().controlSize(.small).frame(height: 22)
                } else {
                    Image(systemName: store.active ? "cable.connector" : "cable.connector.slash").font(.title2)
                }
                Text(store.busy ? "…" : store.active ? "DIRECT" : "CONNECTER").font(.caption2.bold())
            }
            .frame(width: 64, height: 56)
            .foregroundStyle(store.active ? Color.black : Color.primary)
            .background(store.active ? Color.green : Color.orange.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(store.busy || store.flashSlot != nil)
        .accessibilityLabel(store.active ? "ES-9 connecté, suspendre" : "Connecter l’ES-9")
        .help(store.active ? "ES-9 piloté en direct. Cliquer pour suspendre le contrôle."
              : portsMissing ? "Choisir d’abord les ports MIDI de l’ES-9."
              : "Activer le contrôle de l’ES-9 (relecture, configuration et vérification).")
    }
}

struct ChannelStrip: View {
    @EnvironmentObject var store: MixerStore
    let index: Int
    private var channel: Channel { store.session.channels[index] }
    private var selected: Bool { store.bank.target(index % 8) == .input(index) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: "%02d", index + 1)).font(.title3.bold()).foregroundStyle(.cyan)
                Spacer()
                if selected { Text("LC \(index % 8 + 1)").font(.caption2).foregroundStyle(.cyan) }
            }
            TextField("Nom", text: Binding(
                get: { channel.name },
                set: { value in store.changeChannel(index) { $0.name = value } }
            )).textFieldStyle(.plain).font(.title3.bold())
            Text("\(channel.jackSends.filter(\.enabled).count) envoi(s) jack")
                .font(.caption).foregroundStyle(.secondary)
                .help("Modifier les liaisons jack dans la vue Matrice.")
            VStack(spacing: 3) {
                Slider(value: Binding(
                    get: { channel.pan },
                    set: { value in store.changeChannel(index) { $0.pan = value } }
                ), in: -1...1)
                HStack { Text("L"); Spacer(); Text("PAN"); Spacer(); Text("R") }
                    .font(.caption2).foregroundStyle(.secondary)
            }.disabled(!channel.mainEnabled)
            VerticalFader(value: Binding(
                get: { channel.level },
                set: { value in store.changeChannel(index) { $0.level = value } }
            ), tint: .cyan)
            Text(Channel.decibels(channel.level)).font(.system(.caption, design: .monospaced))
            StripButtons(muted: channel.muted, soloed: channel.soloed,
                         mute: { store.changeChannel(index) { $0.muted.toggle() } },
                         solo: { store.changeChannel(index) { $0.soloed.toggle() } })
            Text(store.session.inputIsAudible(index) ? " " : (channel.muted ? "Muet" : "Exclue par SOLO"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 122, height: 430)
        .background(channel.muted ? Color.red.opacity(0.88)
                    : channel.soloed ? Color.yellow.opacity(0.78) : Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            channel.muted ? Color.red
                : channel.soloed ? Color.yellow
                : selected ? Color.cyan.opacity(0.55) : .clear,
            lineWidth: channel.muted || channel.soloed ? 2 : 1
        ))
    }
}

struct OutputStrip: View {
    @EnvironmentObject var store: MixerStore
    let index: Int
    private var output: OutputChannel { store.session.outputs[index] }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("OUT \(index + 1)").font(.headline).foregroundStyle(.orange)
                Spacer()
                if store.bank == .outputs {
                    Text("LC \(index + 1)").font(.caption2).foregroundStyle(.cyan)
                }
            }
            TextField("Nom", text: Binding(
                get: { output.name }, set: { value in store.changeOutput(index) { $0.name = value } }
            )).textFieldStyle(.plain).font(.title3.bold())
            Text("Jack mono").font(.caption).foregroundStyle(.secondary)
            VerticalFader(value: Binding(
                get: { output.level }, set: { value in store.changeOutput(index) { $0.level = value } }
            ), tint: .orange)
            Text(Channel.decibels(output.level)).font(.system(.caption, design: .monospaced))
            StripButtons(muted: output.muted, soloed: output.soloed,
                         mute: { store.changeOutput(index) { $0.muted.toggle() } },
                         solo: { store.changeOutput(index) { $0.soloed.toggle() } })
            Text(store.session.outputIsAudible(index) ? " " : (output.muted ? "Muette" : "Exclue par SOLO"))
                .font(.caption2).foregroundStyle(.secondary)
            Text("\(store.session.channels.filter { $0.jackSends[index].enabled }.count) entrée(s) affectée(s)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 140, height: 400)
        .background(output.muted ? Color.red.opacity(0.88)
                    : output.soloed ? Color.yellow.opacity(0.78) : Color.orange.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            output.muted ? Color.red
                : output.soloed ? Color.yellow
                : store.bank == .outputs ? Color.cyan.opacity(0.55) : .clear,
            lineWidth: output.muted || output.soloed ? 2 : 1
        ))
    }
}

struct RoutingMatrixView: View {
    @EnvironmentObject var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chaque liaison possède son niveau, de −∞ à 0 dB. Gain final = entrée × liaison × sortie. Plusieurs sources peuvent saturer une sortie.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Général : 2 sorties internes ; casque : 2 de plus. « Jacks uniquement » permet les 112 liaisons simultanées, sans général ni casque.")
                .font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("ENTRÉE").frame(width: 160, alignment: .leading)
                    Text("GÉNÉRAL").frame(width: 80)
                    ForEach(0..<8) { output in
                        VStack {
                            Text("OUT \(output + 1)").foregroundStyle(.orange)
                            Text(store.session.outputs[output].name).lineLimit(1)
                        }.frame(width: 108)
                    }
                }.font(.caption.bold())
                ForEach(0..<14) { input in
                    GridRow {
                        VStack(alignment: .leading) {
                            Text("\(input + 1) · \(store.session.channels[input].name)")
                                .lineLimit(1).font(.callout.bold())
                            Text(Channel.decibels(store.session.channels[input].level))
                                .font(.caption).foregroundStyle(.secondary)
                            if !store.session.inputIsAudible(input) {
                                Text("Muette / exclue par SOLO").font(.caption2).foregroundStyle(.orange)
                            }
                        }.frame(width: 160, alignment: .leading)
                        Toggle("Général entrée \(input + 1)", isOn: Binding(
                            get: { store.session.channels[input].mainEnabled },
                            set: { value in store.changeChannel(input) { $0.mainEnabled = value } }
                        )).labelsHidden().toggleStyle(.checkbox)
                            .frame(width: 80).disabled(store.session.routingLocked)
                        ForEach(0..<8) { output in
                            MatrixSendCell(input: input, output: output)
                        }
                    }
                }
            }
        }
    }
}

struct MatrixSendCell: View {
    @EnvironmentObject var store: MixerStore
    let input: Int
    let output: Int
    private var send: JackSend { store.session.channels[input].jackSends[output] }
    private var label: String { "Entrée \(input + 1) vers sortie \(output + 1)" }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Toggle(label, isOn: Binding(
                    get: { send.enabled },
                    set: { value in store.changeChannel(input) { $0.jackSends[output].enabled = value } }
                )).labelsHidden().toggleStyle(.checkbox).disabled(store.session.routingLocked)
                Text(send.enabled ? Channel.decibels(send.level) : "—")
                    .font(.system(.caption2, design: .monospaced))
            }
            Slider(value: Binding(
                get: { send.level },
                set: { value in store.changeChannel(input) { $0.jackSends[output].level = value } }
            ), in: 0...1).disabled(!send.enabled)
                .accessibilityLabel("Niveau \(label)")
        }
        .padding(8)
        .frame(width: 108)
        .background(send.enabled ? Color.cyan.opacity(0.12) : Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 6))
        .help("\(label). Le fader d’entrée et celui de sortie restent actifs. Une liaison à −∞ reste allouée ; décocher pour libérer le routage.")
    }
}

struct StripButtons: View {
    let muted: Bool
    let soloed: Bool
    let mute: () -> Void
    let solo: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button("MUTE", action: mute).tint(muted ? .red : .gray)
                .accessibilityLabel("Mute").accessibilityValue(muted ? "Activé" : "Désactivé")
            Button("SOLO", action: solo).tint(soloed ? .yellow : .gray)
                .accessibilityLabel("Solo").accessibilityValue(soloed ? "Activé" : "Désactivé")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct VerticalFader: View {
    @Binding var value: Double
    var tint: Color = .cyan

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.42))
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
            Slider(value: $value, in: 0...1)
                .tint(tint)
                .frame(width: 160)
                .rotationEffect(.degrees(-90))
                .accessibilityLabel("Niveau")
        }
        .frame(width: 50, height: 178)
    }
}

struct MIDISetupView: View {
    @EnvironmentObject var store: MixerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Connexions et Launch Control XL").font(.title2.bold())
                Spacer()
                Button("Fermer") { store.learning = nil; dismiss() }
            }
            GroupBox("ES-9 — aucune modification à la connexion") {
                VStack(alignment: .leading) {
                    Picker("Réception", selection: $store.esInput) {
                        Text("Non connecté").tag(UInt32(0))
                        ForEach(store.sources) { Text($0.name).tag($0.id) }
                    }.onChange(of: store.esInput) { _ in store.portsChanged() }
                    Picker("Envoi", selection: $store.esOutput) {
                        Text("Non connecté").tag(UInt32(0))
                        ForEach(store.destinations) { Text($0.name).tag($0.id) }
                    }.onChange(of: store.esOutput) { _ in store.portsChanged() }
                    HStack {
                        Button("Interroger la version", action: store.probe)
                            .disabled(store.esInput == 0 || store.esOutput == 0 || store.busy)
                        Text(store.firmware).foregroundStyle(.secondary)
                    }
                    Text(store.dspLabel).monospacedDigit().foregroundStyle(.cyan)
                    Text(store.dspStatus).font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            Picker("Launch Control — réception", selection: $store.controllerInput) {
                Text("Non connecté").tag(UInt32(0))
                ForEach(store.sources.filter { $0.id != store.esInput }) { Text($0.name).tag($0.id) }
            }.onChange(of: store.controllerInput) { _ in store.controllerPortChanged() }
            Picker("Launch Control — retour LED", selection: Binding(
                get: { store.controllerOutput }, set: store.setControllerOutput
            )) {
                Text("Désactivé").tag(UInt32(0))
                ForEach(store.destinations.filter { $0.id != store.esOutput }) {
                    Text($0.name).tag($0.id)
                }
            }
            Text("Choisissez un template User du Novation. Cliquez sur Apprendre, puis bougez le contrôle ou pressez le bouton correspondant. Utilisez des CC absolus et des boutons momentanés (127 à l’appui, 0 au relâchement). Pour le SOLO, apprenez les huit boutons dans la section Solo ci-dessous.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Pour le retour LED, choisissez la sortie Launch Control. Dans Novation Components, réglez le canal LED de chaque bouton sur le même canal que son canal MIDI d’envoi. Les couleurs indiquent Mute (rouge) et Solo (vert), selon la banque affichée.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("Dernier MIDI : \(store.lastMIDI)").monospaced()
                Spacer()
                if let action = store.learning {
                    Text("Bougez : \(ControlMapping.label(action))").foregroundStyle(.orange)
                    Button("Annuler") { store.learning = nil }
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ControlMapping.actions, id: \.self) { action in
                        if ["fader0", "mute0", "solo0", "pan0", "master"].contains(action) {
                            Text(action == "master" ? "Général, casque et banques"
                                 : "\(ControlMapping.label(action).dropLast(2)) — 8 contrôles")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1)
                        }
                        HStack {
                            Text(ControlMapping.label(action)).frame(width: 130, alignment: .leading)
                            if let mapping = store.session.mappings.first(where: { $0.action == action }) {
                                Text("\(mapping.status & 0xF0 == 0xB0 ? "CC" : "Note") \(mapping.number) · ch. \((mapping.status & 0x0F) + 1)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("×") { store.forgetMapping(action) }
                            }
                            Spacer()
                            Button(store.learning == action ? "En attente…" : "Apprendre") { store.learning = action }
                                .disabled(store.controllerInput == 0)
                        }.padding(8).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Text("Trois banques : entrées 1–8, entrées 9–14, sorties 1–8. Mute et Solo suivent la banque. Gain linéaire de 40 % à 100 % de la course MIDI. Général et casque ont des CC indépendants. Panoramiques inactifs sur les sorties mono.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 850, height: 670)
        .disabled(store.busy)
    }
}
