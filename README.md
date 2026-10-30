# A2-Code-Prototype-Project
A 3D first-person stealth puzzle game created in Godot 4.7.

You are trapped inside a two-level maze constructed by your own mind: the upper level represents the **surface mind**, while the lower level represents the **subconscious**.

Move between the two levels, recover every memory shard hidden in the pitch-black subconscious, avoid the presence that continues to search for you, and finally wake up.

# Controls

| Key | Action |
|---|---|
| WASD / Arrow Keys | Move |
| Mouse | Look around |
| Space | Jump |
| F | Switch between the surface mind and subconscious. The transition fades to black, and switching is disabled in certain areas. |
| Q | Listen using sonar. Nearby shards respond with echoes, but the sound attracts “it.” |
| Esc | Release the mouse cursor |

# Gameplay and Mechanics

- Two-level maze: Most of the two levels share the same structure, but some areas differ. Certain paths are only accessible through the subconscious.
- Memory shards: These exist only in the subconscious on the lower level and emit a faint glow in the darkness. Collect every remaining shard to wake up.
- It: It is visible only on the surface level. A red line of sight sweeps from side to side like its eye. If the line detects you, it begins chasing you. You must remain outside the red light for three consecutive seconds to escape. In the pitch-black lower level, you cannot see it and must judge its distance through its low breathing sound.
- Shards can be consumed: When it reaches a shard, it consumes the shard permanently and reduces the total number of available shards. It behaves like a living presence within the maze.
- The cost of listening: Pressing Q is the only way to locate shards, but every use reveals your position and causes it to move towards you.
- Anti-idling system: If you avoid contact with it for too long, it relocates to the valid path cell farthest from you and begins searching again.

# Technical Details

- Engine: Godot 4.7 with Forward+ rendering and Jolt Physics
- Logic: Four GDScript files: `player`, `monster`, `soul`, and `game`. All scripts include instructional comments in Chinese.
- Level: A 15 × 15 two-level maze constructed entirely from scene nodes, with 130 wall assemblies and six restricted switching zones that prevent the player from clipping through mismatched structures.
- Audio: No external audio assets. All WAV files were synthesised using Python, including the sonar ping, shard echoes, and looping breathing sound.

# Running the Project

The Windows executable (`Soul.exe`) is available under **Assets** in [Releases, tag `v1-a2-2026-10-30`](https://github.com/ZY-Zzzzzzzzzzzzzzzzzzzzzz/A2-Code-Prototype-Project/releases/tag/v1-a2-2026-10-30): [download Soul.exe](https://github.com/ZY-Zzzzzzzzzzzzzzzzzzzzzz/A2-Code-Prototype-Project/releases/download/v1-a2-2026-10-30/Soul.exe).

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open the `project.godot` file in this directory using Godot.
3. Press F5 to run the project.
