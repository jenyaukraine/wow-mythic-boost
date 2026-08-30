local _, JP = ...
local BiSData = {}

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
    local index = GetSpecialization and GetSpecialization()
    local specID = index and GetSpecializationInfo and GetSpecializationInfo(index)
    return type(specID) == "number" and not issecretvalue(specID) and specID or nil
end

function BiSData:GetItem(specID, itemID)
    specID, itemID = tonumber(specID), tonumber(itemID)
    if not specID or not itemID then return end

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
    local guide = specID and WOWHEAD_GUIDE[specID]
    local season = specID and JP.SeasonTopData and JP.SeasonTopData.specs and JP.SeasonTopData.specs[specID]
    return guide, season
end

JP.BiSData = BiSData

