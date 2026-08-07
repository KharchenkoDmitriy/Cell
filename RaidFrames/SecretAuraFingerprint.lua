-- ============================================================
-- SecretAuraFingerprint — Secret aura identification via
-- Blizzard filter fingerprint matching (Midnight 12.0+).
--
-- Identifies auras whose spellId/name are secret (opaque) in
-- combat by building a 4-filter signature from _IsAuraFilteredOut
-- results and looking it up in a per-spec database.
-- ============================================================

local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

-- Core API (aliased once to avoid repeated table lookups)
local _IsAuraFilteredOut = C_UnitAuras.IsAuraFilteredOutByInstanceID
local _GetSpecialization = GetSpecialization
local _UnitClassBase = UnitClassBase

-- Locale-independent spec mapping: class token + spec index → spec key.
-- GetSpecializationInfo returns localized names, so use English class + index.
local SpecMap = {
    MONK_1    = "MistweaverMonk",  -- Brewmaster (class spells match MW DB)
    MONK_2    = "MistweaverMonk",
    MONK_3    = "MistweaverMonk",  -- Windwalker (class spells match MW DB)
    PALADIN_1 = "HolyPaladin",
    PALADIN_2 = "HolyPaladin",     -- Retribution (class spells match Holy DB)
    PALADIN_3 = "HolyPaladin",     -- Protection (class spells match Holy DB)
    EVOKER_2  = "PreservationEvoker",
    EVOKER_3  = "AugmentationEvoker",
    DRUID_4   = "RestorationDruid",
    PRIEST_1  = "DisciplinePriest",
    PRIEST_2  = "HolyPriest",
}

-- ============================================================
-- DATABASE
-- Per-spec signature maps + Cell-specific classification table.
-- Signature format: "RAID:RAID_IN_COMBAT:EXTERNAL_DEFENSIVE:RAID_PLAYER_DISPELLABLE"
-- All filters use PLAYER|HELPFUL| prefix (source = player).
-- ============================================================

-- Maps spec key → { ["1:1:1:0"] = "AuraName", ... }
-- Only includes UNIQUE signatures per spec (no intra-spec overlaps).
-- Overlapping signatures use cast-timing or other mechanisms instead.
local SpecAuraSignatures = {
    MistweaverMonk = {
        ["1:1:1:0"] = "LifeCocoon",
        ["0:1:0:1"] = "StrengthOfTheBlackOx",
    },
    HolyPaladin = {
        ["1:1:1:1"] = "BlessingOfProtection",
        ["1:1:1:0"] = "BlessingOfSacrifice",
        ["1:0:0:1"] = "BlessingOfFreedom",
        ["0:1:0:0"] = "HolyArmaments",
        -- Dawnlight shares signature "0:1:0:0" but is a heal tracked by
        -- spellId in Step 1 / Healers indicator. When secret in combat,
        -- fingerprint resolves to HolyArmaments (the CD-relevant one).
    },
    PreservationEvoker = {
        ["1:1:1:0"] = "TimeDilation",
        ["1:1:0:0"] = "Rewind",
        -- "0:1:0:0" skipped — VerdantEmbrace / Lifebind overlap
    },
    RestorationDruid = {
        ["1:1:1:0"] = "Ironbark",
    },
    DisciplinePriest = {
        ["1:1:1:0"] = "PainSuppression",
        ["1:0:0:1"] = "PowerInfusion",
    },
    HolyPriest = {
        ["1:1:1:0"] = "GuardianSpirit",
        ["1:0:0:1"] = "PowerInfusion",
    },
    AugmentationEvoker = {
        ["0:1:0:0"] = "SensePower",
        -- EbonMight shares signature "0:1:0:0" but is a player self-buff
        -- (never appears on raid/party frames in combat), so no collision.
    },
    -- RestorationShaman: no secret auras in Midnight (all spell IDs readable).
}

-- Maps aura name → "defensive" | "external" for Cell's indicator system.
-- An aura not in this table is identified but not classified as a CD.
local AuraClassification = {
    -- Mistweaver Monk
    LifeCocoon           = "external",
    StrengthOfTheBlackOx = "defensive",
    -- Holy Paladin
    BlessingOfProtection = "external",
    BlessingOfSacrifice  = "external",
    BlessingOfFreedom    = "external",
    HolyArmaments        = "external",
    -- Preservation Evoker
    TimeDilation         = "external",
    Rewind               = "external",
    -- Restoration Druid
    Ironbark             = "external",
    -- Discipline Priest
    PainSuppression      = "external",
    PowerInfusion        = "external",
    -- Augmentation Evoker
    SensePower           = "external",
    -- Holy Priest
    GuardianSpirit       = "external",
    -- PowerInfusion shares name with Discipline — already mapped above
}

-- ============================================================
-- SPEC DETECTION (with cache)
-- ============================================================

local _specKeyCache
local _specSignatures

--- Get signature lookup table for the player's current spec.
--- Uses UnitClassBase (always English) + specIndex for locale-independent
--- spec detection (unlike GetSpecializationInfo which returns localized names).
--- Caches result; re-detects on spec change.
--- @return table|nil  Signature → auraName table, or nil if unknown spec.
local function GetSpecSignatures()
    local specIndex = _GetSpecialization()
    if not specIndex then return nil end
    local classToken = _UnitClassBase("player")
    if not classToken then return nil end
    local mapKey = classToken .. "_" .. specIndex
    if mapKey ~= _specKeyCache then
        local specKey = SpecMap[mapKey]
        _specSignatures = SpecAuraSignatures[specKey]
        _specKeyCache = mapKey
    end
    return _specSignatures
end

-- ============================================================
-- SIGNATURE BUILDING
-- Four filter calls → "0:0:0:0" to "1:1:1:1"
-- ============================================================

local FILTER_RAID = "PLAYER|HELPFUL|RAID"
local FILTER_RIC  = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local FILTER_EXT  = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local FILTER_DISP = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"

--- Build a 4-bit filter signature string.
--- Returns nil if the API is unavailable or a filter returns non-boolean.
--- Early-exit: returns nil if aura fails both RAID and RAID_IN_COMBAT
--- (must be a player-sourced aura of some importance).
--- @param unit string Unit token
--- @param auraInstanceID number Blizzard aura instance ID
--- @return string|nil e.g. "1:1:1:0"
local function BuildSignature(unit, auraInstanceID)
    if not _IsAuraFilteredOut then return nil end

    -- CRÍTICO: chequear el resultado CRUDO del API, NO después de not nil.
    -- `not nil = true`, y type(true) = "boolean" no detecta nil original.
    -- Si el API devuelve nil (ej. Midnight para auras de otros jugadores con
    -- filtro PLAYER), debemos bail out — no asumir "passes" por defecto.
    local raidResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_RAID)
    if type(raidResult) ~= "boolean" then return nil end
    local passesRaid = not raidResult

    local ricResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_RIC)
    if type(ricResult) ~= "boolean" then return nil end
    local passesRic = not ricResult

    -- Early exit: aura must pass at least one player-priority filter.
    if not (passesRaid or passesRic) then return nil end

    local extResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_EXT)
    if type(extResult) ~= "boolean" then return nil end
    local passesExt = not extResult

    local dispResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_DISP)
    if type(dispResult) ~= "boolean" then return nil end
    local passesDisp = not dispResult

    return (passesRaid and "1" or "0") .. ":" ..
           (passesRic  and "1" or "0") .. ":" ..
           (passesExt  and "1" or "0") .. ":" ..
           (passesDisp and "1" or "0")
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Identify a secret aura by its filter fingerprint.
--- Returns the aura name and its Cell classification (if any).
--- Returns nil if the aura is not in the fingerprint DB or is not a CD.
--- @param unit string Unit token
--- @param auraInstanceID number Blizzard aura instance ID
--- @return string|nil auraName  e.g. "LifeCocoon"
--- @return string|nil kind      "defensive" or "external"
function Cell.IdentifySecretAura(unit, auraInstanceID)
    if F.IsSecretAuraUnitTrustworthy and not F.IsSecretAuraUnitTrustworthy(unit) then
        return
    end

    local sigs = GetSpecSignatures()
    if not sigs then return end

    local sig = BuildSignature(unit, auraInstanceID)
    if not sig then return end

    local auraName = sigs[sig]
    if not auraName then return end

    local kind = AuraClassification[auraName]
    if not kind then return end  -- known aura but not a Cell CD

    return auraName, kind
end
