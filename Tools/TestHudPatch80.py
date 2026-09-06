"""Native filtered spells, hover drilldown, default anchors and auction layering.

Contract fixtures do not substitute for a live dungeon/auction rendering test.
"""
from TestAvoidableDamage import fixture
from TestAuctionMarket import fixture as auction_fixture
from TestHudPolish import load, source


def test_default_positions_and_saved_layout():
    lua = fixture()
    lua.execute("function UnregisterStateDriver() end; UIParent:SetSize(1600,900)")
    load(lua, 'Modules/TempleHealer.lua')
    load(lua, 'Modules/HealerMana.lua')
    lua.execute(r'''
        local h,m,a=JP.TempleHealer,JP.HealerMana,JP.AvoidableDamage
        h:Enable(); m:Enable(); a:Enable()
        assert(not h.preview and not m.preview and not a.preview)
        h:SetUnlocked(true); m:SetUnlocked(true); a:SetUnlocked(true)
        local function Point(f,anchor,relative,x,y)
            local p,parent,r,px,py=f:GetPoint()
            assert(p==anchor and parent==UIParent and r==relative)
            assert(math.abs(px-x)<.001 and math.abs(py-y)<.001)
        end
        Point(h.previewFrame,'CENTER','BOTTOMLEFT',700,545.4)
        Point(h.frame,'CENTER','BOTTOMLEFT',700,545.4)
        Point(m.frame,'TOPLEFT','TOPLEFT',32,-572.4)
        Point(a.frame,'TOPLEFT','TOPLEFT',64,-378)
        assert(not db.templeHealer.position and not db.healerMana.position and not db.avoidableDamage.position)
        UIParent:SetSize(2560,1440)
        h:Apply(); m:Layout(); a:Layout()
        Point(h.previewFrame,'CENTER','BOTTOMLEFT',1120,872.64)
        Point(m.frame,'TOPLEFT','TOPLEFT',51.2,-915.84)
        Point(a.frame,'TOPLEFT','TOPLEFT',102.4,-604.8)
        for _,key in ipairs({'templeHealer','healerMana','avoidableDamage'}) do
            db[key].position={point='TOPLEFT',relativePoint='BOTTOMLEFT',x=127,y=321}
        end
        for i=1,20 do
            h:SetUnlocked(false); m:SetUnlocked(false); a:SetUnlocked(false)
            h:SetUnlocked(true); m:SetUnlocked(true); a:SetUnlocked(true)
        end
        for _,f in ipairs({h.frame,h.previewFrame,m.frame,a.frame}) do Point(f,'TOPLEFT','BOTTOMLEFT',127,321) end
        assert(a.done==nil)
    ''')


def test_native_filtered_spell_source_and_late_details():
    lua = fixture()
    lua.execute(r'''
        m=JP.AvoidableDamage; m:Enable(); autoFlush=false
        Fire('CHALLENGE_MODE_START')
        Damage(1000)
        -- The category has already filtered these. The extra flag is not a gate.
        local detail={combatSpells={
            {spellID=11,totalAmount=100,isAvoidable=false},
            {spellID=12,totalAmount=200},
            {spellID=13,totalAmount=300,isAvoidable=Secret(true)},
            {spellID=14,totalAmount=400,isAvoidable=true},
        }}
        C_DamageMeter.GetCombatSessionSourceFromType=function(session,typ)
            assert(not combat and typ==Enum.DamageMeterType.AvoidableDamageTaken)
            return detail
        end
        local report=m:ReadCombatReport(true)
        assert(report.complete and #report.entries==4 and report.entries[1].amount==400)
        m:UpdateKeySpells(); m:UpdateKeySpells()
        assert(m.keySpells['P1:11'].amount==100 and m.keySpells['P1:14'].amount==400)
        detail.combatSpells[1].spellID=Secret(11)
        report=m:ReadCombatReport(true); assert(not report.complete and #report.entries==3)
        detail.combatSpells[1].spellID=11; detail.combatSpells[1].totalAmount=Secret(100)
        report=m:ReadCombatReport(true); assert(not report.complete and #report.entries==3)
        detail.combatSpells[1].totalAmount=100
        local get=C_DamageMeter.GetCombatSessionFromType
        C_DamageMeter.GetCombatSessionFromType=function(session,typ)
            if session==1 then return {combatSources={{sourceGUID='P1',totalAmount=1000}}} end
            return get(session,typ)
        end
        local release=GetTime()+3
        C_DamageMeter.GetCombatSessionSourceFromType=function(session,typ)
            assert(not combat and typ==8)
            return GetTime()>=release and detail or nil
        end
        local scheduled=0
        C_Timer.NewTimer=function(delay,fn)
            scheduled=scheduled+1
            local t={delay=delay,fn=fn}; function t:Cancel() self.cancelled=true end
            timers[#timers+1]=t; return t
        end
          combat=true; Fire('PLAYER_REGEN_DISABLED')
          -- The first 1000 was already captured before this pull. Model NEW
          -- damage as well: unchanged cumulative totals must not replay it.
          Damage(2000)
          for _,spell in ipairs(detail.combatSpells) do spell.totalAmount=spell.totalAmount*2 end
          combat=false; Fire('PLAYER_REGEN_ENABLED')
        while m.reportTimer do
            assert(scheduled<=5); now=now+m.reportTimer.delay; Flush()
        end
        assert(m.lastReport.complete and #m.lastReport.entries==4 and now>=release and now<=7)
        local built=allocations
        for i=1,1000 do m:ReadCombatReport(true) end
        assert(allocations==built and not m.reportTimer)
        m.completed=true; m:FinishKeyReport()
        assert(#m.keyReport.entries==4,'public spells reach the final key report')
    ''')


def test_player_spell_hover_and_cleanup():
    lua = fixture()
    lua.execute(r'''
        local methods=getmetatable(UIParent).__index
        function methods:Hide()
            local was=self.shown; self.shown=false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        GameTooltip=NewWidget()
        function GameTooltip:IsForbidden() return self.forbidden end
        function GameTooltip:IsOwned(owner) return self.owner==owner end
        function GameTooltip:SetOwner(owner) assert(not self.forbidden); self.owner=owner; self.lines={} end
        function GameTooltip:SetSpellByID(id) assert(not self.forbidden); self.spell=id; self.lines={'Native description '..id} end
        function GameTooltip:AddLine(text) assert(not self.forbidden); self.lines[#self.lines+1]=text end
        C_Spell.GetSpellInfo=function(id) return {name='Ability '..id,iconID=id} end
        m=JP.AvoidableDamage; m:Enable()
        local function Report()
            local entries={}
            for i=1,12 do entries[i]={guid='P1',name='Me',spellID=100+i,amount=2000000-i*1000} end
            entries[13]={guid='P2',name='Other',spellID=999,amount=100}
            return {key=true,complete=true,entries=entries,players={
                {guid='P1',name='Me',amount=24000000,fatal=0},
                {guid='P2',name='Other',amount=100,fatal=0},
                {guid='P3',name='Empty',amount=0,fatal=0},
            }}
        end
        m.keyReport=Report(); m:OpenKeyReport()
        local owner=m.rows[1]; owner.hovered=true; owner.scripts.OnEnter()
        local tip=m.playerTip
        assert(tip.shown and tip.title.text=='Me' and #tip.rows==5 and tip.next.shown)
        assert(tip.rows[1].name.text=='Ability 101' and tip.rows[1].amount.text=='2.00M')
        tip.rows[1].scripts.OnEnter(tip.rows[1])
        assert(GameTooltip.spell==101 and GameTooltip.lines[1]=='Native description 101')
        assert(GameTooltip.lines[2]=='Избегаемый урон: 2.00M')
        tip.next.scripts.OnClick(); assert(tip.rows[1].record.spellID==106 and tip.previous.shown)
        tip.next.scripts.OnClick(); assert(tip.rows[1].record.spellID==111 and not tip.next.shown and not tip.rows[3].shown)
        tip.previous.scripts.OnClick(); assert(tip.rows[1].record.spellID==106)
        owner.hovered=false; tip.hovered=true; now=now+1; tip.scripts.OnUpdate(); assert(tip.shown)
        tip.hovered=false; tip.scripts.OnUpdate(); now=now+.1; tip.scripts.OnUpdate(); assert(tip.shown)
        now=now+.1; tip.scripts.OnUpdate(); assert(not tip.shown and not tip.owner and not tip.scripts.OnUpdate)
        for _,row in ipairs(tip.rows) do assert(not row.record) end
        m.rows[2].scripts.OnEnter(); assert(tip.rows[1].record.spellID==999 and not tip.rows[2].shown)
        m.rows[3].scripts.OnEnter(); assert(tip.empty.shown and not tip.rows[1].record)
        local built=allocations; local memory; local weak=setmetatable({},{__mode='v'})
        for i=1,1000 do
            m.keyReport=Report(); weak[i]=m.keyReport; m:OpenKeyReport()
            m.rows[1].scripts.OnEnter(); tip.rows[1].scripts.OnEnter(tip.rows[1])
            GameTooltip.forbidden=true; tip.rows[2].scripts.OnEnter(tip.rows[2]); GameTooltip.forbidden=false
            m:HidePlayerSpells()
            if i==100 then collectgarbage('collect'); memory=collectgarbage('count') end
        end
        m.keyReport=nil; m.lastReport=nil; m:Render()
        collectgarbage('collect'); collectgarbage('collect')
        assert(next(weak)==nil and allocations==built and collectgarbage('count')-memory<96)
        assert(not tip.scripts.OnUpdate and not tip.owner,'no hidden hover polling or retained report')
    ''')


def test_auction_button_layer_and_reopen():
    lua = auction_fixture()
    lua.execute(r'''
        AuctionHouseFrame:SetFrameStrata('HIGH'); AuctionHouseFrame:SetFrameLevel(4)
        AuctionHouseFrame.NineSlice=NewWidget(AuctionHouseFrame); AuctionHouseFrame.NineSlice:SetFrameLevel(14)
        AuctionHouseFrame.TitleContainer=NewWidget(AuctionHouseFrame); AuctionHouseFrame.TitleContainer:SetFrameLevel(22)
        m:AttachButton(); assert(m.button.level==32 and m.button.strata=='HIGH')
        local onShow,onHide=AuctionHouseFrame.scripts.OnShow,AuctionHouseFrame.scripts.OnHide
        local built=allocations
        for i=1,500 do
            m:AttachButton(); AuctionHouseFrame.scripts.OnHide()
            assert(not m.button.shown and not m.frame.shown)
            AuctionHouseFrame.scripts.OnShow(); m.button.scripts.OnClick()
        end
        assert(allocations==built and requests==0 and not m.work and not m.events.scripts.OnUpdate)
        assert(AuctionHouseFrame.scripts.OnShow==onShow and AuctionHouseFrame.scripts.OnHide==onHide)
        Event('AUCTION_HOUSE_CLOSED'); combat=true; Event('AUCTION_HOUSE_SHOW')
        assert(not m.button.shown)
        combat=false; Event('PLAYER_REGEN_ENABLED'); assert(m.button.shown)
        m:Disable(); AuctionHouseFrame.scripts.OnShow(); assert(not m.button.shown)
        assert(AuctionHouseFrame.level==4 and AuctionHouseFrame.NineSlice.level==14,'native UI is untouched')
    ''')


if __name__ == '__main__':
    for test in (test_default_positions_and_saved_layout,
                 test_native_filtered_spell_source_and_late_details,
                 test_player_spell_hover_and_cleanup,
                 test_auction_button_layer_and_reopen):
        test()
        print(test.__name__ + ': OK')
    preset=source('Modules/LayoutPresets.lua').split('Presets.Main = [=[',1)[1].split(']=]',1)[0]
    assert ' 18 -1 0 7 7 UIParent 700.0 802.0 -1 #- ' in preset
    assert "&('()U*#+%" in preset and '\\' not in preset
