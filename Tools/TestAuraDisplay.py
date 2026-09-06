"""12.1 display contract: no aura reads, private-button access or growing pools.

This is an API-contract test, not a substitute for a restricted-combat client run.
"""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.execute(r'''
JP={}; combat=false; frames=0; groups=0; buttons=0; refreshes=0; records={}; durationTexts=0
STANDARD_TEXT_FONT='Fonts/FRIZQT__.TTF'
Enum={CustomAuraButtonDispelTypeTextureStyle={PreserveAsset=3}}
AnchorUtil={FlowDirection={Left=1,Right=2,Up=3,Down=4}}
function InCombatLockdown() return combat end
local function forbidden() error('legacy aura API must never be called') end
C_UnitAuras=setmetatable({}, {__index=function() return forbidden end})
C_Timer=setmetatable({}, {__index=function() error('no aura polling timers') end})
local regionMethods={}
for _,name in ipairs({'SetAllPoints','SetColorTexture','SetPoint','SetTexCoord','SetFont',
 'SetTextColor','SetTexture','SetHeight','SetDrawEdge','SetHideCountdownNumbers','SetSize',
 'SetFrameLevel','ClearAllPoints'}) do
 regionMethods[name]=function() end
end
regionMethods.SetPoint=function(self,...) self.point={...} end
regionMethods.GetFrameLevel=function() return 1 end
local function region()
 return setmetatable({}, {__index=function(_,key)
  assert(regionMethods[key], 'unexpected region API '..key); return regionMethods[key]
 end})
end
regionMethods.CreateFontString=region
local containerMethods={}
function containerMethods:SetScale(value) assert(not combat); records[self].scale=value end
function containerMethods:SetUnit(unit) records[self].unit=unit end
function containerMethods:SetFlowLayoutMaximumLineSize(width) records[self].width=width end
function containerMethods:SetFlowLayoutAnchorPoint(point) records[self].anchor=point end
function containerMethods:SetFlowLayoutGrowthDirection(x,y) records[self].growth={x,y} end
function containerMethods:ClearAllPoints() end
function containerMethods:SetPoint(...) assert(not combat); records[self].point={...} end
function containerMethods:SetEnabled(value) records[self].enabled=value end
function containerMethods:SetShown(value) records[self].shown=value end
function containerMethods:UpdateAllAuras() refreshes=refreshes+1 end
function containerMethods:AddAuraGroup(key,filter,options)
 assert(not combat); groups=groups+1
 assert(options.maxFrameCount==18 and options.layout.forceNewLine)
 assert(options.layout.lineSpacing==3 and options.layout.groupLineSpacing==3)
 local record=records[self]; record.groups[#record.groups+1]={key=key,filter=filter}
 for _=1,20 do -- Native allocation rounds up to batches of ten.
  buttons=buttons+1
  local sealed=false
  local methods={CreateTexture=region,CreateFontString=region,SetSize=function() end}
  for _,name in ipairs({'SetIcon','SetDurationCooldown','SetApplicationCount','SetDurationText',
   'AddDispelTypeTexture','SetTooltipAnchorPoint','SetCancelAuraButtons'}) do
   methods[name]=function() end
  end
  methods.SetDurationText=function(_,text)
   assert(text.point[1]=='TOPLEFT' and text.point[3]=='TOPLEFT' and text.point[5]==-1)
   durationTexts=durationTexts+1
  end
  local button=setmetatable({}, {
   __index=function(_,key)
    assert(not sealed,'private aura button accessed after initialization')
    assert(methods[key], 'unexpected button API '..key); return methods[key]
   end,
   __newindex=function() error('must not store aura data or callbacks on a private button') end})
  options.initializeFrame(button); sealed=true
 end
end
function CreateFrame(kind,name,parent,template)
 assert(not combat,'frame created in combat'); frames=frames+1
 if kind=='Cooldown' then assert(template=='CooldownFrameTemplate'); return region() end
 if kind=='Frame' then return region() end
 assert(kind=='AuraContainer' and template=='CustomAuraContainerTemplate')
 local frame=setmetatable({}, {__index=function(_,key)
  assert(containerMethods[key], 'unexpected container API '..key); return containerMethods[key]
 end})
 records[frame]={groups={}}; return frame
end
resourceVisible=false; resourceHeight=10
player={unit='player',holder={},resourceRow={IsShown=function() return resourceVisible end,
 GetHeight=function() return resourceHeight end}}
target={unit='target',mirror=true,holder={}}
settings={enabled=true,aurasAbove=true,resourceHeight=10,playerAurasBeside=true}
''')
load = lua.eval("function(code) assert(load(code))('MythicBoost',JP) end")
source = (root / "MythicBoost/Modules/AuraDisplay.lua").read_text(encoding="utf-8")
load(source)
lua.execute(r'''
unpack=table.unpack
JP.UI={colors={surfaceEdge={.78,.56,.12,.98},surface={.014,.020,.028,.94}}}
function CreateColor(...) return {...} end
tooltipStyles=0; tooltipResets=0
AuraContainerInbound={SetTooltipBackdrop=function(options)
 assert(options.backdropInfo.edgeSize==1 and options.anchorOffsets.left==0)
 assert(options.borderColor[1]==.78 and options.centerColor[4]==.94)
 tooltipStyles=tooltipStyles+1
end,ResetTooltipStyle=function() tooltipResets=tooltipResets+1 end}
JP.AuraDisplay:StyleTooltip(true); JP.AuraDisplay:StyleTooltip(true)
assert(tooltipStyles==1)
combat=true; JP.AuraDisplay:StyleTooltip(false); assert(tooltipResets==0)
combat=false; JP.AuraDisplay:StyleTooltip(false); assert(tooltipResets==1)
''')
lua.execute(r'''
local a=JP.AuraDisplay
combat=true; a:Configure(player,settings); assert(player.auraContainer==nil and frames==0)
combat=false; a:Configure(player,settings); a:Configure(target,settings)
assert(groups==4 and buttons==80 and frames==164 and durationTexts==80)
local p,t=records[player.auraContainer],records[target.auraContainer]
assert(p.unit=='player' and t.unit=='target')
assert(p.groups[1].filter=='HELPFUL' and p.groups[2].filter=='HARMFUL')
assert(t.groups[1].filter=='HELPFUL' and t.groups[2].filter=='HARMFUL')
assert(p.anchor=='TOPLEFT' and t.anchor=='BOTTOMRIGHT')
assert(p.growth[2]==AnchorUtil.FlowDirection.Down and t.growth[2]==AnchorUtil.FlowDirection.Up)
assert(p.enabled and t.enabled and p.width==97)
assert(player.auraAnchor.point[5]==0 and target.auraAnchor.point[5]==3)
assert(rawequal(p.point[2],player.auraAnchor) and p.point[5]==0)
local originalFrames=frames
collectgarbage('collect'); local baseline=collectgarbage('count')
combat=true
resourceVisible=true; a:Position(player,settings); assert(player.auraAnchor.point[5]==0)
resourceHeight=16; a:Position(player,settings); assert(player.auraAnchor.point[5]==0)
resourceVisible=false; a:Position(player,settings); assert(player.auraAnchor.point[5]==0)
for i=1,10000 do a:Configure(target,settings); a:Refresh(target) end
assert(frames==originalFrames and groups==4 and refreshes==10000)
collectgarbage('collect'); assert(collectgarbage('count')-baseline<16)
combat=false
for i=1,100 do a:Configure(player,settings); a:Configure(target,settings) end
assert(frames==originalFrames and groups==4)
settings.showTargetAuras=false; a:Configure(target,settings); assert(not t.enabled and not t.shown)
settings.showPlayerAuras=false; a:Configure(player,settings); assert(not p.enabled and not p.shown)
settings.showPlayerAuras=true; settings.showResourcePips=false; a:Configure(player,settings)
assert(p.enabled and player.auraAnchor.point[5]==0)
settings.aurasAbove=false; a:Configure(target,settings)
assert(t.anchor=='TOPRIGHT' and t.growth[2]==AnchorUtil.FlowDirection.Down)
''')
lua.execute(r'''
local a=JP.AuraDisplay
settings.playerAurasBeside=nil; settings.aurasAbove=true
settings.scale=1.5; settings.auraScale=1.2
a:Configure(player,settings)
local p=records[player.auraContainer]
assert(p.anchor=='BOTTOMLEFT' and p.growth[2]==AnchorUtil.FlowDirection.Up)
assert(p.width==222 and player.auraAnchor.point[3]=='TOPLEFT')
assert(math.abs(p.scale*settings.scale-1.2)<.00001)
settings.scale=2; a:Configure(player,settings)
assert(math.abs(p.scale*settings.scale-1.2)<.00001,'capsule scale must not resize auras')
settings.auraScale=.75; a:Configure(player,settings)
assert(math.abs(p.scale*settings.scale-.75)<.00001)
settings.playerAurasBeside=true; a:Configure(player,settings)
assert(player.auraAnchor.point[3]=='TOPRIGHT' and p.width==97)
settings.playerAurasBeside=false; a:Configure(player,settings)
assert(player.auraAnchor.point[3]=='TOPLEFT','return from side must invalidate position cache')
settings.aurasAbove=false; a:Configure(player,settings)
assert(player.auraAnchor.point[3]=='BOTTOMLEFT' and p.anchor=='TOPLEFT')
local originalFrames=frames
for i=1,1000 do
 settings.aurasAbove=i%2==0; settings.scale=i%2==0 and 1 or 2
 a:Configure(player,settings)
end
assert(frames==originalFrames,'changing size/side must reuse aura frames')
''')
frames_source = (root / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
assert '"UNIT_AURA"' not in frames_source
assert "GetAuraDataBy" not in frames_source and "SafeAura(" not in frames_source
assert "if showAuras and options.preview then" in frames_source
assert "JP.AuraDisplay:Refresh(self.displays.target)" in frames_source
assert "C_Timer" not in source and "OnUpdate" not in source
print("AuraDisplay: combat gate, both units, buff/debuff order, private-button isolation, bounded pools passed")
