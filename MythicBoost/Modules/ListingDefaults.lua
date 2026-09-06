local _, JP = ...
local Defaults = {}
-- Default only an empty new Mythic+ form, after Blizzard finishes opening it.
-- Never call Show/Select/SetEntryTitle from our own listing button, never
-- replace native functions or write their form fields directly.
-- Reference: ApplicantScout's current native playstyle-selection approach.
function Defaults:Apply(panel)
    if not self.running or InCombatLockdown() or not panel or not panel:IsShown() then return end
    if not C_LFGList or not C_LFGList.GetActivityInfoTable
        or type(LFGListEntryCreation_IsEditMode) ~= "function" then return end
    if JP.SafeOptionalBoolean(LFGListEntryCreation_IsEditMode(panel)) ~= false then return end
    local activity = JP.SafeNumber(panel.selectedActivity)
    if not activity then return end
    local info = JP.SafeTable(C_LFGList.GetActivityInfoTable(activity))
    if not info or JP.SafeOptionalBoolean(info.isMythicPlusActivity) ~= true then return end
    local enums = Enum and Enum.LFGEntryGeneralPlaystyle
    if not enums or not enums.FunSerious or issecretvalue(panel.generalPlaystyle) then return end
    local current = panel.generalPlaystyle
    if current ~= nil and current ~= enums.None then return end
    if type(securecallfunction) ~= "function"
        or type(LFGListEntryCreation_OnPlayStyleSelectedInternal) ~= "function" then return end
    securecallfunction(LFGListEntryCreation_OnPlayStyleSelectedInternal, panel, enums.FunSerious)
end
function Defaults:Queue()
    if not self.running or self.pending then return end
    self.pending = C_Timer.NewTimer(0, function()
        self.pending = nil
        self:Apply(LFGListFrame and LFGListFrame.EntryCreation)
    end)
end
function Defaults:Hook()
    if self.hooked or type(LFGListEntryCreation_Show) ~= "function"
        or type(LFGListEntryCreation_Select) ~= "function" then return end
    self.hooked = true
    hooksecurefunc("LFGListEntryCreation_Show", function() self:Queue() end)
    hooksecurefunc("LFGListEntryCreation_Select", function() self:Queue() end)
    self:Queue()
end
function Defaults:Enable()
    self.running = true
    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function() self:Hook() end)
    end
    self.frame:RegisterEvent("ADDON_LOADED"); self:Hook()
end
function Defaults:Disable()
    self.running = false
    if self.pending then self.pending:Cancel(); self.pending = nil end
    if self.frame then self.frame:UnregisterAllEvents() end
end
function Defaults:Destroy() self:Disable() end
JP.ListingDefaults = Defaults
JP:RegisterModule("ListingDefaults", Defaults)
