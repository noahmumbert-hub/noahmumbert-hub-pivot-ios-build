#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 scripts/validate-ride-illustrations.py
xcrun simctl list devices available -j > build/simulators.json
xcrun simctl list runtimes -j > build/simulator-runtimes.json
xcrun simctl list devicetypes -j > build/simulator-device-types.json
simulator_id="$(python3 - <<'PY'
import json
import os
import subprocess
with open('build/simulators.json') as f:
    devices = json.load(f)['devices']
with open('build/simulator-runtimes.json') as f:
    runtimes = json.load(f)['runtimes']
with open('build/simulator-device-types.json') as f:
    device_types = json.load(f)['devicetypes']
requested = os.environ.get('PIVOT_SIMULATOR_NAME', '').strip()
available_runtimes = sorted(
    (r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier']),
    key=lambda r: tuple(int(part) for part in r['version'].split('.')), reverse=True)
selected = None
for runtime in available_runtimes:
    for device in devices.get(runtime['identifier'], []):
        if device.get('isAvailable') and (device['name'] == requested if requested else device['name'].startswith('iPhone')):
            selected = dict(device=device, runtime=runtime, created=False)
            break
    if selected:
        break
if selected is None and requested:
    device_type = next((d for d in device_types if d['name'] == requested), None)
    if device_type is None:
        raise SystemExit(f'Requested simulator device type is unavailable: {requested}')
    if not available_runtimes:
        raise SystemExit('No available iOS simulator runtime')
    runtime = available_runtimes[0]
    identifier = subprocess.check_output(
        ['xcrun', 'simctl', 'create', requested, device_type['identifier'], runtime['identifier']], text=True).strip()
    selected = dict(device=dict(name=requested, udid=identifier), runtime=runtime, created=True)
if selected is None:
    raise SystemExit('No available iPhone simulator')
record = dict(name=selected['device']['name'], identifier=selected['device']['udid'],
              runtime=selected['runtime']['name'], runtimeIdentifier=selected['runtime']['identifier'],
              created=selected['created'])
with open('build/simulator-selection.json', 'w') as f:
    json.dump(record, f, indent=2)
    f.write('\n')
print(record['identifier'])
PY
)"
cat build/simulator-selection.json
test_options=(
  -parallel-testing-enabled NO
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 180
  -maximum-test-execution-time-allowance 240
)
case "${PIVOT_TEST_SCOPE:-all}" in
  all) ;;
  layout-review)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsCompactLayoutKeepsParkHoursAndHistoryTouchTarget
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsCompactLayoutKeepsTwelveSampleControlSmall
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsCompactLayoutAllowsAccessibilityTextToWrap
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsCompactLayoutAllowsLargestAccessibilityTextToWrap
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryHandlesSparseSamples
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestDetailsKeepFirstThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testHourlyForecastShowsFirstTwoCompleteTimesAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedSampleTimesRemainReadableAtLargestAccessibilitySize
      -only-testing:PIVOTUITests/PIVOTUITests/testMapFailedRefreshDoesNotPresentCachedWaitAsCurrent
    ) ;;
  artwork-delivery)
    test_options+=(
      -only-testing:PIVOTTests/PIVOTTests/testGeneratedIllustrationsAreBundledBoundedAndAttributed
      -only-testing:PIVOTTests/PIVOTTests/testGlobalArtworkDeliveryMatchesAcceptedIDsAndKeepsBlockedFallbacks
      -only-testing:PIVOTTests/PIVOTTests/testGeneratedIllustrationsRequireAnExactParkAndRideMatch
      -only-testing:PIVOTTests/PIVOTTests/testIllustrationCacheLoadsPackagedFilesAndHandlesMissingFiles
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup1
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup2
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup3
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup4
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup5
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup6
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup7
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup8
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup9
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup10
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup11
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup12
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup13
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup14
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup15
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup16
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryCreditsRemainReadableAtLargestAccessibilitySize
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryKeepsExcludedDraftAndPhotoFallbackTruthful
      -only-testing:PIVOTUITests/PIVOTUITests/testGeneratedRideIllustrationLoadsWithCreditsAndPreservesWaits
      -only-testing:PIVOTUITests/PIVOTUITests/testGeneratedRideWithReservedPhotoRightsKeepsAccurateCredits
    ) ;;
  artwork-credits)
    test_options+=(
      -only-testing:PIVOTTests/PIVOTTests/testGeneratedIllustrationsAreBundledBoundedAndAttributed
      -only-testing:PIVOTTests/PIVOTTests/testGeneratedIllustrationsRequireAnExactParkAndRideMatch
      -only-testing:PIVOTTests/PIVOTTests/testGlobalArtworkDeliveryMatchesAcceptedIDsAndKeepsBlockedFallbacks
      -only-testing:PIVOTTests/PIVOTTests/testIllustrationCacheLoadsPackagedFilesAndHandlesMissingFiles
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryLoadsParkGroup16
      -only-testing:PIVOTUITests/PIVOTUITests/testArtworkDeliveryCreditsRemainReadableAtLargestAccessibilitySize
      -only-testing:PIVOTUITests/PIVOTUITests/testGeneratedRideIllustrationLoadsWithCreditsAndPreservesWaits
      -only-testing:PIVOTUITests/PIVOTUITests/testGeneratedRideWithReservedPhotoRightsKeepsAccurateCredits
    ) ;;
  park-picker)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testExpandedParkCanBeFoundAndSelected
    ) ;;
  map-refresh)
    test_options+=(
      -only-testing:PIVOTTests/PIVOTTests
      -only-testing:PIVOTUITests/PIVOTUITests/testMapRefreshKeepsUnchangedProviderWaitOnActualMap
      -only-testing:PIVOTUITests/PIVOTUITests/testMapNetworkRefreshRepeatFullScreenFailureRecoveryAndNavigation
      -only-testing:PIVOTUITests/PIVOTUITests/testMapNetworkAutoRefreshContinuesInFullScreenAndAfterForegroundReturn
      -only-testing:PIVOTUITests/PIVOTUITests/testLiveMapRefreshReportsRealProviderStatus
      -only-testing:PIVOTUITests/PIVOTUITests/testMapFailedRefreshDoesNotPresentCachedWaitAsCurrent
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeMapFillsWindowAndSupportsPinchPanZoomWithoutCameraReset
    ) ;;
  map-attribution)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent
    ) ;;
  wait-history)
    test_options+=(
      -only-testing:PIVOTTests/NativeParkExtrasTests
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedWaitDotsKeepEveryValueAndOpenLowestWaitForecast
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLabelsKeepTwelveRepeatedDotsInLightAppearance
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLabelsKeepTwelveRepeatedDotsInDarkAppearance
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryHandlesSingleSample
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryHandlesSparseSamples
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryWithholdsUnavailableSamples
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestRowsKeepFirstThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestRowsKeepSecondThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestRowsKeepThirdThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestRowsKeepLastThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestDetailsKeepFirstThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestDetailsKeepSecondThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestDetailsKeepThirdThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedHistoryLargestDetailsKeepLastThreeLabelsReadable
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedSampleTimesRemainReadableAtLargestAccessibilitySize
    ) ;;
  lowest-waits)
    test_options+=(
      -only-testing:PIVOTTests/NativeWaitForecastTests
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedWaitDotsKeepEveryValueAndOpenLowestWaitForecast
      -only-testing:PIVOTUITests/PIVOTUITests/testHistoryLowestWaitPredictionWithholdsMissingAndStaleEvidence
      -only-testing:PIVOTUITests/PIVOTUITests/testLowestWaitEvidenceAndHourlySheetStayConsistentAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testStaleLowestWaitHourlySheetWithholdsRecommendationAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testHourlyForecastShowsFirstTwoCompleteTimesAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testHourlyForecastShowsSecondTwoCompleteTimesAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testHourlyForecastShowsThirdTwoCompleteTimesAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testHourlyForecastShowsLastTwoCompleteTimesAtAccessibilityTextSize
    ) ;;
  reopening-accessibility)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningPredictionRemainsReadableAtAccessibilitySizeInRows
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningPredictionRemainsReadableAtAccessibilitySizeInRadar
    ) ;;
  reopening)
    test_options+=(
      -only-testing:PIVOTTests/PIVOTTests/testSparseReopeningHistoryCannotShowAnExactGuess
      -only-testing:PIVOTTests/PIVOTTests/testReopeningRangeNeedsHistoryAndPointNeedsScoredSameRideSupport
      -only-testing:PIVOTTests/PIVOTTests/testBestReopeningPredictionUsesForecastMedianAndParkLocalTime
      -only-testing:PIVOTTests/PIVOTTests/testBestReopeningPredictionMarksPassedPointWithinCurrentWindow
      -only-testing:PIVOTTests/PIVOTTests/testReopeningDisplayDisambiguatesDSTFallbackRangeAndBestPrediction
      -only-testing:PIVOTTests/PIVOTTests/testReopeningDisplayKeepsSameOffsetStringsUnchanged
      -only-testing:PIVOTTests/PIVOTTests/testBestReopeningPredictionUsesReleasedV3ForecastWithoutPromotingActivityGuidance
      -only-testing:PIVOTTests/PIVOTTests/testBestReopeningPredictionWithholdsUnavailableAndUnverifiedTimes
      -only-testing:PIVOTTests/PIVOTTests/testExpiredReopeningWindowCannotRemainUpcomingBetweenRefreshes
      -only-testing:PIVOTTests/PIVOTTests/testFailedExpiredAndFutureDataWithholdReopeningGuidance
      -only-testing:PIVOTTests/PIVOTTests/testOctober17FigmentRevisionWaitsForSameEpisodeObservation
      -only-testing:PIVOTTests/PIVOTTests/testActiveAndUnobservedLightningCannotPromiseAReopening
      -only-testing:PIVOTTests/PIVOTTests/testMappedClearanceNeedsCurrentSupportedRestartEvidence
      -only-testing:PIVOTTests/PIVOTTests/testLiveActivityRetainsRangeWithoutUnsupportedPointAndMarksItsContract
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningWindowShowsSupportedBestPredictionAndUnavailableStates
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningWindowWithholdsRangeOnlyStaleAndMissingPoints
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningWindowDistinguishesEndedFailedAndPassedPredictions
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningPredictionRemainsReadableAtAccessibilitySizeInRows
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningPredictionRemainsReadableAtAccessibilitySizeInRadar
    ) ;;
  reference-ui)
    test_options+=(
      -only-testing:PIVOTTests/NativeParkExtrasTests/testHistoryWithholdsConflictingAndImpossibleSampleValues
      -only-testing:PIVOTTests/NativeParkExtrasTests/testHistoryPreservesGapsAndSingleObservationAndSixHourBoundary
      -only-testing:PIVOTTests/NativeWaitForecastTests/testLowestWaitSummaryUsesSupportedWindowAndWithholdsUnavailableStates
      -only-testing:PIVOTTests/PIVOTTests/testReopeningRangeNeedsHistoryAndPointNeedsScoredSameRideSupport
      -only-testing:PIVOTTests/PIVOTTests/testFailedExpiredAndFutureDataWithholdReopeningGuidance
      -only-testing:PIVOTUITests/PIVOTUITests/testObservedWaitDotsKeepEveryValueAndOpenLowestWaitForecast
      -only-testing:PIVOTUITests/PIVOTUITests/testHistoryLowestWaitPredictionWithholdsMissingAndStaleEvidence
      -only-testing:PIVOTUITests/PIVOTUITests/testReopeningWindowShowsSupportedBestPredictionAndUnavailableStates
      -only-testing:PIVOTTests/PIVOTTests/testRideSearchWaitsFollowLatestSnapshotAndOperatingStates
      -only-testing:PIVOTTests/PIVOTTests/testRideSearchWithholdsStaleFailedMissingAndWrongParkWaits
      -only-testing:PIVOTTests/PIVOTTests/testRideSearchRejectsContradictoryProviderStatusAndInvalidWaits
      -only-testing:PIVOTTests/PIVOTTests/testRideSearchRetainsQueryAcrossLiveWaitUpdatesAndFailures
      -only-testing:PIVOTUITests/PIVOTUITests/testRideSearchKeepsHistoricalSizeAndCurrentWaits
      -only-testing:PIVOTUITests/PIVOTUITests/testFavoriteRideSearchConnectsWaitsAndSupportsLargeText
      -only-testing:PIVOTTests/PIVOTTests/testRideSearchUsesFreshProviderSnapshotForUnchangedPostedWait
      -only-testing:PIVOTTests/PIVOTTests/testRideSearchUnchangedProviderWaitPreservesAvailabilityAndFreshnessGuards
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsSearchAndResultsShareOneNativeGroup
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsSearchAndResultsStayJoinedAtAccessibilitySize
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsSharedGroupKeepsUnchangedWaitFromFreshProvider
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitsSharedGroupWithholdsWaitFromExpiredProviderFetch
      -only-testing:PIVOTUITests/PIVOTUITests/testLowestWaitEvidenceAndHourlySheetStayConsistentAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testStaleLowestWaitHourlySheetWithholdsRecommendationAtAccessibilityTextSize
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeSurfacesPreserveHoursShowsAlertsAndPlanProgress
      -only-testing:PIVOTTests/PIVOTTests/testGeneratedIllustrationsAreBundledBoundedAndAttributed
      -only-testing:PIVOTTests/PIVOTTests/testGeneratedIllustrationsRequireAnExactParkAndRideMatch
      -only-testing:PIVOTTests/PIVOTTests/testIllustrationCacheLoadsPackagedFilesAndHandlesMissingFiles
      -only-testing:PIVOTUITests/PIVOTUITests/testGeneratedRideIllustrationLoadsWithCreditsAndPreservesWaits
      -only-testing:PIVOTUITests/PIVOTUITests/testGeneratedRideWithReservedPhotoRightsKeepsAccurateCredits
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceEPCOTCardsSearchFiltersAndPhotoCredits
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceCardsKeepEachParksIdentityAndNativeTabs
      -only-testing:PIVOTUITests/PIVOTUITests/testAccentSettingsPersistAfterRelaunch
    ) ;;
  native-design)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceEPCOTCardsSearchFiltersAndPhotoCredits
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceCardsKeepEachParksIdentityAndNativeTabs
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeMapFillsWindowAndSupportsPinchPanZoomWithoutCameraReset
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeClustersZoomAndCoLocatedPlacesRemainSelectable
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeSurfacesPreserveHoursShowsAlertsAndPlanProgress
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeDarkAndLargeTextSurfacesRemainReachable
    ) ;;
  large-text)
    test_options+=(-only-testing:PIVOTUITests/PIVOTUITests/testNativeDarkAndLargeTextSurfacesRemainReachable) ;;
  map-gestures)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testMapSearchAndCategoryWorkWithBundledLocations
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeMapFillsWindowAndSupportsPinchPanZoomWithoutCameraReset
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeClustersZoomAndCoLocatedPlacesRemainSelectable
    ) ;;
  *)
    echo 'Unsupported PIVOT_TEST_SCOPE; use all, artwork-delivery, artwork-credits, layout-review, map-attribution, wait-history, lowest-waits, reopening, reopening-accessibility, reference-ui, native-design, large-text, map-gestures, or map-refresh.' >&2
    exit 1 ;;
esac
python3 - <<'PY'
import json, os
scope = os.environ.get('PIVOT_TEST_SCOPE', 'all')
with open('build/test-scope.json', 'w') as f:
    json.dump(dict(scope=scope, completeRegression=scope == 'all'), f, indent=2)
    f.write('\n')
PY
test_exit=0
xcodebuild -project PIVOT.xcodeproj -scheme PIVOT \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/TestDerivedData \
  -resultBundlePath build/native-tests.xcresult \
  "${test_options[@]}" -jobs 3 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  test 2>&1 | tee build/native-tests.log || test_exit=$?
export_exit=0
if [[ -d build/native-tests.xcresult ]]; then
  xcrun xcresulttool export attachments --path build/native-tests.xcresult --output-path build/ui-screenshots || export_exit=$?
fi
if [[ "$test_exit" -ne 0 ]]; then
  exit "$test_exit"
fi
exit "$export_exit"
