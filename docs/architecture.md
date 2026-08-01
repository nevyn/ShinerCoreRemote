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
disconnected, becameAvailable, valueRead, readFailed) plus `connect()`,
`disconnect()`, awaitable acked `write`, and `readAll()`. `connect()` is a
standing intent — it keeps trying until it succeeds or `disconnect()` is
called, mirroring CoreBluetooth's never-timing-out `CBCentralManager.connect`.

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
once per throttle interval (100 ms). While dirty, inbound reads for that
prop are dropped (a refetch can't yank a slider mid-drag), and equal-value
writes are skipped (stops color round-trip oscillation). `select()` is for
layer/preset, whose device-side change fans out to other props: immediate
write, then `readAll()` after the ack. Errors land in `lastError`, rendered
by the UI, dismissible.

## Views (app target)

`CoreListView` (browser + scan lifecycle) → `CoreDetailView` (owns the
session via `.task(id:)`, re-reads on scenePhase reactivation) →
`CoreControlsView` (Animation/Core tabs, connection banner, disables
everything while not connected). Prop boxes take `(session, key)` and stay
in the layout even when unavailable — dimmed via `.availability(of:in:)` —
because structural stability is what keeps scrolling from jumping while
characteristic reads trickle in.

## Punted

Firmware notifications (`setNotifyValue`) — wanted for layer/preset-driven
changes and second-phone edits; needs firmware work. Until then: refetch
after `select()` and on foregrounding.
