-- Bots: demo people, so Wowstagram is never empty while you try it alone.
-- They have their own posts, like and comment on yours, and answer when you
-- comment on theirs. Nothing of theirs is ever sent to anyone: their posts
-- carry `bot = true`, and Settings can switch them off (which removes them).
--
-- Their outfits are plain item ids: classic raid tier sets on Retail; on WoW
-- Forever, whose item data doesn't have those (yet), the classic dungeon
-- sets for the same classes (ids checked in ItemTree's Forever data),
-- so they draw on any client. Their pictures show on YOUR character, as any
-- picture does when its owner isn't nearby (see UI\Picture.lua).
local ADDON, ns = ...

local B = {}
ns.Bots = B

B.PEOPLE = {
    { name = "Thrag Ironhide", class = "WARRIOR", race = 2, sex = 2, guild = true,
      outfit = { [1] = 16963, [3] = 16961, [5] = 16966, [10] = 16964, [7] = 16962, [8] = 16965, [16] = 17076 },
      forever = { [1] = 16731, [3] = 16733, [5] = 16730, [10] = 16737, [7] = 16732, [8] = 16734, [16] = 12784 } },
    { name = "Mirelle Dawnveil", class = "PALADIN", race = 1, sex = 3,
      outfit = { [1] = 16955, [3] = 16953, [5] = 16958, [10] = 16956, [7] = 16954, [8] = 16957, [16] = 17182 },
      forever = { [1] = 16727, [3] = 16729, [5] = 16726, [10] = 16724, [7] = 16728, [8] = 16725, [16] = 12796 } },
    { name = "Zix Gearspark", class = "MAGE", race = 7, sex = 2,
      outfit = { [1] = 16914, [3] = 16917, [5] = 16916, [10] = 16913, [7] = 16915, [8] = 16912, [16] = 18842 },
      forever = { [1] = 16686, [3] = 16689, [5] = 16688, [10] = 16684, [7] = 16687, [8] = 16682, [16] = 2243 } },
    { name = "Elora Brightwind", class = "DRUID", race = 4, sex = 3, guild = true,
      outfit = { [1] = 16834, [3] = 16836, [5] = 16833, [10] = 16831, [7] = 16835, [8] = 16829 },
      forever = { [1] = 16720, [3] = 16718, [5] = 16706, [10] = 16717, [7] = 16719, [8] = 16715 } },
    { name = "Vashka Nightfang", class = "ROGUE", race = 8, sex = 3,
      outfit = { [1] = 16908, [3] = 16832, [5] = 16905, [10] = 16907, [7] = 16909, [8] = 16906, [16] = 18832, [17] = 17075 },
      forever = { [1] = 16707, [3] = 16708, [5] = 16721, [10] = 16712, [7] = 16709, [8] = 16711, [16] = 17705, [17] = 17705 } },
}
-- Bump when outfits change: their posts are made again.
B.VERSION = 3
B.BY_NAME = {}
for _, p in ipairs(B.PEOPLE) do B.BY_NAME[p.name] = p end

-- Their posts: who, hours ago, pose, background, framing, caption, changes to
-- their usual outfit, and a filter.
local POSTS = {
    { "Thrag Ironhide", 30, "roar", "durotar", "full", "Molten Core cleared. The Wrath set is finally complete! #lfg #warrior" },
    { "Mirelle Dawnveil", 26, "salute", "stormwind", "full", "For the Light, and for the drip. #judgement" },
    { "Zix Gearspark", 20, "dance", "duskwood", "full", "When the frostbolt crits. #mage #gnomelife",
      { [1] = 21524 } },
    { "Elora Brightwind", 14, "wave", "moonglade", "waist", "Moonglade sunsets never get old.", nil, "warm" },
    { "Vashka Nightfang", 9, "rude", "normal", "full", "You didn't see me. #stealth #ootd", nil, "noir" },
    { "Thrag Ironhide", 5, "laugh", "elwynn", "waist", "Day off. Picnic in Elwynn, ask me how many murlocs ruined it.",
      { [1] = false, [3] = false, [5] = 10036, [4] = 6833, [7] = 6835, [10] = false, [16] = false } },
    { "Zix Gearspark", 2, "cheer", "winterspring", "face", "Selfie at -40. Worth it. #winterspring", nil, "cool" },
}

local COMMENTS = {
    "Love this look!", "Where did you get that helm?", "Okay, that's the best one yet.", "The pose!!",
    "Teach me your ways.", "Clean.", "That filter suits you.", "Saving this for my next transmog.",
    "Haha, legend.", "Looking dangerous.",
}
local REPLIES = { "Thank you!", "Ha, thanks!", "Appreciate it!", "Glad you like it!", "Right?!" }

local function Pick(list) return list[math.random(#list)] end

function B.Is(name)
    return B.BY_NAME[name] ~= nil
end

-- Two of them play "your guild", so the Guild feed has something to show.
function B.InGuild(name)
    local p = B.BY_NAME[name]
    return ns.db.demo == true and p ~= nil and p.guild == true
end

local function LookFor(person, pose, bg, frame, changes, filter)
    local look = ns.Look.New()
    look.race, look.sex, look.class = person.race, person.sex, person.class
    look.pose, look.bg, look.frame, look.filter = pose, bg, frame, filter or "normal"
    look.drawn = ns.Look.POSE[pose] and ns.Look.POSE[pose].drawn or nil
    for slot, item in pairs(ns.FOREVER and person.forever or person.outfit) do look.slots[slot] = { item = item } end
    for slot, item in pairs(changes or {}) do
        look.slots[slot] = item and { item = item } or nil
    end
    return ns.Look.Encode(look)
end

local function HasBotPosts()
    for _, p in ipairs(ns.db.posts) do
        if p.bot then return true end
    end
end

local function Seed()
    local S = ns.Social
    local now = ns.Now()
    for _, def in ipairs(POSTS) do
        local person = B.BY_NAME[def[1]]
        local post = S.Post(LookFor(person, def[3], def[4], def[5], def[7], def[8]), def[6],
            { name = person.name, class = person.class, race = person.race, t = now - def[2] * 3600 })
        -- The others like and comment on it a little.
        for _, other in ipairs(B.PEOPLE) do
            if other ~= person and math.random() < 0.7 then
                post.likes[other.name] = post.t + math.random(60, 3600)
            end
        end
        local who = B.PEOPLE[math.random(#B.PEOPLE)]
        if who ~= person then
            table.insert(post.comments, { author = who.name, class = who.class, t = post.t + math.random(120, 7200),
                edited = 0, text = Pick(COMMENTS), bot = true })
        end
    end
end

-- Remove everything the demo people did.
local function Clear()
    local posts = ns.db.posts
    for i = #posts, 1, -1 do
        if posts[i].bot then table.remove(posts, i) end
    end
    for _, p in ipairs(posts) do
        for name in pairs(p.likes or {}) do
            if B.Is(name) then p.likes[name] = nil end
        end
        for i = #(p.comments or {}), 1, -1 do
            if p.comments[i].bot then table.remove(p.comments, i) end
        end
    end
end

-- Match the Settings switch: demo people there, or gone.
function B:Sync()
    -- New outfits (or another game's): make their posts again.
    local version = B.VERSION .. (ns.FOREVER and "f" or "r")
    if ns.db.botVersion ~= version then
        Clear()
        ns.db.botVersion = version
    end
    if ns.db.demo then
        if not HasBotPosts() then Seed() end
    else
        Clear()
    end
    ns.Changed()
end

function B.SetEnabled(on)
    ns.db.demo = on and true or false
    B:Sync()
end

-- Everyone follows you; each demo person follows the other demo people.
function B.Followers(name)
    if not ns.db.demo then return 0 end
    if B.Is(name) then return #B.PEOPLE - 1 end
    if name == ns.Me() then return #B.PEOPLE end
    return 0
end

-- You posted: a few of them notice, over the next half minute.
function B.React(post)
    if not ns.db.demo or not post then return end
    local id = post.id
    local order = {}
    for _, p in ipairs(B.PEOPLE) do table.insert(order, p) end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    for i = 1, math.random(2, #order) do
        local person = order[i]
        ns.After(3 + math.random() * 25, function()
            if ns.db.demo then ns.Social.Like(id, true, person.name) end
        end)
    end
    local talker = order[1]
    ns.After(8 + math.random() * 20, function()
        if ns.db.demo then ns.Social.Comment(id, Pick(COMMENTS), talker) end
    end)
end

-- You commented on a demo person's post: they answer.
function B.Reply(post)
    if not ns.db.demo or not post or not post.bot then return end
    local person = B.BY_NAME[post.author]
    if not person then return end
    local id = post.id
    ns.After(4 + math.random() * 8, function()
        if ns.db.demo then ns.Social.Comment(id, Pick(REPLIES), person) end
    end)
end
