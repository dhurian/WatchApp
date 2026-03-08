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
                ContentView(manager: manager, selectedWatch: $selectedWatch)
                    .tabItem { Label("Home", systemImage: "house") }

                StatisticsView(manager: manager, selectedWatch: $selectedWatch)
                    .tabItem { Label("Statistics", systemImage: "chart.bar") }

                SyncView(manager: manager, selectedWatch: $selectedWatch)
                    .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

                WatchesView(manager: manager, selectedWatch: $selectedWatch)
                    .tabItem { Label("Watches", systemImage: "watchface.applewatch.case") }
            }
        }
    }
}
