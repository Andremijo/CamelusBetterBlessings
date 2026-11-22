-- Camelus' Better Blessings - the casting bar
--
-- A compact, Pally Power style column. On a class button, left-click casts
-- the class's Greater Blessing and right-click blesses the next player of
-- that class who needs it (top to bottom), with that player's own blessing.
--   (gear) [class icon | greater]  - click: Greater Blessing for the class
--          ...                       hover: flyout with one button per player
--   Colours: red = someone is missing their blessing, green = all buffed,
--   yellow = running out soon, grey = out of range / dead, purple = blocked
--   by camp buffs. Click a red player in the flyout to bless them.
--
-- The bar only casts. Every setting (assignments, roles, options) lives in the
-- settings window (the gear, or /cbb config). The smart button ("bless the
-- next player who needs it") is key-bindable and can be shown on the bar.
--
-- All buttons are SecureActionButtons. Out of combat the addon decides what
-- each one casts; a blessing that would overwrite a camp buff is simply not
-- attached, so clicking cannot overwrite anything. In combat everything is
-- frozen (Blizzard does not allow secure buttons to change, and aura data is
-- restricted) and refreshes once combat ends.
local _, ns = ...
local Logic = ns.Logic

local UI = {}
ns.UI = UI

-- The tooltip-style border has a transparent margin, so a button looks about
-- 3 units smaller than its frame. A small negative gap makes the visible gap
-- between rows about 2 units (~3 px), like Pally Power.
local BTN_W, BTN_H, GAP = 88, 30, -1
-- Class buttons show one small icon per distinct camp buff in the class.
-- 88 fits one; the whole column widens only when a class shows more.
local MAX_CAMP_MARKS, MARK_SIZE, MARK_GAP = 3, 16, 2

local FLY_GAP = 2 -- horizontal space between a class button and its flyout
local FLY_W = 210
local STATUS_W = 38
local TIMER_W = 36 -- class button countdown
local ICON = 24
local HANDLE = 14   -- gear size
local BAR_X = 0     -- the column starts at the bar's left edge; the gear sits on its top-left corner
local GEAR_LEVEL = 50 -- above class buttons and their flyouts
local MAX_CAMP_ICONS = 2
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local BLOCKED_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local STATUS_COLORS = {
    OK      = { 0.10, 0.50, 0.10 },
    REFRESH = { 0.75, 0.62, 0.10 },
    MISSING = { 0.65, 0.08, 0.08 },
    SWAP    = { 0.80, 0.38, 0.08 },
    BLOCKED = { 0.40, 0.10, 0.50 },
    NONE    = { 0.22, 0.22, 0.22 },
    PENDING = { 0.18, 0.36, 0.70 },
    FAR     = { 0.28, 0.28, 0.28 },
}

local ROLE_SOURCE_TEXT = {
    manual = "set by you",
    group = "group role",
    talents = "talents",
    ["group+class"] = "group says DPS, class guess",
    class = "class guess",
}
ns.ROLE_SOURCE_TEXT = ROLE_SOURCE_TEXT

---------------------------------------------------------------------------
-- small helpers (shared with Config.lua through ns)
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
ns.ShortName = ShortName

local function SetClassIcon(tex, class)
    if class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
    elseif class then
        tex:SetTexCoord(0, 1, 0, 1)
        if not pcall(tex.SetAtlas, tex, "classicon-" .. class:lower()) then tex:SetTexture(QUESTION) end
    end
end
ns.SetClassIcon = SetClassIcon

-- Role tag, with "?" only when the role is a guess AND the class has a choice.
local function RoleText(role, source, class)
    local info = ns.ROLE_INFO[role]
    if not info then return "?" end
    local c = info.color
    local choices = class and ns.CLASS_ROLES[class]
    local guess = (source == "class" or source == "group+class") and choices and #choices > 1
    return string.format("|cff%02x%02x%02x%s%s|r", c[1] * 255, c[2] * 255, c[3] * 255, Logic.RoleShort(class, role), guess and "?" or "")
end
ns.RoleText = RoleText

local function BlessingShort(key)
    return key and ns.BLESSINGS[key] and ns.BLESSINGS[key].short or "-"
end
ns.BlessingShort = BlessingShort

---------------------------------------------------------------------------
-- button factory
---------------------------------------------------------------------------
local BORDER = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function MakeButton(name, parent, width)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate, BackdropTemplate")
    b:SetSize(width, BTN_H)
    b:RegisterForClicks("AnyUp", "AnyDown")
    if b.SetBackdrop then
        b:SetBackdrop(BORDER)
        b:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    end
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", 2, -2)
    b.bg:SetPoint("BOTTOMRIGHT", -2, 2)
    b.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.icon1 = b:CreateTexture(nil, "ARTWORK")
    b.icon1:SetSize(ICON, ICON)
    b.icon1:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.icon1:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetJustifyH("RIGHT")
    b.text:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b:Hide()
    return b
end

local function Paint(b, key)
    local c = STATUS_COLORS[key] or STATUS_COLORS.NONE
    b.bg:SetColorTexture(c[1], c[2], c[3], 0.85)
end

-- n = mouse button (1 = left, 2 = right). Left-click uses the plain "unit"
-- attribute; right-click uses "unit2" (the secure template prefers the
-- button-specific one).
local function UnitAttr(n) return n == 2 and "unit2" or "unit" end

local function ClearSecure(b, n)
    n = n or 1
    b:SetAttribute("type" .. n, nil)
    b:SetAttribute("spell" .. n, nil)
    b:SetAttribute(UnitAttr(n), nil)
end

local function SetSpell(b, spell, unit, n)
    n = n or 1
    b:SetAttribute("type" .. n, "spell")
    b:SetAttribute("spell" .. n, spell)
    b:SetAttribute(UnitAttr(n), unit)
end

---------------------------------------------------------------------------
-- creation
---------------------------------------------------------------------------
function UI:Create()
    if self.main then return end
    if InCombatLockdown() then return end -- retried on PLAYER_REGEN_ENABLED

    local f = CreateFrame("Frame", "CBB_MainFrame", UIParent)
    f:SetSize(BAR_X + BTN_W, BTN_H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    self.main = f
    self:RestorePosition()

    -- Settings button: click to open the settings, drag to move the bar.
    local h = CreateFrame("Button", "CBB_SettingsButton", f)
    h:SetSize(HANDLE, HANDLE)
    -- Pinned on the bar's top-left corner and drawn above everything else on
    -- the bar, so a flyout opening to the left can never cover it.
    h:SetPoint("CENTER", f, "TOPLEFT", 0, 0)
    h:SetFrameLevel(f:GetFrameLevel() + GEAR_LEVEL)
    h:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    h:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function()
        if not ns.opt.locked and not InCombatLockdown() then f:StartMoving() end
    end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        UI:SavePosition()
    end)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:SetScript("OnClick", function(_, mouse)
        if not ns.Config then return end
        if mouse == "RightButton" then ns.Config:Toggle("players") else ns.Config:Toggle() end
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Camelus' Better Blessings")
        GameTooltip:AddLine("Left-click: settings", 0.5, 0.8, 1)
        GameTooltip:AddLine("Right-click: Players (roles)", 0.5, 0.8, 1)
        GameTooltip:AddLine(ns.opt.locked and "Bar is locked (unlock in Options)." or "Drag: move the bar", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.handle = h

    -- Smart button (also bindable: Key Bindings > AddOns)
    local sb = MakeButton("CBB_SmartButton", f, BTN_W)
    sb:SetPoint("TOPLEFT", f, "TOPLEFT", BAR_X, 0)
    sb.text:SetFontObject("GameFontHighlightSmall")
    sb.text:ClearAllPoints()
    sb.text:SetPoint("LEFT", sb.icon1, "RIGHT", 4, 0)
    sb.text:SetPoint("RIGHT", sb, "RIGHT", -5, 0)
    sb.text:SetJustifyH("LEFT")
    if sb.text.SetWordWrap then sb.text:SetWordWrap(false) end
    sb:SetScript("PreClick", function() UI:PrepareSmart() end)
    sb:HookScript("OnEnter", function(self) UI:SmartTooltip(self) end)
    sb:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.smart = sb

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetJustifyH("LEFT")
    footer:SetWidth(BTN_W + FLY_W)
    footer:SetTextColor(1, 0.55, 0.3)
    self.footer = footer

    self.classButtons = {}
    C_Timer.NewTicker(1, function() UI:UpdateTimers() end)
    self:ApplyScale()
    self:Layout()
    self:UpdateVisibility()
end

local function CreatePlayerButton(flyout, i)
    local b = MakeButton(nil, flyout, FLY_W)
    b.role = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.role:SetPoint("LEFT", b.icon1, "RIGHT", 4, 0)
    b.role:SetWidth(34)
    b.role:SetJustifyH("LEFT")
    -- Right to left: status text (fixed width), camp icons, then the name,
    -- which ends where the icons begin and is cut short with "..." if needed.
    b.text:SetFontObject("GameFontHighlightSmall")
    b.text:SetWidth(STATUS_W)
    b.camp = {}
    for j = 1, MAX_CAMP_ICONS do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(16, 16)
        if j == 1 then
            t:SetPoint("RIGHT", b.text, "LEFT", -3, 0)
        else
            t:SetPoint("RIGHT", b.camp[j - 1], "LEFT", -2, 0)
        end
        t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        t:Hide()
        b.camp[j] = t
    end
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetJustifyH("LEFT")
    if b.name.SetWordWrap then b.name:SetWordWrap(false) end
    b.SetNameEnd = function(self, anchor)
        if self.nameEnd == anchor then return end
        self.nameEnd = anchor
        self.name:ClearAllPoints()
        self.name:SetPoint("LEFT", self.role, "RIGHT", 2, 0)
        self.name:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    end
    b:SetNameEnd(b.text)
    b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 0, -(i - 1) * (BTN_H + GAP))
    b:HookScript("OnEnter", function(self)
        UI:CancelFlyoutClose()
        UI:PlayerTooltip(self)
    end)
    b:HookScript("OnLeave", function()
        GameTooltip:Hide()
        UI:ScheduleFlyoutClose()
    end)
    return b
end

local function CreateClassButton(i)
    local b = MakeButton("CBB_ClassButton" .. i, UI.main, UI.buttonWidth or BTN_W)
    b.icon2 = b:CreateTexture(nil, "ARTWORK")
    b.icon2:SetSize(ICON, ICON)
    b.icon2:SetPoint("LEFT", b.icon1, "RIGHT", 3, 0)
    b.icon2:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.blockedMark = b:CreateTexture(nil, "OVERLAY")
    b.blockedMark:SetAllPoints(b.icon2)
    b.blockedMark:SetTexture(BLOCKED_ICON)
    b.blockedMark:Hide()
    b.text:SetWidth(TIMER_W)
    b.campMarks = {}
    for j = 1, MAX_CAMP_MARKS do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(MARK_SIZE, MARK_SIZE)
        if j == 1 then
            t:SetPoint("LEFT", b.icon2, "RIGHT", 4, 0)
        else
            t:SetPoint("LEFT", b.campMarks[j - 1], "RIGHT", MARK_GAP, 0)
        end
        t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        t:Hide()
        b.campMarks[j] = t
    end

    local fly = CreateFrame("Frame", nil, b)
    UI:AnchorFlyout(b, fly)
    fly:SetSize(FLY_W, BTN_H)
    fly:Hide()
    fly.buttons = {}
    b.flyout = fly

    -- Right-click blesses the next player of this class who needs it; pick
    -- them right before the click so consecutive clicks walk down the list.
    b:SetScript("PreClick", function(self) UI:PrepareClassSingle(self) end)
    b:HookScript("OnEnter", function(self)
        UI:OpenFlyout(self)
        UI:ClassTooltip(self)
    end)
    b:HookScript("OnLeave", function()
        GameTooltip:Hide()
        UI:ScheduleFlyoutClose()
    end)
    return b
end

---------------------------------------------------------------------------
-- flyouts (opened by hovering a class button, out of combat)
-- Option "flyoutLeft": open to the left of the bar instead of the right.
---------------------------------------------------------------------------
function UI:AnchorFlyout(cb, fly)
    fly = fly or cb.flyout
    local left = ns.opt.flyoutLeft and true or false
    if fly.anchoredLeft == left then return end
    fly.anchoredLeft = left
    fly:ClearAllPoints()
    if left then
        fly:SetPoint("TOPRIGHT", cb, "TOPLEFT", -FLY_GAP, 0)
    else
        fly:SetPoint("TOPLEFT", cb, "TOPRIGHT", FLY_GAP, 0)
    end
end

function UI:OpenFlyout(cb)
    if InCombatLockdown() or not cb.class then return end
    self:CancelFlyoutClose()
    for _, other in ipairs(self.classButtons) do
        if other ~= cb and other.flyout:IsShown() then other.flyout:Hide() end
    end
    if (cb.numPlayers or 0) > 0 then cb.flyout:Show() end
    self.openClass = cb
end

function UI:CancelFlyoutClose()
    self.closeToken = (self.closeToken or 0) + 1
end

function UI:ScheduleFlyoutClose()
    self.closeToken = (self.closeToken or 0) + 1
    local token = self.closeToken
    C_Timer.After(0.2, function()
        if token ~= self.closeToken then return end
        local cb = self.openClass
        if not cb then return end
        if cb:IsMouseOver() or (cb.flyout:IsShown() and cb.flyout:IsMouseOver()) then return end
        self:CloseFlyouts()
    end)
end

function UI:CloseFlyouts()
    if InCombatLockdown() then return end
    for _, cb in ipairs(self.classButtons or {}) do cb.flyout:Hide() end
    self.openClass = nil
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
    self.inCombat = inCombat
    if self.smart then self:RefreshSmartVisual() end
end

---------------------------------------------------------------------------
-- layout (out of combat only)
---------------------------------------------------------------------------
function UI:Layout()
    if not self.main then return end
    if InCombatLockdown() then ns.needLayout = true return end
    ns.needLayout = false

    -- The smart button works from its key binding even while hidden.
    local top = ns.opt.showSmart and 1 or 0
    self.smart:SetShown(ns.opt.showSmart and true or false)
    local ci = 0
    for _, class in ipairs(ns.CLASS_ORDER) do
        local members = ns.ClassMembers(class)
        if #members > 0 then
            ci = ci + 1
            local cb = self.classButtons[ci] or CreateClassButton(ci)
            self.classButtons[ci] = cb
            cb.class = class
            self:AnchorFlyout(cb)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", self.main, "TOPLEFT", BAR_X, -(ci - 1 + top) * (BTN_H + GAP))
            cb:Show()
            for pi, st in ipairs(members) do
                local pb = cb.flyout.buttons[pi] or CreatePlayerButton(cb.flyout, pi)
                cb.flyout.buttons[pi] = pb
                pb.guid = st.guid
                pb:Show()
            end
            for pi = #members + 1, #cb.flyout.buttons do
                local pb = cb.flyout.buttons[pi]
                pb.guid = nil
                ClearSecure(pb)
                pb:Hide()
            end
            cb.numPlayers = #members
            cb.flyout:SetHeight(#members * (BTN_H + GAP) - GAP)
        end
    end
    for i = ci + 1, #self.classButtons do
        local cb = self.classButtons[i]
        cb.class, cb.numPlayers = nil, 0
        ClearSecure(cb, 1)
        ClearSecure(cb, 2)
        cb.nextSingle = nil
        for _, pb in ipairs(cb.flyout.buttons) do pb.guid = nil ClearSecure(pb) pb:Hide() end
        cb.flyout:Hide()
        cb:Hide()
    end
    self.numClasses = ci
    self.main:SetHeight(math.max(1, ci + top) * (BTN_H + GAP) - GAP)
    self:UpdateVisibility()
    self:UpdateFooter()
    self:Refresh()
end

function UI:UpdateFooter()
    if not self.main then return end
    local text = ns.targetWarning
    self.footer:ClearAllPoints()
    self.footer:SetPoint("TOPLEFT", self.main, "BOTTOMLEFT", BAR_X + 2, -3)
    self.footer:SetText(text or "")
    self.footer:SetShown(text ~= nil)
end

---------------------------------------------------------------------------
-- refresh (visuals any time, secure attributes only out of combat)
---------------------------------------------------------------------------
-- Seconds left on MY blessing on this player (any type), or nil.
local function MyRemaining(st)
    local now = GetTime()
    for _, info in pairs(st and st.aura and st.aura.blessings or {}) do
        if info.mine and info.expires then return math.max(0, info.expires - now) end
    end
    return nil
end
UI.MyRemaining = MyRemaining

local function TimerColor(sec)
    if sec and sec <= (ns.opt.refreshMinutes or 5) * 60 then return "|cffffd040" end
    return "|cffffffff"
end

local function PlayerStatus(st)
    local c = st.choice or { status = "NONE" }
    if not st.connected then return "FAR", "offline" end
    if st.dead then return "FAR", "dead" end
    if st.isPending then return "PENDING", "..." end
    local key, label = c.status, ""
    if c.status == "OK" or c.status == "REFRESH" then
        local left = MyRemaining(st) or c.remaining
        label = left and (TimerColor(left) .. Logic.FormatClock(left) .. "|r") or ""
    elseif c.status == "MISSING" then
        label = "!"
    elseif c.status == "SWAP" then
        label = "swap"
    elseif c.status == "BLOCKED" then
        label = "camp"
    end
    if Logic.NEEDS_CAST[c.status] and not st.inRange then key, label = "FAR", "range" end
    return key, label
end

function UI:RefreshPlayerButton(b, canSet)
    local st = b.guid and ns.units[b.guid]
    if not st or not st.choice then
        b.name:SetText("?")
        if canSet then ClearSecure(b) end
        return
    end
    local c = st.choice
    local key, label = PlayerStatus(st)
    Paint(b, key)
    b.text:SetText(label)
    b.icon1:SetTexture(c.blessing and ns.BlessingTexture(c.blessing, false) or BLOCKED_ICON)
    b.role:SetText(RoleText(st.role, st.roleSource, st.class))
    b.name:SetText(ShortName(st.name) .. (st.stale and "|cffaaaaaa*|r" or ""))
    b.name:SetTextColor(ClassColor(st.class))
    local camps = st.aura and st.aura.camps or {}
    local nameEnd = b.text
    for j = 1, MAX_CAMP_ICONS do
        local t, camp = b.camp[j], camps[j]
        if camp then
            t:SetTexture(camp.icon or QUESTION)
            t:Show()
            nameEnd = t
        else
            t:Hide()
        end
    end
    b:SetNameEnd(nameEnd)
    if canSet then
        if c.blessing and st.connected and not st.dead then
            SetSpell(b, ns.BlessingSpell(c.blessing, false), st.unit)
        else
            ClearSecure(b)
        end
    end
end

-- Facts about a Greater Blessing for one class.
function UI:GreaterInfo(class)
    local g, fromPP = ns.EffectiveGreater(class)
    local members = ns.ClassMembers(class)
    local info = { blessing = g, fromPP = fromPP, members = members, have = 0, target = nil, replaces = {}, notIdeal = {},
                   need = 0, needInRange = 0, refresh = 0, camps = {} }
    local seenCamp = {}
    local list = {}
    for _, st in ipairs(members) do
        list[#list + 1] = { name = ShortName(st.name), conflicts = st.conflicts }
        if g and st.aura and st.aura.blessings[g] then info.have = info.have + 1 end
        if not info.target and st.connected and not st.dead and st.inRange then info.target = st end
        if g and st.mine and st.mine.type ~= g then info.replaces[#info.replaces + 1] = ShortName(st.name) end
        local c = st.choice
        if g and c and c.blessing and c.blessing ~= g then
            info.notIdeal[#info.notIdeal + 1] = string.format("%s (wants %s)", ShortName(st.name), BlessingShort(c.blessing))
        end
        if c and Logic.NEEDS_CAST[c.status] and st.connected and not st.dead and not st.isPending then
            info.need = info.need + 1
            if st.inRange then info.needInRange = info.needInRange + 1 end
            if c.status == "REFRESH" then info.refresh = info.refresh + 1 end
        end
        -- every distinct camp buff anyone in the class has
        for _, camp in ipairs(st.aura and st.aura.camps or {}) do
            local id = camp.name or camp.key
            if id and not seenCamp[id] then
                seenCamp[id] = true
                info.camps[#info.camps + 1] = camp
            end
        end
    end
    info.conflicts = Logic.GreaterConflicts(g, list)
    info.known = g and ns.BLESSINGS[g] and ns.BLESSINGS[g].greaterKnown or false
    info.blocked = g and ns.opt.protectGreater and #info.conflicts > 0 or false
    return info
end

function UI:RefreshClassButton(cb, canSet)
    local class = cb.class
    if not class then return end
    local info = self:GreaterInfo(class)
    SetClassIcon(cb.icon1, class)
    cb.icon2:SetTexture(info.blessing and ns.BlessingTexture(info.blessing, true) or QUESTION)
    cb.icon2:SetDesaturated((not info.blessing or info.blocked or not info.known) and true or false)
    cb.blockedMark:SetShown(info.blocked and true or false)
    for j = 1, MAX_CAMP_MARKS do
        local t, camp = cb.campMarks[j], info.camps[j]
        if camp then t:SetTexture(camp.icon or QUESTION) t:Show() else t:Hide() end
    end
    cb.numCampMarks = math.min(#info.camps, MAX_CAMP_MARKS)
    -- colour = the class's single-blessing state (that is what dungeons use)
    local key
    if info.needInRange > info.refresh then key = "MISSING"
    elseif info.needInRange > 0 then key = "REFRESH"
    elseif info.need > 0 then key = "FAR"
    else key = "OK" end
    Paint(cb, key)
    self:UpdateClassTimer(cb)
    for _, pb in ipairs(cb.flyout.buttons) do
        if pb.guid then self:RefreshPlayerButton(pb, canSet) end
    end
    if canSet then
        if info.blessing and info.known and not info.blocked and info.target then
            SetSpell(cb, ns.BlessingSpell(info.blessing, true), info.target.unit, 1)
        else
            ClearSecure(cb, 1)
        end
        self:PrepareClassSingle(cb)
    end
end

-- First player of the class, top to bottom (same order as the flyout), who
-- needs a blessing and can get one now. Each player gets their own choice.
function UI:NextInClass(class)
    for _, st in ipairs(ns.ClassMembers(class)) do
        local c = st.choice
        if c and c.blessing and Logic.NEEDS_CAST[c.status] and not st.isPending
            and st.connected and not st.dead and st.inRange then
            return st
        end
    end
    return nil
end

function UI:PrepareClassSingle(cb)
    if InCombatLockdown() or not cb.class then return end
    local st = self:NextInClass(cb.class)
    if st then
        SetSpell(cb, ns.BlessingSpell(st.choice.blessing, false), st.unit, 2)
    else
        ClearSecure(cb, 2)
    end
    cb.nextSingle = st
end

function UI:RefreshSmartVisual()
    local sb, t = self.smart, self.smart.target
    if self.inCombat then
        Paint(sb, "NONE")
        sb.text:SetText("|cffaaaaaaIn combat|r")
    elseif t then
        Paint(sb, t.choice.status == "REFRESH" and "REFRESH" or "MISSING")
        local r, g, b = ClassColor(t.class)
        sb.text:SetText(string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, ShortName(t.name)))
    else
        Paint(sb, "OK")
        sb.text:SetText("All set")
    end
    sb.icon1:SetTexture(t and ns.BlessingTexture(t.choice.blessing, false) or ns.BlessingTexture("KINGS", false))
    sb.icon1:SetDesaturated(not t)
end

function UI:PrepareSmart()
    if not self.smart or InCombatLockdown() then return end
    local t = ns.NextSmartTarget()
    local sb = self.smart
    if t then SetSpell(sb, ns.BlessingSpell(t.choice.blessing, false), t.unit) else ClearSecure(sb) end
    sb.target = t
    self:RefreshSmartVisual()
end

function UI:Refresh()
    if not self.main then return end
    if ns.needLayout and not InCombatLockdown() then
        self:Layout() -- calls Refresh again
        return
    end
    local canSet = not InCombatLockdown()
    for i = 1, self.numClasses or 0 do self:RefreshClassButton(self.classButtons[i], canSet) end
    if canSet then self:FitWidth() end
    self:PrepareSmart()
end

-- Same width for every class button: wide enough for the class showing the
-- most camp icons, never narrower than BTN_W. Out of combat only.
function UI:ButtonWidth(marks)
    local needed = 4 + ICON + 3 + ICON + 4 + marks * (MARK_SIZE + MARK_GAP) + TIMER_W + 6
    return math.max(BTN_W, needed)
end

-- Like Pally Power: the class button counts down the shortest time left on
-- my blessings in that class.
function UI:UpdateClassTimer(cb)
    if not cb.class then cb.text:SetText("") return end
    local least
    for _, st in ipairs(ns.ClassMembers(cb.class)) do
        local left = MyRemaining(st)
        if left and (not least or left < least) then least = left end
    end
    cb.text:SetText(least and (TimerColor(least) .. Logic.FormatClock(least) .. "|r") or "")
end

-- Every second, also in combat: only text changes (allowed on secure
-- buttons), from expiry times already known - no aura reads.
function UI:UpdateTimers()
    if not self.main or not self.main:IsShown() then return end
    for i = 1, self.numClasses or 0 do
        local cb = self.classButtons[i]
        self:UpdateClassTimer(cb)
        for _, pb in ipairs(cb.flyout.buttons) do
            local st = pb.guid and ns.units[pb.guid]
            if st and st.choice and (st.choice.status == "OK" or st.choice.status == "REFRESH")
                and st.connected and not st.dead and not st.isPending then
                local left = MyRemaining(st)
                if left then pb.text:SetText(TimerColor(left) .. Logic.FormatClock(left) .. "|r") end
            end
        end
    end
end

function UI:FitWidth()
    local most = 0
    for i = 1, self.numClasses or 0 do most = math.max(most, self.classButtons[i].numCampMarks or 0) end
    local w = self:ButtonWidth(most)
    self.buttonWidth = w
    -- Every button, every time: buttons created later (a new class joins
    -- the group) must not keep their creation width.
    for _, cb in ipairs(self.classButtons) do
        if cb:GetWidth() ~= w then cb:SetWidth(w) end
    end
    if self.smart and self.smart:GetWidth() ~= w then self.smart:SetWidth(w) end
    self.main:SetWidth(BAR_X + w)
end

---------------------------------------------------------------------------
-- tooltips (information only - nothing on the bar changes settings)
---------------------------------------------------------------------------
local SKIP_TEXT = {
    unknown = "you have not learned it",
    camp = "would replace %s",
    taken = "already given by %s",
}

function UI:PlayerTooltip(b)
    local st = b.guid and ns.units[b.guid]
    if not st then return end
    local tt = GameTooltip
    tt:SetOwner(b, "ANCHOR_RIGHT")
    tt:AddLine(st.name, ClassColor(st.class))
    tt:AddDoubleLine("Role", string.format("%s (%s)", Logic.RoleLabel(st.class, st.role), ROLE_SOURCE_TEXT[st.roleSource] or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
    if st.talentDetail then tt:AddDoubleLine("Talents", st.talentDetail, 0.8, 0.8, 0.8, 1, 1, 1) end

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
        local statusText = ({ OK = "has it", REFRESH = "refresh soon", MISSING = "missing",
            SWAP = "replaces your " .. BlessingShort(st.mine and st.mine.type) })[c.status] or c.status
        tt:AddDoubleLine("Click casts", ns.BlessingSpell(c.blessing, false) or "?", 1, 0.82, 0, 1, 1, 1)
        tt:AddDoubleLine(" ", statusText, 1, 1, 1, 0.8, 0.8, 0.8)
    elseif c.status == "BLOCKED" then
        tt:AddLine("Nothing to cast - every option would replace a camp buff.", 0.85, 0.5, 1, true)
    else
        tt:AddLine("Nothing to cast (no usable blessing in this role's list).", 0.7, 0.7, 0.7, true)
    end
    for _, s in ipairs(c.skipped or {}) do
        tt:AddLine(string.format("  skipped %s: %s", BlessingShort(s.blessing), string.format(SKIP_TEXT[s.reason] or s.reason, s.detail or "?")), 0.75, 0.75, 0.75)
    end
    if st.ppAssigned then tt:AddLine("Pally Power assigns you " .. BlessingShort(st.ppAssigned) .. " here.", 0.6, 0.8, 1) end
    if st.stale then tt:AddLine("* buff info is from before combat", 0.6, 0.6, 0.6) end
    if InCombatLockdown() then
        local set = b:GetAttribute("spell1")
        local want = c.blessing and ns.BlessingSpell(c.blessing, false)
        if set ~= want then
            tt:AddLine(string.format("In combat this button still casts %s; it updates after combat.",
                set or "nothing"), 1, 0.6, 0.3, true)
        end
    end
    tt:AddLine("Roles and priorities: /cbb config", 0.5, 0.8, 1)
    tt:Show()
end

function UI:ClassTooltip(cb)
    if not cb.class then return end
    local info = self:GreaterInfo(cb.class)
    local tt = GameTooltip
    tt:SetOwner(cb, "ANCHOR_LEFT")
    tt:AddLine(ClassLabel(cb.class), ClassColor(cb.class))
    tt:AddDoubleLine("Left-click", info.blessing and ns.BlessingSpell(info.blessing, true) or "no Greater Blessing set", 0.8, 0.8, 0.8, 1, 1, 1)
    if info.fromPP then tt:AddLine("(your Pally Power assignment)", 0.6, 0.8, 1) end
    local nxt = cb.nextSingle
    if nxt and nxt.choice and nxt.choice.blessing then
        tt:AddDoubleLine("Right-click", string.format("%s on %s", BlessingShort(nxt.choice.blessing), ShortName(nxt.name)), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        tt:AddDoubleLine("Right-click", "nobody in range needs one", 0.8, 0.8, 0.8, 0.6, 1, 0.6)
    end
    if info.blessing then
        tt:AddDoubleLine("Have it", string.format("%d / %d", info.have, #info.members), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if info.need > 0 then
        tt:AddDoubleLine("Need a single blessing", tostring(info.need), 0.8, 0.8, 0.8, 1, 0.5, 0.5)
    end
    if #info.conflicts > 0 then
        tt:AddLine(" ")
        tt:AddLine(info.blocked and "BLOCKED - it would replace:" or "Warning - it would replace:", 0.85, 0.5, 1)
        for _, cf in ipairs(info.conflicts) do tt:AddLine(string.format("  %s's %s", cf.name, cf.camp), 1, 1, 1) end
        tt:AddLine("Use the single blessings instead.", 0.8, 0.8, 0.8)
    end
    if #info.replaces > 0 then
        tt:AddLine("Replaces your single blessing on: " .. table.concat(info.replaces, ", "), 1, 0.6, 0.3, true)
    end
    if #info.notIdeal > 0 then
        tt:AddLine("Role assignments differ: " .. table.concat(info.notIdeal, ", "), 0.8, 0.8, 0.8, true)
    end
    if info.blessing and not info.known then tt:AddLine("You have not learned this Greater Blessing.", 0.7, 0.7, 0.7) end
    if InCombatLockdown() then tt:AddLine("In combat: player list opens after combat.", 0.6, 0.6, 0.6) end
    tt:Show()
end

function UI:SmartTooltip(btn)
    local tt = GameTooltip
    tt:SetOwner(btn, "ANCHOR_LEFT")
    tt:AddLine("Smart blessing")
    local t = btn.target
    if t then
        tt:AddDoubleLine("Next", string.format("%s on %s", BlessingShort(t.choice.blessing), ShortName(t.name)), 0.8, 0.8, 0.8, 1, 1, 1)
        local n = ns.CountNeeding()
        if n > 1 then tt:AddDoubleLine("Still needing", tostring(n), 0.8, 0.8, 0.8, 1, 0.5, 0.5) end
    else
        tt:AddLine("Nobody in range needs a blessing.", 0.6, 1, 0.6)
    end
    tt:AddLine("Bind a key: Key Bindings > AddOns > Camelus' Better Blessings", 0.6, 0.6, 0.6, true)
    tt:Show()
end
