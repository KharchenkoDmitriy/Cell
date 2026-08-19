local _, Cell = ...
local F = Cell.funcs

Cell.vars.editModeOpen = false

local hardDisabled = false
local partyUpdateHooked = false
local partyShowHooked = false
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

local function IsEditModeShown()
    if Cell.vars.editModeOpen then return true end
    local em = _G.EditModeManagerFrame
    return em and em.IsShown and em:IsShown()
end

local function FrameIsForbidden(frame)
    if not frame then return true end
    local ok, forbidden = pcall(function()
        return frame.IsForbidden and frame:IsForbidden()
    end)
    return (not ok) or forbidden
end

local function SetFrameAlpha(frame, alpha)
    if not frame then return end
    if FrameIsForbidden(frame) then return end
    pcall(frame.SetAlpha, frame, alpha)
end

local function UnregisterFrameEvents(frame)
    if not frame then return end
    if FrameIsForbidden(frame) then return end
    pcall(frame.UnregisterAllEvents, frame)
end

local function UnregisterTree(frame)
    if not frame or FrameIsForbidden(frame) then return end
    UnregisterFrameEvents(frame)
    local ok, children = pcall(function()
        return { frame:GetChildren() }
    end)
    if not ok then return end
    for i = 1, #children do
        UnregisterTree(children[i])
    end
end

local function QuietTraditionalMember(frame)
    if not frame then return end
    UnregisterTree(frame)
    SetFrameAlpha(frame, 0)
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

local function QuietTraditionalParty()
    local pf = _G.PartyFrame
    UnregisterFrameEvents(pf)
    UnregisterFrameEvents(_G.PartyMemberBackground)
    ForEachTraditionalPartyMember(QuietTraditionalMember)
    SetFrameAlpha(pf, 0)
    SetFrameAlpha(_G.PartyMemberBackground, 0)
    SetFrameAlpha(_G.CompactPartyFrame, 0)
end

local function QuietCompactRaid()
    SetFrameAlpha(_G.CompactRaidFrameContainer, 0)
    for i = 1, 8 do
        SetFrameAlpha(_G["CompactRaidGroup" .. i], 0)
    end
end

local function QuietRaidManager()
    local manager = _G.CompactRaidFrameManager
    UnregisterFrameEvents(manager)
    SetFrameAlpha(manager, 0)
end

local function HookPartyFrameUpdates()
    if partyUpdateHooked then return end
    local pf = _G.PartyFrame
    if not pf or type(pf.UpdatePartyFrames) ~= "function" then return end
    partyUpdateHooked = true
    hooksecurefunc(pf, "UpdatePartyFrames", function()
        if not ShouldHideBlizzardParty() then return end
        QuietTraditionalParty()
    end)
end

local function HookPartyFrameShow()
    if partyShowHooked then return end
    local pf = _G.PartyFrame
    if not pf or type(pf.Show) ~= "function" then return end
    partyShowHooked = true
    hooksecurefunc(pf, "Show", function()
        if not ShouldHideBlizzardParty() then return end
        QuietTraditionalParty()
    end)
end

local function HardDisableBlizzardFrames()
    if hardDisabled then return true end
    if InCombatLockdown() then return false end
    if not (ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager()) then
        return false
    end

    HookPartyFrameUpdates()
    HookPartyFrameShow()

    if ShouldHideBlizzardParty() then
        QuietTraditionalParty()
    end

    if ShouldHideBlizzardRaid() then
        QuietCompactRaid()
    end

    if ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager() then
        QuietRaidManager()
    end

    hardDisabled = true
    return true
end

local function SuppressBlizzParty()
    if not ShouldHideBlizzardParty() then return end
    HookPartyFrameUpdates()
    HookPartyFrameShow()
    QuietTraditionalParty()
end

local function SuppressBlizzRaid()
    if not ShouldHideBlizzardRaid() then return end
    QuietCompactRaid()
end

local function SuppressBlizzRaidManager()
    if not ShouldHideBlizzardRaidManager() then return end
    QuietRaidManager()
end

local function TrySuppressForGroup()
    if not IsEditModeShown() then
        HardDisableBlizzardFrames()
    end
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
        SuppressBlizzRaid()
        SuppressBlizzRaidManager()
        SuppressBlizzParty()
    end)

    if type(em.ExitEditMode) == "function" then
        hooksecurefunc(em, "ExitEditMode", function()
            Cell.vars.editModeOpen = false
            C_Timer.After(0.25, TrySuppressForGroup)
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
    if event == "EDIT_MODE_LAYOUTS_UPDATED" and IsEditModeShown() then
        SuppressBlizzParty()
        SuppressBlizzRaid()
        SuppressBlizzRaidManager()
        return
    end
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
