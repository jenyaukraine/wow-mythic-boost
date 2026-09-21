"""Run the real category switcher to catch overlapping or unreachable pages."""
from pathlib import Path
from lupa import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'MythicBoost/Modules/SettingsHub.lua').read_text(encoding='utf-8')
mapping = source.split('    local pageTopCategory = {', 1)[1].split('\n    local subnav', 1)[0]
switch = source.split('    local function SwitchCategory(key)', 1)[1].split('\n    self.SwitchCategory', 1)[0]
lua = LuaRuntime()
lua.execute('''
function widget()
 return {SetShown=function(s,v) s.shown=v end,SetActive=function(s,v) s.active=v end,
 SetVerticalScroll=function(s,v) s.offset=v end}
end
self={categoryPages={},categoryTabs={},scrollFrames={},interfaceTabs={},buffTabs={},groupTabs={}}
MythicBoostDB={}; subnav=widget(); UI={SettingsGlow=function(s,v) s.glow=v end}
for _,k in ipairs({'main','automation','groups','bindings','interface','frames','auras','aurafilters','loot','profiles','information','system'}) do
 self.categoryPages[k]=widget(); self.scrollFrames[k]=widget()
end
for _,k in ipairs({'main','bindings','groups','interface','buffs','loot','profiles'}) do self.categoryTabs[k]=widget() end
for _,k in ipairs({'interface','frames'}) do self.interfaceTabs[k]=widget() end
for _,k in ipairs({'auras','aurafilters'}) do self.buffTabs[k]=widget() end
for _,k in ipairs({'groups','automation'}) do self.groupTabs[k]=widget() end
''')
lua.execute('local pageTopCategory = {' + mapping + '\nfunction SwitchCategory(key)' + switch)
lua.execute('''
for _,route in ipairs({'main','frames','automation','aurafilters','bindings','loot','profiles','system','information','interrupts','screenshots','buffs','unknown'}) do
 SwitchCategory(route)
 local shown=0
 for key,page in pairs(self.categoryPages) do
  if page.shown then shown=shown+1; assert(key==self.currentPageKey) end
 end
 assert(shown==1,'exactly one page must be visible')
 local visibleTabs=0
 for _,group in ipairs({self.interfaceTabs,self.buffTabs,self.groupTabs}) do
  for _,tab in pairs(group) do if tab.shown then visibleTabs=visibleTabs+1 end end
 end
 assert(visibleTabs==(subnav.shown and 2 or 0),'unrelated subnavigation must not overlap')
 assert(MythicBoostDB.settingsCategory==self.currentPageKey)
 assert(self.scrollFrames[self.currentPageKey].offset==0)
end
SwitchCategory('interrupts'); assert(self.currentPageKey=='bindings' and self.categoryTabs.bindings.active)
SwitchCategory('system')
for _,tab in pairs(self.categoryTabs) do assert(not tab.active,'help and diagnostics must not select an unrelated category') end
''')
print('PASS: category visibility, subnavigation isolation, legacy links, scroll reset and footer routes')
