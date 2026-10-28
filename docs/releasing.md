# Releasing

How a commit on `main` becomes an App Store version. App Store Connect app id
`6451475618`; every `asc` call below is the [asc CLI](https://asccli.sh).
`Scripts/release.sh` wraps the steps that need ID lookups or waiting.

Submitting for review, and anything else App Store Connect shows the public or
Apple, needs the maintainer's go-ahead. An agent prepares the version and asks.

## 1. Build

A push to `main` makes Xcode Cloud (workflow "Default") upload a build to
TestFlight. The workflow assigns build numbers; the project only sets
`MARKETING_VERSION`.

* Bump `MARKETING_VERSION` in the pbxproj past the live version before merging.
  Otherwise App Store Connect rejects the build as ITMS-90186/90062 ("train closed").
* A merge sometimes fails to start a run. Check with
  `asc xcode-cloud build-runs --workflow-id BB6F9310-8EB0-4FAE-ADD1-25652C17E3B2 --sort -number --limit 3`
  and start one with `asc xcode-cloud run --app 6451475618 --workflow Default --branch main`.
* Every build number exists twice, as an iOS and a visionOS build. The iOS version
  needs the iOS one: `asc builds list --app 6451475618 --platform IOS --version X.Y`.

## 2. Stage

```
Scripts/release.sh stage X.Y PREVIOUS
```

This creates version X.Y with the newest VALID iOS build and copies the
description, keywords and URLs from PREVIOUS. What's New is left empty on
purpose; the script prints the command that sets it. What's New is the
maintainer's to write or approve. `DRY_RUN=1` in front of `stage` or `submit`
previews the plan and the readiness checks without changing anything.

Review notes carry over from the previous version. Read them with
`asc review details-for-version --version-id ID` and update the "changes since"
part with `asc review details-update --id DETAIL_ID --notes …`. The notes tell
the reviewer that the app needs ShinerCore hardware, that an empty core list is
the expected state without it, where to watch a video of it working, and that
there is no account or server.

## 3. Screenshots

Only when the UI changed:

```
Scripts/screenshots.sh all
Scripts/release.sh screenshots X.Y
```

A new version inherits the live version's screenshots under the same file names,
so `release.sh screenshots` empties each set before uploading the local captures.
Screenshots appear in upload order, and App Store Connect can't reorder them.

App Store Connect requires the iPhone 6.1" slot (`APP_IPHONE_61`) and the 13"
iPad (`APP_IPAD_PRO_3GEN_129`); the 6.9" slot is optional. On the Mac this ships
as the iPad app, so there is no macOS listing.

## 4. Check and submit

```
asc review doctor --app 6451475618 --version X.Y
Scripts/release.sh submit X.Y
```

These doctor findings don't block review: the subtitle and copyright warnings,
and the empty legacy screenshot sets `APP_IPHONE_58`/`APP_IPHONE_65` (asc can't
delete sets). An age-rating finding does block; the questionnaire is an
attestation, so the maintainer answers it in the web UI.

`release.sh submit` waits until Apple has processed every screenshot, because
a submission fails with "Asset is being processed" while any are pending.
After approval, `asc versions list --app 6451475618` shows `READY_FOR_SALE`. The
public iTunes lookup API keeps showing the old version for hours.

## asc quirks

* `asc` reshapes the API's JSON. `asc screenshots list` returns
  `.sets[].screenshots[]`, not `.data[]`; reading `.data` gives an empty result
  that looks exactly like "no screenshots yet".
* A screenshot upload can report failure after the bytes landed, because Apple
  settles the checksum slowly. The listing decides whether to retry.
* Only a version in `PREPARE_FOR_SUBMISSION` is editable.
* An empty draft review submission (`a2c29de3…`) can't be cancelled. It is harmless.
