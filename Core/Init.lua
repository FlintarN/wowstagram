-- Wowstagram: pictures of your character, shared with the realm.
--
-- A "picture" is never an image: it is a short string describing an outfit,
-- a pose, an angle and a filter (Core\Look.lua). Everyone's addon draws it
-- again with the game's own 3D model.
--
-- Init owns the namespace, the event bus, saved variables, small helpers and
-- the slash command. Everything else hangs off `ns`.
local ADDON, ns = ...

ns.TITLE = "Wowstagram"
ns.ICON = "Interface\\AddOns\\Wowstagram\\Art\\Logo"

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Wowstagram:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Game events: several handlers per event
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do fn(...) end
end)

---------------------------------------------------------------------------
-- Change bus: anything that alters posts, likes or profiles calls
-- ns.Changed(); the window redraws once, a moment later, and at most four
-- times a second however busy the channel is. (Likes you make show at once
-- anyway: the pages draw those themselves.)
---------------------------------------------------------------------------
local listeners = {}
local pending = false
local lastFire = -1
ns.REDRAW_GAP = 0.25

function ns.OnChange(fn)
    table.insert(listeners, fn)
end

local function Clock() return GetTime and GetTime() or 0 end

local function FireChange()
    pending = false
    lastFire = Clock()
    for _, fn in ipairs(listeners) do fn() end
end

function ns.Changed()
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(0, lastFire + ns.REDRAW_GAP - Clock()), FireChange)
    else
        FireChange()
    end
end

function ns.After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Which game: WoW Forever runs on the Retail engine but reports its own
-- interface version (1.60.x: 16001); Retail is 12.x (120100).
ns.FOREVER = ((select(4, GetBuildInfo())) or 0) < 100000

---------------------------------------------------------------------------
-- Who is who. Every player is known by one id.
--   Retail:  name, "-", realm without spaces or dashes, the way WoW writes
--            it ("Bob-Silvermoon", "Bob-ArgentDawn").
--   Forever: just the name. There are no realms (only rulesets), and names
--            are two words ("First Last").
--
-- Never take a name apart, or cut it at a space or a dash: names can have
-- both. The parts always come separately (UnitName gives name and realm),
-- and a sender writes their own id into every message (Core\Net.lua). On
-- Retail the only safe split is at the LAST dash, because a realm name never
-- has one; on Forever, ids are never split at all.
---------------------------------------------------------------------------
local myRealm
function ns.Realm()
    if ns.FOREVER then return "" end
    if myRealm then return myRealm end
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if r and r ~= "" then
        myRealm = r -- (nil early in the login on Retail: don't keep the guess)
        return r
    end
    return ((GetRealmName and GetRealmName() or ""):gsub("[%s%-]", ""))
end

-- An id from a name and realm (no realm or "": your realm).
function ns.Id(name, realm)
    if not name or name == "" then return nil end
    if ns.FOREVER then return name end
    realm = realm and realm ~= "" and realm:gsub("[%s%-]", "") or ns.Realm()
    if realm == "" then return name end
    return name .. "-" .. realm
end

-- The id of whoever is on a unit ("target", "party1"), or nil.
function ns.UnitId(unit)
    local name, realm = UnitName(unit)
    return ns.Id(name, realm)
end

function ns.Me()
    return ns.UnitId("player")
end

-- How to show an id: on Retail the name alone for your own realm and
-- "Name-Realm" for another; on Forever the id is the name.
function ns.Display(id)
    if not id then return "?" end
    if ns.FOREVER then return id end
    local name, realm = id:match("^(.+)%-([^%-]+)$")
    if name and realm == ns.Realm() then return name end
    return id
end

function ns.Now()
    return time and time() or 0
end

-- "just now", "5m", "3h", "2d", "4w": as Instagram writes it.
function ns.Ago(t)
    local d = ns.Now() - (t or 0)
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    if d < 86400 then return math.floor(d / 3600) .. "h" end
    if d < 86400 * 7 then return math.floor(d / 86400) .. "d" end
    return math.floor(d / (86400 * 7)) .. "w"
end

-- Class colour as a |c code ("ffc79c6e"), grey when unknown.
function ns.ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then return c.colorStr end
    if c then return string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5)) end
    return "ffcccccc"
end

-- A name from the network, as a name: 2 to 64 bytes, no control
-- characters, no "|" (WoW's colour, texture and link codes) and none of the
-- characters messages are built with. (WoW's own names never have them.)
function ns.ValidName(name)
    return type(name) == "string" and #name >= 2 and #name <= 64 and not name:find("[%c|,=;:]")
        and not name:find("^%s") and not name:find("%s$") and not name:find("%s%s")
end

-- A class token from the network: a real class, or nothing.
function ns.ValidClass(class)
    if type(class) ~= "string" or #class > 16 or not class:match("^%u+$") then return nil end
    if RAID_CLASS_COLORS and not RAID_CLASS_COLORS[class] then return nil end
    return class
end

-- Text from anyone, for a chat line or a plain label: "|" doubled.
function ns.Plain(text)
    return (tostring(text or ""):gsub("|", "||"))
end

function ns.ColorName(id, class)
    return "|c" .. ns.ClassHex(class) .. ns.Display(id) .. "|r"
end

-- Counts: 999, 1.2k, 15k.
function ns.Count(n)
    n = n or 0
    if n < 1000 then return tostring(n) end
    if n < 10000 then return string.format("%.1fk", n / 1000) end
    return math.floor(n / 1000) .. "k"
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULTS = {
    posts = {},       -- newest first; see Core\Social.lua for the shape
    tombs = {},       -- deleted posts and comments, so a sync can't bring them back
    profiles = {},    -- id -> { class, race, level, guild, bio, t }
    saved = {},       -- post id -> time you bookmarked it
    unsaved = {},     -- post id -> time you took the bookmark off (kept a while, in case it was a slip)
    faceTune = {},    -- (development) face filter corrections tuned on /wgram wall
    blocked = {},     -- id -> when you blocked them: their pictures and comments are hidden
    met = {},         -- id -> when you last saw them (nameplates, target, group, chat nearby)
    strikes = {},     -- id -> { n = points, t = when }: caught faking (Social)
    users = {},       -- id -> when their addon last sent you anything (they have Wowstagram)
    softTombs = {},   -- "p:id" / "c:id:author:t" -> { t, from }: a deletion passed on by someone else (Social)
    faceObs = {},     -- (development) what the camera saw for each tuned face
    seen = {},        -- post id -> true once you've looked at it (story rings)
    minimap = true,
    minimapAngle = 220,
    sound = true,
    notify = true,    -- chat line when someone likes or comments on your picture
    network = true,   -- join the hidden realm channel and share posts
    demo = false,     -- practice: demo people with their own posts (Settings)
    scale = 1,
}

-- Per character (ns.my = WowstagramDB.chars[id]): what's about you as
-- this character. Everything else (pictures, profiles, settings, saved,
-- blocked...) is shared by all your characters.
local CHAR_DEFAULTS = {
    me = { bio = "", t = 0 },
    following = {},   -- id -> time you followed them
    activity = {},    -- likes and comments on your pictures, newest first
    unread = 0,
    myComments = {},  -- "post id:time" -> fingerprint of each comment you wrote (to vouch for it)
    myLikes = {},     -- post id -> your like's time (minus: taken back), to vouch for it
}

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
                ApplyDefaults(db[k], v)
            else
                db[k] = v
            end
        elseif type(v) == "table" and type(db[k]) == "table" then
            ApplyDefaults(db[k], v)
        end
    end
end

-- This character's own data (ns.my). An older copy of the addon kept it
-- for the whole account: it goes to the character it belongs to, the one
-- who posted pictures here (or the first to log in, if nobody did).
local OLD_CHAR_KEYS = { "me", "following", "activity", "unread", "myComments", "myLikes" }
function ns.LoadCharacter()
    local db = ns.db
    db.chars = db.chars or {}
    local id = ns.Me()
    local c = db.chars[id]
    if not c then
        c = {}
        db.chars[id] = c
        if db.me ~= nil and not db.charsClaimed then
            local mine, anyone = false, false
            for _, p in ipairs(db.posts or {}) do
                if not p.bot then
                    anyone = true
                    if p.author == id then mine = true end
                end
            end
            if mine or not anyone then
                for _, k in ipairs(OLD_CHAR_KEYS) do c[k] = db[k] end
                c.since, c.forgotBefore = db.since, db.forgotBefore
                db.charsClaimed = true
            end
        end
    end
    if db.charsClaimed then
        for _, k in ipairs(OLD_CHAR_KEYS) do db[k] = nil end
        db.since, db.forgotBefore = nil, nil
    end
    ApplyDefaults(c, CHAR_DEFAULTS)
    -- When this character started keeping a record of its things (to vouch
    -- for them); a claimed record from an older copy may have gaps.
    c.since = c.since or ns.Now()
    ns.my = c
end

-- Settings, "Clear everything": every post, profile and follow forgotten.
-- The switches stay as they are.
local DATA = { "posts", "tombs", "profiles", "saved", "unsaved", "blocked", "met", "strikes", "users", "softTombs", "seen", "chars" }
function ns.ResetAll()
    for _, k in ipairs(DATA) do ns.db[k] = nil end
    ApplyDefaults(ns.db, DEFAULTS)
    ns.LoadCharacter()
    -- (Anything of yours from before now can't be vouched for: Social.)
    ns.my.forgotBefore = ns.Now()
    if ns.Bots then ns.Bots:Sync() end
    ns.Changed()
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    WowstagramDB = WowstagramDB or {}
    if not WowstagramDB.v1 then
        wipe(WowstagramDB)
        WowstagramDB.v1 = true
    end
    ns.db = WowstagramDB
    -- v2: players are "Name-Realm" ids. Data from before can't be matched up.
    if not WowstagramDB.v2 then
        for _, k in ipairs(DATA) do WowstagramDB[k] = nil end
        WowstagramDB.v2 = true
    end
    ApplyDefaults(WowstagramDB, DEFAULTS)
    ns.LoadCharacter()
    WowstagramDB.drafts = nil -- (Create no longer keeps a draft)

    ns.Net:Init()
    ns.Social:Init()
    ns.Bots:Sync()
    ns.Minimap:Build()
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
-- Only these two. The development ones (reset, stats, probe, wall, cvars,
-- racetest, placeholders, boxes, debug) only work with ns.DEV = true, set
-- in this file while working on the addon (never in a release).
ns.DEV = false
local HELP = {
    "/wgram - open or close Wowstagram",
    "/wgram demo - demo people on or off (made-up people to try it all alone)",
}

SLASH_WOWSTAGRAM1 = "/wgram"
SLASH_WOWSTAGRAM2 = "/wowstagram"
SlashCmdList.WOWSTAGRAM = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd ~= "" and cmd ~= "demo" and not ns.DEV then
        for _, line in ipairs(HELP) do ns.Print(line) end
        return
    end
    if cmd == "" then
        ns.UI:Toggle()
    elseif cmd == "demo" then
        local on = not ns.db.demo
        ns.Bots.SetEnabled(on)
        ns.Changed()
        ns.Print(on and "Demo people are on: made-up people with their own pictures, who react to yours. /wgram demo again to send them away."
            or "Demo people are off.")
    elseif cmd == "reset" then
        ns.db.windowPos = nil
        ns.UI:ResetPosition()
    elseif cmd == "probe" then
        ns.Picture.Probe()
    elseif cmd == "boxes" then
        ns.Picture.Boxes()
    elseif cmd:match("^cvars") then
        -- (development) every game setting whose name has a word in it,
        -- with its value: run it before and after changing an option to
        -- see which setting it is.
        local word = cmd:match("^cvars%s+(.+)$") or "model"
        local list = C_Console and C_Console.GetAllCommands and C_Console.GetAllCommands() or {}
        local n = 0
        for _, c in ipairs(list) do
            local name = c.command or c.name
            if name and name:lower():find(word, 1, true) and GetCVar then
                local ok, value = pcall(GetCVar, name)
                if ok and value ~= nil then
                    ns.Print(name .. " = " .. tostring(value))
                    n = n + 1
                end
            end
        end
        ns.Print(n .. " settings with \"" .. word .. "\" in the name" .. (#list == 0 and " (this client can't list them)." or "."))
    elseif cmd == "wall" then
        ns.Picture.Wall()
    elseif cmd == "placeholders" then
        ns.Picture.PlaceholderReview()
    elseif cmd == "racetest" then
        ns.Picture.RaceTest()
    elseif cmd == "stats" then
        local t = ns.Net.Traffic()
        local tombs = 0
        for _ in pairs(ns.db.tombs) do tombs = tombs + 1 end
        ns.Print(string.format("Last minute: %d messages in (%.1f KB), %d out (%.1f KB).", t.inN, t.inB / 1024, t.outN,
            t.outB / 1024))
        ns.Print(string.format("People heard from in the last 10 minutes: %d. Waiting to be sent: %d. Dropped (too "
            .. "many, too big): %d.", ns.Net.Peers(600), ns.Net.Waiting(), ns.Net.dropped))
        ns.Print(string.format("Stored: %d pictures, %d deletions remembered.", #ns.db.posts, tombs))
    elseif cmd == "debug" then
        ns.debug = not ns.debug
        ns.Print("Debug: " .. (ns.debug and "on" or "off"))
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end
