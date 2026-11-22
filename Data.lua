-- Camelus' Better Blessings - static data
-- Everything in here is plain data so it can be tuned without touching logic.
local _, ns = ...

ns.MAX_PRIORITY = 3

---------------------------------------------------------------------------
-- Blessings
-- WoW Forever has three: Might, Wisdom and Kings (Kings is baseline from
-- level 20). Salvation, Light and Sanctuary were removed from the game.
-- spellId / greaterId are the classic rank 1 IDs. They are only used to look
-- up the localized name, the icon and "do I know this spell". English names
-- are the fallback if an ID does not exist on the WoW Forever client.
---------------------------------------------------------------------------
ns.BLESSING_ORDER = { "MIGHT", "WISDOM", "KINGS" }

ns.BLESSINGS = {
    MIGHT = {
        short = "Might",
        name = "Blessing of Might",          greaterName = "Greater Blessing of Might",
        spellId = 19740,                     greaterId = 25782,
        icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
        greaterIcon = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",
    },
    WISDOM = {
        short = "Wisdom",
        name = "Blessing of Wisdom",         greaterName = "Greater Blessing of Wisdom",
        spellId = 19742,                     greaterId = 25894,
        icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
        greaterIcon = "Interface\\Icons\\Spell_Holy_GreaterBlessingofWisdom",
    },
    KINGS = {
        short = "Kings",
        name = "Blessing of Kings",          greaterName = "Greater Blessing of Kings",
        spellId = 20217,                     greaterId = 25898,
        icon = "Interface\\Icons\\Spell_Magic_MageArmor",
        greaterIcon = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings",
    },
}

---------------------------------------------------------------------------
-- WoW Forever camp buffs that are mutually exclusive with a paladin blessing.
--
-- How they show up on the client: a player near a campfire gets ONE visible
-- aura, "Camp Benefits" (CAMP_CONTAINER below), whose tooltip has a line per
-- active camp feature, e.g. "Fish Bowl: ...". The real stat aura (Boosted
-- Stats) is hidden from addons, so the addon reads the Camp Benefits tooltip.
--
--   item      : the camp object's item ID - its icon is what the addon shows
--   feature   : spell ID the item casts; its (localized) name is what the
--               Camp Benefits tooltip line starts with (icon fallback too)
--   match     : lower-case names matched against tooltip lines and aura names
--   spellIds  : aura spell IDs, in case a feature ever shows as its own aura
--   conflicts : blessing keys that would REPLACE this camp buff
-- More can be added in game with /cbb camp add (stored in SavedVariables).
-- /cbb auras lists every buff and the Camp Benefits tooltip lines.
---------------------------------------------------------------------------
ns.CAMP_CONTAINER = {
    name = "Camp Benefits",
    spellIds = { 1229741 },
    match = { "camp benefits" },
}

ns.CAMP_BUFFS = {
    {
        key = "FISH_BOWL", name = "Fish Bowl", profession = "Fishing", effect = "+8% all stats (Boosted Stats)",
        item = 279967, feature = 1307245, match = { "fish bowl", "boosted stats" }, spellIds = { 1230098 },
        conflicts = { "KINGS" },
    },
    {
        key = "LODESTONE", name = "Lodestone", profession = "Mining", effect = "Melee attack power",
        item = 279960, feature = 1307254, match = { "lodestone" }, spellIds = {},
        conflicts = { "MIGHT" },
    },
    {
        key = "MANA_WELL", name = "Mana Well", profession = "Alchemy", effect = "Mana every 5 sec",
        item = 279956, feature = 1307259, match = { "mana well" }, spellIds = {},
        conflicts = { "WISDOM" },
    },
}

---------------------------------------------------------------------------
-- Roles
---------------------------------------------------------------------------
ns.ROLE_ORDER = { "TANK", "HEALER", "MELEE", "RANGED", "CASTER" }

ns.ROLE_INFO = {
    TANK   = { label = "Tank",              short = "TANK", color = { 0.45, 0.65, 1.00 } },
    HEALER = { label = "Healer",            short = "HEAL", color = { 0.35, 1.00, 0.35 } },
    MELEE  = { label = "Melee DPS",         short = "MDPS", color = { 1.00, 0.45, 0.35 } },
    RANGED = { label = "Ranged (physical)", short = "RDPS", color = { 1.00, 0.75, 0.25 } },
    CASTER = { label = "Caster DPS",        short = "CDPS", color = { 0.75, 0.55, 1.00 } },
}

ns.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Roles each class can actually fill. The assignment grid shows one row per pair.
ns.CLASS_ROLES = {
    WARRIOR = { "TANK", "MELEE" },
    PALADIN = { "TANK", "HEALER", "MELEE" },
    HUNTER  = { "RANGED", "MELEE" },   -- MELEE = melee weaving
    ROGUE   = { "MELEE" },
    PRIEST  = { "HEALER", "CASTER" },
    SHAMAN  = { "HEALER", "MELEE", "CASTER" },
    MAGE    = { "CASTER" },
    WARLOCK = { "CASTER" },
    DRUID   = { "TANK", "HEALER", "MELEE", "CASTER" },
}

-- Class-specific names for a role (shown in the settings and on the bar).
ns.ROLE_LABEL_OVERRIDE = {
    ["HUNTER:MELEE"] = { label = "Melee weaving", short = "WEAV" },
}

-- Used when nothing else is known about a player.
ns.CLASS_DEFAULT_ROLE = {
    WARRIOR = "MELEE", PALADIN = "HEALER", HUNTER = "RANGED", ROGUE = "MELEE", PRIEST = "HEALER",
    SHAMAN = "MELEE", MAGE = "CASTER", WARLOCK = "CASTER", DRUID = "MELEE",
}

-- Used when the group says "damage dealer" but talents are unknown.
ns.CLASS_DEFAULT_DPS = {
    WARRIOR = "MELEE", PALADIN = "MELEE", HUNTER = "RANGED", ROGUE = "MELEE", PRIEST = "CASTER",
    SHAMAN = "MELEE", MAGE = "CASTER", WARLOCK = "CASTER", DRUID = "MELEE",
}

-- Talent tree (tab index 1/2/3) -> role. Feral druids come out as MELEE and
-- turn into TANK when the group role says TANK (or with a manual override).
ns.TALENT_TAB_ROLES = {
    WARRIOR = { "MELEE", "MELEE", "TANK" },       -- Arms, Fury, Protection
    PALADIN = { "HEALER", "TANK", "MELEE" },      -- Holy, Protection, Retribution
    HUNTER  = { "RANGED", "RANGED", "RANGED" },
    ROGUE   = { "MELEE", "MELEE", "MELEE" },
    PRIEST  = { "HEALER", "HEALER", "CASTER" },   -- Discipline, Holy, Shadow
    SHAMAN  = { "CASTER", "MELEE", "HEALER" },    -- Elemental, Enhancement, Restoration
    MAGE    = { "CASTER", "CASTER", "CASTER" },
    WARLOCK = { "CASTER", "CASTER", "CASTER" },
    DRUID   = { "CASTER", "MELEE", "HEALER" },    -- Balance, Feral, Restoration
}

-- Used if the client exposes a specialization API instead of talent tabs.
ns.SPEC_NAME_ROLES = {
    Arms = "MELEE", Fury = "MELEE", Protection = "TANK", Holy = "HEALER", Retribution = "MELEE",
    Discipline = "HEALER", Shadow = "CASTER", Elemental = "CASTER", Enhancement = "MELEE",
    Restoration = "HEALER", Balance = "CASTER", Feral = "MELEE", Guardian = "TANK",
    ["Feral Combat"] = "MELEE", ["Beast Mastery"] = "RANGED", Marksmanship = "RANGED",
    Survival = "RANGED", Assassination = "MELEE", Combat = "MELEE", Subtlety = "MELEE",
    Outlaw = "MELEE", Arcane = "CASTER", Fire = "CASTER", Frost = "CASTER",
    Affliction = "CASTER", Demonology = "CASTER", Destruction = "CASTER",
}

---------------------------------------------------------------------------
-- Default priorities. Slot 1 is what you normally give; the next slots are
-- used when slot 1 would overwrite a camp buff (or another paladin already
-- gave it). Class+role entries win over the plain role entries.
---------------------------------------------------------------------------
ns.DEFAULT_ROLE_PRIORITY = {
    TANK   = { "KINGS", "MIGHT", false },
    HEALER = { "WISDOM", "KINGS", false },
    MELEE  = { "MIGHT", "KINGS", false },
    RANGED = { "KINGS", "WISDOM", "MIGHT" },
    CASTER = { "WISDOM", "KINGS", false },
}

-- Classes whose melee/tank spec also uses mana get Wisdom as the last resort.
ns.DEFAULT_CLASS_ROLE_PRIORITY = {
    ["PALADIN:TANK"]  = { "KINGS", "WISDOM", "MIGHT" },
    ["PALADIN:MELEE"] = { "MIGHT", "KINGS", "WISDOM" },
    ["SHAMAN:MELEE"]  = { "MIGHT", "KINGS", "WISDOM" },
    ["DRUID:MELEE"]   = { "MIGHT", "KINGS", "WISDOM" },
    ["HUNTER:MELEE"]  = { "KINGS", "MIGHT", "WISDOM" },  -- melee weaving
}

-- Default Greater Blessing per class (class-wide, so no role split possible).
ns.DEFAULT_GREATER = {
    WARRIOR = "MIGHT", PALADIN = "WISDOM", HUNTER = "KINGS", ROGUE = "MIGHT", PRIEST = "WISDOM",
    SHAMAN = "WISDOM", MAGE = "WISDOM", WARLOCK = "WISDOM", DRUID = "WISDOM",
}

ns.DEFAULT_OPTIONS = {
    protectCamp    = true,  -- never pick a blessing that would replace a camp buff
    protectGreater = true,  -- block a Greater Blessing if any member of the class would lose a camp buff
    respectOthers  = true,  -- skip blessings another paladin already put on the player
    refreshMinutes = 5,     -- show "refresh" when my blessing has less than this left
    showSolo       = true,  -- show the bar when not in a group
    locked         = false,
    hidden         = false,
    showSmart      = false, -- show the smart button on the bar (its key binding always works)
    warnTarget     = true,  -- warn about camp buffs on your current target
    tooltip        = true,  -- add camp buff info to unit tooltips
    scale          = 1,
}
