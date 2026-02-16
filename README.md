# SENTINEL AI - Typical Colors 2 Neuroevolutionary Agent

**Educational project.** Building an autonomous AI to learn and play Typical Colors 2 via neuroevolution and supervised learning on recorded gameplay.

## Quick Start

### Recording Gameplay

1. Load `GameplayRecorder.lua` into the game.
2. Click **Start** to record.
3. Play normally. Click **Stop & Save** to save to `gameplay_<timestamp>.json`.

### Agent Training (In-Game)

1. Load `AUI.lua` as a LocalScript.
2. Agent evolves via neuroevolution automatically.
3. Click **INTERPRET ALL RECORDINGS** button to load recorded data.

### Offline Training (Python)

```bash
python trainer.py --mode train --generations 200 --pop-size 20 --output-brain trained_brain.json
```

Then copy the output JSON to the game directory. Agent loads it on startup.

---

## Full Documentation

### Architecture

- **Perception** (`Perception.GetInputs`): 54-dimensional sensor vector (health, rays, enemy, class/weapon, boredom).
- **Policy** (Neural network): 54 → 60 → 45 → 30 → 12 (tanh activation).
- **Action execution** (`Agent.Execute`): Neural outputs → key presses (W/A/S/D, jump, crouch, shoot).
- **Fitness** (`Agent.UpdateFitness`): Rewards survival, kills, damage, movement, aiming; penalizes inactivity and reckless deaths.

### Respawn & Teleport Handling

- Game teleports dead players to Y = -7700.
- Agent now detects server teleports (Y < -1000) and waits for position stabilization.
- Repositions to spawn zone only after Y is stable (~0.5s).
- Clamps velocity during 1.5s respawn buffer.

### Gameplay Recording Format

Each `gameplay_<timestamp>.json` frame contains:
```json
{
  "position": {"x": ..., "y": ..., "z": ...},
  "velocity": {...},
  "health": ...,
  "walkSpeed": ...,
  "rays": [/* 9 raycast distances */],
  "team": "Red" /* or "Green" */,
  "class": "Scout",
  "weapon": "Pistol",
  "kills": ...,
  "damage": ...,
  "dead": false,
  "keys": ["W", "D", "Mouse1", ...]
}
```

### Training Pipeline

```bash
# Load all gameplay_*.json files and train
python trainer.py --mode train --generations 200 --pop-size 20 --output-brain trained.json

# Continue training existing brain
python trainer.py --mode load --input-brain sentinel_v5_7_tc2.json --generations 100 --output-brain v2.json

# Evaluate brain on dataset
python trainer.py --mode eval --input-brain trained.json

# Convert formats
python brain_converter.py --json-to-lua trained.json --output trained.lua
python brain_converter.py --lua-to-json trained.lua --output trained.json
```

### Configuration

**`AUI.lua` Config:**
- `Topology`: {54, 60, 45, 30, 12}
- `MutationRate`: 0.2 (20%)
- `MutationStrength`: 0.6
- `VisionRange`: 300
- `BoredomThreshold`: 25

**`GameplayRecorder.lua`:**
- `SampleInterval`: 0.1 (10 Hz)
- `MaxFrames`: 20000

### Fitness Rewards

**Dense (per frame):**
- Alive: +0.02
- Outside spawn: +5.0
- Near door: +2.0
- Move: +0.5× distance
- Good aim: +0.5 (AimConf > 0.7)

**Sparse (events):**
- Kill: +50
- Damage: +0.5× damage
- Took damage: -3

**Penalties:**
- No target: -0.05
- Boredom: -20, forced respawn
- Died away from spawn: -350

### Troubleshooting

| Issue | Fix |
|-------|-----|
| "Dead: TRUE" after respawn | Check `RespawnBuf` in debug. Wait for Y stabilization. |
| Pos shows Y < -7000 | Agent now waits for Y to stabilize before repositioning. |
| No recordings loaded | Verify `GameplayRecorder.lua` ran and saved files. |
| Training low fitness | Record more diverse gameplay; tune reward weights. |

### Performance Tips

- Recording: 0.1s (10 Hz) good default.
- Training: 5-20 pop size, 100-300 generations.
- In-game: Disable UI updates if FPS drops.
- Dataset: 50K+ frames for robust learning.

### Future Enhancements

1. Supervised learning from recorded actions.
2. Distributed training (multiple agents).
3. Curriculum learning (simple → complex tasks).
4. Transfer learning across map variants.
5. Multi-objective optimization (K/D + objectives).

---

**Educational Project** — Typical Colors 2 (Roblox)