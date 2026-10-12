import AppKit
import SwiftUI
import MixerCore

/// Vertical analog-style channel strip for a single input.
struct InputStripView: View {
    @EnvironmentObject var store: MixerStore
    let slot: Int
    let dragContext: UUID
    private var index: Int { store.session.stripInputs[slot] }
    private var channel: Channel { store.session.channels[index] }
    private var isMuted: Bool { channel.muted || store.session.muteAll }
    private static let bandNames = ["LOW", "MID", "HIGH"]

    var body: some View {
        VStack(spacing: 10) {
            header
            StripSection(title: "GAIN") {
                RotaryKnob(value: trimBinding, range: Channel.trimLimits, defaultValue: 0, origin: 0,
                           tint: .red, size: 58, label: "TRIM", text: Channel.signedDecibels)
                    .help("Gain numérique appliqué avant le mélangeur (l’ES-9 n’a pas de préampli réglable). Au-delà de 0 dB, risque de saturation. Glisser · ⌥ fin · double-clic : 0 dB.")
            }
            StripSection(title: "ÉGALISEUR", trailing: {
                Button(channel.eq.enabled ? "EQ IN" : "EQ OUT") {
                    store.changeChannel(index) { $0.eq.enabled.toggle() }
                }
                .buttonStyle(.borderedProminent)
                .tint(channel.eq.enabled ? .green : .gray)
                .controlSize(.mini)
                .accessibilityLabel("Égaliseur")
                .accessibilityValue(channel.eq.enabled ? "Activé" : "Contourné")
            }) {
                VStack(spacing: 8) {
                    ForEach([2, 1, 0], id: \.self) { band in
                        bandRow(band)
                        if band != 0 { Divider().opacity(0.4) }
                    }
                }
                .opacity(channel.eq.enabled ? 1 : 0.45)
            }
            StripSection(title: "ROUTAGE · SORTIES 1–4") {
                HStack(spacing: 4) {
                    ForEach(0..<4) { sendKnob($0) }
                }
            }
            StripSection(title: "VOLUME") {
                VStack(spacing: 6) {
                    let sceneTarget = store.liveTargetLevel(for: index)
                    VerticalFader(value: Binding(
                        get: { sceneTarget ?? channel.level },
                        set: { value in
                            store.changeChannel(index) { $0.level = value }
                        }
                    ), tint: .cyan)
                    Text(Channel.decibels(sceneTarget ?? channel.level))
                        .font(.system(.caption, design: .monospaced))
                }
            }
            StripButtons(muted: isMuted, soloed: channel.soloed,
                         mute: { store.changeChannel(index) { $0.muted.toggle() } },
                         solo: { store.changeChannel(index) { $0.soloed.toggle() } })
                .controlSize(.regular)
            Text(store.session.inputIsAudible(index) ? " "
                 : store.session.muteAll ? "MUTE GÉNÉRAL" : (channel.muted ? "Muet" : "Exclue par SOLO"))
                .font(.caption2.bold())
                .foregroundStyle(store.session.muteAll || channel.muted ? .white : .secondary)
        }
        .padding(12)
        .frame(width: 236)
        .background(isMuted ? Color.red.opacity(0.5)
                    : channel.soloed ? Color.yellow.opacity(0.4) : Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            isMuted ? Color.red : channel.soloed ? Color.yellow : Color.cyan.opacity(0.35),
            lineWidth: isMuted || channel.soloed ? 2 : 1
        ))
    }

    private var header: some View {
        VStack(spacing: 6) {
            InputStripDragHandle(context: dragContext, source: slot, input: index, isConsole: false)
            Picker("Entrée", selection: Binding(
                get: { store.session.stripInputs[slot] },
                set: { store.setStripInput(slot, input: $0) }
            )) {
                ForEach(Array(0..<ES9.mixerInputCount), id: \.self) {
                    Text("\($0 + 1) · \(store.session.channels[$0].name)").tag($0)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .help("Choisir l’entrée affichée dans cette tranche.")
            TextField("Nom", text: Binding(
                get: { channel.name },
                set: { value in store.changeChannel(index) { $0.name = value } }
            )).textFieldStyle(.plain).font(.title3.bold())
        }
    }

    private var trimBinding: Binding<Double> {
        Binding(get: { channel.trim },
                set: { value in store.changeChannel(index) { $0.trim = value } })
    }

    private func bandBinding(_ band: Int, _ key: WritableKeyPath<EQBand, Double>) -> Binding<Double> {
        Binding(get: { channel.eq.bands[band][keyPath: key] },
                set: { value in store.changeChannel(index) { $0.eq.bands[band][keyPath: key] = value } })
    }

    private func bandRow(_ band: Int) -> some View {
        let settings = channel.eq.bands[band]
        let shelf: EQShape? = band == 0 ? .lowShelf : band == 2 ? .highShelf : nil
        return HStack(alignment: .top, spacing: 2) {
            VStack(spacing: 4) {
                Text(Self.bandNames[band]).font(.caption.bold()).foregroundStyle(.green)
                if let shelf {
                    Button(settings.shape == shelf ? "SHELF" : "BELL") {
                        store.changeChannel(index) {
                            let next: EQShape = $0.eq.bands[band].shape == shelf ? .peak : shelf
                            $0.eq.bands[band].shape = next
                            $0.eq.bands[band].gain = min($0.eq.bands[band].gain, $0.eq.bands[band].maximumGain)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Basculer entre filtre en cloche (avec Q) et filtre en plateau (Q inactif).")
                }
            }
            .frame(width: 46)
            RotaryKnob(value: bandBinding(band, \.frequency), range: ChannelEQ.bandFrequencies[band],
                       logarithmic: true, defaultValue: ChannelEQ().bands[band].frequency,
                       tint: .green, label: "FREQ", text: Self.frequency)
            RotaryKnob(value: bandBinding(band, \.q), range: 0.3...10, logarithmic: true,
                       defaultValue: 0.707, tint: .green, label: "Q", text: { String(format: "%.2f", $0) })
                .disabled(!settings.shape.usesQ)
                .opacity(settings.shape.usesQ ? 1 : 0.35)
            RotaryKnob(value: bandBinding(band, \.gain), range: EQBand.gainLimits.lowerBound...settings.maximumGain,
                       defaultValue: 0, origin: 0, tint: .green, label: "dB",
                       text: { String(format: "%+.1f", $0) })
        }
    }

    private func sendKnob(_ output: Int) -> some View {
        let send = channel.jackSends[output]
        return SendRoutingKnob(send: send, output: output, routingLocked: store.session.routingLocked,
                               controlsEnabled: !store.liveSceneActive,
                               setLevel: { value in store.changeChannel(index) { $0.jackSends[output].level = value } },
                               toggle: { store.changeChannel(index) { $0.jackSends[output].enabled.toggle() } })
    }

    private static func frequency(_ hertz: Double) -> String {
        hertz < 1000 ? String(format: "%.0f Hz", hertz) : String(format: "%.1f k", hertz / 1000)
    }
}

struct SendRoutingKnob: View {
    let send: JackSend
    let output: Int
    let routingLocked: Bool
    var controlsEnabled = true
    let setLevel: (Double) -> Void
    let toggle: () -> Void

    var body: some View {
        return VStack(spacing: 4) {
            RotaryKnob(value: Binding(
                get: { send.level },
                set: setLevel
            ), range: 0...1, defaultValue: 1, tint: .orange, size: 40, label: "OUT \(output + 1)",
                       text: { $0 == 0 ? "−∞" : String(format: "%.0f dB", -60 + $0 * 60) })
                .opacity(send.enabled ? 1 : 0.4)
                .allowsHitTesting(controlsEnabled)
            Button(send.enabled ? "ON" : "OFF", action: toggle)
            .buttonStyle(.borderedProminent)
            .tint(send.enabled ? .orange : .gray)
            .controlSize(.mini)
            .disabled(routingLocked || !controlsEnabled)
            .accessibilityLabel("Envoi vers sortie \(output + 1)")
            .accessibilityValue(send.enabled ? "Activé" : "Désactivé")
            .help(routingLocked
                  ? "Décocher « Routage verrouillé » pour activer ou couper cet envoi."
                  : "Activer ou couper l’envoi vers la sortie jack \(output + 1).")
        }
        .frame(maxWidth: .infinity)
    }

}

struct StripSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension StripSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// Rotary control: drag vertically (or horizontally), ⌥ for fine adjustment, double-click to reset.
struct RotaryKnob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var logarithmic = false
    var defaultValue: Double
    /// Value from which the arc is drawn; nil draws from the minimum.
    var origin: Double?
    var tint: Color = .cyan
    var size: CGFloat = 38
    let label: String
    let text: (Double) -> String
    @State private var dragStart: Double?
    @Environment(\.isEnabled) private var isEnabled

    private func position(_ value: Double) -> Double {
        let lower = range.lowerBound, upper = range.upperBound
        let raw = logarithmic ? log(value / lower) / log(upper / lower) : (value - lower) / (upper - lower)
        return min(1, max(0, raw))
    }

    private func value(at position: Double) -> Double {
        let lower = range.lowerBound, upper = range.upperBound
        let clamped = min(1, max(0, position))
        return logarithmic ? lower * pow(upper / lower, clamped) : lower + clamped * (upper - lower)
    }

    private func adjust(by delta: Double) {
        value = value(at: position(value) + delta)
    }

    var body: some View {
        let current = position(value)
        let start = origin.map(position) ?? 0
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0.75 * min(start, current), to: 0.75 * max(start, current))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.16)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                    .padding(size * 0.16)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: size * 0.22)
                    .offset(y: -size * 0.2)
                    .rotationEffect(.degrees(-135 + 270 * current))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    if dragStart == nil { dragStart = position(value) }
                    let fine = NSEvent.modifierFlags.contains(.option) ? 0.15 : 1
                    let travel = Double(gesture.translation.width - gesture.translation.height)
                    value = value(at: (dragStart ?? 0) + travel / 180 * fine)
                }
                .onEnded { _ in dragStart = nil })
            .onTapGesture(count: 2) { value = defaultValue }
            Text(text(value))
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: size + 6)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: 0.02)
            case .decrement: adjust(by: -0.02)
            @unknown default: break
            }
        }
        .help("Glisser vers le haut ou la droite · ⌥ réglage fin · double-clic : valeur par défaut")
    }
}

/// Compact output section for the Strip view: rotary level knobs instead of faders.
struct StripOutputsView: View {
    @EnvironmentObject var store: MixerStore

    var body: some View {
        VStack(spacing: 8) {
            Text("SORTIES · GÉNÉRAL · CASQUE").font(.headline)
            ForEach(0..<4) { outputCard($0) }
            masterCard
            headphonesCard
        }
        .frame(width: 236)
    }

    private func outputCard(_ index: Int) -> some View {
        let output = store.session.outputs[index]
        return card(muted: output.muted, soloed: output.soloed, tint: .orange) {
            RotaryKnob(value: Binding(
                get: { output.level },
                set: { value in store.changeOutput(index) { $0.level = value } }
            ), range: 0...1, defaultValue: 1, tint: .orange, size: 50, label: "NIVEAU", text: Channel.decibels)
            VStack(alignment: .leading, spacing: 4) {
                Text("OUT \(index + 1)").font(.headline).foregroundStyle(.orange)
                TextField("Nom", text: Binding(
                    get: { output.name }, set: { value in store.changeOutput(index) { $0.name = value } }
                )).textFieldStyle(.plain).font(.callout.bold())
                StripButtons(muted: output.muted, soloed: output.soloed,
                             mute: { store.changeOutput(index) { $0.muted.toggle() } },
                             solo: { store.changeOutput(index) { $0.soloed.toggle() } })
                    .controlSize(.mini)
                Text(store.session.outputIsAudible(index)
                     ? "\(store.session.channels.filter { $0.jackSends[index].enabled }.count) entrée(s)"
                     : (output.muted ? "Muette" : "Exclue par SOLO"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var masterCard: some View {
        let muted = store.session.masterMuted
        let isMuteAll = store.session.muteAll
        return card(muted: muted || isMuteAll, soloed: false, tint: .cyan) {
            RotaryKnob(value: Binding(get: { store.session.master }, set: store.setMaster),
                       range: 0...1, defaultValue: 0.8, tint: .cyan, size: 50, label: "NIVEAU",
                       text: Channel.decibels)
            VStack(alignment: .leading, spacing: 4) {
                Text("GÉNÉRAL").font(.headline).foregroundStyle(.cyan)
                Text(isMuteAll ? "MUTE GÉNÉRAL" : "Stéréo L / R")
                    .font(.caption.bold())
                    .foregroundStyle(isMuteAll ? .red : .secondary)
                Button("MUTE", action: store.toggleMasterMute)
                    .tint(muted ? .red : .gray)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .accessibilityLabel("Mute général")
                    .accessibilityValue(muted ? "Activé" : "Désactivé")
                    .help("Couper uniquement le mix analogique du général. Casque, jacks et USB direct inchangés.")
            }
        }
    }

    private var headphonesCard: some View {
        let enabled = store.session.headphonesEnabled
        return card(muted: false, soloed: false, tint: .cyan) {
            RotaryKnob(value: Binding(get: { store.session.headphonesLevel }, set: store.setHeadphonesLevel),
                       range: 0...1, defaultValue: 42.0 / 72.0, tint: .cyan, size: 50, label: "NIVEAU",
                       text: Session.headphonesDecibels)
                .disabled(!enabled)
            VStack(alignment: .leading, spacing: 4) {
                Text("CASQUE").font(.headline).foregroundStyle(.cyan)
                Toggle("Écoute", isOn: Binding(
                    get: { store.session.headphonesEnabled }, set: store.setHeadphonesEnabled
                ))
                Text("Jusqu’à +12 dB. Baisser le volume physique avant d’activer l’écoute.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<Content: View>(muted: Bool, soloed: Bool, tint: Color,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(muted ? Color.red.opacity(0.5)
                        : soloed ? Color.yellow.opacity(0.4) : tint.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                muted ? Color.red : soloed ? Color.yellow : .clear, lineWidth: 2))
    }
}
