local _, JP = ...
local Info, UI, L, C = {}, JP.UI, JP.L, JP.UI.colors

local PROJECT_URL = "https://www.curseforge.com/wow/addons/mythicboost"

local function Text(parent, value, template, color)
    local f = UI.Text(parent, template or "GameFontHighlightSmall", value or "", color or C.text)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(true)
    return f
end

local function Version()
    if type(JP.GetVersion) == "function" then
        local ok, value = pcall(JP.GetVersion, JP)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return L("неизвестна")
end

function Info:Build(page)
    if self.page or not page then return end
    self.page = page

    local intro = Text(page, L("Баг-репорты, исправления, идеи новых функций и помощь с поддержкой MythicBoost — через страницу проекта CurseForge."))
    intro:SetPoint("TOPLEFT", 28, -84); intro:SetPoint("TOPRIGHT", -28, -84); intro:SetHeight(38)

    local reportTitle = Text(page, L("Что приложить к сообщению об ошибке"), "GameFontHighlight", C.accent)
    reportTitle:SetPoint("TOPLEFT", 28, -132); reportTitle:SetWidth(600); reportTitle:SetWordWrap(false)
    local report = Text(page, L("Версия аддона и клиента; короткие шаги воспроизведения; полный текст Lua-ошибки; скриншот — по желанию."))
    report:SetPoint("TOPLEFT", 28, -160); report:SetPoint("TOPRIGHT", -28, -160); report:SetHeight(40)

    local proposal = Text(page, L("Хочешь присоединиться к разработке или взять на себя поддержку? Напиши автору на CurseForge."))
    proposal:SetPoint("TOPLEFT", 28, -214); proposal:SetPoint("TOPRIGHT", -28, -214); proposal:SetHeight(32)

    local linkTitle = Text(page, L("Страница проекта"), "GameFontHighlight", C.accent)
    linkTitle:SetPoint("TOPLEFT", 28, -264); linkTitle:SetWidth(600); linkTitle:SetWordWrap(false)
    local holder = UI.Panel(page, C.field, C.line)
    holder:SetPoint("TOPLEFT", 28, -292); holder:SetPoint("TOPRIGHT", -164, -292); holder:SetHeight(30)
    local field = CreateFrame("EditBox", nil, holder)
    field:SetPoint("TOPLEFT", 8, -2); field:SetPoint("BOTTOMRIGHT", -8, 2)
    field:SetFontObject("GameFontHighlightSmall"); field:SetAutoFocus(false)
    field:SetTextInsets(2, 2, 0, 0); field:SetJustifyH("LEFT"); field:SetText(PROJECT_URL)
    local restoring
    field:SetScript("OnTextChanged", function(self, userInput)
        -- Keep the URL selectable but never editable or replaced by opaque
        -- input. This runs only after the user attempts an edit.
        if userInput and not restoring and self:GetText() ~= PROJECT_URL then
            restoring = true; self:SetText(PROJECT_URL); restoring = nil
        end
    end)
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.urlField = field
    local selectButton = UI.Button(page, L("Выделить ссылку"), 122, 28)
    selectButton:SetPoint("TOPRIGHT", -28, -291)
    selectButton:SetScript("OnClick", function()
        -- Clipboard APIs are not available to addons. A manual click focuses
        -- and selects the URL so the player can use the client copy shortcut.
        field:SetFocus(); field:HighlightText()
    end)
    self.selectButton = selectButton

    local copyHint = Text(page, L("Нажми «Выделить ссылку», затем Ctrl+C в поле."), nil, C.muted)
    copyHint:SetPoint("TOPLEFT", 28, -332); copyHint:SetPoint("TOPRIGHT", -28, -332); copyHint:SetHeight(24)
    local version = Text(page, (L("Версия аддона: %s")):format(Version()), nil, C.muted)
    version:SetPoint("TOPLEFT", 28, -372); version:SetWidth(600); version:SetWordWrap(false)
    self.versionLabel = version
end

function Info:Refresh()
    if self.versionLabel then self.versionLabel:SetText((L("Версия аддона: %s")):format(Version())) end
end

JP.Information = Info
JP:RegisterModule("Information", Info)
