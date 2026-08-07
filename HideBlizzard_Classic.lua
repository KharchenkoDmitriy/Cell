local _, Cell = ...
local F = Cell.funcs

-- Classic / TBC / Wrath / Cata / MoP Hide Blizzard.
-- Keep this separate from retail HideBlizzard.lua (Midnight secret-taint path).

local hiddenParent = CreateFrame("Frame", nil, _G.UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

local function KeepHidden(frame)
    if not frame or frame.__cellKeepHidden then return end
    frame.__cellKeepHidden = true
    frame:HookScript("OnShow", frame.Hide)
end

local function HideFrame(frame)
    if not frame then return end

    frame:UnregisterAllEvents()
    frame:Hide()
    frame:SetParent(hiddenParent)
    KeepHidden(frame)

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
        KeepHidden(_G.CompactPartyFrame)
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
            HideFrame(_G["CompactPartyMemberFrame" .. i])
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
        KeepHidden(_G.CompactRaidFrameContainer)
    end

    for i = 1, 8 do
        local group = _G["CompactRaidGroup" .. i]
        if group then
            group:UnregisterAllEvents()
            group:SetParent(hiddenParent)
            KeepHidden(group)
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
        KeepHidden(_G.CompactRaidFrameManager)
    end
end
