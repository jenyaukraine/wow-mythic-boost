"""Regression coverage for restricted error strings and handler failures."""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.execute(r'''
local realType=type
secret=setmetatable({}, {
 __index=function() error('indexed restricted string') end,
 __tostring=function() error('formatted restricted string') end,
 __concat=function() error('concatenated restricted string') end,
 __eq=function() error('compared restricted string') end,
 __len=function() error('measured restricted string') end})
-- WoW reports secret strings as strings. Model that without decrypting them.
function type(value) if rawequal(value,secret) then return 'string' end return realType(value) end
function issecretvalue(value) return rawequal(value,secret) end
settings={enabled=false,log={}}; queued={}; forwarded=0; captures=0
stackMode='secret'; forwardingMode='normal'; settingsFail=false
function time() return 100 end
function debugstack()
 captures=captures+1
 if stackMode=='secret' then return secret end
 if stackMode=='error' then error('stack unavailable') end
 return "Interface/AddOns/MythicBoost/Modules/ErrorGuard.lua:1\n[C]: in function 'pcall'\nInterface/AddOns/Test/Original.lua:42: failure"
end
C_Timer={After=function(_,fn) queued[#queued+1]=fn end}
function geterrorhandler()
 return function(message)
  forwarded=forwarded+1; lastForwarded=message
  if forwardingMode=='recursive' then handler('nested') end
  if forwardingMode=='error' then error('previous handler failed') end
 end
end
function seterrorhandler(fn) handler=fn end
JP={L=function(text) return text end,UI={colors={}},RegisterModule=function() end,
 GetVersion=function() return 'test-build' end,
 Settings=function() if settingsFail then error('settings unavailable') end return settings end}
frames={}
function CreateFrame()
 local f={events={}}; frames[#frames+1]=f
 function f:RegisterEvent(e) self.events[e]=true end
 function f:SetScript(k,fn) self[k]=fn end
 return f
end
''')
source = (root / 'MythicBoost/Modules/ErrorGuard.lua').read_text(encoding='utf-8')
lua.eval("function(source) assert(load(source))('MythicBoost',JP) end")(source)
lua.execute(r'''
-- Disabled means untouched forwarding, not stack inspection.
assert(handler('original disabled')); assert(forwarded==1 and captures==0)
settings.enabled=true
assert(handler('original message'))
assert(settings.log[1].message=='original message')
assert(settings.log[1].stack=='[WoW restricted stack]')
for i=1,1000 do assert(handler('original message')) end
assert(#settings.log==1 and settings.log[1].count==1001 and #queued==1)
assert(captures==1, 'repeated errors must not recapture their stack')
assert(handler(secret)); assert(settings.log[1].message=='[WoW restricted error message]')
local bad=setmetatable({}, {__tostring=function() error('bad tostring') end})
assert(handler(bad)); assert(settings.log[1].count==2)
stackMode='plain'; assert(handler('normal stack'))
assert(settings.log[1].stack=='Interface/AddOns/Test/Original.lua:42: failure')
stackMode='error'; assert(handler('no stack')); assert(settings.log[1].stack=='')
-- A logger failure forwards the ORIGINAL message, not the logger exception.
settingsFail=true; forwardingMode='recursive'
assert(not handler('source failure')); assert(lastForwarded=='source failure' and forwarded==2)
settingsFail=false; forwardingMode='normal'; assert(handler('recovered'))
settings.enabled=false; forwardingMode='error'
assert(not handler('bad previous handler')); assert(forwarded==3)
forwardingMode='normal'; assert(handler('still works')); assert(forwarded==4)
settings.enabled=true; settings.log={}; stackMode='secret'
for i=1,1000 do assert(handler('unique '..i)) end
assert(#settings.log==100 and #queued==1)
local job=table.remove(queued); job()
collectgarbage('collect'); local baseline=collectgarbage('count')
local captureBaseline=captures
for i=1,10000 do assert(handler('unique 1000')) end
collectgarbage('collect')
assert(#settings.log==100 and #queued==1 and collectgarbage('count')-baseline<16)
assert(captures==captureBaseline, 'error storms must only increment an existing counter')
-- Protected-action notifications do not go through geterrorhandler.
local guard=JP.ErrorGuard; local watcher=guard.actionEvents
assert(watcher.events.ADDON_ACTION_BLOCKED and watcher.events.ADDON_ACTION_FORBIDDEN)
guard:WatchProtectedActions(); assert(#frames==1, 'one observer across reloadable lifecycle calls')
local count=#settings.log; local stackCount=captures
watcher.OnEvent(nil,'ADDON_ACTION_FORBIDDEN','OtherAddon','OtherAction()')
watcher.OnEvent(nil,'ADDON_ACTION_FORBIDDEN',secret,secret)
assert(#settings.log==count and captures==stackCount, 'ignore other addons and unreadable attribution')
settings.enabled=false; settings.log={}
watcher.OnEvent(nil,'ADDON_ACTION_FORBIDDEN','MythicBoost','Frame:RegisterEvent()')
assert(settings.log[1].message=='[ADDON_ACTION_FORBIDDEN] MythicBoost test-build: Frame:RegisterEvent()')
stackCount=captures
for i=1,10000 do watcher.OnEvent(nil,'ADDON_ACTION_FORBIDDEN','MythicBoost','Frame:RegisterEvent()') end
assert(#settings.log==1 and settings.log[1].count==10001 and captures==stackCount)
watcher.OnEvent(nil,'ADDON_ACTION_BLOCKED','MythicBoost',secret)
assert(settings.log[1].message:find('[WoW restricted action]',1,true))
settingsFail=true; watcher.OnEvent(nil,'ADDON_ACTION_BLOCKED','MythicBoost','broken logger')
settingsFail=false; watcher.OnEvent(nil,'ADDON_ACTION_BLOCKED','MythicBoost','recovered logger')
assert(settings.log[1].message:find('recovered logger',1,true), 'release the re-entry guard after logger errors')
''')
print('ErrorGuard: restricted strings/actions, original-error forwarding, re-entry, 100-entry cap and error storms passed')
