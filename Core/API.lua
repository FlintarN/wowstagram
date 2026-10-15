-- API: the one global other addons use (WowstagramAPI). HearthPhone shows
-- Wowstagram as an app with it.
--
-- Thin wrappers over the modules: everything goes through the same code as
-- the Wowstagram window (limits, owner checks, the network, redraws), and
-- only this surface is promised; the rest can change. Posts come back as
-- Wowstagram's own tables: read them, never change them, and never write
-- to WowstagramDB.
--
-- VERSION goes up only when an existing function changes meaning or
-- arguments; new functions don't change it.
--
-- Loaded last (every module exists by now).
local _, ns = ...

local S, L, P = ns.Social, ns.Look, ns.Picture
local API = { VERSION = 1 }

-- A look string from another addon: decoded and encoded again, so only a
-- look Wowstagram understands goes out.
local function CleanLook(lookString)
    if type(lookString) ~= "string" or lookString == "" then return nil end
    return L.Encode(L.Decode(lookString))
end

---------------------------------------------------------------------------
-- Who and names
---------------------------------------------------------------------------
function API.Me() return ns.Me() end
function API.Display(id) return ns.Display(id) end
function API.ColorName(id, class) return ns.ColorName(id, class) end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
function API.Feed() return S.Feed() end
-- filter: "all", "guild", "following", or a person's id.
function API.List(filter) return S.List(filter) end
function API.Find(id) return (S.Find(id)) end
function API.Comments(post) return S.Comments(post) end
function API.Likes(post) return S.Likes(post) end
function API.Liked(post, name) return S.Liked(post, name) end
function API.Profile(name) return S.Profile(name) end
function API.Following(name) return S.Following(name) end
function API.Saved(id) return S.Saved(id) end
function API.HasGuild() return S.HasGuild() end
function API.IsMine(post) return S.IsMine(post) end
function API.NetworkOn() return ns.db.network == true end

---------------------------------------------------------------------------
-- Actions (the same as the window's buttons)
---------------------------------------------------------------------------
-- share: "guild" (only if you have one) or nil. Returns the new post's id.
function API.Post(lookString, caption, share)
    lookString = CleanLook(lookString)
    if not lookString then return nil end
    local post = S.Post(lookString, caption or "", nil, share == "guild" and S.HasGuild() and "guild" or nil)
    ns.Bots.React(post)
    return post.id
end

-- Your own post only. lookString: nil keeps the picture.
function API.Edit(id, caption, lookString)
    S.Edit(id, caption or "", lookString and CleanLook(lookString) or nil)
end

function API.Delete(id) S.Delete(id) end
function API.Like(id, on) S.Like(id, on and true or false) end

function API.Comment(id, text)
    local post = S.Find(id)
    if not post or type(text) ~= "string" or strtrim(text) == "" then return end
    S.Comment(id, text)
    ns.Bots.Reply(post)
end

function API.DeleteComment(id, author, t) S.DeleteComment(id, author, t) end
function API.Follow(name, on) S.Follow(name, on and true or false) end

function API.Save(id, on)
    if S.Find(id) then S.Save(id, on and true or false) end
end

---------------------------------------------------------------------------
-- Change notifications
---------------------------------------------------------------------------
-- fn() after Wowstagram's data changed (at most a few times a second). An
-- error in fn is reported but never stops Wowstagram's own pages.
function API.OnChange(fn)
    if type(fn) ~= "function" then return end
    ns.OnChange(function()
        local ok, err = pcall(fn)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end)
end

---------------------------------------------------------------------------
-- Pictures
---------------------------------------------------------------------------
-- A picture: pic:SetLook(look, author), pic:Crop(top, bottom),
-- pic.onWheel(delta); opts.onClick(). See UI\Picture.lua.
function API.NewPicture(parent, w, h, opts) return P.New(parent, w, h, opts or {}) end
-- A scrolling list whose pictures are cropped at its edges. See UI\Scroller.lua.
function API.NewScroller(parent, opts) return ns.Scroller.New(parent, opts) end
-- After your frame's scale changed: pictures in view are drawn again.
function API.RefreshPictures() P.RefreshAll() end

---------------------------------------------------------------------------
-- Create
---------------------------------------------------------------------------
function API.Decode(lookString) return L.Decode(lookString) end
function API.Encode(look) return L.Encode(look) end

-- You in your current outfit, transmog included (as Create's "Wear my
-- current outfit"). cb(lookString, transmog): transmog is false when this
-- client can't read it (you're in your gear's own looks).
function API.CurrentOutfitLook(cb)
    if type(cb) ~= "function" then return end
    local look = L.Me(L.New())
    look.slots = P.Equipped()
    P.ReadOutfitOf("player", function(slots)
        local read = slots and next(slots) ~= nil
        if read then look.slots = slots end
        cb(L.Encode(look), read and true or false)
    end)
end

-- What a simple Create can offer: { poses, framings, backgrounds, filters },
-- each a list of { key, label }. Set them on a look (look.pose,
-- look.frame, look.bg, look.filter) and Encode it.
function API.Options()
    local function List(defs)
        local out = {}
        for _, d in ipairs(defs) do out[#out + 1] = { key = d.key, label = d.name } end
        return out
    end
    return { poses = List(L.POSES), framings = List(L.FRAMES), backgrounds = List(L.BACKGROUNDS), filters = List(L.FILTERS) }
end

-- Open the full Wowstagram window on a page: "feed", "search", "studio",
-- "activity", "profile", "settings", "post" (arg: post id) or "person"
-- (arg: a person's id).
function API.Open(page, arg)
    if page == "post" and arg then return ns.UI:OpenPost(arg) end
    if page == "person" and arg then return ns.UI:OpenPerson(arg) end
    ns.UI:Show(page or "feed", arg)
end

WowstagramAPI = API
