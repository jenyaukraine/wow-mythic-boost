local _, JP = ...
local UI, C, L = JP.UI, JP.UI.colors, JP.L
local Filters = {cache={}}
local DEFAULTS = {unit="player", own="any", auraType="any", combat="any", group="any",
    instance="any", alive=false, unmounted=false, dispel="any", stealable=false,
    minStacks=0, maxStacks=0, minRemaining=0, maxRemaining=0, minDuration=0, maxDuration=0}
local UNITS = {player=true, target=true, focus=true, pet=true, party1=true, party2=true, party3=true, party4=true}
local function Settings()
    local s = JP.Settings("positiveAuraTracker")
    s.filters = type(s.filters)=="table" and s.filters or {}
    return s
end
local function Number(value)
    local n = JP.SafeNumber(value)
    return n and n==n and n>=0 and n<math.huge and n or nil
end
function Filters:Rules(id)
    if self.cache[id] then return self.cache[id] end
    local s, result = Settings(), {}
    local all = type(s.filters[0])=="table" and s.filters[0] or {}
    local own = type(s.filters[id])=="table" and s.filters[id] or {}
    for key, default in pairs(DEFAULTS) do
        local value = own[key]
        if value==nil then value=all[key] end
        if value==nil then value=default end
        if type(default)=="number" then value=math.min(3600, Number(value) or 0) end
        result[key]=value
    end
    if not UNITS[result.unit] then result.unit="player" end
    self.cache[id]=result
    return result
end
function Filters:Invalidate() wipe(self.cache) end

-- Unknown is not false. In particular, a remote/hidden party member cannot
-- produce a valid missing-buff warning. All comparisons use public values.
function Filters:CanLoad(r)
    if r.combat~="any" then
        local combat=JP.SafeOptionalBoolean(InCombatLockdown())
        if combat==nil or combat~=(r.combat=="in") then return false end
    end
    if r.group~="any" then
        local group=JP.SafeOptionalBoolean(IsInGroup())
        if group==nil or group~=(r.group=="group") then return false end
    end
    if r.instance~="any" then
        local _, kind=IsInInstance()
        if JP.SafeString(kind)~=r.instance then return false end
    end
    if r.unmounted and JP.SafeOptionalBoolean(IsMounted())~=false then return false end
    if r.unit~="player" then
        if JP.SafeOptionalBoolean(UnitExists(r.unit))~=true
            or JP.SafeOptionalBoolean(UnitIsVisible(r.unit))~=true
            or JP.SafeOptionalBoolean(UnitCanAssist("player", r.unit))~=true then return false end
    end
    if r.alive and JP.SafeOptionalBoolean(UnitIsDeadOrGhost(r.unit))~=false then return false end
    return true
end

-- false, true = unavailable field, never treat it as a failed/missing aura.
function Filters:Matches(r, aura, now)
    if not aura then return true, false end
    if r.own~="any" then
        local source=JP.SafeString(aura.sourceUnit)
        if not source then return false, true end
        local mine=source=="player" or source=="pet" or source=="vehicle"
        if mine~=(r.own=="mine") then return false, false end
    end
    if r.auraType~="any" then
        local helpful=JP.SafeOptionalBoolean(aura.isHelpful)
        local harmful=JP.SafeOptionalBoolean(aura.isHarmful)
        local value = r.auraType=="buff" and helpful or harmful
        if r.auraType=="buff" then value=helpful end
        if value==nil then return false, true end
        if not value then return false, false end
    end
    if r.stealable then
        local value=JP.SafeOptionalBoolean(aura.isStealable)
        if value==nil then return false, true end
        if not value then return false, false end
    end
    if r.dispel~="any" then
        local value=JP.SafeString(aura.dispelName)
        if JP.IsSecret(aura.dispelName) then return false, true end
        if (value or "none")~=r.dispel then return false, false end
    end
    local function Range(value, minimum, maximum)
        if minimum<=0 and maximum<=0 then return true, false end
        if value==nil then return false, true end
        return value>=minimum and (maximum<=0 or value<=maximum), false
    end
    local ok, blocked=Range(Number(aura.applications), r.minStacks, r.maxStacks)
    if not ok then return ok, blocked end
    local duration=Number(aura.duration)
    ok, blocked=Range(duration, r.minDuration, r.maxDuration)
    if not ok then return ok, blocked end
    local expiration=Number(aura.expirationTime)
    local remaining=duration==0 and math.huge or (expiration and math.max(0, expiration-now))
    return Range(remaining, r.minRemaining, r.maxRemaining)
end
function Filters:NextBoundary(r, aura, now)
    if not aura or (Number(aura.duration) or 0)<=0 then return end
    local expiration=Number(aura.expirationTime)
    if not expiration then return end
    local nextTime
    for _, threshold in ipairs({r.minRemaining, r.maxRemaining}) do
        local time=expiration-threshold+.02
        if threshold>0 and time>now+.005 and (not nextTime or time<nextTime) then nextTime=time end
    end
    return nextTime
end

function Filters:Build(page)
    if self.page then return end
    self.page, self.selected, self.controls = page, 0, {}
    local select = UI.Button(page, "", 320, 30)
    select:SetPoint("TOPLEFT", 28, -84)
    local function Apply()
        self:Invalidate(); self:RefreshEditor()
        if JP.PositiveAuraTracker then JP.PositiveAuraTracker:Refresh() end
    end
    select:SetScript("OnClick", function()
        local ids=Settings().spellIDs or {}; local nextID=ids[1] or 0
        for i,id in ipairs(ids) do if id==self.selected then nextID=ids[i+1] or 0; break end end
        self.selected=nextID; self:RefreshEditor()
    end)
    self.selector=select
    local reset=UI.Button(page, L("Сбросить условия"), 180, 30)
    reset:SetPoint("LEFT", select, "RIGHT", 12, 0)
    reset:SetScript("OnClick", function() Settings().filters[self.selected]=nil; Apply() end)
    local y=130
    local function Store(key,value)
        local s=Settings()
        s.filters[self.selected]=type(s.filters[self.selected])=="table" and s.filters[self.selected] or {}
        s.filters[self.selected][key]=value; Apply()
    end
    local function Row(key,label,choices)
        local text=UI.Text(page,"GameFontHighlightSmall",label,C.text)
        text:SetPoint("TOPLEFT",28,-y); text:SetPoint("RIGHT",page,"RIGHT",-282,0)
        text:SetJustifyH("LEFT"); text:SetWordWrap(false)
        local control
        if choices then
            control=UI.Button(page,"",230,28)
            control:SetScript("OnClick",function()
                local current=self:Rules(self.selected)[key]; local nextIndex=1
                for i,item in ipairs(choices) do if item[1]==current then nextIndex=i % #choices+1; break end end
                Store(key,choices[nextIndex][1])
            end)
        else
            control=CreateFrame("EditBox",nil,page,"InputBoxTemplate")
            control:SetSize(230,28); control:SetAutoFocus(false)
            local function Commit(owner)
                local value=tonumber(owner:GetText())
                if value and value==value and value>=0 and value<=3600 then Store(key,value)
                else self:RefreshEditor() end
                owner:ClearFocus()
            end
            control:SetScript("OnEnterPressed",Commit)
            control:SetScript("OnEscapePressed",function(owner) owner:ClearFocus(); self:RefreshEditor() end)
            control:SetScript("OnHide",function(owner) owner:ClearFocus() end)
        end
        control:SetPoint("TOPRIGHT",-28,-y+5)
        self.controls[key]={widget=control,choices=choices}
        y=y+34
    end
    Row("unit",L("Цель отслеживания"),{{"player",L("Игрок")},{"target",L("Цель")},{"focus",L("Фокус")},{"pet",L("Питомец")},
        {"party1","Party 1"},{"party2","Party 2"},{"party3","Party 3"},{"party4","Party 4"}})
    Row("auraType",L("Тип ауры"),{{"any",L("Любой")},{"buff",L("Бафф")},{"debuff",L("Дебафф")}})
    Row("own",L("Источник ауры"),{{"any",L("Любой")},{"mine",L("Я или мой питомец")},{"others",L("Другие игроки")}})
    Row("combat",L("Состояние боя"),{{"any",L("Всегда")},{"in",L("В бою")},{"out",L("Вне боя")}})
    Row("group",L("Состав"),{{"any",L("Всегда")},{"group",L("В группе")},{"solo",L("Соло")}})
    Row("instance",L("Где показывать"),{{"any",L("Везде")},{"none",L("Открытый мир")},{"party",L("Подземелье")},
        {"raid",L("Рейд")},{"arena",L("Арена")},{"pvp",L("Поле боя")}})
    local yesNo={{false,L("Нет")},{true,L("Да")}}
    Row("alive",L("Только живая цель"),yesNo); Row("unmounted",L("Скрывать на ездовом животном"),yesNo)
    Row("stealable",L("Только похищаемые ауры"),yesNo)
    Row("dispel",L("Тип рассеивания"),{{"any",L("Любой")},{"Magic",L("Магия")},{"Curse",L("Проклятие")},
        {"Disease",L("Болезнь")},{"Poison",L("Яд")},{"Enrage",L("Исступление")},{"none",L("Нет")}})
    Row("minStacks",L("Стаки: минимум")); Row("maxStacks",L("Стаки: максимум"))
    Row("minRemaining",L("Осталось секунд: минимум")); Row("maxRemaining",L("Осталось секунд: максимум"))
    Row("minDuration",L("Длительность: минимум секунд")); Row("maxDuration",L("Длительность: максимум секунд"))
    local note=UI.Text(page,"GameFontHighlightSmall",
        L("Нажми на название сверху, чтобы выбрать ауру. «Весь список» задаёт общие условия; индивидуальные значения их заменяют. Числа: 0 — без ограничения, Enter — сохранить. Все условия объединяются через И.\n\nТолько открытые данные дружественных целей. Закрытые ауры и неизвестные поля не проходят проверку и не считаются отсутствующим баффом. Полного сканирования и пользовательского Lua-кода нет."),C.muted)
    note:SetPoint("TOPLEFT",28,-y); note:SetPoint("TOPRIGHT",-28,-y); note:SetJustifyH("LEFT")
    self.status=UI.Text(page,"GameFontHighlightSmall","",C.amber)
    self.status:SetPoint("TOPLEFT",note,"BOTTOMLEFT",0,-12)
    local function Layout() page:SetHeight(y+note:GetStringHeight()+70) end
    page:HookScript("OnSizeChanged",Layout)
    page:HookScript("OnShow",function() self:RefreshEditor(); Layout() end)
    self:RefreshEditor()
end
function Filters:RefreshEditor()
    if not self.selector then return end
    local id=self.selected
    self.selector:SetText(id==0 and L("Весь список") or ("Spell ID: "..id))
    local rules=self:Rules(id)
    for key,row in pairs(self.controls) do
        local value=rules[key]
        if row.choices then
            for _,item in ipairs(row.choices) do if item[1]==value then row.widget:SetText(item[2]); break end end
        else row.widget:SetText(tostring(value)) end
    end
    self:UpdateStatus()
end
function Filters:UpdateStatus()
    if self.status and self.page:IsShown() then
        local count=JP.PositiveAuraTracker and JP.PositiveAuraTracker.blockedCount or 0
        self.status:SetText((L("Недоступных проверок аур: %d")):format(count))
    end
end
JP.AuraFilters=Filters
