local ADDON = ...

-- Spell lists: only spells the player actually knows get shown (outside edit mode).
-- A = Alliance only, H = Horde only, anything else = both.
local A, H = "Alliance", "Horde"
local TELEPORTS = {
    { 3561, A }, { 3562, A }, { 3565, A }, { 32271, A }, { 49359, A }, { 33690, A },   -- Stormwind, Ironforge, Darnassus, Exodar, Theramore, Shattrath
    { 3567, H }, { 3563, H }, { 3566, H }, { 32272, H }, { 49358, H }, { 35715, H },   -- Orgrimmar, Undercity, Thunder Bluff, Silvermoon, Stonard, Shattrath
    { 53140 }, { 120145 }, { 224869 },                                                 -- Dalaran (Northrend), Ancient Dalaran, Dalaran (Broken Isles)
    { 88342, A }, { 88344, H },                                                        -- Tol Barad
    { 132621, A }, { 132627, H },                                                      -- Vale of Eternal Blossoms
    { 176248, A }, { 176242, H },                                                      -- Stormshield, Warspear
    { 193759 },                                                                        -- Hall of the Guardian
    { 281403, A }, { 281404, H },                                                      -- Boralus, Dazar'alor
    { 344587 }, { 395277 }, { 446540 },                                                -- Oribos, Valdrakken, Dornogal
}

local PORTALS = {
    { 10059, A }, { 11416, A }, { 11419, A }, { 32266, A }, { 49360, A }, { 33691, A },
    { 11417, H }, { 11418, H }, { 11420, H }, { 32267, H }, { 49361, H }, { 35717, H },
    { 53142 }, { 120146 }, { 224871 },
    { 88345, A }, { 88346, H },
    { 132620, A }, { 132626, H },
    { 176246, A }, { 176244, H },
    { 281400, A }, { 281402, H },
    { 344597 }, { 395289 }, { 446534 },
}

local editMode = false
local testMode = false  -- screenshot mode: everything shown at full colour, no drag box

local DEFAULTS = {
    mode = "bar",       -- "bar" or "flyout"
    size = 36,
    spacing = 4,
    scale = 1,
    locked = false,
    flyoutDirection = "UP", -- UP, DOWN, LEFT, RIGHT
    point = { "CENTER", "UIParent", "CENTER", 0, -200 },
}

local db
local pending = false
local buttons = {}   -- all spell buttons, reused
local headers = {}   -- flyout toggle buttons

local function IsKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(id)
    end
    return IsSpellKnown(id)
end

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture(id)
end

local function SpellExists(id)
    if C_Spell and C_Spell.DoesSpellExist then return C_Spell.DoesSpellExist(id) end
    return GetSpellInfo(id) ~= nil
end

-- In edit mode, include every spell for the player's faction that exists in this client.
local function KnownList(list)
    local faction = UnitFactionGroup("player")
    local out = {}
    for _, entry in ipairs(list) do
        local id, side = entry[1], entry[2]
        if IsKnown(id) or ((editMode or testMode) and (not side or side == faction) and SpellExists(id)) then
            out[#out + 1] = id
        end
    end
    return out
end

-- Set up a spell button; unknown spells (edit mode preview) are greyed out and do nothing.
local function SetSpell(b, id)
    local known = IsKnown(id)
    b:SetAttribute("type", known and "spell" or nil)
    b:SetAttribute("spell", known and id or nil)
    b.spellID = id
    b.icon:SetTexture(SpellTexture(id))
    local grey = not known and not testMode
    b.icon:SetDesaturated(grey)
    b.icon:SetAlpha(grey and 0.5 or 1)
end

-- Anchor frame (movable)
local anchor = CreateFrame("Frame", "PortalsAnchor", UIParent)
anchor:SetSize(1, 1)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

local handle = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
handle:SetAllPoints(anchor)
handle:SetFrameStrata("HIGH")
handle:EnableMouse(true)
handle:RegisterForDrag("LeftButton")
handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
handle:SetBackdropColor(0.2, 0.5, 1, 0.35)
handle:SetScript("OnDragStart", function() anchor:StartMoving() end)
handle:SetScript("OnDragStop", function()
    anchor:StopMovingOrSizing()
    local p, _, rp, x, y = anchor:GetPoint()
    db.point = { p, "UIParent", rp, x, y }
end)

-- Container used when a flyout header toggles its children
local function NewContainer(name)
    local f = CreateFrame("Frame", name, anchor, "SecureHandlerBaseTemplate")
    f:SetSize(1, 1)
    return f
end

local containers = {
    teleports = NewContainer("PortalsTeleportFlyout"),
    portals = NewContainer("PortalsPortalFlyout"),
}

local function Tooltip(self)
    if self.spellID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    elseif self.tip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip)
        GameTooltip:Show()
    end
end

local function StyleButton(b)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

local function GetButton(i)
    local b = buttons[i]
    if not b then
        b = CreateFrame("Button", "PortalsButton" .. i, anchor, "SecureActionButtonTemplate")
        StyleButton(b)
        buttons[i] = b
    end
    return b
end

local function GetHeader(key, tip, texture)
    local h = headers[key]
    if not h then
        h = CreateFrame("Button", "PortalsHeader_" .. key, anchor, "SecureHandlerClickTemplate")
        StyleButton(h)
        h.tip = tip
        h.icon:SetTexture(texture)
        h:SetFrameRef("container", containers[key])
        h:SetAttribute("_onclick", [[
            local c = self:GetFrameRef("container")
            if c:IsShown() then c:Hide() else c:Show() end
        ]])
        headers[key] = h
    end
    return h
end

local DIRS = {
    UP    = { "BOTTOM", "TOP", 0, 1 },
    DOWN  = { "TOP", "BOTTOM", 0, -1 },
    LEFT  = { "RIGHT", "LEFT", -1, 0 },
    RIGHT = { "LEFT", "RIGHT", 1, 0 },
}

local wrapped = {}

local function Layout()
    if InCombatLockdown() then pending = true return end
    pending = false

    local size, gap = db.size, db.spacing
    local groups = {
        { key = "teleports", spells = KnownList(TELEPORTS) },
        { key = "portals",   spells = KnownList(PORTALS) },
    }

    anchor:SetScale(db.scale)
    anchor:ClearAllPoints()
    anchor:SetPoint(unpack(db.point))

    for _, b in ipairs(buttons) do b:Hide(); b:SetParent(anchor); b:ClearAllPoints() end
    for _, h in pairs(headers) do h:Hide() end
    for _, c in pairs(containers) do c:Hide() end

    local n = 0
    local maxCols, rows = 0, 0

    if db.mode == "bar" then
        for _, g in ipairs(groups) do
            if #g.spells > 0 then
                for col, id in ipairs(g.spells) do
                    n = n + 1
                    local b = GetButton(n)
                    b:SetSize(size, size)
                    b:SetPoint("TOPLEFT", anchor, "TOPLEFT", (col - 1) * (size + gap), -rows * (size + gap))
                    SetSpell(b, id)
                    b:Show()
                end
                maxCols = math.max(maxCols, #g.spells)
                rows = rows + 1
            end
        end
    else -- flyout
        local dir = DIRS[db.flyoutDirection] or DIRS.UP
        local col = 0
        for _, g in ipairs(groups) do
            if #g.spells > 0 then
                local tip = g.key == "teleports" and "Teleports" or "Portals"
                local h = GetHeader(g.key, tip, SpellTexture(g.spells[1]))
                h:SetSize(size, size)
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * (size + gap), 0)
                h:Show()

                local c = containers[g.key]
                c:SetParent(h)
                c:ClearAllPoints()
                c:SetAllPoints(h)

                local prev = h
                for _, id in ipairs(g.spells) do
                    n = n + 1
                    local b = GetButton(n)
                    b:SetParent(c)
                    b:SetSize(size, size)
                    b:SetPoint(dir[1], prev, dir[2], dir[3] * gap, dir[4] * gap)
                    SetSpell(b, id)
                    b:Show()
                    prev = b
                    -- close the flyout after casting (secure, works in combat)
                    if not wrapped[b] then
                        c:WrapScript(b, "OnClick", "", [[ self:GetParent():Hide() ]])
                        wrapped[b] = c
                    elseif wrapped[b] ~= c then
                        wrapped[b]:UnwrapScript(b, "OnClick")
                        c:WrapScript(b, "OnClick", "", [[ self:GetParent():Hide() ]])
                        wrapped[b] = c
                    end
                end
                col = col + 1
            end
        end
        maxCols, rows = col, 1
    end

    -- remove flyout-close wrappers from buttons used in bar mode
    if db.mode == "bar" then
        for b, c in pairs(wrapped) do c:UnwrapScript(b, "OnClick"); wrapped[b] = nil end
    end

    anchor:SetSize(math.max(1, maxCols * (size + gap) - gap), math.max(1, rows * (size + gap) - gap))
    handle:SetShown(not testMode and (editMode or not db.locked))

    -- keep flyouts open in edit/test mode so the full layout is visible
    if (editMode or testMode) and db.mode == "flyout" then
        for key, h in pairs(headers) do
            if h:IsShown() then containers[key]:Show() end
        end
    end
end

local function UpdateCooldowns()
    for _, b in ipairs(buttons) do
        if b.spellID and b:IsVisible() then
            local start, duration
            if C_Spell and C_Spell.GetSpellCooldown then
                local info = C_Spell.GetSpellCooldown(b.spellID)
                if info then start, duration = info.startTime, info.duration end
            elseif GetSpellCooldown then
                start, duration = GetSpellCooldown(b.spellID)
            end
            if start then b.cooldown:SetCooldown(start, duration) end
        end
    end
end

-- Slash commands
SLASH_PORTALS1 = "/portals"
SlashCmdList.PORTALS = function(msg)
    local cmd, arg = msg:lower():match("^(%S*)%s*(.-)$")
    if cmd == "bar" or cmd == "flyout" then
        db.mode = cmd
    elseif cmd == "lock" then
        db.locked = true
    elseif cmd == "unlock" then
        db.locked = false
    elseif cmd == "edit" then
        editMode = not editMode
        print("|cff69ccf0Portals|r: edit mode " .. (editMode and "on - showing all spells, drag to move" or "off"))
    elseif cmd == "test" then
        testMode = not testMode
        print("|cff69ccf0Portals|r: test mode " .. (testMode and "on - showing all spells for screenshots" or "off"))
    elseif cmd == "scale" and tonumber(arg) then
        db.scale = math.min(3, math.max(0.3, tonumber(arg)))
    elseif cmd == "size" and tonumber(arg) then
        db.size = math.min(80, math.max(16, tonumber(arg)))
    elseif cmd == "dir" and DIRS[arg:upper()] then
        db.flyoutDirection = arg:upper()
    elseif cmd == "reset" then
        db.point = CopyTable(DEFAULTS.point)
    else
        print("|cff69ccf0Portals|r commands:")
        print("  /portals bar | flyout  - layout mode (currently " .. db.mode .. ")")
        print("  /portals edit - preview every teleport/portal (even unlearned) and move the bar")
        print("  /portals test - show every spell at full colour for screenshots")
        print("  /portals lock | unlock - drag with the blue box when unlocked")
        print("  /portals scale <0.3-3>, /portals size <16-80>")
        print("  /portals dir up|down|left|right - flyout direction")
        print("  /portals reset - reset position")
        return
    end
    if InCombatLockdown() then print("|cff69ccf0Portals|r: will apply after combat.") end
    Layout()
end

-- Events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        PortalsDB = PortalsDB or {}
        for k, v in pairs(DEFAULTS) do
            if PortalsDB[k] == nil then PortalsDB[k] = type(v) == "table" and CopyTable(v) or v end
        end
        db = PortalsDB
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    elseif event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then
        Layout()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Layout() end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        UpdateCooldowns()
    end
end)
