local _, Cell = ...
local F = Cell.funcs

Cell.vars.editModeOpen = false

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local hardDisabled = false
local partyUpdateHooked = false
local editModeHooked = false

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

local function SafeCall(fn)
    pcall(fn)
end

local function SetFrameAlpha(frame, alpha)
    if not frame then return end
    if FrameIsForbidden(frame) then return end
    pcall(frame.SetAlpha, frame, alpha)
end

local function ReparentToHidden(frame)
    if not frame then return end
    if InCombatLockdown() then return end
    if FrameIsForbidden(frame) then return end
    SafeCall(function()
        frame:UnregisterAllEvents()
        frame:SetParent(hiddenParent)
        frame:Hide()
    end)
end

local function QuietTraditionalWidget(frame)
    if not frame then return end
    if FrameIsForbidden(frame) then return end
    pcall(frame.UnregisterAllEvents, frame)
    pcall(frame.SetScript, frame, "OnEvent", nil)
    pcall(frame.SetScript, frame, "OnUpdate", nil)
end

local function QuietTraditionalMember(frame)
    if not frame then return end
    QuietTraditionalWidget(frame)
    QuietTraditionalWidget(frame.PetFrame)
    QuietTraditionalWidget(frame.healthbar or frame.HealthBar)
    QuietTraditionalWidget(frame.manabar or frame.ManaBar)
    QuietTraditionalWidget(frame.HealthBarContainer or frame.HealthBarsContainer)
    QuietTraditionalWidget(frame.AuraFrameContainer)
    QuietTraditionalWidget(frame.tempMaxHealthLossBar)
    if frame.PetFrame then
        QuietTraditionalWidget(frame.PetFrame.HealthBar or frame.PetFrame.healthbar)
        QuietTraditionalWidget(frame.PetFrame.ManaBar or frame.PetFrame.manabar)
    end
    ReparentToHidden(frame)
    if frame.PetFrame then
        ReparentToHidden(frame.PetFrame)
    end
end

local function ForEachTraditionalPartyMember(fn)
    local pf = _G.PartyFrame
    if pf and pf.PartyMemberFramePool then
        for frame in pf.PartyMemberFramePool:EnumerateActive() do
            fn(frame)
        end
        for i = 1, (_G.MAX_PARTY_MEMBERS or 4) do
            fn(pf["MemberFrame" .. i])
        end
    else
        for i = 1, 4 do
            fn(_G["PartyMemberFrame" .. i])
        end
    end
end

local function HookPartyFrameUpdates()
    if partyUpdateHooked then return end
    local pf = _G.PartyFrame
    if not pf or type(pf.UpdatePartyFrames) ~= "function" then return end
    partyUpdateHooked = true
    hooksecurefunc(pf, "UpdatePartyFrames", function()
        if not ShouldHideBlizzardParty() then return end
        ForEachTraditionalPartyMember(QuietTraditionalMember)
        ReparentToHidden(pf)
    end)
end

local function HardDisableBlizzardFrames()
    if hardDisabled then return true end
    if InCombatLockdown() then return false end
    if not (ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager()) then
        return false
    end

    HookPartyFrameUpdates()

    if ShouldHideBlizzardParty() then
        ForEachTraditionalPartyMember(QuietTraditionalMember)
        ReparentToHidden(_G.PartyFrame)
        ReparentToHidden(_G.PartyMemberBackground)
        SetFrameAlpha(_G.CompactPartyFrame, 0)
    end

    if ShouldHideBlizzardRaid() then
        SetFrameAlpha(_G.CompactRaidFrameContainer, 0)
        for i = 1, 8 do
            SetFrameAlpha(_G["CompactRaidGroup" .. i], 0)
        end
    end

    if ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager() then
        ReparentToHidden(_G.CompactRaidFrameManager)
        if CompactRaidFrameManager_SetSetting then
            pcall(CompactRaidFrameManager_SetSetting, "IsShown", "0")
        end
    end

    hardDisabled = true
    return true
end

local function SuppressBlizzParty()
    if not ShouldHideBlizzardParty() then return end
    HookPartyFrameUpdates()
    ForEachTraditionalPartyMember(QuietTraditionalMember)
    SetFrameAlpha(_G.PartyFrame, 0)
    SetFrameAlpha(_G.PartyMemberBackground, 0)
    SetFrameAlpha(_G.CompactPartyFrame, 0)
end

local function SuppressBlizzRaid()
    if not ShouldHideBlizzardRaid() then return end
    SetFrameAlpha(_G.CompactRaidFrameContainer, 0)
    for i = 1, 8 do
        SetFrameAlpha(_G["CompactRaidGroup" .. i], 0)
    end
end

local function SuppressBlizzRaidManager()
    if not ShouldHideBlizzardRaidManager() then return end
    SetFrameAlpha(_G.CompactRaidFrameManager, 0)
end

local function TrySuppressForGroup()
    HardDisableBlizzardFrames()
    SuppressBlizzRaid()
    SuppressBlizzRaidManager()
    SuppressBlizzParty()
end

local function QueueSuppress()
    C_Timer.After(0, TrySuppressForGroup)
end

local function HookEditMode()
    if editModeHooked then return end
    local em = _G.EditModeManagerFrame
    if not em or type(em.EnterEditMode) ~= "function" then return end
    editModeHooked = true

    hooksecurefunc(em, "EnterEditMode", function()
        Cell.vars.editModeOpen = true
    end)

    if type(em.ExitEditMode) == "function" then
        hooksecurefunc(em, "ExitEditMode", function()
            Cell.vars.editModeOpen = false
            QueueSuppress()
        end)
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("GROUP_ROSTER_UPDATE")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:RegisterEvent("ADDON_LOADED")
pcall(boot.RegisterEvent, boot, "EDIT_MODE_LAYOUTS_UPDATED")
boot:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "Blizzard_EditMode" then
            HookEditMode()
        end
        if addonName == "Blizzard_UnitFrame"
            or addonName == "Blizzard_EditMode"
            or addonName == "Blizzard_RaidFrame"
            or addonName == "Blizzard_CompactRaidFrames" then
            HookPartyFrameUpdates()
            QueueSuppress()
        end
        return
    end

    HookEditMode()
    QueueSuppress()
end)

function F.HideBlizzardParty()
    HookEditMode()
    TrySuppressForGroup()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaid()
    HookEditMode()
    TrySuppressForGroup()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaidManager()
    HookEditMode()
    TrySuppressForGroup()
    C_Timer.After(0.5, TrySuppressForGroup)
end
