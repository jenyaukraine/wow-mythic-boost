"""Profile-theme behavior; mock public API import, never touch live SavedVariables."""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
JP={IsSecret=function() return false end}; combat=false; imports=0; exports=0
MythicBoostDB={}; MPTSV={Profiles={['MythicBoost Compact']={user=true}}}
function InCombatLockdown() return combat end
function UnitFullName() return 'Player','Realm' end
function GetNormalizedRealmName() return 'Realm' end
STANDARD_TEXT_FONT='Fonts/FRIZQT__.TTF'
anchor={GetEffectiveScale=function() return 1.5 end,GetWidth=function() return 200 end,
 GetRight=function() return 1200 end,GetBottom=function() return 500 end}
UIParent={GetEffectiveScale=function() return 1 end,GetWidth=function() return 1920 end,
 GetHeight=function() return 1080 end}
profile={}
for _,k in ipairs({'KeyInfo','KeyLevel','DungeonName','AffixIcons','DeathCounter','TimerBar',
 'TimerText','ComparisonTimer','ChestTimer1','ChestTimer2','ChestTimer3','Tick1','Tick2',
 'Bosses','BossName','BossTimer','BossSplit','ForcesBar','PercentCount','RealCount',
 'ForcesSplits','ForcesCompletion','PBInfo','CurrentPullBar'}) do profile[k]={enabled=true} end
media={Register=function() end}
codec={DecodeForPrint=function(_,s) return s end, DecompressDeflate=function(_,s) return s end,
 CompressDeflate=function(_,s) return s end, EncodeForPrint=function(_,s) return s end}
serializer={Deserialize=function() return true,profile end,
 Serialize=function(_,p) importedProfile=p; return 'redesigned' end}
function LibStub(name)
 if name=='LibDeflate' then return codec elseif name=='AceSerializer-3.0' then return serializer
 elseif name=='LibSharedMedia-3.0' then return media end
 error('unexpected library')
end
MPTAPI={GetExportString=function() exports=exports+1; return 'original' end,
 ImportProfile=function(_,data,name,main)
  assert(data=='redesigned' and not main and not MPTSV.Profiles[name]); imports=imports+1
  importedName=name; MPTSV.Profiles[name]=importedProfile; return true
 end}
''')
loader = lua.eval("function(code) assert(load(code))('MythicBoost',JP) end")
source = (root / "MythicBoost/Modules/TimerTheme.lua").read_text(encoding="utf-8")
loader(source)
lua.execute(r'''
combat=true; JP.TimerTheme:Apply(anchor); assert(imports==0 and exports==0)
combat=false; JP.TimerTheme:Apply(anchor)
assert(imports==1 and importedName=='MythicBoost Compact 2')
assert(MPTSV.Profiles['MythicBoost Compact'].user)
assert(MythicBoostDB.timerTheme['Player-Realm'].original=='original')
assert(profile.KeyInfo.Width==300 and profile.ForcesBar.Width==300)
assert(profile.Position.xOffset==-120 and profile.Position.yOffset==-338)
assert(profile.Background.WidthOffset==0 and profile.Background.HeightOffset==0)
assert(profile.KeyLevel.xOffset<profile.DungeonName.xOffset)
assert(profile.BossSplit.xOffset<profile.BossTimer.xOffset and profile.Bosses.Height==20)
assert(profile.TimerBar.AnchoredTo=='KeyInfo' and profile.ForcesBar.AnchoredTo=='Bosses')
assert(not profile.ComparisonTimer.enabled and profile.TimerText.Decimals==0)
assert(profile.TimerText.Anchor=='TOPLEFT' and profile.ChestTimer1.Anchor=='BOTTOMRIGHT')
assert(profile.ChestTimer1.xOffset>profile.ChestTimer2.xOffset)
assert(profile.ChestTimer2.xOffset>profile.ChestTimer3.xOffset)
for i=1,10000 do JP.TimerTheme:Apply(anchor) end
assert(imports==1 and exports==1)
''')
# Simulated reload: persistent revision prevents duplicate profiles.
loader(source)
lua.execute("JP.TimerTheme:Apply(anchor); assert(imports==1 and exports==1)")
assert "EnumerateFrames" not in source and "hooksecurefunc" not in source
minimal = (root / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
# MinimalUI no longer integrates the third-party timer. Do not require the
# removed method; still guard a future reintroduction against frame traversal.
if "function MinimalUI:StyleMPlusTimer" in minimal:
    body = minimal.split("function MinimalUI:StyleMPlusTimer", 1)[1].split("function MinimalUI:Apply", 1)[0]
    assert "EnumerateFrames" not in body and "SetPoint" not in body
else:
    assert "TimerTheme:Apply" not in minimal and "MPTAPI" not in minimal
print("TimerTheme: compact layout, placement below minimap, original backup, collisions and idempotence passed")
