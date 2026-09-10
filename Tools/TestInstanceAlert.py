"""Dungeon-copy warnings: public signals, event ordering, bounded lifecycle.

WoW mocks cannot prove when the live server emits a notification. Never infer
a unique instance ID from map IDs, unseen party members or restricted data.
"""
from TestDungeonHUD import runtime
from TestHudPolish import load, source
from TestInteractionFixes import TIMERS


def fixture():
    lua = runtime()
    lua.execute(TIMERS + r'''
        inside=true; kind='party'; grouped=true; raid=false; ownShard=false
        Enum.PhaseReason={Phasing=0,Sharding=1,WarMode=2,ChromieTime=3,TimerunningHwt=4}
        playerMap=100; phaseReads=0; visibilityReads=0
        function IsInInstance() return inside,kind end
        function IsInGroup() return grouped end
        function IsInRaid() return raid end
        function UnitInPartyShard(unit)
            if unit=='player' then return ownShard end
            return units[unit] and units[unit].shard
        end
        function UnitPhaseReason(unit) phaseReads=phaseReads+1; return units[unit].phase end
        function UnitIsVisible(unit) visibilityReads=visibilityReads+1; return units[unit].visible end
        function UnitIsConnected(unit)
            if units[unit].connected==nil then return true end
            return units[unit].connected
        end
        C_Map={GetBestMapForUnit=function(unit)
            if unit=='player' then return playerMap end
            return units[unit] and units[unit].map
        end}
        function Member(phase)
            units.party1={name='Ally',guid='Player-1-1',phase=phase,shard=true,map=100,visible=false}
        end
        function Tick(seconds) now=now+(seconds or 1); Flush() end
        function SendChatMessage() error('notification must not send chat') end
        function ResetInstances() error('notification must not reset an instance') end
        function LeaveParty() error('notification must not leave a group') end
        function SetDungeonDifficultyID() error('notification must not change difficulty') end
        function ActiveTimers()
            local n=0; for _,timer in ipairs(timers) do if not timer.cancelled then n=n+1 end end
            return n
        end
    ''')
    load(lua, 'Modules/InstanceAlert.lua')
    return lua


def test_native_notification():
    lua=fixture()
    lua.execute(r'''
        local a=JP.InstanceAlert; a:Enable()
        assert(db.convenience.warnDifferentInstance and not a.frame:IsShown())
        assert(a.events.events.ENTERED_DIFFERENT_INSTANCE_FROM_PARTY)
        a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY')
        assert(a.frame:IsShown() and a.source=='event')
        local objects=allocations
        for i=1,1000 do a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY') end
        assert(ActiveTimers()==1 and allocations==objects)
        Tick(); assert(a.source=='event' and a.frame:IsShown())
        assert(not a.frame.mouse,'live warning must be click-through and locked')
        a.frame.scripts.OnDragStart(); assert(not a.frame.moving)
        -- A native signal does not require readable phase/map/visibility data.
        Member(Secret(1)); ownShard=Secret(false); Tick(3)
        assert(a.source=='event' and a.frame:IsShown())
        -- A same-instance, publicly visible roster clears the stale signal.
        ownShard=true; units.party1.phase=nil; units.party1.visible=true
        a:OnEvent('UNIT_PHASE'); Tick(3)
        assert(not a.frame:IsShown() and not a.pending and not a.source)
        a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY')
        inside=false; a:OnEvent('ZONE_CHANGED_NEW_AREA')
        assert(not a.frame:IsShown() and not a.pending)
    ''')


def test_join_inside_and_resolution():
    lua=fixture()
    lua.execute(r'''
        local a=JP.InstanceAlert; grouped=false; a:Enable()
        grouped=true; Member(Enum.PhaseReason.Sharding); a:OnEvent('GROUP_JOINED')
        Tick(); assert(not a.frame:IsShown(),'first phase sample is not enough')
        Tick(); assert(not a.frame:IsShown())
        Tick(); assert(a.source=='shard' and a.frame:IsShown())
        local objects=allocations
        for i=1,30 do Tick(3); assert(a.source=='shard') end
        assert(allocations==objects and ActiveTimers()==1)
        ownShard=true; units.party1.phase=nil; units.party1.visible=true
        a:OnEvent('UNIT_PHASE'); Tick(3)
        assert(not a.source and not a.pending and not a.frame:IsShown())
        -- Group churn changes the GUID even if the party token stays the same.
        ownShard=false; Member(Enum.PhaseReason.Sharding); a:OnEvent('GROUP_ROSTER_UPDATE'); Tick()
        units.party1.guid='Player-1-2'; Tick(); assert(not a.source)
        Tick(); assert(not a.source)
        Tick(); assert(a.source=='shard')
        units.party1.phase=nil; a:OnEvent('UNIT_PHASE'); Tick(3)
        assert(not a.source and not a.frame:IsShown(),'fallback requires current evidence')
        for i=1,15 do Tick() end
        assert(not a.pending and not a.candidate and not a.deadline)
    ''')


def test_either_side_and_generic_phase():
    for phase in ('Sharding', 'Phasing'):
        lua=fixture()
        lua.execute("Member(Enum.PhaseReason."+phase+"); ownShard=true; units.party1.shard=false")
        lua.execute(r'''
            local a=JP.InstanceAlert; a:Enable()
            for i=1,3 do Tick() end
            assert(a.source=='shard' and a.frame:IsShown())
            assert(a.title.text=='Группа в разных копиях или фазах')
            units.party1.phase=nil; units.party1.visible=true
            a:OnEvent('UNIT_PHASE'); Tick(3)
            assert(not a.source and not a.pending)
        ''')


def test_public_phase_does_not_require_map_data():
    cases = (
        "units.party1.map=200",  # another floor or dungeon is not a copy ID
        "units.party1.map=Secret(100)",
        "units.party1.map=nil",
        "playerMap=0",
        "playerMap=Secret(100)",
        "C_Map=nil",
    )
    for phase in ('Sharding', 'Phasing'):
        for setup in cases:
            lua=fixture()
            lua.execute("Member(Enum.PhaseReason."+phase+"); "+setup)
            lua.execute(r'''
                local a=JP.InstanceAlert; a:Enable()
                for i=1,3 do Tick() end
                assert(a.source=='shard' and a.frame:IsShown(),
                    'public phase evidence must not depend on a readable matching map')
                assert(a.title.text=='Группа в разных копиях или фазах')
                units.party1.phase=nil; Tick(3)
                assert(not a.source and not a.frame:IsShown(),
                    'map differences or missing maps alone must not keep the warning')
            ''')


def test_late_candidate_finishes_confirmation():
    lua=fixture()
    lua.execute(r'''
        Member(nil)
        local a=JP.InstanceAlert; a:Enable()
        local deadline=a.deadline
        Tick(10.5)
        units.party1.phase=Enum.PhaseReason.Sharding
        Tick() -- first evidence at 11.5 seconds of the 12-second window
        assert(not a.source and a.candidateSince==deadline-.5)
        Tick() -- deadline passed, but evidence is only one second old
        assert(GetTime()>deadline and not a.source and a.pending,
            'an existing candidate needs its full two-second confirmation')
        Tick()
        assert(a.source=='shard' and a.frame:IsShown())
        units.party1.phase=nil; Tick(3)
        assert(not a.source and not a.pending and not a.deadline,
            'late confirmation must not create idle polling after evidence is lost')
    ''')


def test_no_false_positives_or_secret_use():
    cases = (
        "units.party1.phase=nil",  # invisible/far away, no phase signal
        "units.party1.phase=Enum.PhaseReason.WarMode",
        "units.party1.phase=Enum.PhaseReason.ChromieTime",
        "units.party1.phase=Enum.PhaseReason.TimerunningHwt",
        "units.party1.phase=Secret(1)",
        "units.party1.phase='1'",
        "units.party1.connected=false",
        "units.party1.connected=Secret(true)",
        "units.party1.dead=true",
        "units.party1.dead=Secret(false)",
        "units.party1.guid=Secret('hidden')",
        "UnitPhaseReason=nil",
        "UnitPhaseReason=function() error('restricted') end",
        "Enum.PhaseReason=nil",
        "combat=true",
        "raid=true",
        "grouped=false",
        "grouped=Secret(true)",
        "raid=Secret(false)",
        "inside=false",
        "inside=Secret(true)",
        "kind=Secret('party')",
        "kind='raid'",
        "kind='scenario'",
        "kind='pvp'",
    )
    for setup in cases:
        lua=fixture()
        lua.execute('Member(Enum.PhaseReason.Sharding); '+setup)
        lua.execute(r'''
            local a=JP.InstanceAlert; a:Enable(); a:OnEvent('GROUP_JOINED')
            for i=1,15 do Tick() end
            assert(not a.source and not a.frame:IsShown() and not a.pending)
        ''')
    # A secret phase or visibility cannot dismiss an authoritative warning.
    lua=fixture()
    lua.execute(r'''
        local a=JP.InstanceAlert; a:Enable(); Member(Secret(0)); ownShard=true
        units.party1.visible=true; a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY'); Tick()
        assert(a.source=='event')
        units.party1.phase=nil; units.party1.visible=Secret(true); Tick(3)
        assert(a.source=='event')
        combat=true; a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY'); Tick(3)
        assert(a.source=='event','native event stays usable in combat')
        combat=false; units.party1.visible=true
        local exists=UnitExists
        UnitExists=function(unit) return unit=='party2' and Secret(true) or exists(unit) end
        Tick(3); assert(a.source=='event','unknown existence must not mean the entire party is present')
        UnitExists=exists; Tick(3); assert(not a.source)
    ''')


def test_loading_disable_preview_and_memory():
    lua=fixture()
    lua.execute(r'''
        local a=JP.InstanceAlert; a:Enable()
        a:OnEvent('PLAYER_LEAVING_WORLD'); assert(not a.pending)
        a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY'); Tick()
        assert(not a.pending and not a.frame:IsShown())
        a:OnEvent('PLAYER_ENTERING_WORLD'); Tick()
        assert(a.source=='event' and a.frame:IsShown())
        a:OnEvent('PLAYER_LEAVING_WORLD'); assert(not a.source and not a.pending)
        a:OnEvent('PLAYER_ENTERING_WORLD'); for i=1,15 do Tick() end
        assert(not a.source and not a.pending,'old copy must not carry into new visit')
        a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY'); a:OnEvent('GROUP_LEFT')
        assert(not a.source and not a.pending and not a.frame:IsShown())
        a:SetUnlocked(true); assert(a.frame:IsShown() and a.frame.mouse)
        assert(not a.source and not a.pending,'preview cannot create an alert or timer')
        a.frame.scripts.OnDragStart(); assert(a.frame.moving)
        a.frame.scripts.OnDragStop(); assert(db.instanceAlert.position)
        a:SetUnlocked(false); assert(not a.frame:IsShown() and not a.frame.mouse)
        a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY')
        db.convenience.warnDifferentInstance=false; a:ApplySettings()
        assert(not a.source and not a.pending and not a.frame:IsShown() and not next(a.events.events))
        a:SetUnlocked(true); assert(not a.frame:IsShown(),'disabled warning stays hidden in preview')
        a:SetUnlocked(false)
        local objects=allocations
        local weak=setmetatable({}, {__mode='v'})
        for i=1,1000 do
            db.convenience.warnDifferentInstance=true; a:Enable()
            a:OnEvent('ENTERED_DIFFERENT_INSTANCE_FROM_PARTY')
            weak[i]=a.pending
            assert(ActiveTimers()==1)
            a:Disable(); Tick()
            assert(not a.pending and not a.source and not a.frame:IsShown() and not next(a.events.events))
        end
        collectgarbage('collect')
        assert(not next(weak),'cancelled timer closures must be collectible')
        assert(allocations==objects and not a.frame.scripts.OnUpdate)
        a:Enable(); inside=false; a:OnEvent('ZONE_CHANGED_NEW_AREA'); Tick()
        local reads=phaseReads+visibilityReads
        for i=1,1000 do a:OnEvent('UNIT_PHASE'); a:OnEvent('GROUP_ROSTER_UPDATE') end
        assert(not a.pending and phaseReads+visibilityReads==reads,'no idle polling outside dungeons')
        db.instanceAlert.position={point='BROKEN',relativePoint='TOP',x=0,y=0}; a:Layout()
        assert(a.frame.points[1][1]=='TOP','bad saved position must fall back without changing the profile')
        db.instanceAlert.position={point='TOPLEFT',relativePoint='TOPLEFT',x=15,y=-90}; a:Layout()
        assert(a.frame.points[1][4]==15 and a.frame.points[1][5]==-90,'saved position is preserved')
        db.instanceAlert.position.x=Secret(15); a:Layout(); assert(a.frame.points[1][1]=='TOP')
    ''')


if __name__=='__main__':
    for test in (test_either_side_and_generic_phase,test_public_phase_does_not_require_map_data,
                 test_late_candidate_finishes_confirmation,test_native_notification,test_join_inside_and_resolution,
                 test_no_false_positives_or_secret_use,test_loading_disable_preview_and_memory):
        test(); print(test.__name__+': OK')
    code=source('Modules/InstanceAlert.lua')
    assert 'NewTicker' not in code and 'OnUpdate' not in code
    assert 'SendChatMessage' not in code and 'GetInstanceInfo(' not in code
    assert 'SetScript("OnUpdate"' not in code and 'UnitPosition(' not in code
    settings=source('Modules/SettingsHub.lua')
    assert 'JP.InstanceAlert:SetUnlocked(unlocked)' in settings
    assert 'JP.InstanceAlert:ApplySettings()' in settings
    assert 'warnDifferentInstance = true' in source('Core.lua')
    print('Instance warning: lifecycle, guards, lock and event-only boundaries OK')
