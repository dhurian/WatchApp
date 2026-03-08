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
    case exporter(URL)

    var id: Int {
        switch self {
        case .customTime: return 0
        case .exporter: return 1
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
                WatchFormSheet(watch: nil)
            }
            .sheet(item: $editingWatch) { watch in
                WatchFormSheet(watch: watch)
            }
            .fullScreenCover(item: $galleryWatch) { watch in
                PhotoGalleryView(watch: watch)
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
    @State private var cachedOverallAvg: Double? = nil
    @State private var cachedLatestEntry: TimeEntry? = nil
    @State private var cachedAverageWindowFirst: TimeEntry? = nil

    private struct DailyDeviation {
        let date: Date
        let averageSeconds: Double
        let sampleCount: Int
    }

    private func recompute() {
        guard let watch = selectedWatch else {
            cachedFilteredEntries = []
            cachedSyncEvents = []
            cachedDailyDeviations = []
            cachedOverallAvg = nil
            cachedLatestEntry = nil
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
        let days: [DailyDeviation] = grouped.keys.sorted().map { day in
            let entries = grouped[day]!
            let drifts = entries.compactMap { entry -> Double? in
                guard let custom = entry.custom else { return nil }
                let raw = custom.timeIntervalSince(entry.recorded)
                return abs(raw) < 1 ? 0.0 : raw
            }
            let avg = drifts.isEmpty ? 0.0 : drifts.reduce(0, +) / Double(drifts.count)
            return DailyDeviation(date: day, averageSeconds: avg, sampleCount: entries.count)
        }
        cachedDailyDeviations = days
        cachedOverallAvg = days.isEmpty ? nil : days.map(\.averageSeconds).reduce(0, +) / Double(days.count)
        cachedAverageWindowFirst = window.first
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
                            if let overall = cachedOverallAvg {
                                HStack {
                                    Label("Overall Avg / Day", systemImage: "function")
                                    Spacer()
                                    Text(formattedAvg(overall))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            ForEach(cachedDailyDeviations, id: \.date) { day in
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
                .listStyle(.insetGrouped)
                .navigationTitle(selectedWatch?.name ?? "Statistics")
            }
        }
        .onAppear { recompute() }
        .onChange(of: selectedWatch) { recompute() }
        .onChange(of: manager.entries) { recompute() }
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
    @State private var currentTime: Date = Date()
    @State private var isVisible: Bool = false
    private let clockTimer = Timer.publish(every: 1, tolerance: 0.5, on: .main, in: .common)
    @State private var clockCancellable: AnyCancellable? = nil

    @State private var watchEntries: [TimeEntry] = []

    private func refreshEntries() {
        guard let watch = selectedWatch else { watchEntries = []; return }
        watchEntries = manager.entries(for: watch)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // Live Clock — only ticks when view is visible
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

// MARK: - FunctionsView

struct FunctionsView: View {
    @EnvironmentObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?

    @State private var exportURL: URL? = nil
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importResult: ImportResult? = nil
    @State private var showingImportAlert = false

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
                    Button {
                        if let url = manager.getCSVURL(for: selectedWatch) {
                            exportURL = url
                            showingExporter = true
                        }
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
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
            .sheet(isPresented: $showingExporter) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
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
