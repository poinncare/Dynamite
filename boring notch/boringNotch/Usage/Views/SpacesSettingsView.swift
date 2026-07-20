//
//  SpacesSettingsView.swift
//  boringNotch — configure notch spaces order & icons
//

import Defaults
import SwiftUI

struct SpacesSettingsView: View {
    @ObservedObject private var spaces = SpacesStore.shared
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        Form {
            Section {
                Text(L("Drag rows to change the order of spaces in the notch. ⌘1–⌘N follow the visible order."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(spaces.orderedEntries) { entry in
                        SpaceSettingsRow(entry: entry)
                    }
                    .onMove { from, to in
                        spaces.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(minHeight: CGFloat(spaces.orderedEntries.count) * 44 + 8)
                .listStyle(.inset(alternatesRowBackgrounds: true))

                Button(L("Reset spaces to defaults")) {
                    spaces.resetToDefaults()
                }
            } header: {
                Text(L("Spaces"))
            } footer: {
                Text(L("Hidden spaces (feature toggles off) stay in order but are skipped by ⌘ shortcuts until re-enabled."))
                    .font(.caption)
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                    ForEach(SpaceIconKind.allCases) { icon in
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .frame(width: 48, height: 48)
                                SpaceIconView(icon: icon, size: 28)
                            }
                            Text(L(icon.displayNameKey))
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 72)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(L("Available icons"))
            } footer: {
                Text(L("Pick an icon per space in the list above. Mascot (red) and Mascot (white) are custom assets."))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .id(language.revision)
    }
}

private struct SpaceSettingsRow: View {
    let entry: SpaceConfigEntry
    @ObservedObject private var spaces = SpacesStore.shared
    @State private var showIconPicker = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .semibold))

            Button {
                showIconPicker = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                        .frame(width: 36, height: 36)
                    SpaceIconView(
                        icon: spaces.icon(for: entry.kind),
                        size: spaces.icon(for: entry.kind).prefersLargerTabSize ? 26 : 20,
                        selected: true
                    )
                }
            }
            .buttonStyle(.plain)
            .help(L("Change icon"))

            VStack(alignment: .leading, spacing: 2) {
                Text(L(entry.kind.defaultLabelKey))
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if !entry.kind.isFeatureEnabled {
                        Text(L("Hidden"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                    Text(L(spaces.icon(for: entry.kind).displayNameKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .popover(isPresented: $showIconPicker, arrowEdge: .trailing) {
            iconPicker
                .padding(12)
                .frame(width: 280)
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Choose icon"))
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(SpaceIconKind.allCases) { icon in
                    Button {
                        spaces.setIcon(icon, for: entry.kind)
                        showIconPicker = false
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(spaces.icon(for: entry.kind) == icon
                                      ? Color.accentColor.opacity(0.25)
                                      : Color(nsColor: .controlBackgroundColor))
                                .frame(width: 44, height: 44)
                            if spaces.icon(for: entry.kind) == icon {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .frame(width: 44, height: 44)
                            }
                            SpaceIconView(icon: icon, size: 22)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(L(icon.displayNameKey))
                }
            }
        }
    }
}
