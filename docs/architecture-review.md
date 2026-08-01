# Architecture review and rearchitecture plan (August 2026)

The diagnosis that drove the ShinerCoreKit rearchitecture. Kept for the reasoning;
docs/architecture.md describes the result.

## Root causes

Two, from which every symptom followed:

1. **The model layer was live.** `CoreProperty` held its `CBCharacteristic`; `ShinerCore`
   was the `CBPeripheralDelegate`. No seam existed for a fake device, so nothing was
   testable or previewable, and nested-`ObservableObject` propagation required manual
   `objectWillChange.send()` before every prop mutation.
2. **Connection was keyed to list selection, not screen visibility.** On compact width,
   `NavigationSplitView` doesn't clear selection on pop, so `onChange(of: selectedCore)`
   never fired: back didn't disconnect, re-tap didn't reconnect, and prop values lived on
   the discovered-core object forever — hence stale state on re-entry.

## Symptoms traced

* Background/foreground "zombie" UI: `didDisconnectPeripheral` only nil'd a var no view
  read. No reconnect attempt, no disabled state.
* Scroll sticking: `if prop.available` conditionally inserted boxes into a `LazyVGrid`,
  so content height churned under the scroll position as characteristic reads trickled in.
* Documentation JSON re-parsed three times per body evaluation.
* Four force-unwrapped callback closures on `CoreManager`, assigned in `onAppear` —
  crash window, hidden dependencies, and a shadow copy of the cores array in view state.
* Throttler raced (task flag mutated from two isolation domains) and delivered the final
  slider value only by accident of reading `rawValue` late.
* `switchTo(layer:)` refetched via blind `asyncAfter(0.5)` instead of awaiting the write.
* Write/connect errors printed and dropped.
* Scanning never stopped; lost cores never pruned.

## Decisions

* **Reconnection uses CoreBluetooth's standing connect intent**: `connect()` never times
  out, it completes whenever the device reappears. Reconnect policy = "on disconnect
  event, if the session is still alive, call connect() again". No timers, no backoff.
* **Session lifetime = view lifetime** via `.task`: structured cancellation is the
  disconnect. Back = disconnect; visible = keep trying.
* **Optimistic writes with a dirty window**: a prop with a pending outbound write ignores
  inbound reads (stops refetches yanking sliders mid-drag); equal-value writes are
  skipped (stops color round-trip oscillation, ±1 from Color→UIColor re-quantization).
* **`ledCount` keeps live writes while dragging** — deliberate: the strip itself is the
  feedback showing when the count matches the physical LEDs.
* **iOS 17 / macOS 14 floor** for `@Observable`; iPhone, iPad, Mac, Vision all stay.
* **Punted: firmware notifications** (`setNotifyValue`). Long-wanted, especially for
  layer/preset-driven prop changes and second-phone edits; needs a firmware-side change.
  Until then the app refetches after preset/layer switches and on foregrounding.
