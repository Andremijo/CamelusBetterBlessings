-- Run from the repository root:  lua5.1 tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error(string.format("%s: expected %s, got %s", msg or "value", tostring(b), tostring(a)), 2) end
end

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
local ns = {}
M.load(".", { "Data.lua", "Logic.lua" }, ns)
local L = ns.Logic

test("role: manual wins", function()
    eq(L.ResolveRole("SHAMAN", "CASTER", "HEALER", "MELEE"), "CASTER")
end)
test("role: invalid manual ignored", function()
    eq(L.ResolveRole("ROGUE", "TANK", "NONE", nil), "MELEE")
end)
test("role: group tank/healer wins over talents", function()
    eq(L.ResolveRole("DRUID", nil, "TANK", "MELEE"), "TANK")
    eq(L.ResolveRole("SHAMAN", nil, "HEALER", "CASTER"), "HEALER")
end)
test("role: talents split dps", function()
    local r, src = L.ResolveRole("SHAMAN", nil, "DAMAGER", "CASTER")
    eq(r, "CASTER") eq(src, "talents")
    eq(L.ResolveRole("SHAMAN", nil, "DAMAGER", "MELEE"), "MELEE")
end)
test("role: group dps beats healer talents", function()
    local r, src = L.ResolveRole("PRIEST", nil, "DAMAGER", "HEALER")
    eq(r, "CASTER") eq(src, "group+class")
end)
test("role: class fallback", function()
    local r, src = L.ResolveRole("MAGE", nil, nil, nil)
    eq(r, "CASTER") eq(src, "class")
end)

test("choose: primary when free", function()
    local c = L.ChooseBlessing({ "MIGHT", "KINGS" }, { threshold = 300 })
    eq(c.blessing, "MIGHT") eq(c.status, "MISSING")
end)
test("choose: camp buff skips to fallback", function()
    local c = L.ChooseBlessing({ "MIGHT", "KINGS" }, { conflicts = { MIGHT = "Lodestone" } })
    eq(c.blessing, "KINGS") eq(c.skipped[1].reason, "camp")
end)
test("choose: camp protection can be disabled", function()
    local c = L.ChooseBlessing({ "MIGHT", "KINGS" }, { conflicts = { MIGHT = "Lodestone" }, protect = false })
    eq(c.blessing, "MIGHT")
end)
test("choose: everything blocked", function()
    local c = L.ChooseBlessing({ "KINGS", false, false, false }, { conflicts = { KINGS = "Fish Bowl" } })
    eq(c.blessing, nil) eq(c.status, "BLOCKED")
end)
test("choose: unknown skipped", function()
    local c = L.ChooseBlessing({ "KINGS", "MIGHT" }, { known = { MIGHT = true } })
    eq(c.blessing, "MIGHT")
end)
test("choose: other paladin's blessing respected", function()
    local c = L.ChooseBlessing({ "KINGS", "MIGHT" }, { taken = { KINGS = "Otherpally" } })
    eq(c.blessing, "MIGHT")
    c = L.ChooseBlessing({ "KINGS", "MIGHT" }, { taken = { KINGS = "Otherpally" }, respectOthers = false })
    eq(c.blessing, "KINGS")
end)
test("choose: my blessing ok / refresh / swap", function()
    eq(L.ChooseBlessing({ "MIGHT" }, { mine = { type = "MIGHT", remaining = 3000 }, threshold = 300 }).status, "OK")
    eq(L.ChooseBlessing({ "MIGHT" }, { mine = { type = "MIGHT", remaining = 100 }, threshold = 300 }).status, "REFRESH")
    eq(L.ChooseBlessing({ "MIGHT" }, { mine = { type = "KINGS", remaining = 3000 }, threshold = 300 }).status, "SWAP")
end)
test("camp match by id and name", function()
    local list = ns.CAMP_BUFFS
    eq(L.MatchCampBuff("whatever", 1307245, list).key, "FISH_BOWL")
    eq(L.MatchCampBuff("Lodestone", nil, list).key, "LODESTONE")
    eq(L.MatchCampBuff("Camp: Mana Well", nil, list).key, "MANA_WELL")
    eq(L.MatchCampBuff("Blessing of Kings", nil, list), nil)
end)
test("greater conflicts", function()
    local r = L.GreaterConflicts("WISDOM", { { name = "A", conflicts = { WISDOM = "Mana Well" } }, { name = "B", conflicts = {} } })
    eq(#r, 1) eq(r[1].name, "A")
end)
test("cycle helpers", function()
    eq(L.CycleBlessing(false, 1), "MIGHT")
    eq(L.CycleBlessing("MIGHT", -1), false)
    eq(L.CycleBlessing(false, -1), "SANCTUARY")
    eq(L.CycleRole("SHAMAN", nil), "HEALER")
    eq(L.CycleRole("SHAMAN", "CASTER"), nil)
end)
test("dominant tab", function()
    eq(L.DominantTab({ { points = 31 }, { points = 0 }, { points = 20 } }), 1)
    eq(L.DominantTab({ { points = 0 }, { points = 0 }, { points = 0 } }), nil)
end)
test("format time", function()
    eq(L.FormatTime(3599), "59m") eq(L.FormatTime(3720), "1h02") eq(L.FormatTime(42), "42s")
end)
test("every class/role pair has a default priority", function()
    for class, roles in pairs(ns.CLASS_ROLES) do
        for _, role in ipairs(roles) do
            local p = L.GetPriority({}, class, role)
            assert(p[1] and ns.BLESSINGS[p[1]], class .. ":" .. role)
        end
    end
end)

---------------------------------------------------------------------------
-- Integration: load the whole addon against the fake API
---------------------------------------------------------------------------
M.install()
local ns2 = {}
local files = {}
for line in io.lines("CamelusBetterBlessings.toc") do
    if line:match("%S") and not line:match("^##") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
end
M.load(".", files, ns2)

for id in pairs(M.spellNames) do M.known[id] = true end
M.known[20911] = nil M.known[25899] = nil -- no Sanctuary talent

M.units.player = { guid = "G-P", name = "Camelus", class = "PALADIN", talents = { 31, 5, 15 }, auras = {} }
M.units.party1 = { guid = "G-1", name = "Tankwar", class = "WARRIOR", role = "TANK", talents = { 0, 5, 31 }, auras = {} }
M.units.party2 = { guid = "G-2", name = "Elly", class = "SHAMAN", role = "DAMAGER", talents = { 31, 0, 5 },
    auras = { M.aura("Mana Well") } }
M.units.party3 = { guid = "G-3", name = "Enhy", class = "SHAMAN", role = "DAMAGER", talents = { 0, 31, 5 },
    auras = { M.aura("Lodestone") } }
M.units.party4 = { guid = "G-4", name = "Stabby", class = "ROGUE", role = "DAMAGER", talents = { 20, 31, 0 },
    auras = { M.aura("Fish Bowl", { spellId = 1307245 }), M.aura("Blessing of Kings", { source = "raid9" }) } }

M.fire("ADDON_LOADED", "CamelusBetterBlessings")
M.fire("PLAYER_LOGIN")
M.fire("GROUP_ROSTER_UPDATE")
M.flush()
-- let the inspect queue run (one player per tick)
for _ = 1, 8 do
    M.now = M.now + 6
    M.ticker()
    if M.inspecting then M.fire("INSPECT_READY", M.units[M.inspecting].guid) M.inspecting = nil end
    M.flush()
end

local function st(guid) return ns2.units[guid] end

test("integration: roster built", function() eq(#ns2.order, 5) end)
test("integration: roles", function()
    eq(st("G-P").role, "HEALER")
    eq(st("G-1").role, "TANK")
    eq(st("G-2").role, "CASTER")
    eq(st("G-3").role, "MELEE")
    eq(st("G-4").role, "MELEE")
end)
test("integration: camp buffs steer the choice", function()
    eq(st("G-1").choice.blessing, "KINGS")   -- tank
    eq(st("G-2").choice.blessing, "KINGS")   -- elemental: Wisdom blocked by Mana Well
    eq(st("G-3").choice.blessing, "KINGS")   -- enhancement: Might blocked by Lodestone
    eq(st("G-4").choice.blessing, "MIGHT")   -- rogue: Fish Bowl (Kings) - Might is fine anyway
    eq(st("G-P").choice.blessing, "WISDOM")
end)

local function rowFor(guid)
    for _, r in ipairs(ns2.UI.playerRows) do if r.guid == guid and r._shown then return r end end
end
local function classRow(class)
    for _, r in ipairs(ns2.UI.classRows) do if r.class == class and r._shown then return r end end
end

test("integration: secure rows cast the chosen blessing", function()
    eq(rowFor("G-2")._attrs.spell1, "Blessing of Kings")
    eq(rowFor("G-2")._attrs.unit, "party2")
    eq(rowFor("G-4")._attrs.spell1, "Blessing of Might")
end)
test("integration: greater blessing blocked by a camp buff", function()
    local r = classRow("SHAMAN")              -- Greater Wisdom, Elly has Mana Well
    eq(r._attrs.type1, nil)
    local w = classRow("WARRIOR")             -- Greater Might, no conflicts
    eq(w._attrs.spell1, "Greater Blessing of Might")
end)
test("integration: everything blocked -> row does nothing", function()
    ns2.db.assign["ROGUE:MELEE"] = { "KINGS", false, false, false }
    ns2.RequestUpdate() M.flush()
    eq(st("G-4").choice.status, "BLOCKED")
    eq(rowFor("G-4")._attrs.type1, nil)
    ns2.db.assign["ROGUE:MELEE"] = nil
    ns2.RequestUpdate() M.flush()
end)
test("integration: manual role override", function()
    SlashCmdList.CAMELUSBETTERBLESSINGS("role Enhy caster")
    M.flush()
    eq(st("G-3").role, "CASTER")
    eq(st("G-3").choice.blessing, "WISDOM")
    SlashCmdList.CAMELUSBETTERBLESSINGS("role Enhy auto")
    M.flush()
    eq(st("G-3").role, "MELEE")
end)
test("integration: smart button targets the tank first", function()
    eq(ns2.UI.smart._attrs.unit, "party1")
    eq(ns2.UI.smart._attrs.spell1, "Blessing of Kings")
end)
test("integration: cast marks pending and smart moves on", function()
    M.fire("UNIT_SPELLCAST_SENT", "player", "Tankwar", "x", 20217)
    M.flush()
    ns2.UI:PrepareSmart()
    assert(ns2.UI.smart._attrs.unit ~= "party1", "smart button should move on")
end)
test("integration: my blessing counts as done", function()
    M.units.party1.auras = { M.aura("Blessing of Kings", { mine = true }) }
    M.now = M.now + 5
    M.fire("UNIT_AURA", "party1")
    M.flush()
    eq(st("G-1").choice.status, "OK")
end)
test("integration: combat freezes attributes", function()
    M.combat = true
    M.secretInCombat = true
    M.fire("PLAYER_REGEN_DISABLED")
    local before = rowFor("G-2")._attrs.spell1
    M.units.party2.auras = {}
    M.fire("UNIT_AURA", "party2")
    M.flush()
    eq(rowFor("G-2")._attrs.spell1, before)
    M.combat = false
    M.fire("PLAYER_REGEN_ENABLED")
    M.flush()
    eq(st("G-2").choice.blessing, "WISDOM") -- Mana Well gone after combat
end)
test("integration: custom camp buff via slash command", function()
    M.units.party1.auras = { M.aura("Weird Campfire Thing") }
    SlashCmdList.CAMELUSBETTERBLESSINGS('camp add Weird Campfire Thing kings')
    M.flush()
    eq(st("G-1").choice.blessing, "MIGHT")
end)
test("integration: other slash commands run", function()
    for _, c in ipairs({ "", "", "lock", "lock", "roles", "auras party2", "camp list", "camp del 4", "refresh 10", "scale 1.2", "help", "config", "config", "reset" }) do
        SlashCmdList.CAMELUSBETTERBLESSINGS(c)
    end
    M.flush()
end)
test("integration: tooltips render", function()
    for _, r in ipairs(ns2.UI.playerRows) do if r._shown then ns2.UI:PlayerTooltip(r) end end
    for _, r in ipairs(ns2.UI.classRows) do if r._shown then ns2.UI:ClassTooltip(r) end end
    ns2.UI:SmartTooltip(ns2.UI.smart)
end)
test("integration: target warning", function()
    M.target = "party3"
    M.fire("PLAYER_TARGET_CHANGED")
    assert(ns2.targetWarning and ns2.targetWarning:find("Lodestone"), "expected a Lodestone warning")
end)
test("integration: config clicks", function()
    ns2.Config:Toggle()
    local row = ns2.Config.rows[1]
    row.slots[1]._scripts.OnClick(row.slots[1], "LeftButton")
    eq(ns2.db.assign["WARRIOR:TANK"][1], "SALVATION")
    row.greater._scripts.OnClick(row.greater, "RightButton")
    ns2.Config.checks[1]._checked = false
    ns2.Config.checks[1]._scripts.OnClick(ns2.Config.checks[1])
    eq(ns2.opt.protectCamp, false)
    M.flush()
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
