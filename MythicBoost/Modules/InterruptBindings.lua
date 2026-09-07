local _, JP = ...
local A = JP.InterruptAssist
local names = {[true]="MythicBoostFocusAction", [false]="MythicBoostInterruptAction",
    shared="MythicBoostFocusInterruptAction", control="MythicBoostControlSequence"}
local function Command(kind) return "CLICK " .. names[kind] .. ":LeftButton" end
function A:BindingKey(kind)
    if type(kind) == "boolean" then
        local shared = GetBindingKey(Command("shared"))
        if shared then return shared end
    end
    return GetBindingKey(Command(kind))
end
function A:BindAction(kind, key)
    if InCombatLockdown() then return false, "combat" end
    if not names[kind] or kind == "shared" or type(key) ~= "string" or key == "" then return false, "failed" end
    local own, previous = Command(kind), GetBindingAction(key) or ""
    local pair = type(kind) == "boolean"
    local shared, other = Command("shared"), pair and Command(not kind)
    local merge = pair and (previous == other or previous == shared)
    if previous ~= "" and previous ~= own and not merge then return false, "busy", previous end

    -- One Blizzard binding owns each key. Combine only this pair of actions;
    -- splitting a shared key leaves the other action bound to the old key.
    local plan = {}
    local function Replace(command, replacement)
        for _, old in ipairs({GetBindingKey(command)}) do
            if GetBindingAction(old) == command then plan[old] = replacement end
        end
    end
    Replace(own, "")
    if merge then
        Replace(other, ""); Replace(shared, "")
    elseif pair then
        Replace(shared, other)
    end
    plan[key] = merge and shared or own
    local keys, before = {}, {}
    for changed in pairs(plan) do
        keys[#keys+1] = changed; before[changed] = GetBindingAction(changed) or ""
    end
    table.sort(keys)
    for index, changed in ipairs(keys) do
        if not SetBinding(changed, plan[changed] ~= "" and plan[changed] or nil) then
            for restore = index, 1, -1 do
                local old = keys[restore]
                SetBinding(old, before[old] ~= "" and before[old] or nil)
            end
            return false, "failed"
        end
    end
    SaveBindings(GetCurrentBindingSet())
    local s = self.Settings()
    s.focusKey, s.interruptKey = self:BindingKey(true), self:BindingKey(false)
    if kind == "control" then s.controlKey = self:BindingKey("control") end
    self:UpdateActions()
    return true, merge and "shared" or "single"
end
