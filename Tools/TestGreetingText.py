"""Custom greeting persistence, plain chat payloads and bounded settings UI."""
import re
from TestDungeonHUD import runtime
from TestHudPolish import load, source
from TestInteractionFixes import TIMERS


def fixture():
    lua=runtime()
    lua.execute(TIMERS+r'''
        LE_PARTY_CATEGORY_HOME=1; grouped=false; leader=false; sent={}
        function IsInGroup(category) assert(category==1); return grouped end
        function IsInRaid() return false end
        function UnitIsGroupLeader() return leader end
        function IsLoggedIn() return true end
        C_ChatInfo={InChatMessagingLockdown=function() return locked or false end,
            SendChatMessage=function(text,channel) sent[#sent+1]={text,channel} end}
        db.convenience={autoHi=true}
        local methods=getmetatable(UIParent).__index
        function methods:SetFontObject() end
        function methods:SetAutoFocus() end
        function methods:SetTextInsets() end
        function methods:SetMaxBytes(value) self.maxBytes=value end
        function methods:SetCursorPosition(value) self.cursor=value end
        function methods:GetText() return self.text or '' end
        function methods:HasFocus() return self.focused==true end
        function methods:ClearFocus()
            local focused=self.focused; self.focused=false
            if focused and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
        end
        function UI.Panel(parent) return NewWidget(parent) end
    ''')
    load(lua,'Modules/PartyGreeting.lua')
    load(lua,'Modules/SettingsHub.lua')
    return lua


def test_greeting_text():
    lua=fixture()
    lua.execute(r'''
        local g=JP.PartyGreeting
        assert(g:GetText()=='hi' and db.convenience.greetingText=='hi')
        assert(g:SetText('  Привет, ребята!  ')=='Привет, ребята!')
        assert(db.convenience.greetingText=='Привет, ребята!')
        assert(g:SetText('Good luck :)')=='Good luck :)')
        assert(g:SetText('  \n\t  ')=='hi')
        assert(g:SetText(nil)=='hi' and g:SetText(Secret('hidden'))=='hi')
        assert(g:SetText('Hello\nteam\t|\r\0')=='Hello team')
        local long=string.rep('Ж',121)
        local result=g:SetText(long)
        assert(#result==240 and utf8.len(result)==120)
        result=g:SetText(string.rep('a',239)..'Ж')
        assert(#result==239 and utf8.len(result)==239,'no half Cyrillic character')
        result=g:SetText(string.rep('a',238)..'👋')
        assert(#result==238 and utf8.len(result)==238,'no half emoji')
        result=g:SetText(string.rep('👋',60)); assert(#result==240 and utf8.len(result)==60)
        g:SetText('Привет всем!'); g:Enable()
        grouped=true; g:OnEvent('GROUP_JOINED',1)
        g:SetText('Удачного ключа!'); Flush()
        assert(#sent==1 and sent[1][1]=='Удачного ключа!' and sent[1][2]=='PARTY')
        g:OnEvent('GROUP_ROSTER_UPDATE'); Flush(); assert(#sent==1)
        now=140; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        locked=true; Flush(); g:SetText('Hello'); locked=false; Flush()
        assert(#sent==2 and sent[2][1]=='Hello' and not g.pending)
        now=180; g:OnEvent('GROUP_LEFT',1); g:OnEvent('GROUP_JOINED',1)
        db.convenience.autoHi=false; Flush(); assert(#sent==2 and not g.pending)
        db.convenience.autoHi=true; g:Disable()
        local saved=db.convenience.greetingText
        g:Enable(); assert(g:GetText()==saved and #sent==2,'reload cannot greet existing group')
        now=220; g:OnEvent('GROUP_LEFT',1); C_ChatInfo.SendChatMessage=nil
        function SendChatMessage(text,channel) assert(text=='Hello' and channel=='PARTY'); sent[#sent+1]={text,channel} end
        g:OnEvent('GROUP_JOINED',1); Flush(); assert(#sent==3)
    ''')


def test_editor_persistence_and_reuse():
    lua=fixture()
    lua.execute(r'''
        local hub,g=JP.SettingsHub,JP.PartyGreeting
        local page=NewWidget(UIParent); hub:BuildGreetingEditor(page)
        local f=hub.greetingText
        assert(f.text=='hi' and f.maxBytes==240 and not f:HasFocus())
        f.focused=true; f:SetText('Привет :)'); f.scripts.OnEnterPressed(f)
        assert(db.convenience.greetingText=='Привет :)' and not f:HasFocus())
        f.focused=true; f:SetText('Draft'); hub:RefreshGreetingText()
        assert(f.text=='Draft','refresh does not replace text under the cursor')
        f.scripts.OnEscapePressed(f); assert(f.text=='Привет :)' and g:GetText()=='Привет :)')
        f.focused=true; f:SetText('Saved on blur'); f:ClearFocus()
        assert(g:GetText()=='Saved on blur')
        f.focused=true; f:SetText('Saved on close'); f.scripts.OnHide(f)
        assert(g:GetText()=='Saved on close' and not f:HasFocus())
        f:SetText('   '); f.scripts.OnEditFocusLost(f); assert(f.text=='hi' and g:GetText()=='hi')
        db.convenience.autoHi=false; f:SetText('Stored while disabled'); f.scripts.OnHide(f)
        assert(g:GetText()=='Stored while disabled' and not db.convenience.autoHi)
        local built=allocations
        for i=1,1000 do hub:BuildGreetingEditor(page); hub:RefreshGreetingText(); f.scripts.OnHide(f) end
        assert(allocations==built and #timers==0 and #sent==0,'settings do not send chat or allocate timers')
    ''')


if __name__=='__main__':
    for test in (test_greeting_text,test_editor_persistence_and_reuse):
        test(); print(test.__name__+': OK')
    settings=source('Modules/SettingsHub.lua')
    heading=int(re.search(r'Heading\(groupPage, L\("УМНЫЙ КЛИК"\), 28, (-\d+)',settings).group(1))
    assert heading<=-320
    for control in ('smartBuff','smartRes'):
        y=int(re.search(control+r':SetPoint\("TOPLEFT", 28, (-\d+)\)',settings).group(1))
        assert y<heading-25 and y>-550
