"""Exercise settings search routes, Cyrillic matching and legacy category migration."""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
source = (root / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
lua = LuaRuntime()
lua.execute(r'''
JP = {UI={colors={panel={},line={},muted={}}}}
JP.L=function(s) return s end
function JP:RegisterModule(name, module) self[name]=module end
function widget(parent)
 local o={parent=parent,scripts={},shown=true,top=1000}
 function o:GetParent() return self.parent end
 function o:GetFrameLevel() return 1 end
 function o:SetFrameLevel(v) self.level=v end
 function o:SetPoint(...) end
 function o:SetWidth(v) self.width=v end
 function o:SetHeight(v) self.height=v end
 function o:SetJustifyH(v) self.justify=v end
 function o:SetShown(v) self.shown=v end
 function o:Show() self.shown=true end
 function o:Hide() self.shown=false end
 function o:IsShown() return self.shown end
 function o:HasFocus() return self.focused == true end
 function o:ClearFocus() self.focused=false end
 function o:GetTop() return self.top end
 function o:HookScript(k,v) self.scripts[k]=v end
 function o:SetScript(k,v) self.scripts[k]=v end
 return o
end
JP.UI.Panel=function(parent) return widget(parent) end
JP.UI.Text=function(parent) return widget(parent) end
JP.UI.Button=function(parent)
 local b=widget(parent); b.label=widget(b)
 function b.label:SetText(v) self.text=v end
 return b
end
JP.UI.SettingsButton=JP.UI.Button
JP.UI.SearchResult=function(parent)
 local b=JP.UI.Button(parent); b.category=JP.UI.Button(parent).label; return b
end
JP.UI.SettingsGlow=function(target,state) target.glow=state end
C_Timer={After=function(_,fn) fn() end}
''')
lua.execute(source, "MythicBoost", lua.globals().JP)
lua.execute(r'''
assert(JP.SettingsHub.SearchLower("СЕЙВ") == "сейв")
local pages={main=true,interface=true,bindings=true,auras=true}
assert(JP.SettingsHub.NormalizeCategory("interrupts",pages)=="bindings")
assert(JP.SettingsHub.NormalizeCategory("screenshots",pages)=="interface")
assert(JP.SettingsHub.NormalizeCategory("buffs",pages)=="auras")
assert(JP.SettingsHub.NormalizeCategory("removed-page",pages)=="main")

local parent, holder, field = widget(), widget(), widget()
field.text=""; field.focused=false
function field:GetText() return self.text end
local root=widget(); root.top=1000
local control=widget(root); control.top=700
local scroll=widget(); scroll.range=300
function scroll:GetVerticalScrollRange() return self.range end
function scroll:SetVerticalScroll(v) self.offset=v end
local hub=JP.SettingsHub
hub.pageRoots={bindings=root}; hub.scrollFrames={bindings=scroll}; hub.searchEntries={}
hub.searchEntries[1]={key="survival1",label="Сейв: Каменная кожа",terms={"Сейв: Каменная кожа","СЕЙВ","защита"},widget=control,pageKey="bindings"}
hub.SwitchCategory=function(key) hub.currentPageKey=key end
hub:BuildSearch(parent,holder,field)
field.scripts.OnTextChanged(field)
assert(not hub.searchResultPanel:IsShown(),'opening settings must not search the placeholder')
field.focused=true; field.scripts.OnEditFocusGained(field)
assert(not hub.searchResultPanel:IsShown(),'focusing an empty field must not show no-results')
field.text='   '; field.scripts.OnTextChanged(field)
assert(not hub.searchResultPanel:IsShown(),'whitespace is not a query')
field.text='СЕЙВ'
field.scripts.OnTextChanged(field)
local result=hub.searchResultButtons[1]
assert(result:IsShown() and result.searchEntry.label=="Сейв: Каменная кожа")
result.scripts.OnClick(result)
assert(hub.currentPageKey=="bindings" and scroll.offset==258)
assert(control.glow=="active")
field.focused=true; field.text="нет такого параметра"; field.scripts.OnTextChanged(field)
assert(hub.searchResultPanel:IsShown())
assert(hub.searchEmptyText:IsShown())
assert(hub.searchResultButtons[1]:IsShown()==false)
assert(control.glow==nil, tostring(control.glow))
field.scripts.OnEscapePressed(field)
assert(not hub.searchResultPanel:IsShown() and not field:HasFocus())
field.focused=true; field.scripts.OnTextChanged(field)
parent.scripts.OnHide(parent)
assert(not hub.searchResultPanel:IsShown() and not field:HasFocus(),'closing settings must close results')
''')

switch = source.split("    local function SwitchCategory(key)", 1)[1].split("    self.SwitchCategory", 1)[0]
assert 'tab:SetShown(topCategory == "interface")' in switch
assert 'tab:SetShown(topCategory == "buffs")' in switch
assert 'tab:SetShown(topCategory == "groups")' in switch
assert 'automation="groups"' in source

print("Settings search/navigation: uppercase Cyrillic, route visibility, scroll, no-results and legacy migration passed")
