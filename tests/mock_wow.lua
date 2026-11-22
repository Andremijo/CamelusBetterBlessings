-- Minimal fake WoW API: enough to load the addon and drive it from tests.
-- Unknown frame methods are no-ops, so this only catches logic / nil errors.
local M = {}
M.frames = {}
M.timers = {}
M.now = 1000
M.combat = false
M.units = {}      -- token -> { guid, name, class, role, auras = {...}, talents = {a,b,c}, connected, dead }
M.known = {}      -- spellId -> true
M.chat = {}

local function newObject(kind, name)
    local o = { _kind = kind, _name = name, _attrs = {}, _scripts = {}, _hooks = {}, _shown = kind ~= "Frame-hidden",
                _width = 0, _height = 0, _events = {}, _text = "" }
    return setmetatable(o, { __index = function(t, k)
        local f = M.methods[k]
        if f then return f end
        return function() end
    end })
end

M.methods = {
    SetAttribute = function(self, k, v) self._attrs[k] = v end,
    GetAttribute = function(self, k) return self._attrs[k] end,
    SetScript = function(self, k, fn) self._scripts[k] = fn end,
    GetScript = function(self, k) return self._scripts[k] end,
    HookScript = function(self, k, fn) self._hooks[k] = self._hooks[k] or {}; table.insert(self._hooks[k], fn) end,
    RegisterEvent = function(self, e) self._events[e] = true end,
    Show = function(self) self._shown = true end,
    Hide = function(self) self._shown = false end,
    SetShown = function(self, v) self._shown = v and true or false end,
    IsShown = function(self) return self._shown end,
    SetSize = function(self, w, h) self._width, self._height = w, h end,
    SetWidth = function(self, w) self._width = w end,
    SetHeight = function(self, h) self._height = h end,
    GetWidth = function(self) return self._width end,
    GetHeight = function(self) return self._height end,
    GetPoint = function() return "CENTER", nil, "CENTER", 10, 20 end,
    GetFrameLevel = function() return 1 end,
    GetStringHeight = function() return 12 end,
    SetText = function(self, t) self._text = t end,
    GetText = function(self) return self._text end,
    SetTexture = function(self, t) self._texture = t end,
    SetChecked = function(self, v) self._checked = v end,
    GetChecked = function(self) return self._checked end,
    CreateTexture = function(self) return newObject("Texture") end,
    CreateFontString = function(self) return newObject("FontString") end,
    SetAtlas = function() end,
}

function M.install()
    _G.CreateFrame = function(kind, name, parent, template)
        local o = newObject(kind, name)
        o._template = template
        o._parent = parent
        if kind == "Button" and template == "SecureActionButtonTemplate" then o._secure = true end
        if name then _G[name] = o; M.frames[name] = o end
        table.insert(M.frames, o)
        return o
    end
    _G.UIParent = newObject("Frame", "UIParent")
    _G.GameTooltip = newObject("GameTooltip", "GameTooltip")
    _G.GameTooltip.GetOwner = function() return nil end
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(M.chat, msg) end }
    _G.GetTime = function() return M.now end
    _G.C_Timer = {
        After = function(_, fn) table.insert(M.timers, fn) end,
        NewTicker = function(_, fn) M.ticker = fn; return {} end,
    }
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.tinsert = table.insert
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.InCombatLockdown = function() return M.combat end
    _G.UnitAffectingCombat = function() return M.combat end
    _G.IsShiftKeyDown = function() return false end
    _G.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    _G.LOCALIZED_CLASS_NAMES_MALE = nil

    local function U(token) return M.units[token] end
    local function resolve(token)
        if M.units[token] then return M.units[token] end
        if token == "target" and M.target then return M.units[M.target] end
        return nil
    end
    _G.UnitExists = function(t) return resolve(t) ~= nil end
    _G.UnitGUID = function(t) local u = resolve(t) return u and u.guid end
    _G.UnitName = function(t) local u = resolve(t) return u and u.name end
    _G.GetUnitName = function(t) local u = resolve(t) return u and u.name end
    _G.UnitClass = function(t) local u = resolve(t) if u then return u.class, u.class end end
    _G.UnitIsUnit = function(a, b) local x, y = resolve(a), resolve(b) return x ~= nil and x == y end
    _G.UnitIsConnected = function(t) local u = resolve(t) return u and u.connected ~= false end
    _G.UnitIsDeadOrGhost = function(t) local u = resolve(t) return u and u.dead or false end
    _G.UnitIsPlayer = function(t) return resolve(t) ~= nil end
    _G.UnitIsFriend = function() return true end
    _G.UnitIsVisible = function() return true end
    _G.UnitInRange = function() return true, true end
    _G.UnitGroupRolesAssigned = function(t) local u = resolve(t) return u and u.role or "NONE" end
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() local n = 0 for k in pairs(M.units) do if k:match("^party") then n = n + 1 end end return n > 0 end
    _G.GetNumSubgroupMembers = function() local n = 0 for k in pairs(M.units) do if k:match("^party") then n = n + 1 end end return n end
    _G.GetNumGroupMembers = function() return _G.GetNumSubgroupMembers() + 1 end

    local spellNames = {
        [19740] = "Blessing of Might", [25782] = "Greater Blessing of Might",
        [19742] = "Blessing of Wisdom", [25894] = "Greater Blessing of Wisdom",
        [20217] = "Blessing of Kings", [25898] = "Greater Blessing of Kings",
        [1038] = "Blessing of Salvation", [25895] = "Greater Blessing of Salvation",
        [19977] = "Blessing of Light", [25890] = "Greater Blessing of Light",
        [20911] = "Blessing of Sanctuary", [25899] = "Greater Blessing of Sanctuary",
    }
    M.spellNames = spellNames
    _G.C_Spell = {
        GetSpellName = function(id) return spellNames[id] end,
        GetSpellTexture = function(id) return spellNames[id] and ("tex:" .. id) end,
        IsSpellInRange = function() return true end,
        GetSpellInfo = function() return nil end,
    }
    _G.IsPlayerSpell = function(id) return M.known[id] or false end

    _G.C_UnitAuras = {
        GetAuraDataByIndex = function(t, i)
            local u = resolve(t)
            if M.combat and M.secretInCombat then error("secret") end
            return u and u.auras and u.auras[i]
        end,
    }

    M.inspecting = nil
    _G.CanInspect = function() return true end
    _G.NotifyInspect = function(t) M.inspecting = t end
    _G.ClearInspectPlayer = function() end
    _G.GetNumTalentTabs = function() return 3 end
    _G.GetTalentTabInfo = function(i, isInspect)
        local u = isInspect and M.units[M.inspecting] or M.units.player
        local pts = u and u.talents and u.talents[i] or 0
        return "Tree" .. i, "icon", pts, "file"
    end
end

function M.flush()
    local guard = 0
    while #M.timers > 0 and guard < 100 do
        local list = M.timers
        M.timers = {}
        for _, fn in ipairs(list) do fn() end
        guard = guard + 1
    end
end

function M.fire(event, ...)
    local core = M.frames.CamelusBetterBlessingsCore
    core._scripts.OnEvent(core, event, ...)
end

function M.load(dir, files, ns)
    for _, f in ipairs(files) do
        local chunk = assert(loadfile(dir .. "/" .. f))
        chunk("CamelusBetterBlessings", ns)
    end
end

function M.aura(name, opts)
    opts = opts or {}
    return { name = name, spellId = opts.spellId, sourceUnit = opts.source, expirationTime = opts.expires or (M.now + 3000),
             isFromPlayerOrPlayerPet = opts.mine or false, icon = "icon" }
end

return M
