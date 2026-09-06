"""End-to-end RunHistory/RunStats/Reviews/PlayerNetwork data-boundary tests."""
from TestDungeonHUD import runtime, load


EPOCH = 1788580800


def integration_client():
    lua = runtime()
    lua.execute(rf'''
        epoch={EPOCH}; sent={{}}; timerList={{}}; afterCallback=nil; meterEnabled=true
        function time() return epoch+math.floor(now) end
        function date(fmt,value) return os.date(fmt or '%c',value or time()) end
        function GetNormalizedRealmName() return 'Realm' end
        function UnitFullName(u) local v=units[u]; return v and v.name,v and v.realm end
        function UnitGUID(u) local v=units[u]; return v and v.guid end
        function UnitClass(u) return 'Class', units[u] and units[u].classFile or 'MAGE' end
        function UnitGroupRolesAssigned(u) return units[u] and units[u].role or 'DAMAGER' end
        function UnitExists(u) return units[u]~=nil end
        function UnitIsUnit(a,b) return a==b end
        units={{}}
        units.player={{name='Alice',realm='Realm',guid='Player-Alice',role='DAMAGER',classFile='MAGE'}}
        units.party1={{name='Bob',realm='Realm',guid='Player-Bob',role='HEALER',classFile='PRIEST'}}
        function IsInRaid() return false end
        function IsInGroup(category) return category~=LE_PARTY_CATEGORY_INSTANCE end
        LE_PARTY_CATEGORY_INSTANCE='instance'
        function GetAverageItemLevel() return 0,0,0 end
        Enum.DamageMeterType={{DamageDone=1,HealingDone=2,AvoidableDamageTaken=3}}
        Enum.DamageMeterSessionType={{Overall=1}}
        C_CVar={{GetCVarBool=function() return meterEnabled end}}
        C_DamageMeter={{IsDamageMeterAvailable=function() return meterEnabled end,
            GetCombatSessionFromType=function(_,kind,meter)
                if not meterEnabled then return nil end
                local source=(meter==1 and 6000 or meter==2 and 3000 or 40)+(meterBoost or 0)
                return {{durationSeconds=meterDuration or 60,combatSources={{
                    {{sourceGUID='Player-Alice',totalAmount=source}},
                    {{sourceGUID='Player-Bob',totalAmount=source*2}},
                }}}}
            end}}
        C_Timer={{NewTicker=function(delay,fn)
            local t={{fn=fn,cancelled=false}}; function t:Cancel() self.cancelled=true end
            return t
        end,NewTimer=function(delay,fn)
            local t={{fn=fn,cancelled=false}}; function t:Cancel() self.cancelled=true end
            timerList[#timerList+1]=t; return t
        end,After=function(delay,fn) afterCallback=fn end}}
        registered={{}}; C_ChatInfo={{registered=registered,RegisterAddonMessagePrefix=function(prefix) registered[#registered+1]=prefix end,
            SendAddonMessage=function(prefix,msg,channel)
                assert(#msg<=255 and channel~='WHISPER' and channel~='GUILD')
                sent[#sent+1]={{prefix=prefix,msg=msg,channel=channel}}; return 0
            end}}
        JP.API.GetActiveChallenge=function() return {{mapID=399,level=12,startedAt=0}} end
        JP.API.GetChallengeMap=function() return {{name='Integration Dungeon',timeLimit=1800}} end
        JP.API.GetChallengeCompletion=function()
            return {{mapID=399,level=12,duration=60000,onTime=true,upgrades=2,
                members={{{{memberGUID='Player-Bob'}}}}}}
        end
        JP.API.GetChallengeDeaths=function() return {{count=1,timeLost=20}} end
    ''')
    # Load in TOC order; all modules are present before any module is enabled.
    for module in ("Modules/RunStats.lua", "Modules/RunHistory.lua", "Modules/Reviews.lua",
                   "Modules/PlayerNetwork.lua", "Modules/PlayerMemoryUI.lua", "Modules/ReviewsUI.lua"):
        load(lua, module)
    lua.execute(r'''
        -- The real UI is loaded before Enable. This small adapter is only for
        -- constructing PlayerMemory/Reviews windows in the headless fixture.
        UI.Panel=function(parent) return NewWidget(parent) end
        UI.Text=function(parent,_,value) local f=NewWidget(parent); f.text=value; return f end
        UI.Button=function(parent,text,w,h) local f=NewWidget(parent); f.text=text; f:SetSize(w,h); f.label=f; return f end
        UI.CheckBox=function(parent,text,checked,fn)
            local f=NewWidget(parent); f.text=text; f.checked=checked; f.toggle=fn
            function f:SetChecked(v) self.checked=v end
            return f
        end
        UI.NumberBox=function(parent,w,h)
            local f=NewWidget(parent); f.frame=NewWidget(parent); f:SetSize(w,h)
            function f:GetText() return self.text or '' end
            function f:SetText(v) self.text=v end
            function f:ClearFocus() end
            function f:SetNumeric(v) self.numeric=v end
            function f:SetMaxLetters(v) self.maxLetters=v end
            function f:SetJustifyH(v) self.justify=v end
            return f
        end
        UI.Tooltip=function() end
        UI.Unpack=table.unpack
        UI.colors.accent={.6,.5,.3,1}; UI.colors.muted={.5,.5,.5,1}; UI.colors.text={1,1,1,1}
        UI.colors.lineSoft={.2,.2,.2,1}; UI.colors.window={.02,.02,.02,1}; UI.colors.amber={1,.7,.2,1}
        UI.colors.green={.2,.9,.5,1}; UI.colors.red={.9,.3,.3,1}; UI.colors.faint={.4,.4,.4,1}
        GameTooltip_Hide=function() end
        h=JP.RunHistory; r=JP.Reviews; n=JP.PlayerNetwork
        h:Create(); n:Enable(); r:Enable(); h:Enable()
    ''')
    return lua


def test_real_run_finish_and_performance():
    lua = integration_client()
    lua.execute(r'''
        -- Completion contains Bob only: Alice was in the start roster but did
        -- not complete, and names are canonical same-realm values.
        h:StartRun(); assert(h.current and h.current.members[2].name=='Bob-Realm')
        meterDuration=60; meterBoost=0; JP.RunStats:Snapshot()
        meterDuration=65; meterBoost=3000; JP.RunStats:Snapshot()
        h:FinishRun(); local run=h.lastRun
        assert(run and #run.members==1 and run.members[1]=='Bob-Realm')
        assert(run.performance and run.performance['bob-realm'])
        assert(run.performance['bob-realm'].damage==6000 and run.combatStatsAvailable)
        assert(r.offerToken and afterCallback, 'completion must offer a local review')
        afterCallback(); assert(r.reviewRun==run)
    ''')

    # Thirty-run cap is enforced by the real Settings/RunHistory path.
    lua.execute(r'''
        for i=1,35 do h:StartRun(); h:FinishRun() end
        assert(#db.runHistory.runs==30)
        assert(db.runHistory.players['bob-realm'].runs==36)
        db.runHistory.runs[30].talentSample={sentinel='old sample'}
        h:StartRun(); h:FinishRun(); h:StartRun(); h:FinishRun()
        for _,old in ipairs(db.runHistory.runs) do
            assert(not (old.talentSample and old.talentSample.sentinel=='old sample'))
        end
    ''')


def test_partial_meter_disabled_and_local_review_updates():
    lua = integration_client()
    lua.execute(r'''
        meterEnabled=false; h:StartRun(true); h:FinishRun(); local partial=h.lastRun
        assert(partial.trackingPartial and not partial.combatStatsAvailable)
        local p=partial.performance['bob-realm']
        assert(p and p.damage==nil and p.healing==nil and p.itemLevel==nil)
        local before=#sent
        assert(r:Save('Bob-Realm',-1,'private negative local',partial,false))
        local own=r:GetOwn('Bob-Realm'); assert(own and own.vote==-1 and own.text=='private negative local')
        assert(#sent==before, 'local reviews must never use the network')
        -- A late native update changes only the exact local review/run pair.
        partial.performance['bob-realm'].damage=2222; partial.performance['bob-realm'].duration=60
        JP.RunStats:Validate(partial.performance['bob-realm'])
        r:UpdateRunStats(partial); assert(r:GetOwn('Bob-Realm').vote==-1)
        r:QueueRound(); assert(#r.outbox==0)
    ''')
    # Shared reviews carry negative marks, text and readonly performance too.
    # The explicitly local record above is a separate opt-out, not a filter
    # suppressing all negative reviews from the common database.
    lua.execute(r'''
        assert(r:Store({author='Stranger-Realm',target='Bob-Realm',stamp=time(),vote=-1,
            text='shared negative',shared=true,map=399,level=12,
            stats={version=1,runAt=time(),role='HEALER',healing=9000,damage=2000,
                avoidable=500,duration=60,itemLevel=300,complete=true}},'Bob-Realm',false))
        local rows=r:Get('Bob-Realm'); assert(#rows==2)
        local score,total,likes,dislikes=r:Rating('Bob-Realm'); assert(score==-2 and total==2 and dislikes==2)
        r:QueueRound(); local wire=table.concat(r.outbox,'\n')
        assert(wire:find('shared negative',1,true) and wire:find('S1,',1,true))
        assert(not wire:find('private negative local',1,true))
    ''')


def test_network_manual_positive_and_legacy_gossip_disabled():
    lua = integration_client()
    lua.execute(r'''
        local hasOld=false; for _,prefix in ipairs(registered) do if prefix=='MBReviews1' then hasOld=true end end
        assert(not hasOld, 'legacy review prefix must not be registered')
        local before=#sent; r:Receive('MBReviews1','legacy','PARTY','Bob-Realm'); assert(#sent==before)
        assert(not n:Recommend('Stranger-Realm',1))
        assert(n:Recommend('Bob-Realm',1)==false, 'recommendation requires local shared history')
        h:StartRun(); h:FinishRun()
        assert(n:Recommend('Bob-Realm',1))
        n:Manifest(); for _,packet in ipairs(n.outbox) do
            assert(packet:find('private',1,true)==nil and packet:find('negative',1,true)==nil)
            assert(not packet:find('DPS',1,true) and not packet:find('HPS',1,true)
                and not packet:find('ilvl',1,true))
        end
        -- Legacy negative foreign text is not a public network record.
        assert(not n:Recommend('Stranger-Realm',127))
        for i=1,10000 do n:Context('Unknown'..i..'-Realm'); r:Rating('Unknown'..i..'-Realm') end
        local indexed=0; for _ in pairs(n.byTarget or {}) do indexed=indexed+1 end
        assert(indexed<=1000)
    ''')


if __name__ == '__main__':
    for test in (test_real_run_finish_and_performance,
                 test_partial_meter_disabled_and_local_review_updates,
                 test_network_manual_positive_and_legacy_gossip_disabled):
        test()
        print(test.__name__ + ': OK')
