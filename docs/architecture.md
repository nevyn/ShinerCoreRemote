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
powered-off cores), discovery (`DiscoveredCore` values, not live objects),
vending sessions, and forwarding central-level delegate callbacks to the
right link. `FakeCoreLink` is the same contract scripted — previews, tests,
and the app's `-demo`/`-demo-offline`/`-demo-list` launch arguments (see
AGENTS.md) run the full stack against it.

## Session — the controller (`Session/`)

`CoreSession` (@Observable @MainActor) enlivens the model. Its lifecycle IS
structured concurrency: a view runs `session.run()` in a `.task`, and

* task cancelled (screen left) → disconnect. Back = disconnect.
* `.disconnected` event while alive → `connection = .reconnecting`,
  re-issue the standing connect; on reconnect, re-read everything. Stale
  state is impossible by construction.

Writes are optimistic: `set()` updates `state` immediately, marks the prop
dirty, and a per-prop trailing-edge task writes the *latest* value at most
once per throttle interval (100 ms). Dirtiness clears only once no writer
is active AND no counted reads are outstanding — the device answers reads
serially, so a response requested before the write is stale even when it
arrives after the ack; dropping exactly that many responses means a refetch
can never yank a slider back. Equal-value writes are skipped (stops color
round-trip oscillation). `select()` is for layer/preset, whose device-side
change fans out to other props: immediate write, then a full re-read after
the ack. Errors land in `lastError`, rendered by the UI, dismissible.

## Views (app target)

`CoreListView` (browser + scan lifecycle) → `CoreDetailView` (owns the
session via `.task(id:)`, re-reads on scenePhase reactivation) →
`CoreControlsView` (Animation/Core tabs, connection banner, disables
everything while not connected). Prop boxes take `(session, key)` and stay
in the layout even when unavailable — dimmed via `.availability(of:in:)` —
because structural stability is what keeps scrolling from jumping while
characteristic reads trickle in.

## Notifications

The firmware notifies on every property change (`BLENotify`; its
`publish()` is the single change path), and the app subscribes to every
characteristic that offers it. Second-phone edits and cursor fanout appear
live; a notification for a dirty prop is dropped like any other inbound
value. The refetch after `select()` and on foregrounding stays — it costs
little, covers dropped notifications, and keeps pre-notify firmware fully
supported.
