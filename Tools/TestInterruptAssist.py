"""Exercise interrupt alerts, secure actions, direct bindings and bounded state."""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
db={}; combat=false; known=57994; focusExists=true; casting=true; ready=true
members={player='Me',party1='Friend'}; frames=0; now=10; sends=0
function UnitClass() return 'Shaman','SHAMAN' end
function IsPlayerSpell(id) return id==known end
function IsSpellKnown() return false end
function InCombatLockdown() return combat end
function UnitExists() return focusExists end
function UnitCanAttack() return true end
function UnitIsDeadOrGhost() return false end
secret=setmetatable({}, {__eq=function() error('restricted comparison') end})
castLocked=secret; channeling=false
function issecretvalue(value) return rawequal(value,secret) end
function UnitCastingInfo() if casting then return secret,nil,nil,nil,nil,nil,nil,castLocked end end
function UnitChannelInfo() if channeling then return secret,nil,nil,nil,nil,nil,castLocked end end
C_Spell={GetSpellInfo=function(id) return {name='Wind Shear'} end,
 GetSpellCooldownDuration=function() return {IsZero=function() return ready end} end}
function GetTime() return now end
function UnitFullName(u) return members[u], 'Realm' end
function GetNormalizedRealmName() return 'Realm' end
function IsInGroup() return members.party1~=nil end
function IsInRaid() return false end
C_ChatInfo={RegisterAddonMessagePrefix=function() end,SendAddonMessage=function() sends=sends+1 end}
function SendChatMessage() end
function PlaySound() end
function MakeFrame(name)
 local f={scripts={},events={},attrs={},name=name}
 setmetatable(f,{__index=function(_,key) return function() end end})
 function f:RegisterEvent(e) self.events[e]=true end
 function f:RegisterUnitEvent(e) self.events[e]=true end
 function f:UnregisterAllEvents() self.events={} end
 function f:SetScript(k,v) self.scripts[k]=v end
 function f:Show() self.shown=true end
 function f:Hide() self.shown=false end
 function f:SetShown(value) self.shown=value end
 function f:SetEnabled(value) self.enabled=value end
 function f:SetAlpha(value) self.alpha=value end
 function f:SetText(value) self.value=value end
 function f:SetAlphaFromBoolean(v,a,b)
  self.alphaArg=v
  if rawequal(v,secret) then self.alpha=nil else self.alpha=v and a or b end
 end
 function f:SetAttribute(k,v) assert(not combat, 'protected attribute changed in combat'); self.attrs[k]=v end
 function f:RegisterForClicks(...) self.clicks={...} end
 function f:GetName() return self.name end
 function f:CreateFontString(_,_,template)
  local text=MakeFrame(); local initialized=template=='GameFontNormal'
  function text:SetFont(font) initialized=type(font)=='string' and font~='' end
  function text:SetText(value) assert(initialized,'FontString:SetText(): Font not set'); self.value=value end
  return text
 end
 return f
end
function CreateFrame(_,name) frames=frames+1; return MakeFrame(name) end
UIParent=MakeFrame(); GameFontNormal={GetFont=function() return 'font' end}; unpack=table.unpack
JP={L=function(x) return x end, UI={}, RegisterModule=function() end,
 Settings=function(_,defaults) for k,v in pairs(defaults) do if db[k]==nil then db[k]=v end end return db end}
''')
loader = lua.eval("function(code) assert(load(code))('MythicBoost',JP) end")
loader((root / 'MythicBoost/Modules/InterruptAssist.lua').read_text(encoding='utf-8'))
loader((root / 'MythicBoost/Modules/InterruptBindings.lua').read_text(encoding='utf-8'))
lua.execute(r'''
A=JP.InterruptAssist; A:Enable(); db.enabled=true; A:Update()
assert(A.frame.shown and A.frame.alphaArg==secret)
assert(A.frame.scripts.OnUpdate==nil)
db.text='ПРЕРВИ КАСТ'; assert(A:AlertText()=='ПРЕРВИ КАСТ' and db.text==nil)
db.text='INTERRUPT'; assert(A:AlertText()=='ПРЕРВИ КАСТ' and db.text==nil)
db.text='UNTERBRECHEN'; assert(A:AlertText()=='ПРЕРВИ КАСТ' and db.text==nil)
A:SetAlertText('My custom alert'); assert(A:AlertText()=='My custom alert')
A:SetAlertText(''); assert(A:AlertText()=='ПРЕРВИ КАСТ' and db.text==nil)
focusExists=false; A:Update(); assert(not A.frame.shown)
focusExists=true; casting=false; A:Update(); assert(not A.frame.shown)
casting=true; A:Update(); assert(A.frame.shown)
assert(A.actions[true].attrs.macrotext:find('/tm [@focus,harm,nodead] ~7',1,true))
assert(A.actions[false].attrs.macrotext:find('[@focus,harm,nodead][]',1,true))
-- Both phases must reach SecureActionButton, which selects exactly one via the CVar.
for _,button in pairs(A.actions) do
 assert(type(button.clicks)=='table', 'secure action has no registered click phases')
 for _,useOnKeyDown in ipairs({true,false}) do
  local actions=0
  for _,phase in ipairs(button.clicks) do
   if (phase=='AnyDown' and useOnKeyDown) or (phase=='AnyUp' and not useOnKeyDown) then
    actions=actions+1
   end
  end
  assert(actions==1, 'secure action must handle either key-down setting exactly once')
 end
end
db.marker=5; A:UpdateActions(); assert(A.actions[true].attrs.macrotext:find('~5',1,true))
local old=A.actions[true].attrs.macrotext; combat=true; db.marker=3; A:UpdateActions()
assert(A.actionsDirty and A.actions[true].attrs.macrotext==old)
combat=false; A.frame.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED'); assert(A.actions[true].attrs.macrotext:find('~3',1,true))
db.fallback='none'; assert(not A:ActionBody(false):find('[]',1,true))
db.fallback='nearby'; assert(A:ActionBody(false):find('/targetenemy',1,true))
known=0; assert(A:ActionBody(false)==nil)
assert(A:ActionBody('shared'):find('/focus',1,true) and not A:ActionBody('shared'):find('/cast',1,true))
known=57994
-- A learned Mighty Bash must produce a real focus action without a kick talent.
local oldClass, oldInfo, oldPlayer, oldKnown = UnitClass, C_Spell.GetSpellInfo, IsPlayerSpell, IsSpellKnown
function UnitClass() return 'Druid','DRUID' end
C_Spell.GetSpellInfo=function(id) return {name=id==5211 and 'Mighty Bash' or 'Skull Bash'} end
known=5211; db.fallback='target'; A:UpdateActions(); A:Update()
assert(A.spell==5211 and A.spellKind=='stun')
assert(A.actions[false].attrs.macrotext=='#showtooltip Mighty Bash\n/stopcasting\n/cast [@focus,harm,nodead][] Mighty Bash')
assert(A:AlertText()=='ОГЛУШЕНИЕ ПО ФОКУСУ' and A.frame.text.value==A:AlertText())
assert(A:SpellStatus():find('Mighty Bash',1,true) and A:SpellStatus():find('иммунитет',1,true))
assert(A.frame.shown and rawequal(A.frame.alphaArg,secret), 'stun hints must pass the interrupt shield to native rendering')
A:SetAlertText(A:AlertText()); assert(db.text==nil, 'stun default must not become a custom caption')
A:SetAlertText('My stun'); assert(A:AlertText()=='My stun'); A:SetAlertText('')
ready=secret; A:Update(); assert(rawequal(A.frame.text.alphaArg,secret)); ready=true
-- Cast/channel shields suppress both stop types without inspecting secret
-- booleans in addon code, while cooldown rendering stays independent.
for _, id in ipairs({5211,106839}) do
 known=id; A:UpdateActions()
 local macro=A.actions[false].attrs.macrotext
 for _, channel in ipairs({false,true}) do
  casting=not channel; channeling=channel; ready=true; castLocked=true
  A:Update(); assert(A.frame.alpha==0 and A.frame.text.alpha==1, 'shielded cast/channel must hide the stop hint')
  castLocked=false; A.frame.scripts.OnEvent(nil,'UNIT_SPELLCAST_INTERRUPTIBLE','focus')
  assert(A.frame.alpha==1 and A.frame.text.alpha==1, 'unshielded ready hint must return')
  ready=false; A:Update(); assert(A.frame.alpha==1 and A.frame.text.alpha==0)
  castLocked=secret; ready=secret; A:Update()
  assert(rawequal(A.frame.alphaArg,secret) and rawequal(A.frame.text.alphaArg,secret))
  assert(A.actions[false].attrs.macrotext==macro, 'display filtering must not change protected actions')
 end
end
known=5211; A:UpdateActions(); casting=true; channeling=false; ready=true; castLocked=secret
local oldSound, stunSounds=PlaySound,0
PlaySound=function() stunSounds=stunSounds+1 end
A.frame.scripts.OnEvent(nil,'UNIT_SPELLCAST_START','focus')
A.frame.scripts.OnEvent(nil,'UNIT_SPELLCAST_CHANNEL_START','focus')
assert(stunSounds==0, 'unfiltered cast-start sound must not urge a stun on shielded casts')
PlaySound=oldSound
db.fallback='none'; assert(A:ActionBody(false):find('/cast [@focus,harm,nodead] Mighty Bash',1,true))
db.fallback='nearby'; assert(A:ActionBody(false):find('/targetenemy\n/cast Mighty Bash',1,true))
-- Modern spellbook API is authoritative and independent of action bars/forms.
IsPlayerSpell=function() error('deprecated player API used') end
IsSpellKnown=function() error('deprecated known API used') end
Enum={SpellBookSpellBank={Player=0,Pet=1}}
local learned={[5211]=true,[106839]=true}
C_SpellBook={IsSpellKnown=function(id,bank) return bank~=1 and learned[id] or false end}
A:UpdateActions(); assert(A.spell==106839 and A.spellKind=='interrupt')
assert(A:AlertText()=='ПРЕРВИ КАСТ')
learned[106839]=nil; learned[78675]=true; A:UpdateActions(); assert(A.spell==78675)
learned[78675]=nil; A:UpdateActions(); assert(A.spell==5211)
local oldMacro=A.actions[false].attrs.macrotext
combat=true; learned[5211]=nil; learned[106839]=true
A.frame.scripts.OnEvent(nil,'SPELLS_CHANGED'); A:CacheSpell()
assert(A.spell==5211 and A.actionsDirty and A.actions[false].attrs.macrotext==oldMacro)
combat=false; A.frame.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
assert(A.spell==106839 and A.actions[false].attrs.macrotext~=oldMacro)
learned={}; A.frame.scripts.OnEvent(nil,'SPELLS_CHANGED')
assert(A.spell==nil and A.spellKind==nil and A.actions[false].attrs.type==nil and not A.frame.shown)
assert(A.actions[true].attrs.type=='macro', 'focus binding remains usable without a stop spell')
learned[5211]=secret; A:UpdateActions(); assert(A.spell==nil)
function UnitClass() return 'Warlock','WARLOCK' end
C_SpellBook.IsSpellKnown=function(id,bank) return id==19647 and bank==1 end
A:UpdateActions(); assert(A.spell==19647, 'pet spell bank still works')
UnitClass, C_Spell.GetSpellInfo, IsPlayerSpell, IsSpellKnown = oldClass, oldInfo, oldPlayer, oldKnown
C_SpellBook=nil; Enum=nil; known=57994; db.fallback='target'; A:UpdateActions()
A:SyncMarks(); local before=sends
A:ReceiveMark('MBFocus1','Q:7','PARTY','Friend-Realm'); assert(sends==before+1)
A:ReceiveMark('MBFocus1','Q:7','PARTY','Friend-Realm'); assert(sends==before+1)
A:ReceiveMark('MBFocus1','S:99','PARTY','Friend-Realm'); assert(A.marks['Friend-Realm']==7)
A:ReceiveMark('MBFocus1','S:1','PARTY','Stranger-Realm'); assert(A.marks['Stranger-Realm']==nil)
members.party1=nil; A:SyncMarks(); assert(A.marks['Friend-Realm']==nil)
-- Clicking the portrait cycles through free marks, ignoring departed claims.
members.party1='Friend'; members.party2='Other'; db.marker=7
A.marks={['Friend-Realm']=6,['Other-Realm']=5,['Departed-Realm']=4}
A:CycleMarker(); assert(db.marker==4 and A.marks['Departed-Realm']==nil)
assert(A.actions[true].attrs.macrotext:find('~4',1,true))
-- The lexicographically first full name keeps a contested mark.
db.marker=7; A:ReceiveMark('MBFocus1','S:7','PARTY','Friend-Realm')
assert(db.marker==6 and A.marks['Me-Realm']==6)
members.player='Aaron'; db.marker=7; A:SyncMarks(); assert(db.marker==7)
members.player='Me'; members.party2=nil; A.marks={}; A:SetMarker(7)
local oldBody=A.actions[true].attrs.macrotext
combat=true; A:CycleMarker()
assert(db.marker==7 and A.pendingMarker==6 and A.actions[true].attrs.macrotext==oldBody)
A:CycleMarker(); assert(A.pendingMarker==5 and db.marker==7)
combat=false; A.frame.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
assert(db.marker==5 and A.pendingMarker==nil and A.marks['Me-Realm']==5)
assert(A.actions[true].attrs.macrotext:find('~5',1,true))
-- Network conflict is deferred too; never move protected attributes in combat.
A:SetMarker(7); oldBody=A.actions[true].attrs.macrotext; combat=true
A:ReceiveMark('MBFocus1','S:7','PARTY','Friend-Realm')
assert(db.marker==7 and A.markConflictDirty and A.actions[true].attrs.macrotext==oldBody)
combat=false; A.frame.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
assert(db.marker==6 and A.marks['Me-Realm']==6)
local sent=sends
for i=1,10000 do A:ReceiveMark('MBFocus1','S:7','PARTY','Friend-Realm') end
assert(sends==sent, 'stable claims must never cause reply loops')
A:ReceiveMark('MBFocus1','S:2','PARTY',secret); A:SetMarker(secret)
assert(db.marker==6 and sends==sent)
members.party1=nil; A:SyncMarks()
for i=1,1000 do A:Disable(); A:Enable() end
assert(frames==4, 'frame leak on re-enable')
A:Disable(); assert(next(A.frame.events)==nil and A.marks==nil and not A.frame.shown)
A:Enable(); collectgarbage('collect'); local baseline=collectgarbage('count')
for i=1,10000 do A:Update() end
collectgarbage('collect'); assert(collectgarbage('count')-baseline<16, 'retained update allocations')
''')
lua.execute(r'''
created={}; buttons={}; bound={}
function CreateFrame(_,name,parent)
 local f=MakeFrame(name); created[#created+1]=f; return f
end
function MakeText(text)
 local f=MakeFrame(); f.value=text
 function f:SetText(t) self.value=t end
 function f:GetText() return self.value end
 return f
end
JP.UI.colors={text={},accent={}}
JP.UI.Text=function(_,_,text) return MakeText(text) end
JP.UI.Button=function(_,label)
 local f=MakeFrame(); f.label=MakeText(label); buttons[label]=f; return f
end
JP.UI.CheckBox=function() return MakeFrame() end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetBindingAction(key) return key=='X' and 'JUMP' or bound[key] or '' end
function GetBindingKey(action)
 local keys={}; for key,value in pairs(bound) do if value==action then keys[#keys+1]=key end end
 table.sort(keys); return table.unpack(keys)
end
function SetBindingClick(k,name,mouse) assert(not combat); bound[k]='CLICK '..name..':'..mouse; return true end
function SetBinding(k,action)
 assert(not combat)
 if failBinding==k then failBinding=nil; return false end
 bound[k]=action; return true
end
function GetCurrentBindingSet() return 2 end
savedBindings=0; function SaveBindings() savedBindings=savedBindings+1 end
''')
loader((root / 'MythicBoost/Modules/InterruptAssistUI.lua').read_text(encoding='utf-8'))
lua.execute('A:Build(MakeFrame())')
lua.execute("known=0; A.frame.scripts.OnEvent(nil,'SPELLS_CHANGED'); assert(A.status.value=='Прерывание или оглушение не изучено для текущей специализации')")
lua.execute("known=57994; A.frame.scripts.OnEvent(nil,'SPELLS_CHANGED'); assert(A.status.value=='Wind Shear')")
lua.execute('capture=created[3]')  # scroll, scroll child, keyboard capture
lua.execute("assert(buttons['1. Подсказка'].enabled==false)")
lua.execute("assert(buttons['Предпросмотр и перемещение'].shown and not buttons['Назначить клавишу фокуса: Нет'].shown)")
lua.execute("buttons['2. Горячие клавиши'].scripts.OnClick(); assert(buttons['Назначить клавишу фокуса: Нет'].shown and not buttons['Предпросмотр и перемещение'].shown)")
lua.execute("local count=#created; for i=1,1000 do buttons['3. Метки группы'].scripts.OnClick(); buttons['2. Горячие клавиши'].scripts.OnClick() end; assert(#created==count, 'section switching must reuse widgets')")
lua.execute("buttons['Назначить клавишу фокуса: Нет'].scripts.OnClick(); assert(capture.button==A.actions[true])")
lua.execute("capture.scripts.OnKeyDown(capture,'X'); assert(bound.X==nil)")
lua.execute("buttons['Назначить клавишу фокуса: Нет'].scripts.OnClick(); capture.scripts.OnKeyDown(capture,'F'); assert(bound.F=='CLICK MythicBoostFocusAction:LeftButton')")
lua.execute("buttons['Назначить клавишу фокуса: Нет'].scripts.OnClick(); capture.scripts.OnKeyDown(capture,'G'); assert(bound.F==nil and bound.G=='CLICK MythicBoostFocusAction:LeftButton')")
lua.execute("combat=true; capture.scripts.OnKeyDown(capture,'H'); assert(bound.H==nil); combat=false")
lua.execute("db.interruptKey='OEM1'; bound[';']='CLICK MythicBoostInterruptAction:LeftButton'; capture.scripts.OnEvent(capture,'UPDATE_BINDINGS'); assert(buttons['Назначить клавишу прерывания: Нет'].label.value=='Назначить клавишу прерывания: ;')")
lua.execute("bound[';']=nil; capture.scripts.OnEvent(capture,'UPDATE_BINDINGS'); assert(buttons['Назначить клавишу прерывания: Нет'].label.value=='Назначить клавишу прерывания: Нет')")
lua.execute(r'''
local focusCommand='CLICK MythicBoostFocusAction:LeftButton'
local kickCommand='CLICK MythicBoostInterruptAction:LeftButton'
local sharedCommand='CLICK MythicBoostFocusInterruptAction:LeftButton'
bound={}; assert(A:BindAction(false,'R')); assert(A:BindAction(true,'ALT-R'))
buttons['Назначить клавишу фокуса: Нет'].scripts.OnClick(); capture.scripts.OnKeyDown(capture,'R')
assert(bound.R==sharedCommand and bound['ALT-R']==nil)
assert(A:BindingKey(true)=='R' and A:BindingKey(false)=='R' and db.focusKey=='R' and db.interruptKey=='R')
assert(buttons['Назначить клавишу фокуса: Нет'].label.value=='Назначить клавишу фокуса: R')
assert(buttons['Назначить клавишу прерывания: Нет'].label.value=='Назначить клавишу прерывания: R')
assert(A.actions.shared.attrs.type=='macro' and A.actions.shared.attrs.macrotext:find('/focus [@mouseover,harm,nodead]',1,true))
assert(not A.actions.shared.attrs.macrotext:find('clearfocus',1,true), 'Alt may be part of the shared key')
assert(A:BindAction(true,'F')); assert(bound.R==kickCommand and bound.F==focusCommand)
assert(A:BindAction(false,'F')); assert(bound.R==nil and bound.F==sharedCommand)
assert(A:BindAction(false,'R')); assert(bound.R==kickCommand and bound.F==focusCommand)
assert(A:BindAction(true,'R')); assert(bound.R==sharedCommand and bound.F==nil)
local saves=savedBindings
failBinding='R'; assert(not A:BindAction(true,'F'))
assert(bound.F==nil and bound.R==sharedCommand and savedBindings==saves, 'failed split must restore bindings')
assert(not A:BindAction('control','R')); assert(bound.R==sharedCommand)
assert(not A:BindAction(true,'X')); assert(GetBindingAction('X')=='JUMP')
combat=true; assert(not A:BindAction(true,'F')); combat=false
assert(savedBindings==saves and bound.R==sharedCommand and bound.F==nil)
-- External edits remain authoritative, including secondary bindings.
bound.R='ACTIONBUTTON1'; assert(A:BindingKey(true)==nil and A:BindingKey(false)==nil)
assert(A:BindAction(true,'F')); assert(bound.R=='ACTIONBUTTON1')
bound.Q=focusCommand; bound.T=kickCommand
assert(A:BindAction(false,'F')); assert(bound.F==sharedCommand and bound.Q==nil and bound.T==nil)
assert(bound.R=='ACTIONBUTTON1')
bound={}; assert(A:BindAction(true,'ALT-R')); assert(A:BindAction(false,'ALT-R'))
assert(bound['ALT-R']==sharedCommand)
-- Bindings reload from Blizzard; stale addon settings never rebind anything.
db.focusKey='STALE'; db.interruptKey='STALE'
A:Disable(); A:Enable(); assert(A:BindingKey(true)=='ALT-R' and A:BindingKey(false)=='ALT-R')
collectgarbage('collect'); local bindingMemory=collectgarbage('count')
for i=1,1000 do assert(A:BindAction(true,'F')); assert(A:BindAction(true,'ALT-R')) end
collectgarbage('collect'); assert(collectgarbage('count')-bindingMemory<24)
bound={}; db.fallback='target'
''')
# Interpret the documented subset of native conditionals in the generated action.
# This checks the actual macro's ordering and target choice, without pretending
# to execute protected Blizzard actions in the offline test environment.
import re
macro = lua.eval("A:ActionBody('shared')")
enemy = {'harm': True, 'dead': False}
friend = {'harm': False, 'dead': False}
corpse = {'harm': True, 'dead': True}


def simulate_shared(mouseover, focus, target, raid=False):
    units = {'mouseover': mouseover, 'focus': focus, 'target': target}
    casts, marks = [], []
    for line in macro.splitlines():
        if not line or line.startswith('#') or line == '/stopcasting':
            continue
        command, options = line.split(' ', 1)
        matched = False
        for group in re.findall(r'\[([^]]*)\]', options):
            tokens = group.split(',') if group else []
            unit = next((t[1:] for t in tokens if t.startswith('@')), 'target')
            value = units.get(unit)
            if 'harm' in tokens and (value is None or not value['harm']):
                continue
            if 'nodead' in tokens and (value is None or value['dead']):
                continue
            if 'nogroup:raid' in tokens and raid:
                continue
            matched = True
            break
        if not matched:
            continue
        if command == '/focus':
            units['focus'] = value
        elif command == '/cast':
            casts.append(value)
        elif command == '/tm':
            marks.append(value)
        else:
            raise AssertionError(f'unexpected macro command {command}')
    return units['focus'], casts, marks


old_focus, hovered, target = dict(enemy), dict(enemy), dict(enemy)
new_focus, casts, marks = simulate_shared(hovered, old_focus, target)
assert new_focus is hovered and casts[0] is hovered and len(casts) == 1
for ignored in (None, friend, corpse):
    new_focus, casts, _ = simulate_shared(ignored, old_focus, target)
    assert new_focus is old_focus and casts[0] is old_focus and len(casts) == 1
assert simulate_shared(None, None, target)[1][0] is target
assert len(simulate_shared(hovered, old_focus, target, raid=True)[1]) == 1
assert not simulate_shared(hovered, old_focus, target, raid=True)[2]

lua.execute(r'''
local oldExists, oldAttack, oldDead, oldCast, oldSound = UnitExists, UnitCanAttack, UnitIsDeadOrGhost, UnitCastingInfo, PlaySound
bound={R='CLICK MythicBoostFocusInterruptAction:LeftButton'}
local units={mouseover={harm=true,casting=false},focus={harm=true,casting=true},target={harm=true,casting=true}}
function UnitExists(unit) return units[unit]~=nil end
function UnitCanAttack(_,unit) return units[unit] and units[unit].harm or false end
function UnitIsDeadOrGhost(unit) return units[unit] and units[unit].dead or false end
function UnitCastingInfo(unit) if units[unit] and units[unit].casting then return secret,nil,nil,nil,nil,nil,nil,secret end end
local sounds=0; function PlaySound() sounds=sounds+1 end
local body=A.actions.shared.attrs.macrotext
A:Update(); assert(A:HintUnit()=='mouseover' and not A.frame.shown, 'idle mouseover must not show casting focus alert')
assert(A.actions.shared.attrs.macrotext==body and A.actions.shared.attrs.type=='macro', 'cast events cannot gate protected actions')
A.frame.scripts.OnEvent(nil,'UNIT_SPELLCAST_START','focus'); assert(sounds==0)
units.mouseover.casting=true; A.frame.scripts.OnEvent(nil,'UNIT_SPELLCAST_START','mouseover')
assert(sounds==1 and A.frame.shown)
units.mouseover.dead=true; A:Update(); assert(A:HintUnit()=='focus' and A.frame.shown)
units.mouseover=nil; units.focus=nil; A:Update(); assert(A:HintUnit()=='target' and A.frame.shown)
db.fallback='none'; A:Update(); assert(A:HintUnit()==nil and not A.frame.shown)
db.fallback='nearby'; A:Update(); assert(A:HintUnit()==nil, 'unknown nearby caster is not inferred')
bound={}; units.focus={harm=true,casting=false}; db.fallback='target'
A:Update(); assert(not A.frame.shown)
UnitExists, UnitCanAttack, UnitIsDeadOrGhost, UnitCastingInfo, PlaySound = oldExists, oldAttack, oldDead, oldCast, oldSound
''')
lua.execute("members.player=nil; A:Roster(); A:SyncMarks()")
lua.execute("members.player='Me'; function UnitFullName(u) return members[u],nil end; function GetNormalizedRealmName() end; A:Roster(); A:SyncMarks()")
print('InterruptAssist: pre-login missing player/realm, runtime, secure actions, direct binding protection,')
print('UI callbacks, group validation, 1000 lifecycle cycles and 10000 stable-memory updates passed')

# Five independent clients hear each other asynchronously, including stale
# simultaneous claims. Exercise both delivery orders to detect marker ping-pong.
for reverse in (False, True):
    clients, queue = [], []
    for name in ('Aaron', 'Bran', 'Cora', 'Dara', 'Ezra'):
        client = LuaRuntime(unpack_returned_tuples=True)
        client.execute('''
            db={enabled=true,marker=7}; combat=false
            function InCombatLockdown() return combat end
            function IsInGroup() return true end
            function IsInRaid() return false end
            function GetTime() return 10 end
            function GetNormalizedRealmName() return 'Realm' end
            function UnitFullName(unit) return members[unit],'Realm' end
            C_ChatInfo={SendAddonMessage=function(prefix,message) Send(message) end}
            JP={L=function(s) return s end,UI={},RegisterModule=function() end,
                Settings=function() return db end}
        ''')
        other_names = [n for n in ('Aaron', 'Bran', 'Cora', 'Dara', 'Ezra') if n != name]
        members_table = client.table_from({'player': name, **{f'party{i+1}': n for i, n in enumerate(other_names)}})
        client.globals().members = members_table
        client.globals().Send = lambda message, sender=name: queue.append((sender, message))
        client.eval("function(s) assert(load(s))('MythicBoost',JP) end")(
            (root / 'MythicBoost/Modules/InterruptAssist.lua').read_text(encoding='utf-8'))
        clients.append((name, client))
    for _, client in clients:
        client.execute('JP.InterruptAssist:SyncMarks()')
    delivered = 0
    while queue:
        sender, message = queue.pop(-1 if reverse else 0)
        delivered += 1
        assert delivered < 50, 'marker conflict protocol failed to converge'
        for name, client in clients:
            if name != sender:
                client.globals().incoming = message
                client.globals().sender = sender + '-Realm'
                client.execute("JP.InterruptAssist:ReceiveMark('MBFocus1',incoming,'PARTY',sender)")
    assert len({client.globals().db.marker for _, client in clients}) == 5
    assert clients[0][1].globals().db.marker == 7
print('Marker conflicts: portrait cycling, combat deferral, no reply loop, five-client convergence passed')
print('Mighty Bash fallback: learned talent, focus/target macros, kick priority, modern/pet spellbook,')
print('secret cooldowns, combat deferral, unlearning and live status refresh passed')
print('Shared key: merge/split, rollback, external bindings, reload, modifier support,')
print('macro target order, mouseover alerts, no protected cast gating and bounded state passed')
print('Shielded stops: kick/stun cast and channel filtering, cooldowns, secret booleans,')
print('interruptibility transitions, stun sound suppression and unchanged protected macros passed')
