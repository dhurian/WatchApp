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
    let driftSeconds = currentCustom.timeIntervalSince(currentRecorded)
    let sign = driftSeconds >= 0 ? "+" : "-"
    return "\(sign)\(String(format: "%3.0f", abs(driftSeconds))) s"
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

// MARK: - ContentView

struct ContentView: View {
    
    @StateObject private var manager = TimeEntryManager()
    @State private var editingEntryID: UUID? = nil
    @State private var activeSheet: ActiveSheet? = nil
    @State private var customHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var customMinute: Int = Calendar.current.component(.minute, from: Date())
    @State private var customSecond: Int = Calendar.current.component(.second, from: Date())
    
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
                
                // Export CSV
                Button {
                    if let url = manager.getCSVURL() {
                        activeSheet = .exporter(url)
                    }
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                
                                
                // Add Custom Time
                Button {
                    let now = Date()
                     let nextMinuteDate = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now
                     customHour = Calendar.current.component(.hour, from: nextMinuteDate)
                     customMinute = Calendar.current.component(.minute, from: nextMinuteDate)
                     customSecond = 0
                     activeSheet = .customTime
                } label: {
                    Label("Watch Time", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                
                // Entries List
                if manager.entries.isEmpty {
                    ContentUnavailableView("No recorded times yet",
                                           systemImage: "clock.badge.questionmark",
                                           description: Text("Tap Record Time to save the current time."))
                        .padding(.top, 8)
                } else {
                    List {
                        Section {
                            ForEach(Array(manager.entries.enumerated()), id: \.element.id) { index, entry in
                                HStack(spacing: 12) {
                                    Text(entry.recorded, format: .dateTime.hour().minute().second())
                                        .monospacedDigit()
                                    Image(systemName: "arrow.left.and.right")
                                        .foregroundStyle(.secondary)
                                    if let custom = entry.custom {
                                        Text(custom, format: .dateTime.hour().minute().second())
                                            .monospacedDigit()
                                    } else {
                                        Text("Set…")
                                            .foregroundStyle(.tertiary)
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
                                indices.map { manager.entries[$0] }.forEach { manager.remove($0) }
                            }
                        } header: {
                            Text(Date.now, format: Date.FormatStyle().weekday(.wide).month(.abbreviated).day())
                        }
                    }
                    .listStyle(.insetGrouped)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(role: .destructive) {
                                manager.removeAll()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                            .disabled(manager.entries.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Time Logger")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    manager.add(TimeEntry(recorded: Date()))
                } label: {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.red)
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                }
                .buttonStyle(.plain)
            }
            // Single sheet handler
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
                                         .pickerStyle(.wheel)
                                         .frame(maxWidth: .infinity)
                                         
                                         Picker("Minute", selection: $customMinute) {
                                             ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)) }
                                         }
                                         .pickerStyle(.wheel)
                                         .frame(maxWidth: .infinity)
                                         
                                         Picker("Second", selection: $customSecond) {
                                             ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)) }
                                         }
                                         .pickerStyle(.wheel)
                                         .frame(maxWidth: .infinity)
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
                                                     let newEntry = TimeEntry(recorded: Date(), custom: date)
                                                     manager.add(newEntry)
                                                 } else if !manager.entries.isEmpty {
                                                     var updatedEntry = manager.entries[0]
                                                     updatedEntry.custom = date
                                                     manager.update(updatedEntry)
                                                 } else {
                                                     manager.add(TimeEntry(recorded: date, custom: date))
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
    ContentView()
}
