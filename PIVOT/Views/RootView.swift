import SwiftUI

private enum DashboardSection: String {
    case today
    case waits
    case shows
    case radar
    case data
}

struct RootView: View {
    @Environment(\.pivotAccent) private var accent
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showParkPicker = false
    @State private var showAlertSettings = false
    @State private var showSettings = false
    @State private var rideFilter: RideListFilter = .all
    @AppStorage(RideSort.storageKey) private var rideSort: RideSort = .shortest
    @State private var rideQuery = ""
    @State private var selectedDockSection: DashboardSection = .waits
    @State private var expandedShowIDs: Set<String> = []

    var body: some View {
        TabView(selection: $selectedDockSection) {
            dashboardTab(.waits)
                .tabItem { Label("Waits", systemImage: "clock") }
                .tag(DashboardSection.waits)

            dashboardTab(.today)
                .tabItem { Label("Plan", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(DashboardSection.today)

            dashboardTab(.shows)
                .tabItem { Label("Shows", systemImage: "sparkles") }
                .tag(DashboardSection.shows)

            dashboardTab(.radar)
                .tabItem { Label("Radar", systemImage: "scope") }
                .tag(DashboardSection.radar)

            dashboardTab(.data)
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(DashboardSection.data)
        }
        .tint(accent)
        .pivotFixedNativeTabBar()
        .sensoryFeedback(.selection, trigger: selectedDockSection)
        .sheet(isPresented: $showSettings) { PivotSettingsView() }
        .sheet(isPresented: $showParkPicker) {
            ParkPickerView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showAlertSettings) {
            AlertSettingsView()
                .environmentObject(store)
        }
        .overlay(alignment: .top) {
            if let toast = store.toastMessage {
                toastView(toast)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        if store.toastMessage == toast {
                            withAnimation { store.toastMessage = nil }
                        }
                    }
            }
        }
        .task {
            await store.bootstrap()
            store.setSceneActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, newPhase in
            store.setSceneActive(newPhase == .active)
        }
        .onChange(of: selectedDockSection) { _, section in
            if section == .radar {
                rideFilter = .radar
            } else if section == .waits, rideFilter == .radar {
                rideFilter = .all
            }
        }
    }

    private func dashboardTab(_ section: DashboardSection) -> some View {
        NavigationStack {
            ZStack {
                Color.pivotBackground.ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                  ScrollView {
                    LazyVStack(spacing: 20) {
                        header
                        parkSwitch

                        if store.selectedPark?.id == 65, store.snapshot?.parkId == 65,
                           let event = store.snapshot?.halloweenHorrorNights {
                            horrorNightSection(event, showHouses: section == .waits)
                        }

                        switch section {
                        case .today:
                            DayPlannerView(
                                park: store.selectedPark,
                                snapshot: store.snapshot,
                                isRefreshing: store.isRefreshing,
                                onChoosePark: { showParkPicker = true }
                            )

                        case .waits:
                            if store.selectedPark != nil {
                                rideList(radarOnly: false)
                            } else {
                                tabIntro(eyebrow: "", title: "Wait times", detail: "Choose your park to see current rides and waits.")
                                chooseParkCard(
                                    title: "Where are you heading?",
                                    detail: "Search parks or use your location."
                                )
                            }

                        case .shows:
                            tabIntro(
                                eyebrow: "",
                                title: "Shows",
                                detail: "Today’s entertainment, all in one place."
                            )

                            if store.selectedPark != nil {
                                showsCard
                            } else {
                                chooseParkCard(
                                    title: "Choose a park for showtimes",
                                    detail: "PIVOT will load the selected park’s live entertainment schedule."
                                )
                            }

                        case .radar:
                            tabIntro(
                                eyebrow: "",
                                title: "Reopen Radar",
                                detail: "Closures, reopening windows, and park weather."
                            )
                            radarCard {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                    scrollProxy.scrollTo("down-rides", anchor: .top)
                                }
                            }
                            if store.selectedPark != nil {
                                weatherStrip
                            }

                            if store.selectedPark != nil {
                                sourceStrip
                                rideList(radarOnly: true).id("down-rides")
                            }

                        case .data:
                            tabIntro(
                                eyebrow: "",
                                title: "More",
                                detail: "Manage your park, alerts, and app."
                            )
                            moreActions
                            sourceStrip
                            DisclosureGroup("Data & methods") {
                                dataMethod.padding(.top, 12)
                            }
                            .font(.subheadline.weight(.semibold))
                            .tint(accent)
                        }

                        attributionFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await store.refreshNow()
                }
                }
            }
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
#endif
        }
    }

    private func radarCard(onShowDown: @escaping () -> Void) -> some View {
        RadarCardView(
            onChoosePark: { showParkPicker = true },
            onShowRadar: onShowDown
        )
    }

    private func rideList(radarOnly: Bool) -> some View {
        RideListView(
            query: $rideQuery,
            filter: $rideFilter,
            sort: $rideSort,
            radarOnly: radarOnly
        )
    }

    private func tabIntro(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .tracking(-1.2)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color.pivotMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func horrorNightSection(_ event: HorrorNightSnapshot, showHouses: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if event.isActive(at: context.date) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Halloween Horror Nights").font(.title3.bold())
                        Text("Tonight · \(horrorClock(event.night.openingTime))–\(horrorClock(event.night.closingTime))")
                            .font(.subheadline)
                        Text("Separate event ticket required · switches off at closing")
                            .font(.footnote).foregroundStyle(Color.pivotMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

                    if showHouses {
                        Text("Haunted houses").font(.title2.bold())
                        ForEach(event.houses) { house in
                            let fresh = context.date.timeIntervalSince(event.fetchedAt) < 15 * 60 && house.status != "UNAVAILABLE"
                            let waitFresh = context.date.timeIntervalSince(house.sourceUpdatedAt) < 15 * 60
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(house.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                    Text(!fresh ? "Updating" : house.status == "OPEN" ? "Open" : house.status == "DOWN" ? "Temporarily down" : context.date < event.night.openingTime ? "Opens with event" : "Closed")
                                        .font(.subheadline).foregroundStyle(Color.pivotMuted)
                                }
                                Spacer(minLength: 4)
                                if fresh, waitFresh, house.status == "OPEN", let wait = house.waitTime {
                                    VStack(spacing: 2) {
                                        Text("\(wait)").font(.title2.bold()).monospacedDigit()
                                        Text("min").font(.caption)
                                    }
                                } else {
                                    Text(fresh && house.status == "OPEN" ? "Wait not published" : "—")
                                        .font(.footnote).foregroundStyle(Color.pivotMuted)
                                        .frame(maxWidth: 85).multilineTextAlignment(.trailing)
                                }
                            }
                            .pivotCard(padding: 16)
                        }
                        if event.houses.isEmpty {
                            Text("House listings are unavailable from the live feed. PIVOT will retry automatically.").font(.subheadline)
                        }
                        Text("House waits by ThemeParks.wiki").font(.footnote).foregroundStyle(Color.pivotMuted)
                    }
                }
                .foregroundStyle(.white)
            }
        }
    }

    private func horrorClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private var moreActions: some View {
        VStack(spacing: 0) {
            Button { showSettings = true } label: {
                settingsRow("Settings", detail: "Accent color & app version", icon: "gearshape")
            }
            Divider().overlay(Color.pivotBorder).padding(.leading, 52)
            Button { showParkPicker = true } label: {
                settingsRow("Park & location", detail: store.selectedPark?.name ?? "Choose a park", icon: "location")
            }
            Divider().overlay(Color.pivotBorder).padding(.leading, 52)
            Button { showAlertSettings = true } label: {
                settingsRow("Ride alerts & Live Activity", detail: store.alertsEnabled ? "Ride alerts on" : "Manage notifications", icon: "bell")
            }
        }
        .buttonStyle(.plain)
        .pivotCard(padding: 4)
    }

    private func settingsRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(Color.pivotMuted)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.pivotMuted)
        }
        .padding(14)
        .frame(minHeight: 70)
        .contentShape(Rectangle())
    }

    private func chooseParkCard(title: String, detail: String) -> some View {
        Button { showParkPicker = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.pivotMuted)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.pivotMuted)
            }
            .pivotCard()
        }
        .buttonStyle(.plain)
    }

    private var attributionFooter: some View {
        Text("Independent park-day information · PIVOT is not affiliated with Disney, Universal, ThemeParks.wiki, or Rope Drop News.")
            .font(.caption)
            .foregroundStyle(Color.pivotMuted)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 3) {
                Text("PIVOT")
                    .font(.system(size: 21, weight: .bold))
                    .tracking(4)
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("PIVOT")

            Spacer()

            Button { showAlertSettings = true } label: {
                Image(systemName: store.alertsEnabled ? "bell.badge.fill" : "bell")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(store.alertsEnabled ? Color.pivotMint : .white)
                    .frame(width: 44, height: 44)
            }
            .pivotNativeGlassIconButton()
            .accessibilityLabel(store.alertsEnabled ? "Ride alerts on" : "Set up ride alerts")

            Button {
                Task { await store.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
                    .rotationEffect(store.isRefreshing && !reduceMotion ? .degrees(360) : .zero)
                    .animation(
                        store.isRefreshing && !reduceMotion
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing
                    )
            }
            .pivotNativeGlassIconButton()
            .disabled(store.selectedPark == nil || store.isRefreshing)
            .accessibilityLabel("Refresh ride data now")
        }
    }

    private var parkSwitch: some View {
        Button { showParkPicker = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 40)
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.selectedPark?.name ?? "No park selected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.locationStatus == .searching {
                        Label("Finding nearby supported park…", systemImage: "location")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    if let selectedPark = store.selectedPark,
                       let hours = store.parkHours(for: selectedPark) {
                        Text(parkHoursLine(hours))
                            .font(.caption)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(earlyEntryLine(hours))
                            .font(.caption)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if store.selectedPark != nil {
                        Text("Park hours updating")
                            .font(.caption2)
                            .foregroundStyle(.white)
                        Text("Early entry · Updating")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pivotMuted)
            }
            .contentShape(Rectangle())
            .pivotCard(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change park. Current park: \(store.selectedPark?.name ?? "none")")
    }

    private func parkHoursLine(_ hours: ParkHoursSnapshot) -> String {
        guard let regular = hours.regular else { return "Park hours updating" }
        return "Park hours · " + ParkTimeFormatter.time(regular.openingTime) + "–" + ParkTimeFormatter.time(regular.closingTime)
    }

    private func earlyEntryLine(_ hours: ParkHoursSnapshot) -> String {
        guard let earlyEntry = hours.earlyEntry else { return "Early entry · Not posted" }
        return earlyEntry.label + " · " + ParkTimeFormatter.time(earlyEntry.openingTime) + "–" + ParkTimeFormatter.time(earlyEntry.closingTime)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.selectedPark == nil ? "NO PARK SELECTED" : ParkTimeFormatter.parkDate())
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(Color.pivotMuted)
            Text(store.selectedPark == nil ? "Choose your park." : "Know what’s next.")
                .font(.system(size: 38, weight: .regular, design: .rounded))
                .minimumScaleFactor(0.8)
            Text(
                store.selectedPark == nil
                    ? "Wait times, Reopen Radar, and ride alerts stay paused until you select a park."
                    : "Live ride waits and careful reopening guidance for supported parks."
            )
            .font(.title3)
            .foregroundStyle(Color.pivotMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    private var sourceStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PivotStatusDot(color: store.snapshot?.feedHealthy == true ? .pivotMint : .orange)
                Text(store.sourceStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(Color.pivotMuted)
            }

            Text("Waits & operating status: ThemeParks.wiki \(themeSourceHealth) · PIVOT checks every 15s")
                .font(.caption2)
                .foregroundStyle(Color.pivotMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.pivotSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.pivotBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var weatherStrip: some View {
        if let weather = store.snapshot?.weather {
            let inferredRides = store.snapshot?.rides.filter {
                $0.status == .down && $0.delayEvidence?.weatherOriginSignal == "RADAR_CLOSURE_WAVE"
            } ?? []
            let contradictoryOpenDescription = inferredRides.compactMap {
                $0.delayEvidence?.closureWaveOpenNonVetoDescription
            }.first
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    weatherCondition(weather)
                    Spacer()
                    lightningCondition(
                        weather,
                        inferredWeatherClosureCount: inferredRides.count,
                        contradictoryOpenDescription: contradictoryOpenDescription
                    )
                }
                VStack(alignment: .leading, spacing: 16) {
                    weatherCondition(weather)
                    Divider().overlay(Color.pivotBorder)
                    lightningCondition(
                        weather,
                        inferredWeatherClosureCount: inferredRides.count,
                        contradictoryOpenDescription: contradictoryOpenDescription
                    )
                }
            }
            .pivotCard(padding: 16)
        }
    }

    private func weatherCondition(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "cloud.sun.fill")
                .foregroundStyle(Color.pivotWeather)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(weatherTitle(weather))
                    .font(.subheadline.weight(.semibold))
                Text("\(weather.location.parkName) coordinate · NOAA/NWS")
                    .font(.caption2)
                    .foregroundStyle(Color.pivotMuted)
            }
        }
    }

    private func lightningCondition(
        _ weather: WeatherSnapshot,
        inferredWeatherClosureCount: Int,
        contradictoryOpenDescription: String?
    ) -> some View {
        let state = weather.lightning.clearanceState
        let radius = weather.lightning.sampleRadiusMiles > 0 ? weather.lightning.sampleRadiusMiles : 5
        let radiusLabel = radius.rounded() == radius ? "\(Int(radius))" : String(format: "%.1f", radius)
        let required = max(1, weather.lightning.requiredClearMinutes ?? 30)
        let clearMinutes = max(0, weather.lightning.clearMinutes ?? 0)
        let detected = inferredWeatherClosureCount >= 2 ||
            (weather.lightning.status == "LIVE" && (state == "ACTIVE" || state == "COUNTDOWN"))
        let title: String
        let detail: String
        if weather.lightning.sourceKind == "GLM", let glm = weather.lightning.glm {
            title = glm.state == "VERIFIED" ? "Estimated weather-clear interval complete" : glm.state == "UNKNOWN" ? "Lightning timer · coverage incomplete" : "Weather-clear estimate · \(glm.clearMinutes)/30 min observed"
            detail = "Last GLM detection \(ParkTimeFormatter.observationTime(glm.lastDetectedAt)) · target \(ParkTimeFormatter.observationTime(glm.targetAt)). Only newer detections move the target; missing observations do not count as clear. Locations are approximate, not exact ground strikes."
        } else if inferredWeatherClosureCount >= 2 {
            title = "Weather impact detected · \(inferredWeatherClosureCount) exposed rides down"
            detail = "Newest lightning frame does not yet cover the closure wave · synchronized park closures corroborated by live NOAA radar and NWS storm context\(contradictoryOpenDescription.map { " · \($0)" } ?? "")"
        } else if weather.lightning.status != "LIVE" {
            title = "Lightning data updating"
            detail = "NOAA nowCOAST \(radiusLabel)-mile zone is not current · \(weather.lightning.completeFrames30Minutes ?? 0) complete recent frames"
        } else if state == "ACTIVE" {
            let nearest = weather.lightning.nearestPositiveSampleMiles.map { String(format: " · nearest positive sample %.1f mi", $0) } ?? ""
            title = "Outdoor hold · lightning inside \(radiusLabel) mi"
            detail = "NOAA positive sample\(nearest) · 30-minute clock uses the possible strike time inside the 15-minute density interval · conservative clear end \(ParkTimeFormatter.dateTime(weather.lightning.clearanceAt))"
        } else if state == "COUNTDOWN" {
            title = "Outdoor reopen clock · \(clearMinutes)/\(required) min"
            detail = "No in-zone strike in complete NOAA frames · target \(ParkTimeFormatter.dateTime(weather.lightning.clearanceAt)) · \(radarTrendText(weather.radar?.trend))"
        } else if state == "VERIFIED" {
            title = "Outdoor lightning clearance verified"
            detail = "\(required)-minute no-strike interval complete at \(ParkTimeFormatter.dateTime(weather.lightning.clearanceVerifiedAt ?? weather.lightning.clearanceAt)) · restart window may begin"
        } else if weather.lightning.lastDensityDetectedAt != nil {
            title = "Waiting for a complete clear interval"
            detail = "Last in-zone sample \(ParkTimeFormatter.dateTime(weather.lightning.lastDensityDetectedAt)) · \(weather.lightning.completeFrames30Minutes ?? 0) complete NOAA frames · \(radarTrendText(weather.radar?.trend))"
        } else {
            title = "No lightning inside \(radiusLabel) mi"
            detail = "Outdoor attractions may remain open under the PIVOT rule · \(radarTrendText(weather.radar?.trend)) · \(weather.lightning.completeFrames30Minutes ?? 0) complete NOAA frames"
        }
        let rule = inferredWeatherClosureCount >= 2
            ? "Park-specific provisional fallback · no verified strike claimed · 30-minute buffer after projected convective echoes exit."
            : "PIVOT outdoor rule: open while lightning is >\(radiusLabel) mi away · reopen after \(required) continuous clear min."
        return HStack(spacing: 10) {
            Image(systemName: detected ? "bolt.fill" : "bolt.slash")
                .foregroundStyle(detected ? Color.pivotWeather : Color.pivotMuted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                DisclosureGroup("Weather & lightning details") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let glm = weather.lightning.glm {
                            Text("GOES-\(glm.satellite) GLM · \(glm.status.lowercased()) · observed through \(ParkTimeFormatter.observationTime(glm.observedThrough)) · \(weather.lightning.sourceKind == "GLM" ? "detection-time clock" : "density fallback clock")")
                                .foregroundStyle(Color.pivotMuted)
                        }
                        Text(detail).foregroundStyle(Color.pivotMuted)
                        Text(rule).foregroundStyle(Color.pivotWeather)
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                }
                .font(.caption)
                .tint(Color.pivotWeather)
            }
        }
    }

    private func radarTrendText(_ trend: String?) -> String {
        switch trend {
        case "CLEAR": "Radar clear"
        case "EXITING": "Radar echoes exiting"
        case "BUILDING": "Radar echoes building"
        case "STEADY": "Radar echoes steady"
        default: "Radar updating"
        }
    }

    private func weatherTitle(_ weather: WeatherSnapshot) -> String {
        let temperature = weather.temperatureF.map { " · \(Int($0.rounded()))°" } ?? ""
        let rain = weather.precipitationChance.map { " · \(Int($0.rounded()))% rain" } ?? ""
        return (weather.condition ?? "Weather updating") + temperature + rain
    }

    @ViewBuilder
    private var parkHoursCard: some View {
        if let hours = store.snapshot?.parkHours {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PARK SCHEDULE")
                            .font(.caption.weight(.bold))
                            .tracking(1.8)
                            .foregroundStyle(Color.pivotMuted)
                        Text("Park hours")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    Text(hours.date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.pivotMuted)
                }

                HStack(spacing: 10) {
                    parkHoursPeriodCard(
                        title: "Park open",
                        period: hours.regular,
                        fallback: "Hours updating"
                    )
                    parkHoursPeriodCard(
                        title: hours.earlyEntry?.label ?? "Early entry",
                        period: hours.earlyEntry,
                        fallback: "Not posted"
                    )
                }

                Text(
                    (hours.stale
                        ? "Most recent saved schedule · daily refresh pending"
                        : "ThemeParks.wiki schedule · refreshes at park local midnight")
                    + " · fetched " + ParkTimeFormatter.dateTime(hours.fetchedAt)
                )
                .font(.caption2)
                .foregroundStyle(hours.stale ? Color.orange : Color.pivotMuted)
                .fixedSize(horizontal: false, vertical: true)

                if let warning = hours.warning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Link("Schedule source: ThemeParks.wiki ↗", destination: URL(string: hours.source.url)!)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .pivotCard(padding: 16)
        }
    }

    private func parkHoursPeriodCard(
        title: String,
        period: ParkHoursPeriod?,
        fallback: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Color.pivotMuted)
                .lineLimit(1)
            if let period {
                Text("\(ParkTimeFormatter.time(period.openingTime))–\(ParkTimeFormatter.time(period.closingTime))")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text(fallback)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.pivotSurfaceRaised.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var showsCard: some View {
        let snapshot = store.snapshot
        let shows = snapshot?.showList ?? []
        let presentation = snapshot?.showSchedulePresentation()

        return VStack(alignment: .leading, spacing: 12) {
            if shows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation?.headline ?? "Updating today’s schedule")
                        .font(.headline).foregroundStyle(.white)
                    Text(presentation?.detail ?? "Checking the daily entertainment provider.")
                        .font(.subheadline).foregroundStyle(Color.pivotMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pivotCard(padding: 16)
            } else {
                HStack {
                    Text("Today’s shows").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(shows.count) listed").font(.caption).foregroundStyle(Color.pivotMuted)
                }
                ForEach(shows) { show in
                    showScheduleRow(show, referenceDate: Date())
                        .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.pivotBorder, lineWidth: 1) }
                }
            }
            Text(showScheduleSourceText(snapshot))
                .font(.caption)
                .foregroundStyle(Color.pivotMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
        .onChange(of: store.selectedPark?.rawValue) { _, _ in expandedShowIDs.removeAll() }
        .onChange(of: shows.map(\.id)) { _, showIDs in
            expandedShowIDs.formIntersection(showIDs)
        }
    }
    @ViewBuilder
    private func showScheduleRow(_ show: LiveShow, referenceDate: Date) -> some View {
        let isExpanded = expandedShowIDs.contains(show.id)
        let rowPresentation = ShowScheduleRowFormatter.presentation(
            for: show,
            referenceDate: referenceDate
        )
        let countLabel = rowPresentation.countLabel
        let statusLabel = rowPresentation.statusLabel

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    if isExpanded { expandedShowIDs.remove(show.id) }
                    else { expandedShowIDs.insert(show.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(width: 36, height: 36)
                        .background(accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(show.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(statusLabel)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isExpanded ? accent : Color.white.opacity(0.62))
                        .rotationEffect(isExpanded ? .degrees(180) : .zero)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(minHeight: 58)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(show.name). \(statusLabel). \(countLabel)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Double tap to hide showtimes" : "Double tap to show all showtimes")

            if isExpanded {
                if show.sortedShowtimes.isEmpty {
                    Text("No timed performances in today’s published schedule")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.leading, 16)
                        .padding(.trailing, 14)
                        .padding(.bottom, 13)
                } else {
                    ShowTimeFlowLayout(spacing: 7) {
                        ForEach(show.sortedShowtimes) { showtime in
                            Text(ShowScheduleRowFormatter.pillLabel(for: showtime))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.pivotSurfaceRaised)
                                .overlay {
                                    Capsule()
                                        .stroke(Color.pivotBorder, lineWidth: 1)
                                }
                                .clipShape(Capsule())
                                .accessibilityLabel(ShowScheduleRowFormatter.accessibilityLabel(for: showtime))
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .padding(.bottom, 13)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(show.name) showtimes")
                }
            }
        }
    }

    private func showScheduleEyebrow(for state: ShowScheduleState?) -> String {
        let parkName = (store.selectedPark?.name ?? "SELECTED PARK").uppercased()
        switch state {
        case .upcoming:
            return "NEXT SHOW AT \(parkName)"
        case .finishedForToday, .noScheduledPerformances:
            return "TODAY AT \(parkName)"
        case .providerUnavailable:
            return "SCHEDULE STATUS"
        case nil:
            return "CHECKING \(parkName)"
        }
    }

    private func showScheduleSourceText(_ snapshot: LiveParkSnapshot?) -> String {
        guard let snapshot else {
            return "Daily entertainment schedule · checking for updates"
        }
        let staleLabel = snapshot.showScheduleIsStale ? " · saved schedule" : ""
        return "\(snapshot.showScheduleSourceLabel) · updated \(ParkTimeFormatter.dateTime(snapshot.showScheduleSourceUpdatedAt))\(staleLabel)"
    }

    private var dataMethod: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 13) {
                dataRow("ThemeParks.wiki updated", ParkTimeFormatter.dateTime(store.snapshot?.themeParksWikiUpdatedAt))
                dataRow("PIVOT fetched", ParkTimeFormatter.dateTime(store.snapshot?.fetchedAt))
                dataRow("PIVOT auto-check", "Every 5 seconds while open")
                dataRow("ThemeParks.wiki cadence", "Source updates on its own schedule")
                dataRow("Wait & status source", "ThemeParks.wiki current ride feed")
                dataRow("Showtimes", "Selected park’s full daily provider schedule")
                dataRow("Park hours", ParkTimeFormatter.dateTime(store.snapshot?.parkHours?.fetchedAt))
                dataRow("Park-hours refresh", "At the selected park’s local midnight")
                dataRow("Theme status", themeDataStatus)
                dataRow("NWS conditions", ParkTimeFormatter.dateTime(store.snapshot?.weather.nws.observedAt))
                dataRow("NOAA last checked", ParkTimeFormatter.dateTime(store.snapshot?.weather.lightning.checkedAt))
                dataRow("NOAA lightning frame", ParkTimeFormatter.dateTime(store.snapshot?.weather.lightning.sourceUpdatedAt))
                dataRow("NOAA radar frame", ParkTimeFormatter.dateTime(store.snapshot?.weather.radar?.sourceUpdatedAt))
                dataRow("Weather location", weatherLocationDescription)
                dataRow("Park timezone", store.snapshot?.park.timezone ?? "Choose a park")

                Divider().overlay(Color.pivotBorder)

                Text("How reopening forecasts work")
                    .font(.headline)
                Text("The Today planner schedules only rides the user marks as favorites and never inserts unrelated filler rides. For selected favorites that are currently open and reporting a fresh standby wait, it combines that hidden queue cost with recent observed demand and exact attraction coordinates from ThemeParks.wiki to reduce time and walking inside the selected visit window. When the full list cannot fit, it names the favorites that must be removed; unavailable favorites are labeled separately and reconsidered after every live refresh. Coordinate distance receives a 1.35× park-path adjustment, so the result is planning guidance rather than turn-by-turn navigation. Raw queue numbers remain only in Waits.")
                Text("Shows and entertainment are a separate daily schedule stream. PIVOT displays every published performance time for the selected park, preserves the full schedule after times pass, and clearly distinguishes a completed day, no scheduled performances, and a provider outage. Showtimes are not ride waits and never enter Reopen Radar.")
                Text("Park hours and early entry come from each selected park’s dated ThemeParks.wiki schedule. Every park has its own local-date cache, so schedules and operating boundaries cannot leak between properties or time zones. A prior schedule is labeled stale if the provider is temporarily unavailable.")
                Text("PIVOT covers \(FloridaPark.allCases.count) reviewed parks across Disney, Universal, United Parks, the legacy Cedar Fair portfolio, and the legacy Six Flags portfolio. The list contains reviewed ride attractions and ride-like queued experiences; stage shows, meet-and-greets, play areas, walkthroughs, duplicate queues, and unreviewed entries are excluded.")
                Text("ThemeParks.wiki supplies PIVOT’s posted waits and operating status for each reviewed ride. PIVOT checks the selected park every 5 seconds while the app is active, but the provider updates on its own schedule. Reviewed operator refurbishment schedules, including expected reopen dates when published, override stale live statuses and are excluded from unexpected-downtime learning.")
                Text("Weather-delay estimates use only fresh NOAA lightning-density frames for the selected park. Each frame covers 15 minutes, not an exact strike time. The conditional reopening range assumes no further lightning within the modeled five-mile zone and adds restart time. Radar, closure waves, and GLM do not create weather labels. Stale data is not a safety all-clear. Raw closure history is retained, while sufficiently supported per-ride outliers are excluded from normal reopening estimates.")
                Text("If a weather-exposed ride closes before a later lightning period, PIVOT keeps the ride-history forecast unchanged through its latest window. Lightning constrains a follow-up only after that window fully ends, a newer source update still confirms the ride down, and the selected park’s five-mile clear clock remains incomplete. If lightning clears first, the normal ride follow-up stays in control. At a later weather handoff, the ride portion is right-censored and only the weather-recovery tail is scored, preventing storm-held time from inflating breakdown history.")
                Text("PIVOT learns from eligible closures it observes. Confirmed reopenings become completed episodes; active or interrupted episodes remain right-censored instead of being treated as reopenings. Same-ride history leads when available, followed by park, destination, operator-and-climate cohort, and the PIVOT network baseline. Active forecasts never train themselves.")
                Text("Each issued forecast is anchored to the observed outage and stays fixed instead of sliding forward with the clock. Operational windows are capped at 40–60 minutes by evidence depth; active weather windows at 60 minutes and verified-clearance restart windows at 30. If a ride remains confirmed closed after its window ends, PIVOT records the miss and issues a new conditional follow-up window. A new positive in-zone lightning frame can reset a weather window once, and complete frames reaching 30 clear minutes can issue one clearance-confirmed revision. Earlier windows remain retained for audit and are scored only against the part of the episode they modeled.")
                Text("Rope Drop News rolling reliability can add a very low-weight, shape-preserving cold-start adjustment for a matched ride. It is aggregate-only—not event-level—and contributes zero closures or park days to PIVOT’s evidence counts.")
                Text("Ride alerts are stored only on this device and follow the selected park. Choosing No park pauses requests, alerts, and the Live Activity. iOS suspends PIVOT’s 5-second checks after the app leaves the foreground, so the Live Activity marks itself stale rather than implying background freshness.")
                Text("Forecasts are independent PIVOT estimates, not park-supplied reopening times, and cannot guarantee when a ride will resume.")

                Link("Powered by ThemeParks.wiki ↗", destination: URL(string: "https://www.themeparks.wiki/")!)
                Link("Universal Orlando refurbishment schedules ↗", destination: URL(string: "https://www.universalorlando.com/web/en/us/things-to-do/rides-attractions/jurassic-park-river-adventure")!)
                Link("Data from Rope Drop News, CC BY 4.0 ↗", destination: URL(string: "https://ropedropnews.com/developers")!)
                Link("NOAA / National Weather Service ↗", destination: URL(string: "https://www.weather.gov/")!)
                Link("NOAA nowCOAST lightning density and radar ↗", destination: URL(string: "https://nowcoast.noaa.gov/")!)
            }
            .font(.subheadline)
            .foregroundStyle(Color.pivotMuted)
            .padding(.top, 14)
        } label: {
            Label("Data source & estimation method", systemImage: "cylinder.split.1x2")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .tint(accent)
        .pivotCard()
    }

    private var themeSourceHealth: String {
        guard let theme = store.snapshot?.themeParksWiki, theme.available else { return "unavailable" }
        return theme.cacheStale ? "stale" : "live"
    }

    private var themeDataStatus: String {
        guard let theme = store.snapshot?.themeParksWiki, theme.available else {
            return store.snapshot == nil ? "Choose a park" : "Temporarily unavailable"
        }
        let freshness = theme.cacheStale ? "stale" : "live"
        return "\(freshness) · \(theme.matchedRideCount) ride matches"
    }

    private var weatherLocationDescription: String {
        guard let location = store.snapshot?.weather.location else { return "Choose a park" }
        return String(
            format: "%@ · %.4f, %.4f",
            location.parkName,
            location.latitude,
            location.longitude
        )
    }

    private func dataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Color.pivotMuted)
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    private func toastView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(Color.pivotMint)
            Text(message)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.pivotBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct DayPlannerView: View {
    @Environment(\.pivotAccent) private var accent
    let park: FloridaPark?
    let snapshot: LiveParkSnapshot?
    let isRefreshing: Bool
    let onChoosePark: () -> Void

    @State private var startAt = Date()
    @State private var endAt = Date().addingTimeInterval(8 * 60 * 60)
    @State private var favoriteRideIDs: Set<Int> = []
    @State private var showFavoritePicker = false
    @State private var clockNow = Date()

    private var plan: DayPlan? {
        guard let park, let snapshot, endAt > startAt else { return nil }
        let entrance = ParkEntranceLocations.coordinates[park].map {
            AttractionLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        return DayPlanner.build(
            rides: snapshot.rides,
            requestedRideIDs: favoriteRideIDs,
            startAt: startAt,
            endAt: endAt,
            now: clockNow,
            startLocation: entrance
        )
    }

    private var favoriteRides: [LiveRide] {
        (snapshot?.rides ?? [])
            .filter { favoriteRideIDs.contains($0.id) && $0.radarEligible }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your day")
                    .font(.largeTitle.weight(.bold))
                    .tracking(-1.2)
                    .accessibilityIdentifier("Today planner title")
                Text("Pick your rides and visit window. We’ll plan the route.")
                    .font(.subheadline)
                    .foregroundStyle(Color.pivotMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)

            if park == nil {
                Button(action: onChoosePark) {
                    HStack(spacing: 14) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose a park to build your day")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Your route updates automatically as conditions change.")
                                .font(.subheadline)
                                .foregroundStyle(Color.pivotMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(Color.pivotMuted)
                    }
                    .pivotCard()
                }
                .buttonStyle(.plain)
            } else {
                favoriteSelection
                visitWindow

                if favoriteRideIDs.isEmpty {
                    plannerState(
                        icon: "star",
                        title: "Choose your favorite rides",
                        detail: "Your route stays empty until you choose the rides you reasonably want to do."
                    )
                } else if snapshot == nil {
                    plannerState(
                        icon: isRefreshing ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle",
                        title: isRefreshing ? "Building today’s route" : "The live route is unavailable",
                        detail: isRefreshing ? "Checking current attraction availability and park geometry…" : "Pull to refresh or check the Waits tab for provider status."
                    )
                } else if endAt <= startAt {
                    plannerState(
                        icon: "clock.badge.exclamationmark",
                        title: "Choose a longer visit window",
                        detail: "Your departure must be after your arrival."
                    )
                } else if let plan {
                    if !plan.cutRides.isEmpty || !plan.unavailableRides.isEmpty {
                        feasibilityWarning(plan)
                    }

                    if plan.stops.isEmpty {
                        plannerState(
                            icon: "calendar.badge.exclamationmark",
                            title: "No selected ride fits right now",
                            detail: "Extend your visit, edit your favorites, or wait for an unavailable favorite to reopen."
                        )
                    } else {
                        planSummary(plan)
                        route(plan)
                        Label {
                            Text("Starts with the closest available favorite to the park entrance, then balances walking, live waits, recent demand, and current operating status.")
                        } icon: {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.pivotMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .pivotCard(padding: 14)
                    }
                    DisclosureGroup("All selected rides") {
                        fullRideList(plan).padding(.top, 10)
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(accent)
                }
            }
        }
        .task(id: park?.id) {
            loadFavoriteRides()
            configureDefaultWindow()
        }
        .task {
            while !Task.isCancelled {
                clockNow = Date()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
        .onChange(of: snapshot?.parkHours?.date) { _, _ in
            configureDefaultWindow()
        }
        .onChange(of: snapshot?.rides.map(\.id)) { _, _ in
            pruneFavoriteRides()
        }
        .sheet(isPresented: $showFavoritePicker, onDismiss: saveFavoriteRides) {
            FavoriteRidePickerSheet(
                parkName: park?.name ?? "Selected park",
                rides: snapshot?.rides.filter(\.radarEligible) ?? [],
                selection: $favoriteRideIDs
            )
        }
    }

    private var favoriteSelection: some View {
        Button {
            showFavoritePicker = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: favoriteRideIDs.isEmpty ? "star" : "star.fill")
                    .font(.headline)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("1 · FAVORITE RIDES")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(accent)
                    Text(favoriteRideIDs.isEmpty ? "What do you want to ride?" : "\(favoriteRideIDs.count) ride\(favoriteRideIDs.count == 1 ? "" : "s") selected")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(favoriteRides.isEmpty
                         ? "PIVOT plans only the rides you choose."
                         : favoriteRides.map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Color.pivotMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)
                Text(favoriteRideIDs.isEmpty ? "Choose" : "Edit")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            .pivotCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("Choose favorite rides")
    }

    private var visitWindow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("2 · Visit window", systemImage: "clock.arrow.2.circlepath")
                    .font(.headline)
                Spacer()
                Text(plan?.startsFromNow == true ? "\(compactDuration(plan?.availableMinutes ?? 0)) left" : visitLength)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.pivotMint)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    timeSelector(title: "Arrive", selection: startBinding)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.pivotMuted)
                    timeSelector(title: "Leave", selection: endBinding)
                }
                VStack(spacing: 10) {
                    timeSelector(title: "Arrive", selection: startBinding)
                    timeSelector(title: "Leave", selection: endBinding)
                }
            }

            if let plan, plan.startsFromNow {
                Label {
                    Text("**Starting now at \(ParkTimeFormatter.time(plan.effectiveStartAt, timeZone: park?.timeZone)).** Time already passed is removed automatically, and this route keeps moving with the clock.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(Color.pivotMint)
                }
                .font(.caption2)
                .foregroundStyle(Color.pivotMuted)
                .padding(10)
                .background(Color.pivotMint.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("Times use \(park?.name ?? "the selected park") local time. If you are already there, PIVOT automatically starts from the current time.")
                    .font(.caption2)
                    .foregroundStyle(Color.pivotMuted)
            }
        }
        .pivotCard()
    }

    private func timeSelector(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.pivotMuted)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.timeZone, park?.timeZone ?? .current)
                .tint(accent)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.pivotBorder, lineWidth: 1)
        }
    }

    private func feasibilityWarning(_ plan: DayPlan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text(plan.cutRides.isEmpty ? "Some favorites cannot be scheduled right now" : "Your full ride list will not fit")
                    .font(.headline)

                if !plan.cutRides.isEmpty {
                    let names = plan.cutRides.map(\.rideName).joined(separator: ", ")
                    Text("To complete everything else before you leave, PIVOT recommends skipping **\(names)** based on current waits, walking detours, and the time remaining.\(plan.extraMinutesNeeded > 0 ? " To keep the entire list, plan on about \(compactDuration(plan.extraMinutesNeeded)) more." : "")")
                        .font(.caption)
                        .foregroundStyle(Color.pivotMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !plan.unavailableRides.isEmpty {
                    let names = plan.unavailableRides.map(\.rideName).joined(separator: ", ")
                    Text("**Currently unavailable:** \(names). PIVOT will add \(plan.unavailableRides.count == 1 ? "it" : "them") back automatically after a confirmed reopening.")
                        .font(.caption)
                        .foregroundStyle(Color.pivotMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .pivotCard()
    }

    private func compactDuration(_ minutes: Int) -> String {
        let rounded = max(0, Int(ceil(Double(minutes) / 5)) * 5)
        let hours = rounded / 60
        let remainder = rounded % 60
        if hours > 0, remainder > 0 { return "\(hours)h \(remainder)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(remainder)m"
    }

    private func fullRideList(_ plan: DayPlan) -> some View {
        let planned = Dictionary(uniqueKeysWithValues: plan.stops.map { ($0.rideID, $0) })
        let cut = Set(plan.cutRides.map(\.rideID))
        let unavailable = Set(plan.unavailableRides.map(\.rideID))
        let rides = favoriteRides.sorted { first, second in
            if let firstStop = planned[first.id], let secondStop = planned[second.id] {
                return firstStop.sequence < secondStop.sequence
            }
            if planned[first.id] != nil { return true }
            if planned[second.id] != nil { return false }
            if cut.contains(first.id) != cut.contains(second.id) { return cut.contains(first.id) }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }

        return VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ALL REQUESTED RIDES")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(accent)
                    Text("Your full ride list")
                        .font(.headline)
                }
                Spacer()
                Text("\(rides.count) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pivotMuted)
            }
            .padding(14)

            Divider().overlay(Color.pivotBorder)

            ForEach(Array(rides.enumerated()), id: \.element.id) { index, ride in
                let stop = planned[ride.id]
                let recommendation = stop.map {
                    "Planned #\($0.sequence) · ride around \(ParkTimeFormatter.time($0.experienceAt, timeZone: park?.timeZone))"
                } ?? (cut.contains(ride.id)
                    ? "Recommended skip · lets the rest of the trip fit"
                    : unavailable.contains(ride.id)
                        ? "Unavailable now · PIVOT will recheck automatically"
                        : "Rechecking this ride")

                HStack(alignment: .top, spacing: 11) {
                    Text(stop.map { "\($0.sequence)" } ?? (cut.contains(ride.id) ? "–" : "!"))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(stop != nil ? Color.pivotBackground : .white)
                        .frame(width: 28, height: 28)
                        .background(stop != nil ? Color.pivotMint : cut.contains(ride.id) ? Color.orange.opacity(0.7) : Color.pivotPink.opacity(0.7))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ride.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(ride.land) · \(recommendation)")
                            .font(.caption2)
                            .foregroundStyle(cut.contains(ride.id) ? Color.orange : Color.pivotMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    Text(currentWaitLabel(for: ride))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(waitColor(for: ride))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(waitColor(for: ride).opacity(0.11))
                        .clipShape(Capsule())
                        .fixedSize()
                }
                .padding(13)

                if index < rides.count - 1 {
                    Divider().overlay(Color.pivotBorder).padding(.leading, 52)
                }
            }
        }
        .background(Color.pivotSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.pivotBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full requested ride list with waits and recommendations")
    }

    private func currentWaitLabel(for ride: LiveRide) -> String {
        if ride.status == .open, ride.waitTime == 0 { return "Walk-on" }
        if ride.status == .open, let wait = ride.waitTime { return "\(wait) min" }
        if ride.status == .open { return "Updating" }
        if ride.status == .down { return "Closed" }
        if ride.status == .scheduled { return "Not operating" }
        if ride.status == .parkInactive { return "Park closed" }
        return "Updating"
    }

    private func waitColor(for ride: LiveRide) -> Color {
        guard ride.status == .open, let wait = ride.waitTime else { return Color.pivotMuted }
        if wait <= 20 { return Color.pivotMint }
        if wait <= 50 { return Color.orange }
        return Color.pivotPink
    }

    private func planSummary(_ plan: DayPlan) -> some View {
        HStack(spacing: 10) {
            summaryMetric(value: "\(plan.stops.count)", label: "favorites")
            summaryMetric(value: "\(plan.totalWalkMinutes)", label: "walking min")
            summaryMetric(value: String(format: "%.1f", plan.totalDistanceMiles), label: "route miles")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.stops.count) attractions, \(plan.totalWalkMinutes) walking minutes, \(String(format: "%.1f", plan.totalDistanceMiles)) route miles")
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.pivotMint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.pivotMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.pivotSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.pivotBorder, lineWidth: 1)
        }
    }

    private func route(_ plan: DayPlan) -> some View {
        VStack(spacing: 0) {
            ForEach(plan.stops) { stop in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(stop.sequence)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.pivotBackground)
                        .frame(width: 30, height: 30)
                        .background(Color.pivotMint)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(ParkTimeFormatter.time(stop.experienceAt, timeZone: park?.timeZone)) · \(stop.land)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.pivotMuted)
                        Text(stop.rideName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(stop.expectedWaitMinutes == 0 ? "Walk-on" : "\(stop.expectedWaitMinutes) min wait")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(stop.expectedWaitMinutes <= 20 ? Color.pivotMint : stop.expectedWaitMinutes <= 50 ? Color.orange : Color.pivotPink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((stop.expectedWaitMinutes <= 20 ? Color.pivotMint : stop.expectedWaitMinutes <= 50 ? Color.orange : Color.pivotPink).opacity(0.11))
                            .clipShape(Capsule())
                        let walkingOrigin = stop.sequence == 1 ? "park entrance" : "prior stop"
                        Label("\(stop.walkMinutes) min walk · \(String(format: "%.2f", stop.distanceMiles)) mi from \(walkingOrigin)", systemImage: "figure.walk")
                            .font(.caption2)
                            .foregroundStyle(Color.pivotMuted)
                    }

                    Spacer(minLength: 8)
                    Text(ParkTimeFormatter.time(stop.completeAt, timeZone: park?.timeZone))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(14)

                if stop.id != plan.stops.last?.id {
                    Divider()
                        .overlay(Color.pivotBorder)
                        .padding(.leading, 56)
                }
            }
        }
        .background(Color.pivotSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.pivotBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Efficient route for \(park?.name ?? "the selected park")")
    }

    private func plannerState(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(Color.pivotMuted)
            }
            Spacer(minLength: 0)
        }
        .pivotCard()
    }

    private var visitLength: String {
        let minutes = max(0, Int(endAt.timeIntervalSince(startAt) / 60))
        guard minutes > 0 else { return "Choose valid times" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0, remainder > 0 { return "\(hours)h \(remainder)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(remainder)m"
    }

    private var startBinding: Binding<Date> {
        Binding(get: { startAt }, set: { value in
            startAt = value
            saveWindow()
        })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { endAt }, set: { value in
            endAt = value
            saveWindow()
        })
    }

    private func configureDefaultWindow() {
        guard let park else { return }
        let key = storageKey(for: park)
        if let savedStart = UserDefaults.standard.object(forKey: key + ".start") as? Date,
           let savedEnd = UserDefaults.standard.object(forKey: key + ".end") as? Date,
           savedEnd > savedStart {
            startAt = savedStart
            endAt = savedEnd
            return
        }

        let hours = snapshot?.parkHours
        let opening = hours?.earlyEntry?.openingTime ?? hours?.regular?.openingTime
        let closing = hours?.regular?.closingTime
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = park.timeZone
        let fallbackStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        let fallbackEnd = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? fallbackStart.addingTimeInterval(11 * 60 * 60)
        let start = opening ?? fallbackStart
        let end = closing ?? fallbackEnd
        let roundedNow = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970 / 900) * 900)
        startAt = roundedNow >= start && roundedNow < end ? roundedNow : start
        endAt = end > startAt ? end : startAt.addingTimeInterval(60 * 60)
        saveWindow()
    }

    private func saveWindow() {
        guard let park else { return }
        let key = storageKey(for: park)
        UserDefaults.standard.set(startAt, forKey: key + ".start")
        UserDefaults.standard.set(endAt, forKey: key + ".end")
    }

    private func loadFavoriteRides() {
        guard let park else {
            favoriteRideIDs = []
            return
        }
        favoriteRideIDs = Set(UserDefaults.standard.array(forKey: favoriteStorageKey(for: park)) as? [Int] ?? [])
        pruneFavoriteRides()
    }

    private func pruneFavoriteRides() {
        guard snapshot != nil else { return }
        let valid = Set((snapshot?.rides ?? []).filter(\.radarEligible).map(\.id))
        let pruned = favoriteRideIDs.intersection(valid)
        guard pruned != favoriteRideIDs else { return }
        favoriteRideIDs = pruned
        saveFavoriteRides()
    }

    private func saveFavoriteRides() {
        guard let park else { return }
        UserDefaults.standard.set(favoriteRideIDs.sorted(), forKey: favoriteStorageKey(for: park))
    }

    private func favoriteStorageKey(for park: FloridaPark) -> String {
        "pivot.favoriteRides.\(park.id)"
    }

    private func storageKey(for park: FloridaPark) -> String {
        let date = snapshot?.parkHours?.date ?? ParkTimeFormatter.parkDate(timeZone: park.timeZone)
        return "pivot.dayPlan.\(park.id).\(date)"
    }
}

private struct FavoriteRidePickerSheet: View {
    @Environment(\.pivotAccent) private var accent
    @Environment(\.dismiss) private var dismiss

    let parkName: String
    let rides: [LiveRide]
    @Binding var selection: Set<Int>
    @State private var query = ""

    private var matchingRides: [LiveRide] {
        rides
            .filter { query.isEmpty || "\($0.name) \($0.land)".localizedCaseInsensitiveContains(query) }
            .sorted {
                let firstSelected = selection.contains($0.id)
                let secondSelected = selection.contains($1.id)
                if firstSelected != secondSelected { return firstSelected }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Pick the rides you reasonably want to do. PIVOT schedules only these choices and tells you if the full list will not fit.")
                            .font(.caption)
                            .foregroundStyle(Color.pivotMuted)
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(accent)
                    }
                }
                .listRowBackground(Color.pivotSurface)

                Section(parkName) {
                    ForEach(matchingRides) { ride in
                        Button {
                            if selection.contains(ride.id) {
                                selection.remove(ride.id)
                            } else {
                                selection.insert(ride.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(ride.id) ? "star.fill" : "star")
                                    .foregroundStyle(accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ride.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("\(ride.land) · \(statusLabel(for: ride))")
                                        .font(.caption)
                                        .foregroundStyle(Color.pivotMuted)
                                }
                                Spacer(minLength: 8)
                                if selection.contains(ride.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.pivotMint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selection.contains(ride.id) ? "Selected" : "Not selected")
                    }
                }
                .listRowBackground(Color.pivotSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.pivotBackground)
            .navigationTitle("Favorite rides")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search rides")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { selection.removeAll() }
                        .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Build my day") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("\(selection.count) ride\(selection.count == 1 ? "" : "s") selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pivotMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func statusLabel(for ride: LiveRide) -> String {
        switch ride.status {
        case .open where ride.waitTime == 0: "Walk-on"
        case .open where ride.waitTime != nil: "\(ride.waitTime ?? 0) min wait"
        case .open: "Wait updating"
        case .down: "Temporarily closed"
        case .scheduled: "Not operating now"
        case .parkInactive: "Park not active"
        case .stale: "Status unavailable"
        case .unknown: "Status unavailable"
        }
    }
}

private struct ShowTimeFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maximumWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if nextWidth > maximumWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                contentWidth = max(contentWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = nextWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        contentWidth = max(contentWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(
            width: proposal.width ?? contentWidth,
            height: totalHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension View {
    @ViewBuilder
    func pivotFixedNativeTabBar() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}
