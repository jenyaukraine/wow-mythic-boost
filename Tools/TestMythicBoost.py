"""Executable smoke tests for the MythicBoost decision and history logic.

Run with a Python environment containing ``lupa``::

    python -m pip install lupa
    python Tools/TestMythicBoost.py

The harness loads the real Lua sources with a deliberately small WoW API stub.
It catches return-position, false/nil, application-capacity, rejected-result,
role-package and run-completion regressions that a syntax parser cannot see.
"""

from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError as error:
    raise SystemExit("Install the test dependency first: python -m pip install lupa") from error


ROOT = Path(__file__).resolve().parents[1]


def load(lua: LuaRuntime, relative: str, jp):
    source = (ROOT / relative).read_text(encoding="utf-8")
    loader = lua.eval("function(code, jp) return assert(load(code))('MythicBoost', jp) end")
    loader(source, jp)


def test_completion_api():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
        C_Timer={After=function() end}; C_AddOns={}; C_ChallengeMode={}; SlashCmdList={}
        function time() return 100000 end; function date() return '' end
    """)
    jp = lua.table()
    jp.L = lambda text: text
    load(lua, "MythicBoost/Contracts.lua", jp)
    load(lua, "MythicBoost/Core.lua", jp)

    lua.execute("""C_ChallengeMode={GetChallengeCompletionInfo=function() return {
        mapChallengeModeID=777, level=12, time=123456, onTime=true,
        keystoneUpgradeLevels=2, practiceRun=false,
        members={{memberGUID='Player-1',name='A'}}} end}""")
    info = jp.GetChallengeCompletionData(jp)
    assert (info.mapID, info.level, info.duration, info.onTime) == (777, 12, 123456, True)
    assert (info.upgrades, info.practiceRun, info.members[1].memberGUID) == (2, False, "Player-1")

    lua.execute("C_ChallengeMode={GetCompletionInfo=function() return 888,9,98765,false,1,true end}")
    info = jp.GetChallengeCompletionData(jp)
    assert (info.mapID, info.level, info.duration, info.onTime) == (888, 9, 98765, False)
    assert (info.upgrades, info.practiceRun) == (1, True)

    lua.execute("""C_ChallengeMode={GetChallengeCompletionInfo=function() return nil end,
        GetCompletionInfo=function() return 999,7,50000,true,0,false end}""")
    info = jp.GetChallengeCompletionData(jp)
    assert (info.mapID, info.level, info.onTime) == (999, 7, True)

    lua.execute("""C_ChallengeMode={GetActiveChallengeMapID=function() return 321 end,
        GetActiveKeystoneInfo=function() return 14,{1,2},false end,
        GetStartTime=function() return 456 end, IsChallengeModeActive=function() return true end}""")
    active = jp.API.GetActiveChallenge()
    assert (active.mapID, active.level, active.startedAt, active.active) == (321, 14, 456, True)

    # Updating an existing record must not defeat the 300-player runtime cap.
    for index in range(1, 301):
        jp.MarkPositivePlayer(jp, f"Player{index}-Realm", lua.table(score=index), False)
    jp.MarkPositivePlayer(jp, "Player1-Realm", lua.table(score=9999), False)
    jp.MarkPositivePlayer(jp, "Player301-Realm", lua.table(score=301), False)
    assert len(jp.positivePlayerOrder) == 300
    assert jp.positivePlayers["player1-realm"] is None
    assert sum(1 for key, _ in jp.positivePlayers.items() if "-" in str(key)) == 300


def test_safe_defaults():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        function time() return 100000 end; function date() return '' end
        C_Timer={After=function() end}; C_AddOns={}; C_ChallengeMode={}; C_MythicPlus={}; SlashCmdList={}
        coreEvents=nil
        function CreateFrame()
            local f={}
            function f:RegisterEvent() end
            function f:SetScript(kind, callback) if kind=='OnEvent' then coreEvents=callback end end
            return f
        end
    """)
    jp = lua.table()
    jp.L = lambda text: text
    load(lua, "MythicBoost/Contracts.lua", jp)
    load(lua, "MythicBoost/Core.lua", jp)

    lua.execute("MythicBoostDB={}; coreEvents(nil,'ADDON_LOADED','MythicBoost')")
    db = lua.globals().MythicBoostDB
    assert db.search.showRejectedResults is True
    assert db.search.allowRejectedApplications is True
    assert db.playerAnalysis.enabled is True and db.playerAnalysis.nameplateMarkers is True
    assert db.groupFilters.runsMin == 0
    assert db.convenience.autoKeystone is True
    for key in ("autoQuests", "summon", "resurrection", "sellJunk", "repair", "whisperInvite"):
        assert db.convenience[key] is False
    assert db.minimalUI is True and db.minimalUIOptions.hideStanceBar is True
    assert db.unitFrames.enabled is True
    assert (db.unitFrames.scale, db.unitFrames.opacity) == (1.5, 1)
    assert db.unitFrames.showHealthText is True and db.unitFrames.showPowerText is True
    assert db.unitFrames.animatedPortrait is True and db.unitFrames.showBadges is True
    assert db.unitFrames.showPlayerAuras is True and db.unitFrames.showTargetAuras is True
    assert db.unitFrames.alwaysShowTarget is True and db.unitFrames.aurasAbove is True
    assert db.unitFrames.showResourcePips is True and db.unitFrames.showEmptyResources is False
    assert (db.unitFrames.resourceHeight, db.unitFrames.resourceGap, db.unitFrames.resourceOpacity) == (10, 2, 1)
    assert db.castBar.enabled is True
    assert db.lootUI.enabled is True
    assert db.smartClick.buff is False and db.smartClick.res is False
    assert db.rcLoot.enabled is False and db.errorGuard.enabled is False
    assert db.errorGuard.stabilityPrunedRevision == 4

    # A non-empty legacy profile with no HUD keys must not be taken over by an
    # update. The same visual defaults above are reserved for genuinely fresh
    # users, while explicit settings remain untouched below.
    lua.execute("""MythicBoostDB={scannedPlayers={Legacy=true}};
        coreEvents(nil,'ADDON_LOADED','MythicBoost')""")
    db = lua.globals().MythicBoostDB
    assert db.minimalUI is False and db.minimalUIOptions.minimap is False
    assert db.unitFrames.enabled is False and db.unitFrames.hideBlizzard is False
    assert db.castBar.enabled is False and db.lootUI.enabled is False
    assert db.convenience.hideBags is False

    # Explicit choices survive initialization, while the old automatically
    # raised leader-run threshold is migrated away once.
    lua.execute("""MythicBoostDB={minimumKeystoneRuns=23,groupFilters={runsMin=23},
        convenience={autoQuests=true},unitFrames={enabled=true,scale=.85,showResourcePips=false},castBar={enabled=true},
        lootUI={enabled=true},smartClick={buff=true,res=true},rcLoot={enabled=true},
        errorGuard={enabled=true}}; coreEvents(nil,'ADDON_LOADED','MythicBoost')""")
    db = lua.globals().MythicBoostDB
    assert db.groupFilters.runsMin == 0 and db.minimumKeystoneRuns == 0
    assert db.convenience.autoQuests is True
    assert db.unitFrames.enabled is True and db.castBar.enabled is True and db.lootUI.enabled is True
    assert db.unitFrames.scale == .85 and db.unitFrames.showResourcePips is False
    assert db.smartClick.buff is True and db.rcLoot.enabled is True and db.errorGuard.enabled is True

    # The dedicated capsule move toggle survives reload independently from the
    # global "move all interface elements" action introduced in older builds.
    lua.execute("""MythicBoostDB={interfaceUnlockRevision=2,interfaceUnlocked=false,
        convenience={movableKeystoneFrame=false},unitFrames={unlocked=true},castBar={unlocked=false}};
        coreEvents(nil,'ADDON_LOADED','MythicBoost')""")
    db = lua.globals().MythicBoostDB
    assert db.unitFrames.unlocked is True and db.castBar.unlocked is False
    assert db.interfaceUnlocked is True


def test_raid_repair_total_resets_after_leaving_instance():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        inRaid=true; repairCost=100; messages={}; repairs=0
        function issecretvalue(_) return false end
        function IsInInstance() return inRaid, inRaid and 'raid' or 'none' end
        function IsShiftKeyDown() return false end
        function CanMerchantRepair() return true end
        function GetRepairAllCost() return repairCost, true end
        function IsInGuild() return false end
        function RepairAllItems() repairs=repairs+1 end
        function GetMoneyString(value) return tostring(value) end
        convenienceDB={repair=true,guildRepair=false,merchantSummary=true}
        JP={L=function(x) return x end,
            UI={UsableNumber=function(v) return type(v)=='number' end},
            Settings=function() return convenienceDB end,
            Print=function(_, message) table.insert(messages,message) end,
            RegisterModule=function(self,name,module) self[name]=module end}
    """)
    jp = lua.globals().JP
    load(lua, "MythicBoost/Modules/Convenience.lua", jp)
    lua.execute("""
        JP.Convenience:Repair()
        repairCost=250
        JP.Convenience:Repair()
        assert(repairs==2 and #messages==4)
        assert(messages[1]=='Ремонт: 100' and messages[2]=='За время рейда: 100')
        assert(messages[3]=='Ремонт: 250' and messages[4]=='За время рейда: 350')
        inRaid=false
        JP.Convenience:UpdateRaidRepairSession()
        inRaid=true; repairCost=75
        JP.Convenience:Repair()
        assert(messages[5]=='Ремонт: 75' and messages[6]=='За время рейда: 75')
    """)


def test_application_plan():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        C_LFGList={}
        JP={L=function(x) return x end,
            UI={colors={}, UsableNumber=function(v) return type(v)=='number' end,
                SafeString=function(v) if type(v)=='string' then return v end end,
                SafeBoolean=function(v) return v==true end,
                SafeTable=function(v) if type(v)=='table' then return v end end},
            RegisterModule=function(self,name,module) self[name]=module end}
    """)
    jp = lua.globals().JP
    load(lua, "MythicBoost/Contracts.lua", jp)
    load(lua, "MythicBoost/Modules/GroupSearchUI.lua", jp)
    lua.execute("""
        local active={[99]=true,[100]=true}
        JP.GroupSearchUI.GetApplicationState=function(self,id)
            return active[id] and 'applied' or 'none',false,active[id] or false
        end
        C_LFGList.GetApplications=function() return {99,100} end
        matches={
            {searchResultID=1,applicationPriority=100,mapID=1,targetLevel=10,dungeon='A'},
            {searchResultID=2,applicationPriority=99,mapID=1,targetLevel=10,dungeon='A2'},
            {searchResultID=3,applicationPriority=95,mapID=2,targetLevel=11,dungeon='B'},
            {searchResultID=4,applicationPriority=94,mapID=3,targetLevel=12,dungeon='C'},
            {searchResultID=5,applicationPriority=90,mapID=4,targetLevel=13,dungeon='D'}}
        JP.GroupSearchUI:OptimizeApplicationPlan(matches)
        representativeLevel=JP.GroupSearchUI:GetUpgradeSearchLevel({
            groupFilters={scoreUpgrade=true,dungeons={}},
            dungeonData={{mapID=1},{mapID=2},{mapID=3},{mapID=4}},
            bestByMap={[1]=10,[2]=11,[3]=12,[4]=13}})
        assert(representativeLevel==12)
    """)
    module, matches = jp.GroupSearchUI, lua.globals().matches
    assert module.applicationPlanCount == 3
    assert [matches[index].searchResultID for index in range(1, 4)] == [1, 3, 4]
    assert "2 активных" in module.applicationSuggestion

    lua.execute("""
        C_LFGList.GetApplicationInfo=function(id)
            if id==1 then return id,'applied','none',42 end
            if id==2 then return id,'declined_full',nil,0 end
            return id,'invited',nil,0
        end
    """)
    applied = jp.API.GetApplicationState(1)
    declined = jp.API.GetApplicationState(2)
    invited = jp.API.GetApplicationState(3)
    assert (applied.cancellable, applied.pending, applied.active, applied.duration) == (True, False, True, 42)
    assert declined.declined is True
    assert invited.active is True and invited.cancellable is False

    lua.execute("""
        composed=JP.GroupSearchUI:ComposeResults({{searchResultID=1}},
            {{searchResultID=2,rejected=true},{searchResultID=3,rejected=true}})
        assert(#composed==4 and composed[2].isSection and composed[2].sectionCount==2)
        JP.Settings=function() return {showRejectedResults=false,allowRejectedApplications=true} end
        composed=JP.GroupSearchUI:ComposeResults({{searchResultID=1}},
            {{searchResultID=2,rejected=true}})
        assert(#composed==1 and composed[1].searchResultID==1)
        function GetTime() return 100 end
        local button={match={searchResultID=8,rejected=true,actionable=true}}
        function button:SetText(value) self.text=value end
        function button:Disable() self.enabled=false end
        function button:Enable() self.enabled=true end
        function button:SetAlpha(value) self.alpha=value end
        JP.Settings=function() return {showRejectedResults=true,allowRejectedApplications=false} end
        JP.GroupSearchUI.GetApplicationState=function() return 'none',false,false,false,nil end
        JP.GroupSearchUI:UpdateApplicationButton(button)
        assert(button.text=='Только просмотр' and button.enabled==false)
        JP.GroupSearchUI.GetApplicationState=function() return 'applied',true,true,false,42 end
        JP.GroupSearchUI:UpdateApplicationButton(button)
        assert(button.text:find('Отменить',1,true)==1 and button.enabled==true)
        JP.Settings=nil
        C_ChallengeMode={}
        strictMatches={{searchResultID=7,members=1,memberInfo={},targetLevel=10,
            score=1000,bestLevel=9,roleCounts={},mapID=777}}
        strictExcluded={}
        JP.GroupSearchUI:EnrichPartyRatings(strictMatches,{experiencedParty=true},strictExcluded)
        assert(#strictMatches==0 and #strictExcluded==1)
        assert(strictExcluded[1].rejected and strictExcluded[1].rejectionReason)
    """)


def test_rejected_search_results():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        function UnitExists(u) return u=='player' end
        function UnitClass() return 'Mage','MAGE' end
        function UnitGroupRolesAssigned() return 'DAMAGER' end
        function IsInGroup() return false end
        function GetSpecialization() return 1 end
        function GetSpecializationRole() return 'DAMAGER' end
        C_ChallengeMode={GetMapTable=function() return {777} end,
            GetMapUIInfo=function(id) return 'Dungeon',id,1800 end}
        infos={
            [101]={activityID=10,numMembers=2,name='+10',leaderName='Good-Realm',leaderOverallDungeonScore=2000,age=30},
            [102]={activityID=10,numMembers=2,name='+10',leaderName='NoTank-Realm',leaderOverallDungeonScore=1900,age=40},
            [103]={activityID=10,numMembers=5,name='+10',leaderName='Full-Realm',leaderOverallDungeonScore=1800,age=50},
            [105]={activityID=10,numMembers=2,leaderName='Hidden-Realm',leaderOverallDungeonScore=2100,age=20,
                leaderDungeonScoreInfo={{mapChallengeModeID=777,bestRunLevel=10}}},
            [106]={activityID=10,numMembers=2,name='+10',leaderName='Low-Realm',leaderOverallDungeonScore=2100,age=20},
            [107]={activityID=10,numMembers=2,name='+11 weekly',leaderName='Eleven-Realm',leaderOverallDungeonScore=2100,age=20},
            [108]={activityID=10,numMembers=2,name='10-10 veterans',leaderName='Ten-Realm',leaderOverallDungeonScore=2100,age=20}}
        C_LFGList={
            GetSearchResults=function() return 4,{101,102,103,104} end,
            GetSearchResultInfo=function(id) if id==104 then error('broken listing') end return infos[id] end,
            GetActivityInfoTable=function() return {mapChallengeModeID=777,fullName='Dungeon'} end,
            GetSearchResultMemberCounts=function(id)
                if id==101 then return {TANK=1,HEALER=1,DAMAGER=0} end
                return {TANK=0,HEALER=1,DAMAGER=1}
            end,
            GetSearchResultPlayerInfo=function() return nil end,
            GetApplicationInfo=function(id) return id,'none','none',0 end}
        JP={L=function(x) return x end,
            UI={UsableNumber=function(v) return type(v)=='number' end,
                SafeString=function(v) if type(v)=='string' then return v end end,
                SafeBoolean=function(v) return v==true end,
                SafeTable=function(v) if type(v)=='table' then return v end end},
            RegisterModule=function(self,name,module) self[name]=module end,
            GetBestLevel=function() return 9 end,
            IsLogging=function() return false end,
            Log=function() end}
    """)
    jp = lua.globals().JP
    load(lua, "MythicBoost/Contracts.lua", jp)
    load(lua, "MythicBoost/Modules/AutoMatch.lua", jp)
    lua.execute("""
        scanMatches,_,scanTotal,scanReasons,scanExcluded=JP.AutoMatch:Scan(
            {requireTank=true,roleFit=true},{bestByMap={},bestByActivity={}})
        assert(scanTotal==4 and #scanMatches==1 and #scanExcluded==3)
        assert(scanMatches[1].searchResultID==101)
        assert(scanExcluded[1].searchResultID==102 and scanExcluded[1].actionable==true)
        assert(scanExcluded[2].searchResultID==103 and scanExcluded[2].actionable==false)
        assert(scanExcluded[3].searchResultID==104 and scanExcluded[3].actionable==true)
        assert(scanExcluded[1].rejectionReason=='в группе нет танка')
        assert(scanExcluded[2].rejectionReason=='группа уже полная')
        assert(scanExcluded[3].rejectionReason=='ошибка чтения результата')

        C_LFGList.GetSearchResults=function() return 2,{105,106} end
        local upgradeMatches,_,_,_,upgradeExcluded=JP.AutoMatch:Scan(
            {scoreUpgrade=true,searchTargetLevel=11,roleFit=false},
            {bestByActivity={[10]=12},bestByMap={[777]=12}})
        assert(#upgradeMatches==1 and upgradeMatches[1].searchResultID==105)
        assert(upgradeMatches[1].keyApprox==true and upgradeMatches[1].targetLevel==13)
        assert(#upgradeExcluded==1 and upgradeExcluded[1].searchResultID==106)
        assert(upgradeExcluded[1].rejectionReason=='ключ ниже твоего рекорда')

        C_LFGList.GetSearchResults=function() return 2,{107,108} end
        local exactMatches,_,_,_,exactExcluded=JP.AutoMatch:Scan(
            {keyMin=10,keyMax=10,searchExactLevel=10,roleFit=false},
            {bestByActivity={[10]=9},bestByMap={[777]=9}})
        assert(#exactMatches==1 and exactMatches[1].searchResultID==108)
        assert(exactMatches[1].keyLevel==10 and exactMatches[1].keyApprox==false)
        assert(#exactExcluded==1 and exactExcluded[1].searchResultID==107)
        assert(exactExcluded[1].rejectionReason=='ключ вне диапазона')
    """)


def test_launch_decision():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        C_MythicPlus={GetOwnedKeystoneChallengeMapID=function() return 1 end,
            GetOwnedKeystoneLevel=function() return 10 end}
        JP={L=function(x) return x end,
            modules={},
            UI={colors={amber={},green={},accent={}},
                UsableNumber=function(v) return type(v)=='number' end,
                SafeString=function(v) if type(v)=='string' then return v end end,
                SafeBoolean=function(v) return v==true end,
                ClassIcon=function(classFile) return '['..(classFile or '?')..']' end,
                RoleIcon=function(role) return '<'..(role or '?')..'>' end,
                ClassColorCode=function() return 'ffffffff' end},
            RegisterModule=function(self,name,module) self[name]=module end}
    """)
    jp = lua.globals().JP
    load(lua, "MythicBoost/Modules/ApplicantBoard.lua", jp)
    lua.execute("""
        local b=JP.ApplicantBoard
        b.partyPower={SetText=function() end}; b.partyPowerBaseText=''
        b.partySafeLevel=10; b.partyConfidence=100
        b.partyMemberCount=4; b.missingRoles={TANK=0,HEALER=1,DAMAGER=0}
        b:UpdateLaunchDecision({
            {name='Damage',role='DAMAGER',numMembers=1,safeLevel=20,applicantID=1},
            {name='Heal',role='HEALER',numMembers=1,safeLevel=9,applicantID=2}})
        assert(b.launchAdvice=='БЕРИ Heal')
        b:UpdateLaunchDecision({{name='Damage',role='DAMAGER',numMembers=1,safeLevel=20,applicantID=1}})
        assert(b.launchAdvice=='ЖДИ ЕЩЁ 1')
        b.partyMemberCount=3; b.missingRoles={TANK=0,HEALER=1,DAMAGER=1}
        b:UpdateLaunchDecision({
            {name='Heal',role='HEALER',numMembers=2,safeLevel=10,applicantID=3},
            {name='Damage',role='DAMAGER',numMembers=2,safeLevel=10,applicantID=3}})
        assert(b.launchAdvice=='ЕСТЬ 2 КАНДИДАТОВ — ДОБЕРИ РОЛИ')
        b:UpdateLaunchDecision({
            {name='D1',role='DAMAGER',numMembers=2,safeLevel=10,applicantID=4},
            {name='D2',role='DAMAGER',numMembers=2,safeLevel=10,applicantID=4}})
        assert(b.launchAdvice=='ЖДИ ЕЩЁ 2')

        C_LFGList={
            GetApplicants=function() return {77,88} end,
            GetApplicantInfo=function(id)
                return {applicationStatus='applied',numMembers=id==77 and 2 or 1}
            end,
            GetApplicantMemberInfo=function(id,index)
                if id==77 and index==1 then
                    return 'Leader-Realm','WARRIOR',nil,nil,610,nil,true,false,false,'TANK',nil,2900
                elseif id==77 and index==2 then
                    return 'Friend-Realm','PRIEST',nil,nil,605,nil,false,true,false,'HEALER',nil,2800
                end
                return 'Solo-Realm','MAGE',nil,nil,620,nil,false,false,true,'DAMAGER',nil,3000
            end}
        JP.GroupSearchUI={GetDungeonCells=function() return {} end}
        b.missingRoles={TANK=1,HEALER=1,DAMAGER=3}; b.partyEvidence={}
        local entries=b:Collect()
        local duo={}
        for position,entry in ipairs(entries) do
            if entry.applicantID==77 then duo[#duo+1]=position end
        end
        assert(#duo==2 and duo[2]==duo[1]+1)
        local leader,friend=entries[duo[1]],entries[duo[2]]
        assert(leader.memberIdx==1 and friend.memberIdx==2)
        assert(string.find(leader.packageInline,'[1/2]',1,true))
        assert(string.find(friend.packageInline,'[2/2]',1,true))
        assert(string.find(leader.packageInline,'Friend-Realm',1,true))
        assert(string.find(friend.packageInline,'Leader-Realm',1,true))
        assert(string.find(leader.packageTooltip,'Leader-Realm',1,true))
        assert(string.find(leader.packageTooltip,'Friend-Realm',1,true))
        assert(entries[duo[1]-1]==nil or entries[duo[1]-1].applicantID~=77)
        assert(entries[duo[2]+1]==nil or entries[duo[2]+1].applicantID~=77)

        -- Raider.IO normally has no exact run count. Unknown sample size must
        -- not turn a proven +13 into "little experience" for a +14 key, even
        -- when the other seven dungeons are already +14.
        C_MythicPlus.GetOwnedKeystoneChallengeMapID=function() return 1 end
        C_MythicPlus.GetOwnedKeystoneLevel=function() return 14 end
        C_LFGList.GetApplicants=function() return {99} end
        C_LFGList.GetApplicantInfo=function() return {applicationStatus='applied',numMembers=1} end
        C_LFGList.GetApplicantMemberInfo=function()
            return 'AlmostDone-Realm','MAGE',nil,nil,620,nil,false,false,true,'DAMAGER',nil,3188
        end
        local cells={{mapID=1,level=13,upgrades=1}}
        for mapID=2,8 do cells[#cells+1]={mapID=mapID,level=14,upgrades=1} end
        JP.GroupSearchUI.GetDungeonCells=function() return cells end
        b.missingRoles={TANK=0,HEALER=0,DAMAGER=1}
        b.partyEvidence={{name='Me',strength=13.3,known=true,level=13}}
        local near=b:Collect()
        assert(#near==1 and near[1].status=='keyClose')
        assert(near[1].recommendationWeight==1)
        assert(string.find(near[1].recommendationReason,'Опыт этого данжа +13',1,true))

        -- Even an explicitly known single timed run is direct evidence for
        -- attempting the next level; sample size affects confidence, not the
        -- candidate label.
        cells[1].runCount=1
        near=b:Collect()
        assert(#near==1 and near[1].status=='keyClose')
    """)


def test_run_history():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        function GetTime() return 500 end; function time() return 100000 end; function date() return '' end
        function UnitExists(u) return u=='player' or u=='party1' or u=='party2' end
        function UnitFullName(u) if u=='player' then return 'Me','Realm' elseif u=='party1' then return 'Good','Other' else return 'Left','Other' end end
        function UnitGUID(u) return ({player='P',party1='G',party2='L'})[u] end
        function UnitClass(u) return 'Class',u=='party1' and 'PRIEST' or 'MAGE' end
        function UnitGroupRolesAssigned(u) return u=='party1' and 'HEALER' or 'DAMAGER' end
        function UnitIsUnit(a,b) return a==b end
        function CreateFrame()
            local f={registered={}}
            function f:RegisterEvent(e) self.registered[e]=true end
            function f:UnregisterEvent(e) self.registered[e]=nil end
            function f:UnregisterAllEvents() self.registered={} end
            function f:SetScript(k,v) self[k]=v end
            return f
        end
        C_ChallengeMode={GetActiveChallengeMapID=function() return 777 end,
            GetActiveKeystoneInfo=function() return 12,{1,2},false end,
            GetStartTime=function() return 400 end, IsChallengeModeActive=function() return false end,
            GetDeathCount=function() return 1,5 end,
            GetMapUIInfo=function(id) return 'Dungeon',id,1800 end}
        db={players={},runs={}}
        for i=1,205 do db.players['old'..i]={name='Old'..i,lastAt=i} end
        for i=1,35 do db.runs[i]={mapName='Old',level=2,duration=1} end
        JP={L=function(x) return x end,UI={colors={}},Settings=function(self) return db end,
            GroupSearchUI={GetPartyMemberProfile=function(self,u) return {score=u=='party1' and 2222 or 1111} end},
            GetChallengeCompletionData=function(self) return {mapID=777,level=12,duration=123456,
                onTime=true,upgrades=2,practiceRun=false,members={{memberGUID='P'},{memberGUID='G'}}} end,
            RegisterModule=function(self,name,module) self[name]=module end}
    """)
    jp = lua.globals().JP
    load(lua, "MythicBoost/Contracts.lua", jp)
    lua.execute("""JP.API.GetChallengeCompletion=function() return {mapID=777,level=12,duration=123456,
        onTime=true,upgrades=2,practiceRun=false,members={{memberGUID='P'},{memberGUID='G'}}} end""")
    load(lua, "MythicBoost/Modules/RunHistory.lua", jp)
    module = jp.RunHistory
    module.Create(module); module.Enable(module); module.StartRun(module, False)
    db = lua.globals().db
    assert len(db.runs) == 30
    assert sum(1 for _ in db.players.items()) == 200
    assert (module.current.level, module.current.startedAt) == (12, 400)
    assert module.events.registered["COMBAT_LOG_EVENT_UNFILTERED"] is True
    module.current.byGUID["G"].interrupts = 3
    module.FinishRun(module)
    assert len(db.runs) == 30 and abs(db.runs[1].duration - 123.456) < 0.001
    assert (db.runs[1].level, db.runs[1].interrupts) == (12, 3)
    assert db.players["good-other"].runs == 1 and db.players["left-other"] is None
    assert module.current is None
    assert module.events.registered["COMBAT_LOG_EVENT_UNFILTERED"] is None


def test_anonymous_screenshot_demo():
    source = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    demo = source.split("-- Anonymous screenshot showcase", 1)[1].split(
        "function UnitFrames:ResetPositions", 1
    )[0]
    assert demo.count('title = L("') == 5
    for fictional_name in (
        "Astraforge", "Voidwarden", "Ironbloom", "Lumenweave", "Nightquill", "Dawnkeeper"
    ):
        assert fictional_name in demo
    for private_api in ("UnitName(", "UnitFullName(", "GetNormalizedRealmName(", "ChatFrame"):
        assert private_api not in demo
    assert "if self.screenshotStage then return self.screenshotStage end" in demo
    assert demo.count("preview = true") == 2
    assert "wipe(display.cache)" in demo


def test_owned_key_visual_priority():
    source = (ROOT / "MythicBoost/Modules/ApplicantBoard.lua").read_text(encoding="utf-8")
    comparison = "tonumber(column.key) == tonumber(ownMapID)"
    assert source.count(comparison) >= 3  # header, current party, and every candidate row
    assert 'tile.value:SetFont(tile.valueFont, isOwnedKey and 20 or 16, "THICKOUTLINE")' in source
    assert "tile.ownedGlow:Show()" in source and "tile.ownedGlow:Hide()" in source
    assert 'L("ТВОЙ КЛЮЧ")' in source
    assert "ownedMark" not in source
    assert "◆" not in source


def test_search_row_hides_internal_priority():
    source = (ROOT / "MythicBoost/Modules/GroupSearchUI.lua").read_text(encoding="utf-8")
    render = source.split("function GroupSearchUI:RenderRows", 1)[1].split(
        "function GroupSearchUI:UpdateApplicationButton", 1
    )[0]
    coach = source.split("local function ApplicationCoachText", 1)[1].split(
        "ApplicationCoachTooltip =", 1
    )[0]
    assert "match.applicationPriority or 0" not in render
    assert 'unknown = L("ЦЕЛЬ")' not in coach
    assert "table.concat(detailParts" in render
    assert 'and "T+"' not in render
    assert 'L("|cff657181+%d скрыт.|r")' not in render
    key_render = render.split("local displayedLevel = LocalDisplayKeyLevel", 1)[1].split(
        "row.dungeon:SetText", 1
    )[0]
    assert "match.targetLevel" not in key_render
    assert "match.keyLevel" not in key_render
    assert "LocalDisplayKeyLevel(welcome, match)" in render
    assert "row.key:SetText(" not in render
    assert "row.keyLabels[displayedLevel]" in render
    create_row = source.split("local function CreateResultRow", 1)[1].split(
        "local ApplicationCoachTooltip", 1
    )[0]
    assert 'row.keyFallback = KeyLabel("+")' in create_row
    assert 'for level = 2, 40 do row.keyLabels[level] = KeyLabel("+" .. level) end' in create_row
    assert "label:SetSize(COL.keyWidth + 8, 30)" in create_row
    assert "keyPlate" not in create_row


def test_header_and_listing_actions_stay_compact():
    welcome = (ROOT / "MythicBoost/Modules/Welcome.lua").read_text(encoding="utf-8")
    header = welcome.split("local function BuildHeader", 1)[1].split("local function BuildGuide", 1)[0]
    assert 'UI.Button(header, L("Как пользоваться")' not in header
    assert 'maximize:SetPoint("RIGHT", close, "LEFT", -8, 0)' in header

    search = (ROOT / "MythicBoost/Modules/GroupSearchUI.lua").read_text(encoding="utf-8")
    assert "function GroupSearchUI:OpenListingAction()" in search
    listing_action = search.split("function GroupSearchUI:OpenListingAction()", 1)[1].split(
        "end", 1
    )[0]
    assert "OpenOwnKeystoneListingForm()" in listing_action
    assert "FrameSwitch.OpenBlizzard" not in listing_action
    assert 'welcome.createOwnKey:SetText(active and L("Открыть объявление") or L("Создать объявление"))' in search
    assert "level ~= nil and leader" in search


def test_exact_key_search_uses_blizzard_range_syntax():
    source = (ROOT / "MythicBoost/Modules/GroupSearchUI.lua").read_text(encoding="utf-8")
    native_exact = source.split("local function NativeExactLevel", 1)[1].split(
        "FinishBlizzardSearch = function", 1
    )[0]
    direct_search = source.split("function GroupSearchUI:RunDirectSearch", 1)[1].split(
        "function GroupSearchUI:OnSearchResults", 1
    )[0]
    assert 'text:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")' in native_exact
    assert "function GroupSearchUI:CaptureNativeExactSearch" in native_exact
    assert "self.manualExactLevel = level" in native_exact
    assert "JP:Print" not in native_exact
    assert "UIErrorsFrame" not in native_exact
    assert ".SetText(" not in native_exact
    assert ".Insert" not in native_exact
    assert "local searchCrossFactionListings = nil" in direct_search
    assert "languages, searchCrossFactionListings, advancedFilter, activityIDs" in direct_search
    assert "languages, searchText" not in direct_search
    assert '("+%d"):format(targetLevel)' not in direct_search
    assert "if C_LFGList.ClearSearchTextFields then pcall(C_LFGList.ClearSearchTextFields) end" in direct_search
    assert "GroupSearchUI:CaptureNativeExactSearch(welcome)" in source
    request = source.split("function GroupSearchUI:RequestBlizzardSearch", 1)[1].split(
        "-- Карточки подземелий", 1
    )[0]
    assert "self:ScheduleCurrentSearch(welcome, token)" in request
    assert "AwaitNativeExactSearch" not in request


def test_basicminimap_owns_the_minimap():
    source = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    core = (ROOT / "MythicBoost/Core.lua").read_text(encoding="utf-8")
    assert 'UI.IsAddOnLoaded("BasicMinimap")' in source
    assert 'UI.IsAddOnLoaded("BasicMinimap_Options")' in source
    style = source.split("function MinimalUI:StyleMinimap", 1)[1].split(
        "local function RememberFontColor", 1
    )[0]
    assert "if enabled and BasicMinimapIsActive() then" in style
    assert "if self.minimapOwnershipActive then self:StyleMinimap(false) end" in style
    assert "if not enabled and not self.minimapOwnershipActive then return end" in style
    assert "RememberAndHideMinimap(self, object)" in style
    assert "RestoreMinimapVisibility(self)" in style
    assert "if not self.minimapOwnershipActive then return end" in source
    assert "function MinimalUI:SetMinimapEnabled" in source
    assert "self:StyleMinimap(minimapEnabled)" in source
    assert 'L("Оформлять миникарту MythicBoost")' in settings
    assert 'Enable("minimalUIMinimap", MythicBoostDB.minimalUI == true)' in settings
    assert "db.minimalUIOptions.minimap = freshProfile" in core


def test_run_history_can_invite_by_whisper():
    source = (ROOT / "MythicBoost/Modules/RunHistory.lua").read_text(encoding="utf-8")
    assert "local function InviteToPlay" in source
    assert 'SendChatMessage(PLAY_INVITE_MESSAGE, "WHISPER", nil, name)' in source
    assert "Hi! I'd like to invite you to play some Mythic+ keys!" in source
    assert 'UI.Button(row, L("Позвать")' in source
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    assert 'Heading(interfacePage, L("РАСПОЛОЖЕНИЕ"), 28, -372, 764)' in settings
    assert 'interfaceMove:SetPoint("TOPLEFT", 28, -406)' in settings


def test_settings_steppers_use_supported_glyphs():
    source = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    stepper = source.split("function SettingsHub:AddStepper", 1)[1].split(
        "function SettingsHub:RefreshDependencies", 1
    )[0]
    assert 'UI.Button(row, "-", 26, 24)' in stepper
    assert "−" not in stepper


def test_warcraft_logs_character_urls():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        function GetCurrentRegion() return 3 end
    """)
    jp = lua.table()
    jp.L = lambda text: text
    jp.RegisterModule = lambda self, name, module: None
    load(lua, "MythicBoost/Modules/WarcraftLogs.lua", jp)

    lua.execute("RaiderIO={GetProfile=function() return {realm='gordunni'} end}")
    url = jp.WarcraftLogs.BuildURL(jp.WarcraftLogs, "Гдезима", "Гордунни")
    assert url == "https://www.warcraftlogs.com/character/eu/gordunni/%D0%93%D0%B4%D0%B5%D0%B7%D0%B8%D0%BC%D0%B0"

    lua.execute("RaiderIO=nil")
    url = jp.WarcraftLogs.BuildURL(jp.WarcraftLogs, "Player", "Tarren Mill", "eu")
    assert url == "https://www.warcraftlogs.com/character/eu/tarren-mill/Player"

    source = (ROOT / "MythicBoost/Modules/WarcraftLogs.lua").read_text(encoding="utf-8")
    assert 'Menu.ModifyMenu("MENU_UNIT_" .. which, callback)' in source
    assert 'Menu.ModifyMenu(tag, callback)' in source
    assert 'rootDescription:CreateTitle("Warcraft Logs")' in source
    assert "InstallAfterFirstMenu" in source


def test_buff_button_is_prepared_before_combat():
    source = (ROOT / "MythicBoost/Modules/SmartClick.lua").read_text(encoding="utf-8")
    refresh = source.split("function SmartClick:RefreshBuffButton", 1)[1].split(
        "function SmartClick:Create", 1
    )[0]
    assert refresh.index("button = button or self:BuildBuffButton()") < refresh.index("local missing, blocked = self:MissingBuff()")
    assert "button:SetAlpha(1)" in refresh and "button:SetAlpha(0)" in refresh
    assert 'button.label:SetText("")' in refresh
    assert "if not missing then button:Hide(); return end" not in refresh
    assert "if not button and inCombat then return end" in refresh
    assert '"UNIT_SPELLCAST_SUCCEEDED"' in source
    assert 'event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player"' in source
    assert "BUFF[class] == spellID" in source
    build = source.split("function SmartClick:BuildBuffButton", 1)[1].split(
        "function SmartClick:RefreshBuffButton", 1
    )[0]
    assert build.index("button:SetAlpha(0)") < build.index("button:Hide()")
    assert "if owner:GetAlpha() <= .01 then return end" in build
    enable = source.split("function SmartClick:Enable()", 1)[1].split("function SmartClick:Disable", 1)[0]
    assert "self:RefreshBuffButton()" in enable
    assert 'L("Заклинание групповое — один каст закрывает всех в радиусе.")' not in source


def test_target_identity_and_portrait_have_fallbacks():
    ui = (ROOT / "MythicBoost/UI.lua").read_text(encoding="utf-8")
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    assert 'model:SetScript("OnModelLoaded"' in ui
    assert "portrait.face:Hide()" in ui and "self.model:Hide()" in ui
    portrait = ui.split("function UI.Portrait", 1)[1].split("function UI.StatusBar", 1)[0]
    loaded = portrait.split('model:SetScript("OnModelLoaded"', 1)[1].split(
        "portrait.ring, portrait.face, portrait.model", 1
    )[0]
    assert "self:Show()" not in loaded
    assert portrait.index("self.model:SetAlpha(0)") < portrait.index(
        "local modelOK = pcall(self.model.SetUnit, self.model, unit)"
    )
    assert "self.model:Show()" in portrait
    assert "self:SetAlpha(1)" in portrait
    assert 'self.ring:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3]' in portrait
    assert "self.face:SetDesaturated(false)" in portrait
    assert "local function ReadUnitName" in frames
    assert "UnitNameUnmodified" in frames and "display.cachedName" in frames
    refresh = frames.split("function UnitFrames:RefreshDisplay", 1)[1].split(
        "function UnitFrames:RefreshAll", 1
    )[0]
    assert "display.holder:SetAlpha(0)" in refresh
    assert "display.holder:SetAlpha(1)" in refresh
    assert 'if not InCombatLockdown() then display.holder:Show() end' in refresh
    assert "display.holder:Hide()" not in refresh
    assert "function UnitFrames:QueuePortraitRefresh" in frames
    assert "display.portraitRefreshToken ~= token" in frames
    assert "self:QueuePortraitRefresh(display)" in frames
    assert 'display.name = UI.Text(namePanel, "GameFontNormalSmall", "", C.amber)' in frames
    assert 'display.name:SetFont(nameFont, 11, nameFlags or "OUTLINE")' in frames
    assert 'display.name:SetPoint("TOPLEFT", 10, 0)' in frames
    assert 'display.name:SetPoint("BOTTOMRIGHT", -10, 1)' in frames


def test_rotation_suggestion_stays_square():
    source = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    mute = source.split("local function MuteSuggestionGlow", 1)[1].split(
        "local function StyleMinimapZoneLabel", 1
    )[0]
    assert "local ForceSquareOnly" in mute
    assert 'hooksecurefunc(node, "SetAlpha"' in mute
    assert "node:GetAnimationGroups()" in mute
    assert "node:GetChildren()" in mute
    assert "MuteTree(object, {}, 0)" in mute
    assert "button.AssistedCombatRotationFrame" in mute
    assert "button.SpellActivationAlert" in mute
    action = source.split("function MinimalUI:StyleActionButtons", 1)[1].split(
        "function MinimalUI:StyleCooldownEffectBars", 1
    )[0]
    combat = action.split("if InCombatLockdown() then", 1)[1].split("return", 1)[0]
    assert "MuteActionSuggestionGlows(self, button)" in combat
    assert "fill:SetColorTexture(.16, .22, .28, .24)" in action


def test_active_cooldown_icons_are_compacted_without_empty_slots():
    source = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    compact = source.split("function MinimalUI:CompactCooldownIcons", 1)[1].split(
        "function MinimalUI:StyleCooldownEffectBars", 1
    )[0]
    assert "BuffIconCooldownViewer" in compact
    assert "button:IsShown()" in compact and "icon:IsShown()" in compact
    assert 'button:SetPoint("CENTER", viewer, "CENTER", cursor + width * .5, 0)' in compact
    assert 'button:HookScript("OnShow"' in compact
    assert 'button:HookScript("OnHide"' in compact
    assert "for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end" in compact


def test_chat_skin_is_fully_removed():
    toc = (ROOT / "MythicBoost/MythicBoost.toc").read_text(encoding="utf-8")
    minimal = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    assert not (ROOT / "MythicBoost/Modules/MinimalChat.lua").exists()
    assert "Modules/MinimalChat.lua" not in toc
    assert "JP.MinimalChat" not in minimal


def test_brand_icon_and_upgrade_shortcut():
    ui = (ROOT / "MythicBoost/UI.lua").read_text(encoding="utf-8")
    switch = (ROOT / "MythicBoost/Modules/FrameSwitch.lua").read_text(encoding="utf-8")
    upgrades = (ROOT / "MythicBoost/Modules/UpgradeCalculator.lua").read_text(encoding="utf-8")
    toc = (ROOT / "MythicBoost/MythicBoost.toc").read_text(encoding="utf-8")
    assert (ROOT / "MythicBoost/Media/MythicBoostIcon.tga").is_file()
    assert (ROOT / "MythicBoost/Media/LootGlass.tga").is_file()
    assert (ROOT / "MythicBoost/Media/LootGlow.tga").is_file()
    assert "function UI.IconButton" in ui
    assert "local function ResetIconButtonPress" in ui
    assert 'button:HookScript("OnHide", ResetIconButtonPress)' in ui
    assert "UI.IconButton(PVEFrame, ICON, 28)" in switch
    assert "function UpgradeCalculator:EnsureUpgraderShortcut" in upgrades
    assert 'button:SetPoint("RIGHT", close, "LEFT", -7, 0)' in upgrades
    assert "close:GetFrameLevel() + 1" in upgrades
    assert 'welcome:SwitchPage("upgrades")' in upgrades
    assert "Media\\MythicBoostIcon.tga" in toc
    assert "## AddonCompartmentFunc: MythicBoost_OnAddonCompartmentClick" in toc
    assert "MythicBoostIcon.tga" in switch and "MythicBoostIcon.tga" in upgrades
    assert "local function ShowCurrencyDetailsTooltip" in upgrades
    assert "GameTooltip.SetCurrencyByID" in upgrades
    assert "ShowCurrencyDetailsTooltip(self)" in upgrades


def test_native_gold_trim_is_applied_without_repainting_damage_meter():
    ui = (ROOT / "MythicBoost/UI.lua").read_text(encoding="utf-8")
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    minimal = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    assert "frame.__mbGoldTrimTop" in ui and "frame.__mbGoldTrimBottom" in ui
    assert "top:SetColorTexture(.98, .76, .22, .86)" in ui
    assert "sheen:SetColorTexture(.98, .76, .22, .82)" in frames
    assert "local ACTION_EDGE_IDLE = { .48, .34, .09 }" in minimal
    assert "anchor.railTop" in minimal and "anchor.railBottom" in minimal
    assert "CreateColor(.98, .76, .22, .22)" in minimal
    assert "self:StyleNativeDamageMeterWindows(false)" in minimal


def test_layout_takeover_features_are_fully_removed():
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    core = (ROOT / "MythicBoost/Core.lua").read_text(encoding="utf-8")
    toc = (ROOT / "MythicBoost/MythicBoost.toc").read_text(encoding="utf-8")
    minimal = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    assert not (ROOT / "MythicBoost/Modules/BottomDock.lua").exists()
    assert "Modules/BottomDock.lua" not in toc
    assert 'L("Нижний HUD: чат, урон и исцеление")' not in settings
    assert 'L("Три ряда панелей способностей")' not in settings
    assert "JP.BottomDock" not in minimal
    assert "function MinimalUI:StyleActionBarRows" not in minimal
    assert "db.minimalUIOptions.bottomDock = nil" in core
    assert "db.minimalUIOptions.compactActionBars = nil" in core


def test_compact_hud_controls_and_native_meter_skin():
    source = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    assert "function MinimalUI:StyleStanceBar" in source
    assert 'L("Скрывать панель стоек")' in settings
    assert "function MinimalUI:StyleNativeDamageMeter" in source
    assert 'name:find("DamageMeter", 1, true)' in source
    assert "NativeMeterDecorations(frame, state)" in source
    native = source.split("function MinimalUI:StyleNativeDamageMeter", 1)[1].split(
        "local function CaptureFrameLayout", 1
    )[0]
    assert native.index("candidates[#candidates + 1] = frame") < native.index(
        "self:SkinNativeDamageMeterFrame(candidate, true)"
    )
    apply = source.split("function MinimalUI:Apply", 1)[1].split(
        "function MinimalUI:SetEnabled", 1
    )[0]
    assert "self:StyleNativeDamageMeterWindows(false)" in apply
    assert "self:StyleNativeDamageMeterWindows(enabled)" not in apply
    assert "self:StyleNativeDamageMeter(true)" not in apply
    native_skin = source.split("function MinimalUI:SkinNativeDamageMeterFrame", 1)[1].split(
        "function MinimalUI:QueueNativeDamageMeterDetails", 1
    )[0]
    assert "frame:SetSize(" not in native_skin
    assert "function MinimalUI:QueueNativeDamageMeterDetails" in source
    assert 'pcall(node.HookScript, node, "OnMouseUp"' in source
    assert "StyleNativeMeterBars(frame, state, true)" in source


def test_native_addon_compartment_and_bright_action_icons():
    source = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    toc = (ROOT / "MythicBoost/MythicBoost.toc").read_text(encoding="utf-8")
    assert "RememberAndHideMinimap(self, nativeCompartment)" not in source
    assert 'GameTooltip:SetText(L("Меню аддонов"))' not in source
    assert "HideLooseMinimapAddonButtons(self, true)" in source
    assert "not IsNativeCompartment(button)" in source
    assert "nativeCompartment:Show()" in source
    assert "MythicBoostMinimapButtonLauncher" not in source
    assert "StyleMinimapAddonButtons" not in source
    assert "button.__mbActionLight" in source
    assert "button.NewActionTexture" in source
    assert "texture.__mbActionArtifactAlphaHooked" in source
    assert "cooldown:SetSwipeColor(0, 0, 0, .42)" in source
    assert "state.icon:SetVertexColor(1, 1, 1, 1)" in source
    assert "Minimap:SetSize(265, 265)" in source
    assert 'label:SetFont(self.minimapZoneLayout.labelFont[1], 13, "OUTLINE")' in source
    assert "local rowWidth, gap = mapWidth, 0" in source
    assert "Add(_G.AddonCompartmentFrame)" not in source
    assert 'anchor:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -4)' in source
    assert 'button:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -8, 8)' in source
    assert "button:SetScale(1.1)" in source
    assert 'buttonName == "HelpMicroButton"' in source
    assert 'Add("HelpMicroButton")' in source
    assert 'buttonName == "MainMenuMicroButton"' in source
    assert 'button == _G.MainMenuMicroButton' in source
    assert "if self.minimapOwnershipActive and not owner.__mbMinimapHideActive then" in source
    assert "button:SetShown(state.shown)" in source
    assert 'button:SetPoint("CENTER", slot, "CENTER", 0, 0)' in source
    assert 'text:SetFont(fontPath, 12, "OUTLINE")' in source
    assert 'Place(queueStatus, "queueStatus", "BOTTOMLEFT", "BOTTOMLEFT", 6, 6)' in source
    assert 'self.minimapClock:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 5)' in source
    assert "PlaceNativeAddonCompartment(self, true)" in source
    assert "## Category: Dungeons & Raids" in toc
    assert "## Category-ruRU: Подземелья и рейды" in toc
    assert "## Category-ru:" not in toc


def test_stability_guards_avoid_foreign_frame_errors_and_idle_tickers():
    minimal = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    guard = (ROOT / "MythicBoost/Modules/ErrorGuard.lua").read_text(encoding="utf-8")
    applicants = (ROOT / "MythicBoost/Modules/ApplicantHighlighter.lua").read_text(encoding="utf-8")
    loot = (ROOT / "MythicBoost/Modules/LootUI.lua").read_text(encoding="utf-8")
    tooltip = (ROOT / "MythicBoost/Modules/PlayerTooltip.lua").read_text(encoding="utf-8")
    native = minimal.split("local function NativeDamageMeterFrame", 1)[1].split(
        "local function SaveAndMuteNativeMeterObject", 1
    )[0]
    assert 'SafeObjectValue(frame, "GetName")' in native
    assert 'SafeObjectValue(frame, "GetWidth")' in native
    assert "SafePushObjectChildren(queue, node)" in minimal
    assert "QueueDirtyRefresh()" in guard
    assert "C_Timer.NewTicker(1" not in guard
    assert "settings.keepBetweenSessions == false and not self.sessionLogReset" in guard
    assert "owner:UnregisterAllEvents()" in guard
    assert "if not viewCallbackInstalled then" in applicants
    assert "function LootUI:ScheduleHistoryExpiry()" in loot
    assert "if self.historyExpiryQueued" in loot
    assert "C_Timer.After(HISTORY_LIFETIME + .1" not in loot
    assert "if attemptsLeft <= 0 then self.raiderSkinTicker = nil end" in tooltip
    assert "not owner.__mbLooseMinimapHideActive" in minimal
    assert "not owner.__mbMinimapHideActive" in minimal
    assert "not owner.__mbQuestionHideActive" in minimal
    assert "not owner.__mbBagHideActive" in minimal
    assert "C_Timer.NewTicker(5, function()" in minimal
    assert "not owner.__mbCastBarHideActive" in (ROOT / "MythicBoost/Modules/CastBar.lua").read_text(encoding="utf-8")
    assert "not owner.__mbErrorGuardHideActive" in guard
    assert "frame.__mbRollHideActive" in loot


def test_loot_roll_preview_is_local_and_draggable():
    loot = (ROOT / "MythicBoost/Modules/LootUI.lua").read_text(encoding="utf-8")
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    core = (ROOT / "MythicBoost/Core.lua").read_text(encoding="utf-8")
    assert "function LootUI:ShowTestRoll()" in loot
    assert "local TEST_ROLL_ID = -2147483647" in loot
    assert "local ok = row.testRoll == true" in loot
    assert "MythicBoostDB.interfaceUnlocked or frame.testMoveUnlocked" in loot
    assert "SaveAuxiliaryPosition(frame, positionKey)" in loot
    assert "local ROLL_FRAME_WIDTH = 420" in loot
    assert 'BuildAuxiliaryHeader(rollFrame, L("БРОСКИ ГРУППЫ")' in loot
    assert "UI-GroupLoot-Dice-Up" in loot
    assert "UI-GroupLoot-Coin-Up" in loot
    assert "UI-GroupLoot-DE-Up" in loot
    assert "UI-GroupLoot-Pass-Up" in loot
    assert "LOOT_GLASS_TEXTURE" in loot and "LOOT_GLOW_TEXTURE" in loot
    assert 'L("БоЕ")' in loot and 'L("БоИ")' in loot
    assert '"CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY"' in loot
    assert "local function IsOwnLootMessage(message)" in loot
    assert "displayMessage = itemLink" in loot
    assert "function LootUI:SetUnlocked(unlocked)" in loot
    assert 'historyFrame.title = UI.Text(historyFrame.header, "GameFontNormalSmall", L("МОНИТОР ДОБЫЧИ")' in loot
    assert 'row:SetPoint("BOTTOMLEFT", 0, HISTORY_FOOTER_HEIGHT + 2' in loot
    assert "if JP.LootUI then JP.LootUI:SetUnlocked(unlocked) end" in settings
    assert "if row.rollID == TEST_ROLL_ID then LootUI:RemoveRoll(TEST_ROLL_ID) end" in loot
    assert "rollFrame.close = UI.CloseButton(rollFrame)" in loot
    assert 'L("Показать тестовый бросок")' in settings
    assert 'Heading(lootPage, L("ГРУППОВАЯ ДОБЫЧА"), 28, -322, 764)' in settings
    assert 'command == "testroll"' in core


def test_unit_frame_badges_target_placeholder_and_aura_order():
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    assert "function UnitFrames:ConfigureBadgeDisplay" in frames
    assert "ApplyBadgeShape(panel, settings.badgeShape)" in frames
    assert "Settings().badgesUnlocked == true" in frames
    assert 'local otherUnit = display.unit == "player" and "target" or "player"' in frames
    assert "otherDisplay.holder:GetWidth()" in frames
    assert "mirroredX, y" in frames
    assert 'L("Нет")' in settings
    assert 'display.name:SetText(moving and L("Цель") or L("Цель не выбрана"))' in frames
    placeholder = frames.split("local function ShowTargetPlaceholder", 1)[1].split(
        "local function RestoreTargetPlaceholder", 1
    )[0]
    assert "display.portrait.ring:Show()" in placeholder
    assert 'display.portrait.face:SetTexture("Interface\\\\Icons\\\\INV_Misc_QuestionMark")' in placeholder
    assert "display.levelPanel:Hide()" in placeholder
    assert "display.classPanel:Hide()" in placeholder
    assert "display.statsPanel:Show()" in placeholder
    assert "display.health:SetValue(1)" in placeholder
    assert "display.power:SetValue(1)" in placeholder
    assert "display.panel:SetSize(SIZE.panelWidth, SIZE.headerH)" in placeholder
    assert "gravityToFrame and (lines - 1 - sourceLine) or sourceLine" in frames
    assert "ActiveSettings().alwaysShowTarget == true" in frames
    aura_above = settings.index('L("Размещать ауры сверху")')
    player_auras = settings.index('L("Показывать ауры игрока")')
    target_auras = settings.index('L("Показывать ауры цели")')
    assert aura_above < player_auras < target_auras


def test_cast_events_are_correlated_and_capsule_uses_glass_progress():
    cast = (ROOT / "MythicBoost/Modules/CastBar.lua").read_text(encoding="utf-8")
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    assert "local function MatchesActiveCast" in cast
    assert "if not self.frame or not self.active then return end" in cast
    assert "if MatchesActiveCast(self, arg2, arg3) then self:Finish(false) end" in cast
    assert "self.sentGUID = PlainToken(arg3) and arg3 or nil" in cast
    assert "function UnitFrames:UpdateCast(display, event)" in frames
    assert "display.name:Hide()" in frames
    assert "castFill:SetGradient" in frames
    assert "display.castIcon:SetTexture(icon)" in frames
    assert "display.classIcon:Hide()" in frames
    assert "UI.SetClassIconTexture(display.classIcon, class)" in frames
    assert 'display.classIcon = CreateBadgeLayer(levelPanel, 22, "OVERLAY", 6)' in frames
    assert "local function UpdateClassBadgePanelVisibility(display)" in frames
    assert "display.hasClassIcon == true or display.hasCastIcon == true" in frames
    assert "UpdateClassBadgePanelVisibility(display)" in frames
    assert "CreateColor(1, .49, 0, .96)" in frames
    assert "CreateColor(.44, .36, 1, .96)" in frames
    assert "local function CastLatency(duration)" in frames
    assert "math.max(IsPlainNumber(homeMS) and homeMS or 0" in frames
    assert "now - startTime + latency" in frames
    assert "endTime - now - latency" in frames
    assert "display.castCompleteUntil = now + math.max(.06, display.castLatency or 0)" in frames
    assert "self:UpdateCast(display, event)" in frames


def test_unit_frames_magnetize_to_blizzard_action_bars():
    source = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    assert "function UnitFrames:MagnetizeToActionBars" in source
    assert '"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton"' in source
    assert "self:MagnetizeToActionBars(display)" in source
    assert "horizontalDistance > 44" in source


def test_blizzard_edit_mode_keeps_native_frame_ownership():
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    minimal = (ROOT / "MythicBoost/Modules/MinimalUI.lua").read_text(encoding="utf-8")
    cast = (ROOT / "MythicBoost/Modules/CastBar.lua").read_text(encoding="utf-8")

    assert 'local BLIZZARD_FRAMES = { "PlayerFrame", "TargetFrame" }' in frames
    assert 'holder:SetClampedToScreen(true)' in frames
    assert 'self:MagnetizeToActionBars(display)' in frames
    aura_style = minimal.split("function MinimalUI:StylePlayerAuras", 1)[1].split("\nend", 1)[0]
    assert "BuffFrame" not in aura_style
    assert "DebuffFrame" not in aura_style
    assert ":SetPoint(" not in aura_style
    assert "Quartz3CastBarPlayer" not in cast
    assert '"ADDON_LOADED",\n        "UNIT_SPELLCAST_SENT"' not in cast


def test_unit_frame_health_can_optionally_use_class_color():
    core = (ROOT / "MythicBoost/Core.lua").read_text(encoding="utf-8")
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")

    assert 'Default(db.unitFrames, "classColoredHealth", false)' in core
    assert 'classColoredHealth = false' in frames
    assert 'settings.classColoredHealth == true' in frames
    assert 'return UI.ClassColor(class)' in frames
    assert 'L("Цвет здоровья по классу")' in settings
    assert 'classColoredHealth = false' in settings


def test_approved_hud_is_the_new_profile_default():
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    cast = (ROOT / "MythicBoost/Modules/CastBar.lua").read_text(encoding="utf-8")
    loot = (ROOT / "MythicBoost/Modules/LootUI.lua").read_text(encoding="utf-8")
    assert 'player = { "BOTTOM", -269, 2 }' in frames
    assert 'target = { "BOTTOM", 269, 2 }' in frames
    assert "local DEFAULT_BADGE_POSITION" in frames
    assert "db.unitFrames.positionRevision ~= 6" in frames
    assert "scale = 1.5" in frames
    assert "alwaysShowTarget = true" in frames
    assert "aurasAbove = true" in frames
    assert "showEmptyResources = false" in frames
    assert "local SETTINGS_DEFAULTS = { enabled = true" in cast
    assert "settings.x, settings.y = 2, 161" in cast
    assert "local SETTINGS_DEFAULTS = { enabled = true" in loot
    assert not (ROOT / "MythicBoost/Media/XPerl_TargetSelect.ogg").exists()


def test_restricted_auras_use_targeted_friendly_lookup():
    ui = (ROOT / "MythicBoost/UI.lua").read_text(encoding="utf-8")
    frames = (ROOT / "MythicBoost/Modules/UnitFrames.lua").read_text(encoding="utf-8")
    smart = (ROOT / "MythicBoost/Modules/SmartClick.lua").read_text(encoding="utf-8")
    tracker = (ROOT / "MythicBoost/Modules/PositiveAuraTracker.lua").read_text(encoding="utf-8")
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    core = (ROOT / "MythicBoost/Core.lua").read_text(encoding="utf-8")
    toc = (ROOT / "MythicBoost/MythicBoost.toc").read_text(encoding="utf-8")

    assert 'function UI.SafeUnitAura(unit, spellID)' in ui
    assert 'C_UnitAuras.GetUnitAuraBySpellID' in ui
    assert 'InCombatLockdown() then return nil, true end' in ui
    assert 'InCombatLockdown() then return false end' in frames
    assert 'local data, blocked = SafeUnitAura(unit, spellID)' in smart
    assert 'UI.SafeUnitAura("player", spellID)' in tracker
    assert "showIcon = true" in tracker
    assert 'Default(db.positiveAuraTracker, "showIcon", true)' in core
    assert "db.positiveAuraTracker.identityRevision ~= 1" in core
    assert "db.errorGuard.stabilityPrunedRevision ~= 4" in core
    assert 'message:find("MythicBoost/Modules/PositiveAuraTracker.lua:42", 1, true)' in core
    assert 'local fixedAuraTimerLoop = message:find("script ran too long", 1, true)' in core
    assert "icon.textureBorder:SetShown(settings.showIcon ~= false)" in tracker
    assert '"! " .. icon.missingCount' in tracker
    assert "if settings.showWhenMissing and #missing > 0 then" in tracker
    assert 'spellScanner:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")' in settings
    assert 'spellScanner:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")' in settings
    assert "PositiveAuraTracker:AddFromInput(tostring(spellID))" in settings
    assert 'L("file:ID, путь или заклинание")' not in settings
    assert 'GetAuraDataByIndex' not in tracker
    assert 'GetAuraDataByAuraInstanceID' not in tracker
    assert 'Modules/PositiveAuraTracker.lua' in toc
    assert 'for index = 1, 8 do frame.icons[index] = CreateIcon(frame) end' in tracker
    assert 'if self.elapsed >= .10' in tracker
    assert 'if expired then self:QueueRefresh() end' in tracker
    assert 'if expired then self:Refresh() end' not in tracker
    assert 'if not self.frame or self.refreshing then return end' in tracker
    assert 'expiration <= refreshNow then aura = nil' in tracker
    assert 'Media\\AuraWingMask.tga' in (ROOT / "Tools/BuildRelease.ps1").read_text(encoding="utf-8")
    assert (ROOT / "MythicBoost/Media/AuraWingMask.tga").stat().st_size > 100_000
    assert (ROOT / "MythicBoost/Media/AuraLunarMask.tga").stat().st_size > 100_000
    assert (ROOT / "MythicBoost/Media/AuraLunarOriginal.blp").stat().st_size > 40_000
    assert 'Media\\AuraLunarOriginal.blp' in (ROOT / "Tools/BuildRelease.ps1").read_text(encoding="utf-8")
    assert not (ROOT / "MythicBoost/lunar.blp").exists()
    assert 'settings.barHeight * progress' in tracker
    assert 'icon.rightSide and 1 or 0' in tracker
    assert 'pulseAlpha = .68 + .32 * wave' in tracker
    assert 'settings.fontSize' in tracker
    settings = (ROOT / "MythicBoost/Modules/SettingsHub.lua").read_text(encoding="utf-8")
    assert 'previewLeftFill:SetTexCoord(0, 1, .35, 1)' in settings
    assert 'local AURA_LEFT, AURA_RIGHT, AURA_CONTROL_WIDTH = 28, 286, 240' in settings
    assert 'previewPanel:SetSize(150, 240)' in settings
    assert 'L("Предупреждать, если бафа нет")' in settings
    assert 'AddFromInput("1233272,194223,102560")' in settings
    assert 'HoofyEclipse' not in (tracker + settings)

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        inCombat=true; indexedCalls=0; targetedCalls=0
        function InCombatLockdown() return inCombat end
        C_UnitAuras={
            GetAuraDataByIndex=function() indexedCalls=indexedCalls+1; return {spellId=1} end,
            GetUnitAuraBySpellID=function(unit,id)
                targetedCalls=targetedCalls+1; return {spellId=id,unit=unit}
            end}
    """)
    jp = lua.table()
    jp.L = lambda text: text
    load(lua, "MythicBoost/Contracts.lua", jp)
    load(lua, "MythicBoost/UI.lua", jp)
    aura, blocked = jp.UI.SafeAura("player", 1, "HELPFUL")
    assert aura is None and blocked is True and lua.globals().indexedCalls == 0
    aura, blocked = jp.UI.SafeUnitAura("player", 777)
    assert blocked is False and aura.spellId == 777 and lua.globals().targetedCalls == 1

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function issecretvalue(_) return false end
        C_Spell={GetSpellInfo=function(id)
            if id==123 or id=='Known Buff' then return {spellID=123,name='Known Buff',iconID=456} end
        end}
        trackerDB={spellIDs={},texturePreset=2}
        JP={L=function(x) return x end,
            UI={colors={},SafeNumber=function(v) if type(v)=='number' then return v end end,
                SafeString=function(v) if type(v)=='string' and v~='' then return v end end,
                UsableNumber=function(v) return type(v)=='number' end},
            Settings=function() return trackerDB end,
            RegisterModule=function(self,name,module) self[name]=module end}
    """)
    jp = lua.globals().JP
    load(lua, "MythicBoost/Modules/PositiveAuraTracker.lua", jp)
    resolved, rejected = jp.PositiveAuraTracker.ResolveInput(jp.PositiveAuraTracker, "|Hspell:123|h[Known Buff]|h, bad")
    assert len(resolved) == 1 and resolved[1].spellID == 123
    assert len(rejected) == 1 and rejected[1] == "bad"
    assert "AuraLunarMask" in jp.PositiveAuraTracker.GetBarTexture(jp.PositiveAuraTracker)
    assert jp.PositiveAuraTracker.GetTextureName(jp.PositiveAuraTracker, 2) == "Вихрь"
    assert jp.PositiveAuraTracker.GetTextureName(jp.PositiveAuraTracker, 3) == "Лунар"
    jp.PositiveAuraTracker.SetTexturePreset(jp.PositiveAuraTracker, 3)
    assert "AuraLunarOriginal" in jp.PositiveAuraTracker.GetBarTexture(jp.PositiveAuraTracker)
    lua.execute("""
        timerCallbacks={}; refreshCalls=0
        C_Timer={After=function(_, callback) table.insert(timerCallbacks, callback) end}
        GetTime=function() return 10 end
        trackerDB.pulse=false
        trackerDB.showSeconds=true
        trackerDB.barHeight=190
        local noop=function() end
        local icon={expiration=9,duration=5,rightSide=false,missing=false,
            fill={SetAlpha=noop,ClearAllPoints=noop,SetPoint=noop,SetHeight=noop,SetTexCoord=noop},
            glow={SetAlpha=noop},seconds={SetText=noop}}
        function icon:IsShown() return true end
        function icon:Hide() self.hidden=true end
        JP.PositiveAuraTracker.frame={icons={icon}}
        function JP.PositiveAuraTracker.frame:IsShown() return true end
        JP.PositiveAuraTracker.Refresh=function() refreshCalls=refreshCalls+1 end
        JP.PositiveAuraTracker:UpdateTimers()
        JP.PositiveAuraTracker:UpdateTimers()
        assert(#timerCallbacks==1 and refreshCalls==0 and icon.hidden==true)
        timerCallbacks[1]()
        assert(refreshCalls==1)
    """)


if __name__ == "__main__":
    test_completion_api()
    test_safe_defaults()
    test_raid_repair_total_resets_after_leaving_instance()
    test_application_plan()
    test_rejected_search_results()
    test_launch_decision()
    test_run_history()
    test_anonymous_screenshot_demo()
    test_owned_key_visual_priority()
    test_search_row_hides_internal_priority()
    test_settings_steppers_use_supported_glyphs()
    test_header_and_listing_actions_stay_compact()
    test_exact_key_search_uses_blizzard_range_syntax()
    test_basicminimap_owns_the_minimap()
    test_run_history_can_invite_by_whisper()
    test_warcraft_logs_character_urls()
    test_buff_button_is_prepared_before_combat()
    test_target_identity_and_portrait_have_fallbacks()
    test_rotation_suggestion_stays_square()
    test_active_cooldown_icons_are_compacted_without_empty_slots()
    test_chat_skin_is_fully_removed()
    test_brand_icon_and_upgrade_shortcut()
    test_native_gold_trim_is_applied_without_repainting_damage_meter()
    test_layout_takeover_features_are_fully_removed()
    test_compact_hud_controls_and_native_meter_skin()
    test_native_addon_compartment_and_bright_action_icons()
    test_stability_guards_avoid_foreign_frame_errors_and_idle_tickers()
    test_loot_roll_preview_is_local_and_draggable()
    test_unit_frame_badges_target_placeholder_and_aura_order()
    test_cast_events_are_correlated_and_capsule_uses_glass_progress()
    test_unit_frames_magnetize_to_blizzard_action_bars()
    test_blizzard_edit_mode_keeps_native_frame_ownership()
    test_unit_frame_health_can_optionally_use_class_color()
    test_approved_hud_is_the_new_profile_default()
    test_restricted_auras_use_targeted_friendly_lookup()
    print("MythicBoost executable smoke tests: all passed")
