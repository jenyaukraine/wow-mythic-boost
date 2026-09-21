"""Settings feedback reuses its visual layers and clears idle state."""
from pathlib import Path
from lupa import LuaRuntime
from TestHudPolish import WIDGETS

source = (Path(__file__).resolve().parents[1] / 'MythicBoost/UI.lua').read_text(encoding='utf-8')
body = source.split('function UI.SettingsGlow(', 1)[1].split('\nfunction UI.Tab(', 1)[0]
lua = LuaRuntime()
lua.execute(WIDGETS)
lua.execute('''
UI={}; C={accent={.16,.72,.96},edge={.95,.72,.18}}; WHITE='white'
glowLayers={}
local baseCreate=CreateFrame
function CreateFrame(...)
 local frame=baseCreate(...); glowLayers[#glowLayers+1]=frame
 return frame
end
local methods=getmetatable(NewWidget()).__index
function methods:SetBackdrop(v) self.backdrop=v end
function methods:SetBackdropColor(...) self.bg={...} end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:SetShown(v) self.shown=v end
''')
lua.execute('function UI.SettingsGlow(' + body)
lua.execute('''
local button=NewWidget()
UI.SettingsGlow(button,'hover')
local n=allocations
assert(#glowLayers>0)
local function intensity()
 local sum=0
 for _,layer in ipairs(glowLayers) do sum=sum+(layer.border and layer.border[4] or 0) end
 return sum
end
local hover=intensity()
UI.SettingsGlow(button,'active'); local active=intensity()
UI.SettingsGlow(button,'capture'); local capture=intensity()
assert(hover>0 and active>hover and capture>active,'states need distinct emphasis')
for i=1,1000 do
 UI.SettingsGlow(button,'active')
 UI.SettingsGlow(button,'capture')
 UI.SettingsGlow(button,'hover')
 UI.SettingsGlow(button,nil)
end
assert(allocations==n,'state changes must reuse glow layers')
for _,layer in ipairs(glowLayers) do
 assert(not layer.shown or (layer.border and layer.border[4]==0),'idle glow must disappear')
 assert(not layer.scripts.OnUpdate,'settings glow must not poll')
end
''')
print('PASS: settings glow reuse, idle cleanup and no polling')
