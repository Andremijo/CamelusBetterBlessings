-- Camelus' Better Blessings - decision logic
-- Pure functions only (no WoW API calls) so they can be unit tested outside the game.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

function Logic.IsValidRole(class, role)
    local list = ns.CLASS_ROLES[class]
    if not list or not role then return false end
    for _, r in ipairs(list) do
        if r == role then return true end
    end
    return false
end

-- Decide a player's role.
--   manual     : role picked by you (right-click on the bar / /cbb role)
--   groupRole  : UnitGroupRolesAssigned() result (TANK / HEALER / DAMAGER / NONE)
--   talentRole : role derived from inspected talents
-- Returns role, source ("manual", "group", "talents", "group+class", "class")
function Logic.ResolveRole(class, manual, groupRole, talentRole)
    if manual and Logic.IsValidRole(class, manual) then
        return manual, "manual"
    end
    if (groupRole == "TANK" or groupRole == "HEALER") and Logic.IsValidRole(class, groupRole) then
        return groupRole, "group"
    end
    if talentRole and Logic.IsValidRole(class, talentRole) then
        -- Group says DPS but talents point at a tank/heal tree: the group wins,
        -- we only use talents to pick melee vs caster.
        if groupRole == "DAMAGER" and (talentRole == "TANK" or talentRole == "HEALER") then
            return ns.CLASS_DEFAULT_DPS[class] or "MELEE", "group+class"
        end
        return talentRole, "talents"
    end
    if groupRole == "DAMAGER" then
        return ns.CLASS_DEFAULT_DPS[class] or "MELEE", "group+class"
    end
    return ns.CLASS_DEFAULT_ROLE[class] or "MELEE", "class"
end

function Logic.AssignKey(class, role)
    return (class or "?") .. ":" .. (role or "?")
end

function Logic.DefaultPriority(class, role)
    local p = ns.DEFAULT_CLASS_ROLE_PRIORITY[Logic.AssignKey(class, role)] or ns.DEFAULT_ROLE_PRIORITY[role]
    local copy = {}
    for i = 1, ns.MAX_PRIORITY do copy[i] = p and p[i] or false end
    return copy
end

-- assign: the saved table { ["CLASS:ROLE"] = { "KINGS", "MIGHT", false, false } }
function Logic.GetPriority(assign, class, role)
    local p = assign and assign[Logic.AssignKey(class, role)]
    if p then return p end
    return Logic.DefaultPriority(class, role)
end

-- Pick the blessing to give one player.
-- priority : list of blessing keys (false = empty slot)
-- ctx:
--   known         : { KEY = true } blessings I can cast (nil = assume all)
--   conflicts     : { KEY = "Fish Bowl" } blessings that would replace a camp buff on this player
--   taken         : { KEY = "Otherpally" } blessings another paladin already gave this player
--   mine          : { type = KEY, remaining = seconds|nil } my current blessing on this player
--   protect       : honour camp buffs (default true)
--   respectOthers : honour other paladins' blessings (default true)
--   threshold     : seconds; my blessing below this counts as needing a refresh
-- Returns { blessing, rank, status, remaining, skipped = { {blessing, reason, detail} } }
--   status: OK | REFRESH | MISSING | SWAP | BLOCKED (camp buffs block everything) | NONE
function Logic.ChooseBlessing(priority, ctx)
    ctx = ctx or {}
    local skipped = {}
    local campBlocked = false
    local seen = {}
    local mine = ctx.mine
    for i = 1, ns.MAX_PRIORITY do
        local b = priority and priority[i]
        if b and ns.BLESSINGS[b] and not seen[b] then
            seen[b] = true
            if ctx.known and not ctx.known[b] then
                skipped[#skipped + 1] = { blessing = b, reason = "unknown" }
            elseif ctx.protect ~= false and ctx.conflicts and ctx.conflicts[b] then
                campBlocked = true
                skipped[#skipped + 1] = { blessing = b, reason = "camp", detail = ctx.conflicts[b] }
            elseif ctx.respectOthers ~= false and ctx.taken and ctx.taken[b] and not (mine and mine.type == b) then
                skipped[#skipped + 1] = { blessing = b, reason = "taken", detail = ctx.taken[b] }
            else
                local result = { blessing = b, rank = i, skipped = skipped }
                if mine and mine.type == b then
                    result.remaining = mine.remaining
                    if mine.remaining and ctx.threshold and mine.remaining <= ctx.threshold then
                        result.status = "REFRESH"
                    else
                        result.status = "OK"
                    end
                elseif mine and mine.type then
                    result.status = "SWAP"
                else
                    result.status = "MISSING"
                end
                return result
            end
        end
    end
    return { status = campBlocked and "BLOCKED" or "NONE", skipped = skipped }
end

-- Statuses where clicking would do something useful.
Logic.NEEDS_CAST = { MISSING = true, SWAP = true, REFRESH = true }

-- Would a Greater Blessing replace a camp buff on any member of the class?
-- members: list of { name = "Bob", conflicts = { KINGS = "Fish Bowl" } }
-- Returns a list of { name, camp } (empty = safe).
function Logic.GreaterConflicts(blessing, members)
    local out = {}
    if not blessing then return out end
    for _, m in ipairs(members or {}) do
        local camp = m.conflicts and m.conflicts[blessing]
        if camp then out[#out + 1] = { name = m.name, camp = camp } end
    end
    return out
end

-- Find which camp buff (if any) an aura is.
-- campList: list of camp buff definitions (see Data.lua)
function Logic.MatchCampBuff(auraName, spellId, campList)
    if not campList then return nil end
    if spellId then
        for _, c in ipairs(campList) do
            for _, id in ipairs(c.spellIds or {}) do
                if id == spellId then return c end
            end
        end
    end
    if type(auraName) == "string" then
        local lower = auraName:lower()
        for _, c in ipairs(campList) do
            for _, m in ipairs(c.match or {}) do
                if m ~= "" and lower:find(m, 1, true) then return c end
            end
        end
    end
    return nil
end

-- Turn a list of camp buffs on a player into { BLESSING = "Camp buff name" }.
function Logic.ConflictMap(camps)
    local map = {}
    for _, c in ipairs(camps or {}) do
        for _, b in ipairs(c.conflicts or {}) do
            if not map[b] then map[b] = c.name end
        end
    end
    return map
end

-- Cycle a blessing slot: nil -> MIGHT -> WISDOM -> ... -> nil
function Logic.CycleBlessing(current, dir, allowNone)
    local list = {}
    if allowNone ~= false then list[#list + 1] = false end
    for _, k in ipairs(ns.BLESSING_ORDER) do list[#list + 1] = k end
    local idx = 1
    for i, k in ipairs(list) do
        if k == (current or false) then idx = i break end
    end
    idx = idx + (dir or 1)
    if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
    return list[idx] or false
end

-- Cycle a manual role override: nil(auto) -> class roles... -> nil
function Logic.CycleRole(class, current)
    local roles = ns.CLASS_ROLES[class] or {}
    local list = { false }
    for _, r in ipairs(roles) do list[#list + 1] = r end
    local idx = 1
    for i, r in ipairs(list) do
        if r == (current or false) then idx = i break end
    end
    idx = idx + 1
    if idx > #list then idx = 1 end
    return list[idx] or nil
end

-- Pick the talent tree with most points. tabs: list of { name, points }
-- Returns tabIndex, summary ("0/31/20"), or nil if no points are spent.
function Logic.DominantTab(tabs)
    local best, bestPts, total, parts = nil, -1, 0, {}
    for i, t in ipairs(tabs or {}) do
        local pts = tonumber(t.points) or 0
        parts[#parts + 1] = tostring(pts)
        total = total + pts
        if pts > bestPts then best, bestPts = i, pts end
    end
    if total <= 0 then return nil end
    return best, table.concat(parts, "/")
end

function Logic.FormatTime(sec)
    if not sec then return "" end
    if sec >= 3600 then return string.format("%dh%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60)) end
    return string.format("%ds", math.floor(sec))
end
