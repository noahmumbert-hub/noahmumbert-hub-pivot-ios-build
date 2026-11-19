import SwiftUI

/// Replaces the old private DayPlannerView within the existing Plan tab.
struct NativeDayPlannerView: View {
    @Environment(\.pivotAccent) private var accent
    let park: FloridaPark?
    let snapshot: LiveParkSnapshot?
    let isRefreshing: Bool
    let feedIsLive: Bool
    @ObservedObject var experience: NativeDayExperienceStore
    let onChoosePark: () -> Void

    @State private var showFavorites = false
    @State private var showCommitment = false
    @State private var showWindow = false
    @State private var showPack = false
    @State private var removePack = false
    @State private var message: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your day").font(.largeTitle.bold()).tracking(-1.2)
                        .accessibilityIdentifier("Today planner title")
                    Text("Favorite rides, fixed stops, and what’s still ahead.")
                        .font(.subheadline).foregroundStyle(Color.pivotMuted)
                }
                if let park {
                    content(park: park, now: context.date)
                } else {
                    Button(action: onChoosePark) {
                        Label("Choose a park to build your day", systemImage: "map")
                            .frame(maxWidth: .infinity, minHeight: 44).pivotCard()
                    }.buttonStyle(.plain)
                }
            }
        }
        .onChange(of: park?.id) { _, _ in
            message = nil; showFavorites = false; showCommitment = false; showWindow = false; showPack = false
        }
    }

    @ViewBuilder
    private func content(park: FloridaPark, now: Date) -> some View {
        let current = snapshot.flatMap { $0.parkId == park.id ? $0 : nil }
        let day = experience.state(for: park, at: now)
        let favorites = experience.favorites(for: park)
        let window = visitWindow(park: park, snapshot: current, day: day, now: now)
        let fresh = feedIsLive && DashboardFeedHealth.presentation(parkSelected: true, snapshot: current,
                          isLoading: isRefreshing, refreshFailed: false, at: now).isLive
        let route = fresh ? current.map {
            NativeDayPlanning.build(rides: $0.rides, favoriteIDs: favorites, day: day, park: park,
                                    startAt: window.start, endAt: window.end, now: now)
        } : nil
        let pack = experience.pack(for: park)

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(favorites.count) favorite rides").font(.headline)
                Spacer()
                Button("Choose / edit") { showFavorites = true }.font(.subheadline.bold())
                    .disabled(current == nil && pack == nil && favorites.isEmpty)
                    .accessibilityIdentifier("native-day-favorites")
            }.pivotCard()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Visit window").font(.headline)
                    Spacer()
                    Button("Edit") { showWindow = true }
                }
                Text("\(time(window.start, park)) – \(time(window.end, park))")
                    .font(.title3.weight(.semibold))
                Text("\(NativeDayPlanning.localDay(park: park, at: now)) · \(park.timeZone.identifier)")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
                startPicker(park: park, rides: current?.rides ?? [], day: day, now: now)
                Text("Manual starting point. Ride coordinates are reviewed; land centers and walking times are approximate. No location tracking is used.")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
            }.pivotCard()
            commitments(park: park, day: day, route: route, window: window, now: now)
            progress(park: park, rides: current?.rides ?? [], savedRides: pack?.rides ?? [], favorites: favorites, day: day, now: now)

            if let route {
                routeCard(route, park: park, rides: current?.rides ?? [], now: now)
            } else {
                Label(isRefreshing ? "Checking current conditions…" : "Current route unavailable", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text("Live planning resumes after a fresh park update. Your day progress and fixed stops remain editable. Open a saved day pack below for its saved route and reference details.")
                    .font(.subheadline).foregroundStyle(Color.pivotMuted)
            }
            offlineCard(park: park, snapshot: current, route: route, pack: pack, sourceIsLive: fresh, now: now)
            if let message {
                Text(message).font(.callout).foregroundStyle(accent).accessibilityAddTraits(.updatesFrequently)
            }
            if let warning = experience.storageMessage {
                Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $showFavorites) {
            NativeFavoriteSelectionView(park: park, liveRides: current?.rides ?? [], savedRides: pack?.rides ?? [], experience: experience)
        }
        .sheet(isPresented: $showCommitment) {
            NativeCommitmentEditor(park: park, rides: current?.rides ?? [], now: now, experience: experience)
        }
        .sheet(isPresented: $showWindow) {
            NativeVisitWindowEditor(park: park, start: window.start, end: window.end, experience: experience)
        }
        .sheet(isPresented: $showPack) {
            if let saved = experience.pack(for: park) { NativeOfflineDayPackView(pack: saved) }
        }
        .confirmationDialog("Remove this park’s saved offline pack?", isPresented: $removePack, titleVisibility: .visible) {
            Button("Remove saved pack", role: .destructive) {
                perform { try experience.removePack(for: park); message = "Saved pack removed." }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func visitWindow(park: FloridaPark, snapshot: LiveParkSnapshot?, day: NativeDayState, now: Date) -> (start: Date, end: Date) {
        if let start = day.visitStart, let end = day.visitEnd { return (start, end) }
        return NativeDayPlanning.defaultWindow(park: park, hours: snapshot?.parkHours, at: now)
    }

    private func startPicker(park: FloridaPark, rides: [LiveRide], day: NativeDayState, now: Date) -> some View {
        let located = uniqueRides(rides).filter { $0.radarEligible && NativeDayPlanning.validLocation($0.location) }
            .sorted { $0.name < $1.name }
        let lands = Set(located.map(\.land)).sorted()
        let choices = Set(["entrance"] + located.map { "ride:\($0.id)" } + lands.map { "land:\($0)" })
        return Picker("Start from", selection: Binding(get: { day.start }, set: { value in
            perform { try experience.setStart(value, park: park, now: now) }
        })) {
            Text("Park entrance").tag("entrance")
            if !choices.contains(day.start) { Text("Saved start unavailable · entrance fallback").tag(day.start) }
            Section("Reviewed ride location") {
                ForEach(located) { ride in Text(ride.name).tag("ride:\(ride.id)") }
            }
            Section("Approximate land center") {
                ForEach(lands, id: \.self) { land in Text(land).tag("land:\(land)") }
            }
        }.tint(accent).accessibilityIdentifier("native-day-start")
    }

    private func commitments(park: FloridaPark, day: NativeDayState, route: NativeDayRoute?,
                             window: (start: Date, end: Date), now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keep time for").font(.headline)
                Spacer()
                Button("Add stop") { showCommitment = true }.accessibilityIdentifier("native-day-add-stop")
            }
            Text("Add shows from Shows, or reserve lunch and manual return windows. Nothing is booked.")
                .font(.caption).foregroundStyle(Color.pivotMuted)
            if day.commitments.isEmpty { Text("No fixed stops yet").font(.subheadline).foregroundStyle(Color.pivotMuted) }
            ForEach(day.commitments.sorted { $0.startAt < $1.startAt }) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(item.title).font(.subheadline.bold())
                        Spacer()
                        Button("Remove", role: .destructive) {
                            perform { try experience.removeCommitment(id: item.id, park: park, now: now) }
                        }.font(.caption).frame(minHeight: 44).accessibilityLabel("Remove \(item.title)")
                    }
                    Text("\(time(item.startAt, park))–\(time(item.endAt, park)) · \(item.bufferMinutes) min early")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                    if let scheduled = route?.commitments.first(where: { $0.id == item.id }) {
                        Text("Leave by \(time(scheduled.leaveBy, park)) · reserve \(scheduled.transferMinutes) min walking")
                            .font(.caption)
                        ForEach(scheduled.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    } else if item.endAt <= now {
                        Text("This stop has ended").font(.caption).foregroundStyle(Color.pivotMuted)
                    } else if item.startAt >= window.end || item.endAt <= window.start {
                        Text("Outside your visit window").font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Walking and timing check needs a fresh park update").font(.caption).foregroundStyle(Color.pivotMuted)
                    }
                    if item.location == nil { Text("Location unspecified; route reserves a conservative transfer").font(.caption).foregroundStyle(Color.pivotMuted) }
                    if let note = item.note { Text(note).font(.caption).foregroundStyle(Color.pivotMuted) }
                }
                if item.id != day.commitments.sorted(by: { $0.startAt < $1.startAt }).last?.id { Divider() }
            }
        }.pivotCard()
    }

    private func progress(park: FloridaPark, rides: [LiveRide], savedRides: [NativeOfflineRide], favorites: Set<Int>,
                          day: NativeDayState, now: Date) -> some View {
        let names = nameLookup(rides: rides, saved: savedRides)
        let ids = favorites.sorted { (names[$0] ?? "\($0)") < (names[$1] ?? "\($1)") }
        let done = ids.filter { day.progress[$0] == .done }.count
        let skipped = ids.filter { day.progress[$0] == .skip }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Today’s progress").font(.headline)
            Text("\(done) done · \(skipped) skipped · \(ids.count - done - skipped) remaining")
                .font(.subheadline).foregroundStyle(accent)
            Text("Done and Skip affect this park’s local day only. Your permanent favorites stay selected. Undo brings a ride back into the remaining plan.")
                .font(.caption).foregroundStyle(Color.pivotMuted)
            if ids.isEmpty { Text("Choose favorite rides to begin").font(.subheadline) }
            ForEach(ids, id: \.self) { id in
                VStack(alignment: .leading, spacing: 8) {
                    Text(names[id] ?? "Saved favorite #\(id)").font(.subheadline.bold())
                    HStack {
                        if let state = day.progress[id] {
                            Label(state == .done ? "Done" : "Skipped", systemImage: state == .done ? "checkmark.circle.fill" : "forward.end")
                                .font(.caption).foregroundStyle(accent)
                            Spacer()
                            Button("Undo") { perform { try experience.setProgress(nil, rideID: id, park: park, now: now) } }
                                .accessibilityLabel("Undo \(names[id] ?? "favorite")")
                        } else {
                            Button("Done") { perform { try experience.setProgress(.done, rideID: id, park: park, now: now) } }
                                .accessibilityLabel("Mark \(names[id] ?? "favorite") done")
                            Spacer()
                            Button("Skip today") { perform { try experience.setProgress(.skip, rideID: id, park: park, now: now) } }
                                .accessibilityLabel("Skip \(names[id] ?? "favorite") today")
                        }
                    }.buttonStyle(.bordered).controlSize(.regular)
                }.padding(.vertical, 4)
                if id != ids.last { Divider() }
            }
        }.pivotCard().accessibilityIdentifier("native-day-progress")
    }

    private func routeCard(_ route: NativeDayRoute, park: FloridaPark, rides: [LiveRide], now: Date) -> some View {
        let names = nameLookup(rides: rides, saved: [])
        return VStack(alignment: .leading, spacing: 14) {
            Text("Remaining route").font(.title2.bold())
            Text("\(route.stops.count) rides · about \(route.plannedMinutes) min · \(route.walkMinutes) min walking")
                .font(.subheadline).foregroundStyle(accent)
            Text("Starts from \(route.startLabel)").font(.caption).foregroundStyle(Color.pivotMuted)
            if now >= route.endAt { Text("Your visit window has ended. Edit it to plan more rides.").font(.callout).foregroundStyle(.orange) }
            else if route.remainingRideCount == 0 { Text("No remaining favorites. Add rides or undo a completed/skipped ride to plan again.").font(.callout) }
            if !route.cutRideIDs.isEmpty {
                Text("Doesn’t fit around your fixed stops: \(route.cutRideIDs.map { names[$0] ?? "#\($0)" }.joined(separator: ", "))")
                    .font(.callout).foregroundStyle(.orange)
            }
            if !route.unavailableRideIDs.isEmpty {
                Text("Currently unavailable or missing a posted wait: \(route.unavailableRideIDs.map { names[$0] ?? "#\($0)" }.joined(separator: ", "))")
                    .font(.callout).foregroundStyle(.orange)
            }
            if !route.missingRideIDs.isEmpty {
                Text("\(route.missingRideIDs.count) saved favorite(s) aren’t in this feed. They remain saved and are not counted as finished.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(route.stops) { stop in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stop.sequence). \(stop.rideName)").font(.headline)
                    Text("\(time(stop.experienceAt, park)) · posted wait \(stop.expectedWaitMinutes) min")
                        .font(.subheadline)
                    Text("\(stop.walkMinutes) min walk · done about \(time(stop.completeAt, park))")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                }
                if stop.id != route.stops.last?.id { Divider() }
            }
            Text("Approximate walking and ride times. Fixed stops reserve walking plus arrival buffers; unknown stop locations reserve at least 15 minutes of walking. Follow park signs and check posted return requirements.")
                .font(.caption).foregroundStyle(Color.pivotMuted)
        }.pivotCard().accessibilityIdentifier("native-day-route")
    }

    private func offlineCard(park: FloridaPark, snapshot: LiveParkSnapshot?, route: NativeDayRoute?,
                             pack: NativeOfflineDayPack?, sourceIsLive: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Offline day pack").font(.headline)
            Text("Save a copy of the route, fixed stops, progress, showtimes, ride reference details, and posted waits. Changes enter this pack only when you save again.")
                .font(.caption).foregroundStyle(Color.pivotMuted)
            Button(pack == nil ? "Save day pack" : "Update saved pack") {
                guard let snapshot else { return }
                perform {
                    try experience.savePack(snapshot: snapshot, park: park, route: route, sourceIsLive: sourceIsLive, now: now)
                    message = "Day pack saved on this device. It opens without a connection."
                }
            }.buttonStyle(.borderedProminent).disabled(!sourceIsLive || snapshot == nil)
                .accessibilityIdentifier("native-day-save-pack")
            if let pack {
                Text("Saved \(ParkTimeFormatter.dateTime(pack.savedAt, timeZone: park.timeZone)) · visit \(pack.localDay)")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
                Text("Saved waits are never live. Schedules and operating conditions may change. No offline reopening forecasts.")
                    .font(.caption).foregroundStyle(.orange)
                Button("Open saved day pack") { showPack = true }.buttonStyle(.bordered)
                    .accessibilityIdentifier("native-day-open-pack")
                Button("Remove saved pack", role: .destructive) { removePack = true }.font(.caption).frame(minHeight: 44)
            } else {
                Text("Save while connected before your visit. Up to 2 MB per park, 24 MB total; saved packs are not automatically replaced.")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
                if experience.hasPackFile(for: park) {
                    Button("Remove unreadable saved pack", role: .destructive) { removePack = true }
                        .font(.caption).frame(minHeight: 44)
                }
            }
        }.pivotCard()
    }

    private func time(_ value: Date, _ park: FloridaPark) -> String { ParkTimeFormatter.time(value, timeZone: park.timeZone) }
    private func perform(_ action: () throws -> Void) { do { message = nil; try action() } catch { message = error.localizedDescription } }
    private func uniqueRides(_ rides: [LiveRide]) -> [LiveRide] {
        var seen: Set<Int> = []; return rides.filter { seen.insert($0.id).inserted }
    }
    private func nameLookup(rides: [LiveRide], saved: [NativeOfflineRide]) -> [Int: String] {
        var names: [Int: String] = [:]
        for ride in saved { names[ride.id] = ride.name }
        for ride in rides { names[ride.id] = ride.name }
        return names
    }
}

private struct NativeFavoriteSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let park: FloridaPark
    let liveRides: [LiveRide]
    let savedRides: [NativeOfflineRide]
    @ObservedObject var experience: NativeDayExperienceStore
    @State private var query = ""

    private var options: [(id: Int, name: String)] {
        var names: [Int: String] = [:]
        for ride in savedRides { names[ride.id] = ride.name }
        for ride in liveRides where ride.radarEligible { names[ride.id] = ride.name }
        for id in experience.favorites(for: park) where names[id] == nil { names[id] = "Saved favorite #\(id) · not in current feed" }
        return names.map { (id: $0.key, name: $0.value) }.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Favorites stay saved until you deselect them. Missing feed entries are kept. Mark rides Done or Skip on the Plan tab for today only.")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                }
                ForEach(options, id: \.id) { ride in
                    Toggle(ride.name, isOn: Binding(get: { experience.favorites(for: park).contains(ride.id) }, set: {
                        experience.setFavorite($0, rideID: ride.id, park: park)
                    }))
                }
            }
            .searchable(text: $query, prompt: "Find a ride")
            .navigationTitle("Favorite rides")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct NativeVisitWindowEditor: View {
    @Environment(\.dismiss) private var dismiss
    let park: FloridaPark
    @ObservedObject var experience: NativeDayExperienceStore
    @State private var start: Date
    @State private var end: Date
    @State private var error: String?

    init(park: FloridaPark, start: Date, end: Date, experience: NativeDayExperienceStore) {
        self.park = park; self.experience = experience
        _start = State(initialValue: start); _end = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Arrival", selection: $start)
                DatePicker("Departure", selection: $end)
                Text("Times are in \(park.timeZone.identifier). Choose the following date explicitly for an overnight visit. Planning uses at most 14 hours per segment.")
                    .font(.caption)
                if let error { Text(error).foregroundStyle(.orange) }
            }.environment(\.timeZone, park.timeZone)
                .navigationTitle("Visit window")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try experience.setVisitWindow(start: start, end: end, park: park); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
        }
    }
}

private struct NativeCommitmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    let park: FloridaPark
    let rides: [LiveRide]
    @ObservedObject var experience: NativeDayExperienceStore
    @State private var kind = NativeCommitmentKind.lunch
    @State private var title = "Lunch"
    @State private var start: Date
    @State private var end: Date
    @State private var buffer = 10
    @State private var place = -1
    @State private var error: String?

    init(park: FloridaPark, rides: [LiveRide], now: Date, experience: NativeDayExperienceStore) {
        self.park = park; self.rides = rides; self.experience = experience
        let rounded = Date(timeIntervalSince1970: ceil(now.timeIntervalSince1970 / 900) * 900)
        _start = State(initialValue: rounded); _end = State(initialValue: rounded.addingTimeInterval(45 * 60))
    }

    private var located: [LiveRide] {
        var ids: Set<Int> = []
        return rides.filter { $0.radarEligible && NativeDayPlanning.validLocation($0.location) && ids.insert($0.id).inserted }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Lunch / break").tag(NativeCommitmentKind.lunch)
                        Text("Manual return window").tag(NativeCommitmentKind.manualReturn)
                    }
                    TextField("Name", text: $title)
                    DatePicker("Start", selection: $start)
                    DatePicker("End", selection: $end)
                    Stepper("Arrive \(buffer) min early", value: $buffer, in: 0...60, step: 5)
                    Picker("Near a ride", selection: $place) {
                        Text("Not specified").tag(-1)
                        ForEach(located) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("A return window reserves the entire interval. Shorten it to the time you intend to use. Times use \(park.timeZone.identifier); select the next date for an overnight stop. Nothing is booked.")
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }.environment(\.timeZone, park.timeZone)
                .navigationTitle("Keep time for")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save stop") { save() } }
                }
        }
    }

    private func save() {
        let commitment = NativeDayCommitment(id: UUID().uuidString, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                            kind: kind, startAt: start, endAt: end, bufferMinutes: buffer,
                                            location: located.first { $0.id == place }?.location)
        do { try experience.addCommitment(commitment, park: park); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// A fully local reader. It never reconstructs LiveParkSnapshot or fetches remote images.
struct NativeOfflineDayPackView: View {
    @Environment(\.dismiss) private var dismiss
    let pack: NativeOfflineDayPack
    private var zone: TimeZone { TimeZone(identifier: pack.timezone) ?? .gmt }
    private func time(_ date: Date) -> String { ParkTimeFormatter.time(date, timeZone: zone) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pack.parkName).font(.title.bold())
                        Text("Saved day pack · visit \(pack.localDay)").font(.headline)
                        if let park = FloridaPark(rawValue: pack.parkID), NativeDayPlanning.localDay(park: park, at: Date()) != pack.localDay {
                            Text("This pack is from a different park day. Check its dates before using the saved route or showtimes.").foregroundStyle(.orange)
                        }
                        Text("Saved \(ParkTimeFormatter.dateTime(pack.savedAt, timeZone: zone))")
                        Text("Park data fetched \(ParkTimeFormatter.dateTime(pack.fetchedAt, timeZone: zone))")
                        Text("Wait source updated \(ParkTimeFormatter.dateTime(pack.sourceUpdatedAt, timeZone: zone))")
                        Text("Show source updated \(ParkTimeFormatter.dateTime(pack.showSourceUpdatedAt, timeZone: zone))")
                        Text("Saved waits are never live. This snapshot does not update automatically and contains no reopening forecasts. Verify schedules and operating conditions in the park.")
                            .foregroundStyle(.orange)
                    }.font(.caption).pivotCard()
                    if let hours = pack.hours, let regular = hours.regular {
                        Text("Saved park hours · \(hours.date): \(time(regular.openingTime))–\(time(regular.closingTime))")
                            .font(.subheadline).pivotCard()
                    }
                    savedRoute
                    savedCommitments
                    savedRides
                    savedShows
                }.padding(20)
            }.background(Color.pivotBackground)
                .navigationTitle("Offline pack")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var savedRoute: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved route").font(.headline)
            if let route = pack.route {
                Text("From \(route.startLabel) · generated \(ParkTimeFormatter.dateTime(route.generatedAt, timeZone: zone))")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
                ForEach(route.stops) { stop in
                    Text("\(stop.sequence). \(stop.rideName) · \(time(stop.experienceAt)) · saved wait \(stop.expectedWaitMinutes) min · \(stop.walkMinutes) min walk")
                        .font(.subheadline)
                }
                if route.stops.isEmpty { Text("No ride route was saved").font(.subheadline) }
            } else { Text("No route in this pack").font(.subheadline) }
        }.pivotCard()
    }

    private var savedCommitments: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved fixed stops").font(.headline)
            if pack.day.commitments.isEmpty { Text("No fixed stops saved").font(.subheadline) }
            ForEach(pack.day.commitments.sorted { $0.startAt < $1.startAt }) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.bold())
                    Text("\(time(item.startAt))–\(time(item.endAt)) · \(item.bufferMinutes) min early").font(.caption)
                    if let stop = pack.route?.commitments.first(where: { $0.id == item.id }) {
                        Text("Saved leave-by \(time(stop.leaveBy)) · \(stop.transferMinutes) min walk").font(.caption)
                        ForEach(stop.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }
                    if let note = item.note { Text(note).font(.caption).foregroundStyle(Color.pivotMuted) }
                }
            }
            Text("A saved plan is not a reservation or return entitlement").font(.caption).foregroundStyle(Color.pivotMuted)
        }.pivotCard()
    }

    private var savedRides: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ride reference & saved progress").font(.headline)
            ForEach(pack.favorites.filter { id in !pack.rides.contains { $0.id == id } }, id: \.self) { id in
                Text("Saved favorite #\(id) · \(savedProgress(id)) · reference data was unavailable when saved")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
            }
            ForEach(pack.rides) { ride in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved status: \(ride.savedStatus) · saved wait: \(ride.savedWaitMinutes.map { "\($0) min" } ?? "not available")")
                            .font(.caption).foregroundStyle(.orange)
                        Text("Source observation: \(ParkTimeFormatter.dateTime(ride.sourceUpdatedAt, timeZone: zone))").font(.caption)
                        if let details = ride.details {
                            Text("Reference reviewed \(details.reviewedAt)").font(.caption).foregroundStyle(Color.pivotMuted)
                            ForEach(details.facts) { fact in
                                Text("\(fact.label): \(fact.value)").font(.subheadline)
                            }
                            if !details.riderNote.isEmpty { Text(details.riderNote).font(.caption) }
                            ForEach(details.unverified, id: \.self) { Text("Not verified: \($0)").font(.caption).foregroundStyle(Color.pivotMuted) }
                            ForEach(details.sources) { source in
                                Text("\(source.label): \(source.url.absoluteString)").font(.caption).textSelection(.enabled)
                            }
                            Text("Photos and source websites need a connection").font(.caption).foregroundStyle(Color.pivotMuted)
                        } else { Text("No reviewed ride details in this pack").font(.caption) }
                    }.padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ride.name).font(.subheadline.bold())
                        Text(savedProgress(ride.id)).font(.caption).foregroundStyle(Color.pivotMuted)
                    }
                }
            }
        }.pivotCard()
    }

    private func savedProgress(_ id: Int) -> String {
        let favorite = pack.favorites.contains(id) ? "Favorite · " : ""
        switch pack.day.progress[id] {
        case .done: return favorite + "Done when saved"
        case .skip: return favorite + "Skipped when saved"
        case nil: return favorite + "Not completed when saved"
        }
    }

    private var savedShows: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved showtimes").font(.headline)
            if pack.shows.isEmpty { Text("No showtimes in this pack").font(.subheadline) }
            ForEach(pack.shows) { show in
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.name).font(.subheadline.bold())
                    Text(show.showtimes.isEmpty ? "No timed performances saved" : show.sortedShowtimes.map {
                        if let end = $0.endTime { return "\(time($0.startTime))–\(time(end))" }
                        return time($0.startTime)
                    }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.pivotMuted)
                }
            }
        }.pivotCard()
    }
}
