"""Queue icon must be corrected synchronously, without polling or hook recursion."""
from pathlib import Path
from lupa import LuaRuntime
from TestHudPolish import WIDGETS

root = Path(__file__).resolve().parents[1]
source = (root / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
body = source.split("function MinimalUI:PinQueueStatus(button)", 1)[1].split(
    "local function StyleMinimapZoneLabel", 1)[0]
lua = LuaRuntime()
lua.execute(r'''
MinimalUI={queueStatusPinned=true}; Minimap={}; MicroMenu={}; hooks=0; moves=0; combat=false
function InCombatLockdown() return combat end
button={point={'BOTTOMLEFT',MicroMenu,'BOTTOMRIGHT',15,0}}
function button:GetPoint() return table.unpack(self.point) end
function button:IsProtected() return self.protected==true end
function button:ClearAllPoints() self.point={} end
function button:SetPoint(...) moves=moves+1; self.point={...} end
function button:UpdatePosition() self:SetPoint('BOTTOMLEFT',MicroMenu,'BOTTOMRIGHT',15,0) end
function hooksecurefunc(object,method,callback)
 hooks=hooks+1; local original=object[method]
 object[method]=function(...) original(...); callback(...) end
end
''')
lua.execute("function MinimalUI:PinQueueStatus(button)" + body)
lua.execute(r'''
MinimalUI:PinQueueStatus(button)
assert(hooks==1 and moves==1 and button.point[2]==Minimap)
for i=1,10000 do MinimalUI:PinQueueStatus(button) end
assert(hooks==1 and moves==1)
for i=1,100 do button:UpdatePosition(); assert(button.point[2]==Minimap) end
assert(hooks==1 and moves==201)
combat=true; button:UpdatePosition(); assert(button.point[2]==Minimap)
button.protected=true; button:UpdatePosition(); assert(button.point[2]==MicroMenu)
combat=false; MinimalUI:PinQueueStatus(button); assert(button.point[2]==Minimap)
EditModeManagerFrame={IsShown=function() return true end}
button:UpdatePosition(); assert(button.point[2]==MicroMenu)
EditModeManagerFrame=nil; MinimalUI:PinQueueStatus(button)
MinimalUI.queueStatusPinned=false; button:UpdatePosition(); assert(button.point[2]==MicroMenu)
assert(hooks==1)
''')
assert "C_Timer" not in body and 'hooksecurefunc(button, "SetPoint"' not in body
print("Minimap queue: immediate placement, one hook, no recursion, combat guard and Edit Mode passed")

mail = LuaRuntime()
mail.execute(WIDGETS)
mail.execute(r'''
local methods=getmetatable(UIParent).__index
function methods:CreateFontString() return NewWidget(self) end
function methods:SetParent(p) assert(not combat); self.parent=p end
function methods:GetStringWidth() return zoneWidth end
function methods:GetTextColor() return 1,1,1,1 end
function methods:GetJustifyH() return 'LEFT' end
function methods:SetMaxLines() end
UI.UsableNumber=function(n) return type(n)=='number' and not issecretvalue(n) end
Minimap=NewWidget(UIParent); Minimap:SetWidth(264)
MinimapZoneTextButton=NewWidget(UIParent); MinimapZoneTextButton.Text=NewWidget(MinimapZoneTextButton)
MinimapCluster={IndicatorFrame=NewWidget(UIParent)}
MinimalUI={PinQueueStatus=function() end}; zoneWidth=92
''')
zone = source.split('local function StyleMinimapZoneLabel', 1)[1].split('local function HideLooseMinimapAddonButtons', 1)[0]
mail.execute('local function StyleMinimapZoneLabel' + zone + '\nApplyZone=StyleMinimapZoneLabel')
mail.execute(r'''
ApplyZone(MinimalUI,true)
local indicator=MinimapCluster.IndicatorFrame
assert(indicator.parent==Minimap and indicator.points[1][4]==106)
zoneWidth=140; ApplyZone(MinimalUI,true); assert(indicator.points[1][4]==154)
zoneWidth=700; ApplyZone(MinimalUI,true); assert(indicator.points[1][4]==196)
local built=allocations
for i=1,1000 do ApplyZone(MinimalUI,true) end
assert(allocations==built, 'zone/mail events must reuse native widgets')
combat=true; zoneWidth=50; ApplyZone(MinimalUI,true); assert(indicator.points[1][4]==196)
combat=false; ApplyZone(MinimalUI,true); assert(indicator.points[1][4]==64)
ApplyZone(MinimalUI,false); assert(indicator.parent==UIParent)
''')
print('Minimap mail: follows zone width, clamps long names, reuses widgets, defers combat, restores parent')
