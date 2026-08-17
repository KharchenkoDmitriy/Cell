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

local function SoftVisualHide(frame)
    if not frame then return end
    if InCombatLockdown() then return end
    if IsEditModeOpen() then return end
    pcall(frame.Hide, frame)
end

local function HideActiveBlizzardPartyMembers()
    if _G.PartyFrame and _G.PartyFrame.PartyMemberFramePool then
        for frame in _G.PartyFrame.PartyMemberFramePool:EnumerateActive() do
            SoftVisualHide(frame)
        end
        for i = 1, (_G.MAX_PARTY_MEMBERS or 4) do
            SoftVisualHide(_G.PartyFrame["MemberFrame" .. i])
        end
    else
        for i = 1, 4 do
            SoftVisualHide(_G["PartyMemberFrame" .. i])
            SoftVisualHide(_G["CompactPartyMemberFrame" .. i])
        end
    end
    local membersPerGroup = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, membersPerGroup do
        SoftVisualHide(_G["CompactPartyFrameMember" .. i])
    end
    if _G.CompactPartyFrame and _G.CompactPartyFrame.memberUnitFrames then
        for _, frame in ipairs(_G.CompactPartyFrame.memberUnitFrames) do
            SoftVisualHide(frame)
        end
    end
    if _G.CompactPartyFrame and _G.CompactPartyFrame.petUnitFrames then
        for _, frame in ipairs(_G.CompactPartyFrame.petUnitFrames) do
            SoftVisualHide(frame)
        end
    end
    SoftVisualHide(_G.PartyMemberBackground)
end

local function HideRaidGroupMembers(group)
    if not group then return end
    local membersPerGroup = _G.MEMBERS_PER_RAID_GROUP or 5
    local name = group.GetName and group:GetName()
    if type(name) == "string" then
        for i = 1, membersPerGroup do
            SoftVisualHide(_G[name .. "Member" .. i])
        end
    end
    if group.memberUnitFrames then
        for _, frame in ipairs(group.memberUnitFrames) do
            SoftVisualHide(frame)
        end
    end
    if group.petUnitFrames then
        for _, frame in ipairs(group.petUnitFrames) do
            SoftVisualHide(frame)
        end
    end
end

local function SuppressBlizzParty()
    if not ShouldHideBlizzardParty() then return end
    SoftVisualHide(_G.PartyFrame)
    SoftVisualHide(_G.CompactPartyFrame)
    HideActiveBlizzardPartyMembers()
end

local function SuppressBlizzRaid()
    if not ShouldHideBlizzardRaid() then return end
    SoftVisualHide(_G.CompactRaidFrameContainer)
    local maxFrames = (_G.MAX_RAID_MEMBERS or 40) * 3
    for i = 1, maxFrames do
        SoftVisualHide(_G["CompactRaidFrame" .. i])
    end
    for i = 1, 8 do
        local group = _G["CompactRaidGroup" .. i]
        SoftVisualHide(group)
        HideRaidGroupMembers(group)
    end
end

local function SuppressBlizzRaidManager()
    if not ShouldHideBlizzardRaidManager() then return end
    SoftVisualHide(_G.CompactRaidFrameManager)
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
    watch.elapsed = 1
    watch:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.25 then return end
        self.elapsed = 0
        local open = IsEditModeOpen()
        if Cell.vars.editModeOpen ~= open then
            Cell.vars.editModeOpen = open
            if not open then
                C_Timer.After(0.5, function()
                    if not IsEditModeOpen() then
                        TrySuppressForGroup()
                    end
                end)
            end
            return
        end
        if not open then
            TrySuppressForGroup()
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
