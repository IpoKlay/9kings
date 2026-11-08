# Isolated combat kernel experiment (native v2)

This is a macOS arm64 prototype outside `godot-game`, not production integration.
The production project does not auto-load this extension. Windows is untested.
V1 moved ordered pair math across the boundary; V2 additionally builds an ordered
64 px neighbor grid. Both preserve the sequential solver and its RNG; neither
establishes equivalence to the unavailable latest original game.

## Reproduce the existing build (not rebuilt in this iteration)

Prerequisites already used on this machine:

- Official `godot-cpp` 4.5 at commit `27d9dd23c83871e0619fca5dc2cddfbfd69e926a`.
- Checkout: `/private/tmp/eagle-godot-cpp-4.5`.
- SCons: `/private/tmp/eagle-native-buildenv/bin/scons`.
- Runtime tested: Godot `4.7.2.stable.official.ed1daf0bf`, macOS arm64.

From this directory, verify the dependency revision, then build only when wanted:

```sh
git -C /private/tmp/eagle-godot-cpp-4.5 rev-parse HEAD
/private/tmp/eagle-native-buildenv/bin/scons godot_cpp=/private/tmp/eagle-godot-cpp-4.5 platform=macos arch=arm64 target=template_release precision=single lto=none build_profile="$PWD/build_profile.json"
```

`SConstruct` enforces macOS arm64 and single precision and appends
`-fno-fast-math -ffp-contract=off`. Do not append flags that override strict FP.
The output is `bin/libeagle_combat_kernel.macos.template_release.arm64.dylib`;
`combat_kernel.gdextension` uses entry symbol `eagle_combat_kernel_library_init`
and declares minimum compatibility 4.5. Compatibility with 4.5 itself has not
been runtime-tested here. The build profile enables RefCounted and OS.

## Prepare and run an isolated probe

From the repository root:

```sh
python3 native/combat_kernel/prepare_probe.py --project "$PWD/godot-game"
```

The command prints JSON containing `probe_project`. Assign that returned path to
`PROBE_PROJECT` below. It copies scripts/tests/cache, links shared resources,
adds a temporary extension loader, and replaces only the copied repulsion dispatch.
It never changes the production dispatch. Do not edit linked resources in the probe.

```sh
PROBE_PROJECT=/absolute/path/from/probe_project
/Users/ip/Downloads/Godot.app/Contents/MacOS/Godot --headless --path "$PROBE_PROJECT" --script res://tests/tactical/test_packed_repulsion.gd
/Users/ip/Downloads/Godot.app/Contents/MacOS/Godot --headless --path "$PROBE_PROJECT" --script "$PWD/native/combat_kernel/test_boundary.gd"
/Users/ip/Downloads/Godot.app/Contents/MacOS/Godot --headless --path "$PROBE_PROJECT" --script res://tests/tactical/benchmark_large_battle.gd -- native-reproduction 500 120 "$PWD/output/api-performance-2026-11-07"
/Users/ip/Downloads/Godot.app/Contents/MacOS/Godot --path "$PROBE_PROJECT" --script res://tests/tactical/benchmark_large_live.gd -- native-live-reproduction "$PWD/output/api-performance-2026-11-07"
```

Boundary tests intentionally emit labelled native errors for rejected inputs;
check the final seven-check verdict. The parity suite checks that native dispatch
was actually exercised (41 checks). Eight additional suites passed in the archived
v2 probe; see `native-v2-regression.json` (181 checks). Repeat these commands on
an unmodified current-source baseline for any new comparison: old timings are
historical evidence, not a benchmark for subsequently modified sources.

## Recorded outcome

V1 fixed-step mean: 61.310→56.511 ms, repeat 54.793→54.519 ms;
actual FPS: 2.838→2.804. No demonstrated useful sustained FPS improvement.
V2 fixed-step mean: 52.338→49.487 ms, repeat 54.429→50.366 ms;
actual FPS: 2.879→3.057, repeat 2.820→2.962. Both v2 120-tick final
binary states match their baselines exactly. Those historical states cover units,
repulsion seed/time, elapsed time and phase; they do not cover all global state
or every intermediate tick. V2 remains far below 30 FPS and simulation runs at
roughly 0.29–0.31 simulated seconds per real second.

Detailed metrics, hashes, logs and limitations:
`../../output/api-performance-2026-11-07/native-validation.json`.
No exports, native rebuilds or production integration were performed in this iteration.
