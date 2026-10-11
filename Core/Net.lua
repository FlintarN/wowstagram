-- Net: addon messages. Long messages are cut into numbered chunks and put
-- back together on the other side.
--
-- Two scopes: "realm", a hidden chat channel that every Wowstagram player on
-- the realm joins (same faction: WoW keeps custom channels per faction), and
-- "guild", the guild's addon channel, so guildmates always reach each other.
-- Messages to one player go by whisper.
--
-- Wire format: "<cmd>:<msgId>:<part>/<parts>@<from>#<protocol>:<data>". <from> is the
-- sender's own id ("Name-Realm", see ns.Id), built from their own UnitName
-- and realm, so nobody has to take the sender string WoW gives apart: on
-- Retail that's "Name-Realm", and WoW Forever names are two words.
local ADDON, ns = ...

local Net = {}
ns.Net = Net

Net.PREFIX = "Wowstagram"
-- The protocol: what the messages mean. Rules for the future:
--   * new information goes in NEW FIELDS AT THE END of a message; older
--     clients ignore fields they don't know (Social's Split drops extras).
--     That needs no new number;
--   * a change that older clients would misread (a field's meaning or
--     order) bumps Net.PROTO. Messages with another number are ignored, and
--     a newer one tells the player, once, that an update is out.
Net.PROTO = 2
Net.CHANNEL = "WowstagramRealm"
-- WoW lets each prefix send about one message a second after a short burst.
-- A picture is two or three parts and a sync is dozens, so the parts are
-- dealt over a few prefixes, each with its own limit.
Net.SPREAD = { "Wowstagram", "Wowstagram2", "Wowstagram3", "Wowstagram4" }
local OURS = {}
for _, p in ipairs(Net.SPREAD) do OURS[p] = true end
local spreadNext = 0
local MAX = 250 -- bytes in one addon message, with room to spare (WoW allows 255)

local SendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

local handlers = {}
local address = {} -- id -> the sender string WoW gave us (a whisper goes to exactly that)
-- A name without spaces, dashes or apostrophes (case kept: WoW's names
-- have one spelling).
local function Squash(s) return ((s or ""):gsub("[%s%-']", "")) end

function Net.Full(name)
    if not name then return name end
    return address[name] or name
end

-- The id a message is from: the one the sender put in it, only when it's
-- exactly the player WoW says sent it (the same letters, the same case;
-- WoW leaves your own realm off). Otherwise built from WoW's sender: on
-- Retail the realm is after the last dash; on Forever the sender is the name.
local function From(raw, said)
    if said and said ~= "" and ns.ValidName(said) then
        local a, b = Squash(raw), Squash(said)
        if a == b or (not raw:find("-", 1, true) and Squash(raw .. ns.Realm()) == b) then return said end
    end
    if ns.FOREVER then return ns.Id(raw) end
    local name, realm = raw:match("^(.+)%-([^%-]+)$")
    if name then return ns.Id(name, realm) end
    return ns.Id(raw)
end
local partial = {}
local nextId = 0

---------------------------------------------------------------------------
-- Keeping it light when many people use it
---------------------------------------------------------------------------
-- A long message is at most this many parts and this many bytes; anything
-- bigger is dropped (a broken or hostile addon). Parts that never complete
-- are forgotten after a while.
Net.MAX_PARTS, Net.MAX_BYTES, Net.PART_TIMEOUT = 24, 5000, 30
Net.MAX_OPEN = 8 -- unfinished long messages per sender at a time

local function Clock0() return GetTime and GetTime() or (time and time() or 0) end

-- Traffic counters for /wgram stats: one bucket per second, the last minute.
local ring = {}
Net.dropped = 0
local function Count(kind, bytes)
    local sec = math.floor(Clock0())
    local b = ring[sec % 60]
    if not b or b.sec ~= sec then
        b = { sec = sec, inN = 0, outN = 0, inB = 0, outB = 0 }
        ring[sec % 60] = b
    end
    b[kind .. "N"] = b[kind .. "N"] + 1
    b[kind .. "B"] = b[kind .. "B"] + (bytes or 0)
end

-- Messages and bytes in and out over the last minute.
function Net.Traffic()
    local now = math.floor(Clock0())
    local t = { inN = 0, outN = 0, inB = 0, outB = 0 }
    for _, b in pairs(ring) do
        if now - b.sec < 60 then
            for k in pairs(t) do t[k] = t[k] + b[k] end
        end
    end
    return t
end

-- Who's been heard from lately: how many people are using it right now.
local peers = {} -- id -> when we last heard from them
function Net.Peers(window)
    local now, n = Clock0(), 0
    for name, t in pairs(peers) do
        if now - t <= (window or 600) then n = n + 1 else peers[name] = nil end
    end
    return n
end

-- Per-sender limits: Net.Allow(sender, "like", 40) is true for up to 40
-- likes a minute from one sender (a burst of that size, then the same rate).
-- Over it, the message is dropped.
local senderBuckets = {}
-- Per-sender records nobody has used for ten minutes go (every few minutes).
function Net.Sweep(now)
    now = now or Clock0()
    if now - (Net.lastBigSweep or 0) < 300 then return end
    Net.lastBigSweep = now
    for k, b in pairs(senderBuckets) do
        if now - b.t > 600 then senderBuckets[k] = nil end
    end
    for name, t in pairs(peers) do
        if now - t > 600 then
            peers[name] = nil
            address[name] = nil
        end
    end
end

function Net.Allow(sender, kind, perMinute)
    local key = kind .. "|" .. (sender or "?")
    local now = Clock0()
    local b = senderBuckets[key]
    if not b then
        b = { tokens = perMinute, t = now }
        senderBuckets[key] = b
    end
    b.tokens = math.min(perMinute, b.tokens + (now - b.t) * perMinute / 60)
    b.t = now
    if b.tokens < 1 then
        Net.dropped = Net.dropped + 1
        return false
    end
    b.tokens = b.tokens - 1
    return true
end

function Net:Init()
    if RegisterPrefix then
        for _, p in ipairs(Net.SPREAD) do RegisterPrefix(p) end
    end
end

function Net.On(cmd, fn)
    handlers[cmd] = fn
end

---------------------------------------------------------------------------
-- The hidden realm channel
---------------------------------------------------------------------------
local function ChannelId(name)
    local id = GetChannelName and GetChannelName(name)
    if id and id ~= 0 then return id end
end

-- Keep our channel out of the chat windows.
local function Hide(name)
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then pcall(ChatFrame_RemoveChannel, frame, name) end
    end
end

-- Join the channel. Returns true once it's usable (joining can take a
-- moment the first time).
function Net.Join()
    if ChannelId(Net.CHANNEL) then return true end
    if JoinTemporaryChannel then JoinTemporaryChannel(Net.CHANNEL) end
    Hide(Net.CHANNEL)
    ns.After(1, function() Hide(Net.CHANNEL) end)
    return ChannelId(Net.CHANNEL) ~= nil
end

function Net.Leave()
    if ChannelId(Net.CHANNEL) and LeaveChannelByName then LeaveChannelByName(Net.CHANNEL) end
end

function Net.Online()
    return ChannelId(Net.CHANNEL) ~= nil
end

---------------------------------------------------------------------------
-- WoW's limit: each prefix may send a burst of about ten messages, then
-- about one a second, and newer clients DROP what goes over. So we keep to
-- it: what can't go now waits its turn, in order.
---------------------------------------------------------------------------
Net.BURST, Net.PER_SECOND = 10, 1
local buckets, queue, draining = {}, {}, {}
local R = Enum and Enum.SendAddonMessageResult
local THROTTLED = { [R and R.AddonMessageThrottle or 3] = true, [R and R.ChannelThrottle or 8] = true }

local function Clock() return GetTime and GetTime() or ns.Now() end

local function Token(prefix)
    local now = Clock()
    local b = buckets[prefix]
    if not b then
        b = { tokens = Net.BURST, t = now }
        buckets[prefix] = b
    end
    b.tokens = math.min(Net.BURST, b.tokens + (now - b.t) * Net.PER_SECOND)
    b.t = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

local function Drain(prefix)
    local q = queue[prefix]
    while q[1] and Token(prefix) do
        local m = q[1]
        -- A channel's number can change after a reload: look it up when sending.
        -- (GUILD has no target; a channel's is looked up now, a whisper's is the name.)
        local target, r = m.target, nil
        if m.chatType == "CHANNEL" then target = ChannelId(Net.CHANNEL) end
        if target or m.chatType == "GUILD" then
            r = SendAddon(prefix, m.msg, m.chatType, target)
            Count("out", #m.msg)
        end
        if ns.debug then
            ns.Print("debug: send " .. m.msg:match("^[^:]*:[^:]*:[^@]*") .. " on " .. m.chatType .. " -> " .. tostring(r))
        end
        if THROTTLED[r] then
            buckets[prefix].tokens = 0
            break
        end
        table.remove(q, 1)
    end
    if q[1] and not draining[prefix] then
        draining[prefix] = true
        ns.After(0.25, function()
            draining[prefix] = nil
            Drain(prefix)
        end)
    end
end

function Net.Waiting()
    local n = 0
    for _, q in pairs(queue) do n = n + #q end
    return n
end

---------------------------------------------------------------------------
-- Sending and receiving
---------------------------------------------------------------------------
local function SendParts(cmd, data, chatType, target)
    if #data > Net.MAX_BYTES then
        Net.dropped = Net.dropped + 1
        return false
    end
    data = data or ""
    nextId = (nextId % 999) + 1
    local me = (ns.Me() or "") .. "#" .. Net.PROTO
    local chunk = MAX - (#cmd + 12 + #me)
    local n = math.max(1, math.ceil(#data / chunk))
    local used = {}
    for i = 1, n do
        local part = data:sub((i - 1) * chunk + 1, i * chunk)
        spreadNext = spreadNext % #Net.SPREAD + 1
        local p = Net.SPREAD[spreadNext]
        queue[p] = queue[p] or {}
        table.insert(queue[p], { msg = cmd .. ":" .. nextId .. ":" .. i .. "/" .. n .. "@" .. me .. ":" .. part,
            chatType = chatType, target = target })
        used[p] = true
    end
    for p in pairs(used) do Drain(p) end
    return true
end

-- To everyone on the realm channel (scope "realm", the default) or in your
-- guild (scope "guild").
function Net.Send(cmd, data, scope)
    if not (SendAddon and ns.db and ns.db.network) then return false end
    if scope == "guild" then
        if not (IsInGuild and IsInGuild()) then return false end
        return SendParts(cmd, data, "GUILD")
    end
    if not Net.Online() then return false end
    return SendParts(cmd, data, "CHANNEL")
end

-- To one player only.
function Net.Whisper(cmd, data, target)
    if not (SendAddon and ns.db and ns.db.network) then return false end
    return SendParts(cmd, data, "WHISPER", Net.Full(target))
end

-- Is WoW's sender string me ("Name", "Name-Realm", "Name Realm")?
function Net.IsMe(sender)
    if not sender then return false end
    local name = UnitName("player")
    local s = Squash(sender)
    return s == Squash(name) or s == Squash(name .. ns.Realm())
        or s == Squash(name .. (GetRealmName and GetRealmName() or ""))
end

-- chatType: how it came ("CHANNEL", "GUILD", "WHISPER"); handlers get it.
function Net.Receive(raw, message, chatType)
    if Net.IsMe(raw) then return end
    local cmd, id, i, n, said, data = message:match("^(%w+):(%d+):(%d+)/(%d+)@([^:]*):(.*)$")
    if not cmd then return end
    -- The protocol number after the name.
    local proto
    said, proto = said:match("^(.-)#(%d+)$")
    proto = tonumber(proto)
    if not proto then
        Net.dropped = Net.dropped + 1
        return
    end
    if proto ~= Net.PROTO then
        if proto > Net.PROTO and not Net.toldNewer then
            Net.toldNewer = true
            ns.Print("Someone is using a newer Wowstagram. Update yours to see their pictures.")
        end
        Net.dropped = Net.dropped + 1
        return
    end
    local sender = From(raw, said)
    if ns.debug then ns.Print("debug: got " .. cmd .. " " .. i .. "/" .. n .. " from " .. sender) end
    if sender == ns.Me() then return end
    Count("in", #message)
    address[sender] = raw
    peers[sender] = Clock0()
    i, n = tonumber(i), tonumber(n)
    if n > Net.MAX_PARTS or i < 1 or i > n then
        Net.dropped = Net.dropped + 1
        return
    end
    if n > 1 then
        local now = Clock0()
        -- Forget parts that never completed.
        if now - (Net.lastSweep or 0) > 10 then
            Net.lastSweep = now
            for k, p in pairs(partial) do
                if now - p.t > Net.PART_TIMEOUT then partial[k] = nil end
            end
        end
        Net.Sweep(now)
        local key = raw .. ":" .. id
        local p = partial[key]
        if not p or p.n ~= n then
            local open = 0
            for _, q in pairs(partial) do if q.raw == raw then open = open + 1 end end
            if open >= Net.MAX_OPEN then
                Net.dropped = Net.dropped + 1
                return
            end
            p = { n = n, got = 0, parts = {}, t = now, raw = raw }
            partial[key] = p
        end
        if not p.parts[i] then
            p.parts[i] = data
            p.got = p.got + 1
        end
        if p.got < n then return end
        partial[key] = nil
        data = table.concat(p.parts)
    end
    if #data > Net.MAX_BYTES then
        Net.dropped = Net.dropped + 1
        return
    end
    -- Someone caught faking (UI: Social's strikes): not listened to.
    if Net.Ignored and Net.Ignored(sender) then
        Net.dropped = Net.dropped + 1
        return
    end
    if Net.Heard then Net.Heard(sender) end
    local fn = handlers[cmd]
    if fn then fn(sender, data, chatType) end
end

ns.On("CHAT_MSG_ADDON", function(prefix, message, chatType, sender)
    if OURS[prefix] then Net.Receive(sender, message, chatType) end
end)
