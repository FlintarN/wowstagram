-- Social: posts, likes, comments, follows and profiles, and keeping them in
-- step with everyone on the realm and in your guild. Everything goes out on
-- both (a guildmate gets it even when the realm channel doesn't work for
-- them); doubles are ignored on arrival. Grown from HearthPhone's Social app:
-- everything is broadcast on one hidden channel, every client keeps its own
-- copy, and a newcomer says hello and gets the latest posts back.
--
--   post = {
--     id, author, class, race, t, edited, caption,
--     look = "<Look string>",
--     likes = { [name] = t },    -- t > 0: liked at t; t < 0: un-liked at -t
--     dislikes = { [code] = t }, -- the same, by anonymous codes
--     comments = { { author, class, t, edited, text }, ... },
--     share = "guild",           -- shared with the guild only
--     unv = true, unvFrom = name,-- passed on by someone else, not yet checked
--     bot = true,                -- a demo person's post: never sent anywhere
--   }
--
-- Only the owner can change things: a post is edited or deleted only by its
-- author, a comment only by whoever wrote it, and a like is only ever your
-- own. Over the network that's checked against who sent the message (WoW
-- tells us). Pictures passed on by someone else are checked with their
-- author when they're around (vouching); a sender caught passing on fakes
-- gets strikes, and too many shut them out.
local _, ns = ...

local Net = ns.Net
local S = {}
ns.Social = S

local US = "\031" -- field separator: can't be typed, so it never shows up in text
-- (Saved data: a picture with its likes and comments is usually under 1 KB,
-- so the budgets below come to a few MB at most.)
S.MAX_POSTS = 1000     -- other people's pictures (not yours, saved, or followed people's)
S.MAX_FOLLOWED = 1000  -- pictures by people you follow and friends
S.MAX_PER_AUTHOR = 30
S.MAX_RELAYED_LIKES = 50 -- liker names taken from one passed-on picture
S.MAX_CHECKS = 500       -- things waiting to be checked with their owners
S.MAX_SOFT = 1000        -- provisional deletions kept
S.MAX_CAPTION = 200
S.MAX_COMMENT = 200
S.MAX_BIO = 140
S.SYNC_POSTS = 15        -- posts sent back to someone who says hello
S.SYNC_WINDOW = 2 * 86400 -- ...from up to this long before their newest one
local TOMB_DAYS = 14
S.UNSAVE_GRACE = 7 * 86400 -- an unsaved picture is still kept this long
S.MAX_TOMBS = 500        -- deleted posts and comments remembered
S.MAX_PROFILES = 1000
S.MAX_LOOK = 1600        -- a picture string longer than this is dropped
S.SYNC_COMMENTS = 20     -- comments sent along with each post in a sync
-- Per sender, per minute (Net.Allow): more than this is dropped.
S.RATE = { post = 6, relay = 60, comment = 20, like = 40, delete = 30, profile = 6, hello = 4, ask = 6, vouch = 6 }
-- Sync: about this many people answer each hello, however many are online.
S.ANSWERERS = 3

local postHeard = {} -- post id -> GetTime() it was last sent or received (sync skips what others just sent)

local function Clock() return GetTime and GetTime() or ns.Now() end

-- Text from anyone: no message separators, line breaks or "|" (WoW's
-- colour, texture and link codes), at most max bytes (never half a letter).
local function Clean(text, max)
    text = tostring(text or ""):gsub("[\029\030\031]", " "):gsub("[\r\n]+", " "):gsub("|", "")
    text = strtrim(text)
    if #text > max then
        text = text:sub(1, max)
        while #text > 0 and text:byte(#text) >= 128 and text:byte(#text) < 192 do text = text:sub(1, -2) end
        if #text > 0 and text:byte(#text) >= 192 then text = text:sub(1, -2) end
    end
    return text
end

-- The first n fields of a message. Fields a newer version added after them
-- are ignored (see Net.PROTO).
local function Split(data, n)
    local out = {}
    local start = 1
    for i = 1, n do
        local stop = data:find(US, start, true)
        if not stop then
            out[i] = data:sub(start)
            return out
        end
        out[i] = data:sub(start, stop - 1)
        start = stop + 1
    end
    return out
end

local function NewId()
    return ns.Look.B36(ns.Now()) .. ns.Look.B36(math.random(46655))
end

local function MyClass()
    local _, class = UnitClass("player")
    return class
end

local function MyRace()
    local _, _, raceId = UnitRace("player")
    return raceId
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- A picture id from the network: letters and digits, not too long.
function S.ValidId(id)
    return type(id) == "string" and #id >= 1 and #id <= 24 and id:match("^%w+$") ~= nil
end

function S.Find(id)
    for i, p in ipairs(ns.db.posts) do
        if p.id == id then return p, i end
    end
end

---------------------------------------------------------------------------
function S.HasTag(post, tag)
    for _, t in ipairs(S.Tags(post.caption)) do
        if t == tag then return true end
    end
    return false
end

-- People you know: friends (the friend list, and Battle.net friends'
-- characters), and people you've seen lately (Blizzard's "recently met",
-- done here so it works everywhere: nameplates, target, mouseover, group,
-- chat nearby). They come first in the Realm feed.
---------------------------------------------------------------------------
local friends = {}
function S.RefreshFriends()
    wipe(friends)
    local FL = C_FriendList
    if FL and FL.GetNumFriends then
        for i = 1, FL.GetNumFriends() or 0 do
            local info = FL.GetFriendInfoByIndex and FL.GetFriendInfoByIndex(i)
            local name = info and info.name
            if name then
                local short, realm = name:match("^(.+)%-([^%-]+)$")
                friends[ns.Id(short or name, realm)] = true
                friends[name] = true
            end
        end
    end
    local BN = C_BattleNet
    if BN and BN.GetFriendNumGameAccounts and BNGetNumFriends then
        for i = 1, (BNGetNumFriends()) or 0 do
            for j = 1, BN.GetFriendNumGameAccounts(i) or 0 do
                local g = BN.GetFriendGameAccountInfo(i, j)
                if g and g.characterName and g.characterName ~= "" and (g.clientProgram == nil or g.clientProgram == "WoW") then
                    friends[ns.Id(g.characterName, g.realmName)] = true
                end
            end
        end
    end
end

function S.IsFriend(id)
    return id ~= nil and friends[id] == true
end

S.MAX_MET = 500
local metWait = {}
function S.Meet(id)
    if not id or id == ns.Me() then return end
    local now = ns.Now()
    if (metWait[id] or 0) > now - 60 then return end
    metWait[id] = now
    ns.db.met[id] = now
    -- Too many: forget the longest ago.
    local n = 0
    for _ in pairs(ns.db.met) do n = n + 1 end
    if n > S.MAX_MET + 50 then
        local list = {}
        for k, t in pairs(ns.db.met) do list[#list + 1] = { k, t } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = S.MAX_MET + 1, #list do ns.db.met[list[i][1]] = nil end
    end
end

-- Seen in the last few days: how fresh (1 just now, 0 three days ago).
function S.MetLately(id)
    local t = id and ns.db.met[id]
    if not t then return 0 end
    return math.max(0, 1 - (ns.Now() - t) / (3 * 86400))
end

-- The game's own list of people you've played with (Recent Allies), where
-- the client has it: everyone on it counts as seen, when it says.
function S.ReadRecentlyMet()
    local RA = C_RecentAllies
    if not (RA and RA.GetRecentAllies) then return 0 end
    local ok, list = pcall(RA.GetRecentAllies)
    if not ok or type(list) ~= "table" then return 0 end
    local n = 0
    for _, a in ipairs(list) do
        local cd = type(a) == "table" and (a.characterData or a) or {}
        local name, realm = cd.name or cd.characterName, cd.realmName
        if type(cd.fullName) == "string" and not name then name = cd.fullName end
        if type(name) == "string" and name ~= "" then
            local short, r = name:match("^(.+)%-([^%-]+)$")
            local id = ns.FOREVER and name or ns.Id(short or name, realm or r)
            local when = a.interactionData and tonumber(a.interactionData.lastInteractionTime)
            when = when and when > 1e9 and math.min(when, ns.Now()) or ns.Now() - 3600
            if id and id ~= ns.Me() and (not ns.db.met[id] or ns.db.met[id] < when) then ns.db.met[id] = when end
            n = n + 1
        end
    end
    return n
end

local function MeetUnit(unit)
    if UnitExists and UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit) then S.Meet(ns.UnitId(unit)) end
end

-- How much you care, probably: friends most, then who you follow, your
-- guild, and people you've seen lately.
function S.Closeness(id)
    if id == ns.Me() then return 1 end -- (your own: by how new, like anyone's)
    local k = 1
    if S.IsFriend(id) then k = math.max(k, 4) end
    if S.Following(id) then k = math.max(k, 3) end
    if S.InGuild(id) then k = math.max(k, 2) end
    local met = S.MetLately(id)
    if met > 0 then k = math.max(k, 1 + 0.8 * met) end
    return k
end

-- The Realm feed, ranked: close people first, newer first, liked a bit
-- higher. A stranger's picture more than three days old drops out (it's
-- still on their profile) unless the feed would be nearly empty.
S.STRANGER_DAYS = 3
function S.Feed()
    local now = ns.Now()
    local list = S.List("all")
    local scored = {}
    for _, p in ipairs(list) do
        local close = S.Closeness(p.author)
        local ageH = math.max(0, (now - (p.t or now)) / 3600)
        if close > 1 or ageH < S.STRANGER_DAYS * 24 or #list < 10 then
            local score = close / (1 + ageH / 18) * (1 + 0.15 * math.log(1 + S.Likes(p)))
            scored[#scored + 1] = { p = p, s = score }
        end
    end
    table.sort(scored, function(a, b)
        if a.s ~= b.s then return a.s > b.s end
        return (a.p.t or 0) > (b.p.t or 0)
    end)
    local out = {}
    for i, e in ipairs(scored) do out[i] = e.p end
    return out
end

---------------------------------------------------------------------------
-- Hashtags and mentions in captions and comments.
---------------------------------------------------------------------------
-- The #tags in a text, lower case, each once.
function S.Tags(text)
    local out, seen = {}, {}
    for tag in tostring(text or ""):gmatch("#([%w_\128-\255]+)") do
        tag = tag:lower()
        if not seen[tag] then seen[tag] = true; out[#out + 1] = tag end
    end
    return out
end

-- The @mentions in a text: { at = what was written, id }. On Forever names
-- are two words ("@First Last"); on Retail "@Name" or "@Name-Realm".
local NAMECH = "[%a\128-\255']"
function S.Mentions(text)
    local out = {}
    text = tostring(text or "")
    if ns.FOREVER then
        for first, last in text:gmatch("@(%u" .. NAMECH .. "+) (%u" .. NAMECH .. "+)") do
            out[#out + 1] = { at = "@" .. first .. " " .. last, id = first .. " " .. last }
        end
    else
        for name, realm in text:gmatch("@(" .. NAMECH .. "+)%-?(" .. NAMECH .. "*)") do
            out[#out + 1] = { at = "@" .. name .. (realm ~= "" and ("-" .. realm) or ""), id = ns.Id(name, realm ~= "" and realm or nil) }
        end
    end
    return out
end

function S.MentionsMe(text)
    for _, m in ipairs(S.Mentions(text)) do
        if m.id == ns.Me() then return true end
    end
    return false
end

-- Every hashtag in the pictures you have, most used first: { tag, n }.
function S.AllTags()
    local count = {}
    for _, p in ipairs(ns.db.posts) do
        if not S.Blocked(p.author) then
            for _, tag in ipairs(S.Tags(p.caption)) do count[tag] = (count[tag] or 0) + 1 end
        end
    end
    local out = {}
    for tag, n in pairs(count) do out[#out + 1] = { tag = tag, n = n } end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.tag < b.tag end)
    return out
end

-- People known to have Wowstagram: their addon sent you something, or
-- their picture, comment or like reached you (or you follow them).
S.MAX_USERS = 3000
local heardWait = {}
function S.Heard(id)
    if not id or id == ns.Me() then return end
    local now = ns.Now()
    if (heardWait[id] or 0) > now - 300 then return end
    heardWait[id] = now
    ns.db.users[id] = now
    -- Too many: forget those postHeard from longest ago.
    local n = 0
    for _ in pairs(ns.db.users) do n = n + 1 end
    if n > S.MAX_USERS + 100 then
        local list = {}
        for k, t in pairs(ns.db.users) do list[#list + 1] = { k, t } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = S.MAX_USERS + 1, #list do ns.db.users[list[i][1]] = nil end
    end
end
Net.Heard = S.Heard

-- Everyone you might look for (Search): only people known to have the
-- addon. Friends and people you've seen decide the order, not who's in.
function S.People()
    local set = {}
    for _, p in ipairs(ns.db.posts) do
        if not p.bot or ns.db.demo then set[p.author] = true end
        for _, c in ipairs(p.comments or {}) do set[c.author] = true end
        for name, t in pairs(p.likes or {}) do if t > 0 then set[name] = true end end
    end
    for name in pairs(ns.db.profiles) do set[name] = true end
    for name in pairs(ns.my.following) do set[name] = true end
    for name in pairs(ns.db.users) do set[name] = true end
    set[ns.Me()] = nil
    local out = {}
    for name in pairs(set) do if not S.Blocked(name) then out[#out + 1] = name end end
    return out
end

-- Blocked: you don't see their pictures, comments, likes or dislikes, and
-- they don't show up anywhere. Only on this computer; they aren't told.
function S.Blocked(name)
    return name ~= nil and ns.db.blocked[name] ~= nil
end

function S.Block(name, on)
    if not name or name == ns.Me() then return end
    ns.db.blocked[name] = on and ns.Now() or nil
    if not on then ns.db.strikes[name] = nil end
    ns.Changed()
end

function S.BlockedList()
    local out = {}
    for name, t in pairs(ns.db.blocked) do out[#out + 1] = { name = name, t = t } end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

-- The comments you see (not blocked people's).
function S.Comments(post)
    local out = {}
    for _, c in ipairs(post.comments or {}) do
        if not S.Blocked(c.author) then out[#out + 1] = c end
    end
    return out
end

function S.IsMine(post)
    return post and post.author == ns.Me()
end

-- filter: "all", "guild", "following", or a name (that person's posts).
function S.List(filter)
    local out = {}
    local follow = ns.my.following
    for _, p in ipairs(ns.db.posts) do
        if S.Blocked(p.author) then
            -- (hidden)
        elseif ((filter == "all" or filter == nil) and p.share ~= "guild")
            or (filter == "following" and (follow[p.author] or p.author == ns.Me()))
            or (filter == "guild" and S.InGuild(p.author))
            or (filter == "saved" and S.Saved(p.id))
            or (type(filter) == "string" and filter:sub(1, 1) == "#" and S.HasTag(p, filter:sub(2)))
            or p.author == filter then
            table.insert(out, p)
        end
    end
    return out
end

function S.Likes(post)
    local n = 0
    for name, t in pairs(post.likes or {}) do
        if t > 0 and not S.Blocked(name) then n = n + 1 end
    end
    return n
end

-- Dislikes are anonymous: never shown, never told, and not even sent by
-- name. Each is kept under a one-way code of the name (S.Anon), enough to
-- count a person once and let them take it back, but nobody can read who.
-- A like and a dislike from the same person don't go together.
local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

function S.Anon(name)
    local a, b = Hash("wgd1#" .. tostring(name)), Hash(tostring(name) .. "#wgd2")
    local L = ns.Look
    return "d" .. L.B36(a) .. L.B36(b)
end

function S.Dislikes(post)
    local hidden = {}
    for name in pairs(ns.db.blocked) do hidden[S.Anon(name)] = true end
    local n = 0
    for key, t in pairs(post.dislikes or {}) do
        if t > 0 and not hidden[key] then n = n + 1 end
    end
    return n
end

function S.Disliked(post, name)
    local t = post.dislikes and post.dislikes[S.Anon(name or ns.Me())]
    return t ~= nil and t > 0
end

function S.Liked(post, name)
    local t = post.likes and post.likes[name or ns.Me()]
    return t ~= nil and t > 0
end

-- Who liked it, newest first.
function S.Likers(post)
    local list = {}
    for name, t in pairs(post.likes or {}) do
        if t > 0 and not S.Blocked(name) then table.insert(list, { name = name, t = t }) end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

function S.Profile(name)
    if name == ns.Me() then
        local p = S.MyProfile()
        p.bio = ns.my.me.bio
        return p
    end
    return ns.db.profiles[name] or {}
end

function S.MyProfile()
    local _, class = UnitClass("player")
    return {
        class = class, race = MyRace(), raceName = UnitRace("player"), level = UnitLevel and UnitLevel("player") or 0,
        guild = GetGuildInfo and GetGuildInfo("player") or "", bio = ns.my.me.bio or "", t = ns.my.me.t or 0,
    }
end

---------------------------------------------------------------------------
-- Your guild: everyone on the guild roster, by id.
---------------------------------------------------------------------------
local guild = {}

function S.RefreshGuild()
    wipe(guild)
    if not (IsInGuild and IsInGuild()) then return end
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            -- Retail writes roster names "Name-Realm". Forever has no realms, so
            -- the name is whole; if a suffix ever shows up, the part before the
            -- last dash counts too.
            guild[name] = true
            local short, realm = name:match("^(.+)%-([^%-]+)$")
            if short then guild[ns.Id(short, realm)] = true end
            guild[ns.Id(name)] = true
        end
    end
end

function S.InGuild(id)
    if not id then return false end
    if ns.Bots and ns.Bots.InGuild(id) then return true end
    if not (IsInGuild and IsInGuild()) then return false end
    return id == ns.Me() or guild[id] == true
end

-- Can the Guild feed show anything: in a guild, or demo guildmates.
function S.HasGuild()
    return (IsInGuild and IsInGuild()) or (ns.db.demo == true)
end

local function AskRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end

function S.Following(name)
    return ns.my.following[name] ~= nil
end

-- Saved (the bookmark): only on this computer, nobody sees what you save.
function S.Saved(id)
    return ns.db.saved[id] ~= nil
end

function S.Save(id, on)
    ns.db.saved[id] = on and ns.Now() or nil
    ns.db.unsaved[id] = (not on) and ns.Now() or nil
    ns.Changed()
end

-- Stories: everyone who posted in the last day, newest first, with their
-- newest post and whether you've seen all of today's.
function S.Stories()
    local since = ns.Now() - 86400
    local out, at = {}, {}
    for _, p in ipairs(ns.db.posts) do
        if p.t >= since and p.author ~= ns.Me() then
            local s = at[p.author]
            if not s then
                s = { author = p.author, class = p.class, post = p, seen = true }
                at[p.author] = s
                table.insert(out, s)
            end
            if not ns.db.seen[p.id] then s.seen = false end
        end
    end
    -- Unseen first, then the rest; each group newest first.
    table.sort(out, function(a, b)
        if a.seen ~= b.seen then return not a.seen end
        return a.post.t > b.post.t
    end)
    return out
end

function S.Seen(id)
    if id and not ns.db.seen[id] then ns.db.seen[id] = true end
end

-- People to follow: authors you don't follow yet, guildmates first, then by
-- how many likes their pictures have.
function S.Suggested(max)
    local score, class = {}, {}
    for _, p in ipairs(ns.db.posts) do
        local a = p.author
        if a ~= ns.Me() and not S.Following(a) then
            score[a] = (score[a] or 0) + 1 + S.Likes(p) + (S.InGuild(a) and 1000 or 0)
            class[a] = class[a] or p.class
        end
    end
    local list = {}
    for name, s in pairs(score) do table.insert(list, { name = name, score = s, class = class[name] }) end
    table.sort(list, function(a, b) return a.score > b.score end)
    while #list > (max or 5) do table.remove(list) end
    return list
end

-- People who follow `name`, as far as we can tell: only you, and demo people.
function S.Followers(name)
    local n = 0
    if name ~= ns.Me() and S.Following(name) then n = n + 1 end
    if ns.Bots then n = n + ns.Bots.Followers(name) end
    return n
end

---------------------------------------------------------------------------
-- Storing (local and remote both come through here)
---------------------------------------------------------------------------
-- Kept whatever the limits say: your own pictures, the ones you saved, and
-- ones you unsaved less than a week ago (in case it was a slip).
local function Keep(p, now)
    if p.author == ns.Me() or ns.db.saved[p.id] then return true end
    local off = ns.db.unsaved[p.id]
    return off ~= nil and now - off < S.UNSAVE_GRACE
end

-- Other people's pictures beyond the limits go, oldest first. That's what
-- keeps years of pictures from piling up: at most S.MAX_POSTS of theirs,
-- S.MAX_PER_AUTHOR each.
local function Prune()
    local db = ns.db
    local now = ns.Now()
    for id, t in pairs(db.unsaved) do
        if now - t >= S.UNSAVE_GRACE then db.unsaved[id] = nil end
    end
    local per = {}
    local i = 1
    while i <= #db.posts do
        local p = db.posts[i]
        per[p.author] = (per[p.author] or 0) + 1
        if per[p.author] > S.MAX_PER_AUTHOR and not Keep(p, now) then table.remove(db.posts, i) else i = i + 1 end
    end
    -- Two budgets, kept pictures (yours, saved) counted in neither: people
    -- you follow and friends (S.MAX_FOLLOWED, the oldest go first), and
    -- everyone else (S.MAX_POSTS, the least interesting go first: strangers
    -- before guildmates and people you've seen, older before newer).
    local close, rest = {}, {}
    for _, p in ipairs(db.posts) do
        if not Keep(p, now) then
            if S.Following(p.author) or S.IsFriend(p.author) then close[#close + 1] = p else rest[#rest + 1] = p end
        end
    end
    local drop = {}
    if #close > S.MAX_FOLLOWED then
        table.sort(close, function(a, b) return (a.t or 0) > (b.t or 0) end)
        for k = S.MAX_FOLLOWED + 1, #close do drop[close[k]] = true end
    end
    if #rest > S.MAX_POSTS then
        local function Score(p)
            return S.Closeness(p.author) / (1 + math.max(0, now - (p.t or now)) / 3600 / 18)
        end
        for _, p in ipairs(rest) do p.pruneScore = Score(p) end
        table.sort(rest, function(a, b) return a.pruneScore > b.pruneScore end)
        for k = S.MAX_POSTS + 1, #rest do drop[rest[k]] = true end
        for _, p in ipairs(rest) do p.pruneScore = nil end
    end
    if next(drop) then
        for j = #db.posts, 1, -1 do
            if drop[db.posts[j]] then table.remove(db.posts, j) end
        end
    end
    local have = {}
    for _, p in ipairs(db.posts) do have[p.id] = true end
    for id in pairs(db.seen or {}) do
        if not have[id] then db.seen[id] = nil end
    end
    for name, s in pairs(db.strikes or {}) do
        if not s.out and now - (s.t or 0) > 7 * 86400 then db.strikes[name] = nil end
    end
    S.PruneSoft()
    local cutoff = ns.Now() - TOMB_DAYS * 86400
    local tombs = {}
    for k, t in pairs(db.tombs) do
        if t < cutoff then db.tombs[k] = nil else tombs[#tombs + 1] = { k, t } end
    end
    -- Too many: forget the oldest.
    if #tombs > S.MAX_TOMBS then
        table.sort(tombs, function(a, b) return a[2] > b[2] end)
        for i = S.MAX_TOMBS + 1, #tombs do db.tombs[tombs[i][1]] = nil end
    end
end

-- Profiles of people you haven't postHeard from in the longest time go first.
local function PruneProfiles()
    local list = {}
    for name, p in pairs(ns.db.profiles) do list[#list + 1] = { name, p.seen or 0 } end
    if #list <= S.MAX_PROFILES then return end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = S.MAX_PROFILES + 1, #list do ns.db.profiles[list[i][1]] = nil end
end

-- Newest first.
local function Insert(post)
    local posts = ns.db.posts
    for i, p in ipairs(posts) do
        if post.t > p.t then
            table.insert(posts, i, post)
            return
        end
    end
    table.insert(posts, post)
end

local function MergeLikes(post, likes, field)
    field = field or "likes"
    local changed = false
    post[field] = post[field] or {}
    local into = post[field]
    for name, t in pairs(likes or {}) do
        local old = into[name]
        if not old or math.abs(t) > math.abs(old) then
            into[name] = t
            changed = true
        end
    end
    return changed
end

-- Returns the post when it was new or changed. sender: who sent it over the
-- network (nil: made here); only the author may change a post we have.
function S.Store(p, sender)
    if ns.db.tombs["p:" .. p.id] then return nil end
    if p.t > ns.Now() + 300 then return nil end -- from the future: a broken clock or a fake
    local old = S.Find(p.id)
    if old then
        local changed = MergeLikes(old, p.likes)
        if MergeLikes(old, p.dislikes, "dislikes") then changed = true end
        if (p.edited or 0) > (old.edited or 0) and (sender == nil or sender == old.author) then
            old.caption, old.look, old.edited = p.caption, p.look, p.edited
            changed = true
        end
        return changed and old or nil
    end
    p.likes = p.likes or {}
    p.dislikes = p.dislikes or {}
    p.comments = p.comments or {}
    Insert(p)
    Prune()
    return p
end

function S.StoreComment(postId, c, sender)
    local post = S.Find(postId)
    if not post then return nil end
    if (c.t or 0) > ns.Now() + 300 then return nil end -- from the future: a broken clock or a fake
    if ns.db.tombs["c:" .. postId .. ":" .. c.author .. ":" .. c.t] then return nil end
    for _, old in ipairs(post.comments) do
        if old.author == c.author and old.t == c.t then
            if (c.edited or 0) > (old.edited or 0) and (sender == nil or sender == old.author) then
                old.text, old.edited = c.text, c.edited
                return post
            end
            return nil
        end
    end
    table.insert(post.comments, c)
    table.sort(post.comments, function(a, b) return a.t < b.t end)
    return post
end

-- Someone liked or commented on your picture: a line in Notifications (and
-- in chat, if you want).
S.MAX_ACTIVITY = 100
local function Activity(kind, who, post, text)
    if who == ns.Me() or S.Blocked(who) then return end
    if kind ~= "mention" and not S.IsMine(post) then return end
    local log = ns.my.activity
    table.insert(log, 1, { t = ns.Now(), kind = kind, who = who, id = post.id, text = text })
    while #log > S.MAX_ACTIVITY do table.remove(log) end
    if ns.db.notify then
        local what = kind == "like" and "liked your picture." or kind == "mention" and ("mentioned you: " .. text)
            or ("commented: " .. text)
        ns.Print(ns.ColorName(who, (S.Profile(who) or {}).class) .. " " .. ns.Plain(what))
    end
    if ns.UI and ns.UI.Ping then ns.UI:Ping() end
end

---------------------------------------------------------------------------
-- Wire
---------------------------------------------------------------------------
local function LikesString(post, field)
    local out = {}
    local unv = (field or "likes") == "likes" and post.likeUnv or {}
    for name, t in pairs(post[field or "likes"] or {}) do
        if not unv[name] then table.insert(out, name .. "=" .. t) end
    end
    return table.concat(out, ",")
end

-- A guild-only picture, and everything about it (likes, comments, edits,
-- deletion), only ever goes to the guild.
local function ScopeOf(post)
    return post and post.share == "guild" and "guild" or nil
end
S.ScopeOf = ScopeOf

-- scope: "realm" or "guild"; nil sends on both.
local function Send(cmd, data, scope)
    if scope then return Net.Send(cmd, data, scope) end
    Net.Send(cmd, data, "realm")
    Net.Send(cmd, data, "guild")
end

-- withComments: the post's latest comments go inside the same message (a
-- sync), "author\030class\030t\030edited\030text" joined by \029.
local function CommentsString(post)
    local out = {}
    local list = post.comments or {}
    for i = math.max(1, #list - S.SYNC_COMMENTS + 1), #list do
        local c = list[i]
        if not c.bot and not c.unv then
            out[#out + 1] = table.concat({ c.author, c.class or "", c.t, c.edited or 0, c.text }, "\030")
        end
    end
    return table.concat(out, "\029")
end

local function Remember(id)
    postHeard[id] = Clock()
    postHeard.n = (postHeard.n or 0) + 1
    if postHeard.n > 2000 then
        local cut = Clock() - 600
        for k, t in pairs(postHeard) do
            if k ~= "n" and t < cut then postHeard[k] = nil end
        end
        postHeard.n = 0
    end
end

local function PostData(post, withComments)
    local function Build(comments, likes, dislikes)
        return table.concat({ post.id, post.author, post.class or "", post.race or "", post.t, post.edited or 0,
            post.look or "", post.caption or "", likes, comments, post.share == "guild" and "g" or "", dislikes }, US)
    end
    local comments = withComments and CommentsString(post) or ""
    local likes, dislikes = LikesString(post), LikesString(post, "dislikes")
    local data = Build(comments, likes, dislikes)
    -- Too big for one message (Net.MAX_BYTES): fewer comments, then the
    -- likes and dislikes are left to their own messages.
    local limit = Net.MAX_BYTES - 100
    while #data > limit and comments ~= "" do
        comments = comments:match("^[^\029]*\029(.*)$") or ""
        data = Build(comments, likes, dislikes)
    end
    if #data > limit then data = Build("", "", "") end
    return data
end

local function SendPost(post, scope, withComments)
    if post.bot then return end
    if post.share == "guild" and scope and scope ~= "guild" then return end
    scope = scope or ScopeOf(post)
    Remember(post.id)
    Send("P", PostData(post, withComments), scope)
end

local function SendComment(post, c, scope)
    if post.bot or c.bot then return end
    if post.share == "guild" and scope and scope ~= "guild" then return end
    scope = scope or ScopeOf(post)
    Send("C", table.concat({ post.id, c.author, c.class or "", c.t, c.edited or 0, c.text }, US), scope)
end

local function SendProfile(scope)
    local p = S.MyProfile()
    Send("R", table.concat({ p.class or "", p.race or "", p.level or 0, p.guild or "", p.bio or "", p.t or 0 }, US), scope)
end

local relayHeard = {} -- scope -> when someone last passed on others' posts (answered a hello)

Net.On("P", function(sender, data, chatType)
    local f = Split(data, 12)
    local id, author, t = f[1], f[2], tonumber(f[5])
    if not (id and id ~= "" and author and author ~= "" and t) then return end
    if not S.ValidId(id) or not ns.ValidName(author) then return end
    -- A guild-only picture is only taken from the guild channel.
    local share = f[11] == "g" and "guild" or nil
    if share and chatType ~= "GUILD" then return end
    local relay = author ~= sender
    if not Net.Allow(sender, relay and "relay" or "post", relay and S.RATE.relay or S.RATE.post) then return end
    if #(f[7] or "") > S.MAX_LOOK then return end
    -- A picture "by you" that you never posted: not taken.
    if relay and author == ns.Me() and not S.Find(id) and S.Vouchable(t) then
        return S.Strike(sender, 3, "a made-up picture in your name")
    end
    local existed = S.Find(id) ~= nil
    Remember(id)
    if relay then relayHeard[chatType == "GUILD" and "guild" or "realm"] = Clock() end
    local likes = {}
    local taken = 0
    for name, lt in (f[9] or ""):gmatch("([^,=]+)=(%-?%d+)") do
        -- (a like "by you" only stands if it's yours; at most so many names
        -- passed on per message, each checked with its liker)
        if ns.ValidName(name) and (name ~= ns.Me() or S.MyLikeIs(id, tonumber(lt))) then
            likes[name] = tonumber(lt)
            if name ~= sender then taken = taken + 1 end
            if taken >= S.MAX_RELAYED_LIKES then break end
        end
    end
    local oldLikes = {}
    local before = S.Find(id)
    for name in pairs(likes) do oldLikes[name] = before and before.likes and before.likes[name] end
    -- Dislikes can't be checked (they're anonymous): only the picture's own
    -- author passes them on (they got each one from the disliker).
    local dislikes = {}
    if author == sender then
        for code, lt in (f[12] or ""):gmatch("([^,=]+)=(%-?%d+)") do
            if code:match("^d%w+$") and #code <= 40 then dislikes[code] = tonumber(lt) end
        end
    end
    local post = S.Store({
        id = id, author = author, class = ns.ValidClass(f[3]), race = ns.Look.Race(f[4]), t = t,
        edited = tonumber(f[6]) or 0, look = f[7] or "", caption = Clean(f[8], S.MAX_CAPTION), likes = likes,
        dislikes = dislikes, share = share,
    }, sender)
    local changed = post ~= nil
    local stored = S.Find(id)
    if stored then
        local soft = S.ResolveSoft("p:" .. id, author, sender)
        if soft and not stored.unv then
            -- (passed on, with a deletion pending: checked with the author)
            stored.unv, stored.unvFrom = true, sender
            S.Check(author, "p", stored, nil, sender)
        end
        -- From its author: confirmed. Passed on by someone else: checked
        -- with the author in the background (it shows meanwhile).
        if not relay then
            stored.unv, stored.unvFrom = nil, nil
        elseif not existed then
            stored.unv, stored.unvFrom = true, sender
            S.Check(author, "p", stored, nil, sender)
        end
        for name, lt in pairs(likes) do
            if stored.likes[name] == lt and oldLikes[name] ~= lt then
                stored.likeUnv = stored.likeUnv or {}
                if name == sender then stored.likeUnv[name] = nil else
                    stored.likeUnv[name] = sender
                    S.Check(name, "l", stored, lt, sender)
                end
            end
        end
    end
    if post and not existed and author == sender and (post.edited or 0) == 0 and S.MentionsMe(post.caption) then
        Activity("mention", author, post, post.caption)
    end
    -- Comments that came along (a sync).
    if f[10] and f[10] ~= "" and S.Find(id) then
        for entry in f[10]:gmatch("[^\029]+") do
            local a, cl, ct, ed, text = entry:match("^([^\030]*)\030([^\030]*)\030([^\030]*)\030([^\030]*)\030(.*)$")
            ct = tonumber(ct)
            if a and ns.ValidName(a) and ct then
                local c = { author = a, class = ns.ValidClass(cl), t = ct, edited = tonumber(ed) or 0,
                    text = Clean(text, S.MAX_COMMENT) }
                if S.TakeComment(id, c, sender) then changed = true end
            end
        end
    end
    if changed then ns.Changed() end
end)

Net.On("C", function(sender, data)
    local f = Split(data, 6)
    local t = tonumber(f[4])
    if not (f[1] and f[2] and f[2] ~= "" and t) then return end
    if not S.ValidId(f[1]) or not ns.ValidName(f[2]) then return end
    if not Net.Allow(sender, f[2] == sender and "comment" or "relay", f[2] == sender and S.RATE.comment or S.RATE.relay) then
        return
    end
    local c = { author = f[2], class = ns.ValidClass(f[3]), t = t, edited = tonumber(f[5]) or 0,
        text = Clean(f[6], S.MAX_COMMENT) }
    local post = S.TakeComment(f[1], c, sender)
    if post then
        if c.author == sender and (c.edited or 0) == 0 then
            if S.IsMine(post) then
                Activity("comment", sender, post, c.text)
            elseif S.MentionsMe(c.text) then
                Activity("mention", sender, post, c.text)
            end
        end
        ns.Changed()
    end
end)

Net.On("L", function(sender, data)
    local f = Split(data, 3)
    local post, t = S.Find(f[1] or ""), tonumber(f[3])
    if f[2] and f[2] ~= sender then return S.Strike(sender, 2, "a like in someone else's name") end
    if not (post and f[2] and t) then return end -- nobody likes in someone else's name
    if not Net.Allow(sender, "like", S.RATE.like) then return end
    local was = S.Liked(post, f[2])
    if post.likeUnv then post.likeUnv[f[2]] = nil end -- (from the liker: confirmed)
    if MergeLikes(post, { [f[2]] = t }) then
        if t > 0 and not was then Activity("like", sender, post) end
        ns.Changed()
    end
end)

Net.On("N", function(sender, data)
    local f = Split(data, 3)
    local post, t = S.Find(f[1] or ""), tonumber(f[3])
    -- (the code must be the sender's own: nobody dislikes in someone else's name)
    if f[2] and f[2] ~= S.Anon(sender) then return S.Strike(sender, 2, "a dislike in someone else's name") end
    if not (post and f[2] and t) then return end
    if not Net.Allow(sender, "like", S.RATE.like) then return end
    if MergeLikes(post, { [f[2]] = t }, "dislikes") then ns.Changed() end
end)

Net.On("D", function(sender, data)
    local f = Split(data, 2)
    local id, t = f[1], math.min(tonumber(f[2]) or ns.Now(), ns.Now())
    if not S.ValidId(id) then return end
    if not Net.Allow(sender, "delete", S.RATE.delete) then return end
    local post, i = S.Find(id)
    if post and post.author ~= sender then return end -- only its author deletes a post
    if post then
        ns.db.tombs["p:" .. id] = math.max(ns.db.tombs["p:" .. id] or 0, t)
        table.remove(ns.db.posts, i)
        ns.Changed()
    elseif not ns.db.tombs["p:" .. id] then
        -- A picture you don't have: whose it was can't be told, so the
        -- deletion is provisional (S.SoftTomb).
        S.SoftTomb("p:" .. id, t, sender)
    end
end)

Net.On("X", function(sender, data)
    local f = Split(data, 4)
    local id, author, ct = f[1], f[2], tonumber(f[3])
    if not (id and author and ct) or not S.ValidId(id) or not ns.ValidName(author) then return end
    if not Net.Allow(sender, "delete", S.RATE.delete) then return end
    local post = S.Find(id)
    local key = "c:" .. id .. ":" .. author .. ":" .. ct
    local when = math.min(tonumber(f[4]) or ns.Now(), ns.Now())
    if author ~= sender then
        if post then
            for _, c in ipairs(post.comments) do
                if c.author == author and c.t == ct then return end -- only its writer deletes a comment
            end
        end
        -- Someone else's comment you don't have: provisional.
        if not ns.db.tombs[key] then S.SoftTomb(key, when, sender) end
        return
    end
    ns.db.tombs[key] = when
    if not post then return end
    for i, c in ipairs(post.comments) do
        if c.author == author and c.t == ct then
            table.remove(post.comments, i)
            ns.Changed()
            return
        end
    end
end)

Net.On("R", function(sender, data)
    if not Net.Allow(sender, "profile", S.RATE.profile) then return end
    local f = Split(data, 6)
    local t = tonumber(f[6]) or 0
    local old = ns.db.profiles[sender]
    if old and (old.t or 0) > t then return end
    ns.db.profiles[sender] = {
        class = ns.ValidClass(f[1]), race = ns.Look.Race(f[2]), level = math.max(0, math.min(200, tonumber(f[3]) or 0)),
        guild = Clean((f[4] or ""):gsub("|", ""), 48), bio = Clean(f[5], S.MAX_BIO), t = t, seen = ns.Now(),
    }
    PruneProfiles()
    ns.Changed()
end)

-- Profiles on request: opening someone's profile asks them (a whisper) for
-- theirs, instead of everyone sending theirs to everyone at every login. If
-- they're offline, the game's "No player named ... is currently playing"
-- line for that name is kept out of chat.
local asked = {}
function S.AskProfile(name)
    if not name or name == ns.Me() or (ns.Bots and ns.Bots.Is(name)) then return false end
    local last = asked[name]
    if last and Clock() - last < 300 then return false end
    asked[name] = Clock()
    return Net.Whisper("Q", "", name)
end

local function Offline(_, _, msg)
    if type(msg) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return false end
    local now = Clock()
    for name, t in pairs(asked) do
        if now - t < 10 then
            local short = ns.Display(name)
            if msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(name) or msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(short)
                or msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(Net.Full(name)) then
                S.Unreachable(name)
                return true
            end
        end
    end
    return false
end
S.OfflineFilter = Offline -- (the chat filter, for the tests)
if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", Offline) end

Net.On("Q", function(sender)
    if not Net.Allow(sender, "ask", S.RATE.ask) then return end
    local p = S.MyProfile()
    Net.Whisper("R", table.concat({ p.class or "", p.race or "", p.level or 0, p.guild or "", p.bio or "", p.t or 0 }, US),
        sender)
end)

---------------------------------------------------------------------------
-- Hello and sync: a player who logs in says how new their newest post is,
-- and someone sends back what's newer. Only a few answer, however many are
-- online:
--   * each answers with a chance of about S.ANSWERERS / (people online),
--     after a random wait of 2 to 12 seconds;
--   * whoever's wait ends after someone else has started answering stays quiet;
--   * if nobody has answered after 15 seconds, the rest still may (a
--     backstop, in case the chosen few were away).
-- An answer is up to 15 posts with their comments inside, and recent
-- deletions. Profiles aren't sent; they're asked for when needed.
---------------------------------------------------------------------------
local syncing = {} -- scope -> an answer is already planned

local function Newest()
    for _, p in ipairs(ns.db.posts) do
        if not p.bot and p.author ~= ns.Me() then return p.t end
    end
    return 0
end

local function HasSomething()
    for _, p in ipairs(ns.db.posts) do
        if not p.bot then return true end
    end
end

local function SendAnswer(since, scope, asked)
    local sent = 0
    local from = (since or 0) - S.SYNC_WINDOW
    for _, p in ipairs(ns.db.posts) do
        if sent >= S.SYNC_POSTS then break end
        if not p.bot and not p.unv and p.t > from and (postHeard[p.id] or -1) < asked and (p.share ~= "guild" or scope == "guild") then
            SendPost(p, scope, true)
            sent = sent + 1
        end
    end
    -- Recent deletions (newest first), so the newcomer drops what's gone.
    local recent = {}
    for key, t in pairs(ns.db.tombs) do
        if t > from then recent[#recent + 1] = { key, t } end
    end
    table.sort(recent, function(x, y) return x[2] > y[2] end)
    for i = 1, math.min(20, #recent) do
        local key, t = recent[i][1], recent[i][2]
        local id = key:match("^p:(.+)$")
        if id then
            Net.Send("D", id .. US .. t, scope)
        else
            local pid, author, ct = key:match("^c:([^:]+):(.+):(%d+)$")
            if pid then Net.Send("X", table.concat({ pid, author, ct, t }, US), scope) end
        end
    end
end

-- Answer a hello on the scope it came from (or not: see above).
function S.Answer(since, scope)
    scope = scope or "realm"
    if syncing[scope] or not HasSomething() then return end
    syncing[scope] = true
    local asked = Clock()
    local chance = math.min(1, S.ANSWERERS / math.max(1, Net.Peers(600)))
    local chosen = math.random() < chance
    local wait = chosen and (2 + math.random() * 10) or (15 + math.random() * 5)
    ns.After(wait, function()
        syncing[scope] = nil
        if (relayHeard[scope] or -1) > asked then return end -- someone else is on it
        SendAnswer(since, scope, asked)
    end)
end

Net.On("H", function(sender, data, chatType)
    S.Reachable(sender)
    if not Net.Allow(sender, "hello", S.RATE.hello) then return end
    S.Answer(tonumber(data) or 0, chatType == "GUILD" and "guild" or "realm")
end)

-- Say hello on the realm channel and in the guild (where reachable).
function S.Hello()
    if not ns.db.network then return false end
    local said = false
    for _, scope in ipairs({ "realm", "guild" }) do
        if Net.Send("H", tostring(Newest()), scope) then
            SendProfile(scope)
            said = true
        end
    end
    return said
end

-- Join the realm channel and say hello. Joining takes a moment the first
-- time, so it tries a few times.
function S.Connect()
    if not ns.db.network then return end
    local tries = 0
    local function Try()
        tries = tries + 1
        Net.Join()
        if Net.Online() then
            S.Hello()
            ns.Changed()
        elseif tries < 6 then
            ns.After(5, Try)
        else
            S.Hello() -- no realm channel: the guild still works
        end
    end
    AskRoster()
    ns.After(3, Try) -- chat channels aren't ready right at login
end

function S.SetNetwork(on)
    ns.db.network = on and true or false
    if on then S.Connect() else Net.Leave() end
    ns.Changed()
end

-- Your profile in the shared list too, so your other characters see it.
function S.KeepOwnProfile()
    local p = S.MyProfile()
    p.seen = ns.Now()
    ns.db.profiles[ns.Me()] = p
    ns.db.users[ns.Me()] = ns.Now()
end

function S:Init()
    ns.my.me.t = ns.my.me.t or 0
    ns.On("PLAYER_LOGIN", S.KeepOwnProfile)
    ns.On("FRIENDLIST_UPDATE", S.RefreshFriends)
    ns.On("BN_FRIEND_INFO_CHANGED", S.RefreshFriends)
    ns.On("PLAYER_LOGIN", function()
        if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
        S.RefreshFriends()
        ns.After(5, S.ReadRecentlyMet)
    end)
    ns.On("RECENT_ALLIES_CACHE_UPDATE", function() S.ReadRecentlyMet() end)
    ns.On("NAME_PLATE_UNIT_ADDED", function(unit) if unit then MeetUnit(unit) end end)
    ns.On("PLAYER_TARGET_CHANGED", function() MeetUnit("target") end)
    ns.On("UPDATE_MOUSEOVER_UNIT", function() MeetUnit("mouseover") end)
    ns.On("GROUP_ROSTER_UPDATE", function()
        local raid = IsInRaid and IsInRaid()
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do MeetUnit(raid and ("raid" .. i) or ("party" .. i)) end
    end)
    for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_WHISPER" }) do
        ns.On(ev, function(_, sender)
            if type(sender) == "string" and sender ~= "" then
                local short, realm = sender:match("^(.+)%-([^%-]+)$")
                S.Meet(ns.FOREVER and sender or ns.Id(short or sender, realm))
            end
        end)
    end
    ns.On("PLAYER_ENTERING_WORLD", function(login, reload)
        if login or reload then S.Connect() end
    end)
    local function Roster()
        S.RefreshGuild()
        ns.Changed()
    end
    ns.On("GUILD_ROSTER_UPDATE", Roster)
    ns.On("PLAYER_GUILD_UPDATE", function()
        AskRoster()
        Roster()
    end)
end

---------------------------------------------------------------------------
-- Doing things
---------------------------------------------------------------------------
-- `as`: a demo person (Core\Bots.lua) posting; their posts stay local.
-- share: "guild" (guild only) or nil (everyone).
function S.Post(lookString, caption, as, share)
    local post = {
        id = NewId(), author = as and as.name or ns.Me(), class = as and as.class or MyClass(),
        race = as and as.race or MyRace(), t = as and as.t or ns.Now(), edited = 0,
        look = lookString, caption = Clean(caption, S.MAX_CAPTION), likes = {}, comments = {},
        bot = as and true or nil, share = share == "guild" and "guild" or nil,
    }
    S.Store(post)
    SendPost(post)
    ns.Changed()
    return post
end

function S.Edit(id, caption, lookString)
    local post = S.Find(id)
    if not S.IsMine(post) then return end
    post.caption = Clean(caption, S.MAX_CAPTION)
    if lookString then post.look = lookString end
    post.edited = ns.Now()
    SendPost(post)
    ns.Changed()
end

function S.Delete(id)
    local post, i = S.Find(id)
    if not (post and S.IsMine(post)) then return end
    table.remove(ns.db.posts, i)
    local t = ns.Now()
    ns.db.tombs["p:" .. id] = t
    Send("D", id .. US .. t, ScopeOf(post))
    ns.Changed()
end

-- A like or dislike (field) on or off, by name; sent unless it's a demo.
local function Vote(post, field, cmd, on, name)
    local key = field == "dislikes" and S.Anon(name) or name
    local t = ns.Now()
    -- Two clicks in the same second must still count as newer.
    post[field] = post[field] or {}
    local old = math.abs(post[field][key] or 0)
    if t <= old then t = old + 1 end
    post[field][key] = on and t or -t
    if name == ns.Me() and not post.bot then
        postHeard[post.id] = nil
        if field == "likes" then S.RememberMine("l", post.id, post.likes[key]) end
        Send(cmd, table.concat({ post.id, key, post[field][key] }, US), ScopeOf(post))
    end
end

function S.Dislike(id, on, name)
    local post = S.Find(id)
    if not post then return end
    name = name or ns.Me()
    if S.Disliked(post, name) == (on and true or false) then return end
    if on and S.Liked(post, name) then Vote(post, "likes", "L", false, name) end
    Vote(post, "dislikes", "N", on, name)
    ns.Changed()
end

-- name: who likes it (a demo person), default you.
function S.Like(id, on, name)
    local post = S.Find(id)
    if not post then return end
    name = name or ns.Me()
    if S.Liked(post, name) == (on and true or false) then return end
    if on and S.Disliked(post, name) then Vote(post, "dislikes", "N", false, name) end
    Vote(post, "likes", "L", on, name)
    if name ~= ns.Me() and on then Activity("like", name, post) end
    ns.Changed()
end

function S.Comment(id, text, as)
    local post = S.Find(id)
    text = Clean(text, S.MAX_COMMENT)
    if not post or text == "" then return end
    local c = { author = as and as.name or ns.Me(), class = as and as.class or MyClass(), t = ns.Now(), edited = 0,
        text = text, bot = as and true or nil }
    -- Two comments in the same second by the same person need different times.
    for _, old in ipairs(post.comments) do
        if old.author == c.author and old.t >= c.t then c.t = old.t + 1 end
    end
    table.insert(post.comments, c)
    if not as then S.RememberMine("c", id .. ":" .. c.t, S.CommentPrint(c)) end
    if as then Activity("comment", c.author, post, text) else SendComment(post, c) end
    ns.Changed()
    return c
end

function S.DeleteComment(id, author, t)
    local post = S.Find(id)
    if not post then return end
    for i, c in ipairs(post.comments) do
        if c.author == author and c.t == t and author == ns.Me() then
            table.remove(post.comments, i)
            if not (post.bot or c.bot) then
                local now = ns.Now()
                ns.db.tombs["c:" .. id .. ":" .. author .. ":" .. t] = now
                Send("X", table.concat({ id, author, t, now }, US), ScopeOf(post))
            end
            ns.Changed()
            return
        end
    end
end

function S.Follow(name, on)
    if name == ns.Me() then return end
    ns.my.following[name] = on and ns.Now() or nil
    ns.Changed()
end

function S.SetBio(text)
    ns.my.me.bio = Clean(text, S.MAX_BIO)
    ns.my.me.t = ns.Now()
    S.KeepOwnProfile()
    SendProfile()
    ns.Changed()
end

---------------------------------------------------------------------------
-- Vouching: is it really theirs? Pictures, comments and likes passed on by
-- someone else (a sync) could be made up by a modified addon. They show at
-- once, marked unconfirmed (post.unv, comment.unv, post.likeUnv[name]), and
-- in the background the person they're from is asked (a whisper, "V"):
-- their addon answers for each (a "W"): 1 theirs, 0 not theirs (it goes,
-- and stays gone), 2 theirs but different (theirs follows), 3:<time> their
-- like as it really is, ? can't say (from before they kept a record).
-- Offline: asked again later, or when they say hello.
---------------------------------------------------------------------------
-- A fingerprint, compared between clients: never change how it's worked out
-- (older versions would see every picture as changed).
local function Hash36(s)
    local h1, h2 = 5381, 52711
    for i = 1, #s do
        local b = s:byte(i)
        h1 = (h1 * 33 + b) % 4294967296
        h2 = (h2 * 31 + b) % 4294967296
    end
    return ns.Look.B36(h1) .. ns.Look.B36(h2)
end

function S.PostPrint(post)
    return Hash36(table.concat({ post.look or "", post.caption or "", post.t or 0, post.edited or 0 }, "\031"))
end

function S.CommentPrint(c)
    return Hash36((c.text or "") .. "\031" .. (c.edited or 0))
end

-- Things of yours from after this computer started keeping a record (and
-- after a Clear everything): only those can be vouched for (or denied).
function S.Vouchable(t)
    t = math.abs(tonumber(t) or 0)
    return t >= (ns.my.since or 0) and t >= (ns.my.forgotBefore or 0)
end

S.MAX_MINE = 3000
function S.RememberMine(kind, key, value)
    local list = kind == "c" and ns.my.myComments or ns.my.myLikes
    list[key] = value
    S.mineCount = (S.mineCount or 0) + 1
    if S.mineCount % 100 == 0 then S.PruneMine() end
end

-- Over S.MAX_MINE: the oldest go (comments by their time, likes by theirs).
function S.PruneMine()
    for _, kind in ipairs({ "c", "l" }) do
        local list = kind == "c" and ns.my.myComments or ns.my.myLikes
        local all = {}
        for k, v in pairs(list) do
            local t = kind == "c" and tonumber(k:match(":(%-?%d+)$")) or math.abs(tonumber(v) or 0)
            all[#all + 1] = { k, t or 0 }
        end
        if #all > S.MAX_MINE then
            table.sort(all, function(a, b) return a[2] > b[2] end)
            for i = S.MAX_MINE + 1, #all do list[all[i][1]] = nil end
        end
    end
end

function S.MyLikeIs(id, t)
    local mine = ns.my.myLikes[id]
    if mine then return mine == t end
    return not S.Vouchable(t)
end

-- A comment from the network: one "by you" that you never wrote isn't taken;
-- one passed on by someone else is unconfirmed and checked.
function S.TakeComment(id, c, sender)
    if c.author == ns.Me() then
        local mine = ns.my.myComments[id .. ":" .. c.t]
        if (mine and mine ~= S.CommentPrint(c)) or (not mine and S.Vouchable(c.t)) then
            S.Strike(sender, 3, "a made-up comment in your name")
            return nil
        end
    end
    local post = S.StoreComment(id, c, sender)
    if not post then return nil end
    S.ResolveSoft("c:" .. id .. ":" .. c.author .. ":" .. c.t, c.author, sender)
    for _, x in ipairs(post.comments) do
        if x.author == c.author and x.t == c.t then
            if c.author == sender then x.unv = nil
            elseif x.unv == nil and x.text == c.text then
                x.unv, x.unvFrom = true, sender
                S.Check(c.author, "c", post, c.t, sender)
            end
        end
    end
    return post
end

-- What's waiting to be checked, per person: key -> item.
local queue, nextTry, inFlight = {}, {}, {}
S.VOUCH_BATCH = 40
S.MAX_FOLLOW = 5 -- full pictures or comments sent back per check

function S.Check(name, kind, post, t, from)
    if not name or name == ns.Me() or post.bot or (ns.Bots and ns.Bots.Is(name)) then return end
    if kind == "p" then t = post.t end -- (its date: was it posted after they kept a record?)
    local key = kind .. ":" .. post.id .. ":" .. tostring(t or "")
    if not queue[name] then
        local n = 0
        for _ in pairs(queue) do n = n + 1 end
        if n >= S.MAX_CHECKS then return end
    end
    queue[name] = queue[name] or {}
    queue[name][key] = { kind = kind, id = post.id, t = t, print = kind == "p" and S.PostPrint(post) or nil, from = from }
    if kind == "c" then
        for _, c in ipairs(post.comments) do
            if c.author == name and c.t == t then queue[name][key].print = S.CommentPrint(c) end
        end
    end
    nextTry[name] = nextTry[name] or 0
end

function S.Reachable(name)
    if queue[name] then nextTry[name] = 0 end
end

function S.Unreachable(name)
    nextTry[name] = Clock() + 600
    inFlight[name] = nil
end

-- Send a few checks (a couple of people at a time).
function S.CheckTick()
    if not ns.db or not ns.db.network then return end
    local now, sent = Clock(), 0
    for name, items in pairs(queue) do
        if sent >= 2 then break end
        if (nextTry[name] or 0) <= now and not inFlight[name] and next(items) then
            local batch, parts = {}, {}
            for key, it in pairs(items) do
                if #batch >= S.VOUCH_BATCH then break end
                batch[#batch + 1] = it
                parts[#parts + 1] = table.concat({ it.kind, it.id, tostring(it.t or ""), it.print or "" }, "\030")
                items[key] = nil
            end
            inFlight[name] = { batch = batch, at = now }
            nextTry[name] = now + 60
            asked[name] = now -- (an offline answer stays out of chat)
            Net.Whisper("V", table.concat(parts, "\029"), name)
            sent = sent + 1
        elseif inFlight[name] and now - inFlight[name].at > 30 then
            -- No answer: put it back for later.
            for _, it in ipairs(inFlight[name].batch) do
                items[it.kind .. ":" .. it.id .. ":" .. tostring(it.t or "")] = it
            end
            inFlight[name] = nil
        end
        if not next(items) and not inFlight[name] then queue[name] = nil end
    end
end

-- At login: anything still unconfirmed goes back in the queue.
function S.RequeueUnconfirmed()
    for _, post in ipairs(ns.db.posts) do
        if post.unv then S.Check(post.author, "p", post, nil, post.unvFrom) end
        for name, from in pairs(post.likeUnv or {}) do
            S.Check(name, "l", post, post.likes[name], type(from) == "string" and from or nil)
        end
        for _, c in ipairs(post.comments or {}) do
            if c.unv then S.Check(c.author, "c", post, c.t, c.unvFrom) end
        end
    end
end

-- Asked: answer for each thing said to be yours.
Net.On("V", function(sender, data, chatType)
    if chatType ~= "WHISPER" or not Net.Allow(sender, "vouch", S.RATE.vouch) then return end
    local answers, follow = {}, {}
    local count = 0
    for entry in tostring(data):gmatch("[^\029]+") do
        count = count + 1
        if count > S.VOUCH_BATCH then break end
        local kind, id, t, print = entry:match("^([plc])\030([^\030]*)\030([^\030]*)\030([^\030]*)$")
        t = tonumber(t)
        local a = "?"
        if kind == "p" then
            local post = S.Find(id)
            if ns.db.tombs["p:" .. id] then a = "D"
            elseif post and post.author == ns.Me() then
                if S.PostPrint(post) == print then a = "1"
                elseif #follow < S.MAX_FOLLOW then a = "2"; follow[#follow + 1] = { "P", PostData(post, false) } end
            elseif S.Vouchable(t or (post and post.t)) then a = "0" end
        elseif kind == "c" and t then
            local key = id .. ":" .. t
            local mine = ns.my.myComments[key]
            if ns.db.tombs["c:" .. id .. ":" .. ns.Me() .. ":" .. t] then a = "D"
            elseif mine then
                if mine == print then a = "1" else
                    local post = S.Find(id)
                    local c
                    for _, x in ipairs(post and post.comments or {}) do
                        if x.author == ns.Me() and x.t == t then c = x end
                    end
                    if c and #follow < S.MAX_FOLLOW then
                        a = "2"
                        follow[#follow + 1] = { "C", table.concat({ id, c.author, c.class or "", c.t, c.edited or 0, c.text }, US) }
                    end
                end
            elseif S.Vouchable(t) then a = "0" end
        elseif kind == "l" and t then
            local mine = ns.my.myLikes[id]
            if mine then a = (mine == t) and "1" or ("3:" .. mine)
            elseif S.Vouchable(t) then a = "0" end
        end
        answers[#answers + 1] = a
    end
    Net.Whisper("W", table.concat(answers, ","), sender)
    for _, m in ipairs(follow) do Net.Whisper(m[1], m[2], sender) end
end)

-- The answers: keep, drop (for good), or wait for the real one.
Net.On("W", function(sender, data, chatType)
    local flight = inFlight[sender]
    if chatType ~= "WHISPER" or not flight then return end
    inFlight[sender] = nil
    nextTry[sender] = 0
    local i, changed = 0, false
    for a in (tostring(data) .. ","):gmatch("([^,]*),") do
        i = i + 1
        local it = flight.batch[i]
        if not it then break end
        local post, idx = S.Find(it.id)
        if post then
            if it.kind == "p" and post.author == sender then
                if a == "0" or a == "D" then
                    table.remove(ns.db.posts, idx)
                    ns.db.tombs["p:" .. it.id] = ns.Now()
                    if a == "0" then S.Strike(it.from, 2, "a made-up picture") end
                    changed = true
                elseif a == "2" then
                    table.remove(ns.db.posts, idx) -- (theirs follows)
                    changed = true
                else
                    post.unv = nil
                end
                local soft = ns.db.softTombs["p:" .. it.id]
                if soft then
                    ns.db.softTombs["p:" .. it.id] = nil
                    if a == "1" or a == "2" or a == "?" then S.Strike(soft.from, 2, "a made-up deletion") end
                end
            elseif it.kind == "c" then
                for j, c in ipairs(post.comments) do
                    if c.author == sender and c.t == it.t then
                        if a == "0" or a == "D" then
                            table.remove(post.comments, j)
                            ns.db.tombs["c:" .. it.id .. ":" .. sender .. ":" .. it.t] = ns.Now()
                            if a == "0" then S.Strike(it.from, 2, "a made-up comment") end
                            changed = true
                        elseif a == "2" then
                            table.remove(post.comments, j) -- (theirs follows)
                            changed = true
                        else
                            c.unv = nil
                        end
                        break
                    end
                end
            elseif it.kind == "l" then
                if post.likeUnv then post.likeUnv[sender] = nil end
                local real = a:match("^3:(%-?%d+)$")
                if a == "0" then
                    -- Never liked: a "taken back" newer than the made-up one.
                    post.likes[sender] = -(math.abs(post.likes[sender] or 0) + 1)
                    S.Strike(it.from, 2, "a made-up like")
                    changed = true
                elseif real then
                    post.likes[sender] = tonumber(real)
                    changed = true
                end
            end
        end
    end
    if changed then ns.Changed() end
end)

do
    local function Tick()
        S.CheckTick()
        ns.After(15, Tick)
    end
    ns.On("PLAYER_LOGIN", function()
        S.RequeueUnconfirmed()
        ns.After(20, Tick)
    end)
end

---------------------------------------------------------------------------
-- Strikes: caught faking (something its real author says isn't theirs, or
-- a like, dislike, picture or comment in someone else's name) earns the
-- sender points. Honest addons only pass on what's confirmed, so only a
-- liar earns them. At S.STRIKE_LIMIT they're shut out: nothing of theirs
-- is listened to, and they're blocked (Settings shows them, with Unblock).
-- Points fade by one a day. Every addon judges for itself, from what it
-- sees: a cheater is caught by everyone they cheat, and nobody can get
-- someone else shut out by reporting them.
---------------------------------------------------------------------------
S.STRIKE_LIMIT = 6
function S.Strike(name, n, why)
    if not name or name == ns.Me() or (ns.Bots and ns.Bots.Is(name)) then return end
    local now = ns.Now()
    local s = ns.db.strikes[name] or { n = 0, t = now }
    s.n = math.max(0, s.n - (now - s.t) / 86400) + (n or 1)
    s.t, s.why = now, why
    ns.db.strikes[name] = s
    if s.n >= S.STRIKE_LIMIT - 0.05 and not S.Blocked(name) then
        ns.db.blocked[name] = now
        s.out = true
        ns.Print(ns.Display(name) .. " was caught faking things (" .. (why or "?") .. ") and is shut out.")
        S.Purge(name)
        ns.Changed()
    end
end

function S.ShutOut(name)
    local s = name and ns.db.strikes[name]
    return s ~= nil and s.out == true and S.Blocked(name)
end
Net.Ignored = S.ShutOut

-- Someone shut out: everything still unconfirmed that they passed on goes
-- now (their other fakes), without waiting for each owner to say so.
function S.Purge(name)
    local posts = ns.db.posts
    for i = #posts, 1, -1 do
        local post = posts[i]
        if post.unv and post.unvFrom == name then
            table.remove(posts, i)
            ns.db.tombs["p:" .. post.id] = ns.Now()
        else
            for j = #(post.comments or {}), 1, -1 do
                local c = post.comments[j]
                if c.unv and c.unvFrom == name then
                    table.remove(post.comments, j)
                    ns.db.tombs["c:" .. post.id .. ":" .. c.author .. ":" .. c.t] = ns.Now()
                end
            end
            for liker, from in pairs(post.likeUnv or {}) do
                if from == name then
                    post.likes[liker] = -(math.abs(post.likes[liker] or 0) + 1)
                    post.likeUnv[liker] = nil
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Provisional deletions: a deletion passed on by someone else, for a
-- picture or comment you don't have, can't be checked (whose was it?). It's
-- kept apart from the real ones (never passed on), and doesn't stop the
-- picture or comment from arriving. If it then arrives from its owner, or
-- its owner vouches for it, the deletion was made up: strikes for whoever
-- sent it. If the owner says it's deleted, it becomes a real deletion.
---------------------------------------------------------------------------
function S.SoftTomb(key, t, from)
    local soft = ns.db.softTombs
    if soft[key] then return end
    S.softCount = (S.softCount or 0) + 1
    if S.softCount % 50 == 0 then
        local n = 0
        for _ in pairs(soft) do n = n + 1 end
        if n >= S.MAX_SOFT then return end
    end
    soft[key] = { t = t, from = from }
end

-- Something arrived that had a provisional deletion: from its owner (alive:
-- the deletion was made up) or passed on (checked with the owner).
function S.ResolveSoft(key, owner, sender)
    local soft = ns.db.softTombs[key]
    if not soft then return nil end
    if owner == sender then
        ns.db.softTombs[key] = nil
        S.Strike(soft.from, 2, "a made-up deletion")
        return nil
    end
    return soft
end

function S.PruneSoft()
    local cutoff = ns.Now() - TOMB_DAYS * 86400
    for k, v in pairs(ns.db.softTombs) do
        if (v.t or 0) < cutoff then ns.db.softTombs[k] = nil end
    end
end
