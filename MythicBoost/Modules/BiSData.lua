local _, JP = ...
local BiSData = {}
local SLOT_NAMES = {[1]="head",[2]="neck",[3]="shoulder",[5]="chest",[6]="waist",
    [7]="legs",[8]="feet",[9]="wrist",[10]="hands",[11]="ring",[12]="ring",
    [13]="trinket",[14]="trinket",[15]="back",[16]="main-hand",[17]="off-hand"}
local TIER_SLOTS = {head=true,shoulder=true,chest=true,hands=true,legs=true}

-- Curated list from the exact Mythic+-only table supplied by the user.
-- Only factual item IDs and source metadata are stored; guide prose is not
-- copied. TOP data for every other specialization comes from SeasonTop.lua.
local WOWHEAD_GUIDE = {
    [105] = { -- Restoration Druid
        updatedAt = "2026-08-12",
        url = "https://www.wowhead.com/guide/classes/druid/restoration/bis-gear#bis-items-mythic-only",
        items = {
            [251142] = { slot="neck", name="Pendant of Malefic Fury" },
            [251190] = { slot="back", name="Bloodthorn Burnous" },
            [159317] = { slot="waist", name="Whirling Dervish Sash" },
            [251153] = { slot="feet", name="Arctic Explorer's Legwraps" },
            [159459] = { slot="ring", name="Ritual Binder's Ring" },
            [252258] = { slot="ring", name="Sickening Signet of Atroxus" },
            [250214] = { slot="trinket", name="Lightspire Core" },
            [250255] = { slot="trinket", name="Unstable Felheart Crystal" },
            [159636] = { slot="main-hand", name="Staff of the Lightning Serpent" },
        },
    },
}

function BiSData:GetCurrentSpecID()
    local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
    local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
    local index = JP.SafeNumber(JP.SafeCall(getSpec))
    local specID = index and JP.SafeCall(getInfo, index)
    return type(specID) == "number" and not issecretvalue(specID) and specID or nil
end

function BiSData:GetLootSpecID()
    local specID = GetLootSpecialization and JP.SafeNumber(GetLootSpecialization())
    return specID and specID > 0 and specID or self:GetCurrentSpecID()
end

local function AutoSpec(specID)
    local data = JP.AutoBiSData
    return data and data.specs and data.specs[specID], data
end

local function SelectedVariants(spec, context)
    local selected, dedicated = {}, false
    for _, variant in ipairs(spec.variants or {}) do
        if variant.context == context then dedicated = true end
    end
    for _, variant in ipairs(spec.variants or {}) do
        if (dedicated and variant.context == context)
            or (not dedicated and (variant.context == "overall" or context == "overall")) then
            selected[#selected+1] = variant
        end
    end
    return selected
end

-- Membership is a separate fact from a particular spec's BiS selection.
-- Use explicit tier/catalyst evidence in the five set slots across the class;
-- never infer a set from an item level, item-ID range or equipment slot alone.
function BiSData:GetTierItem(specID, itemID)
    local spec, data = AutoSpec(specID)
    if not spec then return end
    if self.tierSource ~= data then
        self.tierSource, self.tierByClass = data, {}
        for _, classSpec in pairs(data.specs) do
            local class = classSpec.slug:match("^([^/]+)/")
            local items = self.tierByClass[class] or {}
            self.tierByClass[class] = items
            for _, variant in ipairs(classSpec.variants or {}) do
                for id, item in pairs(variant.items or {}) do
                    local source = item.dropSource or ""
                    if TIER_SLOTS[item.slot] and (item.dropKind == "tier" or source:find("Catalyst",1,true)) then
                        if not items[id] then
                            items[id] = {itemID=id,kind="tier",label="TIER",isTier=true,
                                name=item.name,slot=item.slot,dropSource=source,dropKind=item.dropKind}
                        end
                    end
                end
            end
        end
    end
    local items = self.tierByClass[spec.slug:match("^([^/]+)/")]
    return items and items[itemID]
end

function BiSData:GetGuideItem(specID, itemID, context)
    local spec, data = AutoSpec(specID)
    if not spec then return end
    local variants, selected = {}, nil
    -- A dedicated M+/raid list takes precedence over the overall list.
    for _, variant in ipairs(SelectedVariants(spec, context)) do
        local item = variant.items and variant.items[itemID]
        if item then
            selected = selected or item
            variants[#variants + 1] = variant.name
        end
    end
    if selected then
        return {
            itemID = itemID, kind = "bis", label = "BIS", name = selected.name, slot = selected.slot,
            isTier = self:GetTierItem(specID, itemID) ~= nil,
            source = data.source, updatedAt = data.updatedAt,
            url = "https://www.wowhead.com/guide/classes/" .. spec.slug .. "/bis-gear",
            dropSource = selected.dropSource, dropKind = selected.dropKind,
            variants = variants, variant = table.concat(variants, " / "),
        }
    end
end

function BiSData:GetRecommendationsForSlot(specID, inventorySlotID, context)
    local spec = AutoSpec(specID)
    local slot, result, seen = SLOT_NAMES[inventorySlotID], {}, {}
    if not spec or not slot then return result end
    context = context or "overall"
    for _, variant in ipairs(SelectedVariants(spec, context)) do
        for id, item in pairs(variant.items or {}) do
            if item.slot == slot and not seen[id] then
                seen[id] = true
                result[#result+1] = self:GetGuideItem(specID, id, context)
            end
        end
    end
    table.sort(result, function(a,b) return a.itemID < b.itemID end)
    return result
end

function BiSData:GetSourceText(recommendation)
    local L = JP.L
    local source = recommendation and JP.SafeString(recommendation.dropSource)
    if not source then return L("Источник не указан в гайде") end
    source = source:gsub("Tier Set", function() return L("Тир-сет") end)
        :gsub("Catalyst", function() return L("Катализатор") end)
        :gsub("%(Raid%)", function() return "(" .. L("Рейд") .. ")" end)
    if source == "Crafting" or source == "Crafting/Misc" then return L("Ремесло") end
    local kind = recommendation.dropKind
    if kind == "raid" and not source:find(L("Рейд"),1,true) then return L("Рейд") .. ": " .. source end
    if kind == "mplus" then return L("Подземелье") .. ": " .. source end
    return source
end

function BiSData:GetItem(specID, itemID, context)
    specID, itemID = tonumber(specID), tonumber(itemID)
    if not specID or not itemID then return end

    context = context or "overall"
    local auto = self:GetGuideItem(specID, itemID, context)
    if auto then return auto end
    -- Do not resurrect older curated recommendations once this spec has
    -- a current complete guide. Raid advice never falls back to M+ popularity.
    local autoSpec = AutoSpec(specID)
    if autoSpec or context == "raid" then return end

    local guide = WOWHEAD_GUIDE[specID]
    local guideItem = guide and guide.items[itemID]
    if guideItem then
        return {
            kind = "bis", label = "BIS", name = guideItem.name, slot = guideItem.slot,
            source = "Wowhead M+ BiS", updatedAt = guide.updatedAt, url = guide.url,
        }
    end

    local season = JP.SeasonTopData and JP.SeasonTopData.specs and JP.SeasonTopData.specs[specID]
    local topItem = season and season.items and season.items[itemID]
    if topItem then
        return {
            kind = "top", label = "TOP", name = topItem.name, slot = topItem.slot,
            share = tonumber(topItem.share) or 0, sample = tonumber(season.sample) or 0,
            source = "Murlok.io M+ top players", updatedAt = season.updatedAt,
            season = season.season,
        }
    end
end

function BiSData:GetSourceStatus(specID)
    specID = tonumber(specID) or self:GetCurrentSpecID()
    local autoSpec, data = AutoSpec(specID)
    if autoSpec then return data, nil end
    local guide = specID and WOWHEAD_GUIDE[specID]
    local season = specID and JP.SeasonTopData and JP.SeasonTopData.specs and JP.SeasonTopData.specs[specID]
    return guide, season
end

JP.BiSData = BiSData

