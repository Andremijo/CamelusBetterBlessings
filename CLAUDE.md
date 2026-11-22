# CLAUDE.md — Camelus' Better Blessings

A Pally Power-style paladin blessing addon for **World of Warcraft: Forever**,
Blizzard's classic-based 2026 branch, built for one player (the repo owner). Its
job: assign blessings by **class and role**, show **camp buffs** on every player,
and **never cast a blessing that would replace a camp buff**.

The owner tests everything in game and reports back with screenshots, often in
Swedish. Reply in the language they write in.

## Workflow (how this repo is run)

- **Branch:** work on the branch the session names (it has been
  `claude/admiring-mccarthy-aymdfe`), restarted from `origin/main` for each
  change.
- **Pull requests:** one PR per change into `main`.
  - Merge only when the owner says so ("merge it", or "merga när allt är klart").
  - Merges are **squash**.
- **Releases are automatic.** Bump `## Version:` in `CamelusBetterBlessings.toc`
  in the PR, and merging publishes the release.
  - Never create tags by hand. The session can't push tags anyway; the proxy
    returns 403.
  - `.github/workflows/release.yml` runs on every push to `main`. If the `.toc`
    version has no release yet, it runs the tests, builds the files, tags
    `v<version>` and publishes the release.
  - Same version as an existing release: nothing happens.
  - A version with a suffix (`1.2.0-beta.1`) becomes a pre-release.
  - After merging, confirm the release exists (`get_release_by_tag`) and tell
    the owner.
- **WoWUp naming** is required. Users install with WoWUp's *Install from URL*.
  `.github/scripts/package.sh` builds:
  - `CamelusBetterBlessings-v<version>-forever.zip`: WoWUp matches
    `[-_](forever|camelot)\.zip$`. The zip contains the `CamelusBetterBlessings/`
    folder.
  - `release.json`, in BigWigs packager format with `"flavor": "forever"`.
  - WoWUp only looks at the 5 newest non-draft releases.
  - Unauthenticated, WoWUp gets 60 GitHub requests per hour. A slow
    "update not found" is usually that limit or WoWUp's check interval, not the
    release.
- **Before pushing:**
  - Run `for f in *.lua tests/*.lua; do luac5.1 -p $f; done && lua5.1 tests/run.lua`.
  - CI (`.github/workflows/ci.yml`) runs the same checks, plus a test package.
  - Install Lua with `apt-get install -y lua5.1` if it's missing.
- **Commit and history:**
  - Force-pushing is blocked in this environment.
  - After a squash-merge, restart the branch from `origin/main`, then
    `git merge -s ours` the old remote branch tip before pushing.

## WoW Forever facts (verified the hard way — don't "fix" these back)

- **Client:** `## Interface: 16001`. The UI and API are mainline-style (12.x):
  `C_UnitAuras`, `C_Spell`, `C_TooltipInfo`, `BackdropTemplate`, secure
  templates, and secret values (`issecretvalue`).
- **Blessings:** only **Might, Wisdom, Kings**, single and Greater.
  - Kings is baseline from level 20.
  - Salvation, Light and Sanctuary were removed from the game.
  - Blessings last 1 hour.
  - Each paladin can only have one blessing per target. A new one replaces it.
- **Camp buffs** are *not* separate auras. A campfire gives one visible aura,
  **Camp Benefits** (spell `1229741`). Its tooltip has a line per active
  feature, like `Fish Bowl: ...`.
  - The real stat aura (Boosted Stats, `1230098`) is hidden from addons.
  - The addon reads the tooltip with `C_TooltipInfo.GetUnitBuffByAuraInstanceID`.
  - If the tooltip can't be read, Kings, Might and Wisdom are all treated as
    blocked (fail-safe).
  - The camp buffs, and the blessing each one is replaced by:

    | Camp buff | Item | Spell | Replaced by |
    |---|---|---|---|
    | Fish Bowl | 279967 | 1307245 | Kings |
    | Lodestone | 279960 | 1307254 | Might |
    | Mana Well | 279956 | 1307259 | Wisdom |

  - Icons come from the **item** (`C_Item.GetItemIconByID`), falling back to
    the spell icon.
- **Combat:**
  - Group members' buffs **can** be read in combat. An in-game test with Pally
    Power proved it.
  - Secure buttons **cannot** change in combat, for any addon. Colours, timers
    and statuses update live; what a button casts and the layout catch up
    after combat.
  - Never use `Show`, `Hide`, `SetPoint`, `SetWidth` or `SetAttribute` on
    secure frames while `InCombatLockdown()`. Text and texture changes are fine.
- **Roles:**
  - The detection order is in `Logic.ResolveRole`: manual, then group role
    (Tank/Healer), then talent tabs from inspect, then class guess.
  - The spec API is only a fallback.
  - Hunters can be *Ranged* or *Melee weaving*, the MELEE role with a
    hunter-only name. Auto always picks Ranged for hunters.

## Pally Power integration (read-only)

`PallyPower.lua` listens to the `PLPWR` addon prefix.
- **Numbering**, the same as Lightbound's Forever implementation:
  - blessings: 1 Wisdom, 2 Might, 3 Kings
  - classes: 1 Warrior, 2 Rogue, 3 Priest, 4 Druid, 5 Paladin, 6 Hunter,
    7 Mage, 8 Warlock, 9 Shaman
- **Messages parsed:** `SELF`, `ASSIGN`, `PASSIGN`, `MASSIGN`, `NASSIGN`,
  `CLEAR`, `FREEASSIGN`.
- **Permission rules:** a message may change the sender's own row, or any row
  if the sender is a leader or assistant, or a row whose paladin allows free
  assignment. Messages from outside the group are ignored.
- **Sends only `REQ`**, never assignments. It skips this while Pally Power
  itself is loaded, and resends once after combat if the first went out in
  combat.
- **"Follow my Pally Power assignments"** (default on): my assignment becomes
  the first choice. Camp buff protection still wins.
- **Other paladins:** their assignments count as "taken" when
  `respectOthers` is on.

## Code map

| File | What lives there |
|---|---|
| `Data.lua` | Static data: blessings, camp buffs (`CAMP_CONTAINER`, `CAMP_BUFFS`), roles, class → role tables, default priorities, default options |
| `Logic.lua` | **Pure functions** (no WoW API): `ResolveRole`, `ChooseBlessing`, camp-buff matching, cycling, formatting. Put new decision logic here so it's testable |
| `Core.lua` | Saved variables, spell detection, aura scanning, roster/roles/inspect, `EvaluateUnit`, events, the 1 s ticker, camp re-checks, `/cbb` commands |
| `PallyPower.lua` | PLPWR protocol reader (see above) |
| `UI.lua` | The casting bar: gear handle, class buttons, hover flyouts, timers, tooltips. Secure buttons only |
| `Config.lua` | Settings window, with tabs Blessings / Players / Pally Power / Options, plus the Settings → AddOns entry |
| `tests/mock_wow.lua`, `tests/run.lua` | Mock WoW API and the test suite (unit and integration) |

**Saved variables:**
- `CamelusBetterBlessingsCharDB` (per character): assignments, Greater
  Blessings, role overrides, options, Pally Power data, bar position.
- `CamelusBetterBlessingsDB` (account-wide): custom camp buffs.

## UI decisions the owner made (keep them)

- **Compact, Pally Power style, no header.**
  - A gear (left-click: settings; right-click: Players tab; drag: move), then a
    column of class buttons.
  - Each class button shows the class icon, the Greater Blessing icon, one icon
    per distinct camp buff in the class, and a countdown timer.
- **Rows are packed tight,** with about a 3 px visible gap. All class buttons
  always share one width.
- **Colours:** red = someone missing, green = all buffed, yellow = expiring,
  grey = out of range or dead, purple = blocked by camp buffs.
- **Class button clicks:** left-click casts the Greater Blessing. Right-click
  blesses the **next player in that class** who needs it, top-down, with
  **that player's own** blessing.
- **Hover** opens a player flyout, to the right by default or left via the
  `flyoutLeft` option. Clicking a player blesses them.
- **No setting changes on the bar.** All configuration lives in the settings
  window.
- **Settings window:**
  - It is nearly opaque.
  - Blessings tab: two columns, a class header with a Greater slot, indented
    role rows, and single-role classes with slots on the header.
  - Players tab: laid out like the raid window, Group 1–8.

## Testing notes

- The mock returns no-op functions only for **CamelCase** keys. Lowercase keys
  are addon fields and read as `nil`, like real WoW frames.
- Tests share one scenario and run in order. A test that changes the shared
  state (`M.units.*.auras`, `ns2.db.assign`, `M.combat`) must restore it.
- When fixing a bug, prove the new test fails on the old code: swap the old
  file in with `git show HEAD:file` and run the tests.

## Not yet verified in game

- The exact Camp Benefits tooltip text for **Lodestone** and **Mana Well**.
  Fish Bowl matched, and the others are matched by name.
- The **Pally Power integration** against a real Pally Power user.
- Whether addon messages actually get through in combat (hence the resend).
