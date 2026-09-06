"""Player memory UI: bounded panels, private notes and read-only stats."""

from TestSocialWorkflows import client, load


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
        function UI.Tooltip(owner,title,...)
            tooltip={owner=owner,title=title,lines={...}}
        end
        function GameTooltip_Hide() tooltip=nil end
        function date() return '05.09' end
        db.runHistory={players={['bob-realm']={runs=2,timed=1}},runs={}}
        for i=1,12 do
            db.runHistory.runs[i]={completedAt=epoch-i*86400,mapName='Dungeon '..i,
                level=10+i,onTime=i%2==0,members={'Bob-Realm'},performance={}}
        end
        db.runHistory.runs[1].performance['bob-realm']={version=1,runAt=epoch,
            role='DAMAGER',damage=120000,healing=3000,avoidable=90,duration=600,
            itemLevel=220,complete=true}
    ''')
    load(lua, 'Modules/RunStats.lua')
    load(lua, 'Modules/PlayerNetwork.lua')
    load(lua, 'Modules/PlayerMemoryUI.lua')
    lua.execute('n=JP.PlayerNetwork')
    return lua


def test_memory_panel_reuses_fixed_rows_and_shows_stats():
    lua = fixture()
    lua.execute(r'''
        n:ShowMemory('Bob-Realm')
        assert(n.frame.width==600 and n.frame.height==670)
        assert(#n.runRows==10 and n.runRows[1].stats.text:find('DPS',1,true))
        assert(n.runRows[10].shown and n.runRows[1].run ~= nil)
        local created=allocations
        for i=1,1000 do n:ShowMemory('Bob-Realm') end
        assert(allocations==created, 'memory panel and history rows must be reused')
        n.runRows[1].scripts.OnEnter(n.runRows[1])
        assert(tooltip and tooltip.lines[1]:find('DPS',1,true))
    ''')


def test_private_expiry_is_preserved_and_tags_are_manual_positive_only():
    lua = fixture()
    lua.execute(r'''
        assert(n:SavePrivate('Bob-Realm','private',7))
        local before=n:Private('Bob-Realm').avoidUntil
        n:ShowMemory('Bob-Realm')
        n.note:SetText('edited')
        n.saveButton.scripts.OnClick(n.saveButton)
        assert(n:Private('Bob-Realm').note=='edited')
        assert(n:Private('Bob-Realm').avoidUntil==before,
            'editing a note must not restart temporary Avoid')
        assert(n:Private('Bob-Realm').mask==nil, 'private notes never carry public tags')

        n:ShowMemory('Bob-Realm')
        assert(n.avoidDays==7)
        n.avoid.scripts.OnClick(n.avoid); assert(n.avoidDays==30)
        n.avoid.scripts.OnClick(n.avoid); assert(n.avoidDays==0)
        n.avoid.scripts.OnClick(n.avoid); assert(n.avoidDays==nil)
        n.avoid.scripts.OnClick(n.avoid); assert(n.avoidDays==1)
        n.avoid.scripts.OnClick(n.avoid); assert(n.avoidDays==7)

        local beforeRecords=next(db.playerNetwork.records)
        n.tagButtons[1].scripts.OnClick(n.tagButtons[1])
        assert(next(db.playerNetwork.records)==beforeRecords,
            'tag clicks are drafts; no automatic network action')
        n.saveButton.scripts.OnClick(n.saveButton)
        local own=n:GetOwn('Bob-Realm')
        assert(own and own.mask==1, 'only the selected positive tag is public')
    ''')


def test_unknown_performance_data_is_readable_and_private():
    lua = fixture()
    lua.execute(r'''
        db.runHistory.runs[1].performance=nil
        n:ShowMemory('Bob-Realm')
        assert(n.runRows[1].stats.text:find('Статистика ключа недоступна',1,true))
        assert(n.context.text:find('Вместе',1,true))
        assert(n.foot.text:find('Личная заметка',1,true)
            and n.foot.text:find('Рекомендации',1,true)
            and not n.foot.text:find('В сеть',1,true))
    ''')


def test_roster_uses_four_reusable_rows():
    lua = fixture()
    lua.execute(r'''
        units.party2={name='Bob',realm='OtherRealm'}
        units.party3={name='Dan',realm='Realm'}
        units.party4={name='Eli',realm='Realm'}
        n:ShowRoster()
        assert(#n.rosterFrame.rows==4 and n.rosterFrame.rows[4].shown)
        assert(n.rosterFrame.rows[1].target=='Bob-Realm')
        assert(n.rosterFrame.rows[2].target=='Bob-OtherRealm',
            'roster must preserve the realm returned by UnitFullName')
        local created=allocations
        for i=1,1000 do n:ShowRoster() end
        assert(allocations==created, 'roster rows must be reused')
    ''')


if __name__ == "__main__":
    for test in (test_memory_panel_reuses_fixed_rows_and_shows_stats,
                 test_private_expiry_is_preserved_and_tags_are_manual_positive_only,
                 test_unknown_performance_data_is_readable_and_private,
                 test_roster_uses_four_reusable_rows):
        test()
        print(test.__name__ + ": OK")
