import SwiftUI
import Charts

struct ParkCrowdCard: View {
    let estimate: ParkCrowdEstimate?
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Crowd meter", systemImage: "person.3.fill").font(.headline)
                Spacer()
                Text(estimate.map { "\($0.score)/10" } ?? "—").font(.title2.weight(.bold)).foregroundStyle(Color.pivotMint)
            }
            if let estimate {
                HStack(spacing: 4) {
                    ForEach(1...10, id: \.self) { level in
                        Capsule().fill(level <= estimate.score ? meterColor : Color.pivotMuted.opacity(0.2)).frame(height: 7)
                    }
                }.accessibilityHidden(true)
                Text("\(estimate.label) · typical posted wait \(estimate.typicalWait) min").font(.subheadline.weight(.semibold))
                Text("\(estimate.basis) · \(estimate.rideCount) rides").font(.caption).foregroundStyle(Color.pivotMuted)
            } else {
                Text(subtitle).font(.subheadline).foregroundStyle(Color.pivotMuted)
            }
            Text("Wait-based crowd estimate · not attendance or park capacity").font(.caption2).foregroundStyle(Color.pivotMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("park-crowd-meter")
    }
    private var meterColor: Color { (estimate?.score ?? 0) >= 6 ? .orange : .pivotMint }
}

struct NativeParkCrowdOverview: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var browsing = false
    var body: some View {
        if let park = store.selectedPark {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    ParkCrowdCard(estimate: store.waitLearning.liveCrowd(park: park,
                        snapshot: store.snapshot, failed: store.errorMessage != nil, now: context.date),
                        subtitle: store.snapshot?.parkActive == false ? "Outside monitored operating hours · no live crowd rating" : "Not enough fresh reporting rides yet")
                    Button { browsing = true } label: {
                        Label("Compare parks & days", systemImage: "calendar").font(.subheadline.weight(.medium))
                    }.accessibilityIdentifier("browse-park-crowds")
                }.pivotCard(padding: 16)
            }
            .sheet(isPresented: $browsing) { NativeParkCrowdBrowser(initialPark: park).environmentObject(store) }
        }
    }
}

struct NativeParkCrowdBrowser: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var park: FloridaPark
    @State private var date = Date()
    @State private var search = ""
    init(initialPark: FloridaPark) { _park = State(initialValue: initialPark) }
    private var calendar: Calendar { WaitLearningHistory.calendar(for: park) }
    private var dateRange: ClosedRange<Date> { Date().addingTimeInterval(-55 * 86_400)...Date().addingTimeInterval(14 * 86_400) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Park", selection: $park) {
                        ForEach(FloridaPark.allCases.sorted { $0.name < $1.name }) { Text($0.name).tag($0) }
                    }.tint(Color.pivotMint)
                    DatePicker("Visit day", selection: $date, in: dateRange, displayedComponents: .date)
                        .environment(\.timeZone, park.timeZone).environment(\.calendar, calendar)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let daily = store.waitLearning.dailyCrowd(park: park, date: date, now: context.date)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(park.name).font(.title3.weight(.semibold))
                            ParkCrowdCard(estimate: daily, subtitle: "Learning · need at least three observed days for a future crowd estimate")
                            if let daily {
                                Text("\(daily.hourCount) sampled hours per day · \(daily.days) observed day\(daily.days == 1 ? "" : "s"). Unobserved hours are excluded.")
                                    .font(.caption).foregroundStyle(Color.pivotMuted)
                            }
                            if calendar.isDate(date, inSameDayAs: context.date) {
                                Divider()
                                Text("Right now").font(.subheadline.weight(.semibold))
                                ParkCrowdCard(estimate: store.waitLearning.liveCrowd(park: park,
                                    snapshot: store.crowdSnapshot(for: park), failed: store.crowdRefreshFailed(for: park), now: context.date),
                                    subtitle: store.crowdSnapshot(for: park)?.parkActive == false ? "Outside monitored operating hours" : "Current crowd unavailable · refresh or check coverage")
                            }
                        }.pivotCard()
                    }
                    Button {
                        Task { await store.refreshCrowd(for: park) }
                    } label: {
                        Label(store.isCrowdLoading(for: park) ? "Checking park…" : "Refresh this park", systemImage: "arrow.clockwise")
                    }.disabled(store.isCrowdLoading(for: park)).tint(Color.pivotMint)
                    Text("PIVOT learns from this device’s fresh park observations and recent wait history while you use the app. Open different parks here to build their histories. Future dates use previous observed days; holidays, events, weather, and ride capacity can change the result.")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                    Text("All parks").font(.title3.weight(.semibold))
                    TextField("Search parks", text: $search).textFieldStyle(.roundedBorder)
                    ForEach(FloridaPark.allCases.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.name < $1.name }) { item in
                        Button { park = item } label: {
                            HStack {
                                Text(item.name).font(.subheadline).foregroundStyle(.white)
                                Spacer()
                                let estimate = store.waitLearning.dailyCrowd(park: item, date: WaitLearningHistory.matchingDay(date, from: park, to: item), now: Date())
                                Text(estimate.map { "\($0.label) · \($0.score)/10" } ?? "Learning")
                                    .font(.caption).foregroundStyle(Color.pivotMuted)
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }
            .background(Color.pivotBackground)
            .navigationTitle("Park crowds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onChange(of: park) { oldPark, newPark in
                date = WaitLearningHistory.matchingDay(date, from: oldPark, to: newPark)
            }
            .task(id: park) { await store.refreshCrowd(for: park) }
        }.preferredColorScheme(.dark)
    }
}

/// Plan owns forecast navigation; Waits retains only posted waits and history.
struct NativePlanWaitForecasts: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var presenting = false
    private var rides: [LiveRide] {
        store.reviewedRides.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        Button { presenting = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line").foregroundStyle(Color.pivotMint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Predicted waits").font(.headline).foregroundStyle(.white)
                    Text(rides.isEmpty ? "Rides appear after a park update" : "Hourly estimates & lowest-wait times")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.pivotMuted)
            }.frame(minHeight: 44).pivotCard(padding: 16)
        }
        .buttonStyle(.plain)
        .disabled(rides.isEmpty)
        .accessibilityIdentifier("plan-predicted-waits")
        .sheet(isPresented: $presenting) {
            NativePlanRideForecastBrowser(rides: rides).environmentObject(store)
        }
        .onChange(of: store.selectedPark) { _, _ in presenting = false }
    }
}

private struct NativePlanRideForecastBrowser: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    let rides: [LiveRide]
    @State private var rideID: Int
    init(rides: [LiveRide]) {
        self.rides = rides
        _rideID = State(initialValue: rides.first?.id ?? -1)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(store.selectedPark?.name ?? "Ride forecasts").font(.subheadline).foregroundStyle(Color.pivotMuted)
                    Picker("Ride", selection: $rideID) {
                        ForEach(rides) { Text($0.name).tag($0.id) }
                    }.tint(Color.pivotMint).accessibilityIdentifier("plan-forecast-ride-picker")
                    if let original = rides.first(where: { $0.id == rideID }) {
                        let ride = store.snapshot?.rides.first(where: { $0.id == rideID }) ?? original
                        Text(ride.name).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        NativeRideWaitForecast(ride: ride, timeZone: store.selectedPark?.timeZone ?? .current)
                    }
                }.padding(20)
            }
            .background(Color.pivotBackground)
            .navigationTitle("Predicted waits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct NativeRideWaitForecast: View {
    @EnvironmentObject private var store: DashboardStore
    let ride: LiveRide
    let timeZone: TimeZone
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let park = store.selectedPark {
                let points = store.waitLearning.forecast(rideID: ride.id, park: park,
                    hours: store.parkHours(for: park), snapshot: store.snapshot,
                    failed: store.errorMessage != nil, now: context.date)
                WaitForecastTimeline(points: points, timeZone: timeZone,
                    canRecommend: ride.status == .open && store.feedHealth(at: context.date).isLive
                        && store.snapshot?.rides.contains(where: { $0.id == ride.id }) == true,
                    learningText: WaitLearningHistory.interval(store.parkHours(for: park), park: park, now: context.date) == nil
                        ? "Fresh operating hours aren’t available, or today’s session has ended."
                        : "Learning this ride’s pattern. Hourly estimates need at least three previous observed days. Keep using PIVOT to build its history.")
            }
        }.pivotCard()
    }
}

struct WaitForecastTimeline: View {
    let points: [WaitForecastPoint]
    let timeZone: TimeZone
    let canRecommend: Bool
    let learningText: String
    private var best: WaitForecastPoint? { canRecommend ? points.min { $0.minutes < $1.minutes } : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Predicted waits", systemImage: "chart.xyaxis.line").font(.headline)
            if points.isEmpty {
                Text(learningText).font(.subheadline).foregroundStyle(Color.pivotMuted)
            } else {
                Text("From \(ParkTimeFormatter.dateTime(points[0].start, timeZone: timeZone))")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
                if let best {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lowest estimated wait").font(.caption.weight(.medium)).foregroundStyle(Color.pivotMint)
                        Text("\(clock(best.start))–\(clock(best.end)) · about \(best.minutes) min")
                            .font(.subheadline.weight(.semibold)).accessibilityIdentifier("lowest-predicted-wait")
                        Text("Among the remaining hours with enough history").font(.caption2).foregroundStyle(Color.pivotMuted)
                    }
                } else {
                    Text("History only · a current operating ride and healthy feed are required for a ride-now suggestion.")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                }
                Chart(points) { point in
                    let inset = point.end.timeIntervalSince(point.start) * 0.12
                    RectangleMark(xStart: .value("Hour start", point.start.addingTimeInterval(inset)),
                                  xEnd: .value("Hour end", point.end.addingTimeInterval(-inset)),
                                  yStart: .value("Zero wait", 0), yEnd: .value("Estimated wait", point.minutes))
                        .foregroundStyle(Color.pivotMint)
                        .annotation(position: .top) { Text("\(point.minutes)").font(.caption2).foregroundStyle(Color.pivotMuted) }
                }
                .chartXScale(domain: points[0].start...points[points.count - 1].end)
                .chartYScale(domain: 0...max(15, points.map(\.upper).max() ?? 15))
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: points.count > 8 ? 2 : 1)) { value in
                    AxisValueLabel { if let date = value.as(Date.self) { Text(clock(date)).font(.caption2) } }
                } }
                .frame(height: 150)
                .accessibilityLabel("Hourly wait estimates. Values also listed below.")
                Text("Preliminary · limited confidence · \(points.map(\.days).min() ?? 0)+ observed days\n\(points.contains(where: \.crowdAdjusted) ? "Adjusted for today’s posted-wait crowd pressure" : "Historical pattern · no current crowd adjustment")")
                    .font(.caption).foregroundStyle(Color.pivotMuted)
                DisclosureGroup("Hourly estimates") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(points) { point in
                            Text("\(clock(point.start))–\(clock(point.end)) · ~\(point.minutes) min (\(point.lower)–\(point.upper)) · \(point.sameWeekday ? "same weekday" : "recent days")")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.top, 10)
                }.font(.subheadline).tint(Color.pivotMint)
                Text("Ranges describe observed variation, not a guaranteed interval. Waits can change with weather, events, and operations. Missing hours stay blank; this does not predict reopening.")
                    .font(.caption2).foregroundStyle(Color.pivotMuted)
            }
        }.accessibilityIdentifier("ride-wait-forecast")
    }
    private func clock(_ date: Date) -> String { ParkTimeFormatter.time(date, timeZone: timeZone) }
}

#if DEBUG
/// Deterministic simulator coverage only; never included in the published app.
struct NativeWaitForecastUITestScreen: View {
    private let base = Date(timeIntervalSince1970: 1_792_004_400)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Crowds & waits").font(.largeTitle.weight(.bold))
                ParkCrowdCard(estimate: ParkCrowdEstimate(typicalWait: 45, rideCount: 24, hourCount: 6, days: 3,
                    basis: "Estimate · same weekday · limited confidence"), subtitle: "Learning").pivotCard()
                WaitForecastTimeline(points: [45, 30, 15, 25].enumerated().map { index, wait in
                    WaitForecastPoint(start: base.addingTimeInterval(Double(index) * 3600), end: base.addingTimeInterval(Double(index + 1) * 3600),
                        minutes: wait, lower: max(0, wait - 10), upper: wait + 15, days: 3, sameWeekday: true, crowdAdjusted: true)
                }, timeZone: TimeZone(identifier: "America/New_York")!, canRecommend: !ProcessInfo.processInfo.arguments.contains("--forecast-saved"), learningText: "Learning")
                    .pivotCard()
                WaitForecastTimeline(points: [], timeZone: .current, canRecommend: false, learningText: "Learning this ride’s pattern")
                    .pivotCard()
            }.padding(20)
        }.background(Color.pivotBackground).preferredColorScheme(.dark)
    }
}
#endif
