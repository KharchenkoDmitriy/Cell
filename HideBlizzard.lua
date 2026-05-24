local _, Cell = ...
local F = Cell.funcs

-- stolen from elvui
local hiddenParent = CreateFrame("Frame", nil, _G.UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

-- IMPORTANT:
-- Do NOT overwrite Blizzard global unit-frame functions (e.g.
-- UnitFrameHealthBar_Update / UpdateTextStringWithValues), as that taints
-- execution paths used by Target/Arena/other Blizzard frames and triggers
-- secret-value errors in modern clients.
--
-- Keep our hide logic scoped to frames we explicitly reparent.

local function HideFrame(frame)
    if not frame then return end

    frame:UnregisterAllEvents()
    frame:Hide()
    frame:SetParent(hiddenParent)

    local health = frame.healthBar or frame.healthbar
    if health then
        health:UnregisterAllEvents()
        if health.SetScript then
            health:SetScript("OnValueChanged", nil)
        end
    end

    local power = frame.manabar or frame.manaBar
    if power then
        power:UnregisterAllEvents()
        if power.SetScript then
            power:SetScript("OnValueChanged", nil)
        end
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
        HideFrame(petFrame)
    end
end

function F.HideBlizzardParty()
    _G.UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")

    -- Midnight 12.0.0+ may have different party frame structure
    if _G.CompactPartyFrame then
        _G.CompactPartyFrame:UnregisterAllEvents()
        _G.CompactPartyFrame:SetParent(hiddenParent)
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
        -- Legacy party frame fallback
        for i = 1, 4 do
            HideFrame(_G["PartyMemberFrame"..i])
            HideFrame(_G["CompactPartyMemberFrame"..i])
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
    end
end

function F.HideBlizzardRaidManager()
    if CompactRaidFrameManager_SetSetting then
        CompactRaidFrameManager_SetSetting("IsShown", "0")
    end

    if _G.CompactRaidFrameManager then
        _G.CompactRaidFrameManager:UnregisterAllEvents()
        _G.CompactRaidFrameManager:SetParent(hiddenParent)
    end
end
