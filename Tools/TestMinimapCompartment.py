"""Launchers remain accessible after moving into Blizzard's addon menu."""
from pathlib import Path
from lupa import LuaRuntime

source = (Path(__file__).resolve().parents[1] / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
body = source.split("local function HideLooseMinimapAddonButtons", 1)[1].split("local PlaceNativeAddonCompartment", 1)[0]
lua = LuaRuntime()
lua.execute('''
UI={WeakKeys=function() return {} end}
function wipe(t) for k in pairs(t) do t[k]=nil end end
function Button()
 local b={shown=true}
 function b:IsShown() return self.shown end
 function b:Hide() self.shown=false end
 function b:Show() self.shown=true; if self.onShow then self.onShow(self) end end
 function b:SetShown(v) self.shown=v end
 function b:HookScript(_,fn) self.onShow=fn end
 function b:GetScript() return self.click end
 function b:IsProtected() return self.protected end
 b.click=function(self,key) self.clicked=key end
 return b
end
state={minimapOwnershipActive=true}
WMPI_MinimapButton=Button()
LibDBIcon10_Example=Button()
LibDBIcon10_Example.dataObject={label='Example',icon=123}
''')
lua.execute("function Run" + body)
lua.execute('''
Run(state,true)
assert(WMPI_MinimapButton.shown and LibDBIcon10_Example.shown)
AddonCompartmentFrame={registeredAddons={},Show=function() end}
function AddonCompartmentFrame:RegisterAddon(entry) table.insert(self.registeredAddons,entry) end
Run(state,true)
assert(#AddonCompartmentFrame.registeredAddons==2)
assert(not WMPI_MinimapButton.shown and not LibDBIcon10_Example.shown)
for _,entry in ipairs(AddonCompartmentFrame.registeredAddons) do
 entry.func(nil,{buttonName='RightButton'})
end
assert(WMPI_MinimapButton.clicked=='RightButton' and LibDBIcon10_Example.clicked=='RightButton')
for i=1,10 do Run(state,true) end
assert(#AddonCompartmentFrame.registeredAddons==2)
WMPI_MinimapButton:Show(); assert(not WMPI_MinimapButton.shown)
LibDBIcon10_Existing=Button()
LibDBIcon10_Protected=Button(); LibDBIcon10_Protected.protected=true
AddonCompartmentFrame:RegisterAddon({text='|cffffffffExisting|r',func=function() end})
state.minimapAddonScanDirty=true
Run(state,true)
assert(#AddonCompartmentFrame.registeredAddons==3)
assert(not LibDBIcon10_Existing.shown and LibDBIcon10_Protected.shown)
state.minimapOwnershipActive=false
Run(state,false)
assert(WMPI_MinimapButton.shown and LibDBIcon10_Example.shown and LibDBIcon10_Existing.shown)
''')
print("PASS: addon registration, clicks, deduplication, late load, safe hiding and restoration")
