local _, JP = ...
local Market, L = {}, JP.L
-- Independent native-API implementation. No Auctionator code or dependency.
-- Per-character SavedVariables isolate market history from the HUD/profile DB.
local MAX_ITEMS, MAX_LOTS, DAY = 20000, 1500000, 86400
local IDENTITY_CACHE, LOAD_TIMEOUT = 4096, 30
local FRAME_BUDGET_MS, MAX_STEPS = 2, 1000
local function Num(value)
    value=JP.SafeNumber(value)
    if value and value==value and value>=0 and value<math.huge then return value end
end
function Market:Settings() return JP.Settings("auctionMarket",{enabled=true}) end
function Market:Database()
    if type(MythicBoostMarketDB)~="table" then MythicBoostMarketDB={version=1,catalog={},snapshots={}} end
    local db=MythicBoostMarketDB
    if db.version~=1 or type(db.catalog)~="table" or type(db.snapshots)~="table" then return end
    return db
end
function Market:SetStatus(text)
    self.statusText=text
    if self.status then self.status:SetText(text or "") end
    if self.UpdateScanProgress then self:UpdateScanProgress() end
end
function Market:StopScan(message)
    if self.timeout then self.timeout:Cancel(); self.timeout=nil end
    if self.events then self.events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE"); self.events:SetScript("OnUpdate",nil) end
    self.work=nil
    if message then self:SetStatus(message) end
    if self.UpdateScanProgress then self:UpdateScanProgress() end
    if self.Render then self:Render() end
end
function Market:StartScan()
    if not self.running or not self.atAuction or InCombatLockdown() then return false end
    if self.work then return false end
    local db=self:Database()
    if not db then self:SetStatus(L("Несовместимая версия истории цен")); return false end
    local now=time()
    if db.lastRequest and now-db.lastRequest<900 then
        self:SetStatus((L("Следующий полный скан через %d сек.")):format(math.ceil(900-(now-db.lastRequest)))); return false
    end
    if not C_AuctionHouse or not C_AuctionHouse.ReplicateItems then
        self:SetStatus(L("Сканирование недоступно")); return false
    end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        self:SetStatus(L("Аукцион занят. Повтори запрос позже.")); return false
    end
    self.scanResult=nil
    self.work={prices={},catalog={},count=0,index=0,stamp=now,started=GetTime(),partial=false,phase="waiting",
        pending={},pendingCount=0,retryIndex=0,retryAt=0,loads={},loadCount=0,
        linkKeys={},linkRing={},linkCursor=1,
        stats={priced=0,noBuyout=0,unloaded=0,invalid=0,errors=0,itemLimit=0,lotLimit=0}}
    self.events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    db.lastRequest=now
    self:SetStatus(L("Ожидание полного снимка аукциона…"))
    self.timeout=C_Timer.NewTimer(90,function() self:StopScan(L("Скан не завершён: сервер не ответил вовремя")) end)
    local ok=pcall(C_AuctionHouse.ReplicateItems)
    if not ok then self:StopScan(L("Не удалось запросить скан аукциона")); return false end
    return true
end

-- Prices are compared within a native auction bucket. Gear level/suffix and
-- pet species/level/quality stay separate; different variants are not merged.
function Market:Identity(link,itemID)
    if not link or #link>1024 then return end
    local species,petLevel,quality=link:match("battlepet:(%d+):(%d+):(%d+)")
    if species then
        return ("p:%s:%s:%s"):format(species,petLevel,quality),
            {itemID=82800,itemLevel=0,itemSuffix=0,battlePetSpeciesID=tonumber(species)}
    end
    if not C_Item or not C_Item.GetItemInfoInstant then return end
    local id,_,_,equip=C_Item.GetItemInfoInstant(link)
    if not Num(id) or id~=itemID then return end
    local level=0
    if equip and equip~="" and equip~="INVTYPE_NON_EQUIP_IGNORE" then
        level=C_Item.GetDetailedItemLevelInfo and Num(C_Item.GetDetailedItemLevelInfo(link))
        if not level then return end
    end
    local payload=link:match("item:([^|]+)")
    if not payload then return end
    local suffix=tonumber((select(7,strsplit(":",payload)))) or 0
    local key=("%d:%d:%d"):format(id,level,suffix)
    return key,{itemID=id,itemLevel=level,itemSuffix=suffix,battlePetSpeciesID=0}
end
function Market:ReadLot(index)
    local work=self.work
    local name,texture,count,_,_,_,_,_,_,buyout,_,_,_,_,_,_,itemID,hasAllInfo=C_AuctionHouse.GetReplicateItemInfo(index)
    count,buyout,itemID=Num(count),Num(buyout),Num(itemID)
    if not count or not buyout or not itemID or itemID==0 then return "invalid" end
    if count==0 or buyout==0 then return "noBuyout" end
    local link=JP.SafeString(C_AuctionHouse.GetReplicateItemLink(index))
    local key=link and work.linkKeys[link]
    local known=key and work.catalog[key]
    if not known or known.itemKey.itemID~=itemID then
        key=nil
        if C_Item and C_Item.DoesItemExistByID and C_Item.DoesItemExistByID(itemID)==false then return "invalid" end
    end
    -- Replication can finish before the item cache. Do not turn a temporary
    -- missing link/level/name into a permanent omission from the snapshot.
    if hasAllInfo==false or not JP.SafeString(name) or not Num(texture) or not link then return "pending",itemID end
    local bucket
    if not key then key,bucket=self:Identity(link,itemID) end
    if not key then return "pending",itemID end
    local price=math.ceil(buyout/count)
    if work.prices[key]==nil then
        if work.count>=MAX_ITEMS then return "itemLimit" end
        work.count=work.count+1
        work.catalog[key]={itemKey=bucket,link=link,name=JP.SafeString(name) or ("Item "..itemID),icon=Num(texture) or 134400}
    end
    if not work.linkKeys[link] then
        -- Cache only an exact public link: gear suffix/level and pets remain
        -- separate. A scan-local ring bounds this cache independently of lots.
        local old=work.linkRing[work.linkCursor]
        if old then work.linkKeys[old]=nil end
        work.linkRing[work.linkCursor]=link; work.linkKeys[link]=key
        work.linkCursor=work.linkCursor%IDENTITY_CACHE+1
    end
    if not work.prices[key] or price<work.prices[key] then work.prices[key]=price end
    return "priced"
end
function Market:RequestItemData(itemID)
    local work=self.work
    if not work or not itemID or not C_Item or not C_Item.RequestLoadItemDataByID then return end
    local request=work.loads[itemID]
    if not request then
        if work.loadCount>=MAX_ITEMS then return end
        request={attempts=0,at=-math.huge}; work.loads[itemID]=request; work.loadCount=work.loadCount+1
    end
    local now=GetTime()
    if request.attempts>=3 or now-request.at<1 or work.loadBudget<=0 then return end
    request.at=now; request.attempts=request.attempts+1; work.loadBudget=work.loadBudget-1
    pcall(C_Item.RequestLoadItemDataByID,itemID)
end
-- One numeric bit mask per 32 native indices, at most ceil(MAX_LOTS/32).
-- This retains no lot objects, callbacks or sellers. Unlike a full queue of
-- pending objects, a cold cache cannot block reading the rest of the snapshot.
local function Pending(work,index,enabled)
    if not enabled and work.pendingCount==0 then return end
    local chunk,bit=math.floor(index/32),2^(index%32)
    local bits=work.pending[chunk] or 0
    local present=bits%(bit*2)>=bit
    if enabled and not present then
        work.pending[chunk]=bits+bit; work.pendingCount=work.pendingCount+1
    elseif not enabled and present then
        bits=bits-bit; work.pending[chunk]=bits>0 and bits or nil
        work.pendingCount=work.pendingCount-1
    end
end
local function NextPending(work,now)
    if work.pendingCount==0 or now<work.retryAt then return end
    -- Bound traversal of empty chunks too; never search a million indices
    -- inside one uninterruptible call after most pending lots resolve.
    for _=1,32 do
        if work.retryIndex>=work.index then work.retryIndex=0; work.retryAt=now+.5; return end
        local chunk=math.floor(work.retryIndex/32)
        local bits=work.pending[chunk]
        if bits then
            for index=work.retryIndex,math.min((chunk+1)*32-1,work.index-1) do
                work.retryIndex=index+1
                local bit=2^(index%32)
                if bits%(bit*2)>=bit then return index end
            end
        else work.retryIndex=math.min((chunk+1)*32,work.index) end
    end
end
function Market:ReadScanLot(index)
    local work=self.work
    local ok,result,itemID=pcall(self.ReadLot,self,index)
    if not ok then result="errors" end
    if result=="pending" then
        local now=GetTime()
        if not work.loadDeadline or now<work.loadDeadline then
            self:RequestItemData(itemID)
            Pending(work,index,true)
            return
        end
        result="unloaded"
    end
    result=result or "errors"
    Pending(work,index,false)
    work.stats[result]=(work.stats[result] or 0)+1
    if result~="priced" and result~="noBuyout" then work.partial=true end
end
function Market:ProcessBatch()
    if not self.running or not self.atAuction or InCombatLockdown() then self:StopScan(L("Сканирование остановлено")); return end
    local work=self.work
    if not work or work.phase=="waiting" then return end
    local started=debugprofilestop and debugprofilestop()
    work.loadBudget=20
    for step=1,(started and MAX_STEPS or 200) do
        if work.index>=work.total and work.pendingCount==0 then self:CommitScan(); return end
        local now=GetTime()
        if work.index>=work.total and not work.loadDeadline then work.loadDeadline=now+LOAD_TIMEOUT end
        local retry
        if work.index>=work.total or step%4==0 then retry=NextPending(work,now) end
        if retry~=nil then self:ReadScanLot(retry)
        elseif work.index<work.total then
            self:ReadScanLot(work.index)
            work.index=work.index+1
        else break end
        if started and debugprofilestop()-started>=FRAME_BUDGET_MS then break end
    end
    work.phase=work.index>=work.total and "loading" or "reading"
    if not work.statusAt or GetTime()-work.statusAt>.25 then
        work.statusAt=GetTime()
        self:SetStatus((L("Обработка: %d / %d лотов")):format(work.index-work.pendingCount,work.total))
    end
end
function Market:ReceiveScan()
    local work=self.work
    if not work or work.phase~="waiting" or not self.atAuction then return end
    local total=Num(C_AuctionHouse.GetNumReplicateItems())
    if not total or total==0 then self:StopScan(L("Пустой ответ сервера. История не изменена.")); return end
    self.events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    if self.timeout then self.timeout:Cancel() end
    self.timeout=C_Timer.NewTimer(600,function() self:StopScan(L("Сканирование остановлено")) end)
    work.total=math.min(MAX_LOTS,total); work.partial=total>MAX_LOTS; work.phase="reading"
    work.stats.total=total; work.stats.lotLimit=total-work.total
    self:SetStatus((L("Обработка: %d / %d лотов")):format(0,work.total))
    self.events:SetScript("OnUpdate",function() self:ProcessBatch() end)
end

-- Keep four recent versions, a 4-hour grid for 36 hours, then daily versions.
-- At most 21 snapshots. Preserve time buckets, not a moving "nearest yesterday"
-- sample, which would discard tomorrow's comparison before it reached 24 hours.
function Market:RetainSnapshots(snapshots,now)
    local kept,selected,buckets={},{},{}
    for i=math.max(1,#snapshots-3),#snapshots do selected[i]=true end
    for i=#snapshots,1,-1 do
        local snapshot=snapshots[i]
        local recent=now-snapshot.stamp<=36*3600
        local bucket=(recent and "h" or "d")..math.floor(snapshot.stamp/(recent and 14400 or DAY))
        if not buckets[bucket] then selected[i]=true; buckets[bucket]=true end
    end
    for i,snapshot in ipairs(snapshots) do
        if selected[i] and now-snapshot.stamp<=7*DAY and snapshot.stamp<=now then kept[#kept+1]=snapshot end
    end
    return kept
end
function Market:CommitScan()
    local work,db=self.work,self:Database()
    if not work or not db then self:StopScan(); return end
    if work.count==0 then self:StopScan(L("Нет доступных цен. История не изменена.")); return end
    local snapshots={}
    for _,snapshot in ipairs(db.snapshots) do snapshots[#snapshots+1]=snapshot end
    snapshots[#snapshots+1]={stamp=work.stamp,prices=work.prices,partial=work.partial,count=work.count,stats=work.stats}
    snapshots=self:RetainSnapshots(snapshots,work.stamp)
    -- Retain bounded metadata only for referenced items; the native replicate
    -- list and sellers are never copied or saved by this addon.
    local catalog,count={},0
    for key,entry in pairs(work.catalog) do catalog[key]=entry; count=count+1 end
    for _,snapshot in ipairs(snapshots) do
        local retained=0
        for key in pairs(snapshot.prices) do
            if not catalog[key] then
                if count<MAX_ITEMS and db.catalog[key] then catalog[key]=db.catalog[key]; count=count+1
                else snapshot.prices[key]=nil; snapshot.partial=true; snapshot.trimmed=(snapshot.trimmed or 0)+1 end
            end
            if snapshot.prices[key] then retained=retained+1 end
        end
        snapshot.count=retained
    end
    db.catalog,db.snapshots=catalog,snapshots
    self.versionIndex=#snapshots; self.offset=0
    local skipped=work.stats.unloaded+work.stats.invalid+work.stats.errors+work.stats.itemLimit+work.stats.lotLimit
    self.scanResult={count=work.count,total=work.total,partial=work.partial,skipped=skipped}
    local message=(L("Сохранено: %d предметов. Пропущено лотов: %d.")):format(work.count,skipped)
    self:StopScan(message); self:BuildView(); self:Render()
end
function Market:Comparison(snapshot)
    local db=self:Database()
    if not snapshot or not db then return end
    local best,distance
    for _,old in ipairs(db.snapshots) do
        local age=snapshot.stamp-old.stamp
        local diff=math.abs(age-DAY)
        if age>0 and diff<=10800 and (not distance or diff<distance) then best,distance=old,diff end
    end
    return best
end
function Market:BuildView()
    local db=self:Database(); self.items={}
    if not db then return end
    local index=math.min(self.versionIndex or #db.snapshots,#db.snapshots)
    self.versionIndex=index
    self.snapshot=db.snapshots[index]; self.comparison=self:Comparison(self.snapshot)
    local query=(self.query or ""):lower()
    for key,price in pairs(self.snapshot and self.snapshot.prices or {}) do
        local info=db.catalog[key]
        if info and (query=="" or info.name:lower():find(query,1,true) or tostring(info.itemKey.itemID)==query) then
            local old=self.comparison and self.comparison.prices[key]
            local change=old and old>0 and (price/old-1)*100 or nil
            local signal=change and change<=-10 and not self.snapshot.partial and not self.comparison.partial
            self.items[#self.items+1]={key=key,info=info,price=price,old=old,change=change,signal=signal}
        end
    end
    table.sort(self.items,function(a,b)
        if (not not a.signal)~=(not not b.signal) then return not not a.signal end
        if a.change~=b.change then return (a.change or math.huge)<(b.change or math.huge) end
        return a.key<b.key
    end)
end
function Market:OpenListing(entry)
    if not self.atAuction or self.work or InCombatLockdown() or not entry then return false end
    local ah=AuctionHouseFrame
    if not ah or not ah.SelectBrowseResult or not ah.QueryItem or not AuctionHouseSearchContext or not C_AuctionHouse.GetItemKeyInfo then return false end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        self:SetStatus(L("Аукцион занят. Повтори запрос позже.")); return false
    end
    local key=entry.info.itemKey
    local ok,info=pcall(C_AuctionHouse.GetItemKeyInfo,key)
    if not ok or not info then self:SetStatus(L("Данные предмета ещё не загружены. Повтори нажатие.")); return false end
    -- Native Buy frames fetch current listings and retain their quantity,
    -- exact-variant selection and price confirmation. Never buy a snapshot.
    local opened=pcall(function()
        ah:SelectBrowseResult({itemKey=key,minPrice=0})
        ah:QueryItem(info.isCommodity and AuctionHouseSearchContext.BuyCommodities or AuctionHouseSearchContext.BuyItems,key)
    end)
    if opened then self.frame:Hide() else self:SetStatus(L("Не удалось открыть лоты предмета")) end
    return opened
end
function Market:Enable()
    if self:Settings().enabled==false or not C_AuctionHouse then return end
    self.running=true
    if not self.events then
        self.events=CreateFrame("Frame")
        self.events:SetScript("OnEvent",function(_,event)
            if event=="AUCTION_HOUSE_SHOW" then self.atAuction=true; self:AttachButton()
            elseif event=="PLAYER_REGEN_ENABLED" and self.atAuction then self:AttachButton()
            elseif event=="ADDON_LOADED" and self.atAuction then self:AttachButton()
            elseif event=="AUCTION_HOUSE_CLOSED" then
                self.atAuction=false; self:StopScan(L("Сканирование остановлено"))
                if self.frame then self.frame:Hide() end
                if self.button then self.button:Hide() end
                self.items=nil; self.snapshot=nil; self.comparison=nil
            elseif event=="REPLICATE_ITEM_LIST_UPDATE" then self:ReceiveScan()
            elseif event=="PLAYER_REGEN_DISABLED" then self:StopScan(L("Сканирование остановлено")) end
        end)
    end
    self.events:RegisterEvent("AUCTION_HOUSE_SHOW"); self.events:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self.events:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.events:RegisterEvent("ADDON_LOADED")
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then self.atAuction=true; self:AttachButton() end
end
function Market:Disable()
    self.running=false; self.atAuction=false; self:StopScan()
    if self.events then self.events:UnregisterAllEvents() end
    if self.frame then self.frame:Hide() end
    if self.button then self.button:Hide() end
    self.items=nil; self.snapshot=nil; self.comparison=nil
end
function Market:Destroy() self:Disable() end
JP.AuctionMarket=Market
JP:RegisterModule("AuctionMarket",Market)
