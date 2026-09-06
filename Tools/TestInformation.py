"""Information pane: fixed, copyable project link and safe read-only input."""

from TestDungeonHUD import runtime, load, source


PROJECT_URL = "https://www.curseforge.com/wow/addons/mythicboost"


def fixture():
    lua = runtime()
    lua.execute(r'''
        UI.Unpack=table.unpack
        UI.colors.accent={.2,.8,1,1}; UI.colors.text={.9,.9,.9,1}
        UI.colors.muted={.4,.4,.4,1}; UI.colors.field={.02,.03,.04,1}
        UI.colors.line={.2,.2,.2,1}
        function UI.Text(parent,_,value,color)
            local f=NewWidget(parent); f:SetText(value or ''); f.color=color; return f
        end
        function UI.Panel(parent,border,edge)
            local f=NewWidget(parent); return f
        end
        function UI.Button(parent,text,w,h)
            local f=NewWidget(parent); f.text=text; f:SetSize(w,h); return f
        end
        local methods=getmetatable(UIParent).__index
        function methods:SetFocus() self.focused=true end
        function methods:HighlightText() self.highlighted=true end
        function methods:SetTextInsets() end
        function methods:SetFontObject() end
        function methods:SetAutoFocus() end
        function methods:GetText() return self.text end
        JP.GetVersion=function() return '9.9.9' end
        page=NewWidget(UIParent)
    ''')
    load(lua, 'Modules/Information.lua')
    return lua


def test_information_reuses_pane_and_protects_link():
    lua = fixture()
    lua.execute(r'''
        JP.Information:Build(page)
        assert(JP.Information.urlField.text=='https://www.curseforge.com/wow/addons/mythicboost')
        assert(JP.Information.versionLabel.text=='Версия аддона: 9.9.9')
        local created=allocations
        for i=1,1000 do JP.Information:Build(page) end
        assert(allocations==created, 'information pane must be built once and reused')
        JP.Information.selectButton.scripts.OnClick(JP.Information.selectButton)
        assert(JP.Information.urlField.focused and JP.Information.urlField.highlighted)
        JP.Information.urlField:SetText('changed')
        JP.Information.urlField.scripts.OnTextChanged(JP.Information.urlField,true)
        assert(JP.Information.urlField.text=='https://www.curseforge.com/wow/addons/mythicboost')
    ''')


def test_information_copy_and_support_contract_are_static():
    info = source('Modules/Information.lua')
    settings = source('Modules/SettingsHub.lua')
    assert PROJECT_URL in info
    assert 'SetHyperlink' not in info and 'OpenExternal' not in info
    assert 'informationPage' in settings and '"information"' in settings
    assert 'information", L("Информация")' in settings
    assert 'L("Лаборатория талантов")' in settings


if __name__ == "__main__":
    for test in (test_information_reuses_pane_and_protects_link,
                 test_information_copy_and_support_contract_are_static):
        test()
        print(test.__name__ + ": OK")
