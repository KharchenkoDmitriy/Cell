local _, Cell = ...
local F = Cell.funcs

local editModeWatcherStarted = false

local function ShouldHideBlizzardParty()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardParty"]
end

local function ShouldHideBlizzardRaid()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaid"]
end

local function ShouldHideBlizzardRaidManager()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaidManager"]
end

local function IsEditModeOpen()
    local em = _G.EditModeManagerFrame
    return em and em.IsShown and em:IsShown()
end

local function SetFrameAlpha(frame, alpha)
    if not frame then return end
    if InCombatLockdown() then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    pcall(frame.SetAlpha, frame, alpha)
end

local function SoftVisualHide(frame)
    if IsEditModeOpen() then return end
    SetFrameAlpha(frame, 0)
end

local function RestoreFrame(frame)
    SetFrameAlpha(frame, 1)
end

local function SuppressBlizzParty()
    if not ShouldHideBlizzardParty() then return end
    SoftVisualHide(_G.PartyFrame)
    SoftVisualHide(_G.CompactPartyFrame)
    SoftVisualHide(_G.PartyMemberBackground)
end

local function SuppressBlizzRaid()
    if not ShouldHideBlizzardRaid() then return end
    SoftVisualHide(_G.CompactRaidFrameContainer)
    for i = 1, 8 do
        SoftVisualHide(_G["CompactRaidGroup" .. i])
    end
end

local function SuppressBlizzRaidManager()
    if not ShouldHideBlizzardRaidManager() then return end
    SoftVisualHide(_G.CompactRaidFrameManager)
end

local function RestoreForEditMode()
    if ShouldHideBlizzardParty() then
        RestoreFrame(_G.PartyFrame)
        RestoreFrame(_G.CompactPartyFrame)
        RestoreFrame(_G.PartyMemberBackground)
    end
    if ShouldHideBlizzardRaid() then
        RestoreFrame(_G.CompactRaidFrameContainer)
        for i = 1, 8 do
            RestoreFrame(_G["CompactRaidGroup" .. i])
        end
    end
    if ShouldHideBlizzardRaidManager() then
        RestoreFrame(_G.CompactRaidFrameManager)
    end
end

local function TrySuppressForGroup()
    if IsEditModeOpen() then return end
    if InCombatLockdown() then return end
    if ShouldHideBlizzardRaid() then SuppressBlizzRaid() end
    if ShouldHideBlizzardRaidManager() then SuppressBlizzRaidManager() end
    if ShouldHideBlizzardParty() then SuppressBlizzParty() end
end

local function QueueSuppress()
    C_Timer.After(0, function()
        if not IsEditModeOpen() then
            TrySuppressForGroup()
        end
    end)
end

local function StartEditModeWatcher()
    if editModeWatcherStarted then return end
    editModeWatcherStarted = true
    local watch = CreateFrame("Frame")
    watch:SetScript("OnUpdate", function()
        local open = IsEditModeOpen()
        if Cell.vars.editModeOpen == open then return end
        Cell.vars.editModeOpen = open
        if open then
            RestoreForEditMode()
        else
            C_Timer.After(0.5, function()
                if not IsEditModeOpen() then
                    TrySuppressForGroup()
                end
            end)
        end
    end)
end

StartEditModeWatcher()

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("GROUP_ROSTER_UPDATE")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:RegisterEvent("ADDON_LOADED")
pcall(boot.RegisterEvent, boot, "EDIT_MODE_LAYOUTS_UPDATED")
boot:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "Blizzard_UnitFrame"
            or addonName == "Blizzard_EditMode"
            or addonName == "Blizzard_RaidFrame"
            or addonName == "Blizzard_CompactRaidFrames" then
            QueueSuppress()
        end
        return
    end

    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if not IsEditModeOpen() then
            QueueSuppress()
        end
        return
    end

    QueueSuppress()
end)

function F.HideBlizzardParty()
    StartEditModeWatcher()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaid()
    StartEditModeWatcher()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaidManager()
    StartEditModeWatcher()
    C_Timer.After(0.5, TrySuppressForGroup)
end
