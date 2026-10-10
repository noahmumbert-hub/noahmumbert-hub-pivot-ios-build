#if canImport(ActivityKit) && canImport(SwiftUI) && canImport(WidgetKit) && os(iOS)
import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct PIVOTLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        compatibleWidget()
    }

    private func compatibleWidget() -> some Widget {
        if #available(iOS 18.0, *) {
            return WidgetBundleBuilder.buildOptional(
                WidgetBundleBuilder.buildLimitedAvailability(PIVOTWatchLiveActivityWidget())
            )
        } else {
            return WidgetBundleBuilder.buildOptional(
                WidgetBundleBuilder.buildLimitedAvailability(PIVOTLiveActivityWidget())
            )
        }
    }
}

struct PIVOTLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    fileprivate var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: PIVOTLiveActivityAttributes.self) { context in
            PIVOTActivitySurface(context: context)
                .activityBackgroundTint(.pivotActivityBackground)
                .activitySystemActionForegroundColor(.white)
                .environment(\.timeZone, context.parkTimeZone)
        } dynamicIsland: { _ in
            // ActivityKit requires an iPhone presentation builder, but it does
            // not expose a Lock-Screen-only opt-out. Keep every region
            // explicitly blank so PIVOT never puts ride data in the island.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PIVOTBlankDynamicIslandContent()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PIVOTBlankDynamicIslandContent()
                }
                DynamicIslandExpandedRegion(.center) {
                    PIVOTBlankDynamicIslandContent()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PIVOTBlankDynamicIslandContent()
                }
            } compactLeading: {
                PIVOTBlankDynamicIslandContent()
            } compactTrailing: {
                PIVOTBlankDynamicIslandContent()
            } minimal: {
                PIVOTBlankDynamicIslandContent()
            }
        }
    }
}

@available(iOS 18.0, *)
private struct PIVOTWatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        PIVOTLiveActivityWidget().configuration
            .supplementalActivityFamilies([.small, .medium])
    }
}

private struct PIVOTActivitySurface: View {
    let context: ActivityViewContext<PIVOTLiveActivityAttributes>

    var body: some View {
        if #available(iOS 18.0, *) {
            PIVOTActivityFamilyView(context: context)
        } else {
            PIVOTLockScreenLiveActivityView(context: context)
        }
    }
}

@available(iOS 18.0, *)
private struct PIVOTActivityFamilyView: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<PIVOTLiveActivityAttributes>

    var body: some View {
        if family == .small {
            VStack(alignment: .leading, spacing: 4) {
                Label(context.isStale ? "Update paused" : "PIVOT Radar", systemImage: context.statusSymbol)
                    .font(.caption2.bold())
                    .foregroundStyle(context.accentColor)
                Text(context.state.rideName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if context.isStale {
                    Text("Open PIVOT to refresh").font(.caption2)
                } else if let bestGuess = context.state.bestGuess {
                    HStack(spacing: 4) {
                        Text("Est. reopen")
                        Text(bestGuess, style: .time)
                    }
                    .font(.caption2)
                    .foregroundStyle(context.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    Text(context.state.statusSummary).font(.caption2).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .padding(8)
        } else {
            PIVOTLockScreenLiveActivityView(context: context)
        }
    }
}

private struct PIVOTBlankDynamicIslandContent: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

private struct PIVOTLockScreenLiveActivityView: View {
    let context: ActivityViewContext<PIVOTLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.isStale ? "PIVOT · UPDATE PAUSED" : "PIVOT · REOPEN RADAR")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.isStale ? Color.secondary : context.accentColor)
                Spacer(minLength: 12)
                Text(context.attributes.parkName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 10) {
                PIVOTAnimatedStatusSymbol(
                    symbol: context.statusSymbol,
                    color: context.isStale ? Color.secondary : context.accentColor,
                    animationKey: context.state.animationKey,
                    font: .title3.weight(.semibold),
                    accessibilityLabel: context.statusAccessibilityLabel
                )

                VStack(alignment: .leading, spacing: 1) {
                    PIVOTAnimatedRideName(
                        state: context.state,
                        font: .headline,
                        lineLimit: 1,
                        alignment: .leading
                    )
                    Text(context.state.statusSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                PIVOTClosureDurationView(state: context.state, showsPrefix: false)
                    .font(.caption.monospacedDigit().weight(.semibold))
            }

            PIVOTCompactForecastView(context: context)
        }
        .padding(14)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }
}

private struct PIVOTAnimatedStatusSymbol: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let symbol: String
    let color: Color
    let animationKey: String
    let font: Font
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: symbol)
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(
                .pulse.wholeSymbol,
                options: .nonRepeating,
                value: animationKey
            )
            .symbolEffectsRemoved(isLuminanceReduced)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct PIVOTAnimatedRideName: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let state: PIVOTLiveActivityAttributes.ContentState
    let font: Font
    let lineLimit: Int
    let alignment: TextAlignment

    var body: some View {
        ZStack {
            Text(state.rideName)
                .id(state.animationKey)
                .transition(.push(from: .bottom).combined(with: .opacity))
        }
        .font(font)
        .lineLimit(lineLimit)
        .minimumScaleFactor(0.76)
        .multilineTextAlignment(alignment)
        .animation(
            isLuminanceReduced ? nil : .easeOut(duration: 0.45),
            value: state.animationKey
        )
    }
}

private struct PIVOTClosureDurationView: View {
    let state: PIVOTLiveActivityAttributes.ContentState
    let showsPrefix: Bool

    var body: some View {
        Group {
            if let closureStartedAt = state.closureStartedAt {
                HStack(spacing: 3) {
                    if showsPrefix {
                        Text(state.closureDurationIsMinimum ? "Closed ≥" : "Closed")
                    } else if state.closureDurationIsMinimum {
                        Text("≥")
                    }
                    Text(closureStartedAt, style: .timer)
                        .monospacedDigit()
                }
            } else {
                Text(state.closureDurationText)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDuration)
    }

    private var accessibilityDuration: Text {
        guard let closureStartedAt = state.closureStartedAt else {
            return Text(state.closureDurationAccessibilityLabel)
        }
        let prefix = state.closureDurationIsMinimum
            ? Text("Closed for at least ")
            : Text("Closed for ")
        return prefix + Text(closureStartedAt, style: .timer)
    }
}

private struct PIVOTCompactForecastView: View {
    let context: ActivityViewContext<PIVOTLiveActivityAttributes>

    var body: some View {
        if context.isStale {
            Label("Update paused · open PIVOT to refresh", systemImage: "arrow.clockwise")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let windowStart = context.state.windowStart,
                  let bestGuess = context.state.bestGuess,
                  let windowEnd = context.state.windowEnd {
            HStack(spacing: 6) {
                Text(context.state.forecastTitle)
                    .foregroundStyle(.secondary)
                HStack(spacing: 1) {
                    Text(windowStart, style: .time)
                    Text("–")
                    Text(windowEnd, style: .time)
                }
                .monospacedDigit()
                Spacer(minLength: 4)
                Text("Best")
                    .foregroundStyle(.secondary)
                Text(bestGuess, style: .time)
                    .monospacedDigit()
                    .fontWeight(.bold)
                    .contentTransition(.numericText(value: bestGuess.timeIntervalSinceReferenceDate))
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityElement(children: .combine)
        } else {
            Text("Reopening forecast updating")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private extension ActivityViewContext where Attributes == PIVOTLiveActivityAttributes {
    var parkTimeZone: TimeZone {
        TimeZone(identifier: attributes.timeZoneIdentifier) ?? .current
    }

    var statusSymbol: String {
        if isStale { return "exclamationmark.triangle.fill" }
        return state.isWeatherDelay ? "cloud.bolt.fill" : "sparkles"
    }

    var accentColor: Color {
        let rgb = attributes.accentRGB
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }

    var statusAccessibilityLabel: String {
        isStale ? "PIVOT update paused" : "\(state.rideName) is down"
    }

}

private extension PIVOTLiveActivityAttributes.ContentState {
    var forecastTitle: String {
        if isMissedWindowRevision {
            return forecastPhase == "IN_WINDOW" ? "Inside revised window" : "Revised window"
        }
        return switch forecastPhase {
        case "UPCOMING": "Upcoming window"
        case "IN_WINDOW": "Inside predicted window"
        case "PAST_WINDOW": "Original window"
        default: "Reopening window"
        }
    }
}

private extension Color {
    static let pivotActivityBackground = Color(red: 0.05, green: 0.06, blue: 0.11)
    static let pivotActivityPurple = Color(red: 0.60, green: 0.45, blue: 0.98)
    static let pivotActivityWeather = Color(red: 0.43, green: 0.82, blue: 1.00)
}
#endif
