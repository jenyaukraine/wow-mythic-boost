"""Post-pull feed: delayed unlocks, combined key sessions and stale callback safety."""
from TestAvoidableDamage import fixture as meter_fixture
from TestHudPolish import source


def fixture():
    lua=meter_fixture()
    lua.execute(r'''
        autoFlush=false; spells={}; blocked=false; combat=false
        C_Spell.GetSpellInfo=function(id) return {name='Spell '..id,iconID=id} end
        C_DamageMeter.GetCombatSessionSourceFromType=function(session,typ,guid)
            assert(not combat and typ==8)
            if blocked then return Secret({}) end
            return {combatSpells=guid=='P1' and spells or {}}
        end
        function Totals(a,b)
            spells={{spellID=133,totalAmount=a},{spellID=116,totalAmount=b or 0}}
            Damage(a+(b or 0))
        end
        local created=0
        C_Timer.NewTimer=function(delay,fn)
            created=created+1
            local t={delay=delay,fn=fn}
            function t:Cancel() self.cancelled=true end
            timers[#timers+1]=t; return t
        end
        function TimerCount()
            local n=0; for _,t in ipairs(timers) do if not t.cancelled then n=n+1 end end
            return n
        end
        function Tick(seconds) now=now+(seconds or .5); Flush() end
        function Drain()
            local count=0
            while JP.AvoidableDamage.reportTimer do
                count=count+1; assert(count<=5,'fast retry phase must terminate')
                Tick(JP.AvoidableDamage.reportTimer.delay)
            end
        end
        function Start() combat=true; Fire('PLAYER_REGEN_DISABLED') end
        function Stop() combat=false; Fire('PLAYER_REGEN_ENABLED') end
        Totals(0); m=JP.AvoidableDamage; m:Enable(); Fire('CHALLENGE_MODE_START')
    ''')
    return lua


def test_every_pull_and_whole_key():
    lua=fixture()
    lua.execute(r'''
        local sum=0
        for pull=1,6 do
            Start(); assert(not m.frame.shown)
            sum=sum+pull*100; Totals(sum)
            Stop(); Drain()
            assert(m.lastReport.entries[1].amount==pull*100 and m.lastReport.complete)
            assert(m.frame.shown and not m.lastReport.key and not m.completed)
            assert(not m.awaitingReport and not m.reportTimer and not m.pullBaseline)
            assert(m.keySpells['P1:133'].amount==sum)
            local report=m.lastReport
            for i=1,100 do Fire('DAMAGE_METER_COMBAT_SESSION_UPDATED',8) end
            assert(TimerCount()==1,'meter event storm is one snapshot, not repeated reports')
            Tick(); assert(m.lastReport==report and m.keySpells['P1:133'].amount==sum)
        end
        Fire('CHALLENGE_MODE_COMPLETED'); Drain()
        assert(m.keyReport.key and m.lastReport==m.keyReport)
        assert(m.keyReport.entries[1].amount==sum and m.keyReport.players[1].amount==sum)
        assert(not m.awaitingReport and not m.reportTimer)
    ''')


def test_delayed_ui_unlock_and_late_meter():
    lua=fixture()
    lua.execute(r'''
        Start(); Totals(100)
        local before=reads
        -- The event is delivered before InCombatLockdown flips to false.
        Fire('PLAYER_REGEN_ENABLED'); Tick(.35)
        assert(m.reportTimer and reads==before and not m.frame.shown)
        combat=false; Drain()
        assert(m.lastReport.entries[1].amount==100 and m.frame.shown)
        -- Public source totals exist, but spell details remain secret for >7s.
        Start(); Totals(300); blocked=true; Stop(); Drain()
        assert(m.awaitingReport and not m.reportTimer and not m.lastReport.complete)
        assert(m.empty.shown and m.frame.shown)
        now=now+10; blocked=false
        Fire('DAMAGE_METER_COMBAT_SESSION_UPDATED',8)
        assert(m.reportTimer and TimerCount()<=2)
        Drain()
        assert(m.lastReport.complete and m.lastReport.entries[1].amount==200)
        assert(not m.awaitingReport and not m.reportTimer and m.frame.shown)
        local report=m.lastReport
        Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED'); Tick()
        assert(m.lastReport==report,'late event cannot play a successful report twice')
    ''')


def test_stale_empty_then_data_and_no_damage():
    lua=fixture()
    lua.execute(r'''
        -- Temporarily empty/unchanged totals are not a completed zero-damage pull.
        Start(); Stop(); Drain()
        assert(m.awaitingReport and not m.reportTimer and not m.frame.shown)
        now=now+10; Totals(450); Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED'); Drain()
        assert(m.lastReport.complete and m.lastReport.entries[1].amount==450)
        -- A genuinely clean next fight must not replay the previous cumulative 450.
        Start(); Stop(); Drain()
        assert(not m.frame.shown and not m.reportTimer)
        local deadline=m.reportDeadline
        now=deadline+1; Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED'); Tick()
        assert(not m.awaitingReport and not m.pullBaseline and not m.reportTimer)
        assert(not m.frame.shown and m.keySpells['P1:133'].amount==450)
    ''')


def test_baselines_and_roster_refresh():
    lua=fixture()
    lua.execute(r'''
        Start(); Totals(100); Stop()
        -- Native roster refresh may update key totals before the report callback.
        Fire('GROUP_ROSTER_UPDATE'); Drain()
        assert(m.lastReport.entries[1].amount==100)
        Start(); Totals(160,40); Stop(); Drain()
        assert(#m.lastReport.entries==2 and m.lastReport.entries[1].amount==60)
        assert(m.lastReport.entries[2].amount==40)
        Damage(0); spells={}; Fire('DAMAGE_METER_RESET')
        Start(); Totals(30); Stop(); Drain()
        assert(m.lastReport.entries[1].amount==30)
        assert(m.keySpells['P1:133'].amount==190)
        -- An addon enabled mid-fight cannot know that fight's starting totals.
        m:Disable(); Start(); blocked=true; m:Enable()
        Totals(500); blocked=false; Stop(); Drain()
        assert(m.awaitingReport and #m.lastReport.entries==0 and not m.lastReport.complete)
        Start(); Totals(600); Stop(); Drain()
        assert(m.lastReport.entries[1].amount==100,'unknown initial pull must not break all later pulls')
    ''')


def test_cancellation_scope_and_bounded_memory():
    lua=fixture()
    lua.execute(r'''
        local weak=setmetatable({}, {__mode='v'})
        local baselines=setmetatable({}, {__mode='v'})
        local built=allocations
        for i=1,1000 do
            Start(); blocked=true; Stop()
            weak[i]=m.reportTimer
            baselines[i]=m.pullBaseline
            local old=m.reportTimer
            Start(); assert(old.cancelled and not m.awaitingReport)
            old.fn() -- cancelled callback delivered late must not touch the new fight
            assert(not m.reportTimer and not m.lastReport)
            blocked=false; Totals(i); Stop(); Drain()
            -- There was no readable boundary after the cancelled pull: don't
            -- attribute both pulls to the second. Establish the next baseline.
            assert(m.frame.shown and #m.lastReport.entries==0 and m.awaitingReport)
        end
        collectgarbage('collect'); assert(not next(weak),'no retained report timers')
        assert(not next(baselines),'no retained baselines from cancelled pulls')
        assert(allocations==built and #m.rows==5,'reuse owned rows over repeated fights')
        Start(); Totals(1200); blocked=true; Stop(); Drain()
        inDungeon=false; Fire('PLAYER_ENTERING_WORLD'); blocked=false
        for i=1,1000 do Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED') end
        Tick(); assert(not m.frame.shown and not m.reportTimer and not m.snapshotTimer)
        assert(not m.awaitingReport and not m.pullBaseline)
        inDungeon=true; Fire('PLAYER_ENTERING_WORLD')
        Start(); Totals(1300); Stop(); local old=m.reportTimer
        m:Disable(); old.fn(); Tick()
        assert(old.cancelled and not m.frame.shown and not m.awaitingReport)
    ''')


def test_unread_previous_pull_is_not_misattributed():
    lua=fixture()
    lua.execute(r'''
        Start(); Totals(100); blocked=true; Stop(); Drain()
        assert(m.awaitingReport and not m.pullSnapshotReady)
        Start(); Totals(350); blocked=false; Stop(); Drain()
        assert(#m.lastReport.entries==0 and not m.lastReport.complete)
        assert(m.pullSnapshotReady and m.keySpells['P1:133'].amount==350)
        Start(); Totals(400); Stop(); Drain()
        assert(m.lastReport.complete and m.lastReport.entries[1].amount==50)
        assert(m.keySpells['P1:133'].amount==400,'key total still includes all confirmed public damage')
    ''')


def test_nil_lockdown_and_fail_closed():
    lua=fixture()
    lua.execute(r'''
        function InCombatLockdown() if combat then return 1 end end
        m:Disable(); m:Enable(); Fire('CHALLENGE_MODE_START')
        assert(not m:IsCombatLocked() and m.players.P1.spellSnapshotReady)
        for i=1,3 do
            Start(); local before=reads; Totals(i*100)
            Fire('PLAYER_REGEN_ENABLED'); Tick(.35)
            assert(reads==before and not m.frame.shown, 'numeric lockdown still blocks reads')
            Stop(); Drain()
            assert(m.lastReport.entries[1].amount==100 and m.frame.shown)
            m:UpdateFeed(); assert(m.frame.shown)
        end
        local before=reads
        InCombatLockdown=function() return Secret(false) end
        assert(m:IsCombatLocked()); m:Snapshot(); m:Render()
        assert(reads==before and not m.frame.shown)
        InCombatLockdown=function() error('lockdown API unavailable') end
        assert(m:IsCombatLocked()); m:Snapshot(); m:Render(); assert(reads==before)
        InCombatLockdown=nil; assert(m:IsCombatLocked())
    ''')


def test_one_missing_player_does_not_starve_feed():
    lua=fixture()
    lua.execute(r'''
        -- P2 has damage but no readable spells. P1's zero boundary is known.
        Start(); Damage(0,100); Stop(); Drain()
        assert(not m.spellSnapshotComplete and m.players.P1.spellSnapshotReady)
        assert(not m.players.P2.spellSnapshotReady)
        for pull=1,4 do
            Start(); Totals(pull*150); Damage(pull*150,100); Stop(); Drain()
            assert(m.frame.shown and #m.lastReport.entries==1)
            assert(m.lastReport.entries[1].guid=='P1' and m.lastReport.entries[1].amount==150)
            assert(not m.lastReport.complete, 'missing P2 details remain disclosed')
        end
        assert(m.keySpells['P1:133'].amount==600)
        -- Secret source identity prevents inferring a missing player's zero.
        overall[8].combatSources={Secret({})}
        m:UpdateKeySpells(); assert(not m.players.P1.spellSnapshotReady)
    ''')


def test_manual_diagnostic_is_readonly_and_secret_safe():
    lua=fixture()
    lua.execute(r'''
        local lines={}
        function JP:Print(s) lines[#lines+1]=s end
        function JP:GetVersion() return 'test' end
        local baseline=m.pullBaseline
        m:Diagnose(); assert(#lines==2 and lines[2]:find('spells=0',1,true))
        assert(m.pullBaseline==baseline and not m.lastReport and not m.reportTimer)
        Start(); local before=reads; m:Diagnose(); assert(#lines==3 and reads==before)
        combat=false; overall[8]=Secret({}); m:Diagnose()
        assert(lines[5]:find('sources=?',1,true))
        for _,line in ipairs(lines) do assert(not line:find('P1',1,true)) end
    ''')


if __name__=='__main__':
    for test in (test_every_pull_and_whole_key,test_delayed_ui_unlock_and_late_meter,
                 test_stale_empty_then_data_and_no_damage,test_baselines_and_roster_refresh,
                 test_cancellation_scope_and_bounded_memory,test_unread_previous_pull_is_not_misattributed,
                 test_nil_lockdown_and_fail_closed,test_one_missing_player_does_not_starve_feed,
                 test_manual_diagnostic_is_readonly_and_secret_safe):
        test(); print(test.__name__+': OK')
    module=source('Modules/AvoidableDamage.lua')
    assert 'NewTicker' not in module and 'COMBAT_LOG_EVENT_UNFILTERED' not in module
    assert 'SendChatMessage' not in module and 'SetCVar(' not in module
    print('Post-combat feed: 1000 lifecycles, delayed public data, no stale replay, dungeon-only OK')
