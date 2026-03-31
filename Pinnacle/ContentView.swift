//
//  ContentView.swift
//  Pinnacle
//
//  Created by Zhivko Poroyliev on 31.03.26.
//

import SwiftUI

struct ContentView: View {
    let container: AppContainer

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Pinnacle")
        }
        .padding()
    }
}

#Preview {
    ContentView(container: .live)
}
