//
//  TimeEntryManager.swift
//  WatchApp
//
//  Created by Dhurian Vitoldas on 07/03/2026.
//

import Foundation
import Combine
import UIKit

// MARK: - Watch Model

struct Watch: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var brand: String
    var photoFilenames: [String]

    init(id: UUID = UUID(), name: String, brand: String = "", photoFilenames: [String] = []) {
        self.id = id
        self.name = name
        self.brand = brand
        self.photoFilenames = photoFilenames
    }

    var displayName: String {
        brand.isEmpty ? name : "\(brand) – \(name)"
    }
}

// MARK: - WatchPosition

enum WatchPosition: String, Codable, CaseIterable {
    case crownAt3   // crown toward 3 o'clock (hanging on left wrist, crown right)
    case crownAt9   // crown toward 9 o'clock (crown left)
    case dialUp     // dial face up
    case dialDown   // dial face down

    var label: String {
        switch self {
        case .crownAt3:  return "Crown at 3"
        case .crownAt9:  return "Crown at 9"
        case .dialUp:    return "Dial Up"
        case .dialDown:  return "Dial Down"
        }
    }

    // SF Symbol that best represents each position
    var systemImage: String {
        switch self {
        case .crownAt3:  return "arrow.right.circle"
        case .crownAt9:  return "arrow.left.circle"
        case .dialUp:    return "arrow.up.circle"
        case .dialDown:  return "arrow.down.circle"
        }
    }
}

// MARK: - TimeEntry Model

struct TimeEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var recorded: Date
    var custom: Date?
    var watchID: UUID?
    var position: WatchPosition?

    init(id: UUID = UUID(), recorded: Date, custom: Date? = nil, watchID: UUID? = nil, position: WatchPosition? = nil) {
        self.id = id
        self.recorded = recorded
        self.custom = custom
        self.watchID = watchID
        self.position = position
    }
}

// MARK: - TimeEntryManager

class TimeEntryManager: ObservableObject {

    @Published var entries: [TimeEntry] = [] {
        didSet { scheduleSave() }
    }

    @Published var watches: [Watch] = [] {
        didSet { scheduleSave() }
    }

    private var saveWorkItem: DispatchWorkItem?

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveEntries()
            self?.saveWatches()
        }
        saveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private let entriesURL: URL
    private let watchesURL: URL
    private var imageCache: [String: UIImage] = [:]

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
        watch.photoFilenames.forEach { deletePhoto(filename: $0, from: watch) }
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
            let delta = entry.custom.map { String(format: "%.1f", $0.timeIntervalSince(entry.recorded)) } ?? ""
            csv.append("\(watchName),\(recorded),\(custom),\(delta)\n")
        }
        let filename = watch.map { "watch_log_\($0.id.uuidString).csv" } ?? "watch_log_all.csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("CSV export failed:", error)
            return nil
        }
    }


    // MARK: - Photo Storage

    func addPhoto(_ image: UIImage, to watch: Watch) -> Watch? {
        let filename = "watch_photo_\(watch.id.uuidString)_\(UUID().uuidString).jpg"
        let url = photoURL(for: filename)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            var updated = watch
            updated.photoFilenames.append(filename)
            updateWatch(updated)
            return updated
        } catch {
            print("Failed to save photo:", error)
            return nil
        }
    }

    func loadPhoto(filename: String) -> UIImage? {
        if let cached = imageCache[filename] { return cached }
        let url = photoURL(for: filename)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        imageCache[filename] = image
        return image
    }

    func clearImageCache() {
        imageCache.removeAll()
    }

    func loadPhotos(for watch: Watch) -> [UIImage] {
        watch.photoFilenames.compactMap { loadPhoto(filename: $0) }
    }

    func deletePhoto(filename: String, from watch: Watch) {
        imageCache.removeValue(forKey: filename)
        let url = photoURL(for: filename)
        try? FileManager.default.removeItem(at: url)
        var updated = watch
        updated.photoFilenames.removeAll { $0 == filename }
        updateWatch(updated)
    }

    private func photoURL(for filename: String) -> URL {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docDir.appendingPathComponent(filename)
    }


    // MARK: - CSV Import

    /// Returns the number of entries imported, or -1 on parse failure.
    func importCSV(from url: URL) -> Int {
        guard url.startAccessingSecurityScopedResource() else { return -1 }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return -1 }

        let formatter = ISO8601DateFormatter()
        var lines = raw.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return 0 }
        lines.removeFirst() // skip header

        var count = 0
        for line in lines {
            // Split on comma but respect quoted fields
            let cols = parseCSVLine(line)
            guard cols.count >= 3 else { continue }

            let watchName = cols[0].trimmingCharacters(in: .whitespaces)
            let recordedStr = cols[1].trimmingCharacters(in: .whitespaces)
            let customStr = cols[2].trimmingCharacters(in: .whitespaces)

            guard let recorded = formatter.date(from: recordedStr) else { continue }
            let custom = customStr.isEmpty ? nil : formatter.date(from: customStr)

            // Match or create watch by display name
            var watchID: UUID? = nil
            if !watchName.isEmpty {
                if let existing = watches.first(where: { $0.displayName == watchName }) {
                    watchID = existing.id
                } else {
                    let parts = watchName.components(separatedBy: " – ")
                    let newWatch: Watch
                    if parts.count == 2 {
                        newWatch = Watch(name: parts[1], brand: parts[0])
                    } else {
                        newWatch = Watch(name: watchName)
                    }
                    addWatch(newWatch)
                    watchID = newWatch.id
                }
            }

            let entry = TimeEntry(recorded: recorded, custom: custom, watchID: watchID)
            // Avoid duplicates: skip if same recorded time + watchID already exists
            if !entries.contains(where: { $0.recorded == entry.recorded && $0.watchID == entry.watchID }) {
                add(entry)
                count += 1
            }
        }
        return count
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
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
