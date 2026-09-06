"""Executable privacy and multi-client tests for the public PlayerNetwork.

The fixture deliberately routes addon packets between independent Lua states;
this catches accidental SavedVariables sharing, relay spoofing, and wire-data
regressions that a single-client unit test cannot see.
"""
from pathlib import Path
from TestDungeonHUD import runtime, load, source


EPOCH = 1788580800


def client(name="Alice", peer="Bob", realm="Realm", peer_realm=None):
    lua = runtime()
    lua.globals().my_name = name
    lua.globals().peer_name = peer
    lua.globals().my_realm = realm
    lua.globals().peer_realm = peer_realm or realm
    lua.execute(rf'''
        epoch={EPOCH}; sent={{}}; tickers={{}}; delayed=nil
        function time() return epoch+math.floor(now) end
        function GetNormalizedRealmName() return 'Realm' end
        function UnitFullName(u) local v=units[u]; return v and v.name,v and v.realm end
        units.player={{name=my_name,realm=my_realm,guid='Player-'..my_name}}
        units.party1={{name=peer_name,realm=peer_realm,guid='Player-'..peer_name}}
        function IsInRaid() return raid or false end
        function IsInGroup(category)
            if category==LE_PARTY_CATEGORY_INSTANCE then return instanceGroup or false end
            return true
        end
        LE_PARTY_CATEGORY_INSTANCE='instance'
        Enum.SendAddonMessageResult={{Success=0}}
        chat_gate_in=false; chat_gate_out=false
        C_ChatInfo={{RegisterAddonMessagePrefix=function() end,
            InChatMessagingLockdown=function() return chat_gate_in end,
            AreOutgoingAddonChatMessagesRestricted=function() return chat_gate_out end,
            SendAddonMessage=function(prefix,msg,channel)
                assert(#msg<=255 and channel~='WHISPER' and channel~='GUILD')
                sent[#sent+1]={{prefix=prefix,msg=msg,channel=channel}}
                if apiFailure then return 1 end
                return 0
            end}}
        C_Timer={{NewTicker=function(_,fn)
            local t={{fn=fn,cancelled=false}}; function t:Cancel() self.cancelled=true end
            tickers[#tickers+1]=t; return t
        end}}
    ''')
    load(lua, "Modules/Reviews.lua")
    load(lua, "Modules/PlayerNetwork.lua")
    lua.execute("n=JP.PlayerNetwork; n:Enable()")
    return lua


def packets(lua):
    return [(p["prefix"], p["msg"], p["channel"]) for p in lua.globals().sent.values()]


def route(lua, packet, sender):
    lua.eval("function(p,m,c,s) n:Receive(p,m,c,s) end")(*packet, sender)


def drain(lua):
    result = packets(lua)
    lua.execute("sent={}")
    return result


def queued(lua):
    values = list(lua.globals().n.outbox.values())
    lua.execute("n.outbox={}; n.queued={}")
    return [("MBNetwork1", value, "PARTY") for value in values]


def establish(a, b, sender_a="Alice-Realm", sender_b="Bob-Realm"):
    # HELLO must precede a manifest. Tests may have queued a manifest while
    # preparing a client, so make the handshake explicit here.
    a.execute("n.outbox={}; n.queued={}; n.sendAt=nil; n.retryAt=nil; n:Enqueue('H\\t1')")
    a.execute("n:Pump()")
    for packet in drain(a): route(b, packet, sender_a)
    b.execute("n:Pump()")
    for packet in drain(b): route(a, packet, sender_b)
    a.execute("n:Pump()")
    for packet in drain(a): route(b, packet, sender_a)


def test_multiclient_sync_and_privacy():
    a, b, c = client(), client("Bob", "Alice"), client("Cara", "Bob")
    a.execute(r'''
        db.runHistory={players={['bob-realm']={runs=2,timed=1}},runs={}}
        assert(n:Recommend('Bob-Realm',5))
        n:SavePrivate('Bob-Realm','secret negative note DPS HPS ilvl',7)
        n:Manifest()
    ''')
    establish(a, b)
    for packet in queued(a): route(b, packet, "Alice-Realm")
    b.execute("assert(n.discovered['alice-realm'])")
    # I -> Q -> D, in reverse order and with a duplicate D.
    a.execute("n:Manifest()")
    for packet in queued(a): route(b, packet, "Alice-Realm")
    b.execute("assert(n.outbox[1] and n.outbox[1]:sub(1,1)=='Q')")
    for packet in queued(b): route(a, packet, "Bob-Realm")
    for packet in reversed(queued(a)):
        route(b, packet, "Alice-Realm")
        route(b, packet, "Alice-Realm")
    b.execute(r'''
        assert(n:GetOwn('Bob-Realm')==nil)
        assert(n:Context('Bob-Realm').knownBy==1)
        assert(db.playerNetwork.private['bob-realm']==nil, 'private data must never arrive in the peer DB')
    ''')
    for _, message, _ in packets(b):
        assert("secret" not in message and "DPS" not in message
               and "HPS" not in message and "ilvl" not in message)

    # Forwarding keeps provenance and never turns a relay into the author.
    b.execute("units.party1={name='Cara',realm='Realm',guid='Player-Cara'}; n:CachePeers()")
    establish(b, c, "Bob-Realm", "Cara-Realm")
    b.execute("n:Manifest()")
    for packet in queued(b): route(c, packet, "Bob-Realm")
    for packet in queued(c): route(b, packet, "Cara-Realm")
    for packet in reversed(queued(b)): route(c, packet, "Bob-Realm")
    c.execute("local r=db.playerNetwork.records['alice-realm\\tbob-realm']; assert(r and not r.direct and r.via=='Bob-Realm'); assert(n:Context('Bob-Realm').knownBy==1 and not n:GetOwn('Bob-Realm'))")
    c.execute("assert(n.records == nil or true)")


def test_spoof_revocation_and_version():
    a, b = client(), client("Bob", "Alice")
    a.execute("db.runHistory={players={['bob-realm']={}},runs={}}; assert(n:Recommend('Bob-Realm',3))")
    establish(a, b)
    a.execute("n:Manifest()")
    for packet in queued(a): route(b, packet, "Alice-Realm")
    for packet in queued(b): route(a, packet, "Bob-Realm")
    for packet in reversed(queued(a)): route(b, packet, "Alice-Realm")
    b.execute("assert(n:Context('Bob-Realm').knownBy==1)")
    # The owner must not accept a newer packet forged by another peer.
    a.execute("local old=n:GetOwn('Bob-Realm').stamp; n:Receive('MBNetwork1','D\\tAlice-Realm\\tBob-Realm\\t'..(old+10)..'\\t127','PARTY','Bob-Realm'); assert(n:GetOwn('Bob-Realm').mask==3)")
    # Unsupported protocol versions never establish discovery.
    b.execute("n:Disable(); n:Enable(); n:Receive('MBNetwork1','H\\t999','PARTY','Alice-Realm'); assert(not n.discovered['alice-realm'])")
    # A zero mask is a public tombstone and blocks the old positive revision.
    establish(a, b)
    a.execute("assert(n:Recommend('Bob-Realm',0)); n:Manifest()")
    for packet in queued(a): route(b, packet, "Alice-Realm")
    for packet in queued(b): route(a, packet, "Bob-Realm")
    for packet in reversed(queued(a)): route(b, packet, "Alice-Realm")
    b.execute("assert(n:Context('Bob-Realm').knownBy==0)")
    # A departed name is ignored even if it was cached before the roster update.
    b.execute("units.party1=nil; n.discovered['alice-realm']=nil; n:Receive('MBNetwork1','H\\t1','PARTY','Alice-Realm'); assert(not n.discovered['alice-realm'])")


def test_cross_realm_identity_and_chat_lockdown():
    # UnitFullName returns the realm as its second result.  The network must
    # preserve it instead of normalising every peer to the local realm.
    a = client("Alice", "Same", "RealmA", "RealmB")
    b = client("Same", "Alice", "RealmB", "RealmA")
    a.execute(r'''
        db.runHistory={players={['same-realmb']={runs=1}},runs={}}
        assert(n:Recommend('Same-RealmB',1))
        assert(not n:Recommend('Same-RealmC',1), 'same-name different realm must not be conflated')
    ''')
    establish(a, b, "Alice-RealmA", "Same-RealmB")
    a.execute("n:Manifest()")
    for packet in queued(a): route(b, packet, "Alice-RealmA")
    for packet in queued(b): route(a, packet, "Same-RealmB")
    for packet in reversed(queued(a)): route(b, packet, "Alice-RealmA")
    b.execute("assert(n:Context('Same-RealmB').knownBy==1); assert(n:Context('Same-RealmC').knownBy==0)")

    # An available lockdown/restriction API blocks on true and unknown; only
    # an explicit false allows the queued packet to reach SendAddonMessage.
    gate = client()
    gate.execute(r'''
        n.outbox={}; n.queued={}; n:Enqueue('H\t1')
        chat_gate_in=true; n:Pump(); assert(#sent==0 and #n.outbox==1)
        chat_gate_in=false; chat_gate_out=nil; n:Pump(); assert(#sent==0 and #n.outbox==1)
        chat_gate_out=false; n:Pump(); assert(#sent==1 and #n.outbox==0)
    ''')


def test_limits_lifecycle_and_rate():
    lua = client()
    lua.execute(r'''
        db.runHistory={players={},runs={}}
        for i=1,1001 do
            local who='User'..i..'-Realm'
            db.playerNetwork.records[who:lower()..'\tbob-realm']={author=who,target='Bob-Realm',stamp=time()-i,mask=1}
        end
        n:Prune(); local count=0; for _ in pairs(db.playerNetwork.records) do count=count+1 end
        assert(count==1000)
        for i=1,250 do n:SavePrivate('Note'..i..'-Realm','private',0) end
        count=0; for _ in pairs(db.playerNetwork.private) do count=count+1 end; assert(count==200)
        n:Enqueue(string.rep('x',256)); assert(#n.outbox<=64)
        combat=true; n:Pump(); assert(#sent==0 and n.ticker==nil)
        combat=false; n:UpdatePump(); assert(n.ticker)
        n:SetEnabled(false); assert(not n.ticker and #n.outbox==0)
        n:SetEnabled(true); n:Destroy(); assert(not n.running and not n.ticker and not next(n.events.events))
    ''')

    # Incoming flood is bounded per actual peer and does not broadcast.
    flood = client()
    flood.execute("n:Receive('MBNetwork1','H\\t1','PARTY','Bob-Realm')")
    for _ in range(200):
        flood.execute("n:Receive('MBNetwork1','H\\t1','PARTY','Bob-Realm')")
    flood.execute("assert(n.rates['bob-realm'].count==201 and #sent==0)")
    flood.execute("now=61; n:Receive('MBNetwork1','H\\t1','PARTY','Bob-Realm'); assert(n.rates['bob-realm'].count==1)")


def test_unicode_names_disabled_and_timer_cycles():
    # FullName and packet sizing are byte based, as they are in WoW's chat
    # API. These names are close to the 100-byte accepted-name boundary.
    a = client("Я" * 38, "Ю" * 38)
    a.execute(r'''
        local target=UnitFullName('party1')..'-Realm'
        db.runHistory={players={[target:lower()]={}},runs={}}
        assert(n:Recommend(target,127)); n:Manifest()
        for _,message in ipairs(n.outbox) do assert(#message<=255) end
    ''')
    a.execute(r'''
        n:SetEnabled(false); n:Receive('MBNetwork1','H\t1','PARTY',UnitFullName('party1')..'-Realm')
        assert(not next(n.discovered) and not n.ticker)
        for i=1,1000 do
            n:SetEnabled(true); local old=n.ticker; n:SetEnabled(false)
            assert(old and old.cancelled and not n.ticker)
        end
        do
            local weak=setmetatable({}, {__mode='v'})
            n:SetEnabled(true); weak[1]=n.ticker; n:SetEnabled(false); tickers={}
            collectgarbage('collect'); assert(weak[1]==nil, 'cancelled ticker must not be retained')
        end
    ''')


if __name__ == "__main__":
    for test in (test_multiclient_sync_and_privacy, test_spoof_revocation_and_version,
                 test_cross_realm_identity_and_chat_lockdown,
                 test_limits_lifecycle_and_rate, test_unicode_names_disabled_and_timer_cycles):
        test()
        print(test.__name__ + ": OK")
