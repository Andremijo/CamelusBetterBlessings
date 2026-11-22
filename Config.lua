-- Camelus' Better Blessings - settings window
--   Blessings : what each class/role gets, in priority order, + Greater per class
--   Players   : who plays which role (automatic, or set by you)
--   Options   : behaviour and bar settings
-- Everything that changes how the addon behaves lives here; the bar only casts.
local _, ns = ...
local Logic = ns.Logic

local Config = {}
ns.Config = Config

local WIDTH, HEIGHT = 600, 650
local PAD = 14
local CONTENT_TOP = -64
local ROW_H = 24
local SLOT = 20
local EMPTY = "Interface\\Buttons\\UI-EmptySlot-Disabled"

local OPTIONS = {
    { key = "protectCamp",    label = "Never overwrite camp buffs",           tip = "Skip any blessing that would replace a camp buff on that player and use their next choice." },
    { key = "protectGreater", label = "Block Greater Blessings that would overwrite a camp buff", tip = "A class's Greater Blessing cannot be cast while any member of that class has a camp buff it would replace." },
    { key = "respectOthers",  label = "Respect other paladins' blessings",    tip = "Skip blessings another paladin already put on the player." },
    { key = "warnTarget",     label = "Warn about my target's camp buffs",    tip = "Shows a line under the bar listing which blessings would overwrite a camp buff on your target (covers casts from your action bars too)." },
    { key = "tooltip",        label = "Show camp buffs in unit tooltips" },
    { key = "flyoutLeft",     label = "Open the player list to the left",     tip = "When you hover a class on the bar, its player list opens to the left of the bar instead of the right." },
    { key = "showSmart",      label = "Show the smart button on the bar",     tip = "The smart button blesses the next player who needs it. Its key binding (Key Bindings > AddOns) works even when it is hidden." },
    { key = "followPP",       label = "Follow my Pally Power assignments",    tip = "When another paladin assigns you blessings in Pally Power, those come first. Camp buff protection still applies: if the assigned blessing would replace a camp buff, your own lists are used." },
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

-- Two columns of classes, so there is room for spacing without the window
-- getting taller: rows are ROW_H apart (slots are SLOT tall, so 4 px of air)
-- and each class starts after CLASS_GAP, with its divider line in the
-- middle of that gap - never on top of the icons.
local BLESS_COLUMNS = {
    { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST" },
    { "SHAMAN", "MAGE", "WARLOCK", "DRUID" },
}
local COL_GAP = 24
local CLASS_GAP = 12

function Config:BuildBlessingsTab(tab)
    local help = NewLabel(tab, "GameFontHighlightSmall",
        "For each class (and each role it can play): the blessings you give, in order. A later choice is used when an earlier one would replace a camp buff.")
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetWidth(WIDTH - PAD * 2)

    local colW = (WIDTH - PAD * 2 - COL_GAP) / 2
    local px = colW - ns.MAX_PRIORITY * (SLOT + 8) + 8   -- first priority slot, from the column's left edge
    local gx = px - SLOT - 18                            -- Greater slot
    local headerY = -34
    self.slotRows = {}
    self.dividers = {}
    local lowest = headerY

    local function Slots(row, class, role, ox, rowY)
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
            sb:SetPoint("TOPLEFT", tab, "TOPLEFT", ox + px + (i - 1) * (SLOT + 8), rowY)
            row.slots[i] = sb
        end
    end

    for colIndex, classes in ipairs(BLESS_COLUMNS) do
        local ox = (colIndex - 1) * (colW + COL_GAP)
        local function Header(text, x)
            local h = NewLabel(tab, "GameFontNormalSmall", text)
            h:SetPoint("TOPLEFT", tab, "TOPLEFT", ox + x, headerY)
        end
        Header("Class / role", 0)
        Header("Greater", gx - 8)
        for i = 1, ns.MAX_PRIORITY do Header(tostring(i), px + (i - 1) * (SLOT + 8) + 6) end

        local y = headerY - 18
        for ci, class in ipairs(classes) do
            local roles = ns.CLASS_ROLES[class]
            local single = #roles == 1
            if ci > 1 then
                -- divider in the middle of the gap between two classes
                y = y - CLASS_GAP
                local line = tab:CreateTexture(nil, "ARTWORK")
                line:SetColorTexture(1, 1, 1, 0.15)
                line:SetHeight(1)
                line:SetPoint("TOPLEFT", tab, "TOPLEFT", ox, y + CLASS_GAP / 2 + 2)
                line:SetWidth(colW)
                self.dividers[#self.dividers + 1] = { tex = line, x = ox, y = y + CLASS_GAP / 2 + 2, w = colW }
            end
            -- class header
            local header = { class = class, slots = {}, isHeader = true }
            local icon = tab:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("TOPLEFT", tab, "TOPLEFT", ox, y - 2)
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
            gb:SetPoint("TOPLEFT", tab, "TOPLEFT", ox + gx, y)
            header.greater = gb
            if single then
                header.role = roles[1]
                Slots(header, class, roles[1], ox, y)
            end
            self.slotRows[#self.slotRows + 1] = header
            y = y - ROW_H
            -- role sub-rows
            if not single then
                for _, role in ipairs(roles) do
                    local row = { class = class, role = role, slots = {} }
                    local rc = ns.ROLE_INFO[role].color
                    local label = NewLabel(tab, "GameFontHighlightSmall", Logic.RoleLabel(class, role))
                    label:SetPoint("TOPLEFT", tab, "TOPLEFT", ox + 22, y - 4)
                    label:SetTextColor(rc[1], rc[2], rc[3])
                    row.label = label
                    Slots(row, class, role, ox, y)
                    self.slotRows[#self.slotRows + 1] = row
                    y = y - ROW_H
                end
            end
        end
        lowest = math.min(lowest, y)
    end
    local y = lowest

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
-- Players tab: laid out like the raid window - Group 1-8 in a 2 x 4 grid,
-- up to five players each, so a 40-player raid fits without scrolling.
-- Details (what Auto picked and why, blessing order) are in the tooltip.
---------------------------------------------------------------------------
local GROUP_GAP = 6
local GROUP_W = (WIDTH - PAD * 2 - GROUP_GAP) / 2
local SLOT_H = 19
local GROUP_HEADER = 16
local GROUP_H = GROUP_HEADER + 5 * SLOT_H + 6
local ROLE_BTN_W = 84

local function RoleButtonText(st)
    local manual = ns.db.overrides[st.name]
    local role = manual or st.role
    local info = ns.ROLE_INFO[role]
    if not info then return "?" end
    local text = Hex(info.color[1], info.color[2], info.color[3]) .. Logic.RoleShort(st.class, role) .. "|r"
    if not manual then text = "|cff999999Auto|r " .. text end
    return text
end

local function PlayerDetailTooltip(owner, st)
    if not st then return end
    local tt = GameTooltip
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:AddLine(st.name, ns.ClassColor(st.class))
    local manual = ns.db.overrides[st.name]
    local roles = ns.CLASS_ROLES[st.class] or {}
    if manual then
        tt:AddDoubleLine("Role", Logic.RoleLabel(st.class, manual) .. " (set by you)", 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if #roles <= 1 then
        tt:AddLine("Only one role for this class.", 0.7, 0.7, 0.7)
    else
        local autoRole, src = Logic.ResolveRole(st.class, nil, st.groupRole, st.talentRole)
        tt:AddDoubleLine("Auto picks", string.format("%s (%s)", Logic.RoleLabel(st.class, autoRole), ns.ROLE_SOURCE_TEXT[src] or "?"),
            0.8, 0.8, 0.8, 1, 1, 1)
        if st.talentDetail then tt:AddDoubleLine("Talents", st.talentDetail, 0.8, 0.8, 0.8, 1, 1, 1) end
    end
    local order = {}
    for j = 1, ns.MAX_PRIORITY do
        local key = st.priority and st.priority[j]
        if key and ns.BLESSINGS[key] then order[#order + 1] = ns.BlessingShort(key) end
    end
    tt:AddDoubleLine("Blessings", #order > 0 and table.concat(order, " > ") or "none", 0.8, 0.8, 0.8, 1, 0.82, 0)
    if #roles > 1 then tt:AddLine("Role button: left-click next, right-click previous", 0.5, 0.8, 1) end
    tt:Show()
end

local function MakePlayerRow(box, slot)
    local row = CreateFrame("Frame", nil, box)
    row:SetSize(GROUP_W - 8, SLOT_H)
    row:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -GROUP_HEADER - (slot - 1) * SLOT_H)
    row:EnableMouse(true)
    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(14, 14)
    row.classIcon:SetPoint("LEFT", row, "LEFT", 2, 0)

    local rb = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    rb:SetSize(ROLE_BTN_W, SLOT_H - 1)
    rb:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    rb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if rb.SetNormalFontObject then
        rb:SetNormalFontObject("GameFontHighlightSmall")
        rb:SetHighlightFontObject("GameFontHighlightSmall")
        if rb.SetDisabledFontObject then rb:SetDisabledFontObject("GameFontDisableSmall") end
    end
    rb:SetScript("OnClick", function(self, mouse)
        local st = row.guid and ns.units[row.guid]
        if not st then return end
        ns.db.overrides[st.name] = Logic.CycleRole(st.class, ns.db.overrides[st.name], mouse == "RightButton" and -1 or 1)
        Changed()
        Config:RefreshPlayers(true)
        PlayerDetailTooltip(self, ns.units[row.guid])
    end)
    rb:SetScript("OnEnter", function(self) PlayerDetailTooltip(self, row.guid and ns.units[row.guid]) end)
    rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.roleButton = rb

    row.name = NewLabel(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", rb, "LEFT", -4, 0)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row:SetScript("OnEnter", function(self) PlayerDetailTooltip(self, row.guid and ns.units[row.guid]) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:Hide()
    return row
end

function Config:BuildPlayersTab(tab)
    local help = NewLabel(tab, "GameFontHighlightSmall",
        "Roles decide which row of the Blessings tab a player uses. Auto detects them; click a role to set it yourself (saved per player). Hover a player for details.")
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetWidth(WIDTH - PAD * 2)

    self.groupBoxes, self.slotsByGroup = {}, {}
    for g = 1, 8 do
        local col, line = (g - 1) % 2, math.floor((g - 1) / 2)
        local box = CreateFrame("Frame", nil, tab, "BackdropTemplate")
        box:SetSize(GROUP_W, GROUP_H)
        box:SetPoint("TOPLEFT", tab, "TOPLEFT", col * (GROUP_W + GROUP_GAP), -32 - line * (GROUP_H + GROUP_GAP))
        if box.SetBackdrop then
            box:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            box:SetBackdropColor(0.12, 0.12, 0.14, 1)
            box:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        end
        local title = NewLabel(box, "GameFontNormalSmall", "Group " .. g)
        title:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -4)
        self.groupBoxes[g] = box
        self.slotsByGroup[g] = {}
    end

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
    if not self.groupBoxes then return end
    if force then ns.EvaluateAll() end

    local byGroup = {}
    for g = 1, 8 do byGroup[g] = {} end
    for _, guid in ipairs(ns.order) do
        local st = ns.units[guid]
        if st then
            local g = st.subgroup or 1
            if g < 1 or g > 8 then g = 1 end
            local list = byGroup[g]
            if #list < 5 then list[#list + 1] = st end
        end
    end

    local inRaid = IsInRaid()
    self.playerRows = {}
    for g = 1, 8 do
        local box = self.groupBoxes[g]
        box:SetShown(inRaid or g == 1)
        for slot = 1, 5 do
            local st = byGroup[g][slot]
            local row = self.slotsByGroup[g][slot]
            if st then
                row = row or MakePlayerRow(box, slot)
                self.slotsByGroup[g][slot] = row
                row.guid = st.guid
                ns.SetClassIcon(row.classIcon, st.class)
                row.name:SetText(ns.ShortName(st.name))
                row.name:SetTextColor(ns.ClassColor(st.class))
                row.roleButton:SetText(RoleButtonText(st))
                row.roleButton:SetEnabled(#(ns.CLASS_ROLES[st.class] or {}) > 1)
                row:Show()
                self.playerRows[#self.playerRows + 1] = row
            elseif row then
                row.guid = nil
                row:Hide()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Pally Power tab (read-only view of the group's Pally Power assignments)
---------------------------------------------------------------------------
local PP_NAME_W = 118
local PP_CELL = 30
local PP_ROW_H = 26

local function PPCellTooltip(cell)
    local PPm = ns.PP
    if not PPm or not cell.paladin then return end
    local class = PPm.CLASS_BY_ID[cell.cid]
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    local b = PPm.BlessingFor(cell.paladin, class, nil)
    GameTooltip:AddLine(string.format("%s: %s", ns.ShortName(cell.paladin), ns.ClassLabel(class)))
    GameTooltip:AddLine(b and (ns.BlessingSpell(b, false) or b) or "Nothing assigned", 1, 1, 1)
    local d = PPm.Data()
    local n = d.normal[cell.paladin] and d.normal[cell.paladin][cell.cid]
    if n and next(n) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Single-player assignments:", 0.6, 0.8, 1)
        for target, idx in pairs(n) do
            local nb = PPm.BLESSING_BY_ID[idx]
            GameTooltip:AddDoubleLine("  " .. ns.ShortName(target), nb and ns.BlessingShort(nb) or "?", 1, 1, 1, 1, 0.82, 0)
        end
    end
    GameTooltip:Show()
end

function Config:BuildPallyPowerTab(tab)
    local help = NewLabel(tab, "GameFontHighlightSmall",
        "Assignments made in Pally Power (or a compatible addon) by the paladins in your group. Read-only: this addon listens but never sends its own assignments.")
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetWidth(WIDTH - PAD * 2)

    self.ppStatus = NewLabel(tab, "GameFontNormalSmall")
    self.ppStatus:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -36)
    self.ppStatus:SetWidth(WIDTH - PAD * 2)

    local headerY = -60
    for cid = 1, 9 do
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", tab, "TOPLEFT", PP_NAME_W + (cid - 1) * PP_CELL + 2, headerY)
        ns.SetClassIcon(icon, ns.PP and ns.PP.CLASS_BY_ID[cid])
    end
    self.ppRows = {}
    self.ppTab = tab
    self.ppFirstY = headerY - 24

    local req = SmallButton(tab, "Request update", 140)
    req:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 4)
    req:SetScript("OnClick", function()
        if ns.PP and ns.PP.Request(true) then ns.Print("asked the group for their Pally Power assignments.")
        else ns.Print("you need to be in a group to ask for Pally Power assignments.") end
    end)
end

local function MakePPRow(tab, i, firstY)
    local row = CreateFrame("Frame", nil, tab)
    row:SetSize(PP_NAME_W + 9 * PP_CELL, PP_ROW_H)
    row:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, firstY - (i - 1) * PP_ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0)
    row.name = NewLabel(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetWidth(PP_NAME_W - 8)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.cells = {}
    for cid = 1, 9 do
        local cell = CreateFrame("Frame", nil, row)
        cell:SetSize(22, 22)
        cell:SetPoint("LEFT", row, "LEFT", PP_NAME_W + (cid - 1) * PP_CELL, 0)
        cell:EnableMouse(true)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetAllPoints()
        cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        cell.plus = NewLabel(cell, "GameFontGreenSmall", "+")
        cell.plus:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 3, -3)
        cell.cid = cid
        cell:SetScript("OnEnter", PPCellTooltip)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.cells[cid] = cell
    end
    return row
end

function Config:RefreshPallyPower()
    if not self.ppRows or not ns.PP then return end
    if self.frame and not self.frame:IsShown() then return end
    local PPm = ns.PP
    local list = PPm.Paladins()
    local d = PPm.Data()
    local others = 0
    for _, p in ipairs(list) do if not p.isMe then others = others + 1 end end
    local status
    if not IsInGroup() then
        status = "|cffaaaaaaJoin a group to see Pally Power assignments.|r"
    elseif #list == 0 then
        status = "|cffaaaaaaNo Pally Power assignments seen in this group yet.|r"
    else
        status = string.format("%d paladin%s with Pally Power assignments.", #list, #list == 1 and "" or "s")
    end
    if ns.opt.followPP then
        status = status .. "  |cff60ff60Following your assignments.|r"
    else
        status = status .. "  |cffff8060Not following (see Options).|r"
    end
    self.ppStatus:SetText(status)

    for i, p in ipairs(list) do
        local row = self.ppRows[i] or MakePPRow(self.ppTab, i, self.ppFirstY)
        self.ppRows[i] = row
        row.name:SetText(ns.ShortName(p.name) .. (p.isMe and " |cff60ff60(you)|r" or ""))
        row.name:SetTextColor(ns.ClassColor("PALADIN"))
        row.bg:SetColorTexture(1, 1, 1, p.isMe and 0.08 or 0)
        for cid = 1, 9 do
            local cell = row.cells[cid]
            cell.paladin = p.name
            local b = PPm.BlessingFor(p.name, PPm.CLASS_BY_ID[cid], nil)
            if b and ns.BLESSINGS[b] then
                cell.icon:SetTexture(ns.BlessingTexture(b, true))
                cell.icon:Show()
            else
                cell.icon:SetTexture(EMPTY)
                cell.icon:Show()
            end
            local n = d.normal[p.name] and d.normal[p.name][cid]
            cell.plus:SetShown(n and next(n) ~= nil or false)
        end
        row:Show()
    end
    for i = #list + 1, #self.ppRows do self.ppRows[i]:Hide() end
    self.ppList = list
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
    { key = "blessings",  label = "Blessings" },
    { key = "players",    label = "Players" },
    { key = "pallypower", label = "Pally Power" },
    { key = "options",    label = "Options" },
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
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    -- Nearly opaque, so text stays readable over any background.
    if f.SetBackdropColor then f:SetBackdropColor(0.06, 0.06, 0.08, 0.97) end
    f:Hide()
    tinsert(UISpecialFrames, "CBB_ConfigFrame")
    self.frame = f

    local title = NewLabel(f, "GameFontNormalLarge", "Camelus' Better Blessings")
    title:SetPoint("TOP", 0, -14)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    self.tabFrames, self.tabButtons = {}, {}
    for i, t in ipairs(TABS) do
        local b = SmallButton(f, t.label, 98)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * 103, -34)
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
    self:BuildPallyPowerTab(self.tabFrames.pallypower)
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
    if self.activeTab == "pallypower" then self:RefreshPallyPower() end
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
