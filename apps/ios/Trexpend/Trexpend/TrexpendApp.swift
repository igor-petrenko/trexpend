//
//  TrexpendApp.swift
//  Trexpend
//
//  Created by Igor P on 2026-10-06.
//

import SwiftUI

@main
struct TrexpendApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .preferredColorScheme(.light)
        }
    }
}
