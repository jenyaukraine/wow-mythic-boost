"""Removed listing filter must not reject groups, even with legacy settings."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def test_build_match_spam_boundaries():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        function issecretvalue(v) return type(v)=='table' and v.secret end
        function Secret() return setmetatable({secret=true},{__index=function() error('secret') end}) end
        JP={IsTest=true,Limits={HISTORY_TEAMMATES=50,HISTORY_RUNS=50}}
        JP.L=function(s) return s end; JP.UI={}
        JP.UI.UsableNumber=function(v) return type(v)=='number' and v end
        JP.UI.SafeString=function(v) return issecretvalue(v) and nil or (type(v)=='string' and v or nil) end
        JP.UI.SafeBoolean=function(v) return not issecretvalue(v) and type(v)=='boolean' and v end
        JP.UI.SafeTable=function(v) return not issecretvalue(v) and type(v)=='table' and v end
        JP.SafeNumber=JP.UI.UsableNumber; JP.SafeString=JP.UI.SafeString
        JP.SafeTable=JP.UI.SafeTable; JP.SafeOptionalBoolean=JP.UI.SafeBoolean
        JP.GetBestLevel=function() return 0 end; JP.RegisterModule=function() end
        C_LFGList={GetSearchResultInfo=function() return info end,
          GetActivityInfoTable=function() return {} end,
          GetSearchResultPlayerInfo=function() return {} end}
        function SetText(a,b) info={activityIDs={1},numMembers=1,name=a,comment=b} end
    ''')
    source = (ROOT / "MythicBoost/Modules/AutoMatch.lua").read_text(encoding="utf-8-sig")
    lua.eval("function(code) return assert(load(code))('MythicBoost', JP) end")(source)
    lua.execute(r'''
        local f=JP.AutoMatch.TestBuildMatch
        SetText('WTS +12','for gold')
        local ok,reason,match=f(1,{hideSpamListings=true},{},{}); assert(reason~='рекламный/платный пост', "legacy enabled flag must not hide a listing")
        SetText('no boost weekly learning','free run, learning route'); ok,reason,match=f(2,{hideSpamListings=true},{},{}); assert(reason~='рекламный/платный пост')
        SetText('not boosting','free weekly'); ok,reason,match=f(3,{hideSpamListings=true},{},{}); assert(reason~='рекламный/платный пост')
        for _,name in ipairs({'Goldrinn weekly','Unpaid learning group','Newts +12'}) do
            SetText(name,'free weekly'); ok,reason,match=f(3,{hideSpamListings=true},{},{})
            assert(reason~='рекламный/платный пост','substrings inside normal words are not ads: '..name)
        end
        SetText(Secret(),Secret()); ok,reason,match=f(4,{hideSpamListings=true},{},{}); assert(reason~='рекламный/платный пост')
        SetText('WTS +12','for gold'); ok,reason,match=f(5,{hideSpamListings=false},{},{}); assert(reason~='рекламный/платный пост')
    ''')


if __name__ == "__main__":
    test_build_match_spam_boundaries()
    print("TestListingSpam: OK")
