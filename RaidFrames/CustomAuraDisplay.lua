---@class Cell
local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@type CellIndicatorFuncs
local I = Cell.iFuncs

local INIT_VERSION = 1
local BUILD = select(4, GetBuildInfo())
local SUPPORTED = Cell.isRetail and BUILD >= 120100

local HARD_EXCLUDE_SPELLS = {
    [225788] = true,
    [186404] = true,
}

local stateByButton = setmetatable({}, { __mode = "k" })
local cachedConfigs
local featureReady
local durationFormatter
local buildQueue = {}
local buildQueued = setmetatable({}, { __mode = "k" })
local buildTicker

local function EnsureAuraContainerLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
end

local function ProbeSupported()
    if featureReady ~= nil then return featureReady end
    if not SUPPORTED then
        featureReady = false
        return false
    end
    EnsureAuraContainerLoaded()
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not container then
        featureReady = false
        return false
    end
    container:Hide()
    container:SetParent(nil)
    featureReady = type(container.AddAuraGroup) == "function"
        and type(container.SetUnit) == "function"
        and type(container.SetEnabled) == "function"
    return featureReady
end

local function IsSupportedCustomCfg(t)
    if not (t and t.enabled and t.auraType == "buff") then return false end
    if t.name == "Healers" then return false end
    if t.type ~= "icon" and t.type ~= "icons" then return false end
    if type(t.indicatorName) ~= "string" or not t.indicatorName:find("^indicator") then return false end
    if type(t.auras) ~= "table" then return false end
    local hasSpell = false
    for k, v in pairs(t.auras) do
        local n = tonumber(v)
        if not (n and n > 0) then n = tonumber(k) end
        if n and n > 0 then
            hasSpell = true
            break
        end
    end
    return hasSpell
end

local function RefreshCachedConfigs()
    local list = {}
    local layout = Cell.vars.currentLayoutTable
    if layout and layout.indicators then
        for _, t in ipairs(layout.indicators) do
            if IsSupportedCustomCfg(t) then
                list[#list + 1] = t
            end
        end
    end
    cachedConfigs = list
    return list
end

local function BuildSpellMap(auras)
    local map = {}
    if type(auras) ~= "table" then return map end
    for k, v in pairs(auras) do
        local n = tonumber(v)
        if not (n and n > 0) then n = tonumber(k) end
        if n and n > 0 then map[n] = true end
    end
    return map
end

local function SpellMapCount(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

local function BuildExcludeSpellMap()
    local map = {}
    for id in pairs(HARD_EXCLUDE_SPELLS) do
        map[id] = true
    end

    local function addId(id)
        id = tonumber(id)
        if id and id > 0 then
            map[id] = true
        end
    end

    local function addAuraBlacklistTable(tbl)
        if type(tbl) ~= "table" then return end
        for spellId, entry in pairs(tbl) do
            if type(spellId) == "number" then
                if entry == true then
                    addId(spellId)
                elseif type(entry) == "table" and (entry.combat or entry.ooc) then
                    addId(spellId)
                end
            elseif type(entry) == "number" then
                addId(entry)
            end
        end
    end

    if CellDB and CellDB["auraBlacklist"] then
        addAuraBlacklistTable(CellDB["auraBlacklist"]["buffs"])
        addAuraBlacklistTable(CellDB["auraBlacklist"]["HELPFUL"])
    end

    local alts = Cell.AuraBlacklist and Cell.AuraBlacklist.AlternateSpellIDs
    if type(alts) == "table" then
        for altId, primaryId in pairs(alts) do
            if map[primaryId] then
                addId(altId)
            elseif map[altId] then
                addId(primaryId)
            end
        end
    end

    return map
end

local function BuildFilter(castBy)
    if castBy == "anyone" then
        return "HELPFUL"
    end
    if castBy == "others" then
        return "HELPFUL"
    end
    return "HELPFUL|PLAYER"
end

local function ResolveUnit(unitButton)
    local unit = unitButton.states and (unitButton.states.displayedUnit or unitButton.states.unit)
    if type(unit) == "string" and unit ~= "" then
        return unit
    end
    local attr = unitButton.GetAttribute and unitButton:GetAttribute("unit")
    if type(attr) == "string" and attr ~= "" then
        return attr
    end
end

local function StyleFont(fs, fontCfg, defaultSize)
    local font, size, outline, shadow
    if type(fontCfg) == "table" then
        font, size, outline, shadow = fontCfg[1], fontCfg[2], fontCfg[3], fontCfg[4]
    end
    size = size or defaultSize or 11
    local flags = "OUTLINE"
    if outline == "None" or outline == "" then
        flags = ""
    elseif outline == "Monochrome Outline" then
        flags = "OUTLINE,MONOCHROME"
    elseif outline == "Monochrome" then
        flags = "MONOCHROME"
    end
    local path = GameFontNormal:GetFont()
    if font and F.GetFont then
        local ok, resolved = pcall(F.GetFont, font)
        if ok and type(resolved) == "string" and resolved ~= "" then
            path = resolved
        end
    end
    if not pcall(fs.SetFont, fs, path, size, flags) then
        pcall(fs.SetFontObject, fs, GameFontNormalSmall)
    end
    if shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
    fs:SetTextColor(1, 1, 1, 1)
end

local function GetCellDurationFormatter()
    if durationFormatter then return durationFormatter end
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum and Enum.NumericRuleFormatRounding then
        local Up = Enum.NumericRuleFormatRounding.Up
        local Down = Enum.NumericRuleFormatRounding.Down
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        local ok = pcall(formatter.SetBreakpoints, formatter, {
            { threshold = 0,     format = "%d",  step = 1, rounding = Up },
            { threshold = 60,    format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
            { threshold = 3600,  format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
            { threshold = 86400, format = "%dd", step = 1, rounding = Down, components = { { div = 86400 } } },
        })
        if ok then
            durationFormatter = formatter
            return durationFormatter
        end
    end
    return nil
end

local function ShouldShowDuration(cfg)
    local v = cfg and cfg.showDuration
    if v == false or v == nil or v == 0 then
        return false
    end
    return true
end

local function ResolveAnimationStyle(cfg)
    if type(cfg) == "table" and type(cfg.animationStyle) == "string" then
        local s = cfg.animationStyle
        if s == "none" or s == "vertical" or s == "clock" then
            return s
        end
    end
    if type(cfg) == "table" and cfg.showAnimation == false then
        return "none"
    end
    return "clock"
end

local function AttachInvisibleCooldown(button)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:EnableMouse(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetSwipeColor(0, 0, 0, 0)
    pcall(button.SetDurationCooldown, button, cooldown)
    return cooldown
end

local function MakeInitAuraButton(cfg)
    return function(button)
        local sizeW = (cfg.size and cfg.size[1]) or 13
        local sizeH = (cfg.size and cfg.size[2]) or sizeW
        pcall(button.SetSize, button, sizeW, sizeH)
        pcall(button.SetMouseClickEnabled, button, false)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)

        local style = ResolveAnimationStyle(cfg)
        local animFrame

        if style == "none" then
            animFrame = AttachInvisibleCooldown(button)
        elseif style == "vertical" and type(button.SetDurationBar) == "function" then
            local bar = CreateFrame("StatusBar", nil, button)
            bar:SetAllPoints(button)
            bar:EnableMouse(false)
            bar:SetOrientation("VERTICAL")
            bar:SetReverseFill(true)
            bar:SetStatusBarTexture(Cell.vars.whiteTexture)
            local barTex = bar:GetStatusBarTexture()
            if barTex then
                barTex:SetVertexColor(0, 0, 0, 0.77)
            end
            local barOpts = {}
            if Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime then
                barOpts.direction = Enum.StatusBarTimerDirection.ElapsedTime
            end
            if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate then
                barOpts.interpolation = Enum.StatusBarInterpolation.Immediate
            end
            pcall(button.SetDurationBar, button, bar, barOpts)
            animFrame = bar
        else
            local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cooldown:SetAllPoints(button)
            cooldown:EnableMouse(false)
            cooldown:SetHideCountdownNumbers(true)
            cooldown:SetDrawEdge(false)
            cooldown:SetDrawBling(false)
            cooldown:SetReverse(true)
            if Cell.vars and Cell.vars.whiteTexture then
                cooldown:SetSwipeTexture(Cell.vars.whiteTexture)
                cooldown:SetSwipeColor(0, 0, 0, 0.77)
            end
            pcall(button.SetDurationCooldown, button, cooldown)
            animFrame = cooldown
        end

        local textHost = CreateFrame("Frame", nil, button)
        textHost:SetAllPoints(button)
        textHost:EnableMouse(false)
        local baseLevel = (animFrame and animFrame.GetFrameLevel and animFrame:GetFrameLevel())
            or (button.GetFrameLevel and button:GetFrameLevel())
            or 1
        textHost:SetFrameLevel(baseLevel + 10)

        if cfg.showStack ~= false then
            local stack = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            local fontCfg = cfg.font and cfg.font[1]
            local ox = (type(fontCfg) == "table" and fontCfg[6]) or 2
            local oy = (type(fontCfg) == "table" and fontCfg[7]) or 1
            stack:ClearAllPoints()
            stack:SetPoint("TOPRIGHT", textHost, "TOPRIGHT", ox, oy)
            stack:SetJustifyH("RIGHT")
            StyleFont(stack, fontCfg, 11)
            if type(fontCfg) == "table" and type(fontCfg[8]) == "table" then
                stack:SetTextColor(fontCfg[8][1] or 1, fontCfg[8][2] or 1, fontCfg[8][3] or 1, fontCfg[8][4] or 1)
            else
                stack:SetTextColor(1, 1, 1, 1)
            end
            pcall(button.SetApplicationCount, button, stack, {})
        end

        if ShouldShowDuration(cfg) then
            local duration = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            local fontCfg = cfg.font and cfg.font[2]
            local ox = (type(fontCfg) == "table" and fontCfg[6]) or 2
            local oy = (type(fontCfg) == "table" and fontCfg[7]) or -1
            duration:ClearAllPoints()
            duration:SetPoint("BOTTOMRIGHT", textHost, "BOTTOMRIGHT", ox, oy)
            duration:SetJustifyH("RIGHT")
            StyleFont(duration, fontCfg, 11)
            if type(fontCfg) == "table" and type(fontCfg[8]) == "table" then
                duration:SetTextColor(fontCfg[8][1] or 1, fontCfg[8][2] or 1, fontCfg[8][3] or 1, fontCfg[8][4] or 1)
            else
                duration:SetTextColor(1, 1, 1, 1)
            end
            local opts = {}
            local formatter = GetCellDurationFormatter()
            if formatter then
                opts.textFormatter = formatter
            end
            if not pcall(button.SetDurationText, button, duration, opts) then
                pcall(button.SetDurationText, button, duration, { textFormatter = formatter })
            end
        end
    end
end

local function ResolveContainerParent(unitButton)
    if unitButton.widgets and unitButton.widgets.indicatorFrame then
        return unitButton.widgets.indicatorFrame
    end
    return unitButton
end

local function HideLegacy(unitButton, indicatorName)
    local ind = unitButton.indicators and indicatorName and unitButton.indicators[indicatorName]
    if not ind then return end
    ind:Hide(true)
    if ind.SetAlpha then ind:SetAlpha(0) end
end

local function ShowLegacy(unitButton, indicatorName)
    local ind = unitButton.indicators and indicatorName and unitButton.indicators[indicatorName]
    if not ind then return end
    if ind.SetAlpha then ind:SetAlpha(1) end
end

local function DestroyContainer(st)
    if not (st and st.container) then return end
    st.container:SetEnabled(false)
    st.container:Hide()
    st.container:SetParent(nil)
    st.container = nil
end

local function AnchorContainer(container, unitButton, cfg)
    local sizeW = (cfg.size and cfg.size[1]) or 13
    local sizeH = (cfg.size and cfg.size[2]) or sizeW
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    local num = (cfg.type == "icon") and 1 or (cfg.num or 5)
    local numPerLine = cfg.numPerLine or num
    local pos = cfg.position or { "TOPRIGHT", "button", "TOPRIGHT", 0, 3 }
    local point = pos[1] or "TOPRIGHT"
    local relative = pos[2]
    local relativePoint = pos[3] or point
    local x, y = pos[4] or 0, pos[5] or 0

    local relativeTo = unitButton
    if relative == "healthBar" and unitButton.widgets and unitButton.widgets.healthBar then
        relativeTo = unitButton.widgets.healthBar
    end

    container:ClearAllPoints()
    container:SetPoint(point, relativeTo, relativePoint, x, y)
    container:SetSize(1, 1)

    if container.SetFlowLayoutAnchorPoint then
        pcall(container.SetFlowLayoutAnchorPoint, container, point)
    end

    local orientation = cfg.orientation or "left-to-right"
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if FD and container.SetFlowLayoutGrowthDirection then
        local h, v = FD.Right, FD.Down
        if orientation == "right-to-left" then
            h, v = FD.Left, FD.Down
        elseif orientation == "top-to-bottom" then
            h, v = FD.Right, FD.Down
        elseif orientation == "bottom-to-top" then
            h, v = FD.Right, FD.Up
        end
        pcall(container.SetFlowLayoutGrowthDirection, container, h, v)
    end
    if container.SetFlowLayoutMaximumLineSize then
        local rowWidth = numPerLine * sizeW + math.max(numPerLine - 1, 0) * spacingX + 0.4
        if orientation == "top-to-bottom" or orientation == "bottom-to-top" then
            rowWidth = sizeH + 0.4
        end
        pcall(container.SetFlowLayoutMaximumLineSize, container, rowWidth)
    end

    local groupKey = cfg.indicatorName
    if container.HasAuraGroup and container:HasAuraGroup(groupKey) and container.SetAuraGroupLayout then
        pcall(container.SetAuraGroupLayout, container, groupKey, {
            elementWidth = sizeW,
            elementHeight = sizeH,
            elementSpacing = spacingX,
            lineSpacing = spacingY,
        })
    end

    local parent = ResolveContainerParent(unitButton)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + (cfg.frameLevel or 5))
end

local function CreateCustomContainer(unitButton, cfg)
    local spellMap = BuildSpellMap(cfg.auras)
    if SpellMapCount(spellMap) == 0 then
        return nil, "empty spell list"
    end

    EnsureAuraContainerLoaded()
    local parent = ResolveContainerParent(unitButton)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not container then
        return nil, tostring(container)
    end

    local sizeW = (cfg.size and cfg.size[1]) or 13
    local sizeH = (cfg.size and cfg.size[2]) or sizeW
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    local filter = BuildFilter(cfg.castBy)
    local unit = ResolveUnit(unitButton) or "player"
    local maxCount = (cfg.type == "icon") and 1 or (cfg.num or 5)
    local groupKey = cfg.indicatorName

    container:SetEnabled(false)
    container:Hide()
    AnchorContainer(container, unitButton, cfg)
    pcall(container.SetUnit, container, unit)

    local groupOpts = {
        maxFrameCount = maxCount,
        candidateFilters = {
            includeSpellIDs = spellMap,
            excludeSpellIDs = BuildExcludeSpellMap(),
        },
        initializeFrame = MakeInitAuraButton(cfg),
        layout = {
            elementWidth = sizeW,
            elementHeight = sizeH,
            elementSpacing = spacingX,
            lineSpacing = spacingY,
        },
    }
    if AuraContainerSortMethod and AuraContainerSortMethod.Default then
        groupOpts.sortMethod = AuraContainerSortMethod.Default
    end
    if AuraContainerSortDirection and AuraContainerSortDirection.Normal then
        groupOpts.sortDirection = AuraContainerSortDirection.Normal
    end

    local addOk, addErr = pcall(container.AddAuraGroup, container, groupKey, filter, groupOpts)
    if not addOk then
        container:SetParent(nil)
        return nil, tostring(addErr)
    end

    AnchorContainer(container, unitButton, cfg)
    if container.UpdateAllAuras then
        pcall(container.UpdateAllAuras, container)
    end
    return container
end

local function DriveContainer(unitButton, cfg, enable)
    local map = stateByButton[unitButton]
    local st = map and map[cfg.indicatorName]
    if not (st and st.container and cfg) then return end
    local unit = ResolveUnit(unitButton)
    AnchorContainer(st.container, unitButton, cfg)
    if unit then
        pcall(st.container.SetUnit, st.container, unit)
    end
    if enable then
        st.container:Show()
        st.container:SetEnabled(true)
        if st.container.UpdateAllAuras then
            pcall(st.container.UpdateAllAuras, st.container)
        end
        HideLegacy(unitButton, cfg.indicatorName)
    else
        st.container:SetEnabled(false)
        st.container:Hide()
        ShowLegacy(unitButton, cfg.indicatorName)
    end
end

local function EnsureIndicatorContainer(unitButton, cfg, allowCreate)
    if not ProbeSupported() then return false end
    local map = stateByButton[unitButton]
    if not map then
        map = {}
        stateByButton[unitButton] = map
    end
    local name = cfg.indicatorName
    local st = map[name]
    if not st then
        st = {}
        map[name] = st
    end

    if st.createFailed and st.failedVersion == INIT_VERSION then
        return false
    end
    if st.createFailed and st.failedVersion ~= INIT_VERSION then
        st.createFailed = nil
        st.failedVersion = nil
    end

    if st.container then
        local p = st.container:GetParent()
        if (p == UIParent or p == nil or st.initVersion ~= INIT_VERSION) and allowCreate then
            DestroyContainer(st)
        end
    end

    if st.container then
        return true
    end
    if not allowCreate then
        return false
    end

    local container, err = CreateCustomContainer(unitButton, cfg)
    if not container then
        st.createFailed = true
        st.failedVersion = INIT_VERSION
        if not Cell.vars._customAuraDisplayWarned then
            Cell.vars._customAuraDisplayWarned = true
            F.Print("|cFFFF7D7DCustom AuraContainer failed:|r " .. tostring(err))
        end
        return false
    end
    st.container = container
    st.initVersion = INIT_VERSION
    st.createFailed = nil
    st.failedVersion = nil
    return true
end

local EnqueueBuild

local function PumpBuildQueue()
    buildTicker = nil
    local b = table.remove(buildQueue, 1)
    while b do
        buildQueued[b] = nil
        if b._indicatorsReady then
            break
        end
        b = table.remove(buildQueue, 1)
    end
    if not b then return end

    local list = cachedConfigs or RefreshCachedConfigs()
    for i = 1, #list do
        local cfg = list[i]
        if EnsureIndicatorContainer(b, cfg, true) then
            DriveContainer(b, cfg, true)
        end
    end

    if #buildQueue > 0 and not buildTicker then
        buildTicker = C_Timer.After(0, PumpBuildQueue)
    end
end

EnqueueBuild = function(unitButton)
    if not unitButton or buildQueued[unitButton] then return end
    buildQueued[unitButton] = true
    buildQueue[#buildQueue + 1] = unitButton
    if not buildTicker then
        buildTicker = C_Timer.After(0, PumpBuildQueue)
    end
end

local function SyncButton(unitButton, allowCreate)
    if not unitButton or not unitButton._indicatorsReady then return end
    local list = RefreshCachedConfigs()
    if allowCreate == nil then
        allowCreate = true
    end

    local seen = {}
    local needsBuild = false
    for i = 1, #list do
        local cfg = list[i]
        local name = cfg.indicatorName
        seen[name] = true
        if EnsureIndicatorContainer(unitButton, cfg, false) then
            DriveContainer(unitButton, cfg, true)
        else
            needsBuild = true
        end
    end

    if needsBuild and allowCreate then
        EnqueueBuild(unitButton)
    end

    local map = stateByButton[unitButton]
    if map then
        for name, st in pairs(map) do
            if not seen[name] then
                if not InCombatLockdown() then
                    DestroyContainer(st)
                    map[name] = nil
                elseif st.container then
                    st.container:SetEnabled(false)
                    st.container:Hide()
                end
                ShowLegacy(unitButton, name)
            end
        end
    end
end

function I.ShouldSkipLegacyCustom(indicatorTable)
    if not ProbeSupported() or not indicatorTable then
        return false
    end
    return IsSupportedCustomCfg(indicatorTable)
end

function I.CustomAuraDisplayActive()
    return ProbeSupported()
end

function I.SyncCustomAuraDisplays(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

function I.UpdateCustomAuraDisplays(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

function I.RefreshAllCustomAuraDisplays()
    if not SUPPORTED then return end
    cachedConfigs = nil
    F.IterateAllUnitButtons(function(b)
        local map = stateByButton[b]
        if map then
            for _, st in pairs(map) do
                DestroyContainer(st)
            end
            stateByButton[b] = nil
        end
        EnqueueBuild(b)
    end, true)
end

if SUPPORTED then
    Cell.RegisterCallback("UpdateIndicators", "CustomAuraDisplay_UpdateIndicators", function(layout, indicatorName, setting)
        if not layout or not indicatorName or not tostring(indicatorName):find("^indicator") then
            if not layout or not indicatorName then
                C_Timer.After(0, I.RefreshAllCustomAuraDisplays)
            end
            return
        end
        if setting == "create" or setting == "remove"
            or setting == "auras" or setting == "position" or setting == "size"
            or setting == "num" or setting == "numPerLine" or setting == "orientation"
            or setting == "spacing" or setting == "castBy" or setting == "enabled"
            or setting == "frameLevel" or setting == "showAnimation" or setting == "animationStyle"
            or setting == "showDuration" or setting == "showStack"
            or setting == "checkbutton" or setting == "font"
            or setting == "type" or setting == "auraType" then
            C_Timer.After(0, I.RefreshAllCustomAuraDisplays)
        end
    end)

    Cell.RegisterCallback("UpdateLayout", "CustomAuraDisplay_UpdateLayout", function()
        C_Timer.After(0, I.RefreshAllCustomAuraDisplays)
    end)

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:RegisterEvent("PLAYER_REGEN_DISABLED")
    boot:RegisterEvent("PLAYER_REGEN_ENABLED")
    boot:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.5, I.RefreshAllCustomAuraDisplays)
            return
        end
        F.IterateAllUnitButtons(function(b)
            SyncButton(b, true)
        end, true)
    end)
end
