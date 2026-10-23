# Under the Eagle — Godot native port

Open `project.godot` with Godot 4.7.2 or later compatible 4.x releases and press **F5** (Run Project). The main scene is `scenes/main.tscn`. This is a native GDScript/CanvasItem game, not a browser embedded in Godot. No JavaScript runtime, Node installation, or network connection is required to play.

## Migrated from the local v0.22 game

- A cool earthy forest clearing with scattered trees, root moss, leaf litter and boot impressions. The isometric projection, original pixel characters and buildings are preserved.
- Seven allied troop types plus the training yard, all 24 cards, three nonrepeating choices per year, in-place upgrades, level caps, permanent doctrines and temporary orders.
- Unified battlefield, role-based automatic formation, healing, shields, Testudo, burning, slowing, charge, area damage, kill haste and all five documented synergies.
- Endless years, three camp lives, early gentle encounters and progressively mixed, stronger enemy armies.
- Chinese / English settings, sound enable, master and voice volume, impact feedback, pause, speed controls, army/build panel, building inspection and year reports.
- Original edited sound bank decoded to standard WAV; source credits remain in `assets/AUDIO-CREDITS.txt`.
- Settings persist in Godot's user directory. Campaign progress remains session-only, as in the original version.

### Controls

Choose a card with the mouse or **1 / 2 / 3**. Building cards reveal camp cells; click an empty cell or matching camp to build/upgrade. Click **MARCH / 出征**, or press **Space**, to start. Space pauses combat; the speed button cycles 1× / 2× / 4×. **Esc** opens settings or closes a panel. **M** toggles sound. Settings and other panels suspend combat. Buildings cannot be moved.

## Implementation

- `scripts/campaign.gd`: engine-independent native campaign/combat rules.
- `scripts/battlefield.gd`: fixed isometric projection, depth sorting, frame animation, projectiles and bounded impact effects; the world renders at 960×540 and is enlarged without smoothing.
- `scripts/main.gd`: native interface, input, modal pause, localization and preferences. UI is constructed at runtime, so the scene canvas is intentionally empty before running.
- `scripts/sound.gd`: 12-voice pool, per-sound cooldowns and limiter using existing recordings. Headless tests skip playback because no audio device is available.
- `data/rules.json`: all original card/type/enemy definitions and Chinese translations.
- `assets/`: baked pixel art/animation sheets and WAV files. Animations reuse the original renderer; the native port does not convert the game to 3D meshes.

The old HTML game and its deployment have not been replaced. This port is maintained separately in the private repository’s `godot-game/` directory. Export templates and publishing are separate next steps. The GUI uses the operating system's serif/CJK fonts; verify the target's font coverage when packaging for other platforms, or bundle a suitably licensed CJK font.

## Verification

```
godot --headless --path . --script tests/test_campaign.gd
godot --headless --path . -- --smoke-test
godot --path . -- --render-test
```

- 161 rule checks: 18 original-JavaScript combat references across nine years, combat duration, 100 seeded yearly draws, construction validity, three-life defeat, order expiry and full-camp fallback.
- Native UI smoke: language switches preserve state; settings suspend battle; opening battle wins; reports advance into the next year.
- Render check: all 24 cards in both languages fit their bounds; screenshots cover cards, construction, battle, build panel, settings and result. `--render-test` uses a temporary verification window and quits automatically.

`tools/import_web_assets.cjs` rebuilds native assets and reference fixtures from `../eagle-standard-demo/dist`. It requires Node and `@napi-rs/canvas` (set `EAGLE_CANVAS_MODULE` to the installed module path if needed). It is a developer tool, not a runtime dependency.

## Forest clearing terrain

`node tools/forest_floor.cjs` rebuilds only the native terrain texture. The central battlefield and construction area use bare soil; moss and litter gather beneath the retained forest trees. The web asset importer uses this same generator, so importing again will not restore the old grass field.

## Slightly layered card hand

Three cards overlap by 18 logical pixels (7.5% of their width), with only 1.4 degrees of side-card tilt. Hover lifts a card by 58 pixels and scales it to 140% in 0.19 seconds, placing it above its neighbours; leaving settles it in 0.22 seconds. A chosen card lifts out while the others fade, with input locked until the one reward is committed. Resting hit regions remain stable during animation, including fast switching and overlap-edge clicks.

Native paper foley uses Kenney's CC0 Casino Audio recordings: fan/deal, a single slide on hover, and a single shove on selection. Each action always uses the same recording; leaving a card is silent. The four active short cues in `assets/cards/trimmed/` have aligned onsets, matched RMS levels, and baked fades. Other earlier variants remain as unused assets. A dedicated single-voice player prevents rapidly changing gestures from stacking; pitch is fixed and global volume/mute still apply. This preserves the original recordings and short durations without frame-dependent volume tweens. Rebuild with `godot --headless --path . --script tools/prepare_card_audio.gd`, then reimport assets.

`godot --headless --path . --script tests/test_card_hand.gd` checks overlapping hit targets, hover depth, rapid switching, modal blocking, double-selection protection and audio decoding.

`godot --headless --path . --script tests/test_card_audio.gd` checks decoded loudness spread, clipping, short durations, rapid-hover gain, voice isolation, master volume and mute.
