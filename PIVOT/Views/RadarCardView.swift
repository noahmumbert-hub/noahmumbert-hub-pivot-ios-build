import SwiftUI

struct RadarCardView: View {
    @Environment(\.pivotAccent) private var accent
    @EnvironmentObject private var store: DashboardStore

    let onChoosePark: () -> Void
    let onShowRadar: () -> Void

    var body: some View {
        Group {
            if store.selectedPark == nil {
                emptyPark
            } else if store.isLoading && store.snapshot == nil {
                loading
            } else if let ride = store.radarRide {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    radar(ride, at: context.date)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    clearState(at: context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyPark: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("No park is being monitored", systemImage: "mappin.slash")
                .font(.headline)
            Text("Select one supported park to load its rides and receive its alerts.")
                .foregroundStyle(Color.pivotMuted)
            Button("Choose park", action: onChoosePark)
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .pivotCard()
    }

    private var loading: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text("Checking the park now")
                    .font(.headline)
                Text("Loading current ride status…")
                    .font(.subheadline)
                    .foregroundStyle(Color.pivotMuted)
            }
        }
        .pivotCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking the selected park now")
    }

    private func radar(_ ride: LiveRide, at now: Date) -> some View {
        let downTime = ride.downTimePresentation
        let guidance = ReopeningGuidance.presentation(ride: ride, snapshot: store.snapshot,
            feedHealth: store.feedHealth(at: now), at: now,
            timeZone: store.selectedPark?.timeZone ?? ParkTimeFormatter.selectedParkTimeZone)
        let weather = ride.hasWeatherHold
        let closureWaveOpenCopy = (ride.delayEvidence?.closureWaveOpenNonVetoDescription)
            .map { "\($0) " } ?? ""

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 9) {
                    PivotStatusDot(color: weather ? .pivotWeather : .pivotPink)
                    Text(ride.downStatusLabel.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                }
                Spacer()
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(ride.trend.isEmpty ? "Featured closed ride" : "Most popular closed ride")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                    Text(ride.name)
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let downTime {
                        Label(downTime.text, systemImage: "clock")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(downTime.accessibilityLabel)
                    }

                    Text(guidance.headline).font(.headline)
                    if let range = guidance.range {
                        Text(range).font(.title2.weight(.bold)).monospacedDigit()
                    }
                    if let best = guidance.bestGuess {
                        Text("Best guess \(best)").font(.subheadline)
                    }
                    Text(guidance.detail).font(.subheadline).foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let estimate = ride.estimate {
                DisclosureGroup("Estimate details") {
                    VStack(alignment: .leading, spacing: 8) {
                        if estimate.estimateKind == "WEATHER" {
                            if ride.delayEvidence?.weatherOriginSignal == "RADAR_CLOSURE_WAVE" {
                                Text("\(estimate.modelVersion) · \(basisName(estimate.basis)). The park’s lightning-density layer was not current, so PIVOT required a synchronized exposed-ride closure wave plus live NOAA radar and NWS storm context. \(closureWaveOpenCopy)An older pre-storm breakdown is never relabeled. This limited range reserves a modeled restart buffer; the scalar radar trend does not measure when storm cells leave and does not claim verified lightning clearance.")
                            } else if ride.isPostOperationalWeatherConstraint {
                                Text("\(estimate.modelVersion) · \(basisName(estimate.basis)). This ride closed before the later lightning period, so its original ride-recovery window stayed primary. Only after that window expired with a fresh still-closed report did lightning clearance constrain the next range. Complete NOAA frames run the 30-minute clear clock across PIVOT’s modeled five-mile zone.")
                            } else {
                                Text("\(estimate.modelVersion) · \(basisName(estimate.basis)). Complete NOAA lightning-density frames run a 30-minute clear clock across PIVOT’s modeled five-mile zone; the scalar NOAA radar trend describes intensity changes, not storm movement or the final lightning strike.")
                            }
                        } else {
                            Text("\(estimate.modelVersion) · \(basisName(estimate.basis)) · \(estimate.sampleSize) completed and \(estimate.censoredSampleSize) ongoing comparable closures across \(estimate.distinctDayCount) park days.")
                            if let sameRideSampleSize = estimate.sameRideSampleSize,
                               let sameRideCensoredSampleSize = estimate.sameRideCensoredSampleSize {
                                Text("Same-ride support: \(sameRideSampleSize) completed · \(sameRideCensoredSampleSize) ongoing. Effective live sample weight: \(decimal(estimate.effectiveSampleSize)).")
                            }
                            if let survivalEstimator = estimate.survivalEstimator {
                                Text("Estimator: \(survivalEstimator).")
                            }
                        }

                        if let history = estimate.historyProvenance {
                            Text("PIVOT history through \(ParkTimeFormatter.modelTimestamp(history.trainedThrough)): \(history.confirmedTransitionCount) confirmed transitions, \(history.forecastLifecycleCount) forecast-lifecycle episodes, \(history.activeCensoredCount) active censored episodes, and \(history.legacyCount) legacy episodes.")
                        }

                        if let calibration = estimate.calibration, calibration.sampleSize > 0 {
                            let coverage = calibration.historicalCoverage.map { " · \(Int(($0 * 100).rounded()))% historical range coverage" } ?? ""
                            Text("Calibration: \(calibration.sampleSize) scored forecasts (effective \(decimal(calibration.effectiveSampleSize))) across \(calibration.distinctRideCount) rides and \(calibration.distinctParkCount) parks\(coverage). Median adjustment \(signedMinutes(calibration.medianAdjustmentMinutes)); interval padding \(calibration.intervalPaddingMinutes) min · trained through \(ParkTimeFormatter.modelTimestamp(calibration.trainedThrough)).")
                        }

                        if let prior = estimate.historicalPrior, prior.basis != "none" {
                            Text("Licensed frozen prior: \(prior.basis) · \(prior.sampleSize) archived closures across \(prior.distinctDayCount) days through \(ParkTimeFormatter.modelTimestamp(prior.trainedThrough)) · \(prior.version ?? "version unavailable"). Archived rows are weighted separately and are not included in the live sample count above.")
                        }

                        if let prior = estimate.aggregateReliabilityPrior, prior.applied {
                            Text("Aggregate reliability prior: \(prior.sourceRideName ?? "matched ride") · \(prior.meanOutageMinutes.map(String.init) ?? "unknown") min published mean across \(prior.aggregateOutageCount) aggregate outages and \(prior.operatingDays) operating days\(availabilityCopy(prior.availabilityPercent)). PIVOT applies a \(decimal(prior.timeScale, places: 3))× shape adjustment at \(decimal(prior.totalWeight, places: 3)) total weight for \(prior.exposure.lowercased()) exposure. It is aggregate-only, not event-level, and contributes \(prior.evidenceCount) closure events and \(prior.evidenceAccounting.distinctDayCountContribution) park days to PIVOT’s evidence counts.")
                            if let documentationURL = URL(string: prior.provenance.documentationUrl) {
                                Link("Rope Drop News · CC BY 4.0 ↗", destination: documentationURL)
                                    .foregroundStyle(.white)
                            }
                        }

                        Text("Closure signal: \(estimate.closureSignal) · start: \(estimate.startQuality). This is a PIVOT model range, not a park-supplied reopening time.")
                        if let fallbackRejectedDescription = estimate.radarFallbackRejectedRevisionDescription {
                            Text(fallbackRejectedDescription)
                        } else if estimate.revisionReason == "MODEL_UPDATE" {
                            Text("Revision \(estimate.revision) issued \(ParkTimeFormatter.dateTime(estimate.issuedAt)) with the newly calibrated PIVOT model. The earlier forecast remains retained for scoring.")
                        } else if estimate.revisionReason == "WINDOW_MISSED" {
                            Text("Revision \(estimate.revision) issued \(ParkTimeFormatter.dateTime(estimate.issuedAt)) after a later live source check beyond the prior window still reported the ride closed. The prior forecast remains retained for scoring.")
                        } else if estimate.revisionReason == "NEW_LIGHTNING" {
                            Text(ride.isPostOperationalWeatherConstraint
                                ? "Revision \(estimate.revision) issued \(ParkTimeFormatter.dateTime(estimate.issuedAt)) after the original ride-recovery window expired, a later live park-feed check still showed the ride closed, and a later five-mile lightning restriction remained active."
                                : "Revision \(estimate.revision) issued \(ParkTimeFormatter.dateTime(estimate.issuedAt)) after a new NOAA lightning frame reset the clear clock. Earlier forecasts remain retained for scoring.")
                        } else if estimate.revisionReason == "CLEAR_INTERVAL_CONFIRMED" {
                            Text("Revision \(estimate.revision) issued \(ParkTimeFormatter.dateTime(estimate.issuedAt)) after complete NOAA frames verified 30 continuous lightning-clear minutes. Earlier forecasts remain retained for scoring.")
                        } else {
                            Text("Initial forecast issued \(ParkTimeFormatter.dateTime(estimate.issuedAt)).")
                        }
                        if estimate.lockedForOutage {
                            Text("This issued window is fixed. It does not slide with the clock; a later closed observation can create a separate conditional revision while the prior result remains pending.")
                        }
                        if let lightningAt = ride.delayEvidence?.lastLightningDensityAt {
                            let clearMinutes = ride.delayEvidence?.clearMinutes ?? 0
                            let requiredMinutes = ride.delayEvidence?.requiredClearMinutes ?? 30
                            let clearClock = ride.delayEvidence?.clearanceState == "VERIFIED"
                                ? "30 minutes verified"
                                : "\(clearMinutes) of \(requiredMinutes) minutes"
                            Text("Latest positive five-mile-zone lightning interval: \(ParkTimeFormatter.dateTime(lightningAt)) · clear clock: \(clearClock) · modeled clearance: \(ParkTimeFormatter.dateTime(ride.delayEvidence?.clearanceAt)).")
                        }
                        if let radarTrend = ride.delayEvidence?.radarTrend {
                            let reflectivity = ride.delayEvidence?.radarReflectivityDbz.map { " · \(Int($0.rounded())) dBZ highest zone sample" } ?? ""
                            let projectedClear = ride.delayEvidence?.radarProjectedClearAt.map { _ in " · legacy intensity-only heuristic; not spatial departure" } ?? ""
                            Text("NOAA radar: \(radarTrendName(radarTrend))\(reflectivity)\(projectedClear).")
                        }
                        if let reason = ride.estimateReason { Text(reason) }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 8)
                }
                .tint(.white)
                .font(.subheadline.weight(.semibold))
            }

            Button(action: onShowRadar) {
                HStack {
                    Spacer()
                    Text("View down rides")
                        .fontWeight(.bold)
                    Image(systemName: "arrow.right")
                    Spacer()
                }
                .foregroundStyle(Color.pivotBackground)
                .padding(.vertical, 15)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.pivotSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke((weather ? Color.pivotWeather : Color.pivotPink).opacity(0.5), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func clearState(at now: Date) -> some View {
        let verified = store.canAssertNoClosures(at: now)
        return HStack(spacing: 14) {
            Image(systemName: verified ? "checkmark.circle.fill" : "questionmark.circle")
                .font(.title2)
                .foregroundStyle(verified ? Color.pivotMint : Color.pivotMuted)
            VStack(alignment: .leading, spacing: 4) {
                Text(verified ? "No reviewed rides are reported down" : "Current ride status unavailable")
                    .font(.headline)
                Text(verified ? "No down rides in the current observations for \(store.selectedPark?.name ?? "the selected park")."
                    : store.feedHealth(at: now).retainedGuidance ?? "Valid ride observations are required before Radar can report no closures. Pull to refresh.")
                    .font(.subheadline)
                    .foregroundStyle(Color.pivotMuted)
            }
        }
        .pivotCard()
    }

    private func basisName(_ basis: String) -> String {
        switch basis {
        case "NOAA weather clearance", "NOAA five-mile weather clearance": "NOAA five-mile weather-clearance model"
        case "NOAA radar closure-wave recovery": "NOAA radar + closure-wave weather model"
        case "same-ride blend": "Same-ride model"
        case "park-history blend": "Park-history model"
        case "destination-history blend", "resort-history blend": "Destination-history model"
        case "operator-climate blend": "Operator and climate-history model"
        case "network-history blend": "PIVOT network-history model"
        case "network operational prior": "PIVOT network baseline model"
        default: "PIVOT reopening model"
        }
    }

    private func radarTrendName(_ trend: String) -> String {
        switch trend {
        case "CLEAR": "clear near the park"
        case "EXITING": "reflectivity decreasing"
        case "BUILDING": "echoes building"
        case "STEADY": "echoes steady"
        default: "updating"
        }
    }

    private func decimal(_ value: Double, places: Int = 1) -> String {
        String(format: "%.*f", places, value)
    }

    private func signedMinutes(_ value: Int) -> String {
        value > 0 ? "+\(value) min" : "\(value) min"
    }

    private func availabilityCopy(_ availability: Double?) -> String {
        guard let availability else { return "" }
        return " · \(decimal(availability, places: availability.rounded() == availability ? 0 : 1))% availability"
    }
}
