---@class Cell
local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs

-------------------------------------------------
-- Aura timing / display helpers (Midnight+)
-- Duration objects let cooldown swipes work when start/duration are secret.
-- Based on Blizzard C_UnitAuras APIs only — Cell-native wrappers.
-------------------------------------------------

function F.GetAuraTiming(auraInfo)
    local expirationTime = auraInfo and auraInfo.expirationTime or 0
    local duration = auraInfo and auraInfo.duration
    if F.IsValueNonSecret(expirationTime) and F.IsValueNonSecret(duration) then
        return (expirationTime or 0) - (duration or 0), duration or 0, false
    end
    return 0, 0, true
end

function F.GetAuraStackText(unit, auraInstanceID, count, minStacks)
    minStacks = minStacks or 2
    if Cell.isMidnight and unit and auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, minStacks, 99)
        if ok and text ~= nil then
            return text
        end
    end
    if issecretvalue and issecretvalue(count) then
        return ""
    end
    count = count or 0
    if count == 0 or count == 1 or (minStacks > 1 and count < minStacks) then
        return ""
    end
    return count
end

function F.ApplyAuraCooldown(cooldown, start, duration, unit, auraInstanceID)
    if not cooldown then return false end

    local timingReadable = F.IsValueNonSecret(start) and F.IsValueNonSecret(duration) and duration and duration ~= 0

    if (not timingReadable) and Cell.isMidnight and unit and auraInstanceID
        and C_UnitAuras and C_UnitAuras.GetAuraDuration
        and cooldown.SetCooldownFromDurationObject then
        local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
        if durationObj then
            cooldown:SetCooldownFromDurationObject(durationObj)
            cooldown:Show()
            return true
        end
    end

    if timingReadable then
        if cooldown._SetCooldown then
            cooldown:_SetCooldown(start, duration)
            cooldown:Show()
            return true
        elseif cooldown.ShowCooldown then
            cooldown:ShowCooldown(start, duration)
            return true
        end
    end

    return false
end

function F.BindAuraMeta(frame, unit, auraInstanceID)
    if not frame then return end
    frame._cellAuraUnit = unit
    frame._cellAuraInstanceID = auraInstanceID
end

function F.ClearAuraMeta(frame)
    if not frame then return end
    frame._cellAuraUnit = nil
    frame._cellAuraInstanceID = nil
end

function F.CopyAuraTable(aura)
    if not aura then return nil end
    if aura._cellOwned then return aura end
    local copy = {}
    for k, v in pairs(aura) do
        copy[k] = v
    end
    copy._cellOwned = true
    return copy
end
