//
//  ContentView.swift
//  WatchApp
//
//  Created by Dhurian Vitoldas on 07/03/2026.
//

import SwiftUI
import Combine
import PhotosUI

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
    case watchReader

    var id: Int {
        switch self {
        case .customTime: return 0
        case .watchReader: return 1
        }
    }
}

// MARK: - WatchesView

struct WatchesView: View {
    @EnvironmentObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?
    @State private var showingAddSheet = false
    @State private var editingWatch: Watch? = nil
    @State private var galleryWatch: Watch? = nil
    @State private var isReordering = false

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
                            HStack(spacing: 12) {
                                WatchThumbnail(watch: watch)
                                    .onTapGesture {
                                        if !watch.photoFilenames.isEmpty {
                                            galleryWatch = watch
                                        }
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(watch.name).font(.headline)
                                    if !watch.brand.isEmpty {
                                        Text(watch.brand).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if isReordering {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.tertiary)
                                } else if selectedWatch?.id == watch.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isReordering { selectedWatch = watch }
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
                        .onMove { from, to in
                            var reordered = manager.watches
                            reordered.move(fromOffsets: from, toOffset: to)
                            manager.watches = reordered
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(isReordering ? .active : .inactive))
                }
            }
            .navigationTitle("Watches")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if manager.watches.count > 1 {
                        Button(isReordering ? "Done" : "Reorder") {
                            isReordering.toggle()
                        }
                        .fontWeight(isReordering ? .semibold : .regular)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                WatchFormSheet(watch: nil)
            }
            .sheet(item: $editingWatch) { watch in
                WatchFormSheet(watch: watch)
            }
            .fullScreenCover(item: $galleryWatch) { watch in
                PhotoGalleryView(watch: watch)
            }
            .onChange(of: manager.watches) {
                // Stop reordering if watches drop to 1
                if manager.watches.count <= 1 { isReordering = false }
            }
        }
    }
}

// MARK: - PhotoGalleryView

struct PhotoGalleryView: View {
    @EnvironmentObject var manager: TimeEntryManager
    let watch: Watch
    @State private var currentIndex: Int = 0
    @Environment(\.dismiss) private var dismiss

    private var photos: [UIImage] {
        manager.watches.first(where: { $0.id == watch.id })?.photoFilenames.compactMap {
            manager.loadPhoto(filename: $0)
        } ?? []
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if photos.isEmpty {
                ContentUnavailableView("No Photos", systemImage: "photo")
                    .colorScheme(.dark)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, img in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(20)
            }
        }
    }
}

// MARK: - WatchThumbnail

struct WatchThumbnail: View {
    @EnvironmentObject var manager: TimeEntryManager
    let watch: Watch
    let size: CGFloat
    @State private var image: UIImage? = nil

    init(watch: Watch, size: CGFloat = 48) {
        self.watch = watch
        self.size = size
    }

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "watchface.applewatch.case")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .task {
            guard let filename = watch.photoFilenames.first else { return }
            image = manager.loadPhoto(filename: filename)
        }
    }
}

// MARK: - WatchFormSheet

struct WatchFormSheet: View {
    @EnvironmentObject var manager: TimeEntryManager
    var watch: Watch?

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var newImages: [UIImage] = []
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @Environment(\.dismiss) private var dismiss

    private var existingFilenames: [String] {
        guard let w = watch else { return [] }
        return manager.watches.first(where: { $0.id == w.id })?.photoFilenames ?? w.photoFilenames
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    let cols = [GridItem(.adaptive(minimum: 90), spacing: 8)]
                    LazyVGrid(columns: cols, spacing: 8) {
                        // Existing saved photos
                        ForEach(existingFilenames, id: \.self) { filename in
                            if let img = manager.loadPhoto(filename: filename) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 90, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Button {
                                        if let w = watch {
                                            manager.deletePhoto(filename: filename, from: w)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.white, .red)
                                            .padding(4)
                                    }
                                }
                            }
                        }
                        // New unsaved preview images
                        ForEach(Array(newImages.enumerated()), id: \.offset) { index, img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Button {
                                    newImages.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white, .red)
                                        .padding(4)
                                }
                            }
                        }
                        // Add button
                        Menu {
                            Button {
                                showingPhotoPicker = true
                            } label: {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                            }
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 28))
                                Text("Add")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 90, height: 90)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

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
                            for img in newImages { _ = manager.addPhoto(img, to: existing) }
                        } else {
                            var newWatch = Watch(name: trimmedName, brand: brand.trimmingCharacters(in: .whitespaces))
                            manager.addWatch(newWatch)
                            for img in newImages {
                                if let updated = manager.addPhoto(img, to: newWatch) {
                                    newWatch = updated
                                }
                            }
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
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        newImages.append(img)
                        selectedPhoto = nil
                    }
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
            .sheet(isPresented: $showingCamera) {
                CameraAppendView { img in newImages.append(img) }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - CameraAppendView

struct CameraAppendView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> FullCameraViewController {
        let vc = FullCameraViewController()
        vc.onCapture = onCapture
        vc.onDismiss = { context.coordinator.parent.dismiss() }
        return vc
    }

    func updateUIViewController(_ uiViewController: FullCameraViewController, context: Context) {}

    class Coordinator: NSObject {
        let parent: CameraAppendView
        init(_ parent: CameraAppendView) { self.parent = parent }
    }
}

// MARK: - StatisticsView

struct StatisticsView: View {
    @EnvironmentObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?

    // Cached computed values — only recalculated when entries change
    @State private var cachedFilteredEntries: [TimeEntry] = []
    @State private var cachedSyncEvents: [TimeEntry] = []
    @State private var cachedDailyDeviations: [DailyDeviation] = []
    @State private var cachedLatestEntry: TimeEntry? = nil
    @State private var cachedAverageWindowFirst: TimeEntry? = nil

    private struct DailyDeviation {
        let date: Date
        let averageSeconds: Double
        let sampleCount: Int
        let dayOverDayDelta: Double?
    }

    // Drift rate in seconds/day since the last sync, nil if not enough data
    @State private var cachedDriftRate: Double? = nil

    private func recompute() {
        guard let watch = selectedWatch else {
            cachedFilteredEntries = []
            cachedSyncEvents = []
            cachedDailyDeviations = []
            cachedLatestEntry = nil
            cachedDriftRate = nil
            return
        }
        let all = manager.entries(for: watch).sorted { $0.recorded < $1.recorded }
        cachedFilteredEntries = all
        cachedSyncEvents = all.filter { isSyncEvent($0) }.sorted { $0.recorded > $1.recorded }
        cachedLatestEntry = all.last { $0.custom != nil }

        let withCustom = all.filter { $0.custom != nil }
        let window: [TimeEntry]
        if let lastSyncIndex = withCustom.indices.last(where: { isSyncEvent(withCustom[$0]) }) {
            var windowEnd = withCustom.count - 1
            if let nextSync = withCustom.indices.dropFirst(lastSyncIndex + 1).first(where: { isSyncEvent(withCustom[$0]) }) {
                windowEnd = nextSync - 1
            }
            window = Array(withCustom[lastSyncIndex...windowEnd])
        } else {
            window = withCustom
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: window) { calendar.startOfDay(for: $0.recorded) }
        let sortedDays = grouped.keys.sorted()
        var days: [DailyDeviation] = []
        for (i, day) in sortedDays.enumerated() {
            let entries = grouped[day]!
            let drifts = entries.compactMap { entry -> Double? in
                guard let custom = entry.custom else { return nil }
                let raw = custom.timeIntervalSince(entry.recorded)
                return abs(raw) < 1 ? 0.0 : raw
            }
            let avg = drifts.isEmpty ? 0.0 : drifts.reduce(0, +) / Double(drifts.count)
            let prevAvg = i > 0 ? days[i - 1].averageSeconds : nil
            let delta = prevAvg.map { avg - $0 }
            days.append(DailyDeviation(date: day, averageSeconds: avg, sampleCount: entries.count, dayOverDayDelta: delta))
        }
        cachedDailyDeviations = days
        cachedAverageWindowFirst = window.first

        // Drift rate: seconds of additional drift accumulated per calendar day since the window start
        // Uses linear regression over daily averages so single-day outliers don't dominate.
        if days.count >= 2, let windowStart = window.first?.recorded {
            let refDay = calendar.startOfDay(for: windowStart)
            // x = days since window start, y = cumulative drift average
            let points: [(x: Double, y: Double)] = days.map { d in
                let x = Double(calendar.dateComponents([.day], from: refDay, to: d.date).day ?? 0)
                return (x, d.averageSeconds)
            }
            let n = Double(points.count)
            let sumX  = points.map(\.x).reduce(0, +)
            let sumY  = points.map(\.y).reduce(0, +)
            let sumXY = points.map { $0.x * $0.y }.reduce(0, +)
            let sumX2 = points.map { $0.x * $0.x }.reduce(0, +)
            let denom = n * sumX2 - sumX * sumX
            cachedDriftRate = denom == 0 ? nil : (n * sumXY - sumX * sumY) / denom
        } else {
            cachedDriftRate = nil
        }
    }

    private func formattedAvg(_ seconds: Double) -> String {
        let isZero = abs(seconds) < 0.05
        if isZero { return "  0.0 s" }
        let sign = seconds >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", abs(seconds))) s"
    }

    @ViewBuilder
    private func dailyDeviationRow(_ day: DailyDeviation) -> some View {
        HStack(alignment: .center) {
            Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .frame(minWidth: 70, alignment: .leading)
            Spacer()
            deltaLabel(day.dayOverDayDelta)
            Text(formattedAvg(day.averageSeconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
            Text("(\(day.sampleCount))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func deltaLabel(_ delta: Double?) -> some View {
        if let delta {
            let icon = delta > 0.05 ? "arrow.up" : delta < -0.05 ? "arrow.down" : "equal"
            let color: Color = abs(delta) < 0.5 ? .secondary : delta > 0 ? .orange : .blue
            HStack(spacing: 2) {
                Image(systemName: icon).font(.caption2)
                Text(formattedAvg(delta)).monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(color)
        } else {
            Text("—").font(.footnote).foregroundStyle(.tertiary)
        }
    }

    var body: some View {
        NavigationStack {
            if selectedWatch == nil {
                ContentUnavailableView("No Watch Selected",
                                       systemImage: "watchface.applewatch.case",
                                       description: Text("Select a watch in the Watches tab to view statistics."))
                .navigationTitle("Statistics")
            } else if cachedFilteredEntries.isEmpty {
                ContentUnavailableView("No Statistics Yet",
                                       systemImage: "chart.bar",
                                       description: Text("Record some times for \(selectedWatch!.name) to see statistics here."))
                .navigationTitle("Statistics")
            } else {
                List {
                    Section("Latest Measurement") {
                        if let entry = cachedLatestEntry, let custom = entry.custom {
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
                        if cachedDailyDeviations.isEmpty {
                            Text("Not enough data yet.").foregroundStyle(.secondary)
                        } else {
                            if let rate = cachedDriftRate {
                                HStack {
                                    Label("Drift rate", systemImage: "chart.line.uptrend.xyaxis")
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(formattedAvg(rate) + " / day")
                                            .monospacedDigit()
                                            .foregroundStyle(abs(rate) < 0.5 ? .green : abs(rate) < 2 ? .orange : .red)
                                        Text("since last sync")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            ForEach(cachedDailyDeviations, id: \.date) { day in
                                dailyDeviationRow(day)
                            }
                        }
                    } header: {
                        Text("Average Deviation Per Day Since Last Sync")
                    } footer: {
                        if let first = cachedAverageWindowFirst {
                            Text("Window starts \(first.recorded, format: .dateTime.month().day().hour().minute())")
                                .font(.footnote)
                        }
                    }
                    Section("Sync Events") {
                        if cachedSyncEvents.isEmpty {
                            Text("No sync events yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(cachedSyncEvents) { entry in
                                NavigationLink {
                                    SyncDetailView(
                                        syncEntry: entry,
                                        allEntries: cachedFilteredEntries,
                                        watch: selectedWatch
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.recorded, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                                            .font(.headline)
                                        Text(entry.recorded, format: .dateTime.hour().minute().second())
                                            .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(selectedWatch?.name ?? "Statistics")
            }
        }
        .onAppear { recompute() }
        .onChange(of: selectedWatch) { recompute() }
        .onChange(of: manager.entries) { recompute() }
    }
}

// MARK: - SyncDetailView

struct SyncDetailView: View {
    let syncEntry: TimeEntry
    let allEntries: [TimeEntry]   // all entries for this watch, sorted ascending
    let watch: Watch?

    /// Entries that belong to this sync period:
    /// Entries between the previous sync (exclusive) and this sync (exclusive).
    /// The sync event itself (delta ≈ 0) is excluded so it doesn't skew the averages.
    private var periodEntries: [TimeEntry] {
        let sorted = allEntries.sorted { $0.recorded < $1.recorded }

        guard let syncIdx = sorted.firstIndex(where: { $0.id == syncEntry.id }) else { return [] }

        let prevSyncIdx = sorted[..<syncIdx].indices.last(where: { isSyncEvent(sorted[$0]) })
        let startIdx = prevSyncIdx.map { $0 + 1 } ?? sorted.startIndex

        // Exclude syncIdx — it's the reset point, not a drift measurement
        guard startIdx < syncIdx else { return [] }
        return Array(sorted[startIdx..<syncIdx])
    }

    // MARK: - Derived stats (same logic as StatisticsView)

    private struct DailyDeviation {
        let date: Date
        let averageSeconds: Double
        let sampleCount: Int
        let dayOverDayDelta: Double?
    }

    private var dailyDeviations: [DailyDeviation] {
        let withCustom = periodEntries.filter { $0.custom != nil }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: withCustom) { calendar.startOfDay(for: $0.recorded) }
        var days: [DailyDeviation] = []
        for (i, day) in grouped.keys.sorted().enumerated() {
            let entries = grouped[day]!
            let drifts = entries.compactMap { e -> Double? in
                guard let c = e.custom else { return nil }
                let raw = c.timeIntervalSince(e.recorded)
                return abs(raw) < 1 ? 0.0 : raw
            }
            let avg = drifts.isEmpty ? 0.0 : drifts.reduce(0, +) / Double(drifts.count)
            let prevAvg = i > 0 ? days[i - 1].averageSeconds : nil
            days.append(DailyDeviation(date: day, averageSeconds: avg,
                                       sampleCount: entries.count,
                                       dayOverDayDelta: prevAvg.map { avg - $0 }))
        }
        return days
    }

    private var driftRate: Double? {
        let days = dailyDeviations
        guard days.count >= 2,
              let windowStart = periodEntries.first?.recorded else { return nil }
        let cal = Calendar.current
        let refDay = cal.startOfDay(for: windowStart)
        let points = days.map { d -> (Double, Double) in
            let x = Double(cal.dateComponents([.day], from: refDay, to: d.date).day ?? 0)
            return (x, d.averageSeconds)
        }
        let n = Double(points.count)
        let sumX  = points.map { $0.0 }.reduce(0, +)
        let sumY  = points.map { $0.1 }.reduce(0, +)
        let sumXY = points.map { $0.0 * $0.1 }.reduce(0, +)
        let sumX2 = points.map { $0.0 * $0.0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        return denom == 0 ? nil : (n * sumXY - sumX * sumY) / denom
    }

    // MARK: - Formatting helpers

    private func formattedAvg(_ s: Double) -> String {
        if abs(s) < 0.05 { return "  0.0 s" }
        return "\(s >= 0 ? "+" : "-")\(String(format: "%.1f", abs(s))) s"
    }

    private func formattedDev(_ recorded: Date, _ custom: Date) -> String {
        let raw = custom.timeIntervalSince(recorded)
        let s = abs(raw) < 1 ? 0.0 : raw
        if s == 0 { return "  0 s" }
        return "\(s >= 0 ? "+" : "-")\(String(format: "%.0f", abs(s))) s"
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func dailyRow(_ day: DailyDeviation) -> some View {
        HStack(alignment: .center) {
            Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .frame(minWidth: 70, alignment: .leading)
            Spacer()
            // Day-over-day delta
            if let delta = day.dayOverDayDelta {
                let icon = delta > 0.05 ? "arrow.up" : delta < -0.05 ? "arrow.down" : "equal"
                let color: Color = abs(delta) < 0.5 ? .secondary : delta > 0 ? .orange : .blue
                HStack(spacing: 2) {
                    Image(systemName: icon).font(.caption2)
                    Text(formattedAvg(delta)).monospacedDigit()
                }
                .font(.footnote).foregroundStyle(color)
            } else {
                Text("—").font(.footnote).foregroundStyle(.tertiary)
            }
            Text(formattedAvg(day.averageSeconds))
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
            Text("(\(day.sampleCount))")
                .font(.footnote).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Sync event header
            Section("Sync Event") {
                HStack {
                    Label("Date", systemImage: "calendar")
                    Spacer()
                    Text(syncEntry.recorded, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("Time", systemImage: "clock")
                    Spacer()
                    Text(syncEntry.recorded, format: .dateTime.hour().minute().second())
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                HStack {
                    Label("Measurements", systemImage: "list.number")
                    Spacer()
                    Text("\(periodEntries.count)")
                        .foregroundStyle(.secondary)
                }
            }

            // Drift rate for this period
            let days = dailyDeviations
            if !days.isEmpty {
                Section {
                    if let rate = driftRate {
                        HStack {
                            Label("Drift rate", systemImage: "chart.line.uptrend.xyaxis")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formattedAvg(rate) + " / day")
                                    .monospacedDigit()
                                    .foregroundStyle(abs(rate) < 0.5 ? .green : abs(rate) < 2 ? .orange : .red)
                                Text("this sync period")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    ForEach(days, id: \.date) { day in
                        dailyRow(day)
                    }
                } header: {
                    Text("Average Deviation Per Day")
                } footer: {
                    if let first = periodEntries.first {
                        Text("Period: \(first.recorded, format: .dateTime.month().day().hour().minute()) – \(syncEntry.recorded, format: .dateTime.month().day().hour().minute())")
                            .font(.footnote)
                    }
                }
            }

            // All individual measurements in this period
            Section("Measurements") {
                let allPeriod = (periodEntries + [syncEntry]).sorted { $0.recorded > $1.recorded }
                if allPeriod.isEmpty {
                    Text("No measurements for this period.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allPeriod) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.recorded, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                    .font(.caption).foregroundStyle(.tertiary)
                                Text(entry.recorded, format: .dateTime.hour().minute().second())
                                    .monospacedDigit().font(.subheadline)
                            }
                            Spacer()
                            if let custom = entry.custom {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formattedDev(entry.recorded, custom))
                                        .monospacedDigit()
                                        .foregroundStyle(isSyncEvent(entry) ? .green : .secondary)
                                    if isSyncEvent(entry) {
                                        Text("sync — excluded from averages")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }
                            } else {
                                Text("no watch time")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(syncEntry.recorded.formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ContentView

struct ContentView: View {

    @EnvironmentObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?
    @State private var editingEntryID: UUID? = nil
    @State private var activeSheet: ActiveSheet? = nil
    @State private var customHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var customMinute: Int = Calendar.current.component(.minute, from: Date())
    @State private var customSecond: Int = Calendar.current.component(.second, from: Date())
    @State private var customPosition: WatchPosition? = nil
    @State private var currentTime: Date = Date()
    @State private var isVisible: Bool = false
    private let clockTimer = Timer.publish(every: 1, tolerance: 0.5, on: .main, in: .common)
    @State private var clockCancellable: AnyCancellable? = nil

    @State private var watchEntries: [TimeEntry] = []

    private func refreshEntries() {
        guard let watch = selectedWatch else { watchEntries = []; return }
        watchEntries = manager.entries(for: watch)
    }

    private var groupedEntries: [Date: [TimeEntry]] {
        Dictionary(grouping: watchEntries) {
            Calendar.current.startOfDay(for: $0.recorded)
        }
    }

    private var sortedDays: [Date] {
        groupedEntries.keys.sorted(by: >)
    }

    @ViewBuilder
    private func entryRow(_ entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
                if let pos = entry.position {
                    Image(systemName: pos.systemImage)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                Button {
                    editingEntryID = entry.id
                    let base = entry.custom ?? entry.recorded
                    customHour   = Calendar.current.component(.hour,   from: base)
                    customMinute = Calendar.current.component(.minute, from: base)
                    customSecond = Calendar.current.component(.second, from: base)
                    customPosition = entry.position
                    activeSheet = .customTime
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
            }
            if let custom = entry.custom {
                Text("Δ = \(deviation(currentRecorded: entry.recorded, currentCustom: custom))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var watchPickerBanner: some View {
        if !manager.watches.isEmpty {
            Menu {
                ForEach(manager.watches) { watch in
                    Button { selectedWatch = watch } label: {
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
    }

    @ViewBuilder
    private var entriesList: some View {
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
                ForEach(sortedDays, id: \.self) { day in
                    let dayEntries = groupedEntries[day]!.sorted { $0.recorded > $1.recorded }
                    Section {
                        ForEach(dayEntries) { entry in
                            entryRow(entry)
                        }
                        .onDelete { indices in
                            indices.map { dayEntries[$0] }.forEach { manager.remove($0) }
                        }
                    } header: {
                        Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    }
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

    @ViewBuilder
    private var positionPicker: some View {
        VStack(spacing: 8) {
            Text("Watch Position")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(WatchPosition.allCases, id: \.self) { pos in
                    Button {
                        customPosition = customPosition == pos ? nil : pos
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: pos.systemImage)
                                .font(.system(size: 28))
                            Text(pos.label)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(customPosition == pos ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .foregroundStyle(customPosition == pos ? .accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(customPosition == pos ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func saveTimeEntry() {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour   = customHour
        components.minute = customMinute
        components.second = customSecond
        guard let date = Calendar.current.date(from: components) else { return }
        if let id = editingEntryID,
           let old = manager.entries.first(where: { $0.id == id }) {
            var updated = old
            updated.custom   = date
            updated.position = customPosition
            manager.update(updated)
        } else if editingEntryID == nil {
            manager.add(TimeEntry(recorded: Date(), custom: date,
                                  watchID: selectedWatch?.id, position: customPosition))
        } else if !watchEntries.isEmpty {
            var updated = watchEntries[0]
            updated.custom   = date
            updated.position = customPosition
            manager.update(updated)
        } else {
            manager.add(TimeEntry(recorded: date, custom: date,
                                  watchID: selectedWatch?.id, position: customPosition))
        }
        activeSheet = nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Live Clock
                HStack {
                    Image(systemName: "clock")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    Text(currentTime, format: .dateTime.hour().minute().second())
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal)
                .onAppear {
                    currentTime = Date()
                    clockCancellable = clockTimer.autoconnect().sink { date in
                        currentTime = date
                    }
                    refreshEntries()
                }
                .onDisappear {
                    clockCancellable?.cancel()
                    clockCancellable = nil
                }
                .onChange(of: selectedWatch) { refreshEntries() }
                .onChange(of: manager.entries) { refreshEntries() }

                watchPickerBanner
                entriesList
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
                        customPosition = nil
                        activeSheet = .customTime
                    } label: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedWatch == nil)

                    Button {
                        activeSheet = .watchReader
                    } label: {
                        ZStack {
                            Circle()
                                .fill(selectedWatch == nil ? Color.gray : Color.blue)
                                .frame(width: 60, height: 60)
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedWatch == nil)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .watchReader:
                    WatchPhotoReaderView(selectedWatch: $selectedWatch)
                        .environmentObject(manager)
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

                            Divider().padding(.horizontal)

                            positionPicker

                            Spacer()
                            Button {
                                saveTimeEntry()
                            } label: {
                                Label("Save", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { activeSheet = nil }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }
}

// MARK: - FunctionsView

struct FunctionsView: View {
    @EnvironmentObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?

    @State private var showingImporter = false
    @State private var importResult: ImportResult? = nil
    @State private var showingImportAlert = false
    @State private var cachedExportURL: URL? = nil

    private func prepareExport() {
        Task.detached(priority: .userInitiated) {
            let url = await MainActor.run { manager.getCSVURL(for: selectedWatch) }
            await MainActor.run { cachedExportURL = url }
        }
    }

    enum ImportResult {
        case success(Int)
        case failure(String)

        var title: String {
            switch self {
            case .success: return "Import Successful"
            case .failure: return "Import Failed"
            }
        }

        var message: String {
            switch self {
            case .success(let count): return "\(count) entries imported."
            case .failure(let reason): return reason
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Export") {
                    if let url = cachedExportURL {
                        ShareLink(item: url, preview: SharePreview("watch_log.csv", image: Image(systemName: "doc.text"))) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                    if selectedWatch != nil {
                        Text("Exports entries for the selected watch only.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No watch selected — will export all entries.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Import") {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }
                    Text("CSV must match the export format: Watch, Recorded Time, Custom Time, Delta Seconds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Functions")
            .onAppear { prepareExport() }
            .onChange(of: selectedWatch) { prepareExport() }
            .onChange(of: manager.entries) { prepareExport() }

            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { [manager] result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let count = manager.importCSV(from: url)
                    if count >= 0 {
                        importResult = .success(count)
                    } else {
                        importResult = .failure("Could not parse the CSV file. Make sure it matches the export format.")
                    }
                    showingImportAlert = true
                case .failure(let error):
                    importResult = .failure(error.localizedDescription)
                    showingImportAlert = true
                }
            }
            .alert(importResult?.title ?? "", isPresented: $showingImportAlert) {
                Button("OK") {}
            } message: {
                Text(importResult?.message ?? "")
            }
        }
    }
}



// MARK: - Preview

#Preview {
    @Previewable @StateObject var manager = TimeEntryManager()
    @Previewable @State var selectedWatch: Watch? = nil

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
