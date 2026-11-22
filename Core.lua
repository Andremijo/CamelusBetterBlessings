-- Camelus' Better Blessings - core: saved variables, roster, auras, roles, events
local ADDON_NAME, ns = ...
local Logic = ns.Logic

local CBB = CreateFrame("Frame", "CamelusBetterBlessingsCore")
ns.core = CBB

ns.units = {}        -- guid -> unit state
ns.order = {}        -- roster order (list of guids)
ns.talentCache = {}  -- guid -> { role, detail, time }
ns.pending = {}      -- guid -> GetTime() of a cast we just made (aura not seen yet)
ns.known = {}        -- blessing key -> true
ns.spellNames = {}   -- blessing key -> { single = "...", greater = "..." }
ns.blessingByName = {} -- lower-case aura name -> { key, greater }

BINDING_HEADER_CAMELUSBETTERBLESSINGS = "Camelus' Better Blessings"
_G["BINDING_NAME_CLICK CBB_SmartButton:LeftButton"] = "Bless the next player who needs it"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local issecret = _G.issecretvalue or function() return false end

-- WoW Forever inherits the "secret value" restrictions from modern WoW: while
-- restricted (combat), aura data can be opaque. Never compare a secret.
local function readable(v)
    return v ~= nil and not issecret(v)
end
ns.readable = readable

function ns.Print(msg, ...)
    if select("#", ...) > 0 then msg = string.format(msg, ...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cfff5c542CBB|r " .. tostring(msg))
end
local Print = ns.Print

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = SafeCall(C_Spell.GetSpellName, id)
        if ok and readable(n) and n then return n end
    end
    if GetSpellInfo then
        local ok, n = SafeCall(GetSpellInfo, id)
        if ok and readable(n) and n then return n end
    end
    return nil
end

local function SpellTexture(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = SafeCall(C_Spell.GetSpellTexture, id)
        if ok and readable(t) and t then return t end
    end
    if GetSpellTexture then
        local ok, t = SafeCall(GetSpellTexture, id)
        if ok and readable(t) and t then return t end
    end
    return nil
end

local function KnowsSpellById(id)
    if not id then return false end
    for _, fn in ipairs({ _G.IsPlayerSpell, _G.IsSpellKnownOrOverridesKnown, _G.IsSpellKnown }) do
        local ok, r = SafeCall(fn, id)
        if ok and readable(r) and r then return true end
    end
    return false
end

local function KnowsSpellByName(name)
    if not name then return false end
    -- name lookups normally only resolve for spells in the player's spellbook
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = SafeCall(C_Spell.GetSpellInfo, name)
        if ok and readable(info) and type(info) == "table" and info.spellID then return true end
    elseif GetSpellInfo then
        local ok, n = SafeCall(GetSpellInfo, name)
        if ok and readable(n) and n then return true end
    end
    return false
end

function ns.Now() return GetTime() end

function ns.InCombat()
    return InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local function InitDB()
    CamelusBetterBlessingsDB = CamelusBetterBlessingsDB or {}
    CamelusBetterBlessingsCharDB = CamelusBetterBlessingsCharDB or {}
    local g, c = CamelusBetterBlessingsDB, CamelusBetterBlessingsCharDB
    g.customCamp = g.customCamp or {}
    c.assign = c.assign or {}
    c.greater = c.greater or {}
    c.overrides = c.overrides or {}
    c.options = c.options or {}
    for k, v in pairs(ns.DEFAULT_OPTIONS) do
        if c.options[k] == nil then c.options[k] = v end
    end
    -- Drop blessings that no longer exist (Salvation, Light, Sanctuary were
    -- removed from WoW Forever) from saved assignments.
    for key, list in pairs(c.assign) do
        local clean = {}
        for i = 1, ns.MAX_PRIORITY do
            local b = list[i]
            clean[i] = (b and ns.BLESSINGS[b]) and b or false
        end
        c.assign[key] = clean
    end
    for class, b in pairs(c.greater) do
        if b and not ns.BLESSINGS[b] then c.greater[class] = nil end
    end
    for _, e in ipairs(g.customCamp) do
        local keep = {}
        for _, b in ipairs(e.conflicts or {}) do if ns.BLESSINGS[b] then keep[#keep + 1] = b end end
        e.conflicts = keep
    end
    ns.gdb, ns.db, ns.opt = g, c, c.options
end

function ns.GetGreater(class)
    local v = ns.db.greater[class]
    if v == nil then return ns.DEFAULT_GREATER[class] end
    return v or nil
end

---------------------------------------------------------------------------
-- Spells: localized names, icons, known state
---------------------------------------------------------------------------
function ns.RefreshSpells()
    wipe(ns.blessingByName)
    for key, b in pairs(ns.BLESSINGS) do
        local single = SpellName(b.spellId) or b.name
        local greater = SpellName(b.greaterId) or b.greaterName
        ns.spellNames[key] = { single = single, greater = greater }
        b.texture = SpellTexture(b.spellId) or b.icon
        b.greaterTexture = SpellTexture(b.greaterId) or b.greaterIcon
        ns.blessingByName[single:lower()] = { key = key, greater = false }
        ns.blessingByName[greater:lower()] = { key = key, greater = true }
        -- English names too, in case IDs resolve to something unexpected
        ns.blessingByName[b.name:lower()] = ns.blessingByName[b.name:lower()] or { key = key, greater = false }
        ns.blessingByName[b.greaterName:lower()] = ns.blessingByName[b.greaterName:lower()] or { key = key, greater = true }

    end

    -- Which blessings do I know? Spell IDs are preferred; if no ID matches at
    -- all (the client may use new IDs) fall back to spellbook name lookups,
    -- and if that also finds nothing, assume everything is known rather than
    -- locking the player out.
    local function detect(check)
        local any, res, gres = false, {}, {}
        for key, b in pairs(ns.BLESSINGS) do
            local names = ns.spellNames[key]
            res[key] = check(b.spellId, names.single) or nil
            gres[key] = check(b.greaterId, names.greater) or false
            any = any or res[key] or gres[key]
        end
        return any, res, gres
    end
    local any, res, gres = detect(function(id) return KnowsSpellById(id) end)
    ns.knownMethod = "spell IDs"
    if not any then
        any, res, gres = detect(function(_, name) return KnowsSpellByName(name) end)
        ns.knownMethod = "spell names"
    end
    ns.knownDetectionFailed = (not any) and ns.isPaladin
    if ns.knownDetectionFailed then
        ns.knownMethod = "none (assuming all known)"
        for key in pairs(ns.BLESSINGS) do res[key] = true gres[key] = true end
    end
    wipe(ns.known)
    for key, b in pairs(ns.BLESSINGS) do
        ns.known[key] = res[key]
        b.greaterKnown = gres[key] and true or false
    end
end

function ns.BlessingSpell(key, greater)
    local n = ns.spellNames[key]
    if not n then return nil end
    return greater and n.greater or n.single
end

function ns.BlessingTexture(key, greater)
    local b = key and ns.BLESSINGS[key]
    if not b then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if greater then return b.greaterTexture or b.greaterIcon end
    return b.texture or b.icon
end

---------------------------------------------------------------------------
-- Camp buff definitions (built-in + user added)
---------------------------------------------------------------------------
-- The camp object's real icon: the item's icon (what players see on their
-- action bar), else the icon of the spell it casts.
function ns.CampIcon(c)
    if c.item then
        local fn = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon
        local ok, icon = SafeCall(fn, c.item)
        if ok and readable(icon) and icon then return icon end
    end
    if c.feature then return SpellTexture(c.feature) end
    return nil
end

function ns.CampList()
    local list = {}
    for _, c in ipairs(ns.CAMP_BUFFS) do
        -- The Camp Benefits tooltip names features in the client's language.
        -- Spell names may carry a rank suffix like "(Tier 1)"; drop it.
        if c.feature and c.localName == nil then
            local n = SpellName(c.feature)
            c.localName = n and (n:gsub("%s*%b()", "")) or false
        end
        if not c.resolvedIcon then c.resolvedIcon = ns.CampIcon(c) end
        list[#list + 1] = c
    end
    for _, c in ipairs(ns.gdb and ns.gdb.customCamp or {}) do list[#list + 1] = c end
    return list
end

---------------------------------------------------------------------------
-- Aura scanning
---------------------------------------------------------------------------
-- Calls fn(aura, index) for every helpful aura. Returns false if the data is
-- restricted (secret) right now, true otherwise.
local function ForEachHelpful(unit, fn)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 100 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok then return false end
            if not aura then break end
            if not readable(aura) or not readable(aura.name) then return false end
            fn(aura, i)
        end
        return true
    elseif UnitBuff then
        for i = 1, 40 do
            local ok, name, icon, _, _, duration, expirationTime, source, _, _, spellId = pcall(UnitBuff, unit, i)
            if not ok then return false end
            if not name then break end
            if not readable(name) then return false end
            fn({ name = name, icon = icon, duration = duration, expirationTime = expirationTime,
                 sourceUnit = source, spellId = spellId }, i)
        end
        return true
    end
    return false
end
ns.ForEachHelpful = ForEachHelpful

local function AuraIsMine(aura)
    if readable(aura.isFromPlayerOrPlayerPet) and aura.isFromPlayerOrPlayerPet then return true end
    local src = aura.sourceUnit
    if readable(src) and type(src) == "string" then
        local ok, same = pcall(UnitIsUnit, src, "player")
        if ok and readable(same) and same then return true end
    end
    return false
end

local function AuraCaster(aura)
    local src = aura.sourceUnit
    if readable(src) and type(src) == "string" then
        local ok, n = pcall(UnitName, src)
        if ok and readable(n) and n then return n end
    end
    return "another paladin"
end

local function AuraExpires(aura)
    local e = aura.expirationTime
    if readable(e) and type(e) == "number" and e > 0 then return e end
    return nil
end

-- Returns { ok, blessings = { KEY = { mine, greater, expires, caster } }, camps = { ... } }
-- Text lines of a buff's tooltip, or nil if they cannot be read.
local function AuraTooltipLines(unit, aura, index)
    if not C_TooltipInfo then return nil end
    local data
    local id = aura.auraInstanceID
    if C_TooltipInfo.GetUnitBuffByAuraInstanceID and readable(id) and id then
        local ok, d = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, unit, id, "HELPFUL")
        if ok and readable(d) and type(d) == "table" then data = d end
    end
    if not data and C_TooltipInfo.GetUnitAura and index then
        local ok, d = pcall(C_TooltipInfo.GetUnitAura, unit, index, "HELPFUL")
        if ok and readable(d) and type(d) == "table" then data = d end
    end
    if not data or not readable(data.lines) or type(data.lines) ~= "table" then return nil end
    local lines = {}
    for _, line in ipairs(data.lines) do
        if readable(line) and type(line) == "table" then
            for _, key in ipairs({ "leftText", "rightText" }) do
                local t = line[key]
                if readable(t) and type(t) == "string" and t ~= "" then lines[#lines + 1] = t end
            end
        end
    end
    return lines
end
ns.AuraTooltipLines = AuraTooltipLines

local UNREADABLE_CAMP = "Camp Benefits (unreadable)"

-- Returns { ok, blessings = { KEY = { mine, greater, expires, caster } }, camps = { ... } }
-- camps entries: { key, name, conflicts, icon, expires, unreadable }
function ns.ScanUnit(unit)
    local res = { blessings = {}, camps = {} }
    local campList = ns.CampList()
    local seenCamp = {}
    local function AddCamp(camp, aura, spellId, extra)
        local id = camp.name or camp.key
        if seenCamp[id] then return end
        seenCamp[id] = true
        local e = {
            key = camp.key, name = camp.name, conflicts = camp.conflicts,
            icon = camp.resolvedIcon or camp.icon or (readable(aura.icon) and aura.icon) or nil,
            expires = AuraExpires(aura), auraName = aura.name, spellId = spellId,
        }
        for k, v in pairs(extra or {}) do e[k] = v end
        res.camps[#res.camps + 1] = e
    end
    res.ok = ForEachHelpful(unit, function(aura, index)
        local spellId = readable(aura.spellId) and aura.spellId or nil
        -- WoW Forever bundles every camp feature into one "Camp Benefits"
        -- aura; its tooltip says which features are active.
        if Logic.IsCampContainer(aura.name, spellId, ns.CAMP_CONTAINER) then
            res.hasCampBenefits = true
            local lines = AuraTooltipLines(unit, aura, index)
            if lines then
                for _, camp in ipairs(Logic.MatchCampLines(lines, campList)) do AddCamp(camp, aura, spellId) end
            else
                -- Can't tell which features are on: assume every camp buff, so
                -- nothing gets overwritten by accident.
                AddCamp({ key = "CAMP_UNKNOWN", name = UNREADABLE_CAMP, conflicts = Logic.AllCampConflicts(campList),
                          icon = readable(aura.icon) and aura.icon or nil }, aura, spellId, { unreadable = true })
            end
            return
        end
        local camp = Logic.MatchCampBuff(aura.name, spellId, campList)
        if camp then
            AddCamp(camp, aura, spellId)
            return
        end
        local b = ns.blessingByName[aura.name:lower()]
        if b then
            local mine = AuraIsMine(aura)
            res.blessings[b.key] = {
                mine = mine, greater = b.greater, expires = AuraExpires(aura),
                caster = mine and UnitName("player") or AuraCaster(aura),
            }
        end
    end)
    return res
end

---------------------------------------------------------------------------
-- Talents / specialization -> role
---------------------------------------------------------------------------
function ns.GetTalentRole(unit, isInspect, class)
    class = class or select(2, UnitClass(unit))
    -- 1) Classic talent tabs: read actual points spent
    if GetTalentTabInfo then
        local n = 3
        if GetNumTalentTabs then
            local ok, c = pcall(GetNumTalentTabs, isInspect)
            if ok and type(c) == "number" and c > 0 then n = c end
        end
        local tabs = {}
        for i = 1, n do
            local r = { pcall(GetTalentTabInfo, i, isInspect) }
            if r[1] then
                -- Two known return layouts:
                --   name, icon, pointsSpent, ...            (Classic Era)
                --   id, name, desc, icon, pointsSpent, ...  (later Classic)
                local name, pts
                if type(r[2]) == "number" then name, pts = r[3], r[6] else name, pts = r[2], r[4] end
                tabs[i] = { name = readable(name) and name or ("Tree " .. i), points = readable(pts) and pts or 0 }
            else
                tabs[i] = { name = "Tree " .. i, points = 0 }
            end
        end
        local idx, summary = Logic.DominantTab(tabs)
        if idx then
            local roles = ns.TALENT_TAB_ROLES[class]
            local role = roles and roles[idx]
            if role then return role, string.format("%s %s", tabs[idx].name or "?", summary) end
        end
    end
    -- 2) Specialization API (if the client exposes one)
    local specId
    if isInspect then
        local ok, id = SafeCall(_G.GetInspectSpecialization, unit)
        if ok then specId = id end
    elseif GetSpecialization and GetSpecializationInfo then
        local ok, idx = pcall(GetSpecialization)
        if ok and readable(idx) and type(idx) == "number" and idx > 0 then
            local ok2, id = pcall(GetSpecializationInfo, idx)
            if ok2 then specId = id end
        end
    end
    if readable(specId) and type(specId) == "number" and specId > 0 and GetSpecializationInfoByID then
        local ok, _, name, _, _, role = pcall(GetSpecializationInfoByID, specId)
        if ok and readable(name) and name then
            local r = ns.SPEC_NAME_ROLES[name]
            if not r and role == "TANK" then r = "TANK" end
            if not r and role == "HEALER" then r = "HEALER" end
            if r and Logic.IsValidRole(class, r) then return r, name end
        end
    end
    return nil
end

-- Inspect queue: one player at a time, only out of combat.
local inspectQueue, inspectPending, inspectPendingAt = {}, nil, 0
local INSPECT_TTL = 15 * 60

local function QueueInspect(guid)
    if not guid or guid == UnitGUID("player") then return end
    local cached = ns.talentCache[guid]
    if cached and (GetTime() - cached.time) < INSPECT_TTL then return end
    for _, g in ipairs(inspectQueue) do if g == guid then return end end
    inspectQueue[#inspectQueue + 1] = guid
end
ns.QueueInspect = QueueInspect

local function ProcessInspectQueue()
    if ns.InCombat() then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    if inspectPending and GetTime() - inspectPendingAt < 5 then return end
    inspectPending = nil
    while #inspectQueue > 0 do
        local guid = table.remove(inspectQueue, 1)
        local st = ns.units[guid]
        local unit = st and st.unit
        if unit and UnitGUID(unit) == guid and UnitIsConnected(unit) and CanInspect and CanInspect(unit) then
            local ok = pcall(NotifyInspect, unit)
            if ok then
                inspectPending, inspectPendingAt = guid, GetTime()
                return
            end
        end
    end
end

local function OnInspectReady(guid)
    if not guid or guid ~= inspectPending then return end
    inspectPending = nil
    local st = ns.units[guid]
    if st and st.unit and UnitGUID(st.unit) == guid then
        local role, detail = ns.GetTalentRole(st.unit, true, st.class)
        ns.talentCache[guid] = { role = role, detail = detail, time = GetTime() }
    end
    if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then pcall(ClearInspectPlayer) end
    ns.RequestUpdate()
end

---------------------------------------------------------------------------
-- Roster and unit state
---------------------------------------------------------------------------
local function GroupUnits()
    local list = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do list[#list + 1] = "raid" .. i end
    else
        list[1] = "player"
        for i = 1, GetNumSubgroupMembers() do list[#list + 1] = "party" .. i end
    end
    return list
end

local function UnitFullName(unit)
    local ok, n = pcall(GetUnitName, unit, true)
    if ok and readable(n) and n then return n end
    local ok2, n2 = pcall(UnitName, unit)
    if ok2 and readable(n2) and n2 then return n2 end
    return nil
end
ns.UnitFullName = UnitFullName

local function InRange(unit, spell)
    if UnitIsUnit(unit, "player") then return true end
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    if spell then
        if C_Spell and C_Spell.IsSpellInRange then
            local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
            if ok and readable(r) and r ~= nil then return r == true or r == 1 end
        elseif IsSpellInRange then
            local ok, r = pcall(IsSpellInRange, spell, unit)
            if ok and readable(r) and r ~= nil then return r == 1 or r == true end
        end
    end
    if UnitInRange then
        local ok, r, checked = pcall(UnitInRange, unit)
        if ok and readable(r) and readable(checked) and checked then return r and true or false end
    end
    return true
end
ns.InRange = InRange

function ns.RebuildRoster()
    local seen = {}
    wipe(ns.order)
    for _, unit in ipairs(GroupUnits()) do
        local guid = UnitGUID(unit)
        if readable(guid) and guid and UnitExists(unit) and not seen[guid] then
            seen[guid] = true
            local st = ns.units[guid] or { guid = guid, aura = { blessings = {}, camps = {} } }
            st.unit = unit
            st.name = UnitFullName(unit) or st.name or "?"
            st.class = select(2, UnitClass(unit)) or st.class
            st.dirty = true
            ns.units[guid] = st
            ns.order[#ns.order + 1] = guid
            if st.class ~= "HUNTER" and st.class ~= "ROGUE" and st.class ~= "MAGE" and st.class ~= "WARLOCK" then
                QueueInspect(guid) -- single-role classes never need inspecting
            end
        end
    end
    for guid in pairs(ns.units) do
        if not seen[guid] then ns.units[guid] = nil end
    end
end

function ns.UnitByToken(unit)
    local guid = UnitGUID(unit)
    return readable(guid) and guid and ns.units[guid] or nil
end

local function UpdateUnitRole(st)
    local unit = st.unit
    local manual = ns.db.overrides[st.name]
    local groupRole
    if UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, unit)
        if ok and readable(r) then groupRole = r end
    end
    local talentRole, talentDetail
    if UnitIsUnit(unit, "player") then
        talentRole, talentDetail = ns.GetTalentRole("player", false, st.class)
    else
        local c = ns.talentCache[st.guid]
        if c then talentRole, talentDetail = c.role, c.detail end
    end
    st.groupRole, st.talentRole, st.talentDetail, st.manualRole = groupRole, talentRole, talentDetail, manual
    st.role, st.roleSource = Logic.ResolveRole(st.class, manual, groupRole, talentRole)
end

-- Work out what to cast on one player.
function ns.EvaluateUnit(st)
    local unit = st.unit
    if not unit or UnitGUID(unit) ~= st.guid then return end
    st.connected = UnitIsConnected(unit) and true or false
    st.dead = UnitIsDeadOrGhost(unit) and true or false

    if st.dirty and not ns.InCombat() then
        local scan = ns.ScanUnit(unit)
        if scan.ok then
            st.aura = scan
            st.stale = false
        else
            st.stale = true -- keep what we saw last
        end
        st.dirty = false
    end
    UpdateUnitRole(st)

    local now = GetTime()
    local aura = st.aura or { blessings = {}, camps = {} }
    local mine, taken = nil, {}
    for key, info in pairs(aura.blessings) do
        if info.mine then
            mine = { type = key, remaining = info.expires and (info.expires - now) or nil, greater = info.greater }
        else
            taken[key] = info.caster
        end
    end
    st.conflicts = Logic.ConflictMap(aura.camps)
    st.mine = mine
    st.priority = Logic.GetPriority(ns.db.assign, st.class, st.role)
    st.choice = Logic.ChooseBlessing(st.priority, {
        known = ns.known,
        conflicts = st.conflicts,
        taken = taken,
        mine = mine,
        protect = ns.opt.protectCamp,
        respectOthers = ns.opt.respectOthers,
        threshold = (ns.opt.refreshMinutes or 5) * 60,
    })
    local pend = ns.pending[st.guid]
    if pend and now - pend > 3 then ns.pending[st.guid] = nil pend = nil end
    st.isPending = pend and Logic.NEEDS_CAST[st.choice.status] or false
    local spell = st.choice.blessing and ns.BlessingSpell(st.choice.blessing, false)
    st.inRange = InRange(unit, spell or ns.BlessingSpell("MIGHT", false))
end

function ns.EvaluateAll()
    for _, guid in ipairs(ns.order) do
        local st = ns.units[guid]
        if st then ns.EvaluateUnit(st) end
    end
end

-- Members of one class, in roster order.
function ns.ClassMembers(class)
    local list = {}
    for _, guid in ipairs(ns.order) do
        local st = ns.units[guid]
        if st and st.class == class then list[#list + 1] = st end
    end
    return list
end

-- Who should the smart button bless next? Tanks first, then healers, then
-- everyone else in roster order. Only players that need something, are
-- alive, online and in range.
local SMART_ROLE_WEIGHT = { TANK = 1, HEALER = 2 }
function ns.NextSmartTarget()
    local best, bestWeight, bestIdx
    for i, guid in ipairs(ns.order) do
        local st = ns.units[guid]
        local c = st and st.choice
        if c and c.blessing and Logic.NEEDS_CAST[c.status] and not st.isPending
            and st.connected and not st.dead and st.inRange then
            local w = SMART_ROLE_WEIGHT[st.role] or 3
            if not best or w < bestWeight or (w == bestWeight and i < bestIdx) then
                best, bestWeight, bestIdx = st, w, i
            end
        end
    end
    return best
end

-- Count players that still need a blessing from me.
function ns.CountNeeding()
    local n = 0
    for _, guid in ipairs(ns.order) do
        local st = ns.units[guid]
        if st and st.choice and Logic.NEEDS_CAST[st.choice.status] then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Target warning & unit tooltip
---------------------------------------------------------------------------
local function CampSummary(unit)
    if not UnitIsPlayer(unit) then return nil end
    local scan = ns.ScanUnit(unit)
    if not scan.ok or #scan.camps == 0 then return nil end
    local parts = {}
    for _, c in ipairs(scan.camps) do
        local blocked = {}
        for _, b in ipairs(c.conflicts or {}) do blocked[#blocked + 1] = ns.BLESSINGS[b] and ns.BLESSINGS[b].short or b end
        parts[#parts + 1] = string.format("%s (no %s)", c.name, table.concat(blocked, "/"))
    end
    return table.concat(parts, ", ")
end

function ns.UpdateTargetWarning()
    ns.targetWarning = nil
    if ns.opt.warnTarget and not ns.InCombat() and UnitExists("target") and UnitIsPlayer("target")
        and UnitIsFriend("player", "target") then
        local s = CampSummary("target")
        if s then ns.targetWarning = string.format("%s: %s", UnitFullName("target") or "Target", s) end
    end
    if ns.UI then ns.UI:UpdateFooter() end
end

local function HookTooltip()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not ns.opt or not ns.opt.tooltip or ns.InCombat() or tooltip ~= GameTooltip then return end
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        if not ok or not readable(unit) or not unit then return end
        local s = CampSummary(unit)
        if s then tooltip:AddLine("|cfff5c542Camp:|r " .. s, 1, 1, 1, true) end
    end)
end

---------------------------------------------------------------------------
-- Update scheduling
---------------------------------------------------------------------------
local updateQueued = false
function ns.RequestUpdate(rebuild)
    if rebuild then ns.needRoster = true end
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.15, function()
        updateQueued = false
        ns.Update()
    end)
end

function ns.Update()
    if not ns.db or not ns.isPaladin then return end
    -- Aura data is restricted in combat and secure buttons cannot be changed:
    -- freeze until combat ends (PLAYER_REGEN_ENABLED triggers a full update).
    if ns.InCombat() then return end
    if ns.needRoster then
        ns.needRoster = false
        ns.RebuildRoster()
        if ns.UI then ns.UI:Layout() end
    end
    ns.EvaluateAll()
    if ns.UI then ns.UI:Refresh() end
    if ns.Config then ns.Config:RefreshPlayers() end
end

local function MarkAllDirty()
    for _, st in pairs(ns.units) do st.dirty = true end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function SafeRegister(event)
    pcall(CBB.RegisterEvent, CBB, event)
end

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    InitDB()
end

function handlers.PLAYER_LOGIN()
    if not ns.db then InitDB() end
    ns.isPaladin = select(2, UnitClass("player")) == "PALADIN"
    if not ns.isPaladin then
        Print("loaded, but you are not a paladin - the blessing bar stays hidden.")
        return
    end
    ns.RefreshSpells()
    HookTooltip()
    ns.UI:Create()
    if ns.Config then ns.Config:RegisterSettingsPanel() end
    ns.RequestUpdate(true)
    C_Timer.NewTicker(1, function()
        if ns.InCombat() then return end
        ProcessInspectQueue()
        ns.Update()
    end)
    if ns.knownDetectionFailed then
        Print("could not detect which blessings you know on this client - assuming all of them.")
    end
end

function handlers.GROUP_ROSTER_UPDATE() ns.RequestUpdate(true) end
handlers.PLAYER_ENTERING_WORLD = handlers.GROUP_ROSTER_UPDATE
handlers.PLAYER_ROLES_ASSIGNED = function() ns.RequestUpdate() end
handlers.UNIT_CONNECTION = function() ns.RequestUpdate() end

function handlers.UNIT_AURA(unit)
    if unit == "target" then ns.UpdateTargetWarning() end
    local st = ns.UnitByToken(unit)
    if st and st.unit == unit then
        st.dirty = true
        ns.RequestUpdate()
    end
end

function handlers.PLAYER_TARGET_CHANGED() ns.UpdateTargetWarning() end

function handlers.SPELLS_CHANGED()
    if not ns.isPaladin then return end
    ns.RefreshSpells()
    ns.RequestUpdate()
end
handlers.LEARNED_SPELL_IN_TAB = handlers.SPELLS_CHANGED

function handlers.CHARACTER_POINTS_CHANGED() ns.RequestUpdate() end
handlers.PLAYER_TALENT_UPDATE = handlers.CHARACTER_POINTS_CHANGED

function handlers.INSPECT_READY(guid) OnInspectReady(guid) end

-- Mark the target of a blessing we just cast as "pending" so the smart
-- button moves on to the next player before the aura shows up.
function handlers.UNIT_SPELLCAST_SENT(unit, target, _, spellId)
    if unit ~= "player" or not readable(target) or type(target) ~= "string" or target == "" then return end
    local isBlessing = false
    if readable(spellId) and spellId then
        local n = SpellName(spellId)
        isBlessing = n and ns.blessingByName[n:lower()] and true or false
    end
    if not isBlessing then return end
    local now = GetTime()
    for guid, st in pairs(ns.units) do
        local short = st.name and st.name:match("^[^-]+")
        if st.name == target or short == target then
            ns.pending[guid] = now
            st.isPending = true
        end
    end
    ns.RequestUpdate()
end

function handlers.PLAYER_REGEN_DISABLED()
    if ns.UI then ns.UI:SetCombat(true) end
end

function handlers.PLAYER_REGEN_ENABLED()
    if ns.isPaladin and ns.UI and not ns.UI.main then ns.UI:Create() end
    MarkAllDirty()
    if ns.UI then ns.UI:SetCombat(false) ns.UI:CloseFlyouts() end
    ns.RequestUpdate(true)
    ns.UpdateTargetWarning()
end

CBB:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then h(...) end
end)
for event in pairs(handlers) do SafeRegister(event) end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ParseBlessing(s)
    if not s then return nil end
    s = s:upper()
    for _, k in ipairs(ns.BLESSING_ORDER) do
        if k == s or k:sub(1, #s) == s then return k end
    end
    return nil
end

local function ParseRole(s)
    if not s then return nil end
    s = s:upper()
    local aliases = { HEAL = "HEALER", HEALS = "HEALER", MDPS = "MELEE", RDPS = "RANGED", CDPS = "CASTER",
                      DPS = "MELEE", CASTERDPS = "CASTER", MELEEDPS = "MELEE" }
    s = aliases[s] or s
    for _, r in ipairs(ns.ROLE_ORDER) do if r == s then return r end end
    return nil
end

local function DumpAuras(unit)
    if not UnitExists(unit) then Print("no unit '%s'", unit) return end
    Print("helpful auras on %s:", UnitFullName(unit) or unit)
    local campList = ns.CampList()
    local ok = ForEachHelpful(unit, function(a, index)
        local id = readable(a.spellId) and a.spellId or "?"
        local tag = ""
        if Logic.MatchCampBuff(a.name, readable(a.spellId) and a.spellId or nil, campList) then
            tag = " |cff40ff40[camp buff]|r"
        elseif ns.blessingByName[a.name:lower()] then
            tag = AuraIsMine(a) and " |cfff5c542[my blessing]|r" or " |cfff5c542[blessing]|r"
        end
        local isContainer = Logic.IsCampContainer(a.name, readable(a.spellId) and a.spellId or nil, ns.CAMP_CONTAINER)
        if isContainer then tag = " |cff40ff40[camp benefits]|r" end
        local exp = AuraExpires(a)
        Print("  %s  (spellId %s)%s %s", a.name, tostring(id), tag, exp and Logic.FormatTime(exp - GetTime()) or "")
        if isContainer then
            local lines = AuraTooltipLines(unit, a, index)
            if not lines then
                Print("    |cffff6060tooltip could not be read - treating Kings/Might/Wisdom as blocked|r")
            else
                local matched = {}
                for _, c in ipairs(Logic.MatchCampLines(lines, campList)) do matched[#matched + 1] = c.name end
                for _, l in ipairs(lines) do Print("    | %s", l) end
                Print("    -> recognised: %s", #matched > 0 and table.concat(matched, ", ") or "nothing that blocks a blessing")
            end
        end
    end)
    if not ok then Print("  aura data is restricted right now (combat?) - try again out of combat.") end
end

local function Help()
    Print("commands:")
    Print("  /cbb - show / hide the blessing bar")
    Print("  /cbb config - settings (Blessings / Players / Options)")
    Print("  /cbb players - set up roles for your group")
    Print("  /cbb lock - lock / unlock the bar")
    Print("  /cbb role <player> <auto|tank|healer|melee|ranged|caster> - set a player's role")
    Print("  /cbb roles - list detected roles")
    Print("  /cbb auras [unit] - list buffs + spell IDs on target (to identify camp buffs)")
    Print("  /cbb camp list | add <spellId|name> <blessing> | del <n> - manage camp buffs")
    Print("  /cbb refresh <minutes> - refresh warning threshold")
    Print("  /cbb scale <0.5-2> - bar scale")
    Print("  /cbb reset - reset assignments to defaults")
end

SLASH_CAMELUSBETTERBLESSINGS1 = "/cbb"
SLASH_CAMELUSBETTERBLESSINGS2 = "/betterblessings"
SlashCmdList.CAMELUSBETTERBLESSINGS = function(msg)
    if not ns.db then return end
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        if not ns.isPaladin then Print("only paladins get a blessing bar.") return end
        ns.opt.hidden = not ns.opt.hidden
        if ns.UI then ns.UI:UpdateVisibility() end
    elseif cmd == "config" or cmd == "options" or cmd == "assign" or cmd == "settings" then
        if ns.Config then ns.Config:Toggle() end
    elseif cmd == "players" then
        if ns.Config then ns.Config:Toggle("players") end
    elseif cmd == "lock" then
        ns.opt.locked = not ns.opt.locked
        Print("bar %s.", ns.opt.locked and "locked" or "unlocked")
    elseif cmd == "role" then
        local name, role = rest:match("^(.-)%s+(%S+)$")
        if not name or name == "" then Print("usage: /cbb role <player> <auto|tank|healer|melee|ranged|caster>") return end
        local target
        for _, st in pairs(ns.units) do
            if st.name:lower() == name:lower() or (st.name:match("^[^-]+") or ""):lower() == name:lower() then target = st end
        end
        local key = target and target.name or name
        if role:lower() == "auto" then
            ns.db.overrides[key] = nil
            Print("%s: role back to automatic.", key)
        else
            local r = ParseRole(role)
            if not r then Print("unknown role '%s'", role) return end
            if target and not Logic.IsValidRole(target.class, r) then
                Print("%s cannot be %s.", key, ns.ROLE_INFO[r].label) return
            end
            ns.db.overrides[key] = r
            Print("%s is now %s.", key, ns.ROLE_INFO[r].label)
        end
        ns.RequestUpdate()
    elseif cmd == "roles" then
        ns.EvaluateAll()
        for _, guid in ipairs(ns.order) do
            local st = ns.units[guid]
            Print("  %s (%s): %s via %s%s", st.name, st.class or "?", st.role or "?", st.roleSource or "?",
                st.talentDetail and (" - " .. st.talentDetail) or "")
        end
    elseif cmd == "auras" then
        local unit = rest ~= "" and rest or (UnitExists("target") and "target" or "player")
        DumpAuras(unit)
    elseif cmd == "camp" then
        local sub, args = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        if sub == "" or sub == "list" then
            Print("camp buffs that block blessings:")
            for i, c in ipairs(ns.CampList()) do
                local custom = i > #ns.CAMP_BUFFS
                Print("  %d. %s -> blocks %s%s", i, c.name, table.concat(c.conflicts or {}, ", "), custom and " (custom)" or "")
            end
        elseif sub == "add" then
            local what, bless = args:match("^(.-)%s+(%S+)$")
            local b = ParseBlessing(bless)
            if not what or what == "" or not b then Print("usage: /cbb camp add <spellId|aura name> <might|wisdom|kings>") return end
            local entry = { key = "CUSTOM", conflicts = { b }, icon = "Interface\\Icons\\INV_Misc_QuestionMark" }
            local id = tonumber(what)
            if id then
                entry.spellIds, entry.match, entry.name = { id }, {}, SpellName(id) or ("spell " .. id)
            else
                what = what:gsub('^"(.*)"$', "%1")
                entry.spellIds, entry.match, entry.name = {}, { what:lower() }, what
            end
            table.insert(ns.gdb.customCamp, entry)
            Print("added camp buff '%s' (blocks %s).", entry.name, ns.BLESSINGS[b].short)
            MarkAllDirty() ns.RequestUpdate()
        elseif sub == "del" or sub == "remove" then
            local n = tonumber(args)
            local idx = n and (n - #ns.CAMP_BUFFS)
            if not idx or idx < 1 or not ns.gdb.customCamp[idx] then Print("only custom entries can be removed - see /cbb camp list") return end
            local e = table.remove(ns.gdb.customCamp, idx)
            Print("removed '%s'.", e.name)
            MarkAllDirty() ns.RequestUpdate()
        else
            Help()
        end
    elseif cmd == "refresh" then
        local m = tonumber(rest)
        if m and m >= 0 and m <= 60 then ns.opt.refreshMinutes = m Print("refresh threshold: %d min.", m) ns.RequestUpdate()
        else Print("usage: /cbb refresh <0-60>") end
    elseif cmd == "scale" then
        local s = tonumber(rest)
        if s and s >= 0.5 and s <= 2 then ns.opt.scale = s if ns.UI then ns.UI:ApplyScale() end
        else Print("usage: /cbb scale <0.5-2>") end
    elseif cmd == "reset" then
        wipe(ns.db.assign) wipe(ns.db.greater)
        Print("assignments reset to defaults.")
        ns.RequestUpdate()
        if ns.Config then ns.Config:Refresh() end
    else
        Help()
    end
end
