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
    if em then
        if em.editModeActive then return true end
        if em.IsEditModeActive and em:IsEditModeActive() then return true end
        if em.IsShown and em:IsShown() then return true end
    end
    if C_EditMode and C_EditMode.IsInEditMode then
        return C_EditMode.IsInEditMode()
    end
    return false
end

function F.IsEditModeOpen()
    return IsEditModeOpen()
end

local function SetFrameAlpha(frame, alpha)
    if not frame then return end
    if InCombatLockdown() then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    pcall(frame.SetAlpha, frame, alpha)
end

local function SetFrameMouse(frame, enabled)
    if not frame then return end
    if InCombatLockdown() then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    pcall(frame.EnableMouse, frame, enabled)
    if frame.SetMouseClickEnabled then
        pcall(frame.SetMouseClickEnabled, frame, enabled)
    end
    if frame.SetMouseMotionEnabled then
        pcall(frame.SetMouseMotionEnabled, frame, enabled)
    end
end

local function StopOnUpdate(frame)
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if not (frame.GetScript and frame:GetScript("OnUpdate")) then return end
    pcall(frame.SetScript, frame, "OnUpdate", nil)
end

local function FrameHasUnitEvents(frame)
    if not (frame and frame.IsEventRegistered) then return true end
    return frame:IsEventRegistered("UNIT_HEALTH")
        or frame:IsEventRegistered("UNIT_MAXHEALTH")
        or frame:IsEventRegistered("UNIT_HEALTH_FREQUENT")
        or frame:IsEventRegistered("UNIT_AURA")
        or frame:IsEventRegistered("UNIT_NAME_UPDATE")
        or frame:IsEventRegistered("UNIT_POWER_UPDATE")
        or frame:IsEventRegistered("UNIT_POWER_FREQUENT")
        or frame:IsEventRegistered("UNIT_CONNECTION")
        or frame:IsEventRegistered("UNIT_PHASE")
        or frame:IsEventRegistered("GROUP_ROSTER_UPDATE")
        or frame:IsEventRegistered("PLAYER_ENTERING_WORLD")
        or frame:IsEventRegistered("PLAYER_ROLES_ASSIGNED")
end

local function QuietFrame(frame)
    if not frame then return end
    if IsEditModeOpen() then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    StopOnUpdate(frame)
    if FrameHasUnitEvents(frame) then
        pcall(frame.UnregisterAllEvents, frame)
    end

    local container = frame.HealthBarContainer or frame.HealthBarsContainer
    if container then
        StopOnUpdate(container)
        if FrameHasUnitEvents(container) then
            pcall(container.UnregisterAllEvents, container)
        end
    end

    local health = (container and (container.HealthBar or container.healthBar))
        or frame.healthbar or frame.healthBar or frame.HealthBar
    if health then
        StopOnUpdate(health)
        if FrameHasUnitEvents(health) then
            pcall(health.UnregisterAllEvents, health)
        end
        if health.AnimatedLossBar then
            StopOnUpdate(health.AnimatedLossBar)
        end
    end

    local mana = frame.ManaBar or frame.manabar or frame.PowerBar or frame.powerBar
    if mana then
        StopOnUpdate(mana)
        if FrameHasUnitEvents(mana) then
            pcall(mana.UnregisterAllEvents, mana)
        end
    end

    local extra = {
        frame.BuffFrame or frame.AurasFrame,
        frame.DebuffFrame,
        frame.CcRemoverFrame,
        frame.castBar or frame.spellbar or frame.CastingBarFrame,
        frame.powerBarAlt or frame.PowerBarAlt,
        frame.totFrame,
    }
    for i = 1, #extra do
        local child = extra[i]
        if child then
            StopOnUpdate(child)
            if FrameHasUnitEvents(child) then
                pcall(child.UnregisterAllEvents, child)
            end
        end
    end

    if frame.PetFrame then
        QuietFrame(frame.PetFrame)
        SetFrameMouse(frame.PetFrame, false)
    end

    SetFrameMouse(frame, false)
end

local function RestoreMemberMouse(frame)
    if not frame then return end
    SetFrameMouse(frame, true)
    if frame.PetFrame then
        SetFrameMouse(frame.PetFrame, true)
    end
end

local function ForEachPartyMember(fn)
    if _G.PartyFrame and _G.PartyFrame.PartyMemberFramePool then
        for frame in _G.PartyFrame.PartyMemberFramePool:EnumerateActive() do
            fn(frame)
        end
        for i = 1, (_G.MAX_PARTY_MEMBERS or 4) do
            fn(_G.PartyFrame["MemberFrame" .. i])
        end
    else
        for i = 1, 4 do
            fn(_G["PartyMemberFrame" .. i])
        end
    end
    local membersPerGroup = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, membersPerGroup do
        fn(_G["CompactPartyFrameMember" .. i])
    end
    if _G.CompactPartyFrame and _G.CompactPartyFrame.memberUnitFrames then
        for _, frame in ipairs(_G.CompactPartyFrame.memberUnitFrames) do
            fn(frame)
        end
    end
    if _G.CompactPartyFrame and _G.CompactPartyFrame.petUnitFrames then
        for _, frame in ipairs(_G.CompactPartyFrame.petUnitFrames) do
            fn(frame)
        end
    end
end

local function QuietPartyMembers()
    if IsEditModeOpen() then return end
    ForEachPartyMember(QuietFrame)
end

local function RestorePartyMemberMouse()
    ForEachPartyMember(RestoreMemberMouse)
end

local function QuietRaidMembers()
    if IsEditModeOpen() then return end
    local membersPerGroup = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, 8 do
        for m = 1, membersPerGroup do
            QuietFrame(_G["CompactRaidGroup" .. i .. "Member" .. m])
        end
    end
    for i = 1, 80 do
        QuietFrame(_G["CompactRaidFrame" .. i])
    end
end

local function RestoreRaidMemberMouse()
    local membersPerGroup = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, 8 do
        for m = 1, membersPerGroup do
            RestoreMemberMouse(_G["CompactRaidGroup" .. i .. "Member" .. m])
        end
    end
    for i = 1, 80 do
        RestoreMemberMouse(_G["CompactRaidFrame" .. i])
    end
end

local function SoftVisualHide(frame)
    if IsEditModeOpen() then return end
    SetFrameAlpha(frame, 0)
    SetFrameMouse(frame, false)
end

local function RestoreFrame(frame)
    SetFrameAlpha(frame, 1)
    SetFrameMouse(frame, true)
end

local function SuppressBlizzParty()
    if not ShouldHideBlizzardParty() then return end
    SoftVisualHide(_G.PartyFrame)
    SoftVisualHide(_G.CompactPartyFrame)
    SoftVisualHide(_G.PartyMemberBackground)
    QuietFrame(_G.PartyFrame)
    QuietFrame(_G.CompactPartyFrame)
    QuietPartyMembers()
end

local function SuppressBlizzRaid()
    if not ShouldHideBlizzardRaid() then return end
    SoftVisualHide(_G.CompactRaidFrameContainer)
    QuietFrame(_G.CompactRaidFrameContainer)
    for i = 1, 8 do
        local group = _G["CompactRaidGroup" .. i]
        SoftVisualHide(group)
        QuietFrame(group)
    end
    QuietRaidMembers()
    local container = _G.CompactRaidFrameContainer
    if container and container.ApplyToFrames then
        pcall(container.ApplyToFrames, container, "normal", QuietFrame)
        pcall(container.ApplyToFrames, container, "mini", QuietFrame)
    end
end

local function SuppressBlizzRaidManager()
    if not ShouldHideBlizzardRaidManager() then return end
    SoftVisualHide(_G.CompactRaidFrameManager)
    QuietFrame(_G.CompactRaidFrameManager)
end

local function RestoreForEditMode()
    if ShouldHideBlizzardParty() then
        RestoreFrame(_G.PartyFrame)
        RestoreFrame(_G.CompactPartyFrame)
        RestoreFrame(_G.PartyMemberBackground)
        RestorePartyMemberMouse()
    end
    if ShouldHideBlizzardRaid() then
        RestoreFrame(_G.CompactRaidFrameContainer)
        for i = 1, 8 do
            RestoreFrame(_G["CompactRaidGroup" .. i])
        end
        RestoreRaidMemberMouse()
    end
    if ShouldHideBlizzardRaidManager() then
        RestoreFrame(_G.CompactRaidFrameManager)
    end
end

local function TrySuppressForGroup()
    if IsEditModeOpen() then return end
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
        if Cell.vars.editModeOpen ~= open then
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
        end
        if not open then
            if ShouldHideBlizzardParty() then QuietPartyMembers() end
            if ShouldHideBlizzardRaid() then QuietRaidMembers() end
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
