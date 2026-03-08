//
//  TimeEntryManager.swift
//  WatchApp
//
//  Created by Dhurian Vitoldas on 07/03/2026.
//

import Foundation
import Combine

// MARK: - Model
struct TimeEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var recorded: Date
    var custom: Date?
    
    init(id: UUID = UUID(), recorded: Date, custom: Date? = nil) {
        self.id = id
        self.recorded = recorded
        self.custom = custom
    }
}

// MARK: - Manager
class TimeEntryManager: ObservableObject {
    
    @Published var entries: [TimeEntry] = [] {
        didSet {
            save()
           
        }
    }
    
    private let fileURL: URL
    private var cachedCSV: URL?

    
    init(fileName: String = "time_entries.json") {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docDir.appendingPathComponent(fileName)
        load()                       // Load entries from disk
        //generateCSVIfNeeded()        // Pre-generate CSV immediately
            
    }
    
    // MARK: - CRUD
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
    
    func removeAll() {
        entries.removeAll()
    }
    
    // MARK: - CSV Caching
    func getCSVURL() -> URL? {
        let formatter = ISO8601DateFormatter()
        var csv = "Recorded Time,Custom Time,Delta Seconds\n"
        for entry in entries {
            let recorded = formatter.string(from: entry.recorded)
            let custom = entry.custom.map { formatter.string(from: $0) } ?? ""
            let delta = entry.custom.map { String($0.timeIntervalSince(entry.recorded)) } ?? ""
            csv.append("\(recorded),\(custom),\(delta)\n")
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
    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to save entries:", error)
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([TimeEntry].self, from: data)
        } catch {
            print("Failed to load entries:", error)
        }
    }
}
