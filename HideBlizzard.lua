local _, Cell = ...
local F = Cell.funcs

Cell.vars.editModeOpen = false

local hardDisabled = false
local editModeHooked = false
local visibilityTicker

local function ShouldHideBlizzardParty()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardParty"]
end

local function ShouldHideBlizzardRaid()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaid"]
end

local function ShouldHideBlizzardRaidManager()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaidManager"]
end

function F.IsEditModeOpen()
    return Cell.vars.editModeOpen == true
end

local function FrameIsForbidden(frame)
    if not frame then return true end
    local ok, forbidden = pcall(function()
        return frame.IsForbidden and frame:IsForbidden()
    end)
    return (not ok) or forbidden
end

local function SetFrameAlpha(frame, alpha)
    if not frame or FrameIsForbidden(frame) then return end
    pcall(frame.SetAlpha, frame, alpha)
end

local function HideSelectionHighlight(frame)
    if not frame or FrameIsForbidden(frame) then return end
    local hl = frame.selectionHighlight
    if hl then
        pcall(hl.SetShown, hl, false)
        pcall(hl.SetAlpha, hl, 0)
        pcall(hl.SetIgnoreParentAlpha, hl, false)
    end
    local ind = frame.selectionIndicator
    if ind then
        pcall(ind.SetShown, ind, false)
        pcall(ind.SetAlpha, ind, 0)
    end
end

local function ForEachCompactPartyMember(func)
    local members = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, members do
        func(_G["CompactPartyFrameMember" .. i])
        func(_G["CompactPartyFramePet" .. i])
    end
    local cpf = _G.CompactPartyFrame
    if cpf then
        if cpf.memberUnitFrames then
            for _, frame in ipairs(cpf.memberUnitFrames) do
                func(frame)
            end
        end
        if cpf.petUnitFrames then
            for _, frame in ipairs(cpf.petUnitFrames) do
                func(frame)
            end
        end
    end
end

local function ForEachCompactRaidMember(func)
    local members = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, 8 do
        for m = 1, members do
            func(_G["CompactRaidGroup" .. i .. "Member" .. m])
        end
    end
    for i = 1, 80 do
        func(_G["CompactRaidFrame" .. i])
    end
end

local function HideGoldHighlights()
    if ShouldHideBlizzardParty() then
        HideSelectionHighlight(_G.CompactPartyFrame)
        ForEachCompactPartyMember(HideSelectionHighlight)
    end
    if ShouldHideBlizzardRaid() then
        ForEachCompactRaidMember(HideSelectionHighlight)
    end
end

local function QuietCompactParty()
    local cpf = _G.CompactPartyFrame
    SetFrameAlpha(cpf, 0)
    if cpf then
        SetFrameAlpha(cpf.title, 0)
        SetFrameAlpha(cpf.borderFrame, 0)
        HideSelectionHighlight(cpf)
    end
    ForEachCompactPartyMember(HideSelectionHighlight)
end

local function QuietCompactRaid()
    SetFrameAlpha(_G.CompactRaidFrameContainer, 0)
    for i = 1, 8 do
        SetFrameAlpha(_G["CompactRaidGroup" .. i], 0)
    end
    ForEachCompactRaidMember(HideSelectionHighlight)
end

local function QuietRaidManager()
    SetFrameAlpha(_G.CompactRaidFrameManager, 0)
end

local function ApplyHiddenBlizzard()
    if ShouldHideBlizzardParty() then
        QuietCompactParty()
    end
    if ShouldHideBlizzardRaid() then
        QuietCompactRaid()
    end
    if ShouldHideBlizzardRaidManager() then
        QuietRaidManager()
    end
    HideGoldHighlights()
end

local function HardDisableBlizzardFrames()
    if hardDisabled then return true end
    if InCombatLockdown() then return false end
    if not (ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager()) then
        return false
    end
    ApplyHiddenBlizzard()
    hardDisabled = true
    return true
end

local function TrySuppressForGroup()
    HardDisableBlizzardFrames()
    ApplyHiddenBlizzard()
end

local function QueueSuppress()
    C_Timer.After(0, TrySuppressForGroup)
end

local function EnsureVisibilityTicker()
    if visibilityTicker then return end
    if not (ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager()) then
        return
    end
    visibilityTicker = C_Timer.NewTicker(1, function()
        if InCombatLockdown() then return end
        if ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager() then
            ApplyHiddenBlizzard()
        end
    end)
end

local function HookEditMode()
    if editModeHooked then return end
    local em = _G.EditModeManagerFrame
    if not em then return end
    editModeHooked = true

    em:HookScript("OnShow", function()
        Cell.vars.editModeOpen = true
        C_Timer.After(0, TrySuppressForGroup)
    end)

    em:HookScript("OnHide", function()
        Cell.vars.editModeOpen = false
        C_Timer.After(0.25, TrySuppressForGroup)
    end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:RegisterEvent("PLAYER_TARGET_CHANGED")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "Blizzard_EditMode"
            or addonName == "Blizzard_UnitFrame"
            or addonName == "Blizzard_CompactRaidFrames"
            or addonName == "Blizzard_RaidFrame"
            or addonName == "Blizzard_Game" then
            HookEditMode()
            QueueSuppress()
            EnsureVisibilityTicker()
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        HideGoldHighlights()
        return
    end

    HookEditMode()
    QueueSuppress()
    EnsureVisibilityTicker()
end)

function F.HideBlizzardParty()
    HookEditMode()
    hardDisabled = false
    QueueSuppress()
    EnsureVisibilityTicker()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaid()
    HookEditMode()
    QueueSuppress()
    EnsureVisibilityTicker()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaidManager()
    HookEditMode()
    QueueSuppress()
    EnsureVisibilityTicker()
    C_Timer.After(0.5, TrySuppressForGroup)
end
