# Camelus' Better Blessings

A Pally Power-style blessing manager for **World of Warcraft: Forever** that
knows about campfire buffs.

On WoW Forever, some camp buffs are mutually exclusive with paladin blessings.
Casting the blessing replaces the camp buff:

| Camp object (profession) | Camp buff effect   | Replaced by        |
|--------------------------|--------------------|--------------------|
| Fish Bowl (Fishing)      | +8% all stats      | Blessing of Kings  |
| Lodestone (Mining)       | Melee attack power | Blessing of Might  |
| Mana Well (Alchemy)      | Mana every 5 sec   | Blessing of Wisdom |

If a player already has a camp buff, giving them the matching blessing wastes a
buff slot. Give them their next-best blessing instead and they keep both.
This addon handles that for you.

## What it does

- **Assign blessings by class *and* role.** Each class/role pair has its own
  row: Warrior Tank, Warrior Melee, Shaman Healer, Shaman Melee, Shaman Caster,
  Druid Tank, and so on. An Enhancement Shaman gets Might and an Elemental
  Shaman gets Wisdom.
- **Priority lists instead of a single blessing.** WoW Forever paladins have
  three blessings: Might, Wisdom and Kings. Salvation, Light and Sanctuary
  were removed. Each row lists up to three of them in order. Choice 1 is what
  that player normally gets. If it would overwrite a
  camp buff, isn't learned, or another paladin already gave it, the addon uses
  the next choice.
- **Shows camp buffs on every player.** The bar shows their icons, and the row
  tooltip lists each camp buff, what it blocks, and how long it has left.
- **Blocks the cast.** Every row is a click-to-cast button. If the only options
  would overwrite a camp buff, the row has no spell attached, so clicking it
  does nothing.
- **Greater Blessings per class.** These are class-wide, so roles can't apply.
  The class button is blocked if *any* member of the class has a camp buff it
  would replace. You can turn that off in the options. The tooltip also lists
  whose single blessing it would replace.
- **Smart button.** One button (bindable to a key) blesses the next player who
  needs it: tanks first, then healers, then everyone else.
- **Target warning.** This also covers casts from your normal action bars. When
  you target a player with a camp buff, the bar shows which blessings to avoid.
  Player tooltips get the same line.

## How roles are detected

The first source that gives an answer wins:

1. **Your manual choice.** Right-click a player row to cycle the role, or use
   `/cbb role <name> <role>`. It is saved per player name.
2. **Group role** (Tank / Healer) from the group finder or the leader.
3. **Talents**, read by inspecting each group member out of combat. The tree
   with the most points decides: Elemental → caster, Enhancement → melee,
   Feral → melee (tank if the group role says tank), and so on.
4. **A class guess**, shown with a `?` after the role tag.

Roles are Tank, Healer, Melee DPS, Ranged (physical, hunters) and Caster DPS.

## Using it

- **Bar:** each class has a header row (its Greater Blessing) and one row per
  player under it.
  - Row colours: green = has it, yellow = refresh soon, red = missing,
    orange = would swap your other blessing, purple = blocked by camp buffs,
    grey = out of range / dead / offline.
  - **Left-click** a player row to cast its blessing.
  - **Right-click** a player row to change their role.
  - **Left-click** a class row to cast its Greater Blessing. **Right-click** it
    (or Shift-right-click) to change which Greater Blessing it casts.
  - The `+` / `-` button folds a class open or closed.
- **Assignment grid:** open it with the cog on the bar or `/cbb config`.
  - Left-click or scroll a slot to pick the next blessing; right-click to go back.
  - The options checkboxes are at the bottom.
- **Key binding:** Key Bindings → AddOns → *Camelus' Better Blessings*.

### Commands

```
/cbb                       show / hide the bar
/cbb config                assignment grid + options
/cbb lock                  lock / unlock the bar
/cbb role <player> <auto|tank|healer|melee|ranged|caster>
/cbb roles                 list everyone's detected role and why
/cbb auras [unit]          list buffs + spell IDs on your target
/cbb camp list             camp buffs the addon knows about
/cbb camp add <spellId|aura name> <might|wisdom|kings>
/cbb camp del <n>          remove a camp buff you added
/cbb refresh <minutes>     "refresh soon" threshold (default 5)
/cbb scale <0.5-2>         bar scale
/cbb reset                 reset assignments to defaults
```

If Blizzard renames a camp buff or adds a new one, run `/cbb auras` on a player
who has it. That shows every buff with its spell ID, plus the lines of the
*Camp Benefits* tooltip and which of them the addon recognised. Then add the
missing one by the name its line starts with, for example
`/cbb camp add "Mana Well" wisdom`.

## Limits

These come from the WoW client and can't be worked around:

- **Combat lockdown.** Blizzard does not let addons change click-to-cast
  buttons in combat, and WoW Forever hides aura data from addons in combat. The
  bar freezes when combat starts, keeping what it knew before the pull, and
  updates when combat ends. Blessings go out between pulls anyway.
- **Action bars can't be blocked.** No addon can stop a spell cast from the
  default action bars. Only this addon's buttons and smart button block. The
  target warning covers the rest.
- **Greater Blessings are class-wide.** That is a spell limitation, so role
  logic only applies to single blessings.
- **How camp buffs are detected.** WoW Forever shows no separate aura per
  camp buff. A player at a campfire gets one aura, *Camp Benefits*, and its
  tooltip has a line per active feature, such as `Fish Bowl: ...`. The real
  stat aura is hidden from addons, so the addon reads that tooltip. If the
  tooltip can't be read, it treats Kings, Might and Wisdom as blocked for
  that player. Lodestone and Mana Well are matched by their English names,
  so `/cbb auras` and `/cbb camp add` let you fix them in game if needed.

## Installing with WoWUp

1. In WoWUp, select your **WoW Forever** installation.
2. Click **Install from URL**.
3. Paste this repository's GitHub URL.

WoWUp checks this repository's releases for the zip that matches WoW Forever.

## Releasing (for maintainers)

Releases are automatic. You never create tags or releases by hand.

1. Bump `## Version:` in `CamelusBetterBlessings.toc` (for example `1.0.0` → `1.1.0`).
2. Merge that change into `main`.

`.github/workflows/release.yml` runs on every push to `main`. If the `.toc`
version has not been released yet, it does the following:

1. Runs the syntax checks and the test suite.
2. Builds `CamelusBetterBlessings-v<version>-forever.zip`, with the addon
   folder inside.
3. Builds a BigWigs-style `release.json` with flavor `forever` and the
   interface number from the `.toc`.
4. Publishes a GitHub release tagged `v<version>` with both files.

If the version was already released, the workflow does nothing. Merges that
don't change the version publish no release.

WoWUp finds WoW Forever builds by a `-forever.zip` / `-camelot.zip` file name
suffix, or by a `forever` entry in `release.json`. Both are provided. It only
looks at the 5 most recent releases. A version with a suffix (for example
`1.1.0-beta.1`) is published as a pre-release, so only WoWUp users on the
Beta/Alpha channel see it.

When Blizzard patches WoW Forever, update `## Interface:` in
`CamelusBetterBlessings.toc`. In game, `/dump select(4, GetBuildInfo())` shows
the current value.

## Development

```bash
lua5.1 tests/run.lua
```

This runs the decision logic tests and an integration test. The integration
test loads the whole addon against a mock WoW API in `tests/mock_wow.lua`.
