import SwiftUI

struct RideListView: View {
    @Environment(\.pivotAccent) private var accent
    @EnvironmentObject private var store: DashboardStore
    @Binding var query: String
    @Binding var filter: RideListFilter
    @Binding var sort: RideSort
    let radarOnly: Bool
    @State private var selectedRide: LiveRide?

    private var rides: [LiveRide] {
        store.visibleRides(query: query, filter: radarOnly ? .radar : filter, sort: sort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if radarOnly {
                HStack {
                    Text("All down rides").font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(rides.count) rides").font(.caption).foregroundStyle(Color.pivotMuted)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Wait times").font(.largeTitle.weight(.bold)).tracking(-1.2)
                        Spacer(minLength: 8)
                        Label(feedLabel, systemImage: "circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(feedIsLive ? Color.pivotMint : Color.pivotMuted)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { rideCounts; Spacer(minLength: 8); freshness }
                        VStack(alignment: .leading, spacing: 6) { rideCounts; freshness }
                    }
                }
                .padding(.top, 4)
            }

            if let error = store.errorMessage {
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
                .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 13))

                Menu {
                    Picker("Sort rides", selection: $sort) {
                        ForEach(RideSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 46, height: 46)
                        .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 13))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Sort rides. Current sort: \(sort.rawValue)")
                .accessibilityIdentifier("ride-sort-menu")
            }

            if !radarOnly {
                HStack(spacing: 4) {
                    ForEach(RideListFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option == .all ? "All rides" : option == .radar ? "Down" : "Open")
                                .font(.subheadline.weight(filter == option ? .semibold : .medium))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(filter == option ? Color.pivotBackground : Color.pivotMuted)
                                .background(filter == option ? accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityLabel("Filter rides")
            }

            LazyVStack(spacing: 8) {
                if store.isLoading && store.snapshot == nil {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Loading current rides…").font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .pivotCard()
                } else if rides.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: effectiveFilter == .radar ? "checkmark.circle" : "magnifyingglass")
                    } description: { Text(emptyDetail) }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .pivotCard()
                } else {
                    ForEach(rides) { ride in
                        RideRowView(ride: ride, timeZone: store.selectedPark?.timeZone ?? ParkTimeFormatter.selectedParkTimeZone) { selectedRide = ride }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedRide) { ride in
            RideDetailScreenView(initialRide: ride, timeZone: store.selectedPark?.timeZone ?? ParkTimeFormatter.selectedParkTimeZone)
        }
    }

    private var feedIsLive: Bool { store.snapshot?.feedHealthy == true && store.errorMessage == nil }
    private var feedLabel: String { store.errorMessage != nil ? "Offline" : feedIsLive ? "Live" : "Updating" }
    private var effectiveFilter: RideListFilter { radarOnly ? .radar : filter }

    private var rideCounts: some View {
        HStack(spacing: 14) {
            Text("\(store.reviewedRides.filter { $0.status == .open }.count) open")
            Text("\(store.reviewedRides.filter(\.isRadarDown).count) down")
        }
        .font(.subheadline)
        .foregroundStyle(Color.pivotMuted)
    }

    private var freshness: some View {
        Text(store.snapshot == nil ? "Checking the park…" : "Checked \(ParkTimeFormatter.age(store.snapshot?.fetchedAt))")
            .font(.caption)
            .foregroundStyle(Color.pivotMuted)
    }

    private var emptyTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matching rides" }
        switch effectiveFilter {
        case .all: return "No current ride data"
        case .open: return "No open ride waits"
        case .radar: return "Reopen Radar is clear"
        }
    }

    private var emptyDetail: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Try another ride or land name." }
        switch effectiveFilter {
        case .all: return "Pull to refresh and check for current attraction data."
        case .open: return "No reviewed attractions currently report an open wait."
        case .radar: return "No rides are currently reported down at \(store.selectedPark?.name ?? "this park")."
        }
    }
}

private struct RideInformationView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let details: RideDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About this ride").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(minimum: 0), alignment: .leading)]
                : [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(details.facts) { fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.label).font(.subheadline).foregroundStyle(Color.pivotMuted)
                        Text(fact.value).font(.title3.weight(.medium)).foregroundStyle(.white)
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
                    Label(source.label, systemImage: "arrow.up.right").foregroundStyle(.white)
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

private struct RideDetailScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DashboardStore
    let initialRide: LiveRide
    let timeZone: TimeZone
    private var ride: LiveRide { store.snapshot?.rides.first(where: { $0.id == initialRide.id }) ?? initialRide }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let photo = ride.details?.photo {
                        VStack(alignment: .leading, spacing: 8) {
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
                        Text(ride.name).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if !ride.land.isEmpty { Text(ride.land).font(.subheadline).foregroundStyle(Color.pivotMuted) }
                    }
                    if ride.details?.photo == nil { Text("A verified ride photo isn’t available yet.").font(.subheadline).foregroundStyle(Color.pivotMuted) }
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(ride.statusDescription).font(.headline)
                            if ride.status == .open {
                                Text(ride.waitTime.map { "\($0) min wait" } ?? "Wait not posted").font(.title2.weight(.semibold))
                            }
                            if let downtime = ride.downTimePresentation { Text(downtime.text).accessibilityLabel(downtime.accessibilityLabel) }
                            if ride.hasWeatherHold, let clearance = ride.delayEvidence?.rideWeatherClearanceDescription {
                                Label(clearance, systemImage: "bolt.shield.fill").foregroundStyle(Color.pivotWeather)
                            }
                            if let forecast = ride.estimate?.presentation(timeZone: timeZone), ride.status == .down {
                                Text("\(forecast.headline) · \(forecast.range)").font(.headline)
                                Text("Best guess \(forecast.bestGuess)")
                                if let note = ride.retainedOperationalWeatherNote { Text(note).foregroundStyle(Color.pivotWeather) }
                                Text(forecast.detail).foregroundStyle(Color.pivotMuted)
                                if let reason = ride.estimateReason { Text(reason).foregroundStyle(Color.pivotMuted) }
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
                        .font(.subheadline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading).pivotCard()
                    }
                    if let details = ride.details { RideInformationView(details: details).pivotCard() }
                }
                .frame(width: max(0, geometry.size.width - 40), alignment: .leading)
                .padding(20)
            }
            }
            .background(Color.pivotBackground)
            .navigationTitle("Ride information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(.white) } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct RideRowView: View {
    @Environment(\.pivotAccent) private var accent
    let ride: LiveRide
    let timeZone: TimeZone
    let onSelect: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    onSelect()
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ride.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Circle().fill(statusColor).frame(width: 5, height: 5).accessibilityHidden(true)
                                Text(subtitle).font(.caption).foregroundStyle(Color.pivotMuted)
                            }
                            if let downtime = ride.downTimePresentation {
                                Text(downtime.text)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                    .accessibilityLabel(downtime.accessibilityLabel)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        waitDisplay
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.pivotMuted.opacity(0.7))
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityHint("Double tap to open the ride information screen")

                if let forecast = ride.estimate?.presentation(timeZone: timeZone), ride.status == .down {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: ride.hasWeatherHold ? "cloud.bolt" : "arrow.uturn.forward")
                            .foregroundStyle(statusColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(forecast.headline) · \(forecast.range)")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            Text("Best guess \(forecast.bestGuess)")
                                .font(.caption).foregroundStyle(Color.pivotMuted)
                            if let note = ride.retainedOperationalWeatherNote {
                                Text(note).font(.caption).foregroundStyle(Color.pivotWeather)
                            }
                        }
                    }
                    .padding(.top, 24)
                    .overlay(alignment: .top) { Rectangle().fill(Color.pivotBorder).frame(height: 1).padding(.top, 12) }
                }

            }
            .padding(16)
            .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.pivotBorder, lineWidth: 1) }
        }
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
        return ride.land.isEmpty ? state : "\(ride.land) · \(state)"
    }

    @ViewBuilder
    private var waitDisplay: some View {
        if ride.status == .open, let wait = ride.waitTime {
            VStack(spacing: 0) {
                Text("\(wait)").font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().tracking(-1.5)
                Text("min").font(.caption)
            }
            .foregroundStyle(wait <= 20 ? Color.pivotMint : wait <= 50 ? Color.orange : Color.pivotPink)
            .frame(minWidth: 48)
            .accessibilityHidden(true)
        } else {
            Text(ride.status == .down ? "Down" : ride.status == .scheduled || ride.status == .parkInactive ? "Closed" : "—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
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

    private var accessibilitySummary: String {
        var parts = [ride.name, ride.land, ride.statusDescription]
        if ride.status == .open, let wait = ride.waitTime { parts.append("\(wait) minute wait") }
        if let downtime = ride.downTimePresentation { parts.append(downtime.accessibilityLabel) }
        return parts.joined(separator: ". ")
    }
}
