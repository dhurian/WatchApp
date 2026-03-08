//
//  TimeEntryManager.swift
//  WatchApp
//
//  Created by Dhurian Vitoldas on 07/03/2026.
//

import Foundation
import Combine

// MARK: - Watch Model

struct Watch: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var brand: String

    init(id: UUID = UUID(), name: String, brand: String = "") {
        self.id = id
        self.name = name
        self.brand = brand
    }

    var displayName: String {
        brand.isEmpty ? name : "\(brand) – \(name)"
    }
}

// MARK: - TimeEntry Model

struct TimeEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var recorded: Date
    var custom: Date?
    var watchID: UUID?

    init(id: UUID = UUID(), recorded: Date, custom: Date? = nil, watchID: UUID? = nil) {
        self.id = id
        self.recorded = recorded
        self.custom = custom
        self.watchID = watchID
    }
}

// MARK: - TimeEntryManager

class TimeEntryManager: ObservableObject {

    @Published var entries: [TimeEntry] = [] {
        didSet { saveEntries() }
    }

    @Published var watches: [Watch] = [] {
        didSet { saveWatches() }
    }

    private let entriesURL: URL
    private let watchesURL: URL

    init() {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.entriesURL = docDir.appendingPathComponent("time_entries.json")
        self.watchesURL = docDir.appendingPathComponent("watches.json")
        loadEntries()
        loadWatches()
    }

    // MARK: - Entry CRUD

    func add(_ entry: TimeEntry) {
        entries.append(entry)
        entries.sort { $0.recorded > $1.recorded }
    }

    func update(_ entry: TimeEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    func remove(_ entry: TimeEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func removeAll(for watchID: UUID? = nil) {
        if let watchID = watchID {
            entries.removeAll { $0.watchID == watchID }
        } else {
            entries.removeAll()
        }
    }

    func entries(for watch: Watch) -> [TimeEntry] {
        entries.filter { $0.watchID == watch.id }
    }

    // MARK: - Watch CRUD

    func addWatch(_ watch: Watch) {
        watches.append(watch)
    }

    func updateWatch(_ watch: Watch) {
        guard let index = watches.firstIndex(where: { $0.id == watch.id }) else { return }
        watches[index] = watch
    }

    func removeWatch(_ watch: Watch) {
        watches.removeAll { $0.id == watch.id }
        entries.removeAll { $0.watchID == watch.id }
    }

    // MARK: - CSV

    func getCSVURL(for watch: Watch? = nil) -> URL? {
        let formatter = ISO8601DateFormatter()
        let subset = watch.map { w in entries.filter { $0.watchID == w.id } } ?? entries
        var csv = "Watch,Recorded Time,Custom Time,Delta Seconds\n"
        for entry in subset {
            let watchName = watches.first(where: { $0.id == entry.watchID })?.displayName ?? ""
            let recorded = formatter.string(from: entry.recorded)
            let custom = entry.custom.map { formatter.string(from: $0) } ?? ""
            let delta = entry.custom.map { String(format: "%0.2f", $0.timeIntervalSince(entry.recorded)) } ?? ""
            csv.append("\(watchName),\(recorded),\(custom),\(delta)\n")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch_log.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("CSV export failed:", error)
            return nil
        }
    }

    // MARK: - Persistence

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: entriesURL, options: [.atomic, .completeFileProtection])
        } catch { print("Failed to save entries:", error) }
    }

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: entriesURL.path) else { return }
        do {
            let data = try Data(contentsOf: entriesURL)
            entries = try JSONDecoder().decode([TimeEntry].self, from: data)
        } catch { print("Failed to load entries:", error) }
    }

    private func saveWatches() {
        do {
            let data = try JSONEncoder().encode(watches)
            try data.write(to: watchesURL, options: [.atomic, .completeFileProtection])
        } catch { print("Failed to save watches:", error) }
    }

    private func loadWatches() {
        guard FileManager.default.fileExists(atPath: watchesURL.path) else { return }
        do {
            let data = try Data(contentsOf: watchesURL)
            watches = try JSONDecoder().decode([Watch].self, from: data)
        } catch { print("Failed to load watches:", error) }
    }
}
