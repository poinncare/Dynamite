//
//  TabButton.swift
//  boringNotch
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    /// 1-based ⌘N badge when command is held; nil to hide.
    var commandIndex: Int? = nil
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .top) {
                Image(systemName: icon)
                    .padding(.horizontal, 15)
                    .contentShape(Capsule())

                if let commandIndex, commandIndex >= 1, commandIndex <= 9 {
                    Text("⌘\(commandIndex)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        )
                        .offset(y: -10)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.12), value: commandIndex != nil)
        .help(label)
    }
}

#Preview {
    TabButton(label: "Home", icon: "house.fill", selected: true, commandIndex: 1) {
        print("Tapped")
    }
}
