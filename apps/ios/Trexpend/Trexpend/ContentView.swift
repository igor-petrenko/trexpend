//
//  ContentView.swift
//  Trexpend
//
//  Created by Igor P on 2026-10-06.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)

            Text("Trexpend")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.tint)

            Text("Personal finance, kept local.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.light)
}
