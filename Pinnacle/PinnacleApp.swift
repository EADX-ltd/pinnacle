//
//  PinnacleApp.swift
//  Pinnacle
//
//  Created by Zhivko Poroyliev on 31.03.26.
//

import SwiftUI

@main
struct PinnacleApp: App {
    @MainActor
    private let container = AppContainer.live

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
        }
    }
}
