//
//  WatchApp.swift
//  WatchApp
//

import SwiftUI

@main
struct WatchApp: App {
    @StateObject private var manager = TimeEntryManager()
    @State private var selectedWatch: Watch? = nil

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(selectedWatch: $selectedWatch)
                    .tabItem { Label("Home", systemImage: "house") }

                StatisticsView(selectedWatch: $selectedWatch)
                    .tabItem { Label("Statistics", systemImage: "chart.bar") }

                WatchesView(selectedWatch: $selectedWatch)
                    .tabItem { Label("Watches", systemImage: "watchface.applewatch.case") }

                FunctionsView(selectedWatch: $selectedWatch)
                    .tabItem { Label("Functions", systemImage: "gearshape") }
            }
            .environmentObject(manager)
            .onAppear { autoSelectIfSingle() }
            .onChange(of: manager.watches) { autoSelectIfSingle() }
        }
    }

    private func autoSelectIfSingle() {
        if manager.watches.count == 1 {
            selectedWatch = manager.watches[0]
        } else if let current = selectedWatch,
                  !manager.watches.contains(where: { $0.id == current.id }) {
            // Selected watch was deleted — clear selection
            selectedWatch = nil
        }
    }
}
