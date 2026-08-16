local _, Cell = ...
local F = Cell.funcs

local Noop = function() end
local Swallow = function() end
local partyMemberSetupHookInstalled = false
local partyFrameInitHookInstalled = false
local editModeOverlayHooked = false
local raidMemberHooksInstalled = false
local showHooks = {}
local registerHooks = setmetatable({}, { __mode = "k" })

local function ShouldHideBlizzardParty()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardParty"]
end

local function ShouldHideBlizzardRaid()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaid"]
end

local function ShouldHideBlizzardRaidManager()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaidManager"]
end

local function SafeGetName(frame)
    if not frame or not frame.GetName then return nil end
    local ok, name = pcall(frame.GetName, frame)
    if ok and type(name) == "string" then
        return name
    end
end

local function IsCompactLayoutFrame(frame)
    if not frame then return false end
    if frame == _G.CompactPartyFrame
        or frame == _G.CompactArenaFrame
        or frame == _G.CompactRaidFrameContainer
        or frame == _G.CompactRaidFrameManager then
        return true
    end
    local name = SafeGetName(frame)
    if not name then return false end
    return name:find("^CompactParty", 1, true) ~= nil
        or name:find("^CompactArena", 1, true) ~= nil
        or name:find("^CompactRaid", 1, true) ~= nil
end

local function SoftVisualHide(frame)
    if not frame then return end
    if InCombatLockdown() then return end
    pcall(function()
        frame:Hide()
        if IsCompactLayoutFrame(frame) then
            return
        end
        frame:SetAlpha(0)
        if frame ~= _G.PartyFrame then
            frame:SetScale(0.001)
        end
    end)
end

local function SoftVisualHideDeferred(frame)
    if not frame then return end
    C_Timer.After(0, function()
        if InCombatLockdown() then return end
        SoftVisualHide(frame)
    end)
end

local function KeepHidden(frame, shouldHideFn)
    if not frame or showHooks[frame] then return end
    -- Compact layout frames share CompactRaidFrameManager_UpdateContainerVisibility
    -- with CompactArenaFrame. A Show hook here taints that path and blocks
    -- CompactArenaFrameMember:SetSize / HideBase in combat.
    if IsCompactLayoutFrame(frame) then return end
    showHooks[frame] = shouldHideFn or function() return true end
    hooksecurefunc(frame, "Show", function(self)
        local check = showHooks[self]
        if check and check() then
            SoftVisualHideDeferred(self)
        end
    end)
end

local function UnregisterBar(bar)
    if not bar then return end
    pcall(function()
        bar:UnregisterAllEvents()
        if bar.SetScript then
            bar:SetScript("OnEvent", Swallow)
            bar:SetScript("OnUpdate", nil)
            bar:SetScript("OnValueChanged", nil)
        end
    end)
end

local MEMBER_NOOP_METHODS = {
    "UpdateAuras",
    "UpdateMemberAuras",
    "UpdateAurasInternal",
    "ParseAllAuras",
    "UpdateMember",
    "UpdateMemberHealth",
    "UpdatePet",
    "UpdateOnlineStatus",
    "UpdateAssignedRoles",
    "UpdateNotPresentIcon",
    "UpdateArt",
    "ToPlayerArt",
    "ToVehicleArt",
}

local function HookStopRegistration(frame, shouldHideFn)
    if not frame or registerHooks[frame] or not hooksecurefunc then return end
    registerHooks[frame] = shouldHideFn or ShouldHideBlizzardParty

    pcall(function()
        hooksecurefunc(frame, "RegisterEvent", function(self, event)
            local check = registerHooks[self]
            if check and check() and event then
                self:UnregisterEvent(event)
            end
        end)
    end)
    pcall(function()
        hooksecurefunc(frame, "RegisterUnitEvent", function(self, event)
            local check = registerHooks[self]
            if check and check() and event then
                self:UnregisterEvent(event)
            end
        end)
    end)
end

local function NeutralizeCompactUnitFrameScripts(frame)
    if not frame then return end
    pcall(function()
        frame:UnregisterAllEvents()
        if frame.SetScript then
            frame:SetScript("OnEvent", Swallow)
            frame:SetScript("OnUpdate", nil)
            frame:SetScript("OnShow", Swallow)
        end
        if frame.onUpdateFrame and frame.onUpdateFrame.SetScript then
            frame.onUpdateFrame:SetScript("OnUpdate", nil)
        end
    end)
end

local function IsCompactRaidMemberFrame(frame)
    local name = SafeGetName(frame)
    if not name then return false end
    if name:find("^CompactRaidFrame%d+$") then return true end
    if name:find("^CompactRaidGroup%d+Member%d+") then return true end
    return false
end

local function NeutralizeMemberFrame(frame)
    if not frame then return end

    HookStopRegistration(frame)

    for i = 1, #MEMBER_NOOP_METHODS do
        frame[MEMBER_NOOP_METHODS[i]] = Noop
    end

    frame.OnEvent = false

    if frame.SetScript then
        frame:SetScript("OnEvent", Swallow)
        frame:SetScript("OnUpdate", nil)
    end

    pcall(function() frame:UnregisterAllEvents() end)
end

local function HideFrame(frame)
    if not frame then return end

    NeutralizeMemberFrame(frame)

    local health = frame.healthBar or frame.healthbar or frame.HealthBar
        or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
        or (frame.HealthBarContainer and (frame.HealthBarContainer.HealthBar or frame.HealthBarContainer.healthBar))
    UnregisterBar(health)

    local power = frame.manabar or frame.manaBar or frame.ManaBar or frame.powerBar
    UnregisterBar(power)

    local spell = frame.castBar or frame.spellbar or frame.CastingBarFrame
    if spell then
        pcall(function() spell:UnregisterAllEvents() end)
    end

    local altpowerbar = frame.powerBarAlt or frame.PowerBarAlt
    if altpowerbar then
        pcall(function() altpowerbar:UnregisterAllEvents() end)
    end

    local buffFrame = frame.BuffFrame or frame.AurasFrame
    if buffFrame then
        pcall(function() buffFrame:UnregisterAllEvents() end)
    end

    local petFrame = frame.PetFrame or frame.petFrame
    if petFrame then HideFrame(petFrame) end

    SoftVisualHide(frame)
    KeepHidden(frame, ShouldHideBlizzardParty)
end

local function suppressEditModeOverlay(frame)
    if not frame then return end
    pcall(function()
        if InCombatLockdown() then return end
        if not IsCompactLayoutFrame(frame) then
            frame:SetAlpha(0)
            if frame ~= _G.PartyFrame then
                frame:SetScale(0.001)
            end
        else
            frame:Hide()
        end
        if frame.selectionHighlight and frame.selectionHighlight.SetShown then
            frame.selectionHighlight:SetShown(false)
        end
        if frame.selectionIndicator and frame.selectionIndicator.SetShown then
            frame.selectionIndicator:SetShown(false)
        end
    end)
end

local function NeutralizeCompactPartyMember(frame)
    if not frame then return end
    HookStopRegistration(frame, ShouldHideBlizzardParty)
    NeutralizeCompactUnitFrameScripts(frame)
    UnregisterBar(frame.healthBar or frame.healthbar)
    UnregisterBar(frame.powerBar or frame.manabar)
    SoftVisualHide(frame)
    KeepHidden(frame, ShouldHideBlizzardParty)
end

local function NeutralizeCompactRaidMember(frame)
    if not frame then return end
    HookStopRegistration(frame, ShouldHideBlizzardRaid)
    NeutralizeCompactUnitFrameScripts(frame)
    UnregisterBar(frame.healthBar or frame.healthbar)
    UnregisterBar(frame.powerBar or frame.manabar)
    SoftVisualHide(frame)
    KeepHidden(frame, ShouldHideBlizzardRaid)
end

local function NeutralizeRaidGroupMembers(group)
    if not group then return end
    local MEMBERS_PER_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5
    local groupName = SafeGetName(group)
    if groupName then
        for i = 1, MEMBERS_PER_GROUP do
            NeutralizeCompactRaidMember(_G[groupName .. "Member" .. i])
        end
    end
    if group.memberUnitFrames then
        for _, frame in ipairs(group.memberUnitFrames) do
            NeutralizeCompactRaidMember(frame)
        end
    end
    if group.petUnitFrames then
        for _, frame in ipairs(group.petUnitFrames) do
            NeutralizeCompactRaidMember(frame)
        end
    end
end

local function NeutralizeAllBlizzardRaidMembers()
    if not ShouldHideBlizzardRaid() then return end

    local maxFrames = (_G.MAX_RAID_MEMBERS or 40) * 3
    for i = 1, maxFrames do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            NeutralizeCompactRaidMember(frame)
        end
    end

    for i = 1, 8 do
        NeutralizeRaidGroupMembers(_G["CompactRaidGroup" .. i])
    end
end

local function InstallRaidMemberHooks()
    if raidMemberHooksInstalled or not hooksecurefunc then return end
    raidMemberHooksInstalled = true

    local function reassert()
        if ShouldHideBlizzardRaid() then
            NeutralizeAllBlizzardRaidMembers()
        end
    end

    if _G.CompactRaidGroup_UpdateUnits then
        hooksecurefunc("CompactRaidGroup_UpdateUnits", reassert)
    end
    if _G.CompactRaidGroup_InitializeForGroup then
        hooksecurefunc("CompactRaidGroup_InitializeForGroup", reassert)
    end
    if _G.CompactRaidGroup_GenerateForGroup then
        hooksecurefunc("CompactRaidGroup_GenerateForGroup", reassert)
    end
end

local function InstallPartyUpdateNoops()
    if not ShouldHideBlizzardParty() then return end

    -- Instance only. Do not replace PartyFrameMixin / CompactPartyFrameMixin /
    -- PartyMemberFrameMixin; Scenarios and Delves reuse those mixins.
    if _G.PartyFrame then
        _G.PartyFrame.OnShow = Noop
        _G.PartyFrame.InitializePartyMemberFrames = Noop
        _G.PartyFrame.UpdatePartyFrames = Noop
        _G.PartyFrame.UpdateMemberFrames = Noop
        _G.PartyFrame.ShouldShow = function() return false end
        if _G.PartyFrame.UpdateVisibility then
            _G.PartyFrame.UpdateVisibility = Noop
        end
        if _G.PartyFrame.SetScript then
            _G.PartyFrame:SetScript("OnShow", Swallow)
            _G.PartyFrame:SetScript("OnEvent", Swallow)
        end
        pcall(function() _G.PartyFrame:UnregisterAllEvents() end)
    end

    if _G.CompactPartyFrame then
        _G.CompactPartyFrame.RefreshMembers = Noop
        if _G.CompactPartyFrame.OnEvent then
            _G.CompactPartyFrame.OnEvent = Noop
        end
        if _G.CompactPartyFrame.UpdatePaddingAndLayout then
            _G.CompactPartyFrame.UpdatePaddingAndLayout = Noop
        end
        if _G.CompactPartyFrame.Layout then
            _G.CompactPartyFrame.Layout = Noop
        end
        if ShouldHideBlizzardRaid() then
            _G.CompactPartyFrame.applyFunc = Noop
            if _G.CompactPartyFrame.ApplyFunctionToAllFrames then
                _G.CompactPartyFrame.ApplyFunctionToAllFrames = Noop
            end
        end
        pcall(function()
            _G.CompactPartyFrame:UnregisterAllEvents()
        end)
    end
end

local function HideActiveBlizzardPartyMembers()
    if _G.PartyFrame and _G.PartyFrame.PartyMemberFramePool then
        for frame in _G.PartyFrame.PartyMemberFramePool:EnumerateActive() do
            HideFrame(frame)
        end
        for i = 1, (_G.MAX_PARTY_MEMBERS or 4) do
            HideFrame(_G.PartyFrame["MemberFrame" .. i])
        end
    else
        for i = 1, 4 do
            HideFrame(_G["PartyMemberFrame" .. i])
            HideFrame(_G["CompactPartyMemberFrame" .. i])
        end
    end
    local MEMBERS_PER_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, MEMBERS_PER_GROUP do
        NeutralizeCompactPartyMember(_G["CompactPartyFrameMember" .. i])
    end
    if _G.CompactPartyFrame and _G.CompactPartyFrame.memberUnitFrames then
        for _, frame in ipairs(_G.CompactPartyFrame.memberUnitFrames) do
            NeutralizeCompactPartyMember(frame)
        end
    end
    if _G.CompactPartyFrame and _G.CompactPartyFrame.petUnitFrames then
        for _, frame in ipairs(_G.CompactPartyFrame.petUnitFrames) do
            NeutralizeCompactPartyMember(frame)
        end
    end
end

local function InstallBlizzardPartyHooks()
    InstallPartyUpdateNoops()

    if not partyMemberSetupHookInstalled
        and hooksecurefunc and _G.PartyMemberFrameMixin and _G.PartyMemberFrameMixin.Setup then
        partyMemberSetupHookInstalled = true
        hooksecurefunc(_G.PartyMemberFrameMixin, "Setup", function(frame)
            if ShouldHideBlizzardParty() then
                InstallPartyUpdateNoops()
                HideFrame(frame)
            end
        end)
    end

    if not partyFrameInitHookInstalled
        and hooksecurefunc and _G.PartyFrameMixin and _G.PartyFrameMixin.InitializePartyMemberFrames then
        partyFrameInitHookInstalled = true
        hooksecurefunc(_G.PartyFrameMixin, "InitializePartyMemberFrames", function()
            if ShouldHideBlizzardParty() then
                InstallPartyUpdateNoops()
                HideActiveBlizzardPartyMembers()
            end
        end)
    end
end

local function SuppressBlizzParty()
    if not ShouldHideBlizzardParty() then return end
    if InCombatLockdown() then return end

    InstallBlizzardPartyHooks()
    InstallPartyUpdateNoops()

    if _G.CompactPartyFrame then
        SoftVisualHide(_G.CompactPartyFrame)
        KeepHidden(_G.CompactPartyFrame, ShouldHideBlizzardParty)
        suppressEditModeOverlay(_G.CompactPartyFrame)
    end

    if _G.PartyFrame then
        HideActiveBlizzardPartyMembers()
        SoftVisualHide(_G.PartyFrame)
        KeepHidden(_G.PartyFrame, ShouldHideBlizzardParty)
        suppressEditModeOverlay(_G.PartyFrame)
    else
        HideActiveBlizzardPartyMembers()
        if _G.PartyMemberBackground then
            HideFrame(_G.PartyMemberBackground)
        end
    end
end

local function SuppressBlizzRaid()
    if not ShouldHideBlizzardRaid() then return end

    InstallRaidMemberHooks()
    NeutralizeAllBlizzardRaidMembers()

    if ShouldHideBlizzardParty() then
        InstallPartyUpdateNoops()
    end

    if InCombatLockdown() then return end

    local container = _G.CompactRaidFrameContainer
    if container then
        pcall(function() container:UnregisterAllEvents() end)
        SoftVisualHide(container)
        KeepHidden(container, ShouldHideBlizzardRaid)
        if container.ApplyToFrames then
            container.ApplyToFrames = Noop
        end
        if container.TryUpdate then
            container.TryUpdate = Noop
        end
        suppressEditModeOverlay(container)
    end

    for i = 1, 8 do
        local group = _G["CompactRaidGroup" .. i]
        if group then
            pcall(function() group:UnregisterAllEvents() end)
            if group.applyFunc then
                group.applyFunc = Noop
            end
            if group.SetScript then
                group:SetScript("OnEvent", Swallow)
            end
            SoftVisualHide(group)
            KeepHidden(group, ShouldHideBlizzardRaid)
        end
    end
end

local function SuppressBlizzRaidManager()
    if not ShouldHideBlizzardRaidManager() then return end
    if InCombatLockdown() then return end
    local mgr = _G.CompactRaidFrameManager
    if mgr then
        pcall(function() mgr:UnregisterAllEvents() end)
        SoftVisualHide(mgr)
        KeepHidden(mgr, ShouldHideBlizzardRaidManager)
    end
end

local function applyEditModeOverlaySuppression()
    if ShouldHideBlizzardRaid() then
        suppressEditModeOverlay(_G.CompactRaidFrameContainer)
    end
    if ShouldHideBlizzardParty() then
        InstallPartyUpdateNoops()
        suppressEditModeOverlay(_G.PartyFrame)
        suppressEditModeOverlay(_G.CompactPartyFrame)
    end
end

local function TrySuppressForGroup()
    if ShouldHideBlizzardRaid() then
        InstallRaidMemberHooks()
        NeutralizeAllBlizzardRaidMembers()
    end
    if InCombatLockdown() then return end
    if ShouldHideBlizzardRaid() then SuppressBlizzRaid() end
    if ShouldHideBlizzardRaidManager() then SuppressBlizzRaidManager() end
    if ShouldHideBlizzardParty() then SuppressBlizzParty() end
    applyEditModeOverlaySuppression()
end

local function InstallEditModeOverlayHooks()
    if editModeOverlayHooked then return end
    local function hookEditModeManager()
        if not _G.EditModeManagerFrame or editModeOverlayHooked then return end
        editModeOverlayHooked = true
        _G.EditModeManagerFrame:HookScript("OnShow", function()
            C_Timer.After(0, function()
                applyEditModeOverlaySuppression()
                TrySuppressForGroup()
            end)
        end)
        if hooksecurefunc then
            hooksecurefunc(_G.EditModeManagerFrame, "Hide", function()
                C_Timer.After(0, applyEditModeOverlaySuppression)
            end)
        end
    end
    if _G.EditModeManagerFrame then
        hookEditModeManager()
    elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", hookEditModeManager)
    end
end

local function TryEarlyPartyNoops()
    if ShouldHideBlizzardParty() then
        InstallPartyUpdateNoops()
        InstallBlizzardPartyHooks()
    end
    if ShouldHideBlizzardRaid() then
        InstallRaidMemberHooks()
        if _G.CompactRaidFrameContainer and _G.CompactRaidFrameContainer.ApplyToFrames then
            _G.CompactRaidFrameContainer.ApplyToFrames = Noop
        end
        NeutralizeAllBlizzardRaidMembers()
    end
    InstallEditModeOverlayHooks()
end

TryEarlyPartyNoops()

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
            TryEarlyPartyNoops()
            if ShouldHideBlizzardParty() then
                HideActiveBlizzardPartyMembers()
            end
            if ShouldHideBlizzardRaid() then
                NeutralizeAllBlizzardRaidMembers()
            end
        end
        return
    end

    TryEarlyPartyNoops()

    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
        C_Timer.After(0, TrySuppressForGroup)
        return
    end

    if event == "PLAYER_LOGIN" then
        C_Timer.After(0, TrySuppressForGroup)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0, TrySuppressForGroup)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if not InCombatLockdown() then
            if ShouldHideBlizzardParty() then
                InstallPartyUpdateNoops()
                HideActiveBlizzardPartyMembers()
            end
            if ShouldHideBlizzardRaid() then
                InstallRaidMemberHooks()
                NeutralizeAllBlizzardRaidMembers()
            end
        end
        C_Timer.After(0, applyEditModeOverlaySuppression)
        C_Timer.After(0.5, TrySuppressForGroup)
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if not InCombatLockdown() then
            if ShouldHideBlizzardParty() then
                InstallPartyUpdateNoops()
                HideActiveBlizzardPartyMembers()
            end
            if ShouldHideBlizzardRaid() then
                InstallRaidMemberHooks()
                NeutralizeAllBlizzardRaidMembers()
            end
        end
        C_Timer.After(0, TrySuppressForGroup)
    end
end)

function F.HideBlizzardParty()
    TryEarlyPartyNoops()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaid()
    TryEarlyPartyNoops()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaidManager()
    InstallEditModeOverlayHooks()
    C_Timer.After(0.5, TrySuppressForGroup)
end
