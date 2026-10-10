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
              isFresh(house.sourceUpdatedAt, now: now, maximumAge: 15 * 60),
              house.status == "OPEN", let wait = house.waitTime, wait >= 0 else { return nil }
        return wait
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
            isFresh($0.sourceUpdatedAt, now: now, maximumAge: 15 * 60)
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
              isFresh(house.sourceUpdatedAt, now: now, maximumAge: 15 * 60) else { return "Status unavailable" }
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
    static let amber = Color(red: 1, green: 0.72, blue: 0.40)
    static let lavender = Color(red: 0.79, green: 0.70, blue: 1)
    static let surface = Color(red: 0.095, green: 0.080, blue: 0.125)
    static let muted = Color(red: 0.73, green: 0.70, blue: 0.79)
    static let border = lavender.opacity(0.18)
}

private extension View {
    func horrorNightCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(HorrorNightTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(HorrorNightTheme.border, lineWidth: 1) }
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
                VStack(alignment: .leading, spacing: 16) {
                    if phase == .preview && showHouses {
                        DisclosureGroup(isExpanded: $previewExpanded) {
                            if showHouses { checklist(now: context.date).padding(.top, 16) }
                        } label: {
                            eventHeader(now: context.date)
                        }
                        .tint(HorrorNightTheme.amber)
                        .accessibilityIdentifier("hhn-tonight-preview")
                    } else {
                        eventHeader(now: context.date)
                        if showHouses { checklist(now: context.date) }
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .onChange(of: event.night.date) { _, _ in previewExpanded = false }
    }

    @ViewBuilder
    private func eventHeader(now: Date) -> some View {
        if showHouses {
            fullEventHeader(now: now)
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

    private func fullEventHeader(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2).foregroundStyle(HorrorNightTheme.amber)
                    .padding(12)
                    .background(HorrorNightTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("UNIVERSAL ORLANDO")
                        .font(.caption.weight(.semibold)).tracking(1.4)
                        .foregroundStyle(HorrorNightTheme.lavender)
                    Text("Halloween Horror Nights")
                        .font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("hhn-event-title")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { eventDate; Spacer(minLength: 0); eventHours }
                VStack(alignment: .leading, spacing: 6) { eventDate; eventHours }
            }
            Divider().overlay(HorrorNightTheme.border)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { feedBadge(now: now); Spacer(minLength: 0); ticketNotice }
                VStack(alignment: .leading, spacing: 10) { feedBadge(now: now); ticketNotice }
            }
            if now < event.night.openingTime && showHouses {
                Text("Browse tonight’s houses and save your favorites.")
                    .font(.subheadline).foregroundStyle(HorrorNightTheme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.10, blue: 0.27), HorrorNightTheme.surface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(HorrorNightTheme.lavender.opacity(0.25), lineWidth: 1) }
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

    private func feedBadge(now: Date) -> some View {
        let state = HorrorNightPresentation.feedState(for: event, now: now, refreshFailed: refreshFailed)
        let color = state == .live ? Color.pivotMint : HorrorNightTheme.amber
        return Label(state.label, systemImage: state == .live ? "dot.radiowaves.left.and.right" : state == .preview ? "moon" : "exclamationmark.circle")
            .font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 8)
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
        VStack(alignment: .leading, spacing: 16) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your night").font(.headline)
                    Text(favoriteHouses.isEmpty ? "Star the houses you want to visit." : "\(completedCount) of \(favoriteHouses.count) favorites done")
                        .font(.subheadline).foregroundStyle(HorrorNightTheme.muted)
                        .accessibilityIdentifier("hhn-progress-description")
                }
                Spacer(minLength: 12)
                Image(systemName: favoriteHouses.isEmpty ? "star" : "checkmark.circle")
                    .font(.title2).foregroundStyle(HorrorNightTheme.amber).accessibilityHidden(true)
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
        .horrorNightCard()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(HorrorNightTheme.muted).accessibilityHidden(true)
            TextField("Search houses", text: $query)
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
                HorrorHouse(id: "test-charlie", name: "Midnight Lanterns", status: "OPEN", waitTime: 0, sourceUpdatedAt: now)
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
        var seen = Set<Date>()
        let valid = (source ?? []).filter {
            $0.waitTime.isFinite && $0.waitTime >= 0 &&
            $0.observedAt >= start && $0.observedAt <= now &&
            seen.insert($0.observedAt).inserted
        }.sorted { $0.observedAt < $1.observedAt }
        return Array(valid.suffix(maximumSamples))
    }
}

/// Insert as a disclosure below a row's main button, and as its own detail card.
/// Dots use real observation time on a continuous six-hour axis; no connecting
/// line, interpolated point, trend timestamp, or prediction is generated.
struct NativeWaitHistoryView: View {
    @Environment(\.pivotAccent) private var accent
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
                VStack(alignment: .leading, spacing: 12) {
                    if samples.isEmpty {
                        Text("No recent observations yet. History appears after fresh park snapshots are collected.")
                            .font(.subheadline).foregroundStyle(Color.pivotMuted)
                    } else {
                        chart(samples: samples, now: context.date)
                        Text("Up to 12 PIVOT observations in the last 6 hours. Dots preserve collection gaps; these are posted waits, not predictions.")
                            .font(.caption).foregroundStyle(Color.pivotMuted)
                        DisclosureGroup("Sample times") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(samples) { sample in
                                    Text("\(NativeExtrasFormatting.timestamp(sample.observedAt, timeZone: timeZone)) · \(NativeExtrasFormatting.number(sample.waitTime)) min")
                                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.caption)
                    }
                }.padding(.top, 12)
            } label: {
                Text("Recent observed waits · \(samples.count) samples").font(.caption.weight(.medium))
            }
            .tint(accent)
        }
        .accessibilityIdentifier("wait-history-\(ride.id)")
    }

    private func chart(samples: [WaitHistorySample], now: Date) -> some View {
        let start = now.addingTimeInterval(-WaitHistoryPresentation.window)
        let maximum = max(10, samples.map(\.waitTime).max() ?? 10)
        return Chart(samples) { sample in
            PointMark(x: .value("Observed at", sample.observedAt), y: .value("Posted wait", sample.waitTime))
                .foregroundStyle(accent).symbolSize(36)
                .accessibilityLabel(NativeExtrasFormatting.timestamp(sample.observedAt, timeZone: timeZone))
                .accessibilityValue("\(NativeExtrasFormatting.number(sample.waitTime)) minutes")
        }
        .chartXScale(domain: start...now)
        .chartYScale(domain: 0...(maximum * 1.1))
        .chartXAxis {
            AxisMarks(values: [start, now]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(NativeExtrasFormatting.clock(date, timeZone: timeZone))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, maximum]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text("\(NativeExtrasFormatting.number(minutes)) m") }
                }
            }
        }
        .frame(height: 145)
        .accessibilityLabel("Observed posted wait samples for \(ride.name), last six hours. Gaps have no observations.")
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pivotCard()
            .accessibilityIdentifier("experimental-storm-departure")
        }
    }

    private func evidence(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fontWeight(.semibold).foregroundStyle(.white)
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
