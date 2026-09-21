"""Protected actions stay fixed in combat; secret HP only reaches decoration."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
combat=false; dead=false; allocations=0; class='SHAMAN'; hp=.25
known={[108271]=true,[8004]=true}; inventory={[5512]=1}; db={}
secret=setmetatable({}, {__lt=function() error('secret comparison') end,
 __le=function() error('secret comparison') end, __eq=function() error('secret comparison') end})
function issecretvalue(v) return rawequal(v,secret) end
function InCombatLockdown() return combat end
function UnitIsDeadOrGhost() return dead end
function UnitClass() return class,class end
function IsPlayerSpell(id) return known[id] or false end
function UnitHealthPercent(_,_,curve)
 if rawequal(hp,secret) then return secret end
 return hp < curve.points[2][1] and 1 or 0
end
Enum={LuaCurveType={Step=1}}
C_CurveUtil={CreateCurve=function()
 local c={points={}}; function c:SetType() end
 function c:AddPoint(x,y) self.points[#self.points+1]={x,y} end
 return c
end}
C_Spell={IsSpellPassive=function() return false end,GetSpellTexture=function(id) return id end,
 GetSpellName=function(id) return 'Spell'..id end, IsSpellUsable=function() return true end,
 GetSpellCooldownDuration=function(id) return {id=id,secret=secret} end}
C_Item={GetItemCount=function(id,bank,uses) assert(bank==false and uses==true); return inventory[id] or 0 end,
 IsUsableItem=function() return true end,GetItemIconByID=function(id) return id end,
 GetItemCooldown=function() return secret,secret,true end}
unpack=table.unpack
local methods={}
function CreateFrame(kind,name,parent,template)
 allocations=allocations+1
 return setmetatable({name=name,parent=parent,scripts={},events={},attrs={},alpha=1,
  protected=(parent and parent.protected) or (template and template:find('Secure')~=nil)},
  {__index=function(_,k)
   if k:sub(1,2)=='__' then return nil end
   if methods[k] then return methods[k] end
   if k:match('^[A-Z]') then return function() end end
  end})
end
local function Check(f) assert(not (combat and f.protected),'protected mutation in combat') end
function methods:SetAttribute(k,v) Check(self); self.attrs[k]=v end
function methods:SetSize(w,h) Check(self); self.width=w; self.height=h end
function methods:SetWidth(w) Check(self); self.width=w end
function methods:SetPoint() Check(self) end
function methods:EnableMouse(v) Check(self); self.mouse=v end
function methods:SetMouseClickEnabled(v) Check(self); self.mouse=v end
function methods:SetAlpha(v) self.alpha=v end
function methods:SetShown(v) Check(self); self.shown=v end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:RegisterEvent(k) self.events[k]=true end
function methods:RegisterUnitEvent(k,unit) assert(unit=='player'); self.events[k]=true end
function methods:UnregisterAllEvents() self.events={} end
function methods:GetFrameLevel() return 1 end
function methods:CreateTexture() return CreateFrame('Texture',nil,self) end
function methods:SetTexture(v) self.tex=v end
function methods:SetDesaturated(v) self.desaturated=v end
function methods:SetCooldownFromDurationObject(v) self.duration=v end
function methods:SetCooldown(a,b) self.start=a; self.duration=b end
function methods:Clear() self.duration=nil end
function methods:RegisterForClicks(...) self.clicks={...} end
function RegisterStateDriver(f,k,v) Check(f); f.driver=v end
function UnregisterStateDriver(f) Check(f); f.driver=nil end
UIParent=CreateFrame('Frame'); GameTooltip_Hide=function() end
JP={L=function(v) return v end,RegisterModule=function() end,
 Settings=function(key,defaults)
 db[key]=db[key] or {}; for k,v in pairs(defaults or {}) do if db[key][k]==nil then db[key][k]=v end end
 return db[key]
 end}
''')
loader=lua.eval("function(code) assert(load(code))('MythicBoost',JP) end")
for path in ['Contracts.lua','UI.lua','Modules/SurvivalPrompt.lua']:
    loader((ROOT/'MythicBoost'/path).read_text(encoding='utf-8'))
lua.execute(r'''
local p=JP.SurvivalPrompt
p:Enable(); local n=allocations
assert(p:Settings().enabled and #p.actions==3)
assert(p.buttons[1].attrs.spell==108271 and p.buttons[2].attrs.spell==8004)
assert(p.buttons[3].attrs.item=='item:5512' and p.buttons[1].attrs.unit=='player')
assert(p.buttons[1].width==64 and p.buttons[2].width==48)
assert(p.frame.driver=='[combat,nodead] show; hide')
assert(p.sequence.attrs.type=='macro' and p.sequence.attrs.macrotext=='/castsequence [@player] reset=60 Spell108271, item:5512')
for _,b in ipairs(p.buttons) do
 assert(b.alpha==1 and b.mouse and not b.glow.mouse and not b.cooldown.mouse)
 assert(#b.clicks==2 and b.attrs.useOnKeyDown==false and not b.scripts.OnClick)
end
for i=1,100 do p:Enable() end; assert(allocations==n)
combat=true; p:Update(); assert(p.buttons[1].glow.alpha==1)
hp=.30; p:Update(); assert(p.buttons[1].glow.alpha==0)
hp=secret; p:Update(); assert(rawequal(p.buttons[1].glow.alpha,secret))
assert(p.buttons[1].alpha==1 and p.buttons[1].attrs.spell==108271)
known={}; inventory={[271884]=5}; p.events.scripts.OnEvent(nil,'BAG_UPDATE_DELAYED')
assert(p.buttons[3].attrs.item=='item:5512' and p.buttons[3].texture.desaturated)
assert(p.sequence.attrs.macrotext=='/castsequence [@player] reset=60 Spell108271, item:5512')
assert(rawequal(p.buttons[3].cooldown.start,secret))
dead=true; p:Update(); assert(p.buttons[1].glow.alpha==0); dead=false
p:Disable(); assert(not p.events.events.UNIT_HEALTH and p.events.events.PLAYER_REGEN_ENABLED)
assert(p.buttons[1].attrs.spell==108271)
combat=false; p.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
assert(not p.frame.shown and not next(p.events.events) and not p.buttons[1].attrs.type)
assert(p.sequence.attrs.type==nil)
p:Enable(); assert(#p.actions==1 and p.buttons[1].attrs.item=='item:271884')
known={[108271]=true,[8004]=true}; inventory={[5512]=3,[241305]=81}
C_Item.IsUsableItem=function() return false end
p:Enable(); assert(#p.actions==4 and p.buttons[4].attrs.item=='item:241305')
assert(p.sequence.attrs.macrotext=='/castsequence [@player] reset=60 Spell108271, item:5512, item:241305')
inventory[224464]=1; p:Enable(); assert(p.actions[3].id==224464 and p.actions[4].id==241305)
inventory[224464]=0; inventory[5512]=0; p:Enable()
assert(#p.actions==3 and p.actions[3].id==241305)
assert(p.sequence.attrs.macrotext=='/castsequence [@player] reset=60 Spell108271, item:241305')
known={}
db.survivalPrompt.enabled=false; p:Enable(); assert(p.frame.driver=='hide' and not next(p.events.events) and p.sequence.attrs.type==nil)
db.survivalPrompt.threshold=999; assert(p:Settings().threshold==50)
db.survivalPrompt.threshold=-1; assert(p:Settings().threshold==10)
db.survivalPrompt.threshold='bad'; assert(p:Settings().threshold==30)
db.survivalPrompt.enabled=true; db.survivalPrompt.showPotions=false
p:Enable(); assert(#p.actions==0 and p.frame.driver=='hide')
for _,c in ipairs({'WARRIOR','PALADIN','DEATHKNIGHT','HUNTER','SHAMAN','DRUID',
 'MONK','ROGUE','PRIEST','MAGE','WARLOCK','DEMONHUNTER','EVOKER'}) do
 class=c; setmetatable(known,{__index=function() return true end})
 p:Enable(); assert(#p.actions==2 and p.actions[1].id~=p.actions[2].id)
end
p:Disable(); assert(not next(p.events.events))
''')
# Login/reload in combat must allocate no protected frames until combat ends.
loader((ROOT/'MythicBoost/Modules/SurvivalPrompt.lua').read_text(encoding='utf-8'))
lua.execute(r'''
combat=true; local p=JP.SurvivalPrompt; p:Enable()
assert(p.frame==nil and p.events.events.PLAYER_REGEN_ENABLED)
combat=false; p.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
assert(p.frame and p.events.events.UNIT_HEALTH)
''')
print('Survival prompt tests passed')
lua.execute(r'''
bindings={}; saved=0
function GetBindingKey(command)
 for key,value in pairs(bindings) do if value==command then return key end end
end
function GetBindingAction(key) return bindings[key] or '' end
function SetBinding(key,command) assert(not combat); bindings[key]=command; return true end
function GetCurrentBindingSet() return 2 end
function SaveBindings(set) assert(set==2); saved=saved+1 end
JP.InterruptAssist={Settings=function() return {} end,UpdateActions=function() end}
''')
loader((ROOT/'MythicBoost/Modules/InterruptBindings.lua').read_text(encoding='utf-8'))
lua.execute(r'''
local a=JP.InterruptAssist
for i=1,4 do
 assert(a:BindAction('survival'..i,'F'..i))
 assert(bindings['F'..i]=='CLICK MythicBoostSurvivalAction'..i..':LeftButton')
end
bindings.R='JUMP'; assert(not a:BindAction('survival1','R') and bindings.R=='JUMP')
assert(a:BindAction('survival1','F6') and bindings.F1==nil)
combat=true; assert(not a:BindAction('survival1','F5') and bindings.F5==nil)
assert(a:BindAction('survivalSequence','F7')==false)
combat=false; assert(a:BindAction('survivalSequence','F7'))
assert(bindings.F7=='CLICK MythicBoostSurvivalSequence:LeftButton' and saved==6)
''')
print('Survival keybindings: conflicts, reassignment, persistence and combat lock passed')
