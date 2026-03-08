//
//  ContentView.swift
//  WatchApp
//
//  Created by Dhurian Vitoldas on 07/03/2026.
//

import SwiftUI

// MARK: - Helpers

private func formattedDelta(from start: Date, to end: Date) -> String {
    let interval = end.timeIntervalSince(start)
    let sign = interval < 0 ? "-" : "+"
    let absInterval = abs(Int(interval))
    let minutes = (absInterval % 3600) / 60
    let seconds = absInterval % 60
    return "\(sign)\(String(format: "%02d min: %02d s", minutes, seconds))"
}

private func deviation(currentRecorded: Date, currentCustom: Date) -> String {
    let raw = currentCustom.timeIntervalSince(currentRecorded)
    let driftSeconds = abs(raw) < 1 ? 0.0 : raw
    if driftSeconds == 0 { return "  0 s" }
    let sign = driftSeconds >= 0 ? "+" : "-"
    return "\(sign)\(String(format: "%3.0f", abs(driftSeconds))) s"
}

private func isSyncEvent(_ entry: TimeEntry) -> Bool {
    guard let custom = entry.custom else { return false }
    return abs(custom.timeIntervalSince(entry.recorded)) < 1
}

// MARK: - ActiveSheet

enum ActiveSheet: Identifiable {
    case customTime
    case exporter(URL)

    var id: Int {
        switch self {
        case .customTime: return 0
        case .exporter: return 1
        }
    }
}

// MARK: - RootView

struct RootView: View {
    @StateObject private var manager = TimeEntryManager()
    @State private var selectedWatch: Watch? = nil

    var body: some View {
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

// MARK: - WatchesView

struct WatchesView: View {
    @ObservedObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?
    @State private var showingAddSheet = false
    @State private var editingWatch: Watch? = nil

    var body: some View {
        NavigationStack {
            Group {
                if manager.watches.isEmpty {
                    ContentUnavailableView("No Watches",
                                          systemImage: "watchface.applewatch.case",
                                          description: Text("Tap + to add your first watch."))
                } else {
                    List {
                        ForEach(manager.watches) { watch in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(watch.name).font(.headline)
                                    if !watch.brand.isEmpty {
                                        Text(watch.brand).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedWatch?.id == watch.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedWatch = watch
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if selectedWatch?.id == watch.id { selectedWatch = nil }
                                    manager.removeWatch(watch)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingWatch = watch
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Watches")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                WatchFormSheet(manager: manager, watch: nil)
            }
            .sheet(item: $editingWatch) { watch in
                WatchFormSheet(manager: manager, watch: watch)
            }
        }
    }
}

// MARK: - WatchFormSheet

struct WatchFormSheet: View {
    @ObservedObject var manager: TimeEntryManager
    var watch: Watch?

    @State private var name: String = ""
    @State private var brand: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Watch Details") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }
            }
            .navigationTitle(watch == nil ? "Add Watch" : "Edit Watch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmedName.isEmpty else { return }
                        if var existing = watch {
                            existing.name = trimmedName
                            existing.brand = brand.trimmingCharacters(in: .whitespaces)
                            manager.updateWatch(existing)
                        } else {
                            manager.addWatch(Watch(name: trimmedName, brand: brand.trimmingCharacters(in: .whitespaces)))
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = watch?.name ?? ""
                brand = watch?.brand ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - StatisticsView

struct StatisticsView: View {
    @ObservedObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?

    private var filteredEntries: [TimeEntry] {
        guard let watch = selectedWatch else { return [] }
        return manager.entries(for: watch).sorted { $0.recorded < $1.recorded }
    }

    private var latestEntry: TimeEntry? {
        filteredEntries.last { $0.custom != nil }
    }

    private var averageWindow: [TimeEntry] {
        let withCustom = filteredEntries.filter { $0.custom != nil }
        guard !withCustom.isEmpty else { return [] }
        guard let lastSyncIndex = withCustom.indices.last(where: { isSyncEvent(withCustom[$0]) }) else {
            return withCustom
        }
        var windowEnd = withCustom.count - 1
        if let nextSync = withCustom.indices.dropFirst(lastSyncIndex + 1).first(where: { isSyncEvent(withCustom[$0]) }) {
            windowEnd = nextSync - 1
        }
        return Array(withCustom[lastSyncIndex...windowEnd])
    }

    private struct DailyDeviation {
        let date: Date
        let averageSeconds: Double
        let sampleCount: Int
    }

    private var dailyDeviations: [DailyDeviation] {
        let window = averageWindow
        guard !window.isEmpty else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: window) { entry in
            calendar.startOfDay(for: entry.recorded)
        }
        return grouped.keys.sorted().map { day in
            let entries = grouped[day]!
            let drifts = entries.compactMap { entry -> Double? in
                guard let custom = entry.custom else { return nil }
                let raw = custom.timeIntervalSince(entry.recorded)
                return abs(raw) < 1 ? 0.0 : raw
            }
            let avg = drifts.isEmpty ? 0.0 : drifts.reduce(0, +) / Double(drifts.count)
            return DailyDeviation(date: day, averageSeconds: avg, sampleCount: entries.count)
        }
    }

    private var overallAveragePerDay: Double? {
        let days = dailyDeviations
        guard !days.isEmpty else { return nil }
        return days.map(\.averageSeconds).reduce(0, +) / Double(days.count)
    }

    private func formattedAvg(_ seconds: Double) -> String {
        let isZero = abs(seconds) < 0.05
        if isZero { return "  0.0 s" }
        let sign = seconds >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", abs(seconds))) s"
    }

    var body: some View {
        NavigationStack {
            if selectedWatch == nil {
                ContentUnavailableView("No Watch Selected",
                                       systemImage: "watchface.applewatch.case",
                                       description: Text("Select a watch in the Watches tab to view statistics."))
                .navigationTitle("Statistics")
            } else if filteredEntries.isEmpty {
                ContentUnavailableView("No Statistics Yet",
                                       systemImage: "chart.bar",
                                       description: Text("Record some times for \(selectedWatch!.name) to see statistics here."))
                .navigationTitle("Statistics")
            } else {
                List {
                    Section("Latest Measurement") {
                        if let entry = latestEntry, let custom = entry.custom {
                            HStack {
                                Label("Day", systemImage: "calendar")
                                Spacer()
                                Text(entry.recorded, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Label("Recorded", systemImage: "iphone")
                                Spacer()
                                Text(entry.recorded, format: .dateTime.hour().minute().second())
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            HStack {
                                Label("Watch", systemImage: "applewatch")
                                Spacer()
                                Text(custom, format: .dateTime.hour().minute().second())
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            HStack {
                                Label("Deviation", systemImage: "plusminus")
                                Spacer()
                                Text(deviation(currentRecorded: entry.recorded, currentCustom: custom))
                                    .monospacedDigit()
                                    .foregroundStyle(isSyncEvent(entry) ? .green : .secondary)
                            }
                        } else {
                            Text("No measurement with watch time yet.").foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        if dailyDeviations.isEmpty {
                            Text("Not enough data yet.").foregroundStyle(.secondary)
                        } else {
                            if let overall = overallAveragePerDay {
                                HStack {
                                    Label("Overall Avg / Day", systemImage: "function")
                                    Spacer()
                                    Text(formattedAvg(overall))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            ForEach(dailyDeviations, id: \.date) { day in
                                HStack {
                                    Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                    Spacer()
                                    Text(formattedAvg(day.averageSeconds))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                    Text("(\(day.sampleCount))")
                                        .font(.footnote).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text("Average Deviation Per Day Since Last Sync")
                    } footer: {
                        if let first = averageWindow.first {
                            Text("Window starts \(first.recorded, format: .dateTime.month().day().hour().minute())")
                                .font(.footnote)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(selectedWatch?.name ?? "Statistics")
            }
        }
    }
}

// MARK: - SyncView

struct SyncView: View {
    @ObservedObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?

    private var syncEvents: [TimeEntry] {
        guard let watch = selectedWatch else { return [] }
        return manager.entries(for: watch)
            .filter { isSyncEvent($0) }
            .sorted { $0.recorded > $1.recorded }
    }

    var body: some View {
        NavigationStack {
            if selectedWatch == nil {
                ContentUnavailableView("No Watch Selected",
                                       systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Select a watch in the Watches tab to view sync events."))
                .navigationTitle("Sync")
            } else if syncEvents.isEmpty {
                ContentUnavailableView("No Sync Events",
                                       systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("A sync event occurs when the watch time matches the recorded time exactly."))
                .navigationTitle("Sync")
            } else {
                List {
                    ForEach(syncEvents) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.recorded, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                                .font(.headline)
                            Text(entry.recorded, format: .dateTime.hour().minute().second())
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Sync – \(selectedWatch?.name ?? "")")
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {

    @ObservedObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?
    @State private var editingEntryID: UUID? = nil
    @State private var activeSheet: ActiveSheet? = nil
    @State private var customHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var customMinute: Int = Calendar.current.component(.minute, from: Date())
    @State private var customSecond: Int = Calendar.current.component(.second, from: Date())

    private var watchEntries: [TimeEntry] {
        guard let watch = selectedWatch else { return [] }
        return manager.entries(for: watch)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // Live Clock
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let now = context.date
                    HStack {
                        Image(systemName: "clock")
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                        Text(now, format: .dateTime.hour().minute().second())
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                // Watch picker banner
                if !manager.watches.isEmpty {
                    Menu {
                        ForEach(manager.watches) { watch in
                            Button {
                                selectedWatch = watch
                            } label: {
                                if selectedWatch?.id == watch.id {
                                    Label(watch.displayName, systemImage: "checkmark")
                                } else {
                                    Text(watch.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "watchface.applewatch.case")
                            Text(selectedWatch?.displayName ?? "Select a watch")
                                .font(.subheadline)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }

                // Export CSV
                Button {
                    if let url = manager.getCSVURL(for: selectedWatch) {
                        activeSheet = .exporter(url)
                    }
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                // Entries List
                if selectedWatch == nil {
                    ContentUnavailableView("No Watch Selected",
                                           systemImage: "watchface.applewatch.case",
                                           description: Text("Select or add a watch in the Watches tab."))
                        .padding(.top, 8)
                } else if watchEntries.isEmpty {
                    ContentUnavailableView("No recorded times yet",
                                           systemImage: "clock.badge.questionmark",
                                           description: Text("Tap the record button to save the current time."))
                        .padding(.top, 8)
                } else {
                    List {
                        Section {
                            ForEach(Array(watchEntries.enumerated()), id: \.element.id) { index, entry in
                                HStack(spacing: 12) {
                                    Text(entry.recorded, format: .dateTime.hour().minute().second())
                                        .monospacedDigit()
                                    Image(systemName: "arrow.left.and.right")
                                        .foregroundStyle(.secondary)
                                    if let custom = entry.custom {
                                        Text(custom, format: .dateTime.hour().minute().second())
                                            .monospacedDigit()
                                    } else {
                                        Text("Set…").foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Button {
                                        editingEntryID = entry.id
                                        let base = entry.custom ?? entry.recorded
                                        customHour = Calendar.current.component(.hour, from: base)
                                        customMinute = Calendar.current.component(.minute, from: base)
                                        customSecond = Calendar.current.component(.second, from: base)
                                        activeSheet = .customTime
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.borderless)
                                }

                                if let custom = entry.custom {
                                    let delta = deviation(currentRecorded: entry.recorded, currentCustom: custom)
                                    Text("Δ = \(delta)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .onDelete { indices in
                                indices.map { watchEntries[$0] }.forEach { manager.remove($0) }
                            }
                        } header: {
                            Text(Date.now, format: Date.FormatStyle().weekday(.wide).month(.abbreviated).day())
                        }
                    }
                    .listStyle(.insetGrouped)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(role: .destructive) {
                                if let watch = selectedWatch {
                                    manager.removeAll(for: watch.id)
                                }
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                            .disabled(watchEntries.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle(selectedWatch?.name ?? "Time Logger")
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    Button {
                        let now = Date()
                        let nextMinuteDate = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now
                        customHour = Calendar.current.component(.hour, from: nextMinuteDate)
                        customMinute = Calendar.current.component(.minute, from: nextMinuteDate)
                        customSecond = 0
                        editingEntryID = nil
                        activeSheet = .customTime
                    } label: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedWatch == nil)

                    Button {
                        guard let watch = selectedWatch else { return }
                        manager.add(TimeEntry(recorded: Date(), watchID: watch.id))
                    } label: {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(selectedWatch == nil ? .gray : .red)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedWatch == nil)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .customTime:
                    NavigationStack {
                        VStack {
                            Text("Select Time")
                                .font(.headline)
                                .padding(.top)
                            HStack(spacing: 0) {
                                Picker("Hour", selection: $customHour) {
                                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)

                                Picker("Minute", selection: $customMinute) {
                                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)) }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)

                                Picker("Second", selection: $customSecond) {
                                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)) }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                            }
                            .font(.system(.title2, design: .monospaced))
                            .padding(.horizontal)
                            Spacer()
                            HStack {
                                Spacer()
                                Button {
                                    var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                                    components.hour = customHour
                                    components.minute = customMinute
                                    components.second = customSecond
                                    if let date = Calendar.current.date(from: components) {
                                        if let id = editingEntryID,
                                           let oldEntry = manager.entries.first(where: { $0.id == id }) {
                                            var updatedEntry = oldEntry
                                            updatedEntry.custom = date
                                            manager.update(updatedEntry)
                                        } else if editingEntryID == nil {
                                            let newEntry = TimeEntry(recorded: Date(), custom: date, watchID: selectedWatch?.id)
                                            manager.add(newEntry)
                                        } else if !watchEntries.isEmpty {
                                            var updatedEntry = watchEntries[0]
                                            updatedEntry.custom = date
                                            manager.update(updatedEntry)
                                        } else {
                                            manager.add(TimeEntry(recorded: date, custom: date, watchID: selectedWatch?.id))
                                        }
                                    }
                                    activeSheet = nil
                                } label: {
                                    Image(systemName: "record.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 24)
                            }
                            .padding(.bottom, 24)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { activeSheet = nil }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])

                case .exporter(let url):
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    RootView()
}
