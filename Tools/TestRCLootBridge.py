"""RCLootBridge protocol and response regression tests."""

from TestDungeonHUD import runtime, load


def fixture():
    lua = runtime()
    lua.execute(
        r'''
        sent = {}; registered = nil; rcLoaded = false
        function IsInRaid() return inRaid == true end
        function GameTooltip_Hide() hiddenTooltip = true end
        function UI.MakeMovable() end
        function UI.Backdrop() end
        UI.colors.surface = {0,0,0,1}; UI.colors.surfaceEdge = {1,1,1,1}
        UI.colors.accent = {0,1,1,1}; UI.colors.row = {.1,.1,.1,1}
        UI.colors.lineSoft = {.2,.2,.2,1}; UI.colors.text = {1,1,1,1}
        UI.colors.muted = {.5,.5,.5,1}
        function UI.IsAddOnLoaded(name) return name == 'RCLootCouncil' and rcLoaded end
        function UI.Text(parent)
            local f = NewWidget(parent)
            function f:SetText(value) self.text = value end
            function f:SetTextColor() end
            function f:SetJustifyH(value) self.justify = value end
            function f:SetWordWrap(value) self.wrap = value end
            return f
        end
        buttonsByText = {}
        function UI.Button(parent, text, width, height)
            local f = NewWidget(parent)
            f.text = text
            f:SetSize(width, height)
            buttonsByText[text] = f
            return f
        end
        function UI.CloseButton(parent) return UI.Button(parent, 'x', 18, 18) end
        function JP.Settings(key, defaults)
            db[key] = db[key] or {}
            for name, value in pairs(defaults or {}) do
                if db[key][name] == nil then db[key][name] = value end
            end
            return db[key]
        end
        function JP:RegisterModule(name, module) self[name] = module end
        local methods = getmetatable(UIParent).__index
        function methods:SetFrameStrata(value) self.strata = value end
        function methods:SetClampedToScreen(value) self.clamped = value end
        function methods:SetAlpha(value) self.alpha = value end
        function methods:SetTexCoord(...) self.texCoord = {...} end
        function methods:SetTexture(value) self.texture = value end
        function methods:SetHyperlink(value) self.link = value end
        function methods:SetOwner(owner) self.owner = owner end
        function methods:SetJustifyH(value) self.justify = value end
        function methods:SetWordWrap(value) self.wrap = value end
        -- Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:
        -- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID.
        C_Item = {GetItemInfoInstant = function()
            return 270162, 'Armor', 'Miscellaneous', 'INVTYPE_TRINKET', 98765, 4, 0
        end}
        GameTooltip = NewWidget(UIParent)
        local comm = {
            SendCommMessage = function(_, prefix, payload, channel, target, priority)
                if failComm then error('comm failed') end
                sent[#sent + 1] = {prefix = prefix, payload = payload, channel = channel, target = target, priority = priority}
            end,
            RegisterComm = function(self, prefix, callback)
                registered = {self = self, prefix = prefix, callback = callback}
            end,
        }
        serializer = {
            Serialize = function(_, command, data)
                if failSerialize then error('serialize failed') end
                lastSerialized = {command = command, data = data}
                return command
            end,
            Deserialize = function(_, value)
                if value == 'bad-ser' then return false end
                return true, value, decodedData
            end,
        }
        deflate = {
            CompressDeflate = function(_, value, config)
                lastCompress = config
                return value
            end,
            EncodeForWoWAddonChannel = function(_, value) return value end,
            DecodeForWoWAddonChannel = function(_, value)
                if value == 'bad-codec' then return nil end
                return value
            end,
            DecompressDeflate = function(_, value)
                if value == 'bad-deflate' then return nil end
                return value
            end,
        }
        function LibStub(name)
            if name == 'AceComm-3.0' then return comm end
            if name == 'AceSerializer-3.0' then return serializer end
            if name == 'LibDeflate' then return deflate end
        end
        JP.BiSData = {
            GetCurrentSpecID = function() return 105 end,
            GetItem = function(_, spec, itemID, context)
                if spec == 105 and itemID == 270162 and context == 'raid' then
                    return {label = 'BIS', slot = 'Trinket'}
                end
            end,
        }
        '''
    )
    load(lua, "Modules/RCLootBridge.lua")
    lua.execute("r = JP.RCLootBridge")
    return lua


def test_register_and_disable_when_real_rclootcouncil_is_loaded():
    lua = fixture()
    lua.execute(
        r'''
        assert(r:IsEnabled())
        r:Register()
        assert(registered and registered.prefix == 'RCLC')
        rcLoaded = true
        assert(not r:IsEnabled(), 'real RCLootCouncil owns its own protocol')
        '''
    )


def test_real_acecomm_callback_dispatch():
    lua = fixture()
    lua.execute('''
        mockSend = LibStub('AceComm-3.0').SendCommMessage
        LibStub = nil
        function securecallfunction(fn, ...) return fn(...) end
        function Ambiguate(name) return name end
        C_ChatInfo = {RegisterAddonMessagePrefix=function() return true end}
        ChatThrottleLib = {}
    ''')
    for path in ('Libs/LibStub/LibStub.lua',
                 'Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua',
                 'Libs/AceComm-3.0/AceComm-3.0.lua'):
        load(lua, path)
    lua.execute('''
        LibStub.libs['AceSerializer-3.0'] = serializer
        LibStub.libs['LibDeflate'] = deflate
        local comm = LibStub('AceComm-3.0')
        comm.SendCommMessage = mockSend
        assert(r:Register())
        decodedData = {{{session=7, link='item:270162'}}}
        comm.frame.scripts.OnEvent(comm.frame, 'CHAT_MSG_ADDON',
            'RCLC', 'lootTable', 'RAID', 'Master-Realm')
        assert(r.masterLooter=='Master-Realm' and r.frame and r.frame.shown,
            'real AceComm callback must preserve prefix, payload, distribution and sender')
        assert(#sent==1 and lastSerialized.command=='lootAck')
        comm.frame.scripts.OnEvent(comm.frame, 'CHAT_MSG_ADDON',
            'RCLC', 'session_end', 'RAID', 'Master-Realm')
        assert(not r.masterLooter and not r.frame.shown)
    ''')


def test_loot_table_ack_window_and_single_response():
    lua = fixture()
    lua.execute(
        r'''
        decodedData = {{{
            session = 77,
            link = '|Hitem:270162::::::::|h[Test Trinket]|h',
        }}}
        assert(r:Register())
        r:OnComm('RCLC', 'lootTable', 'WHISPER', 'Master-Realm')
        assert(#sent == 1 and sent[1].target == 'Master-Realm' and lastSerialized.command == 'lootAck')
        assert(r.masterLooter == 'Master-Realm')
        assert(r.frame and r.frame.shown)
        local row = r.frame.rows[1]
        assert(row.session == 77 and row.link:find('270162', 1, true))
        assert(row.icon.texture == 98765, 'item icon is the fifth API return value, before classID')
        local need = buttonsByText['Нужно']
        assert(need and need.scripts.OnClick)
        failComm = true
        need.scripts.OnClick()
        assert(not row.answered and row.alpha == 1, 'failed send must allow retry')
        failComm = false
        need.scripts.OnClick()
        need.scripts.OnClick()
        assert(#sent == 2, 'answered row must not send duplicate responses')
        assert(lastSerialized.command == 'response')
        assert(lastSerialized.data[1] == 77)
        assert(lastSerialized.data[2].response == 1)
        assert(row.answered and row.alpha == .45)
        '''
    )


def test_malformed_or_disabled_messages_are_ignored():
    lua = fixture()
    lua.execute(
        r'''
        r:OnComm('OTHER', 'lootTable', 'WHISPER', 'Master-Realm')
        assert(r:Register())
        r:OnComm('RCLC', 'bad-codec', 'WHISPER', 'Master-Realm')
        r:OnComm('RCLC', 'bad-deflate', 'WHISPER', 'Master-Realm')
        r:OnComm('RCLC', 'bad-ser', 'WHISPER', 'Master-Realm')
        assert(#sent == 0 and not r.frame)
        for _, malformed in ipairs({123, 'bad', true, {123}, {'bad'}, {false}}) do
            decodedData = malformed
            r:OnComm('RCLC', 'lootTable', 'WHISPER', 'Master-Realm')
        end
        assert(#sent == 0 and not r.frame and not r.masterLooter, 'malformed envelope ignored')
        rcLoaded = true
        decodedData = {{{session = 1, link = '|Hitem:270162::::::::|h[Test]|h'}}}
        r:OnComm('RCLC', 'lootTable', 'WHISPER', 'Master-Realm')
        assert(#sent == 0 and not r.frame)
        rcLoaded = false
        r:OnComm('RCLC', 'lootTable', 'WHISPER', nil)
        r:OnComm('RCLC', 'lootTable', 'WHISPER', '')
        assert(#sent == 0 and not r.frame)
        '''
    )


def test_malformed_loot_entries_are_skipped():
    lua = fixture()
    lua.execute(
        r'''
        assert(r:Register())
        decodedData = {{123, {session = 9}, {
            session = 10,
            link = '|Hitem:270162::::::::|h[Test Trinket]|h',
        }}}
        r:OnComm('RCLC', 'lootTable', 'WHISPER', 'Master-Realm')
        assert(#sent == 1 and r.frame and r.frame.shown)
        assert(r.frame.rows[1].session == 9 and r.frame.rows[1].link == nil)
        assert(r.frame.rows[2].session == 10 and r.frame.rows[2].link:find('270162', 1, true))
        assert(r.frame.rows[3] == nil or not r.frame.rows[3].shown)
        '''
    )


def test_invalid_sessions_and_send_errors_are_ignored():
    lua = fixture()
    lua.execute(
        r'''
        assert(r:Register())
        r.masterLooter = 'Master-Realm'
        r:Respond(0, 1)
        r:Respond('', 1)
        r:Respond(false, 1)
        r:Respond({}, 1)
        r:Respond(-1, 1)
        r:Respond(1.5, 1)
        r:Respond(math.huge, 1)
        assert(#sent == 0, 'invalid sessions must not produce responses')

        failSerialize = true
        r:Send('Master-Realm', 'lootAck')
        assert(#sent == 0, 'serialize failure is contained')

        failSerialize = false
        failComm = true
        r:Send('Master-Realm', 'lootAck')
        assert(#sent == 0, 'comm failure is contained')

        decodedData = {{{session = 1, link = '|Hitem:270162::::::::|h[Test]|h'}}}
        failComm = false
        r:OnComm('RCLC', 'lootTable', 'WHISPER', 'Master-Realm')
        assert(r.masterLooter == 'Master-Realm' and r.frame and r.frame.shown)
        r:OnComm('RCLC', 'session_end', 'WHISPER', 'Other-Realm')
        assert(r.masterLooter == 'Master-Realm' and r.frame.shown, 'unrelated sender cannot end session')
        r:OnComm('RCLC', 'session_end', 'WHISPER', 'Master-Realm')
        assert(r.masterLooter == nil and not r.frame.shown)
        '''
    )


if __name__ == "__main__":
    test_real_acecomm_callback_dispatch()
    test_register_and_disable_when_real_rclootcouncil_is_loaded()
    test_loot_table_ack_window_and_single_response()
    test_malformed_or_disabled_messages_are_ignored()
    test_malformed_loot_entries_are_skipped()
    test_invalid_sessions_and_send_errors_are_ignored()
    print("RCLootBridge: protocol, disable guard, malformed payloads, send failures and duplicate answers passed")
