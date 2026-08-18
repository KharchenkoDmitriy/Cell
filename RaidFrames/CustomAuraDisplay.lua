local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

local INIT_VERSION = 21
local BUILD = select(4, GetBuildInfo())
local SUPPORTED = Cell.isRetail and BUILD >= 120100

local SUPPORTED_TYPES = {
    icon = true, icons = true, color = true, border = true,
    text = true, bar = true, bars = true, rect = true,
    texture = true, overlay = true, block = true, blocks = true,
}

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
    pcall(function()
        container:Hide()
        container:SetParent(nil)
    end)
    featureReady = type(container.AddAuraGroup) == "function"
        and type(container.SetUnit) == "function"
        and type(container.SetEnabled) == "function"
    return featureReady
end

local function IsOverlayType(cfgType)
    return cfgType == "color" or cfgType == "border" or cfgType == "overlay"
end

local function IsSingleSlot(cfgType)
    return cfgType ~= "icons" and cfgType ~= "bars" and cfgType ~= "blocks"
end

local function GetElementSize(cfg)
    if IsOverlayType(cfg.type) then
        return 1, 1
    end
    if cfg.type == "text" then
        local s = (type(cfg.font) == "table" and cfg.font[2]) or 12
        return s, s
    end
    local w = (cfg.size and cfg.size[1]) or 13
    local h = (cfg.size and cfg.size[2]) or w
    return w, h
end

local function AuraEntrySpellId(k, v)
    if type(v) == "table" then
        local n = tonumber(v[1])
        if n and n > 0 then return n end
        return
    end
    local n = tonumber(v)
    if n and n > 0 then return n end
    n = tonumber(k)
    if n and n > 0 then return n end
end

local function IsSupportedCustomCfg(t)
    if not (t and t.enabled) then return false end
    if t.auraType ~= "buff" and t.auraType ~= "debuff" then return false end
    if t.name == "Healers" then return false end
    if not SUPPORTED_TYPES[t.type] then return false end
    if type(t.indicatorName) ~= "string" or not t.indicatorName:find("^indicator") then return false end
    if type(t.auras) ~= "table" then return false end
    local hasSpell = false
    for k, v in pairs(t.auras) do
        if AuraEntrySpellId(k, v) then
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
        local n = AuraEntrySpellId(k, v)
        if n then map[n] = true end
    end
    local alts = Cell.AuraBlacklist and Cell.AuraBlacklist.AlternateSpellIDs
    if type(alts) == "table" then
        for altId, primaryId in pairs(alts) do
            if map[primaryId] then
                map[altId] = true
            elseif map[altId] then
                map[primaryId] = true
            end
        end
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

local function BuildFilter(castBy, auraType)
    local base = (auraType == "debuff") and "HARMFUL" or "HELPFUL"
    if castBy == "anyone" or castBy == "others" then
        return base
    end
    return base .. "|PLAYER"
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

local function UnpackColor(c, fallback)
    fallback = fallback or { 0, 1, 0, 1 }
    if type(c) ~= "table" then
        return fallback[1], fallback[2], fallback[3], fallback[4] or 1
    end
    return c[1] or fallback[1], c[2] or fallback[2], c[3] or fallback[3], c[4] or fallback[4] or 1
end

local function GetCfgColor(cfg, fallback)
    local colors = cfg and cfg.colors
    if type(colors) ~= "table" then
        return UnpackColor(nil, fallback)
    end
    if type(colors[1]) == "table" then
        return UnpackColor(colors[1], fallback)
    end
    if type(colors[1]) == "string" and type(colors[2]) == "table" then
        return UnpackColor(colors[2], fallback)
    end
    return UnpackColor(nil, fallback)
end

local function GetSpellTexture(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then return tex end
    end
    local _, icon = F.GetSpellInfo(spellId)
    return icon
end

local function AddTextureColorKey(map, key, color)
    if key == nil or key == "" then return end
    map[key] = color
    if type(key) ~= "string" then
        map[tostring(key)] = color
    end
end

local function BuildTextureColorMap(auras)
    local map, first = {}, nil
    if type(auras) ~= "table" then return map, first end
    for k, v in pairs(auras) do
        local id, color
        if type(v) == "table" then
            id = tonumber(v[1])
            if type(v[2]) == "table" then color = v[2] end
        else
            id = AuraEntrySpellId(k, v)
        end
        if id and color then
            first = first or color
            AddTextureColorKey(map, GetSpellTexture(id), color)
            local _, icon = F.GetSpellInfo(id)
            AddTextureColorKey(map, icon, color)
            if C_Spell and C_Spell.GetSpellInfo then
                local info = C_Spell.GetSpellInfo(id)
                if type(info) == "table" then
                    AddTextureColorKey(map, info.iconID, color)
                    AddTextureColorKey(map, info.originalIconID, color)
                end
            end
        end
    end
    return map, first
end

local function ResolveIconTexture(button, fallback)
    if button and button.GetIcon then
        local ok, tex = pcall(button.GetIcon, button)
        if ok and tex then return tex end
    end
    return fallback
end

local function HookIconColor(icon, texMap, firstColor, apply)
    if not icon or not apply then return end
    local function onTex(_, tex)
        apply((texMap and tex and texMap[tex]) or (texMap and tex and texMap[tostring(tex)]) or firstColor)
    end
    hooksecurefunc(icon, "SetTexture", onTex)
    if icon.SetAtlas then
        hooksecurefunc(icon, "SetAtlas", onTex)
    end
end

local function AttachHiddenIcon(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetAlpha(0)
    pcall(button.SetIcon, button, icon)
    return icon
end

local function DurationBarOpts()
    local barOpts = {}
    if Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime then
        barOpts.direction = Enum.StatusBarTimerDirection.ElapsedTime
    end
    if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate then
        barOpts.interpolation = Enum.StatusBarInterpolation.Immediate
    end
    return barOpts
end

local function AttachDurationBar(button, orientation, r, g, b, a)
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:EnableMouse(false)
    if orientation == "vertical" or orientation == "top-to-bottom" or orientation == "bottom-to-top" then
        bar:SetOrientation("VERTICAL")
    else
        bar:SetOrientation("HORIZONTAL")
    end
    bar:SetReverseFill(true)
    bar:SetStatusBarTexture(Cell.vars.whiteTexture or Cell.vars.texture)
    local barTex = bar:GetStatusBarTexture()
    if barTex then
        barTex:SetVertexColor(r or 0, g or 1, b or 0, a or 1)
    end
    pcall(button.SetDurationBar, button, bar, DurationBarOpts())
    return bar
end

local function AttachStackAndDuration(button, cfg, host, animFrame)
    host = host or button
    local textHost = CreateFrame("Frame", nil, host)
    textHost:SetAllPoints(host)
    textHost:EnableMouse(false)
    local baseLevel = (animFrame and animFrame.GetFrameLevel and animFrame:GetFrameLevel())
        or (button.GetFrameLevel and button:GetFrameLevel())
        or 1
    textHost:SetFrameLevel(baseLevel + 10)

    if cfg.showStack ~= false then
        local stack = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        local fontCfg = cfg.font and cfg.font[1]
        local point = (type(fontCfg) == "table" and fontCfg[5]) or "TOPRIGHT"
        local ox = (type(fontCfg) == "table" and fontCfg[6]) or 2
        local oy = (type(fontCfg) == "table" and fontCfg[7]) or 1
        stack:ClearAllPoints()
        stack:SetPoint(point, textHost, point, ox, oy)
        stack:SetJustifyH("RIGHT")
        StyleFont(stack, fontCfg, 11)
        if type(fontCfg) == "table" and type(fontCfg[8]) == "table" then
            stack:SetTextColor(fontCfg[8][1] or 1, fontCfg[8][2] or 1, fontCfg[8][3] or 1, fontCfg[8][4] or 1)
        else
            stack:SetTextColor(1, 1, 1, 1)
        end
        pcall(button.SetApplicationCount, button, stack, {})
    end

    local showDuration = ShouldShowDuration(cfg)
    if not showDuration and cfg.duration and cfg.duration[1] then
        showDuration = true
    end
    if showDuration then
        local duration = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        local fontCfg = (cfg.font and cfg.font[2]) or cfg.font
        local point = (type(fontCfg) == "table" and fontCfg[5]) or "BOTTOMRIGHT"
        local ox = (type(fontCfg) == "table" and fontCfg[6]) or 2
        local oy = (type(fontCfg) == "table" and fontCfg[7]) or -1
        duration:ClearAllPoints()
        duration:SetPoint(point, textHost, point, ox, oy)
        duration:SetJustifyH("RIGHT")
        StyleFont(duration, fontCfg, 11)
        if type(fontCfg) == "table" and type(fontCfg[8]) == "table" then
            duration:SetTextColor(fontCfg[8][1] or 1, fontCfg[8][2] or 1, fontCfg[8][3] or 1, fontCfg[8][4] or 1)
        else
            duration:SetTextColor(1, 1, 1, 1)
        end
        F.BindAuraDurationText(button, duration, GetCellDurationFormatter(), cfg.auras)
    end
    return textHost
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
    if type(cfg) == "table" and cfg.type == "rect" then
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

local function AttachDurationAnimation(button, cfg)
    local style = ResolveAnimationStyle(cfg)
    if style == "none" then
        return AttachInvisibleCooldown(button)
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
        pcall(button.SetDurationBar, button, bar, DurationBarOpts())
        return bar
    end

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
    return cooldown
end

local function AnchorColorOverlay(tex, unitButton, cfg)
    local anchor = (cfg and cfg.anchor) or "healthbar-current"
    local w = unitButton.widgets
    tex:ClearAllPoints()
    if anchor == "healthbar-current" and w and w.healthBar then
        tex:SetAllPoints(w.healthBar:GetStatusBarTexture())
    elseif anchor == "healthbar-loss" and w and w.healthBarLoss then
        tex:SetAllPoints(w.healthBarLoss)
    elseif anchor == "healthbar-entire" and w and w.healthBar then
        tex:SetAllPoints(w.healthBar)
    else
        local inset = CELL_BORDER_SIZE or 1
        tex:SetPoint("TOPLEFT", unitButton, "TOPLEFT", inset, -inset)
        tex:SetPoint("BOTTOMRIGHT", unitButton, "BOTTOMRIGHT", -inset, inset)
    end
end

local function ApplyColorOverlay(solidTex, gradientTex, cfg, unitButton)
    local colors = cfg and cfg.colors
    if type(colors) ~= "table" then
        solidTex:SetVertexColor(1, 0, 0.4, 1)
        solidTex:Show()
        gradientTex:Hide()
        return
    end

    local kind = colors[1]
    if kind == "gradient-vertical" or kind == "gradient-horizontal" then
        local c1, c2 = colors[2], colors[3]
        if type(c1) == "table" and type(c2) == "table" then
            local dir = (kind == "gradient-vertical") and "VERTICAL" or "HORIZONTAL"
            gradientTex:SetGradient(dir,
                CreateColor(c1[1] or 1, c1[2] or 0, c1[3] or 0, c1[4] or 1),
                CreateColor(c2[1] or 0, c2[2] or 0, c2[3] or 0, c2[4] or 1))
        end
        gradientTex:Show()
        solidTex:Hide()
        return
    end

    local r, g, b, a = 1, 0, 0.4, 1
    if kind == "class-color" then
        r, g, b = F.GetClassColor(unitButton.states and unitButton.states.class)
        r, g, b, a = r or 1, g or 1, b or 1, 1
    elseif kind == "change-over-time" and type(colors[4]) == "table" then
        r, g, b, a = colors[4][1], colors[4][2], colors[4][3], colors[4][4] or 1
    elseif type(colors[2]) == "table" then
        r, g, b, a = colors[2][1], colors[2][2], colors[2][3], colors[2][4] or 1
    end
    solidTex:SetVertexColor(r, g, b, a)
    solidTex:Show()
    gradientTex:Hide()
end

local function MakeInitColorButton(cfg, unitButton)
    return function(button)
        pcall(button.SetSize, button, 0.001, 0.001)
        F.SetupEngineAuraButtonMouse(button, true)

        local dummy = button:CreateTexture(nil, "ARTWORK")
        dummy:SetAllPoints(button)
        dummy:SetColorTexture(0, 0, 0, 0)
        pcall(button.SetIcon, button, dummy)

        local solidTex = button:CreateTexture(nil, "ARTWORK", nil, 3)
        solidTex:SetTexture(Cell.vars.texture or Cell.vars.whiteTexture)
        AnchorColorOverlay(solidTex, unitButton, cfg)

        local gradientTex = button:CreateTexture(nil, "ARTWORK", nil, 3)
        gradientTex:SetTexture(Cell.vars.whiteTexture)
        AnchorColorOverlay(gradientTex, unitButton, cfg)

        ApplyColorOverlay(solidTex, gradientTex, cfg, unitButton)

        local health = unitButton.widgets and unitButton.widgets.healthBar
        local base = (health and health.GetFrameLevel and health:GetFrameLevel())
            or (unitButton.GetFrameLevel and unitButton:GetFrameLevel())
            or 1
        pcall(button.SetFrameLevel, button, base + (cfg.frameLevel or 1))
    end
end

local function GetBorderColor(cfg)
    local auras = cfg and cfg.auras
    if type(auras) == "table" then
        for _, v in ipairs(auras) do
            if type(v) == "table" and type(v[2]) == "table" then
                local c = v[2]
                return c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 1
            end
        end
    end
    return 1, 0, 0, 1
end

local function MakeInitBorderButton(cfg, unitButton)
    return function(button)
        pcall(button.SetSize, button, 0.001, 0.001)
        F.SetupEngineAuraButtonMouse(button, true)

        local dummy = button:CreateTexture(nil, "ARTWORK")
        dummy:SetAllPoints(button)
        dummy:SetColorTexture(0, 0, 0, 0)
        pcall(button.SetIcon, button, dummy)

        local inset = CELL_BORDER_SIZE or 1
        local thickness = cfg.thickness or 2
        local r, g, b, a = GetBorderColor(cfg)

        local tex = button:CreateTexture(nil, "ARTWORK", nil, 3)
        tex:SetTexture(Cell.vars.whiteTexture)
        tex:SetVertexColor(r, g, b, a)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", unitButton, "TOPLEFT", inset, -inset)
        tex:SetPoint("BOTTOMRIGHT", unitButton, "BOTTOMRIGHT", -inset, inset)

        local mask = button:CreateMaskTexture()
        mask:SetTexture(Cell.vars.emptyTexture, "CLAMPTOWHITE", "CLAMPTOWHITE")
        mask:ClearAllPoints()
        mask:SetPoint("TOPLEFT", tex, "TOPLEFT", thickness, -thickness)
        mask:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -thickness, thickness)
        tex:AddMaskTexture(mask)

        local tex2 = button:CreateTexture(nil, "ARTWORK", nil, 2)
        tex2:SetColorTexture(0, 0, 0, 1)
        tex2:ClearAllPoints()
        tex2:SetPoint("TOPLEFT", unitButton, "TOPLEFT", inset, -inset)
        tex2:SetPoint("BOTTOMRIGHT", unitButton, "BOTTOMRIGHT", -inset, inset)

        local mask2 = button:CreateMaskTexture()
        mask2:SetTexture(Cell.vars.emptyTexture, "CLAMPTOWHITE", "CLAMPTOWHITE")
        mask2:ClearAllPoints()
        mask2:SetPoint("TOPLEFT", tex2, "TOPLEFT", thickness + inset, -(thickness + inset))
        mask2:SetPoint("BOTTOMRIGHT", tex2, "BOTTOMRIGHT", -(thickness + inset), thickness + inset)
        tex2:AddMaskTexture(mask2)

        local host = unitButton.widgets and unitButton.widgets.highLevelFrame or unitButton
        local base = (host.GetFrameLevel and host:GetFrameLevel())
            or (unitButton.GetFrameLevel and unitButton:GetFrameLevel())
            or 1
        pcall(button.SetFrameLevel, button, base + (cfg.frameLevel or 10))
    end
end

local function MakeInitTextButton(cfg)
    return function(button)
        local size = (type(cfg.font) == "table" and cfg.font[2]) or 12
        pcall(button.SetSize, button, size, size)
        F.SetupEngineAuraButtonMouse(button, cfg.showTooltip ~= true, cfg)
        AttachHiddenIcon(button)

        local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        text:SetPoint("CENTER", 1, 0)
        StyleFont(text, cfg.font, size)
        local r, g, b, a = GetCfgColor(cfg, { 0, 1, 0, 1 })
        text:SetTextColor(r, g, b, a)

        local showDuration = cfg.duration and cfg.duration[1]
        local showStack = not (cfg.stack and cfg.stack[1] == false)
        if showDuration then
            F.BindAuraDurationText(button, text, GetCellDurationFormatter(), cfg.auras)
            if showStack then
                local stack = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                stack:SetPoint("TOPRIGHT", 2, 1)
                StyleFont(stack, cfg.font, size)
                stack:SetTextColor(r, g, b, a)
                pcall(button.SetApplicationCount, button, stack, {})
            end
        elseif showStack then
            pcall(button.SetApplicationCount, button, text, {})
        end
    end
end

local function MakeInitRectButton(cfg)
    return function(button)
        local sizeW = (cfg.size and cfg.size[1]) or 11
        local sizeH = (cfg.size and cfg.size[2]) or 4
        pcall(button.SetSize, button, sizeW, sizeH)
        F.SetupEngineAuraButtonMouse(button, cfg.showTooltip ~= true, cfg)
        AttachHiddenIcon(button)

        local r, g, b, a = GetCfgColor(cfg, { 0, 1, 0, 1 })
        local fill = button:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints(button)
        fill:SetColorTexture(r, g, b, a)

        local br, bg, bb, ba = 0, 0, 0, 1
        if type(cfg.colors) == "table" and type(cfg.colors[4]) == "table" then
            br, bg, bb, ba = UnpackColor(cfg.colors[4], { 0, 0, 0, 1 })
        end
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(button)
        border:SetColorTexture(br, bg, bb, ba)
        local mask = button:CreateMaskTexture()
        mask:SetTexture(Cell.vars.emptyTexture or "Interface\\Buttons\\WHITE8X8", "CLAMPTOWHITE", "CLAMPTOWHITE")
        mask:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
        mask:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
        border:AddMaskTexture(mask)

        local animFrame = AttachDurationAnimation(button, cfg)
        AttachStackAndDuration(button, cfg, button, animFrame)
    end
end

local function MakeInitBarButton(cfg)
    return function(button)
        local sizeW = (cfg.size and cfg.size[1]) or 18
        local sizeH = (cfg.size and cfg.size[2]) or 4
        pcall(button.SetSize, button, sizeW, sizeH)
        F.SetupEngineAuraButtonMouse(button, cfg.showTooltip ~= true, cfg)
        local icon = AttachHiddenIcon(button)

        local bgr, bgg, bgb, bga = 0.07, 0.07, 0.07, 0.9
        if type(cfg.colors) == "table" and type(cfg.colors[5]) == "table" then
            bgr, bgg, bgb, bga = UnpackColor(cfg.colors[5], { 0.07, 0.07, 0.07, 0.9 })
        end
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(button)
        bg:SetColorTexture(bgr, bgg, bgb, bga)

        local r, g, b, a = GetCfgColor(cfg, { 0, 1, 0, 1 })
        local texMap, firstColor = BuildTextureColorMap(cfg.auras)
        if firstColor then
            r, g, b, a = UnpackColor(firstColor, { r, g, b, a })
        end
        local fillOrientation = (cfg.type == "bar") and (cfg.orientation or "horizontal") or "horizontal"
        local bar = AttachDurationBar(button, fillOrientation, r, g, b, a)
        HookIconColor(ResolveIconTexture(button, icon), texMap, firstColor or { r, g, b, a }, function(color)
            if not (bar and color) then return end
            local cr, cg, cb, ca = UnpackColor(color, { r, g, b, a })
            local barTex = bar:GetStatusBarTexture()
            if barTex then
                barTex:SetVertexColor(cr, cg, cb, ca)
            end
        end)

        AttachStackAndDuration(button, cfg, button, bar)
    end
end

local function MakeInitBlockButton(cfg)
    return function(button)
        local sizeW = (cfg.size and cfg.size[1]) or 10
        local sizeH = (cfg.size and cfg.size[2]) or 10
        pcall(button.SetSize, button, sizeW, sizeH)
        F.SetupEngineAuraButtonMouse(button, cfg.showTooltip ~= true, cfg)
        local icon = AttachHiddenIcon(button)

        local texMap, firstColor = BuildTextureColorMap(cfg.auras)
        local r, g, b, a
        if cfg.type == "blocks" then
            r, g, b, a = UnpackColor(firstColor, { 0, 1, 0, 1 })
        else
            r, g, b, a = GetCfgColor(cfg, { 0, 1, 0, 1 })
        end
        local fill = button:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints(button)
        fill:SetColorTexture(r, g, b, a)

        local br, bg, bb, ba = 0, 0, 0, 1
        if type(cfg.colors) == "table" and type(cfg.colors[5]) == "table" then
            br, bg, bb, ba = UnpackColor(cfg.colors[5], { 0, 0, 0, 1 })
        end
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(button)
        border:SetColorTexture(br, bg, bb, ba)
        local mask = button:CreateMaskTexture()
        mask:SetTexture(Cell.vars.emptyTexture or "Interface\\Buttons\\WHITE8X8", "CLAMPTOWHITE", "CLAMPTOWHITE")
        mask:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
        mask:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
        border:AddMaskTexture(mask)

        if cfg.type == "blocks" then
            HookIconColor(ResolveIconTexture(button, icon), texMap, firstColor or { r, g, b, a }, function(color)
                if not color then return end
                fill:SetColorTexture(UnpackColor(color, { r, g, b, a }))
            end)
        end

        local animFrame = AttachDurationAnimation(button, cfg)
        AttachStackAndDuration(button, cfg, button, animFrame)
    end
end

local function MakeInitTextureButton(cfg, unitButton)
    return function(button)
        local sizeW = (cfg.size and cfg.size[1]) or 16
        local sizeH = (cfg.size and cfg.size[2]) or 16
        pcall(button.SetSize, button, sizeW, sizeH)
        F.SetupEngineAuraButtonMouse(button, cfg.showTooltip ~= true, cfg)
        AttachHiddenIcon(button)

        local tex = button:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(button)
        local texTbl = cfg.texture
        if type(texTbl) == "table" and texTbl[1] then
            local path = texTbl[1]
            if type(path) == "string" and strfind(strlower(path), "^interface") then
                tex:SetTexture(path)
            else
                tex:SetAtlas(path)
            end
            if texTbl[2] then
                tex:SetRotation((texTbl[2] or 0) * math.pi / 180)
            end
            if type(texTbl[3]) == "table" then
                tex:SetVertexColor(UnpackColor(texTbl[3], { 1, 1, 1, 1 }))
            end
        else
            tex:SetColorTexture(1, 1, 1, 1)
        end
    end
end

local function MakeInitOverlayButton(cfg, unitButton)
    return function(button)
        pcall(button.SetSize, button, 0.001, 0.001)
        F.SetupEngineAuraButtonMouse(button, true)
        AttachHiddenIcon(button)

        local health = unitButton.widgets and unitButton.widgets.healthBar
        local r, g, b, a = GetCfgColor(cfg, { 0, 0.61, 1, 0.55 })

        local bar = CreateFrame("StatusBar", nil, button)
        if health then
            bar:SetAllPoints(health)
        else
            bar:SetAllPoints(unitButton)
        end
        bar:EnableMouse(false)
        bar:SetStatusBarTexture(Cell.vars.whiteTexture or Cell.vars.texture)
        local orientation = cfg.orientation or "horizontal"
        if orientation == "vertical" then
            bar:SetOrientation("VERTICAL")
        else
            bar:SetOrientation("HORIZONTAL")
        end
        bar:SetReverseFill(true)
        local barTex = bar:GetStatusBarTexture()
        if barTex then
            barTex:SetVertexColor(r, g, b, a)
        end
        local parent = health or unitButton
        local base = (parent.GetFrameLevel and parent:GetFrameLevel()) or 1
        pcall(bar.SetFrameLevel, bar, base + (cfg.frameLevel or 1) + 55)
        pcall(button.SetDurationBar, button, bar, DurationBarOpts())
    end
end

local function MakeInitAuraButton(cfg)
    return function(button)
        local sizeW = (cfg.size and cfg.size[1]) or 13
        local sizeH = (cfg.size and cfg.size[2]) or sizeW
        pcall(button.SetSize, button, sizeW, sizeH)
        F.SetupEngineAuraButtonMouse(button, cfg.showTooltip ~= true, cfg)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)

        local animFrame = AttachDurationAnimation(button, cfg)

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
            F.BindAuraDurationText(button, duration, GetCellDurationFormatter(), cfg.auras)
        end
    end
end

local function ResolveContainerParent(unitButton, cfg)
    if cfg and cfg.type == "border" and unitButton.widgets and unitButton.widgets.highLevelFrame then
        return unitButton.widgets.highLevelFrame
    end
    if cfg and cfg.type == "overlay" and unitButton.widgets and unitButton.widgets.healthBar then
        return unitButton.widgets.healthBar
    end
    if unitButton.widgets and unitButton.widgets.indicatorFrame then
        return unitButton.widgets.indicatorFrame
    end
    return unitButton
end

local function HideLegacy(unitButton, indicatorName)
    local ind = unitButton.indicators and indicatorName and unitButton.indicators[indicatorName]
    if not ind then return end
    if ind.StopGlow then
        pcall(ind.StopGlow, ind)
    end
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
    st.container:Hide()
    pcall(st.container.SetUnit, st.container, nil)
    st.container:SetParent(nil)
    st.container = nil
    st.boundUnit = nil
end

local function AnchorContainer(container, unitButton, cfg)
    local sizeW, sizeH = GetElementSize(cfg)
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    local num = IsSingleSlot(cfg.type) and 1 or (cfg.num or 5)
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

    local parent = ResolveContainerParent(unitButton, cfg)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + (cfg.frameLevel or 5))
end

local function CreateCustomContainer(unitButton, cfg)
    local spellMap = BuildSpellMap(cfg.auras)
    if SpellMapCount(spellMap) == 0 then
        return nil, "empty spell list"
    end

    EnsureAuraContainerLoaded()
    local parent = ResolveContainerParent(unitButton, cfg)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not container then
        return nil, tostring(container)
    end

    local sizeW, sizeH = GetElementSize(cfg)
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    local filter = BuildFilter(cfg.castBy, cfg.auraType)
    local unit = ResolveUnit(unitButton) or "player"
    local maxCount = IsSingleSlot(cfg.type) and 1 or (cfg.num or 5)
    local groupKey = cfg.indicatorName

    AnchorContainer(container, unitButton, cfg)

    local initFrame
    if cfg.type == "color" then
        initFrame = MakeInitColorButton(cfg, unitButton)
    elseif cfg.type == "border" then
        initFrame = MakeInitBorderButton(cfg, unitButton)
    elseif cfg.type == "text" then
        initFrame = MakeInitTextButton(cfg)
    elseif cfg.type == "rect" then
        initFrame = MakeInitRectButton(cfg)
    elseif cfg.type == "bar" or cfg.type == "bars" then
        initFrame = MakeInitBarButton(cfg)
    elseif cfg.type == "block" or cfg.type == "blocks" then
        initFrame = MakeInitBlockButton(cfg)
    elseif cfg.type == "texture" then
        initFrame = MakeInitTextureButton(cfg, unitButton)
    elseif cfg.type == "overlay" then
        initFrame = MakeInitOverlayButton(cfg, unitButton)
    else
        initFrame = MakeInitAuraButton(cfg)
    end
    local rawInit = initFrame
    initFrame = function(button)
        local ok, err = pcall(rawInit, button)
        if not ok and not Cell.vars._customAuraInitWarned then
            Cell.vars._customAuraInitWarned = true
            F.Print("|cFFFF7D7DCustom indicator setup failed:|r " .. tostring(err))
        end
    end

    local groupOpts = {
        maxFrameCount = maxCount,
        candidateFilters = {
            includeSpellIDs = spellMap,
            excludeSpellIDs = BuildExcludeSpellMap(),
        },
        initializeFrame = initFrame,
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
    pcall(container.SetUnit, container, unit)
    if container.UpdateAllAuras then
        pcall(container.UpdateAllAuras, container)
    end
    return container
end

function I.ForEachCustomAuraContainer(func)
    if not func then return end
    for _, map in pairs(stateByButton) do
        if type(map) == "table" then
            for _, st in pairs(map) do
                if st and st.container then
                    func(st.container)
                end
            end
        end
    end
end

local function DriveContainer(unitButton, cfg, enable)
    local map = stateByButton[unitButton]
    local st = map and map[cfg.indicatorName]
    if not (st and st.container and cfg) then return end
    if Cell.vars.editModeOpen then
        return
    end
    local unit = ResolveUnit(unitButton)
    AnchorContainer(st.container, unitButton, cfg)
    if enable then
        st.container:Show()
        if unit and st.boundUnit ~= unit then
            pcall(st.container.SetUnit, st.container, unit)
            st.boundUnit = unit
        end
        if st.container.UpdateAllAuras then
            pcall(st.container.UpdateAllAuras, st.container)
        end
        HideLegacy(unitButton, cfg.indicatorName)
    else
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
    st.boundUnit = ResolveUnit(unitButton)
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
                    st.container:Hide()
                end
                ShowLegacy(unitButton, name)
                local ind = unitButton.indicators and unitButton.indicators[name]
                if ind and (ind.indicatorType == "color" or ind.indicatorType == "border"
                    or ind.indicatorType == "glow" or ind.indicatorType == "overlay"
                    or ind.indicatorType == "texture") then
                    ind:Hide()
                end
            end
        end
    end
end

function I.ShouldSkipLegacyCustom(indicatorTable)
    if indicatorTable and indicatorTable.type == "glow" then
        return true
    end
    if not ProbeSupported() or not indicatorTable then
        return false
    end
    if IsSupportedCustomCfg(indicatorTable) then
        return true
    end
    if indicatorTable.name == "Healers" then
        return false
    end
    return SUPPORTED_TYPES[indicatorTable.type] and true or false
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
            or setting == "showDuration" or setting == "showStack" or setting == "showTooltip"
            or setting == "checkbutton" or setting == "font"
            or setting == "type" or setting == "auraType"
            or setting == "colors" or setting == "anchor" or setting == "thickness"
            or setting == "glowOptions" or setting == "texture" or setting == "fadeOut"
            or setting == "smooth" or setting == "maxValue" or setting == "duration"
            or setting == "stack" or setting == "barOrientation" then
            C_Timer.After(0, I.RefreshAllCustomAuraDisplays)
        end
    end)

    Cell.RegisterCallback("UpdateLayout", "CustomAuraDisplay_UpdateLayout", function()
        C_Timer.After(0, I.RefreshAllCustomAuraDisplays)
    end)

    Cell.RegisterCallback("UpdateAppearance", "CustomAuraDisplay_UpdateAppearance", function(which)
        if which == nil or which == "icon" or which == "reset" then
            C_Timer.After(0, I.RefreshAllCustomAuraDisplays)
        end
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
