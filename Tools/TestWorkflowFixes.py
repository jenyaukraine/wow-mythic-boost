"""Regression tests for owned loot, signup roles and responsive tracker settings."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def load(lua, name):
    # Загружаем Contracts.lua для доступа к API
    contracts = (ROOT / 'MythicBoost/Contracts.lua').read_text(encoding='utf-8')
    lua.eval("function(code) return assert(load(code))('MythicBoost', JP) end")(contracts)
    source = (ROOT / 'MythicBoost/Modules' / name).read_text(encoding='utf-8')
    lua.eval("function(code) return assert(load(code))('MythicBoost', JP) end")(source)


def test_loot():
    lua = LuaRuntime()
    lua.execute('''
        equipped={[15]={id=101,level=311},[13]={id=102,level=311},[14]={id=900,level=300}}
        bags={[0]={{id=103,level=311},{id=104,level=300},{id=105,level=324},{id=999,level=0}}}
        bis={[101]=true,[102]=true,[103]=true,[104]=true,[105]=true,[106]=true}
        loot={}; bagScans=0; journalScans=0; timers={}; refreshes=0; requests=0
        for id=101,106 do loot[#loot+1]={itemID=id,name='item'..id,link='template',filterType=3} end
        loot[2].filterType=13
        function wipe(t) for k in pairs(t) do t[k]=nil end end
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return 105 end
        function UnitClass() return 'Druid','DRUID',11 end
        function GetInventoryItemID(_,slot) return equipped[slot] and equipped[slot].id end
        function GetInventoryItemLink(_,slot) return equipped[slot] end
        C_Item={GetDetailedItemLevelInfo=function(link)
            if type(link)=='table' then return link.level end
            return tonumber(link:match(':(%d+)$')) or 63 end,
            RequestLoadItemDataByID=function() requests=requests+1 end,
            GetItemInfoInstant=function(id) return id,nil,nil,id==999 and '' or 'INVTYPE_CLOAK' end}
        C_Container={GetContainerNumSlots=function(bag) bagScans=bagScans+1; return #(bags[bag] or {}) end,
            GetContainerItemID=function(bag,slot) return bags[bag][slot].id end,
            GetContainerItemLink=function(bag,slot) return bags[bag][slot] end}
        rewards={[2]=285,[10]=311,[12]=315}; preview=0; difficulty=2; journalID=99
        classFilter=1; specFilter=71; slotFilter=14; EncounterJournal={instanceID=99}
        C_MythicPlus={GetRewardLevelForDifficultyLevel=function(key) return 999,rewards[key] end,
            RequestRewards=function() end}
        C_EncounterJournal={GetInstanceForGameMap=function(id) return id end,
            GetSlotFilter=function() return slotFilter end,
            ResetSlotFilter=function() slotFilter=0 end,
            SetSlotFilter=function(value) slotFilter=value end,
            SetPreviewMythicPlusLevel=function(key) preview=key end,
            GetLootInfoByIndex=function(index)
                assert(difficulty==8 and preview>=2, 'preview applied before instance selection')
                assert(classFilter==11 and specFilter==105 and slotFilter==0)
                if journalFailure then error('journal loading failed') end
                local item={}; for k,v in pairs(loot[index]) do item[k]=v end
                item.link='item:'..item.itemID..':'..(unscaled and 276 or rewards[preview] or 0)
                return item
            end}
        function EJ_SelectInstance(id) journalScans=journalScans+1; journalID=id; difficulty=2; preview=0 end
        function EJ_GetDifficulty() return difficulty end
        function EJ_SetDifficulty(value) difficulty=value end
        function EJ_GetLootFilter() return classFilter,specFilter end
        function EJ_SetLootFilter(class,spec) classFilter=class; specFilter=spec end
        function EJ_GetNumLoot() return #loot end
        function CreateFrame()
            return {events={},RegisterEvent=function(self,event) self.events[event]=true end,
                SetScript=function(self,kind,fn) self[kind]=fn end}
        end
        C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
        JP={L=function(s) return s end,UI={UsableNumber=function(n) return type(n)=='number' end},
            BiSData={GetCurrentSpecID=function() return 105 end,
                GetItem=function(_,_,id) return bis[id] and {kind='bis'} end},
            modules={Welcome={frame={IsShown=function() return true end},Refresh=function() refreshes=refreshes+1 end}},
            RegisterModule=function() end}
        dungeons={{mapID=1,instanceMapID=1},{mapID=2,instanceMapID=2}}
    ''')
    load(lua, 'LootAdvisor.lua')
    lua.execute('''
        local advisor=JP.LootAdvisor
        advisor:Create()
        assert(advisor.events.events.BAG_UPDATE_DELAYED)
        local result=advisor:Analyze(dungeons)[1]
        assert(result.total==6 and result.useful==2 and result.bisCount==2 and result.percent==33)
        local found={}; for _,item in ipairs(result.upgrades) do found[item.itemID]=true end
        assert(found[104] and found[106], 'lower owned version and different equal-ilvl BIS must stay')
        assert(not found[101] and not found[102], 'equipped duplicates including second trinket slot must disappear')
        assert(not found[103] and not found[105], 'equal/better bag versions must disappear')
        assert(not advisor.cache.pending, 'non-equipment bag item must not force retries')
        assert(bagScans==5, 'only one bag snapshot for all dungeons')
        local scans=journalScans
        for i=1,1000 do advisor:Analyze(dungeons) end
        assert(journalScans==scans and bagScans==5, 'cached advice must not rescan bags or journal')
        -- Equal-ilvl swaps must change the cache signature even before the event.
        equipped[15]={id=106,level=311}
        result=advisor:Analyze(dungeons)[1]; found={}
        for _,item in ipairs(result.upgrades) do found[item.itemID]=true end
        assert(found[101] and not found[106])
        -- Acquisition and removal from bags both invalidate ownership.
        bags[0][1]={id=101,level=311}
        advisor.events:OnEvent('BAG_UPDATE_DELAYED')
        result=advisor:Analyze(dungeons)[1]; found={}
        for _,item in ipairs(result.upgrades) do found[item.itemID]=true end
        assert(not found[101] and found[103])
        local timerCount=#timers
        for i=1,10000 do advisor.events:OnEvent('BAG_UPDATE_DELAYED') end
        assert(#timers==timerCount, 'event bursts must schedule at most one UI refresh')
        timers[1](); assert(refreshes==1)
        -- Unknown ilvl never suppresses a possible upgrade and remains retryable.
        bags[0][1]={id=101,level=0}
        result=advisor:Analyze(dungeons)[1]
        assert(advisor.cache.pending and requests>0)
        bags[0][1].level=311
        advisor.events:OnEvent('GET_ITEM_INFO_RECEIVED')
        result=advisor:Analyze(dungeons)[1]
        assert(not advisor.cache.pending)
        -- All visible stats come from the native scaled hyperlink; reward API
        -- return #1 is deliberately wrong to catch weekly/chest confusion.
        assert(result.keyLevel==10 and result.dropLevel==311)
        for _,item in ipairs(result.upgrades) do
            assert(C_Item.GetDetailedItemLevelInfo(item.link)==item.level and item.level==311)
        end
        assert(journalID==99 and difficulty==2 and classFilter==1 and specFilter==71 and slotFilter==14)
        result=advisor:Analyze(dungeons,12)[1]
        assert(result.keyLevel==12 and result.dropLevel==315)
        for _,item in ipairs(result.upgrades) do assert(item.level==315 and item.link:match(':315$')) end
        result=advisor:Analyze(dungeons,2)[1]; assert(result.dropLevel==285)
        -- Do not retain a constant ilvl across seasons or changed input lists.
        rewards[12]=318
        result=advisor:Analyze(dungeons,12)[1]; assert(result.dropLevel==318)
        local expanded={{mapID=3,instanceMapID=3}}
        assert(advisor:Analyze(expanded,12)[3].dropLevel==318)
        -- A heroic/base journal response must never appear as the M+ tooltip.
        unscaled=true; advisor:Invalidate()
        result=advisor:Analyze(dungeons,12)[1]
        assert(not result.pending and #result.upgrades>0, 'unavailable scaled tooltip must not block valid recommendations')
        for _,item in ipairs(result.upgrades) do
            assert(item.link==nil and item.level==318)
            assert(item.tooltipLink:match(':276$'), 'preserve the base tooltip without calling it M+')
        end
        unscaled=false; advisor:Invalidate()
        result=advisor:Analyze(dungeons,12)[1]; assert(not result.pending)
        for _,item in ipairs(result.upgrades) do assert(item.link:match(':318$')) end
        -- Missing native rewards are not guessed from base links or constants.
        rewards[12]=nil
        result=advisor:Analyze(dungeons,12)[1]
        assert(result.rewardUnknown and result.dropLevel==nil and #result.upgrades>0)
        for _,item in ipairs(result.upgrades) do
            assert(item.recommendation and item.level==nil and item.gain==nil and item.link==nil)
            assert(item.itemID==103, 'only the unowned BIS must appear when rewards are unknown')
        end
        -- A stat/BIS goal is independent of an ilvl gain.
        rewards[12]=280
        result=advisor:Analyze(dungeons,12)[1]
        local missingBis
        for _,item in ipairs(result.upgrades) do
            if item.itemID==103 then missingBis=item end
        end
        assert(missingBis and missingBis.recommendation and missingBis.gain<0)
        -- Native ItemLocation data must work even before full links load.
        ItemLocation={CreateFromEquipmentSlot=function(_,slot)
            return {slot=slot,IsValid=function() return equipped[slot]~=nil end}
        end}
        local originalLink=GetInventoryItemLink
        GetInventoryItemLink=function() return nil end
        C_Item.GetCurrentItemLevel=function(location) return equipped[location.slot].level end
        equipped[4]={id=500,level=0} -- cosmetic shirt must not block gear loading
        rewards[12]=318
        result=advisor:Analyze(dungeons,12)[1]
        assert(result.equipmentLoaded==3 and result.equipmentTotal==3 and not result.equipmentPending)
        assert(not advisor.cache.pending)
        equipped[15].level=0
        result=advisor:Analyze(dungeons,12)[1]
        assert(result.equipmentLoaded==2 and result.equipmentPending and advisor.cache.pending)
        for _,item in ipairs(result.upgrades) do
            if item.itemID==103 then assert(item.equipped==nil and item.gain==nil and not item.isUpgrade) end
        end
        rewards[12]=nil
        result=advisor:Analyze(dungeons,12)[1]
        for _,item in ipairs(result.upgrades) do assert(item.itemID~=106) end
        equipped[15].level=311; GetInventoryItemLink=originalLink
        rewards[12]=318; journalFailure=true; advisor:Invalidate()
        assert(not pcall(advisor.Analyze,advisor,dungeons,12))
        assert(journalID==99 and difficulty==2 and classFilter==1 and specFilter==71 and slotFilter==14,
            'journal state must also be restored on failure')
    ''')


def test_signup_roles():
    lua = LuaRuntime()
    lua.execute('''
        selected={true,true,false,false}; role='HEALER'; clicked=0; setCalls=0; shown=false
        function GetSpecialization() return 1 end
        function GetSpecializationRole() return role end
        function GetLFGRoles() return table.unpack(selected) end
        function SetLFGRoles(...)
            assert(select('#',...)==4, 'leader + tank + healer + damage required')
            selected={...}; setCalls=setCalls+1
        end
        C_LFGList={GetSearchResultInfo=function() return {isDelisted=false} end}
        LFGListApplicationDialog={IsShown=function() return shown end,
            SignUpButton={IsEnabled=function() return true end,
                Click=function() clicked=clicked+1; submitted={table.unpack(selected)}; shown=false end}}
        function LFGListApplicationDialog_Show()
            shown=true
            dialogRoles={table.unpack(selected)}
        end
        JP={L=function(s) return s end,Print=function() end,RegisterModule=function() end,
            UI={SafeBoolean=function(v) return v==true end}}
    ''')
    load(lua, 'AutoMatch.lua')
    lua.execute('''
        for _,value in ipairs({'HEALER','DAMAGER','TANK'}) do
            role=value
            for _,editing in ipairs({false,true}) do
                local before=clicked
                assert(JP.AutoMatch:Apply(1,editing))
                assert(dialogRoles[1]==true, 'leader preference must be preserved')
                assert(dialogRoles[2]==(role=='TANK'))
                assert(dialogRoles[3]==(role=='HEALER'))
                assert(dialogRoles[4]==(role=='DAMAGER'))
                assert(clicked==before+(editing and 0 or 1))
            end
        end
        -- Manual changes in the opened dialog remain untouched until the next application.
        SetLFGRoles(false,false,true,false)
        assert(selected[3] and not selected[2])
        role='NONE'; local before=setCalls
        JP.AutoMatch:Apply(1,true); assert(setCalls==before, 'unknown spec must not guess tank')
        local old=clicked
        JP.AutoMatch:Apply(1,false); assert(clicked==old, 'unknown role needs manual confirmation')
        local setter=SetLFGRoles
        SetLFGRoles=function() error('unavailable') end
        role='HEALER'; JP.AutoMatch:Apply(1,false)
        assert(clicked==old, 'failed role selection must not submit the old tank role')
        SetLFGRoles=setter
        role='HEALER'; local old=clicked
        LFGListApplicationDialog_Show=function() shown=false end
        JP.AutoMatch:Apply(1,false); assert(clicked==old, 'never double-submit after another addon')
        C_LFGList.GetSearchResultInfo=function() return {isDelisted=true} end
        before=setCalls; assert(JP.AutoMatch:Apply(1,false)==false and setCalls==before)
    ''')


def test_tracker_layout():
    lua = LuaRuntime()
    source = (ROOT / 'MythicBoost/Modules/SettingsHub.lua').read_text(encoding='utf-8')
    # Compile the entire page too: catch Lua's per-function local-variable limit.
    lua.eval('function(code) assert(load(code)) end')(source)
    method = 'function SettingsHub:LayoutAuraPage()' + source.split(
        'function SettingsHub:LayoutAuraPage()', 1)[1].split('function SettingsHub:RefreshDependencies()', 1)[0]
    lua.execute('''
        SettingsHub={}; allocations=0
        function Frame(width,text)
            allocations=allocations+1
            local f={width=width or 0,height=20,text=text or ''}
            function f:ClearAllPoints() end
            function f:SetPoint(_,parent,_,x,y) self.x=x; self.y=-y end
            function f:SetWidth(w) self.width=w end
            function f:GetWidth() return self.width end
            function f:SetHeight(h) self.height=h end
            function f:SetWordWrap() end
            function f:GetStringHeight()
                local w=self.owner and (self.owner.width-self.inset) or self.width
                return math.ceil(#self.text*6/math.max(1,w))*14
            end
            return f
        end
        local page=Frame(700)
        local function Heading() return {label=Frame(),line=Frame()} end
        local layout={page=page,displayHeading=Heading(),spellHeading=Heading(),checks={},steppers={},
            preview=Frame(),input=Frame(),buttons={Frame(),Frame(),Frame(),Frame()}}
        for i=1,6 do
            local check=Frame(); check.label=Frame(nil,string.rep('long label ',6))
            check.label.owner=check; check.label.inset=26; layout.checks[i]=check
        end
        for i=1,8 do
            local row=Frame(); row.caption=Frame(nil,string.rep('caption ',5))
            row.caption.owner=row; row.caption.inset=122; layout.steppers[i]=row
        end
        SettingsHub.auraSpellSummary=Frame(nil,string.rep('many tracked spells ',40))
        SettingsHub.auraStatus=Frame(nil,string.rep('scan status ',10))
        SettingsHub.auraLayout=layout
    ''')
    lua.execute(method)
    lua.execute('''
        local layout=SettingsHub.auraLayout
        local before=allocations
        function Overlaps(a,b)
            return a.x<b.x+b.width-.01 and b.x<a.x+a.width-.01
                and a.y<b.y+b.height-.01 and b.y<a.y+a.height-.01
        end
        for _,width in ipairs({340,430,550,600,650,690,720,900,1200,690}) do
            layout.page.width=width; SettingsHub:LayoutAuraPage()
            local controls={layout.preview,layout.input,SettingsHub.auraSpellSummary,SettingsHub.auraStatus}
            for _,group in ipairs({layout.checks,layout.steppers,layout.buttons}) do
                for _,frame in ipairs(group) do controls[#controls+1]=frame end
            end
            -- FontStrings naturally grow to their measured height.
            SettingsHub.auraSpellSummary.height=SettingsHub.auraSpellSummary:GetStringHeight()
            SettingsHub.auraStatus.height=SettingsHub.auraStatus:GetStringHeight()
            for i,a in ipairs(controls) do
                assert(a.x>=28 and a.x+a.width<=width-28+.01, 'horizontal overflow at '..width)
                assert(a.y+a.height<=layout.page.height-27.99, 'bottom control is unreachable')
                for j=i+1,#controls do assert(not Overlaps(a,controls[j]), 'overlap at '..width..' '..i..' '..j) end
            end
        end
        for i=1,1000 do SettingsHub:LayoutAuraPage() end
        assert(allocations==before, 'resize must not allocate frames')
    ''')


def test_applicant_footer():
    lua = LuaRuntime()
    lua.execute(r'''
        combat=false; timers={}; allocations=0; mutations=0
        function InCombatLockdown() return combat end
        function issecretvalue(v) return type(v)=='table' and v.secret==true end
        local methods={}
        function CreateFrame()
            allocations=allocations+1
            return setmetatable({shown=true,scripts={},events={},points={}}, {__index=methods})
        end
        function methods:HookScript(k,fn)
            local old=self.scripts[k]
            self.scripts[k]=function(...) if old then old(...) end; fn(...) end
        end
        function methods:SetScript(k,fn) self.scripts[k]=fn end
        function methods:RegisterEvent(k) self.events[k]=true end
        function methods:UnregisterAllEvents() self.events={} end
        function methods:IsVisible() return self.shown end
        function methods:IsShown() return self.shown end
        function methods:GetNumPoints() return #self.points end
        function methods:GetPoint(i) return table.unpack(self.points[i]) end
        function methods:ClearAllPoints() assert(not combat); mutations=mutations+1; self.points={} end
        function methods:SetPoint(...) assert(not combat); self.points[#self.points+1]={...} end
        C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
        function Flush() local old=timers; timers={}; for _,fn in ipairs(old) do fn() end end
        JP={UI={SafeBoolean=function(v) return not issecretvalue(v) and v==true end},
            L=function(s) return s end,RegisterModule=function() end}
        C_LFGList=setmetatable({}, {__index=function() error('footer must not read listing data or invoke protected actions') end})
        viewer=CreateFrame(); viewer.BrowseGroupsButton=CreateFrame(); viewer.RemoveEntryButton=CreateFrame()
        viewer.EditButton=CreateFrame(); viewer.AutoAcceptButton=CreateFrame()
        viewer.RemoveEntryButton:SetPoint('BOTTOMLEFT',viewer,'BOTTOMLEFT',-3,4)
        originalClick=function() end; viewer.RemoveEntryButton.scripts.OnClick=originalClick
        LFGListFrame={ApplicationViewer=viewer}
    ''')
    load(lua, 'FrameSwitch.lua')
    lua.execute(r'''
        local m=JP.FrameSwitch
        assert(m:InstallApplicantLayout()); Flush()
        local p=viewer.RemoveEntryButton.points[1]
        assert(p[1]=='LEFT' and p[2]==viewer.BrowseGroupsButton and p[3]=='RIGHT' and p[4]==15)
        local before=allocations; local changes=mutations
        for i=1,1000 do m:InstallApplicantLayout(); m:QueueApplicantLayout() end
        assert(#timers==1); Flush(); assert(allocations==before and mutations==changes)
        assert(viewer.RemoveEntryButton.scripts.OnClick==originalClick)
        assert(viewer.AutoAcceptButton.shown and viewer.EditButton.shown)
        -- Hidden browse / secret visibility never turns into a new visible button.
        viewer.BrowseGroupsButton.shown=false; m:LayoutApplicantFooter(); assert(mutations==changes)
        viewer.BrowseGroupsButton.shown={secret=true}; m:LayoutApplicantFooter(); assert(mutations==changes)
        viewer.BrowseGroupsButton.shown=true
        viewer.RemoveEntryButton.points={{'BOTTOMLEFT',viewer,'BOTTOMLEFT',-3,4}}
        m:QueueApplicantLayout(); combat=true; Flush(); assert(mutations==changes)
        m:QueueApplicantLayout(); assert(#timers==0)
        combat=false; m.layoutEvents.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED'); Flush()
        assert(mutations==changes+1)
        viewer.RemoveEntryButton.points={{'BOTTOMLEFT',viewer,'BOTTOMLEFT',{secret=true},4}}
        m:LayoutApplicantFooter(); assert(mutations==changes+1)
        m:QueueApplicantLayout(); m:Disable(); Flush(); assert(mutations==changes+1)
        assert(next(m.layoutEvents.events)==nil)
        m:Enable(); Flush(); assert(m.layoutEvents.events.PLAYER_REGEN_ENABLED)
    ''')
    welcome=(ROOT/'MythicBoost/Modules/Welcome.lua').read_text(encoding='utf-8')
    assert 'local WINDOW_ALPHA = 1' in welcome
    assert 'UI.Backdrop(frame, { C.window[1], C.window[2], C.window[3], .87 }' in welcome
    on_show=welcome.split('frame:SetScript("OnShow", function()',1)[1].split('frame:SetScript("OnHide"',1)[0]
    assert 'GameTooltip_Hide()' in on_show and ':HideBlizzardResultTooltip()' in on_show


if __name__ == '__main__':
    test_loot()
    delta = (ROOT / 'MythicBoost/Modules/GroupSearchUI.lua').read_text(encoding='utf-8')
    assert '"BIS/TOP " ..' not in delta, 'verbose fallback label must not cover dungeon cards'
    delta = delta.split('function GroupSearchUI.LootDelta', 1)[1].split('local function LayoutCardLoot', 1)[0]
    lua = LuaRuntime()
    lua.execute('GroupSearchUI={}; function L(s) return s end\nfunction GroupSearchUI.LootDelta' + delta)
    lua.execute('''
        assert(GroupSearchUI.LootDelta({}):find('недоступен',1,true))
        assert(GroupSearchUI.LootDelta({level=311}):find('311',1,true))
        assert(not GroupSearchUI.LootDelta({level=311}):find('0 →',1,true))
        assert(GroupSearchUI.LootDelta({level=300,equipped=314,gain=-14}):find('(-14)',1,true))
    ''')
    test_signup_roles()
    test_tracker_layout()
    test_applicant_footer()
    print('Workflow fixes: owned loot/cache, all signup roles, responsive bounds and reuse passed')
