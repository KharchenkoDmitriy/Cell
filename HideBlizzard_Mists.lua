local _, Cell = ...
local F = Cell.funcs

-- MoP Classic (5.5.x) Hide Blizzard.
-- Keep separate from HideBlizzard_Classic.lua (Vanilla/TBC/Wrath/Cata) and retail
-- HideBlizzard.lua (Midnight). Do NOT HookScript("OnShow") on Compact* frames —
-- that taints secure updates (ADDON_ACTION_BLOCKED on CompactPartyFrameMemberN:SetSize).

local hiddenParent = CreateFrame("Frame", nil, _G.UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

--- Post-hook Show (not HookScript) so secure OnShow stays clean; we only re-hide OOC.
local function SoftKeepHidden(frame)
    if not frame or frame.__cellSoftKeepHidden then return end
    frame.__cellSoftKeepHidden = true
    if type(frame.Show) ~= "function" then return end
    hooksecurefunc(frame, "Show", function(self)
        if InCombatLockdown() then return end
        if self.IsShown and self:IsShown() then
            self:Hide()
        end
    end)
end

local function HideFrame(frame)
    if not frame then return end

    frame:UnregisterAllEvents()
    frame:Hide()
    frame:SetParent(hiddenParent)
    SoftKeepHidden(frame)

    local health = frame.healthBar or frame.healthbar
    if health then
        health:UnregisterAllEvents()
    end

    local power = frame.manabar
    if power then
        power:UnregisterAllEvents()
    end

    local spell = frame.castBar or frame.spellbar
    if spell then
        spell:UnregisterAllEvents()
    end

    local altpowerbar = frame.powerBarAlt
    if altpowerbar then
        altpowerbar:UnregisterAllEvents()
    end

    local buffFrame = frame.BuffFrame
    if buffFrame then
        buffFrame:UnregisterAllEvents()
    end

    local petFrame = frame.PetFrame
    if petFrame then
        petFrame:UnregisterAllEvents()
    end
end

function F.HideBlizzardParty()
    _G.UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")

    if _G.CompactPartyFrame then
        _G.CompactPartyFrame:UnregisterAllEvents()
        _G.CompactPartyFrame:SetParent(hiddenParent)
        _G.CompactPartyFrame:Hide()
        SoftKeepHidden(_G.CompactPartyFrame)
    end

    if _G.PartyFrame then
        _G.PartyFrame:UnregisterAllEvents()
        _G.PartyFrame:SetScript("OnShow", nil)
        if _G.PartyFrame.PartyMemberFramePool then
            for frame in _G.PartyFrame.PartyMemberFramePool:EnumerateActive() do
                HideFrame(frame)
            end
        end
        HideFrame(_G.PartyFrame)
    else
        for i = 1, 4 do
            HideFrame(_G["PartyMemberFrame" .. i])
            -- CompactPartyMemberFrame* intentionally not SoftKeepHidden (secure SetSize taint)
            local compactMember = _G["CompactPartyMemberFrame" .. i]
            if compactMember then
                compactMember:UnregisterAllEvents()
                compactMember:Hide()
                compactMember:SetParent(hiddenParent)
            end
        end
        if _G.PartyMemberBackground then
            HideFrame(_G.PartyMemberBackground)
        end
    end
end

function F.HideBlizzardRaid()
    _G.UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")

    if _G.CompactRaidFrameContainer then
        _G.CompactRaidFrameContainer:UnregisterAllEvents()
        _G.CompactRaidFrameContainer:SetParent(hiddenParent)
        _G.CompactRaidFrameContainer:Hide()
        SoftKeepHidden(_G.CompactRaidFrameContainer)
    end

    for i = 1, 8 do
        local group = _G["CompactRaidGroup" .. i]
        if group then
            group:UnregisterAllEvents()
            group:SetParent(hiddenParent)
            group:Hide()
            SoftKeepHidden(group)
        end
    end
end

function F.HideBlizzardRaidManager()
    if CompactRaidFrameManager_SetSetting then
        CompactRaidFrameManager_SetSetting("IsShown", "0")
    end

    if _G.CompactRaidFrameManager then
        _G.CompactRaidFrameManager:UnregisterAllEvents()
        _G.CompactRaidFrameManager:SetParent(hiddenParent)
        _G.CompactRaidFrameManager:Hide()
        SoftKeepHidden(_G.CompactRaidFrameManager)
    end
end

-- Classic/MoP often re-shows Blizzard frames after roster churn — reinforce OOC only.
local reinforce = CreateFrame("Frame")
reinforce:RegisterEvent("PLAYER_ENTERING_WORLD")
reinforce:RegisterEvent("GROUP_ROSTER_UPDATE")
reinforce:RegisterEvent("PLAYER_REGEN_ENABLED")
reinforce:SetScript("OnEvent", function()
    if InCombatLockdown() then return end
    if type(CellDB) ~= "table" or type(CellDB.general) ~= "table" then return end
    if CellDB.general.hideBlizzardParty then
        F.HideBlizzardParty()
    end
    if CellDB.general.hideBlizzardRaid then
        F.HideBlizzardRaid()
    end
    if CellDB.general.hideBlizzardRaidManager then
        F.HideBlizzardRaidManager()
    end
end)
