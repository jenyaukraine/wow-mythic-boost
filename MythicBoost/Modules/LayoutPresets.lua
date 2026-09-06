local _, JP = ...
local UI, C, L = JP.UI, JP.UI.colors, JP.L
local Presets = {}

-- User-supplied native Edit Mode export. Opaque data, never evaluated as Lua.
-- Deliberately no layout import/save/activation API: the player owns that step.
Presets.Main = [=[2 52 0 0 0 7 7 UIParent 0.0 2.0 -1 ##$$%-&('%)$+#,$ 0 1 1 7 7 UIParent 0.0 45.0 -1 ##$$%-&('%(#,$ 0 2 1 7 7 UIParent 0.0 45.0 -1 ##$$%/&('%(#,$ 0 3 0 3 3 UIParent 2.0 39.0 -1 #$$$%+&('%(#,$ 0 4 1 5 5 UIParent -5.0 -77.0 -1 #$$$%/&('%(#,$ 0 5 1 1 4 UIParent 0.0 0.0 -1 ##$$%/&('%(#,$ 0 6 1 1 4 UIParent 0.0 -50.0 -1 ##$$%/&('%(#,$ 0 7 1 1 4 UIParent 0.0 -100.0 -1 ##$$%/&('%(#,$ 0 10 1 7 7 UIParent 0.0 45.0 -1 ##$$&('% 0 11 1 7 7 UIParent 0.0 45.0 -1 ##$$&('%,# 0 12 1 7 7 UIParent 0.0 45.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%(&( 3 0 1 8 7 UIParent -300.0 250.0 -1 $#3# 3 1 1 6 7 UIParent 300.0 250.0 -1 %#3# 3 2 1 6 7 UIParent 520.0 265.0 -1 %#&#3# 3 3 0 0 0 UIParent 1235.3 -874.0 -1 '$(#)#-Y.=/#1#3#5#6,7-7$8(9( 3 4 0 0 0 UIParent 1268.7 -479.2 -1 ,$-C.;/#0#1#2(3#5#6+7-7$8(9( 3 5 0 2 2 UIParent -244.0 -0.0 -1 &#*$3# 3 6 1 5 5 UIParent 0.0 0.0 -1 -5.)/#4$5#6(7-7$8(9( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 1 7 7 UIParent 0.0 45.0 -1 # 5 -1 1 7 7 UIParent 0.0 45.0 -1 # 6 0 0 4 4 UIParent -427.2 -400.0 -1 ##$#%#&.(()( 6 1 1 2 2 UIParent -270.0 -155.0 -1 ##$#%#'+(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 1 7 7 UIParent 0.0 45.0 -1 # 8 -1 0 6 6 UIParent 34.0 34.0 -1 #'$D%$&7 9 -1 1 7 7 UIParent 0.0 45.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 4 4 UIParent 900.0 -349.1 -1 # 12 -1 0 5 5 UIParent -2.0 -82.8 -1 #F$#%# 13 -1 0 2 8 MinimapCluster 0.0 -4.0 -1 ##$#%%&+ 14 -1 1 2 2 MicroButtonAndBagsBar 0.0 10.0 -1 ##$#%( 15 0 0 1 1 UIParent -37.7 -2.0 -1 &- 15 1 0 0 2 MainStatusTrackingBarContainer 4.0 0.0 -1 &- 16 -1 0 7 7 UIParent -266.2 2.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 7 7 UIParent 700.0 802.0 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 1 7 7 UIParent 0.0 310.0 -1 ##$/%$&('%(-($)%+$,$-$ 20 1 1 7 7 UIParent 0.0 240.0 -1 ##$*%$&('%(-($)%+$,$-$ 20 2 0 7 7 UIParent 0.0 102.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 4 4 UIParent -800.0 -300.0 -1 #$$$%#&('((-($)#*#+$,$-$.-.$ 21 -1 1 7 7 UIParent -410.0 380.0 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 0 7 7 UIParent -800.0 402.0 -1 #$$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+% 23 -1 0 7 7 UIParent 938.2 2.0 -1 ##$#%$&X'2(%)U+$,$-$.(/U 24 -1 1 1 1 UIParent 0.0 -182.0 -1 # 26 -1 1 4 4 UIParent 0.0 0.0 -1 #(]=]

function Presets:Build(page)
    if self.page then return end
    self.page = page
    local card = UI.Panel(page, C.field, C.lineSoft)
    card:SetPoint("TOPLEFT", 28, -86); card:SetPoint("TOPRIGHT", -28, -86)
    card:SetHeight(88)
    local heading = UI.Text(card, "GameFontNormalLarge", "Main", C.text)
    heading:SetPoint("TOPLEFT", 18, -16)
    local description = UI.Text(card, "GameFontHighlightSmall", L("Раскладка Blizzard"), C.muted)
    description:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    local copy = UI.Button(card, L("Показать код"), 170, 32)
    copy:SetPoint("RIGHT", -18, 0)

    local steps = UI.Text(page, "GameFontHighlightSmall",
        L("Сохраните текущую раскладку, затем импортируйте код в режиме редактирования Blizzard под новым именем — например, MythicBoost Main."), C.text)
    steps:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -20)
    steps:SetPoint("RIGHT", page, "RIGHT", -28, 0); steps:SetJustifyH("LEFT")
    local note = UI.Text(page, "GameFontHighlightSmall",
        L("Для возврата выберите прежнюю раскладку. Назначения клавиш и настройки других аддонов не переносятся."), C.muted)
    note:SetPoint("TOPLEFT", steps, "BOTTOMLEFT", 0, -12)
    note:SetPoint("RIGHT", page, "RIGHT", -28, 0); note:SetJustifyH("LEFT")
    local box = UI.Panel(page, C.field, C.lineSoft)
    box:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -24)
    box:SetPoint("RIGHT", page, "RIGHT", -28, 0); box:SetHeight(36)
    local field = CreateFrame("EditBox", nil, box)
    field:SetPoint("TOPLEFT", 8, -4); field:SetPoint("BOTTOMRIGHT", -8, 4)
    field:SetFontObject("GameFontHighlightSmall"); field:SetAutoFocus(false)
    field:SetText(self.Main); field:SetCursorPosition(0)
    field:SetScript("OnTextChanged", function(owner, userInput)
        if userInput then owner:SetText(Presets.Main); owner:SetCursorPosition(0); owner:HighlightText() end
    end)
    field:SetScript("OnEditFocusGained", function(owner) owner:HighlightText() end)
    field:SetScript("OnEscapePressed", function(owner) owner:ClearFocus() end)
    field:SetScript("OnEnterPressed", function(owner) owner:ClearFocus() end)
    field:SetScript("OnHide", function(owner) owner:ClearFocus() end)
    local hint = UI.Text(page, "GameFontHighlightSmall", L("Ctrl+C — скопировать код"), C.accent)
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    box:Hide(); hint:Hide()
    copy:SetScript("OnClick", function()
        box:Show(); hint:Show()
        field:SetFocus(); field:SetCursorPosition(0); field:HighlightText()
    end)
    self.field, self.copyButton, self.codeBox = field, copy, box
    local function Resize()
        page:SetHeight(math.max(480, 320 + steps:GetStringHeight() + note:GetStringHeight()))
    end
    page:HookScript("OnSizeChanged", Resize)
end
JP.LayoutPresets = Presets
