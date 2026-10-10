-- Minimal WoW API mock for Wowstagram tests (taken from Flintar's Fun 'n' Games).
-- One copy per simulated player (each runs in its own Lua VM); run.mjs passes
-- addon messages between them.
local methods = {}
setmetatable(methods, { __index = function(_, k)
    if type(k) == "string" and k:match("^[A-Z]") then return function() end end
end })
local Obj = { __index = methods }
EVENTS = {}
CHAT = {}
TIMERS = {}
CLOCK = 1000

local function new(kind, name, parent)
    local o = setmetatable({ _kind = kind, _scripts = {}, _shown = true, _parent = parent }, Obj)
    if parent and type(parent) == "table" then
        parent._children = parent._children or {}
        table.insert(parent._children, o)
    end
    if name then _G[name] = o end
    return o
end

function methods:SetScript(k, f) self._scripts[k] = f end
function methods:GetScript(k) return self._scripts[k] end
function methods:HookScript(k, f)
    local old = self._scripts[k]
    self._scripts[k] = old and function(...) old(...) f(...) end or f
end
function methods:Show()
    local was = self._shown
    self._shown = true
    if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
-- Hiding a frame fires OnHide on it and on its shown children (as WoW does).
local function FireHide(f)
    if f._scripts.OnHide then f._scripts.OnHide(f) end
    for _, c in ipairs(f._children or {}) do
        if c._shown then FireHide(c) end
    end
end
function methods:Hide()
    local was = self._shown
    self._shown = false
    if was then FireHide(self) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown end
function methods:SetText(t) self._text = t end
function methods:GetText() return self._text end
function methods:SetChecked(v) self._checked = v end
function methods:GetChecked() return self._checked end
function methods:SetEnabled(v) self._enabled = v and true or false end
function methods:Enable() self._enabled = true end
function methods:Disable() self._enabled = false end
function methods:IsEnabled() return self._enabled ~= false end
function methods:SetTexture(t) self._tex = t return true end
function methods:CreateTexture() return new("Texture", nil, self) end
function methods:CreateFontString() return new("FontString", nil, self) end
function methods:GetFont() return self._font or "Fonts\\FRIZQT__.TTF", self._fontSize or 12, self._fontFlags or "" end
function methods:SetFont(f, size, flags) self._font, self._fontSize, self._fontFlags = f, size, flags return true end
-- Roughly half the font size per letter.
function methods:GetStringWidth() return #(self._text or "") * (self._fontSize or 12) * 0.5 end
function methods:GetWidth() return self._w or 500 end
function methods:GetHeight() return self._h or 400 end
function methods:SetSize(w, h) self._w, self._h = w, h end
function methods:SetWidth(w) self._w = w end
function methods:SetHeight(h) self._h = h end
function methods:GetCenter() return 0, 0 end
function methods:GetEffectiveScale() return 1 end
function methods:SetScale(k) self._scale = k end
-- 3D: model scenes have actors with a bounding box; creatures have a display id.
function methods:SetLightAmbientColor(r, g, b) self._ambient = { r, g, b } end
function methods:SetLightDiffuseColor(r, g, b) self._diffuse = { r, g, b } end
function methods:CreateActor()
    local a = new("Actor", nil, self)
    function a:GetActiveBoundingBox() return -1, -1, 0, 1, 1, 2 end
    return a
end
-- Each creature has its own look (100000 + its npc id).
function methods:SetCreature(npc) self._npc = npc end
function methods:GetDisplayInfo() return self._npc and (100000 + self._npc) or 4321 end
function methods:SetCameraPosition(x, y, z) self._cam = { x, y, z } end
function methods:GetScale() return self._scale or 1 end
function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods:RegisterEvent(e)
    EVENTS[e] = EVENTS[e] or {}
    table.insert(EVENTS[e], self)
end
function methods:CreateAnimationGroup()
    local ag = new("AnimationGroup")
    function ag:CreateAnimation() return new("Animation") end
    function ag:Play() self._playing = true end
    function ag:Stop() self._playing = false end
    return ag
end

function Fire(event, ...)
    for _, f in ipairs(EVENTS[event] or {}) do f._scripts.OnEvent(f, event, ...) end
end

-- Run timers that are due by CLOCK (all of them when `all`).
function Advance(seconds)
    CLOCK = CLOCK + (seconds or 0)
    local again = true
    while again do
        again = false
        for i, t in ipairs(TIMERS) do
            if t.at <= CLOCK then
                table.remove(TIMERS, i)
                t.fn()
                again = true
                break
            end
        end
    end
end

CreateFrame = function(kind, name, parent, template)
    local f = new(kind, name, parent)
    if template == "ButtonFrameTemplate" then f.Inset = new("Frame", nil, f) end
    if template == "UIPanelScrollFrameTemplate" then f.ScrollBar = new("Slider", nil, f) end
    return f
end
UIParent = new("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
Minimap = new("Frame", "Minimap")
GameTooltip = new("GameTooltip", "GameTooltip")
GameTooltip_Hide = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(CHAT, m) end }
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function(name, _, _, data) POPUP = { which = name, data = data } end
StaticPopup_Hide = function() POPUP = nil end
function AnswerPopup() StaticPopupDialogs[POPUP.which].OnAccept(nil, POPUP.data) POPUP = nil end
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function(d, fn) table.insert(TIMERS, { at = CLOCK + d, fn = fn }) end }
GetTime = function() return CLOCK end
time = function() return math.floor(CLOCK) end
date = os.date
math.atan2 = math.atan2 or math.atan
GetCoinTextureString = function(c)
    local out = {}
    local g, s, k = c // 10000, (c // 100) % 100, c % 100
    if g > 0 then table.insert(out, math.floor(g) .. "g") end
    if s > 0 then table.insert(out, math.floor(s) .. "s") end
    if k > 0 then table.insert(out, math.floor(k) .. "c") end
    return table.concat(out, " ")
end
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"

-- The player and their group.
PLAYER_NAME = PLAYER_NAME or "Flintar"
GROUP = GROUP or {}  -- names of the others in the party
UnitName = function(u) if u == "player" then return PLAYER_NAME end end
IsInRaid = function() return false end
IsInGroup = function() return #GROUP > 0 end
UnitInParty = function(n) for _, g in ipairs(GROUP) do if g == n then return true end end return false end
UnitInRaid = function() return nil end

-- Outgoing traffic, picked up by run.mjs.
OUTBOX = {}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel) table.insert(OUTBOX, { "addon", prefix, msg, channel }) end,
}
-- Real rolls: the "server" (run.mjs) decides the number via ROLL_SOURCE.
ROLL_SOURCE = function(lo, hi) return math.random(lo, hi) end
RandomRoll = function(lo, hi)
    table.insert(OUTBOX, { "roll", PLAYER_NAME, ROLL_SOURCE(lo, hi), lo, hi })
end

-- WoW's bit library (Lua 5.1 BitOp), on Lua 5.4 operators.
local function I(x) return math.tointeger(math.floor(x) % 4294967296) end
bit = {
    band = function(a, ...) local r = I(a) for _, b in ipairs({ ... }) do r = r & I(b) end return r end,
    bor = function(a, ...) local r = I(a) for _, b in ipairs({ ... }) do r = r | I(b) end return r end,
    bxor = function(a, ...) local r = I(a) for _, b in ipairs({ ... }) do r = r ~ I(b) end return r end,
    bnot = function(a) return (~I(a)) & 0xFFFFFFFF end,
    rshift = function(a, n) return I(a) >> n end,
    lshift = function(a, n) return (I(a) << n) & 0xFFFFFFFF end,
}
unpack = table.unpack
C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
    table.insert(OUTBOX, { "addon", prefix, msg, channel, target or "" })
end
function methods:GetFrameLevel() return self._level or 1 end
function methods:SetFrameLevel(l) self._level = l end
function methods:GetParent() return self._parent end

-- Trading
TRADE_PARTNER, TRADE_MINE, TRADE_THEIRS = nil, 0, 0
local baseUnitName = UnitName
UnitName = function(u) if u == "NPC" then return TRADE_PARTNER end return baseUnitName(u) end
GetPlayerTradeMoney = function() return TRADE_MINE end
GetTargetTradeMoney = function() return TRADE_THEIRS end
ERR_TRADE_COMPLETE = "Trade complete."
WHISPERS = {}
SendChatMessage = function(msg, channel, _, target) table.insert(WHISPERS, { msg, channel, target }) end

-- Group units and connections: party1..N are the others in GROUP.
OFFLINE = {}
GetNumGroupMembers = function() return #GROUP > 0 and #GROUP + 1 or 0 end
local unitNameBefore = UnitName
UnitName = function(u)
    local i = type(u) == "string" and tonumber(u:match("^party(%d+)$"))
    if i then return GROUP[i] end
    return unitNameBefore(u)
end
UnitIsConnected = function(u) local n = UnitName(u) return n ~= nil and not OFFLINE[n] end

-- Single-player tests: rolls come straight back as system messages.
DIRECT_ROLLS = false
local queuedRoll = RandomRoll
RandomRoll = function(lo, hi)
    if not DIRECT_ROLLS then return queuedRoll(lo, hi) end
    Fire("CHAT_MSG_SYSTEM", PLAYER_NAME .. " rolls " .. ROLL_SOURCE(lo, hi) .. " (" .. lo .. "-" .. hi .. ")")
end
function methods:SetPoint(...) self._point = { ... } end

-- Portraits and classes.
PORTRAITS = {}
SetPortraitTexture = function(tex, unit) tex._portrait = unit table.insert(PORTRAITS, unit) end
UnitExists = function(u) return u == "player" or UnitName(u) ~= nil end
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 }, PRIEST = { 0.5, 0.75, 0.25, 0.5 },
    ROGUE = { 0.5, 0.75, 0, 0.25 } }
UnitClass = function(u) if UnitExists(u) then return "Warrior", "WARRIOR", 1 end end

-- Sounds: count what plays.
SOUNDS = {}
SOUNDKIT = setmetatable({}, { __index = function(_, k) return k end })
PlaySound = function(kit) table.insert(SOUNDS, kit) end
SOUND_FILES = {}
PlaySoundFile = function(id, channel)
    table.insert(SOUND_FILES, id)
    return true, #SOUND_FILES
end
StopSound = function() end

-- Guild and hidden chat channels.
IN_GUILD = false
IsInGuild = function() return IN_GUILD end
CHANNELS, CHANNEL_NAMES, NEXT_CHANNEL = {}, {}, 5
JoinTemporaryChannel = function(name)
    if not CHANNELS[name] then
        CHANNELS[name] = NEXT_CHANNEL
        CHANNEL_NAMES[NEXT_CHANNEL] = name
        NEXT_CHANNEL = NEXT_CHANNEL + 1
    end
end
GetChannelName = function(name) return CHANNELS[name] or 0 end
GetRealmName = function() return REALM_NAME or "Realm" end
GetNormalizedRealmName = function() return (GetRealmName():gsub("[%s%-]", "")) end
LeaveChannelByName = function(name)
    local id = CHANNELS[name]
    if id then CHANNEL_NAMES[id] = nil end
    CHANNELS[name] = nil
end
-- WoW's send limit, as the real client does it: each prefix gets a burst of
-- 10 messages, then one a second; anything over is refused (result 3,
-- AddonMessageThrottle) and never sent.
SEND_LIMIT = true
local sendBucket = {}
C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
    if SEND_LIMIT then
        local b = sendBucket[prefix] or { tokens = 10, t = CLOCK }
        sendBucket[prefix] = b
        b.tokens = math.min(10, b.tokens + (CLOCK - b.t))
        b.t = CLOCK
        if b.tokens < 1 then
            SENDS_REFUSED = (SENDS_REFUSED or 0) + 1
            return 3
        end
        b.tokens = b.tokens - 1
    end
    if channel == "CHANNEL" then target = CHANNEL_NAMES[target] end
    table.insert(OUTBOX, { "addon", prefix, msg, channel, target or "" })
    return 0
end

-- Mouse and combat
MOUSE_DOWN = false
IsMouseButtonDown = function() return MOUSE_DOWN end
InCombatLockdown = function() return false end
CURSOR_X, CURSOR_Y = 0, 0
GetCursorPosition = function() return CURSOR_X, CURSOR_Y end

---------------------------------------------------------------------------
-- Wowstagram: characters, gear, the player actor and transmog.
---------------------------------------------------------------------------
UnitRace = function(u) if u == "player" then return "Human", "Human", 1 end end
UnitSex = function() return 2 end
UnitLevel = function() return 60 end
GetGuildInfo = function() return nil end
UnitIsPlayer = function() return true end
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
hooksecurefunc = function(name, fn)
    local old = _G[name]
    _G[name] = function(...) local r = old and old(...) fn(...) return r end
end
HandleModifiedItemClick = function() end
IsShiftKeyDown = function() return SHIFT_DOWN end
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
CURSOR = nil -- { "item", id, link }
GetCursorInfo = function() if CURSOR then return CURSOR[1], CURSOR[2], CURSOR[3] end end
ClearCursor = function() CURSOR = nil end

-- What you wear: slot -> item id. Items the client knows: id -> equip location.
EQUIPPED = { [1] = 16963, [5] = 16966, [16] = 17076 }
ITEMS = { [16963] = "INVTYPE_HEAD", [16966] = "INVTYPE_CHEST", [17076] = "INVTYPE_2HWEAPON",
    [21524] = "INVTYPE_HEAD", [18832] = "INVTYPE_WEAPON", [2575] = "INVTYPE_BODY" }
UNCACHED = {} -- ids the client hasn't fetched yet
GetInventoryItemID = function(_, slot) return EQUIPPED[slot] end
local function ItemInfo(item)
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)") or item)
    if not id or not ITEMS[id] or UNCACHED[id] then return nil end
    return "Item " .. id, "|cffa335ee|Hitem:" .. id .. "::|h[Item " .. id .. "]|h|r", 4, 60, 60, "Armor", "Plate", 1, ITEMS[id]
end
GetItemInfo = ItemInfo
C_Item = {
    GetItemInfo = ItemInfo,
    RequestLoadItemDataByID = function(id) REQUESTED = id end,
    GetItemIconByID = function(id) return "icon" .. id end,
}
-- Transmog: appearance source = item id + 100000 (mock).
TRANSMOG = true
C_TransmogCollection = {
    GetItemInfo = function(item)
        local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)") or item)
        if TRANSMOG and id then return id + 50000, id + 100000 end
    end,
    GetSourceInfo = function(source) return { itemID = source - 100000 } end,
}
ItemUtil = { CreateItemTransmogInfo = function(a, s, i)
    return { appearanceID = a, secondaryAppearanceID = s, illusionID = i }
end }

function methods:SetModelByUnit(unit, sheathe) self._unit, self._sheathe, self._worn = unit, sheathe, {} end
function methods:Undress() self._worn = {} end
function methods:TryOn(item, hand) self._worn = self._worn or {} table.insert(self._worn, { try = item, hand = hand }) end
function methods:SetItemTransmogInfo(info, slot) self._worn = self._worn or {} self._worn[slot] = info end
function methods:SetAnimation(anim, variation, speed) self._anim, self._animSpeed = anim, speed end
function methods:SetYaw(y) self._yaw = y end
function methods:SetRoll(r) self._roll = r end
function methods:SetDesaturation(k) self._grey = k end
function methods:GetItemTransmogInfoList()
    if not TRANSMOG then return nil end
    local list = {}
    for slot = 1, 19 do list[slot] = { appearanceID = EQUIPPED[slot] and (EQUIPPED[slot] + 100000) or 0,
        secondaryAppearanceID = 0, illusionID = 0 } end
    return list
end
function methods:GetCameraForward() return -1, 0, 0 end
function methods:GetStringHeight() return 14 end
function methods:SetFocus() self._focus = true end
function methods:ClearFocus() self._focus = false end
function methods:HasFocus() return self._focus == true end
function methods:GetEffectiveScale() return 1 end

-- Your target: { name, realm } (realm nil: your own realm, as WoW does it).
TARGET = nil
local unitNameHg = UnitName
UnitName = function(u)
    if u == "target" then
        if TARGET then return TARGET[1], TARGET[2] end
        return nil
    end
    return unitNameHg(u)
end

-- Which game: Retail 120100, WoW Forever 16001 (run.mjs sets BUILD_TOC).
GetBuildInfo = function() return "12.1.0", "69933", "Oct 1 2026", BUILD_TOC or 120100 end

-- The body is 2 tall; dressed, a polearm on the back makes the box 3 tall.
function methods:SetModelByUnit(unit, sheathe, autoDress, hideWeapons)
    self._unit, self._sheathe, self._worn, self._bare = unit, sheathe, {}, hideWeapons and not autoDress
end
function methods:GetActiveBoundingBox() return -0.5, -0.5, 0, 0.5, 0.5, self._bare and 2 or 3 end
function methods:SetAlpha(a) self._alpha = a end
-- Run a frame's OnUpdate for a while, like the game does every frame.
function Pump(frame, seconds)
    local f = frame._scripts.OnUpdate
    for _ = 1, math.floor((seconds or 1) / 0.05) do if f then f(frame, 0.05) end end
end

-- Guild: GUILD_ROSTER lists names as WoW gives them ("Name-Realm" on Retail).
GUILD_ROSTER = {}
GetNumGuildMembers = function() return #GUILD_ROSTER end
GetGuildRosterInfo = function(i) return GUILD_ROSTER[i] end
C_GuildInfo = { GuildRoster = function() end }

-- Fonts and the flat UI.
CreateFont = function(name) local f = setmetatable({ _kind = "Font", _scripts = {} }, { __index = function() return function() end end }) _G[name] = f return f end
STANDARD_TEXT_FONT = "Fonts/FRIZQT__.TTF"
function methods:SetCameraFieldOfView(f) self._fov = f end
-- Remember every anchor point, not only the last one.
function methods:SetPoint(...)
    local args = { ... }
    self._point = args
    self._points = self._points or {}
    self._points[args[1]] = args
end
function methods:ClearAllPoints() self._points = {} end

function methods:SetModelByCreatureDisplayID(d) self._display, self._unit, self._worn = d, nil, {} end
-- Anyone on a unit is a Human (race 1), sex 2, unless told otherwise.
UnitRace = function(u) if UnitExists(u) then return "Human", "Human", 1 end end
UnitSex = function() return 2 end

function methods:SetModelByUnit(unit, sheathe, autoDress, hideWeapons, native, bow, race)
    self._unit, self._sheathe, self._worn, self._race, self._display = unit, sheathe, {}, race, nil
    self._bare = hideWeapons and not autoDress
end
-- Instant item info: armour class 4; subclass 4 (plate) for the Wrath pieces, 1 (cloth) otherwise.
ITEM_SUBCLASS = { [16963] = 4, [16966] = 4 }
C_Item.GetItemInfoInstant = function(item)
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)") or item)
    if not id or not ITEMS[id] then return nil end
    return id, "Armor", "", ITEMS[id], "icon", 4, ITEM_SUBCLASS[id] or 1
end
-- Players with nameplates: nameplate1.. are the names in NAMEPLATE.
NAMEPLATE = {}
local unitNameNp = UnitName
UnitName = function(u)
    local i = type(u) == "string" and tonumber(u:match("^nameplate(%d+)$"))
    if i then return NAMEPLATE[i] end
    return unitNameNp(u)
end
C_CreatureInfo = { GetRaceInfo = function(r) local n = { [1] = "Human", [2] = "Orc", [4] = "Night Elf" } return n[r] and { raceName = n[r] } end }

-- The friend list (tests set FRIENDS = { "Name", ... }).
FRIENDS = {}
C_FriendList = C_FriendList or {}
C_FriendList.GetNumFriends = function() return #FRIENDS end
C_FriendList.GetFriendInfoByIndex = function(i) return FRIENDS[i] and { name = FRIENDS[i] } or nil end
C_FriendList.ShowFriends = function() end
