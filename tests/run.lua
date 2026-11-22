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
    eq(L.MatchCampBuff("whatever", 1230098, list).key, "FISH_BOWL")
    eq(L.MatchCampBuff("Boosted Stats", nil, list).key, "FISH_BOWL")
    eq(L.MatchCampBuff("Lodestone", nil, list).key, "LODESTONE")
    eq(L.MatchCampBuff("Camp: Mana Well", nil, list).key, "MANA_WELL")
    eq(L.MatchCampBuff("Blessing of Kings", nil, list), nil)
end)
test("camp benefits container detection", function()
    assert(L.IsCampContainer("Camp Benefits", nil, ns.CAMP_CONTAINER))
    assert(L.IsCampContainer("whatever", 1229741, ns.CAMP_CONTAINER))
    assert(not L.IsCampContainer("Fish Bowl", nil, ns.CAMP_CONTAINER))
end)
test("camp benefits tooltip lines", function()
    local found = L.MatchCampLines({ "Camp Benefits", "Fish Bowl: All stats increased by 8%.", "Incense Candle: Intellect increased by 25." }, ns.CAMP_BUFFS)
    eq(#found, 1) eq(found[1].key, "FISH_BOWL")
    found = L.MatchCampLines({ "Lodestone: +90 attack power", "Mana Well: 29 mana per 5 sec." }, ns.CAMP_BUFFS)
    eq(#found, 2)
    found = L.MatchCampLines({ "Fischschale: Alle Werte +8%" }, { { key = "X", name = "Fish Bowl", localName = "Fischschale", match = {} } })
    eq(#found, 1)
    eq(#L.MatchCampLines({ "Camp Chair: +1% crit" }, ns.CAMP_BUFFS), 0)
end)
test("all camp conflicts", function()
    eq(#L.AllCampConflicts(ns.CAMP_BUFFS), 3)
end)
test("greater conflicts", function()
    local r = L.GreaterConflicts("WISDOM", { { name = "A", conflicts = { WISDOM = "Mana Well" } }, { name = "B", conflicts = {} } })
    eq(#r, 1) eq(r[1].name, "A")
end)
test("cycle helpers", function()
    eq(L.CycleBlessing(false, 1), "MIGHT")
    eq(L.CycleBlessing("MIGHT", -1), false)
    eq(L.CycleBlessing(false, -1), "KINGS")
    eq(L.CycleBlessing("KINGS", 1), false)
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
test("only WoW Forever blessings exist", function()
    for _, k in ipairs({ "SALVATION", "LIGHT", "SANCTUARY" }) do assert(ns.BLESSINGS[k] == nil, k) end
    eq(#ns.BLESSING_ORDER, 3)
    for key, p in pairs(ns.DEFAULT_ROLE_PRIORITY) do
        for i = 1, ns.MAX_PRIORITY do assert(p[i] == false or ns.BLESSINGS[p[i]], key) end
    end
    for key, p in pairs(ns.DEFAULT_CLASS_ROLE_PRIORITY) do
        for i = 1, ns.MAX_PRIORITY do assert(p[i] == false or ns.BLESSINGS[p[i]], key) end
    end
end)
test("hunters: Ranged DPS and Melee weaving", function()
    eq(#ns.CLASS_ROLES.HUNTER, 2)
    assert(L.IsValidRole("HUNTER", "MELEE"))
    eq(L.RoleLabel("HUNTER", "MELEE"), "Melee weaving")
    eq(L.RoleShort("HUNTER", "MELEE"), "WEAV")
    eq(L.RoleLabel("ROGUE", "MELEE"), "Melee DPS")      -- only hunters get the special name
    eq(L.RoleLabel("HUNTER", "RANGED"), "Ranged (physical)")
    -- Auto never guesses melee weaving: talents, group DPS and class guess all say ranged
    eq(L.ResolveRole("HUNTER", nil, "DAMAGER", "RANGED"), "RANGED")
    eq(L.ResolveRole("HUNTER", nil, "DAMAGER", nil), "RANGED")
    eq(L.ResolveRole("HUNTER", nil, nil, nil), "RANGED")
    -- set by hand
    eq(L.ResolveRole("HUNTER", "MELEE", "DAMAGER", "RANGED"), "MELEE")
    local p = L.GetPriority({}, "HUNTER", "MELEE")
    eq(p[1], "KINGS") eq(p[2], "MIGHT") eq(p[3], "WISDOM")
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

M.units.player = { guid = "G-P", name = "Camelus", class = "PALADIN", talents = { 31, 5, 15 }, auras = {} }
-- Camp buffs arrive the way WoW Forever shows them: one "Camp Benefits" aura.
M.units.party1 = { guid = "G-1", name = "Tankwar", class = "WARRIOR", role = "TANK", talents = { 0, 5, 31 }, auras = {} }
M.units.party2 = { guid = "G-2", name = "Elly", class = "SHAMAN", role = "DAMAGER", talents = { 31, 0, 5 },
    auras = { M.campBenefits({ "Camp Benefits", "Mana Well: Restores 29 mana per 5 sec." }) } }
M.units.party3 = { guid = "G-3", name = "Enhy", class = "SHAMAN", role = "DAMAGER", talents = { 0, 31, 5 },
    auras = { M.campBenefits({ "Camp Benefits", "Lodestone: Melee attack power increased by 90.", "Camp Chair: +1% crit" }) } }
M.units.party4 = { guid = "G-4", name = "Stabby", class = "ROGUE", role = "DAMAGER", talents = { 20, 31, 0 },
    auras = { M.campBenefits({ "Fish Bowl: All stats increased by 8%." }), M.aura("Blessing of Kings", { source = "raid9" }) } }

-- Settings saved by v1.0.0, which still offered Salvation / Light / Sanctuary.
CamelusBetterBlessingsCharDB = {
    assign = { ["HUNTER:RANGED"] = { "SALVATION", "KINGS", "LIGHT", "SANCTUARY" } },
    greater = { HUNTER = "SALVATION", WARRIOR = "MIGHT" },
}
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
test("integration: old saved blessings are cleaned up", function()
    local p = ns2.db.assign["HUNTER:RANGED"]
    eq(p[1], false) eq(p[2], "KINGS") eq(p[3], false) eq(p[4], nil)
    eq(ns2.db.greater.HUNTER, nil)
    eq(ns2.db.greater.WARRIOR, "MIGHT")
end)
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

-- Player buttons live in each class button's hover flyout.
local function rowFor(guid)
    for _, cb in ipairs(ns2.UI.classButtons) do
        for _, b in ipairs(cb.flyout.buttons) do if b.guid == guid and b._shown then return b end end
    end
end
local function classRow(class)
    for _, r in ipairs(ns2.UI.classButtons) do if r.class == class and r._shown then return r end end
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
test("integration: the reported bug - Fish Bowl on yourself blocks Kings", function()
    ns2.db.overrides["Camelus"] = "TANK"            -- Kings first for a paladin tank
    M.units.player.auras = {}
    M.fire("UNIT_AURA", "player") M.flush()
    eq(st("G-P").choice.blessing, "KINGS")
    eq(rowFor("G-P")._attrs.spell1, "Blessing of Kings")
    M.units.player.auras = { M.campBenefits({ "Camp Benefits", "Fish Bowl: All stats increased by 8%." }) }
    M.fire("UNIT_AURA", "player") M.flush()
    assert(st("G-P").choice.blessing ~= "KINGS", "Kings must not be picked with Fish Bowl")
    assert(rowFor("G-P")._attrs.spell1 ~= "Blessing of Kings", "the row must not cast Kings")
    eq(st("G-P").choice.skipped[1].reason, "camp")
    ns2.db.overrides["Camelus"] = nil
end)
test("integration: unreadable Camp Benefits blocks every camp blessing", function()
    M.units.player.auras = { M.campBenefits(false) }
    ns2.db.overrides["Camelus"] = "TANK"
    M.fire("UNIT_AURA", "player") M.flush()
    local b = st("G-P").choice.blessing
    assert(b ~= "KINGS" and b ~= "MIGHT" and b ~= "WISDOM", "got " .. tostring(b))
    assert(st("G-P").aura.camps[1].unreadable, "camp should be marked unreadable")
    ns2.db.overrides["Camelus"] = nil
    M.units.player.auras = {}
    M.fire("UNIT_AURA", "player") M.flush()
end)
test("integration: camp buffs use the real item icons", function()
    M.units.party2.auras = { M.campBenefits({ "Mana Well: Restores 29 mana per 5 sec." }) }
    M.units.party3.auras = { M.campBenefits({ "Lodestone: Melee attack power increased by 90." }) }
    M.fire("UNIT_AURA", "party2") M.fire("UNIT_AURA", "party3") M.flush()
    local camps = st("G-4").aura.camps
    eq(camps[1].key, "FISH_BOWL")
    eq(camps[1].icon, "item:279967")
    eq(st("G-2").aura.camps[1].icon, "item:279956")   -- Mana Well
    eq(st("G-3").aura.camps[1].icon, "item:279960")   -- Lodestone
    eq(ns2.CAMP_BUFFS[2].localName, "Lodestone")      -- "(Tier 1)" stripped
end)
test("camp re-check: a feature leaving Camp Benefits is noticed without UNIT_AURA", function()
    -- Holy paladin: Wisdom > Kings. Mana Well blocks Wisdom, so Kings is given.
    M.units.player.auras = {
        M.campBenefits({ "Camp Benefits", "Mana Well: Restores 29 mana per 5 sec.", "Camp Chair: +1% crit" }),
        M.aura("Blessing of Kings", { mine = true }),
    }
    M.fire("UNIT_AURA", "player") M.flush()
    eq(st("G-P").choice.blessing, "KINGS")
    eq(st("G-P").choice.status, "OK")
    -- Mana Well's line disappears, Camp Benefits stays, and no UNIT_AURA fires.
    M.units.player.auras[1]._tooltip = { "Camp Benefits", "Camp Chair: +1% crit" }
    for _ = 1, 5 do M.now = M.now + 1.01 M.ticker() M.flush() end   -- within 5 seconds
    eq(st("G-P").choice.blessing, "WISDOM")
    eq(st("G-P").choice.status, "SWAP")      -- click replaces my Kings with Wisdom
    M.units.player.auras = {}
    M.fire("UNIT_AURA", "player") M.flush()
end)
test("camp re-check: an expired camp buff is re-read right away", function()
    M.units.player.auras = { M.aura("Camp Benefits", { spellId = 1229741, expires = M.now + 2,
        tooltip = { "Mana Well: Restores 29 mana per 5 sec." } }) }
    M.fire("UNIT_AURA", "player") M.flush()
    eq(st("G-P").choice.blessing, "KINGS")
    M.units.player.auras = {}                -- gone, but no event
    st("G-P").nextCampCheck = M.now + 100    -- not due for the periodic check
    M.now = M.now + 3
    M.ticker() M.flush()
    eq(st("G-P").choice.blessing, "WISDOM")
end)
test("camp re-check: re-reads are spread out in a full raid", function()
    local list, saved = {}, ns2.order
    ns2.order = {}
    for i = 1, 40 do
        local g = "R-" .. i
        ns2.units[g] = { guid = g, aura = { blessings = {}, camps = {}, hasCampBenefits = true } }
        ns2.order[i] = g
        list[i] = ns2.units[g]
    end
    ns2.CampRefreshTick(M.now)
    local dirty = 0
    for _, u in ipairs(list) do if u.dirty then dirty = dirty + 1 end end
    eq(dirty, 8)                             -- 40 players / 5 s = 8 per tick
    for i = 1, 40 do ns2.units["R-" .. i] = nil end
    ns2.order = saved
end)
test("integration: /cbb auras prints Camp Benefits lines", function()
    local before = #M.chat
    SlashCmdList.CAMELUSBETTERBLESSINGS("auras party4")
    local text = table.concat(M.chat, "\n", before + 1)
    assert(text:find("Fish Bowl: All stats"), "tooltip line missing")
    assert(text:find("recognised: Fish Bowl"), "recognised line missing")
end)
test("integration: other slash commands run", function()
    for _, c in ipairs({ "", "", "lock", "lock", "roles", "auras party2", "camp list", "camp del 4", "refresh 10", "scale 1.2", "help", "config", "config", "players", "reset" }) do
        SlashCmdList.CAMELUSBETTERBLESSINGS(c)
    end
    M.flush()
end)
test("integration: tooltips render", function()
    for _, cb in ipairs(ns2.UI.classButtons) do
        if cb._shown then
            ns2.UI:ClassTooltip(cb)
            for _, b in ipairs(cb.flyout.buttons) do if b._shown then ns2.UI:PlayerTooltip(b) end end
        end
    end
    ns2.UI:SmartTooltip(ns2.UI.smart)
end)
test("bar: no header, smart row hidden by default, flyout opens on hover", function()
    eq(ns2.UI.smart._shown, false)
    local cb = classRow("SHAMAN")
    eq(cb.flyout._shown, false)
    for _, fn in ipairs(cb._hooks.OnEnter) do fn(cb) end
    eq(cb.flyout._shown, true)
    eq(#cb.flyout.buttons, 2)
    ns2.UI:CloseFlyouts()
    eq(cb.flyout._shown, false)
end)
test("bar: class colour shows who is missing a blessing", function()
    local cb = classRow("SHAMAN")
    local c = cb.bg._color
    assert(c and c[1] > c[2], "shaman button should be red (someone missing)")
end)
test("bar: no setting changes from the bar", function()
    for _, cb in ipairs(ns2.UI.classButtons) do
        assert(not cb._hooks.OnMouseUp, "class buttons must not change settings")
        for _, b in ipairs(cb.flyout.buttons) do assert(not b._hooks.OnMouseUp, "player buttons must not change settings") end
    end
end)
test("bar: names never run under the camp icons or the status text", function()
    -- G-4 (rogue) has a camp buff; Tankwar (G-1) has none at this point.
    M.units.party4.auras = { M.campBenefits({ "Fish Bowl: +8%", "Mana Well: 29 mp5" }) }
    M.units.party1.auras = {}
    M.fire("UNIT_AURA", "party4") M.fire("UNIT_AURA", "party1") M.flush()
    local withCamp, without = rowFor("G-4"), rowFor("G-1")
    -- icons sit left of the status text, side by side
    eq(withCamp.camp[1]._points.RIGHT.rel, withCamp.text)
    eq(withCamp.camp[2]._points.RIGHT.rel, withCamp.camp[1])
    -- the name ends at the left-most shown icon
    eq(withCamp.camp[2]._shown, true)
    eq(withCamp.name._points.RIGHT.rel, withCamp.camp[2])
    eq(withCamp.name._points.LEFT.rel, withCamp.role)
    -- no camp buffs: the name ends at the status text
    eq(without.name._points.RIGHT.rel, without.text)
    -- class button camp marker sits beside the Greater icon, not on it
    local cb = classRow("ROGUE")
    eq(cb.campMarks[1]._points.LEFT.rel, cb.icon2)
    eq(cb.campMarks[1]._points.LEFT.relPoint, "RIGHT")
end)
test("bar: class button shows every distinct camp buff, and widens only when needed", function()
    -- rogue (G-4) has Fish Bowl + Mana Well: both icons on the class button
    M.units.party4.auras = { M.campBenefits({ "Fish Bowl: +8%", "Mana Well: 29 mp5" }) }
    M.fire("UNIT_AURA", "party4") M.flush()
    local cb = classRow("ROGUE")
    eq(cb.campMarks[1]._shown, true) eq(cb.campMarks[1]._texture, "item:279967")
    eq(cb.campMarks[2]._shown, true) eq(cb.campMarks[2]._texture, "item:279956")
    eq(cb.campMarks[3]._shown, false)
    eq(cb.campMarks[2]._points.LEFT.rel, cb.campMarks[1])
    -- two icons need more room than one: every class button widens together
    local w = ns2.UI:ButtonWidth(2)
    assert(w > ns2.UI:ButtonWidth(1), "should widen for two icons")
    for _, b in ipairs(ns2.UI.classButtons) do if b._shown then eq(b._width, w) end end
    -- shamans: Elly and Enhy both with Mana Well -> shown once
    M.units.party2.auras = { M.campBenefits({ "Mana Well: 29 mp5" }) }
    M.units.party3.auras = { M.campBenefits({ "Mana Well: 29 mp5" }) }
    M.fire("UNIT_AURA", "party2") M.fire("UNIT_AURA", "party3") M.flush()
    local sh = classRow("SHAMAN")
    eq(sh.campMarks[1]._shown, true) eq(sh.campMarks[2]._shown, false)
    -- back to one camp buff anywhere: width returns to 88
    M.units.party4.auras = { M.campBenefits({ "Fish Bowl: +8%" }) }
    M.fire("UNIT_AURA", "party4") M.flush()
    eq(cb._width, ns2.UI:ButtonWidth(1))     -- back to the one-icon width
    -- restore the scenario's buffs for later tests
    M.units.party3.auras = { M.campBenefits({ "Camp Benefits", "Lodestone: Melee attack power increased by 90.", "Camp Chair: +1% crit" }) }
    M.fire("UNIT_AURA", "party3") M.flush()
end)
test("bar: rows are packed tight like Pally Power", function()
    local shown = {}
    for _, cb in ipairs(ns2.UI.classButtons) do if cb._shown then shown[#shown + 1] = cb end end
    assert(#shown >= 2, "need two class rows")
    local y1, y2 = shown[1]._points.TOPLEFT.y, shown[2]._points.TOPLEFT.y
    eq(y1 - y2, 29)                     -- 30 tall, overlapping by 1 => ~2 visible units apart
    eq(shown[1]._width, ns2.UI.buttonWidth)  -- 88, or wider while a class shows several camp icons
    assert(ns2.UI.buttonWidth >= 88)
    -- flyout rows use the same spacing
    local fb = shown[1].flyout.buttons
    if fb[2] then eq(fb[1]._points.TOPLEFT.y - fb[2]._points.TOPLEFT.y, 29) end
end)
test("bar: left-click = Greater, right-click = next player in the class, own blessing", function()
    -- Two shamans with no buffs: Elly (Elemental -> Caster) then Enhy (Enhancement -> Melee)
    M.units.party2.auras, M.units.party3.auras = {}, {}
    M.fire("UNIT_AURA", "party2") M.fire("UNIT_AURA", "party3") M.flush()
    local cb = classRow("SHAMAN")
    -- left-click is still the class's Greater Blessing (Wisdom for shamans)
    eq(cb._attrs.spell1, "Greater Blessing of Wisdom")
    -- right-click: first shaman in the list, with HER blessing
    cb._scripts.PreClick(cb, "RightButton")
    eq(cb._attrs.type2, "spell")
    eq(cb._attrs.unit2, "party2")
    eq(cb._attrs.spell2, "Blessing of Wisdom")
    -- she was just blessed: the next right-click goes to the enhancement shaman, with Might
    M.fire("UNIT_SPELLCAST_SENT", "player", "Elly", "x", 19742)
    cb._scripts.PreClick(cb, "RightButton")
    eq(cb._attrs.unit2, "party3")
    eq(cb._attrs.spell2, "Blessing of Might")
    -- both done: right-click does nothing
    M.fire("UNIT_SPELLCAST_SENT", "player", "Enhy", "x", 19740)
    cb._scripts.PreClick(cb, "RightButton")
    eq(cb._attrs.type2, nil)
    -- the left-click Greater Blessing was not touched
    eq(cb._attrs.spell1, "Greater Blessing of Wisdom")
    -- out of range players are skipped
    M.now = M.now + 5   -- pending marks expire
    M.far = { party2 = true }
    ns2.RequestUpdate() M.flush()
    cb._scripts.PreClick(cb, "RightButton")
    eq(cb._attrs.unit2, "party3")
    M.far = nil
    ns2.UI:ClassTooltip(cb)
    -- restore the scenario's buffs for later tests
    M.units.party2.auras = { M.campBenefits({ "Camp Benefits", "Mana Well: Restores 29 mana per 5 sec." }) }
    M.units.party3.auras = { M.campBenefits({ "Camp Benefits", "Lodestone: Melee attack power increased by 90.", "Camp Chair: +1% crit" }) }
    M.fire("UNIT_AURA", "party2") M.fire("UNIT_AURA", "party3") M.flush()
end)
test("bar: Pally Power style timers, counting down in combat too", function()
    eq(L.FormatClock(3364), "56:04")
    eq(L.FormatClock(59), "0:59")
    eq(L.FormatClock(3900), "1h05")
    -- my Kings on Tankwar with 56:04 left, my Might on Stabby with 10:00 left
    M.units.party1.auras = { M.aura("Blessing of Kings", { mine = true, expires = M.now + 3364 }) }
    M.units.party4.auras = { M.aura("Blessing of Might", { mine = true, expires = M.now + 600 }) }
    M.fire("UNIT_AURA", "party1") M.fire("UNIT_AURA", "party4") M.flush()
    local war, rogue = classRow("WARRIOR"), classRow("ROGUE")
    assert(war.text._text:find("56:04", 1, true), war.text._text)
    assert(rogue.text._text:find("10:00", 1, true), rogue.text._text)
    assert(rowFor("G-1").text._text:find("56:04", 1, true), rowFor("G-1").text._text)
    -- the class button has room for the timer
    assert(war._width >= ns2.UI:ButtonWidth(0))
    -- in combat nothing is re-read, but the countdown keeps going
    M.combat = true
    M.now = M.now + 65
    ns2.UI:UpdateTimers()
    assert(war.text._text:find("54:59", 1, true), war.text._text)
    assert(rowFor("G-1").text._text:find("54:59", 1, true), rowFor("G-1").text._text)
    M.combat = false
    -- a class where I have no blessing shows no timer
    M.units.party4.auras = {}
    M.fire("UNIT_AURA", "party4") M.flush()
    eq(classRow("ROGUE").text._text, "")
    M.units.party1.auras = {}
    M.fire("UNIT_AURA", "party1") M.flush()
end)
test("bar: gear left-click opens settings, right-click opens Players", function()
    local gear = ns2.UI.handle
    ns2.Config.frame._shown = false
    gear._scripts.OnClick(gear, "RightButton")
    eq(ns2.Config.frame._shown, true)
    eq(ns2.Config.activeTab, "players")
    ns2.Config.frame._shown = false
    gear._scripts.OnClick(gear, "LeftButton")
    eq(ns2.Config.frame._shown, true)
end)
test("bar: player list opens right by default, left with the option", function()
    local cb = classRow("SHAMAN")
    local p = cb.flyout._points
    eq(p.TOPLEFT.rel, cb) eq(p.TOPLEFT.relPoint, "TOPRIGHT")
    ns2.opt.flyoutLeft = true
    ns2.RequestUpdate(true) M.flush()
    p = cb.flyout._points
    eq(p.TOPRIGHT.rel, cb) eq(p.TOPRIGHT.relPoint, "TOPLEFT")
    eq(p.TOPLEFT, nil)
    ns2.opt.flyoutLeft = false
    ns2.RequestUpdate(true) M.flush()
    p = cb.flyout._points
    eq(p.TOPLEFT.relPoint, "TOPRIGHT") eq(p.TOPRIGHT, nil)
end)
test("bar: single-role classes have no '?' on their role", function()
    local rogue = rowFor("G-4")
    assert(not rogue.role._text:find("?", 1, true), rogue.role._text)
end)
test("integration: target warning", function()
    M.target = "party3"
    M.fire("PLAYER_TARGET_CHANGED")
    assert(ns2.targetWarning and ns2.targetWarning:find("Lodestone"), "expected a Lodestone warning")
end)
test("integration: players tab sets roles", function()
    ns2.Config:Toggle("players")
    local row
    for _, r in ipairs(ns2.Config.playerRows) do if r.guid == "G-3" then row = r end end
    assert(row, "Enhy should be listed")
    row.roleButton._scripts.OnClick(row.roleButton, "LeftButton")   -- Auto -> Healer
    eq(ns2.db.overrides["Enhy"], "HEALER")
    row.roleButton._scripts.OnClick(row.roleButton, "RightButton")  -- back to Auto
    eq(ns2.db.overrides["Enhy"], nil)
    M.flush()
end)
test("settings: classes are headers, roles are sub-rows only when a class has several", function()
    ns2.Config:Toggle("blessings")
    local rows = ns2.Config.slotRows
    local byClass = {}
    for _, r in ipairs(rows) do
        byClass[r.class] = byClass[r.class] or { header = 0, sub = 0 }
        if r.isHeader then byClass[r.class].header = byClass[r.class].header + 1 else byClass[r.class].sub = byClass[r.class].sub + 1 end
    end
    for class, roles in pairs(ns2.CLASS_ROLES) do
        eq(byClass[class].header, 1, class .. " header")
        eq(byClass[class].sub, #roles > 1 and #roles or 0, class .. " role rows")
    end
    for _, r in ipairs(rows) do
        if r.isHeader then
            eq(r.label._text, ns2.ClassLabel(r.class), "header shows the class")
            if #ns2.CLASS_ROLES[r.class] == 1 then eq(#r.slots, ns2.MAX_PRIORITY, r.class .. " slots on header") else eq(#r.slots, 0) end
        else
            eq(r.label._text, ns2.Logic.RoleLabel(r.class, r.role), "sub-row shows the role")
        end
    end
    -- the single-role header's slots edit that class's only role
    for _, r in ipairs(rows) do
        if r.class == "MAGE" then
            r.slots[1]._scripts.OnClick(r.slots[1], "LeftButton")
            eq(ns2.db.assign["MAGE:CASTER"][1], "KINGS")
            ns2.db.assign["MAGE:CASTER"] = nil
        end
    end
end)
test("players tab: a raid is shown in Group 1-8 boxes, like the raid window", function()
    local savedUnits = M.units
    local savedInRaid, savedNum, savedInfo = IsInRaid, GetNumGroupMembers, GetRaidRosterInfo
    M.units = {}
    for i = 1, 12 do
        M.units["raid" .. i] = { guid = "RG-" .. i, name = "Raider" .. i,
            class = (i % 2 == 0) and "WARRIOR" or "MAGE", auras = {} }
    end
    M.units.player = M.units.raid1
    IsInRaid = function() return true end
    GetNumGroupMembers = function() return 12 end
    GetRaidRosterInfo = function(i) return "Raider" .. i, 0, math.floor((i - 1) / 5) + 1 end
    M.fire("GROUP_ROSTER_UPDATE") M.flush()
    ns2.Config:Toggle("players")
    local cfg = ns2.Config
    local function shownIn(g)
        local n = 0
        for slot = 1, 5 do
            local row = cfg.slotsByGroup[g][slot]
            if row and row._shown then n = n + 1 end
        end
        return n
    end
    eq(shownIn(1), 5) eq(shownIn(2), 5) eq(shownIn(3), 2) eq(shownIn(4), 0)
    for g = 1, 8 do eq(cfg.groupBoxes[g]._shown, true) end     -- all 8 boxes in a raid
    eq(#cfg.playerRows, 12)                                    -- everyone visible, no scrolling
    -- the third player of group 2 is raid8
    eq(cfg.slotsByGroup[2][3].guid, "RG-8")
    -- mages have one role: button disabled; warriors can change
    local mageRow, warRow = cfg.slotsByGroup[1][1], cfg.slotsByGroup[1][2]
    eq(mageRow.roleButton._enabled, false)
    eq(warRow.roleButton._enabled, true)
    -- restore the party scenario
    M.units = savedUnits
    IsInRaid, GetNumGroupMembers, GetRaidRosterInfo = savedInRaid, savedNum, savedInfo
    M.fire("GROUP_ROSTER_UPDATE") M.flush()
    ns2.Config:RefreshPlayers(true)
    eq(cfg.groupBoxes[1]._shown, true)
    eq(cfg.groupBoxes[2]._shown, false)                        -- party: only Group 1
end)
test("settings: blessing rows have air and dividers never touch an icon", function()
    ns2.Config:Toggle("blessings")
    local slots = {}
    for _, r in ipairs(ns2.Config.slotRows) do
        if r.greater then slots[#slots + 1] = r.greater end
        for _, b in ipairs(r.slots) do slots[#slots + 1] = b end
    end
    -- two slots in the same column are on the same row or at least a slot + 4 px apart
    for i = 1, #slots do
        for j = i + 1, #slots do
            local a, b = slots[i]._points.TOPLEFT, slots[j]._points.TOPLEFT
            if a.x == b.x and a.y ~= b.y then
                assert(math.abs(a.y - b.y) >= 24, string.format("rows too close: %d vs %d", a.y, b.y))
            end
        end
    end
    -- no divider line crosses any 20 px tall slot in its column
    assert(#ns2.Config.dividers > 0)
    for _, d in ipairs(ns2.Config.dividers) do
        for _, sl in ipairs(slots) do
            local p = sl._points.TOPLEFT
            if p.x >= d.x and p.x < d.x + d.w then
                local top, bottom = p.y, p.y - 20
                assert(not (d.y <= top and d.y >= bottom), string.format("divider at %d crosses a slot at %d", d.y, top))
                assert(math.abs(d.y - top) >= 4 and math.abs(d.y - bottom) >= 4, "divider too close to a slot")
            end
        end
    end
end)
test("integration: config clicks", function()
    ns2.Config:Toggle("blessings")
    local row, header
    for _, r in ipairs(ns2.Config.slotRows) do
        if r.class == "WARRIOR" and r.role == "TANK" then row = r end
        if r.class == "WARRIOR" and r.isHeader then header = r end
    end
    row.greater = header.greater
    row.slots[1]._scripts.OnClick(row.slots[1], "LeftButton")
    eq(ns2.db.assign["WARRIOR:TANK"][1], false)
    row.greater._scripts.OnClick(row.greater, "RightButton")
    ns2.Config.checks[1]._checked = false
    ns2.Config.checks[1]._scripts.OnClick(ns2.Config.checks[1])
    eq(ns2.opt.protectCamp, false)
    M.flush()
end)

test("pally power: reads other paladins' assignments and never sends any", function()
    local sent = {}
    C_ChatInfo = {
        SendAddonMessage = function(prefix, msg, channel) sent[#sent + 1] = { prefix, msg, channel } end,
        RegisterAddonMessagePrefix = function() end,
    }
    UnitInParty = function(n) return n == "Holybob" end
    UnitIsGroupLeader = function(n) return n == "Holybob" end
    local PP = ns2.PP
    local function recv(msg, from)
        PP.frame._scripts.OnEvent(PP.frame, "CHAT_MSG_ADDON", "PLPWR", msg, "PARTY", from or "Holybob")
        M.flush()
    end
    ns2.db.assign["WARRIOR:TANK"] = nil   -- an earlier test edited this row; use the defaults (Kings > Might)
    M.units.party1.auras, M.units.party2.auras = {}, {}
    M.fire("UNIT_AURA", "party1") M.fire("UNIT_AURA", "party2") M.flush()

    -- asking: the same REQ Pally Power sends, nothing else
    assert(PP.Request(true), "request should go out in a group")
    eq(sent[1][1], "PLPWR") eq(sent[1][2], "REQ") eq(sent[1][3], "PARTY")

    -- Holybob's own row: Kings on warriors (class 1), Wisdom on shamans (class 9)
    recv("SELF 3n3n3n@3nnnnnnn1")
    eq(PP.BlessingFor("Holybob", "WARRIOR"), "KINGS")
    eq(PP.BlessingFor("Holybob", "SHAMAN"), "WISDOM")
    eq(PP.BlessingFor("Holybob", "ROGUE"), nil)
    -- Tankwar would get Kings from me, but Holybob gives it: I pick the next one
    eq(st("G-1").choice.blessing, "MIGHT")
    eq(st("G-1").choice.skipped[1].reason, "taken")

    -- the leader assigns ME Wisdom on warriors
    recv("ASSIGN Camelus 1 1")
    eq(st("G-1").priority[1], "WISDOM")
    eq(st("G-1").choice.blessing, "WISDOM")
    eq(ns2.EffectiveGreater("WARRIOR"), "WISDOM")
    -- a single-player assignment beats the class one
    recv("NASSIGN Camelus 9 Elly 3")
    eq(st("G-2").priority[1], "KINGS")

    -- the Pally Power tab lists both paladins, me first
    ns2.Config:Toggle("pallypower")
    eq(#ns2.Config.ppList, 2)
    eq(ns2.Config.ppList[1].isMe, true)
    eq(ns2.Config.ppList[2].name, "Holybob")

    -- not following: back to my own lists and my own Greater Blessing
    ns2.opt.followPP = false
    ns2.RequestUpdate() M.flush()
    eq(st("G-1").priority[1], "KINGS")
    eq(ns2.EffectiveGreater("WARRIOR"), ns2.GetGreater("WARRIOR"))
    ns2.opt.followPP = true

    -- someone outside the group is ignored; a non-leader can't change my row
    recv("SELF 3n@333333333", "Stranger")
    eq(PP.Data().rows["Stranger"], nil)
    UnitInParty = function(n) return n == "Holybob" or n == "Otherpal" end
    recv("ASSIGN Camelus 1 3", "Otherpal")
    eq(PP.BlessingFor("Camelus", "WARRIOR"), "WISDOM")

    -- the leader clears everything
    recv("CLEAR")
    eq(PP.BlessingFor("Holybob", "WARRIOR"), nil)
    eq(PP.BlessingFor("Camelus", "WARRIOR"), nil)

    -- this addon only ever sent requests
    for _, m in ipairs(sent) do eq(m[2], "REQ") end
    C_ChatInfo, UnitInParty, UnitIsGroupLeader = nil, nil, nil
    ns2.RequestUpdate() M.flush()
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
