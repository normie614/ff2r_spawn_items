# FF2R Spawn Items

Custom FF2R boss ability that spawns configurable pickup items (sprites or 3D models) around the map or on enemy kills, with per-item pickup permissions and slot-ability triggers.

## Features

- Two item types per config entry:
  - **Sprite pickup** — floating sprite (`vtm`) attached to a small physics prop.
  - **3D model pickup** — spawns as a real model (`model`) instead of a sprite.
- Items respawn on a timer at random map-defined spawn points.
- Optional chance to drop an item at a victim's position on kill.
- Per-item pickup sound and spawn sound.
- Per-item pickup permissions via `grab_flags`.
- Boss-slot ability trigger on pickup (`do slot after low` / `do slot after high`).

## Config

Add a `special_spawn_items` and `glow_items` ability block to your boss config:

```
"special_spawn_items"
{
	"item_respawn_period"			"20.0"	// Time between spawns.
	"item_on_kill_spawn_chance"		"30.0"	// % chance to drop an item at a victim's position on kill.
    "max_items"                     "2"     // Max items alive at once (ignored for on-kill drops).

	"item1" // This gets added to the ItemsToSpawn arraylist.
	{
		"vtm"					"freak_fortress_2/doom/item_berserk.vmt" // Sprite material (no "materials/" prefix). Leave empty if using model.
        "model"					""                                      // Leave empty if using "vtm". Set a .mdl path to spawn a 3D model instead.
		"pickup_sound"			"freak_fortress_2/doom/item_pickup.wav" // Self explanatory, required.
        "spawn_sound"			"freak_fortress_2/doom/item_pickup.wav" // No sound is played if not defined.
		"grab_flags"			""   // Missing or 1 = Boss | 2 = Minions | 4 = Enemy | add values together (3 = Boss + Minions).
		"do slot after low"		"5" // Example: Create a 'rage_new_weapon' somewhere with the slot "5", it will use it on touch.
		"do slot after high"	"" // Optional slot range end. Empty = same as low.
	}
	"item2"
	{
		"vtm"					""
        "model"					"models/weapons/c_models/c_scattergun.mdl"
		"pickup_sound"			"freak_fortress_2/doom/item_weaponpickup.wav"
        "spawn_sound"			"freak_fortress_2/doom/item_pickup.wav"
		"grab_flags"            ""
		"do slot after low"		""
		"do slot after high"	""
	}
        "plugin_name" "ff2r_spawn_items"
}

"glow_items" // Makes the items glow (except the ones dropped by killing).
{
	"slot" "0"

	"plugin_name"	"ff2r_spawn_items"
}
```

Only set one of `vtm` / `model` per item — whichever is filled in determines the spawn type.

### grab_flags

Controls who is allowed to pick up the item. Add the numbers together for every group you want to allow:

| Value | Meaning |
|-------|---------|
| 1     | Boss |
| 2     | Minions |
| 4     | Enemy players |

Examples:
- `1` → Boss only (default if left empty)
- `3` → Boss + Minions (1 + 2)
- `6` → Minions + Enemies, not the Boss (2 + 4)
- `7` → Everyone (1 + 2 + 4)

## Notes

- Sprite (`vtm`) paths must **not** include the `materials/` prefix — it's implied.
- Model (`model`) paths use the normal full `models/...` path.
- Items still on the ground are cleaned up automatically when the boss is removed.

## FAQ

- **"Could you optimize this?"** Maybe, but I won't.
- **"Could you make the code cleaner?"** It's SourcePawn and it was built in two hours on two coffees. Manage your expectations.
- **"Does this have bugs?"** It has *features* I haven't discovered yet.