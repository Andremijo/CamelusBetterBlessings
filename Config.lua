-- Camelus' Better Blessings - assignment grid and options window
local _, ns = ...
local Logic = ns.Logic

local Config = {}
ns.Config = Config

local ROW_H = 22
local SLOT = 20
local LABEL_W = 150
local PAD = 12
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY = "Interface\\Buttons\\UI-EmptySlot-Disabled"

local OPTIONS = {
    { key = "protectCamp",    label = "Never overwrite camp buffs",          tip = "Skip any blessing that would replace a camp buff on that player and use the next one in the list." },
    { key = "protectGreater", label = "Block Greaters that overwrite camps", tip = "Disable a class's Greater Blessing button if any member of that class has a camp buff it would replace." },
    { key = "respectOthers",  label = "Respect other paladins",              tip = "Skip blessings another paladin already put on the player." },
    { key = "warnTarget",     label = "Warn about target's camp buffs",      tip = "Show which blessings would overwrite a camp buff on your current target (also covers casts from your action bars)." },
    { key = "tooltip",        label = "Camp buffs in unit tooltips",         tip = "Add a line to player tooltips listing their camp buffs." },
    { key = "showSolo",       label = "Show bar when solo" },
    { key = "collapseRaid",   label = "Collapse classes in raids",           tip = "In raids, start with only the Greater Blessing rows visible." },
    { key = "locked",         label = "Lock bar position" },
}

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
    if key and not ns.known[key] and not btn.isGreater then GameTooltip:AddLine("You have not learned this blessing.", 1, 0.4, 0.4) end
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
    if key then
        b.icon:SetTexture(ns.BlessingTexture(key, greater))
        local known = greater and ns.BLESSINGS[key].greaterKnown or (not greater and ns.known[key])
        b.icon:SetDesaturated(not known)
        b.icon:SetAlpha(known and 1 or 0.6)
    else
        b.icon:SetTexture(EMPTY)
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(0.6)
    end
end

function Config:Create()
    if self.frame then return end
    local rows = 0
    for _, class in ipairs(ns.CLASS_ORDER) do rows = rows + #ns.CLASS_ROLES[class] end
    local width = PAD * 2 + LABEL_W + (SLOT + 10) + ns.MAX_PRIORITY * (SLOT + 6) + 10
    local optRows = math.ceil(#OPTIONS / 2)
    local height = 74 + rows * ROW_H + 14 + optRows * 24 + 46

    local f = CreateFrame("Frame", "CBB_ConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(math.max(width, 380), height)
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

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Camelus' Better Blessings")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", PAD, -38)
    help:SetWidth(f:GetWidth() - PAD * 2)
    help:SetJustifyH("LEFT")
    help:SetText("Each class/role row lists what you give, in order. Later choices are used when an earlier one would replace a camp buff.")

    local headerY = -66
    local function Header(text, x)
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", f, "TOPLEFT", x, headerY)
        h:SetText(text)
    end
    local gx = PAD + LABEL_W
    local px = gx + SLOT + 10
    Header("Class / role", PAD)
    Header("Gr.", gx)
    for i = 1, ns.MAX_PRIORITY do Header(tostring(i), px + (i - 1) * (SLOT + 6) + 6) end

    self.rows = {}
    local y = headerY - 14
    for _, class in ipairs(ns.CLASS_ORDER) do
        for ri, role in ipairs(ns.CLASS_ROLES[class]) do
            local row = { class = class, role = role, slots = {} }
            local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 4)
            label:SetWidth(LABEL_W - 4)
            label:SetJustifyH("LEFT")
            local r, g, b = ns.ClassColor(class)
            local rc = ns.ROLE_INFO[role].color
            label:SetText(string.format("%s%s|r  |cff%02x%02x%02x%s|r",
                string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255), ri == 1 and ns.ClassLabel(class) or "",
                rc[1] * 255, rc[2] * 255, rc[3] * 255, ns.ROLE_INFO[role].label))
            if ri == 1 then
                local gb = MakeSlot(f, function(btn, dir)
                    ns.db.greater[class] = Logic.CycleBlessing(ns.GetGreater(class), dir, true)
                    Config:Refresh() ns.RequestUpdate() SlotTooltip(btn)
                end)
                gb.isGreater = true
                gb:SetPoint("TOPLEFT", f, "TOPLEFT", gx, y)
                row.greater = gb
            end
            for i = 1, ns.MAX_PRIORITY do
                local sb = MakeSlot(f, function(btn, dir)
                    local key = Logic.AssignKey(class, role)
                    local cur = Logic.GetPriority(ns.db.assign, class, role)
                    local copy = {}
                    for k = 1, ns.MAX_PRIORITY do copy[k] = cur[k] or false end
                    copy[btn.slot] = Logic.CycleBlessing(copy[btn.slot], dir, true)
                    ns.db.assign[key] = copy
                    Config:Refresh() ns.RequestUpdate() SlotTooltip(btn)
                end)
                sb.slot = i
                sb:SetPoint("TOPLEFT", f, "TOPLEFT", px + (i - 1) * (SLOT + 6), y)
                row.slots[i] = sb
            end
            if ri == 1 and y ~= headerY - 14 then
                local line = f:CreateTexture(nil, "ARTWORK")
                line:SetColorTexture(1, 1, 1, 0.12)
                line:SetHeight(1)
                line:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y + 1)
                line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y + 1)
            end
            self.rows[#self.rows + 1] = row
            y = y - ROW_H
        end
    end

    -- options
    y = y - 10
    self.checks = {}
    local colW = (f:GetWidth() - PAD * 2) / 2
    for i, o in ipairs(OPTIONS) do
        local col = (i - 1) % 2
        local rowY = y - math.floor((i - 1) / 2) * 24
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * colW, rowY)
        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        text:SetWidth(colW - 28)
        text:SetJustifyH("LEFT")
        text:SetText(o.label)
        cb.key = o.key
        cb:SetScript("OnClick", function(self)
            ns.opt[self.key] = self:GetChecked() and true or false
            ns.RequestUpdate(true)
            if ns.UI then ns.UI:UpdateVisibility() end
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
    end

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(130, 22)
    reset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    reset:SetText("Reset assignments")
    reset:SetScript("OnClick", function()
        wipe(ns.db.assign) wipe(ns.db.greater)
        Config:Refresh() ns.RequestUpdate()
    end)

    local campBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    campBtn:SetSize(130, 22)
    campBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 14)
    campBtn:SetText("List camp buffs")
    campBtn:SetScript("OnClick", function() SlashCmdList.CAMELUSBETTERBLESSINGS("camp list") end)

    f:SetScript("OnShow", function() Config:Refresh() end)
end

function Config:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    for _, row in ipairs(self.rows) do
        if row.greater then PaintSlot(row.greater, ns.GetGreater(row.class), true) end
        local p = Logic.GetPriority(ns.db.assign, row.class, row.role)
        for i = 1, ns.MAX_PRIORITY do PaintSlot(row.slots[i], p[i], false) end
    end
    for _, cb in ipairs(self.checks) do cb:SetChecked(ns.opt[cb.key] and true or false) end
end

function Config:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end
