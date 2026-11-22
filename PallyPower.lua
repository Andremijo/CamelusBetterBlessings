-- Camelus' Better Blessings - reading Pally Power assignments (read-only)
--
-- Pally Power (and compatible addons such as Lightbound) share blessing
-- assignments over the addon-message prefix "PLPWR". This module only LISTENS:
-- it asks the group for their assignments ("REQ", the same request Pally
-- Power sends) and parses the replies. It never sends assignments, so other
-- paladins do not see this addon as a Pally Power user.
--
-- Wire format (numbers as Pally Power uses them on WoW Forever):
--   blessings 1 Wisdom, 2 Might, 3 Kings (4-6 Salvation/Light/Sanctuary are
--             removed on Forever and ignored)
--   classes   1 Warrior, 2 Rogue, 3 Priest, 4 Druid, 5 Paladin, 6 Hunter,
--             7 Mage, 8 Warlock, 9 Shaman
--   SELF <ranks>@<digit per class>      a paladin's own row ('n' = none)
--   ASSIGN <paladin> <class> <blessing> one cell
--   PASSIGN <paladin>@<digit per class> a whole row
--   MASSIGN <paladin> <blessing>        every class
--   NASSIGN <pal> <class> <target> <blessing>[@...]  single-target overrides
--   CLEAR [SKIP]                        leader clears all / others their own
--   ... FREEASSIGN YES|NO ...           "others may change my row"
local _, ns = ...
local Logic = ns.Logic

local PP = {}
ns.PP = PP

local PREFIX = "PLPWR"
local NUM_CLASSES = 9
PP.CLASS_BY_ID = { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
PP.ID_BY_CLASS = {}
for i, c in ipairs(PP.CLASS_BY_ID) do PP.ID_BY_CLASS[c] = i end
PP.BLESSING_BY_ID = { "WISDOM", "MIGHT", "KINGS" } -- 4-6 no longer exist on Forever

local issecret = _G.issecretvalue or function() return false end
local function readable(v) return v ~= nil and not issecret(v) end

-- Saved data: { rows = {[paladin] = {[cid] = idx}}, normal = {[paladin] = {[cid] = {[target] = idx}}},
--               free = {[paladin] = true}, seen = {[paladin] = time} }
local function Data()
    local db = ns.db
    db.pp = db.pp or {}
    local d = db.pp
    d.rows = d.rows or {}
    d.normal = d.normal or {}
    d.free = d.free or {}
    d.seen = d.seen or {}
    return d
end
PP.Data = Data

---------------------------------------------------------------------------
-- names
---------------------------------------------------------------------------
-- Pally Power drops the realm for players on your own realm.
local function Normalize(name)
    if not readable(name) or type(name) ~= "string" or name == "" then return nil end
    if Ambiguate then
        local ok, s = pcall(Ambiguate, name, "none")
        if ok and readable(s) and s then name = s end
    end
    return name
end
PP.Normalize = Normalize

function PP.Me()
    local ok, n = pcall(GetUnitName, "player", false)
    if ok and readable(n) and n then return n end
    return UnitName("player")
end

local function SameName(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local sa, sb = a:match("^[^-]+"), b:match("^[^-]+")
    return sa == sb and (not a:find("-", 1, true) or not b:find("-", 1, true))
end
PP.SameName = SameName

local function InGroup(name)
    if not name then return false end
    if SameName(name, PP.Me()) then return true end
    for _, key in ipairs({ "UnitInRaid", "UnitInParty" }) do
        local fn = _G[key]
        if fn then
            local ok, r = pcall(fn, name)
            if ok and readable(r) and r then return true end
        end
    end
    for _, st in pairs(ns.units or {}) do
        if SameName(st.name, name) then return true end
    end
    return false
end
PP.InGroup = InGroup

local function IsLeader(name)
    for _, key in ipairs({ "UnitIsGroupLeader", "UnitIsGroupAssistant" }) do
        local fn = _G[key]
        if fn then
            local ok, r = pcall(fn, name)
            if ok and readable(r) and r then return true end
        end
    end
    return false
end

local function Digits(s)
    local t = {}
    for i = 1, NUM_CLASSES do
        local v = tonumber(s and s:sub(i, i) or "") or 0
        t[i] = (v >= 1 and v <= 6) and v or 0
    end
    return t
end

---------------------------------------------------------------------------
-- receiving
---------------------------------------------------------------------------
local function Changed()
    if ns.RequestUpdate then ns.RequestUpdate() end
    if ns.Config and ns.Config.RefreshPallyPower then ns.Config:RefreshPallyPower() end
end

function PP.Parse(sender, msg)
    sender = Normalize(sender)
    if not sender or not readable(msg) or type(msg) ~= "string" then return end
    if SameName(sender, PP.Me()) then return end
    if not InGroup(sender) then return end
    local d = Data()
    local leader = IsLeader(sender)
    -- who may change whose row: themselves, the leader/assistants, or anyone
    -- if that paladin allows it (FREEASSIGN)
    local function allowed(name)
        return SameName(name, sender) or leader or d.free[name] or false
    end

    if msg == "REQ" or msg:find("^PPLEADER") then return end

    local _, assign = msg:match("^SELF ([0-9a-fn]*)@([0-9n]*)")
    if assign then
        d.rows[sender] = Digits(assign)
        d.seen[sender] = time and time() or 0
        Changed()
        return
    end
    local name, cid, idx = msg:match("^ASSIGN (.+) (%d+) (%d+)$")
    if name then
        name, cid, idx = Normalize(name), tonumber(cid), tonumber(idx)
        if name and allowed(name) and cid and cid >= 1 and cid <= NUM_CLASSES and idx then
            d.rows[name] = d.rows[name] or Digits(nil)
            d.rows[name][cid] = idx
            Changed()
        end
        return
    end
    local pname, row = msg:match("^PASSIGN (.+)@([0-9n]*)$")
    if pname then
        pname = Normalize(pname)
        if pname and allowed(pname) then d.rows[pname] = Digits(row) Changed() end
        return
    end
    local mname, midx = msg:match("^MASSIGN (.+) (%d+)$")
    if mname then
        mname, midx = Normalize(mname), tonumber(midx)
        if mname and allowed(mname) and midx then
            local r = {}
            for i = 1, NUM_CLASSES do r[i] = midx end
            d.rows[mname] = r
            Changed()
        end
        return
    end
    if msg:find("^NASSIGN ") then
        for pn, c, tn, sk in msg:sub(9):gmatch("([^@]*) ([^@]*) ([^@]*) ([^@]*)") do
            pn = Normalize((pn:gsub("_", " ")))
            c, sk = tonumber(c), tonumber(sk)
            tn = Normalize((tn:gsub("_", " ")))
            if pn and tn and allowed(pn) and c and c >= 1 and c <= NUM_CLASSES then
                d.normal[pn] = d.normal[pn] or {}
                d.normal[pn][c] = d.normal[pn][c] or {}
                d.normal[pn][c][tn] = (sk and sk > 0) and sk or nil
            end
        end
        Changed()
        return
    end
    if msg:find("^CLEAR") then
        if leader then
            wipe(d.rows) wipe(d.normal)
        else
            d.rows[sender], d.normal[sender] = nil, nil
        end
        Changed()
        return
    end
    if msg:find("FREEASSIGN YES") then d.free[sender] = true end
    if msg:find("FREEASSIGN NO") then d.free[sender] = nil end
end

---------------------------------------------------------------------------
-- asking the group for their assignments
---------------------------------------------------------------------------
local lastReq = 0

local function Channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        and IsInInstance and IsInInstance() then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    return "PARTY"
end

local function PallyPowerLoaded()
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if not fn then return false end
    local ok, r = pcall(fn, "PallyPower")
    return ok and r and true or false
end
PP.PallyPowerLoaded = PallyPowerLoaded

-- force: the "Request update" button (ignores the throttle and Pally Power itself)
function PP.Request(force)
    if not IsInGroup() then return false end
    if not force and PallyPowerLoaded() then return false end -- Pally Power asks by itself
    local now = GetTime()
    if not force and now - lastReq < 10 then return false end
    lastReq = now
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "REQ", Channel())
    return ok
end

---------------------------------------------------------------------------
-- what the assignments mean for this addon
---------------------------------------------------------------------------
local function BlessingFor(paladin, class, target)
    local d = Data()
    local cid = PP.ID_BY_CLASS[class]
    if not cid then return nil end
    local n = d.normal[paladin] and d.normal[paladin][cid]
    if n and target then
        for tname, idx in pairs(n) do
            if SameName(tname, target) then return PP.BLESSING_BY_ID[idx], true end
        end
    end
    local row = d.rows[paladin]
    local idx = row and row[cid]
    return idx and PP.BLESSING_BY_ID[idx] or nil, false
end
PP.BlessingFor = BlessingFor

local function MyRowKey()
    local d, me = Data(), PP.Me()
    for name in pairs(d.rows) do if SameName(name, me) then return name end end
    for name in pairs(d.normal) do if SameName(name, me) then return name end end
    return me
end

-- Pally Power's assignment for ME on this player (single-target first, then class).
function PP.MyAssignment(class, target)
    return BlessingFor(MyRowKey(), class, target)
end

-- Put my Pally Power assignment first in a player's priority list.
function PP.ApplyPriority(st, priority)
    if not ns.opt.followPP or not st then return priority, nil end
    local b = PP.MyAssignment(st.class, st.name)
    if not b or not ns.BLESSINGS[b] then return priority, nil end
    local out = { b }
    for i = 1, ns.MAX_PRIORITY do
        local p = priority and priority[i]
        if p and p ~= b and #out < ns.MAX_PRIORITY then out[#out + 1] = p end
    end
    for i = #out + 1, ns.MAX_PRIORITY do out[i] = false end
    return out, b
end

-- My Greater Blessing for a class according to Pally Power (or nil).
function PP.MyGreater(class)
    if not ns.opt.followPP then return nil end
    local row = Data().rows[MyRowKey()]
    local idx = row and row[PP.ID_BY_CLASS[class]]
    local b = idx and PP.BLESSING_BY_ID[idx]
    return (b and ns.BLESSINGS[b]) and b or nil
end

-- Blessings other paladins in the group are assigned to give this player.
-- Returns { BLESSING = "Name (Pally Power)" }.
function PP.PlannedByOthers(st)
    local out = {}
    if not st then return out end
    local d, me = Data(), PP.Me()
    local names = {}
    for name in pairs(d.rows) do names[name] = true end
    for name in pairs(d.normal) do names[name] = true end
    for name in pairs(names) do
        if not SameName(name, me) and InGroup(name) then
            local b = BlessingFor(name, st.class, st.name)
            if b and ns.BLESSINGS[b] and not out[b] then out[b] = ns.ShortName and ns.ShortName(name) .. " (Pally Power)" or name end
        end
    end
    return out
end

-- Paladins with assignments that are in the group now (for the settings tab).
function PP.Paladins()
    local d, me, list = Data(), PP.Me(), {}
    local seen = {}
    for _, t in ipairs({ d.rows, d.normal }) do
        for name in pairs(t) do
            if not seen[name] and InGroup(name) then
                seen[name] = true
                list[#list + 1] = { name = name, isMe = SameName(name, me) }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.isMe ~= b.isMe then return a.isMe end
        return a.name < b.name
    end)
    return list
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
PP.frame = frame
frame:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "CHAT_MSG_ADDON" then
        if not readable(prefix) or prefix ~= PREFIX then return end
        if not ns.db then return end
        PP.Parse(sender, msg)
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        end
        C_Timer.After(3, function() PP.Request() end)
    elseif event == "GROUP_JOINED" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if IsInGroup() then C_Timer.After(2, function() PP.Request() end) end
    end
end)
for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_LOGIN", "GROUP_JOINED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    pcall(frame.RegisterEvent, frame, e)
end
