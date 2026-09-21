"""The one-time combat guide opens the actual keybinding controls."""
from TestDungeonHUD import runtime
from TestHudPolish import load

lua=runtime()
lua.execute(r'''
MythicBoostDB={}; opened={}; buttons={}
function UI.Panel(parent) return NewWidget(parent) end
function UI.Button(parent,label)
 local b=NewWidget(parent); b.label=NewWidget(b); b.label:SetText(label)
 buttons[label]=b; return b
end
JP.SettingsHub={SwitchCategory=function(key) opened.category=key end}
JP.InterruptAssist={SelectSettingsSection=function(index) opened.section=index end}
''')
load(lua,'Modules/Welcome.lua')
lua.execute(r'''
local w=JP.modules.Welcome
w.frame=NewWidget(UIParent)
function w:SwitchPage(key) opened.page=key end
combat=true; w:ShowCombatGuide(); assert(not w.combatGuide)
combat=false; w:ShowCombatGuide(); assert(w.combatGuide.shown)
local n=allocations
buttons['Настроить клавиши'].scripts.OnClick()
assert(opened.page=='settings' and opened.category=='bindings' and opened.section==2)
assert(MythicBoostDB.combatGuideSeen and not w.combatGuide.shown)
w:ShowCombatGuide(); assert(not w.combatGuide.shown and allocations==n)
w:ShowCombatGuide(true); assert(w.combatGuide.shown and allocations==n)
buttons['Понятно'].scripts.OnClick(); assert(not w.combatGuide.shown)
''')
print('Combat guide: first open, dismissal, reuse and keybinding navigation passed')
