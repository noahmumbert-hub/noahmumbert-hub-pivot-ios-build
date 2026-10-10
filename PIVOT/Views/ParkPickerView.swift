import SwiftUI

private enum ParkOperatorFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case disney = "Disney"
    case universal = "Universal"
    case unitedParks = "United Parks"
    case legacyCedarFair = "Legacy Cedar Fair"
    case legacySixFlags = "Legacy Six Flags"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .legacyCedarFair: "Cedar Fair"
        case .legacySixFlags: "Six Flags"
        default: rawValue
        }
    }
}

struct ParkPickerView: View {
    @Environment(\.pivotAccent) private var accent
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var operatorFilter: ParkOperatorFilter = .all

    private var matchingParks: [FloridaPark] {
        FloridaPark.allCases.filter { park in
            let operatorMatches = operatorFilter == .all || park.portfolioName == operatorFilter.rawValue
            let queryMatches = query.isEmpty || "\(park.name) \(park.destination) \(park.operatorName) \(park.portfolioName) \(park.region) \(park.country)".localizedCaseInsensitiveContains(query)
            return operatorMatches && queryMatches
        }
    }

    private var matchingPortfolios: [String] {
        ParkOperatorFilter.allCases
            .filter { $0 != .all }
            .map(\.rawValue)
            .filter { portfolio in matchingParks.contains { $0.portfolioName == portfolio } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Location") {
                    Button {
                        store.requestParkFromLocation()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.locationStatus == .searching ? "Finding your park…" : "Use my location")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(store.locationStatus.label)
                                    .font(.caption)
                                    .foregroundStyle(Color.pivotMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: store.locationStatus == .searching ? "location" : "location.fill")
                                .foregroundStyle(accent)
                        }
                    }
                    .disabled(store.locationStatus == .searching)
                }

                Section("Monitoring") {
                    parkButton(nil)
                }


                ForEach(matchingPortfolios, id: \.self) { portfolio in
                    let parks = matchingParks.filter { $0.portfolioName == portfolio }
                    if !parks.isEmpty {
                        Section(portfolio) {
                            ForEach(parks) { park in
                                parkButton(park)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.pivotBackground)
            .navigationTitle("Choose a park")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $query, prompt: "Search \(FloridaPark.allCases.count) supported parks")
            .safeAreaInset(edge: .top) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ParkOperatorFilter.allCases) { filter in
                            Button {
                                operatorFilter = filter
                            } label: {
                                Text(filter.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(operatorFilter == filter ? Color.pivotBackground : .white)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .background(operatorFilter == filter ? accent : Color.pivotSurfaceRaised)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(operatorFilter == filter ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            store.loadParkHours()
        }
        .onChange(of: store.locationStatus) { _, status in
            if case .found = status {
                dismiss()
            }
        }
    }

    private func parkButton(_ park: FloridaPark?) -> some View {
        Button {
            store.selectPark(park)
            dismiss()
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(park.map(parkColor) ?? Color.pivotSurfaceRaised)
                    if let park {
                        Text(park.monogram)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(Color.pivotMuted)
                    }
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(park?.name ?? "No park")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(parkDetail(for: park))
                        .font(.caption)
                        .foregroundStyle(Color.pivotMuted)
                    if let park, let hours = store.parkHours(for: park) {
                        Text(scheduleLine(hours, park: park))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(earlyEntryLine(hours, park: park))
                            .font(.caption)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if park != nil {
                        Text("Park hours load after selection")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Early entry · Updating")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if store.selectedPark == park {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.pivotSurface)
    }

    private func parkDetail(for park: FloridaPark?) -> String {
        guard let park else { return "Pause ride data and alerts" }
        return "\(park.region) · \(park.operatorName)"
    }

    private func scheduleSummary(_ hours: ParkHoursSnapshot, park: FloridaPark) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(accent)
                Text(hours.parkName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(hours.stale ? "Saved schedule" : "Today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(hours.stale ? Color.orange : Color.pivotMuted)
            }
            Text(scheduleLine(hours, park: park))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(earlyEntryLine(hours, park: park))
                .font(.caption)
                .foregroundStyle(.white)
            if let warning = hours.warning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }

    private func scheduleLine(_ hours: ParkHoursSnapshot, park: FloridaPark) -> String {
        guard let regular = hours.regular else { return "Park hours updating" }
        return "Park open · " + ParkTimeFormatter.time(regular.openingTime, timeZone: park.timeZone) + "–" + ParkTimeFormatter.time(regular.closingTime, timeZone: park.timeZone)
    }

    private func earlyEntryLine(_ hours: ParkHoursSnapshot, park: FloridaPark) -> String {
        guard let earlyEntry = hours.earlyEntry else { return "Early entry · Not posted" }
        return earlyEntry.label + " · " + ParkTimeFormatter.time(earlyEntry.openingTime, timeZone: park.timeZone) + "–" + ParkTimeFormatter.time(earlyEntry.closingTime, timeZone: park.timeZone)
    }

    private func parkColor(_ park: FloridaPark) -> Color {
        switch park.portfolioName {
        case "Disney": accent.opacity(0.32)
        case "Universal": Color.pivotBlue.opacity(0.28)
        case "United Parks": Color.pivotMint.opacity(0.24)
        case "Legacy Cedar Fair": Color.orange.opacity(0.25)
        default: Color.pivotPink.opacity(0.24)
        }
    }
}
