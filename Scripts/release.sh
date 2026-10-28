#!/bin/bash
# App Store release steps for one version. The procedure: docs/releasing.md.
#
#   Scripts/release.sh stage VERSION FROM   create VERSION with the newest VALID iOS
#                                           build, metadata copied from FROM
#   Scripts/release.sh screenshots VERSION  replace each set with screenshots/<type>/*.png
#   Scripts/release.sh submit VERSION       wait for screenshot processing, submit for review
#
# DRY_RUN=1 makes stage and submit preview their changes instead of making them.

set -euo pipefail
cd "$(dirname "$0")/.."

APP=6451475618
MODE=--confirm
[ -z "${DRY_RUN:-}" ] || MODE=--dry-run
CMD=${1:-}
VERSION=${2:-}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '\n▸ %s\n' "$*"; }

version_id() {
  local id
  id=$(asc versions list --app "$APP" --platform IOS \
    | jq -r --arg v "$VERSION" '.data[] | select(.attributes.versionString == $v) | .id')
  [ -n "$id" ] || die "no iOS version $VERSION in App Store Connect; stage it first"
  echo "$id"
}

version_state() { asc versions view --version-id "$1" | jq -r '.state'; }

localization_id() {
  local id
  id=$(asc localizations list --version "$1" \
    | jq -r '.data[] | select(.attributes.locale == "en-US") | .id')
  [ -n "$id" ] || die "version $VERSION has no en-US localization"
  echo "$id"
}

# The listing is .sets[].screenshots[], not .data[]: asc reshapes the API's JSON.
shots() { asc screenshots list --version-localization "$1"; }

names_in_set() {
  shots "$1" | jq -r --arg t "$2" \
    '.sets[] | select(.set.attributes.screenshotDisplayType == $t) | .screenshots[]?.attributes.fileName'
}

ids_in_set() {
  shots "$1" | jq -r --arg t "$2" \
    '.sets[] | select(.set.attributes.screenshotDisplayType == $t) | .screenshots[]?.id'
}

# Screenshots that Apple has not finished processing; a submit fails while any remain.
pending() {
  shots "$1" | jq -r '.sets[] | .set.attributes.screenshotDisplayType as $t | .screenshots[]?
    | (.attributes.assetDeliveryState | if type == "object" then .state else . end) as $s
    | select($s != "COMPLETE") | "\($t)/\(.attributes.fileName)=\($s)"'
}

require_editable() {
  local state
  state=$(version_state "$1")
  [ "$state" = PREPARE_FOR_SUBMISSION ] || die "version $VERSION is $state; only PREPARE_FOR_SUBMISSION is editable"
}

stage() {
  local from=${1:-} build report status=0
  [ -n "$from" ] || die "usage: $0 stage VERSION FROM"
  # Each build number exists twice, iOS and visionOS; the iOS version needs the iOS one.
  build=$(asc builds list --app "$APP" --platform IOS --version "$VERSION" \
    --processing-state VALID --sort -uploadedDate --limit 1 | jq -r '.data[0].id // empty')
  [ -n "$build" ] || die "no VALID iOS build of $VERSION yet; is Xcode Cloud still uploading or processing?"

  say "Staging $VERSION with build $build, metadata from $from"
  # Without --checkpoint-file, asc writes .asc/ into the working directory.
  report=$(asc release stage --app "$APP" --version "$VERSION" --build-id "$build" \
    --copy-metadata-from "$from" --exclude-fields whatsNew \
    --checkpoint-file "$(mktemp -d)/stage.json" "$MODE") || status=$?
  jq -r '(.steps[] | "  \(.name): \(.status) - \(.message)"),
    (.steps[] | select(.name == "validate_readiness") | .details.report.checks[]? | "    \(.severity): \(.message)")' <<<"$report"
  [ "$status" -eq 0 ] || die "staging stopped at $(jq -r .failedStep <<<"$report")"
  [ -z "${DRY_RUN:-}" ] || return 0

  local loc
  loc=$(localization_id "$(version_id)")
  say "Next: What's New, then screenshots"
  echo "  asc localizations update --id $loc --whats-new \"...\""
}

screenshots() {
  local vid loc dir type device name ids id attempt
  vid=$(version_id)
  require_editable "$vid"
  loc=$(localization_id "$vid")

  for dir in screenshots/APP_*; do
    [ -d "$dir" ] || die "no captures under screenshots/; run Scripts/screenshots.sh first"
    type=$(basename "$dir")
    device=${type#APP_}
    say "$type"

    # A new version inherits the live version's screenshots under the same file
    # names, so the set is emptied rather than merged.
    ids=$(ids_in_set "$loc" "$type")
    for id in $ids; do
      asc screenshots delete --id "$id" --confirm >/dev/null
      printf '  deleted %s\n' "$id"
    done

    # Upload order is listing order, and there is no way to reorder afterwards.
    for path in "$dir"/*.png; do
      name=$(basename "$path")
      # Upload can report failure after the bytes landed (Apple settles the
      # checksum slowly), so the listing decides, not the exit code.
      for attempt in 1 2 3; do
        asc screenshots upload --version-localization "$loc" --path "$path" \
          --device-type "$device" >/dev/null 2>&1 || true
        sleep 5
        if names_in_set "$loc" "$type" | grep -qxF "$name"; then
          printf '  uploaded %s\n' "$name"
          continue 2
        fi
        printf '  retrying %s (%s)\n' "$name" "$attempt"
      done
      die "$type/$name did not appear after 3 uploads"
    done
  done
}

submit() {
  local vid loc build waiting deadline
  vid=$(version_id)
  require_editable "$vid"
  loc=$(localization_id "$vid")
  build=$(asc versions view --version-id "$vid" | jq -r '.buildId // empty')
  [ -n "$build" ] || die "version $VERSION has no build attached; stage it first"

  deadline=$((SECONDS + 45 * 60))
  while :; do
    waiting=$(pending "$loc")
    [ -n "$waiting" ] || break
    [ $SECONDS -lt $deadline ] || die "screenshots still processing after 45 min: $waiting"
    printf '  waiting on %s screenshot(s), e.g. %s\n' "$(wc -l <<<"$waiting" | tr -d ' ')" "$(head -1 <<<"$waiting")"
    sleep 45
  done

  say "Submitting $VERSION (build $build) for review"
  asc review submit --app "$APP" --version-id "$vid" --build-id "$build" "$MODE"
  printf '  %s is now %s\n' "$VERSION" "$(version_state "$vid")"
}

[ -n "$VERSION" ] || die "usage: $0 stage|screenshots|submit VERSION"
case "$CMD" in
  stage)       stage "${3:-}" ;;
  screenshots) screenshots ;;
  submit)      submit ;;
  *)           die "usage: $0 stage|screenshots|submit VERSION" ;;
esac
