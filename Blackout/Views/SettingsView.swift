import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: BlackoutModel
    private var disconnectedCount: Int {
        model.settings.selectedDisplayUUIDs.subtracting(Set(model.displays.map(\.id))).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "display.2").font(.largeTitle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Blackout").font(.title.bold())
                    Text("Give your displays a break.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox("Displays") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.displays) { display in
                        Toggle(isOn: Binding(
                            get: { model.settings.selectedDisplayUUIDs.contains(display.id) },
                            set: { model.setSelected($0, display: display) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(display.name).fontWeight(.medium)
                                Text("\(display.pixelWidth) × \(display.pixelHeight) pixels · \(display.detail)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(!display.isEligible)
                    }
                    if !model.displays.contains(where: \.isEligible) {
                        Text("Connect a display in extended mode to get started.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if disconnectedCount > 0 {
                        HStack {
                            Text("\(disconnectedCount) disconnected selection(s) remembered.").font(.caption)
                            Spacer()
                            Button("Forget") { model.forgetDisconnectedSelections() }
                        }.foregroundStyle(.secondary)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            Picker("Appearance", selection: Binding(get: { model.settings.appearance }, set: { model.setAppearance($0) })) {
                ForEach(CoverAppearance.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if model.settings.appearance == .lockScreen {
                HStack {
                    Text("Wallpaper").fontWeight(.medium)
                    Spacer()
                    Text(model.settings.usesCustomWallpaper ? "Custom image" : "Built-in")
                        .foregroundStyle(.secondary)
                    Button("Choose Image…") { chooseWallpaper() }
                    if model.settings.usesCustomWallpaper {
                        Button("Reset") { model.useBuiltInWallpaper() }
                    }
                }
                if let error = model.wallpaperError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Global shortcut").fontWeight(.medium)
                    Spacer()
                    Text(model.registeredShortcut?.label ?? "Not registered").monospaced()
                    Button(model.isRecordingShortcut ? "Cancel" : "Record Shortcut…") {
                        model.shortcutError = nil
                        model.isRecordingShortcut.toggle()
                    }
                    Button("Reset") { model.setShortcut(.default) }
                }
                if model.isRecordingShortcut {
                    Text("Press Command or Control with a letter, number, or F1–F12. Escape cancels.")
                        .font(.caption).foregroundStyle(.secondary)
                    ShortcutRecorder(model: model).frame(height: 1)
                }
                Text("Uses physical US key positions. Some macOS shortcuts are reserved.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.shortcutError {
                    Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            if model.eligibleSelectedDisplays.contains(where: \.isPrimary) {
                Text(model.needsShortcutToCover
                     ? "Register a global shortcut before covering the primary display."
                     : "The menu and settings will be covered too. \(model.shortcutHint).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .center) {
                Text("Covers provide visual privacy only. They do not lock your Mac or power off displays.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 24)
                Button(model.isCovered ? "Uncover Displays" : "Cover Displays") { model.toggle() }
                    .buttonStyle(.borderedProminent).disabled(!model.canToggle)
            }
        }.padding(24).frame(width: 560)
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "Choose Lock Screen Wallpaper"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setWallpaper(from: url)
    }
}
