local _, Cell = ...
local F = Cell.funcs

Cell.vars.editModeOpen = false

local hardDisabled = false
local editModeHooked = false
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local containerHooks = {}
local TrySuppressForGroup

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
        func(_G["CompactRaidGroup" .. i])
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

local function QuietStatusBar(bar)
    if not bar or FrameIsForbidden(bar) then return end
    pcall(bar.UnregisterAllEvents, bar)
    pcall(bar.SetScript, bar, "OnUpdate", nil)
end

local function QuietUnitParts(frame)
    if not frame then return end
    local container = frame.HealthBarContainer or frame.HealthBarsContainer
    local health = (container and (container.HealthBar or container.healthBar))
        or frame.healthbar or frame.HealthBar or frame.healthBar
    QuietStatusBar(health)
    QuietStatusBar(frame.ManaBar or frame.manabar or frame.powerBar or frame.PowerBar)
    QuietStatusBar(frame.castBar or frame.spellbar or frame.CastingBarFrame)
    QuietStatusBar(frame.powerBarAlt or frame.PowerBarAlt)
    if frame.BuffFrame then
        pcall(frame.BuffFrame.UnregisterAllEvents, frame.BuffFrame)
    end
    if frame.DebuffFrame then
        pcall(frame.DebuffFrame.UnregisterAllEvents, frame.DebuffFrame)
    end
    if frame.AurasFrame then
        pcall(frame.AurasFrame.UnregisterAllEvents, frame.AurasFrame)
    end
end

local function KillFrame(frame, reparent, hide)
    if not frame or FrameIsForbidden(frame) then return end
    pcall(function()
        frame:UnregisterAllEvents()
        if not InCombatLockdown() then
            if hide then
                frame:Hide()
            end
            if reparent then
                frame:SetParent(hiddenParent)
            end
        else
            frame:SetAlpha(0)
        end
    end)
    QuietUnitParts(frame)
    HideSelectionHighlight(frame)
end

local function ShrinkContainer(frame)
    if not frame or FrameIsForbidden(frame) then return end
    pcall(function()
        frame:SetAlpha(0)
        if not InCombatLockdown() then
            frame:SetScale(0.001)
        end
    end)
    HideSelectionHighlight(frame)
end

local function HookContainerOnShow(frame)
    if not frame or containerHooks[frame] then return end
    containerHooks[frame] = true
    frame:HookScript("OnShow", function()
        C_Timer.After(0, TrySuppressForGroup)
    end)
end

local function QuietCompactMember(frame)
    if not frame or FrameIsForbidden(frame) then return end
    pcall(frame.UnregisterAllEvents, frame)
    SetFrameAlpha(frame, 0)
    QuietUnitParts(frame)
    HideSelectionHighlight(frame)
    if frame.PetFrame then
        QuietCompactMember(frame.PetFrame)
    end
end

local function QuietTraditionalMember(frame)
    if not frame or FrameIsForbidden(frame) then return end
    KillFrame(frame, true, true)
    if frame.PetFrame then
        KillFrame(frame.PetFrame, true, true)
    end
end

local function QuietTraditionalParty()
    local pf = _G.PartyFrame
    if pf and not FrameIsForbidden(pf) then
        KillFrame(pf, true, true)
        ShrinkContainer(pf)
        if pf.PartyMemberFramePool then
            for memberFrame in pf.PartyMemberFramePool:EnumerateActive() do
                KillFrame(memberFrame, false, true)
                QuietUnitParts(memberFrame)
                if memberFrame.PetFrame then
                    KillFrame(memberFrame.PetFrame, false, true)
                end
            end
        end
        SetFrameAlpha(pf.DropdownButton, 0)
        SetFrameAlpha(pf.PartyMemberFrameDropDown, 0)
        if not InCombatLockdown() then
            if pf.DropdownButton then
                pcall(pf.DropdownButton.Hide, pf.DropdownButton)
            end
        end
    end
    for i = 1, 4 do
        QuietTraditionalMember(_G["PartyMemberFrame" .. i])
        QuietTraditionalMember(_G["PartyMemberFrame" .. i .. "PetFrame"])
    end
    if _G.PartyMemberBackground then
        KillFrame(_G.PartyMemberBackground, false, true)
    end
end

local function QuietCompactParty()
    local cpf = _G.CompactPartyFrame
    if cpf and not FrameIsForbidden(cpf) then
        pcall(cpf.UnregisterAllEvents, cpf)
        ShrinkContainer(cpf)
        SetFrameAlpha(cpf.title, 0)
        SetFrameAlpha(cpf.borderFrame, 0)
        HideSelectionHighlight(cpf)
        if not InCombatLockdown() then
            if cpf.dropdown then
                pcall(cpf.dropdown.Hide, cpf.dropdown)
            end
            if cpf.menuButton then
                pcall(cpf.menuButton.Hide, cpf.menuButton)
            end
        else
            SetFrameAlpha(cpf.dropdown, 0)
            SetFrameAlpha(cpf.menuButton, 0)
        end
        HookContainerOnShow(cpf)
    end
    ForEachCompactPartyMember(QuietCompactMember)
end

local function QuietCompactRaid()
    local container = _G.CompactRaidFrameContainer
    if container and not FrameIsForbidden(container) then
        pcall(container.UnregisterAllEvents, container)
        ShrinkContainer(container)
        HookContainerOnShow(container)
    end
    for i = 1, 8 do
        SetFrameAlpha(_G["CompactRaidGroup" .. i], 0)
    end
    ForEachCompactRaidMember(QuietCompactMember)
end

local function QuietRaidManager()
    local manager = _G.CompactRaidFrameManager
    if not manager or FrameIsForbidden(manager) then return end
    pcall(function()
        manager:UnregisterAllEvents()
        if not InCombatLockdown() then
            manager:Hide()
            manager:SetParent(hiddenParent)
            if CompactRaidFrameManager_SetSetting then
                CompactRaidFrameManager_SetSetting("IsShown", "0")
            end
        else
            manager:SetAlpha(0)
        end
    end)
    SetFrameAlpha(manager.container, 0)
    SetFrameAlpha(manager.toggleButton, 0)
    SetFrameAlpha(manager.displayFrame, 0)
    HookContainerOnShow(manager)
end

local function ApplyHiddenBlizzard()
    if ShouldHideBlizzardParty() then
        QuietTraditionalParty()
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

    pcall(function()
        if ShouldHideBlizzardParty() and ShouldHideBlizzardRaid() then
            UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")
        end
        if ShouldHideBlizzardRaid() and CompactRaidFrameContainer then
            CompactRaidFrameContainer:UnregisterAllEvents()
        end
        if ShouldHideBlizzardRaidManager() and CompactRaidFrameManager then
            CompactRaidFrameManager:UnregisterAllEvents()
            CompactRaidFrameManager:SetParent(hiddenParent)
            if CompactRaidFrameManager_SetSetting then
                CompactRaidFrameManager_SetSetting("IsShown", "0")
            end
        end
        if ShouldHideBlizzardParty() then
            if CompactPartyFrame then
                CompactPartyFrame:UnregisterAllEvents()
            end
            if PartyFrame then
                PartyFrame:UnregisterAllEvents()
            end
        end
    end)

    ApplyHiddenBlizzard()
    hardDisabled = true
    return true
end

TrySuppressForGroup = function()
    HardDisableBlizzardFrames()
    ApplyHiddenBlizzard()
end

local function QueueSuppress()
    C_Timer.After(0, TrySuppressForGroup)
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
            C_Timer.After(0, function()
                HookEditMode()
                TrySuppressForGroup()
            end)
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        C_Timer.After(0, HideGoldHighlights)
        return
    end

    C_Timer.After(0, function()
        HookEditMode()
        TrySuppressForGroup()
    end)
end)

function F.HideBlizzardParty()
    hardDisabled = false
    QueueSuppress()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaid()
    hardDisabled = false
    QueueSuppress()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaidManager()
    hardDisabled = false
    QueueSuppress()
    C_Timer.After(0.5, TrySuppressForGroup)
end
