import HakenCore
import SwiftUI

private enum HakenSection: String, CaseIterable, Identifiable {
  case slots = "Slots"
  case settings = "Settings"
  case diagnostics = "Diagnostics"
  var id: Self { self }
  var icon: String {
    switch self {
    case .slots: "square.grid.2x2"
    case .settings: "gearshape"
    case .diagnostics: "waveform.path.ecg"
    }
  }
}

struct HakenRootView: View {
  @ObservedObject var model: HakenAppModel
  @State private var section: HakenSection? = .slots

  var body: some View {
    NavigationSplitView {
      List(HakenSection.allCases, selection: $section) { item in
        Label(item.rawValue, systemImage: item.icon).tag(item)
      }
      .navigationTitle("Haken")
    } detail: {
      switch section ?? .slots {
      case .slots: SlotsView(model: model)
      case .settings: SettingsView(model: model)
      case .diagnostics: DiagnosticsView(model: model)
      }
    }
    .frame(minWidth: 760, minHeight: 520)
    .onAppear { model.refreshEnvironment() }
  }
}

private struct SlotsView: View {
  @ObservedObject var model: HakenAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading) {
          Text("Haken Slots").font(.title2.bold())
          Text(
            "Assigned slots reserve the selected shortcuts. Empty slots stay available to the foreground app."
          )
          .foregroundStyle(.secondary)
        }
        Spacer()
        if model.accessibilityGranted {
          Button("Refresh Chrome Profiles") { model.refreshChromeProfiles() }
        } else {
          Button("Enable Chrome Profiles…") { model.requestAccessibility() }
        }
      }
      if !model.accessibilityGranted {
        PermissionCallout(model: model)
      }
      List(model.configuration.slots) { slot in SlotRow(slot: slot, model: model) }
    }
    .padding()
  }
}

private struct SlotRow: View {
  let slot: HakenSlot
  @ObservedObject var model: HakenAppModel

  var body: some View {
    HStack(spacing: 14) {
      Text(model.configuration.shortcutStyle.displayValue(for: slot.id))
        .font(.system(.body, design: .monospaced)).frame(width: 52, alignment: .leading)
      Image(systemName: icon).frame(width: 20)
      VStack(alignment: .leading) {
        Text(slot.target?.displayName ?? "Not assigned")
        if let error = model.hotKeyErrors[slot.id] {
          Text(error.userMessage).font(.caption).foregroundStyle(.red)
        }
      }
      Spacer()
      Menu(slot.target == nil ? "Choose…" : "Change…") {
        Menu("Application") {
          ForEach(model.applicationCandidates) { app in
            Button(app.displayName) { model.assign(.application(app.target()), to: slot.id) }
          }
          Divider()
          Button("Add Application…") { model.chooseApplication(for: slot.id) }
        }
        Menu("Google Chrome Profile") {
          if model.chromeProfiles.isEmpty {
            Text(
              model.accessibilityGranted
                ? "Refresh Chrome Profiles first" : "Accessibility permission required")
          } else {
            ForEach(model.chromeProfiles) { profile in
              Button(profile.name) {
                model.assign(
                  .chromeProfile(
                    ChromeProfileTarget(
                      profileName: profile.name, lastSeenChromeVersion: profile.chromeVersion)),
                  to: slot.id)
              }
            }
          }
        }
        if slot.target != nil {
          Divider()
          Button("Unassign", role: .destructive) { model.assign(nil, to: slot.id) }
        }
      }
      Button("Test") { model.test(slot: slot.id) }.disabled(slot.target == nil)
    }
    .padding(.vertical, 3)
  }

  private var icon: String {
    switch slot.target {
    case .application: "app.fill"
    case .chromeProfile: "person.crop.circle"
    case nil: "minus.circle"
    }
  }
}

private struct SettingsView: View {
  @ObservedObject var model: HakenAppModel

  var body: some View {
    Form {
      Section("Haken") {
        Toggle(
          "Enable Haken",
          isOn: Binding(
            get: { model.configuration.isEnabled }, set: { model.setEnabled($0) }
          ))
        Toggle(
          "Launch at Login",
          isOn: Binding(
            get: { model.configuration.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
          ))
        Picker(
          "Shortcut keys",
          selection: Binding(
            get: { model.configuration.shortcutStyle }, set: { model.setShortcutStyle($0) }
          )
        ) {
          ForEach(ShortcutStyle.allCases) { style in
            Text(style.displayName).tag(style)
          }
        }
        Text("The selected pattern applies to all 10 slots.")
          .font(.caption).foregroundStyle(.secondary)
        Picker(
          "Switch feedback",
          selection: Binding(
            get: { model.configuration.feedbackMode }, set: { model.setFeedbackMode($0) }
          )
        ) {
          Text("Menu Bar").tag(FeedbackMode.menuBar)
          Text("HUD").tag(FeedbackMode.hud)
        }
        Toggle(
          "Developer Mode",
          isOn: Binding(
            get: { model.configuration.developerMode }, set: { model.setDeveloperMode($0) }
          ))
      }
      Section("Accessibility") {
        if model.usesChromeProfiles || model.accessibilityGranted {
          Text(
            model.accessibilityGranted
              ? "Granted — used only to choose Chrome profiles."
              : "Required only for Chrome profile switching.")
          HStack {
            Button("Request Permission") { model.requestAccessibility() }
            Button("Open System Settings") { model.openAccessibilitySettings() }
            Button("Recheck") { model.refreshEnvironment() }
          }
        } else {
          Text(
            "Not required for Application targets. Choose a Chrome profile only when you want to grant this permission."
          )
          .foregroundStyle(.secondary)
          HStack {
            Button("Enable Chrome Profiles…") { model.requestAccessibility() }
            Button("Open System Settings") { model.openAccessibilitySettings() }
          }
        }
      }
      if model.configurationError != nil {
        Section("Configuration recovery") {
          Text(HakenError.configurationCorrupt.userMessage).foregroundStyle(.red)
          Button("Reset Settings") { model.resetCorruptConfiguration() }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Settings")
  }
}

private struct DiagnosticsView: View {
  @ObservedObject var model: HakenAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Diagnostics").font(.title2.bold())
        Spacer()
        Button("Copy Diagnostics") { model.copyDiagnostics() }
      }
      Text(
        "Copy Diagnostics excludes Chrome profile names, application paths, URLs, tab titles, and key input history."
      )
      .foregroundStyle(.secondary)
      Text(
        "Accessibility: \(model.accessibilityGranted ? "Granted" : "Not granted") · Slots: \(model.assignedSlots) / 10"
      )
      List(model.recentResults) { result in
        VStack(alignment: .leading) {
          Text(result.error?.userMessage ?? result.summary)
          Text(
            "\(result.slot.map { model.configuration.shortcutStyle.displayValue(for: $0) } ?? "Manual") · \(result.targetKind ?? "Haken") · \(result.durationMilliseconds) ms"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding()
  }
}

private struct PermissionCallout: View {
  @ObservedObject var model: HakenAppModel
  var body: some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      Text("Chrome profile switching requires Accessibility permission.")
      Spacer()
      Button("Grant Permission") { model.requestAccessibility() }
      Button("System Settings") { model.openAccessibilitySettings() }
    }
    .padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }
}
