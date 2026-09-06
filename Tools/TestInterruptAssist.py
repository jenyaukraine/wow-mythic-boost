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
secret=setmetatable({}, {__eq=function() error('restricted comparison') end})
function issecretvalue(value) return rawequal(value,secret) end
function UnitCastingInfo() if casting then return secret,nil,nil,nil,nil,nil,nil,secret end end
function UnitChannelInfo() end
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
 function f:SetAlphaFromBoolean(v,a,b) self.alphaArg=v end
 function f:SetAttribute(k,v) self.attrs[k]=v end
 function f:RegisterForClicks(...) self.clicks={...} end
 function f:GetName() return self.name end
 function f:CreateFontString() return MakeFrame() end
 return f
end
function CreateFrame(_,name) frames=frames+1; return MakeFrame(name) end
UIParent=MakeFrame(); GameFontNormal={GetFont=function() return 'font' end}; unpack=table.unpack
JP={L=function(x) return x end, UI={}, RegisterModule=function() end,
 Settings=function(_,defaults) for k,v in pairs(defaults) do if db[k]==nil then db[k]=v end end return db end}
''')
loader = lua.eval("function(code) assert(load(code))('MythicBoost',JP) end")
loader((root / 'MythicBoost/Modules/InterruptAssist.lua').read_text(encoding='utf-8'))
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
known=0; assert(A:ActionBody(false)==nil); known=57994
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
assert(frames==3, 'frame leak on re-enable')
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
function GetBindingKey(action) for key,value in pairs(bound) do if value==action then return key end end end
function SetBindingClick(k,name,mouse) assert(not combat); bound[k]='CLICK '..name..':'..mouse; return true end
function SetBinding(k) assert(not combat); bound[k]=nil; return true end
function GetCurrentBindingSet() return 2 end
function SaveBindings() end
''')
loader((root / 'MythicBoost/Modules/InterruptAssistUI.lua').read_text(encoding='utf-8'))
lua.execute('A:Build(MakeFrame())')
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
