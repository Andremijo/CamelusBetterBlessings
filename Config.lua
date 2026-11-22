-- Camelus' Better Blessings - settings window
--   Blessings : what each class/role gets, in priority order, + Greater per class
--   Players   : who plays which role (automatic, or set by you)
--   Options   : behaviour and bar settings
-- Everything that changes how the addon behaves lives here; the bar only casts.
local _, ns = ...
local Logic = ns.Logic

local Config = {}
ns.Config = Config

local WIDTH, HEIGHT = 440, 650
local PAD = 14
local CONTENT_TOP = -64
local ROW_H = 20
local SLOT = 20
local LABEL_W = 170
local PLAYER_ROW_H = 36
local EMPTY = "Interface\\Buttons\\UI-EmptySlot-Disabled"

local OPTIONS = {
    { key = "protectCamp",    label = "Never overwrite camp buffs",           tip = "Skip any blessing that would replace a camp buff on that player and use their next choice." },
    { key = "protectGreater", label = "Block Greater Blessings that would overwrite a camp buff", tip = "A class's Greater Blessing cannot be cast while any member of that class has a camp buff it would replace." },
    { key = "respectOthers",  label = "Respect other paladins' blessings",    tip = "Skip blessings another paladin already put on the player." },
    { key = "warnTarget",     label = "Warn about my target's camp buffs",    tip = "Shows a line under the bar listing which blessings would overwrite a camp buff on your target (covers casts from your action bars too)." },
    { key = "tooltip",        label = "Show camp buffs in unit tooltips" },
    { key = "showSmart",      label = "Show the smart button on the bar",     tip = "The smart button blesses the next player who needs it. Its key binding (Key Bindings > AddOns) works even when it is hidden." },
    { key = "showSolo",       label = "Show the bar when not in a group" },
    { key = "locked",         label = "Lock the bar's position" },
}

local function Changed(rebuild)
    ns.RequestUpdate(rebuild)
    if ns.UI then ns.UI:UpdateVisibility() end
end

local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end

local function NewLabel(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

local function SmallButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 120, 22)
    b:SetText(text)
    return b
end

---------------------------------------------------------------------------
-- Blessings tab
---------------------------------------------------------------------------
local function SlotTooltip(btn)
    local key = btn.value
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if btn.isGreater then
        GameTooltip:AddLine(key and ns.BlessingSpell(key, true) or "No Greater Blessing")
        GameTooltip:AddLine("Greater Blessings hit the whole class, so they cannot follow roles.", 0.8, 0.8, 0.8, true)
    else
        GameTooltip:AddLine(string.format("Choice %d: %s", btn.slot, key and ns.BlessingSpell(key, false) or "empty"))
        if btn.slot == 1 then
            GameTooltip:AddLine("What this class/role normally gets from you.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Used when the earlier choices would overwrite a camp buff, you do not know them, or another paladin already gave them.", 0.8, 0.8, 0.8, true)
        end
    end
    if key and not btn.isGreater and not ns.known[key] then GameTooltip:AddLine("You have not learned this blessing.", 1, 0.4, 0.4) end
    GameTooltip:AddLine("Left-click / wheel: next   Right-click: previous", 0.5, 0.8, 1)
    GameTooltip:Show()
end

local function MakeSlot(parent, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SLOT, SLOT)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    b:SetScript("OnClick", function(self, mouse) onChange(self, mouse == "RightButton" and -1 or 1) end)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(self, delta) onChange(self, delta > 0 and -1 or 1) end)
    b:SetScript("OnEnter", SlotTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function PaintSlot(b, key, greater)
    b.value = key or nil
    if key and ns.BLESSINGS[key] then
        b.icon:SetTexture(ns.BlessingTexture(key, greater))
        local known
        if greater then known = ns.BLESSINGS[key].greaterKnown else known = ns.known[key] end
        b.icon:SetDesaturated(not known)
        b.icon:SetAlpha(known and 1 or 0.6)
    else
        b.icon:SetTexture(EMPTY)
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(0.6)
    end
end

function Config:BuildBlessingsTab(tab)
    local help = NewLabel(tab, "GameFontHighlightSmall",
        "For each class (and each role it can play): the blessings you give, in order. A later choice is used when an earlier one would replace a camp buff.")
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetWidth(WIDTH - PAD * 2)

    local headerY = -34
    local gx = LABEL_W
    local px = gx + SLOT + 16
    local function Header(text, x)
        local h = NewLabel(tab, "GameFontNormalSmall", text)
        h:SetPoint("TOPLEFT", tab, "TOPLEFT", x, headerY)
    end
    Header("Class / role", 0)
    Header("Greater", gx - 6)
    for i = 1, ns.MAX_PRIORITY do Header(tostring(i), px + (i - 1) * (SLOT + 8) + 6) end

    -- One header row per class (icon, name, Greater Blessing). Classes with
    -- several roles get an indented row per role under it; single-role
    -- classes keep their blessing slots on the header row itself.
    self.slotRows = {}
    local y = headerY - 16
    local function Slots(row, class, role, rowY)
        for i = 1, ns.MAX_PRIORITY do
            local sb = MakeSlot(tab, function(btn, dir)
                local cur = Logic.GetPriority(ns.db.assign, class, role)
                local copy = {}
                for k = 1, ns.MAX_PRIORITY do copy[k] = cur[k] or false end
                copy[btn.slot] = Logic.CycleBlessing(copy[btn.slot], dir, true)
                ns.db.assign[Logic.AssignKey(class, role)] = copy
                Config:Refresh() Changed() SlotTooltip(btn)
            end)
            sb.slot = i
            sb.class, sb.role = class, role
            sb:SetPoint("TOPLEFT", tab, "TOPLEFT", px + (i - 1) * (SLOT + 8), rowY)
            row.slots[i] = sb
        end
    end
    for ci, class in ipairs(ns.CLASS_ORDER) do
        local roles = ns.CLASS_ROLES[class]
        local single = #roles == 1
        if ci > 1 then
            local line = tab:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 1, 1, 0.15)
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y + 2)
            line:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, y + 2)
        end
        -- class header
        local header = { class = class, slots = {}, isHeader = true }
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y - 2)
        ns.SetClassIcon(icon, class)
        local name = NewLabel(tab, "GameFontNormal", ns.ClassLabel(class))
        name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        name:SetTextColor(ns.ClassColor(class))
        header.label = name
        local gb = MakeSlot(tab, function(btn, dir)
            ns.db.greater[class] = Logic.CycleBlessing(ns.GetGreater(class), dir, true)
            Config:Refresh() Changed() SlotTooltip(btn)
        end)
        gb.isGreater = true
        gb:SetPoint("TOPLEFT", tab, "TOPLEFT", gx, y)
        header.greater = gb
        if single then
            header.role = roles[1]
            Slots(header, class, roles[1], y)
        end
        self.slotRows[#self.slotRows + 1] = header
        y = y - ROW_H
        -- role sub-rows
        if not single then
            for _, role in ipairs(roles) do
                local row = { class = class, role = role, slots = {} }
                local rc = ns.ROLE_INFO[role].color
                local label = NewLabel(tab, "GameFontHighlightSmall", Logic.RoleLabel(class, role))
                label:SetPoint("TOPLEFT", tab, "TOPLEFT", 22, y - 4)
                label:SetTextColor(rc[1], rc[2], rc[3])
                row.label = label
                Slots(row, class, role, y)
                self.slotRows[#self.slotRows + 1] = row
                y = y - ROW_H
            end
        end
    end

    local reset = SmallButton(tab, "Reset to defaults", 140)
    reset:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y - 8)
    reset:SetScript("OnClick", function()
        wipe(ns.db.assign) wipe(ns.db.greater)
        Config:Refresh() Changed()
    end)
    local camps = SmallButton(tab, "List camp buffs", 140)
    camps:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    camps:SetScript("OnClick", function() SlashCmdList.CAMELUSBETTERBLESSINGS("camp list") end)
end

---------------------------------------------------------------------------
-- Players tab
---------------------------------------------------------------------------
local function RoleButtonText(st)
    local manual = ns.db.overrides[st.name]
    local role = manual or st.role
    local info = ns.ROLE_INFO[role]
    local text = info and (Hex(info.color[1], info.color[2], info.color[3]) .. Logic.RoleLabel(st.class, role) .. "|r") or "?"
    if not manual then text = "Auto: " .. text end
    return text
end

local function MakePlayerRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - PAD * 2 - 8, PLAYER_ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * PLAYER_ROW_H)
    if i % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end
    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(18, 18)
    row.classIcon:SetPoint("TOPLEFT", 2, -4)
    row.name = NewLabel(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.classIcon, "RIGHT", 6, 0)
    row.name:SetWidth(120)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    local rb = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    rb:SetSize(150, 20)
    rb:SetPoint("TOPLEFT", row, "TOPLEFT", 150, -3)
    rb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rb:SetScript("OnClick", function(self, mouse)
        local st = row.guid and ns.units[row.guid]
        if not st then return end
        ns.db.overrides[st.name] = Logic.CycleRole(st.class, ns.db.overrides[st.name], mouse == "RightButton" and -1 or 1)
        Changed()
        Config:RefreshPlayers(true)
    end)
    rb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Role")
        GameTooltip:AddLine("Auto = detected from group role and talents.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Left-click: next   Right-click: previous", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.roleButton = rb

    row.prio = {}
    for j = 1, ns.MAX_PRIORITY do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(18, 18)
        t:SetPoint("TOPLEFT", rb, "TOPRIGHT", 8 + (j - 1) * 20, 1)
        t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.prio[j] = t
    end
    row.detail = NewLabel(row, "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.classIcon, "BOTTOMLEFT", 24, -1)
    row.detail:SetWidth(WIDTH - PAD * 2 - 40)
    if row.detail.SetWordWrap then row.detail:SetWordWrap(false) end
    return row
end

function Config:BuildPlayersTab(tab)
    local help = NewLabel(tab, "GameFontHighlightSmall",
        "Roles decide which row of the Blessings tab a player uses. Leave them on Auto, or click to set one yourself (saved per player).")
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetWidth(WIDTH - PAD * 2)

    local scroll = CreateFrame("ScrollFrame", nil, tab)
    scroll:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -36)
    scroll:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 34)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - PAD * 2, 10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, content:GetHeight() - self:GetHeight())
        local v = math.min(max, math.max(0, self:GetVerticalScroll() - delta * PLAYER_ROW_H))
        self:SetVerticalScroll(v)
    end)
    self.playerScroll, self.playerContent, self.playerRows = scroll, content, {}

    self.emptyText = NewLabel(content, "GameFontDisable", "Join a group to set up roles for its members.")
    self.emptyText:SetPoint("TOPLEFT", 0, -PLAYER_ROW_H)

    local reset = SmallButton(tab, "Set everyone to Auto", 160)
    reset:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 4)
    reset:SetScript("OnClick", function()
        for _, guid in ipairs(ns.order) do
            local st = ns.units[guid]
            if st then ns.db.overrides[st.name] = nil end
        end
        Changed()
        Config:RefreshPlayers(true)
    end)
end

-- force: refresh even if the tab is not visible yet (called right after a click)
function Config:RefreshPlayers(force)
    if not self.frame or not self.frame:IsShown() or self.activeTab ~= "players" then
        if not force then return end
    end
    if not self.playerContent then return end
    if force then ns.EvaluateAll() end
    local n = 0
    for _, guid in ipairs(ns.order) do
        local st = ns.units[guid]
        if st then
            n = n + 1
            local row = self.playerRows[n] or MakePlayerRow(self.playerContent, n)
            self.playerRows[n] = row
            row.guid = guid
            ns.SetClassIcon(row.classIcon, st.class)
            row.name:SetText(ns.ShortName(st.name))
            row.name:SetTextColor(ns.ClassColor(st.class))
            row.roleButton:SetText(RoleButtonText(st))
            local roles = ns.CLASS_ROLES[st.class] or {}
            row.roleButton:SetEnabled(#roles > 1)
            for j = 1, ns.MAX_PRIORITY do
                local key = st.priority and st.priority[j]
                local t = row.prio[j]
                if key and ns.BLESSINGS[key] then t:SetTexture(ns.BlessingTexture(key, false)) t:Show() else t:Hide() end
            end
            local detected
            if #roles <= 1 then
                detected = "Only one role for this class."
            else
                -- what Auto would pick, and why
                local autoRole, src = Logic.ResolveRole(st.class, nil, st.groupRole, st.talentRole)
                detected = string.format("Auto picks %s (%s%s)", Logic.RoleLabel(st.class, autoRole), ns.ROLE_SOURCE_TEXT[src] or "?",
                    (src == "talents" and st.talentDetail) and (": " .. st.talentDetail) or "")
            end
            row.detail:SetText(detected)
            row:Show()
        end
    end
    for i = n + 1, #self.playerRows do self.playerRows[i]:Hide() self.playerRows[i].guid = nil end
    self.playerContent:SetHeight(math.max(10, n * PLAYER_ROW_H))
    self.emptyText:SetShown(n <= 1)
end

---------------------------------------------------------------------------
-- Options tab
---------------------------------------------------------------------------
local function Stepper(tab, y, label, get, set, step, min, max, fmt)
    local text = NewLabel(tab, "GameFontHighlight")
    text:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, y)
    local minus = SmallButton(tab, "-", 24)
    minus:SetPoint("TOPLEFT", tab, "TOPLEFT", 260, y + 4)
    local plus = SmallButton(tab, "+", 24)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local function Update() text:SetText(string.format("%s: |cffffffff" .. fmt .. "|r", label, get())) end
    minus:SetScript("OnClick", function() set(math.max(min, get() - step)) Update() end)
    plus:SetScript("OnClick", function() set(math.min(max, get() + step)) Update() end)
    return Update
end

function Config:BuildOptionsTab(tab)
    self.checks = {}
    local y = 0
    for _, o in ipairs(OPTIONS) do
        local cb = CreateFrame("CheckButton", nil, tab, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y)
        local text = NewLabel(cb, "GameFontHighlight", o.label)
        text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        text:SetWidth(WIDTH - PAD * 2 - 32)
        cb.key = o.key
        cb:SetScript("OnClick", function(self)
            ns.opt[self.key] = self:GetChecked() and true or false
            Changed(true)
            ns.UpdateTargetWarning()
        end)
        if o.tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(o.label)
                GameTooltip:AddLine(o.tip, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        self.checks[#self.checks + 1] = cb
        y = y - 28
    end
    y = y - 10
    self.steppers = {
        Stepper(tab, y, "Refresh warning (minutes left)", function() return ns.opt.refreshMinutes or 5 end,
            function(v) ns.opt.refreshMinutes = v Changed() end, 1, 0, 30, "%d"),
        Stepper(tab, y - 30, "Bar scale", function() return ns.opt.scale or 1 end,
            function(v) ns.opt.scale = math.floor(v * 10 + 0.5) / 10 if ns.UI then ns.UI:ApplyScale() end end, 0.1, 0.5, 2, "%.1f"),
    }
    local note = NewLabel(tab, "GameFontDisableSmall",
        "Smart button key binding: Key Bindings > AddOns > Camelus' Better Blessings.  More: /cbb help")
    note:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, y - 70)
    note:SetWidth(WIDTH - PAD * 2)
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local TABS = {
    { key = "blessings", label = "Blessings" },
    { key = "players",   label = "Players" },
    { key = "options",   label = "Options" },
}

function Config:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "CBB_ConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    f:Hide()
    tinsert(UISpecialFrames, "CBB_ConfigFrame")
    self.frame = f

    local title = NewLabel(f, "GameFontNormalLarge", "Camelus' Better Blessings")
    title:SetPoint("TOP", 0, -14)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    self.tabFrames, self.tabButtons = {}, {}
    for i, t in ipairs(TABS) do
        local b = SmallButton(f, t.label, 100)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * 104, -34)
        b:SetScript("OnClick", function() Config:ShowTab(t.key) end)
        self.tabButtons[t.key] = b
        local tab = CreateFrame("Frame", nil, f)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, CONTENT_TOP)
        tab:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
        tab:Hide()
        self.tabFrames[t.key] = tab
    end
    self:BuildBlessingsTab(self.tabFrames.blessings)
    self:BuildPlayersTab(self.tabFrames.players)
    self:BuildOptionsTab(self.tabFrames.options)

    f:SetScript("OnShow", function() Config:Refresh() end)
    self:ShowTab("blessings")
end

function Config:ShowTab(key)
    self.activeTab = key
    for k, tab in pairs(self.tabFrames) do tab:SetShown(k == key) end
    for k, b in pairs(self.tabButtons) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
    end
    self:Refresh()
end

function Config:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    for _, row in ipairs(self.slotRows) do
        if row.greater then PaintSlot(row.greater, ns.GetGreater(row.class), true) end
        if row.role then
            local p = Logic.GetPriority(ns.db.assign, row.class, row.role)
            for i = 1, ns.MAX_PRIORITY do PaintSlot(row.slots[i], p[i], false) end
        end
    end
    for _, cb in ipairs(self.checks) do cb:SetChecked(ns.opt[cb.key] and true or false) end
    for _, update in ipairs(self.steppers) do update() end
    if self.activeTab == "players" then self:RefreshPlayers(true) end
end

function Config:Toggle(tab)
    self:Create()
    if tab then
        self.frame:Show()
        self:ShowTab(tab)
        return
    end
    self.frame:SetShown(not self.frame:IsShown())
end

-- Entry in the game's Settings > AddOns list that opens this window.
function Config:RegisterSettingsPanel()
    if self.registered or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    self.registered = true
    pcall(function()
        local panel = CreateFrame("Frame")
        panel.name = "Camelus' Better Blessings"
        local t = NewLabel(panel, "GameFontNormalLarge", panel.name)
        t:SetPoint("TOPLEFT", 16, -16)
        local b = SmallButton(panel, "Open settings", 160)
        b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
        b:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
            Config:Toggle("blessings")
        end)
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    end)
end
