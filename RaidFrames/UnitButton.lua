local _, Cell = ...

-- UnitButton tiene ~560 file-scope locals. WoW Lua 5.1 limita a 200 locales
-- por función y cuenta TODAS las locales del scope contenedor como upvalues
-- (límite: 60). Dividimos el archivo en 3 IIFEs SIBLINGS (no anidados):
--   Seg 1 (line 7, ~200 locals): imports, helpers, UnitButton_UpdateDebuffs
--   Seg 2 (line 2008, ~200 locals): buffs, events, health, power
--   Seg 3 (line 4310, ~70 locals): color curves, OnLoad, initialization
-- Cada IIFE recibe Cell como parámetro (0 upvalues). Función cross-segment
-- via Cell._* exports/imports o variables globales.
(function(Cell)
    local L = Cell.L
    ---@type CellFuncs
    local F = Cell.funcs
    ---@class CellUnitButtonFuncs
    local B = Cell.bFuncs
    ---@type CellIndicatorFuncs
    local I = Cell.iFuncs
    ---@type CellUtilityFuncs
    local U = Cell.uFuncs
    ---@type PixelPerfectFuncs
    local P = Cell.pixelPerfectFuncs
    ---@type CellAnimations
    local A = Cell.animations
    local LGI = LibStub:GetLibrary("LibGroupInfo")

CELL_FADE_OUT_HEALTH_PERCENT = nil

local UnitGUID = UnitGUID
-- local UnitHealth = LibCLHealth.UnitHealth
local UnitName = UnitName
local GetUnitName = GetUnitName
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
-- 12.0+ APIs: secret value globals are only referenced in Utils.lua wrappers.
-- All callsites use F.IsValueNonSecret() / F.HasAnySecretValues() instead.
local UnitIsFriend = UnitIsFriend
local UnitIsUnit = UnitIsUnit
local UnitIsPlayer = UnitIsPlayer
local UnitIsConnected = UnitIsConnected
local UnitIsAFK = UnitIsAFK
local UnitIsFeignDeath = UnitIsFeignDeath
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitPowerType = UnitPowerType
local UnitPowerMax = UnitPowerMax
-- local UnitInRange = UnitInRange
-- local UnitIsVisible = UnitIsVisible
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local GetTime = GetTime
local GetRaidTargetIndex = GetRaidTargetIndex
local GetReadyCheckStatus = GetReadyCheckStatus
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitIsCharmed = UnitIsCharmed
local UnitInPartyIsAI = UnitInPartyIsAI
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitThreatSituation = UnitThreatSituation
local GetThreatStatusColor = GetThreatStatusColor
local UnitExists = UnitExists
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local UnitPhaseReason = UnitPhaseReason
local IsInRaid = IsInRaid
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo -- nil in 12.0+
local _GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
local GetAuraSlots = C_UnitAuras.GetAuraSlots
local _GetAuraDataBySlot = C_UnitAuras.GetAuraDataBySlot
local _GetAuraDispelTypeColor = C_UnitAuras.GetAuraDispelTypeColor
local _IsAuraFilteredOut = C_UnitAuras.IsAuraFilteredOutByInstanceID
local _GetAuraDuration = C_UnitAuras.GetAuraDuration -- 12.0+: NOT restricted, returns LuaDurationObject
-- wrapped versions applied after AnnotateAura is defined (see below)
local GetAuraDataByAuraInstanceID, GetAuraDataBySlot
local IsDelveInProgress = C_PartyInfo.IsDelveInProgress
-- 12.0+ heal prediction and interpolation APIs (nil pre-12.0)
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local CreateUnitHealPredictionCalculator = CreateUnitHealPredictionCalculator
local UnitHealthPercent = UnitHealthPercent
local AbbreviateNumbers = AbbreviateNumbers
local SBI_ExponentialEaseOut = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SBI_Immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

--! for AI followers, UnitClassBase is buggy
local UnitClassBase = function(unit)
    return select(2, UnitClass(unit))
end

local barAnimationType, highlightEnabled, predictionEnabled
local shieldEnabled, overshieldEnabled, overshieldReverseFillEnabled
local absorbEnabled, absorbInvertColor

local SECRET_HELPFUL_CAST_FALLBACK_WINDOW = 1.5
local secretHelpfulCastFallbacks = {
    [116841] = "external",  -- Tiger's Lust / Deseo del Tigre (se vuelve secreto en combate en Midnight)
    [1044] = "external",   -- Blessing of Freedom / Bendición de Libertad (cast spell = buff spell)
    [86150] = "defensive", -- Guardian of Ancient Kings (cast spell)
    [86659] = "defensive", -- Guardian of Ancient Kings (base buff)
    [212641] = "defensive", -- Guardian of Ancient Kings (glyph/model variant)
    [498] = "defensive",   -- Divine Protection / Protección Divina (Holy/Protection, buff = cast)
    [403876] = "defensive", -- Divine Protection / Protección Divina (Retribution, wrapper spell)
    [184662] = "defensive", -- Shield of Vengeance / Escudo de Venganza (legacy/live aura ID on some Midnight builds)
    [1261562] = "defensive", -- Shield of Vengeance / Escudo de Venganza (buff aura from Divine Protection)
    [325197] = "external", -- Invoke Chi-Ji / Invocar a Chi-Ji (cast spell, applies Life Cocoon to party)
    [406220] = "external", -- Life Cocoon / Crisálida de Chi (buff aura from Chi-Ji)
    [432472] = "external", -- Holy Armaments / Santos Arreos (cast; NOT in Cell's externals table — explicit fallback needed)
    [360823] = "external", -- Verdant Embrace / Abrazo Verde (Preservation Evoker; signature "0:1:0:0" overlaps with Lifebind — explicit fallback needed)
    [357170] = "external", -- Time Dilation / Dilatación Temporal (Preservation Evoker)
    [102342] = "external", -- Ironbark / Corteza de Hierro (Restoration Druid)
    [33206]  = "external", -- Pain Suppression / Supresión del Dolor (Discipline Priest)
    [10060]  = "external", -- Power Infusion / Infusión de Poder (Discipline/Holy Priest)
    [47788]  = "external", -- Guardian Spirit / Espíritu Guardián (Holy Priest)
    [1022]   = "external", -- Blessing of Protection / Bendición de Protección (Holy Paladin)
    [6940]   = "external", -- Blessing of Sacrifice / Bendición de Sacrificio (Holy Paladin)
}

-- Known external-cast buffs that should NOT be matched on the caster's own
-- frame (unit == "player"). External casts apply their buff to a TARGET
-- (another player or party member), not to the caster. When the caster's
-- frame sees a recently-added aura that matches an external fingerprint,
-- it's almost always a coincidental proc or personal buff, NOT the cast
-- result. Self-cast external buffs (Blessing of Freedom on self, etc.)
-- are NOT in this table — they DO land on the caster's frame.
-- Cast spellId -> true means: skip this cast's fingerprint on player frame.
local secretHelpfulCastSkipOnPlayer = {
    [325197] = true, -- Invoke Chi-Ji: Life Cocoon lands on party member, not caster
    [360823] = true, -- Verdant Embrace: Lifebind lands on party member, not caster
}

-- Expected buff info per cast spellId for Step 2.5 verification.
-- Maps cast spellId ? { spellId = expected buff spellId, spellIds = aliases, name = expected buff name (or nil) }.
-- Step 2.5 matches secret auras by their readable spellId/name against the expected
-- buff for the recent cast. Fully-secret auras from these explicit known pairs can
-- match by tight cast timing because the cast-to-buff mapping itself is curated.
local castExpectedBuff = {
    [116841]  = { spellId = 116841 },                  -- Tiger's Lust / Deseo del Tigre (cast = buff)
    [1044]    = { spellId = 1044 },                    -- Blessing of Freedom = Blessing of Freedom
    [86150]   = { spellId = 86150 },                   -- Guardian of Ancient Kings
    [86659]   = { spellId = 86659 },                   -- GoAK base buff
    [212641]  = { spellId = 212641 },                  -- GoAK glyph variant
    [498]     = { spellId = 498 },                                                   -- Divine Protection (Holy/Protection, buff = cast)
    [403876]  = { spellId = 1261562, spellIds = {[1261562]=true, [184662]=true} }, -- Divine Protection (Retribution, buff = Shield of Vengeance)
    [184662]  = { spellId = 184662, spellIds = {[184662]=true, [1261562]=true} },  -- Shield of Vengeance
    [1261562] = { spellId = 1261562, spellIds = {[1261562]=true, [184662]=true} }, -- Shield of Vengeance
    [325197]  = { spellId = 406220 },                  -- Invoke Chi-Ji → Life Cocoon
    [406220]  = { spellId = 406220 },                  -- Life Cocoon
    [432472]  = { spellId = 432472 },                  -- Holy Armaments
    [360823]  = { spellId = 363534 },                  -- Verdant Embrace → Lifebind
    [357170]  = { spellId = 357170 },                   -- Time Dilation
    [102342]  = { spellId = 102342 },                   -- Ironbark
    [33206]   = { spellId = 33206 },                    -- Pain Suppression
    [10060]   = { spellId = 10060 },                    -- Power Infusion
    [47788]   = { spellId = 47788 },                    -- Guardian Spirit
    [1022]    = { spellId = 1022 },                     -- Blessing of Protection
    [6940]    = { spellId = 6940 },                     -- Blessing of Sacrifice
}
local recentSecretHelpfulCasts = {}

-- Store HandleBuff's dependencies in Cell._hb to avoid the 60-upvalue limit.
-- HandleBuff.lua reads from _hb instead of capturing file-scope locals.
Cell._hb = {}
Cell._hb.SECRET_HELPFUL_CAST_FALLBACK_WINDOW = SECRET_HELPFUL_CAST_FALLBACK_WINDOW
Cell._hb.secretHelpfulCastFallbacks = secretHelpfulCastFallbacks
Cell._hb.secretHelpfulCastSkipOnPlayer = secretHelpfulCastSkipOnPlayer
Cell._hb.castExpectedBuff = castExpectedBuff
Cell._hb.recentSecretHelpfulCasts = recentSecretHelpfulCasts
Cell._hb._IsAuraFilteredOut = _IsAuraFilteredOut

local function DoesAuraMatchExpectedBuff(auraInfo, buffInfo, fallbackCastAt, maxAge, allowFullySecretTimeMatch)
    if not buffInfo then return false end

    if F.IsValueNonSecret(auraInfo.spellId) then
        if auraInfo.spellId == buffInfo.spellId then return true end
        return buffInfo.spellIds and buffInfo.spellIds[auraInfo.spellId] or false
    end

    if F.IsValueNonSecret(auraInfo.name) then
        local expectedName = buffInfo.name or F.GetSpellInfo(buffInfo.spellId)
        if expectedName and auraInfo.name == expectedName then return true end

        if buffInfo.spellIds then
            for id in pairs(buffInfo.spellIds) do
                expectedName = F.GetSpellInfo(id)
                if expectedName and auraInfo.name == expectedName then return true end
            end
        end
        return false
    end

    if not allowFullySecretTimeMatch then return false end

    -- Fully-secret known pair: accept only inside a tight window and only when
    -- the caller already proved this auraInstanceID was just added. Without that
    -- guard, a full/cache pass after a cast can falsely classify unrelated
    -- persistent buffs such as reputation tabards or Well Fed.
    -- This is intentionally limited to entries in castExpectedBuff, not the whole
    -- defensive table, to avoid false positives from unrelated combat procs.
    return fallbackCastAt and maxAge and (GetTime() - fallbackCastAt) <= maxAge
end

-- Midnight: Curve for CELL_FADE_OUT_HEALTH_PERCENT feature
-- Maps health percent -> alpha so we can evaluate secret health% without comparisons
local fadeOutHealthCurve
local fadeOutHealthCurve_threshold -- track last threshold to know when to rebuild
local fadeOutHealthCurve_alpha -- track last outOfRangeAlpha to know when to rebuild

-- Builds/rebuilds the fade-out health curve when threshold or alpha changes.
-- health% < threshold -> alpha 1.0 (fully visible, needs healing)
-- health% >= threshold -> outOfRangeAlpha (faded out, healthy enough)
local function RebuildFadeOutHealthCurve()
    if not Cell.isMidnight or not C_CurveUtil then return end
    local threshold = CELL_FADE_OUT_HEALTH_PERCENT
    local alpha = CellDB and CellDB["appearance"] and CellDB["appearance"]["outOfRangeAlpha"] or 0.4
    if not threshold then
        fadeOutHealthCurve = nil
        fadeOutHealthCurve_threshold = nil
        fadeOutHealthCurve_alpha = nil
        return
    end
    if fadeOutHealthCurve and fadeOutHealthCurve_threshold == threshold and fadeOutHealthCurve_alpha == alpha then
        return -- no change needed
    end
    fadeOutHealthCurve = C_CurveUtil.CreateCurve()
    -- Below threshold: fully visible (unit needs healing)
    fadeOutHealthCurve:AddPoint(0.0, 1.0)
    fadeOutHealthCurve:AddPoint(threshold - 0.001, 1.0)
    -- At/above threshold: faded out (unit is healthy enough)
    fadeOutHealthCurve:AddPoint(threshold, alpha)
    fadeOutHealthCurve:AddPoint(1.0, alpha)
    fadeOutHealthCurve_threshold = threshold
    fadeOutHealthCurve_alpha = alpha
end

local CheckCLEURequired

-------------------------------------------------
-- 12.0+ aura annotation (read-only tagging)
-------------------------------------------------
local function AnnotateAura(aura)
    if not aura then return nil end

    -- auraInstanceID is the cache key — if secret, drop the aura
    if not F.IsValueNonSecret(aura.auraInstanceID) then return nil end

    aura = F.CopyAuraTable(aura)

    -- Fast path: readable spellId means the aura is not opaque-secret.
    -- Prefer curated tables over fingerprint matching in that case.
    if F.IsValueNonSecret(aura.spellId) then
        aura._hasSecrets = false
        return aura
    end

    -- Slow path: opaque secret spellId
    aura._hasSecrets = true
    return aura
end

-- Wrap aura data retrieval to annotate secret state (read-only tag only)
GetAuraDataByAuraInstanceID = function(unit, id)
    return AnnotateAura(_GetAuraDataByAuraInstanceID(unit, id))
end
GetAuraDataBySlot = function(unit, slot)
    return AnnotateAura(_GetAuraDataBySlot(unit, slot))
end

-- _IsAuraFilteredOut is called directly (no pcall wrapper) — it's a stable
-- C API that won't error in normal use. The wrapper approach added table
-- allocation + pcall overhead for every aura, which caused GC pressure
-- in raid-sized groups.

-------------------------------------------------
-- 12.0+ dispel display via bracket curves
-------------------------------------------------
-- WoW step curves CLAMP below the first point (never return nil).
-- So we can't use nil/non-nil for type detection. Instead:
--
-- 1. Use F.IsValueNonSecret(aura.dispelName) to detect dispellable vs non-dispellable
--    (non-dispellable = nil, dispellable = SECRET in combat)
-- 2. Use "bracket curves" with 3 points to isolate each type:
--    e.g. Magic: {0:transparent, 1:visible, 2:transparent}
--    The step curve returns visible only for index 1, transparent for all others.
-- 3. Pass raw (secret) colors to C-level SetVertexColor for rendering.
--
-- Dispel type indices: None=0, Magic=1, Curse=2, Disease=3, Poison=4, Enrage=9, Bleed=11

local _dispelCurvesReady = false

-- Highlight curve: maps each type -> its correct display color
local _dispelHighlightCurve

-- Bracket curves: isolate each type (visible alpha for match, 0 alpha for non-match)
local _bracketCurves = {} -- [typeName] = curve

-- Type definitions for curve building (order matches Built-in.lua dispelOrder)
local _dispelTypes = {
    {name = "Magic",   idx = 1,  nextIdx = 2,  r = 0.20, g = 0.60, b = 1.00},
    {name = "Curse",   idx = 2,  nextIdx = 3,  r = 0.60, g = 0.00, b = 1.00},
    {name = "Disease", idx = 3,  nextIdx = 4,  r = 0.60, g = 0.40, b = 0.00},
    {name = "Poison",  idx = 4,  nextIdx = 5,  r = 0.00, g = 0.60, b = 0.00},
    {name = "Bleed",   idx = 11, nextIdx = nil, r = 1.00, g = 0.20, b = 0.60},
}

-- Feature check via API existence (no pcall — check before calling)
if C_CurveUtil and C_CurveUtil.CreateColorCurve and _GetAuraDispelTypeColor
    and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
    local stepType = Enum.LuaCurveType.Step
    local transparent = CreateColor(0, 0, 0, 0)

    -- highlight curve: all types -> correct colors, non-dispellable -> transparent
    _dispelHighlightCurve = C_CurveUtil.CreateColorCurve()
    _dispelHighlightCurve:SetType(stepType)
    _dispelHighlightCurve:AddPoint(0, transparent)  -- None
    for _, t in ipairs(_dispelTypes) do
        _dispelHighlightCurve:AddPoint(t.idx, CreateColor(t.r, t.g, t.b, 1))
    end
    _dispelHighlightCurve:AddPoint(9, transparent)  -- Enrage

    -- bracket curves: isolate each type
    -- e.g. Magic: {0:transparent, 1:typeColor, 2:transparent}
    for _, t in ipairs(_dispelTypes) do
        local curve = C_CurveUtil.CreateColorCurve()
        curve:SetType(stepType)
        curve:AddPoint(0, transparent) -- below target: invisible
        curve:AddPoint(t.idx, CreateColor(t.r, t.g, t.b, 1)) -- target: visible
        if t.nextIdx then
            curve:AddPoint(t.nextIdx, transparent) -- above target: invisible
        end
        _bracketCurves[t.name] = curve
    end

    _dispelCurvesReady = true
end

-- Get a ColorMixin from a curve for a specific aura.
-- Returns nil if curve is nil or aura has expired (API returns nil for invalid auras).
local function _getCurveColor(unit, auraInstanceID, curve)
    if not curve then return nil end
    return _GetAuraDispelTypeColor(unit, auraInstanceID, curve)
end

-- Gradient textures with baked-in vertical alpha (opaque at bottom). Used with
-- SetVertexColor for secret-safe dispel highlights (C-level accepts secret colors).
local GRADIENT_TEXTURE = "Interface\\AddOns\\Cell\\Media\\gradient"
local GRADIENT_SHARP_TEXTURE = "Interface\\AddOns\\Cell\\Media\\gradient-sharp"

-- Lazily create a single gradient overlay texture for secret dispel display.
local function _ensureGradientOverlay(dispels, sharp)
    local key = sharp and "_secretGradientSharpOverlay" or "_secretGradientOverlay"
    if dispels[key] then return dispels[key] end

    local hlParent = dispels.highlight:GetParent()
    local tex = hlParent:CreateTexture(nil, "ARTWORK", nil, 0)
    tex:SetTexture(sharp and GRADIENT_SHARP_TEXTURE or GRADIENT_TEXTURE)
    tex:SetBlendMode("BLEND")
    tex:Hide()

    dispels[key] = tex
    return tex
end

local function _hideSecretGradientOverlays(dispels)
    if dispels._secretGradientOverlay then
        dispels._secretGradientOverlay:Hide()
    end
    if dispels._secretGradientSharpOverlay then
        dispels._secretGradientSharpOverlay:Hide()
    end
end

-- Debug dispel trace (gated behind Cell.debug)
local _dispelTraceEnabled = false
if Cell.debug then
    function F.ToggleDispelTrace()
        _dispelTraceEnabled = not _dispelTraceEnabled
        print("|cff00ff00[Cell]|r Dispel trace:", _dispelTraceEnabled and "ON" or "OFF")
    end
    function F.PrintDispelDiag()
        print("|cff00ff00[Cell Dispel Diag]|r")
        print("  GetAuraDispelTypeColor:", _GetAuraDispelTypeColor and "exists" or "MISSING")
        print("  IsAuraFilteredOut:", _IsAuraFilteredOut and "exists" or "MISSING")
        print("  bracketCurves:", _dispelCurvesReady and "initialized" or "NOT READY")
        print("  highlightCurve:", _dispelHighlightCurve and "yes" or "NO")
        print("  InCombatLockdown:", InCombatLockdown() and "YES" or "NO")
    end
end

-------------------------------------------------
-- unit button func declarations
-- NOTA: sin 'local' — seg 2/3 las definen como globales, seg 1 las llama como tales
-- (sibling IIFEs: no hay upvalues entre segmentos)
-----------------------------------------------------------------

-------------------------------------------------
-- unit button init indicators
-------------------------------------------------
local enabledIndicators = {}
local indicatorNums, indicatorBooleans, indicatorColors, indicatorCustoms = {}, {}, {}, {}

local function UpdateIndicatorParentVisibility(b, indicatorName, enabled)
    if not (indicatorName == "debuffs" or
            indicatorName == "privateAuras" or
            indicatorName == "defensiveCooldowns" or
            indicatorName == "externalCooldowns" or
            indicatorName == "allCooldowns" or
            indicatorName == "dispels" or
            indicatorName == "crowdControls" or
            indicatorName == "missingBuffs") then
        return
    end

    local indicator = b.indicators[indicatorName]
    if indicator then
        if enabled then
            indicator:Show()
        else
            indicator:Hide()
        end
    end
end

local function ResetIndicators()
    wipe(enabledIndicators)
    wipe(indicatorNums)

    for _, t in next, Cell.vars.currentLayoutTable["indicators"] do
        -- update enabled
        if t["enabled"] then
            enabledIndicators[t["indicatorName"]] = true
        end
        -- update num
        if t["num"] then
            indicatorNums[t["indicatorName"]] = t["num"]
        end

        -- update statusIcon
        if t["indicatorName"] == "statusIcon" then
            I.EnableStatusIcon(t["enabled"])

        -- update aoehealing
        elseif t["indicatorName"] == "aoeHealing" then
            I.EnableAoEHealing(t["enabled"])

        -- update targetCounter
        elseif t["indicatorName"] == "targetCounter" then
            I.UpdateTargetCounterFilters(t["filters"], true)
            I.EnableTargetCounter(t["enabled"])

        -- update targetedSpells
        elseif t["indicatorName"] == "targetedSpells" then
            I.UpdateTargetedSpellsNum(t["num"])
            I.ShowAllTargetedSpells(t["showAllSpells"])
            if I.UpdateTargetedSpellsDisplayMode then
                I.UpdateTargetedSpellsDisplayMode(t["displayMode"] or "Both")
            end
            I.EnableTargetedSpells(t["enabled"])

        -- update actions
        elseif t["indicatorName"] == "actions" then
            I.EnableActions(t["enabled"])

        -- update missingBuffs
        elseif t["indicatorName"] == "missingBuffs" then
            I.EnableMissingBuffs(t["enabled"])

        -- update healthThresholds
        elseif t["indicatorName"] == "healthThresholds" then
            I.UpdateHealthThresholds()
        end

        -- update extra
        if t["indicatorName"] == "nameText" or t["indicatorName"] == "powerText" then
            indicatorColors[t["indicatorName"]] = t["color"]
        end
        if t["indicatorName"] == "powerText" then
            indicatorCustoms[t["indicatorName"]] = t["filters"]
        end
        if t["indicatorName"] == "dispels" then
            indicatorBooleans["dispels"] = t["filters"]
        end
        if t["dispellableByMe"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["dispellableByMe"]
        end
        if t["onlyShowTopGlow"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["onlyShowTopGlow"]
        end
        if t["hideInCombat"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["hideInCombat"]
        end
        if t["onlyEnableNotInCombat"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["onlyEnableNotInCombat"]
        end
        if t["onlyShowOvershields"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["onlyShowOvershields"]
        end
    end
end

local function HandleIndicators(b)
    b._indicatorsReady = nil

    if b._waitingForIndicatorCreation then
        b._waitingForIndicatorCreation = nil
        I.CreateDefensiveCooldowns(b)
        I.CreateExternalCooldowns(b)
        I.CreateAllCooldowns(b)
        I.CreateDebuffs(b)
    end

    -- NOTE: Remove old
    I.RemoveAllCustomIndicators(b)

    for _, t in next, b._config do
        local indicator = b.indicators[t["indicatorName"]] or I.CreateIndicator(b, t)
        indicator.configs = t

        -- update position
        if t["position"] then
            if t["indicatorName"] == "statusText" then
                indicator:SetPosition(t["position"][1], t["position"][2], t["position"][3])
            else
                P.ClearPoints(indicator)
                local relativeTo = t["position"][2] == "healthBar" and b.widgets.healthBar or b
                P.Point(indicator, t["position"][1], relativeTo, t["position"][3], t["position"][4], t["position"][5])
            end
        end
        -- update anchor
        if t["anchor"] then
            indicator:SetAnchor(t["anchor"])
        end
        -- update frameLevel
        if t["frameLevel"] then
            indicator:SetFrameLevel(indicator:GetParent():GetFrameLevel()+t["frameLevel"])
        end
        -- update size
        if t["size"] then
            -- NOTE: debuffs: ["size"] = {{normalSize}, {bigSize}}
            if t["indicatorName"] == "debuffs" then
                indicator:SetSize(t["size"][1], t["size"][2])
            else
                P.Size(indicator, t["size"][1], t["size"][2])
            end
        end
        -- update thickness
        if t["thickness"] then
            indicator:SetThickness(t["thickness"])
        end
        -- update border
        if t["border"] then
            indicator:SetBorder(t["border"])
        end
        -- update height
        if t["height"] then
            P.Height(indicator, t["height"])
        end
        -- update height
        if t["textWidth"] then
            indicator:UpdateTextWidth(t["textWidth"])
        end
        -- update alpha
        if t["alpha"] then
            indicator:SetAlpha(t["alpha"])
        end
        -- update numPerLine
        if t["numPerLine"] then
            indicator:SetNumPerLine(t["numPerLine"])
        end
        -- update spacing
        if t["spacing"] then
            indicator:SetSpacing(t["spacing"])
        end
        -- update orientation
        if t["orientation"] then
            indicator:SetOrientation(t["orientation"])
        end
        -- update font
        if t["font"] then
            indicator:SetFont(unpack(t["font"]))
        end
        -- update format
        if t["format"] then
            indicator:SetFormat(t["format"])
            if t["indicatorName"] == "healthText" then
                B.UpdateHealthText(b)
            elseif t["indicatorName"] == "powerText" then
                B.UpdatePowerText(b)
            end
        end
        -- update color
        if t["color"] and t["indicatorName"] ~= "nameText" and t["indicatorName"] ~="powerText" then
            indicator:SetColor(unpack(t["color"]))
        end
        -- update colors
        if t["colors"] then
            indicator:SetColors(t["colors"])
        end
        -- update texture
        if t["texture"] then
            indicator:SetTexture(t["texture"])
        end
        -- update dispel highlight
        if t["highlightType"] then
            indicator:UpdateHighlight(t["highlightType"])
        end
        -- update icon style
        if t["iconStyle"] then
            indicator:SetIconStyle(t["iconStyle"])
        end
        -- update animation
        if type(t["showAnimation"]) == "boolean" and indicator.ShowAnimation then
            indicator:ShowAnimation(t["showAnimation"])
        end
        -- update duration
        if type(t["showDuration"]) == "boolean" or type(t["showDuration"]) == "number" then
            indicator:ShowDuration(t["showDuration"])
        end
        -- update stack
        if type(t["showStack"]) == "boolean" then
            indicator:ShowStack(t["showStack"])
        end
        -- update duration
        if t["duration"] then
            indicator:SetDuration(t["duration"])
        end
        -- update stack
        if t["stack"] then
            indicator:SetStack(t["stack"])
        end
        -- update groupNumber
        if type(t["showGroupNumber"]) == "boolean" then
            indicator:ShowGroupNumber(t["showGroupNumber"])
        end
        -- update vehicleNamePosition
        if t["vehicleNamePosition"] then
            indicator:UpdateVehicleNamePosition(t["vehicleNamePosition"])
        end
        -- update timer
        if type(t["showTimer"]) == "boolean" then
            indicator:SetShowTimer(t["showTimer"])
        end
        -- update background
        if type(t["showBackground"]) == "boolean" then
            indicator:ShowBackground(t["showBackground"])
        end
        -- update role texture
        if t["roleTexture"] then
            indicator:SetRoleTexture(t["roleTexture"])
            indicator:HideDamager(t["hideDamager"])
            UnitButton_UpdateRole(b)
        end
        -- tooltip
        if type(t["showTooltip"]) == "boolean" then
            indicator:ShowTooltip(t["showTooltip"])
        end
        -- blacklist shortcut
        if type(t["enableBlacklistShortcut"]) == "boolean" then
            indicator:EnableBlacklistShortcut(t["enableBlacklistShortcut"])
        end
        -- speed
        if t["speed"] then
            indicator:SetSpeed(t["speed"])
        end
        -- privateAuraOptions
        if t["privateAuraOptions"] then
            indicator:UpdateOptions(t["privateAuraOptions"])
        end
        -- update fadeOut
        if type(t["fadeOut"]) == "boolean" then
            indicator:SetFadeOut(t["fadeOut"])
        end
        -- update glow
        if t["glowOptions"] then
            indicator:SetupGlow(t["glowOptions"])
        end
        -- update smooth
        if type(t["smooth"]) == "boolean" then
            indicator:EnableSmooth(t["smooth"])
        end
        -- max value
        if t["maxValue"] then
            indicator:SetMaxValue(t["maxValue"])
        end
        -- update hideIfEmptyOrFull
        if type(t["hideIfEmptyOrFull"]) == "boolean" then
            indicator:SetHideIfEmptyOrFull(t["hideIfEmptyOrFull"])
        end

        -- init
        -- update name visibility
        if t["indicatorName"] == "nameText" or t["indicatorName"] == "healthText" then
            if t["enabled"] then
                indicator:Show()
            else
                indicator:Hide()
            end
        elseif t["indicatorName"] == "playerRaidIcon" then
            B.UpdatePlayerRaidIcon(b, t["enabled"])
        elseif t["indicatorName"] == "targetRaidIcon" then
            B.UpdateTargetRaidIcon(b, t["enabled"])
        elseif t["indicatorName"] == "readyCheckIcon" then
            B.UpdateReadyCheckIcon(b, t["enabled"])
        else
            UpdateIndicatorParentVisibility(b, t["indicatorName"], t["enabled"])
        end

        -- update pixel perfect for built-in widgets
        -- if t["type"] == "built-in" then
        --     if indicator.UpdatePixelPerfect then
        --         indicator:UpdatePixelPerfect()
        --     end
        -- end
    end

    --! update pixel perfect for widgets
    B.UpdatePixelPerfect(b, true)

    b._indicatorsReady = true
    if I.SyncHealersAuraDisplay then
        I.SyncHealersAuraDisplay(b)
    end
    if I.SyncCustomAuraDisplays then
        I.SyncCustomAuraDisplays(b)
    end
    if I.SyncCombatAuraDisplays then
        I.SyncCombatAuraDisplays(b)
    end
end

-------------------------------------------------
-- indicator update queue
-------------------------------------------------
local updater = CreateFrame("Frame")
updater:Hide()
local queue = {}

local WAITING_FOR_INIT = "WAITING_FOR_INIT"
local WAITING_FOR_UPDATE = "WAITING_FOR_UPDATE"

local function Process(b)
    if b then
        -- print("Process", GetTime(), b:GetName(), b._status)
        if b._status == WAITING_FOR_INIT then
            -- print("processing_init", GetTime(), b:GetName())
            b._status = "processing"
            HandleIndicators(b)
            UnitButton_UpdateAuras(b)
        elseif b._status == WAITING_FOR_UPDATE then
            -- print("processing_update", GetTime(), b:GetName())
            b._indicatorsReady = true
            b._status = "processing"
            UnitButton_UpdateAuras(b)
            if I.SyncHealersAuraDisplay then
                I.SyncHealersAuraDisplay(b)
            end
            if I.SyncCustomAuraDisplays then
                I.SyncCustomAuraDisplays(b)
            end
            if I.SyncCombatAuraDisplays then
                I.SyncCombatAuraDisplays(b)
            end
        end

        CellLoadingBar.current = (CellLoadingBar.current or 0) + 1
        CellLoadingBar:SetValue(CellLoadingBar.current)
        b._status = nil
        b._config = nil
        queue[b] = nil
    else
        CellLoadingBar:Hide()
        CellLoadingBar.current = 0
        updater:Hide()
    end
end

updater:SetScript("OnUpdate", function()
    Process(next(queue))
    Process(next(queue))
end)

hooksecurefunc(updater, "Show", function()
    CellLoadingBar.total = F.Getn(queue)
    CellLoadingBar.current = 0
    CellLoadingBar:SetMinMaxValues(0, CellLoadingBar.total)
    CellLoadingBar:SetValue(0)
    CellLoadingBar:Show()
end)

local function FlushQueue()
    updater:Hide()
    wipe(queue)
end

local function AddToInitQueue(b)
    b._indicatorsReady = nil
    b._status = WAITING_FOR_INIT
    b._config = Cell.vars.currentLayoutTable["indicators"]
    queue[b] = true
end

local function AddToUpdateQueue(b)
    if queue[b] then return end
    b._indicatorsReady = nil
    b._status = WAITING_FOR_UPDATE
    queue[b] = true
end

-------------------------------------------------
-- UpdateIndicators
-------------------------------------------------
local activeLayouts = {
    solo = nil,
    party = nil,
    raid = nil,
}

local function UpdateIndicators(layout, indicatorName, setting, value, value2)
    F.Debug("|cffff7777UpdateIndicators:|r ", layout, indicatorName, setting, value, value2)

    -- FlushQueue()

    local currentLayout = Cell.vars.currentLayout
    local INDEX = Cell.vars.groupType

    if layout then
        -- Cell.Fire("UpdateIndicators", layout): indicators copy/import
        -- Cell.Fire("UpdateIndicators", xxx, ...): indicator updated
        for groupType, groupLayout in next, activeLayouts do
            if groupLayout == layout then
                activeLayouts[groupType] = nil -- update required
                F.Debug("  -> UPDATE REQUIRED:", groupType)
            end
        end

        --! indicator changed, but not current layout
        if layout ~= currentLayout then
            F.Debug("  -> NO UPDATE: not active layout")
            return
        end

    else -- Cell.Fire("UpdateIndicators")
        --! layout/groupType switched, check if update is required
        if activeLayouts[INDEX] == currentLayout then
            I.ResetCustomIndicatorTables()
            ResetIndicators()
            F.Debug("  -> NO FULL UPDATE: only reset custom indicator tables")
            F.IterateAllUnitButtons(AddToUpdateQueue, true, nil, true)
            F.IterateSharedUnitButtons(AddToInitQueue)
            updater:Show()
            return
        end
    end

    if Cell.vars.isHidden then
        F.Debug("  -> NO UPDATE: Cell is hidden")
        I.ResetCustomIndicatorTables()
        ResetIndicators()
        return
    end

    activeLayouts[INDEX] = currentLayout

    if not indicatorName then -- init
        F.Debug("  -> FULL UPDATE", INDEX, currentLayout)
        I.ResetCustomIndicatorTables()
        ResetIndicators()
        F.IterateAllUnitButtons(AddToInitQueue, true)
        updater:Show()

    else
        -- changed in IndicatorsTab
        if setting == "enabled" then
            enabledIndicators[indicatorName] = value

            if indicatorName == "combatIcon" then
                F.IterateAllUnitButtons(function(b)
                    if not value then
                        b.indicators[indicatorName]:Hide()
                    end
                end, true)
            elseif indicatorName == "aoeHealing" then
                I.EnableAoEHealing(value)
            elseif indicatorName == "targetCounter" then
                I.EnableTargetCounter(value)
            elseif indicatorName == "targetedSpells" then
                I.EnableTargetedSpells(value)
            elseif indicatorName == "actions" then
                I.EnableActions(value)
            elseif indicatorName == "roleIcon" then
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateRole(b)
                end, true)
            elseif indicatorName == "leaderIcon" then
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateLeader(b)
                end, true)
            elseif indicatorName == "playerRaidIcon" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdatePlayerRaidIcon(b, value)
                end, true)
            elseif indicatorName == "targetRaidIcon" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateTargetRaidIcon(b, value)
                end, true)
            elseif indicatorName == "readyCheckIcon" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateReadyCheckIcon(b, value)
                end, true)
            elseif indicatorName == "nameText" then
                F.IterateAllUnitButtons(function(b)
                    if value then
                        b.indicators[indicatorName]:Show()
                    else
                        b.indicators[indicatorName]:Hide()
                    end
                end, true)
            elseif indicatorName == "statusText" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateStatusText(b)
                end, true)
            elseif indicatorName == "healthText" then
                F.IterateAllUnitButtons(function(b)
                    if value then
                        b.indicators[indicatorName]:Show()
                        B.UpdateHealthText(b)
                    else
                        b.indicators[indicatorName]:Hide()
                    end
                end, true)
            elseif indicatorName == "powerText" then
                -- Ensure SetFormat has been called (SetValue is noop until then).
                local fmt
                for _, t in next, Cell.vars.currentLayoutTable["indicators"] do
                    if t["indicatorName"] == "powerText" then
                        fmt = t["format"]
                        break
                    end
                end

                -- IterateAllUnitButtons doesn't reach active party header
                -- children. Use the .units sub-table which maps unit tokens
                -- to the actual visible buttons assigned by the secure header.
                local function UpdatePowerForButton(b)
                    local indicator = b.indicators[indicatorName]
                    if indicator and fmt then
                        indicator:SetFormat(fmt)
                    end
                    b._shouldShowPowerText = ShouldShowPowerText(b)
                    CheckPowerEventRegistration(b)
                    if b._shouldShowPowerText then
                        B.UpdatePowerText(b)
                    else
                        if indicator then indicator:Hide() end
                    end
                end

                -- Standard iterator (covers solo, raid, pet, npc, spotlight)
                F.IterateAllUnitButtons(UpdatePowerForButton, true)

                -- Also reach active party/raid buttons via .units tables
                if Cell.unitButtons.party and Cell.unitButtons.party.units then
                    for _, b in pairs(Cell.unitButtons.party.units) do
                        UpdatePowerForButton(b)
                    end
                end
                if Cell.unitButtons.raid then
                    for header, buttons in pairs(Cell.unitButtons.raid) do
                        if type(buttons) == "table" and buttons.units then
                            for _, b in pairs(buttons.units) do
                                UpdatePowerForButton(b)
                            end
                        end
                    end
                end
            elseif indicatorName == "shieldBar" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateShield(b)
                end, true)
            elseif indicatorName == "healthThresholds" then
                if value then
                    I.UpdateHealthThresholds()
                end
                F.IterateAllUnitButtons(function(b)
                    B.UpdateHealth(b)
                end, true)
            elseif indicatorName == "missingBuffs" then
                I.EnableMissingBuffs(value)
                F.IterateAllUnitButtons(function(b)
                    UpdateIndicatorParentVisibility(b, indicatorName, value)
                end, true)
            else
                -- refresh
                F.IterateAllUnitButtons(function(b)
                    UpdateIndicatorParentVisibility(b, indicatorName, value)
                    if not value then
                        b.indicators[indicatorName]:Hide() -- hide indicators which is shown right now
                    end
                    UnitButton_UpdateAuras(b)
                end, true)
            end
        elseif setting == "position" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                if indicatorName == "statusText" then
                    indicator:SetPosition(value[1], value[2], value[3])
                else
                    P.ClearPoints(indicator)
                    local relativeTo = value[2] == "healthBar" and b.widgets.healthBar or b
                    P.Point(indicator, value[1], relativeTo, value[3], value[4], value[5])
                end
                -- update arrangement
                if indicator.indicatorType == "icons" then
                    indicator:SetOrientation(indicator.orientation)
                end
            end, true)
        elseif setting == "anchor" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetAnchor(value)
            end, true)
        elseif setting == "frameLevel" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetFrameLevel(indicator:GetParent():GetFrameLevel()+value)
            end, true)
        elseif setting == "size" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                if indicatorName == "debuffs" then
                    indicator:SetSize(value[1], value[2])
                    -- update debuffs' normal/big icon sizes
                    UnitButton_UpdateAuras(b)
                else
                    P.Size(indicator, value[1], value[2])
                end
            end, true)
        elseif setting == "size-border" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                P.Size(indicator, value[1], value[2])
                indicator:SetBorder(value[3])
            end, true)
        elseif setting == "thickness" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetThickness(value)
            end, true)
        elseif setting == "height" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                P.Height(indicator, value)
            end, true)
        elseif setting == "textWidth" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:UpdateTextWidth(value)
            end, true)
        elseif setting == "alpha" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetAlpha(value)
            end, true)
        elseif setting == "spacing" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetSpacing(value)
            end, true)
        elseif setting == "orientation" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetOrientation(value)
            end, true)
        elseif setting == "font" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetFont(unpack(value))
            end, true)
        elseif setting == "format" then
            if indicatorName == "healthText" then
                F.IterateAllUnitButtons(function(b)
                    local indicator = b.indicators[indicatorName]
                    indicator:SetFormat(value)
                    B.UpdateHealthText(b)
                end, true)
            elseif indicatorName == "powerText" then
                F.IterateAllUnitButtons(function(b)
                    local indicator = b.indicators[indicatorName]
                    indicator:SetFormat(value)
                    B.UpdatePowerText(b)
                end, true)
            end
        elseif setting == "color" then
            if indicatorName == "nameText" then
                indicatorColors[indicatorName] = value
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateNameTextColor(b)
                end, true)
            elseif indicatorName == "powerText" then
                indicatorColors[indicatorName] = value
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdatePowerTextColor(b)
                end, true)
            else
                F.IterateAllUnitButtons(function(b)
                    local indicator = b.indicators[indicatorName]
                    indicator:SetColor(unpack(value))
                end, true)
            end
        elseif setting == "colors" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetColors(value) -- update color on next SetCooldown
                UnitButton_UpdateAuras(b) -- call SetCooldown now
            end, true)
        elseif setting == "vehicleNamePosition" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:UpdateVehicleNamePosition(value)
            end, true)
        elseif setting == "statusColors" then
            F.IterateAllUnitButtons(function(b)
                UnitButton_UpdateStatusText(b)
            end, true)
        elseif setting == "num" then
            indicatorNums[indicatorName] = value
            if indicatorName == "targetedSpells" then
                I.UpdateTargetedSpellsNum(value)
            else
                -- refresh
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateAuras(b)
                end, true)
            end
        elseif setting == "numPerLine" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetNumPerLine(value)
            end, true)
        elseif setting == "roleTexture" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetRoleTexture(value)
                UnitButton_UpdateRole(b)
            end, true)
        elseif setting == "texture" then
            F.IterateAllUnitButtons(function(b)
                local indicator = b.indicators[indicatorName]
                indicator:SetTexture(value)
            end, true)
        elseif setting == "duration" or setting == "dispelFilters" then
            F.IterateAllUnitButtons(function(b)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "stack" then
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:SetStack(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "highlightType" then
            if value == "gradient-sharp" then
                value = "edge-bottom"
            elseif value ~= "edge-top" and value ~= "edge-bottom" then
                value = "entire"
            end
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:UpdateHighlight(value)
                UnitButton_UpdateAuras(b)
            end, true)
            if I.RefreshAllCombatAuraDisplays then
                I.RefreshAllCombatAuraDisplays()
            end
        elseif setting == "thresholds" then
            I.UpdateHealthThresholds()
            F.IterateAllUnitButtons(function(b)
                B.UpdateHealth(b)
            end, true)
        elseif setting == "showDuration" then
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:ShowDuration(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "privateAuraOptions" then
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:UpdateOptions(value)
            end, true)
        elseif setting == "powerTextFilters" then
            F.IterateAllUnitButtons(function(b)
                b._shouldShowPowerText = ShouldShowPowerText(b)
                CheckPowerEventRegistration(b)
                if b._shouldShowPowerText then
                    B.UpdatePowerText(b)
                else
                    b.indicators[indicatorName]:Hide()
                end
            end, true)
        elseif setting == "targetCounterFilters" then
            I.UpdateTargetCounterFilters()
        elseif setting == "maxValue" then
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:SetMaxValue(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "glowOptions" then
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:SetupGlow(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "iconStyle" then
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:SetIconStyle(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "checkbutton" then
            if value == "showGroupNumber" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:ShowGroupNumber(value2)
                end, true)
            elseif value == "showTimer" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:SetShowTimer(value2)
                    UnitButton_UpdateStatusText(b)
                end, true)
            elseif value == "showBackground" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:ShowBackground(value2)
                end, true)
            elseif value == "hideIfEmptyOrFull" then
                if indicatorName == "powerText" then
                    F.IterateAllUnitButtons(function(b)
                        b.indicators[indicatorName]:SetHideIfEmptyOrFull(value2)
                        B.UpdatePowerText(b)
                    end, true)
                end
            elseif value == "hideInCombat" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateLeader(b)
                end, true)
            elseif value == "onlyEnableNotInCombat" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:Hide()
                end, true)
            elseif value == "onlyShowOvershields" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateShieldAbsorbs(b)
                end, true)
            elseif value == "showStack" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:ShowStack(value2)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "showAnimation" then
                F.IterateAllUnitButtons(function(b)
                    local ind = b.indicators[indicatorName]
                    if ind and ind.ShowAnimation then
                        ind:ShowAnimation(value2)
                    end
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "trackByName" then
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "dispellableByMe" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "showTooltip" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:ShowTooltip(value2)
                end, true)
            elseif value == "enableBlacklistShortcut" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:EnableBlacklistShortcut(value2)
                end, true)
            elseif value == "hideDamager" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:HideDamager(value2)
                    UnitButton_UpdateRole(b)
                end, true)
            elseif value == "fadeOut" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:SetFadeOut(value2)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "smooth" then
                F.IterateAllUnitButtons(function(b)
                    b.indicators[indicatorName]:EnableSmooth(value2)
                end, true)
            elseif value == "showAllSpells" then
                I.ShowAllTargetedSpells(value2)
            else
                indicatorBooleans[indicatorName] = value2
            end
        elseif setting == "create" then
            I.UpdateIndicatorTable(value)
            F.IterateAllUnitButtons(function(b)
                local indicator = I.CreateIndicator(b, value)
                indicator.configs = value

                -- update position
                if value["position"] then
                    P.ClearPoints(indicator)
                    local relativeTo = value["position"][2] == "healthBar" and b.widgets.healthBar or b
                    P.Point(indicator, value["position"][1], relativeTo, value["position"][3], value["position"][4], value["position"][5])
                end
                -- update anchor
                if value["anchor"] then
                    indicator:SetAnchor(value["anchor"])
                end
                -- update size
                if value["size"] then
                    P.Size(indicator, value["size"][1], value["size"][2])
                end
                -- update thickness
                if value["thickness"] then
                    indicator:SetThickness(value["thickness"])
                end
                -- update frameLevel
                if value["frameLevel"] then
                    indicator:SetFrameLevel(indicator:GetParent():GetFrameLevel()+value["frameLevel"])
                end
                -- update numPerLine
                if value["numPerLine"] then
                    indicator:SetNumPerLine(value["numPerLine"])
                end
                -- update spacing
                if value["spacing"] then
                    indicator:SetSpacing(value["spacing"])
                end
                -- update orientation
                if value["orientation"] then
                    indicator:SetOrientation(value["orientation"])
                end
                -- update font
                if value["font"] then
                    indicator:SetFont(unpack(value["font"]))
                end
                -- update color
                if value["color"] then
                    indicator:SetColor(unpack(value["color"]))
                end
                -- update colors
                if value["colors"] then
                    indicator:SetColors(value["colors"])
                end
                -- update texture
                if value["texture"] then
                    indicator:SetTexture(value["texture"])
                end
                -- update showAnimation
                if type(value["showAnimation"]) == "boolean" and indicator.ShowAnimation then
                    indicator:ShowAnimation(value["showAnimation"])
                end
                -- update showDuration
                if type(value["showDuration"]) ~= "nil" then
                    indicator:ShowDuration(value["showDuration"])
                end
                -- update showStack
                if type(value["showStack"]) ~= "nil" then
                    indicator:ShowStack(value["showStack"])
                end
                -- update duration
                if value["duration"] then
                    indicator:SetDuration(value["duration"])
                end
                -- update stack
                if value["stack"] then
                    indicator:SetStack(value["stack"])
                end
                -- update fadeOut
                if type(value["fadeOut"]) == "boolean" then
                    indicator:SetFadeOut(value["fadeOut"])
                end
                -- update glow
                if value["glowOptions"] then
                    indicator:SetupGlow(value["glowOptions"])
                end
                -- FirstRun: Healers
                if value["auras"] and #value["auras"] ~= 0 then
                    UnitButton_UpdateAuras(b)
                end
            end, true)
        elseif setting == "remove" then
            F.IterateAllUnitButtons(function(b)
                I.RemoveIndicator(b, indicatorName, value)
            end, true)
        elseif setting == "auras" then
            -- indicator auras changed, hide them all, then recheck whether to show
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:Hide()
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "dispelBlacklist" or setting == "defensives" or setting == "externals" or setting == "crowdControls" or setting == "bigDebuffs" or setting == "debuffTypeColor" or setting == "castBy" then
            F.IterateAllUnitButtons(function(b)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "speed" then
            -- only Actions indicator has this option for now
            F.IterateAllUnitButtons(function(b)
                b.indicators[indicatorName]:SetSpeed(value)
            end, true)
        end
    end
end
Cell.RegisterCallback("UpdateIndicators", "UnitButton_UpdateIndicators", UpdateIndicators)

-------------------------------------------------
-- ForEachAura
-------------------------------------------------
local function ForEachAuraHelper(button, func, ...)
    local n = select('#', ...)
    for i = 1, n do
        local slot = select(i, ...)
        if slot then
            local auraInfo = GetAuraDataBySlot(button.states.displayedUnit, slot)
            if auraInfo then
                func(button, auraInfo)
            end
        end
    end
end

local function ForEachAura(button, filter, func)
    if F.IsLiveAuraScanBlocked and F.IsLiveAuraScanBlocked() then
        return
    end
    if F.IsAuraRestricted and F.IsAuraRestricted() then
        return
    end

    local unit = button.states.displayedUnit
    if not unit then return end

    if GetAuraSlots then
        local ok, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, s30, s31, s32, s33, s34, s35, s36, s37, s38, s39, s40 =
            pcall(GetAuraSlots, unit, filter)
        if not ok then
            return
        end
        ForEachAuraHelper(button, func, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, s30, s31, s32, s33, s34, s35, s36, s37, s38, s39, s40)
    elseif AuraUtil and AuraUtil.ForEachAura then
        pcall(AuraUtil.ForEachAura, unit, filter, nil, function(auraData)
            if auraData and auraData.auraInstanceID then
                local aura = GetAuraDataByAuraInstanceID(unit, auraData.auraInstanceID)
                if not aura then
                    aura = AnnotateAura(auraData)
                end
                if aura then
                    func(button, aura)
                end
            end
        end, true)
    end
end

-------------------------------------------------
-- ForEachAuraCache
-------------------------------------------------
local function ForEachAuraCache(button, filter, func)
    if filter == "HARMFUL" then
        for auraInstanceID, aura in next, button._debuffs_cache do
            if F.IsValueNonSecret(auraInstanceID) then
                func(button, aura)
            end
        end
    elseif filter == "HELPFUL" then
        for auraInstanceID, aura in next, button._buffs_cache do
            if F.IsValueNonSecret(auraInstanceID) then
                func(button, aura)
            end
        end
    end
end

-------------------------------------------------
-- UpdateAuraRefreshState
-------------------------------------------------
local function UpdateAuraRefreshState(auraInfo)
    if Cell.vars.iconAnimation == "duration" then
        local timeIncreased, countIncreased
        if Cell.isMidnight and (
            not F.IsValueNonSecret(auraInfo.expirationTime)
            or not F.IsValueNonSecret(auraInfo.oldExpirationTime)
            or not F.IsValueNonSecret(auraInfo.applications)
            or not F.IsValueNonSecret(auraInfo.oldApplications)
        ) then
            -- One or more fields are secret: can't do arithmetic/comparison (Midnight 12.0.0+)
            timeIncreased = false
            countIncreased = false
        else
            timeIncreased = auraInfo.oldExpirationTime and ((auraInfo.expirationTime or 0) - auraInfo.oldExpirationTime >= 0.5) or false
            countIncreased = auraInfo.oldApplications and (auraInfo.applications > auraInfo.oldApplications) or false
        end
        auraInfo.refreshing = timeIncreased or countIncreased
    elseif Cell.vars.iconAnimation == "stack" then
        if Cell.isMidnight and (
            not F.IsValueNonSecret(auraInfo.applications)
            or not F.IsValueNonSecret(auraInfo.oldApplications)
        ) then
            -- Secret applications: can't compare (Midnight 12.0.0+)
            auraInfo.refreshing = false
        else
            auraInfo.refreshing = auraInfo.oldApplications and (auraInfo.applications > auraInfo.oldApplications) or false
        end
    else
        auraInfo.refreshing = false
    end

    auraInfo.oldExpirationTime = nil
    auraInfo.oldApplications = nil
end

-------------------------------------------------
-- debuffs
-------------------------------------------------
-- cleuAuras
-- local cleuUnits = {}

-- NOTE: Weakened Soul has been removed in Dragonflight
-- won't show if not a priest, otherwise show mine only
-- local function FilterWeakenedSoul(spellId, caster)
--     if spellId ~= 6788 then return true end

--     if not Cell.vars.playerClassID == 5 then return end
--     return caster == "player"
-- end

local function ResetDebuffVars(self)
    self._debuffs.resurrectionFound = false
    self._debuffs.crowdControlsFound = 0
    self._dispelAuraID = nil
    self._dispelUnit = nil

    self.states.BGOrb = nil -- TODO: move to _debuffs
end

local function CanPlayerDispelAura(unit, auraInfo, debuffType)
    if Cell.isMidnight and unit and auraInfo and auraInfo.auraInstanceID and _IsAuraFilteredOut then
        local playerDispellable = not _IsAuraFilteredOut(unit, auraInfo.auraInstanceID, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if playerDispellable then return true end

        -- Fallback for Blizzard API bugs:
        -- Shaman Poison Cleansing Totem is not recognized by Blizzard's filter
        if Cell.vars.playerClassID == 7 and debuffType == "Poison" then
            return I.CanDispel("Poison")
        end

        return false
    end

    if auraInfo and auraInfo._hasSecrets then
        return not (auraInfo.dispelName == nil)
    end

    return I.CanDispel(debuffType)
end


local function HandleDebuff(self, auraInfo)
    if not auraInfo or not F.IsValueNonSecret(auraInfo.auraInstanceID) then
        return
    end

    local auraInstanceID = auraInfo.auraInstanceID
    local unit = self.states.displayedUnit

    local name = auraInfo.name
    local icon = auraInfo.icon
    local count = auraInfo.applications
    local spellId = auraInfo.spellId

    -- Blacklist check: skip auras that the user has blacklisted
    -- NOTE: secrets can't be compared, skip blacklist for _hasSecrets auras
    if spellId and not auraInfo._hasSecrets and F.IsAuraBlacklisted and F.IsAuraBlacklisted(spellId, "HARMFUL") then return end

    -- Dispel detection
    local isDispellable = not (auraInfo.dispelName == nil)
    local debuffType
    if auraInfo._hasSecrets then
        debuffType = ""
    else
        debuffType = auraInfo.dispelName or ""
    end

    debuffType = I.CheckDebuffType(debuffType, spellId)

    -- Duration handling for secret auras
    local start, duration
    if auraInfo._hasSecrets then
        start = 0
        duration = 0
    else
        local expirationTime = auraInfo.expirationTime or 0
        duration = auraInfo.duration
        start = expirationTime - duration
    end

    auraInfo.refreshing = false

    if Cell.isMidnight or (duration ~= nil) then
        UpdateAuraRefreshState(auraInfo)
        self._debuffs_cache[auraInstanceID] = auraInfo

        -- Classification
        local isBig = auraInfo._hasSecrets and _IsAuraFilteredOut and not _IsAuraFilteredOut(unit, auraInstanceID, "HARMFUL|IMPORTANT") or false

        local isBlacklisted = false
        local isDispelBlacklisted = false
        if not auraInfo._hasSecrets and spellId then
            if not isBig then
                isBig = Cell.vars.bigDebuffs[spellId] or false
            end
            -- On Retail/Midnight, the new auraBlacklist (line 1518) replaces the old debuffBlacklist.
            -- The old array (CellDB["debuffBlacklist"]) still exists for Classic/Cata backward compat,
            -- but on Retail it would double-block spells the user already unchecked in the AuraBlacklist UI.
            if not Cell.isRetail then
                isBlacklisted = Cell.vars.debuffBlacklist[spellId] or false
            end
            isDispelBlacklisted = Cell.vars.dispelBlacklist[spellId] or false
        end

        local canPlayerDispelAura
        local function GetCanPlayerDispelAura()
            if canPlayerDispelAura == nil then
                canPlayerDispelAura = CanPlayerDispelAura(unit, auraInfo, debuffType) and true or false
            end
            return canPlayerDispelAura
        end

        -- Always-on AuraContainer owns debuff icons when active — skip legacy buckets.
        if enabledIndicators["debuffs"] and not isBlacklisted
            and not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("debuffs")) then
            local canShowDebuff = not indicatorBooleans["debuffs"]
            if not canShowDebuff then
                canShowDebuff = GetCanPlayerDispelAura()
            end
            if canShowDebuff then
                if isBig then
                    self._debuffs_big[auraInstanceID] = true
                else
                    self._debuffs_normal[auraInstanceID] = true
                end
            end
        end

        -- user created indicators
        I.UpdateCustomIndicators(self, auraInfo, "debuff")

        -- raidDebuffs: Cell's curated tables only. No _IsAuraFilteredOut fallback
        -- because Blizzard's HARMFUL|RAID filter is broader than Cell's curated
        -- list and can route personal debuffs (e.g. Luz del mártir) into the
        -- raidDebuffs indicator. Secret auras that aren't in Cell's tables
        -- simply don't appear here — the fingerprint handles defensive/external
        -- classification, and encounter mechanics that apply secret debuffs are
        -- already in Cell's tables.
        local order = I.GetDebuffOrder(name, spellId, count)

        if enabledIndicators["raidDebuffs"] and order then
            auraInfo.raidDebuffOrder = order
            tinsert(self._debuffs_raid, auraInstanceID)

            if not indicatorBooleans["raidDebuffs"] then
                local glowType, glowOptions = I.GetDebuffGlow(name, spellId, count)
                if glowType and glowType ~= "None" then
                    auraInfo.raidDebuffGlowType = glowType
                    auraInfo.raidDebuffGlowOptions = glowOptions
                    self._debuffs_glow_current[glowType] = glowOptions
                end
            end
        end

        if enabledIndicators["dispels"] then
            local canShowDispel = not indicatorBooleans["dispels"]["dispellableByMe"]
            if not canShowDispel then
                canShowDispel = GetCanPlayerDispelAura()
            end

            if canShowDispel and debuffType and debuffType ~= "" then
                if indicatorBooleans["dispels"][debuffType] then
                    if isDispelBlacklisted then
                        self._debuffs_dispel[debuffType] = false
                    else
                        self._debuffs_dispel[debuffType] = true
                    end
                end
            elseif canShowDispel and auraInfo._hasSecrets and isDispellable and unit then
                self._dispelAuraID = auraInstanceID
                self._dispelUnit = unit
            end
        end

        -- crowdControls (container owns paint when always-on; still strip from legacy debuff buckets)
        if enabledIndicators["crowdControls"] and I.IsCrowdControls(name, spellId) then
            if not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("crowdControls"))
                and self._debuffs.crowdControlsFound < indicatorNums["crowdControls"] then
                self._debuffs.crowdControlsFound = self._debuffs.crowdControlsFound + 1
                if Cell.isMidnight then
                    self.indicators.crowdControls[self._debuffs.crowdControlsFound]:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                else
                    self.indicators.crowdControls[self._debuffs.crowdControlsFound]:SetCooldown(start, duration, debuffType, icon, count, auraInfo.refreshing)
                end
            end
            self._debuffs_big[auraInstanceID] = nil
            self._debuffs_normal[auraInstanceID] = nil
        end

        -- specific debuffs
        if not auraInfo._hasSecrets and spellId then
            if spellId == 255234 or spellId == 225080 then
                self._debuffs.resurrectionFound = true
                self.states.hasRezDebuff = true
            end

            if spellId == 121164 then
                self.states.BGOrb = "blue"
            elseif spellId == 121175 then
                self.states.BGOrb = "purple"
            elseif spellId == 121176 then
                self.states.BGOrb = "green"
            elseif spellId == 121177 then
                self.states.BGOrb = "orange"
            end
        end
    end
end

local RAID_DEBUFFS_GLOW_TYPES = {"Normal", "Pixel", "Shine", "Proc"}

local function UnitButton_UpdateDebuffs(self, isFullUpdate)
    local unit = self.states.displayedUnit

    ResetDebuffVars(self)
    I.ResetCustomIndicators(self, "debuff")

    if isFullUpdate then
        self._debuffs_cache = {}
        ForEachAura(self, "HARMFUL", HandleDebuff)
    else
        ForEachAuraCache(self, "HARMFUL", HandleDebuff)
    end

    if not self._debuffs.resurrectionFound then
        self.states.hasRezDebuff = nil
    end

    local startIndex = 1

    -- update raid debuffs
    -- if self._debuffs.raidDebuffsFound or cleuUnits[unit] then
    if self._debuffs_raid[1] then
        self.indicators.raidDebuffs:Show()

        -- cleuAuras
        -- local offset = 0
        -- if cleuUnits[unit] then
        --     offset = 1
        --     startIndex = startIndex + 1
        -- end

        -- sort indices
        sort(self._debuffs_raid, function(a, b)
            local ca, cb = self._debuffs_cache[a], self._debuffs_cache[b]
            if not ca or not cb then return ca ~= nil end
            return ca["raidDebuffOrder"] < cb["raidDebuffOrder"]
        end)

        -- show
        local topAuraInstanceID
        for i = 1, indicatorNums["raidDebuffs"] do
            local auraInstanceID = self._debuffs_raid[i]
            if auraInstanceID then
                local auraInfo = self._debuffs_cache[auraInstanceID]
                if auraInfo then
                    if Cell.isMidnight then
                        -- Pass-through: C-level DurationObject APIs handle secret values
                        self.indicators.raidDebuffs[i]:SetCooldownFromAura(
                            unit, auraInstanceID, auraInfo.icon, auraInfo.refreshing)
                        -- Dispel color: border = dispel type color (base), swipe = black
                        -- Same pattern as regular debuffs in showDebuff
                        local frame = self.indicators.raidDebuffs[i]
                        if frame.cooldown and frame.cooldown.SetSwipeColor then
                            frame.cooldown:SetSwipeColor(0, 0, 0)
                        end
                        if auraInfo._hasSecrets and (auraInfo.dispelName == nil) then
                            -- Non-dispellable secret: red
                            if frame.border then frame.border:SetColorTexture(1, 0, 0); frame.border:Show() end
                        elseif auraInfo._hasSecrets and _dispelCurvesReady then
                            local hlColor = _getCurveColor(unit, auraInstanceID, _dispelHighlightCurve)
                            if hlColor then
                                local r, g, b = hlColor:GetRGBA()
                                if frame.border then frame.border:SetColorTexture(r, g, b); frame.border:Show() end
                            end
                        elseif not auraInfo._hasSecrets and auraInfo.dispelName then
                            local r, g, b = I.GetDebuffTypeColor(auraInfo.dispelName)
                            if frame.border then frame.border:SetColorTexture(r, g, b); frame.border:Show() end
                        else
                            if frame.border then frame.border:SetColorTexture(1, 0, 0); frame.border:Show() end
                        end
                    else
                        -- Pre-Midnight: standard Lua arithmetic (identical to upstream)
                        local rdStart = (auraInfo.expirationTime or 0) - auraInfo.duration
                        self.indicators.raidDebuffs[i]:SetCooldown(
                            rdStart, auraInfo.duration,
                            auraInfo.dispelName or "",
                            auraInfo.icon, auraInfo.applications,
                            auraInfo.refreshing,
                            I.IsDebuffUseElapsedTime(auraInfo.name, auraInfo.spellId))
                    end
                    self.indicators.raidDebuffs[i].auraInstanceID = auraInstanceID -- NOTE: for tooltip
                    startIndex = startIndex + 1
                    self._debuffs_big[auraInstanceID] = nil
                    self._debuffs_normal[auraInstanceID] = nil

                    if i == 1 then topAuraInstanceID = auraInstanceID end
                end
            end
        end

        self.indicators.raidDebuffs:UpdateSize(startIndex - 1)
        for i = startIndex, 3 do
            self.indicators.raidDebuffs[i].auraInstanceID = nil
        end

        -- update glow
        if not indicatorBooleans["raidDebuffs"] then
            -- to make sure top glow has highest priority
            local topAura = topAuraInstanceID and self._debuffs_cache[topAuraInstanceID]
            local topGlowType = topAura and topAura["raidDebuffGlowType"]
            local topGlowOptions = topAura and topAura["raidDebuffGlowOptions"]
            if topGlowType and topGlowType ~= "None" then
                self._debuffs_glow_current[topGlowType] = topGlowOptions
            end
            for t, o in next, self._debuffs_glow_current do
                self.indicators.raidDebuffs:ShowGlow(t, o, true)
            end
            for _, t in next, RAID_DEBUFFS_GLOW_TYPES do
                if not self._debuffs_glow_current[t] then
                    self.indicators.raidDebuffs:HideGlow(t)
                end
            end
            wipe(self._debuffs_glow_current)
        else
            local topAura = topAuraInstanceID and self._debuffs_cache[topAuraInstanceID]
            if topAura then
                self.indicators.raidDebuffs:ShowGlow(
                    I.GetDebuffGlow(
                        topAura["name"],
                        topAura["spellId"],
                        topAura["applications"]
                    )
                )
            end
        end
    else
        self.indicators.raidDebuffs:Hide()
    end

    -- update debuffs
    startIndex = 1
    if enabledIndicators["debuffs"] then
        -- helper to display a debuff indicator
        local function showDebuff(auraInstanceID, auraInfo, isBig)
            if Cell.isMidnight then
                local frame = self.indicators.debuffs[startIndex]
                frame:SetCooldownFromAura(
                    unit, auraInstanceID, auraInfo.icon, auraInfo.refreshing)
                -- Border = dispel type color (base), swipe = black (fills over as time expires).
                -- SetReverse(true) in SetCooldownFromAura makes the swipe fill IN.
                if frame.cooldown and frame.cooldown.SetSwipeColor then
                    frame.cooldown:SetSwipeColor(0, 0, 0)
                end
                local br, bg, bb = 1, 0, 0
                if auraInfo._hasSecrets and (auraInfo.dispelName == nil) then
                    -- Non-dispellable secret: red (check before curves since curve returns transparent for Physical)
                    br, bg, bb = 1, 0, 0
                elseif auraInfo._hasSecrets and _dispelCurvesReady then
                    local hlColor = _getCurveColor(unit, auraInstanceID, _dispelHighlightCurve)
                    if hlColor then
                        br, bg, bb = hlColor:GetRGBA()
                    end
                elseif not auraInfo._hasSecrets and auraInfo.dispelName then
                    br, bg, bb = I.GetDebuffTypeColor(auraInfo.dispelName)
                else
                    br, bg, bb = 1, 0, 0
                end
                if frame.border then
                    frame.border:SetColorTexture(br, bg, bb)
                    frame.border:Show()
                end
                -- Big debuff sizing (matches pre-Midnight wrapper in Built-in.lua)
                local debuffs = self.indicators.debuffs
                if isBig then
                    P.Size(frame, debuffs.bigSize[1], debuffs.bigSize[2])
                else
                    P.Size(frame, debuffs.normalSize[1], debuffs.normalSize[2])
                end
            else
                local dStart = (auraInfo.expirationTime or 0) - auraInfo.duration
                self.indicators.debuffs[startIndex]:SetCooldown(
                    dStart, auraInfo.duration,
                    auraInfo.dispelName or "", auraInfo.icon,
                    auraInfo.applications, auraInfo.refreshing, isBig)
            end
            self.indicators.debuffs[startIndex].auraInstanceID = auraInstanceID
            self.indicators.debuffs[startIndex].spellId = auraInfo.spellId
            startIndex = startIndex + 1
        end

        -- bigDebuffs first
        for auraInstanceID in next, self._debuffs_big do
            local auraInfo = self._debuffs_cache[auraInstanceID]
            if auraInfo and startIndex <= indicatorNums["debuffs"] then
                showDebuff(auraInstanceID, auraInfo, true)
            elseif startIndex > indicatorNums["debuffs"] then
                break
            end
        end
        -- then normal debuffs
        for auraInstanceID in next, self._debuffs_normal do
            local auraInfo = self._debuffs_cache[auraInstanceID]
            if auraInfo and startIndex <= indicatorNums["debuffs"] then
                showDebuff(auraInstanceID, auraInfo)
            elseif startIndex > indicatorNums["debuffs"] then
                break
            end
        end
    end

    if not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("debuffs")) then
        self.indicators.debuffs:UpdateSize(startIndex - 1)
        for i = startIndex, 10 do
            self.indicators.debuffs[i].auraInstanceID = nil
            self.indicators.debuffs[i].spellId = nil
        end
    end

    -- update dispels (icons + health overlay owned by always-on AuraContainer when active)
    if (F.UnitInGroup(unit) or UnitIsFriend("player", unit))
        and not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("dispels")) then
        local dispels = self.indicators.dispels
        -- Restore icon positions from previous secret dispel mode
        if dispels._secretIconsStacked then
            dispels:SetOrientation(dispels._orientation)
            dispels._secretIconsStacked = nil
            for i = 1, 5 do
                dispels[i]:SetAlpha(1)
                dispels[i]:SetVertexColor(1, 1, 1, 1)
            end
        end
        if dispels._secretGradientShown then
            dispels._secretGradientShown = nil
            _hideSecretGradientOverlays(dispels)
        end
        dispels:SetDispels(self._debuffs_dispel)

        -- Midnight secret fallback (legacy path only)
        if self._dispelAuraID and _dispelCurvesReady
            and not dispels.highlight:IsShown()
            and not dispels._secretGradientShown
            and enabledIndicators["dispels"] then

            local sUnit = self._dispelUnit
            local sAuraID = self._dispelAuraID
            local hlColor = _getCurveColor(sUnit, sAuraID, _dispelHighlightCurve)
            if hlColor then
                local cr, cg, cb = hlColor:GetRGBA()
                local ht = dispels.highlightType
                if ht == "edge-top" or ht == "edge-bottom" or ht == "gradient-sharp" then
                    local overlay = _ensureGradientOverlay(dispels, true)
                    if ht == "edge-bottom" or ht == "gradient-sharp" then
                        overlay:SetTexture("Interface\\AddOns\\Cell\\Media\\Edge-Fade-Bottom")
                    else
                        overlay:SetTexture("Interface\\AddOns\\Cell\\Media\\Edge-Fade-Top")
                    end
                    overlay:SetTexCoord(0, 1, 0, 1)
                    overlay:ClearAllPoints()
                    overlay:SetAllPoints(dispels.highlight)
                    overlay:SetVertexColor(cr, cg, cb, 1)
                    overlay:Show()
                    dispels._secretGradientShown = true
                elseif ht ~= "none" then
                    dispels.highlight:SetTexture(Cell.vars.whiteTexture)
                    dispels.highlight:SetTexCoord(0, 1, 0, 1)
                    dispels.highlight:SetVertexColor(cr, cg, cb, 0.5)
                    dispels.highlight:Show()
                end

                if dispels.showIcons then
                    for i, t in ipairs(_dispelTypes) do
                        local dIcon = dispels[i]
                        if dIcon then
                            if dIcon.SetDispel then dIcon:SetDispel(t.name) end
                            local bColor = _getCurveColor(sUnit, sAuraID, _bracketCurves[t.name])
                            if bColor then
                                local _, _, _, ba = bColor:GetRGBA()
                                dIcon:SetAlpha(ba)
                            end
                            if i > 1 then
                                dIcon:ClearAllPoints()
                                dIcon:SetAllPoints(dispels[1])
                            end
                            dIcon:Show()
                        end
                    end
                    dispels:UpdateSize(1)
                    dispels._secretIconsStacked = true
                end
            end
        end
    end

    -- update crowdControls
    if not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("crowdControls")) then
        self.indicators.crowdControls:UpdateSize(self._debuffs.crowdControlsFound)
    end

    -- user created indicators
    I.ShowCustomIndicators(self, "debuff")

    if self.indicators.privateAuras and self.indicators.privateAuras.UpdateDispelOverlayVisibility then
        self.indicators.privateAuras:UpdateDispelOverlayVisibility()
    end

    wipe(self._debuffs_normal)
    wipe(self._debuffs_big)
    wipe(self._debuffs_dispel)
    wipe(self._debuffs_raid)
end

Cell._debuffs = UnitButton_UpdateDebuffs  -- export para seg 2
Cell._enabledIndicators = enabledIndicators  -- export para seg 2/3
Cell._indicatorNums = indicatorNums  -- export para seg 2/3
Cell._indicatorBooleans = indicatorBooleans  -- export para seg 2
Cell._indicatorColors = indicatorColors  -- export para seg 2
Cell._indicatorCustoms = indicatorCustoms  -- export para seg 2
Cell._isAuraFilteredOut = _IsAuraFilteredOut  -- export para seg 2 y HandleBuff
Cell._fadeOutHealthCurve = fadeOutHealthCurve
Cell._fadeOutHealthCurve_threshold = fadeOutHealthCurve_threshold
Cell._fadeOutHealthCurve_alpha = fadeOutHealthCurve_alpha
Cell._rebuildFadeOutHealthCurve = RebuildFadeOutHealthCurve
Cell._forEachAura = ForEachAura
Cell._forEachAuraCache = ForEachAuraCache
Cell._getAuraDataByAuraInstanceID = GetAuraDataByAuraInstanceID
Cell._annotateAura = AnnotateAura
Cell._doesAuraMatchExpectedBuff = DoesAuraMatchExpectedBuff  -- export para HandleBuff via seg 3
Cell._updateAuraRefreshState = UpdateAuraRefreshState  -- export para HandleBuff via seg 3

end)(Cell)  -- end seg 1 (IIFE externo: helpers + UnitButton_UpdateDebuffs)

-- =============================================================================
-- Seg 2: buffs, events, health, power
-- =============================================================================
;(function(Cell)  -- IIFE seg 2: 0 upvalues, ~197 locales

local Cell_ = Cell

-- Imports desde Cell (evitan que sean upvalues desde seg 1)
local F = Cell_.funcs
local I = Cell_.iFuncs
local B = Cell_.bFuncs
local A = Cell_.animations
local P = Cell_.pixelPerfectFuncs

-- Import debuffs desde seg 1
local UnitButton_UpdateDebuffs = Cell_._debuffs
local enabledIndicators = Cell_._enabledIndicators
local indicatorNums = Cell_._indicatorNums
local indicatorBooleans = Cell_._indicatorBooleans
local indicatorColors = Cell_._indicatorColors
local indicatorCustoms = Cell_._indicatorCustoms

-- Import vars de HandleBuff desde Cell._hb (definidos en seg 1)
local _IsAuraFilteredOut = Cell_._isAuraFilteredOut
local GetAuraDataByAuraInstanceID = Cell_._getAuraDataByAuraInstanceID
local AnnotateAura = Cell_._annotateAura
local ForEachAura = Cell_._forEachAura
local ForEachAuraCache = Cell_._forEachAuraCache
local wipe = table.wipe
local fadeOutHealthCurve = Cell_._fadeOutHealthCurve
local fadeOutHealthCurve_threshold = Cell_._fadeOutHealthCurve_threshold
local fadeOutHealthCurve_alpha = Cell_._fadeOutHealthCurve_alpha
local RebuildFadeOutHealthCurve = Cell_._rebuildFadeOutHealthCurve
local secretHelpfulCastFallbacks = Cell_._hb.secretHelpfulCastFallbacks
local recentSecretHelpfulCasts = Cell_._hb.recentSecretHelpfulCasts
local SECRET_HELPFUL_CAST_FALLBACK_WINDOW = Cell_._hb.SECRET_HELPFUL_CAST_FALLBACK_WINDOW

local SBI_ExponentialEaseOut = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SBI_Immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local LGI = LibStub:GetLibrary("LibGroupInfo")

-- Forward declarations para funciones definidas más abajo en seg 2
local UnitButton_UpdateHealthColor, UnitButton_UpdateHealthTextColor
local UnitButton_UpdatePowerMax, UnitButton_UpdatePower, UnitButton_UpdatePowerType, UnitButton_UpdatePowerText
local ShouldShowPowerBar

-------------------------------------------------
-- buffs
-------------------------------------------------
local function ResetBuffVars(self)
    self._buffs.defensiveFound = 0
    self._buffs.externalFound = 0
    self._buffs.allFound = 0
    self._buffs.tankActiveMitigationFound = false
    self._buffs.drinkingFound = false

    self.states.BGFlag = nil -- TODO: move to _buffs
end

local function RememberSecretHelpfulCast(self, spellId)
    if not F.IsValueNonSecret(spellId) then return end

    local kind = secretHelpfulCastFallbacks[spellId]
    if not kind then
        -- Si no está en secretHelpfulCastFallbacks, pruebo con las tablas
        -- de externals/defensives de Cell por si es un spell conocido.
        if I.IsExternalCooldown(nil, spellId) then
            kind = "external"
        elseif I.IsDefensiveCooldown(nil, spellId) then
            kind = "defensive"
        end
    end
    if not kind then return end

    self._recentSecretHelpfulCastKind = kind
    self._recentSecretHelpfulCastAt = GetTime()
    self._recentSecretHelpfulCastSpellId = spellId

    -- Clean expired entries before adding the new one, keeping the list bounded
    local expireCutoff = self._recentSecretHelpfulCastAt - SECRET_HELPFUL_CAST_FALLBACK_WINDOW
    for i = #recentSecretHelpfulCasts, 1, -1 do
        if recentSecretHelpfulCasts[i].castAt < expireCutoff then
            tremove(recentSecretHelpfulCasts, i)
        end
    end

    recentSecretHelpfulCasts[#recentSecretHelpfulCasts + 1] = {
        kind = kind,
        spellId = spellId,
        castAt = self._recentSecretHelpfulCastAt,
    }
end

local function GetRecentSecretHelpfulCastKind(self)
    local castAt = self._recentSecretHelpfulCastAt
    if not castAt or GetTime() - castAt > SECRET_HELPFUL_CAST_FALLBACK_WINDOW then
        local now = GetTime()
        for i = #recentSecretHelpfulCasts, 1, -1 do
            local cast = recentSecretHelpfulCasts[i]
            if now - cast.castAt > SECRET_HELPFUL_CAST_FALLBACK_WINDOW then
                tremove(recentSecretHelpfulCasts, i)
            elseif cast.kind and cast.spellId then
                return cast.kind, cast.spellId, cast.castAt
            end
        end
        return nil, nil
    end

    return self._recentSecretHelpfulCastKind, self._recentSecretHelpfulCastSpellId, self._recentSecretHelpfulCastAt
end

-- HandleBuff movida a HandleBuff.lua — el cuerpo vive allá, no acá.

local function UnitButton_UpdateBuffs(self, isFullUpdate)
    local unit = self.states.displayedUnit

    ResetBuffVars(self)
    I.ResetCustomIndicators(self, "buff")

    if isFullUpdate then
        self._buffs_cache = {}
        -- Do NOT wipe _classified on full updates. Step 2.5 classifies secret auras
        -- (like Blessing of Freedom, Divine Protection) by tracking newly-added auras
        -- and verifying the cast spell against Cell's tables. Wiping _classified here
        -- causes those auras to lose their classification on subsequent updates since
        -- they're no longer "newly added" and can't be re-classified. Stale entries
        -- in _classified are harmless: they're only checked for auras that still exist
        -- in _buffs_cache, and removed on aura removal events.

        ForEachAura(self, "HELPFUL", Cell.HandleBuff)
    else
        ForEachAuraCache(self, "HELPFUL", Cell.HandleBuff)
    end

    local skipLegacy = I.ShouldSkipLegacyCombatAura

    -- check Mirror Image
    if self._mirror_image and I.IsDefensiveCooldown(55342) then -- exists and enabled
        if not (skipLegacy and skipLegacy("defensiveCooldowns"))
            and self._buffs.defensiveFound < indicatorNums["defensiveCooldowns"] then
            self._buffs.defensiveFound = self._buffs.defensiveFound + 1
            self.indicators.defensiveCooldowns[self._buffs.defensiveFound]:SetCooldown(self._mirror_image, 40, nil, 135994, 0)
        end
        if not (skipLegacy and skipLegacy("allCooldowns"))
            and self._buffs.allFound < indicatorNums["allCooldowns"] then
            self._buffs.allFound = self._buffs.allFound + 1
            self.indicators.allCooldowns[self._buffs.allFound]:SetCooldown(self._mirror_image, 40, nil, 135994, 0)
        end
    end

    -- check Mass Barrier (self)
    if self._mass_barrier and I.IsExternalCooldown(414660) then -- exists and enabled
        if not (skipLegacy and skipLegacy("externalCooldowns"))
            and self._buffs.externalFound < indicatorNums["externalCooldowns"] then
            self._buffs.externalFound = self._buffs.externalFound + 1
            self.indicators.externalCooldowns[self._buffs.externalFound]:SetCooldown(self._mass_barrier, 60, nil, self._mass_barrier_icon, 0)
        end
        if not (skipLegacy and skipLegacy("allCooldowns"))
            and self._buffs.allFound < indicatorNums["allCooldowns"] then
            self._buffs.allFound = self._buffs.allFound + 1
            self.indicators.allCooldowns[self._buffs.allFound]:SetCooldown(self._mass_barrier, 60, nil, self._mass_barrier_icon, 0)
        end
    end

    -- update defensiveCooldowns
    if not (skipLegacy and skipLegacy("defensiveCooldowns")) then
        self.indicators.defensiveCooldowns:UpdateSize(self._buffs.defensiveFound)
    end

    -- update externalCooldowns
    if not (skipLegacy and skipLegacy("externalCooldowns")) then
        self.indicators.externalCooldowns:UpdateSize(self._buffs.externalFound)
    end

    -- update allCooldowns
    if not (skipLegacy and skipLegacy("allCooldowns")) then
        self.indicators.allCooldowns:UpdateSize(self._buffs.allFound)
    end

    -- hide tankActiveMitigation
    if not self._buffs.tankActiveMitigationFound then
        self.indicators.tankActiveMitigation:Hide()
    end

    -- hide drinking
    if not self._buffs.drinkingFound and self.indicators.statusText:GetStatus() == "DRINKING" then
        -- self.indicators.statusText:Hide()
        self.indicators.statusText:SetStatus()
    end

    -- user created indicators
    I.ShowCustomIndicators(self, "buff")
end

-------------------------------------------------
-- aura tables
-------------------------------------------------
local function InitAuraTables(self)
    -- vars
    self._buffs = {}
    self._debuffs = {}

    -- for icon animation only
    self._buffs_cache = {}
    self._debuffs_cache = {}
    self._missing_auras = {}

    -- debuffs
    self._debuffs_normal = {} -- [auraInstanceID] = refreshing
    self._debuffs_big = {} -- [auraInstanceID] = refreshing
    self._debuffs_dispel = {} -- [debuffType] = true/false
    self._debuffs_raid = {} -- {id1, id2, ...}
    self._debuffs_glow_current = {}
end

local function ResetAuraTables(self)
    wipe(self._buffs_cache)
    wipe(self._debuffs_cache)
    wipe(self._missing_auras)

    -- debuffs
    wipe(self._debuffs_normal)
    wipe(self._debuffs_big)
    wipe(self._debuffs_dispel)
    wipe(self._debuffs_raid)

    -- raid debuffs glow
    wipe(self._debuffs_glow_current)
    if self.indicators.raidDebuffs then
        self.indicators.raidDebuffs:HideGlow()
    end

    self._mirror_image = nil
    self._mass_barrier = nil
    self._mass_barrier_icon = nil
    self._recentSecretHelpfulCastKind = nil
    self._recentSecretHelpfulCastAt = nil
    self._recentSecretHelpfulCastSpellId = nil
end

-------------------------------------------------
-- check auras using CLEU
-- NOTE: COMBAT_LOG_EVENT_UNFILTERED is unavailable on Midnight (12.0.0+).
-- CheckCLEURequired guards registration; CLEU handler is wrapped with Cell.isMidnight check.
-------------------------------------------------
local cleu = CreateFrame("Frame")

function CheckCLEURequired()
    -- CLEU (CombatLogGetCurrentEventInfo) removed in 12.0+
    if not CombatLogGetCurrentEventInfo then return end

    if (Cell.vars.currentLayoutTable.indicators[Cell.defaults.indicatorIndices.externalCooldowns].enabled
        or Cell.vars.currentLayoutTable.indicators[Cell.defaults.indicatorIndices.defensiveCooldowns].enabled
        or Cell.vars.currentLayoutTable.indicators[Cell.defaults.indicatorIndices.allCooldowns].enabled)
        and (I.IsDefensiveCooldown(55342) or I.IsExternalCooldown(414660)) then
        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function UpdateMirrorImage(b, event)
    if event == "SPELL_AURA_APPLIED" then
        b._mirror_image = GetTime()
    elseif event == "SPELL_AURA_REMOVED" then
        b._mirror_image = nil
    end
    if b._indicatorsReady then
        UnitButton_UpdateBuffs(b, false) -- should be no full update needed, indicator update is done
    end
end

local SelfBarriers = {
    [11426] = true, -- å¯'å†°æŠ¤ä½" (self)
    [235313] = true, -- çƒˆç„°æŠ¤ä½" (self)
    [235450] = true, -- æ£±å…‰æŠ¤ä½" (self)
}

local function UpdateMassBarrier(b, event)
    if event == "SPELL_CAST_SUCCESS" then
        b._mass_barrier = GetTime()
        local info = LGI:GetCachedInfo(b.states.guid)
        if info then
            if info.specId == 62 then -- Arcane
                b._mass_barrier_icon = 135991
            elseif info.specId == 63 then -- Fire
                b._mass_barrier_icon = 132221
            elseif info.specId == 64 then -- Frost
                b._mass_barrier_icon = 135988
            else
                b._mass_barrier_icon = 1723997
            end
        end
    elseif event == "SPELL_AURA_REMOVED" then
        b._mass_barrier = nil
        b._mass_barrier_icon = nil
    end
    if b._indicatorsReady then
        UnitButton_UpdateBuffs(b, false) -- should be no full update needed, indicator update is done
    end
end

-- CLEU-based indicator tracking (mirror image, mass barrier).
-- Unavailable on Midnight (12.0.0+); guarded by Cell.isMidnight.
if not Cell.isMidnight then
    cleu:SetScript("OnEvent", function()
        local _, subEvent, _, sourceGUID, _, sourceFlags, _, _, _, destFlags, _, spellId = CombatLogGetCurrentEventInfo()

        -- mirror image
        if spellId == 55342 and F.IsFriend(sourceFlags) then
            F.HandleUnitButton("guid", sourceGUID, UpdateMirrorImage, subEvent)
        end

        -- mass barrier (self), SPELL_CAST_SUCCESS
        if spellId == 414660 and F.IsFriend(sourceFlags) then
            F.HandleUnitButton("guid", sourceGUID, UpdateMassBarrier, "SPELL_CAST_SUCCESS")
        end
        if (subEvent == "SPELL_AURA_REMOVED" or subEvent == "SPELL_AURA_REFRESH") and SelfBarriers[spellId] and F.IsFriend(sourceFlags) then
            F.HandleUnitButton("guid", sourceGUID, UpdateMassBarrier, "SPELL_AURA_REMOVED")
        end
    end)
end

-------------------------------------------------
-- functions
-------------------------------------------------
local function GetTrackedSpells()
    local spells = {}
    -- Externals
    if Cell.vars.builtInExternals then
        for id, _ in pairs(Cell.vars.builtInExternals) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    if Cell.vars.customExternals then
        for id, _ in pairs(Cell.vars.customExternals) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    -- Defensives
    if Cell.vars.builtInDefensives then
        for id, _ in pairs(Cell.vars.builtInDefensives) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    if Cell.vars.customDefensives then
        for id, _ in pairs(Cell.vars.customDefensives) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    -- Custom indicators
    if Cell.snippetVars and Cell.snippetVars.customIndicators then
        for auraType, indicators in pairs(Cell.snippetVars.customIndicators) do
            local filter = auraType == "buff" and "HELPFUL" or "HARMFUL"
            for _, indicatorTable in pairs(indicators) do
                if indicatorTable._auras then
                    for _, id in pairs(indicatorTable._auras) do
                        spells[id] = filter
                    end
                end
            end
        end
    end
    -- Layout indicators (including Healers and default class indicators)
    if Cell.vars.currentLayoutTable and Cell.vars.currentLayoutTable["indicators"] then
        for _, t in ipairs(Cell.vars.currentLayoutTable["indicators"]) do
            if t["auras"] then
                local filter = t["auraType"] == "buff" and "HELPFUL" or "HARMFUL"
                for _, id in pairs(t["auras"]) do
                    if type(id) == "number" then
                        spells[id] = filter
                    end
                end
            end
        end
    end
    return spells
end

UnitButton_UpdateAuras = function(self, updateInfo)
    if not self._indicatorsReady then return end

    local unit = self.states.displayedUnit
    if not unit then return end

    if F.IsLiveAuraScanBlocked and F.IsLiveAuraScanBlocked() then
        return
    end

    if F.IsAuraRestricted and F.IsAuraRestricted() then
        if I.UpdateHealersAuraDisplayUnit then
            I.UpdateHealersAuraDisplayUnit(self)
        end
        if I.UpdateCustomAuraDisplays then
            I.UpdateCustomAuraDisplays(self)
        end
        if I.UpdateCombatAuraDisplays then
            I.UpdateCombatAuraDisplays(self)
        end
        return
    end

    -- 12.1+: isFullUpdate may be secret under aura restrictions — never boolean-test it raw.
    local isFullUpdate = true
    if updateInfo then
        local full = updateInfo.isFullUpdate
        if F.IsValueNonSecret(full) then
            isFullUpdate = full and true or false
        end
    end

    if isFullUpdate then
        -- full update
        UnitButton_UpdateBuffs(self, true)
        UnitButton_UpdateDebuffs(self, true)
    else
        -- Midnight 12.0.0+: some aura fields may still be secret. Per-aura checks in
        -- HandleBuff/HandleDebuff handle this. We no longer force full update for ALL
        -- Midnight aura events  -- only fall back to full update if we encounter secret
        -- isHelpful/isHarmful fields in addedAuras that prevent classification.
        local buffsChanged, debuffsChanged
        local needsFullUpdate
        wipe(self._missing_auras)

        if updateInfo.addedAuras then
            for _, rawAura in next, updateInfo.addedAuras do
                local aura = AnnotateAura(rawAura)
                if aura then
                    local isHelpful, isHarmful
                    if aura._hasSecrets then
                        -- Secret aura: can't boolean-test isHelpful/isHarmful. Use server filter.
                        if _IsAuraFilteredOut then
                            isHelpful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL") and true or nil
                            isHarmful = (not isHelpful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL")) and true or nil
                        end
                        -- Fallback: try to classify by spellId directly (bypasses secret filters)
                        if not isHelpful and not isHarmful and F.IsValueNonSecret(aura.spellId) then
                            if I.IsExternalCooldown(nil, aura.spellId) or I.IsDefensiveCooldown(nil, aura.spellId) then
                                isHelpful = true
                            end
                        end
                    else
                        -- Non-secret: use fields directly (safe boolean test)
                        isHelpful, isHarmful = aura.isHelpful, aura.isHarmful
                        if not isHelpful and not isHarmful and _IsAuraFilteredOut then
                            isHelpful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL") and true or nil
                            isHarmful = (not isHelpful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL")) and true or nil
                        end
                    end
                    -- Track ALL newly added secret auras (regardless of isHelpful/isHarmful
                    -- resolution) for Step 2.5 fingerprint matching. This ensures auras
                    -- that can't be classified as helpful/harmful (triggering needsFullUpdate)
                    -- are still tracked for the fingerprint fallback path.
                    if aura._hasSecrets then
                        if not self._recentlyAddedAuraIDs then self._recentlyAddedAuraIDs = {} end
                        self._recentlyAddedAuraIDs[aura.auraInstanceID] = true
                    end
                    if not isHelpful and not isHarmful then
                        needsFullUpdate = true
                    elseif isHelpful then
                        buffsChanged = true
                        self._buffs_cache[aura.auraInstanceID] = aura
                    else
                        debuffsChanged = true
                        self._debuffs_cache[aura.auraInstanceID] = aura
                    end
                end
            end
        end

        if not needsFullUpdate and updateInfo.updatedAuraInstanceIDs then
            local aura
            -- auraInstanceID is NOT secret and is safe to use as table key
            for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
                if self._buffs_cache[auraInstanceID] then
                    buffsChanged = true
                    aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if aura then
                        if not aura._hasSecrets then
                            -- Non-secret: safe to read cached values for refresh animation
                            local cachedExp = self._buffs_cache[auraInstanceID].expirationTime
                            local cachedApp = self._buffs_cache[auraInstanceID].applications
                            aura.oldExpirationTime = (cachedExp and F.IsValueNonSecret(cachedExp)) and cachedExp or 0
                            aura.oldApplications = (cachedApp and F.IsValueNonSecret(cachedApp)) and cachedApp or nil
                        end
                        self._buffs_cache[auraInstanceID] = aura
                    end
                elseif self._debuffs_cache[auraInstanceID] then
                    debuffsChanged = true
                    aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if aura then
                        if not aura._hasSecrets then
                            local cachedExp = self._debuffs_cache[auraInstanceID].expirationTime
                            local cachedApp = self._debuffs_cache[auraInstanceID].applications
                            aura.oldExpirationTime = (cachedExp and F.IsValueNonSecret(cachedExp)) and cachedExp or 0
                            aura.oldApplications = (cachedApp and F.IsValueNonSecret(cachedApp)) and cachedApp or nil
                        end
                        self._debuffs_cache[auraInstanceID] = aura
                    end
                else
                    aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if aura then
                        self._missing_auras[auraInstanceID] = aura
                    end
                end
            end
        end

        if not needsFullUpdate and updateInfo.removedAuraInstanceIDs then
            for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
                if self._buffs_cache[auraInstanceID] then
                    self._buffs_cache[auraInstanceID] = nil
                    if self._buffs._classified then self._buffs._classified[auraInstanceID] = nil end
                    buffsChanged = true
                elseif self._debuffs_cache[auraInstanceID] then
                    self._debuffs_cache[auraInstanceID] = nil
                    debuffsChanged = true
                else
                    self._missing_auras[auraInstanceID] = nil
                end
            end
        end

        if not needsFullUpdate and next(self._missing_auras) then
            for _, aura in next, self._missing_auras do
                if aura then
                    local isHelpful, isHarmful
                    if aura._hasSecrets then
                        if _IsAuraFilteredOut then
                            isHarmful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL") and true or nil
                            isHelpful = (not isHarmful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL")) and true or nil
                        end
                    else
                        isHelpful, isHarmful = aura.isHelpful, aura.isHarmful
                        if not isHelpful and not isHarmful and _IsAuraFilteredOut then
                            isHarmful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL") and true or nil
                            isHelpful = (not isHarmful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL")) and true or nil
                        end
                    end
                    if isHelpful then
                        buffsChanged = true
                        self._buffs_cache[aura.auraInstanceID] = aura
                    elseif isHarmful then
                        debuffsChanged = true
                        self._debuffs_cache[aura.auraInstanceID] = aura
                    end
                end
            end
        end

        if needsFullUpdate then
            UnitButton_UpdateBuffs(self, true)
            UnitButton_UpdateDebuffs(self, true)
        else
            if buffsChanged then UnitButton_UpdateBuffs(self) end
            if debuffsChanged then UnitButton_UpdateDebuffs(self) end
        end
        -- Clear recently-added tracking after processing (used by Step 2.5 fingerprint matching)
        if self._recentlyAddedAuraIDs then
            wipe(self._recentlyAddedAuraIDs)
        end
    end

    I.UpdateStatusIcon(self)
end

-- Updates the health prediction calculator for a button (Midnight 12.0.0+)
local function UnitButton_UpdateCalculator(self)
    local unit = self.states.displayedUnit
    if not unit then return end
    local calc = self.widgets.healthCalculator
    if not calc then return end
    -- UnitGetDetailedHealPrediction is C-level; guard with UnitExists for AI followers/unavailable units
    if UnitExists(unit) then
        UnitGetDetailedHealPrediction(unit, "player", calc)
    end
end

local function UnitButton_UpdateHealthStates(self, diff)
    local unit = self.states.displayedUnit

    if Cell.isMidnight and self.widgets.healthCalculator then
        -- MIDNIGHT PATH: use calculator  -- no arithmetic on secrets
        UnitButton_UpdateCalculator(self)
        -- Store healthPercent for color logic.
        -- Calculator's GetCurrentHealthPercent() always returns secret (even out of combat).
        -- Fall back to UnitHealth/UnitHealthMax which are non-secret outside PvP instances.
        local health = UnitHealth(unit)
        local healthMax = UnitHealthMax(unit)
        if not F.HasAnySecretValues(health, healthMax) and healthMax > 0 then
            self.states.healthPercent = health / healthMax
            self.states.healthMax = healthMax
        else
            -- In-combat secret: default to 0 so F.GetHealthBarColor won't trigger fullColor (which checks == 1).
            -- class_color / class_color_dark modes don't use percent, so they still work.
            self.states.healthPercent = 0
        end
        -- Death detection uses non-secret boolean
        self.states.wasDead = self.states.isDead
        self.states.isDead = UnitIsDeadOrGhost(unit) or false
        -- Fallback: use UnitIsDeadOrGhost which is always non-secret
        self.states.wasDeadOrGhost = self.states.isDeadOrGhost
        self.states.isDeadOrGhost = UnitIsDeadOrGhost(unit) or false

        -- Health text: calculator values flow to C-level SetFormattedText/SetText
        if enabledIndicators["healthText"] then
            local calc = self.widgets.healthCalculator
            local health = calc:GetCurrentHealth()
            local maxHealth = calc:GetMaximumHealth()
            local totalAbsorbs = calc:GetTotalDamageAbsorbs()
            local healAbsorbs = calc:GetTotalHealAbsorbs()
            -- Fallback: if calculator wasn't populated (e.g. solo, no group),
            -- use direct UnitHealth/UnitHealthMax for health text display.
            if F.IsValueNonSecret(maxHealth) and maxHealth == 0 and unit then
                health = UnitHealth(unit)
                maxHealth = UnitHealthMax(unit)
                totalAbsorbs = UnitGetTotalAbsorbs(unit) or 0
                healAbsorbs = UnitGetTotalHealAbsorbs(unit) or 0
            end
            self.indicators.healthText:SetValue(health, maxHealth, totalAbsorbs, healAbsorbs, unit)
            self.indicators.healthText:Show()
        else
            self.indicators.healthText:Hide()
        end

        -- Fire death-state change callbacks
        if self.states.wasDead ~= self.states.isDead then
            UnitButton_UpdateStatusText(self)
            I.UpdateStatusIcon_Resurrection(self)
            if not self.states.isDead then
                self.states.hasSoulstone = nil
                I.UpdateStatusIcon(self)
            end
        end
        if self.states.wasDeadOrGhost ~= self.states.isDeadOrGhost then
            I.UpdateStatusIcon_Resurrection(self)
            UnitButton_UpdateHealthColor(self)
        end
    else
        -- CLASSIC/PRE-MIDNIGHT PATH: original logic preserved
        local health = UnitHealth(unit) + (diff or 0)
        local healthMax = UnitHealthMax(unit)
        health = min(health, healthMax) --! diff

        self.states.health = health
        self.states.healthMax = healthMax
        self.states.totalAbsorbs = UnitGetTotalAbsorbs(unit)
        self.states.healAbsorbs = UnitGetTotalHealAbsorbs(unit)

        if healthMax == 0 then
            self.states.healthPercent = 0
        else
            self.states.healthPercent = health / healthMax
        end

        self.states.wasDead = self.states.isDead
        self.states.isDead = health == 0
        if self.states.wasDead ~= self.states.isDead then
            UnitButton_UpdateStatusText(self)
            I.UpdateStatusIcon_Resurrection(self)
            if not self.states.isDead then
                self.states.hasSoulstone = nil
                I.UpdateStatusIcon(self)
            end
        end

        self.states.wasDeadOrGhost = self.states.isDeadOrGhost
        self.states.isDeadOrGhost = UnitIsDeadOrGhost(unit)
        if self.states.wasDeadOrGhost ~= self.states.isDeadOrGhost then
            I.UpdateStatusIcon_Resurrection(self)
            UnitButton_UpdateHealthColor(self)
        end

        if enabledIndicators["healthText"] then -- and not self.states.isDeadOrGhost then
            self.indicators.healthText:SetValue(health, healthMax, self.states.totalAbsorbs, self.states.healAbsorbs, unit)
            self.indicators.healthText:Show()
        else
            self.indicators.healthText:Hide()
        end
    end
end

local function UnitButton_UpdatePowerStates(self)
    local unit = self.states.displayedUnit
    if not unit then return end

    -- 12.0+: UnitPower may return secret values; store raw for SetValue
    self.states.power = UnitPower(unit)
    self.states.powerMax = UnitPowerMax(unit)
    -- Midnight 12.0.0+: UnitPowerMax may be secret — only clamp when non-secret
    if F.IsValueNonSecret(self.states.powerMax) then
        if self.states.powerMax <= 0 then self.states.powerMax = 1 end
    end
end

-------------------------------------------------
-- power filter funcs
-------------------------------------------------
local function GetRole(b)
    if b.states.role and b.states.role ~= "NONE" then
        return b.states.role
    end

    -- For the player's own unit, get role from current spec directly
    -- (UnitGroupRolesAssigned returns "NONE" when solo or in non-LFG groups)
    -- UnitIsUnit may return a secret boolean; check before boolean test.
    -- For player identity check, treat secret as false (safe fallback).
    local isPlayer = b.states.unit and UnitIsUnit(b.states.unit, "player")
    if GetSpecialization and GetSpecializationRole
        and b.states.unit and F.IsValueNonSecret(isPlayer) and isPlayer then
        local spec = GetSpecialization()
        if spec then
            local specRole = GetSpecializationRole(spec)
            if specRole and specRole ~= "NONE" then
                return specRole
            end
        end
    end

    -- Fresh UnitGroupRolesAssigned check (role may have been assigned after init)
    if b.states.unit then
        local freshRole = UnitGroupRolesAssigned(b.states.unit)
        if freshRole and freshRole ~= "NONE" then
            b.states.role = freshRole
            return freshRole
        end
    end

    local info = LGI:GetCachedInfo(b.states.guid)
    if not info then return end
    return info.role
end

-- Evaluate a role filter table when the specific role is unknown.
-- Returns false if ALL roles in the table are disabled, true otherwise.
local function EvaluateFilterWithoutRole(filterTable)
    if type(filterTable) == "boolean" then
        return filterTable
    end
    -- If any role is enabled, show (safe default when role unknown)
    for _, enabled in pairs(filterTable) do
        if enabled then
            return true
        end
    end
    -- All roles disabled for this class → hide
    return false
end

-- Determine class and role for a unit button (used by power filter functions)
local function GetClassAndRole(b)
    local class, role
    local guid = b.states.guid
    -- 12.0+: guid may be secret for NPC units — can't use string.find on secrets
    if guid and not F.IsValueNonSecret(guid) then
        -- Fallback: use UnitInPartyIsAI to detect AI followers without needing guid
        if b.states.unit and UnitInPartyIsAI(b.states.unit) then
            class = b.states.class
            role = GetRole(b)
        end
        return class, role
    end
    if b.states.inVehicle then
        class = "VEHICLE"
    elseif F.IsPlayer(guid) then
        class = b.states.class
        role = GetRole(b)
    elseif F.IsPet(guid) then
        class = "PET"
    elseif F.IsNPC(guid) then
        if UnitInPartyIsAI(b.states.unit) then
            class = b.states.class
            role = GetRole(b)
        else
            class = "NPC"
        end
    elseif F.IsVehicle(guid) then
        class = "VEHICLE"
    end
    return class, role
end

ShouldShowPowerText = function(b)
    if not enabledIndicators["powerText"] then return end
    if not (b:IsVisible() or b.isPreview) then return end

    -- guid may be secret for NPC/follower units; `== nil` is safe on secrets.
    if b.states.guid == nil then
        return true
    end

    local class, role = GetClassAndRole(b)

    if class then
        local filter = indicatorCustoms["powerText"] and indicatorCustoms["powerText"][class]
        if filter == nil then
            return true
        elseif type(filter) == "boolean" then
            return filter
        else
            if role then
                return filter[role]
            else
                return EvaluateFilterWithoutRole(filter)
            end
        end
    end

    return true
end

ShouldShowPowerBar = function(b)
    if not (b:IsVisible() or b.isPreview) then return end
    if not b.powerSize or b.powerSize == 0 then return end

    -- guid may be secret for NPC/follower units; == nil is safe on secrets.
    if b.states.guid == nil then
        return true
    end

    local class, role = GetClassAndRole(b)

    if class and Cell.vars.currentLayoutTable then
        local filter = Cell.vars.currentLayoutTable["powerFilters"] and Cell.vars.currentLayoutTable["powerFilters"][class]
        if filter == nil then
            return true
        elseif type(filter) == "boolean" then
            return filter
        else
            if role then
                return filter[role]
            else
                return EvaluateFilterWithoutRole(filter)
            end
        end
    end

    return true
end

CheckPowerEventRegistration = function(b)
    if b:IsVisible() and not b.isPreview and (b._shouldShowPowerText or b._shouldShowPowerBar) then
        b:RegisterEvent("UNIT_POWER_FREQUENT")
        b:RegisterEvent("UNIT_MAXPOWER")
        b:RegisterEvent("UNIT_DISPLAYPOWER")
        return true
    else
        b:UnregisterEvent("UNIT_POWER_FREQUENT")
        b:UnregisterEvent("UNIT_MAXPOWER")
        b:UnregisterEvent("UNIT_DISPLAYPOWER")
        return false
    end
end

local function ShowPowerBar(b)
    b.widgets.powerBar:Show()
    b.widgets.powerBarLoss:Show()
    b.widgets.gapTexture:SetShown(CELL_BORDER_SIZE ~= 0)

    P.ClearPoints(b.widgets.healthBar)
    P.ClearPoints(b.widgets.powerBar)
    if b.orientation == "horizontal" or b.orientation == "vertical_health" then
        P.Point(b.widgets.healthBar, "TOPLEFT", b, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
        P.Point(b.widgets.healthBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, b.powerSize + CELL_BORDER_SIZE * 2)
        P.Point(b.widgets.powerBar, "TOPLEFT", b.widgets.healthBar, "BOTTOMLEFT", 0, -CELL_BORDER_SIZE)
        P.Point(b.widgets.powerBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
    else
        P.Point(b.widgets.healthBar, "TOPLEFT", b, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
        P.Point(b.widgets.healthBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -(b.powerSize + CELL_BORDER_SIZE * 2), CELL_BORDER_SIZE)
        P.Point(b.widgets.powerBar, "TOPLEFT", b.widgets.healthBar, "TOPRIGHT", CELL_BORDER_SIZE, 0)
        P.Point(b.widgets.powerBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
    end

    if b:IsVisible() then
        -- update now
        CheckPowerEventRegistration(b)
        UnitButton_UpdatePowerStates(b)
        UnitButton_UpdatePowerType(b)
        UnitButton_UpdatePowerMax(b)
        UnitButton_UpdatePower(b)
    end
end

local function HidePowerBar(b)
    CheckPowerEventRegistration(b)
    b.widgets.powerBar:Hide()
    b.widgets.powerBarLoss:Hide()
    b.widgets.gapTexture:Hide()

    P.ClearPoints(b.widgets.healthBar)
    P.Point(b.widgets.healthBar, "TOPLEFT", b, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
    P.Point(b.widgets.healthBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
end

-------------------------------------------------
-- unit button functions
-------------------------------------------------
local function UnitButton_UpdateTarget(self)
    local unit = self.states.displayedUnit
    if not unit then return end

    -- UnitIsUnit may return a secret boolean in combat; check before boolean test.
    -- Treat secret as true (better to show highlight than miss the player's target).
    local isTarget = UnitIsUnit(unit, "target")
    if not F.IsValueNonSecret(isTarget) or isTarget then
        if highlightEnabled then self.widgets.targetHighlight:Show() end
    else
        self.widgets.targetHighlight:Hide()
    end
end


local function CheckVehicleRoot(self, petUnit)
    if not petUnit then return end

    local playerUnit = F.GetPlayerUnit(petUnit)

    local isRoot
    for i = 1, UnitVehicleSeatCount(playerUnit) do
        local controlType, occupantName, serverName, ejectable, canSwitchSeats = UnitVehicleSeatInfo(playerUnit, i)
        local pName = UnitName(playerUnit)
        -- On Midnight 12.0.0+, UnitName() may return a secret string in instances
        -- Comparing a secret string with == will error, so guard before comparing
        if F.IsValueNonSecret(pName) and pName == occupantName then
            isRoot = controlType == "Root"
            break
        end
    end

    self.indicators.roleIcon:SetRole(isRoot and "VEHICLE-ROOT" or "VEHICLE")
end

UnitButton_UpdateRole = function(self)
    local unit = self.states.unit
    if not unit then return end

    local role = UnitGroupRolesAssigned(unit)
    self.states.role = role

    local roleIcon = self.indicators.roleIcon
    if enabledIndicators["roleIcon"] then

        roleIcon:SetRole(role)

        --! check vehicle root
        -- Midnight 12.0.0+: guid may be secret for NPC/boss units
        if self.states.guid and F.IsValueNonSecret(self.states.guid) and strfind(self.states.guid, "^Vehicle") and not UnitInPartyIsAI(unit) then
            CheckVehicleRoot(self, unit)
        end
    else
        roleIcon:Hide()
    end
end

UnitButton_UpdateLeader = function(self, event)
    local unit = self.states.unit
    if not unit then return end

    local leaderIcon = self.indicators.leaderIcon

    if enabledIndicators["leaderIcon"] then
        if indicatorBooleans["leaderIcon"] and (InCombatLockdown() or event == "PLAYER_REGEN_DISABLED") then
            leaderIcon:Hide()
            return
        end

        local isLeader = UnitIsGroupLeader(unit)
        self.states.isLeader = isLeader
        local isAssistant = UnitIsGroupAssistant(unit) and IsInRaid()
        self.states.isAssistant = isAssistant

        leaderIcon:SetIcon(isLeader, isAssistant)
    else
        leaderIcon:Hide()
    end
end

local function UnitButton_UpdatePlayerRaidIcon(self)
    local unit = self.states.displayedUnit
    if not unit then return end

    local playerRaidIcon = self.indicators.playerRaidIcon

    local index = GetRaidTargetIndex(unit)

    if enabledIndicators["playerRaidIcon"] then
        if index then
            SetRaidTargetIconTexture(playerRaidIcon.tex, index)
            playerRaidIcon:Show()
        else
            playerRaidIcon:Hide()
        end
    else
        playerRaidIcon:Hide()
    end
end

local function UnitButton_UpdateTargetRaidIcon(self)
    local unit = self.states.displayedUnit
    if not unit then return end

    local targetRaidIcon = self.indicators.targetRaidIcon

    local index = GetRaidTargetIndex(unit.."target")

    if enabledIndicators["targetRaidIcon"] then
        if index then
            SetRaidTargetIconTexture(targetRaidIcon.tex, index)
            targetRaidIcon:Show()
        else
            targetRaidIcon:Hide()
        end
    else
        targetRaidIcon:Hide()
    end
end

local function UnitButton_UpdateReadyCheck(self)
    local unit = self.states.unit
    if not unit then return end

    local status = GetReadyCheckStatus(unit)
    self.states.readyCheckStatus = status

    if enabledIndicators["readyCheckIcon"] and status then
        -- self.widgets.readyCheckHighlight:SetVertexColor(unpack(READYCHECK_STATUS[status].c))
        -- self.widgets.readyCheckHighlight:Show()
        self.indicators.readyCheckIcon:SetStatus(status)
    else
        -- self.widgets.readyCheckHighlight:Hide()
        self.indicators.readyCheckIcon:Hide()
    end
end

local function UnitButton_FinishReadyCheck(self)
    if not enabledIndicators["readyCheckIcon"] then return end

    if self.states.readyCheckStatus == "waiting" then
        -- self.widgets.readyCheckHighlight:SetVertexColor(unpack(READYCHECK_STATUS.notready.c))
        self.indicators.readyCheckIcon:SetStatus("notready")
    end
    C_Timer.After(6, function()
        -- self.widgets.readyCheckHighlight:Hide()
        self.indicators.readyCheckIcon:Hide()
    end)
end

UnitButton_UpdatePowerText = function(self)
    if not self._shouldShowPowerText then return end

    local power = self.states.power
    local powerMax = self.states.powerMax
    -- 12.0+: power may be secret; == nil is safe on secrets
    if power == nil or self.states.isDeadOrGhost then
        self.indicators.powerText:Hide()
        return
    end

    if not F.HasAnySecretValues(power, powerMax) then
        self.indicators.powerText:SetValue(power, powerMax)
    else
        -- Pass secret values to C-level SetFormattedText directly.
        local unit = self.states.displayedUnit
        local fmt = self.indicators.powerText._format
        if fmt == "percentage" then
            -- UnitPowerPercent returns 0-1 by default; use ScaleTo100 curve for 0-100
            local pct
            if unit and UnitPowerPercent then
                if CurveConstants and CurveConstants.ScaleTo100 then
                    pct = UnitPowerPercent(unit, nil, true, CurveConstants.ScaleTo100)
                else
                    pct = UnitPowerPercent(unit)
                end
            end
            if pct then
                self.indicators.powerText.text:SetFormattedText("%d%%", pct)
            else
                self.indicators.powerText.text:SetFormattedText("%d", power)
            end
        elseif fmt == "number-short" and AbbreviateNumbers then
            self.indicators.powerText.text:SetFormattedText("%s", AbbreviateNumbers(power))
        else
            -- "number" or "number-short" without AbbreviateNumbers: raw number
            self.indicators.powerText.text:SetFormattedText("%d", power)
        end
        -- GetStringWidth returns secret when text is tainted; skip SetWidth
        self.indicators.powerText:Show()
    end
end

UnitButton_UpdatePowerTextColor = function(self)
    if not self._shouldShowPowerText then return end

    local unit = self.states.displayedUnit
    if not unit then return end

    if indicatorColors["powerText"][1] == "power_color" then
        self.indicators.powerText:SetColor(F.GetPowerColor(unit))
    elseif indicatorColors["powerText"][1] == "class_color" then
        self.indicators.powerText:SetColor(F.GetUnitClassColor(unit))
    else
        self.indicators.powerText:SetColor(unpack(indicatorColors["powerText"][2]))
    end
end

UnitButton_UpdatePowerMax = function(self)
    if not self._shouldShowPowerBar then return end
    if self.states.powerMax == nil then return end

    -- powerMax may be secret on Midnight 12.0.0+ for some units.
    -- SetMinMaxSmoothedValue is a Lua mixin that does arithmetic (Clamp) — unsafe on Midnight.
    if barAnimationType == "Smooth" and not Cell.isMidnight then
        self.widgets.powerBar:SetMinMaxSmoothedValue(0, self.states.powerMax)
    else
        self.widgets.powerBar:SetMinMaxValues(0, self.states.powerMax)
    end
end

UnitButton_UpdatePower = function(self)
    if not self._shouldShowPowerBar then return end
    if self.states.power == nil then return end

    -- Midnight "Smooth": StatusBarInterpolation (secret-safe).
    -- Midnight "Legacy"/None: immediate SetValue (SmoothStatusBarMixin cannot Clamp secrets).
    -- Pre-Midnight: SetBarValue maps to SetSmoothedValue in Smooth mode.
    if Cell.isMidnight and SBI_ExponentialEaseOut then
        local smoothEnum = (barAnimationType == "Smooth" and SBI_ExponentialEaseOut) or SBI_Immediate
        self.widgets.powerBar:SetValue(self.states.power, smoothEnum)
    else
        self.widgets.powerBar:SetBarValue(self.states.power)
    end
end

UnitButton_UpdatePowerType = function(self)
    if not self._shouldShowPowerBar then return end

    local unit = self.states.displayedUnit
    if not unit then return end

    local r, g, b, lossR, lossG, lossB
    local a = Cell.loaded and CellDB["appearance"]["lossAlpha"] or 1

    if not UnitIsConnected(unit) then
        r, g, b = 0.4, 0.4, 0.4
        lossR, lossG, lossB = 0.4, 0.4, 0.4
    else
        r, g, b, lossR, lossG, lossB, self.states.powerType = F.GetPowerBarColor(unit, self.states.class)
    end

    self.widgets.powerBar:SetStatusBarColor(r, g, b)
    self.widgets.powerBarLoss:SetVertexColor(lossR, lossG, lossB)
end

local function UnitButton_UpdateHealthMax(self)
    local unit = self.states.displayedUnit
    if not unit then return end

    UnitButton_UpdateHealthStates(self)

    if Cell.isMidnight and self.widgets.healthCalculator then
        -- MIDNIGHT PATH: pass secret maxHealth directly
        -- Never use SetMinMaxSmoothedValue on Midnight — mixin Clamp() errors on secrets.
        local maxHealth = self.widgets.healthCalculator:GetMaximumHealth()
        self.widgets.healthBar:SetMinMaxValues(0, maxHealth)
        -- Also update overlay bar ranges
        if self.widgets.incomingHeal then
            self.widgets.incomingHeal:SetMinMaxValues(0, maxHealth)
        end
        if self.widgets.shieldBar then
            self.widgets.shieldBar:SetMinMaxValues(0, maxHealth)
        end
        if self.widgets.shieldBarR then
            self.widgets.shieldBarR:SetMinMaxValues(0, maxHealth)
        end
        if self.widgets.absorbsBar then
            self.widgets.absorbsBar:SetMinMaxValues(0, maxHealth)
        end
    else
        -- CLASSIC/PRE-MIDNIGHT PATH: original logic
        if barAnimationType == "Smooth" or barAnimationType == "Legacy" or barAnimationType == "Old" then
            self.widgets.healthBar:SetMinMaxSmoothedValue(0, self.states.healthMax)
        else
            self.widgets.healthBar:SetMinMaxValues(0, self.states.healthMax)
        end
    end

    if Cell.vars.useThresholdColor or Cell.vars.useFullColor then
        UnitButton_UpdateHealthColor(self)
    end
end

local function UnitButton_UpdateHealth(self, diff, skipStateUpdates)
    local unit = self.states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self, diff)
    end

    if Cell.isMidnight and self.widgets.healthCalculator then
        -- MIDNIGHT PATH: pass health to status bar
        -- "Smooth": StatusBarInterpolation (secret-safe).
        -- "Legacy": same as upstream Cell_beta — immediate SetValue.
        -- SmoothStatusBarMixin cannot be used here: its OnUpdate Clamp() errors on secrets.
        local calc = self.widgets.healthCalculator
        local health = calc:GetCurrentHealth()
        local smoothEnum = (barAnimationType == "Smooth" and SBI_ExponentialEaseOut) or SBI_Immediate
        self.widgets.healthBar:SetValue(health, smoothEnum)

        if Cell.vars.useThresholdColor or Cell.vars.useFullColor then
            UnitButton_UpdateHealthColor(self)
        end

        -- Health thresholds: use EvaluateCurrentHealthPercent with a curve
        if enabledIndicators["healthThresholds"] and self.widgets.healthCalculator then
            self.indicators.healthThresholds:CheckThresholdMidnight(self.widgets.healthCalculator)
        else
            self.indicators.healthThresholds:Hide()
        end

        -- CELL_FADE_OUT_HEALTH_PERCENT: use EvaluateMissingHealthPercent with a Curve to fade
        -- frames that are above the health threshold (healthy enough to fade out)
        if CELL_FADE_OUT_HEALTH_PERCENT and self.widgets.healthCalculator then
            RebuildFadeOutHealthCurve()
            if fadeOutHealthCurve and self.states.inRange then
                -- EvaluateCurrentHealthPercent feeds secret health% into the curve
                -- Curve output: 1.0 if below threshold (needs healing), outOfRangeAlpha if above
                local targetAlpha = self.widgets.healthCalculator:EvaluateCurrentHealthPercent(fadeOutHealthCurve)
                -- targetAlpha is a secret value  -- SetAlpha accepts secrets on Midnight
                self:SetAlpha(targetAlpha)
            end
        end
    else
        -- CLASSIC/PRE-MIDNIGHT PATH: original logic
        local healthPercent = self.states.healthPercent

        self.widgets.healthBar:SetBarValue(self.states.health)

        if Cell.vars.useThresholdColor or Cell.vars.useFullColor then
            UnitButton_UpdateHealthColor(self)
        end

        self.states.healthPercentOld = healthPercent

        if enabledIndicators["healthThresholds"] then
            self.indicators.healthThresholds:CheckThreshold(healthPercent)
        else
            self.indicators.healthThresholds:Hide()
        end

        if CELL_FADE_OUT_HEALTH_PERCENT then
            if self.states.inRange and healthPercent < CELL_FADE_OUT_HEALTH_PERCENT then
                A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
            else
                A.FrameFadeOut(self, 0.25, self:GetAlpha(), CellDB["appearance"]["outOfRangeAlpha"])
            end
        end
    end
end

local function UnitButton_UpdateHealPrediction(self, skipStateUpdates)
    if Cell.isMidnight and self.widgets.healPredictionCalculator then
        -- MIDNIGHT PATH: use a DEDICATED calculator for heal prediction.
        -- This keeps clamp/overflow settings isolated from the shared
        -- healthCalculator used by health, absorb, and heal-absorb reads.
        -- Bar is anchored to health fill edge (set in SetOrientation).
        -- SetMinMaxValues(0, maxHealth) + SetValue(incomingHeals) lets the
        -- C++ widget compute the proportional fill natively with secrets.
        if not predictionEnabled then
            self.widgets.incomingHeal:Hide()
            return
        end
        local unit = self.states.displayedUnit
        if not unit then return end
        local calc = self.widgets.healPredictionCalculator
        -- Configure clamp: 0 = MissingHealth (no overheal past frame edge)
        calc:SetIncomingHealClampMode(0)
        calc:SetIncomingHealOverflowPercent(1.0)
        -- Populate calculator with fresh data
        UnitGetDetailedHealPrediction(unit, "player", calc)
        local maxHealth = calc:GetMaximumHealth()
        local incomingHeals = calc:GetIncomingHeals()
        local bar = self.widgets.incomingHeal
        -- Set explicit size: bar fills from health edge across remaining bar space
        if self.orientation == "horizontal" then
            bar:SetWidth(self.widgets.healthBar:GetWidth())
        else
            bar:SetHeight(self.widgets.healthBar:GetHeight())
        end
        bar:SetMinMaxValues(0, maxHealth)
        bar:SetValue(incomingHeals)
        bar:Show()
        return
    end
    -- CLASSIC/PRE-MIDNIGHT PATH: original logic
    if not predictionEnabled then
        self.widgets.incomingHeal:Hide()
        return
    end

    local unit = self.states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self)
    end

    local incomingHeal = self.widgets.incomingHeal
    -- Set size to match health bar for correct proportions
    if self.orientation == "horizontal" then
        incomingHeal:SetWidth(self.widgets.healthBar:GetWidth())
    else
        incomingHeal:SetHeight(self.widgets.healthBar:GetHeight())
    end

    -- 12.0+: UnitGetDetailedHealPrediction populates a calculator object whose
    -- getter methods return potentially secret values. These are passed directly
    -- to SetMinMaxValues/SetValue (C-level APIs that accept secrets).
    local calc = self.widgets.healPredictionCalculator
    if calc and UnitGetDetailedHealPrediction then
        if UnitExists(unit) then
            UnitGetDetailedHealPrediction(unit, nil, calc)
        end
        local allHeal
        if calc.GetIncomingHeals then
            allHeal = select(1, calc:GetIncomingHeals())
        end
        incomingHeal:SetMinMaxValues(0, self.states.healthMax)
        incomingHeal:SetValue((allHeal == nil) and 0 or allHeal)
    else
        -- Fallback for pre-12.0
        local value = UnitGetIncomingHeals(unit) or 0
        incomingHeal:SetMinMaxValues(0, self.states.healthMax)
        incomingHeal:SetValue(value)
    end
    incomingHeal:Show()
end

UnitButton_UpdateShieldAbsorbs = function(self, skipStateUpdates)
        if Cell.isMidnight and self.widgets.healthCalculator then
            -- MIDNIGHT PATH: use calculator secret values
            if not shieldEnabled then
                self.widgets.shieldBar:Hide()
                self.widgets.shieldBarR:Hide()
                self.widgets.overShieldGlow:Hide()
                self.widgets.overShieldGlowR:Hide()
                self.indicators.shieldBar:Hide()
                return
            end
            local unit = self.states.displayedUnit
            if not unit then return end
            -- Skip redundant calculator refresh when called from UNIT_HEALTH chain
            -- (UpdateHealthStates already populated it).
            if not skipStateUpdates then
                UnitButton_UpdateCalculator(self)
            end
        local absorbs = self.widgets.healthCalculator:GetTotalDamageAbsorbs()
        local healthMax = self.widgets.healthCalculator:GetMaximumHealth()

        -- Overshield detection: GetDamageAbsorbs returns (amount, isClamped)
        -- where isClamped is true when absorbs exceed max health (overshield).
        -- isClamped may be a secret boolean; SetAlphaFromBoolean handles that.
        local _, isClamped
        local calc = self.widgets.healPredictionCalculator
        if calc and UnitGetDetailedHealPrediction then
            if UnitExists(unit) then
                UnitGetDetailedHealPrediction(unit, nil, calc)
            end
            if calc.GetDamageAbsorbs then
                _, isClamped = calc:GetDamageAbsorbs()
            end
        end

        if overshieldReverseFillEnabled then
            self.widgets.shieldBar:Hide()
            self.widgets.shieldBarR:SetMinMaxValues(0, healthMax)
            self.widgets.shieldBarR:SetValue(absorbs)
            self.widgets.shieldBarR:Show()
            if overshieldEnabled and isClamped ~= nil then
                local glow = self.widgets.overShieldGlowR
                if glow.SetAlphaFromBoolean then
                    glow:Show()
                    glow:SetAlphaFromBoolean(isClamped, 1, 0)
                elseif F.IsValueNonSecret(isClamped) and isClamped then
                    glow:Show()
                else
                    glow:Hide()
                end
            else
                self.widgets.overShieldGlowR:Hide()
            end
            self.widgets.overShieldGlow:Hide()
        else
            self.widgets.shieldBar:SetMinMaxValues(0, healthMax)
            self.widgets.shieldBar:SetValue(absorbs)
            self.widgets.shieldBar:Show()
            if overshieldEnabled and isClamped ~= nil then
                local glow = self.widgets.overShieldGlow
                if glow.SetAlphaFromBoolean then
                    glow:Show()
                    glow:SetAlphaFromBoolean(isClamped, 1, 0)
                elseif F.IsValueNonSecret(isClamped) and isClamped then
                    glow:Show()
                else
                    glow:Hide()
                end
            else
                self.widgets.overShieldGlow:Hide()
            end
            self.widgets.shieldBarR:Hide()
            self.widgets.overShieldGlowR:Hide()
        end

        -- Update shield indicator (user-configurable indicator on top of health bar)
        if enabledIndicators["shieldBar"] then
            local indBar = self.indicators.shieldBar
            if indicatorBooleans["shieldBar"] then
                -- onlyShowOvershields: can't compute overshield from secrets, hide indicator
                -- TODO: Use a Curve to detect overshield (absorbs + health > maxHealth)
                indBar:Hide()
            else
                -- SetAbsorbs anchors to health bar and uses StatusBar fill for proportioning
                indBar:Show()
                indBar:SetAbsorbs(absorbs, healthMax)
            end
        else
            self.indicators.shieldBar:Hide()
        end
        return
    end

    -- CLASSIC/PRE-MIDNIGHT PATH: original logic
    local unit = self.states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self)
    end

    local shieldBar = self.widgets.shieldBar
    local _ta = self.states.totalAbsorbs
    local totalAbsorbs = (_ta == nil) and 0 or _ta
    local healthMax = self.states.healthMax
    local health = self.states.health

    -- Check if values are secret (12.0+ combat)
    local isSecret = F.HasAnySecretValues(totalAbsorbs, healthMax, health)

    if isSecret then
        -- Secret path: use StatusBar min/max approach (C-level handles secrets)
        -- Set size to match health bar for correct proportions
        if self.orientation == "horizontal" then
            shieldBar:SetWidth(self.widgets.healthBar:GetWidth())
        else
            shieldBar:SetHeight(self.widgets.healthBar:GetHeight())
        end

        -- 12.0+: calculator returns potentially secret values, passed to C-level StatusBar APIs
        local calc = self.widgets.healPredictionCalculator
        local absorbAmt, isClamped
        if calc and UnitGetDetailedHealPrediction then
            if UnitExists(unit) then
                UnitGetDetailedHealPrediction(unit, nil, calc)
            end
            if calc.GetDamageAbsorbs then
                absorbAmt, isClamped = calc:GetDamageAbsorbs()
            end
        end
        local displayAbsorbs = (absorbAmt == nil) and totalAbsorbs or absorbAmt

        if shieldEnabled then
            shieldBar:SetMinMaxValues(0, healthMax)
            shieldBar:SetValue(displayAbsorbs)
            shieldBar:Show()
        else
            shieldBar:Hide()
        end

        -- Overshield glow: use SetAlphaFromBoolean for secret bool support
        if overshieldEnabled and isClamped ~= nil then
            local glow = self.widgets.overShieldGlow
            if glow.SetAlphaFromBoolean then
                glow:Show()
                glow:SetAlphaFromBoolean(isClamped, 1, 0)
            else
                if F.IsValueNonSecret(isClamped) and isClamped then
                    glow:Show()
                else
                    glow:Hide()
                end
            end
        else
            self.widgets.overShieldGlow:Hide()
        end
        self.widgets.shieldBarR:Hide()
        self.widgets.overShieldGlowR:Hide()

        -- Indicator: StatusBar-based, C-level handles secret values
        if enabledIndicators["shieldBar"] then
            -- Size the indicator to match health bar
            local indBar = self.indicators.shieldBar
            if self.orientation == "horizontal" then
                indBar:SetWidth(self.widgets.healthBar:GetWidth())
            else
                indBar:SetHeight(self.widgets.healthBar:GetHeight())
            end
            indBar:SetAbsorbs(displayAbsorbs, healthMax)
            indBar:Show()
        else
            self.indicators.shieldBar:Hide()
        end
    else
        -- Normal path: Lua arithmetic is safe (non-secret values)
        if totalAbsorbs > 0 then
            local shieldPercent = totalAbsorbs / healthMax

            -- Indicator (percentage-based overlay)
            if enabledIndicators["shieldBar"] then
                if indicatorBooleans["shieldBar"] then
                    -- onlyShowOvershields
                    local overshieldPercent = (totalAbsorbs + health - healthMax) / healthMax
                    if overshieldPercent > 0 then
                        self.indicators.shieldBar:Show()
                        self.indicators.shieldBar:SetPercent(overshieldPercent)
                    else
                        self.indicators.shieldBar:Hide()
                    end
                else
                    self.indicators.shieldBar:Show()
                    self.indicators.shieldBar:SetPercent(shieldPercent)
                end
            else
                self.indicators.shieldBar:Hide()
            end

            -- Widget shield bar (StatusBar)
            if shieldEnabled then
                -- Set size to match health bar
                if self.orientation == "horizontal" then
                    shieldBar:SetWidth(self.widgets.healthBar:GetWidth())
                else
                    shieldBar:SetHeight(self.widgets.healthBar:GetHeight())
                end
                shieldBar:SetMinMaxValues(0, healthMax)
                shieldBar:SetValue(totalAbsorbs)
                shieldBar:Show()
            else
                shieldBar:Hide()
            end

            -- Overshield glow
            local healthPercent = self.states.healthPercent
            if shieldPercent + healthPercent > 1 then
                if overshieldReverseFillEnabled then
                    local p = shieldPercent + healthPercent - 1
                    if p > healthPercent then p = healthPercent end
                    local barSize = (self.orientation == "horizontal")
                        and self.widgets.healthBar:GetWidth()
                        or self.widgets.healthBar:GetHeight()
                    local shieldBarR = self.widgets.shieldBarR
                    if self.orientation == "horizontal" then
                        shieldBarR:SetWidth(p * barSize)
                    else
                        shieldBarR:SetHeight(p * barSize)
                    end
                    shieldBarR:Show()
                    if overshieldEnabled then
                        self.widgets.overShieldGlowR:Show()
                    else
                        self.widgets.overShieldGlowR:Hide()
                    end
                    self.widgets.overShieldGlow:Hide()
                else
                    if overshieldEnabled then
                        self.widgets.overShieldGlow:Show()
                    else
                        self.widgets.overShieldGlow:Hide()
                    end
                    self.widgets.shieldBarR:Hide()
                    self.widgets.overShieldGlowR:Hide()
                end
            else
                self.widgets.overShieldGlow:Hide()
                self.widgets.shieldBarR:Hide()
                self.widgets.overShieldGlowR:Hide()
            end
        else
            self.indicators.shieldBar:Hide()
            shieldBar:Hide()
            self.widgets.overShieldGlow:Hide()
            self.widgets.shieldBarR:Hide()
            self.widgets.overShieldGlowR:Hide()
        end
    end
end

local function UnitButton_UpdateHealAbsorbs(self, skipStateUpdates)
    if Cell.isMidnight and self.widgets.healthCalculator then
        -- MIDNIGHT PATH: use calculator secret values
        if not absorbEnabled then
            self.widgets.absorbsBar:Hide()
            self.widgets.overAbsorbGlow:Hide()
            return
        end
        local unit = self.states.displayedUnit
        if not unit then return end
        -- Skip redundant calculator refresh when called from UNIT_HEALTH chain
        -- (UpdateHealthStates already populated it).
        if not skipStateUpdates then
            UnitButton_UpdateCalculator(self)
        end
        local healAbsorbs = self.widgets.healthCalculator:GetHealAbsorbs()
        self.widgets.absorbsBar:SetValue(healAbsorbs)
        self.widgets.absorbsBar:Show()
        return
    end

    -- CLASSIC/PRE-MIDNIGHT PATH: original logic
    if not absorbEnabled then
        self.widgets.absorbsBar:Hide()
        self.widgets.overAbsorbGlow:Hide()
        return
    end

    local unit = self.states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self)
    end

    local absorbsBar = self.widgets.absorbsBar
    if absorbInvertColor then
        local r, g, b = F.InvertColor(self.widgets.healthBar:GetStatusBarColor())
        absorbsBar:SetStatusBarColor(r, g, b)
        absorbsBar.overAbsorbGlow:SetVertexColor(r, g, b)
    end

    -- 12.0+: calculator returns potentially secret values, passed to C-level StatusBar APIs
    local calc = self.widgets.healPredictionCalculator
    local healAbsorbAmt, isClamped
    if calc and UnitGetDetailedHealPrediction then
        if UnitExists(unit) then
            UnitGetDetailedHealPrediction(unit, nil, calc)
        end
        if calc.GetHealAbsorbs then
            healAbsorbAmt, isClamped = calc:GetHealAbsorbs()
        end
    end

    local _healAbs = (healAbsorbAmt == nil) and self.states.healAbsorbs or healAbsorbAmt
    local displayAbsorbs = (_healAbs == nil) and 0 or _healAbs
    absorbsBar:SetMinMaxValues(0, self.states.health)
    absorbsBar:SetValue(displayAbsorbs)
    absorbsBar:Show()

    -- Over-absorb glow using SetAlphaFromBoolean for secret bool support
    local glow = self.widgets.overAbsorbGlow
    if isClamped ~= nil then
        if SetAlphaFromBoolean then
            glow:Show()
            SetAlphaFromBoolean(glow, isClamped, 1, 0)
        else
            if F.IsValueNonSecret(isClamped) and isClamped then
                glow:Show()
            else
                glow:Hide()
            end
        end
    else
        -- No isClamped available: compare displayAbsorbs to health when non-secret
        local showGlow = F.IsValueNonSecret(displayAbsorbs) and displayAbsorbs and displayAbsorbs > self.states.health
        if showGlow then
            glow:Show()
        else
            glow:Hide()
        end
    end
end

local function UnitButton_UpdateThreat(self)
    local unit = self.states.displayedUnit
    if not unit or not UnitExists(unit) then return end

    local status = UnitThreatSituation(unit)
    if status and status >= 1 then
        if enabledIndicators["aggroBlink"] then
            self.indicators.aggroBlink:ShowAggro(GetThreatStatusColor(status))
        end
        if enabledIndicators["aggroBorder"] then
            self.indicators.aggroBorder:ShowAggro(GetThreatStatusColor(status))
        end
    else
        self.indicators.aggroBlink:Hide()
        self.indicators.aggroBorder:Hide()
    end
end

local function UnitButton_UpdateThreatBar(self)
    if not enabledIndicators["aggroBar"] then
        self.indicators.aggroBar:Hide()
        return
    end

    local unit = self.states.displayedUnit
    if not unit or not UnitExists(unit) then return end

    -- isTanking, status, scaledPercentage, rawPercentage, threatValue = UnitDetailedThreatSituation(unit, mobUnit)
    local _, status, scaledPercentage, rawPercentage = UnitDetailedThreatSituation(unit, "target")
    if status then
        self.indicators.aggroBar:Show()
        self.indicators.aggroBar:SetSmoothedValue(scaledPercentage)
        self.indicators.aggroBar:SetStatusBarColor(GetThreatStatusColor(status))
    else
        self.indicators.aggroBar:Hide()
    end
end

local function UnitButton_UpdateCombatIcon(self)
    if not enabledIndicators["combatIcon"] then return end

    local unit = self.states.displayedUnit
    if not unit then return end

    if not (indicatorBooleans["combatIcon"] and InCombatLockdown()) and UnitAffectingCombat(unit) then
        self.indicators.combatIcon:Show()
    else
        self.indicators.combatIcon:Hide()
    end
end

-- UNIT_IN_RANGE_UPDATE: unit, inRange
local IsInRange = F.IsInRange
local function UnitButton_UpdateInRange(self, ir)
    local unit = self.states.displayedUnit
    if not unit then return end

    local inRange = IsInRange(unit)
    -- Nil-safety: if IsInRange errors (e.g. secret value issue), default to true
    -- so frames don't grey out incorrectly
    if inRange == nil then inRange = true end

    self.states.inRange = inRange
    if Cell.loaded then
        if self.states.inRange ~= self.states.wasInRange then
            if inRange then
                if CELL_FADE_OUT_HEALTH_PERCENT then
                    if Cell.isMidnight and self.widgets and self.widgets.healthCalculator then
                        -- Midnight: use Curve-based fade (secret-safe)
                        RebuildFadeOutHealthCurve()
                        if fadeOutHealthCurve then
                            local targetAlpha = self.widgets.healthCalculator:EvaluateCurrentHealthPercent(fadeOutHealthCurve)
                            self:SetAlpha(targetAlpha)
                        else
                            A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
                        end
                    elseif not self.states.healthPercent or self.states.healthPercent < CELL_FADE_OUT_HEALTH_PERCENT then
                        A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
                    else
                        A.FrameFadeOut(self, 0.25, self:GetAlpha(), CellDB["appearance"]["outOfRangeAlpha"])
                    end
                else
                    A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
                end
            else
                A.FrameFadeOut(self, 0.25, self:GetAlpha(), CellDB["appearance"]["outOfRangeAlpha"])
            end
        end
        self.states.wasInRange = inRange
        -- self:SetAlpha(inRange and 1 or CellDB["appearance"]["outOfRangeAlpha"])
    end
end

local function UnitButton_UpdateVehicleStatus(self)
    local unit = self.states.unit
    if not unit then return end

    if UnitHasVehicleUI(unit) then -- or UnitInVehicle(unit) or UnitUsingVehicle(unit) then
        self.states.inVehicle = true
        if unit == "player" then
            self.states.displayedUnit = "vehicle"
        else
            -- local prefix, id, suffix = strmatch(unit, "([^%d]+)([%d]*)(.*)")
            local prefix, id = strmatch(unit, "([^%d]+)([%d]*)")
            self.states.displayedUnit = prefix .. "pet" .. (id or "")
        end
        self.indicators.nameText:UpdateVehicleName()
    else
        self.states.inVehicle = nil
        self.states.displayedUnit = self.states.unit
        self.indicators.nameText.vehicle:SetText("")
    end
    if I.UpdateHealersAuraDisplayUnit then
        I.UpdateHealersAuraDisplayUnit(self)
    end
    if I.UpdateCustomAuraDisplays then
        I.UpdateCustomAuraDisplays(self)
    end
    if I.UpdateCombatAuraDisplays then
        I.UpdateCombatAuraDisplays(self)
    end
end

UnitButton_UpdateStatusText = function(self)
    local statusText = self.indicators.statusText
    if not enabledIndicators["statusText"] then
        -- statusText:Hide()
        statusText:SetStatus()
        return
    end

    local unit = self.states.unit
    if not unit then return end

    self.states.guid = UnitGUID(unit) -- update!
    if not self.states.guid then return end

    if not UnitIsConnected(unit) and UnitIsPlayer(unit) then
        statusText:Show()
        statusText:SetStatus("OFFLINE")
        statusText:ShowTimer()
    -- Midnight 12.0.0+: UnitIsAFK may return a secret boolean  -- skip on Midnight
    elseif not Cell.isMidnight and UnitIsAFK(unit) then
        statusText:Show()
        statusText:SetStatus("AFK")
        statusText:ShowTimer()
    elseif UnitIsFeignDeath(unit) then
        statusText:Show()
        statusText:SetStatus("FEIGN")
        statusText:HideTimer(true)
    elseif UnitIsDeadOrGhost(unit) then
        statusText:Show()
        statusText:HideTimer(true)
        if UnitIsGhost(unit) then
            statusText:SetStatus("GHOST")
        else
            statusText:SetStatus("DEAD")
        end
    elseif C_IncomingSummon.HasIncomingSummon(unit) then
        statusText:Show()
        statusText:HideTimer()
        local status = C_IncomingSummon.IncomingSummonStatus(unit)
        if status == Enum.SummonStatus.Pending then
            statusText:SetStatus("PENDING")
        else
            if status == Enum.SummonStatus.Accepted then
                statusText:SetStatus("ACCEPTED")
            elseif status == Enum.SummonStatus.Declined then
                statusText:SetStatus("DECLINED")
            end
            C_Timer.After(6, function() UnitButton_UpdateStatusText(self) end)
        end
    elseif statusText:GetStatus() == "DRINKING" then
        -- update colors
        statusText:Show()
        statusText:SetStatus("DRINKING")
    else
        -- statusText:Hide()
        statusText:HideTimer(true)
        statusText:SetStatus()
    end
end

local function UnitButton_UpdateName(self)
    local unit = self.states.unit
    if not unit then return end

    -- unit name may be a secret string in instances on Midnight 12.0.0+
    -- FontString:SetText() accepts secrets, so display works without change
    -- However, any NAME COMPARISONS (name == something) will error if name is secret
    self.states.name = UnitName(unit)
    self.states.fullName = F.UnitFullName(unit)
    local resolvedClass = F.ResolveUnitClassFile(unit, self.states.class)
    if resolvedClass then
        self.states.class = resolvedClass
        self.states._classGuid = UnitGUID(unit)
    else
        local classFile = UnitClassBase(unit)
        if classFile and F.IsValueNonSecret(classFile) then
            self.states.class = classFile
            self.states._classGuid = UnitGUID(unit)
        end
    end
    self.states.guid = UnitGUID(unit)
    self.states.isPlayer = UnitIsPlayer(unit)

    self.indicators.nameText:UpdateName()
end

UnitButton_UpdateNameTextColor = function(self)
    local unit = self.states.unit
    if not unit then return end

    if enabledIndicators["nameText"] then
        local connected = UnitIsConnected(unit)
        local charmed = UnitIsCharmed(unit)
        local charmedPlayer = (UnitIsPlayer(unit) or UnitInPartyIsAI(unit))
            and F.IsValueNonSecret(charmed) and charmed
        if indicatorColors["nameText"][1] == "class_color"
            or (F.IsValueNonSecret(connected) and not connected)
            or charmedPlayer
            or self.states.inVehicle then
            self.indicators.nameText:SetColor(F.GetUnitClassColor(unit))
        else
            self.indicators.nameText:SetColor(unpack(indicatorColors["nameText"][2]))
        end
    end
end

UnitButton_UpdateHealthTextColor = function(self)
    local unit = self.states.unit
    if not unit then return end

    if enabledIndicators["healthText"] then
        self.indicators.healthText:SetColor(F.GetUnitClassColor(unit))
    end
end

UnitButton_UpdateHealthColor = function(self)
    local unit = self.states.unit
    if not unit then return end

    -- Secret-safe class resolve (UnitClass can be opaque in combat on Midnight).
    -- Keep last known class for the same GUID so bars don't pick up a recycled frame's color.
    local guid = UnitGUID(unit)
    local resolved = F.ResolveUnitClassFile(unit)
    if resolved then
        self.states.class = resolved
        self.states._classGuid = guid
    elseif guid and F.IsValueNonSecret(guid) and self.states._classGuid == guid and self.states.class then
        -- keep cached class for this unit
    else
        local fallback = UnitClassBase(unit)
        if fallback and F.IsValueNonSecret(fallback) then
            self.states.class = fallback
            self.states._classGuid = guid
        end
    end

    local barR, barG, barB
    local lossR, lossG, lossB
    local barA, lossA = 1, 1

    if Cell.loaded then
        barA =  CellDB["appearance"]["barAlpha"]
        lossA =  CellDB["appearance"]["lossAlpha"]
    end

    -- MIDNIGHT PATH: use UnitHealthPercent + color curves for secret-safe gradient evaluation
    if Cell.isMidnight and self.widgets.healthBarColorCurve and UnitHealthPercent then
        local useCurve = false

        if UnitIsPlayer(unit) or UnitInPartyIsAI(unit) then
            local connected = UnitIsConnected(unit)
            local charmed = UnitIsCharmed(unit)
            if F.IsValueNonSecret(connected) and not connected then
                barR, barG, barB = 0.4, 0.4, 0.4
                lossR, lossG, lossB = 0.4, 0.4, 0.4
            elseif F.IsValueNonSecret(charmed) and charmed then
                barR, barG, barB, barA = 0.5, 0, 1, 1
                lossR, lossG, lossB, lossA = barR*0.2, barG*0.2, barB*0.2, 1
            else
                useCurve = true
            end
        elseif F.IsPet(self.states.guid, self.states.unit) then
            useCurve = true
        else
            useCurve = true
        end

        if useCurve then
            -- Rebuild curves (handles class color per unit + current settings)
            B.UpdateHealthColorCurve(self)
            -- UnitHealthPercent(unit, true, curve) evaluates health% against the curve
            -- entirely at the C level — secret-safe, returns a ColorMixin
            local barColor = UnitHealthPercent(unit, true, self.widgets.healthBarColorCurve)
            local lossColor = UnitHealthPercent(unit, true, self.widgets.healthLossColorCurve)
            if barColor then
                barR, barG, barB = barColor:GetRGB()
            end
            if lossColor then
                lossR, lossG, lossB = lossColor:GetRGB()
            end
            -- fullColor override: check if at full health (non-secret path)
            if Cell.vars.useFullColor then
                local health = UnitHealth(unit)
                local healthMax = UnitHealthMax(unit)
                if not F.HasAnySecretValues(health, healthMax) and healthMax > 0 and health == healthMax then
                    barR = CellDB["appearance"]["fullColor"][2][1]
                    barG = CellDB["appearance"]["fullColor"][2][2]
                    barB = CellDB["appearance"]["fullColor"][2][3]
                end
            end
            -- deathColor override
            if (self.states.isDeadOrGhost or self.states.isDead) and Cell.vars.useDeathColor then
                lossR = CellDB["appearance"]["deathColor"][2][1]
                lossG = CellDB["appearance"]["deathColor"][2][2]
                lossB = CellDB["appearance"]["deathColor"][2][3]
            end
        end

        -- Apply colors — SetStatusBarColor and SetVertexColor accept secret ColorMixin results
        if barR then
            self.widgets.healthBar:SetStatusBarColor(barR, barG, barB, barA)
        end
        if lossR then
            self.widgets.healthBarLoss:SetVertexColor(lossR, lossG, lossB, lossA)
        end
        -- Incoming heal color
        if Cell.loaded and CellDB["appearance"]["healPrediction"][2] then
            self.widgets.incomingHeal:SetStatusBarColor(CellDB["appearance"]["healPrediction"][3][1], CellDB["appearance"]["healPrediction"][3][2], CellDB["appearance"]["healPrediction"][3][3], CellDB["appearance"]["healPrediction"][3][4])
        elseif barR then
            self.widgets.incomingHeal:SetStatusBarColor(barR, barG, barB, 0.4)
        end
        return
    end

    -- PRE-MIDNIGHT PATH: original Lua-based color logic
    if UnitIsPlayer(unit) or UnitInPartyIsAI(unit) then -- player
        if not UnitIsConnected(unit) then
            barR, barG, barB = 0.4, 0.4, 0.4
            lossR, lossG, lossB = 0.4, 0.4, 0.4
        elseif UnitIsCharmed(unit) then
            barR, barG, barB, barA = 0.5, 0, 1, 1
            lossR, lossG, lossB, lossA = barR*0.2, barG*0.2, barB*0.2, 1
        elseif self.states.inVehicle then
            barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(self.states.healthPercent, self.states.isDeadOrGhost or self.states.isDead, 0, 1, 0.2)
        else
            barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(self.states.healthPercent, self.states.isDeadOrGhost or self.states.isDead, F.GetClassColor(self.states.class))
        end
    elseif F.IsPet(self.states.guid, self.states.unit) then -- pet
        barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(self.states.healthPercent, self.states.isDeadOrGhost or self.states.isDead, 0.5, 0.5, 1)
    else -- npc
        barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(self.states.healthPercent, self.states.isDeadOrGhost or self.states.isDead, 0, 1, 0.2)
    end

    self.widgets.healthBar:SetStatusBarColor(barR, barG, barB, barA)
    self.widgets.healthBarLoss:SetVertexColor(lossR, lossG, lossB, lossA)

    -- Texture on pre-Midnight: use SetVertexColor
    if Cell.loaded and CellDB["appearance"]["healPrediction"][2] then
        self.widgets.incomingHeal:SetVertexColor(CellDB["appearance"]["healPrediction"][3][1], CellDB["appearance"]["healPrediction"][3][2], CellDB["appearance"]["healPrediction"][3][3], CellDB["appearance"]["healPrediction"][3][4])
    else
        self.widgets.incomingHeal:SetVertexColor(barR, barG, barB, 0.4)
    end
end

-- Export funciones de seg 2 para seg 3
Cell_._updateHealthColor = UnitButton_UpdateHealthColor
Cell_._updateHealthTextColor = UnitButton_UpdateHealthTextColor
Cell_._updatePowerMax = UnitButton_UpdatePowerMax
Cell_._updatePower = UnitButton_UpdatePower
Cell_._updatePowerType = UnitButton_UpdatePowerType
Cell_._updatePowerText = UnitButton_UpdatePowerText
Cell_._updatePowerTextColor = UnitButton_UpdatePowerTextColor
Cell_._updateNameTextColor = UnitButton_UpdateNameTextColor
Cell_._updateName = UnitButton_UpdateName
Cell_._updateVehicleStatus = UnitButton_UpdateVehicleStatus
Cell_._updateHealthMax = UnitButton_UpdateHealthMax
Cell_._updateHealth = UnitButton_UpdateHealth
Cell_._updateHealPrediction = UnitButton_UpdateHealPrediction
Cell_._updateTarget = UnitButton_UpdateTarget
Cell_._updatePlayerRaidIcon = UnitButton_UpdatePlayerRaidIcon
Cell_._updateTargetRaidIcon = UnitButton_UpdateTargetRaidIcon
Cell_._updateReadyCheck = UnitButton_UpdateReadyCheck
Cell_._updateHealAbsorbs = UnitButton_UpdateHealAbsorbs
Cell_._updateInRange = UnitButton_UpdateInRange
Cell_._updateThreat = UnitButton_UpdateThreat
Cell_._updateThreatBar = UnitButton_UpdateThreatBar
Cell_._updatePowerStates = UnitButton_UpdatePowerStates
Cell_._rememberSecretHelpfulCast = RememberSecretHelpfulCast
Cell_._getRecentSecretHelpfulCastKind = GetRecentSecretHelpfulCastKind
Cell_._updateHealthStates = UnitButton_UpdateHealthStates
Cell_._finishReadyCheck = UnitButton_FinishReadyCheck
Cell_._shouldShowPowerBar = ShouldShowPowerBar
Cell_._hidePowerBar = HidePowerBar
Cell_._showPowerBar = ShowPowerBar
Cell_._updateCombatIcon = UnitButton_UpdateCombatIcon
Cell_._initAuraTables = InitAuraTables
Cell_._resetAuraTables = ResetAuraTables

end)(Cell)  -- end seg 2

-- =============================================================================
-- Seg 3: curvas de color, OnLoad, init
-- =============================================================================
;(function(Cell)  -- IIFE seg 3: 0 upvalues, ~62 locales

local Cell_ = Cell

-- Imports desde Cell (evitan que sean upvalues desde seg 1/2)
local L = Cell_.L
local F = Cell_.funcs
local I = Cell_.iFuncs
local B = Cell_.bFuncs
local U = Cell_.uFuncs
local P = Cell_.pixelPerfectFuncs
local A = Cell_.animations
local LGI = LibStub:GetLibrary("LibGroupInfo")

-- Import funciones de seg 2
local InitAuraTables = Cell_._initAuraTables
local ResetAuraTables = Cell_._resetAuraTables
local HidePowerBar = Cell_._hidePowerBar
local ShowPowerBar = Cell_._showPowerBar
local UnitButton_UpdateCombatIcon = Cell_._updateCombatIcon
local UnitButton_UpdateHealthStates = Cell_._updateHealthStates
local UnitButton_FinishReadyCheck = Cell_._finishReadyCheck
local RememberSecretHelpfulCast = Cell_._rememberSecretHelpfulCast
local UnitButton_UpdateHealthColor = Cell_._updateHealthColor
local UnitButton_UpdateHealthTextColor = Cell_._updateHealthTextColor
local UnitButton_UpdatePowerMax = Cell_._updatePowerMax
local UnitButton_UpdatePower = Cell_._updatePower
local UnitButton_UpdatePowerType = Cell_._updatePowerType
local UnitButton_UpdatePowerText = Cell_._updatePowerText
local UnitButton_UpdatePowerTextColor = Cell_._updatePowerTextColor
local UnitButton_UpdateNameTextColor = Cell_._updateNameTextColor
local UnitButton_UpdateName = Cell_._updateName
local UnitButton_UpdateVehicleStatus = Cell_._updateVehicleStatus
local UnitButton_UpdateHealthMax = Cell_._updateHealthMax
local UnitButton_UpdateHealth = Cell_._updateHealth
local UnitButton_UpdateHealPrediction = Cell_._updateHealPrediction
local UnitButton_UpdateTarget = Cell_._updateTarget
local UnitButton_UpdatePlayerRaidIcon = Cell_._updatePlayerRaidIcon
local UnitButton_UpdateTargetRaidIcon = Cell_._updateTargetRaidIcon
local UnitButton_UpdateReadyCheck = Cell_._updateReadyCheck
local UnitButton_UpdateHealAbsorbs = Cell_._updateHealAbsorbs
local UnitButton_UpdateInRange = Cell_._updateInRange
local UnitButton_UpdateThreat = Cell_._updateThreat
local UnitButton_UpdateThreatBar = Cell_._updateThreatBar
local UnitButton_UpdatePowerStates = Cell_._updatePowerStates
local ShouldShowPowerBar = Cell_._shouldShowPowerBar

-- Import vars desde seg 1
local enabledIndicators = Cell_._enabledIndicators
local indicatorNums = Cell_._indicatorNums

-- Import HandleBuff helpers (para Cell._hb)
local DoesAuraMatchExpectedBuff = Cell_._doesAuraMatchExpectedBuff
local UpdateAuraRefreshState = Cell_._updateAuraRefreshState
local GetRecentSecretHelpfulCastKind = Cell_._getRecentSecretHelpfulCastKind

-- Curve-based health color system (Midnight 12.0.0+)
do
    -- Builds a color curve from 3 color points + boundary settings.
    local function BuildThresholdCurve(curve, c1, c2, c3, lowBound, highBound, useGradient)
        curve:ClearPoints()
        lowBound = lowBound or 0.05
        highBound = highBound or 0.95

        local col1 = CreateColor(c1[1], c1[2], c1[3], 1)
        local col2 = CreateColor(c2[1], c2[2], c2[3], 1)
        local col3 = CreateColor(c3[1], c3[2], c3[3], 1)

        if useGradient then
            curve:SetType(Enum.LuaCurveType.Linear)
            curve:AddPoint(0.0, col1)
            curve:AddPoint(lowBound, col1)
            local mid = (lowBound + highBound) / 2
            curve:AddPoint(mid, col2)
            curve:AddPoint(highBound, col3)
            curve:AddPoint(1.0, col3)
        else
            curve:SetType(Enum.LuaCurveType.Linear)
            local eps = 0.001
            curve:AddPoint(0.0, col1)
            if lowBound > eps then
                curve:AddPoint(lowBound - eps, col1)
            end
            curve:AddPoint(lowBound + eps, col2)
            if highBound - lowBound > 2 * eps then
                curve:AddPoint(highBound - eps, col2)
            end
            curve:AddPoint(highBound + eps, col3)
            curve:AddPoint(1.0, col3)
        end
    end

    local function BuildFlatCurve(curve, r, g, b)
        curve:ClearPoints()
        curve:SetType(Enum.LuaCurveType.Linear)
        local col = CreateColor(r, g, b, 1)
        curve:AddPoint(0.0, col)
        curve:AddPoint(1.0, col)
    end

    -- Configures the health color curves for a button (Midnight 12.0.0+)
    -- Builds curves from user settings so UnitHealthPercent(unit, true, curve)
    -- can evaluate gradient colors at the C level.
    function B.UpdateHealthColorCurve(button)
        if not Cell.isMidnight then return end
        if not button.widgets.healthBarColorCurve then return end
        if not Cell.loaded then return end

        local unit = button.states.displayedUnit or button.states.unit
        local barCurve = button.widgets.healthBarColorCurve
        local lossCurve = button.widgets.healthLossColorCurve

        local class = F.ResolveUnitClassFile(unit, button.states.class) or button.states.class or Cell.vars.playerClass
        if class and F.IsValueNonSecret(class) then
            button.states.class = class
        end
        local cr, cg, cb = F.GetClassColor(class)

        -- Build bar color curve
        local barMode = CellDB["appearance"]["barColor"][1]
        if barMode == "threshold1" then
            local c = CellDB["appearance"]["colorThresholds"]
            BuildThresholdCurve(barCurve, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif barMode == "threshold2" then
            local c = CellDB["appearance"]["colorThresholds"]
            BuildThresholdCurve(barCurve, c[1], c[2], {cr, cg, cb}, c[4], c[5], c[6])
        elseif barMode == "threshold3" then
            local c = CellDB["appearance"]["colorThresholds"]
            BuildThresholdCurve(barCurve, c[1], c[2], {cr*0.2, cg*0.2, cb*0.2}, c[4], c[5], c[6])
        elseif barMode == "class_color" then
            BuildFlatCurve(barCurve, cr, cg, cb)
        elseif barMode == "class_color_dark" then
            BuildFlatCurve(barCurve, cr*0.2, cg*0.2, cb*0.2)
        else
            local cc = CellDB["appearance"]["barColor"][2]
            BuildFlatCurve(barCurve, cc[1], cc[2], cc[3])
        end

        -- Build loss color curve
        local lossMode = CellDB["appearance"]["lossColor"][1]
        if lossMode == "threshold1" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            BuildThresholdCurve(lossCurve, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif lossMode == "threshold2" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            BuildThresholdCurve(lossCurve, {cr, cg, cb}, c[2], c[3], c[4], c[5], c[6])
        elseif lossMode == "threshold3" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            BuildThresholdCurve(lossCurve, {cr*0.2, cg*0.2, cb*0.2}, c[2], c[3], c[4], c[5], c[6])
        elseif lossMode == "class_color" then
            BuildFlatCurve(lossCurve, cr, cg, cb)
        elseif lossMode == "class_color_dark" then
            BuildFlatCurve(lossCurve, cr*0.2, cg*0.2, cb*0.2)
        else
            local cc = CellDB["appearance"]["lossColor"][2]
            BuildFlatCurve(lossCurve, cc[1], cc[2], cc[3])
        end
    end
end

-------------------------------------------------
-- translit names
-------------------------------------------------
Cell.RegisterCallback("TranslitNames", "UnitButton_TranslitNames", function()
    F.IterateAllUnitButtons(function(b)
        UnitButton_UpdateName(b)
    end, true)
end)

-------------------------------------------------
-- update all
-------------------------------------------------
local UnitButton_UpdateAll = function(self)
    if not self:IsVisible() then return end

    -- print(GetTime(), "UpdateAll", self:GetName())

    UnitButton_UpdateVehicleStatus(self)
    UnitButton_UpdateName(self)
    UnitButton_UpdateNameTextColor(self)
    UnitButton_UpdateHealthTextColor(self)
    UnitButton_UpdateHealthMax(self)
    UnitButton_UpdateHealth(self, nil, true)
    UnitButton_UpdateHealPrediction(self, true)
    UnitButton_UpdateStatusText(self)
    UnitButton_UpdateHealthColor(self)
    UnitButton_UpdateTarget(self)
    UnitButton_UpdatePlayerRaidIcon(self)
    UnitButton_UpdateTargetRaidIcon(self)
    UnitButton_UpdateShieldAbsorbs(self, true)
    UnitButton_UpdateHealAbsorbs(self, true)
    UnitButton_UpdateInRange(self)
    UnitButton_UpdateRole(self)
    UnitButton_UpdateLeader(self)
    UnitButton_UpdateReadyCheck(self)
    UnitButton_UpdateThreat(self)
    UnitButton_UpdateThreatBar(self)
    -- UnitButton_UpdateStatusIcon(self)
    I.UpdateStatusIcon_Resurrection(self)

    UnitButton_UpdatePowerStates(self)
    if Cell.loaded then
        if self._powerUpdateRequired then
            self._powerUpdateRequired = nil

            self._shouldShowPowerText = ShouldShowPowerText(self)
            self._shouldShowPowerBar = ShouldShowPowerBar(self)
            CheckPowerEventRegistration(self)

            if self._shouldShowPowerText then
                UnitButton_UpdatePowerTextColor(self)
                UnitButton_UpdatePowerText(self)
            else
                self.indicators.powerText:Hide()
            end

            if self._shouldShowPowerBar then
                ShowPowerBar(self)
            else
                HidePowerBar(self)
            end

        end
    end

    UnitButton_UpdateAuras(self)
end

-------------------------------------------------
-- unit button events
-------------------------------------------------
local function UnitButton_RegisterEvents(self)
    -- self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    self:RegisterEvent("UNIT_HEALTH")
    self:RegisterEvent("UNIT_MAXHEALTH")

    self:RegisterEvent("UNIT_POWER_FREQUENT")
    self:RegisterEvent("UNIT_MAXPOWER")
    self:RegisterEvent("UNIT_DISPLAYPOWER")

    self:RegisterEvent("UNIT_AURA")
    if Cell.isMidnight then
        self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end

    self:RegisterEvent("UNIT_HEAL_PREDICTION")
    self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    self:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")

    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    self:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    self:RegisterEvent("UNIT_ENTERED_VEHICLE")
    self:RegisterEvent("UNIT_EXITED_VEHICLE")

    self:RegisterEvent("INCOMING_SUMMON_CHANGED")
    self:RegisterEvent("UNIT_IN_RANGE_UPDATE")
    self:RegisterEvent("UNIT_FLAGS") -- afk
    self:RegisterEvent("UNIT_FACTION") -- mind control

    self:RegisterEvent("UNIT_CONNECTION") -- offline
    self:RegisterEvent("PLAYER_FLAGS_CHANGED") -- afk
    self:RegisterEvent("UNIT_NAME_UPDATE") -- unknown target
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA") --? update status text

    -- self:RegisterEvent("PARTY_LEADER_CHANGED") -- GROUP_ROSTER_UPDATE
    -- self:RegisterEvent("PLAYER_ROLES_ASSIGNED") -- GROUP_ROSTER_UPDATE
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")

    self:RegisterEvent("PLAYER_TARGET_CHANGED")

    if Cell.loaded then
        if enabledIndicators["playerRaidIcon"] then
            self:RegisterEvent("RAID_TARGET_UPDATE")
        end
        if enabledIndicators["targetRaidIcon"] then
            self:RegisterEvent("UNIT_TARGET")
        end
        if enabledIndicators["readyCheckIcon"] then
            self:RegisterEvent("READY_CHECK")
            self:RegisterEvent("READY_CHECK_FINISHED")
            self:RegisterEvent("READY_CHECK_CONFIRM")
        end
    else
        self:RegisterEvent("RAID_TARGET_UPDATE")
        self:RegisterEvent("UNIT_TARGET")
        self:RegisterEvent("READY_CHECK")
        self:RegisterEvent("READY_CHECK_FINISHED")
        self:RegisterEvent("READY_CHECK_CONFIRM")
    end

    -- self:RegisterEvent("UNIT_PHASE") -- warmode, traditional sources of phasing such as progress through quest chains
    -- self:RegisterEvent("PARTY_MEMBER_DISABLE")
    -- self:RegisterEvent("PARTY_MEMBER_ENABLE")
    -- self:RegisterEvent("INCOMING_RESURRECT_CHANGED")

    -- self:RegisterEvent("VOICE_CHAT_CHANNEL_ACTIVATED")
    -- self:RegisterEvent("VOICE_CHAT_CHANNEL_DEACTIVATED")

    -- self:RegisterEvent("UNIT_PET")
    self:RegisterEvent("UNIT_PORTRAIT_UPDATE") -- pet summoned far away

    --! OnShow时立即执行，但UpdateIndicators可能并未执行完毕，导致在ResetCustomIndicators过程中指示器发生变化，进而报错
    -- OnShow fires immediately but UpdateIndicators may not have completed yet,
    -- so indicators can change during ResetCustomIndicators and cause errors.
    -- pcall prevents one frame's error from breaking all other frames.
    local success, result = pcall(UnitButton_UpdateAll, self)
    if not success then
        F.Debug("UnitButton_UpdateAll |cffff0000FAILED:|r", self:GetName(), result)
    end
end

local function UnitButton_UnregisterEvents(self)
    self:UnregisterAllEvents()
end

local function UnitButton_OnEvent(self, event, unit, arg, arg2, ...)
    if unit and (self.states.displayedUnit == unit or self.states.unit == unit) then
        if  event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" or event == "UNIT_CONNECTION" then
            self._updateRequired = 1
            self._powerUpdateRequired = 1

        elseif event == "UNIT_NAME_UPDATE" then
            UnitButton_UpdateName(self)
            UnitButton_UpdateNameTextColor(self)
            UnitButton_UpdateHealthColor(self)
            UnitButton_UpdateHealthTextColor(self)
            UnitButton_UpdatePowerTextColor(self)

        elseif event == "UNIT_MAXHEALTH" then
            UnitButton_UpdateHealthMax(self)
            UnitButton_UpdateHealth(self, nil, true)
            UnitButton_UpdateHealPrediction(self, true)
            UnitButton_UpdateShieldAbsorbs(self, true)
            UnitButton_UpdateHealAbsorbs(self, true)

        elseif event == "UNIT_HEALTH" then
            UnitButton_UpdateHealth(self)
            UnitButton_UpdateHealPrediction(self, true)
            UnitButton_UpdateShieldAbsorbs(self, true)
            UnitButton_UpdateHealAbsorbs(self, true)
            -- UnitButton_UpdateStatusText(self)

        elseif event == "UNIT_HEAL_PREDICTION" then
            UnitButton_UpdateHealPrediction(self)

        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            UnitButton_UpdateShieldAbsorbs(self)
            -- Refresh health text so shield component updates immediately
            if enabledIndicators["healthText"] then
                UnitButton_UpdateHealthStates(self)
            end

        elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            UnitButton_UpdateHealAbsorbs(self)
            -- Refresh health text so healAbsorb component updates immediately
            if enabledIndicators["healthText"] then
                UnitButton_UpdateHealthStates(self)
            end

        elseif event == "UNIT_MAXPOWER" then
            UnitButton_UpdatePowerStates(self)
            UnitButton_UpdatePowerMax(self)
            UnitButton_UpdatePower(self)
            UnitButton_UpdatePowerText(self)

        elseif event == "UNIT_POWER_FREQUENT" then
            UnitButton_UpdatePowerStates(self)
            UnitButton_UpdatePower(self)
            UnitButton_UpdatePowerText(self)

        elseif event == "UNIT_DISPLAYPOWER" then
            UnitButton_UpdatePowerStates(self)
            UnitButton_UpdatePowerMax(self)
            UnitButton_UpdatePower(self)
            UnitButton_UpdatePowerType(self)
            UnitButton_UpdatePowerTextColor(self)
            UnitButton_UpdatePowerText(self)

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Midnight (12.0.0+): event, unit, spellID
            -- Pre-Midnight: event, unit, spellName, rank, lineID, spellID
            -- CRÍTICO: este evento se dispara para TODAS las unidades porque el
            -- frame lo registra sin filtro de unidad (line 4275). Sin el guard
            -- de castingUnit, los casts de CUALQUIER miembro de la raid trackean
            -- en TODOS los botones. Steps 2.5/3 encuentran casts de otros players
            -- y matchean auras no relacionadas (class buffs, Devotion Aura, CDs
            -- ofensivos, etc.) por timing.
            -- unit (2do parámetro del handler) = la unidad que castea, SIEMPRE es string
            -- plano del juego, incluso en Midnight. arg es spellName/spellID, NO unit.
            local castingUnit = unit
            if castingUnit ~= "player" then return end
            local spellID = arg2  -- Midnight: arg2 = spellID; Pre-Midnight: arg2 = spellName
            if not spellID or type(spellID) ~= "number" then
                spellID = select(5, ...)  -- Pre-Midnight: spellID es 5to vararg
            end
            if spellID and type(spellID) == "number" then
                RememberSecretHelpfulCast(self, spellID)
            end

        elseif event == "UNIT_AURA" then
            UnitButton_UpdateAuras(self, arg)

        elseif event == "UNIT_IN_RANGE_UPDATE" then
            UnitButton_UpdateInRange(self, arg)

        elseif event == "UNIT_TARGET" then
            UnitButton_UpdateTargetRaidIcon(self)

        elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FLAGS" or event == "INCOMING_SUMMON_CHANGED" then
            -- if CELL_SUMMON_ICONS_ENABLED then UnitButton_UpdateStatusIcon(self) end
            UnitButton_UpdateStatusText(self)

        elseif event == "UNIT_FACTION" then -- mind control
            UnitButton_UpdateNameTextColor(self)
            UnitButton_UpdateHealthColor(self)

        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            UnitButton_UpdateThreat(self)

        -- elseif event == "INCOMING_RESURRECT_CHANGED" or event == "UNIT_PHASE" or event == "PARTY_MEMBER_DISABLE" or event == "PARTY_MEMBER_ENABLE" then
            -- UnitButton_UpdateStatusIcon(self)

        elseif event == "READY_CHECK_CONFIRM" then
            UnitButton_UpdateReadyCheck(self)

        elseif event == "UNIT_PORTRAIT_UPDATE" then -- pet summoned far away
            if self.states.healthMax == 0 then
                self._updateRequired = 1
                self._powerUpdateRequired = 1
            end
        end

    else
        if event == "GROUP_ROSTER_UPDATE" then
            -- FIXME:
            -- if IsDelveInProgress() then
            --     self.__tickCount = 2
            --     self.__updateElapsed = 0.25
            -- else
                self._updateRequired = 1
                self._powerUpdateRequired = 1
            -- end

        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            UnitButton_UpdateLeader(self, event)
            if event == "PLAYER_REGEN_ENABLED" then
                -- 12.0+: secret values may linger briefly after combat ends.
                -- Immediate refresh + delayed retry to catch stale secrets.
                UnitButton_UpdateHealth(self)
                UnitButton_UpdateShieldAbsorbs(self)
                UnitButton_UpdateHealAbsorbs(self)
                UnitButton_UpdatePowerStates(self)
                UnitButton_UpdatePowerText(self)
                UnitButton_UpdateAuras(self)
                -- Delayed retry: values at full health/power won't get events
                local btn = self
                C_Timer.After(0.5, function()
                    if btn.states.displayedUnit then
                        UnitButton_UpdateHealth(btn)
                        UnitButton_UpdateShieldAbsorbs(btn)
                        UnitButton_UpdateHealAbsorbs(btn)
                        UnitButton_UpdatePowerStates(btn)
                        UnitButton_UpdatePowerText(btn)
                        UnitButton_UpdateAuras(btn)
                    end
                end)
            end

        elseif event == "PLAYER_TARGET_CHANGED" then
            UnitButton_UpdateTarget(self)
            UnitButton_UpdateThreatBar(self)
            if self:GetAttribute("updateOnTargetChanged") then
                UnitButton_UpdateAll(self)
            end

        elseif event == "UNIT_THREAT_LIST_UPDATE" then
            UnitButton_UpdateThreatBar(self)

        elseif event == "RAID_TARGET_UPDATE" then
            UnitButton_UpdatePlayerRaidIcon(self)
            UnitButton_UpdateTargetRaidIcon(self)

        elseif event == "READY_CHECK" then
            UnitButton_UpdateReadyCheck(self)

        elseif event == "READY_CHECK_FINISHED" then
            UnitButton_FinishReadyCheck(self)

        elseif event == "ZONE_CHANGED_NEW_AREA" then
            -- F.Debug("|cffbbbbbb=== ZONE_CHANGED_NEW_AREA ===")
            -- self._updateRequired = 1
            UnitButton_UpdateStatusText(self)

        -- elseif event == "VOICE_CHAT_CHANNEL_ACTIVATED" or event == "VOICE_CHAT_CHANNEL_DEACTIVATED" then
        -- 	VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED
        end
    end
end

local timer
local function EnterLeaveInstance()
    if timer then timer:Cancel() timer=nil end
    timer = C_Timer.NewTimer(1, function()
        F.Debug("|cffff1111*** EnterLeaveInstance:|r UnitButton_UpdateAll")
        F.IterateAllUnitButtons(UnitButton_UpdateAll, true)
        timer = nil
    end)
end
Cell.RegisterCallback("EnterInstance", "UnitButton_EnterInstance", EnterLeaveInstance)
Cell.RegisterCallback("LeaveInstance", "UnitButton_LeaveInstance", EnterLeaveInstance)

local function UnitButton_OnAttributeChanged(self, name, value)
    if name == "unit" then
        if not value or value ~= self.states.unit then
            -- FIX: Safe cleanup with secret key protection
            if self.__unitGuid then
                if not self.isSpotlight and F.IsValueNonSecret(self.__unitGuid) then
                    Cell.vars.guids[self.__unitGuid] = nil
                end
                self.__unitGuid = nil
            end

            if self.__unitName then
                if not self.isSpotlight and F.IsValueNonSecret(self.__unitName) then
                    Cell.vars.names[self.__unitName] = nil
                end
                self.__unitName = nil
            end

            self._recentSecretHelpfulCastKind = nil
            self._recentSecretHelpfulCastAt = nil
            self._recentSecretHelpfulCastSpellId = nil
            wipe(self.states)

            if self.widgets and self.widgets.healthCalculator then
                self.widgets.healthCalculator:ResetPredictedValues()
            end
        end

        -- private auras
        if self.states.unit ~= value then
            self.indicators.privateAuras:UpdatePrivateAuraAnchor(value)
        end

        if type(value) == "string" then
            self.states.unit = value
            self.states.displayedUnit = value
            if string.find(value, "^raid%d+$") then 
                Cell.unitButtons.raid.units[value] = self 
            end
            if I.UpdateHealersAuraDisplayUnit then
                I.UpdateHealersAuraDisplayUnit(self)
            end
            if I.UpdateCustomAuraDisplays then
                I.UpdateCustomAuraDisplays(self)
            end
            if I.UpdateCombatAuraDisplays then
                I.UpdateCombatAuraDisplays(self)
            end
        end
    end
end

-------------------------------------------------
-- unit button show/hide/enter/leave
-------------------------------------------------
Cell.vars.guids = {} -- guid to unitid
Cell.vars.names = {} -- name to unitid

local function UnitButton_OnShow(self)
    -- print(GetTime(), "OnShow", self:GetName())
    self._updateRequired = nil -- prevent UnitButton_UpdateAll twice. when convert party <-> raid, GROUP_ROSTER_UPDATE fired.
    self._powerUpdateRequired = 1
    UnitButton_RegisterEvents(self)

    --[[
    if self.states.unit then
        -- NOTE: update Cell.vars.guids
        local guid = UnitGUID(self.states.unit)
        if guid then
            Cell.vars.guids[guid] = self.states.unit
        end
        --! NOTE: can't get valid name immediately after an unseen player joining into group
        self.__timer = C_Timer.NewTicker(0.5, function()
            local name = GetUnitName(self.states.unit, true)
            if name and name ~= _G.UNKNOWN then
                Cell.vars.names[name] = self.states.unit
                self.__timer:Cancel()
                self.__timer = nil
            end
        end)
        -- print("show", self.states.unit, guid, name)
    end
    ]]
end

local function UnitButton_OnHide(self)
    UnitButton_UnregisterEvents(self)
    ResetAuraTables(self)

    -- FIX: No intentar indexar con secret keys
    if self.__unitGuid then
        if not self.isSpotlight and F.IsValueNonSecret(self.__unitGuid) then
            Cell.vars.guids[self.__unitGuid] = nil
        end
        self.__unitGuid = nil
    end

    if self.__unitName then
        if not self.isSpotlight and F.IsValueNonSecret(self.__unitName) then
            Cell.vars.names[self.__unitName] = nil
        end
        self.__unitName = nil
    end

    self.__displayedGuid = nil
    self._updateRequired = nil

    F.RemoveElementsExceptKeys(self.states, "unit", "displayedUnit")

    -- Reset calculator
    if self.widgets and self.widgets.healthCalculator then
        self.widgets.healthCalculator:ResetPredictedValues()
    end
end

local function UnitButton_OnEnter(self)
    if not IsEncounterInProgress() then UnitButton_UpdateStatusText(self) end

    if highlightEnabled then self.widgets.mouseoverHighlight:Show() end

    local unit = self.states.displayedUnit
    if not unit then return end

    F.ShowTooltips(self, "unit", unit)
end

local function UnitButton_OnLeave(self)
    self.widgets.mouseoverHighlight:Hide()
    GameTooltip:Hide()
end

local UNKNOWN, UNKNOWNOBJECT = _G.UNKNOWN, _G.UNKNOWNOBJECT
local function UnitButton_OnTick(self)
    local e = (self.__tickCount or 0) + 1
    if e >= 2 then
        e = 0

        if self.states.unit and self.states.displayedUnit then
            local displayedGuid = UnitGUID(self.states.displayedUnit)
            
            local guidChanged = false
            if not F.IsValueNonSecret(displayedGuid) or not F.IsValueNonSecret(self.__displayedGuid) then
                guidChanged = true
            else
                guidChanged = displayedGuid ~= self.__displayedGuid
            end

            if guidChanged then
                F.RemoveElementsExceptKeys(self.states, "unit", "displayedUnit")
                self.__displayedGuid = displayedGuid
                if displayedGuid ~= nil then
                    self._updateRequired = 1
                    self._powerUpdateRequired = 1
                end
            end

            local guid = UnitGUID(self.states.unit)
            local unitGuidChanged = false

            if not F.IsValueNonSecret(guid) or not F.IsValueNonSecret(self.__unitGuid) then
                unitGuidChanged = guid ~= nil
            else
                unitGuidChanged = guid and guid ~= self.__unitGuid
            end

            if unitGuidChanged then
                self.__unitGuid = guid
                
                if not self.isSpotlight and F.IsValueNonSecret(guid) then
                    Cell.vars.guids[guid] = self.states.unit
                end

                if UnitIsPlayer(self.states.unit) then
                    local name = GetUnitName(self.states.unit, true)
                    if (name and self.__nameRetries and self.__nameRetries >= 4) or 
                       (name and name ~= UNKNOWN and name ~= UNKNOWNOBJECT) then
                        self.__unitName = name
                        if not self.isSpotlight and F.IsValueNonSecret(name) then 
                            Cell.vars.names[name] = self.states.unit 
                        end
                        self.__nameRetries = nil
                    else
                        self.__nameRetries = (self.__nameRetries or 0) + 1
                        self.__unitGuid = nil
                    end
                end
            end
        end

        UnitButton_UpdateInRange(self)
    end

    self.__tickCount = e

    if self._updateRequired and self._indicatorsReady then
        self._updateRequired = nil
        UnitButton_UpdateAll(self)
    end

    if self:GetAttribute("refreshOnUpdate") then
        UnitButton_UpdateAll(self)
    end
end

local function UnitButton_OnUpdate(self, elapsed)
    local e = (self.__updateElapsed or 0) + elapsed
    if e > 0.25 then
        e = 0
        UnitButton_OnTick(self)
        UnitButton_UpdateCombatIcon(self)
    end
    self.__updateElapsed = e
end

-------------------------------------------------
-- button functions
-------------------------------------------------
function B.SetPowerSize(button, size)
    -- print(GetTime(), "SetPowerSize", button:GetName(), button:IsShown(), button:IsVisible())
    button.powerSize = size

    if size == 0 then
        HidePowerBar(button)
        button._shouldShowPowerBar = false
    else
        button._shouldShowPowerBar = ShouldShowPowerBar(button)
        if button._shouldShowPowerBar then
            ShowPowerBar(button)
        else
            HidePowerBar(button)
        end
    end
    CheckPowerEventRegistration(button)
end

function B.UpdateShields(button)
    predictionEnabled = CellDB["appearance"]["healPrediction"][1]
    shieldEnabled = CellDB["appearance"]["shield"][1]
    overshieldEnabled = CellDB["appearance"]["overshield"][1]
    overshieldReverseFillEnabled = shieldEnabled and CellDB["appearance"]["overshieldReverseFill"]
    absorbEnabled = CellDB["appearance"]["healAbsorb"][1]
    absorbInvertColor = CellDB["appearance"]["healAbsorbInvertColor"]

    if Cell.isMidnight then
        -- StatusBars on Midnight: use SetStatusBarColor
        button.widgets.shieldBar:SetStatusBarColor(unpack(CellDB["appearance"]["shield"][2]))
        button.widgets.shieldBarR:SetStatusBarColor(unpack(CellDB["appearance"]["shield"][2]))
    else
        -- Textures on pre-Midnight: use SetVertexColor
        button.widgets.shieldBar:SetVertexColor(unpack(CellDB["appearance"]["shield"][2]))
        button.widgets.shieldBarR:SetVertexColor(unpack(CellDB["appearance"]["shield"][2]))
    end
    -- overShieldGlow textures are always textures
    button.widgets.overShieldGlow:SetVertexColor(unpack(CellDB["appearance"]["overshield"][2]))
    button.widgets.overShieldGlowR:SetVertexColor(unpack(CellDB["appearance"]["overshield"][2]))
    if not absorbInvertColor then
        button.widgets.overAbsorbGlow:SetVertexColor(unpack(CellDB["appearance"]["healAbsorb"][2]))
        if Cell.isMidnight then
            button.widgets.absorbsBar:SetStatusBarColor(unpack(CellDB["appearance"]["healAbsorb"][2]))
        else
            button.widgets.absorbsBar:SetVertexColor(unpack(CellDB["appearance"]["healAbsorb"][2]))
        end
    end

    UnitButton_UpdateHealPrediction(button)
    UnitButton_UpdateHealAbsorbs(button)
    UnitButton_UpdateShieldAbsorbs(button)
end

function B.SetTexture(button, tex)
    button.widgets.healthBar:SetStatusBarTexture(tex)
    button.widgets.healthBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7) --! VERY IMPORTANT
    button.widgets.healthBarLoss:SetTexture(tex)
    button.widgets.powerBar:SetStatusBarTexture(tex)
    button.widgets.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7) --! VERY IMPORTANT
    button.widgets.powerBarLoss:SetTexture(tex)
    if Cell.isMidnight then
        button.widgets.incomingHeal:SetStatusBarTexture(tex)
    else
        button.widgets.incomingHeal:SetTexture(tex)
    end
    button.widgets.damageFlashTex:SetTexture(tex)
end

function B.UpdateColor(button)
    UnitButton_UpdateHealthColor(button)
    UnitButton_UpdatePowerType(button)
    UnitButton_UpdatePowerTextColor(button)
    button:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])
end

local function IncomingHeal_SetValue_Horizontal(self, incomingPercent, healthPercent)
    local barWidth = self:GetParent():GetWidth()
    local incomingHealWidth = incomingPercent * barWidth
    local lostHealthWidth = barWidth * (1 - healthPercent)

    -- print(incomingPercent, barWidth, incomingHealWidth, lostHealthWidth)
    -- FIXME: if incomingPercent is a very tiny number, like 0.005
    -- P.Scale(incomingHealWidth) ==> 0
    --! if width is set to 0, then the ACTUAL width may be 256!!!

    if lostHealthWidth == 0 then
        self:Hide()
    else
        if lostHealthWidth > incomingHealWidth then
            self:SetWidth(incomingHealWidth)
        else
            self:SetWidth(lostHealthWidth)
        end
        self:Show()
    end
end

local function ShieldBar_SetValue_Horizontal(self, shieldPercent, healthPercent)
    local barWidth = self:GetParent():GetWidth()
    if shieldPercent + healthPercent > 1 then -- overshield
        local p = 1 - healthPercent
        if p ~= 0 then
            if shieldEnabled then
                self:SetWidth(p * barWidth)
                self:Show()
            else
                self:Hide()
            end
        else
            self:Hide()
        end

        if overshieldReverseFillEnabled then
            p = shieldPercent + healthPercent - 1
            if p > healthPercent then p = healthPercent end
            self.shieldBarR:SetWidth(p * barWidth)
            self.shieldBarR:Show()
            if overshieldEnabled then
                self.overShieldGlowR:Show()
            else
                self.overShieldGlowR:Hide()
            end
            self.overShieldGlow:Hide()
        else
            if overshieldEnabled then
                self.overShieldGlow:Show()
            else
                self.overShieldGlow:Hide()
            end
            self.shieldBarR:Hide()
            self.overShieldGlowR:Hide()
        end
    else
        if shieldEnabled then
            self:SetWidth(shieldPercent * barWidth)
            self:Show()
        else
            self:Hide()
        end
        self.shieldBarR:Hide()
        self.overShieldGlow:Hide()
        self.overShieldGlowR:Hide()
    end
end

local function AbsorbsBar_SetValue_Horizontal(self, absorbsPercent, healthPercent)
    if absorbInvertColor then
        local r, g, b = F.InvertColor(self.healthBar:GetStatusBarColor())
        self:SetVertexColor(r, g, b)
        self.overAbsorbGlow:SetVertexColor(r, g, b)
    end

    local barWidth = self:GetParent():GetWidth()
    if absorbsPercent > healthPercent then
        self:SetWidth(healthPercent * barWidth)
        self.overAbsorbGlow:Show()
    else
        self:SetWidth(absorbsPercent * barWidth)
        self.overAbsorbGlow:Hide()
    end
    self:Show()
end

local function DamageFlashTex_SetValue_Horizontal(self, lostPercent)
    local barWidth = self:GetParent():GetWidth()
    self:SetWidth(barWidth * lostPercent)
end

local function IncomingHeal_SetValue_Vertical(self, incomingPercent, healthPercent)
    local barHeight = self:GetParent():GetHeight()
    local incomingHealHeight = incomingPercent * barHeight
    local lostHealthHeight = barHeight * (1 - healthPercent)

    if lostHealthHeight == 0 then
        self:Hide()
    else
        if lostHealthHeight > incomingHealHeight then
            self:SetHeight(incomingHealHeight)
        else
            self:SetHeight(lostHealthHeight)
        end
        self:Show()
    end
end

local function ShieldBar_SetValue_Vertical(self, shieldPercent, healthPercent)
    local barHeight = self:GetParent():GetHeight()
    if shieldPercent + healthPercent > 1 then -- overshield
        local p = 1 - healthPercent
        if p ~= 0 then
            if shieldEnabled then
                self:SetHeight(p * barHeight)
                self:Show()
            else
                self:Hide()
            end
        else
            self:Hide()
        end

        if overshieldReverseFillEnabled then
            p = shieldPercent + healthPercent - 1
            if p > healthPercent then p = healthPercent end
            self.shieldBarR:SetHeight(p * barHeight)
            self.shieldBarR:Show()
            if overshieldEnabled then
                self.overShieldGlowR:Show()
            else
                self.overShieldGlowR:Hide()
            end
            self.overShieldGlow:Hide()
        else
            if overshieldEnabled then
                self.overShieldGlow:Show()
            else
                self.overShieldGlow:Hide()
            end
            self.shieldBarR:Hide()
            self.overShieldGlowR:Hide()
        end
    else
        if shieldEnabled then
            self:SetHeight(shieldPercent * barHeight)
            self:Show()
        else
            self:Hide()
        end
        self.shieldBarR:Hide()
        self.overShieldGlow:Hide()
        self.overShieldGlowR:Hide()
    end
end

local function AbsorbsBar_SetValue_Vertical(self, absorbsPercent, healthPercent)
    if absorbInvertColor then
        local r, g, b = F.InvertColor(self.healthBar:GetStatusBarColor())
        self:SetVertexColor(r, g, b)
        self.overAbsorbGlow:SetVertexColor(r, g, b)
    end

    local barHeight = self:GetParent():GetHeight()
    if absorbsPercent > healthPercent then
        self:SetHeight(healthPercent * barHeight)
        self.overAbsorbGlow:Show()
    else
        self:SetHeight(absorbsPercent * barHeight)
        self.overAbsorbGlow:Hide()
    end
    self:Show()
end

local function DamageFlashTex_SetValue_Vertical(self, lostPercent)
    local barHeight = self:GetParent():GetHeight()
    self:SetHeight(barHeight * lostPercent)
end

function B.SetOrientation(button, orientation, rotateTexture)
    local healthBar = button.widgets.healthBar
    local healthBarLoss = button.widgets.healthBarLoss
    local powerBar = button.widgets.powerBar
    local powerBarLoss = button.widgets.powerBarLoss
    local incomingHeal = button.widgets.incomingHeal
    local damageFlashTex = button.widgets.damageFlashTex
    local gapTexture = button.widgets.gapTexture
    local shieldBar = button.widgets.shieldBar
    local shieldBarR = button.widgets.shieldBarR
    local overShieldGlow = button.widgets.overShieldGlow
    local overShieldGlowR = button.widgets.overShieldGlowR
    local overAbsorbGlow = button.widgets.overAbsorbGlow
    local absorbsBar = button.widgets.absorbsBar

    gapTexture:SetColorTexture(unpack(CELL_BORDER_COLOR))

    button.orientation = orientation
    if orientation == "vertical_health" then
        healthBar:SetOrientation("vertical")
        powerBar:SetOrientation("horizontal")
    else
        healthBar:SetOrientation(orientation)
        powerBar:SetOrientation(orientation)
    end
    healthBar:SetRotatesTexture(rotateTexture)
    powerBar:SetRotatesTexture(rotateTexture)

    -- StatusBar orientation for shield/absorb/heal bars (12.0 secret value support)
    local barOrientation = (orientation == "vertical_health") and "vertical" or orientation
    incomingHeal:SetOrientation(barOrientation)
    incomingHeal:SetRotatesTexture(rotateTexture)
    shieldBar:SetOrientation(barOrientation)
    shieldBar:SetRotatesTexture(rotateTexture)
    absorbsBar:SetOrientation(barOrientation)
    absorbsBar:SetRotatesTexture(rotateTexture)

    button.indicators.healthThresholds:SetOrientation(orientation)

    if rotateTexture then
        F.RotateTexture(healthBarLoss, 90)
        F.RotateTexture(powerBarLoss, 90)
        if not Cell.isMidnight then F.RotateTexture(incomingHeal, 90) end
        F.RotateTexture(damageFlashTex, 90)
    else
        F.RotateTexture(healthBarLoss, 0)
        F.RotateTexture(powerBarLoss, 0)
        if not Cell.isMidnight then F.RotateTexture(incomingHeal, 0) end
        F.RotateTexture(damageFlashTex, 0)
    end

    if orientation == "horizontal" then
        -- update healthBarLoss
        P.ClearPoints(healthBarLoss)
        P.Point(healthBarLoss, "TOPRIGHT", healthBar)
        P.Point(healthBarLoss, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

        -- update powerBarLoss
        P.ClearPoints(powerBarLoss)
        P.Point(powerBarLoss, "TOPRIGHT", powerBar)
        P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "BOTTOMRIGHT")

        -- update gapTexture
        P.ClearPoints(gapTexture)
        P.Point(gapTexture, "BOTTOMLEFT", powerBar, "TOPLEFT")
        P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "TOPRIGHT")
        P.Height(gapTexture, CELL_BORDER_SIZE)

        if Cell.isMidnight then
            -- Midnight: anchor incomingHeal to health fill edge so it starts where health ends
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")
            incomingHeal:SetOrientation("horizontal")
            shieldBar:SetOrientation("horizontal")
            shieldBarR:SetOrientation("horizontal")
            absorbsBar:SetOrientation("horizontal")
        else
            -- Pre-Midnight: Textures with manual positioning
            -- update incomingHeal
            incomingHeal.SetValue = IncomingHeal_SetValue_Horizontal
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

            -- update shieldBar
            shieldBar.SetValue = ShieldBar_SetValue_Horizontal
            P.ClearPoints(shieldBar)
            P.Point(shieldBar, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            P.Point(shieldBar, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

            -- update shieldBarR
            P.ClearPoints(shieldBarR)
            P.Point(shieldBarR, "TOPRIGHT", healthBar:GetStatusBarTexture())
            P.Point(shieldBarR, "BOTTOMRIGHT", healthBar:GetStatusBarTexture())

            -- update absorbsBar
            absorbsBar.SetValue = AbsorbsBar_SetValue_Horizontal
            P.ClearPoints(absorbsBar)
            P.Point(absorbsBar, "TOPRIGHT", healthBar:GetStatusBarTexture())
            P.Point(absorbsBar, "BOTTOMRIGHT", healthBar:GetStatusBarTexture())
        end

        -- update overShieldGlow
        P.ClearPoints(overShieldGlow)
        P.Point(overShieldGlow, "TOPRIGHT")
        P.Point(overShieldGlow, "BOTTOMRIGHT")
        P.Width(overShieldGlow, 4)
        F.RotateTexture(overShieldGlow, 0)

        -- update overShieldGlowR
        local reverseShieldAnchor = Cell.isMidnight and shieldBarR:GetStatusBarTexture() or shieldBarR
        P.ClearPoints(overShieldGlowR)
        P.Point(overShieldGlowR, "TOP", reverseShieldAnchor, "TOPLEFT", 0, 0)
        P.Point(overShieldGlowR, "BOTTOM", reverseShieldAnchor, "BOTTOMLEFT", 0, 0)
        P.Width(overShieldGlowR, 8)
        F.RotateTexture(overShieldGlowR, 0)

        -- update overAbsorbGlow
        P.ClearPoints(overAbsorbGlow)
        P.Point(overAbsorbGlow, "TOPLEFT")
        P.Point(overAbsorbGlow, "BOTTOMLEFT")
        P.Width(overAbsorbGlow, 4)
        F.RotateTexture(overAbsorbGlow, 0)

        -- update damageFlashTex
        damageFlashTex.SetValue = DamageFlashTex_SetValue_Horizontal
        P.ClearPoints(damageFlashTex)
        P.Point(damageFlashTex, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
        P.Point(damageFlashTex, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

    else -- vertical / vertical_health
        P.ClearPoints(healthBarLoss)
        P.Point(healthBarLoss, "TOPRIGHT", healthBar)
        P.Point(healthBarLoss, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")

        if orientation == "vertical" then
            -- update powerBarLoss
            P.ClearPoints(powerBarLoss)
            P.Point(powerBarLoss, "TOPRIGHT", powerBar)
            P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "TOPLEFT")

            -- update gapTexture
            P.ClearPoints(gapTexture)
            P.Point(gapTexture, "TOPRIGHT", powerBar, "TOPLEFT")
            P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "BOTTOMLEFT")
            P.Width(gapTexture, CELL_BORDER_SIZE)
        else -- vertical_health
            -- update powerBarLoss
            P.ClearPoints(powerBarLoss)
            P.Point(powerBarLoss, "TOPRIGHT", powerBar)
            P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "BOTTOMRIGHT")

            -- update gapTexture
            P.ClearPoints(gapTexture)
            P.Point(gapTexture, "BOTTOMLEFT", powerBar, "TOPLEFT")
            P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "TOPRIGHT")
            P.Height(gapTexture, CELL_BORDER_SIZE)
        end

        if Cell.isMidnight then
            -- Midnight: anchor incomingHeal to health fill edge so it starts where health ends
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
            P.Point(incomingHeal, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            incomingHeal:SetOrientation("vertical")
            shieldBar:SetOrientation("vertical")
            shieldBarR:SetOrientation("vertical")
            absorbsBar:SetOrientation("vertical")
        else
            -- Pre-Midnight: Textures with manual positioning
            -- update incomingHeal
            incomingHeal.SetValue = IncomingHeal_SetValue_Vertical
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
            P.Point(incomingHeal, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")

            -- update shieldBar
            shieldBar.SetValue = ShieldBar_SetValue_Vertical
            P.ClearPoints(shieldBar)
            P.Point(shieldBar, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
            P.Point(shieldBar, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")

            -- update shieldBarR
            P.ClearPoints(shieldBarR)
            P.Point(shieldBarR, "TOPLEFT", healthBar:GetStatusBarTexture())
            P.Point(shieldBarR, "TOPRIGHT", healthBar:GetStatusBarTexture())

            -- update absorbsBar
            absorbsBar.SetValue = AbsorbsBar_SetValue_Vertical
            P.ClearPoints(absorbsBar)
            P.Point(absorbsBar, "TOPLEFT", healthBar:GetStatusBarTexture())
            P.Point(absorbsBar, "TOPRIGHT", healthBar:GetStatusBarTexture())
        end

        -- update overShieldGlow
        P.ClearPoints(overShieldGlow)
        P.Point(overShieldGlow, "TOPLEFT")
        P.Point(overShieldGlow, "TOPRIGHT")
        P.Height(overShieldGlow, 4)
        F.RotateTexture(overShieldGlow, 90)

        -- update overShieldGlowR
        local reverseShieldAnchor = Cell.isMidnight and shieldBarR:GetStatusBarTexture() or shieldBarR
        P.ClearPoints(overShieldGlowR)
        P.Point(overShieldGlowR, "LEFT", reverseShieldAnchor, "BOTTOMLEFT", 0, 0)
        P.Point(overShieldGlowR, "RIGHT", reverseShieldAnchor, "BOTTOMRIGHT", 0, 0)
        P.Height(overShieldGlowR, 8)
        F.RotateTexture(overShieldGlowR, 90)

        -- update overAbsorbGlow
        P.ClearPoints(overAbsorbGlow)
        P.Point(overAbsorbGlow, "BOTTOMLEFT")
        P.Point(overAbsorbGlow, "BOTTOMRIGHT")
        P.Height(overAbsorbGlow, 4)
        F.RotateTexture(overAbsorbGlow, 90)

        -- update damageFlashTex
        damageFlashTex.SetValue = DamageFlashTex_SetValue_Vertical
        P.ClearPoints(damageFlashTex)
        P.Point(damageFlashTex, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
        P.Point(damageFlashTex, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
    end

    -- update actions
    I.UpdateActionsOrientation(button, orientation)
end

function B.UpdateHighlightColor(button)
    button.widgets.targetHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["targetColor"]))
    button.widgets.mouseoverHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["mouseoverColor"]))
end

function B.UpdateHighlightSize(button)
    local targetHighlight = button.widgets.targetHighlight
    local mouseoverHighlight = button.widgets.mouseoverHighlight

    local size = CellDB["appearance"]["highlightSize"]

    if size ~= 0 then
        highlightEnabled = true

        P.ClearPoints(targetHighlight)
        P.ClearPoints(mouseoverHighlight)

        -- update point
        if size < 0 then
            size = abs(size)
            P.Point(targetHighlight, "TOPLEFT", button, "TOPLEFT")
            P.Point(targetHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT")
            P.Point(mouseoverHighlight, "TOPLEFT", button, "TOPLEFT")
            P.Point(mouseoverHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT")
        else
            P.Point(targetHighlight, "TOPLEFT", button, "TOPLEFT", -size, size)
            P.Point(targetHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", size, -size)
            P.Point(mouseoverHighlight, "TOPLEFT", button, "TOPLEFT", -size, size)
            P.Point(mouseoverHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", size, -size)
        end

        -- update thickness
        targetHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(size)})
        mouseoverHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(size)})

        -- update color
        targetHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["targetColor"]))
        mouseoverHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["mouseoverColor"]))

        UnitButton_UpdateTarget(button) -- 0->!0 show highlight again
    else
        highlightEnabled = false
        targetHighlight:Hide()
        mouseoverHighlight:Hide()
    end
end

-- raidIcons
function B.UpdatePlayerRaidIcon(button, enabled)
    if not button:IsShown() then return end
    UnitButton_UpdatePlayerRaidIcon(button)
    if enabled then
        button:RegisterEvent("RAID_TARGET_UPDATE")
    else
        button:UnregisterEvent("RAID_TARGET_UPDATE")
    end
end

function B.UpdateTargetRaidIcon(button, enabled)
    if not button:IsShown() then return end
    UnitButton_UpdateTargetRaidIcon(button)
    if enabled then
        button:RegisterEvent("UNIT_TARGET")
    else
        button:UnregisterEvent("UNIT_TARGET")
    end
end

-- readyCheckIcon
function B.UpdateReadyCheckIcon(button, enabled)
    if not button:IsShown() then return end
    UnitButton_UpdateReadyCheck(button)
    if enabled then
        button:RegisterEvent("READY_CHECK")
        button:RegisterEvent("READY_CHECK_FINISHED")
        button:RegisterEvent("READY_CHECK_CONFIRM")
    else
        button:UnregisterEvent("READY_CHECK")
        button:UnregisterEvent("READY_CHECK_FINISHED")
        button:UnregisterEvent("READY_CHECK_CONFIRM")
    end
end

-- healthText
function B.UpdateHealthText(button)
    if button.states.displayedUnit then
        UnitButton_UpdateHealthStates(button)
    end
end

-- powerText
function B.UpdatePowerText(button)
    -- displayedUnit is set by UnitButton_UpdateAll (OnShow/vehicle check).
    -- When enabling the indicator at runtime, buttons may not have gone
    -- through UpdateAll yet. Fall back to states.unit so power APIs work.
    if not button.states.displayedUnit and button.states.unit then
        button.states.displayedUnit = button.states.unit
    end
    -- If still no unit, try GetAttribute (secure header always sets this)
    if not button.states.displayedUnit then
        local attrUnit = button:GetAttribute("unit")
        if attrUnit then
            button.states.displayedUnit = attrUnit
        end
    end
    if button.states.displayedUnit then
        UnitButton_UpdatePowerStates(button)
        UnitButton_UpdatePowerText(button)
        UnitButton_UpdatePowerTextColor(button)
    end
end

-- statusText
function B.UpdateStatusText(button)
    UnitButton_UpdateStatusText(button)
end

-- shields
function B.UpdateShield(button)
    UnitButton_UpdateShieldAbsorbs(button)
end

-- animation
function B.UpdateAnimation(button)
    barAnimationType = CellDB["appearance"]["barAnimation"]

    if Cell.isMidnight then
        -- Never drive unit bars through SmoothStatusBarMixin on Midnight (secret Clamp errors).
        -- "Smooth" uses StatusBarInterpolation in SetValue(); "Legacy"/None snap immediately.
        button.widgets.healthBar:ResetSmoothedValue()
        button.widgets.powerBar:ResetSmoothedValue()
        button.widgets.healthBar.SetBarValue = button.widgets.healthBar.SetValue
        button.widgets.powerBar.SetBarValue = button.widgets.powerBar.SetValue
    elseif barAnimationType == "Smooth" or barAnimationType == "Legacy" or barAnimationType == "Old" then
        button.widgets.healthBar.SetBarValue = button.widgets.healthBar.SetSmoothedValue
        button.widgets.powerBar.SetBarValue = button.widgets.powerBar.SetSmoothedValue
    else
        button.widgets.healthBar:ResetSmoothedValue()
        button.widgets.healthBar.SetBarValue = button.widgets.healthBar.SetValue
        button.widgets.powerBar:ResetSmoothedValue()
        button.widgets.powerBar.SetBarValue = button.widgets.powerBar.SetValue
    end

    button.widgets.damageFlashAG:Finish()
end

-- backdrop
function B.UpdateBackdrop(button)
    if CELL_BORDER_SIZE == 0 then
        button:SetBackdrop({bgFile = Cell.vars.whiteTexture})
        button:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])
    else
        button:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})
        button:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])
        button:SetBackdropBorderColor(unpack(CELL_BORDER_COLOR))
    end
end

-- pixel perfect
function B.UpdatePixelPerfect(button, updateIndicators)
    if not InCombatLockdown() then P.Resize(button) end
    P.Reborder(button)

    P.Repoint(button.widgets.healthBar)
    P.Repoint(button.widgets.healthBarLoss)
    P.Repoint(button.widgets.powerBar)
    P.Repoint(button.widgets.powerBarLoss)
    P.Repoint(button.widgets.gapTexture)
    P.Resize(button.widgets.gapTexture)

    P.Repoint(button.widgets.incomingHeal)
    P.Repoint(button.widgets.shieldBar)
    P.Repoint(button.widgets.absorbsBar)
    P.Repoint(button.widgets.damageFlashTex)

    P.Resize(button.widgets.overShieldGlow)
    P.Repoint(button.widgets.overShieldGlow)
    P.Resize(button.widgets.overAbsorbGlow)
    P.Repoint(button.widgets.overAbsorbGlow)

    B.UpdateHighlightSize(button)
    B.UpdateBackdrop(button)

    if updateIndicators then
        -- indicators
        for _, i in next, button.indicators do
            if i.UpdatePixelPerfect then
                i:UpdatePixelPerfect()
            end
        end
    end

    button.widgets.srIcon:UpdatePixelPerfect()
end

B.UpdateAll = UnitButton_UpdateAll
B.UpdateHealth = UnitButton_UpdateHealth
B.UpdateHealthMax = UnitButton_UpdateHealthMax
B.UpdateAuras = UnitButton_UpdateAuras
B.UpdateName = UnitButton_UpdateName

-------------------------------------------------
-- unit button init
-------------------------------------------------
-- local startTimeCache, statusCache = {}, {}
local startTimeCache = {}

-- Layers ---------------------------------------
-- OVERLAY
-- ARTWORK
--  -2 overAbsorbGlow (texture)
--  absorbsBar (StatusBar, frame level midLevel+2)
--  -4 overShieldGlow, overShieldGlowR (texture)
--  shieldBar (StatusBar, frame level midLevel+1), shieldBarR (texture)
--  incomingHeal (StatusBar, frame level healthBar+1)
--	-6 damageFlashTex
--	-7 healthBar, healthBarLoss
-- BORDER
--  0 gapTexture
-- BACKGROUND
-------------------------------------------------

-- NOTE: prevent a nil method error
local DumbFunc = function() end

-- Remaining HandleBuff dependencies (defined above, stored here for HandleBuff.lua)
Cell._hb.GetTime = GetTime
Cell._hb.enabledIndicators = enabledIndicators
Cell._hb.indicatorNums = indicatorNums
Cell._hb.DoesAuraMatchExpectedBuff = DoesAuraMatchExpectedBuff
Cell._hb.GetRecentSecretHelpfulCastKind = GetRecentSecretHelpfulCastKind
Cell._hb.UpdateAuraRefreshState = UpdateAuraRefreshState

function CellUnitButton_OnLoad(button)
    local name = button:GetName()

    button.widgets = {}
    button.states = {}
    button.indicators = {}

    -- Health prediction calculator (Patch 12.0.0+)
    if Cell.isMidnight and CreateUnitHealPredictionCalculator then
        button.widgets.healthCalculator = CreateUnitHealPredictionCalculator()
        -- Separate calculator for heal prediction so clamp settings don't
        -- corrupt the shared healthCalculator used by health/absorb reads.
        button.widgets.healPredictionCalculator = CreateUnitHealPredictionCalculator()
    end
    -- Color curves for health bar coloring (Patch 12.0.0+)
    if Cell.isMidnight and C_CurveUtil then
        button.widgets.healthBarColorCurve = C_CurveUtil.CreateColorCurve()
        button.widgets.healthLossColorCurve = C_CurveUtil.CreateColorCurve()
    end

    InitAuraTables(button)

    -- ping system
    Mixin(button, PingableType_UnitFrameMixin)
    button:SetAttribute("ping-receiver", true)

    function button:GetTargetPingGUID()
        return button.__unitGuid
    end

    -- background
    -- local background = button:CreateTexture(name.."Background", "BORDER")
    -- button.widgets.background = background
    -- background:SetAllPoints(button)
    -- background:SetTexture(Cell.vars.whiteTexture)
    -- background:SetVertexColor(0, 0, 0, 1)

    -- NOTE: SecureUnitButton has no OnActionButtonPressAndHoldRelease
    -- button:SetAttribute("pressAndHoldAction", true)
    -- button:SetAttribute("typerelease", "macro")

    -- backdrop
    -- button:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})
    -- button:SetBackdropColor(0, 0, 0, 1)
    -- button:SetBackdropBorderColor(unpack(CELL_BORDER_COLOR))

    -- healthbar
    local healthBar = CreateFrame("StatusBar", name.."HealthBar", button)
    button.widgets.healthBar = healthBar
    -- P.Point(healthBar, "TOPLEFT", button, "TOPLEFT", 1, -1)
    -- P.Point(healthBar, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 4)
    healthBar:SetStatusBarTexture(Cell.vars.texture)
    healthBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7)
    healthBar:SetFrameLevel(button:GetFrameLevel()+1)
    healthBar.SetBarValue = healthBar.SetValue

    -- healthBar:SetScript("OnValueChanged", function(self, value)
    --     if value == 0 then
    --         healthBar:SetValue(0.1)
    --     end
    -- end)

    -- hp loss
    local healthBarLoss = button:CreateTexture(name.."HealthBarLoss", "ARTWORK", nil , -7)
    button.widgets.healthBarLoss = healthBarLoss
    -- P.Point(healthBarLoss, "TOPRIGHT", healthBar)
    -- P.Point(healthBarLoss, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    healthBarLoss:SetTexture(Cell.vars.texture)

    -- powerbar
    local powerBar = CreateFrame("StatusBar", name.."PowerBar", button)
    button.widgets.powerBar = powerBar
    -- P.Point(powerBar, "TOPLEFT", healthBar, "BOTTOMLEFT", 0, -1)
    -- P.Point(powerBar, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    powerBar:SetStatusBarTexture(Cell.vars.texture)
    powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7)
    powerBar:SetFrameLevel(button:GetFrameLevel()+2)
    powerBar.SetBarValue = powerBar.SetValue

    local gapTexture = button:CreateTexture(nil, "BORDER")
    button.widgets.gapTexture = gapTexture
    -- P.Point(gapTexture, "BOTTOMLEFT", powerBar, "TOPLEFT")
    -- P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "TOPRIGHT")
    -- P.Height(gapTexture, 1)
    gapTexture:SetColorTexture(unpack(CELL_BORDER_COLOR))

    -- power loss
    local powerBarLoss = button:CreateTexture(name.."PowerBarLoss", "ARTWORK", nil , -7)
    button.widgets.powerBarLoss = powerBarLoss
    -- P.Point(powerBarLoss, "TOPRIGHT", powerBar)
    -- P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    powerBarLoss:SetTexture(Cell.vars.texture)

    -- incoming heal
    local incomingHeal
    if Cell.isMidnight then
        -- Midnight: StatusBar so native SetMinMaxValues/SetValue work with secret values
        -- Health values are always secret in instances, so we must use calculator-based StatusBar
        incomingHeal = CreateFrame("StatusBar", name.."IncomingHealBar", healthBar)
        incomingHeal:SetStatusBarTexture(Cell.vars.texture)
        incomingHeal:GetStatusBarTexture():SetDrawLayer("ARTWORK", -6)
        incomingHeal:SetFrameLevel(healthBar:GetFrameLevel()+1)
        -- Positioned by SetOrientation (anchored to health fill edge, not SetAllPoints)
        -- Compatibility shims: map Texture methods to StatusBar equivalents
        incomingHeal.SetVertexColor = incomingHeal.SetStatusBarColor
        incomingHeal.SetTexture = incomingHeal.SetStatusBarTexture
    else
        -- Pre-Midnight: Texture with manual width/height positioning
        incomingHeal = healthBar:CreateTexture(name.."IncomingHealBar", "ARTWORK", nil, -3)
        incomingHeal:SetTexture(Cell.vars.texture)
        incomingHeal.SetValue = DumbFunc
    end
    button.widgets.incomingHeal = incomingHeal
    incomingHeal:Hide()

    --* indicatorFrame
    local indicatorFrame = CreateFrame("Frame", name.."IndicatorFrame", button)
    button.widgets.indicatorFrame = indicatorFrame
    indicatorFrame:SetFrameLevel(button:GetFrameLevel()+220)
    indicatorFrame:SetAllPoints(button)

    --* tsGlowFrame (Targeted Spells)
    local tsGlowFrame = CreateFrame("Frame", name.."TSGlowFrame", button)
    button.widgets.tsGlowFrame = tsGlowFrame
    tsGlowFrame:SetFrameLevel(button:GetFrameLevel()+200)
    tsGlowFrame:SetAllPoints(button)

    --* srGlowFrame (Spell Request)
    local srGlowFrame = CreateFrame("Frame", name.."SRGlowFrame", button)
    button.widgets.srGlowFrame = srGlowFrame
    srGlowFrame:SetFrameLevel(button:GetFrameLevel()+200)
    srGlowFrame:SetAllPoints(button)

    --* drGlowFrame (Dispel Request)
    local drGlowFrame = CreateFrame("Frame", name.."DRGlowFrame", button)
    button.widgets.drGlowFrame = drGlowFrame
    drGlowFrame:SetFrameLevel(button:GetFrameLevel()+200)
    drGlowFrame:SetAllPoints(button)

    --* highLevelFrame
    local highLevelFrame = CreateFrame("Frame", name.."HighLevelFrame", button)
    button.widgets.highLevelFrame = highLevelFrame
    highLevelFrame:SetFrameLevel(button:GetFrameLevel()+140)
    highLevelFrame:SetAllPoints(button)

    --* midLevelFrame
    local midLevelFrame = CreateFrame("Frame", name.."MidLevelFrame", button)
    button.widgets.midLevelFrame = midLevelFrame
    midLevelFrame:SetFrameLevel(button:GetFrameLevel()+120)
    midLevelFrame:SetAllPoints(healthBar)

    -- shield bar
    local shieldBar
    if Cell.isMidnight then
        -- Midnight: StatusBar so native SetMinMaxValues/SetValue work with secret values
        shieldBar = CreateFrame("StatusBar", name.."ShieldBar", midLevelFrame)
        shieldBar:SetStatusBarTexture("Interface\\AddOns\\Cell\\Media\\shield")
        shieldBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -5)
        shieldBar:SetFrameLevel(midLevelFrame:GetFrameLevel()+1)
        shieldBar:SetAllPoints(healthBar)
        -- Compatibility shims: map Texture methods to StatusBar equivalents
        shieldBar.SetVertexColor = shieldBar.SetStatusBarColor
        shieldBar.SetTexture = shieldBar.SetStatusBarTexture
    else
        -- Pre-Midnight: Texture with manual width/height positioning
        shieldBar = midLevelFrame:CreateTexture(name.."ShieldBar", "ARTWORK", nil, -5)
        shieldBar:SetTexture("Interface\\AddOns\\Cell\\Media\\shield", "REPEAT", "REPEAT")
        shieldBar:SetHorizTile(true)
        shieldBar:SetVertTile(true)
        shieldBar.SetValue = DumbFunc
    end
    button.widgets.shieldBar = shieldBar
    shieldBar:Hide()

    local shieldBarR
    if Cell.isMidnight then
        -- Midnight: StatusBar for reverse-fill shield display with secret values
        shieldBarR = CreateFrame("StatusBar", name.."ShieldBarR", midLevelFrame)
        shieldBarR:SetStatusBarTexture("Interface\\AddOns\\Cell\\Media\\shield")
        shieldBarR:GetStatusBarTexture():SetDrawLayer("ARTWORK", -5)
        shieldBarR:SetFrameLevel(midLevelFrame:GetFrameLevel()+1)
        shieldBarR:SetAllPoints(healthBar)
        shieldBarR:SetReverseFill(true)
        -- Compatibility shims: map Texture methods to StatusBar equivalents
        shieldBarR.SetVertexColor = shieldBarR.SetStatusBarColor
        shieldBarR.SetTexture = shieldBarR.SetStatusBarTexture
    else
        -- Pre-Midnight: Texture with manual width/height positioning
        shieldBarR = midLevelFrame:CreateTexture(name.."ShieldBarR", "ARTWORK", nil, -5)
        shieldBarR:SetTexture("Interface\\AddOns\\Cell\\Media\\shield", "REPEAT", "REPEAT")
        shieldBarR:SetHorizTile(true)
        shieldBarR:SetVertTile(true)
    end
    button.widgets.shieldBarR = shieldBarR
    shieldBarR:Hide()
    shieldBar.shieldBarR = shieldBarR

    -- over-shield glow
    local overShieldGlow = midLevelFrame:CreateTexture(name.."OverShieldGlow", "ARTWORK", nil, -4)
    button.widgets.overShieldGlow = overShieldGlow
    overShieldGlow:SetTexture("Interface\\AddOns\\Cell\\Media\\overshield")
    -- overShieldGlow:SetBlendMode("ADD")
    overShieldGlow:Hide()
    shieldBar.overShieldGlow = overShieldGlow

    -- over-shield glow reversed
    local overShieldGlowR = midLevelFrame:CreateTexture(name.."OverShieldGlowR", "ARTWORK", nil, -4)
    button.widgets.overShieldGlowR = overShieldGlowR
    overShieldGlowR:SetTexture("Interface\\AddOns\\Cell\\Media\\overshield_reversed")
    -- overShieldGlowR:SetBlendMode("ADD")
    overShieldGlowR:Hide()
    shieldBar.overShieldGlowR = overShieldGlowR

    -- over-absorb glow
    local overAbsorbGlow = midLevelFrame:CreateTexture(name.."OverAbsorbGlow", "ARTWORK", nil, -2)
    button.widgets.overAbsorbGlow = overAbsorbGlow
    overAbsorbGlow:SetTexture("Interface\\AddOns\\Cell\\Media\\overabsorb")
    -- overAbsorbGlow:SetBlendMode("ADD")
    overAbsorbGlow:Hide()

    -- absorbs bar
    local absorbsBar
    if Cell.isMidnight then
        -- Midnight: StatusBar so native SetMinMaxValues/SetValue work with secret values
        absorbsBar = CreateFrame("StatusBar", name.."AbsorbsBar", midLevelFrame)
        absorbsBar:SetStatusBarTexture("Interface\\AddOns\\Cell\\Media\\shield.tga")
        absorbsBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
        absorbsBar:SetStatusBarColor(1, 0.1, 0.1, 1)
        absorbsBar:SetFrameLevel(midLevelFrame:GetFrameLevel()+2)
        absorbsBar:SetAllPoints(healthBar)
        absorbsBar:SetReverseFill(true)
        -- Compatibility shims: map Texture methods to StatusBar equivalents
        absorbsBar.SetVertexColor = absorbsBar.SetStatusBarColor
        absorbsBar.SetTexture = absorbsBar.SetStatusBarTexture
    else
        -- Pre-Midnight: Texture with manual width/height positioning
        absorbsBar = midLevelFrame:CreateTexture(name.."AbsorbsBar", "ARTWORK", nil, 1)
        absorbsBar:SetTexture("Interface\\AddOns\\Cell\\Media\\shield.tga", "REPEAT", "REPEAT")
        absorbsBar:SetHorizTile(true)
        absorbsBar:SetVertTile(true)
        absorbsBar:SetVertexColor(1, 0.1, 0.1, 1)
        absorbsBar.SetValue = DumbFunc
    end
    button.widgets.absorbsBar = absorbsBar
    absorbsBar.healthBar = healthBar
    -- absorbsBar:SetBlendMode("ADD")
    absorbsBar:Hide()
    absorbsBar.overAbsorbGlow = overAbsorbGlow

    -- Midnight: Overlay StatusBars need initial min/max for SetValue to work before UpdateHealthMax fires
    if Cell.isMidnight then
        if button.widgets.incomingHeal then
            button.widgets.incomingHeal:SetMinMaxValues(0, 1)
        end
        if button.widgets.shieldBar then
            button.widgets.shieldBar:SetMinMaxValues(0, 1)
        end
        if button.widgets.shieldBarR then
            button.widgets.shieldBarR:SetMinMaxValues(0, 1)
        end
        if button.widgets.absorbsBar then
            button.widgets.absorbsBar:SetMinMaxValues(0, 1)
        end
    end

    -- bar animation
    -- flash
    local damageFlashTex = healthBar:CreateTexture(name.."DamageFlash", "ARTWORK", nil, -6)
    button.widgets.damageFlashTex = damageFlashTex
    damageFlashTex:SetTexture(Cell.vars.whiteTexture)
    damageFlashTex:SetVertexColor(1, 1, 1, 0.7)
    -- P.Point(damageFlashTex, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
    -- P.Point(damageFlashTex, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    damageFlashTex:Hide()
    damageFlashTex.SetValue = DumbFunc

    -- damage flash animation group
    local damageFlashAG = damageFlashTex:CreateAnimationGroup()
    button.widgets.damageFlashAG = damageFlashAG

    local alpha = damageFlashAG:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.7)
    alpha:SetToAlpha(0)
    alpha:SetDuration(0.2)

    damageFlashAG:SetScript("OnPlay", function(self)
        damageFlashTex:Show()
    end)

    damageFlashAG:SetScript("OnFinished", function(self)
        damageFlashTex:Hide()
    end)

    -- smooth
    Mixin(healthBar, SmoothStatusBarMixin)
    Mixin(powerBar, SmoothStatusBarMixin)

    -- target highlight
    local targetHighlight = CreateFrame("Frame", name.."TargetHighlight", button, "BackdropTemplate")
    button.widgets.targetHighlight = targetHighlight
    targetHighlight:SetIgnoreParentAlpha(true)
    targetHighlight:SetFrameLevel(button:GetFrameLevel()+3)
    -- targetHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
    -- P.Point(targetHighlight, "TOPLEFT", button, "TOPLEFT", -1, 1)
    -- P.Point(targetHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    targetHighlight:Hide()

    -- mouseover highlight
    local mouseoverHighlight = CreateFrame("Frame", name.."MouseoverHighlight", button, "BackdropTemplate")
    button.widgets.mouseoverHighlight = mouseoverHighlight
    mouseoverHighlight:SetIgnoreParentAlpha(true)
    mouseoverHighlight:SetFrameLevel(button:GetFrameLevel()+4)
    -- mouseoverHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
    -- P.Point(mouseoverHighlight, "TOPLEFT", button, "TOPLEFT", -1, 1)
    -- P.Point(mouseoverHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    mouseoverHighlight:Hide()

    -- readyCheck highlight
    -- local readyCheckHighlight = button:CreateTexture(name.."ReadyCheckHighlight", "BACKGROUND")
    -- button.widgets.readyCheckHighlight = readyCheckHighlight
    -- readyCheckHighlight:SetPoint("TOPLEFT", -1, 1)
    -- readyCheckHighlight:SetPoint("BOTTOMRIGHT", 1, -1)
    -- readyCheckHighlight:SetTexture(Cell.vars.whiteTexture)
    -- readyCheckHighlight:Hide()

    -- aggro bar
    local aggroBar = Cell.CreateStatusBar(name.."AggroBar", indicatorFrame, 20, 4, 100, true)
    button.indicators.aggroBar = aggroBar
    aggroBar:Hide()

    -- indicators
    I.CreateNameText(button)
    I.CreateStatusText(button)
    I.CreateHealthText(button)
    I.CreatePowerText(button)
    I.CreateStatusIcon(button)
    I.CreateRoleIcon(button)
    I.CreateLeaderIcon(button)
    I.CreateCombatIcon(button)
    I.CreateReadyCheckIcon(button)
    I.CreateAggroBlink(button)
    I.CreateAggroBorder(button)
    I.CreatePlayerRaidIcon(button)
    I.CreateTargetRaidIcon(button)
    I.CreateShieldBar(button)
    I.CreateAoEHealing(button)
    I.CreateTankActiveMitigation(button)
    -- I.CreateDefensiveCooldowns(button)
    -- I.CreateExternalCooldowns(button)
    -- I.CreateAllCooldowns(button)
    -- I.CreateDebuffs(button)
    I.CreateDispels(button)
    I.CreateRaidDebuffs(button)
    I.CreatePrivateAuras(button)
    I.CreateTargetedSpells(button)
    I.CreateTargetCounter(button)
    I.CreateCrowdControls(button)
    I.CreateActions(button)
    I.CreateMissingBuffs(button)
    I.CreateHealthThresholds(button)
    U.CreateSpellRequestIcon(button)
    U.CreateDispelRequestText(button)

    button._waitingForIndicatorCreation = true

    -- events
    button:SetScript("OnAttributeChanged", UnitButton_OnAttributeChanged) -- init
    button:HookScript("OnShow", UnitButton_OnShow)
    button:HookScript("OnHide", UnitButton_OnHide) -- use _onhide for click-castings
    button:HookScript("OnEnter", UnitButton_OnEnter) -- SecureHandlerEnterLeaveTemplate
    button:HookScript("OnLeave", UnitButton_OnLeave) -- SecureHandlerEnterLeaveTemplate
    button:SetScript("OnUpdate", UnitButton_OnUpdate)
    button:SetScript("OnEvent", UnitButton_OnEvent)
    button:RegisterForClicks("AnyDown")
end

end)(Cell)  -- end seg 3
