local _, JP = ...
local RoleSlotFilter = {}
local UI = JP.UI

local updating = false
local filterQueued = false

local function GetMinimumRuns()
    local value = MythicBoostDB and tonumber(MythicBoostDB.minimumKeystoneRuns)
    return value and math.max(0, math.floor(value)) or 20
end

local function GetPlayerRole()
    local specialization = GetSpecialization and GetSpecialization()
    if specialization then
        local role = GetSpecializationRole(specialization)
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
end

local function HasFreeSlot(resultID, role)
    local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
    if type(counts) ~= "table" then return false end
    local remaining = counts[role .. "_REMAINING"]
    return type(remaining) == "number" and not issecretvalue(remaining) and remaining > 0
end

local function LeaderHasEnoughRuns(resultID)
    -- Строгий режим: недоступный профиль не может доказать, что лидер набрал
    -- нужное число ключей, поэтому такой результат фильтр не проходит.
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or (issecretvaluekey and issecretvaluekey(info, "leaderName")) then return false end
    local leaderName = info.leaderName
    if type(leaderName) ~= "string" or issecretvalue(leaderName) then return false end
    local profile = RaiderIO.GetProfile(leaderName)
    local keystone = profile and profile.mythicKeystoneProfile
    if not keystone then return false end
    local total = 0
    for _, level in ipairs({ 10, 12, 15 }) do
        local count = keystone["keystoneMilestone" .. level]
        if type(count) == "number" and not issecretvalue(count) then total = total + count end
    end
    return total >= GetMinimumRuns()
end

-- Фильтр работает только когда может доказать своё решение. Без Raider.IO
-- он вычистил бы вообще все группы, и стандартный поиск выглядел бы
-- сломанным, поэтому в таком случае список остаётся нетронутым.
local function FilterEnabled()
    if not MythicBoostDB or MythicBoostDB.filterGroupFinder == false then return false end
    return RaiderIO and type(RaiderIO.GetProfile) == "function"
end

local function FilterResults(panel)
    if updating or not panel or not FilterEnabled() then return end
    local role = GetPlayerRole()
    if not role then return end
    -- Запускаемся после того, как Blizzard и Premade Groups Filter собрали
    -- свой итоговый список, и сужаем его, а не строим заново.
    local results = panel.results
    if type(results) ~= "table" then return end

    local filtered = {}
    for _, resultID in ipairs(results) do
        if HasFreeSlot(resultID, role) and LeaderHasEnoughRuns(resultID) then
            filtered[#filtered + 1] = resultID
        end
    end

    updating = true
    panel.results = filtered
    panel.totalResults = #filtered
    LFGListSearchPanel_UpdateResults(panel)
    updating = false
end

local function QueueFilterResults(panel)
    if filterQueued then return end
    filterQueued = true
    C_Timer.After(0, function()
        filterQueued = false
        FilterResults(panel)
    end)
end

-- Каждый сданный ключ +10 поднимает планку: список групп не должен
-- предлагать лидеров слабее тебя самого.
local function CountCompletedKey(module)
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

    if module.minimumRunsBox then
        module.minimumRunsBox:SetText(tostring(MythicBoostDB.minimumKeystoneRuns))
    end
    JP:Print(("Порог ключей +10 повышен до %d."):format(MythicBoostDB.minimumKeystoneRuns))
end

local function ApplyMinimumRuns(panel, value)
    MythicBoostDB.minimumKeystoneRuns = math.max(0, math.floor(value))
    if type(LFGListSearchPanel_UpdateResultList) == "function" then
        LFGListSearchPanel_UpdateResultList(panel)
    end
end

local function CreateMinimumRunsBox(module, panel, anchor)
    local field, box = UI.NumberBox(panel, 44, 21)
    box:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 3)
    field:SetMaxLetters(3)
    field:SetText(tostring(GetMinimumRuns()))
    field:HookScript("OnEnter", function(self)
        UI.Tooltip(self, "Минимум ключей +10",
            "MythicBoost прячет из списка лидеров, у которых пройдено меньше указанного числа ключей +10 и выше.",
            "Профиль без данных Raider.IO тоже скрывается. Выключить фильтр: /mb filter")
    end)
    field:HookScript("OnLeave", GameTooltip_Hide)
    field:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local value = tonumber(self:GetText())
        if value then ApplyMinimumRuns(panel, value) end
    end)
    field:SetScript("OnEnterPressed", function(self)
        local value = math.max(0, math.floor(tonumber(self:GetText()) or 20))
        ApplyMinimumRuns(panel, value)
        self:SetText(tostring(value))
        self:ClearFocus()
    end)
    module.minimumRunsBox = field
end

function RoleSlotFilter:Create()
    if not self.completionWatcher then
        self.completionWatcher = CreateFrame("Frame")
        self.completionWatcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        self.completionWatcher:SetScript("OnEvent", function()
            C_Timer.After(1, function() CountCompletedKey(self) end)
        end)
    end
    if self.hooked then return end

    local function Install()
        if self.hooked or type(LFGListSearchPanel_UpdateResultList) ~= "function" then return end
        hooksecurefunc("LFGListSearchPanel_UpdateResultList", QueueFilterResults)
        self.hooked = true

        local panel = LFGListFrame and LFGListFrame.SearchPanel
        local filterButton = panel and panel.FilterButton
        if panel and filterButton and not self.minimumRunsBox then
            CreateMinimumRunsBox(self, panel, filterButton)
        end
    end

    Install()
    if not self.hooked then
        self.loader = CreateFrame("Frame")
        self.loader:RegisterEvent("ADDON_LOADED")
        self.loader:SetScript("OnEvent", function(_, _, name)
            if name == "Blizzard_GroupFinder" then Install() end
        end)
    end
end

function RoleSlotFilter:Enable() end
function RoleSlotFilter:Disable() end
function RoleSlotFilter:Destroy() end

JP:RegisterModule("SearchResultInterest", RoleSlotFilter)
