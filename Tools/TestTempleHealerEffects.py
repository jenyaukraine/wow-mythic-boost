"""Temple healing display: secure selection, native aura ownership and bounded FX.

Contract mocks do not certify live NPC UNIT_COMBAT delivery or client rendering.
"""
from TestDungeonHUD import runtime
from TestHudPolish import load, source


def fixture():
    lua = runtime()
    lua.execute(r'''
        instance=1877; STANDARD_TEXT_FONT='font'; auraRecords={}; auraButtons=0
        AuraContainerInboundMixin={}
        AnchorUtil={FlowDirection={Right=1,Down=2}}
        function GetInstanceInfo() return nil,nil,nil,nil,nil,nil,nil,instance end
        function UnregisterStateDriver(f) f.condition=nil end
        C_Timer=setmetatable({}, {__index=function() error('no per-heal timers') end})
        C_UnitAuras=setmetatable({}, {__index=function() error('no addon-side aura reads') end})
        local methods=getmetatable(UIParent).__index
        local originalSetText=methods.SetText
        function methods:SetText(value)
            -- Native SetText replaces the text created by SetFormattedText.
            -- Drop the base fixture's captured formatting arguments as well.
            self.formatted=nil; originalSetText(self,value)
        end
        function methods:HookScript(key,fn)
            local prior=self.scripts[key]
            self.scripts[key]=function(...) if prior then prior(...) end; fn(...) end
        end
        function methods:Show()
            assert(not self.protected or not combat or engine)
            local was=self.shown; self.shown=true
            if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function methods:Hide()
            assert(not self.protected or not combat or engine)
            local was=self.shown; self.shown=false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function methods:SetAttribute(key,value)
            assert(not combat or engine,'no insecure retargeting')
            self.attrs=self.attrs or {}; local prior=self.attrs[key]; self.attrs[key]=value
            if prior~=value and self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self,key,value) end
        end
        local originalCreate=CreateFrame
        function CreateFrame(kind,name,parent,template)
            assert(not combat,'no effect/aura frame allocation during combat')
            local f=originalCreate(kind,name,parent,template)
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
            if kind=='AuraContainer' then
                assert(template=='CustomAuraContainerTemplate')
                local record={}; auraRecords[#auraRecords+1]=record
                function f:SetUnit(unit) assert(not combat); record.unit=unit end
                function f:SetEnabled(value) assert(not combat); record.enabled=value end
                function f:SetFlowLayoutMaximumLineSize(width) record.width=width end
                function f:SetFlowLayoutAnchorPoint(point) record.anchor=point end
                function f:SetFlowLayoutGrowthDirection(x,y) record.growth={x,y} end
                function f:AddAuraGroup(key,filter,options)
                    assert(not combat and filter=='HELPFUL' and options.maxFrameCount==8)
                    record.filter=filter; record.max=options.maxFrameCount
                    for i=1,10 do -- Blizzard preallocates in batches of ten.
                        local sealed=false; local base=NewWidget(self); local state={}
                        function base:SetIcon(icon) state.icon=icon end
                        function base:SetDurationCooldown(cooldown) state.cooldown=cooldown end
                        function base:SetApplicationCount(count) state.count=count end
                        function base:SetDurationText(text) state.duration=text end
                        function base:SetTooltipAnchorPoint(anchor) state.anchor=anchor end
                        local button=setmetatable({}, {
                            __index=function(_,field) assert(not sealed,'private aura button read after initialization'); return base[field] end,
                            __newindex=function(_,field,value) assert(not sealed,'private aura button write'); base[field]=value end,
                        })
                        options.initializeFrame(button)
                        assert(base.mouseClicks==false and base.mouseMotion==true)
                        assert(state.icon and state.cooldown and state.count and state.duration and state.anchor=='ANCHOR_RIGHT')
                        sealed=true; auraButtons=auraButtons+1
                    end
                end
            end
            return f
        end
        function Driver(state)
            local previous=engine; engine=true
            JP.TempleHealer.frame:SetAttribute('state-healtarget',state)
            engine=previous
        end
        function Event(event,...) JP.TempleHealer.events.scripts.OnEvent(nil,event,...) end
        units.boss1={name=Secret('Avatar')}; units.boss2={name=Secret('Other')}
    ''')
    load(lua, 'Modules/TempleHealerEffects.lua')
    load(lua, 'Modules/TempleHealer.lua')
    return lua


def test_native_auras_and_secure_clicks():
    lua = fixture()
    lua.execute(r'''
        local h=JP.TempleHealer; h:Enable(); local f=h.frame
        assert(#auraRecords==5 and auraButtons==50 and #f.healEffects.slots==6)
        assert(f:GetAttribute('*type1')=='target' and ClickCastFrames[f])
        assert(f.health.height==24 and f.height==86 and f.width==250)
        assert(f.portrait.width==32 and f.healAuras[1].width==197)
        for i,record in ipairs(auraRecords) do
            assert(record.unit=='boss'..i and record.enabled and record.filter=='HELPFUL')
            assert(record.width==197 and record.anchor=='TOPLEFT')
            assert(not f.healAuras[i].shown and not ClickCastFrames[f.healAuras[i]])
            f.healAuras[i].protected=true
        end
        local built=allocations
        combat=true; Driver('boss1')
        assert(f.shown and f:GetAttribute('unit')=='boss1' and f.healAuras[1].shown)
        assert(issecretvalue(f.name.text),'secret name renders without being parsed')
        Event('UNIT_COMBAT','boss1','HEAL','','123')
        assert(not f.healEffects.slots[1].started)
        Driver('boss2')
        assert(f.healAuras[2].shown and not f.healAuras[1].shown)
        for i=1,1000 do h:Update() end
        assert(allocations==built and #auraRecords==5,'no retargeting or frame creation in combat')
        Driver('none'); assert(not f.shown and not f.healAuras[2].shown)
        combat=false; h:SetUnlocked(true)
        assert(h.previewFrame.shown and not ClickCastFrames[h.previewFrame])
        assert(#h.previewFrame.previewBuffs==4 and not h.previewFrame.healAuras)
        assert(h.previewFrame.healEffects.slots[1].text.text=='+124.5k')
        assert(not h.previewFrame.healEffects.scripts.OnUpdate,'static preview has no permanent animation')
        built=allocations
        for i=1,100 do h:SetUnlocked(false); h:SetUnlocked(true) end
        assert(allocations==built and #auraRecords==5,'native rows and preview are reused')
        h:SetUnlocked(false); Driver('boss1'); h:Disable()
        for _,record in ipairs(auraRecords) do assert(not record.enabled) end
        assert(not f.shown and not next(h.events.events))
    ''')


def test_heal_events_and_cleanup():
    lua = fixture()
    lua.execute(r'''
        local h=JP.TempleHealer; h:Enable(); Driver('boss1')
        local f=h.frame; local fx=f.healEffects; local built=allocations
        combat=true
        Event('UNIT_COMBAT','boss2','HEAL','CRITICAL',150000)
        Event('UNIT_COMBAT','boss1','WOUND','CRITICAL',150000)
        Event('UNIT_COMBAT',Secret('boss1'),'HEAL','',150000)
        Event('UNIT_COMBAT','boss1',Secret('HEAL'),'',150000)
        Event('UNIT_HEALTH','boss1')
        assert(not fx.slots[1].started,'only confirmed healing for the active boss spawns numbers')
        for _,bad in ipairs({0,-1,.0/0,math.huge,'42'}) do Event('UNIT_COMBAT','boss1','HEAL','',bad) end
        assert(not fx.slots[1].started)
        Event('UNIT_COMBAT','boss1','HEAL','CRITICAL',124500)
        assert(fx.slots[1].text.text=='+124.5k' and fx.slots[1].text.font[2]==19)
        local cursor=fx.cursor
        for i=1,500 do Event('UNIT_COMBAT','boss1','HEAL','',15) end
        assert(fx.cursor==cursor,'burst events cannot grow a backlog')
        now=.2; fx.scripts.OnUpdate()
        assert(fx.slots[1].text.alpha>0 and fx.glow.alpha>0 and fx.slots[1].text.points[1][5]>-4)
        local opaque=Secret(4000)
        Event('UNIT_COMBAT','boss1','HEAL',Secret('CRITICAL'),opaque)
        assert(fx.slots[2].text.text==opaque and fx.slots[2].text.font[2]==15)
        now=2; fx.scripts.OnUpdate()
        assert(not fx.scripts.OnUpdate and not fx.slots[1].text.shown and fx.slots[2].text.text=='')
        assert(fx.glow.alpha==0 and allocations==built)
        Event('UNIT_COMBAT','boss1','HEAL','',100)
        Driver('boss2')
        assert(not fx.scripts.OnUpdate and not fx.slots[fx.cursor].text.shown,'unit changes clear old healing')
        now=3; Event('UNIT_COMBAT','boss2','HEAL','',100); Driver('none')
        assert(not fx.scripts.OnUpdate,'hidden heal target has no animation work')
        Driver('boss1'); now=4; Event('UNIT_COMBAT','boss1','HEAL','',100); h:Disable()
        assert(not fx.scripts.OnUpdate and h.pending)
        Event('UNIT_COMBAT','boss1','HEAL','',100); assert(not fx.scripts.OnUpdate)
        combat=false; Event('PLAYER_REGEN_ENABLED')
        assert(not f.shown and not next(h.events.events))
    ''')


def test_memory_and_instance_scope():
    lua = fixture()
    lua.execute(r'''
        local h=JP.TempleHealer; instance=1; h:Enable()
        assert(not h.frame.healAuras,'no native aura pools outside Temple until first needed')
        instance=1877; h:Apply(); Driver('boss1')
        local fx=h.frame.healEffects; local built=allocations
        collectgarbage('collect'); local baseline=collectgarbage('count')
        local weak=setmetatable({},{__mode='v'})
        combat=true
        for i=1,2000 do
            now=i*2; local value=Secret(i); weak[i]=value
            Event('UNIT_COMBAT','boss1','HEAL','',value)
            now=now+1.5; fx.scripts.OnUpdate()
        end
        collectgarbage('collect'); collectgarbage('collect')
        assert(next(weak)==nil,'secret amount references are released on expiration')
        assert(allocations==built and #fx.slots==6 and not fx.scripts.OnUpdate)
        assert(collectgarbage('count')-baseline<96,'retained memory is bounded across healing events')
        combat=false; instance=1; h:Apply(); Driver('boss1')
        assert(not h.frame.shown)
        for _,record in ipairs(auraRecords) do assert(not record.enabled) end
        for i=1,300 do h:Disable(); h:Enable() end
        assert(allocations==built and not fx.scripts.OnUpdate and #auraRecords==5)
    ''')
    effects = source('Modules/TempleHealerEffects.lua')
    assert 'C_UnitAuras.' not in effects and 'C_Timer' not in effects
    assert 'SetCancelAuraButtons' not in effects


if __name__ == '__main__':
    for test in (test_native_auras_and_secure_clicks, test_heal_events_and_cleanup, test_memory_and_instance_scope):
        test()
        print(test.__name__ + ': OK')
