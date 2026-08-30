local _, JP = ...
local SafeSearchThreshold = {}

local function GetMinimumRuns()
    local value = MythicBoostDB and tonumber(MythicBoostDB.minimumKeystoneRuns)
    return value and math.max(0, math.floor(value)) or 20
end

-- После каждого завершённого +10 порог для собственного фильтра MythicBoost
-- растёт вместе с игроком. Стандартный LFG при этом не изменяется.
local function CountCompletedKey()
    local mapID, level, practiceRun
    if C_ChallengeMode.GetChallengeCompletionInfo then
        local info = C_ChallengeMode.GetChallengeCompletionInfo()
        if info then mapID, level, practiceRun = info.mapChallengeModeID, info.level, info.practiceRun end
    elseif C_ChallengeMode.GetCompletionInfo then
        mapID, level, _, _, _, practiceRun = C_ChallengeMode.GetCompletionInfo()
    end
    if practiceRun or type(level) ~= "number" or issecretvalue(level) or level < 10 then return end

    local signature = ("%s:%s"):format(tostring(mapID), tostring(level))
    local now = GetServerTime()
    if MythicBoostDB.lastCountedCompletion == signature and now - (MythicBoostDB.lastCountedAt or 0) < 300 then return end
    MythicBoostDB.lastCountedCompletion, MythicBoostDB.lastCountedAt = signature, now
    MythicBoostDB.minimumKeystoneRuns = GetMinimumRuns() + 1
    JP:Print(("Порог ключей +10 в фильтрах MythicBoost повышен до %d."):format(MythicBoostDB.minimumKeystoneRuns))
end

function SafeSearchThreshold:Create()
    -- В Midnight panel.results и связанные поля стандартного Group Finder
    -- являются secret. Их нельзя фильтровать или перерисовывать из аддона.
    if MythicBoostDB then MythicBoostDB.filterGroupFinder = false end
    if self.events then return end
    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self.events:SetScript("OnEvent", function()
        C_Timer.After(1, CountCompletedKey)
    end)
end

function SafeSearchThreshold:Enable() end
function SafeSearchThreshold:Disable() end
function SafeSearchThreshold:Destroy() end

JP:RegisterModule("SearchResultInterest", SafeSearchThreshold)
