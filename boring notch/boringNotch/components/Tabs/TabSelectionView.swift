//
//  TabSelectionView.swift
//  boringNotch
//
//  ⌘ held → badges ⌘1 ⌘2 ⌘3 on Home / Shelf / Clipboard (product order).
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
    /// Fixed product index for ⌘N (1-based).
    let commandNumber: Int
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home, commandNumber: 1),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf, commandNumber: 2),
    TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard, commandNumber: 3)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var keyboard = ClipboardKeyboardMonitor.shared
    @Namespace var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(
                    label: tab.label,
                    icon: tab.icon,
                    selected: coordinator.currentView == tab.view,
                    commandIndex: keyboard.isCommandHeld ? tab.commandNumber : nil
                ) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                // Extra top room so ⌘ badge isn’t clipped
                .padding(.top, keyboard.isCommandHeld ? 10 : 0)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
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
            }
        }
        // No outer clipShape — ⌘ badges sit above the bar and would be clipped.
        .animation(.easeInOut(duration: 0.12), value: keyboard.isCommandHeld)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
