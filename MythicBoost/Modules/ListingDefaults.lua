local _, JP = ...
local Defaults = {}

function Defaults:ShowPanel()
    if not PVEFrame_ShowFrame then return false end
    -- Shortlist's optional OnShow replacement otherwise hides our native input
    -- on the next frame. Suppress only this synchronous open and restore the
    -- user's setting even if the public opener raises an error.
    local settings=type(ShortlistDB)=="table" and ShortlistDB or nil
    local previous=settings and settings.autoOpen
    if settings then settings.autoOpen=false end
    local ok,err=pcall(PVEFrame_ShowFrame,"GroupFinderFrame","LFGListPVEStub")
    if settings then settings.autoOpen=previous end
    return ok and PVEFrame and PVEFrame:IsShown(),err
end

-- A blocked protected call can return normally: inspect its event as well.
function Defaults:Call(fn, ...)
    if not self.guard then
        self.guard=CreateFrame("Frame")
        self.guard:RegisterEvent("ADDON_ACTION_BLOCKED")
        self.guard:RegisterEvent("ADDON_ACTION_FORBIDDEN")
        self.guard:SetScript("OnEvent",function(_,_,addon)
            if self.calling and JP.SafeString(addon)=="MythicBoost" then self.refused=true end
        end)
    end
    self.refused=false; self.calling=true
    local ok,err=xpcall(fn,function(message)
        -- Forward caught errors to the normal collector while the failing
        -- stack still exists, independently of optional debug logging.
        local handler=type(geterrorhandler)=="function" and geterrorhandler()
        if type(handler)=="function" then pcall(handler,message) end
        return message
    end,...)
    self.calling=false
    return ok and not self.refused,err
end

function Defaults:OpenOwned()
    if InCombatLockdown() then return false end
    if IsInGroup(LE_PARTY_CATEGORY_HOME) and not UnitIsGroupLeader("player",LE_PARTY_CATEGORY_HOME) then
        JP:Print(JP.L("Создать объявление может только лидер группы.")); return false
    end
    local unavailableMessage = JP.L("Окно заявки Blizzard сейчас недоступно. Открой поиск подземелий и попробуй ещё раз.")
    if (not LFGListFrame or not LFGListFrame.EntryCreation) and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn,"Blizzard_GroupFinder")
    end
    if not PVEFrame_ShowFrame or not LFGListFrame or not LFGListFrame.EntryCreation then
        JP:Print(unavailableMessage); return false
    end
    local active=JP.SafeBoolean(C_LFGList.HasActiveEntryInfo())
    local activityID,groupID,level=C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
    if not active and (not JP.UsableNumber(activityID) or not JP.UsableNumber(groupID)
        or not JP.UsableNumber(level) or level<2) then
        JP:Print(JP.L("Свой мифический ключ не найден.")); return false
    end
    if JP.GroupTools then JP.GroupTools:EndEdit() end
    local welcome=JP.modules.Welcome
    local restoreWelcome=welcome and welcome.frame and welcome.frame:IsShown()
    if restoreWelcome then welcome.frame:Hide() end
    local shown,showError=self:ShowPanel()
    if not shown then
        if restoreWelcome then welcome.frame:Show() end
        JP:Print(unavailableMessage)
        if showError then JP:Log("LFG panel: %s",tostring(showError)) end
        return false
    end
    if active then return true end
    local ec=LFGListFrame.EntryCreation
    local base=(Enum and Enum.LFGListFilter and Enum.LFGListFilter.PvE) or 4
    local ok,err=self:Call(function()
        local keep=ec.selectedActivity==activityID and ec.selectedCategory==2
            and self.draftLevel==level and JP.SafeOptionalBoolean(ec.editMode)~=true
        LFGListEntryCreation_SetBaseFilters(ec,base)
        if not keep then
            LFGListEntryCreation_Clear(ec)
            -- The native new-listing handler reads selectedActivity before
            -- selecting the owned key. Supply its context after Clear; calling
            -- it with nil raises an API error. It performs the sole Select and
            -- protected title update itself.
            ec.selectedCategory=2; ec.selectedGroup=groupID
            ec.selectedActivity=activityID; ec.selectedFilters=1
            ec.generalPlaystyle=Enum.LFGEntryGeneralPlaystyle.FunSerious
            LFGListEntryCreation_SetEditMode(ec,false)
        end
        LFGListEntryCreation_UpdateValidState(ec)
    end)
    if not ok then
        JP:Print(JP.L("Не удалось открыть форму объявления. Подробности — в журнале ошибок."))
        if err then JP:Log("LFG form: %s",tostring(err)) end
        return false
    end
    self.draftLevel=level
    if not self.navigationHook and hooksecurefunc and LFGListFrame_SetActivePanel then
        self.navigationHook=true
        hooksecurefunc("LFGListFrame_SetActivePanel",function(frame,panel)
            if self.formVisible and frame==LFGListFrame and panel~=ec then
                if JP.SafeBoolean(C_LFGList.HasActiveEntryInfo()) then
                    self.formVisible=false; ec:Hide()
                else
                    -- Availability/base-filter events can restore the old
                    -- search/category panel. Keep the prepared form visible
                    -- without rewriting its title or the secure dispatcher.
                    if panel and type(panel.Hide)=="function" then panel:Hide() end
                    ec:Show()
                end
            end
        end)
        if LFGListEntryCreationCancelButton_OnClick then
            hooksecurefunc("LFGListEntryCreationCancelButton_OnClick",function()
                if not self.formVisible then return end
                self.formVisible=false; ec:Hide()
                local panel=LFGListFrame.activePanel
                if panel and panel~=ec then panel:Show() end
            end)
        end
        local function Closed()
            if self.formVisible then self.formVisible=false; ec:Hide() end
        end
        PVEFrame:HookScript("OnHide",Closed)
        if LFGListPVEStub then LFGListPVEStub:HookScript("OnHide",Closed) end
    end
    -- Never assign activePanel: the stock event dispatcher must stay secure.
    local previous=LFGListFrame.activePanel
    if previous and previous~=ec then previous:Hide() end
    self.formVisible=true; ec:Show()
    local info=C_LFGList.GetLfgCategoryInfo(2)
    local name=info and JP.SafeString(info.name)
    if name and ec.Label then ec.Label:SetText(name) end
    if ec.Name then ec.Name:SetFocus() end
    return true
end
-- Native forms retain their own playstyle controls; no delayed title writes.
function Defaults:Enable() self.running=true end
function Defaults:Disable() self.running=false end
function Defaults:Destroy() self:Disable() end
JP.ListingDefaults=Defaults
JP:RegisterModule("ListingDefaults",Defaults)
