"""Native-message preservation and bounded, fixed-deadline duplicate bursts."""
from TestRunStats import fixture
from TestSocialWorkflows import load


def test_chat_condenser_boundaries():
    lua=fixture()
    lua.execute(r'''
        DEFAULT_CHAT_FRAME={lines={}}
        function DEFAULT_CHAT_FRAME:AddMessage(text) self.lines[#self.lines+1]=text end
        filters={}
        function ChatFrame_AddMessageEventFilter(e,f) filters[e]=f end
        function ChatFrame_RemoveMessageEventFilter(e,f) if filters[e]==f then filters[e]=nil end end
        function JP:Log() end
        function Count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
    ''')
    load(lua,'Modules/ChatSpamCondenser.lua')
    lua.execute(r'''
        local c=JP.ChatSpamCondenser; c:Enable(); local frame=DEFAULT_CHAT_FRAME
        assert(not filters.CHAT_MSG_PARTY and not filters.CHAT_MSG_GUILD,'private group chat is not condensed')
        for _,msg in ipairs({'no boost weekly','Goldrinn group','unpaid learning','Newts'}) do
            assert(c:OnChatMessage(frame,'CHAT_MSG_CHANNEL',msg,'Alice','Common','Trade')==false)
        end
        assert(c:OnChatMessage({},'CHAT_MSG_CHANNEL','WTS 12','Alice','Common','Trade')==false,'secondary tabs remain native')
        assert(c:OnChatMessage(frame,'CHAT_MSG_CHANNEL',Secret('WTS'),'Alice','Common','Trade')==false)
        assert(c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS',Secret('Alice'),'Common','Trade')==false)
        assert(c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS','Alice','Common',Secret('Trade'))==false)
        assert(c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS 12','Alice','Common','Trade'))
        local timer=timers[1]
        for i=1,1000 do c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS 12','Alice','Common','Trade') end
        assert(#timers==1 and timers[1]==timer,'duplicates do not allocate or postpone timer')
        c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS 12','Bob','Common','Trade')
        c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS 12','Alice','Common','LocalDefense')
        c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS 13','Alice','Common','Trade')
        assert(Count(c.pending)==4)
        Tick(1.2); assert(#frame.lines==4 and next(c.pending)==nil)
        assert(frame.lines[1]:find('Alice',1,true) and frame.lines[1]:find('Trade',1,true) and frame.lines[1]:find('x1001',1,true))
        for i=1,200 do c:OnChatMessage(frame,'CHAT_MSG_CHANNEL','WTS '..i,'Alice','Common','Trade') end
        assert(Count(c.pending)==128,'bounded burst map')
        c:Disable(); assert(next(c.pending)==nil and next(filters)==nil)
        local before=#frame.lines; Tick(2); assert(#frame.lines==before,'disable cancels and flushes without lost/duplicate messages')
        c:Enable(); timer.fn(); assert(next(c.pending)==nil,'stale callback cannot consume a new entry')
        c:Disable()
    ''')


if __name__=='__main__':
    test_chat_condenser_boundaries(); print('TestChatSpamCondenser: OK')
