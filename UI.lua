-- Camelus' Better Blessings - the blessing bar (secure click-to-cast rows)
--
-- Every row is a SecureActionButton. Out of combat the addon decides what
-- each row casts; when a blessing would overwrite a camp buff the row simply
-- has no spell attached, so clicking it cannot overwrite anything.
-- In combat everything is frozen (Blizzard does not allow secure buttons to
-- change, and aura data is restricted), and refreshes once combat ends.
local _, ns = ...
local Logic = ns.Logic

local UI = {}
ns.UI = UI

local WIDTH = 280
local ROW_H = 20
local PAD = 4
local HEADER_H = 26
local INNER_W = WIDTH - PAD * 2
local MAX_CAMP_ICONS = 3
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local BLOCKED_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local STATUS_COLORS = {
    OK      = { 0.10, 0.55, 0.10 },
    REFRESH = { 0.80, 0.65, 0.10 },
    MISSING = { 0.70, 0.10, 0.10 },
    SWAP    = { 0.85, 0.40, 0.10 },
    BLOCKED = { 0.45, 0.10, 0.55 },
    NONE    = { 0.25, 0.25, 0.25 },
    PENDING = { 0.20, 0.40, 0.75 },
    FAR     = { 0.30, 0.30, 0.30 },
}

local ROLE_SOURCE_TEXT = {
    manual = "set by you",
    group = "group role",
    talents = "talents",
    ["group+class"] = "group says DPS, class guess",
    class = "class guess",
}

---------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------
local function ClassColor(class)
    if class and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c then return c.r, c.g, c.b end
    end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end
ns.ClassColor = ClassColor

local function ClassLabel(class)
    if not class then return "?" end
    local loc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    return loc or (class:sub(1, 1) .. class:sub(2):lower())
end
ns.ClassLabel = ClassLabel

local function ShortName(name)
    if not name then return "?" end
    if Ambiguate then
        local ok, s = pcall(Ambiguate, name, "short")
        if ok and s then return s end
    end
    return name:match("^[^-]+") or name
end

local function SetClassIcon(tex, class)
    if class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
    elseif class then
        tex:SetTexCoord(0, 1, 0, 1)
        if not pcall(tex.SetAtlas, tex, "classicon-" .. class:lower()) then tex:SetTexture(QUESTION) end
    end
end

local function RoleText(role, source)
    local info = ns.ROLE_INFO[role]
    if not info then return "?" end
    local c = info.color
    local guess = (source == "class" or source == "group+class") and "?" or ""
    return string.format("|cff%02x%02x%02x%s%s|r", c[1] * 255, c[2] * 255, c[3] * 255, info.short, guess)
end

local function BlessingShort(key)
    return key and ns.BLESSINGS[key] and ns.BLESSINGS[key].short or "-"
end

local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end

---------------------------------------------------------------------------
-- frame creation
---------------------------------------------------------------------------
local function MakeRowBase(name, isClass)
    local b = CreateFrame("Button", name, UI.main, "SecureActionButtonTemplate")
    b:SetSize(INNER_W, ROW_H)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ROW_H - 2, ROW_H - 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.status:SetJustifyH("RIGHT")
    b.status:SetWidth(54)
    b.name = b:CreateFontString(nil, "OVERLAY", isClass and "GameFontNormalSmall" or "GameFontHighlightSmall")
    b.name:SetJustifyH("LEFT")
    if b.name.SetWordWrap then b.name:SetWordWrap(false) end
    b:Hide()
    return b
end

local function CreatePlayerRow(i)
    local b = MakeRowBase("CBB_PlayerRow" .. i, false)
    b.icon:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.role = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.role:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    b.role:SetWidth(34)
    b.role:SetJustifyH("LEFT")
    b.name:SetPoint("LEFT", b.role, "RIGHT", 2, 0)
    b.name:SetWidth(96)
    b.status:SetPoint("RIGHT", b, "RIGHT", -3, 0)
    b.camp = {}
    for j = 1, MAX_CAMP_ICONS do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(14, 14)
        t:SetPoint("RIGHT", b, "RIGHT", -58 - (j - 1) * 16, 0)
        t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        t:Hide()
        b.camp[j] = t
    end
    b:HookScript("OnEnter", function(self) UI:PlayerTooltip(self) end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("OnMouseUp", function(self, mouse)
        if mouse == "RightButton" then UI:CyclePlayerRole(self) end
    end)
    return b
end

local function CreateClassRow(i)
    local b = MakeRowBase("CBB_ClassRow" .. i, true)
    b.bg:SetColorTexture(1, 1, 1, 0.06)
    b.icon:SetPoint("LEFT", b, "LEFT", 1, 0)
    b.classIcon = b:CreateTexture(nil, "ARTWORK")
    b.classIcon:SetSize(14, 14)
    b.classIcon:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    b.name:SetPoint("LEFT", b.classIcon, "RIGHT", 4, 0)
    b.name:SetWidth(120)
    b.toggle = CreateFrame("Button", nil, b)
    b.toggle:SetSize(14, 14)
    b.toggle:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    b.toggle:SetScript("OnClick", function(self) UI:ToggleClass(self:GetParent()) end)
    b.status:SetPoint("RIGHT", b.toggle, "LEFT", -3, 0)
    b.status:SetWidth(80)
    b:HookScript("OnEnter", function(self) UI:ClassTooltip(self) end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("OnMouseUp", function(self, mouse)
        if mouse == "RightButton" then UI:CycleGreater(self, IsShiftKeyDown() and -1 or 1) end
    end)
    return b
end

function UI:Create()
    if self.main then return end
    if InCombatLockdown() then return end -- retried on PLAYER_REGEN_ENABLED

    local f = CreateFrame("Frame", "CBB_MainFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEADER_H + PAD * 2)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        if not ns.opt.locked and not InCombatLockdown() then s:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        UI:SavePosition()
    end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0, 0, 0, 0.8)
        f:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    end
    self.main = f
    self:RestorePosition()

    -- smart button (also bindable: Key Bindings > AddOns)
    local sb = CreateFrame("Button", "CBB_SmartButton", f, "SecureActionButtonTemplate")
    sb:SetSize(22, 22)
    sb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 1, -PAD - 1)
    sb:RegisterForClicks("AnyUp", "AnyDown")
    sb.icon = sb:CreateTexture(nil, "ARTWORK")
    sb.icon:SetAllPoints()
    sb.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local sbhl = sb:CreateTexture(nil, "HIGHLIGHT")
    sbhl:SetAllPoints()
    sbhl:SetColorTexture(1, 1, 1, 0.2)
    sb:SetScript("PreClick", function() UI:PrepareSmart() end)
    sb:HookScript("OnEnter", function(self) UI:SmartTooltip(self) end)
    sb:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.smart = sb

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", sb, "RIGHT", 6, 0)
    title:SetText("Better Blessings")
    self.title = title
    local count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", title, "RIGHT", 6, 0)
    self.count = count

    local cfg = CreateFrame("Button", nil, f)
    cfg:SetSize(18, 18)
    cfg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 2, -PAD - 3)
    cfg:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    cfg:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    cfg:SetScript("OnClick", function() if ns.Config then ns.Config:Toggle() end end)
    cfg:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Assignments & options")
        GameTooltip:AddLine("/cbb for commands", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    cfg:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetJustifyH("LEFT")
    footer:SetWidth(INNER_W - 4)
    footer:SetTextColor(1, 0.55, 0.3)
    self.footer = footer

    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints()
    ov:SetFrameLevel(f:GetFrameLevel() + 30)
    ov:EnableMouse(false)
    ov.tex = ov:CreateTexture(nil, "OVERLAY")
    ov.tex:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -HEADER_H - PAD)
    ov.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    ov.tex:SetColorTexture(0, 0, 0, 0.5)
    ov.text = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ov.text:SetPoint("TOP", ov.tex, "TOP", 0, -4)
    ov.text:SetText("|cffff8040In combat - frozen until combat ends|r")
    ov:Hide()
    self.overlay = ov

    self.playerRows, self.classRows = {}, {}

    self:ApplyScale()
    self:Layout()
    self:UpdateVisibility()
end

---------------------------------------------------------------------------
-- position / visibility
---------------------------------------------------------------------------
function UI:SavePosition()
    local point, _, relPoint, x, y = self.main:GetPoint(1)
    ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

function UI:RestorePosition()
    local p = ns.db.pos
    self.main:ClearAllPoints()
    if p and p.point then
        self.main:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        self.main:SetPoint("LEFT", UIParent, "LEFT", 40, 120)
    end
end

function UI:ApplyScale()
    if self.main and not InCombatLockdown() then self.main:SetScale(ns.opt.scale or 1) end
end

function UI:UpdateVisibility()
    if not self.main then return end
    if InCombatLockdown() then ns.needLayout = true return end
    local show = ns.isPaladin and not ns.opt.hidden and (IsInGroup() or ns.opt.showSolo)
    self.main:SetShown(show and true or false)
end

function UI:SetCombat(inCombat)
    if self.overlay then self.overlay:SetShown(inCombat) end
end

---------------------------------------------------------------------------
-- layout (out of combat only)
---------------------------------------------------------------------------
local function ClearSecure(b)
    b:SetAttribute("type1", nil)
    b:SetAttribute("spell1", nil)
    b:SetAttribute("unit", nil)
end

local function CollapseKey(class)
    return (IsInRaid() and "R:" or "P:") .. class
end

function UI:IsCollapsed(class)
    local v = ns.db.collapsed[CollapseKey(class)]
    if v == nil then return IsInRaid() and ns.opt.collapseRaid or false end
    return v
end

function UI:ToggleClass(row)
    if not row.class then return end
    if InCombatLockdown() then ns.Print("cannot change the bar layout in combat.") return end
    ns.db.collapsed[CollapseKey(row.class)] = not self:IsCollapsed(row.class)
    self:Layout()
end

function UI:Layout()
    if not self.main then return end
    if InCombatLockdown() then ns.needLayout = true return end
    ns.needLayout = false

    local y = -(PAD + HEADER_H)
    local ci, pi = 0, 0
    for _, class in ipairs(ns.CLASS_ORDER) do
        local members = ns.ClassMembers(class)
        if #members > 0 then
            ci = ci + 1
            local row = self.classRows[ci] or CreateClassRow(ci)
            self.classRows[ci] = row
            row.class = class
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.main, "TOPLEFT", PAD, y)
            row:Show()
            y = y - ROW_H - 1
            local collapsed = self:IsCollapsed(class)
            row.toggle:SetNormalTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            if not collapsed then
                for _, st in ipairs(members) do
                    pi = pi + 1
                    local pr = self.playerRows[pi] or CreatePlayerRow(pi)
                    self.playerRows[pi] = pr
                    pr.guid = st.guid
                    pr:ClearAllPoints()
                    pr:SetPoint("TOPLEFT", self.main, "TOPLEFT", PAD, y)
                    pr:Show()
                    y = y - ROW_H - 1
                end
            end
        end
    end
    for i = ci + 1, #self.classRows do
        local r = self.classRows[i]
        r.class = nil
        ClearSecure(r)
        r:Hide()
    end
    for i = pi + 1, #self.playerRows do
        local r = self.playerRows[i]
        r.guid = nil
        ClearSecure(r)
        r:Hide()
    end
    self.numClassRows, self.numPlayerRows = ci, pi
    self.contentBottom = y
    self:UpdateVisibility()
    self:UpdateFooter()
    self:Refresh()
end

function UI:UpdateFooter()
    if not self.main then return end
    local text
    if ns.targetWarning then
        text = ns.targetWarning
    elseif #ns.order == 0 then
        text = "|cffaaaaaaNo group members.|r"
    end
    local y = self.contentBottom or -(PAD + HEADER_H)
    self.footer:ClearAllPoints()
    self.footer:SetPoint("TOPLEFT", self.main, "TOPLEFT", PAD + 2, y - 2)
    self.footer:SetText(text or "")
    self.footer:SetShown(text ~= nil)
    if InCombatLockdown() then return end
    local h = -y + PAD
    if text then h = h + (self.footer:GetStringHeight() or 12) + 4 end
    self.main:SetHeight(h)
end

---------------------------------------------------------------------------
-- refresh (visuals any time, secure attributes only out of combat)
---------------------------------------------------------------------------
local function PaintBg(row, key, alpha)
    local c = STATUS_COLORS[key] or STATUS_COLORS.NONE
    row.bg:SetColorTexture(c[1], c[2], c[3], alpha or 0.35)
end

function UI:RefreshPlayerRow(row, canSet)
    local st = row.guid and ns.units[row.guid]
    if not st or not st.choice then
        row.name:SetText("?")
        if canSet then ClearSecure(row) end
        return
    end
    local c = st.choice
    local colorKey, label = c.status, ""
    if not st.connected then
        colorKey, label = "FAR", "offline"
    elseif st.dead then
        colorKey, label = "FAR", "dead"
    elseif st.isPending then
        colorKey, label = "PENDING", "..."
    elseif c.status == "OK" then
        label = c.remaining and Logic.FormatTime(c.remaining) or "ok"
    elseif c.status == "REFRESH" then
        label = Logic.FormatTime(c.remaining)
    elseif c.status == "MISSING" then
        label = "MISSING"
    elseif c.status == "SWAP" then
        label = "swap"
    elseif c.status == "BLOCKED" then
        label = "blocked"
    else
        label = "-"
    end
    if Logic.NEEDS_CAST[c.status] and st.connected and not st.dead and not st.inRange then
        colorKey, label = "FAR", "range"
    end
    PaintBg(row, colorKey)
    row.status:SetText(label)
    row.icon:SetTexture(c.blessing and ns.BlessingTexture(c.blessing, false) or BLOCKED_ICON)
    row.icon:SetAlpha(c.status == "OK" and 0.7 or 1)
    row.role:SetText(RoleText(st.role, st.roleSource))
    local r, g, b = ClassColor(st.class)
    row.name:SetText(ShortName(st.name) .. (st.stale and "|cffaaaaaa*|r" or ""))
    row.name:SetTextColor(r, g, b)
    local camps = st.aura and st.aura.camps or {}
    for j = 1, MAX_CAMP_ICONS do
        local t, camp = row.camp[j], camps[j]
        if camp then
            t:SetTexture(camp.icon or QUESTION)
            t:Show()
        else
            t:Hide()
        end
    end
    if canSet then
        row:SetAttribute("unit", st.unit)
        if c.blessing and st.connected and not st.dead then
            row:SetAttribute("type1", "spell")
            row:SetAttribute("spell1", ns.BlessingSpell(c.blessing, false))
        else
            row:SetAttribute("type1", nil)
            row:SetAttribute("spell1", nil)
        end
    end
end

-- Facts about a Greater Blessing for one class.
function UI:GreaterInfo(class)
    local g = ns.GetGreater(class)
    local members = ns.ClassMembers(class)
    local info = { blessing = g, members = members, have = 0, target = nil, replaces = {}, notIdeal = {} }
    local list = {}
    for _, st in ipairs(members) do
        list[#list + 1] = { name = ShortName(st.name), conflicts = st.conflicts }
        if g and st.aura and st.aura.blessings[g] then info.have = info.have + 1 end
        if not info.target and st.connected and not st.dead and st.inRange then info.target = st end
        if g and st.mine and st.mine.type ~= g then info.replaces[#info.replaces + 1] = ShortName(st.name) end
        if g and st.choice and st.choice.blessing and st.choice.blessing ~= g then
            info.notIdeal[#info.notIdeal + 1] = string.format("%s (wants %s)", ShortName(st.name), BlessingShort(st.choice.blessing))
        end
    end
    info.conflicts = Logic.GreaterConflicts(g, list)
    info.known = g and ns.BLESSINGS[g].greaterKnown or false
    info.blocked = g and ns.opt.protectGreater and #info.conflicts > 0 or false
    return info
end

function UI:RefreshClassRow(row, canSet)
    local class = row.class
    if not class then return end
    local info = self:GreaterInfo(class)
    local r, g, b = ClassColor(class)
    SetClassIcon(row.classIcon, class)
    row.name:SetText(string.format("%s (%d)", ClassLabel(class), #info.members))
    row.name:SetTextColor(r, g, b)
    row.icon:SetTexture(info.blessing and ns.BlessingTexture(info.blessing, true) or QUESTION)
    row.icon:SetDesaturated((not info.blessing or info.blocked or not info.known) and true or false)
    local label
    if not info.blessing then
        label = "|cffaaaaaano greater|r"
    elseif info.blocked then
        label = "|cffd080ffblocked|r"
    elseif not info.known then
        label = "|cffaaaaaanot learned|r"
    elseif not info.target then
        label = "|cffaaaaaaout of range|r"
    else
        label = string.format("%s %d/%d", BlessingShort(info.blessing), info.have, #info.members)
    end
    row.status:SetText(label)
    if canSet then
        if info.blessing and info.known and not info.blocked and info.target then
            row:SetAttribute("type1", "spell")
            row:SetAttribute("spell1", ns.BlessingSpell(info.blessing, true))
            row:SetAttribute("unit", info.target.unit)
        else
            ClearSecure(row)
        end
    end
end

function UI:PrepareSmart()
    if not self.smart or InCombatLockdown() then return end
    local t = ns.NextSmartTarget()
    local sb = self.smart
    if t then
        sb:SetAttribute("type1", "spell")
        sb:SetAttribute("spell1", ns.BlessingSpell(t.choice.blessing, false))
        sb:SetAttribute("unit", t.unit)
    else
        ClearSecure(sb)
    end
    sb.target = t
    sb.icon:SetTexture(t and ns.BlessingTexture(t.choice.blessing, false) or ns.BlessingTexture("WISDOM", false))
    sb.icon:SetDesaturated(not t)
end

function UI:Refresh()
    if not self.main then return end
    if ns.needLayout and not InCombatLockdown() then
        self:Layout() -- calls Refresh again
        return
    end
    local canSet = not InCombatLockdown()
    for i = 1, self.numClassRows or 0 do self:RefreshClassRow(self.classRows[i], canSet) end
    for i = 1, self.numPlayerRows or 0 do self:RefreshPlayerRow(self.playerRows[i], canSet) end
    local n = ns.CountNeeding()
    self.count:SetText(n > 0 and string.format("|cffff6060%d need|r", n) or "|cff60ff60all set|r")
    self:PrepareSmart()
end

---------------------------------------------------------------------------
-- clicks that change settings
---------------------------------------------------------------------------
function UI:CyclePlayerRole(row)
    local st = row.guid and ns.units[row.guid]
    if not st then return end
    local new = Logic.CycleRole(st.class, ns.db.overrides[st.name])
    ns.db.overrides[st.name] = new
    ns.Print("%s: %s", ShortName(st.name), new and ns.ROLE_INFO[new].label or "automatic role")
    if InCombatLockdown() then ns.Print("the change applies when combat ends.") end
    ns.RequestUpdate()
    if GameTooltip:GetOwner() == row then self:PlayerTooltip(row) end
end

function UI:CycleGreater(row, dir)
    if not row.class then return end
    ns.db.greater[row.class] = Logic.CycleBlessing(ns.GetGreater(row.class), dir, true)
    if InCombatLockdown() then ns.Print("the change applies when combat ends.") end
    ns.RequestUpdate()
    if ns.Config then ns.Config:Refresh() end
    if GameTooltip:GetOwner() == row then self:ClassTooltip(row) end
end

---------------------------------------------------------------------------
-- tooltips
---------------------------------------------------------------------------
local SKIP_TEXT = {
    unknown = "you have not learned it",
    camp = "would replace %s",
    taken = "already given by %s",
}

function UI:PlayerTooltip(row)
    local st = row.guid and ns.units[row.guid]
    if not st then return end
    local tt = GameTooltip
    tt:SetOwner(row, "ANCHOR_RIGHT")
    local r, g, b = ClassColor(st.class)
    tt:AddLine(st.name, r, g, b)
    local role = ns.ROLE_INFO[st.role]
    tt:AddDoubleLine("Role", string.format("%s (%s)", role and role.label or "?", ROLE_SOURCE_TEXT[st.roleSource] or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
    if st.talentDetail then tt:AddDoubleLine("Talents", st.talentDetail, 0.8, 0.8, 0.8, 1, 1, 1) end
    if st.groupRole and st.groupRole ~= "NONE" then tt:AddDoubleLine("Group role", st.groupRole, 0.8, 0.8, 0.8, 1, 1, 1) end

    local now = GetTime()
    local aura = st.aura or { blessings = {}, camps = {} }
    if #aura.camps > 0 then
        tt:AddLine(" ")
        tt:AddLine("Camp buffs", 0.4, 1, 0.4)
        for _, camp in ipairs(aura.camps) do
            local blocks = {}
            for _, k in ipairs(camp.conflicts or {}) do blocks[#blocks + 1] = BlessingShort(k) end
            tt:AddDoubleLine("  " .. camp.name, string.format("blocks %s  %s", table.concat(blocks, "/"),
                camp.expires and Logic.FormatTime(camp.expires - now) or ""), 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    local any = false
    for _, key in ipairs(ns.BLESSING_ORDER) do
        local info = aura.blessings[key]
        if info then
            if not any then tt:AddLine(" ") tt:AddLine("Blessings", 1, 0.82, 0) any = true end
            tt:AddDoubleLine("  " .. (info.greater and "Greater " or "") .. BlessingShort(key),
                string.format("%s  %s", info.mine and "you" or (info.caster or "?"), info.expires and Logic.FormatTime(info.expires - now) or ""),
                1, 1, 1, info.mine and 0.4 or 0.8, info.mine and 1 or 0.8, info.mine and 0.4 or 0.8)
        end
    end

    tt:AddLine(" ")
    local c = st.choice or { status = "NONE", skipped = {} }
    if c.blessing then
        local statusText = ({ OK = "has it", REFRESH = "refresh soon", MISSING = "missing", SWAP = "replaces your " .. BlessingShort(st.mine and st.mine.type) })[c.status] or c.status
        tt:AddDoubleLine("Click casts", (ns.BlessingSpell(c.blessing, false) or "?"), 1, 0.82, 0, 1, 1, 1)
        tt:AddDoubleLine(" ", statusText, 1, 1, 1, 0.8, 0.8, 0.8)
    elseif c.status == "BLOCKED" then
        tt:AddLine("Nothing to cast - every option would replace a camp buff.", 0.85, 0.5, 1, true)
    else
        tt:AddLine("Nothing to cast (no usable blessing in this role's list).", 0.7, 0.7, 0.7, true)
    end
    for _, s in ipairs(c.skipped or {}) do
        tt:AddLine(string.format("  skipped %s: %s", BlessingShort(s.blessing), string.format(SKIP_TEXT[s.reason] or s.reason, s.detail or "?")), 0.75, 0.75, 0.75)
    end
    local prio = {}
    for i = 1, ns.MAX_PRIORITY do
        if st.priority and st.priority[i] then prio[#prio + 1] = BlessingShort(st.priority[i]) end
    end
    tt:AddLine("Priority: " .. table.concat(prio, " > "), 0.6, 0.6, 0.6)
    if st.stale then tt:AddLine("* buff info is from before combat", 0.6, 0.6, 0.6) end
    tt:AddLine(" ")
    tt:AddLine("Left-click: cast   Right-click: change role", 0.5, 0.8, 1)
    tt:Show()
end

function UI:ClassTooltip(row)
    if not row.class then return end
    local info = self:GreaterInfo(row.class)
    local tt = GameTooltip
    tt:SetOwner(row, "ANCHOR_RIGHT")
    tt:AddLine(ClassLabel(row.class) .. " - Greater Blessing", ClassColor(row.class))
    tt:AddDoubleLine("Assigned", info.blessing and ns.BlessingSpell(info.blessing, true) or "none", 0.8, 0.8, 0.8, 1, 1, 1)
    if info.blessing then
        tt:AddDoubleLine("Players with it", string.format("%d / %d", info.have, #info.members), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if #info.conflicts > 0 then
        tt:AddLine(" ")
        tt:AddLine(info.blocked and "BLOCKED - it would replace:" or "Warning - it would replace:", 0.85, 0.5, 1)
        for _, cf in ipairs(info.conflicts) do tt:AddLine(string.format("  %s's %s", cf.name, cf.camp), 1, 1, 1) end
        tt:AddLine("Use the single blessings below instead.", 0.8, 0.8, 0.8)
    end
    if #info.replaces > 0 then
        tt:AddLine(" ")
        tt:AddLine("Replaces your single blessing on: " .. table.concat(info.replaces, ", "), 1, 0.6, 0.3, true)
    end
    if #info.notIdeal > 0 then
        tt:AddLine("Role assignments differ: " .. table.concat(info.notIdeal, ", "), 0.8, 0.8, 0.8, true)
    end
    if info.blessing and not info.known then tt:AddLine("You have not learned this Greater Blessing.", 0.7, 0.7, 0.7) end
    tt:AddLine(" ")
    tt:AddLine("Left-click: cast   Right-click: next blessing   Shift-right: previous", 0.5, 0.8, 1, true)
    tt:Show()
end

function UI:SmartTooltip(btn)
    local tt = GameTooltip
    tt:SetOwner(btn, "ANCHOR_RIGHT")
    tt:AddLine("Smart blessing")
    local t = btn.target
    if t then
        tt:AddDoubleLine("Next", string.format("%s on %s", BlessingShort(t.choice.blessing), ShortName(t.name)), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        tt:AddLine("Nobody in range needs a blessing.", 0.6, 1, 0.6)
    end
    tt:AddLine("Bind a key: Key Bindings > AddOns > Camelus' Better Blessings", 0.6, 0.6, 0.6, true)
    tt:Show()
end
