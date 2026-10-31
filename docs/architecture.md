# Architecture

Four layers in one direction; the seam between session and device is the
`CoreLink` protocol. Everything below the views lives in the local package
**ShinerCoreKit** (the app target holds views only). Rationale and history:
[architecture-review.md](architecture-review.md).

## Model — pure values (`Model/`)

`CoreState` is a snapshot: raw wire strings keyed by `PropertyID`, an
availability set, and the decoded `Documentation`. `PropertyKey<Converter>`
pairs a property's identity with its wire format; `CoreProps` lists every
key — the UUIDs are the spec and must match the
[firmware](https://github.com/nevyn/shinercore). No CoreBluetooth, no I/O:
CBUUIDs exist only in `BLE/`.

## Transport — the `CoreLink` seam (`Transport/`, `BLE/`)

A `CoreLink` is one device: an `AsyncStream<CoreLinkEvent>` (connected,
disconnected, incompatible, becameAvailable, valueRead, readFailed,
valueChanged) plus `connect()`, `disconnect()`, awaitable acked `write`,
and `read(id)` — exactly one response event per read request, which is what
lets the session count outstanding reads. `valueChanged` is an unsolicited
notification: another central wrote, the firmware's layer/preset cursor
fanned out, or our own write echoed back. CoreBluetooth delivers reads and
notifications through the same callback; `BLECoreLink` tells them apart by
that outstanding-read count (a notification arriving mid-read can swap
roles with the response — harmless, both carry fresh device values).
Firmware without notify support (pre-BLENotify) just never emits
`valueChanged`; everything else works identically. `connect()` is a
standing intent — it keeps trying until it succeeds or `disconnect()` is
called, mirroring CoreBluetooth's never-timing-out
`CBCentralManager.connect`. `incompatible` (wrong device, forgotten
peripheral) means reconnecting is pointless; the session parks in `.failed`
instead of retrying forever.

`BLECoreLink` implements it over a `CBPeripheral`. `CoreBrowser` owns the
`CBCentralManager`: scanning (foreground only; `refresh()` prunes
powered-off cores), discovery (`DiscoveredCore` values, not live objects;
signal bars live beside them in `signalBars`, smoothed by `SignalMeter`, so a
changing RSSI never changes list identity),
vending sessions, and forwarding central-level delegate callbacks to the
right link. `FakeCoreLink` is the same contract backed by a small model of the
firmware — previews, tests, and the app's `-demo…` launch arguments (see AGENTS.md)
run the full stack against it. It keeps five presets of ten layers behind the `preset`
and `layer` cursors and serves the per-layer properties (`CoreProps.perLayer`) of the
layer under them; moving a cursor republishes them as notifications. `layers` and
`layersRevision` derive from the model, `layerMove` moves layers per the contract,
`gates` and `neighborLayers` stand in for switches and the mesh carousel, and a write
yields once before acking, as a round trip would. Assigning `values` routes into the
model, so tests and previews still set a property by id. The model has no DEBUG-only
parts: it is meant to ship as demo mode.

## Session — the controller (`Session/`)

`CoreSession` (@Observable @MainActor) enlivens the model. Its lifecycle IS
structured concurrency: a view runs `session.run()` in a `.task`, and

* task cancelled (screen left) → disconnect. Back = disconnect.
* `.disconnected` event while alive → `connection = .reconnecting`,
  re-issue the standing connect; on reconnect, re-read everything. Stale
  state is impossible by construction.

Writes are optimistic: `set()` updates `state` immediately, and a per-prop
trailing-edge timer queues the *latest* value at most once per throttle interval
(100 ms). Equal-value writes are skipped (stops color round-trip oscillation).

Queued writes reach the link one at a time, in the order queued, each with the value
it had when queued. Order matters because the core applies a per-layer write to
whichever layer its cursor points at when the write arrives. `select()` is for
layer/preset, whose device-side change fans out to other props: it first flushes
every throttled edit (they were made for the old cursor), then queues the cursor
write, then re-reads everything after the ack. A failed write drops the writes
queued behind it (they may depend on it, as edits depend on a cursor move), says so
in `lastError`, and re-reads.

Inbound values never clobber a newer optimistic one. While a write that changes a
prop is throttled, queued or in flight, reads and notifications of that prop are
dropped. The device answers reads in order, so a read requested before a write went
out is stale even when it arrives after the ack; the session tracks outstanding reads
per prop and drops exactly those responses, so a refetch can never yank a slider
back. A write can also hold other props whose device values it changes: a cursor
write holds the per-layer props, and a layer move holds those, the cursor and the
summary. Errors land in `lastError`,
rendered by the UI, dismissible.

## Views (app target)

`CoreListView` (browser + scan lifecycle) → `CoreDetailView` (owns the
session via `.task(id:)`, re-reads on scenePhase reactivation) →
`CoreControlsView` (Play/Wiring/Setup tabs, connection banner, disables
everything while not connected).

* **Play** (`PlayView`): the composite preview, lights, brightness, preset chips and
  the layer stack: front-most first, the bottom layer labeled Base, each row with a
  strip of that layer alone. Drag reorders (`moveLayer`), swipe removes, Add layer fills
  the first empty slot, a tap moves the cursor and opens `LayerEditorView` in a sheet.
  A core without `layers`, or with one that can't be read, gets `SingleLayerView`
  (layer chips, "Layer N alone") in place of the stack.
* **Wiring**: see below.
* **Setup**: owner, power-on preset, LED strip, sound and mesh: what is set once. Prop boxes take `(session, key)` and stay
in the layout even when unavailable — dimmed via `.availability(of:in:)` —
because structural stability is what keeps scrolling from jumping while
characteristic reads trickle in.

## Strip preview

Play draws what the strip shows; the layer editor, the stack's rows and the
animation cards draw one layer alone. The drawing
comes from the firmware's render library, not from Swift: ShinerCoreKit depends on
the firmware repository's SwiftPM package `ShinerRender`, pinned to a firmware commit
(move the pin when the firmware's animations change, so previews follow), and only
`Render/StripRenderer.swift` imports it. The library's C API is a contract that only
grows; see the firmware's docs/rendering.md.

* `RenderLibrary` addresses the library's animations and blend modes by name, so a
  core on other firmware previews correctly wherever names match. `StripRenderer`
  returns nil for an animation name the library doesn't know: no preview beats a
  wrong one. An unknown blend mode blends as Add, as on the device.
* `CoreState.layerLook` turns the selected layer's wire values into a `LayerLook`.
  A layer's time is seconds / speed; a beat-synced layer and Beat Pulse play against
  a steady 120 bpm beat, because the app hears no music.
* `CoreState.animationDoc(for:)` says which colors an animation reads and what it
  calls tau and phi. The core's `animationDocs` wins (matched by index to
  `documentation.animations`; a count mismatch is reported and ignored), then the
  render library's table by name, then generic "Tau"/"Phi" with both colors.
* `StripPreview` (app target) draws pixels as dots with additive halos in a black
  well, in both appearances; `compact` is a thin strip without halos that bins by
  the brightest pixel, so a lone spark stays visible. One layer alone is drawn with
  Set, because a Multiply or Darken layer blended onto black shows nothing. For one
  layer, a `PreviewClock` advances playback by the current speed each frame, so a
  speed change alters the pace instead of jumping; a stack plays in seconds. Under
  Reduce Motion the preview holds a still frame a third of the way into the cycle.
* The composite (`StripRenderer.render(_:seconds:pixelCount:brightness:)`) blends
  every layer with its blend mode, hides a layer whose gate is closed, then scales by
  `CoreState.stripBrightness` (0 while the lights are off). Play passes that through
  a 1/2.2 power: LEDs look brighter than their duty cycle and screens are
  gamma-encoded, so a linear scale would show a 20 % strip as nearly black.

## The layer summary

The per-layer properties show one layer at a time, the one under the cursor. The
firmware's `layers` property shows the whole stack at once, `layersRevision` notifies
when it would read differently, and `layerMove` reorders it. Formats: the firmware's
docs/ble-comms.md, "The layer summary".

* The session reads `layers` at connect and whenever `layersRevision` changes, and
  decodes it into `LayerSummary` once `documentation` names its indices. A value
  that fails to decode sets `layerSummaryError` (the failing line, in `lastError`)
  and Play falls back to the single-layer view.
* The summary says whose preset plays: the core's own (`P n`) or a neighbor's while
  the mesh carousel plays one (`M`). The carousel takes turns every few beats, so
  `ownLayerSummary` keeps the last own summary: the stack lists the core's own layers
  throughout, the hero shows what plays, and Play says "Playing a neighbor's preset".
* `CoreState.stack` overlays the cursor's layer from the per-layer properties, which
  follow an edit at once, while the summary waits for the next revision.
* `selectLayer` shows the summary's values for the new layer until the core answers,
  so a cursor move never shows the previous layer's settings; `selectPreset` shows
  the per-layer properties as loading instead. `addLayer` writes Static to the first
  empty slot, unconditionally, because the current value may describe another layer.
  `removeLayer` writes Nothing. Both move the cursor first.
* `moveLayer` updates the summary optimistically. Wiring and layer gates stay with
  their slot, so `LayerSummary.wiringNotice` says which wired controls now act on
  another layer ("The switch on G23 now controls Comet."), and Play shows it under
  the stack. `LayerSummary.layerMove(fromRow:toRow:)` maps a drop in the front-first
  list to the firmware's `FROM TO`.

## Wiring

The Wiring tab edits the core's wiring: a map from pin to role, defined by the
firmware's [docs/wiring.md](https://github.com/nevyn/shinercore/blob/main/docs/wiring.md).
Three properties carry it:

* `wiringDocs` (read once) decodes into `CoreState.wiringDocs`: the board id, its
  pins in status bit order, the front button's label, which pins can be knobs or
  LEDs, which hardware can claim, and the knob targets.
* `wiring` decodes into `Wiring` (pin label → `PinRole`). The editor writes the
  whole value through `set`.
* `pinStatus` notifies live pin state as hex: a revision, closed and claimed
  bitmasks, and knob positions.

`wiring` is too long for a notification (ArduinoBLE caps them at 20 bytes), so it
has no notify. Every `wiring` write bumps the pinStatus revision instead, and the
session re-reads `wiring` whenever it sees a new revision. That read-back also
corrects the optimistic value after the firmware rejects a write.

The firmware publishes what each pin can do; the app owns only the board layout
(header drawing, Grove labels and wire colors in `WiringDiagram.swift`), keyed by
board id. An unknown board id gets the pin list without the drawing.

The front button on the face of the case is a wiring key like any pin, but its
only role is button, `pinStatus` doesn't report it, and an absent key means
`nextPreset` (`Wiring.role(of:docs:)`). Its row has no live indicator, and its
editor offers only the button action. Firmware that predates it omits it from
`wiringDocs`, and the tab shows no row.

Closed switches hold the lights or a preset (`CoreState.lightsHold`,
`presetHold`); Play names the holding switch and disables
the control, because the firmware would undo any write.

## Notifications

The firmware notifies on every property change (`BLENotify`; its
`publish()` is the single change path), and the app subscribes to every
characteristic that offers it. Device-side changes appear live — today
that's the core's button switching presets (verified on hardware); mesh
sync will ride the same path. A second simultaneous phone won't:
ArduinoBLE accepts one central at a time. A notification for a dirty prop
is dropped like any other inbound value. The refetch after `select()` and
on foregrounding stays — it costs little, covers dropped notifications,
and keeps pre-notify firmware fully supported.
