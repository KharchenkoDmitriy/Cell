-- ============================================================
-- AuraBlacklist — Global blacklist for buffs and debuffs.
--
-- Allows users to hide specific auras from ALL indicators
-- (Healers, Externals, Defensives, Custom) with separate
-- Combat / OOC toggles per spell.
--
-- Storage: CellDB["auraBlacklist"] = {
--     buffs = { [spellId] = { combat = true, ooc = false }, ... },
--     debuffs = { [spellId] = { combat = true, ooc = true }, ... },
-- }
--
-- Alternate spell IDs (e.g. Earth Shield 974 ↔ 383648) are
-- mapped so blacklisting the primary ID covers all variants.
-- ============================================================

local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

local InCombatLockdown = InCombatLockdown
local pairs = pairs
local tinsert = table.insert

-- ============================================================
-- ALTERNATE SPELL ID MAP
-- Maps secondary/alternate spell IDs to their primary ID.
-- When checking IsAuraBlacklisted, if the aura's spell ID is
-- not found directly, we check if it has a primary via this
-- map and check that instead.
-- ============================================================
local AlternateSpellIDs = {
    -- Earth Shield: talent version → base
    [383648] = 974,
    -- Earthliving Weapon variants → primary
    [382021] = 382024,
    [382022] = 382024,
    -- Symbiotic Relationship: target auras → caster aura
    [474750] = 474754,
    [474760] = 474754,
    -- Holy Armaments: Holy Bulwark → Sacred Weapon (primary)
    [432496] = 432502,
    -- Tidecaller's Guard variant
    [457481] = 457496,
    -- Thunderstrike Ward variant
    [462742] = 462757,
    -- Exhaustion variants → Sated
    [390435] = 57723,
    [428628] = 57723,
    -- Fatigued variant
    [264689] = 160455,
    -- Blessing of the Bronze: class-specific buffs → Evoker primary
    [381732] = 381748,  -- Death Knight
    [381741] = 381748,  -- Demon Hunter
    [381746] = 381748,  -- Druid
    [381749] = 381748,  -- Hunter
    [381750] = 381748,  -- Mage
    [381751] = 381748,  -- Monk
    [381752] = 381748,  -- Paladin
    [381753] = 381748,  -- Priest
    [381754] = 381748,  -- Rogue
    [381756] = 381748,  -- Shaman
    [381757] = 381748,  -- Warlock
    [381758] = 381748,  -- Warrior
}

-- ============================================================
-- RESOLVE PRIMARY ID
-- Returns the primary spell ID to check in the blacklist.
-- Falls back to the input itself if no alternate mapping exists.
-- ============================================================
local function ResolvePrimary(spellId)
    if spellId and AlternateSpellIDs[spellId] then
        return AlternateSpellIDs[spellId]
    end
    return spellId
end

-- ============================================================
-- IS BLACKLISTED STATE
-- Given a blacklist entry (nil, true, or {combat, ooc}), returns
-- whether the spell should be hidden RIGHT NOW.
-- true → always hidden. table → depends on combat state.
-- ============================================================
local function IsBlacklistedState(entry)
    if not entry then return false end
    -- Legacy support: plain true = always blacklisted
    if entry == true then return true end
    -- Table format: check combat/ooc flags
    if InCombatLockdown() then
        return entry.combat
    end
    return entry.ooc
end

-- ============================================================
-- IsAuraBlacklisted(spellId, filter)
-- Returns true if the given spell is blacklisted for the
-- current combat state.
--   spellId : number — the aura's spell ID
--   filter  : "HELPFUL" | "HARMFUL" — which table to check
-- Returns boolean.
-- ============================================================
function F.IsAuraBlacklisted(spellId, filter)
    if not spellId then return false end
    if not (CellDB and CellDB["auraBlacklist"]) then return false end

    local bl = CellDB["auraBlacklist"][filter]
    if not bl then
        if filter == "HARMFUL" then
            bl = CellDB["auraBlacklist"]["debuffs"]
        elseif filter == "HELPFUL" then
            bl = CellDB["auraBlacklist"]["buffs"]
        end
    end
    if not bl then return false end

    -- Direct entry check
    local entry = bl[spellId]
    if entry and IsBlacklistedState(entry) then return true end

    -- Alternate spell ID check
    local pId = AlternateSpellIDs[spellId]
    if pId then
        entry = bl[pId]
        if entry and IsBlacklistedState(entry) then return true end
    end

    return false
end

-- ============================================================
-- ToggleAuraBlacklist(spellId, filter, combat, ooc)
-- Sets or clears a blacklist entry for the given spell.
--   combat : boolean — blacklisted in combat (nil to remove)
--   ooc    : boolean — blacklisted out of combat (nil to remove)
-- If both are false/nil, the entry is removed entirely.
-- ============================================================
function F.ToggleAuraBlacklist(spellId, filter, combat, ooc)
    if not spellId then return end

    local bl = CellDB["auraBlacklist"]
    if not bl[filter] then bl[filter] = {} end
    local list = bl[filter]

    if combat or ooc then
        list[spellId] = { combat = combat or false, ooc = ooc or false }
    else
        list[spellId] = nil
    end
end

-- ============================================================
-- RemoveAuraBlacklist(spellId, filter)
-- Convenience: remove a spell from blacklist entirely.
-- ============================================================
function F.RemoveAuraBlacklist(spellId, filter)
    if not spellId or not filter then return end
    local list = CellDB["auraBlacklist"][filter]
    if list then
        list[spellId] = nil
    end
end

-- ============================================================
-- GetAuraBlacklistEntry(spellId, filter)
-- Returns the blacklist entry for a spell: { combat, ooc }
-- or nil if not blacklisted.
-- ============================================================
function F.GetAuraBlacklistEntry(spellId, filter)
    if not spellId or not filter then return nil end
    local list = CellDB["auraBlacklist"][filter]
    if not list then return nil end

    -- Direct check
    local entry = list[spellId]
    if entry then return entry end

    -- Alternate ID check
    local primary = AlternateSpellIDs[spellId]
    if primary and list[primary] then
        return list[primary]
    end

    return nil
end

-- ============================================================
-- GetAuraBlacklistCount(filter)
-- Returns how many spells are currently blacklisted for filter.
-- ============================================================
function F.GetAuraBlacklistCount(filter)
    local list = CellDB["auraBlacklist"][filter]
    if not list then return 0 end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    return count
end

-- ============================================================
-- BUFF LIST BY CLASS (for the options UI)
-- Organized so the UI can display spells per class with icons.
-- Each entry: { spellId = number, display = string, icon = number }
-- We reuse Cell's own data where possible.
-- ============================================================

-- Icon texture cache — resolved once at init
local iconCache = {}

--- Resolve a spell icon, caching the result.
--- @param spellId number
--- @return number texture ID (or fallback)
local function GetSpellIcon(spellId)
    if iconCache[spellId] then return iconCache[spellId] end
    local icon = select(2, F.GetSpellInfo(spellId))
    if not icon then icon = 134400 end  -- fallback: "?"
    iconCache[spellId] = icon
    return icon
end

-- ============================================================
-- Helper: build a spell entry for the UI list
-- ============================================================
local function SpellEntry(spellId, display)
    return { spellId = spellId, display = display, icon = GetSpellIcon(spellId) }
end

-- ============================================================
-- SPELL DATA — organized by class AND spec
-- Healer buffs + raid buffs.
-- Healer classes (DRUID, PRIEST, PALADIN, SHAMAN, MONK, EVOKER)
-- use spec-indexed tables so the UI can filter by spec.
-- Non-healer classes use flat arrays shared across all specs.
-- ============================================================

local BuffSpellsBySpec = {
    DRUID = {
        [1] = { SpellEntry(1126, "Mark of the Wild"), },                     -- Balance
        [2] = { SpellEntry(1126, "Mark of the Wild"), },                     -- Feral
        [3] = { SpellEntry(1126, "Mark of the Wild"), },                     -- Guardian
        [4] = {                                                              -- Restoration
            SpellEntry(155777, "Germination"),
            SpellEntry(33763,  "Lifebloom"),
            SpellEntry(1126,   "Mark of the Wild"),
            SpellEntry(8936,   "Regrowth"),
            SpellEntry(774,    "Rejuvenation"),
            SpellEntry(474754, "Symbiotic Relationship"),
            SpellEntry(439530, "Symbiotic Blooms"),
            SpellEntry(48438,  "Wild Growth"),
        },
    },
    PRIEST = {
        [1] = {                                                              -- Discipline
            SpellEntry(194384, "Atonement"),
            SpellEntry(17,     "Power Word: Shield"),
            SpellEntry(21562,  "Power Word: Fortitude"),
            SpellEntry(41635,  "Prayer of Mending"),
            SpellEntry(139,    "Renew"),
            SpellEntry(1253593,"Void Shield"),
        },
        [2] = {                                                              -- Holy
            SpellEntry(77489,  "Echo of Light"),
            SpellEntry(17,     "Power Word: Shield"),
            SpellEntry(21562,  "Power Word: Fortitude"),
            SpellEntry(41635,  "Prayer of Mending"),
            SpellEntry(139,    "Renew"),
            SpellEntry(1253593,"Void Shield"),
        },
        [3] = {                                                              -- Shadow
            SpellEntry(21562,  "Power Word: Fortitude"),
            SpellEntry(1253593,"Void Shield"),
        },
    },
    PALADIN = {
        [1] = {                                                              -- Holy
            SpellEntry(156910, "Beacon of Faith"),
            SpellEntry(53563,  "Beacon of Light"),
            SpellEntry(1244893,"Beacon of the Savior"),
            SpellEntry(200025, "Beacon of Virtue"),
            SpellEntry(156322, "Eternal Flame"),
            SpellEntry(432502, "Holy Armaments"),
            SpellEntry(433583, "Rite of Adjuration"),
            SpellEntry(433568, "Rite of Sanctification"),
        },
        [2] = {},                                                             -- Protection
        [3] = {},                                                            -- Retribution
    },
    SHAMAN = {
        [1] = {                                                              -- Elemental
            SpellEntry(462854, "Skyfury"),
            SpellEntry(369459, "Source of Magic"),
            SpellEntry(462757, "Thunderstrike Ward"),
            SpellEntry(20608,  "Reincarnation"),
        },
        [2] = {                                                              -- Enhancement
            SpellEntry(319778, "Flametongue Weapon"),
            SpellEntry(319773, "Windfury Weapon"),
            SpellEntry(462854, "Skyfury"),
            SpellEntry(369459, "Source of Magic"),
            SpellEntry(462757, "Thunderstrike Ward"),
            SpellEntry(20608,  "Reincarnation"),
        },
        [3] = {                                                              -- Restoration
            SpellEntry(207400, "Ancestral Vigor"),
            SpellEntry(974,    "Earth Shield"),
            SpellEntry(382024, "Earthliving Weapon"),
            SpellEntry(444490, "Hydrobubble"),
            SpellEntry(61295,  "Riptide"),
            SpellEntry(457496, "Tidecaller's Guard"),
            SpellEntry(462854, "Skyfury"),
            SpellEntry(369459, "Source of Magic"),
            SpellEntry(462757, "Thunderstrike Ward"),
            SpellEntry(20608,  "Reincarnation"),
        },
    },
    MONK = {
        [1] = {},                                                             -- Brewmaster
        [2] = {                                                              -- Mistweaver
            SpellEntry(450769, "Aspect of Harmony"),
            SpellEntry(124682, "Enveloping Mist"),
            SpellEntry(119611, "Renewing Mist"),
            SpellEntry(115175, "Soothing Mist"),
        },
        [3] = {},                                                             -- Windwalker
    },
    EVOKER = {
        [1] = {                                                              -- Devastation
            SpellEntry(381748, "Blessing of the Bronze"),
            SpellEntry(410263, "Inferno's Blessing"),
            SpellEntry(369459, "Source of Magic"),
        },
        [2] = {                                                              -- Augmentation
            SpellEntry(360827, "Blistering Scales"),
            SpellEntry(395152, "Ebon Might"),
            SpellEntry(410089, "Prescience"),
            SpellEntry(413984, "Shifting Sands"),
            SpellEntry(381748, "Blessing of the Bronze"),
            SpellEntry(410686, "Symbiotic Bloom"),
            SpellEntry(369459, "Source of Magic"),
        },
        [3] = {                                                              -- Preservation
            SpellEntry(355941, "Dream Breath"),
            SpellEntry(363502, "Dream Flight"),
            SpellEntry(364343, "Echo"),
            SpellEntry(376788, "Echo Dream Breath"),
            SpellEntry(367364, "Echo Reversion"),
            SpellEntry(373267, "Lifebind"),
            SpellEntry(366155, "Reversion"),
            SpellEntry(381748, "Blessing of the Bronze"),
            SpellEntry(410686, "Symbiotic Bloom"),
            SpellEntry(369459, "Source of Magic"),
        },
    },
    MAGE = {
        SpellEntry(1459,   "Arcane Intellect"),
        SpellEntry(205473, "Icicles"),
    },
    WARRIOR = {
        SpellEntry(6673,   "Battle Shout"),
    },
    ROGUE = {
        SpellEntry(381664, "Amplifying Poison"),
        SpellEntry(381637, "Atrophic Poison"),
        SpellEntry(3408,   "Crippling Poison"),
        SpellEntry(2823,   "Deadly Poison"),
        SpellEntry(315584, "Instant Poison"),
        SpellEntry(5761,   "Numbing Poison"),
        SpellEntry(8679,   "Wound Poison"),
    },
    HUNTER = {
        SpellEntry(260286, "Tip of the Spear"),
    },
}

-- ============================================================
-- Cache for class-merged spell arrays (all specs combined).
-- Built on first demand when no specIndex is given.
-- ============================================================
local mergedCache = {}

--- Check if a class entry is "flat" (shared across all specs)
--- rather than spec-indexed.
local function IsFlatFormat(entry)
    local k, v = next(entry)
    if not k then return true end
    -- If the first key is a number and its value has .spellId, it's a flat spell array
    return type(v) == "table" and v.spellId ~= nil
end

local DebuffSpells = {
    -- Sated / Exhaustion family
    { spellId = 57723,  display = "Exhaustion",             icon = GetSpellIcon(57723) },
    { spellId = 160455, display = "Fatigued",               icon = GetSpellIcon(160455) },
    { spellId = 95809,  display = "Insanity",               icon = GetSpellIcon(95809) },
    { spellId = 57724,  display = "Sated",                  icon = GetSpellIcon(57724) },
    { spellId = 80354,  display = "Temporal Displacement",  icon = GetSpellIcon(80354) },
    -- Deserter
    { spellId = 26013,  display = "BG Deserter",            icon = GetSpellIcon(26013) },
    { spellId = 71041,  display = "Dungeon Deserter",       icon = GetSpellIcon(71041) },
    -- Skyriding
    { spellId = 427490, display = "Ride Along Available",   icon = GetSpellIcon(427490) },
    { spellId = 447959, display = "Ride Along Active",      icon = GetSpellIcon(447959) },
    { spellId = 447960, display = "Ride Along Inactive",    icon = GetSpellIcon(447960) },
}

-- ============================================================
-- GETTERS — defined AFTER data tables so Lua 5.1 closures
-- capture the local variables, not global nil references.
-- ============================================================
-- GetAuraBlacklistBuffSpells(classToken, specIndex)
-- Returns an array of { spellId, display, icon } for the
-- given class (and optionally spec).
--   classToken : string (e.g. "PRIEST") or nil for ALL classes
--   specIndex  : number (1-4) to filter by spec, or nil for all specs merged
-- Used by the options UI to populate the blacklist table.
-- ============================================================
function F.GetAuraBlacklistBuffSpells(classToken, specIndex)
    if not classToken then return BuffSpellsBySpec end

    local entry = BuffSpellsBySpec[classToken]
    if not entry then return {} end

    -- Flat format (non-healer classes): all specs share the same list
    if IsFlatFormat(entry) then
        return entry
    end

    -- Spec-indexed format (healer classes)
    if specIndex and entry[specIndex] then
        return entry[specIndex]
    end

    -- No specIndex given: merge all specs with cache (deduplicated by spellId)
    if not mergedCache[classToken] then
        local merged = {}
        local seen = {}
        for _, spells in pairs(entry) do
            for _, spell in ipairs(spells) do
                if not seen[spell.spellId] then
                    seen[spell.spellId] = true
                    tinsert(merged, spell)
                end
            end
        end
        mergedCache[classToken] = merged
    end
    return mergedCache[classToken]
end

-- ============================================================
-- GetAuraBlacklistDebuffSpells()
-- Returns the array of known debuffs for blacklisting.
-- ============================================================
function F.GetAuraBlacklistDebuffSpells()
    return DebuffSpells
end

-- ============================================================
-- CLASS ORDER (for UI dropdown)
-- ============================================================
F.AuraBlacklistClassOrder = {
    "DRUID", "PRIEST", "PALADIN", "SHAMAN", "MONK", "EVOKER",
    "MAGE", "WARRIOR", "ROGUE", "HUNTER",
}

F.AuraBlacklistClassNames = {
    DRUID   = "Druid",
    PRIEST  = "Priest",
    PALADIN = "Paladin",
    SHAMAN  = "Shaman",
    MONK    = "Monk",
    EVOKER  = "Evoker",
    MAGE    = "Mage",
    WARRIOR = "Warrior",
    ROGUE   = "Rogue",
    HUNTER  = "Hunter",
}

-- ============================================================
-- Spec name lookup by class (for UI dropdown).
-- Uses static English names for consistency with the rest of
-- the AddonSkins ecosystem; GetSpecializationInfo with classIndex
-- is avoided due to API uncertainty across WoW patches.
-- ============================================================
F.AuraBlacklistSpecNames = {
    DRUID   = { "Balance", "Feral", "Guardian", "Restoration" },
    PRIEST  = { "Discipline", "Holy", "Shadow" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
    MONK    = { "Brewmaster", "Mistweaver", "Windwalker" },
    EVOKER  = { "Devastation", "Augmentation", "Preservation" },
}

-- ============================================================
-- Initialize defaults: all known blacklistable debuffs come
-- checked (combat + OOC) on first run so users can opt OUT
-- rather than opt IN. Uses a one-time flag in CellDB to
-- respect user changes after first configuration.
-- ============================================================
do
    local function InitDebuffDefaults()
        if not CellDB or not CellDB["auraBlacklist"] then return end
        if CellDB["auraBlacklist"]["_debuffInitDone"] == true then return end

        local db = CellDB["auraBlacklist"]["debuffs"]
        for _, spell in ipairs(DebuffSpells) do
            if not db[spell.spellId] then
                db[spell.spellId] = { combat = true, ooc = true }
            end
        end
        CellDB["auraBlacklist"]["_debuffInitDone"] = true
    end
    Cell.RegisterCallback("AddonLoaded", "AuraBlacklist_InitDebuffDefaults", InitDebuffDefaults)
end

-- ============================================================
-- Explicit export so the check function can be called
-- from anywhere in Cell.
Cell.AuraBlacklist = {
    AlternateSpellIDs = AlternateSpellIDs,
    BuffSpellsBySpec = BuffSpellsBySpec,
    DebuffSpells = DebuffSpells,
}
