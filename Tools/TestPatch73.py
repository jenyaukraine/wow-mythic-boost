"""Executable regressions for forbidden tooltips, guild hover and run grades.

These mocks test addon decisions/lifecycle, not live Blizzard taint or rendering.
"""
from TestDungeonHUD import runtime
from TestHudPolish import load


def test_forbidden_tooltip():
    lua = runtime()
    lua.execute(r'''
        UI.colors.surfaceEdge=UI.colors.hudEdge; UI.colors.accent={.1,.8,1,1}
        db.minimalUI=true; deferred={}; callbacks={}
        C_Timer={After=function(_,fn) deferred[#deferred+1]=fn end}
        function Flush()
            local pending=deferred; deferred={}; for _,fn in ipairs(pending) do fn() end
        end
        function GuardedWidget()
            local base=NewWidget(); local state={blocked=false}
            function base:HookScript(event,fn)
                callbacks[event]=callbacks[event] or {}; table.insert(callbacks[event],fn)
            end
            return setmetatable({}, {
                __index=function(_,key)
                    if key=='IsForbidden' then return function() return state.blocked end end
                    assert(not state.blocked, 'forbidden read: '..key)
                    return base[key]
                end,
                __newindex=function(_,key,value)
                    assert(not state.blocked, 'forbidden write: '..key); base[key]=value
                end
            }),state
        end
        GameTooltip,tipState=GuardedWidget()
        GameTooltip.NineSlice,sliceState=GuardedWidget()
        Enum.TooltipDataType={Unit=1}
        TooltipDataProcessor={AddTooltipPostCall=function(_,fn) unitCallback=fn end}
        function Fire(event) for _,fn in ipairs(callbacks[event] or {}) do fn(GameTooltip) end end
    ''')
    load(lua, 'Modules/PlayerTooltip.lua')
    lua.execute(r'''
        JP.modules.PlayerTooltip:Create()
        assert(GameTooltip.NineSlice.alpha==0 and GameTooltip.__mbBackdrop.shown)
        local count=allocations
        for i=1,1000 do Fire('OnShow') end
        assert(#deferred==1 and allocations==count, 'coalesce deferred skinning and reuse textures')
        tipState.blocked=true
        Fire('OnShow'); Fire('OnTooltipCleared'); unitCallback(GameTooltip); Flush()
        assert(#deferred==0 and allocations==count)
        tipState.blocked=false; sliceState.blocked=true
        Fire('OnShow'); assert(#deferred==0, 'NineSlice can be forbidden independently')
        db.minimalUI=false; Fire('OnShow') -- restoration must not touch a forbidden child
        sliceState.blocked=false; Fire('OnShow'); Flush()
        assert(GameTooltip.NineSlice.alpha==1 and not GameTooltip.__mbBackdrop.shown)
        db.minimalUI=true; Fire('OnShow'); sliceState.blocked=true; Flush()
        sliceState.blocked=false; Fire('OnShow'); Flush()
        assert(GameTooltip.NineSlice.alpha==0 and allocations==count)
    ''')


def test_tooltip_timed_run_count():
    lua = runtime()
    lua.execute(r'''
        UI.colors.surfaceEdge=UI.colors.hudEdge; UI.colors.accent={.1,.8,1,1}
        C_Timer={After=function(_,fn) fn() end}
        GameTooltip=NewWidget(); lines={}
        function GameTooltip:AddLine() end
        function GameTooltip:AddDoubleLine(label,text) lines[label]=text end
        function GameTooltip:GetUnit() return 'Player','player' end
        function UnitFullName() return 'Player','Realm' end
        function JP:GetPositivePlayer() end
        units.player={name='Player',guid='P1'}
        Enum.TooltipDataType={Unit=1}
        TooltipDataProcessor={AddTooltipPostCall=function(_,fn) unitCallback=fn end}
        local runs={}
        for i=1,8 do runs[i]={level=16,chests=1,dungeon={name='Dungeon '..i}} end
        keystone={sortedDungeons=runs,keystoneMilestone10=21,keystoneMilestone12=32,
            keystoneMilestone15=5,keystoneMilestone7=99}
        RaiderIO={GetProfile=function() return {mythicKeystoneProfile=keystone} end}
        function Count()
            GameTooltip.__jpDungeonKey=nil; lines={}; unitCallback(GameTooltip)
            return lines['В таймер +10 и выше за сезон (Raider.IO)']
        end
    ''')
    load(lua, 'Modules/PlayerTooltip.lua')
    lua.execute(r'''
        JP.modules.PlayerTooltip:Create()
        assert(Count()=='58','sum timed runs across level ranges, not eight best dungeon records')
        keystone.keystoneMilestone20=4
        assert(Count()=='62','higher milestone ranges must not be omitted')
        keystone.keystoneMilestone20=nil; keystone.keystoneMilestone15=200
        assert(Count()=='253+','quantized or capped buckets remain lower bounds')
        keystone.keystoneMilestone10=100; keystone.keystoneMilestone12=199; keystone.keystoneMilestone15=0
        assert(Count()=='299','an exact sum above 255 is not itself a rounded bucket')
        keystone.keystoneMilestone10=nil
        assert(Count()=='Нет данных','best records cannot substitute for missing run counts')
        keystone.keystoneMilestone10=Secret(30)
        assert(Count()=='Нет данных','the threshold bucket is guarded before any comparison')
        keystone.keystoneMilestone10=0; keystone.keystoneMilestone12=0
        assert(Count()=='0','known zero is distinct from unavailable data')
        for _,bad in ipairs({Secret(30),-1,.5,math.huge,0/0,'30'}) do
            keystone.keystoneMilestone12=bad
            assert(Count()=='Нет данных','invalid/secret counters must not become made-up totals')
        end
        local built=allocations
        keystone.keystoneMilestone12=32
        for i=1,1000 do assert(Count()=='32') end
        assert(allocations==built,'hover refreshes do not allocate new frames')
    ''')


def test_guild_key_tooltip():
    lua = runtime()
    lua.execute(r'''
        for _,key in ipairs({'line','lineSoft','row','rowAlt','raised','faint'}) do UI.colors[key]={.1,.2,.3,1} end
        function UI.Panel(parent) return NewWidget(parent) end
        function UI.ClassIcon() return '' end
        function UI.ClassColor() return .3,.8,1 end
        columns={}; cells={}; reads=0
        for i=1,8 do
            columns[i]={key=i,name='Dungeon '..i,texture=i}
            cells[i]={value='++'..(i+10),grade='plusTwo'}
        end
        JP.GroupSearchUI={
            GetPartyDungeonColumns=function() return columns end,
            GetDungeonCells=function(_,name,class)
                assert(name=='Player-Realm' and class=='MAGE', 'must use the hovered member full name')
                reads=reads+1
                if not missing then return cells end
            end,
            GetRunGradeColor=function(_,grade) return grade=='plusTwo' and {.3,.92,.56} or {.3,.3,.3} end,
        }
    ''')
    load(lua, 'Modules/GuildBoard.lua')
    lua.execute(r'''
        local g=JP.GuildBoard; local owner=NewWidget()
        owner.entry={fullName='Player-Realm',classFile='MAGE',score=3456}
        g:ShowKeyTooltip(owner); local tip=g.keyTooltip; local built=allocations
        assert(tip.owner==owner and tip.strata=='TOOLTIP' and tip.width==440 and #tip.rows==8)
        assert(tip.score.text==3456 and tip.rows[8].name.text=='Dungeon 8' and tip.rows[8].value.text=='++18')
        assert(tip.rows[8].icon.texture==8 and tip.rows[1].value.color[2]==.92)
        for i=1,1000 do g:ShowKeyTooltip(owner) end
        assert(allocations==built, 'one reused tooltip and fixed row pool')
        missing=true; g:ShowKeyTooltip(owner)
        assert(tip.rows[1].value.text=='—' and tip.footer.text=='Нет данных')
        g:HideKeyTooltip({}); assert(tip.shown)
        g:HideKeyTooltip(owner); assert(not tip.shown and not tip.owner)
        -- Recycling a hovered roster row must not display the previous player.
        local row=NewWidget(); row.entry=owner.entry; g.keyTooltip.owner=row; tip:Show()
        g.rows={row}; g.entries={}; g:RenderRows()
        assert(row.entry==nil and not tip.shown and not tip.owner)
        g:ShowKeyTooltip(owner); g:Disable(); assert(not tip.shown and not tip.owner)
    ''')


def test_run_upgrade_status():
    lua = runtime()
    load(lua, 'Modules/RunHistory.lua')
    lua.execute(r'''
        local h=JP.RunHistory; h.page=NewWidget(); h.Layout=function() end; h.RenderPlayers=function() end
        for _,key in ipairs({'reportTitle','reportStatusText','reportStatus','reportLoss','reportSegment','scrollBar'}) do
            h[key]=NewWidget()
        end
        for _,key in ipairs({'reportTime','reportDeaths','reportInterrupts','reportInsight'}) do
            h[key]=NewWidget(); h[key].value=NewWidget(); h[key].note=NewWidget()
        end
        local run={mapName='Temple',level=10,duration=1182,onTime=true,upgrades=2}
        db.runHistory={runs={run},players={}}
        h:Refresh(); assert(h.reportStatusText.text=='В ТАЙМЕР  +2')
        for grade=1,3 do
            run.upgrades=grade; h:Refresh(); assert(h.reportStatusText.text=='В ТАЙМЕР  +'..grade)
        end
        for _,grade in ipairs({0,4,-1,1.5,Secret(2)}) do
            run.upgrades=grade; h:Refresh(); assert(h.reportStatusText.text=='В ТАЙМЕР')
        end
        run.upgrades=nil; h:Refresh(); assert(h.reportStatusText.text=='В ТАЙМЕР')
        run.upgrades=2; run.onTime=false; h:Refresh(); assert(h.reportStatusText.text=='НЕ В ТАЙМЕР')
        run.practiceRun=true; h:Refresh(); assert(h.reportStatusText.text=='ТРЕНИРОВОЧНЫЙ')
    ''')


if __name__ == '__main__':
    for test in (test_forbidden_tooltip, test_tooltip_timed_run_count, test_guild_key_tooltip, test_run_upgrade_status):
        test()
        print(test.__name__ + ': OK')
