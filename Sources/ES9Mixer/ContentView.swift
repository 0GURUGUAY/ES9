import SwiftUI
import MixerCore
import CoreTransferable
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: MixerStore
    @State private var confirmJacksOnly = false
    @State private var inputDragContext = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ViewSidebar()
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    workspaceHeader
                    if store.displayMode == .live {
                        LiveSceneView()
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            VStack(alignment: .leading, spacing: 16) {
                                switch store.displayMode {
                                case .matrix:
                                    RoutingMatrixView()
                                case .console:
                                    HStack(alignment: .top, spacing: 10) {
                                        ForEach(store.session.consoleInputOrder.filter { $0 < ES9.mixerInputCount }, id: \.self) { input in
                                            ChannelStrip(index: input, dragContext: inputDragContext)
                                                .modifier(InputStripDropTarget(context: inputDragContext, source: input, isConsole: true))
                                        }
                                    }
                                case .strip:
                                    HStack(alignment: .top, spacing: 10) {
                                        ForEach(0..<store.session.stripInputs.count, id: \.self) { slot in
                                            InputStripView(slot: slot, dragContext: inputDragContext)
                                                .modifier(InputStripDropTarget(context: inputDragContext, source: slot, isConsole: false))
                                        }
                                        StripOutputsView().padding(.leading, 10)
                                    }
                                case .live:
                                    EmptyView()
                                }
                                if store.displayMode == .console || store.displayMode == .matrix {
                                    Text("SORTIES · GÉNÉRAL · CASQUE").font(.headline)
                                    HStack(alignment: .top, spacing: 10) {
                                        ForEach(0..<ES9.audioJackCount, id: \.self) { OutputStrip(index: $0) }
                                        master
                                        headphones
                                    }
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("USB direct : 1–2 → Général ; 3–4 → Casque ; 9–15 → Jacks 1–7. USB 16 / OUT 8 réservé au GATE Pamela : ne rien y envoyer depuis VCV.")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.pickupMessage.isEmpty {
                    Text(store.pickupMessage).font(.caption).foregroundStyle(.cyan)
                }
            }.padding()
            if store.session.muteAll {
                Text("MUTE GÉNÉRAL actif — entrées audio coupées sur le général, le casque et les jacks. USB direct inchangé.")
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

    private var workspaceHeader: some View {
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
            Spacer()
            if store.displayMode != .live {
                Button("MUTE GÉNÉRAL", systemImage: store.session.muteAll ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       action: store.toggleMuteAll)
                    .buttonStyle(.borderedProminent)
                    .tint(store.session.muteAll ? .red : .gray)
                    .accessibilityIdentifier("workspace-mute-all")
                    #if MIXER_UI_TESTS
                    .background(MixerUITestButtonProbe(identifier: "workspace-mute-all"))
                    #endif
                    .accessibilityValue(store.session.muteAll ? "Activé" : "Désactivé")
                    .help("Couper le mix des entrées audio. Lancer une scène depuis l’arrêt désactive le mute général.")
            }
        }
    }

    private var title: String {
        switch store.displayMode {
        case .console: return "ENTRÉES"
        case .matrix: return "MATRICE · 13 ENTRÉES × 7 SORTIES AUDIO · OUT 8 GATE"
        case .strip: return "STRIP · ENTRÉES " + store.session.stripInputs
            .filter { $0 < ES9.mixerInputCount }.map { String($0 + 1) }.joined(separator: " · ")
        case .live: return "SÉQUENCEUR LIVE"
        }
    }

    private var master: some View {
        let isMasterMuted = store.session.masterMuted
        let isMuteAll = store.session.muteAll
        return VStack(spacing: 12) {
            Text("GÉNÉRAL").font(.headline)
            Text("Stéréo L / R").foregroundStyle(.secondary)
            Image(systemName: isMasterMuted || isMuteAll ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.largeTitle).foregroundStyle(isMasterMuted || isMuteAll ? Color.red : Color.cyan)
                .frame(height: 65)
            VerticalFader(value: Binding(get: { store.session.master }, set: store.setMaster), tint: .cyan)
            Text(Channel.decibels(store.session.master)).monospacedDigit()
            Button("MUTE", action: store.toggleMasterMute)
                .tint(isMasterMuted ? .red : .gray)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Mute général")
                .accessibilityValue(isMasterMuted ? "Activé" : "Désactivé")
                .help("Couper uniquement le mix analogique du général. Casque, jacks et USB direct inchangés.")
            if isMuteAll {
                Text("MUTE GÉNÉRAL").font(.caption.bold()).foregroundStyle(.red)
            } else {
                Text("Agit uniquement sur\nle général stéréo").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(width: 130, height: 400)
        .background(isMasterMuted || isMuteAll ? Color.red.opacity(0.18) : Color.cyan.opacity(0.08),
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
            Divider().frame(width: 64).padding(.vertical, 4)
            gatePlayButton
            Spacer()
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
    }

    private var gatePlayButton: some View {
        Button(action: store.toggleClockGate) {
            VStack(spacing: 4) {
                Image(systemName: store.clockGateHigh ? "stop.fill" : "play.fill")
                    .font(.title2)
                Text(store.clockGateHigh ? "STOP" : "PLAY")
                    .font(.caption2.bold())
            }
            .frame(width: 64, height: 56)
            .foregroundStyle(store.clockGateHigh ? Color.white : Color.black)
            .background(store.clockGateHigh ? Color.red : Color.green,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.clockGateHigh ? "Arrêter le GATE Pamela (OUT 8)" : "Lancer le GATE Pamela (OUT 8)")
        .accessibilityIdentifier("sidebar-gate-toggle")
        #if MIXER_UI_TESTS
        .background(MixerUITestButtonProbe(identifier: "sidebar-gate-toggle"))
        #endif
        .help(store.clockGateHigh
              ? "Arrêter le signal GATE Pamela sur OUT 8 (ramener à 0 V)."
              : "Déclencher le signal GATE Pamela sur OUT 8 (+5 V).")
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
                    .lineLimit(1).minimumScaleFactor(0.7)
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

struct LiveSceneView: View {
    @EnvironmentObject var store: MixerStore
    @State private var sceneName = ""
    @State private var subsceneName = ""
    @State private var durationDraft = "00:00"

    private var scene: LiveScene? {
        store.session.liveScenes.first { $0.id == store.selectedLiveSceneID }
    }

    private var subscene: LiveSubscene? {
        scene?.subscenes.first { $0.id == store.selectedLiveSubsceneID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            sceneList
            Divider()
            if let scene, let subscene {
                editor(scene: scene, subscene: subscene)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucune scène").font(.headline)
                    Text("Créez une scène pour préparer le déroulé du set.")
                        .foregroundStyle(.secondary)
                    Button("Créer une scène", action: store.addLiveScene)
                        .buttonStyle(.borderedProminent)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if store.selectedLiveSceneID == nil, let first = store.session.liveScenes.first {
                store.selectLiveScene(first.id)
            }
            syncNameDrafts()
        }
        .onChange(of: store.selectedLiveSceneID) { _ in syncNameDrafts() }
        .onChange(of: store.selectedLiveSubsceneID) { _ in syncNameDrafts() }
        .onChange(of: subscene?.durationSeconds) { _ in syncDurationDraft() }
    }

    private var sceneList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SET").font(.headline)
                Spacer()
                Button {
                    store.addLiveScene()
                } label: {
                    Label("Scène", systemImage: "plus")
                }
                .help("Créer une scène. Ses entrées commencent toutes en mute.")
            }
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(store.session.liveScenes.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 3) {
                                Button {
                                    store.selectLiveScene(item.id)
                                } label: {
                                    Text("\(index + 1). \(item.name)")
                                        .font(.callout.bold()).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(store.selectedLiveSceneID == item.id
                                                    ? Color.cyan.opacity(0.2) : Color.white.opacity(0.04),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                VStack(spacing: 0) {
                                    Button { store.moveLiveScene(item.id, by: -1) } label: {
                                        Image(systemName: "chevron.up")
                                    }.disabled(index == 0)
                                    Button { store.moveLiveScene(item.id, by: 1) } label: {
                                        Image(systemName: "chevron.down")
                                    }.disabled(index == store.session.liveScenes.count - 1)
                                }.buttonStyle(.borderless).controlSize(.mini)
                            }
                            Text("Total : \(durationLabel(item.totalDurationSeconds))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                            ForEach(Array(item.subscenes.enumerated()), id: \.element.id) { subIndex, cue in
                                HStack(spacing: 3) {
                                    Button {
                                        store.selectLiveScene(item.id)
                                        store.selectLiveSubscene(cue.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: store.liveSceneID == item.id
                                                  && store.liveSubsceneID == cue.id
                                                  ? "play.fill" : "circle")
                                                .font(.caption2)
                                                .foregroundStyle(store.liveSceneID == item.id
                                                                 && store.liveSubsceneID == cue.id
                                                                 ? .green : .secondary)
                                            Text(cue.name).lineLimit(1)
                                            Text(durationLabel(cue.durationSeconds))
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            if store.liveSceneID == item.id && store.liveSubsceneID == cue.id,
                                               let remaining = store.liveTimerRemainingSeconds {
                                                Text(durationLabel(remaining))
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(.green)
                                            }
                                            Spacer(minLength: 0)
                                            if store.liveSceneID == item.id && store.liveSubsceneID == cue.id {
                                                Text(store.sceneTransitioning ? "TRANSITION" : "LIVE")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(store.sceneTransitioning ? .red : .green)
                                            }
                                        }
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 8)
                                        .padding(.vertical, 5)
                                        .background(store.selectedLiveSceneID == item.id
                                                    && store.selectedLiveSubsceneID == cue.id
                                                    ? Color.cyan.opacity(0.16) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                    VStack(spacing: 0) {
                                        Button {
                                            store.moveLiveSubscene(sceneID: item.id, subsceneID: cue.id, by: -1)
                                        } label: { Image(systemName: "chevron.up") }
                                        .disabled(subIndex == 0)
                                        Button {
                                            store.moveLiveSubscene(sceneID: item.id, subsceneID: cue.id, by: 1)
                                        } label: { Image(systemName: "chevron.down") }
                                        .disabled(subIndex == item.subscenes.count - 1)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.mini)
                                }
                            }
                        }
                        .id(item.id)
                    }
                }
            }
            .clipped()
            .onChange(of: store.selectedLiveSceneID) { id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: store.selectedLiveSubsceneID) { _ in
                if let id = store.selectedLiveSceneID { proxy.scrollTo(id, anchor: .top) }
            }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                if let id = store.selectedLiveSceneID { store.removeLiveScene(id) }
            } label: {
                Label("Supprimer la scène", systemImage: "trash")
            }
            .disabled(scene == nil)
        }
        .frame(width: 255)
        .frame(maxHeight: .infinity)
    }

    private func editor(scene: LiveScene, subscene: LiveSubscene) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Nom de la scène", text: $sceneName)
                    .font(.title2.bold())
                    .onSubmit { store.setLiveSceneName(sceneName, id: scene.id) }
                Button {
                    store.setLiveSceneName(sceneName, id: scene.id)
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Enregistrer le nom de la scène.")
                Button {
                    store.addLiveSubscene(to: scene.id)
                } label: {
                    Label("Sous-scène", systemImage: "plus")
                }
                Button {
                    store.captureLiveSubscene(sceneID: scene.id, subsceneID: subscene.id)
                } label: {
                    Label("Capturer le mix", systemImage: "camera")
                }
                .help("Copier les mutes, niveaux et envois OUT 1–4 actuels sans changer les durées.")
            }

            HStack(spacing: 8) {
                Text("SOUS-SCÈNE").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Nom sous-scène", text: $subsceneName)
                    .frame(maxWidth: 240)
                    .onSubmit {
                        store.setLiveSubsceneName(subsceneName, sceneID: scene.id, subsceneID: subscene.id)
                    }
                Button {
                    store.setLiveSubsceneName(subsceneName, sceneID: scene.id, subsceneID: subscene.id)
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Enregistrer le nom de la sous-scène.")
            }

            HStack(spacing: 8) {
                Label("Durée", systemImage: "timer")
                    .font(.callout)
                TextField("MM:SS", text: $durationDraft)
                    .frame(width: 76)
                    .monospacedDigit()
                    .onSubmit {
                        store.setLiveSubsceneDuration(durationDraft, sceneID: scene.id, subsceneID: subscene.id)
                    }
                    .help("Durée de la sous-scène au format minutes:secondes. 00:00 désactive l’auto-avance.")
                Button {
                    store.setLiveSubsceneDuration(durationDraft, sceneID: scene.id, subsceneID: subscene.id)
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Enregistrer la durée de la sous-scène.")
                if store.liveSceneID == scene.id && store.liveSubsceneID == subscene.id,
                   let remaining = store.liveTimerRemainingSeconds {
                    Text("Restant : \(durationLabel(remaining))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.green)
                }
                Spacer()
                Text("Total scène : \(durationLabel(scene.totalDurationSeconds))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("SAVE", systemImage: "square.and.arrow.down") {
                    guard store.setLiveSubsceneDuration(
                        durationDraft, sceneID: scene.id, subsceneID: subscene.id
                    ) else { return }
                    store.setLiveSceneName(sceneName, id: scene.id)
                    store.setLiveSubsceneName(subsceneName, sceneID: scene.id, subsceneID: subscene.id)
                    store.saveLiveChanges(sceneID: scene.id, subsceneID: subscene.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .help("Enregistrer les modifications de cette sous-scène.")
                Button(goButtonTitle, systemImage: store.sceneTransitioning ? "waveform" : "play.fill") {
                    guard store.setLiveSubsceneDuration(
                        durationDraft, sceneID: scene.id, subsceneID: subscene.id
                    ) else { return }
                    store.goLive(sceneID: scene.id, subsceneID: subscene.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .accessibilityIdentifier("live-go")
                #if MIXER_UI_TESTS
                .background(MixerUITestButtonProbe(identifier: "live-go"))
                #endif
                .help("Appliquer cette sous-scène et lancer les transitions par entrée.")
                Button("NEXT", systemImage: "forward.fill") {
                    guard store.setLiveSubsceneDuration(
                        durationDraft, sceneID: scene.id, subsceneID: subscene.id
                    ) else { return }
                    store.nextLiveSubscene()
                }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .accessibilityIdentifier("live-next")
                    #if MIXER_UI_TESTS
                    .background(MixerUITestButtonProbe(identifier: "live-next"))
                    #endif
                    .disabled(store.session.liveScenes.isEmpty || store.liveSetFinished)
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("ARRÊT", systemImage: "stop.fill", action: store.stopLive)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .accessibilityIdentifier("live-stop")
                    #if MIXER_UI_TESTS
                    .background(MixerUITestButtonProbe(identifier: "live-stop"))
                    #endif
                    .disabled(!store.liveSceneActive)
                    .help("Arrêter la scène et revenir à la première scène, sans modifier les niveaux ni le routage atteints.")
                Button("MUTE GÉNÉRAL", systemImage: store.session.muteAll ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       action: store.toggleMuteAll)
                    .buttonStyle(.borderedProminent)
                    .tint(store.session.muteAll ? .red : .gray)
                    .controlSize(.large)
                    .accessibilityIdentifier("live-mute-all")
                    #if MIXER_UI_TESTS
                    .background(MixerUITestButtonProbe(identifier: "live-mute-all"))
                    #endif
                    .accessibilityValue(store.session.muteAll ? "Activé" : "Désactivé")
                    .help("Couper le mix des entrées audio. Lancer une scène depuis l’arrêt désactive le mute général.")
                if store.liveSetFinished {
                    Label("FIN DU SET · dernière sous-scène maintenue", systemImage: "checkmark.seal")
                        .foregroundStyle(.orange)
                    Button("Réarmer") { store.resetLiveSet() }
                        .help("Réarmer la progression sans modifier les niveaux actuels.")
                } else if store.sceneTransitioning {
                    ProgressView().controlSize(.small)
                    Text("Transitions en cours").foregroundStyle(.red)
                } else if let liveScene = store.session.liveScenes.first(where: { $0.id == store.liveSceneID }),
                          let liveCue = liveScene.subscenes.first(where: { $0.id == store.liveSubsceneID }) {
                    Text("Actuel : \(liveScene.name) / \(liveCue.name)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    store.removeLiveSubscene(sceneID: scene.id, subsceneID: subscene.id)
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(scene.subscenes.count <= 1)
                .help("Supprimer cette sous-scène.")
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Label(store.clockGateHigh ? "OUT 8 · GATE HAUT" : "OUT 8 · GATE BAS",
                      systemImage: "waveform.path")
                    .foregroundStyle(store.clockGateHigh ? .green : .secondary)
                Image(systemName: transportSymbol)
                    .foregroundStyle(store.sceneTransitioning ? .red
                                     : store.liveSceneActive ? .green : .secondary)
                Text(transportMessage(scene: scene, subscene: subscene))
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))

            Text("Faders, MUTE et SOLO agissent immédiatement sur le mix, même avant GO. Un réglage manuel de niveau ou de mute interrompt la transition de cette entrée. Le mute global reste prioritaire ; GO/NEXT réappliquent les niveaux programmés et effacent les solos. USB direct inchangé.")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.session.consoleInputOrder.filter { $0 < ES9.mixerInputCount }, id: \.self) { input in
                        inputCueRow(input, cue: subscene.inputs[input], sceneID: scene.id, subsceneID: subscene.id)
                    }
                }
            }
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var goButtonTitle: String {
        guard store.liveSceneID == store.selectedLiveSceneID,
              store.liveSubsceneID == store.selectedLiveSubsceneID else {
            return "GO"
        }
        return store.sceneTransitioning ? "TRANSITION…" : "EN COURS"
    }

    private var transportSymbol: String {
        if store.busy { return "hourglass" }
        if store.sceneTransitioning { return "waveform" }
        return store.liveSceneActive ? "play.circle.fill" : "pause.circle"
    }

    private func transportMessage(scene: LiveScene, subscene: LiveSubscene) -> String {
        if store.busy { return "Opération MIDI en cours — transport temporairement indisponible." }
        if store.sceneTransitioning { return "Transition en cours vers \(scene.name) / \(subscene.name)." }
        if store.liveSceneID == scene.id && store.liveSubsceneID == subscene.id {
            return "Sous-scène active : \(scene.name) / \(subscene.name)."
        }
        return "Prêt — \(subscene.inputs.filter(\.enabled).count) entrée(s) active(s) dans cette sous-scène."
    }

    private func inputCueRow(_ input: Int, cue: LiveInputCue, sceneID: UUID, subsceneID: UUID) -> some View {
        let isCurrentLiveSubscene = store.liveSceneActive
            && store.liveSceneID == sceneID
            && store.liveSubsceneID == subsceneID
        let isTransitioning = store.sceneTransitioning
            && isCurrentLiveSubscene
            && cue.transitionSeconds > 0
        let transitionLevel: Double? = isTransitioning ? store.session.channels[input].level : nil
        let displayedLevel = isCurrentLiveSubscene ? store.liveTargetLevel(for: input) ?? cue.level : cue.level
        let channel = store.session.channels[input]
        let isMuted = channel.muted || store.session.muteAll

        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
            HStack {
                Toggle(isOn: Binding(
                    get: { cue.enabled },
                    set: { value in
                        store.updateLiveInput(sceneID: sceneID, subsceneID: subsceneID, input: input) {
                            $0.enabled = value
                        }
                    }
                )) {
                    Text(String(format: "%02d · %@", input + 1, store.session.channels[input].name))
                        .font(.callout.bold()).lineLimit(1)
                }
                Text(cue.enabled ? "ACTIVE" : "OFF AU GO")
                    .font(.caption2.bold())
                    .foregroundStyle(cue.enabled ? .green : .secondary)
            }
            StripButtons(muted: isMuted, soloed: channel.soloed,
                         mute: { store.changeChannel(input) { $0.muted.toggle() } },
                         solo: { store.changeChannel(input) { $0.soloed.toggle() } },
                         accessibilityPrefix: "live-input-\(input)")
            Text(store.session.inputIsAudible(input) ? " "
                 : store.session.muteAll ? "MUTE GÉNÉRAL" : channel.muted ? "Muet" : "Exclue par SOLO")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                LiveHorizontalFader(
                    value: Binding(
                        get: { displayedLevel },
                        set: { value in
                            store.setLiveInputLevel(value, sceneID: sceneID, subsceneID: subsceneID, input: input)
                        }
                    ),
                    transitionValue: transitionLevel
                )
                .accessibilityIdentifier("live-input-\(input)-level")
                #if MIXER_UI_TESTS
                .background(MixerUITestButtonProbe(identifier: "live-input-\(input)-level"))
                #endif
                if let transitionLevel {
                    Text(Channel.decibels(transitionLevel))
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(.red)
                        .frame(width: 58, alignment: .trailing)
                } else {
                    Text(Channel.decibels(displayedLevel))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 58, alignment: .trailing)
                }
            }
            HStack {
                Text("Transition").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { cue.transitionSeconds },
                    set: { value in
                        store.updateLiveInput(sceneID: sceneID, subsceneID: subsceneID, input: input) {
                            $0.transitionSeconds = value
                        }
                    }
                ), in: 0...30, step: 1)
                Text(String(format: "%.1f s", cue.transitionSeconds))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 46, alignment: .trailing)
            }
            }
            .frame(minWidth: 300, maxWidth: .infinity)
            if cue.enabled {
            StripSection(title: "ROUTAGE · SORTIES 1–4") {
                HStack(spacing: 4) {
                    ForEach(0..<4) { output in
                        SendRoutingKnob(
                            send: cue.jackSends?[output] ?? store.session.channels[input].jackSends[output],
                            output: output, routingLocked: store.session.routingLocked,
                            setLevel: { value in
                                store.updateLiveSend(sceneID: sceneID, subsceneID: subsceneID,
                                                     input: input, output: output) { $0.level = value }
                            },
                            toggle: {
                                store.updateLiveSend(sceneID: sceneID, subsceneID: subsceneID,
                                                     input: input, output: output) { $0.enabled.toggle() }
                            }
                        )
                    }
                }
            }
            .frame(width: 220)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, cue.enabled ? 8 : 3)
        .background(cue.enabled ? Color.green.opacity(0.07) : Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 7))
    }

    private func syncNameDrafts() {
        sceneName = scene?.name ?? ""
        subsceneName = subscene?.name ?? ""
        syncDurationDraft()
    }

    private func syncDurationDraft() {
        durationDraft = durationLabel(subscene?.durationSeconds ?? 0)
    }

    private func durationLabel(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct ChannelStrip: View {
    @EnvironmentObject var store: MixerStore
    let index: Int
    let dragContext: UUID
    private var channel: Channel { store.session.channels[index] }
    private var selected: Bool { store.bank.target(index % 8) == .input(index) }
    private var sceneTarget: Double? { store.liveTargetLevel(for: index) }
    private var isMuted: Bool { channel.muted || store.session.muteAll }

    var body: some View {
        VStack(spacing: 12) {
            InputStripDragHandle(context: dragContext, source: index, input: index, isConsole: true)
            TextField("Nom", text: Binding(
                get: { channel.name },
                set: { value in store.changeChannel(index) { $0.name = value } }
            )).textFieldStyle(.plain).font(.title3.bold())
            Text("\(channel.jackSends.prefix(ES9.audioJackCount).filter(\.enabled).count) envoi(s) jack")
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
                get: { sceneTarget ?? channel.level },
                set: { value in
                    store.changeChannel(index) { $0.level = value }
                }
            ), tint: .cyan)
            Text(Channel.decibels(sceneTarget ?? channel.level)).font(.system(.caption, design: .monospaced))
            StripButtons(muted: isMuted, soloed: channel.soloed,
                         mute: { store.changeChannel(index) { $0.muted.toggle() } },
                         solo: { store.changeChannel(index) { $0.soloed.toggle() } })
            Text(store.session.inputIsAudible(index) ? " "
                 : store.session.muteAll ? "MUTE GÉNÉRAL" : (channel.muted ? "Muet" : "Exclue par SOLO"))
                .font(.caption2.bold())
                .foregroundStyle(store.session.muteAll || channel.muted ? .white : .secondary)
        }
        .padding(12)
        .frame(width: 122, height: 430)
        .background(isMuted ? Color.red.opacity(0.88)
                    : channel.soloed ? Color.yellow.opacity(0.78) : Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            isMuted ? Color.red
                : channel.soloed ? Color.yellow
                : selected ? Color.cyan.opacity(0.55) : .clear,
            lineWidth: isMuted || channel.soloed ? 2 : 1
        ))
    }
}

struct InputStripDrag: Codable, Transferable {
    let context: UUID
    let source: Int
    let isConsole: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.es9mixer.input-strip"))
    }
}

struct InputStripDragHandle: View {
    let context: UUID
    let source: Int
    let input: Int
    let isConsole: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d", input + 1))
                .font(.system(.headline, design: .monospaced))
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
        }
            .foregroundStyle(.cyan)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .draggable(InputStripDrag(context: context, source: source, isConsole: isConsole)) {
                Label("Entrée \(input + 1)", systemImage: "slider.vertical.3")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Déplacer l’entrée \(input + 1)")
            .help("Glisser ce bandeau sur un autre bloc pour déplacer l’entrée à sa position.")
    }
}

struct InputStripDropTarget: ViewModifier {
    @EnvironmentObject var store: MixerStore
    @State private var targeted = false
    let context: UUID
    let source: Int
    let isConsole: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.cyan, lineWidth: targeted && !store.busy ? 3 : 0)
                    .allowsHitTesting(false)
            }
            .dropDestination(for: InputStripDrag.self) { items, _ in
                guard !store.busy, items.count == 1, let item = items.first,
                      item.context == context, item.isConsole == isConsole else { return false }
                if isConsole {
                    guard let from = store.session.consoleInputOrder.firstIndex(of: item.source),
                          let to = store.session.consoleInputOrder.firstIndex(of: source) else { return false }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.moveConsoleInput(from: from, to: to)
                    }
                } else {
                    guard store.session.stripInputs.indices.contains(item.source),
                          store.session.stripInputs.indices.contains(source) else { return false }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.moveStripInput(from: item.source, to: source)
                    }
                }
                return true
            } isTargeted: { targeted = $0 }
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
            Text("Général : 2 sorties internes ; casque : 2 de plus. « Jacks uniquement » permet les 91 liaisons audio simultanées. OUT 8 est réservée au GATE Pamela.")
                .font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("ENTRÉE").frame(width: 160, alignment: .leading)
                    Text("GÉNÉRAL").frame(width: 80)
                    ForEach(0..<ES9.audioJackCount, id: \.self) { output in
                        VStack {
                            Text("OUT \(output + 1)").foregroundStyle(.orange)
                            Text(store.session.outputs[output].name).lineLimit(1)
                        }.frame(width: 108)
                    }
                }.font(.caption.bold())
                ForEach(Array(0..<ES9.mixerInputCount), id: \.self) { input in
                    GridRow {
                        VStack(alignment: .leading) {
                            Text("\(input + 1) · \(store.session.channels[input].name)")
                                .lineLimit(1).font(.callout.bold())
                            Text(Channel.decibels(store.session.channels[input].level))
                                .font(.caption).foregroundStyle(.secondary)
                            if !store.session.inputIsAudible(input) {
                                Text(store.session.muteAll ? "MUTE GÉNÉRAL" : store.session.channels[input].muted ? "Muette" : "Exclue par SOLO")
                                    .font(.caption2.bold())
                                    .foregroundStyle(store.session.muteAll || store.session.channels[input].muted ? .red : .orange)
                            }
                        }.frame(width: 160, alignment: .leading)
                        Toggle("Général entrée \(input + 1)", isOn: Binding(
                            get: { store.session.channels[input].mainEnabled },
                            set: { value in store.changeChannel(input) { $0.mainEnabled = value } }
                        )).labelsHidden().toggleStyle(.checkbox)
                            .frame(width: 80).disabled(store.session.routingLocked)
                        ForEach(0..<ES9.audioJackCount, id: \.self) { output in
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
    var accessibilityPrefix = "strip"

    var body: some View {
        HStack(spacing: 4) {
            Button("MUTE", action: mute).tint(muted ? .red : .gray)
                .accessibilityLabel("Mute").accessibilityValue(muted ? "Activé" : "Désactivé")
                .accessibilityIdentifier("\(accessibilityPrefix)-mute")
                #if MIXER_UI_TESTS
                .background(MixerUITestButtonProbe(identifier: "\(accessibilityPrefix)-mute"))
                #endif
            Button("SOLO", action: solo).tint(soloed ? .yellow : .gray)
                .accessibilityLabel("Solo").accessibilityValue(soloed ? "Activé" : "Désactivé")
                .accessibilityIdentifier("\(accessibilityPrefix)-solo")
                #if MIXER_UI_TESTS
                .background(MixerUITestButtonProbe(identifier: "\(accessibilityPrefix)-solo"))
                #endif
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct VerticalFader: View {
    @Binding var value: Double
    var tint: Color = .cyan
    var isInteractive = true

    init(value: Binding<Double>, tint: Color = .cyan, isInteractive: Bool = true) {
        _value = value
        self.tint = tint
        self.isInteractive = isInteractive
    }

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
                .allowsHitTesting(isInteractive)
        }
        .frame(width: 50, height: 178)
    }
}

struct LiveHorizontalFader: View {
    @Binding var value: Double
    var transitionValue: Double?
    var tint: Color = .cyan
    var isInteractive = true

    var body: some View {
        ZStack(alignment: .leading) {
            Slider(value: $value, in: 0...1)
                .tint(tint)
                .allowsHitTesting(isInteractive)
            if let transitionValue {
                GeometryReader { geometry in
                    let inset: CGFloat = 8
                    let travel = max(0, geometry.size.width - 2 * inset)
                    let clamped = min(1, max(0, transitionValue))
                    let xPos = inset + travel * clamped

                    // Red level progress bar under track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.35))
                        .frame(width: max(0, xPos), height: 6)
                        .position(x: xPos / 2, y: geometry.size.height / 2)

                    // Red temporary fader cursor
                    ZStack {
                        Capsule()
                            .fill(Color.red)
                            .frame(width: 6, height: 20)
                        Capsule()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            .frame(width: 6, height: 20)
                    }
                    .shadow(color: Color.red.opacity(0.8), radius: 3, x: 0, y: 0)
                    .position(x: xPos, y: geometry.size.height / 2)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(height: 22)
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
            Text("Choisissez un template User du Novation. Cliquez sur Apprendre, puis bougez le contrôle ou pressez le bouton correspondant. Utilisez des CC absolus et des boutons momentanés (127 à l’appui, 0 au relâchement). Pour le SOLO, apprenez les huit boutons dans la section Solo ci-dessous. « Sous-scène suivante » est un mapping séparé des boutons de banque précédent/suivant.")
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
            Text("Trois banques : entrées 1–8, entrées 9–13, sorties 1–7. Les contrôles 6–8 de la banque entrées 9–13 et le huitième contrôle de la banque sorties sont inactifs. OUT 8 est le GATE Pamela. Gain linéaire de 40 % à 100 % de la course MIDI. Général et casque ont des CC indépendants.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 850, height: 670)
        .disabled(store.busy)
    }
}
