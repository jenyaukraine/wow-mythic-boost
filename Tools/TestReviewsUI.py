"""Review consent UI: explicit shared checkbox and withdraw behaviour."""

from TestSocialWorkflows import client, load


def test_shared_consent_is_explicit_and_saved():
    lua = client()
    load(lua, "Modules/ReviewsUI.lua")
    lua.execute(r'''
        r=JP.Reviews
        local methods=getmetatable(UIParent).__index
        function UI.Tooltip(owner,title,...)
            tooltip={owner=owner,title=title,lines={...}}
        end
        -- The lightweight social fixture has a checkbox callback but no
        -- native click dispatcher; expose its callback as the test action.
        local saved={
            ['Bob-Realm']={vote=1,text='old',shared=true},
            ['Cara-Realm']={vote=-1,text='legacy',shared=false}
        }
        function r:GetOwn(target) return saved[target] end
        calls={}
        function r:Save(target,vote,text,run,shared)
            calls[#calls+1]={target=target,vote=vote,text=text,shared=shared}
            return true
        end
        run={level=12,mapName='Dawn',upgrades=2,members={'Bob-Realm','Cara-Realm','Dave-Realm'}}
        r:ShowRun(run)
        assert(r.note.text:find('отзывы',1,true) and r.note.text:find('Личные заметки',1,true)
            and not r.note.text:find('согласия',1,true))
        assert(r.reviewRows[1].shared.checked==true,
            'migrated shared records must be visibly opted in')
        assert(r.reviewRows[2].shared.checked==false,
            'an explicit shared=false record remains local')
        assert(r.reviewRows[3].shared.checked==true,
            'new reviews default to the common database')
        r.reviewRows[1].shared.toggle(false)
        r.reviewRows[2].shared.toggle(true)
        r.saveButton.scripts.OnClick(r.saveButton)
        assert(#calls==2 and calls[1].target=='Bob-Realm' and calls[1].shared==false,
            'turning sharing off must pass explicit false')
        assert(calls[2].target=='Cara-Realm' and calls[2].shared==true,
            'sharing requires the visible checkbox and Save')
        r:ShowRun(run)
        r.reviewRows[1].shared.toggle(true)
        r.reviewRows[1].shared.toggle(false)
        r.saveButton.scripts.OnClick(r.saveButton)
        assert(calls[3] and calls[3].target=='Bob-Realm' and calls[3].shared==false,
            'unchecking a shared review withdraws it from the common database')
        r.reviewRows[1].shared.scripts.OnEnter(r.reviewRows[1].shared)
        assert(tooltip and tooltip.lines[1]:find('Отзыв',1,true)
            and tooltip.lines[1]:find('не делает',1,true))
    ''')


if __name__ == "__main__":
    test_shared_consent_is_explicit_and_saved()
    print("test_shared_consent_is_explicit_and_saved: OK")
