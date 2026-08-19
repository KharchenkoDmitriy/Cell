local _, Cell = ...
Cell._hb = Cell._hb or {}
local hb = Cell._hb
local F = Cell.funcs
local I = Cell.iFuncs

local function HandleBuff(self, auraInfo)
    if not auraInfo then return end

    if not F.IsValueNonSecret(auraInfo.auraInstanceID) then
        if F.IsValueNonSecret(auraInfo.spellId) then
            I.UpdateCustomIndicators(self, auraInfo, "buff")
        end
        return
    end

    local unit = self.states.displayedUnit
    local auraInstanceID = auraInfo.auraInstanceID

    local name = auraInfo.name
    local icon = auraInfo.icon
    local count = auraInfo.applications
    local spellId = auraInfo.spellId
    local source = auraInfo.sourceUnit

    -- Si el usuario blacklisteó este buff me lo salto.
    -- Las auras secretas no se pueden comparar por spellId así que las salteo.
    if spellId and not auraInfo._hasSecrets and F.IsAuraBlacklisted and F.IsAuraBlacklisted(spellId, "HELPFUL") then return end

    local start, duration
    if auraInfo._hasSecrets then
        start = 0
        duration = 0
    else
        local expirationTime = auraInfo.expirationTime or 0
        duration = auraInfo.duration
        start = expirationTime - duration
    end

    auraInfo.refreshing = false

    if Cell.isMidnight or (duration ~= nil) then
        hb.UpdateAuraRefreshState(auraInfo)
        self._buffs_cache[auraInstanceID] = auraInfo

        local isDefensive = false
        local isExternal = false
        local isOffensive = false
        local secretAuraUnitTrustworthy = F.IsSecretAuraUnitTrustworthy and F.IsSecretAuraUnitTrustworthy(unit, self)

        -- Combat guard: fuera de combate solo confío en Step 1 (tablas curadas)
        -- y el cache. Fingerprint y timing producen falsos positivos con
        -- class buffs y flasks cuando los spellIds son opacos para otros
        -- miembros de la raid fuera de combate en Midnight.
        local inCombat = UnitAffectingCombat("player")

        -- Cache de clasificación: en Midnight a veces un aura llega con datos
        -- legibles y después se vuelve secreta. Con el cache no pierdo la
        -- clasificación en el siguiente UNIT_AURA.
        --
        -- Guard fuera de combate: si el aura es secreta y no estamos en combate,
        -- no confío en el cache. Steps 2/2.5/3 (que requieren combate) pudieron
        -- haber clasificado un aura durante combate y el cache la arrastra fuera.
        -- Esto causa falsos positivos donde class buffs/flasks/etc. aparecen
        -- fuera de combate porque su fingerprint matcheó durante combate.
        local classified = self._buffs._classified and self._buffs._classified[auraInstanceID]
        if classified and (inCombat or not auraInfo._hasSecrets) then
            isDefensive = classified == "defensive"
            isExternal = classified == "external"
            isOffensive = classified == "offensive"
        end

        if not classified then
            isDefensive = I.IsDefensiveCooldown(name, spellId)
            isExternal = I.IsExternalCooldown(name, spellId, source, unit)
            isOffensive = I.IsOffensiveCooldown and I.IsOffensiveCooldown(name, spellId)
        end

        if not isDefensive and not isExternal and inCombat
            and auraInfo._hasSecrets and secretAuraUnitTrustworthy then
            if not F.IsValueNonSecret(spellId) then
                local _, kind = Cell.IdentifySecretAura(unit, auraInstanceID)
                if kind == "defensive" then
                    isDefensive = true
                elseif kind == "external" then
                    isExternal = true
                elseif kind == "offensive" then
                    isOffensive = true
                end
            end
        end

        -- Cacheo la clasificación.
        if not classified and (isDefensive or isExternal or isOffensive) then
            self._buffs._classified = self._buffs._classified or {}
            self._buffs._classified[auraInstanceID] = isDefensive and "defensive" or (isExternal and "external" or "offensive")
        end

        -- Usa filtros Blizzard con PLAYER para verificar source=player.
        -- CRÍTICO: type guards en cada resultado porque _IsAuraFilteredOut
        -- puede devolver nil para auras secretas en Midnight, y `not nil = true`.
        local isPlayerCast = false
        if isExternal or isDefensive or isOffensive then
            if not auraInfo._hasSecrets then
                isPlayerCast = source == "player" or source == "pet"
            elseif hb._IsAuraFilteredOut then
                local function CheckPlayerFilter(filter)
                    local result = hb._IsAuraFilteredOut(unit, auraInstanceID, filter)
                    return type(result) == "boolean" and not result
                end
                if isExternal then
                    isPlayerCast = CheckPlayerFilter("HELPFUL|EXTERNAL_DEFENSIVE|PLAYER")
                end
                if not isPlayerCast and isDefensive then
                    isPlayerCast = CheckPlayerFilter("HELPFUL|BIG_DEFENSIVE|PLAYER")
                end
                if not isPlayerCast then
                    isPlayerCast = CheckPlayerFilter("HELPFUL|RAID|PLAYER")
                end
            end
        end

        local borderR, borderG, borderB = 1, 0.85, 0
        if isPlayerCast then
            borderR, borderG, borderB = 0, 0.8, 0
        end

        local skipLegacy = I.ShouldSkipLegacyCombatAura
        if hb.enabledIndicators["defensiveCooldowns"] and isDefensive
            and not (skipLegacy and skipLegacy("defensiveCooldowns", self))
            and self._buffs.defensiveFound < hb.indicatorNums["defensiveCooldowns"] then
            self._buffs.defensiveFound = self._buffs.defensiveFound + 1
            local frame = self.indicators.defensiveCooldowns[self._buffs.defensiveFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if hb.enabledIndicators["externalCooldowns"] and isExternal
            and not (skipLegacy and skipLegacy("externalCooldowns", self))
            and self._buffs.externalFound < hb.indicatorNums["externalCooldowns"] then
            self._buffs.externalFound = self._buffs.externalFound + 1
            local frame = self.indicators.externalCooldowns[self._buffs.externalFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if hb.enabledIndicators["offensiveCooldowns"] and isOffensive
            and not (skipLegacy and skipLegacy("offensiveCooldowns", self))
            and self._buffs.offensiveFound < hb.indicatorNums["offensiveCooldowns"] then
            self._buffs.offensiveFound = self._buffs.offensiveFound + 1
            local frame = self.indicators.offensiveCooldowns[self._buffs.offensiveFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if hb.enabledIndicators["allCooldowns"] and (isDefensive or isExternal)
            and not (skipLegacy and skipLegacy("allCooldowns", self))
            and self._buffs.allFound < hb.indicatorNums["allCooldowns"] then
            self._buffs.allFound = self._buffs.allFound + 1
            local frame = self.indicators.allCooldowns[self._buffs.allFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if not Cell.isMidnight and hb.enabledIndicators["tankActiveMitigation"] and I.IsTankActiveMitigation(spellId) then
            self.indicators.tankActiveMitigation:SetCooldown(start, duration)
            self._buffs.tankActiveMitigationFound = true
        end

        if hb.enabledIndicators["statusText"] and I.IsDrinking(name) then
            if not self.indicators.statusText:GetStatus() then
                self.indicators.statusText:SetStatus("DRINKING")
                self.indicators.statusText:Show()
            end
            self._buffs.drinkingFound = true
        end

        I.UpdateCustomIndicators(self, auraInfo, "buff")

        if not auraInfo._hasSecrets and spellId then
            if spellId == 156621 then
                self.states.BGFlag = "alliance"
            elseif spellId == 156618 then
                self.states.BGFlag = "horde"
            end
        end
    end
end

Cell.HandleBuff = HandleBuff
