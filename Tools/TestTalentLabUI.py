"""Talent Lab UI: bounded source rows, build comparison and unknown data."""

from TestSocialWorkflows import client, load
from TestHudPolish import source


def fixture():
    lua = client()
    lua.execute(r'''
        local methods=getmetatable(UIParent).__index
        UI.Unpack=table.unpack
        UI.colors.accent={.2,.8,1,1}; UI.colors.text={.9,.9,.9,1}
        UI.colors.muted={.4,.4,.4,1}; UI.colors.amber={1,.7,.2,1}
        UI.colors.green={.2,.9,.5,1}; UI.colors.lineSoft={.1,.1,.1,1}
        UI.colors.surface={.014,.020,.028,.94}; UI.colors.hudEdge={.30,.32,.34,.92}
        function UI.Text(parent,_,value,color)
            local f=NewWidget(parent); f:SetText(value or ''); f.color=color; return f
        end
        function UI.HUDPanel(parent,name,w,h)
            local f=CreateFrame('Frame',name,parent); f:SetSize(w,h); return f
        end
        function methods:EnableMouseWheel(value) self.mouseWheel=value end
        function methods:SetScrollChild(child) self.child=child end
        function methods:GetVerticalScrollRange()
            return math.max(0,(self.child and self.child.height or 0)-(self.height or 0))
        end
        function methods:GetVerticalScroll() return self.offset or 0 end
        function methods:SetVerticalScroll(value) self.offset=value end
        function Number(value) return value end
        function UI.Tooltip(owner,title,...)
            tooltip={owner=owner,title=title,lines={...}}
        end
        function GameTooltip_Hide() tooltip=nil end
        GameTooltip=NewWidget(UIParent)
        local tooltipMethods=getmetatable(GameTooltip).__index
        function tooltipMethods:SetOwner(owner,anchor) self.owner=owner; self.anchor=anchor end
        function tooltipMethods:SetSpellByID(id) self.spellID=id end
        function tooltipMethods:Show() self.shown=true end
        C_Spell={GetSpellInfo=function(id) return {name='Spell '..id,iconID='Icon'..id} end}
        JP.TalentLab={}
        function JP.TalentLab:Rows(sample,metric)
            local out={}; local values=sample and sample.spells and sample.spells[metric] or {}
            for id,amount in pairs(values or {}) do out[#out+1]={spellID=id,amount=amount} end
            table.sort(out,function(a,b) return a.amount>b.amount end); return out
        end
        function JP.TalentLab:TalentRows(sample,metric)
            local out={}; local values=sample and sample.spells and sample.spells[metric] or {}
            for _,entry in pairs(sample and sample.selected or {}) do
                local id=entry.spellID; local amount=values[id]
                out[#out+1]={spellID=id,talentSpellID=id,rank=entry.rank,amount=amount,
                    kind=amount and 'direct' or 'unattributed'}
            end
            table.sort(out,function(a,b) return (a.amount or -1)>(b.amount or -1) end); return out
        end
        function JP.TalentLab:Compare(runs,metric)
            local grouped={}; local order={}
            for _,run in ipairs(runs or {}) do
                local s=run.talentSample; local g=s and grouped[s.buildKey]
                if s and s.complete and not s.mixed and not g then
                    g={specID=s.specID,gameBuild=s.gameBuild,mapID=run.mapID,level=run.level,
                        buildKey=s.buildKey,buildName=s.buildName,runs=0,duration=0,rows={}}
                    grouped[s.buildKey]=g; order[#order+1]=g
                end
                if g and s.duration and s.duration>0 then
                    g.runs=g.runs+1; g.duration=g.duration+s.duration
                    for id,amount in pairs(s.spells[metric] or {}) do g.rows[id]=(g.rows[id] or 0)+amount end
                end
            end
            for _,g in ipairs(order) do
                local rows={}; for id,amount in pairs(g.rows) do rows[#rows+1]={spellID=id,amount=amount} end
                table.sort(rows,function(a,b)return a.amount>b.amount end); g.rows=rows
            end
            return {metric=metric,builds=order}
        end
        db.runHistory={runs={
            {completedAt=300,mapID=399,mapName='Dawn',level=12,talentSample={specID=1,gameBuild='12.0',buildKey='build-b',buildName='Hero build',duration=500,overallHealing=50000,overallDamage=100000,complete=true,mixed=false,spells={healing={[1002]=30000,[1003]=20000},damage={[2002]=60000}},selected={[1]={spellID=1002,rank=1},[2]={spellID=1003,rank=1}}}},
            {completedAt=200,mapID=399,mapName='Dawn',level=12,talentSample={specID=1,gameBuild='12.0',buildKey='build-a',buildName='Base build',duration=600,overallHealing=60000,overallDamage=90000,complete=true,mixed=false,spells={healing={[1001]=36000,[1003]=24000},damage={[2001]=50000}},selected={[1]={spellID=1001,rank=1},[2]={spellID=1003,rank=1}}}},
            {completedAt=100,mapID=399,mapName='Dawn',level=12,talentSample={specID=1,gameBuild='12.0',buildKey='build-a',buildName='Base build',duration=400,overallHealing=40000,overallDamage=70000,complete=true,mixed=false,spells={healing={[1001]=20000},damage={[2001]=40000}},selected={[1]={spellID=1001,rank=1},[2]={spellID=1003,rank=1}}}},
        }}
    ''')
    load(lua, 'Modules/TalentLabUI.lua')
    lua.execute('lab=JP.TalentLab')
    return lua


def test_rows_pagination_tooltip_and_reuse():
    lua = fixture()
    lua.execute(r'''
        lab:Show()
        assert(lab.uiFrame.width==640 and lab.uiFrame.height==580)
        assert(lab.latestRun and lab.uiBuild.text:find('Hero build',1,true))
        assert(lab.keyPicker.text=='Выбрать ключ' and lab.uiSubtitle.text:find('Dawn',1,true))
        assert(lab.uiDate.text:find('8:20',1,true))
        lab.keyPicker.scripts.OnClick(lab.keyPicker)
        assert(lab.keyPickerMenu.shown and #lab.keyPickerOptions==3)
        lab.keyPickerOptions[2].scripts.OnClick(lab.keyPickerOptions[2])
        assert(lab.sampleIndex==2 and lab.uiBuild.text:find('Base build',1,true))
        assert(#lab.rows==2 and lab.rows[1].nameText.text=='Spell 1001')
        lab.keyPicker.scripts.OnClick(lab.keyPicker)
        lab.keyPickerOptions[1].scripts.OnClick(lab.keyPickerOptions[1])
        assert(lab.sampleIndex==1 and lab.uiBuild.text:find('Hero build',1,true))
        assert(#lab.rows==2 and lab.rows[1].nameText.text=='Spell 1002')
        assert(lab.rows[1].rate.text~='—' and lab.rows[1].share.text~='—')
        lab.talentButton.scripts.OnClick(lab.talentButton)
        assert(lab.sourceHeader.text=='Талант' and lab.rows[1].nameText.text=='Spell 1002')
        lab.sourceButton.scripts.OnClick(lab.sourceButton)
        assert(lab.rowScroll and lab.rowCanvas)
        -- Force a longer source list to exercise the scroll viewport.
        lab.latestRun.talentSample.spells.healing={[1001]=10,[1002]=9,[1003]=8,[1004]=7,[1005]=6,[1006]=5,[1007]=4,[1008]=3,[1009]=2}
        lab:Render(); assert(#lab.rows>=9 and lab.rowCanvas.height>=9*34)
        lab.rowScroll.scripts.OnMouseWheel(lab.rowScroll,-1)
        assert(lab.rowScroll.offset==34)
        lab.rows[1].scripts.OnEnter(lab.rows[1]); assert(GameTooltip.spellID==1001 and GameTooltip.owner==lab.rows[1])
        local created=allocations
        for i=1,1000 do lab:Show() end
        assert(allocations==created, 'Talent Lab must reuse one window and fixed row pool')
    ''')


def test_compare_is_build_comparison_and_unknown_is_explicit():
    lua = fixture()
    lua.execute(r'''
        lab:Show()
        assert(lab.compare.text:find('Сравнение сборок',1,true))
        assert(lab.compare.text:find('Условия и состав группы влияют на результат.',1,true))
        assert(lab.compare.text:find('ключей',1,true))
        lab.damageButton.scripts.OnClick(lab.damageButton)
        assert(lab.rateHeader.text=='DPS' and lab.rows[1].rate.text~='—')
        -- A mixed or partial sample must never become fabricated zeros.
        db.runHistory.runs[1].talentSample.complete=false
        db.runHistory.runs[1].talentSample.mixed=true
        lab:Show()
        assert(lab.empty.text:find('Смешанная сборка',1,true))
        for _,run in ipairs(db.runHistory.runs) do run.talentSample=nil end
        lab:Show(); assert(lab.empty.text:find('Нет измеримого снимка',1,true))
    ''')
    ui = source('Modules/TalentLabUI.lua')
    assert 'hooksecurefunc' not in ui and 'GameTooltip:Hook' not in ui


def test_talent_launcher_layering_combat_and_lifecycle():
    lua = fixture()
    lua.execute(r'''
        lab:Enable(); assert(lab.launcherEvents and not lab.talentButtonLauncher)
        PlayerSpellsFrame=NewWidget(UIParent)
        local owner=PlayerSpellsFrame
        owner:SetFrameStrata('HIGH'); owner:SetFrameLevel(5)
        for _,key in ipairs({'TitleContainer','NineSlice','TalentsFrame','MaximizeMinimizeButton','CloseButton'}) do
            owner[key]=NewWidget(owner); owner[key]:SetFrameLevel(5500)
        end
        local hookCount=0
        local methods=getmetatable(owner).__index
        local hook=methods.HookScript
        function methods:HookScript(...) hookCount=hookCount+1; return hook(self,...) end
        combat=true
        lab.launcherEvents.scripts.OnEvent(nil,'ADDON_LOADED','Blizzard_PlayerSpells')
        assert(not lab.talentButtonLauncher, 'defer native attachment in combat')
        combat=nil
        lab.launcherEvents.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
        local b=lab.talentButtonLauncher
        assert(b and b.shown and b.level==5510 and b.strata=='HIGH')
        assert(b.parent==owner and b.points[1][1]=='RIGHT' and b.points[1][2]==owner.MaximizeMinimizeButton)
        assert(b.points[1][3]=='LEFT' and b.points[1][4]==-8, 'clear of close/maximize controls')
        b.scripts.OnClick(); assert(lab.uiFrame.shown and lab.uiFrame.level>b.level)
        local created=allocations
        local hooks=hookCount
        collectgarbage('collect'); local memory=collectgarbage('count')
        for i=1,1000 do
            lab:Disable(); assert(not b.shown and next(lab.launcherEvents.events)==nil)
            owner.scripts.OnShow(); assert(not b.shown)
            lab:Enable(); owner:SetWidth(i%2==0 and 809 or 1618)
            owner.scripts.OnSizeChanged()
            owner.TalentsFrame:Hide(); owner.TalentsFrame.scripts.OnHide(); assert(not b.shown)
            owner.TalentsFrame:Show(); owner.TalentsFrame.scripts.OnShow(); assert(b.shown)
            b.scripts.OnClick()
            lab.uiFrame.scripts.OnHide()
            assert(lab.sampleRuns==nil and lab.latestRun==nil and not lab.keyPickerMenu.shown)
        end
        collectgarbage('collect')
        assert(allocations==created and hookCount==hooks, 'one launcher, no stacked hooks')
        assert(collectgarbage('count')-memory<64, 'no retained run lists or growing closures')
        assert(owner.level==5 and owner.NineSlice.level==5500, 'do not change Blizzard frame levels')
        local renders=0; lab.Show=function() renders=renders+1 end
        combat=Secret(true); b.scripts.OnClick(); assert(renders==0)
        combat=true; b.scripts.OnClick(); assert(renders==0)
    ''')


def test_scroll_pool_limits_and_bad_durations():
    lua = fixture()
    lua.execute(r'''
        local run=db.runHistory.runs[1]
        run.talentSample.spells.healing={}
        for i=1,400 do run.talentSample.spells.healing[i]=i end
        lab:Show(); assert(#lab.rows==256)
        lab.rowScroll.scripts.OnMouseWheel(nil,-100000)
        assert(lab.rowScroll.offset==256*34-270)
        local created=allocations
        for _,duration in ipairs({math.huge,0/0,Secret(50),'broken',-5}) do
            run.talentSample.duration=duration; lab:Render()
        end
        for i=1,100 do lab:Render() end
        assert(allocations==created)
        run.talentSample.spells.healing={[1]=1}
        lab:Render(); assert(lab.rowScroll.offset==0 and not lab.rows[2].shown)
        lab.uiFrame.scripts.OnHide()
        assert(not lab.sampleRuns and not lab.latestRun)
    ''')


def test_measured_talents_default_zeros_and_unknown_filter():
    lua=fixture()
    lua.execute('''
        local run=db.runHistory.runs[1]
        run.duration=1843
        run.talentSample.duration=18
        run.talentSample.selected[3]={spellID=999,rank=1}
        run.talentSample.selected[4]={spellID=888,rank=1}
        run.talentSample.spells.healing[888]=0
        lab:Show(); lab.talentButton.scripts.OnClick()
        assert(lab.uiDate.text:find('Ключ 30:43 / замер 0:18',1,true))
        assert(#lab.rows==3 and lab.rows[3].amount.text=='0')
        assert(lab.rows[3].share.text=='0.0%')
        assert(lab.coverage.text:find('С цифрами: 3',1,true))
        lab.allTalentsButton.scripts.OnClick()
        assert(lab.rows[4].kind=='unattributed')
        assert(lab.rows[4].amount.text=='Нет привязанных данных' and lab.rows[4].rate.text=='')
        lab.allTalentsButton.scripts.OnClick()
        assert(not lab.rows[4].shown)
        lab.sourceButton.scripts.OnClick(); assert(not lab.allTalentsButton.shown)
    ''')


if __name__ == "__main__":
    for test in (test_rows_pagination_tooltip_and_reuse,
                 test_compare_is_build_comparison_and_unknown_is_explicit,
                 test_talent_launcher_layering_combat_and_lifecycle,
                 test_scroll_pool_limits_and_bad_durations,
                 test_measured_talents_default_zeros_and_unknown_filter):
        test()
        print(test.__name__ + ": OK")
