"""Native avoidable-damage HUD: model, isolation and owned-frame lifecycle.

Executable mocks cannot certify live Midnight meter availability/taint.
"""
from TestDungeonHUD import runtime
from TestHudPolish import load, source


def fixture():
    lua = runtime()
    lua.execute(r'''
        UI.colors.accent={.1,.8,1,1}
        function UI.ClassIcon(c) return c or '' end
        function UI.Button(parent,label,w,h)
            local f=NewWidget(parent); f:SetSize(w,h); f.label=UI.Text(f,nil,label); return f
        end
        local methods=getmetatable(UIParent).__index
        function methods:HookScript(key,fn)
            local prior=self.scripts[key]
            self.scripts[key]=function(...)
                if prior then prior(...) end
                fn(...)
            end
        end
        function methods:SetChecked(value) self.checked=value end
        function methods:IsMouseOver() return self.hovered==true end
        function methods:EnableMouseWheel(value) self.mouseWheel=value end
        function methods:SetOrientation(value) self.orientation=value end
        function methods:SetThumbTexture(value) self.thumb=value end
        function methods:SetValueStep(value) self.valueStep=value end
        function methods:SetObeyStepOnDrag(value) self.obeyStep=value end
        local setValue=methods.SetValue
        function methods:SetValue(value)
            local old=self.value; setValue(self,value)
            if self.orientation and old~=value and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end
        end
        UI.colors.field={.1,.1,.1,1}
        function UI.Backdrop() end
        function UnitClass(u) return 'Class',units[u].class or 'DRUID' end
        zone=1; inDungeon=true; available=true; recording=true; reads=0
        function IsInInstance() return inDungeon,inDungeon and 'party' or 'none' end
        function GetInstanceInfo() return 'Dungeon',nil,nil,nil,nil,nil,nil,zone end
        units={player={name='Me',guid='P1'},party1={name='Other',guid='P2'}}
        Enum.DamageMeterSessionType={Overall=0,Current=1}
        Enum.DamageMeterType={AvoidableDamageTaken=8,Deaths=9,DamageTaken=7}
        overall={[8]={combatSources={}},[9]={combatSources={}}}
        history={}; sessions={}; recaps={}
        C_DamageMeter={
            IsDamageMeterAvailable=function() return available end,
            GetCombatSessionFromType=function(_,typ)
                assert(not combat); reads=reads+1; return overall[typ]
            end,
            GetAvailableCombatSessions=function() return sessions end,
            GetCombatSessionFromID=function(id,typ)
                assert(typ==9); reads=reads+1; return history[id] or {combatSources={}}
            end,
            ResetAllCombatSessions=function() error('native meter must not be reset') end,
        }
        C_CVar={GetCVarBool=function(key) assert(key=='damageMeterEnabled'); return recording end,
            SetCVar=function() error('no global CVar changes') end}
        C_DeathRecap={GetRecapEvents=function(id) return recaps[id] end}
        function SendChatMessage() error('no chat') end
        C_ChatInfo={SendChatMessage=SendChatMessage,SendAddonMessage=SendChatMessage}
        timers={}; autoFlush=true
        C_Timer={NewTicker=function() error('no ticker') end,After=function() error('no After') end,
            NewTimer=function(delay,fn)
                local t={fn=fn}; function t:Cancel() self.cancelled=true end
                timers[#timers+1]=t; return t
            end}
        function Flush()
            local pending=timers; timers={}
            for _,t in ipairs(pending) do if not t.cancelled then t.fn() end end
        end
        function Damage(a,b)
            overall[8]={combatSources={{sourceGUID='P1',totalAmount=a},{sourceGUID='P2',totalAmount=b or 0}}}
        end
        function Death(id,guid)
            return {sourceGUID=guid or 'P1',deathRecapID=id}
        end
        function Fire(event,...)
            JP.AvoidableDamage.events.scripts.OnEvent(nil,event,...)
            if autoFlush then Flush() end
        end
    ''')
    ui_source=source('UI.lua')
    scrollbar=ui_source.split('function UI.ScrollBar',1)[1].split('function UI.Tooltip',1)[0]
    wheel=ui_source.split('function UI.BindScrollWheel',1)[1].split('function UI.WeakKeys',1)[0]
    lua.execute('local C,Unpack=UI.colors,table.unpack\nfunction UI.ScrollBar'+scrollbar)
    lua.execute('function UI.BindScrollWheel'+wheel)
    load(lua, 'Modules/AvoidableDamage.lua')
    load(lua, 'Modules/AvoidableDamageUI.lua')
    return lua


def test_scoping_and_damage():
    lua = fixture()
    lua.execute(r'''
        Damage(900,200); m=JP.AvoidableDamage; m:Enable()
        assert(db.avoidableDamage.enabled and not m.frame.shown, 'no empty scoreboard before combat')
        assert(m.players.P1.amount==0 and m.players.P2.amount==0, 'exclude old fights')
        Damage(1000,225); Fire('DAMAGE_METER_COMBAT_SESSION_UPDATED',8)
        assert(m.players.P1.amount==100 and m.players.P2.amount==25)
        for i=1,30 do Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED') end
        assert(m.players.P1.amount==100,'repeated cumulative snapshots must not add twice')
        local before=reads; combat=true; Damage(1500,450); Fire('PLAYER_REGEN_DISABLED')
        for i=1,100 do Fire('DAMAGE_METER_COMBAT_SESSION_UPDATED',8) end
        assert(reads==before and m.players.P1.amount==100 and m.stale)
        combat=false; Fire('PLAYER_REGEN_ENABLED')
        assert(m.players.P1.amount==600 and not m.stale)
        Fire('CHALLENGE_MODE_START'); assert(m.players.P1.amount==0 and m.scope=='key')
        Damage(0); Fire('DAMAGE_METER_RESET')
        Damage(300); Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==300)
        Damage(0); Fire('DAMAGE_METER_RESET')
        Damage(50); Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==350)
        Damage(20); Fire('PLAYER_REGEN_ENABLED')
        assert(m.players.P1.amount==350 and m.partial,'unannounced decrease is not fabricated damage')
        Damage(40); Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==370)
        Fire('CHALLENGE_MODE_COMPLETED'); assert(m.completed)
        combat=true; Fire('PLAYER_REGEN_DISABLED'); combat=false; Damage(999)
        Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==370,'freeze before post-key fights')
        inDungeon=false; Fire('PLAYER_ENTERING_WORLD'); assert(not m.frame.shown)
        inDungeon=true; zone=2; Fire('PLAYER_ENTERING_WORLD')
        assert(m.players.P1.amount==0 and not m.completed)
        units.party2={name='New',guid='P3'}
        overall[8].combatSources[3]={sourceGUID='P3',totalAmount=10000}
        Fire('GROUP_ROSTER_UPDATE'); assert(m.players.P3.amount==0,'new party member needs baseline')
    ''')


def test_confirmed_deaths():
    lua = fixture()
    lua.execute(r'''
        overall[9]={combatSources={Death(10)}}
        recaps[10]={{avoidable=true}}
        m=JP.AvoidableDamage; m:Enable()
        assert(m.players.P1.fatal==0,'old deaths are baseline, not this dungeon')
        overall[9]={combatSources={Death(10),Death(11),Death(12,'P2'),Death(13)}}
        sessions={{sessionID=44}}; history[44]=overall[9]
        -- Native recap index 1 is the killing blow. No causedDeath field is
        -- present until Blizzard UI adds it to its own display provider.
        recaps[11]={{avoidable=false},{avoidable=true,deadly=true}}
        recaps[12]={{avoidable=true},{avoidable=true}}
        -- 13 arrives late, and must not be counted as zero/fatal yet.
        Fire('PLAYER_REGEN_ENABLED')
        assert(m.players.P1.fatal==0 and m.players.P1.deathUnknown)
        assert(m.players.P2.fatal==1,'two flagged events still describe one death')
        assert(m.players.P1.deathUnknown)
        recaps[13]={Secret('killing blow')}
        Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.fatal==0)
        recaps[13]={{avoidable=true}}
        Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.fatal==1)
        for i=1,20 do Fire('DAMAGE_METER_COMBAT_SESSION_UPDATED',9) end
        assert(m.players.P1.fatal==1 and m.players.P2.fatal==1,'dedupe across sessions and updates')
        overall[9].combatSources[5]=Death(14)
        recaps[14]={{deadly=true,amount=1000000,overkill=999}}
        Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.fatal==1,'danger flag/overkill not proof of death')
        recaps[14]={{avoidable=Secret(true)}}
        Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.fatal==1)
        recaps[14]={{avoidable=false}}
        Fire('PLAYER_REGEN_ENABLED'); assert(not m.players.P1.deathUnknown)
        m:MeterReset(); Fire('PLAYER_REGEN_ENABLED')
        assert(m.players.P1.fatal==1,'native reset must not repeat retained recaps')
    ''')


def test_unknown_and_lifecycle():
    lua = fixture()
    lua.execute(r'''
        m=JP.AvoidableDamage; combat=true; m:Enable()
        assert(m.partial and not m.players.P1.known,'load in combat is partial, not zero')
        combat=false; overall[8]=Secret('session'); overall[9]=Secret('deaths')
        Fire('PLAYER_REGEN_ENABLED'); assert(not m.players.P1.known)
        overall[8]={combatSources={Secret('source'),{sourceGUID=Secret('P1'),totalAmount=Secret(200)}}}
        Fire('PLAYER_REGEN_ENABLED'); assert(not m.players.P1.known)
        Damage(800); overall[9]={combatSources={}}
        Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==0 and m.players.P1.known)
        Damage(900); Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==100)
        recording=false; Fire('PLAYER_REGEN_ENABLED'); assert(m.unavailable)
        recording=true; Fire('PLAYER_REGEN_ENABLED'); assert(not m.unavailable)
        local old=allocations
        for i=1,200 do Fire('PLAYER_REGEN_ENABLED'); m:Render() end
        assert(allocations==old and #m.rows==5,'fixed pool, no redraw allocations')
        assert(not m.events.scripts.OnUpdate)
        assert(not m.frame.scripts.OnUpdate or (m.lastReport and m.reportExpires and m.frame.shown), 'animation only for a visible report')
        m:SetUnlocked(true); assert(#m.rows==5 and m.frame.mouseClicks and m.frame.height==132)
        assert(not m.footer.shown and not m.title.shown and m.frame.background[4]==0)
        m.frame.points={{'LEFT',UIParent,'LEFT',80,25}}
        m.frame.scripts.OnDragStop()
        assert(db.avoidableDamage.position.x==80)
        m:ShowHelp(); local help=m.tooltip; local count=allocations
        m:ShowHelp(); assert(m.tooltip==help and allocations==count)
        m:Disable(); assert(not m.frame.shown and next(m.events.events)==nil and not help.shown)
        local before=reads; Fire('PLAYER_REGEN_ENABLED'); assert(reads==before)
        db.avoidableDamage.enabled=false; m:Enable(); assert(not m.running)
        db.avoidableDamage.enabled=true; m:Enable(); assert(allocations==count)
        m:SetUnlocked(false); assert(not m.frame.mouseClicks)
        -- Bounded identity/recap caches fail closed, not by evicting dedupe IDs.
        m.recapCount=512; overall[9].combatSources={Death(999)}
        recaps[999]={{avoidable=true}}
        Fire('PLAYER_REGEN_ENABLED'); assert(m.partial and not m.recaps[999])
    ''')


def test_settings_preview():
    lua = fixture()
    # Exercise the settings action itself, rather than calling the HUD method
    # directly. Both entry points (checkbox and button) share this route.
    settings_methods = source('Modules/SettingsHub.lua').split(
        'function SettingsHub:SetInterfaceUnlocked(value)', 1)[1].split(
        'function SettingsHub:Build(', 1)[0]
    lua.execute('''
        JP.SettingsHub={checks={interfaceUnlocked=NewWidget()},GetSettings=function() return {} end}
        local SettingsHub=JP.SettingsHub
        function SettingsHub:SetInterfaceUnlocked(value)
    ''' + settings_methods)
    lua.execute(r'''
        m=JP.AvoidableDamage; inDungeon=false; units={}; available=false
        db.avoidableDamage={enabled=false}; m:Enable()
        local before=reads
        assert(JP.SettingsHub:PreviewAvoidableDamage())
        assert(m.preview and m.frame.shown and m.frame.strata=='DIALOG')
        assert(m.done==nil and not m.brand.shown and m.rows[3].shown and not m.rows[4].shown,
            'layout uses the global lock, without a duplicate Done button')
        assert(m.rows[1].amount.text=='1.28M' and m.rows[1].record.spellID==133)
        assert(db.avoidableDamage.enabled==false and reads==before and not m.running)
        assert(db.interfaceUnlocked and JP.SettingsHub.checks.interfaceUnlocked.checked)
        m.frame.scripts.OnDragStart()
        assert(m.dragging and m.frame.moving)
        m.frame.points={{'LEFT',UIParent,'LEFT',147,63}}
        for i=1,50 do m:Render() end
        assert(m.frame.points[1][4]==147,'updates must not reset a moving anchor')
        m.frame.scripts.OnDragStop()
        assert(not m.dragging and not m.frame.moving)
        assert(db.avoidableDamage.position.x==147 and db.avoidableDamage.position.y==63)
        JP.SettingsHub:SetInterfaceUnlocked(false)
        assert(not m.frame.shown and not m.preview and m.frame.strata=='MEDIUM')
        assert(not db.interfaceUnlocked and not JP.SettingsHub.checks.interfaceUnlocked.checked)
        assert(not db.avoidableDamage.enabled and reads==before)
        local count=allocations
        for i=1,100 do JP.SettingsHub:PreviewAvoidableDamage(); JP.SettingsHub:SetInterfaceUnlocked(false) end
        assert(allocations==count,'preview must reuse its row/button pool')
        JP.SettingsHub:PreviewAvoidableDamage()
        m.frame.scripts.OnDragStart(); m.frame.points={{'LEFT',UIParent,'LEFT',222,44}}
        JP.SettingsHub:SetInterfaceUnlocked(false)
        assert(db.avoidableDamage.position.x==222 and not m.dragging,'the global lock also finishes an active drag')
        combat=true; assert(not JP.SettingsHub:PreviewAvoidableDamage() and not m.preview)
        combat=false; db.avoidableDamage.enabled=true; inDungeon=true
        units={player={name='Me',guid='P1'}}; available=true; Damage(100); m:Enable()
        Damage(600); Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==500)
        JP.SettingsHub:PreviewAvoidableDamage(); assert(m.rows[1].amount.text=='1.28M')
        Damage(800); Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==700)
        JP.SettingsHub:SetInterfaceUnlocked(false)
        assert(not m.frame.shown and m.players.P1.amount==700,'real data survives the demonstration')
        m:Disable(); m:Enable()
        assert(db.avoidableDamage.position.x==222 and m.frame.points[1][4]==222)
    ''')


if __name__ == '__main__':
    test_scoping_and_damage()
    test_confirmed_deaths()
    test_unknown_and_lifecycle()
    test_settings_preview()
    model = source('Modules/AvoidableDamage.lua')
    assert 'SendChatMessage' not in model and 'SendAddonMessage' not in model
    print('Avoidable damage: scoping, public snapshots, resets, fatal confirmation, dedupe, secrets, settings and HUD lifecycle passed')
