import SwiftUI

struct RideListView: View {
    @Environment(\.pivotAccent) private var accent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: DashboardStore
    @Binding var query: String
    @Binding var filter: RideListFilter
    @Binding var sort: RideSort
    let radarOnly: Bool
    var usesNativeList = false
    var nativeHeader: AnyView? = nil
    var nativeFooter: AnyView? = nil
    @State private var selectedRide: LiveRide?
    @FocusState private var searchFocused: Bool

    private var rides: [LiveRide] {
        store.visibleRides(query: query, filter: radarOnly ? .radar : filter, sort: sort)
    }

    var body: some View {
        Group {
            if usesNativeList {
                nativeList
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    LazyVStack(spacing: 0) {
                        if store.isLoading && store.snapshot == nil {
                            HStack(spacing: 10) {
                                ProgressView().tint(.primary)
                                Text("Loading current rides…").font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .pivotCard()
                        } else if rides.isEmpty {
                            ContentUnavailableView {
                                Label(emptyTitle, systemImage: effectiveFilter == .radar ? (store.canAssertNoClosures() ? "checkmark.circle" : "questionmark.circle") : "magnifyingglass")
                            } description: { Text(emptyDetail) }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .pivotCard()
                        } else {
                            ForEach(rides) { ride in
                                RideRowView(ride: ride, timeZone: store.selectedPark?.timeZone ?? ParkTimeFormatter.selectedParkTimeZone) { selectedRide = ride }
                                if ride.id != rides.last?.id { Divider().padding(.leading, 16) }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedRide) { ride in
            RideDetailScreenView(initialRide: ride, timeZone: store.selectedPark?.timeZone ?? ParkTimeFormatter.selectedParkTimeZone)
        }
    }

    // Let the native List own the Waits viewport and cell virtualization. A
    // SwiftUI LazyVStack measuring inside a hidden tab's ScrollView can oscillate.
    private var nativeList: some View {
        List {
            if let nativeHeader {
                Section { nativeHeader }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section { controls.buttonStyle(.plain).pivotCard(padding: 14) }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            Section {
                if store.isLoading && store.snapshot == nil {
                    HStack(spacing: 10) {
                        ProgressView().tint(.primary)
                        Text("Loading current rides…").font(.subheadline)
                    }.frame(maxWidth: .infinity)
                } else if rides.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: effectiveFilter == .radar ? (store.canAssertNoClosures() ? "checkmark.circle" : "questionmark.circle") : "magnifyingglass")
                    } description: { Text(emptyDetail) }
                } else {
                    ForEach(rides) { ride in
                        RideRowView(ride: ride, timeZone: store.selectedPark?.timeZone ?? ParkTimeFormatter.selectedParkTimeZone) { selectedRide = ride }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.pivotSurface)
                            .listRowSeparatorTint(Color.pivotBorder)
                    }
                }
            }
            if let nativeFooter {
                Section { nativeFooter }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.horizontal, 14, for: .scrollContent)
        .contentMargins(.top, 8, for: .scrollContent)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .background(Color.pivotBackground)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refreshNow() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if radarOnly {
                HStack {
                    Text("All down rides").font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(rides.count) rides").font(.caption).foregroundStyle(Color.pivotMuted)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Current rides").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        ActiveScreenTimeline { date in
                            let health = store.feedHealth(at: date)
                            Label(health.badgeLabel, systemImage: "circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(health.isLive ? Color.pivotMint : Color.orange)
                        }
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        // Choose one stable layout at accessibility sizes. Probing
                        // competing multiline layouts can oscillate as a tab hides.
                        VStack(alignment: .leading, spacing: 6) { rideCounts; freshness }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack { rideCounts; Spacer(minLength: 8); freshness }
                            VStack(alignment: .leading, spacing: 6) { rideCounts; freshness }
                        }
                    }
                }
            }

            if let error = store.errorMessage, store.snapshot == nil {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Couldn’t refresh waits").font(.subheadline.weight(.semibold))
                        Text(error).font(.caption).foregroundStyle(Color.pivotMuted)
                    }
                    Spacer(minLength: 0)
                }
                .pivotCard(padding: 14)
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.pivotMuted)
                    TextField("Search rides or lands", text: $query)
                        .font(.body)
                        .accessibilityIdentifier("Ride search")
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onSubmit { searchFocused = false }
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.pivotMuted)
                        }
                        .frame(minWidth: 32, minHeight: 44)
                        .accessibilityLabel("Clear ride search")
                    }
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 46)
                .background(Color.pivotBackground.opacity(0.7), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.pivotBorder, lineWidth: 1).allowsHitTesting(false) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ride-search-control")

                Menu {
                    Picker("Sort rides", selection: $sort) {
                        ForEach(RideSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 46, height: 46)
                        .background(Color.pivotBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.pivotBorder, lineWidth: 1).allowsHitTesting(false) }
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("Sort rides. Current sort: \(sort.rawValue)")
                .accessibilityIdentifier("ride-sort-menu")
            }

            if !radarOnly {
                Picker("Filter rides", selection: $filter) {
                    ForEach(RideListFilter.allCases) { option in
                        Text(option == .all ? "All rides" : option == .radar ? "Down" : "Open").tag(option)
                    }
                }.pickerStyle(.segmented)
                    .frame(minHeight: 36)
                    .accessibilityIdentifier("ride-status-filter")
            }
        }
    }

    private var effectiveFilter: RideListFilter { radarOnly ? .radar : filter }

    private var rideCounts: some View {
        HStack(spacing: 14) {
            Text("\(store.reviewedRides.filter { $0.status == .open }.count) open")
            Text("\(store.reviewedRides.filter(\.isRadarDown).count) down")
        }
        .font(.caption)
        .foregroundStyle(Color.pivotMuted)
    }

    private var freshness: some View {
        ActiveScreenTimeline { date in
            let health = store.feedHealth(at: date)
            Text(health.status)
                .font(.caption2)
                .foregroundStyle(Color.pivotMuted)
        }
    }

    private var emptyTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matching rides" }
        switch effectiveFilter {
        case .all: return "No current ride data"
        case .open: return "No open ride waits"
        case .radar: return store.canAssertNoClosures() ? "No reviewed rides reported down" : "Current ride status unavailable"
        }
    }

    private var emptyDetail: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Try another ride or land name." }
        switch effectiveFilter {
        case .all: return "Pull to refresh and check for current attraction data."
        case .open: return "No reviewed attractions currently report an open wait."
        case .radar: return store.canAssertNoClosures() ? "No down rides in the current observations at \(store.selectedPark?.name ?? "this park")." : "Missing or saved data cannot establish that there are no closures. Pull to refresh."
        }
    }
}

private struct RideInformationView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let details: RideDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About this ride").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(minimum: 0), alignment: .leading)]
                : [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(details.facts) { fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.label).font(.subheadline).foregroundStyle(Color.pivotMuted)
                        Text(fact.value).font(.title3.weight(.medium)).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
            if !details.unverified.isEmpty {
                Text("Not yet verified: \(details.unverified.joined(separator: ", ").lowercased()).")
            }
            Text(details.riderNote)
            ForEach(details.sources) { source in
                Link(destination: source.url) {
                    Label(source.label, systemImage: "arrow.up.right").foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            Text("Facts reviewed \(details.reviewedAt) · not live operating data").font(.caption2)
        }
        .font(.subheadline)
        .foregroundStyle(Color.pivotMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RideDetailScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DashboardStore
    let initialRide: LiveRide
    let timeZone: TimeZone
    var mapPoint: ParkMapPoint? = nil
    private var ride: LiveRide { store.snapshot?.rides.first(where: { $0.id == initialRide.id }) ?? initialRide }
    private var artwork: ParkArtwork? { ParkArtworkCatalog.ride(parkID: store.selectedPark?.id, rideID: ride.id) }
    private var illustration: RideIllustration? { RideIllustrationCatalog.ride(parkID: store.selectedPark?.id, rideID: ride.id) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RetainedSnapshotNotice()
                    if let illustration {
                        VStack(alignment: .leading, spacing: 8) {
                            RideIllustrationImage(artwork: illustration, detail: true, contentMode: .fit)
                                .frame(width: min(352, max(0, geometry.size.width - 40)), height: min(440, max(0, geometry.size.width - 40) * 1.25))
                                .clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("ride-illustration-\(illustration.id)")
                            RideIllustrationCredit(artwork: illustration)
                        }
                    } else if let photo = artwork?.photo ?? ride.details?.photo {
                        VStack(alignment: .leading, spacing: 8) {
                            Group {
                                if let artwork {
                                    Image(artwork.assetName).resizable().scaledToFill()
                                        .frame(width: max(0, geometry.size.width - 40), height: min(280, max(0, geometry.size.width - 40) * 0.75)).clipped()
                                        .accessibilityLabel(photo.alt)
                                } else {
                                    AsyncImage(url: photo.url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                                .frame(width: max(0, geometry.size.width - 40), height: min(280, max(0, geometry.size.width - 40) * 0.75)).clipped()
                                                .accessibilityLabel(photo.alt)
                                        } else if phase.error != nil {
                                            Text("The ride photo couldn’t load.").foregroundStyle(Color.pivotMuted).frame(maxWidth: .infinity, minHeight: 100)
                                        } else {
                                            ProgressView().frame(maxWidth: .infinity, minHeight: 280)
                                        }
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            VStack(alignment: .leading, spacing: 6) {
                                Link("Photo: \(photo.credit)", destination: photo.sourceURL)
                                Link(photo.license, destination: photo.licenseURL)
                            }
                            .font(.caption).foregroundStyle(Color.pivotMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.selectedPark?.name ?? "Ride information").font(.subheadline).foregroundStyle(Color.pivotMuted)
                        Text(ride.name).font(.largeTitle.weight(.bold)).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !ride.land.isEmpty { Text(ride.land).font(.subheadline).foregroundStyle(Color.pivotMuted) }
                    }
                    if illustration == nil && ride.details?.photo == nil && artwork == nil {
                        Text("A verified ride photo isn’t available yet.").font(.subheadline).foregroundStyle(Color.pivotMuted)
                    }
                    ActiveScreenTimeline(every: 15) { date in
                        VStack(alignment: .leading, spacing: 10) {
                            if let mapPoint {
                                let status = ParkMapRidePresentation.resolve(point: mapPoint, parkID: store.selectedPark?.id,
                                    snapshot: store.snapshot, refreshFailed: store.errorMessage != nil, at: date)
                                Text(status.waitMinutes == nil ? "Ride status" : "Current wait").font(.caption).foregroundStyle(.secondary)
                                Text(status.title).font(.title2.weight(.semibold))
                                Text(status.detail).font(.caption).foregroundStyle(Color.pivotMuted)
                            } else {
                                let current = RideWaitPresentation.resolve(rideID: ride.id, parkID: store.selectedPark?.id,
                                    snapshot: store.snapshot, refreshFailed: store.errorMessage != nil, at: date)
                                Text(current.waitMinutes == nil ? "Ride status" : "Current wait").font(.caption).foregroundStyle(.secondary)
                                Text(current.title).font(.title2.weight(.semibold))
                            }
                            if store.feedHealth(at: date).isLive, let downtime = ride.downTimePresentation { Text(downtime.text).accessibilityLabel(downtime.accessibilityLabel) }
                            if ride.hasWeatherHold, let clearance = ride.delayEvidence?.rideWeatherClearanceDescription {
                                Label(clearance, systemImage: "bolt.shield.fill").foregroundStyle(Color.pivotWeather)
                            }
                            if ride.status == .down {
                                let guidance = ReopeningGuidance.presentation(ride: ride, snapshot: store.snapshot,
                                    feedHealth: store.feedHealth(at: date), at: date, timeZone: timeZone)
                                Text(guidance.headline).font(.headline)
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("reopening-headline-\(ride.id)")
                                if let range = guidance.range {
                                    Text(range).font(.headline)
                                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("reopening-window-\(ride.id)")
                                }
                                Text(guidance.bestPredictionLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("reopening-best-prediction-\(ride.id)")
                                Text(guidance.detail).foregroundStyle(Color.pivotMuted)
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("reopening-detail-\(ride.id)")
                            }
                            if ride.status == .scheduled {
                                if let closure = ride.scheduledClosure {
                                    Text(closure.expectedReopenAt.map { "Expected reopen \(ParkTimeFormatter.dateTime($0, timeZone: timeZone))" } ?? "Expected reopen date not published")
                                    Text("Reviewed operator schedule · \(closure.source.name)")
                                }
                                if let window = ride.operatingWindow { Text(window.label) }
                            }
                            Text("Waits & status from ThemeParks.wiki").font(.caption).foregroundStyle(Color.pivotMuted)
                        }
                        .font(.subheadline).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).pivotCard()
                    }
                    NativeWaitHistoryView(ride: ride, timeZone: timeZone, initiallyExpanded: true).pivotCard()
                    if let details = ride.details { RideInformationView(details: details).pivotCard() }
                }
                .frame(width: max(0, geometry.size.width - 40), alignment: .leading)
                .padding(20)
            }
            }
            .background(Color.pivotBackground)
            .navigationTitle("Ride information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(.primary) } }
        }
        .modifier(PivotUITestTypeSize(probeIdentifier: "Ride information body size"))
    }
}

private struct RideRowView: View {
    @Environment(\.pivotAccent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var store: DashboardStore
    let ride: LiveRide
    let timeZone: TimeZone
    let onSelect: () -> Void

    var body: some View {
        ActiveScreenTimeline(every: 15) { date in
            let current = RideWaitPresentation.resolve(rideID: ride.id, parkID: store.selectedPark?.id,
                snapshot: store.snapshot, refreshFailed: store.errorMessage != nil, at: date)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    onSelect()
                } label: {
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 12) {
                                rideDescription(current)
                                HStack(spacing: 12) {
                                    RideThumbnailView(ride: ride, parkID: store.selectedPark?.id)
                                    waitDisplay(current)
                                    Spacer(minLength: 0)
                                    disclosureArrow
                                }
                            }
                        } else {
                            HStack(alignment: .center, spacing: 10) {
                                RideThumbnailView(ride: ride, parkID: store.selectedPark?.id)
                                rideDescription(current)
                                waitDisplay(current)
                                disclosureArrow
                            }
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilitySummary(current))
                .accessibilityHint("Double tap to open the ride information screen")

                NativeWaitHistoryView(ride: ride, timeZone: timeZone)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.pivotSurfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.pivotBorder.opacity(0.6), lineWidth: 0.75).allowsHitTesting(false) }
                    .padding(.top, 12)

                if ride.status == .down {
                    let guidance = ReopeningGuidance.presentation(ride: ride, snapshot: store.snapshot,
                        feedHealth: store.feedHealth(at: date), at: date, timeZone: timeZone)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: ride.hasWeatherHold ? "cloud.bolt" : "arrow.uturn.forward")
                            .foregroundStyle(statusColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(guidance.headline).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("reopening-headline-\(ride.id)")
                            if let range = guidance.range {
                                Text(range).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("reopening-window-\(ride.id)")
                            }
                            Text(guidance.bestPredictionLabel).font(.caption.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("reopening-best-prediction-\(ride.id)")
                            Text(guidance.detail).font(.caption).foregroundStyle(Color.pivotMuted)
                                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("reopening-detail-\(ride.id)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 24)
                    .overlay(alignment: .top) { Rectangle().fill(Color.pivotBorder).frame(height: 1).padding(.top, 12) }
                }

            }
            .padding(14)
            .background(Color.pivotSurface)
        }
    }

    private func rideDescription(_ current: RideWaitPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ride.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !ride.land.isEmpty {
                Label(ride.land, systemImage: "globe.americas.fill")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                PivotStatusDot(color: current.isCurrent ? statusColor : Color.pivotMuted)
                Text(current.isCurrent ? subtitle : current.title).font(.caption).foregroundStyle(Color.pivotMuted)
            }
            if current.isCurrent, let downtime = ride.downTimePresentation {
                Text(downtime.text).font(.caption.weight(.medium)).foregroundStyle(.primary)
                    .accessibilityLabel(downtime.accessibilityLabel)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclosureArrow: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            .foregroundStyle(Color.pivotMuted).accessibilityHidden(true)
    }

    private var subtitle: String {
        let state: String
        switch ride.status {
        case .open: state = ride.waitTime == nil ? "Open · wait not posted" : "Open"
        case .down: state = ride.downStatusLabel
        case .scheduled: state = ride.operatingWindow?.label ?? (ride.scheduledClosure == nil ? "Scheduled closed" : "Refurbishment")
        case .stale: state = "Updating status"
        case .parkInactive: state = "Park not active"
        case .unknown: state = "Status unavailable"
        }
        return state
    }

    @ViewBuilder
    private func waitDisplay(_ current: RideWaitPresentation) -> some View {
        if let wait = current.waitMinutes {
            VStack(spacing: 0) {
                Text("\(wait)").font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit().tracking(-1.5)
                Text("min").font(.caption)
            }
            .foregroundStyle(wait <= 20 ? Color.pivotMint : wait <= 50 ? PivotAccent.orange.color : Color.pivotPink)
            .frame(minWidth: 48)
            .accessibilityHidden(true)
        } else {
            Text(!current.isCurrent ? "—" : current.title == "Park not active" ? "Closed" : ride.status == .down ? "Down" : ride.status == .scheduled ? "Closed" : "—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(current.isCurrent ? statusColor : Color.pivotMuted)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.08), in: Capsule())
                .accessibilityHidden(true)
        }
    }

    private var statusColor: Color {
        switch ride.status {
        case .open: .pivotMint
        case .down where ride.hasWeatherHold: .pivotWeather
        case .down: .pivotPink
        default: .pivotMuted
        }
    }

    private func accessibilitySummary(_ current: RideWaitPresentation) -> String {
        var parts = [ride.name, ride.land]
        if current.isCurrent { parts.append(ride.statusDescription) }
        if let wait = current.waitMinutes { parts.append("\(wait) minute wait") }
        else { parts.append(current.title) }
        if current.isCurrent, let downtime = ride.downTimePresentation { parts.append(downtime.accessibilityLabel) }
        return parts.joined(separator: ". ")
    }
}
