#!/bin/zsh

# Read-only verification shared by the worker and command-line waiters.
pivot_reported_build() {
    local json="$1" bundle="$2" index reported version
    [[ "$(plist_read "$json" info.outcome || true)" == success ]] || return 1
    for index in {0..127}; do
        reported="$(plist_read "$json" "result.apps.$index.bundleIdentifier")" || reported=""
        [[ -n "$reported" ]] || { reported="$(plist_read "$json" "result.apps.$index.bundleID")" || reported=""; }
        [[ -n "$reported" ]] || break
        [[ "$reported" == "$bundle" ]] || continue
        version="$(plist_read "$json" "result.apps.$index.bundleVersionNumber")" || version=""
        [[ -n "$version" ]] || { version="$(plist_read "$json" "result.apps.$index.bundleVersion")" || version=""; }
        [[ -n "$version" && "$version" != *[^0-9.]* ]] || return 1
        print -r -- "$version"
        return 0
    done
    return 1
}

pivot_state_is_verified() {
    local state_file="$1" fingerprint="$2" release_id="$3" device="$4" since="$5"
    local verified build
    [[ -n "$fingerprint" && -n "$release_id" && -n "$device" && "$since" == <-> ]] || return 1
    [[ "$(plist_read "$state_file" NeedsSourceInstall || true)" == false && \
       "$(plist_read "$state_file" PendingInstall || true)" == false && \
       "$(plist_read "$state_file" InstalledSourceFingerprint || true)" == "$fingerprint" && \
       "$(plist_read "$state_file" InstalledReleaseID || true)" == "$release_id" && \
       "$(plist_read "$state_file" VerifiedDeviceUDID || true)" == "$device" ]] || return 1
    build="$(plist_read "$state_file" InstalledBuildVersion || true)"
    verified="$(plist_read "$state_file" LastVerifiedEpoch || true)"
    [[ -n "$build" && "$build" != *[^0-9.]* && "$verified" == <-> ]] || return 1
    (( verified >= since ))
}
