"""Regression fixtures for the .70 interactions. Not a live combat/taint test."""
from TestDungeonHUD import runtime
from TestHudPolish import load, source

TIMERS = r'''
timers={}; now=100; function GetTime() return now end
C_Timer={NewTimer=function(delay,fn)
    local t={fn=fn,delay=delay}; function t:Cancel() self.cancelled=true end
    timers[#timers+1]=t; return t
end}
function Flush()
    local old=timers; timers={}
    for _,t in ipairs(old) do if not t.cancelled then t.fn() end end
end
'''


def test_summon():
    lua = runtime()
    load(lua, 'Modules/Convenience.lua')
    lua.execute(r'''
        local c=JP.Convenience; db.convenience={summon=true}; accepted=0; hidden=0
        function StaticPopup_Hide() hidden=hidden+1 end
        function IsShiftKeyDown() return shift or false end
        function UnitAffectingCombat() return fighting or false end
        function PlayerCanTeleport() return teleport end
        C_SummonInfo={GetSummonConfirmTimeLeft=function() return left end,
            ConfirmSummon=function() accepted=accepted+1 end}
        teleport=true; left=20; c:AcceptSummon(); assert(accepted==1 and hidden==0)
        teleport=false; c:AcceptSummon(); assert(accepted==1)
        teleport=Secret(true); c:AcceptSummon(); assert(accepted==1)
        teleport=true; left=Secret(20); c:AcceptSummon(); assert(accepted==1)
        left=0; c:AcceptSummon(); assert(accepted==1)
        left=20; shift=true; c:AcceptSummon(); assert(accepted==1)
        shift=false; combat=true; c:AcceptSummon(); assert(accepted==1)
        combat=false; fighting=true; c:AcceptSummon(); assert(accepted==1)
        fighting=false; C_SummonInfo.ConfirmSummon=function() error('unavailable') end
        c:AcceptSummon(); assert(hidden==0)
        C_SummonInfo.ConfirmSummon=nil; c:AcceptSummon(); assert(hidden==0)
        db.convenience.summon=false; c:AcceptSummon(); assert(hidden==0)
    ''')


def test_party_greeting():
    lua = runtime()
    lua.execute(TIMERS + r'''
        LE_PARTY_CATEGORY_HOME=1; grouped=false; leader=false; sent={}
        function IsInGroup(category) assert(category==1); return grouped end
        function IsInRaid() return raid or false end
        function UnitIsGroupLeader() return leader end
        C_ChatInfo={InChatMessagingLockdown=function() return chatLocked or false end,
            SendChatMessage=function(text,channel) sent[#sent+1]={text,channel} end}
        db.convenience={autoHi=true}
    ''')
    load(lua, 'Modules/PartyGreeting.lua')
    lua.execute(r'''
        local g=JP.PartyGreeting; g:Enable()
        g:OnEvent('GROUP_JOINED',1); Flush(); assert(#sent==0,'loading baseline')
        g:OnEvent('PLAYER_ENTERING_WORLD'); grouped=true
        g:OnEvent('GROUP_JOINED',2); Flush(); assert(#sent==0,'not instance chat')
        g:OnEvent('GROUP_JOINED',1); g:OnEvent('GROUP_JOINED',1); assert(#timers==1)
        Flush(); assert(#sent==1 and sent[1][1]=='hi' and sent[1][2]=='PARTY')
        g:OnEvent('PLAYER_ENTERING_WORLD'); g:OnEvent('GROUP_JOINED',1); Flush(); assert(#sent==1)
        g:Disable(); g:Enable(); g:OnEvent('GROUP_JOINED',1); Flush(); assert(#sent==1,'reload in group')
        g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1); Flush(); assert(#sent==1,'cooldown')
        now=140; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1); g:OnEvent('GROUP_LEFT',1)
        Flush(); assert(#sent==1,'left before greeting')
        leader=true
        g:OnEvent('GROUP_FORMED',1); g:OnEvent('GROUP_JOINED',1); Flush(); assert(#sent==1,'own party')
        leader=false
        g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1); combat=true; Flush(); assert(#sent==1)
        combat=false; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        chatLocked=Secret(true); Flush(); assert(#sent==1)
        chatLocked=false; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        g:Disable(); Flush(); assert(#sent==1 and not next(g.frame.events))
        local count=allocations
        for i=1,1000 do g:Enable(); g:Disable() end
        assert(allocations==count and not g.pending)
        -- A party formed by someone else's invitation must greet normally.
        g:Enable(); g:OnEvent('GROUP_LEFT',1)
        g:OnEvent('GROUP_FORMED',1); g:OnEvent('GROUP_JOINED',1)
        Flush(); assert(#sent==2 and not g.pending and not g.deadline)
        -- A settled roster is also a fallback if GROUP_JOINED was missed.
        now=180; grouped=false; g:OnEvent('GROUP_LEFT',1)
        grouped=true; g:OnEvent('GROUP_ROSTER_UPDATE')
        for i=1,1000 do g:OnEvent('GROUP_ROSTER_UPDATE'); g:OnEvent('GROUP_JOINED',1) end
        assert(#timers==1); Flush(); assert(#sent==3)
        -- Wait through a transient combat lock; do not consume the greeting.
        now=220; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        combat=true; Flush(); assert(#sent==3 and g.pending)
        combat=false; g:OnEvent('PLAYER_REGEN_ENABLED'); Flush()
        assert(#sent==4 and not g.pending and g.lastSent==220)
        -- Join may arrive before the roster; only one pending timer survives.
        now=260; g:OnEvent('GROUP_LEFT',1); grouped=false; g:OnEvent('GROUP_JOINED',1)
        Flush(); assert(#sent==4 and g.pending)
        grouped=true; chatLocked=true; Flush(); assert(#sent==4 and g.pending)
        chatLocked=false; Flush(); assert(#sent==5 and not g.pending)
        -- No delayed greeting after leaving, disabling, or a minute of lockout.
        now=300; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        chatLocked=true; Flush(); now=361; Flush()
        assert(#sent==5 and not g.pending and not g.deadline)
        chatLocked=false; g:OnEvent('GROUP_ROSTER_UPDATE'); Flush(); assert(#sent==5)
        g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        db.convenience.autoHi=false; Flush(); assert(#sent==5 and not g.pending)
        db.convenience.autoHi=true; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        g:OnEvent('GROUP_LEFT',1); Flush(); assert(#sent==5)
        -- A failed API call is not recorded as success or blindly retried.
        local before=g.lastSent
        C_ChatInfo.SendChatMessage=function() error('restricted') end
        g:OnEvent('GROUP_JOINED',1); Flush()
        assert(g.lastSent==before and not g.pending and not g.deadline)
        g:Disable()
        -- Enabling late in a session cannot wait forever for the login event.
        function IsLoggedIn() return true end
        g.ready=nil; grouped=false; g:Enable(); assert(g.ready)
        grouped=true; g:OnEvent('GROUP_JOINED',1); assert(g.pending)
        g:Disable(); Flush()
        for _,message in ipairs(sent) do assert(message[1]=='hi' and message[2]=='PARTY') end
        -- Both supported chat APIs must send the same unbranded greeting.
        now=500; grouped=false; g:Enable(); g:OnEvent('GROUP_LEFT',1)
        local legacyCalls=0
        C_ChatInfo.SendChatMessage=nil
        function SendChatMessage(text,channel)
            assert(text=='hi' and channel=='PARTY'); legacyCalls=legacyCalls+1
        end
        grouped=true; g:OnEvent('GROUP_JOINED',1); Flush()
        assert(legacyCalls==1 and not g.pending)
        g:Disable()
    ''')


def test_listing_default():
    lua = runtime()
    lua.execute(TIMERS + r'''
        hooks={}; calls=0
        function hooksecurefunc(name,fn) hooks[name]=fn end
        function LFGListEntryCreation_Show() error('must not open native form') end
        function LFGListEntryCreation_Select() error('must not select native activity') end
        function LFGListEntryCreation_IsEditMode(panel) return panel.edit or false end
        function LFGListEntryCreation_OnPlayStyleSelectedInternal(panel,value)
            assert(secureContext); calls=calls+1; panel.generalPlaystyle=value
        end
        function securecallfunction(fn,...) secureContext=true; fn(...); secureContext=false end
        Enum.LFGEntryGeneralPlaystyle={None=0,FunSerious=3}
        C_LFGList={GetActivityInfoTable=function() return {isMythicPlusActivity=mythic} end}
        mythic=true; LFGListFrame={EntryCreation=NewWidget(UIParent)}
        LFGListFrame.EntryCreation.selectedActivity=42; LFGListFrame.EntryCreation:Show()
    ''')
    load(lua, 'Modules/ListingDefaults.lua')
    lua.execute(r'''
        local d=JP.ListingDefaults; local p=LFGListFrame.EntryCreation
        d:Enable(); hooks.LFGListEntryCreation_Show(); hooks.LFGListEntryCreation_Select()
        assert(#timers==1); Flush(); assert(calls==1 and p.generalPlaystyle==3)
        p.generalPlaystyle=2; d:Queue(); Flush(); assert(calls==1,'keep user choice')
        p.generalPlaystyle=Secret(0); d:Queue(); Flush(); assert(calls==1)
        p.generalPlaystyle=0; p.edit=true; d:Queue(); Flush(); assert(calls==1,'keep editing')
        p.edit=false; mythic=false; d:Queue(); Flush(); assert(calls==1)
        mythic=true; combat=true; d:Queue(); Flush(); assert(calls==1)
        combat=false; p:Hide(); d:Queue(); Flush(); assert(calls==1)
        p:Show(); d:Queue(); d:Disable(); Flush(); assert(calls==1)
        local count=allocations
        for i=1,1000 do d:Enable(); hooks.LFGListEntryCreation_Show(); d:Disable(); Flush() end
        assert(count==allocations and not next(d.frame.events) and not d.pending)
    ''')
    text = source('Modules/ListingDefaults.lua')
    assert 'panel.generalPlaystyle =' not in text
    assert 'C_LFGList.SetEntryTitle(' not in text


def test_devour():
    lua = runtime()
    lua.execute(TIMERS)
    load(lua, 'Modules/DungeonTimer.lua')
    lua.execute(r'''
        local t=JP.DungeonTimer
        t.frame=NewWidget(UIParent); t.affix=UI.HUDBar(t.frame,22); t.active=true
        t.LayoutRows=function(self) self.affix:SetShown(self.affixDuration~=nil or self.affixEstimate==true) end
        auras={}; queryCount=0
        C_UnitAuras={GetUnitAuraBySpellID=function(unit,id)
            assert(id==440313); queryCount=queryCount+1; return auras[unit]
        end,GetAuraDuration=function() return Duration(11) end}
        t:RefreshAffix(); assert(not t.affix.shown)
        auras.party1={auraInstanceID=1,duration=15,expirationTime=115}
        t:RefreshAffix(); assert(t.affix.shown and t.affix.left.text=='Снять аффикс')
        assert(t.devourWave==100 and not t.devourInterval)
        auras.player={auraInstanceID=2,duration=15,expirationTime=115.1}
        t:RefreshAffix(); assert(not t.devourInterval,'do not count other party members as a new wave')
        auras={}; t:RefreshAffix(); assert(not t.affix.shown,'one wave cannot predict interval')
        now=175; auras.party2={auraInstanceID=3,duration=15,expirationTime=190}
        t:RefreshAffix(); assert(t.devourInterval==75 and t.devourNext==250)
        auras={}; now=190; t:RefreshAffix()
        assert(t.affixEstimate and t.affix.value==60 and t.affix.left.text=='~ Следующий разлом')
        now=251; t:RefreshAffix(); assert(not t.affix.shown,'no countdown forever after a missed wave')
        auras.player=Secret('aura'); t:RefreshAffix(); assert(not t.affix.shown)
        auras.player={auraInstanceID=4,duration=Secret(15),expirationTime=Secret(270)}
        t:RefreshAffix(); assert(t.affix.shown and t.devourNext==250,'secret time must not calibrate')
        assert(t:IsAffixEvent({spellID=440313,spellName=Secret('Rift')}))
        assert(not t:IsAffixEvent({spellID=Secret(440313),spellName=Secret('Rift')}))
        t.finished=true; t:RefreshAffix(); assert(not t.affix.shown)
    ''')


def test_control_actions():
    lua = runtime()
    load(lua, 'Modules/ControlAssist.lua')
    lua.execute(r'''
        for _,id in ipairs({102793,132469,99,5211,20549}) do learned[id]=true end
        local c=JP.ControlAssist; c:Enable()
        assert(c.frame.width==258 and c.frame.height==70 and not c.label)
        assert(c.sequence:GetAttribute('macrotext')=='/castsequence [@player] reset=60 Spell102793, Spell132469, Spell99, Spell20549')
        for i,b in ipairs(c.icons) do
            assert(b.width==42 and b.height==42 and b.clicks[1]=='AnyDown' and b.clicks[2]=='AnyUp')
            assert(b:GetAttribute('useOnKeyDown')==false)
            assert(b:GetAttribute('unit')==(b.spellID==5211 and 'target' or nil))
        end
        c:SetUnlocked(true); assert(c.sequence:GetAttribute('type')==nil)
        c:SetUnlocked(false); assert(c.sequence:GetAttribute('type')=='macro')
        local macro=c.sequence:GetAttribute('macrotext'); combat=true
        learned[102793]=false; c:CacheSpells(); assert(c.sequence:GetAttribute('macrotext')==macro)
        c:Disable(); combat=false; c.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
        assert(c.sequence:GetAttribute('type')==nil and not next(c.events.events))
    ''')


def test_all_class_controls():
    lua = runtime()
    load(lua, 'Modules/ControlAssist.lua')
    lua.execute(r'''
        local c=JP.ControlAssist; c:Enable(); local built=allocations
        -- One actual learned CC from each class, plus all supported racials.
        for _,id in ipairs({207167,179057,102793,368970,19577,31661,119381,
            853,8122,408,192058,30283,46968,20549,255654,107079,287712,357214,474421}) do
            wipe(learned); learned[id]=true; c:CacheSpells()
            assert(#c.spells==1 and c.spells[1]==id, 'missing class/race spell '..id)
            assert(c.icons[1]:GetAttribute('spell')==id and c.icons[1]:GetAttribute('type')=='spell')
        end
        wipe(learned)
        for _,id in ipairs({179057,207684,202137,217832,211881,202138,368970,357214}) do learned[id]=true end
        c:CacheSpells(); assert(#c.spells==8 and c.frame.width==258 and c.frame.height==132)
        assert(c.icons[6].points[1][2]==8 and c.icons[6].points[1][3]==-70)
        assert(not c.sequence:GetAttribute('macrotext'):find('@player',1,true), 'targeted CC must not target self')
        assert(c.icons[4]:GetAttribute('unit')=='target')
        combat=true; wipe(learned); c:CacheSpells(); assert(#c.spells==8)
        combat=false; c.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
        assert(#c.spells==0 and c.sequence:GetAttribute('type')==nil)
        for i=1,1000 do c:CacheSpells(); c:Update(); c:Refresh() end
        assert(allocations==built, 'spell changes must reuse the fixed button pool')
    ''')


def test_battle_res_and_finish():
    lua = runtime()
    lua.execute(r'''
        calls=0; now=100; worldTime=100
        function GetWorldElapsedTimers() return 1 end
        function GetWorldElapsedTime() return 'key',worldTime,1 end
        C_Spell.GetSpellCharges=function(id) assert(id==20484); calls=calls+1; return chargeInfo end
        C_Spell.GetSpellChargeDuration=function() error('personal duration is not the shared recharge') end
        JP.API.GetChallengeCompletion=function() return {mapID=1,duration=111000} end
        JP.API.GetChallengeDeaths=function() return {count=2,timeLost=10} end
        C_Scenario={GetStepInfo=function() return nil,nil,criteriaCount end}
        C_ScenarioInfo={GetCriteriaInfo=function(i)
            if i==3 then return {isWeightedProgress=true,totalQuantity=200,quantityString='190'} end
            return {description='Boss '..i,criteriaID=i,completed=i==1}
        end}
    ''')
    load(lua, 'Modules/DungeonTimer.lua')
    lua.execute(r'''
        local t=JP.DungeonTimer; t:Create(); t.running=true; t.active=true; t.mapID=1; t.limit=120
        local icon=t.bres.icon; local iconCount=allocations
        assert(icon and icon.texture==20484 and icon.drawLayer=='OVERLAY' and icon.sublevel==1)
        for _,progress in ipairs({0,.25,.5,.75,1}) do
            t.bres:SetValue(progress)
            assert(t.bres.icon==icon and icon.drawLayer=='OVERLAY' and icon.shown and icon.alpha==1,
                'BR icon must stay above the growing status-bar fill')
        end
        assert(allocations==iconCount,'BR progress must reuse its icon')
        criteriaCount=3; t:RefreshCriteria(true)
        assert(t.rows[1].name.font[2]==12 and t.title.font[2]==13 and t.timeBar.left.font[2]==18)
        t:UpdateClock(); assert(not t.bres.shown and not t.bresKnown)
        chargeInfo={currentCharges=1,maxCharges=5,cooldownStartTime=100,cooldownDuration=87}
        t.bresDirty=true; t:UpdateClock()
        assert(t.bres.shown and t.bres.left.text=='BR  1' and t.bres.right.text=='+1 через 87 с')
        local queried=calls; local built=allocations
        for i=1,10000 do t:UpdateClock() end
        assert(calls==queried and allocations==built, 'BR reads at most once per second without new charge events')
        chargeInfo.currentCharges=0; chargeInfo.cooldownDuration=Secret(45); now=101; t:UpdateClock()
        assert(t.bres.left.text=='BR  0' and t.bres.right.text=='—')
        chargeInfo.currentCharges=Secret(1); now=102; t:UpdateClock()
        assert(issecretvalue(t.bres.left.text), 'restricted count goes to native sink')
        chargeInfo=Secret({}); now=103; t:UpdateClock(); assert(not t.bres.shown)
        chargeInfo={currentCharges=5,maxCharges=5}; chargeDuration=Duration(0)
        now=104; t:UpdateClock(); assert(t.bres.right.alpha==0)
        chargeDuration=nil; chargeInfo={currentCharges=1,maxCharges=5,cooldownStartTime=100,cooldownDuration=20}
        now=105; t:UpdateClock(); assert(t.bres.right.text=='+1 через 15 с')
        chargeInfo.cooldownStartTime=Secret(100); now=106; t:UpdateClock(); assert(t.bres.right.text=='—')
        -- The terminal criteria event can arrive before the completion event.
        criteriaCount=0; t:RefreshCriteria(false)
        assert(t.rowCount==2 and t.forces.left.text=='95.00%')
        worldTime=nil; t:Finish()
        assert(t.elapsed==111 and t.rowCount==2 and t.forces.left.text=='100.00%')
        assert(t.forces.right.text=='200 / 200' and t.rows[2].time.text=='1:51')
        assert(not t.bres.shown and not t.frame.scripts.OnUpdate)
        criteriaCount=3; t:RefreshCriteria(false); t:Refresh()
        assert(t.forces.left.text=='100.00%' and not t.frame.scripts.OnUpdate, 'late updates cannot erase finish')
        t:Disable(); assert(not t.bresDuration and not next(t.events.events))
    ''')


def test_loot_tooltip_fallback():
    lua = runtime()
    tooltip = source('Modules/GroupSearchUI.lua').split('function GroupSearchUI.ShowLootItemTooltip', 1)[1].split('local function LayoutCardLoot', 1)[0]
    lua.execute(r'''
        function L(s) return s end
        GroupSearchUI={LootDelta=function() return 'delta' end}
        requests=0; compared=0; cached=false
        C_Item={RequestLoadItemDataByID=function() requests=requests+1 end,
            IsItemDataCachedByID=function() return cached end}
        function GameTooltip_ShowCompareItem() compared=compared+1 end
        GameTooltip={SetOwner=function(self,b) self.owner=b; self.lines={} end,
            SetHyperlink=function(self,link) self.link=link; self.itemID=nil end,
            SetItemByID=function(self,id) self.itemID=id; self.link=nil end,
            AddLine=function(self,text) self.lines[#self.lines+1]=text end,Show=function() end,
            SetText=function() error('item stats must not be replaced by a title') end}
    ''')
    lua.execute('function GroupSearchUI.ShowLootItemTooltip' + tooltip)
    lua.execute(r'''
        local button={item={itemID=123,name='item',tooltipLink='item:123:base'}}
        GroupSearchUI.ShowLootItemTooltip(button)
        assert(GameTooltip.link=='item:123:base' and compared==0 and requests==1)
        assert(#GameTooltip.lines==1 and GameTooltip.lines[1]:find('Атласа',1,true))
        button.item.tooltipLink=nil; GroupSearchUI.ShowLootItemTooltip(button,true)
        assert(GameTooltip.itemID==123 and requests==1, 'loaded callback must not request again')
        button.item.link='item:123:scaled'; button.item.level=311; button.item.keyLevel=10
        cached=true; GroupSearchUI.ShowLootItemTooltip(button)
        assert(GameTooltip.link=='item:123:scaled' and compared==1 and requests==1)
        assert(GameTooltip.lines[1]=='Дроп +10: 311')
    ''')


def test_resurrection_safety():
    lua = runtime()
    load(lua, 'Modules/Convenience.lua')
    lua.execute(r'''
        db.convenience={resurrection=true}; accepted=0; hidden=0; fighting={}
        units.player={name='Me',dead=true}; units.party1={name='Healer'}; units.party2={name='Tank'}
        function UnitAffectingCombat(unit) return fighting[unit] or false end
        function IsEncounterInProgress() return encounter or false end
        function IsInInstance() return true,raid and 'raid' or 'party' end
        function IsShiftKeyDown() return shift or false end
        function AcceptResurrect() accepted=accepted+1 end
        function StaticPopup_Hide() hidden=hidden+1 end
        local c=JP.Convenience
        fighting.party1=true; c:AcceptResurrection('Healer'); assert(accepted==0,'caster fighting while corpse is not')
        fighting.party1=false; fighting.party2=true; c:AcceptResurrection('Healer'); assert(accepted==0,'tank fighting')
        fighting.party2=Secret(true); c:AcceptResurrection('Healer'); assert(accepted==0,'unknown combat stays manual')
        fighting.party2=false; encounter=true; c:AcceptResurrection('Healer'); assert(accepted==0,'boss encounter')
        encounter=false; combat=true; c:AcceptResurrection('Healer'); assert(accepted==0)
        combat=false; shift=true; c:AcceptResurrection('Healer'); assert(accepted==0)
        shift=false; c:AcceptResurrection(Secret('Healer')); c:AcceptResurrection('Failure Detection Pylon')
        c:AcceptResurrection('Brazier of Awakening'); assert(accepted==0)
        c:AcceptResurrection('Healer'); assert(accepted==1 and hidden==0)
        function UnitFullName(unit) return units[unit] and units[unit].name,'Realm' end
        c:AcceptResurrection('Healer-Realm'); assert(accepted==2)
        raid=true; units.raid1={name='Healer'}; units.raid2={name='Tank'}; fighting.raid2=true
        c:AcceptResurrection('Healer-Realm'); assert(accepted==2)
        fighting.raid2=false; c:AcceptResurrection('Healer-Realm'); assert(accepted==3)
        function IsInInstance() return true,Secret('raid') end
        c:AcceptResurrection('Healer-Realm'); assert(accepted==3,'unknown instance stays manual')
        function IsInInstance() return true,'raid' end
        c:Create()
        fighting.raid1=true; c.events.scripts.OnEvent(c.events,'RESURRECT_REQUEST','Healer-Realm')
        assert(accepted==3,'event forwards caster name and checks combat')
        fighting.raid1=false; c.events.scripts.OnEvent(c.events,'PLAYER_REGEN_ENABLED')
        assert(accepted==3,'combat ending must not auto-accept old resurrection')
        c.events.scripts.OnEvent(c.events,'RESURRECT_REQUEST','Healer-Realm')
        assert(accepted==4,'new out-of-combat request works through event')
        db.convenience.resurrection=false; c:AcceptResurrection('Healer'); assert(accepted==4 and hidden==0)
    ''')


def test_temple_healer():
    lua = runtime()
    lua.execute(r'''
        instance=1877
        function GetInstanceInfo() return nil,nil,nil,nil,nil,nil,nil,instance end
        function UnregisterStateDriver(f) f.condition=nil end
        local methods=getmetatable(UIParent).__index
        -- Model the actual template script. The old fixture executed the
        -- restricted snippet directly and missed SetScript replacing its
        -- dispatcher, which kept the real frame hidden indefinitely.
        local originalCreate=CreateFrame
        function CreateFrame(kind,name,parent,template)
            local f=originalCreate(kind,name,parent,template)
            if template and template:find('SecureUnitButtonTemplate',1,true) then
                f.scripts.OnClick=function(self)
                    assert(type(self:GetAttribute('unit'))=='string', 'ExecuteBinding requires a target token')
                end
            end
            if template and template:find('SecureHandlerStateTemplate',1,true) then
                f.scripts.OnAttributeChanged=function(self,key,value)
                    if key:sub(1,6)=='state-' then
                        local snippet=self:GetAttribute('_on'..key)
                        if snippet then
                            local previous=engine; engine=true
                            assert(load('return function(self,newstate) '..snippet..' end'))()(self,value)
                            engine=previous
                        end
                    end
                end
            end
            return f
        end
        function methods:HookScript(key,fn)
            local previous=self.scripts[key]
            self.scripts[key]=function(...)
                if previous then previous(...) end
                fn(...)
            end
        end
        function methods:SetAttribute(key,value)
            assert(not combat or engine, 'only secure driver can change the heal target in combat')
            local previous=self.attrs and self.attrs[key]
            self.attrs=self.attrs or {}; self.attrs[key]=value
            if previous~=value and self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self,key,value) end
        end
    ''')
    load(lua, 'Modules/TempleHealer.lua')
    lua.execute(r'''
        local h=JP.TempleHealer; h:Enable(); local f=h.frame; local built=allocations
        assert(f:GetAttribute('mb-enabled') and ClickCastFrames[f] and not f.shown)
        assert(f:GetAttribute('*type1')=='target' and f:GetAttribute('useOnKeyDown')==false)
        assert(f.condition:find('[@boss1,exists,help]',1,true) and f.condition:find('[@boss5,exists,help]',1,true))
        local function driver(frame,state)
            local old=engine; engine=true
            frame:SetAttribute('state-healtarget',state)
            engine=old
        end
        units.boss1={name=Secret('Avatar')}
        combat=true; engine=true; driver(f,'boss1'); engine=false
        h:Update(); assert(f.shown and f:GetAttribute('unit')=='boss1' and issecretvalue(f.name.text))
        for i=1,1000 do h:Update() end
        assert(allocations==built and not f.scripts.OnUpdate,'event-driven fixed frame')
        h:Apply(); assert(h.pending and f:GetAttribute('unit')=='boss1')
        engine=true; driver(f,'none'); engine=false; assert(not f.shown and not f:GetAttribute('unit'))
        combat=false; instance=1; h:Apply(); driver(f,'boss1'); assert(not f.shown)
        instance=1877; h:Apply(); driver(f,'boss1'); assert(f.shown)
        h:Disable(); driver(f,'boss1'); assert(not f.shown and not next(h.events.events))
        h:Enable(); h:SetUnlocked(true)
        local preview=h.previewFrame
        assert(not f.shown and not f:GetAttribute('unit') and not f:GetAttribute('mb-enabled'))
        assert(preview.shown and not preview.scripts.OnClick and not ClickCastFrames[preview])
        built=allocations
        for i=1,100 do h:SetUnlocked(false); h:SetUnlocked(true) end
        assert(allocations==built,'reuse a single isolated preview')
        h:SetUnlocked(false); assert(not preview.shown and f:GetAttribute('state-healtarget')=='none')
        driver(f,'boss1'); assert(f.shown and f:GetAttribute('unit')=='boss1','real template dispatch survives repaint hook')
        f.scripts.OnClick(f)
        driver(f,'none'); assert(not f.shown)
        db.interfaceUnlocked=true; h:Disable(); h:Enable()
        assert(not f.shown and preview.shown and h.preview,'manual mover mode uses the plain preview')
    ''')


def test_outgoing_chat_policy():
    # Automatic party greetings are configurable plain text, defaulting to hi. Other addon-
    # authored messages retain branding; sync packets and user text are separate.
    focus = source('Modules/InterruptAssist.lua')
    greeting = source('Modules/PartyGreeting.lua')
    history = source('Modules/RunHistory.lua')
    assert 'SendChatMessage("[MythicBoost] My interrupt focus: {rt"' in focus
    assert 'pcall(send, self:GetText(), "PARTY")' in greeting
    assert 'local PLAY_INVITE_MESSAGE = "[MythicBoost] Hi!' in history
    assert 'L("Мой фокус для прерывания: ")' not in focus


def test_native_boss_restore():
    lua = runtime()
    lua.execute(r'''
        manager={RemoveManagedFrame=function(self,frame) self.removed=frame end,
            AddManagedFrame=function(self,frame) self.added=frame end}
        BossTargetFrameContainer.layoutParent=manager
        for i=1,5 do _G['Boss'..i..'TargetFrame']=NewWidget(BossTargetFrameContainer) end
        function SetPortraitTexture(texture,unit) texture.unit=unit end
    ''')
    load(lua, 'Modules/BossFrames.lua')
    lua.execute(r'''
        local b=JP.BossFrames; b:Enable()
        assert(BossTargetFrameContainer.ignoreFramePositionManager==true)
        assert(Boss1TargetFrame.parent==b.hider and b.rows[1].portrait.unit=='boss1')
        BossTargetFrameContainer.parent=UIParent -- simulate another layout restore
        assert(Boss1TargetFrame.parent==b.hider,'container reopening cannot revive its child frames')
        b:Apply(); assert(BossTargetFrameContainer.parent==b.hider)
        b:Disable(); assert(Boss1TargetFrame.parent==BossTargetFrameContainer)
        assert(BossTargetFrameContainer.parent==UIParent and BossTargetFrameContainer.ignoreFramePositionManager==nil)
        assert(manager.added==BossTargetFrameContainer and not next(b.nativeFrames))
    ''')


if __name__ == '__main__':
    for test in (test_summon, test_party_greeting, test_listing_default, test_devour,
                 test_control_actions, test_all_class_controls, test_battle_res_and_finish,
                 test_loot_tooltip_fallback, test_resurrection_safety, test_temple_healer, test_outgoing_chat_policy, test_native_boss_restore):
        test()
        print(test.__name__ + ': OK')
