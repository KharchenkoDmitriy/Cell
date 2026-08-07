local _, Cell = ...
local L = Cell.L
local I = Cell.iFuncs
local F = Cell.funcs

-------------------------------------------------
-- dispelBlacklist
-------------------------------------------------
-- suppress dispel highlight
local dispelBlacklist = {}

function I.GetDefaultDispelBlacklist()
    return dispelBlacklist
end

-------------------------------------------------
-- debuffBlacklist
-------------------------------------------------
local debuffBlacklist = {
    8326, -- 鬼魂 - Ghost
    160029, -- 正在复活 - Resurrecting
    255234, -- 图腾复生 - Totemic Revival
    225080, -- 复生 - Reincarnation
    57723, -- 筋疲力尽 - Exhaustion
    57724, -- 心满意足 - Sated
    80354, -- 时空错位 - Temporal Displacement
    264689, -- 疲倦 - Fatigued
    390435, -- 筋疲力尽 - Exhaustion
    206151, -- 挑战者的负担 - Challenger's Burden
    195776, -- 月羽疫病 - Moonfeather Fever
    352562, -- 起伏机动 - Undulating Maneuvers
    356419, -- 审判灵魂 - Judge Soul
    387847, -- 邪甲术 - Fel Armor
    213213, -- 伪装 - Masquerade
}

function I.GetDefaultDebuffBlacklist()
    -- local temp = {}
    -- for i, id in pairs(debuffBlacklist) do
    --     temp[i] = F.GetSpellInfo(id)
    -- end
    -- return temp
    return debuffBlacklist
end

-------------------------------------------------
-- bigDebuffs
-------------------------------------------------
local bigDebuffs = {
    46392, -- 专注打击 - Focused Assault
    -----------------------------------------------
    240443, -- 爆裂 - Burst
    209858, -- 死疽溃烂 - Necrotic Wound
    240559, -- 重伤 - Grievous Wound
    -- 226512, -- 鲜血脓液（血池）
    -----------------------------------------------
    -- NOTE: Thundering Affix - Dragonflight Season 1
    -- 396369, -- 闪电标记
    -- 396364, -- 狂风标记
    -----------------------------------------------
    -- NOTE: Shrouded Affix - Shadowlands Season 4
    -- 373391, -- 梦魇
    -- 373429, -- 腐臭虫群
    -----------------------------------------------
    -- NOTE: Encrypted Affix - Shadowlands Season 3
    -- 尤型拆卸者
    -- 366297, -- 解构
    -- 366288, -- 猛力砸击
    -----------------------------------------------
    -- NOTE: Tormented Affix - Shadowlands Season 2
    -- 焚化者阿寇拉斯
    -- 355732, -- 融化灵魂
    -- 355738, -- 灼热爆破
    -- 凇心之欧罗斯
    -- 356667, -- 刺骨之寒
    -- 刽子手瓦卢斯
    -- 356925, -- 屠戮
    -- 356923, -- 撕裂
    -- 358973, -- 恐惧浪潮
    -- 粉碎者索苟冬
    -- 355806, -- 重压
    -- 358777, -- 痛苦之链
}

function I.GetDefaultBigDebuffs()
    return bigDebuffs
end

-------------------------------------------------
-- aoeHealings
-------------------------------------------------
local aoeHealings = {
    ["DRUID"] = {
        [740] = true,      -- 宁静 - Tranquility
        [145205] = true,   -- 百花齐放 - Efflorescence
    },

    ["EVOKER"] = {
        [355916] = true,   -- 翡翠之花 - Emerald Blossom
        [361361] = true,   -- 婆娑幼苗 - Fluttering Seedlings
        [363534] = true,   -- 回溯 - Rewind
        [367230] = true,   -- 精神之花 - Spiritbloom
        [370984] = true,   -- 翡翠交融 - Emerald Communion
        [371441] = true,   -- 赐命者之焰 - Life-Giver's Flame
        [371879] = true,   -- 生生不息 - Cycle of Life
        [377509] = false,  -- 梦境投影（pvp）- Dream Projection
    },

    ["MONK"] = {
        [115098] = true,   -- 真气波 - Chi Wave
        [123986] = true,   -- 真气爆裂 - Chi Burst
        [115310] = true,   -- 还魂术 - Revival
        [322118] = true,   -- 青龙下凡 (SUMMON) - Invoke Yu'lon, the Jade Serpent
        [388193] = true,   -- 碧火踏 - Jadefire Stomp
        [443028] = true,   -- 天神御身 - Celestial Conduit
        [343819] = false,  -- 迷雾之风 (朱鹤下凡产生的“迷雾之风”的施法者是玩家) - Gust of Mists
    },

    ["PALADIN"] = {
        [85222]  = true,   -- 黎明之光 - Light of Dawn
        [119952] = true,   -- 弧形圣光 - Arcing Light
        [114165] = true,   -- 神圣棱镜 - Holy Prism
        [200654] = true,   -- 提尔的拯救 - Tyr's Deliverance
        [216371] = true,   -- 复仇十字军 - Avenging Crusader
    },

    ["PRIEST"] = {
        [120517] = true,   -- 光晕 - Halo (moved to Archon hero talent in 12.0)
        [34861]  = true,   -- 圣言术：灵 - Holy Word: Sanctify
        [596]    = true,   -- 治疗祷言 - Prayer of Healing
        [64843]  = true,   -- 神圣赞美诗 - Divine Hymn
        -- [110744] = true,   -- 神圣之星 - Divine Star (removed in 12.0)
        [204883] = true,   -- 治疗之环 - Circle of Healing
        [281265] = true,   -- 神圣新星 - Holy Nova
        -- [314867] = true,   -- 暗影盟约 - Shadow Covenant (removed in 12.0)
        [15290]  = true,   -- 吸血鬼的拥抱 - Vampiric Embrace
        [372787] = true,   -- 神言术：佑 - Divine Word: Sanctuary
    },

    ["SHAMAN"] = {
        [1064]   = true,   -- 治疗链 - Chain Heal
        [73920]  = true,   -- 治疗之雨 - Healing Rain
        [108280] = true,   -- 治疗之潮图腾 (SUMMON) - Healing Tide Totem
        [52042]  = true,   -- 治疗之泉图腾 (SUMMON) - Healing Stream Totem
        [197995] = true,   -- 奔涌之流 - Wellspring
        -- [157503] = true,   -- 暴雨图腾 - Cloudburst (removed in 12.0)
        [114911] = true,   -- 先祖指引 - Ancestral Guidance
        [382311] = true,   -- 先祖复苏 - Ancestral Awakening
        [207778] = true,   -- 倾盆大雨 - Downpour
        [114083] = true,   -- 恢复迷雾 (升腾) - Restorative Mists
    },
}

function I.GetAoEHealings()
    return aoeHealings
end

local builtInAoEHealings = {}
local customAoEHealings = {}

function I.UpdateAoEHealings(t)
    -- user disabled
    wipe(builtInAoEHealings)
    for class, spells in pairs(aoeHealings) do
        for id, trackByName in pairs(spells) do
            if not t["disabled"][id] then -- not disabled
                if trackByName then
                    local name = F.GetSpellInfo(id)
                    if name then
                        builtInAoEHealings[name] = true
                    end
                else
                    builtInAoEHealings[id] = true
                end
            end
        end
    end

    -- user created
    wipe(customAoEHealings)
    for _, id in pairs(t["custom"]) do
        customAoEHealings[id] = true
    end
end

function I.IsAoEHealing(name, id)
    if F.IsValueNonSecret(name) and builtInAoEHealings[name] then
        return true
    end

    if F.IsValueNonSecret(id) then
        return builtInAoEHealings[id] or customAoEHealings[id]
    end
end

local summonDuration = {
    -- evoker
    [377509] = 6, -- 梦境投影（pvp）- Dream Projection

    -- monk
    [322118] = 25, -- 青龙下凡 - Invoke Yu'lon, the Jade Serpent

    -- shaman
    [108280] = 12, -- 治疗之潮图腾 - Healing Tide Totem
    [52042] = 15, -- 治疗之泉图腾 - Healing Stream Totem
}

do
    local temp = {}
    for id, duration in pairs(summonDuration) do
        temp[F.GetSpellInfo(id)] = duration
    end
    summonDuration = temp
end

function I.GetSummonDuration(spellName)
    return summonDuration[spellName]
end

-------------------------------------------------
-- externalCooldowns
-------------------------------------------------
local externals = { -- true: track by name, false: track by id
    ["DEATHKNIGHT"] = {
        [51052] = true, -- 反魔法领域 - Anti-Magic Zone
    },

    ["DEMONHUNTER"] = {
        [196718] = true, -- 黑暗 - Darkness
    },

    ["DRUID"] = {
        [102342] = true, -- 铁木树皮 - Ironbark
    },

    ["EVOKER"] = {
        [374227] = true, -- 微风 - Zephyr
        [357170] = true, -- 时间膨胀 - Time Dilation
        [363534] = true, -- 回溯 - Rewind
        [360995] = true, -- 翠绿拥抱 - Verdant Embrace
        [378441] = true, -- 时间停止 - Time Stop (pvp)
        [374348] = true, -- 新生光焰 - Renewing blaze
    },

    ["MAGE"] = {
        [198158] = true, -- 群体隐形 - Mass Invisibility
        [414660] = { -- 群体屏障 - Mass Barrier
            [414661] = false, -- 寒冰护体 - Ice Barrier
            [414662] = false, -- 烈焰护体 - Blazing Barrier
            [414663] = false, -- 棱光护体 - Prismatic Barrier
            -- [11426] = false, -- 寒冰护体 (self)
            -- [235313] = false, -- 烈焰护体 (self)
            -- [235450] = false, -- 棱光护体 (self)
        },
    },

    ["MONK"] = {
        [116849] = true, -- 作茧缚命 - Life Cocoon
        [406139] = true, -- 真气之茧 - Chi Cocoon (Yu'lon)
        [406220] = true, -- 真气之茧 - Chi Cocoon (Chi-Ji)
        [116841] = true, -- 迅如猛虎 - Tiger's Lust
        [202248] = false, -- 偏转冥想 - Guided Meditation
    },

    ["PALADIN"] = {
        [1022] = true, -- 保护祝福 - Blessing of Protection
        [6940] = true, -- 牺牲祝福 - Blessing of Sacrifice
        [204018] = true, -- 破咒祝福 - Blessing of Spellwarding
        [1044] = true, -- 自由祝福 - Blessing of Freedom
        [31821] = true, -- 光环掌握 - Aura Mastery
        [210256] = true, -- 庇护祝福 - Blessing of Sanctuary
        [228050] = false, -- 圣盾术 (被遗忘的女王护卫) - Divine Shield
        [432496] = true, -- 圣洁壁垒 - Holy Bulwark (Holy Armaments shield variant)
        [432502] = true, -- 圣洁武器 - Holy Armaments (Sacred Weapon variant)
        -- [211210] = true, -- 提尔的保护
        -- [216328] = true, -- 光之优雅
    },

    ["PRIEST"] = {
        [33206] = true, -- 痛苦压制 - Pain Suppression
        [47788] = true, -- 守护之魂 - Guardian Spirit
        [10060] = true, -- 能量灌注 - Power Infusion
        [62618] = true, -- 真言术：障 - Power Word: Barrier
        [213610] = true, -- 神圣守卫 - Holy Ward
        [197268] = true, -- 希望之光 - Ray of Hope
    },

    ["ROGUE"] = {
        [114018] = true, -- 潜伏帷幕 - Shroud of Concealment
    },

    ["SHAMAN"] = {
        [98008] = true, -- 灵魂链接图腾 - Spirit Link Totem
        [201633] = true, -- 大地之墙图腾 - Earthen Wall
        [8178] = true, -- 根基图腾 - Grounding Totem
        [383018] = true, -- 石肤图腾 - Stoneskin
    },

    ["WARRIOR"] = {
        [97462] = true, -- 集结呐喊 - Rallying Cry
        [3411] = true, -- 援护 - Intervene
        [213871] = true, -- 护卫 - Bodyguard
    },
}

function I.GetExternals()
    return externals
end

local builtInExternals = {}
local customExternals = {}

local function UpdateExternals(id, trackByName)
    if trackByName then
        local name = F.GetSpellInfo(id)
        if name then
            builtInExternals[name] = true
        end
    end
    -- Also store by ID (in addition to name when trackByName is true)
    -- so IsExternalCooldown/IsDefensiveCooldown can match by ID directly
    builtInExternals[id] = true
end

function I.UpdateExternals(t)
    -- user disabled
    wipe(builtInExternals)
    for class, spells in pairs(externals) do
        for id, v in pairs(spells) do
            if not t["disabled"][id] then -- not disabled
                if type(v) == "table" then
                    builtInExternals[id] = true -- for I.IsExternalCooldown()
                    for subId, subTrackByName in pairs(v) do
                        UpdateExternals(subId, subTrackByName)
                    end
                else
                    UpdateExternals(id, v)
                end
            end
        end
    end

    -- user created
    wipe(customExternals)
    for _, id in pairs(t["custom"]) do
        -- local name = F.GetSpellInfo(id)
        -- if name then
        --     customExternals[name] = true
        -- end
        customExternals[id] = true
    end
    Cell.vars.builtInExternals = builtInExternals
    Cell.vars.customExternals = customExternals
end

local UnitIsUnit = UnitIsUnit
local bos = F.GetSpellInfo(6940) -- 牺牲祝福
function I.IsExternalCooldown(name, id, source, target)
    local nameIsReadable = F.IsValueNonSecret(name)
    local idIsReadable = F.IsValueNonSecret(id)

    if nameIsReadable and name == bos then
        if source and target then
            -- NOTE: hide bos on caster
            return not UnitIsUnit(source, target)
        else
            return true
        end
    end

    if nameIsReadable and builtInExternals[name] then
        return true
    end

    if idIsReadable then
        return builtInExternals[id] or customExternals[id]
    end
end

-------------------------------------------------
-- defensiveCooldowns
-------------------------------------------------
local defensives = { -- true: track by name, false: track by id
    ["DEATHKNIGHT"] = {
        [48707] = true, -- 反魔法护罩 - Anti-Magic Shell
        [48792] = true, -- 冰封之韧 - Icebound Fortitude
        [49028] = true, -- 符文刃舞 - Dancing Rune Weapon
        [55233] = true, -- 吸血鬼之血 - Vampiric Blood
        [49039] = false, -- 巫妖之躯 - Lichborne
        [194679] = true, -- 符文分流 - Rune Tap
    },

    ["DEMONHUNTER"] = {
        [196555] = true, -- 虚空行走 - Netherwalk
        [198589] = true, -- 疾影 - Blur
        [187827] = false, -- 恶魔变形 162264(DPS) - Metamorphosis
    },

    ["DRUID"] = {
        [22812] = true, -- 树皮术 - Barkskin
        [61336] = true, -- 生存本能 - Survival Instincts
        [200851] = true, -- 沉睡者之怒 - Rage of the Sleeper
        [102558] = true, -- 化身：乌索克的守护者 - Incarnation: Guardian of Ursoc
        [22842] = true, -- 狂暴回复 - Frenzied Regeneration
    },

    ["EVOKER"] = {
        [363916] = true, -- 黑曜鳞片 - Obsidian Scales
        [374348] = true, -- 新生光焰 - Renewing Blaze
        [370960] = true, -- 翡翠交融 - Emerald Communion
        [431872] = false, -- 瞬息之隔 - Temporality (Chronowarden Hero Talent)
        [377088] = false, -- 活力迸射 - Rush of Vitality
    },

    ["HUNTER"] = {
        [186265] = true, -- 灵龟守护 - Aspect of the Turtle
        [264735] = true, -- 优胜劣汰 - Survival of the Fittest
    },

    ["MAGE"] = {
        [45438] = true, -- 寒冰屏障 - Ice Block
        [414658] = true, -- 深寒凝冰 - Ice Cold
        [113862] = false, -- 强化隐形术 - Greater Invisibility
        [55342] = false, -- 镜像（使用 CLEU 而非 UNIT_AURA） - Mirror Image
        [342246] = true, -- 操控时间 - Alter Time
    },

    ["MONK"] = {
        [115176] = false, -- 禅悟冥想 - Zen Meditation
        [115203] = true, -- 壮胆酒 - Fortifying Brew
        [122278] = true, -- 躯不坏 - Dampen Harm
        [122783] = true, -- 散魔功 - Diffuse Magic
        [125174] = true, -- 业报之触 - Touch of Karma
        [443113] = true, -- 黑牛之力 - Strength of the Black Ox
    },

    ["PALADIN"] = {
        [498] = true, -- 圣佑术 - Divine Protection (Holy/Protection)
        [403876] = true, -- Protección Divina (cast de Retribution en TWW+, el 498 ya no funciona para Ret)
        [642] = true, -- 圣盾术 - Divine Shield
        [31850] = true, -- 炽热防御者 - Ardent Defender
        [86659] = true, -- 远古列王守卫 - Guardian of Ancient Kings (base buff)
        [212641] = true, -- 远古列王守卫 - Guardian of Ancient Kings
        [205191] = true, -- 以眼还眼 - Eye for an Eye
        [389539] = true, -- 戒卫 - Sentinel
        [184662] = true, -- 复仇之盾 - Shield of Vengeance (legacy ID)
        [1261562] = true, -- Escudo de Venganza (buff ID de TWW+, el 184662 ya no funciona en Midnight)
    },

    ["PRIEST"] = {
        [47585] = true, -- 消散 - Dispersion
        [19236] = true, -- 绝望祷言 - Desperate Prayer
        [586] = true, -- 渐隐术 -- TODO: 373446 通透影像 - Fade
        [193065] = true, -- 防护圣光 - Protective Light
        [27827] = true, -- 救赎之魂 - Spirit of Redemption
    },

    ["ROGUE"] = {
        [1966] = true, -- 佯攻 - Feint
        [5277] = true, -- 闪避 - Evasion
        [31224] = false, -- 暗影斗篷 - Cloak of Shadows
    },

    ["SHAMAN"] = {
        [108271] = true, -- 星界转移 - Astral Shift
        [409293] = true, -- 掘地三尺 - Burrow (PVP)
        [114893] = true, -- 石壁 - Stone Bulwark
    },

    ["WARLOCK"] = {
        [104773] = true, -- 不灭决心 - Unending Resolve
        [212295] = true, -- 虚空守卫 - Nether Ward (PVP)
        [108416] = true, -- 黑暗契约 - Dark Pact
    },

    ["WARRIOR"] = {
        [871] = true, -- 盾墙 - Shield Wall
        [12975] = true, -- 破釜沉舟 - Last Stand
        [23920] = true, -- 法术反射 - Spell Reflection
        [118038] = true, -- 剑在人在 - Die by the Sword
        [184364] = true, -- 狂怒回复 - Enraged Regeneration
    },
}

function I.GetDefensives()
    return defensives
end

local builtInDefensives = {}
local customDefensives = {}

function I.UpdateDefensives(t)
    -- user disabled
    wipe(builtInDefensives)
    for class, spells in pairs(defensives) do
        for id, trackByName in pairs(spells) do
            if not t["disabled"][id] then -- not disabled
                if trackByName then
                    local name = F.GetSpellInfo(id)
                    if name then
                        builtInDefensives[name] = true
                    end
                end
                -- Also store by ID (in addition to name when trackByName is true)
    -- so IsExternalCooldown/IsDefensiveCooldown can match by ID directly
                builtInDefensives[id] = true
            end
        end
    end

    -- user created
    wipe(customDefensives)
    for _, id in pairs(t["custom"]) do
        -- local name = F.GetSpellInfo(id)
        -- if name then
        --     customDefensives[name] = true
        -- end
        customDefensives[id] = true
    end
    Cell.vars.builtInDefensives = builtInDefensives
    Cell.vars.customDefensives = customDefensives
end

function I.IsDefensiveCooldown(name, id)
    if F.IsValueNonSecret(name) and builtInDefensives[name] then
        return true
    end

    if F.IsValueNonSecret(id) then
        return builtInDefensives[id] or customDefensives[id]
    end
end

-------------------------------------------------
-- tankActiveMitigation
-------------------------------------------------
local tankActiveMitigations = {
    -- death knight
    -- 77535, -- 鲜血护盾
    195181, -- 白骨之盾 - Bone Shield

    -- demon hunter
    203819, -- 恶魔尖刺 - Demon Spikes

    -- druid
    192081, -- 铁鬃 - Ironfur

    -- monk
    215479, -- 酒醒入定 - Shuffle

    -- paladin
    132403, -- 正义盾击 - Shield of the Righteous

    -- warrior
    132404, -- 盾牌格挡 - Shield Block
}

local tankActiveMitigationNames = {
    -- death knight
    -- F.GetClassColorStr("DEATHKNIGHT")..F.GetSpellInfo(77535).."|r", -- 鲜血护盾
    F.GetClassColorStr("DEATHKNIGHT")..F.GetSpellInfo(195181).."|r", -- 白骨之盾

    -- demon hunter
    F.GetClassColorStr("DEMONHUNTER")..F.GetSpellInfo(203819).."|r", -- 恶魔尖刺

    -- druid
    F.GetClassColorStr("DRUID")..F.GetSpellInfo(192081).."|r", -- 铁鬃

    -- monk
    F.GetClassColorStr("MONK")..F.GetSpellInfo(215479).."|r", -- 酒醒入定

    -- paladin
    F.GetClassColorStr("PALADIN")..F.GetSpellInfo(132403).."|r", -- 正义盾击

    -- warrior
    F.GetClassColorStr("WARRIOR")..F.GetSpellInfo(132404).."|r", -- 盾牌格挡
}

do
    local temp = {}
    for _, id in pairs(tankActiveMitigations) do
        -- temp[F.GetSpellInfo(id)] = true
        temp[id] = true
    end
    tankActiveMitigations = temp
end

function I.IsTankActiveMitigation(spellId)
    if not F.IsValueNonSecret(spellId) then return end
    return tankActiveMitigations[spellId]
end

function I.GetTankActiveMitigationString()
    return table.concat(tankActiveMitigationNames, ", ").."."
end

-------------------------------------------------
-- dispels
-------------------------------------------------
local dispellable = {}

function I.CanDispel(dispelType)
    if not dispelType then return end
    return dispellable[dispelType]
end

local dispelNodeIDs = {
    -- DRUID ----------------
        -- 102 - Balance
        [102] = {["Curse"] = 82241, ["Poison"] = 82241},
        -- 103 - Feral
        [103] = {["Curse"] = 82241, ["Poison"] = 82241},
        -- 104 - Guardian
        [104] = {["Curse"] = 82241, ["Poison"] = 82241},
        -- Restoration
        [105] = {["Curse"] = true, ["Magic"] = true, ["Poison"] = true},
    -------------------------

    -- EVOKER ---------------
        -- 1467 - Devastation
        [1467] = {["Curse"] = 93294, ["Disease"] = 93294, ["Poison"] = {93306, 93294}, ["Bleed"] = 93294},
        -- 1468	- Preservation
        [1468] = {["Curse"] = 93294, ["Disease"] = 93294, ["Magic"] = true, ["Poison"] = true, ["Bleed"] = 93294},
        -- 1473 - Augmentation
        [1473] = {["Curse"] = 93294, ["Disease"] = 93294, ["Poison"] = {93306, 93294}, ["Bleed"] = 93294},
    -------------------------

    -- MAGE -----------------
        -- 62 - Arcane
        [62] = {["Curse"] = 62116},
        -- 63 - Fire
        [63] = {["Curse"] = 62116},
        -- 64 - Frost
        [64] = {["Curse"] = 62116},
    -------------------------

    -- MONK -----------------
        -- 268 - Brewmaster
        [268] = {["Disease"] = 101090, ["Poison"] = 101090},
        -- 269 - Windwalker
        [269] = {["Disease"] = 101150, ["Poison"] = 101150},
        -- 270 - Mistweaver
        [270] = {["Disease"] = 101089, ["Magic"] = true, ["Poison"] = 101089},
    -------------------------

    -- PALADIN --------------
        -- 65 - Holy
        [65] = {["Disease"] = 81508, ["Magic"] = true, ["Poison"] = 81508, ["Bleed"] = 81616},
        -- 66 - Protection
        [66] = {["Disease"] = 81507, ["Poison"] = 81507, ["Bleed"] = 81616},
        -- 70 - Retribution
        [70] = {["Disease"] = 81507, ["Poison"] = 81507, ["Bleed"] = 81616},
    -------------------------

    -- PRIEST ---------------
        -- 256 - Discipline
        [256] = {["Disease"] = 82705, ["Magic"] = true},
        -- 257 - Holy
        [257] = {["Disease"] = 82705, ["Magic"] = true},
        -- 258 - Shadow
        [258] = {["Disease"] = 82704, ["Magic"] = 82699},
    -------------------------

    -- SHAMAN ---------------
        -- 262 - Elemental
        [262] = {["Curse"] = 103608, ["Poison"] = 103599},
        -- 263 - Enhancement
        [263] = {["Curse"] = 103608, ["Poison"] = 103599},
        -- 264 - Restoration
        [264] = {["Curse"] = 81073, ["Magic"] = true, ["Poison"] = 103599},
    -------------------------

    -- WARLOCK --------------
        -- 265 - Affliction
        -- [265] = {["Magic"] = function() return IsSpellKnown(89808, true) end},
        -- 266 - Demonology
        -- [266] = {["Magic"] = function() return IsSpellKnown(89808, true) end},
        -- 267 - Destruction
        -- [267] = {["Magic"] = function() return IsSpellKnown(89808, true) end},
    -------------------------
}

local eventFrame = CreateFrame("Frame")
--Whenever anything is committed to the configID, e.g. when saving talents, switching talent loadouts, spending profession points, etc

if UnitClassBase("player") == "WARLOCK" then
    eventFrame:RegisterEvent("UNIT_PET")

    local timer
    eventFrame:SetScript("OnEvent", function(self, event, unit)
        if unit ~= "player" then return end

        if timer then
            timer:Cancel()
        end
        timer = C_Timer.NewTimer(1, function()
            -- update dispellable
            dispellable["Magic"] = IsSpellKnown(89808, true)
            -- texplore(dispellable)
        end)

    end)
else
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    -- eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

    local function UpdateDispellable()
        -- update dispellable
        wipe(dispellable)
        local activeConfigID = C_ClassTalents.GetActiveConfigID()
        if activeConfigID and dispelNodeIDs[Cell.vars.playerSpecID] then
            for dispelType, value in pairs(dispelNodeIDs[Cell.vars.playerSpecID]) do
                if type(value) == "boolean" then
                    dispellable[dispelType] = value
                elseif type(value) == "table" then -- more than one trait
                    for _, v in pairs(value) do
                        local nodeInfo = C_Traits.GetNodeInfo(activeConfigID, v)
                        if nodeInfo and nodeInfo.activeRank ~= 0 then
                            dispellable[dispelType] = true
                            break
                        end
                    end
                else -- number: check node info
                    local nodeInfo = C_Traits.GetNodeInfo(activeConfigID, value)
                    if nodeInfo and nodeInfo.activeRank ~= 0 then
                        dispellable[dispelType] = true
                    end
                end
            end
        end

        -- texplore(dispellable)
    end

    local timer

    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end

        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(1, UpdateDispellable)
    end)

    Cell.RegisterCallback("SpecChanged", "Dispellable_SpecChanged", function()
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(1, UpdateDispellable)
    end)
end

-------------------------------------------------
-- drinking
-------------------------------------------------
local drinks = {
    170906, -- 食物和饮水 - Food & Drink
    167152, -- 进食饮水 - Refreshment
    430, -- 喝水 - Drink
    43182, -- 饮水 - Drink
    172786, -- 饮料 - Drink
    308433, -- 食物和饮料 - Food & Drink
    369162, -- 饮用 - Drink
    456574, -- 燧烬蜜露 - Cinder Nectar
    461063, -- 静默省思（土灵）- Quiet Contemplation (Earthen)
}

do
    local temp = {}
    for _, id in pairs(drinks) do
        temp[F.GetSpellInfo(id)] = true
    end
    drinks = temp
end

function I.IsDrinking(name)
    if not F.IsValueNonSecret(name) then return end
    return drinks[name]
end

-------------------------------------------------
-- healer
-------------------------------------------------
local spells =  {
    -- druid
    8936, -- 愈合 - Regrowth
    774, -- 回春术 - Rejuvenation
    155777, -- 回春术（萌芽） - Rejuvenation (Germination)
    33763, -- 生命绽放 - Lifebloom
    188550, -- 生命绽放 - Lifebloom
    48438, -- 野性成长 - Wild Growth
    102351, -- 塞纳里奥结界 - Cenarion Ward
    102352, -- 塞纳里奥结界 - Cenarion Ward
    391891, -- 激变蜂群 - Adaptive Swarm
    145205, -- 百花齐放 - Efflorescence
    383193, -- 林地护理 - Grove Tending
    439530, -- 共生绽华 - Symbiotic Blooms
    474754, -- 共生关系 - Symbiotic Relationship
    -- 429224, -- 次级塞纳里奥结界 - Minor Cenarion Ward (removed in 12.0, Durability of Nature redesigned)

    -- evoker
    363502, -- 梦境飞行 - Dream Flight
    370889, -- 双生护卫 - Twin Guardian
    364343, -- 回响 - Echo
    355941, -- 梦境吐息 - Dream Breath
    376788, -- 梦境吐息（回响） - Dream Breath (Echo)
    366155, -- 逆转 - Reversion
    367364, -- 逆转（回响） - Reversion (Echo)
    373862, -- 时空畸体 - Temporal Anomaly
    378001, -- 梦境投影（pvp） - Dream Projection (pvp)
    373267, -- 缚誓生命 - Lifebind
    395296, -- 黑檀之力 (self) - Ebon Might
    395152, -- 黑檀之力 - Ebon Might
    360827, -- 炽火龙鳞 - Blistering Scales
    410089, -- 先知先觉 - Prescience
    406732, -- 空间悖论 (self) - Spatial Paradox
    406789, -- 空间悖论 - Spatial Paradox
    445740, -- 纵焰 - Enkindle
    409895, -- 精神之花 - Spiritbloom (Reverberations, Chronowarden Hero Talent)
    410263, -- 炼狱祝福 - Inferno's Blessing
    410686, -- 共生绽放 - Symbiotic Bloom
    413984, -- 流沙 - Shifting Sands

    -- monk
    119611, -- 复苏之雾 - Renewing Mist
    124682, -- 氤氲之雾 - Enveloping Mist
    325209, -- 氤氲之息 - Enveloping Breath
    406139, -- 真气之茧 - Chi Cocoon from Yu'lon
    406220, -- 真气之茧 - Chi Cocoon from Chi-Ji
    450769, -- 和谐化身 - Aspect of Harmony
    450805, -- 净化之魂 - Purified Spirit
    467281, -- 金创药 - Healing Elixir
    115175, -- 抚慰之雾 - Soothing Mist

    -- paladin
    53563, -- 圣光道标 - Beacon of Light
    223306, -- 赋予信仰 - Bestow Faith
    148039, -- 信仰屏障 - Barrier of Faith
    156910, -- 信仰道标 - Beacon of Faith
    200025, -- 美德道标 - Beacon of Virtue
    287280, -- 圣光闪烁 - Glimmer of Light
    156322, -- 永恒之火 - Eternal Flame
    431381, -- 晨光 - Dawnlight
    -- 388013, -- 阳春祝福 - Blessing of Spring, removed in 12.0
    -- 388007, -- 仲夏祝福 - Blessing of Summer, removed in 12.0
    -- 388010, -- 暮秋祝福 - Blessing of Autumn, removed in 12.0
    -- 388011, -- 凛冬祝福 - Blessing of Winter, removed in 12.0
    200654, -- 提尔的拯救 - Tyr's Deliverance
    1244893, -- 救世主道标 - Beacon of the Savior
    432496, -- 圣洁壁垒 - Holy Bulwark (Holy Armaments shield variant)
    432502, -- 圣洁武器 - Holy Armaments (Sacred Weapon variant)

    -- priest
    139, -- 恢复 - Renew (removed in 12.0)
    200829, -- 恳求 - Plea (added in 12.0, Disc)
    41635, -- 愈合祷言 - Prayer of Mending
    17, -- 真言术：盾 - Power Word: Shield
    194384, -- 救赎 - Atonement
    77489, -- 圣光回响 - Echo of Light
    372847, -- 光明之泉恢复 - Blessed Bolt
    -- 443526, -- 慰藉预兆 - Premonition of Solace (removed in 12.0)
    1253593, -- 虚空之盾 - Void Shield

    -- shaman
    974, -- 大地之盾 - Earth Shield
    383648, -- 大地之盾（天赋） - Earth Shield
    61295, -- 激流 - Riptide
    382024, -- 大地生命武器 - Earthliving Weapon
    375986, -- 始源之潮 - Primordial Wave
    207400, -- 先祖活力 - Ancestral Vigor
    444490, -- 源水气泡 - Hydrobubble
    -- 73920, -- 治疗之雨 - Healing Rain
    -- 456366, -- 治疗之雨 - Healing Rain
}

function F.FirstRun()
    local currentLayoutTable = Cell.vars.currentLayoutTable

    -- Check if Healers indicator already exists
    for _, indicator in ipairs(currentLayoutTable["indicators"]) do
        if indicator["name"] == "Healers" then
            local existingAuras = indicator["auras"] or {}
            local seen = {}
            for _, id in ipairs(existingAuras) do seen[id] = true end

            local missing = {}
            for _, id in ipairs(spells) do
                if not seen[id] then tinsert(missing, id) end
            end

            if #missing == 0 then
                F.Print(L["Healers indicator is up to date."])
                return
            end

            -- Build icon preview for missing spells
            local icons = "\n\n"
            for _, id in ipairs(missing) do
                local icon = select(2, F.GetSpellInfo(id))
                if icon then icons = icons .. "|T"..icon..":0|t" end
            end

            local popup = Cell.CreateConfirmPopup(Cell.frames.anchorFrame, 200,
                string.format(L["Healers indicator already exists. Add new spells?"], #missing) .. icons,
                function()
                    for _, id in ipairs(missing) do
                        tinsert(indicator["auras"], id)
                    end
                    Cell.Fire("UpdateIndicators", Cell.vars.currentLayout, indicator["indicatorName"], "auras", "buff", indicator["auras"])
                    F.ReloadIndicatorList()
                end
            )
            popup:SetPoint("TOPLEFT")
            popup:Show()
            return
        end
    end

    -- No Healers found → create one
    local icons = "\n\n"
    for i, id in pairs(spells) do
        local icon = select(2, F.GetSpellInfo(id))
        if icon then
            icons = icons .. "|T"..icon..":0|t"
            if i % 11 == 0 then
                icons = icons .. "\n"
            end
        end
    end

    local popup = Cell.CreateConfirmPopup(Cell.frames.anchorFrame, 200, L["Would you like Cell to create a \"Healers\" indicator (icons)?"]..icons, function(self)
        local last = #currentLayoutTable["indicators"]
        if currentLayoutTable["indicators"][last]["type"] == "built-in" then
            indicatorName = "indicator1"
        else
            indicatorName = "indicator"..(tonumber(strmatch(currentLayoutTable["indicators"][last]["indicatorName"], "%d+"))+1)
        end

        tinsert(currentLayoutTable["indicators"], {
            ["name"] = "Healers",
            ["indicatorName"] = indicatorName,
            ["type"] = "icons",
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {13, 13},
            ["num"] = 5,
            ["numPerLine"] = 5,
            ["orientation"] = "right-to-left",
            ["spacing"] = {0, 0},
            ["font"] = {
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = true,
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}},
            ["auraType"] = "buff",
            ["castBy"] = "me",
            ["auras"] = spells,
        })
        Cell.Fire("UpdateIndicators", Cell.vars.currentLayout, indicatorName, "create", currentLayoutTable["indicators"][last+1])
        CellDB["firstRun"] = false
        F.ReloadIndicatorList()
    end, function()
        CellDB["firstRun"] = false
    end)
    popup:SetPoint("TOPLEFT")
    popup:Show()
end

-------------------------------------------------
-- cleuAuras
-------------------------------------------------
-- local cleuAuras = {}

-- function I.UpdateCleuAuras(t)
--     -- reset
--     wipe(cleuAuras)
--     -- insert
--     for _, c in pairs(t) do
--         local icon = select(2, F.GetSpellInfo(c[1]))
--         cleuAuras[c[1]] = {c[2], icon}
--     end
-- end

-- function I.CheckCleuAura(id)
--     return cleuAuras[id]
-- end

-------------------------------------------------
-- targetedSpells
-------------------------------------------------
local targetedSpells = {
    -- Altar of Fangs --------------
    1296220, -- Triple Shot
    1296050, -- Regurgitate
    1296058, -- Regurgitate
    1300503, -- Spiteful Hunt
    1299130, -- Burrowing Charge
    1300044, -- Venom Jet
    1301413, -- Boneslicer
    1294567, -- Paralyzing Shots
    1289416, -- Envenom
    1308865, -- Infest
    1294557, -- Piercing Hiss
    1306381, -- Fetid Spit (Stinkender Auswurf)
    1308862, -- Fetid Spit
    1294432, -- Septic Spatter
    1306232, -- Septic Spatter
    1305637, -- Septic Spatter
    1306235, -- Septic Spatter
    1306129, -- Septic Spatter
    1305641, -- Septic Spatter
    1294934, -- Noxious Spray
    1294859, -- Rattle
    1294197, -- Experimental Toxin
    1293985, -- Experimental Toxin
    1293983, -- Experimental Toxin

    -- Murder Row ------------------
    1214357, -- Fire Bomb
    1214637, -- Axe Toss
    474478, -- Killing Spree
    474765, -- Same-Day Delivery
    474766, -- Same-Day Delivery
    1222795, -- Envenom
    473898, -- Legion Strike
    474375, -- Chaos Bolt
    1217633, -- Corroding Spittle
    1217973, -- Curse of Doom
    1216954, -- Eye Beam
    1215872, -- Fel Beam
    1216570, -- Fel Missiles
    1201554, -- Seduction
    1217881, -- Shadow Bite
    1293101, -- Shadow Bite

    -- Den of Nalorakk -------------
    1243569, -- Overwhelming Onslaught
    1242860, -- Echoing Maul
    1242976, -- Echoing Maul
    1241226, -- Bloodrush
    1241214, -- Earth Bolt
    1246687, -- Lightning Bolt
    1241217, -- Shredding Claws
    1246847, -- Shoot
    1238439, -- Razor Dive
    1232012, -- Serrated Fists

    -- The Blinding Vale -----------
    1237090, -- Bloodthirsty Gaze
    1235640, -- Thornblade
    1238066, -- Thornblade
    1234850, -- Lightsower Dash
    1235564, -- Lightblossom Beam
    1239824, -- Lightfire
    1241058, -- Grievous Thrash
    1242135, -- Grievous Gash
    1247685, -- Thornspike
    1246607, -- Concentrated Lightbeam
    1237855, -- Earthrupture Strike
    1238063, -- Light Bolt
    1238368, -- Lightmaw Beams
    1250829, -- Potad-Toss
    1238232, -- Seed Shot
    1250100, -- Tongue Toss

    -- Voidscar Arena --------------
    1222098, -- Nether Dash
    1222100, -- Nether Dash
    1227264, -- Cosmic Crash
    1222642, -- Hulking Claw
    1226120, -- Poison Splash
    1249236, -- Fire Spit
    1228176, -- Lava Bolt
    1233472, -- Rip and Slice
    1239855, -- Sky Strike
    1234890, -- Smashing Charge
    1250640, -- Venomous Spit
    1227020, -- Dimensional Shred

    -- Kings' Rest -----------------
    265773, -- Spit Gold
    268932, -- Quaking Leap
    1303327, -- Quaking Leap
    1303115, -- Aerial Smash
    266951, -- Barrel Through
    266231, -- Severing Axe
    267618, -- Drain Fluids
    267702, -- Entomb
    271555, -- Entomb
    268586, -- Blade Combo
    1303488, -- Savage Maul
    270506, -- Deadeye Shot
    270507, -- Poison Barrage
    270492, -- Hex
    270284, -- Purification Beam
    270482, -- Blooded Leap
    270503, -- Hunting Leap
    269230, -- Hunting Leap
    269231, -- Hunting Leap
    270928, -- Bladestorm
    270891, -- Channel Lightning
    270920, -- Seduction
    270865, -- Hidden Blade
    271640, -- Dark Revelation
    270931, -- Darkshot

    -- Temple of Sethraliss --------
    264574, -- Power Shot
    268008, -- Snake Charm
    267237, -- Drain
    263309, -- Cyclone Strike
    263958, -- A Knot of Snakes
    1290029, -- A Knot of Snakes
    1289109, -- Thunder Spit
    1289059, -- Gale Force
    1288864, -- Tempest Winds
    1288428, -- Overload

    -- Ruby Life Pools -------------
    372858, -- Searing Blows
    381512, -- Stormslam
    372107, -- Molten Boulder
    372863, -- Ritual of Blazebinding
    372851, -- Chillstorm
    1307308, -- Chillstorm
    381862, -- Inferno Spit
    381602, -- Flamespit
    372087, -- Blazing Rush
    372047, -- Steel Barrage
    392640, -- Rolling Thunder
    392451, -- Flashfire
    373693, -- Living Bomb
}

function I.GetDefaultTargetedSpellsList()
    return targetedSpells
end

function I.GetDefaultTargetedSpellsGlow()
    return {"Pixel", {0.95,0.95,0.32,1}, 9, 0.25, 8, 2}
end

-------------------------------------------------
-- Actions
-------------------------------------------------
local actions = {
    {
        6262, -- 治疗石 - Healthstone
        {"A", {0.4, 1, 0}},
    },
    {
        1234768, -- 银月治疗药水 - Silvermoon Health Potion
        {"A", {1, 0.1, 0.1}},
    },
    {
        1236616, -- 圣光潜能 - Light's Potential
        {"C3", {1, 1, 0}},
    },
}


function I.GetDefaultActions()
    return actions
end

function I.ConvertActions(db)
    local temp = {}
    for _, t in pairs(db) do
        temp[t[1]] = t[2]
    end
    return temp
end

-------------------------------------------------
-- crowdControls
-------------------------------------------------
local crowdControls = { -- true: track by name, false: track by id
    ["DEATHKNIGHT"] = {
        [47476] = true, -- 绞袭 - Strangulate (PVP)
        [91800] = true, -- 撕扯 - Gnaw
        [207167] = true, -- 致盲冰雨 - Blinding Sleet
        [210128] = true, -- 复苏 - Reanimation
        [221562] = true, -- 窒息 - Asphyxiate
        [287254] = false, -- 寒冬死神 - Dead of Winter
        [377048] = true, -- 绝对零度 - Absolute Zero
    },

    ["DEMONHUNTER"] = {
        [179057] = true, -- 混乱新星 - Chaos Nova
        [205630] = true, -- 伊利丹之握 - Illidan's Grasp
        [204490] = true, -- 沉默咒符 - Sigil of Silence
        [207684] = true, -- 悲苦咒符 - Sigil of Misery
        [211881] = true, -- 邪能爆发 - Fel Eruption
        [217832] = true, -- 禁锢 - Imprison
        -- [213491] = true, -- 恶魔践踏
    },

    ["DRUID"] = {
        [99] = true, -- 夺魂咆哮 - Incapacitating Roar
        [2637] = true, -- 休眠 - Hibernate
        [5211] = true, -- 蛮力猛击 - Mighty Bash
        [22570] = true, -- 割碎 - Maim
        [33786] = true, -- 旋风 - Cyclone
        [81261] = true, -- 日光术 - Solar Beam
        [127797] = true, -- 乌索尔旋风 - Ursol's Vortex
        [163505] = false, -- 斜掠 - Rake
        [209749] = true, -- 精灵虫群 - Faerie Swarm
        [202244] = true, -- 蛮力冲锋 - Overrun
        [410065] = false, -- 活性树脂 - Reactive Resin
    },

    ["EVOKER"] = {
        [360806] = true, -- 梦游 - Sleep Walk
        [372245] = true, -- 天空霸主 - Terror of the Skies
        [408544] = true, -- 震地猛击 - Seismic Slam
    },

    ["HUNTER"] = {
        [1513] = true, -- 恐吓野兽 - Scare Beast
        [3355] = true, -- 冰冻陷阱 - Freezing Trap
        [24394] = true, -- 胁迫 - Intimidation
        [117526] = true, -- 束缚射击 - Binding Shot
        [213691] = true, -- 驱散射击 - Scatter Shot
        [357021] = false, -- 连续震荡 - Consecutive Concussion
        [407032] = true, -- 粘稠焦油炸弹 - Sticky Tar Bomb
    },

    ["MAGE"] = {
        [118] = true, -- 变形术 - Polymorph
        [31661] = true, -- 龙息术 - Dragon's Breath
        [82691] = true, -- 冰霜之环 - Ring of Frost
        [383121] = true, -- 群体变形 - Mass Polymorph
        [389831] = false, -- 积雪 - Snowdrift
    },

    ["MONK"] = {
        [115078] = true, -- 分筋错骨 - Paralysis
        [119381] = true, -- 扫堂腿 - Leg Sweep
        [198909] = true, -- 赤精之歌 - Song of Chi-Ji
        [202274] = true, -- 热酿 - Hot Trub
        [202346] = true, -- 醉上加醉 - Double Barrel
        [233759] = true, -- 抓钩武器 - Grapple Weapon (PVP)
    },

    ["PALADIN"] = {
        [853] = true, -- 制裁之锤 - Hammer of Justice
        [10326] = true, -- 超度邪恶 - Turn Evil
        [20066] = true, -- 忏悔 - Repentance
        [105421] = true, -- 盲目之光 - Blinding Light
        [234299] = true, -- 制裁之拳 - Fist of Justice
        [255941] = false, -- 灰烬觉醒 - Wake of Ashes
    },

    ["PRIEST"] = {
        [605] = true, -- 精神控制 - Mind Control
        [8122] = true, -- 心灵尖啸 - Psychic Scream
        [9484] = true, -- 束缚亡灵 - Shackle Undead
        [15487] = true, -- 沉默 - Silence
        [64044] = true, -- 心灵惊骇 - Psychic Horror
        [88625] = true, -- 圣言术-罚 - Holy Word: Chastise
        -- [226943] = true, -- 心灵炸弹
    },

    ["ROGUE"] = {
        [408] = true, -- 肾击 - Kidney Shot
        [1776] = true, -- 凿击 - Gouge
        [1833] = true, -- 偷袭 - Cheap Shot
        [2094] = true, -- 致盲 - Blind
        [6770] = true, -- 闷棍 - Sap
        [207777] = true, -- 卸除武装 - Dismantle (PVP)
        [212183] = true, -- 烟雾弹 - Smoke Bomb
    },

    ["SHAMAN"] = {
        [51514] = true, -- 妖术 - Hex
        [77505] = true, -- 地震术 - Earthquake
        [118345] = true, -- 粉碎 - Pulverize
        [118905] = true, -- 静电充能 - Static Charge
        [197214] = true, -- 裂地术 - Sundering
        [305485] = true, -- 闪电磁索 - Lightning Lasso
    },

    ["WARLOCK"] = {
        [710] = true, -- 放逐术 - Banish
        [5484] = true, -- 恐惧嚎叫 - Howl of Terror
        [5782] = true, -- 恐惧 - Fear
        [6358] = true, -- 诱惑 - Seduction
        [6789] = true, -- 死亡缠绕 - Mortal Coil
        [22703] = true, -- 地狱火觉醒 - Infernal Awakening
        [30283] = true, -- 暗影之怒 - Shadowfury
        [89766] = true, -- 巨斧投掷 - Axe Toss
        [196364] = false, -- 痛苦无常 - Unstable Affliction
        [213688] = true, -- 邪能顺劈 - Fel Cleave
    },

    ["WARRIOR"] = {
        [5246] = true, -- 破胆怒吼 - Intimidating Shout
        [132168] = true, -- 震荡波 - Shockwave
        [132169] = true, -- 风暴之锤 - Storm Bolt
        [236077] = true, -- 缴械 - Disarm (PVP)
    },

    ["UNCATEGORIZED"] = {
        [20549] = true, -- 战争践踏 - War Stomp
        [107079] = true, -- 震山掌 - Quaking Palm
        [255723] = true, -- 蛮牛冲撞 - Bull Rush
        [287712] = true, -- 强力一击 - Haymaker
    }
}

function I.GetCrowdControls()
    return crowdControls
end

local builtInCrowdControls = {}
local customCrowdControls = {}

function I.UpdateCrowdControls(t)
    -- user disabled
    wipe(builtInCrowdControls)
    for class, spells in pairs(crowdControls) do
        for id, trackByName in pairs(spells) do
            if not t["disabled"][id] then -- not disabled
                if trackByName then
                    local name = F.GetSpellInfo(id)
                    if name then
                        builtInCrowdControls[name] = true
                    end
                else
                    builtInCrowdControls[id] = true
                end
            end
        end
    end

    -- user created
    wipe(customCrowdControls)
    for _, id in pairs(t["custom"]) do
        local name = F.GetSpellInfo(id)
        if name then
            customCrowdControls[name] = true
        end
    end
end

function I.IsCrowdControls(name, id)
    if F.IsValueNonSecret(name) and (builtInCrowdControls[name] or customCrowdControls[name]) then
        return true
    end

    if F.IsValueNonSecret(id) then
        return builtInCrowdControls[id]
    end
end
