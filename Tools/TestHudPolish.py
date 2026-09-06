"""Execute the HUD/reminder regressions with bounded, engine-independent fixtures."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / "MythicBoost" / name).read_text(encoding="utf-8")


def load(lua, name):
    lua.eval("function(s) return assert(load(s))('MythicBoost', JP) end")(source(name))


WIDGETS = r'''
unpack=table.unpack; allocations=0; combat=false; now=0
function wipe(t) for k in pairs(t) do t[k]=nil end end
function issecretvalue(v) return type(v)=='table' and rawget(v,'secret')==true end
function InCombatLockdown() return combat end
function GetTime() return now end
function CreateColor(...) return {...} end
local methods={}
function NewWidget(parent)
    allocations=allocations+1
    return setmetatable({parent=parent,points={},scripts={},events={},shown=true,scale=1,alpha=1,level=1}, {__index=methods})
end
function CreateFrame(_,name,parent) local f=NewWidget(parent); f.name=name; return f end
for _,key in ipairs({'SetTexCoord','SetGradient','SetBlendMode','SetJustifyH','SetWordWrap',
    'SetClampedToScreen','SetMovable','RegisterForDrag','SetClipsChildren','SetLooping',
    'SetFromAlpha','SetToAlpha','SetDuration','SetOrder','SetSmoothing','SetShadowColor','SetShadowOffset'}) do
    methods[key]=function() end
end
function methods:GetParent() return self.parent end
function methods:GetName() return self.name end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(v) self.level=v end
function methods:SetFrameStrata(v) self.strata=v end
function methods:GetFrameStrata() return self.strata end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:GetWidth() return self.width or (self.parent and self.parent:GetWidth()-27) or 253 end
function methods:GetHeight() return self.height or 18 end
function methods:SetPoint(...) self.points[#self.points+1]={...} end
function methods:ClearAllPoints() wipe(self.points) end
function methods:GetNumPoints() return #self.points end
function methods:GetPoint(i) return unpack(self.points[i or 1] or {}) end
function methods:SetAllPoints(v) self.allPoints=v or self.parent end
function methods:SetScale(v) self.scale=v end
function methods:GetScale() return self.scale end
function methods:GetEffectiveScale() return self.scale*(self.parent and self.parent:GetEffectiveScale() or 1) end
function methods:SetScript(k,fn) self.scripts[k]=fn end
function methods:SetAttribute(k,v) assert(not combat, 'attribute mutation during combat'); self.attrs=self.attrs or {}; self.attrs[k]=v end
function methods:GetAttribute(k) return self.attrs and self.attrs[k] end
function methods:SetFrameRef(k,v) assert(not combat); self.refs=self.refs or {}; self.refs[k]=v end
function methods:GetFrameRef(k) return self.refs and self.refs[k] end
function methods:HookScript(k,fn) self.scripts[k]=fn end
function methods:RegisterEvent(e) self.events[e]=true end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:EnableMouse(v) self.mouse=v end
function methods:SetAlpha(v) assert(not issecretvalue(v)); self.alpha=v end
function methods:GetAlpha() return self.alpha end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetShown(v) self.shown=not not v end
function methods:SetBackdrop(v) self.backdrop=v end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:SetBackdropColor(...) self.background={...} end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetVertexColor(...) self.color={...} end
function methods:SetTexture(v) self.texture=v end
function methods:SetText(v) self.text=v end
function methods:SetFormattedText(fmt,...) self.text=string.format(fmt,...) end
function methods:SetTextColor(...) self.color={...} end
function methods:GetFont() return 'font',11,'OUTLINE' end
function methods:SetFont(...) self.font={...} end
function methods:CreateTexture(_,layer,_,sublevel)
    local t=NewWidget(self); t.drawLayer=layer or 'ARTWORK'; t.sublevel=sublevel or 0; return t
end
function methods:CreateAnimationGroup() return NewWidget(self) end
function methods:CreateAnimation() return NewWidget(self) end
function methods:IsPlaying() return self.playing end
function methods:Play() self.playing=true end
function methods:Stop() self.playing=false end
function methods:SetMinMaxValues(low,high) self.low=low; self.high=high end
function methods:GetMinMaxValues() return self.low,self.high end
function methods:SetValue(v) self.value=v end
function methods:SetStatusBarTexture() self.fill=NewWidget(self) end
function methods:GetStatusBarTexture() return self.fill end
function methods:SetStatusBarColor(...) self.color={...} end
UIParent=NewWidget()
settings={enabled=true,unlocked=false,buff=true,layoutRevision=3,point='BOTTOM',relativePoint='BOTTOM',x=21,y=99}
JP={L=function(s) return s end, Settings=function() return settings end, modules={},
    RegisterModule=function(self,k,v) self.modules[k]=v end, UI={}}
UI=JP.UI
UI.colors={surface={.014,.020,.028,.94},text={.9,.9,.9,1},muted={.4,.4,.4,1},
    hudEdge={.30,.32,.34,.92},hudAccent={.60,.49,.29,.55},hudShadow={.008,.011,.016,.88}}
function UI.Unpack(v) return unpack(v) end
function UI.WeakKeys() return setmetatable({}, {__mode='k'}) end
function UI.Text(parent,_,text,color) local w=NewWidget(parent); w.text=text; w.color=color; return w end
function UI.SafeBoolean(v) return not issecretvalue(v) and v==true end
function UI.UsableNumber(v) return type(v)=='number' and not issecretvalue(v) end
'''


def test_buff_range():
    lua = LuaRuntime()
    lua.execute(WIDGETS)
    lua.execute(r'''
        secret={secret=true}; members={player={buff=true},party1={range=false},party2={range=false}}
        raid=false; auraReads={}; timers={}; applies=0; auraBlocked=false
        function UnitClass() return 'Druid','DRUID' end
        function UnitExists(u) return members[u]~=nil end
        function UnitIsConnected(u) return members[u].connected~=false end
        function UnitIsDeadOrGhost(u) return members[u].dead or false end
        function UnitIsUnit(u,v) return u==v or members[u].alias==v end
        function UnitPhaseReason(u) return members[u].phase end
        function UnitIsVisible(u) return members[u].visible~=false end
        function UnitName(u) return members[u].name or u end
        function IsInRaid() return raid end
        function IsInGroup() return true end
        function GetNumGroupMembers() return 3 end
        function GetNumSubgroupMembers() return 2 end
        function UnitInRange(u) return members[u].fallback, members[u].checked end
        function IsPlayerSpell() return false end
        C_UnitAuras={}
        C_Spell={IsSpellInRange=function(id,u)
            assert(id==1126); if members[u].rangeError then error('restricted') end
            return members[u].range end}
        C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
        function UI.SafeUnitAura(u,id)
            auraReads[u]=(auraReads[u] or 0)+1
            if auraBlocked then return nil,true end
            return members[u].buff and {spellId=id} or nil
        end
        function Flush() local t=timers; timers={}; for _,fn in ipairs(t) do fn() end end
    ''')
    load(lua, "Modules/SmartClick.lua")
    lua.execute(r'''
        local m=JP.SmartClick
        assert(m:MissingBuff()==nil, 'distant unbuffed members must not show a reminder')
        assert(not auraReads.party1 and not auraReads.party2, 'filter before reading auras')
        members.party1.range=true
        local missing=m:MissingBuff(); assert(#missing==1 and missing[1]=='party1')
        members.party2.range=true; missing=m:MissingBuff(); assert(#missing==2)
        members.party1.buff=true; assert(#m:MissingBuff()==1)
        members.party2.dead=true; assert(m:MissingBuff()==nil)
        members.party2.dead=secret; assert(m:MissingBuff()==nil)
        members.party2.dead=false; members.party2.connected=false; assert(m:MissingBuff()==nil)
        members.party2.connected=true; members.party2.phase=1; assert(m:MissingBuff()==nil)
        members.party2.phase=0; assert(m:MissingBuff()==nil, 'phase zero is a real separation')
        members.party2.phase=secret; assert(m:MissingBuff()==nil)
        members.party2.phase=nil
        local phaseAPI=UnitPhaseReason
        UnitPhaseReason=function() error('unavailable') end
        assert(m:MissingBuff()==nil, 'unreadable phase must not suggest buffing')
        UnitPhaseReason=nil; assert(m:MissingBuff()==nil)
        UnitPhaseReason=phaseAPI
        members.party2.visible=false; assert(m:MissingBuff()==nil)
        members.party2.visible=true; members.party2.range=secret; members.party2.fallback=secret
        members.party2.checked=secret; assert(m:MissingBuff()==nil, 'secret range is never proximity')
        members.party2.range=nil; members.party2.fallback=true; members.party2.checked=false
        assert(m:MissingBuff()==nil, 'unchecked range is unknown')
        members.party2.checked=true; assert(#m:MissingBuff()==1)
        members.party2.rangeError=true; members.party2.fallback=false; assert(m:MissingBuff()==nil)
        members.party2.rangeError=nil
        -- Raid self aliases must not duplicate the player in the count.
        raid=true; members.raid1={alias='player'}; members.raid2={range=true}; members.raid3={range=false}
        members.player.buff=false; missing=m:MissingBuff(); assert(#missing==2)
        members.raid2.buff=true; missing=m:MissingBuff(); assert(#missing==1 and missing[1]=='player')
        raid=false; members.player.buff=true; members.party2.range=true
        m.buffButton=NewWidget(); m.buffButton.label=NewWidget(); m.buffButton.spellName='buff'
        m.Apply=function() applies=applies+1 end
        m:Create(); m:Create()
        assert(m.events.events.UNIT_IN_RANGE_UPDATE and m.events.events.UNIT_PHASE and m.events.events.UNIT_CONNECTION)
        m:RefreshBuffButton(); assert(m.buffButton.shown and m.buffButton:GetAttribute('mb-visible'))
        -- 1000 range events collapse into one pass, without rebuilding macros.
        members.party2.range=false
        for i=1,1000 do m.events.scripts.OnEvent(nil,'UNIT_IN_RANGE_UPDATE','party2') end
        assert(#timers==1); Flush(); assert(applies==0 and not m.buffButton.shown)
        m.events.scripts.OnEvent(nil,'UNIT_AURA','nameplate1'); assert(#timers==0)
        members.party2.range=true
        m.events.scripts.OnEvent(nil,'UNIT_IN_RANGE_UPDATE','party2'); Flush(); assert(m.buffButton.shown)
        -- The secure state driver hides the real button on combat entry.
        m.buffButton:Hide(); combat=true; auraBlocked=true; m:RefreshBuffButton()
        assert(not m.buffButton.shown, 'refresh must not resurrect the hidden secure button')
        combat=false; m.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED'); Flush(); assert(applies==1)
        m:RefreshBuffButton(); assert(not m.buffButton.shown and m.buffButton.label.text=='')
    ''')
    text = source("Modules/SmartClick.lua")
    assert 'NewTicker' not in text and '"OnUpdate"' not in text


def test_castbar():
    lua = LuaRuntime()
    lua.execute(WIDGETS)
    lua.execute(r'''
        function UnitCastingInfo() return 'Long spell name','Long spell name',42,0,1500,nil,nil,false,1126 end
        function UnitChannelInfo() return 'Channel','Channel',43,0,3000,nil,false,42 end
        function UnitName() return 'Player' end
        function GetNetStats() return 0,0,45,78 end
    ''')
    load(lua, "Modules/CastBar.lua")
    lua.execute(r'''
        local c=JP.CastBar; c:Create(); local f=c.frame
        local built=allocations; c:Create(); assert(allocations==built)
        assert(f.width==400 and f.height==32 and f.icon.width==24)
        assert(f.bar.points[1][2]==30 and f.bar.points[2][4]==-4)
        local labelWidth=f.width-30-4-5-82-12
        assert(labelWidth>=260, 'spell and target need room without shrinking the font')
        assert(f.name.points[2][4]==-94, 'keep a separate time region and 12 px gap')
        assert(f.name.parent==f.time.parent and f.time.parent.parent==f.bar)
        assert(f.time.parent.level>f.bar.level and f.time.width==82)
        assert(f.backdrop.edgeSize==12 and f.backdrop.edgeFile:find('XPerl_ThinEdge',1,true))
        assert(f.barBorder==nil and f.name.font[3]=='', 'no sharp inner frame or heavy font outline')
        assert(f.time.height+1+f.latencyText.height<=24, 'MS must have its own line inside the bar')
        assert(f.timePanel==nil and f.name.font[2]==f.time.font[2])
        assert(settings.x==21 and settings.y==99, 'custom anchor must not migrate')
        c:Start(false,false,'cast',1126); assert(f.time.text=='0.0 / 1.5')
        assert(f.latencyText.text=='78 ms')
        now=1.1; c:OnUpdate(); assert(f.time.text=='1.1 / 1.5')
        now=1.5; c:OnUpdate(); assert(f.time.text=='1.5 / 1.5' and not c.active)
        now=3; c:OnUpdate(); assert(not f.shown)
        now=0; c:Start(true,false,'channel',42); assert(f.time.text=='3.0 / 3.0')
        now=1.2; c:OnUpdate(); assert(f.time.text=='1.8 / 3.0')
        c:Finish(true); assert(f.time.text=='0.0 / 3.0')
        now=0; c:Start(false,false,'again',1126); assert(f.time.text=='0.0 / 1.5')
        c:Finish(false); assert(not c.active and not f.spark.playing)
        built=allocations
        for i=1,1000 do now=0; c:Start(false,false,'again',1126); now=1.1; c:OnUpdate(); c:Finish(true) end
        assert(allocations==built, 'casts must reuse all frames/textures/animations')
        c:SetUnlocked(true); assert(f.time.text=='1.1 / 1.5' and f.latencyText.text=='78 ms')
        c.sentAt=-100; c.sentGUID='old'; now=0; c:Start(false,false,'new',1126)
        assert(f.latencyText.text=='78 ms', 'a stale SENT timestamp must never fill the latency zone')
        c:Finish(true); c.sentAt=-.13; c.sentGUID='new2'; c:Start(false,false,'new2',1126)
        assert(f.latencyText.text=='130 ms', 'matched send-to-start latency is displayed')
        c:Finish(true); GetNetStats=function() return 0,0,0,0 end; c:Start(false,false,'zero',1126)
        assert(f.latencyText.text=='0 ms' and not f.latency.shown)
        c:Finish(true); GetNetStats=function() return nil,nil,nil,nil end; c:Start(false,false,'unknown',1126)
        assert(f.latencyText.text=='— ms', 'unavailable latency must not be invented')
    ''')


def test_header():
    lua = LuaRuntime()
    lua.execute(WIDGETS)
    load(lua, "Modules/Welcome.lua")
    composition = source("Modules/GroupSearchUI.lua").split("function GroupSearchUI:RefreshOwnComposition(welcome)", 1)[1].split("\n---------------------------------------------------------------------------", 1)[0]
    lua.execute(r'''
        GroupSearchUI={}; JP.GroupSearchUI=GroupSearchUI
        roles={player='HEALER'}
        function IsInGroup() return true end
        function IsInRaid() return false end
        function GetNumSubgroupMembers() return 4 end
        function UnitExists(u) return roles[u]~=nil end
        function UnitGroupRolesAssigned(u) return roles[u] end
        function GetSpecialization() return 1 end
        function GetSpecializationRole() return 'HEALER' end
        function UI.SetRoleTexture(icon,role) icon.role=role; return role~='NONE' end
        for _,name in ipairs({'GuildBoard','ApplicantBoard','RunHistory','UpgradeCalculator','SettingsHub'}) do
            JP[name]={Refresh=function() end}
        end
    ''')
    lua.execute("function GroupSearchUI:RefreshOwnComposition(welcome)" + composition)
    lua.execute(r'''
        local w=JP.modules.Welcome; w.frame=NewWidget(); w.rows={}; w.status=NewWidget(); w.partySlots={}
        for i=1,5 do local slot=NewWidget(); slot.icon=NewWidget(); slot.unknown=NewWidget(); w.partySlots[i]=slot end
        for _,page in ipairs({'guild','applicants','history','upgrades','settings'}) do
            w.currentPage=page; roles.party1='TANK'; w:Refresh()
            assert(w.partySlots[2].icon.shown and w.partySlots[2].icon.role=='TANK', page)
            roles.party1='DAMAGER'; w:Refresh(); assert(w.partySlots[2].icon.role=='DAMAGER',page)
            roles.party1=nil; w:Refresh(); assert(not w.partySlots[2].icon.shown,page)
            roles.player='NONE'; w:Refresh(); assert(w.partySlots[1].icon.role=='HEALER',page)
        end
    ''')


def test_micro_menu():
    lua = LuaRuntime()
    lua.execute(WIDGETS)
    body = source("Modules/MinimalUI.lua").split("function MinimalUI:StyleMicroMenu(enabled)", 1)[1].split("\nlocal ACTION_BUTTON_PREFIXES", 1)[0]
    lua.execute(r'''
        C=UI.colors; MinimalUI={}; Minimap=NewWidget(UIParent); buttons={}
        function MicroButtons() return buttons end
        for i=1,14 do
            local parent=NewWidget(UIParent); parent:SetScale(i%2==0 and .8 or 1.2)
            local button=NewWidget(parent); button:SetSize(28+i%3,32+i%2)
            button:SetPoint('TOP',parent,'TOP',i,0); buttons[i]=button
        end
    ''')
    lua.execute("function MinimalUI:StyleMicroMenu(enabled)" + body)
    lua.execute(r'''
        for _,width in ipairs({120,245,400}) do
            Minimap:SetWidth(width); MinimalUI:StyleMicroMenu(true)
            local anchor=MinimalUI.microMenuAnchor
            for i,slot in ipairs(MinimalUI.microMenuSlots) do
                local x,y=slot.points[1][4],slot.points[1][5]
                assert(x>=3 and x+slot.width<=width-3+.00001)
                assert(y==-3 and anchor.height==slot.height+6)
                local button=buttons[i]
                assert(button.parent~=slot and button.points[1][2]==slot)
                local physicalWidth=button.width*button:GetEffectiveScale()/UIParent:GetEffectiveScale()
                assert(physicalWidth<=slot.width+.00001, 'native click rectangles must not overlap')
            end
        end
        local built=allocations
        for i=1,1000 do MinimalUI:StyleMicroMenu(true) end
        assert(allocations==built, 'layout must reuse slots')
        combat=true; Minimap:SetWidth(300); MinimalUI:StyleMicroMenu(true)
        assert(MinimalUI.microMenuAnchor.width==400, 'no native frame moves in combat')
        combat=false; MinimalUI:StyleMicroMenu(false)
        for i,b in ipairs(buttons) do assert(b.scale==1 and b.points[1][4]==i) end
    ''')


def test_neutral_edges():
    frames = source("Modules/UnitFrames.lua")
    marker = frames.split('local marker = CreateFrame', 1)[1].split('display.interruptMarker = marker', 1)[0]
    assert 'marker:SetSize(19, 19)' in marker and 'BadgeBackdrop(marker)' in marker
    assert '"TOPLEFT", 4, -4' in marker and 'C.accent' not in marker
    assert 4 + 19 < 58  # marker remains inside the portrait
    assert 'frame.__mbGoldTrimTop:Hide()' in frames
    assert 'ModernBackdrop(statsPanel, .95)' in frames
    assert 'UI.Backdrop(card, C.panel, C.hudEdge)' in source('Modules/ApplicantCards.lua')
    for module in ('UpgradeCalculator',):
        assert 'UI.Backdrop(row, row.baseColor, C.hudEdge)' in source(f'Modules/{module}.lua')


def test_portrait_marker():
    lua = LuaRuntime()
    lua.execute(WIDGETS)
    lua.execute('''
        UnitFrames={}; settings.marker=7; cycles=0
        JP.InterruptAssist={Settings=function() return settings end,
            CycleMarker=function() cycles=cycles+1 end}
        display={portrait={ring=NewWidget(),model=NewWidget()}}
        function BadgeBackdrop() end
        function GameTooltip_Hide() end
    ''')
    code = source('Modules/UnitFrames.lua')
    badge = 'local marker = CreateFrame' + code.split('local marker = CreateFrame', 1)[1].split('display.interruptMarker = marker', 1)[0]
    lua.execute(badge + 'display.interruptMarker = marker')
    refresh = code.split('local function UpdateInterruptMarker', 1)[1].split('local function UpdateIdentity', 1)[0]
    public = code.split('function UnitFrames:RefreshInterruptMarker()', 1)[1].split('function UnitFrames:ApplySettings()', 1)[0]
    lua.execute('local function UpdateInterruptMarker' + refresh
                + 'function UnitFrames:RefreshInterruptMarker()' + public)
    lua.execute('''
        UnitFrames.displays={player=display}
        local badge=display.interruptMarker
        assert(badge.clicks[1]=='LeftButtonUp')
        badge.scripts.OnClick(); assert(cycles==1)
        UnitFrames:RefreshInterruptMarker()
        assert(badge.shown and badge.icon.texture:match('_7$'))
        local count=allocations
        for i=1,10000 do UnitFrames:RefreshInterruptMarker() end
        assert(count==allocations, 'refresh only changes the icon, never rebuilds the portrait')
        settings.marker=0; UnitFrames:RefreshInterruptMarker(); assert(not badge.shown)
    ''')


def test_applicant_experience():
    from TestReviewBrowser import test_applicant_cards
    test_applicant_cards()


if __name__ == '__main__':
    for test in (test_buff_range, test_castbar, test_header, test_micro_menu, test_neutral_edges, test_portrait_marker, test_applicant_experience):
        test()
        print(test.__name__ + ': OK')
