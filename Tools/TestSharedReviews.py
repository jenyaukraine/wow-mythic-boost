"""Execution tests for the MBReviews2 public review/statistics transport."""
from TestSocialWorkflows import client, load


def packets(lua):
    lua.execute("r:QueueRound()")
    return list(lua.globals().r.outbox.values())


def deliver(lua, values, sender):
    for value in reversed(values):
        lua.eval("function(m,s) r:Receive('MBReviews2',m,'PARTY',s) end")(value, sender)


def test_shared_roundtrip_and_privacy():
    a, b = client(), client("Bob", "Alice")
    load(a, "Modules/RunStats.lua")
    load(b, "Modules/RunStats.lua")
    a.execute(r'''
        run={mapID=399,level=13,members={'Alice-Realm','Bob-Realm','Carol-Realm'},
          performance={['bob-realm']={version=1,runAt=time(),role='HEALER',
            damage=45000,healing=90000,avoidable=7000,duration=90,itemLevel=310.3,complete=true}}}
        assert(r:Save('Bob-Realm',1,'public comment',run,true))
        assert(r:Save('Carol-Realm',-1,'private note',run,false))
    ''')
    wire = packets(a)
    assert(wire and all("private note" not in x for x in wire)
           and all("MBReviews1" not in x for x in wire))
    deliver(b, wire, "Alice-Realm")
    b.execute(r'''
        local rows=r:Get('Bob-Realm'); assert(#rows==1 and rows[1].vote==1)
        assert(rows[1].text=='public comment' and rows[1].shared and rows[1].direct)
        assert(rows[1].stats and rows[1].stats.damage==45000 and rows[1].stats.itemLevel==310.3)
        assert(rows[1].statsTrusted~=true, 'foreign stats are never locally trusted')
        assert(not db.reviews.records['alice-realm\tcarol-realm'], 'private data did not arrive')
    ''')

    old = packets(a)
    a.execute("assert(r:Withdraw('Bob-Realm'))")
    tombstone = packets(a)
    deliver(b, tombstone, "Alice-Realm")
    b.execute("assert(#r:Get('Bob-Realm')==0, 'public tombstone hides withdrawn review')")
    deliver(b, old, "Alice-Realm")
    b.execute("assert(#r:Get('Bob-Realm')==0, 'replayed old public record cannot resurrect')")
    a.execute("assert(r:GetOwn('Carol-Realm').text=='private note' and r:GetOwn('Carol-Realm').shared==false)")

    b.execute("r:Disable(); r:Receive('MBReviews2', tombstone or '', 'PARTY', 'Alice-Realm'); assert(not r.running)")


def test_legacy_migration_and_explicit_local_optout():
    a, b = client(), client("Bob", "Alice")
    # Simulate a pre-2.4.84 SavedVariables database. It is migrated exactly
    # once; a new explicit shared=false record remains in the local map.
    a.execute(r'''
        db.reviews.sharedMigration=0
        db.reviews.records['alice-realm\tbob-realm']={author='Alice-Realm',target='Bob-Realm',
          stamp=time(),vote=1,text='legacy public',map=399,level=10}
        db.reviews.records['alice-realm\tcarol-realm']={author='Alice-Realm',target='Carol-Realm',
          stamp=time(),vote=-1,text='explicit private',shared=false,map=399,level=10}
        r:Prune()
        assert(db.reviews.sharedRecords['alice-realm\tbob-realm'].shared==true)
        assert(db.reviews.records['alice-realm\tcarol-realm'].shared==false)
    ''')
    wire = packets(a)
    assert(any("legacy public" in p for p in wire))
    assert(all("explicit private" not in p for p in wire))
    deliver(b, wire, "Alice-Realm")
    b.execute("assert(r:Get('Bob-Realm')[1].text=='legacy public')")


def test_relay_newer_revision_replaces_direct_copy():
    a, b, c = client(), client("Bob", "Alice"), client("Charlie", "Bob")
    a.execute("run={mapID=399,level=10,members={'Alice-Realm','Bob-Realm'}}; assert(r:Save('Bob-Realm',1,'first',run,true))")
    old = packets(a)
    c.execute("units.party1.name='Alice'; r:CachePeers()")
    deliver(c, old, "Alice-Realm")
    c.execute("assert(r:Get('Bob-Realm')[1].direct); units.party1.name='Bob'; r:CachePeers()")
    a.execute("assert(r:Save('Bob-Realm',-1,'newer',run,true))")
    deliver(b, packets(a), "Alice-Realm")
    newer = packets(b)
    deliver(c, newer, "Bob-Realm")
    c.execute("local x=r:Get('Bob-Realm')[1]; assert(x.text=='newer' and x.vote==-1 and not x.direct and x.via=='Bob-Realm')")
    a.execute("assert(r:Save('Bob-Realm',0,'',run,true))")
    deliver(b, packets(a), "Alice-Realm")
    deliver(c, packets(b), "Bob-Realm")
    deliver(c, newer, "Bob-Realm")
    c.execute("assert(#r:Get('Bob-Realm')==0, 'relay deletion wins over old direct and replayed revisions')")


def test_visibility_switch_and_pending_revision():
    a, b = client(), client("Bob", "Alice")
    a.execute(r'''
        run={mapID=399,level=10,completedAt=time(),members={'Bob-Realm'}}
        assert(r:Save('Bob-Realm',-1,'visible',run))
        r:QueueRound(); assert(#r.outbox>0)
        assert(r:Save('Bob-Realm',-1,'local revision',run,false))
        assert(#r.outbox==0 and r.nextRound==0, 'withdraw invalidates queued public fragments')
        assert(r:GetOwn('Bob-Realm').text=='local revision' and not r:GetOwn('Bob-Realm').shared)
        local rows=r:Database(); assert(#rows==1 and rows[1].text=='local revision')
    ''')
    wire=packets(a)
    assert(all("visible" not in p and "local revision" not in p for p in wire))
    deliver(b,wire,"Alice-Realm")
    b.execute("assert(#r:Get('Bob-Realm')==0)")
    a.execute(r'''
        assert(r:Save('Bob-Realm',1,'published again',run,true))
        local rows=r:Database(); assert(#rows==1 and rows[1].text=='published again')
        assert(not db.reviews.records['alice-realm\tbob-realm'])
        assert(r:Save('Bob-Realm',1,'private again',run,false))
        assert(r:Publish(r:GetOwn('Bob-Realm')))
        assert(not db.reviews.records['alice-realm\tbob-realm'])
        assert(r.nextRound==0 and #r.outbox==0)
    ''')
    deliver(b,packets(a),"Alice-Realm")
    b.execute("assert(r:Get('Bob-Realm')[1].text=='private again')")


def test_late_initial_statistics_and_departed_peer():
    a,b=client(),client("Bob","Alice")
    load(a,"Modules/RunStats.lua"); load(b,"Modules/RunStats.lua")
    a.execute(r'''
        run={mapID=399,level=10,completedAt=time(),members={'Bob-Realm'}}
        assert(r:Save('Bob-Realm',-1,'stats arrive later',run))
        r:QueueRound(); local before=r:GetOwn('Bob-Realm').stamp
        run.performance={['bob-realm']={version=1,runAt=run.completedAt,role='HEALER',
            healing=12345,damage=1000,avoidable=10,duration=45,complete=true}}
        r:UpdateRunStats(run)
        assert(r:GetOwn('Bob-Realm').stats.healing==12345 and r:GetOwn('Bob-Realm').stamp>before)
        assert(#r.outbox==0 and r.nextRound==0)
    ''')
    wire=packets(a)
    b.execute("units.party1=nil")
    deliver(b,wire,"Alice-Realm")
    b.execute("assert(#r:Get('Bob-Realm')==0 and next(r.incoming)==nil)")
    b.execute("units.party1={name='Alice',realm='Realm'}; r:CachePeers()")
    deliver(b,wire,"Alice-Realm")
    b.execute("assert(r:Get('Bob-Realm')[1].stats.healing==12345)")
    a.execute(r'''
        assert(r:Save('Bob-Realm',0,'',run)); r:UpdateRunStats(run)
        assert(not r:GetOwn('Bob-Realm').stats, 'late stats never resurrect a deletion')
    ''')


if __name__ == "__main__":
    test_shared_roundtrip_and_privacy()
    print("test_shared_roundtrip_and_privacy: OK")
    test_legacy_migration_and_explicit_local_optout()
    print("test_legacy_migration_and_explicit_local_optout: OK")
    test_relay_newer_revision_replaces_direct_copy()
    print("test_relay_newer_revision_replaces_direct_copy: OK")
    test_visibility_switch_and_pending_revision()
    print("test_visibility_switch_and_pending_revision: OK")
    test_late_initial_statistics_and_departed_peer()
    print("test_late_initial_statistics_and_departed_peer: OK")
