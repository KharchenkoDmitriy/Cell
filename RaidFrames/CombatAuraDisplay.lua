---@class Cell
local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@type CellIndicatorFuncs
local I = Cell.iFuncs

local INIT_VERSION = 15
local BUILD = select(4, GetBuildInfo())
local SUPPORTED = Cell.isRetail and BUILD >= 120100

local DISPEL_TYPE_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local DISPEL_TYPE_LEVEL = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Bleed = 5 }
local EDGE_FADE_TOP = "Interface\\AddOns\\Cell\\Media\\Edge-Fade-Top"
local EDGE_FADE_BOTTOM = "Interface\\AddOns\\Cell\\Media\\Edge-Fade-Bottom"
local WHITE_TEXTURE = "Interface\\AddOns\\Cell\\Media\\white"
local DISPEL_FULL_ALPHA = 0.5

local stateByButton = setmetatable({}, { __mode = "k" })
local featureReady
local durationFormatter
local cachedLayouts

local function NormalizeDispelHighlightType(ht)
    if ht == "edge-top" then
        return "edge-top"
    end
    if ht == "edge-bottom" or ht == "gradient-sharp" then
        return "edge-bottom"
    end
    return "entire"
end

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

local function ResolveContainerParent(unitButton)
    if unitButton.widgets and unitButton.widgets.indicatorFrame then
        return unitButton.widgets.indicatorFrame
    end
    return unitButton
end

local function JoinFilter(...)
    local n = select("#", ...)
    if n == 1 then return (select(1, ...)) end
    local t = {}
    for i = 1, n do
        t[i] = select(i, ...)
    end
    return table.concat(t, "|")
end

local TRACKED = {
    "crowdControls",
    "debuffs",
    "dispels",
    "defensiveCooldowns",
    "externalCooldowns",
    "allCooldowns",
    "raidDebuffs",
}

local function RefreshCachedLayouts()
    if not cachedLayouts then
        cachedLayouts = {}
    else
        wipe(cachedLayouts)
    end
    local layout = Cell.vars.currentLayoutTable
    if not (layout and layout.indicators) then return end
    for _, t in ipairs(layout.indicators) do
        if t.enabled and t.indicatorName then
            for i = 1, #TRACKED do
                if t.indicatorName == TRACKED[i] then
                    cachedLayouts[t.indicatorName] = t
                end
            end
        end
    end
end

local function ResolveSize(cfg)
    local s = cfg and cfg.size
    if type(s) == "table" and type(s[1]) == "table" then
        return s[1][1] or 13, s[1][2] or 13
    end
    return (s and s[1]) or 13, (s and s[2]) or 13
end

local function BuildExcludeSpellMap()
    local map = {}
    local function addId(id)
        id = tonumber(id)
        if id and id > 0 then
            map[id] = true
        end
    end

    if I.GetDefaultDebuffBlacklist then
        local defaults = I.GetDefaultDebuffBlacklist()
        if type(defaults) == "table" then
            for _, id in pairs(defaults) do
                addId(id)
            end
        end
    end

    if Cell.vars and type(Cell.vars.debuffBlacklist) == "table" then
        for id, v in pairs(Cell.vars.debuffBlacklist) do
            if v then addId(id) end
        end
    end
    if Cell.vars and type(Cell.vars.dispelBlacklist) == "table" then
        for id, v in pairs(Cell.vars.dispelBlacklist) do
            if v then addId(id) end
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
        addAuraBlacklistTable(CellDB["auraBlacklist"]["debuffs"])
        addAuraBlacklistTable(CellDB["auraBlacklist"]["HARMFUL"])
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

local function CollectSpellIds(src, dest)
    if type(src) ~= "table" then return dest end
    for k, v in pairs(src) do
        if type(k) == "number" and k > 0 then
            dest[k] = true
        end
        if type(v) == "number" and v > 0 then
            dest[v] = true
        elseif type(v) == "table" then
            CollectSpellIds(v, dest)
        end
    end
    return dest
end

local function BuildDefensiveSpellMap()
    local map = CollectSpellIds(Cell.vars and Cell.vars.builtInDefensives, {})
    CollectSpellIds(Cell.vars and Cell.vars.customDefensives, map)
    if not next(map) and I.GetDefensives then
        CollectSpellIds(I.GetDefensives(), map)
    end
    return map
end

local function BuildExternalSpellMap()
    local map = CollectSpellIds(Cell.vars and Cell.vars.builtInExternals, {})
    CollectSpellIds(Cell.vars and Cell.vars.customExternals, map)
    if not next(map) and I.GetExternals then
        CollectSpellIds(I.GetExternals(), map)
    end
    return map
end

local function BuildRaidDebuffSpellMap()
    local map = {}
    local current = I.GetCurrentAreaDebuffs and I.GetCurrentAreaDebuffs()
    if type(current) ~= "table" then return map end
    for k, t in pairs(current) do
        if type(k) == "number" and k > 0 then
            map[k] = true
        end
        if type(t) == "table" then
            local id = tonumber(t.id)
            if id and id > 0 then
                map[id] = true
            end
        end
    end
    return map
end

local function CountKeys(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

local function BuildGroupsForIndicator(indicatorName, cfg)
    local groups = {}
    local exclude = BuildExcludeSpellMap()
    local hasExclude = CountKeys(exclude) > 0

    local function cand(extra)
        local c
        if extra then
            c = {}
            for k, v in pairs(extra) do
                c[k] = v
            end
        else
            c = {}
        end
        if hasExclude then
            c.excludeSpellIDs = exclude
        end
        if not next(c) then return nil end
        return c
    end

    if indicatorName == "crowdControls" then
        groups[#groups + 1] = {
            key = "cc",
            filter = JoinFilter("HARMFUL", "CROWD_CONTROL"),
            candidateFilters = cand(),
            maxFrameCount = cfg.num or 3,
        }
    elseif indicatorName == "debuffs" then
        local filter
        if cfg.dispellableByMe then
            filter = JoinFilter("HARMFUL", "RAID_PLAYER_DISPELLABLE")
        elseif cachedLayouts and cachedLayouts.crowdControls then
            filter = JoinFilter("HARMFUL", "!CROWD_CONTROL")
        else
            filter = "HARMFUL"
        end
        groups[#groups + 1] = {
            key = "deb",
            filter = filter,
            candidateFilters = cand(),
            maxFrameCount = cfg.num or 3,
        }
    elseif indicatorName == "dispels" then
        local filters = cfg.filters or {}
        local filter
        if filters.dispellableByMe ~= false then
            filter = JoinFilter("HARMFUL", "RAID_PLAYER_DISPELLABLE")
        else
            filter = "HARMFUL"
        end
        for _, token in ipairs(DISPEL_TYPE_ORDER) do
            if filters[token] then
                groups[#groups + 1] = {
                    key = "dis_" .. string.lower(token),
                    filter = filter,
                    candidateFilters = cand({ includeDispelTypes = { [token] = true } }),
                    maxFrameCount = 1,
                    dispelToken = token,
                }
            end
        end
    elseif indicatorName == "defensiveCooldowns" then
        local map = BuildDefensiveSpellMap()
        if next(map) then
            groups[#groups + 1] = {
                key = "def",
                filter = "HELPFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 5,
            }
        end
    elseif indicatorName == "externalCooldowns" then
        local map = BuildExternalSpellMap()
        if next(map) then
            groups[#groups + 1] = {
                key = "ext",
                filter = "HELPFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 5,
            }
        end
    elseif indicatorName == "allCooldowns" then
        local map = BuildDefensiveSpellMap()
        CollectSpellIds(BuildExternalSpellMap(), map)
        if next(map) then
            groups[#groups + 1] = {
                key = "allcd",
                filter = "HELPFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 5,
            }
        end
    elseif indicatorName == "raidDebuffs" then
        local map = BuildRaidDebuffSpellMap()
        if next(map) then
            groups[#groups + 1] = {
                key = "rd",
                filter = "HARMFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 3,
            }
        end
    end

    return groups
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

local function MakeInitDispelAuraButton(cfg, token, unitButton)
    return function(button)
        local sizeW, sizeH = ResolveSize(cfg)
        local iconStyle = cfg.iconStyle or "blizzard"
        local showIcons = iconStyle ~= "none"
        local mode = NormalizeDispelHighlightType(cfg and cfg.highlightType)
        local health = unitButton and unitButton.widgets and unitButton.widgets.healthBar
        local r, g, b = I.GetDebuffTypeColor(token)
        r, g, b = r or 1, g or 1, b or 1
        local isEdge = mode == "edge-top" or mode == "edge-bottom"
        local alpha = isEdge and 1 or DISPEL_FULL_ALPHA
        local asset = WHITE_TEXTURE
        if mode == "edge-top" then
            asset = EDGE_FADE_TOP
        elseif mode == "edge-bottom" then
            asset = EDGE_FADE_BOTTOM
        end

        if showIcons then
            pcall(button.SetSize, button, sizeW, sizeH)
        else
            pcall(button.SetSize, button, 0.001, 0.001)
        end
        pcall(button.SetMouseClickEnabled, button, false)

        if health then
            local overlay = button:CreateTexture(nil, "ARTWORK", nil, 3)
            overlay:ClearAllPoints()
            overlay:SetAllPoints(health)
            overlay:SetTexture(asset)
            overlay:SetTexCoord(0, 1, 0, 1)
            overlay:SetVertexColor(r, g, b, alpha)
            overlay:Show()
            local lvl = (health.GetFrameLevel and health:GetFrameLevel() or 1)
                + 1 + (DISPEL_TYPE_LEVEL[token] or 1)
            pcall(button.SetFrameLevel, button, lvl)
        end

        if showIcons then
            local tex = button:CreateTexture(nil, "ARTWORK", nil, 6)
            tex:SetAllPoints(button)
            if iconStyle == "rhombus" then
                tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Debuffs\\Rhombus")
                tex:SetVertexColor(r, g, b, 1)
            else
                tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Debuffs\\" .. token)
                tex:SetVertexColor(1, 1, 1, 1)
            end
        end
    end
end

local function MakeInitAuraButton(cfg)
    return function(button)
        local sizeW, sizeH = ResolveSize(cfg)
        pcall(button.SetSize, button, sizeW, sizeH)
        pcall(button.SetMouseClickEnabled, button, false)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)

        local showAnimation = cfg.showAnimation ~= false
        local cooldownStyle = (CellDB and CellDB.appearance and CellDB.appearance.cooldownStyle)
            or CELL_COOLDOWN_STYLE or "VERTICAL"
        local useVertical = showAnimation and cooldownStyle ~= "CLOCK" and type(button.SetDurationBar) == "function"
        local animFrame

        if showAnimation then
            if useVertical then
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
                cooldown:SetReverse(true)
                if Cell.vars and Cell.vars.whiteTexture then
                    cooldown:SetSwipeTexture(Cell.vars.whiteTexture)
                    cooldown:SetSwipeColor(0, 0, 0, 0.77)
                end
                pcall(button.SetDurationCooldown, button, cooldown)
                animFrame = cooldown
            end
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

        if cfg.showDuration then
            local duration = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            local fontCfg = cfg.font and cfg.font[2]
            local ox = (type(fontCfg) == "table" and fontCfg[6]) or 2
            local oy = (type(fontCfg) == "table" and fontCfg[7]) or -1
            duration:ClearAllPoints()
            duration:SetPoint("BOTTOMRIGHT", textHost, "BOTTOMRIGHT", ox, oy)
            duration:SetJustifyH("RIGHT")
            StyleFont(duration, fontCfg, 11)
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

local function HideLegacy(unitButton, indicatorName)
    local ind = unitButton.indicators and indicatorName and unitButton.indicators[indicatorName]
    if not ind then return end
    if indicatorName == "dispels" then
        if type(ind) == "table" then
            for i = 1, 10 do
                local child = ind[i]
                if child and child.Hide then
                    pcall(child.Hide, child)
                end
            end
        end
        return
    end
    if ind.Hide then
        if indicatorName == "raidDebuffs" then
            pcall(ind.Hide, ind)
        else
            pcall(ind.Hide, ind, true)
        end
    end
    if ind.SetAlpha then ind:SetAlpha(0) end
    if type(ind) == "table" then
        for i = 1, 10 do
            local child = ind[i]
            if child and child.Hide then
                pcall(child.Hide, child)
            end
        end
    end
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
    if st.hlContainer then
        st.hlContainer:SetEnabled(false)
        st.hlContainer:Hide()
        st.hlContainer:SetParent(nil)
        st.hlContainer = nil
    end
end

local function DestroyButtonState(unitButton)
    local map = stateByButton[unitButton]
    if not map then return end
    for _, st in pairs(map) do
        DestroyContainer(st)
    end
    stateByButton[unitButton] = nil
end

local function AnchorContainer(container, unitButton, cfg, indicatorName)
    local sizeW, sizeH = ResolveSize(cfg)
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    if indicatorName == "dispels" and not (cfg.spacing and cfg.spacing[1]) then
        spacingX = -math.floor(sizeW / 2)
        spacingY = -math.floor(sizeH / 2)
    end
    local num = cfg.num or 3
    if indicatorName == "dispels" then
        num = 5
    end
    local numPerLine = cfg.numPerLine or num
    local pos = cfg.position or { "TOPRIGHT", "button", "TOPRIGHT", 0, 0 }
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
        local rowWidth = numPerLine * sizeW + math.max(numPerLine - 1, 0) * math.abs(spacingX) + 0.4
        if orientation == "top-to-bottom" or orientation == "bottom-to-top" then
            rowWidth = sizeH + 0.4
        end
        pcall(container.SetFlowLayoutMaximumLineSize, container, rowWidth)
    end

    local parent = ResolveContainerParent(unitButton)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + (cfg.frameLevel or 5))
end

local function CreateIndicatorContainer(unitButton, indicatorName, cfg)
    local groups = BuildGroupsForIndicator(indicatorName, cfg)
    if #groups == 0 then
        return nil, "skip"
    end

    EnsureAuraContainerLoaded()
    local parent = ResolveContainerParent(unitButton)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not container then
        return nil, tostring(container)
    end

    local sizeW, sizeH = ResolveSize(cfg)
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    if indicatorName == "dispels" and not (cfg.spacing and cfg.spacing[1]) then
        spacingX = -math.floor(sizeW / 2)
        spacingY = -math.floor(sizeH / 2)
    end
    local unit = ResolveUnit(unitButton) or "player"
    local defaultInitFn = MakeInitAuraButton(cfg)

    container:SetEnabled(false)
    container:Hide()
    AnchorContainer(container, unitButton, cfg, indicatorName)
    pcall(container.SetUnit, container, unit)

    for i = 1, #groups do
        local g = groups[i]
        local initFn = defaultInitFn
        if g.dispelToken then
            initFn = MakeInitDispelAuraButton(cfg, g.dispelToken, unitButton)
        end
        local groupOpts = {
            maxFrameCount = g.maxFrameCount or cfg.num or 3,
            initializeFrame = initFn,
            layout = {
                elementWidth = sizeW,
                elementHeight = sizeH,
                elementSpacing = spacingX,
                lineSpacing = spacingY,
            },
        }
        if g.candidateFilters then
            groupOpts.candidateFilters = g.candidateFilters
        end
        if AuraContainerSortMethod and AuraContainerSortMethod.Default then
            groupOpts.sortMethod = AuraContainerSortMethod.Default
        end
        if AuraContainerSortDirection and AuraContainerSortDirection.Normal then
            groupOpts.sortDirection = AuraContainerSortDirection.Normal
        end
        local addOk, addErr = pcall(container.AddAuraGroup, container, g.key, g.filter, groupOpts)
        if not addOk then
            container:SetParent(nil)
            return nil, tostring(addErr)
        end
    end

    AnchorContainer(container, unitButton, cfg, indicatorName)
    if container.UpdateAllAuras then
        pcall(container.UpdateAllAuras, container)
    end
    return container
end

local function DriveContainer(unitButton, indicatorName, cfg, enable)
    local map = stateByButton[unitButton]
    local st = map and map[indicatorName]
    if not (st and st.container and cfg) then return end
    local unit = ResolveUnit(unitButton)
    AnchorContainer(st.container, unitButton, cfg, indicatorName)
    if unit then
        pcall(st.container.SetUnit, st.container, unit)
    end
    if enable then
        st.container:Show()
        st.container:SetEnabled(true)
        if st.container.UpdateAllAuras then
            pcall(st.container.UpdateAllAuras, st.container)
        end
        HideLegacy(unitButton, indicatorName)
    else
        st.container:SetEnabled(false)
        st.container:Hide()
        ShowLegacy(unitButton, indicatorName)
    end
end

local function EnsureIndicatorContainer(unitButton, indicatorName, cfg, allowCreate)
    if not ProbeSupported() then return false end
    local map = stateByButton[unitButton]
    if not map then
        map = {}
        stateByButton[unitButton] = map
    end
    local st = map[indicatorName]
    if not st then
        st = {}
        map[indicatorName] = st
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
        local highlightChanged = indicatorName == "dispels"
            and st.highlightType ~= NormalizeDispelHighlightType(cfg.highlightType)
        if (p == UIParent or p == nil or st.initVersion ~= INIT_VERSION or highlightChanged) and allowCreate then
            DestroyContainer(st)
        end
    end

    if st.container then
        return true
    end

    if not allowCreate then
        return false
    end

    local container, err = CreateIndicatorContainer(unitButton, indicatorName, cfg)
    if not container then
        st.createFailed = true
        st.failedVersion = INIT_VERSION
        if err ~= "skip" and not Cell.vars._combatAuraDisplayWarned then
            Cell.vars._combatAuraDisplayWarned = true
            F.Print("|cFFFF7D7DCombat AuraContainer (" .. indicatorName .. ") failed:|r " .. tostring(err))
        end
        return false
    end
    st.container = container
    st.hlContainer = nil
    st.initVersion = INIT_VERSION
    st.highlightType = indicatorName == "dispels" and NormalizeDispelHighlightType(cfg.highlightType) or nil
    st.createFailed = nil
    st.failedVersion = nil
    return true
end

local buildQueue = {}
local buildQueued = setmetatable({}, { __mode = "k" })
local buildTicker

local EnqueueBuild

local function NeedsContainerBuild(unitButton, name, cfg)
    if not cfg then return false end
    local map = stateByButton[unitButton]
    local st = map and map[name]
    if st and st.container then return false end
    if st and st.createFailed and st.failedVersion == INIT_VERSION then return false end
    return true
end

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

    RefreshCachedLayouts()
    for i = 1, #TRACKED do
        local name = TRACKED[i]
        local cfg = cachedLayouts and cachedLayouts[name]
        if NeedsContainerBuild(b, name, cfg) then
            if EnsureIndicatorContainer(b, name, cfg, true) then
                DriveContainer(b, name, cfg, true)
            end
            break
        end
    end

    local more = false
    for i = 1, #TRACKED do
        local name = TRACKED[i]
        local cfg = cachedLayouts and cachedLayouts[name]
        if NeedsContainerBuild(b, name, cfg) then
            more = true
            break
        end
    end
    if more then
        EnqueueBuild(b)
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
    RefreshCachedLayouts()
    if allowCreate == nil then
        allowCreate = true
    end

    local seen = {}
    local needsBuild = false
    for i = 1, #TRACKED do
        local name = TRACKED[i]
        local cfg = cachedLayouts and cachedLayouts[name]
        if cfg then
            seen[name] = true
            if EnsureIndicatorContainer(unitButton, name, cfg, false) then
                DriveContainer(unitButton, name, cfg, true)
            elseif NeedsContainerBuild(unitButton, name, cfg) then
                needsBuild = true
            end
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

function I.ShouldSkipLegacyCombatAura(indicatorName)
    if not ProbeSupported() or not indicatorName then
        return false
    end
    local tracked = false
    for i = 1, #TRACKED do
        if TRACKED[i] == indicatorName then
            tracked = true
            break
        end
    end
    if not tracked then
        return false
    end
    RefreshCachedLayouts()
    return cachedLayouts and cachedLayouts[indicatorName] and true or false
end

function I.CombatAuraDisplayActive()
    return ProbeSupported()
end

function I.HasCombatAuraContainer(unitButton, indicatorName)
    if not (unitButton and indicatorName) then return false end
    local map = stateByButton[unitButton]
    local st = map and map[indicatorName]
    return st and st.container and true or false
end

function I.SyncCombatAuraDisplays(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

function I.UpdateCombatAuraDisplays(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

function I.RefreshAllCombatAuraDisplays()
    if not SUPPORTED then return end
    RefreshCachedLayouts()
    F.IterateAllUnitButtons(function(b)
        DestroyButtonState(b)
        EnqueueBuild(b)
    end, true)
end

if SUPPORTED then
    Cell.RegisterCallback("UpdateIndicators", "CombatAuraDisplay_UpdateIndicators", function()
        C_Timer.After(0, I.RefreshAllCombatAuraDisplays)
    end)

    Cell.RegisterCallback("UpdateLayout", "CombatAuraDisplay_UpdateLayout", function()
        C_Timer.After(0, I.RefreshAllCombatAuraDisplays)
    end)

    Cell.RegisterCallback("RaidDebuffsChanged", "CombatAuraDisplay_RaidDebuffs", function()
        C_Timer.After(0, I.RefreshAllCombatAuraDisplays)
    end)

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:RegisterEvent("PLAYER_REGEN_DISABLED")
    boot:RegisterEvent("PLAYER_REGEN_ENABLED")
    boot:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.5, I.RefreshAllCombatAuraDisplays)
            return
        end
        RefreshCachedLayouts()
        F.IterateAllUnitButtons(function(b)
            SyncButton(b, true)
        end, true)
    end)
end
