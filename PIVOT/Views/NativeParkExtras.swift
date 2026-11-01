import SwiftUI
import Charts

// MARK: - HHN event-night scope and independent preferences

enum HorrorNightPhase: Equatable {
    case hidden, preview, live
}

enum HorrorHouseSort: String, CaseIterable, Identifiable {
    case shortest = "Shortest wait"
    case name = "Name"
    var id: String { rawValue }
}

enum HorrorNightPreferences {
    // House identifiers are strings and never enter the ride-favorite store.
    static let favoritesKey = "pivot.hhn.favorites.v1.65"
    static let sortKey = "pivot.hhn.sort.v1.65"
    static func doneKey(eventDate: String) -> String { "pivot.hhn.done.v1.65.\(eventDate)" }

    static func ids(from json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values.filter { !$0.isEmpty })
    }

    static func toggling(_ id: String, in json: String) -> String {
        var values = ids(from: json)
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
        guard let data = try? JSONEncoder().encode(values.sorted()),
              let encoded = String(data: data, encoding: .utf8) else { return json }
        return encoded
    }
}

enum HorrorNightPresentation {
    static let timeZone = TimeZone(identifier: "America/New_York")!

    static func phase(for event: HorrorNightSnapshot, at now: Date) -> HorrorNightPhase {
        let night = event.night
        guard isFresh(event.scheduleCheckedAt, now: now, maximumAge: 36 * 60 * 60),
              night.closingTime > night.openingTime,
              night.closingTime > night.modeStartsAt,
              night.closingTime.timeIntervalSince(night.modeStartsAt) <= 18 * 60 * 60,
              now < night.closingTime else { return .hidden }
        if now >= night.modeStartsAt { return .live }
        // Today's preview only. The previous event remains scoped to its API
        // date after midnight until its actual closing instant, not midnight.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now) == night.date ? .preview : .hidden
    }

    static func isFresh(_ date: Date, now: Date, maximumAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age.isFinite && age >= -120 && age < maximumAge
    }

    static func liveWait(for house: HorrorHouse, event: HorrorNightSnapshot, now: Date, refreshFailed: Bool) -> Int? {
        guard !refreshFailed, phase(for: event, at: now) == .live, now >= event.night.openingTime,
              isFresh(event.fetchedAt, now: now, maximumAge: 15 * 60),
              sourceVersionIsUsable(house.sourceUpdatedAt, now: now),
              house.status == "OPEN", let wait = house.waitTime, wait >= 0 else { return nil }
        return wait
    }

    // A fresh successful park response observes the current posted value.
    // lastUpdated describes when that value changed, not when it was checked.
    static func sourceVersionIsUsable(_ date: Date, now: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date <= now.addingTimeInterval(120)
    }

    static func sortedHouses(_ event: HorrorNightSnapshot, sort: HorrorHouseSort, now: Date, refreshFailed: Bool) -> [HorrorHouse] {
        var seen = Set<String>()
        let houses = event.houses.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        return houses.sorted { left, right in
            if sort == .shortest {
                let a = liveWait(for: left, event: event, now: now, refreshFailed: refreshFailed)
                let b = liveWait(for: right, event: event, now: now, refreshFailed: refreshFailed)
                switch (a, b) {
                case let (.some(a), .some(b)) where a != b: return a < b
                case (.some(_), .none): return true
                case (.none, .some(_)): return false
                default: break
                }
            }
            let comparison = left.name.localizedStandardCompare(right.name)
            return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
        }
    }
}

enum HorrorHouseFilter: String, CaseIterable, Identifiable {
    case all = "All houses"
    case favorites = "Favorites"
    case remaining = "To do"
    var id: String { rawValue }
}

enum HorrorNightFeedState: Equatable {
    case preview, live, saved, unavailable

    var label: String {
        switch self {
        case .preview: "Tonight’s preview"
        case .live: "Live house updates"
        case .saved: "Saved · waits unknown"
        case .unavailable: "Updates unavailable"
        }
    }
}

extension HorrorNightPresentation {
    static func feedState(for event: HorrorNightSnapshot, now: Date, refreshFailed: Bool) -> HorrorNightFeedState {
        guard phase(for: event, at: now) != .hidden else { return .unavailable }
        if now < event.night.openingTime { return .preview }
        let houses = sortedHouses(event, sort: .name, now: now, refreshFailed: refreshFailed)
        guard !houses.isEmpty else { return .unavailable }
        guard !refreshFailed, isFresh(event.fetchedAt, now: now, maximumAge: 15 * 60) else { return .saved }
        let observed = houses.contains {
            !$0.id.isEmpty && ["OPEN", "DOWN", "CLOSED", "UPCOMING"].contains($0.status) &&
            sourceVersionIsUsable($0.sourceUpdatedAt, now: now)
        }
        return observed ? .live : .unavailable
    }

    static func visibleHouses(_ houses: [HorrorHouse], filter: HorrorHouseFilter,
                              favorites: Set<String>, done: Set<String>, query: String) -> [HorrorHouse] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return houses.filter { house in
            let included: Bool
            switch filter {
            case .all: included = true
            case .favorites: included = favorites.contains(house.id)
            case .remaining: included = favorites.contains(house.id) && !done.contains(house.id)
            }
            return included && (query.isEmpty || house.name.localizedStandardContains(query))
        }
    }

    static func houseStatus(_ house: HorrorHouse, event: HorrorNightSnapshot, now: Date, refreshFailed: Bool) -> String {
        guard phase(for: event, at: now) != .hidden else { return "Status unavailable" }
        if now < event.night.openingTime { return "Opens with event" }
        guard !refreshFailed, isFresh(event.fetchedAt, now: now, maximumAge: 15 * 60),
              sourceVersionIsUsable(house.sourceUpdatedAt, now: now) else { return "Status unavailable" }
        switch house.status {
        case "OPEN": return "Open"
        case "DOWN": return "Temporarily down"
        case "CLOSED": return "Closed"
        case "UPCOMING": return "Opening later"
        default: return "Status unavailable"
        }
    }
}

private enum HorrorNightTheme {
    static let amber = PivotAccent.orange.color
    static let lavender = PivotAccent.purple.color
    static let surface = Color.pivotSurface
    static let muted = Color.secondary
    static let border = lavender.opacity(0.18)
}

private extension View {
    func horrorNightCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(HorrorNightTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.clear, lineWidth: 0) }
    }
}

/// Scoped to the USF event night, including its operating hours after midnight.
struct NativeHorrorNightPanel: View {
    let event: HorrorNightSnapshot
    var showHouses: Bool = true
    var refreshFailed: Bool = false
    @State private var previewExpanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let phase = HorrorNightPresentation.phase(for: event, at: context.date)
            if phase != .hidden {
                VStack(alignment: .leading, spacing: 12) {
                    if phase == .preview && showHouses {
                        DisclosureGroup(isExpanded: $previewExpanded) {
                            if showHouses { checklist(now: context.date).padding(.top, 12) }
                        } label: {
                            eventHeader(now: context.date)
                        }
                        .tint(HorrorNightTheme.amber)
                    } else {
                        eventHeader(now: context.date)
                        if showHouses { checklist(now: context.date) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .onChange(of: event.night.date) { _, _ in previewExpanded = false }
    }

    @ViewBuilder
    private func eventHeader(now: Date) -> some View {
        if showHouses {
            compactEventHeader(now: now)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Halloween Horror Nights", systemImage: "moon.stars.fill")
                    .font(.headline).foregroundStyle(HorrorNightTheme.amber)
                    .accessibilityIdentifier("hhn-event-title")
                eventHours
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { feedBadge(now: now); Spacer(minLength: 0); ticketNotice }
                    VStack(alignment: .leading, spacing: 8) { feedBadge(now: now); ticketNotice }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .horrorNightCard()
        }
    }

    private func compactEventHeader(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.body).foregroundStyle(HorrorNightTheme.amber)
                    .padding(8)
                    .background(HorrorNightTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text("Halloween Horror Nights")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hhn-event-title")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { eventDate; Spacer(minLength: 0); eventHours }
                VStack(alignment: .leading, spacing: 6) { eventDate; eventHours }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { feedBadge(now: now, compact: true); Spacer(minLength: 0); ticketNotice }
                VStack(alignment: .leading, spacing: 6) { feedBadge(now: now, compact: true); ticketNotice }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var eventDate: some View {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = HorrorNightPresentation.timeZone
        formatter.dateFormat = "EEE, MMM d"
        return Text(formatter.string(from: event.night.openingTime))
            .font(.subheadline.weight(.semibold))
    }

    private var eventHours: some View {
        Label("\(clock(event.night.openingTime)) – \(clock(event.night.closingTime))", systemImage: "clock")
            .font(.subheadline).foregroundStyle(HorrorNightTheme.muted)
    }

    private var ticketNotice: some View {
        Label("Separate ticket required", systemImage: "ticket")
            .font(.caption).foregroundStyle(HorrorNightTheme.muted)
    }

    private func feedBadge(now: Date, compact: Bool = false) -> some View {
        let state = HorrorNightPresentation.feedState(for: event, now: now, refreshFailed: refreshFailed)
        let color = state == .live ? Color.pivotMint : HorrorNightTheme.amber
        return Label(state.label, systemImage: state == .live ? "dot.radiowaves.left.and.right" : state == .preview ? "moon" : "exclamationmark.circle")
            .font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, compact ? 6 : 10).padding(.vertical, compact ? 4 : 8)
            .background(color.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.label)
            .accessibilityIdentifier("hhn-feed-status")
    }

    private func checklist(now: Date) -> some View {
        NativeHorrorNightChecklist(event: event, now: now, refreshFailed: refreshFailed)
            .id(event.night.date)
    }

    private func clock(_ date: Date) -> String {
        NativeExtrasFormatting.clock(date, timeZone: HorrorNightPresentation.timeZone)
    }
}

private struct NativeHorrorNightChecklist: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let event: HorrorNightSnapshot
    let now: Date
    let refreshFailed: Bool
    @AppStorage(HorrorNightPreferences.favoritesKey) private var favoritesJSON = "[]"
    @AppStorage(HorrorNightPreferences.sortKey) private var sortValue = HorrorHouseSort.shortest.rawValue
    @AppStorage private var doneJSON: String
    @State private var filter: HorrorHouseFilter = .all
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    init(event: HorrorNightSnapshot, now: Date, refreshFailed: Bool) {
        self.event = event
        self.now = now
        self.refreshFailed = refreshFailed
        _doneJSON = AppStorage(wrappedValue: "[]", HorrorNightPreferences.doneKey(eventDate: event.night.date))
    }

    private var favorites: Set<String> { HorrorNightPreferences.ids(from: favoritesJSON) }
    private var done: Set<String> { HorrorNightPreferences.ids(from: doneJSON) }
    private var houses: [HorrorHouse] {
        HorrorNightPresentation.sortedHouses(event, sort: HorrorHouseSort(rawValue: sortValue) ?? .shortest, now: now, refreshFailed: refreshFailed)
    }
    private var favoriteHouses: [HorrorHouse] { houses.filter { favorites.contains($0.id) } }
    private var completedCount: Int { favoriteHouses.filter { done.contains($0.id) }.count }
    private var visible: [HorrorHouse] {
        HorrorNightPresentation.visibleHouses(houses, filter: filter, favorites: favorites, done: done, query: query)
    }
    private var isPreview: Bool { now < event.night.openingTime }
    private var feedState: HorrorNightFeedState { HorrorNightPresentation.feedState(for: event, now: now, refreshFailed: refreshFailed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            nightProgress
            ViewThatFits(in: .horizontal) {
                HStack { Text("Haunted houses").font(.title2.bold()); Spacer(); sortMenu }
                VStack(alignment: .leading, spacing: 4) { Text("Haunted houses").font(.title2.bold()); sortMenu }
            }
            searchField
            filters
            if isPreview || feedState != .live {
                Label(isPreview ? "Live waits start when the event opens." : "Live waits are unavailable. Your checklist is still saved.",
                      systemImage: isPreview ? "clock" : "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(HorrorNightTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(visible) { house in houseRow(house) }
            if visible.isEmpty { emptyState }
            Text("House updates by ThemeParks.wiki")
                .font(.footnote).foregroundStyle(HorrorNightTheme.muted)
        }
    }

    private var nightProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: favoriteHouses.isEmpty ? "star" : "checkmark.circle")
                    .font(.body).foregroundStyle(HorrorNightTheme.amber).accessibilityHidden(true)
                Text(favoriteHouses.isEmpty ? "Star houses to plan your night." : "\(completedCount) of \(favoriteHouses.count) favorites done")
                    .font(.subheadline).foregroundStyle(HorrorNightTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hhn-progress-description")
                Spacer(minLength: 0)
            }
            if !favoriteHouses.isEmpty {
                ProgressView(value: Double(completedCount), total: Double(favoriteHouses.count))
                    .tint(HorrorNightTheme.amber)
                    .accessibilityLabel("Favorite house progress")
                    .accessibilityValue("\(completedCount) of \(favoriteHouses.count) completed")
            }
            let missing = favorites.subtracting(Set(houses.map(\.id))).count
            if missing > 0 {
                Text("\(missing) saved favorite\(missing == 1 ? " is" : "s are") missing from this feed. They’re still saved.")
                    .font(.caption).foregroundStyle(HorrorNightTheme.muted)
            }
        }
        .horrorNightCard(padding: 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(HorrorNightTheme.muted).accessibilityHidden(true)
            TextField("Search houses", text: $query,
                      prompt: Text("Search houses").foregroundColor(HorrorNightTheme.muted))
                .font(.body).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("hhn-house-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(HorrorNightTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Clear house search")
            }
        }
        .frame(minHeight: 48).padding(.horizontal, 14)
        .background(HorrorNightTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(HorrorNightTheme.border, lineWidth: 1) }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(HorrorHouseFilter.allCases) { filterButton($0) } }
            VStack(spacing: 6) { ForEach(HorrorHouseFilter.allCases) { filterButton($0) } }
        }
    }

    private func filterButton(_ choice: HorrorHouseFilter) -> some View {
        let selected = filter == choice
        let count = HorrorNightPresentation.visibleHouses(houses, filter: choice, favorites: favorites, done: done, query: "").count
        return Button { filter = choice } label: {
            HStack(spacing: 6) {
                Text(choice.rawValue).font(.subheadline.weight(.semibold))
                Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(selected ? Color.black.opacity(0.10) : HorrorNightTheme.lavender.opacity(0.10), in: Capsule())
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .foregroundStyle(selected ? Color.pivotBackground : HorrorNightTheme.muted)
            .background(selected ? HorrorNightTheme.amber : HorrorNightTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice == .all ? "Show all houses" : choice == .favorites ? "Show favorite houses" : "Show remaining favorite houses")
        .accessibilityValue("\(count) houses")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("hhn-filter-\(choice == .all ? "all" : choice == .favorites ? "favorites" : "remaining")")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort houses", selection: $sortValue) {
                ForEach(HorrorHouseSort.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
        } label: {
            Label(HorrorHouseSort(rawValue: sortValue)?.rawValue ?? "Shortest wait", systemImage: "arrow.up.arrow.down")
                .font(.subheadline).frame(minHeight: 44)
        }
        .tint(HorrorNightTheme.lavender)
        .accessibilityLabel("Sort haunted houses")
        .accessibilityIdentifier("hhn-sort-menu")
    }

    private func houseRow(_ house: HorrorHouse) -> some View {
        let completed = done.contains(house.id)
        return VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    houseIdentity(house)
                    waitDisplay(house)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    houseIdentity(house)
                    waitDisplay(house)
                }
            }
            Divider().overlay(HorrorNightTheme.border)
            HStack(spacing: 12) {
                favoriteButton(house)
                Button { doneJSON = HorrorNightPreferences.toggling(house.id, in: doneJSON) } label: {
                    Label(completed ? "Done · Undo" : "Mark done", systemImage: completed ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 10)
                        .background(completed ? Color.pivotMint.opacity(0.10) : HorrorNightTheme.lavender.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).foregroundStyle(completed ? Color.pivotMint : HorrorNightTheme.lavender)
                .accessibilityLabel("\(completed ? "Undo completion of" : "Mark done") \(house.name) for event night \(event.night.date)")
                .accessibilityValue(completed ? "Done" : "Not done")
                .accessibilityIdentifier("hhn-done-\(house.id)")
            }
        }
        .horrorNightCard()
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(completed ? Color.pivotMint.opacity(0.25) : Color.clear, lineWidth: 1) }
    }

    private func houseIdentity(_ house: HorrorHouse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(house.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("hhn-house-title-\(house.id)")
            statusBadge(house)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func waitDisplay(_ house: HorrorHouse) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            if let wait = HorrorNightPresentation.liveWait(for: house, event: event, now: now, refreshFailed: refreshFailed) {
                Text("\(wait)").font(.largeTitle.weight(.bold)).monospacedDigit().foregroundStyle(HorrorNightTheme.amber)
                Text("min wait").font(.caption).foregroundStyle(HorrorNightTheme.muted)
            } else {
                Text("—").font(.title.weight(.semibold)).foregroundStyle(HorrorNightTheme.muted)
                Text(isPreview ? "Not open yet" : "Wait unknown").font(.caption).foregroundStyle(HorrorNightTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HorrorNightPresentation.liveWait(for: house, event: event, now: now, refreshFailed: refreshFailed).map { "\($0) minute wait" } ?? (isPreview ? "Live wait begins when the event opens" : "Wait unknown"))
        .accessibilityIdentifier("hhn-wait-\(house.id)")
    }

    private func statusBadge(_ house: HorrorHouse) -> some View {
        let status = HorrorNightPresentation.houseStatus(house, event: event, now: now, refreshFailed: refreshFailed)
        let color: Color = status == "Open" ? .pivotMint : status == "Temporarily down" ? HorrorNightTheme.amber : HorrorNightTheme.muted
        return Label(status, systemImage: status == "Open" ? "checkmark.circle" : status == "Temporarily down" ? "pause.circle" : "clock")
            .font(.caption.weight(.medium)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func favoriteButton(_ house: HorrorHouse) -> some View {
        let selected = favorites.contains(house.id)
        return Button { favoritesJSON = HorrorNightPreferences.toggling(house.id, in: favoritesJSON) } label: {
            Image(systemName: selected ? "star.fill" : "star")
                .font(.body.weight(.semibold)).frame(minWidth: 48, minHeight: 44)
                .background(HorrorNightTheme.amber.opacity(selected ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).foregroundStyle(HorrorNightTheme.amber)
        .accessibilityLabel("\(selected ? "Remove" : "Add") \(house.name) \(selected ? "from" : "to") HHN favorites")
        .accessibilityValue(selected ? "Favorited" : "Not favorited")
        .accessibilityIdentifier("hhn-favorite-\(house.id)")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(houses.isEmpty ? "House listings unavailable" : !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No matching houses" : filter == .remaining && !favoriteHouses.isEmpty ? "All favorites done" : "No favorites yet",
                  systemImage: houses.isEmpty ? "exclamationmark.circle" : filter == .remaining && !favoriteHouses.isEmpty ? "checkmark.circle" : "star")
                .font(.headline)
            Text(houses.isEmpty ? "House listings will appear when the feed returns. Your saved favorites are kept." : !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Try a different name or clear your search." : filter == .remaining && !favoriteHouses.isEmpty ? "Switch to Favorites to undo a completed house." : "Switch to All houses and tap a star to build your night.")
                .font(.subheadline).foregroundStyle(HorrorNightTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .horrorNightCard()
        .accessibilityIdentifier("hhn-empty-state")
    }
}

#if DEBUG
/// Explicit simulator UI-test screen. Excluded from release IPAs.
struct NativeHorrorNightUITestScreen: View {
    private static var didResetPreferences = false
    private let event: HorrorNightSnapshot
    private let failed: Bool
    private let largeType: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let now = Date()
        let preview = arguments.contains("--hhn-ui-test-preview")
        let formatter = DateFormatter()
        formatter.timeZone = HorrorNightPresentation.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let eventDate = formatter.string(from: now)
        failed = arguments.contains("--hhn-ui-test-stale")
        largeType = arguments.contains("--hhn-ui-test-large-type")
        event = HorrorNightSnapshot(
            night: HorrorNight(date: eventDate, modeStartsAt: now.addingTimeInterval(preview ? 3600 : -7200),
                               openingTime: now.addingTimeInterval(preview ? 5400 : -3600), closingTime: now.addingTimeInterval(6 * 3600)),
            scheduleCheckedAt: now, fetchedAt: failed ? now.addingTimeInterval(-1800) : now,
            houses: arguments.contains("--hhn-ui-test-empty") ? [] : [
                HorrorHouse(id: "test-alpha", name: "The Haunted Conservatory", status: "OPEN", waitTime: 15, sourceUpdatedAt: now),
                HorrorHouse(id: "test-bravo", name: "A Very Long Haunted House Name for Readability", status: "DOWN", waitTime: nil, sourceUpdatedAt: now),
                HorrorHouse(id: "test-charlie", name: "Midnight Lanterns", status: "OPEN", waitTime: 0, sourceUpdatedAt: now.addingTimeInterval(-7200))
            ])
        if arguments.contains("--reset-hhn-ui-test") && !Self.didResetPreferences {
            Self.didResetPreferences = true
            UserDefaults.standard.removeObject(forKey: HorrorNightPreferences.favoritesKey)
            UserDefaults.standard.removeObject(forKey: HorrorNightPreferences.sortKey)
            UserDefaults.standard.removeObject(forKey: HorrorNightPreferences.doneKey(eventDate: eventDate))
        }
    }

    var body: some View {
        ScrollView {
            NativeHorrorNightPanel(event: event, refreshFailed: failed).padding(18)
        }
        .background(Color.pivotBackground)
        .dynamicTypeSize(largeType ? .accessibility3 : .large)
    }
}
#endif

// MARK: - Actual timestamped wait observations

enum WaitHistoryPresentation {
    static let window: TimeInterval = 6 * 60 * 60
    static let maximumSamples = 12

    static func samples(_ source: [WaitHistorySample]?, at now: Date) -> [WaitHistorySample] {
        let start = now.addingTimeInterval(-window)
        let valid = Dictionary(grouping: source ?? [], by: \.observedAt).compactMap { time, values -> WaitHistorySample? in
            guard time.timeIntervalSince1970.isFinite, time >= start, time <= now,
                  let sample = values.first, WaitLearningHistory.validWait(sample.waitTime),
                  values.allSatisfy({ $0.waitTime == sample.waitTime }) else { return nil }
            return sample
        }.sorted { $0.observedAt < $1.observedAt }
        return Array(valid.suffix(maximumSamples))
    }
}

/// Keep the disclosure's toggle inside its header. The default List disclosure
/// hit region can also receive taps intended for controls in expanded content.
private struct WaitHistoryDisclosureStyle: DisclosureGroupStyle {
    let identifier: String

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { configuration.isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}

/// Insert as a disclosure below a row's main button, and as its own detail card.
/// Every dot retains its observed time and value. Samples use equal horizontal
/// spacing so clustered polling times never obscure labels; no values are interpolated.
struct NativeWaitHistoryView: View {
    @Environment(\.pivotAccent) private var accent
    @ScaledMetric(relativeTo: .caption2) private var sampleColumnWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .caption2) private var axisAllowance: CGFloat = 60
    @ScaledMetric(relativeTo: .caption2) private var annotationAllowance: CGFloat = 26
    @ScaledMetric(relativeTo: .caption2) private var chartHeight: CGFloat = 175
    @ScaledMetric(relativeTo: .caption2) private var timeLabelHeight: CGFloat = 20
    let ride: LiveRide
    let timeZone: TimeZone
    var initiallyExpanded: Bool = false
    @State private var expanded: Bool

    init(ride: LiveRide, timeZone: TimeZone, initiallyExpanded: Bool = false) {
        self.ride = ride
        self.timeZone = timeZone
        self.initiallyExpanded = initiallyExpanded
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let samples = WaitHistoryPresentation.samples(ride.waitHistory, at: context.date)
            DisclosureGroup(isExpanded: $expanded) {
                // A collapsed ride must not construct a chart or resolve its forecast.
                if expanded {
                    VStack(alignment: .leading, spacing: 12) {
                        if samples.isEmpty {
                            Text("No recent observations yet. History appears after fresh park snapshots are collected.")
                                .font(.subheadline).foregroundStyle(Color.pivotMuted)
                                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("wait-history-empty-\(ride.id)")
                        } else {
                            chart(samples: samples)
                            Text("Up to 12 observations from the last 6 hours, in time order. Swipe for all samples. Dots are evenly spaced for readable labels; time gaps can vary. These are observed posted waits, not predictions.")
                                .font(.caption).foregroundStyle(Color.pivotMuted)
                                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                                        Text("\(ParkTimeFormatter.waitHistoryTimestamp(sample.observedAt, timeZone: timeZone)) · \(NativeExtrasFormatting.number(sample.waitTime)) min")
                                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                                            .accessibilityIdentifier("wait-sample-row-\(ride.id)-\(index)")
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            } label: {
                                Text("Sample times").frame(minHeight: 44, alignment: .leading)
                            }.font(.caption)
                                .disclosureGroupStyle(WaitHistoryDisclosureStyle(identifier: "wait-history-sample-toggle-\(ride.id)"))
                        }
                        Divider()
                        NativeRideLowWaitSummary(ride: ride, timeZone: timeZone)
                    }.padding(.top, 12)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chart.bar.fill").accessibilityHidden(true)
                    Text("Recent observed waits · \(samples.count) \(samples.count == 1 ? "sample" : "samples")")
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wait-history-title-\(ride.id)")
                }
                    .font(.caption.weight(.medium)).foregroundStyle(Color.pivotMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .tint(accent)
            .disclosureGroupStyle(WaitHistoryDisclosureStyle(identifier: "wait-history-toggle-\(ride.id)"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wait-history-\(ride.id)")
    }

    private func chart(samples: [WaitHistorySample]) -> some View {
        let maximum = max(10, samples.map(\.waitTime).max() ?? 10)
        let plotHeight = max(80, min(chartHeight, 320) - timeLabelHeight)
        let annotationPadding = min(annotationAllowance, plotHeight / 3)
        return GeometryReader { geometry in
            let plotWidth = max(geometry.size.width - axisAllowance, CGFloat(samples.count) * sampleColumnWidth)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    NativeWaitChartYAxis(maximum: maximum, height: plotHeight, padding: annotationPadding)
                        .frame(width: axisAllowance)
                    VStack(spacing: 0) {
                        Chart(Array(samples.enumerated()), id: \.element.id) { index, sample in
                            PointMark(x: .value("Observation", index), y: .value("Posted wait", sample.waitTime))
                                .foregroundStyle(accent).symbolSize(36)
                                .annotation(position: .top, spacing: 4) {
                                    Text("\(NativeExtrasFormatting.number(sample.waitTime)) min")
                                        .font(.caption2.weight(.semibold)).monospacedDigit().fixedSize()
                                        .foregroundStyle(.primary)
                                        .accessibilityIdentifier("wait-sample-value-\(ride.id)-\(index)")
                                }
                                .accessibilityLabel("Observation \(index + 1), \(ParkTimeFormatter.waitHistoryTimestamp(sample.observedAt, timeZone: timeZone))")
                                .accessibilityValue("\(NativeExtrasFormatting.number(sample.waitTime)) minutes")
                        }
                        .chartXScale(domain: -0.5...max(0.5, Double(samples.count) - 0.5),
                                     range: .plotDimension(startPadding: 0, endPadding: 0))
                        .chartYScale(domain: 0...maximum, range: .plotDimension(
                            startPadding: annotationPadding, endPadding: annotationPadding))
                        .chartXAxis { AxisMarks(values: Array(samples.indices)) { _ in AxisGridLine() } }
                        .chartYAxis { AxisMarks(values: [0.0, maximum]) { _ in AxisGridLine() } }
                        .frame(width: plotWidth, height: plotHeight)
                        // Real text outside Charts' virtual axes remains measurable
                        // and keeps the full local time at every Dynamic Type size.
                        HStack(spacing: 0) {
                            ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    Text(ParkTimeFormatter.time(sample.observedAt, timeZone: timeZone))
                                        .font(.caption2).fixedSize()
                                        .foregroundStyle(Color.pivotMuted)
                                        .accessibilityIdentifier("wait-sample-time-\(ride.id)-\(index)")
                                    Spacer(minLength: 0)
                                }
                                .frame(width: plotWidth / CGFloat(samples.count), height: timeLabelHeight)
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("observed-wait-chart-\(ride.id)")
        }
        .frame(height: min(chartHeight, 320) + 20)
        .accessibilityLabel("Observed posted wait samples for \(ride.name), last six hours. Each labeled dot is one observation, equally spaced in time order; time gaps can vary.")
    }
}

/// A separate gutter keeps axis-label width out of the measured data columns.
struct NativeWaitChartYAxis: View {
    let maximum: Double
    let height: CGFloat
    let padding: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let labelWidth = max(0, geometry.size.width - 8)
            ZStack {
                Text("\(NativeExtrasFormatting.number(maximum)) min").fixedSize()
                    .frame(width: labelWidth, alignment: .trailing)
                    .position(x: labelWidth / 2, y: padding)
                Text("0 min").fixedSize()
                    .frame(width: labelWidth, alignment: .trailing)
                    .position(x: labelWidth / 2, y: height - padding)
            }
        }
        .font(.caption2).foregroundStyle(Color.pivotMuted)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Server-controlled, uncalibrated storm-movement experiment

struct LightningDeparturePresentation {
    let range: ClosedRange<Date>?
    let headline: String
    let detail: String

    init(estimate: LightningDepartureEstimate, now: Date, refreshFailed: Bool = false) {
        range = Self.validRange(estimate, now: now, refreshFailed: refreshFailed)
        if estimate.status == "DISABLED" {
            headline = "Storm movement experiment is off"
            detail = estimate.label
        } else if range != nil {
            headline = "Storm movement outlook"
            detail = estimate.label
        } else {
            headline = "No dependable movement estimate"
            if refreshFailed { detail = "New weather data could not be fetched; the earlier movement window is withheld." }
            else if estimate.status == "EXPERIMENTAL_RANGE" { detail = "The earlier movement evidence is expired, incomplete, or not current enough to show a window." }
            else { detail = estimate.label }
        }
    }

    static func validRange(_ value: LightningDepartureEstimate, now: Date, refreshFailed: Bool) -> ClosedRange<Date>? {
        guard !refreshFailed,
              value.status == "EXPERIMENTAL_RANGE", value.reason == "PATTERN_TRANSLATING",
              value.algorithmVersion == "PIVOT_SPATIAL_DEPARTURE_EXPERIMENT_V1",
              value.calibration == "UNCALIBRATED", value.trackedRadiusMiles == 5,
              value.issuedAt <= now.addingTimeInterval(120),
              let radar = value.radarObservedAt, radar <= now,
              now.timeIntervalSince(radar) <= 12 * 60,
              let lightning = value.lightningIntervalEndAt,
              lightning <= now.addingTimeInterval(120), now.timeIntervalSince(lightning) <= 25 * 60,
              value.frameCount >= 3, value.frameTimes.count == value.frameCount, value.motion != nil,
              Set(value.frameTimes).count == value.frameTimes.count,
              value.frameTimes.allSatisfy({ $0 <= now && now.timeIntervalSince($0) <= 30 * 60 }),
              value.diagnostics.unknownRadarCells.count == value.frameCount,
              value.diagnostics.unknownRadarCells.allSatisfy({ $0 == 0 }),
              value.diagnostics.unknownLightningCells == 0,
              let start = value.earliestDepartureAt, let end = value.latestDepartureAt,
              start < end, end > now, start >= radar,
              end.timeIntervalSince(radar) <= 60 * 60 else { return nil }
        return start...end
    }
}

/// Add only when weather.lightningDeparture is present. This does not turn on
/// the server experiment, synthesize estimates, or alter operational guidance.
struct NativeLightningDepartureCard: View {
    let estimate: LightningDepartureEstimate
    let timeZone: TimeZone
    var refreshFailed: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let presentation = LightningDeparturePresentation(estimate: estimate, now: context.date, refreshFailed: refreshFailed)
            VStack(alignment: .leading, spacing: 12) {
                Text("EXPERIMENTAL · UNCALIBRATED").font(.caption.weight(.bold)).foregroundStyle(.orange)
                Text(presentation.headline).font(.title3.bold())
                Text(presentation.detail).font(.subheadline)
                if let range = presentation.range {
                    Text("\(clock(range.lowerBound))–\(clock(range.upperBound))")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .accessibilityLabel("Uncalibrated storm footprint departure window, \(clock(range.lowerBound)) to \(clock(range.upperBound))")
                }
                Text("Estimates when a lightning-associated radar footprint may move beyond five miles. New lightning can develop. This is not a final-strike prediction, a safety all-clear, or a ride-reopening signal.")
                    .font(.subheadline).foregroundStyle(Color.pivotMuted)
                DisclosureGroup("Evidence behind this estimate") {
                    VStack(alignment: .leading, spacing: 10) {
                        evidence("Radar observations", "\(estimate.frameCount) distinct frames · latest \(timestamp(estimate.radarObservedAt))")
                        evidence("Lightning density", "15-minute interval ending \(timestamp(estimate.lightningIntervalEndAt))")
                        evidence("Observed area", estimate.watchRadiusMiles.map { "\(NativeExtrasFormatting.number($0))-mile radius around the park" } ?? "Not available")
                        evidence("Pattern motion", estimate.motion.map { "\(NativeExtrasFormatting.number($0.speedMph)) mph toward \(NativeExtrasFormatting.number($0.bearingDegrees))° · \($0.agreement)" } ?? "Not established")
                        evidence("Footprint sizes", estimate.diagnostics.footprintPixelCounts.isEmpty ? "Not available" : estimate.diagnostics.footprintPixelCounts.map(String.init).joined(separator: " → ") + " rendered cells")
                        evidence("Radar source", estimate.source.radar)
                        evidence("Lightning source", estimate.source.lightning)
                        evidence("Issued", "\(timestamp(estimate.issuedAt)) · \(estimate.algorithmVersion)")
                        Text("Tracking diagnostics are not calibrated probabilities.")
                        Text(estimate.limitations)
                    }.font(.caption).foregroundStyle(Color.pivotMuted).padding(.top, 10)
                }
                .font(.subheadline).tint(.orange)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pivotCard()
            .accessibilityIdentifier("experimental-storm-departure")
        }
    }

    private func evidence(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fontWeight(.semibold).foregroundStyle(.primary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func clock(_ date: Date) -> String { NativeExtrasFormatting.clock(date, timeZone: timeZone) }
    private func timestamp(_ date: Date?) -> String {
        date.map { NativeExtrasFormatting.timestamp($0, timeZone: timeZone) } ?? "Not available"
    }
}

private enum NativeExtrasFormatting {
    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a z"
        return formatter.string(from: date)
    }
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
