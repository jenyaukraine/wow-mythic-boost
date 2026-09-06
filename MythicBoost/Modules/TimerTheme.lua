local _, JP = ...
local Theme = {}
JP.TimerTheme = Theme
local REVISION = 1
local TEXT = { .90, .93, .97, 1 }
local MUTED = { .56, .65, .72, 1 }
local GOLD = { .95, .72, .18, 1 }
local GREEN = { .28, .85, .56, 1 }
local RED = { .93, .38, .38, 1 }

-- A real MPlusTimer profile, not an overlay or hooks on its frame graph.
-- The original profile is untouched. Only public export/import APIs are used.
function Theme:Build(profile, width, position)
    profile.Scale, profile.Spacing, profile.UpdateRate = 1, 4, .2
    profile.Position = position
    profile.Background = { enabled = true, Color = { .025, .035, .048, .86 },
        WidthOffset = 0, HeightOffset = 0, xOffset = 0, yOffset = 0,
        BorderSize = 1, BorderColor = { .13, .19, .23, .9 } }
    for _, key in ipairs({ "KeyLevel", "DungeonName", "AffixIcons", "DeathCounter", "TimerText",
        "ComparisonTimer", "ChestTimer1", "ChestTimer2", "ChestTimer3", "BossName", "BossTimer",
        "BossSplit", "PercentCount", "RealCount", "ForcesSplits", "ForcesCompletion", "PBInfo" }) do
        local text = profile[key]
        if text then
            text.Font, text.FontSize, text.Outline = "MythicBoost UI", 11, "OUTLINE"
            text.Color, text.ShadowOffset = TEXT, { 0, 0 }
            text.SuccessColor, text.CompletionColor, text.AheadColor = GREEN, GREEN, GREEN
            text.FailColor, text.BehindColor, text.EqualColor = RED, RED, GOLD
        end
    end
    local function Position(key, anchor, relative, x, y)
        local item = profile[key]
        item.Anchor, item.RelativeTo, item.xOffset, item.yOffset = anchor, relative, x, y
    end
    for _, key in ipairs({ "KeyInfo", "TimerBar", "Bosses", "ForcesBar" }) do
        profile[key].Width = width
        profile[key].xOffset, profile[key].yOffset = 0, 0
    end
    profile.KeyInfo.Height, profile.TimerBar.Height = 26, 36
    profile.Bosses.Height, profile.ForcesBar.Height = 20, 20
    profile.KeyInfo.AnchoredTo = "MainFrame"
    profile.TimerBar.AnchoredTo = "KeyInfo"
    profile.Bosses.AnchoredTo = "TimerBar"
    profile.ForcesBar.AnchoredTo = "Bosses"
    for _, key in ipairs({ "KeyInfo", "TimerBar", "Bosses", "ForcesBar" }) do
        Position(key, "TOPLEFT", key == "KeyInfo" and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
    end
    Position("KeyLevel", "LEFT", "LEFT", 8, 0)
    profile.KeyLevel.FontSize, profile.KeyLevel.Color = 14, GOLD
    Position("DungeonName", "LEFT", "LEFT", 46, 0)
    profile.DungeonName.FontSize, profile.DungeonName.Shorten = 12, math.floor((width - 96) / 7)
    profile.AffixIcons.enabled = false
    Position("DeathCounter", "RIGHT", "RIGHT", -24, 0)
    profile.DeathCounter.IconxOffset, profile.DeathCounter.IconyOffset = -6, 0
    profile.DeathCounter.ShowTimer, profile.DeathCounter.Color = false, MUTED
    Position("TimerText", "TOPLEFT", "TOPLEFT", 8, -3)
    profile.TimerText.FontSize, profile.TimerText.Decimals, profile.TimerText.Space = 14, 0, true
    profile.ComparisonTimer.enabled = false
    profile.TimerBar.ChestTimerDisplay = 1
    -- MPT displays TWO thresholds on completion. Distinct cells on the lower
    -- line prevent those values from overlapping each other or the main timer.
    for i = 1, 3 do Position("ChestTimer" .. i, "BOTTOMRIGHT", "BOTTOMRIGHT", -8 - (i - 1) * 58, 3) end
    for _, key in ipairs({ "Tick1", "Tick2" }) do
        profile[key].Width, profile[key].Color = 1, { .7, .8, .86, .45 }
    end
    Position("BossName", "LEFT", "LEFT", 8, 0)
    profile.BossName.MaxLength = math.floor((width - 120) / 6.5)
    Position("BossTimer", "RIGHT", "RIGHT", -8, 0)
    Position("BossSplit", "RIGHT", "RIGHT", -58, 0)
    profile.BossTimer.Color, profile.BossSplit.FontSize = MUTED, 10
    Position("PercentCount", "LEFT", "LEFT", 8, 0)
    Position("RealCount", "RIGHT", "RIGHT", -8, 0)
    Position("ForcesCompletion", "LEFT", "LEFT", 8, 0)
    profile.ForcesSplits.enabled, profile.PBInfo.enabled = false, false
    profile.PercentCount.pullcount, profile.RealCount.pullcount = false, false
    profile.RealCount.Color = MUTED
    local timerColors = { { .40, .19, .20, 1 }, { .46, .30, .14, 1 },
        { .24, .39, .36, 1 }, { .09, .36, .47, 1 } }
    local forceColors = { { .10, .23, .30, 1 }, { .10, .28, .34, 1 },
        { .10, .32, .38, 1 }, { .10, .36, .40, 1 }, { .12, .40, .37, 1 } }
    for _, key in ipairs({ "TimerBar", "ForcesBar" }) do
        local bar = profile[key]
        bar.Texture, bar.BorderSize = "MythicBoost Flat", 1
        bar.BackgroundColor, bar.BorderColor = { .035, .055, .070, .9 }, { .10, .17, .20, 1 }
        bar.Color = key == "TimerBar" and timerColors or forceColors
    end
    profile.ForcesBar.CompletionColor = { .12, .40, .28, 1 }
    profile.CurrentPullBar.Texture = "MythicBoost Flat"
    profile.CurrentPullBar.Color = { .24, .60, .64, .7 }
    return profile
end

function Theme:Apply(anchor)
    if self.applied or InCombatLockdown() or not MPTAPI or not MythicBoostDB or not anchor then return end
    local media = LibStub("LibSharedMedia-3.0")
    media:Register("font", "MythicBoost UI", STANDARD_TEXT_FONT)
    media:Register("statusbar", "MythicBoost Flat", "Interface/Buttons/WHITE8X8")
    local player, realm = UnitFullName("player")
    if JP.IsSecret(player) or JP.IsSecret(realm) or type(player) ~= "string" then return end
    local character = player .. "-" .. (realm or GetNormalizedRealmName() or "")
    local saved = MythicBoostDB.timerTheme or {}
    MythicBoostDB.timerTheme = saved
    if saved[character] and saved[character].revision == REVISION then self.applied = true; return end
    local exported = MPTAPI:GetExportString()
    if type(exported) ~= "string" then return end
    local codec, serializer = LibStub("LibDeflate"), LibStub("AceSerializer-3.0")
    local decoded = codec:DecodeForPrint(exported)
    local data = decoded and codec:DecompressDeflate(decoded)
    if not data then return end
    local ok, profile = serializer:Deserialize(data)
    if not ok or type(profile) ~= "table" then return end
    local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, bottom = anchor:GetRight(), anchor:GetBottom()
    if not right or not bottom then return end
    local width = math.max(240, math.min(420, anchor:GetWidth() * scale))
    local position = { Anchor = "TOPRIGHT", relativeTo = "TOPRIGHT",
        xOffset = right * scale - UIParent:GetWidth(), yOffset = bottom * scale - UIParent:GetHeight() - 8 }
    self:Build(profile, width, position)
    local name = "MythicBoost Compact"
    -- Bound collision handling; never invoke MPT's recursive name search.
    if MPTSV and MPTSV.Profiles then
        local available
        for i = 1, 100 do
            local candidate = i == 1 and name or name .. " " .. i
            if not MPTSV.Profiles[candidate] then name = candidate; available = true; break end
        end
        if not available then self.applied = true; return end
    end
    local encoded = codec:EncodeForPrint(codec:CompressDeflate(serializer:Serialize(profile)))
    if MPTAPI:ImportProfile(encoded, name, false) then
        saved[character] = { revision = REVISION, original = exported, profile = name }
        self.applied = true
    end
end
