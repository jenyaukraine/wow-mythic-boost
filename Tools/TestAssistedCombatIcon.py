"""MinimalUI preserves Blizzard's assistant marker, including aliased glows."""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
source = (root / 'MythicBoost/Modules/MinimalUI.lua').read_text(encoding='utf-8')
helpers = source.split('local ACTION_EDGE_IDLE =', 1)[1].split('function MinimalUI:PinQueueStatus', 1)[0]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
unpack=table.unpack
MythicBoostDB={minimalUI=true}
UI={WeakKeys=function() return setmetatable({},{__mode='k'}) end}
function hooksecurefunc(object,method,hook)
 local original=object[method]
 object[method]=function(self,...) original(self,...); hook(self,...) end
end
function Visual()
 local v={alpha=1,shown=true,writes=0,stops=0,regions={},children={}}
 function v:GetAlpha() return self.alpha end
 function v:SetAlpha(a) self.writes=self.writes+1; self.alpha=a end
 function v:IsShown() return self.shown end
 function v:Show() self.shown=true end
 function v:Hide() self.shown=false end
 function v:SetShown(s) self.shown=s end
 function v:GetRegions() return unpack(self.regions) end
 function v:GetChildren() return unpack(self.children) end
 function v:GetAnimationGroups() return {Stop=function() self.stops=self.stops+1 end} end
 return v
end
''')
lua.execute('local ACTION_EDGE_IDLE =' + helpers + '\nMute=MuteActionSuggestionGlows')
lua.execute(r'''
local skin={}
local marker=Visual(); local artwork=Visual(); marker.regions={artwork}
local button={AssistedCombatRotationFrame=marker}
for i=1,100 do Mute(skin,button) end
assert(marker.writes==0 and marker.stops==0 and artwork.writes==0 and artwork.stops==0)
assert(not marker.__mbGlowHooked and not button.__mbSpellSuggested)
-- A generic alias must not reintroduce suppression of the assistant marker.
button.Glow=marker; Mute(skin,button)
assert(marker.writes==0 and marker.stops==0 and not marker.__mbGlowHooked)
marker:SetAlpha(.65); marker:Hide(); marker:Show()
assert(marker.alpha==.65 and marker.shown and not button.__mbSpellSuggested)
-- Actual proc glows still use the established square-border styling.
local proc=Visual(); proc.children={Visual()}; button.SpellActivationAlert=proc
Mute(skin,button)
assert(proc.alpha==0 and proc.children[1].alpha==0 and proc.stops>0)
assert(button.__mbSpellSuggested and not skin.savedTextureAlpha[marker])
proc:Hide(); assert(not button.__mbSpellSuggested)
proc:Show(); proc:SetAlpha(.9); assert(proc.alpha==0 and button.__mbSpellSuggested)
assert(marker.alpha==.65 and artwork.alpha==1)
-- A later-created assistant marker (e.g. during combat) is also untouched.
local late={}; Mute(skin,late); late.AssistedCombatRotationFrame=Visual()
Mute(skin,late); assert(late.AssistedCombatRotationFrame.writes==0)
''')
print('Assisted combat icon: native visibility/alpha/animation preserved; proc styling retained')
