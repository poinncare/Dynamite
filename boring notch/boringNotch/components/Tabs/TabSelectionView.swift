//
//  TabSelectionView.swift
//  boringNotch
//
//  Spaces order + icons from SpacesStore.
//  ⌘ held → badges ⌘1…⌘N on visible spaces (dynamic order).
//  Long-press / drag to reorder spaces in the notch.
//

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var keyboard = ClipboardKeyboardMonitor.shared
    @ObservedObject private var spaces = SpacesStore.shared
    @Default(.boringShelf) private var boringShelf
    @Default(.clipboardEnabled) private var clipboardEnabled
    @Default(.usageTabEnabled) private var usageTabEnabled
    @ObservedObject private var language = LanguageManager.shared
    @Namespace var animation

    @State private var draggingKind: SpaceKind?
    @State private var dropTargetKind: SpaceKind?

    /// Visible spaces in configured order; command index = 1-based list position.
    private var visibleSpaces: [(entry: SpaceConfigEntry, commandNumber: Int)] {
        // Touch feature flags so SwiftUI refreshes when toggles change.
        _ = boringShelf
        _ = clipboardEnabled
        _ = usageTabEnabled
        return spaces.visibleEntries.enumerated().map { idx, entry in
            (entry, idx + 1)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleSpaces, id: \.entry.id) { item in
                let entry = item.entry
                let commandNumber = item.commandNumber
                TabButton(
                    label: L(entry.kind.defaultLabelKey),
                    icon: entry.icon,
                    selected: coordinator.currentView == entry.kind.notchView,
                    commandIndex: keyboard.isCommandHeld ? commandNumber : nil
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        coordinator.currentView = entry.kind.notchView
                    }
                }
                .frame(height: 26)
                .padding(.top, keyboard.isCommandHeld ? 10 : 0)
                .foregroundStyle(entry.kind.notchView == coordinator.currentView ? .white : .gray)
                .background {
                    if entry.kind.notchView == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
                .opacity(draggingKind == entry.kind ? 0.45 : 1)
                .overlay(alignment: .bottom) {
                    if dropTargetKind == entry.kind, draggingKind != entry.kind {
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                            .frame(height: 2)
                            .padding(.horizontal, 10)
                            .offset(y: 4)
                    }
                }
                .onDrag {
                    draggingKind = entry.kind
                    return NSItemProvider(object: entry.kind.rawValue as NSString)
                }
                .onDrop(of: [UTType.plainText, UTType.text], delegate: SpaceTabDropDelegate(
                    target: entry.kind,
                    dragging: $draggingKind,
                    dropTarget: $dropTargetKind,
                    onReorder: { dragged, before in
                        spaces.move(kind: dragged, before: before)
                        // Keep selection; renumber shortcuts via visibleEntries.
                    }
                ))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: keyboard.isCommandHeld)
        .animation(.easeInOut(duration: 0.15), value: spaces.visibleEntries.map(\.id))
        .id("\(language.revision)-\(spaces.visibleEntries.map { "\($0.kind.rawValue):\($0.icon.rawValue)" }.joined(separator: ","))")
        .onDrop(of: [UTType.plainText, UTType.text], isTargeted: nil) { providers in
            // Drop past the end → append
            guard let draggingKind else { return false }
            spaces.move(kind: draggingKind, before: nil)
            self.draggingKind = nil
            dropTargetKind = nil
            return true
        }
    }
}

// MARK: - Drop delegate

private struct SpaceTabDropDelegate: DropDelegate {
    let target: SpaceKind
    @Binding var dragging: SpaceKind?
    @Binding var dropTarget: SpaceKind?
    let onReorder: (SpaceKind, SpaceKind?) -> Void

    func dropEntered(info: DropInfo) {
        dropTarget = target
    }

    func dropExited(info: DropInfo) {
        if dropTarget == target {
            dropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            dropTarget = nil
        }
        guard let dragging else { return false }
        guard dragging != target else { return true }
        onReorder(dragging, target)
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
