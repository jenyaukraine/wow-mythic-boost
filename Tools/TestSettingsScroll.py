"""Exercise the shared settings viewport without a running WoW client."""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
source = (root / 'MythicBoost/Modules/SettingsHub.lua').read_text(encoding='utf-8')
factory = source.split('    local function MakePage(', 1)[1].split('\n    self.categoryTabs', 1)[0]
lua = LuaRuntime()
lua.execute('''
frames={}; self={categoryPages={}}; C={}; content={}; interfaceKeys={frames=true,auras=true,interface=true,loot=true,aurafilters=true}
function CreateFrame(kind, name, parent, template)
 local f={kind=kind,parent=parent,template=template,scripts={},width=700,height=400,offset=0}
 setmetatable(f,{__index=function() return function() end end})
 function f:SetSize(w,h) self.width=w; self.height=h end
 function f:SetWidth(w) self.width=w end
 function f:GetWidth() return self.width end
 function f:SetScrollChild(child) self.child=child end
 function f:SetScript(k,v) self.scripts[k]=v end
 function f:HookScript(k,v) self.scripts[k]=v end
 function f:GetVerticalScrollRange() return math.max(0,self.child.height-self.height) end
 function f:GetVerticalScroll() return self.offset end
 function f:SetVerticalScroll(v) self.offset=v end
 frames[#frames+1]=f; return f
end
UI={Text=function() return CreateFrame('Text') end}
''')
lua.execute('local function MakePage(' + factory + '\nmakePage=MakePage')
lua.execute('''
local page=makePage('frames','Title','Description')
local viewport=self.categoryPages.frames
local scroll=page.parent
assert(scroll.kind=='ScrollFrame' and scroll.template=='UIPanelScrollFrameTemplate')
assert(scroll.parent==viewport and scroll.child==page)
viewport.scripts.OnShow(); assert(page.width==700)
scroll.scripts.OnSizeChanged(scroll,650); assert(page.width==650)
scroll.scripts.OnMouseWheel(scroll,-1); assert(scroll.offset==36)
scroll.scripts.OnMouseWheel(scroll,-100); assert(scroll.offset==200)
assert(page.height-scroll.offset==scroll.height, 'bottom controls must be reachable')
scroll.scripts.OnMouseWheel(scroll,100); assert(scroll.offset==0)
scroll.height=900; scroll.scripts.OnMouseWheel(scroll,-1); assert(scroll.offset==0)
local before=#frames
for i=1,1000 do viewport.scripts.OnShow() end
assert(#frames==before, 'reopening must not allocate frames')
local interrupt=makePage('interrupts','Title','Description')
assert(interrupt==self.categoryPages.interrupts, 'do not nest interrupt scroll views')
''')
print('Settings scroll: clipping hierarchy, resize, wheel bounds, bottom reachability and reuse passed')

# Execute the actual HUD option list and placement expression. Adding another
# checkbox must move the next section instead of colliding with its heading.
import re
hud = source.split('    local hudOptions = {', 1)[1].split('    -------', 1)[0]
lua.execute('''
checks={}; db={}; interfacePage={}
function L(s) return s end
JP={Settings=function(k,defaults)
 db[k]=db[k] or {}; for key,v in pairs(defaults) do if db[k][key]==nil then db[k][key]=v end end
 return db[k]
end}
function self:AddStoredCheck(parent,settings,key,label,x,y)
 checks[#checks+1]={y=y,enabled=settings[key]}
end
''')
lua.execute('local hudOptions = {' + hud + '''
assert(db.templeHealer.enabled==true)
assert(db.avoidableDamage.enabled==true)
assert(-checks[#checks].y+22<=520)
''')
assert 'MakePage("screenshots"' not in source
assert 'self.checks.interfaceUnlocked = interfaceMove' not in source
assert '"unitFramesUnlocked")' not in source
assert '"frameBadgesUnlocked", 24)' not in source
assert 'JP.LayoutPresets:Build(profilesPage)' in source
assert 'JP.AuraFilters:Build(auraFiltersPage)' in source
# 1000px minimum window still has room for the two 300px settings columns.
for window in (1000, 1200, 2400):
    canvas = window - 24 - 28 - 174 - 10 - 26
    assert canvas - 56 >= 620
    assert (canvas+26-24-24)/5 >= 110

group_last = int(re.search(r'"autoHi"[^\n]+, 28, (-\d+)', source).group(1))
group_heading = int(re.search(r'Heading\(groupPage, L\("УМНЫЙ КЛИК"\), 28, (-\d+)', source).group(1))
assert group_last - 22 - group_heading >= 24
print('Settings layout: no HUD/group heading overlap; Avatar enabled by default')
