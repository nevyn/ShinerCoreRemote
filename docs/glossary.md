# Glossary

The firmware owns the vocabulary that the app shares with it (wiring, pin, role,
claim, knob, target, layer gate, preset, layer, mesh):
[shinercore docs/glossary.md](https://github.com/nevyn/shinercore/blob/main/docs/glossary.md).
Use those terms in code, docs, the app's texts and commits.

App-only terms:

* **board layout**: the app's drawing data for a board (headers, Grove socket, wire
  colors), keyed by the firmware's board id. Not "board geometry" or "pinout".
* **hold**: a closed switch keeping a setting (lights, preset) at its value; the app
  shows "Held by the switch on G25" and disables that control. Not "lock" or "override".
* **strip preview**: the app's drawing of what a strip shows, rendered by the
  firmware's render library. A preview, not a mirror: the core may run other firmware.
  Not "simulator" or "virtual strip".
* **composite**: the strip preview of every layer, blended and at the core's brightness:
  what the strip shows. Play's hero draws it; everything else draws one layer alone.
* **stack**: a preset's layers that play (not Nothing), as Play lists them, front-most
  first. Not "layer list".
