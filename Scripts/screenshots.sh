#!/bin/bash
# Capture the App Store / README screenshot set, unattended.
#
#   Scripts/screenshots.sh [iphone|ipad|all]   (default: all)
#
# Every shot is "launch with a -demo argument, then capture" — no taps, so
# nothing breaks when a control moves. Both simulators are exact matches for
# the pixel sizes App Store Connect accepts (asc screenshots sizes).
#
# iPhone and iPad are the whole story: on the Mac this ships as the iPad app,
# so there is no macOS listing and no separate Mac screenshots to take.
#
# Upload (only onto a PREPARE_FOR_SUBMISSION version, and never without
# checking what is already there — `asc screenshots download` first):
#   LOC=$(asc localizations list --version <VERSION_ID> | ...)
#   asc screenshots upload --version-localization "$LOC" \
#       --path screenshots/APP_IPHONE_67/3-core.png --device-type IPHONE_67

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE=jpg.nevyn.shinerconf
SCHEME=ShinerCoreRemote
OUT=${OUT:-screenshots}
DD=${DD:-build/screenshots-dd}
WHICH=${1:-all}

# name:launch-arguments — the order here is the order on the store listing.
SHOTS=(
  "1-cores:-demo-list"
  "2-animation:-demo-tab animation"
  "3-core:-demo-tab core"
  "4-mesh:-demo-tab mesh"
  "5-wiring:-demo-tab wiring"
)

# Simulator name : ASC display type. `asc screenshots sizes --all` lists which
# pixel sizes each display type accepts; these two devices are native matches
# (iPhone Air 1260x2736, iPad Pro 13" 2064x2752).
SIMS=(
  "iPhone Air:APP_IPHONE_67"
  "iPad Pro 13-inch (M5):APP_IPAD_PRO_3GEN_129"
)

say() { printf '\n▸ %s\n' "$*"; }

# The iPad draws the discovery list as a narrow sidebar beside an empty detail
# pane, which is a weak lead screenshot; its set starts at the first tab.
skip_shot() {
  [ "$1" = "APP_IPAD_PRO_3GEN_129" ] && [ "$2" = "1-cores" ]
}

capture_sim() {
  local device="$1" display="$2" udid dir
  udid=$(xcrun simctl list devices available -j \
    | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for v in d.values() for x in v if x['name']=='$device'))")

  say "$device ($display)"
  xcodebuild -project ShinerCoreRemote.xcodeproj -scheme "$SCHEME" \
    -destination "id=$udid" -derivedDataPath "$DD" build >/dev/null
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$DD/Build/Products/Debug-iphonesimulator/$SCHEME.app"
  # A believable status bar; the real one shows a dying battery and TestFlight.
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --cellularMode active --cellularBars 4 \
    --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100

  dir="$OUT/$display"
  mkdir -p "$dir"
  for shot in "${SHOTS[@]}"; do
    local name=${shot%%:*} args=${shot#*:}
    if skip_shot "$display" "$name"; then continue; fi
    xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
    # shellcheck disable=SC2086 -- args are intentionally word-split
    xcrun simctl launch "$udid" "$BUNDLE" $args >/dev/null
    sleep 3   # let the fake link connect and the view settle
    xcrun simctl io "$udid" screenshot "$dir/$name.png" >/dev/null 2>&1
    printf '  %s\n' "$dir/$name.png"
  done
  xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
}

case "$WHICH" in
  iphone) capture_sim "iPhone Air" APP_IPHONE_67 ;;
  ipad)   capture_sim "iPad Pro 13-inch (M5)" APP_IPAD_PRO_3GEN_129 ;;
  all)    for sim in "${SIMS[@]}"; do capture_sim "${sim%%:*}" "${sim##*:}"; done ;;
  *) echo "usage: $0 [iphone|ipad|all]" >&2; exit 2 ;;
esac

say "Sizes (must match asc screenshots sizes --all):"
find "$OUT" -name '*.png' | sort | while read -r f; do
  printf '  %-46s %s\n' "$f" "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done
