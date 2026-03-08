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
        }
    }
}
