"""Per-fight reports, whole-key aggregation, explicit sharing and UI regressions."""
from TestAvoidableDamage import fixture
from TestHudPolish import load, source


def test_combat_reports():
    lua=fixture()
    lua.execute(r'''
        autoFlush=false; pulls={combatSources={}}; details={[0]={},[1]={}}
        local get=C_DamageMeter.GetCombatSessionFromType
        C_DamageMeter.GetCombatSessionFromType=function(session,typ)
            assert(not combat)
            if session==1 and typ==8 then return pulls end
            return get(session,typ)
        end
        C_DamageMeter.GetCombatSessionSourceFromType=function(session,typ,guid)
            assert(not combat and typ==8); return details[session][guid]
        end
        C_Spell.GetSpellInfo=function(id) return {name='Ability '..id,iconID=id} end
        function Spells(session,id,n)
            details[session].P1={combatSpells={{spellID=id,totalAmount=n,isAvoidable=true}}}
        end
        function Pull(id,n,total)
            combat=true; Fire('PLAYER_REGEN_DISABLED')
            Damage(total); pulls={combatSources={{sourceGUID='P1',totalAmount=n}}}
            Spells(1,id,n); Spells(0,id,total)
            combat=false; Fire('PLAYER_REGEN_ENABLED'); Flush()
        end
        m=JP.AvoidableDamage; m:Enable(); Fire('CHALLENGE_MODE_START')
        Pull(133,100,100)
        assert(m.lastReport.complete and #m.lastReport.entries==1 and m.rows[1].icon.texture==133)
        assert(m.rows[1].amount.text=='100' and m.frame.shown and m.frame.scripts.OnUpdate)
        Pull(133,200,300)
        assert(m.lastReport.entries[1].amount==200,'fight summary is not cumulative')
        for i=1,100 do Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED'); Flush() end
        assert(m.keySpells['P1:133'].amount==300,'meter events cannot duplicate key damage')
        m:UpdateKeySpells(); m:UpdateKeySpells(); assert(m.keySpells['P1:133'].amount==300)
        -- Native overall reset is a new baseline, not a subtraction from history.
        Damage(0); Fire('DAMAGE_METER_RESET'); Pull(133,50,50)
        Fire('CHALLENGE_MODE_COMPLETED'); Flush()
        assert(m.keyReport.key and m.keyReport.entries[1].amount==350 and m.keyReport.players[1].amount==350)
        assert(m.lastReport==m.keyReport and not m.reportExpires and m.reportView=='players')
        assert(not m.frame.scripts.OnUpdate,'final report stays until dismissed without ticker')
        local final=m.keyReport
        Fire('CHALLENGE_MODE_COMPLETED'); Flush(); assert(m.keyReport==final)
        m.close.scripts.OnClick(); assert(not m.frame.shown); assert(m:OpenKeyReport())
        -- Sharing is explicit, bounded and does not send localized ordinary text.
        sent={}; function IsInGroup() return true end; function IsInRaid() return false end
        C_ChatInfo.SendChatMessage=function(text,channel,language,target)
            assert(#text<=255 and text:sub(1,13)=='[MythicBoost]')
            sent[#sent+1]={text,channel,target}
        end
        assert(m:ShareReport('PARTY') and #sent==3 and sent[2][2]=='PARTY')
        assert(not m:ShareReport('PARTY') and #sent==3,'double-click cooldown')
        now=6; assert(not m:ShareReport('WHISPER','bad name'))
        assert(m:ShareReport('WHISPER','Friend-Realm') and sent[6][3]=='Friend-Realm')
        m.view.scripts.OnClick(); now=12
        assert(m:ShareReport('PARTY') and sent[8][1]:find('|Hspell:133',1,true))
        combat=true; assert(not m:ShareReport('PARTY')); combat=false
        local before=allocations
        for i=1,1000 do m:Render() end
        assert(allocations==before and #m.rows==5)
        m:Disable(); assert(not m.reportTimer and not m.snapshotTimer)
    ''')


def test_report_secrets_and_cancellation():
    lua=fixture()
    lua.execute(r'''
        m=JP.AvoidableDamage; m:Enable(); autoFlush=false
        Damage(100)
        C_DamageMeter.GetCombatSessionSourceFromType=function()
            return {combatSpells={{spellID=Secret(133),totalAmount=Secret(100),isAvoidable=Secret(true)}}}
        end
        combat=true; Fire('PLAYER_REGEN_DISABLED'); combat=false; Fire('PLAYER_REGEN_ENABLED')
        for i=1,5 do Flush() end
        assert(m.lastReport and not m.lastReport.complete and #m.lastReport.entries==0)
        assert(not m.reportTimer and m.empty.text=='Подробности по способностям недоступны')
        assert(m.frame.shown and m.empty.shown,'missing data is visible, not silent zero')
        now=now+16; m.frame.scripts.OnUpdate()
        assert(not m.frame.shown and not m.frame.scripts.OnUpdate)
        local before=reads; combat=true; Fire('PLAYER_REGEN_DISABLED'); Flush()
        assert(reads==before and not m.lastReport,'no old summary during next fight')
        combat=false; Fire('PLAYER_REGEN_ENABLED'); local pending=m.reportTimer
        m:Disable(); Flush(); assert(pending.cancelled and not m.frame.shown)
        m:Enable(); autoFlush=false
        combat=true; Fire('PLAYER_REGEN_DISABLED'); combat=false; Fire('PLAYER_REGEN_ENABLED')
        combat=true; Fire('PLAYER_REGEN_DISABLED'); Flush(); assert(not m.reportTimer)
        combat=false
    ''')


def test_loot_actions_and_timers():
    lua=fixture()
    lua.execute(r'''
        local methods=getmetatable(UIParent).__index
        function methods:SetEnabled(v) self.enabled=v end
        UI.colors.accent={.1,.8,1,1}; UI.colors.line={.1,.1,.1,1}
        function GetItemQualityColor() return .8,.2,1 end
        function JP:Print() end
        function RollOnLoot(id,kind) casts=(casts or 0)+1; castType=kind end
        db.lootUI={enabled=true,showRolls=true}
    ''')
    load(lua,'Modules/LootUI.lua')
    lua.execute(r'''
        local l=JP.LootUI; l.rollFrame=NewWidget(); l.rollRows={}; l.rolls={}
        for i=1,4 do l:BuildRollRow(i) end
        local built=allocations
        l.rolls[10]={rollID=10,name='Item',duration=292,deadline=292,quality=4,canNeed=true,canGreed=true,canDisenchant=false,canTransmog=true}
        l:RefreshRolls()
        local row=l.rollRows[1]
        assert(row.timer.text=='4:52' and row.height==60 and row.iconFrame.width==40)
        assert(row.choices[1].shown and not row.choices[3].shown and row.choices[5].shown)
        row.choices[5].scripts.OnClick(row.choices[5]); assert(casts==1 and castType==0)
        row.choices[1].scripts.OnClick(row.choices[1]); assert(casts==1,'pass=0 still blocks another selection')
        for i=1,1000 do l:RefreshRolls() end
        assert(allocations==built and row.selectionMade==0)
        for i=11,14 do l.rolls[i]={rollID=i,name='Expired',deadline=0,duration=1,quality=1} end
        now=300
        for i=1,3 do l:UpdateRollTimers(.1) end
        assert(not next(l.rolls),'expiry terminates even with more rolls than visible rows')
        l.rolls[-2147483647]={rollID=-2147483647,test=true,name='Preview',deadline=400,duration=100,quality=4,canNeed=true}
        l:RefreshRolls(); row=l.rollRows[1]
        C_Timer.After=function(_,fn) previewDone=fn end
        row.choices[1].scripts.OnClick(row.choices[1]); assert(casts==1,'preview never rolls loot')
        previewDone(); assert(not next(l.rolls))
    ''')


def test_guild_real_profile_path():
    lua=fixture()
    lua.execute(r'''
        UI.SafeTable=JP.SafeTable; UI.SafeString=JP.SafeString; UI.SafeBoolean=JP.SafeBoolean
        UI.UsableNumber=JP.UsableNumber or function(n) return JP.SafeNumber(n)~=nil end
        JP.Limits=JP.Limits or {ACTIVE_APPLICATIONS=5,PROFILE_CACHE_ENTRIES=128}
        function UI.Panel(p) return NewWidget(p) end
        function UI.ClassColor() return .3,.8,1 end
        for _,key in ipairs({'line','lineSoft','row','rowAlt','raised','faint'}) do UI.colors[key]={.1,.2,.3,1} end
        function UI.KeystoneScore(profile) return profile and profile.score end
        function IsInGuild() return true end
        function GetNumGuildMembers() return 1 end
        function GetGuildRosterInfo() return 'Musorila-Silvermoon-Silvermoon',nil,nil,90,nil,nil,nil,nil,true,nil,'MAGE' end
        function GetMaxLevelForPlayerExpansion() return 90 end
        function GetNormalizedRealmName() return 'Silvermoon' end
        function JP:Log() end
        profile={name='Musorila',realm='Silvermoon',mythicKeystoneProfile={score=3524,sortedDungeons={}}}
        local maps={588,584,586,587,585,399,250,249}
        for i,id in ipairs(maps) do profile.mythicKeystoneProfile.sortedDungeons[i]={dungeon={keystone_instance=id,name='English '..i},level=i+10,chests=2} end
        calls=0
        RaiderIO={GetProfile=function(name,realm)
            if name=='player' then return profile end
            calls=calls+1
            assert(realm==nil and name=='Musorila-Silvermoon-Silvermoon','no second malformed realm lookup')
            return profile
        end}
        JP.API.GetChallengeMap=function(id) return {name='Локальное '..id,icon=id} end
    ''')
    load(lua,'Modules/GroupSearchUI.lua'); load(lua,'Modules/GuildBoard.lua')
    lua.execute(r'''
        local g=JP.GuildBoard
        local entries=g:Collect(true)
        assert(#entries==1 and entries[1].fullName=='Musorila-Silvermoon' and entries[1].profile==profile)
        local row=NewWidget(); row.entry=entries[1]; g:ShowKeyTooltip(row)
        assert(g.keyTooltip.rows[8].value.text=='++18' and g.keyTooltip.rows[1].name.text=='Локальное 588')
        local built=allocations
        for i=1,100 do g:ShowKeyTooltip(row) end
        assert(calls==1 and allocations==built and profile.name=='Musorila' and profile.realm=='Silvermoon')
    ''')


def test_center_recovery():
    lua=fixture()
    load(lua,'Modules/Welcome.lua')
    lua.execute(r'''
        local w=JP.modules.Welcome; w.frame=NewWidget(); w.frame:SetSize(1000,650)
        db.window={width=1000,height=650}; db.healerMana={position={x=100,y=123}}
        w.setMaximized=function(value) assert(value==false); w.frame.maximized=false; db.window.maximized=false end
        w.frame.maximized=true; w.frame:SetPoint('LEFT',UIParent,'LEFT',-10000,10000)
        w:Center()
        assert(db.window.point=='CENTER' and db.window.x==0 and db.window.y==0 and w.frame.shown)
        assert(db.healerMana.position.x==100 and db.healerMana.position.y==123)
    ''')
    assert 'frame:SetClampedToScreen(false)' in source('Modules/Welcome.lua')


def test_headerless_feed_and_severity():
    lua=fixture()
    lua.execute(r'''
        local methods=getmetatable(UIParent).__index
        function methods:Hide()
            local was=self.shown; self.shown=false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        spellReads=0
        C_Spell.GetSpellInfo=function(id) spellReads=spellReads+1; return {name='Spell '..id,iconID=id} end
        m=JP.AvoidableDamage; m:Enable()
        local entries={}
        for i=1,12 do entries[i]={spellID=i,amount=i*100,name='Player',class='DRUID',healthRatio=i==1 and 1.5 or (i==2 and .6 or nil)} end
        m.lastReport={entries=entries,complete=true,created=now}; m.reportExpires=now+30; m:Render()
        assert(m.frame.shown and not m.title.shown and not m.brand.shown and not m.footer.shown)
        assert(not m.share.shown and not m.close.shown and m.done==nil and m.frame.background[4]==0 and m.frame.border[4]==0)
        assert(m.rows[1].shown and not m.rows[2].shown and m.rows[1].severity==3)
        local built=allocations; local read=reads
        now=.1; m.frame.scripts.OnUpdate()
        assert(m.rows[1].alpha>0 and m.rows[1].alpha<1 and m.rows[1].glow.alpha>0)
        now=3.2; m.frame.scripts.OnUpdate()
        assert(m.rows[1].record.spellID==1 and m.rows[2].record.spellID==2 and not m.rows[3].shown)
        assert(m.rows[2].severity==2 and m.rows[2].amount.color[2]==.40)
        now=14.6; m.frame.scripts.OnUpdate()
        assert(m.rows[1].record.spellID==1 and m.rows[5].record.spellID==5,'five cards stay readable for fifteen seconds')
        now=15.1; m.frame.scripts.OnUpdate()
        assert(m.rows[1].record.spellID==2,'cards expire individually in order')
        local clock=m.feedClock; local record=m.rows[1].record
        m.rows[1].hovered=true; now=now+2; m.frame.scripts.OnUpdate()
        assert(m.feedClock==clock and m.rows[1].record==record,'hover pauses the feed for reading a tooltip')
        m.rows[1].hovered=false
        for i=1,1000 do now=now+.05; if m.frame.scripts.OnUpdate then m.frame.scripts.OnUpdate() end end
        assert(not m.frame.shown and not m.frame.scripts.OnUpdate and not m.rows[1].record)
        m:Render(); assert(not m.frame.shown,'meter refresh must not replay an expired feed')
        assert(allocations==built and reads==read and spellReads<80,'fixed pool and no meter reads from animation')
        m.keyReport={key=true,complete=true,entries=entries,players={{name='Player',class='DRUID',amount=500,fatal=1}}}
        assert(m:OpenKeyReport() and m.title.shown and m.share.shown and m.frame.background[4]>0)
        assert(not m.frame.scripts.OnUpdate and m.rows[1].alpha==1 and not m.rows[1].accent.shown)
        m:SetUnlocked(true)
        assert(not m.title.shown and not m.footer.shown and m.done==nil and m.frame.background[4]==0)
        assert(m.rows[1].severity==3 and m.rows[2].severity==2 and m.rows[3].severity==1)
        m:SetUnlocked(false); assert(m.title.shown and m.share.shown,'key report returns after layout preview')
        m.keyReport=nil; m.reportExpires=nil
        local weak=setmetatable({},{__mode='v'})
        for i=1,500 do
            local report={entries={{spellID=133,amount=100,name='Player'}},complete=true,created=now}
            weak[i]=report; m.lastReport=report; m:Render()
            now=now+16; m.frame.scripts.OnUpdate()
        end
        m.lastReport=nil; m:Render(); collectgarbage('collect'); collectgarbage('collect')
        assert(next(weak)==nil and allocations==built,'expired/replaced feeds cannot accumulate')
        m:Disable(); assert(not m.frame.scripts.OnUpdate)
    ''')


def test_severity_uses_only_public_matching_health():
    lua=fixture()
    lua.execute(r'''
        m=JP.AvoidableDamage; m:Enable()
        local get=C_DamageMeter.GetCombatSessionFromType
        C_DamageMeter.GetCombatSessionFromType=function(session,typ)
            if session==1 then return {combatSources={{sourceGUID='P1',totalAmount=600}}} end
            return get(session,typ)
        end
        C_DamageMeter.GetCombatSessionSourceFromType=function() return {combatSpells={{spellID=133,totalAmount=600,isAvoidable=true}}} end
        local health=1000
        function UnitHealthMax() assert(not combat); return health end
        local report=m:ReadCombatReport(); assert(report.entries[1].healthRatio==.6)
        health=Secret(1000); report=m:ReadCombatReport()
        assert(report.entries[1].healthRatio==nil and report.complete,'secret health does not invalidate public damage')
        health=0; assert(m:ReadCombatReport().entries[1].healthRatio==nil)
        health=1000; units.player.guid='NEW'
        assert(m:ReadCombatReport().entries[1].healthRatio==nil,'never normalize against another unit')
        combat=true; assert(m:ReadCombatReport()==nil)
    ''')


def test_continuous_key_report_scroll():
    lua=fixture()
    lua.execute(r'''
        m=JP.AvoidableDamage; m:Enable()
        C_Spell.GetSpellInfo=function(id) return {name='Ability '..id,iconID=id} end
        local entries={}
        for i=1,512 do entries[i]={guid='P1',spellID=i,amount=i,name='Player',class='DRUID'} end
        m.keyReport={key=true,complete=true,entries=entries,players={{guid='P1',name='Player',amount=512,fatal=0}}}
        m:OpenKeyReport()
        assert(m.reportView=='players' and not m.scrollBar.shown)
        assert(m.previous==nil and m.next==nil,'key report has no page buttons')
        m.view.scripts.OnClick()
        assert(m.reportView=='spells' and m.scrollBar.high==507 and m.scrollBar.shown)
        assert(m.rows[1].record.spellID==1 and m.rows[5].record.spellID==5)
        local built=allocations
        m.rows[3].scripts.OnMouseWheel(m.rows[3],-1)
        assert(m.reportOffset==1 and m.rows[1].record.spellID==2 and m.rows[5].record.spellID==6)
        assert(m.footer.text:find('2-6 / 512',1,true))
        for i=1,1000 do m.frame.scripts.OnMouseWheel(m.frame,-1) end
        assert(m.reportOffset==507 and m.rows[5].record.spellID==512)
        m.scrollBar:SetValue(200)
        assert(m.reportOffset==200 and m.rows[1].record.spellID==201)
        sent={}; function IsInGroup() return true end; function IsInRaid() return false end
        C_ChatInfo.SendChatMessage=function(text,channel) sent[#sent+1]=text end
        assert(m:ShareReport('PARTY') and #sent==6)
        assert(sent[1]:find('[201-205/512]',1,true))
        assert(sent[2]:find('|Hspell:201',1,true) and sent[6]:find('|Hspell:205',1,true))
        m.view.scripts.OnClick()
        assert(m.reportOffset==0 and m.reportView=='players' and not m.scrollBar.shown)
        m.view.scripts.OnClick()
        for i=1,1000 do m:SetReportOffset(i%508) end
        assert(allocations==built and #m.rows==5 and not m.frame.scripts.OnUpdate,'scrolling reuses five rows')
        combat=true; local offset=m.reportOffset; m:SetReportOffset(0)
        assert(m.reportOffset==offset); m:Render(); assert(not m.scrollBar.shown)
        combat=false; m:SetUnlocked(true)
        assert(not m.scrollBar.shown and not m.frame.mouseWheel and not m.rows[1].mouseWheel)
        m:SetReportOffset(10); assert(m.reportOffset==offset,'preview cannot scroll the summary')
        m:SetUnlocked(false); m.keyReport.entries={}
        m:Render(); assert(m.reportOffset==0 and not m.scrollBar.shown and m.empty.shown)
        m:Disable(); assert(not m.frame.shown and not m.reportTimer)
    ''')


def test_empty_share_is_local_only():
    lua=fixture()
    lua.execute('''
        local m=JP.AvoidableDamage; m:Enable()
        sent={}; function IsInGroup() return true end; function IsInRaid() return false end
        C_ChatInfo.SendChatMessage=function(text) sent[#sent+1]=text end
        m.reportView='players'
        m.lastReport={key=true,complete=false,entries={},players={
            {name='A',known=false,amount=0,fatal=0}, {name='B',known=false,amount=0,fatal=0}}}
        local ok,reason=m:ShareReport('PARTY')
        assert(not ok and reason and #sent==0 and not m.lastShare)
        m.lastReport.players[2].known=true
        assert(m:ShareReport('PARTY') and #sent==2 and not sent[2]:find('unknown',1,true))
        now=6; sent={}; m.lastReport.players={}; m.lastReport.complete=true
        assert(m:ShareReport('PARTY') and #sent==2,'confirmed zero remains shareable')
    ''')


if __name__=='__main__':
    for test in (test_combat_reports,test_report_secrets_and_cancellation,test_loot_actions_and_timers,
                 test_guild_real_profile_path,test_center_recovery,test_headerless_feed_and_severity,
                 test_severity_uses_only_public_matching_health,test_continuous_key_report_scroll,
                 test_empty_share_is_local_only):
        test(); print(test.__name__+': OK')
