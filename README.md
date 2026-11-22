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

1. **Your manual choice,** set in the settings window's Players tab, or with
   `/cbb role <name> <role>`. It is saved per player name.
2. **Group role** (Tank / Healer) from the group finder or the leader.
3. **Talents**, read by inspecting each group member out of combat. The tree
   with the most points decides: Elemental → caster, Enhancement → melee,
   Feral → melee (tank if the group role says tank), and so on.
4. **A class guess**, shown with a `?` after the role tag.

Roles are Tank, Healer, Melee DPS, Ranged (physical, hunters) and Caster DPS.
Hunters can also be set to **Melee weaving**, which has its own blessing order.
Auto always picks Ranged for hunters, because talents can't show melee
weaving, so set it in the Players tab.

## Using it

**The bar only casts.** It's a compact column in the style of Pally Power:

- **Class buttons.** Each one shows the class icon and that class's Greater
  Blessing. The colour tells you who needs what:
  - red: someone in the class is missing their blessing
  - green: everyone has theirs
  - yellow: a blessing is running out soon
  - grey: the players who need one are out of range or dead
- **Timers, like Pally Power:** a class button counts down the shortest time
  left on your blessings in that class (for example `56:04`), and each player
  in the flyout shows their own countdown. They turn yellow when it is time to
  refresh, and keep counting in combat.
- **Left-click a class button** to cast its Greater Blessing. A red ✕ over the
  icon means it is blocked because it would replace someone's camp buff.
- **Right-click a class button** to bless the next player of that class who
  needs it, from the top of the list down, like Pally Power.
  - Each player gets **their own** blessing, from their role and camp buffs.
    With an Enhancement and an Elemental Shaman, one right-click gives Might
    to one and the next gives Wisdom to the other.
  - It skips players who already have theirs, are out of range or dead, or
    whose every option would replace a camp buff.
- **Hover a class button** to open a flyout to the right, with one button per
  player:
  - Players are green when buffed and red when missing.
  - Purple means every option would replace a camp buff.
  - Each button shows the blessing it will cast, their role, their camp buffs
    and the time left.
  - **Click a red player** to give them the blessing set up for them, when
    you want a specific player rather than the next one.
- **The gear** next to the bar opens the settings. Drag it to move the bar.
- **Smart button key binding:** Key Bindings → AddOns → *Camelus' Better
  Blessings*. It blesses the next player who needs it, tanks first. It works
  without being on the bar, but the Options tab can show it there.

In combat the bar freezes and player flyouts don't open. Blizzard doesn't allow
addon buttons to change in combat. Everything updates again when combat ends.

**All setup happens in the settings window** (the gear, `/cbb config`, or
Settings → AddOns):

- **Blessings tab:** two columns of classes, one header per class with its
  Greater Blessing.
  - Classes with several roles (Warrior, Paladin, Hunter, Priest, Shaman,
    Druid) list each role underneath. Each role row holds up to three
    blessings in priority order.
  - Single-role classes (Rogue, Mage, Warlock) keep their three blessings on
    the class header.
  - Left-click or scroll a slot to pick the next blessing; right-click to go
    back.
- **Players tab:** laid out like the raid window, with Group 1–8 in a grid of
  up to five players each. A full 40-player raid fits without scrolling; a
  party shows only Group 1.
  - Each player has a role button: `Auto HEAL` when detected, or `TANK` when
    set by you.
  - Click the role button to set it yourself; right-click to go back. Your
    choice is saved per player.
  - Hover a player to see what Auto picked and why (group role or talents),
    and the blessing order they will get.
- **Pally Power tab:** the blessing assignments the other paladins in your
  group made in Pally Power, or a compatible addon such as Lightbound.
  - Shown as a grid of paladins × classes, with your row marked.
  - A `+` means there are single-player assignments; hover the cell to see
    them.
  - This addon only **reads** them. It asks the group for their assignments,
    the same request Pally Power sends, but never sends its own, so other
    paladins don't see you in Pally Power.
  - **Follow my Pally Power assignments** (in Options, on by default): when
    someone assigns you, e.g., Might on Warriors, Might becomes the first
    choice for every warrior, and the Warrior class button's Greater Blessing
    follows it too. A single-player assignment beats the class one. Camp buff
    protection still applies: if the assigned blessing would replace a camp
    buff, your own lists are used.
  - With **Respect other paladins** on, a blessing another paladin is assigned
    to give a player counts as taken, so you pick your next one for them.
  - WoW Forever can hold back addon messages during boss fights; the
    assignments update once that ends.
- **Options tab:** camp buff protection, Greater Blessing blocking, respecting
  other paladins, target warning, tooltips, smart button, bar lock and scale,
  and the refresh warning time.

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
  that player.
- **Camp buffs are tracked as they change.** The addon re-reads a player's
  buffs whenever the game reports a change. Out of combat it also re-reads a
  camp buff the moment its timer runs out. On top of that it checks everyone
  with Camp Benefits every 5 seconds, spread out so a full raid never re-reads
  at once. So when a camp buff runs out, the blocked blessing becomes available
  again. For example, a healer who got Kings because of Mana Well shows "swap"
  and gets Wisdom on the next click.

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
