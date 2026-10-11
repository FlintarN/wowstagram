-- Profile, like Instagram's desktop profile: a big avatar, the name with
-- Edit profile (you) or Follow (someone else), "12 posts  5 followers
-- 3 following", who they are and their bio, then POSTS and SAVED (yours
-- only) over a three-column grid. Hover a picture for its likes and
-- comments. The whole page scrolls, header and all (UI\Scroller.lua).
local _, ns = ...

local W = ns.Widgets
local C = W.C
local S = ns.Social
local PR = {}
ns.Profile = PR

local COLS = 3
local HEAD_H = 236

local function RaceName(id)
    if not id then return nil end
    if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local info = C_CreatureInfo.GetRaceInfo(id)
        if info and info.raceName then return info.raceName end
    end
end

local function ClassName(class)
    class = ns.ValidClass(class)
    return class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
        or (class and class:sub(1, 1) .. class:sub(2):lower())
end

-- key: "profile" (you) or "person" (whoever ns.UI:OpenPerson names).
function PR.New(parent, key)
    local view = { mine = key == "profile", tab = "posts", list = {} }
    local UI = ns.UI
    local page = parent
    -- The header is the top of the scrolling page.
    parent = CreateFrame("Frame", nil, page)
    parent:SetSize(UI.MAIN_W, HEAD_H)

    -- Header.
    view.face = W.Avatar(parent, 120)
    view.face:SetPoint("TOPLEFT", 60, -24)
    local info = CreateFrame("Frame", nil, parent)
    info:SetPoint("TOPLEFT", 230, -30)
    info:SetSize(UI.MAIN_W - 260, 140)
    view.name = W.Text(info, 20)
    view.name:SetPoint("TOPLEFT", 0, 0)
    view.name:SetWordWrap(false)

    if view.mine then
        view.editButton = W.Flat(info, "Edit profile", 104, 30, "secondary", function()
            -- Done saves what's in the box (as Enter does).
            if view.editing then S.SetBio(view.bioBox:GetText() or "") end
            view.editing = not view.editing
            if view.editing then view.bioBox:SetText(ns.my.me.bio or "") view.bioBox:SetFocus() end
            view:Refresh()
        end)
        view.editButton:SetPoint("LEFT", view.name, "RIGHT", 20, 0)
        view.gear = W.Glyph(info, "Gear", 20, function() UI:Show("settings") end)
        view.gear:SetPoint("LEFT", view.editButton, "RIGHT", 8, 0)
        W.Tooltip(view.gear, "Settings")
    else
        view.follow = W.FollowButton(info, 100, 30, function() return view.name_ end)
        view.follow:SetPoint("LEFT", view.name, "RIGHT", 20, 0)
        view.block = W.Flat(info, "Block", 70, 30, "link", function()
            local who = view.name_
            if not who then return end
            if S.Blocked(who) then S.Block(who, false) else UI:ConfirmBlock(who) end
        end, 12)
        view.block:SetPoint("LEFT", view.follow, "RIGHT", 6, 0)
    end

    view.counts = W.Text(info, 13)
    view.counts:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -20)
    view.who = W.Text(info, 12, C.dim)
    view.who:SetPoint("TOPLEFT", view.counts, "BOTTOMLEFT", 0, -16)
    view.bio = W.Text(info, 12)
    view.bio:SetPoint("TOPLEFT", view.who, "BOTTOMLEFT", 0, -6)
    view.bio:SetWidth(UI.MAIN_W - 270)
    view.bio:SetWordWrap(true)
    ns.Feed.Linkable(info)
    if view.mine then
        view.bioBox = W.Input(info, 320, 28, "A line about you", S.MAX_BIO, function(text)
            S.SetBio(text)
            view.editing = false
            view:Refresh()
        end)
        view.bioBox:SetPoint("TOPLEFT", view.who, "BOTTOMLEFT", -2, -4)
        view.bioBox:Hide()
    end

    -- POSTS / SAVED.
    local top = 200
    local line = W.Line(parent)
    line:SetPoint("TOPLEFT", 20, -top)
    line:SetPoint("TOPRIGHT", -20, -top)
    local items = { { key = "posts", label = "POSTS", icon = "Grid" } }
    if view.mine then items[2] = { key = "saved", label = "SAVED", icon = "Bookmark" } end
    view.tabs = W.Tabs(parent, items, function(k)
        view.tab = k
        view:Refresh()
        view.scroll:Top()
    end, { top = true, size = 11, gap = 40 })
    local tabW = 0
    for _, b in ipairs(view.tabs.buttons) do tabW = tabW + b:GetWidth() + 40 end
    view.tabs.buttons[1]:SetPoint("TOPLEFT", (UI.MAIN_W - tabW + 40) / 2, -top)

    -- The grid, three to a row, under the header; it all scrolls.
    local gap, left = 4, 20
    local tw = math.floor((UI.MAIN_W - left * 2 - gap * (COLS - 1)) / COLS)
    local th = math.floor(tw * ns.Look.ASPECT)
    view.thumbs = {}
    local function Thumb(row, col)
        local thumb
        thumb = ns.Picture.New(row, tw, th, {
            badge = "small",
            onClick = function() if thumb.post then UI:OpenPost(thumb.post.id) end end,
        })
        thumb:SetPoint("TOPLEFT", left + (col - 1) * (tw + gap), 0)
        thumb.rowY = 0
        -- Hover: darker, with the counts in the middle.
        local hover = CreateFrame("Frame", nil, thumb.over)
        hover:SetAllPoints()
        W.Fill(hover, C.bg, 0.45, "ARTWORK")
        local heart = W.Icon(hover, "Heart", 18, { 1, 1, 1 })
        heart:SetPoint("CENTER", -34, 0)
        thumb.likes = W.Text(hover, 14, { 1, 1, 1 })
        thumb.likes:SetPoint("LEFT", heart, "RIGHT", 6, 0)
        local bubble = W.Icon(hover, "Bubble", 17, { 1, 1, 1 })
        bubble:SetPoint("CENTER", 22, 0)
        thumb.comments = W.Text(hover, 14, { 1, 1, 1 })
        thumb.comments:SetPoint("LEFT", bubble, "RIGHT", 6, 0)
        hover:Hide()
        thumb:HookScript("OnEnter", function() hover:Show() end)
        thumb:HookScript("OnLeave", function() hover:Hide() end)
        view.thumbs[#view.thumbs + 1] = thumb
        return thumb
    end
    view.scroll = ns.Scroller.New(page, {
        header = parent, headerH = HEAD_H, rowH = th + gap, bottom = 16,
        count = function() return math.ceil(#view.list / COLS) end,
        build = function(row)
            row.pics = {}
            for c = 1, COLS do row.pics[c] = Thumb(row, c) end
        end,
        fill = function(row, index)
            for c, thumb in ipairs(row.pics) do
                local post = view.list[(index - 1) * COLS + c]
                thumb.post = post
                if post then
                    if thumb.lookString ~= post.look or thumb.author ~= post.author then
                        thumb.lookString = post.look
                        thumb:SetLook(post.look, post.author)
                    end
                    thumb.likes:SetText(ns.Count(S.Likes(post)))
                    thumb.comments:SetText(ns.Count(#S.Comments(post)))
                    thumb:Show()
                else
                    thumb:Hide()
                end
            end
        end,
    })
    view.empty = W.Text(page, 14, C.dim)
    view.empty:SetPoint("TOP", 0, -HEAD_H - 60)
    view.empty:SetJustifyH("CENTER")
    view.emptyButton = W.Flat(page, "Create a picture", 150, 32, "primary", function() UI:Show("studio") end)
    view.emptyButton:SetPoint("TOP", view.empty, "BOTTOM", 0, -16)

    function view:Open(name)
        local who = self.mine and ns.Me() or name
        if who ~= self.name_ then
            self.tab = "posts"
            self.scroll:Top()
        end
        self.name_ = who
        self.editing = false
        if not self.mine then ns.Social.AskProfile(who) end
    end

    function view:Refresh()
        local who = self.mine and ns.Me() or self.name_
        self.name_ = who
        if not who then return end
        local prof = S.Profile(who)
        local posts = S.List(who)
        local class = prof.class or (posts[1] and posts[1].class)
        self.face:SetPlayer(who, class)
        self.name:SetText(ns.Display(who))

        local likes = 0
        for _, p in ipairs(posts) do likes = likes + S.Likes(p) end
        local B = function(n) return "|cffffffff" .. ns.Count(n) .. "|r" end
        local counts = B(#posts) .. W.Hex(C.dim) .. " posts|r      " .. B(S.Followers(who)) .. W.Hex(C.dim)
            .. " followers|r      "
        if self.mine then
            local n = 0
            for _ in pairs(ns.my.following) do n = n + 1 end
            counts = counts .. B(n) .. W.Hex(C.dim) .. " following|r"
        else
            counts = counts .. B(likes) .. W.Hex(C.dim) .. " likes|r"
        end
        self.counts:SetText(counts)

        local bits = {}
        if (prof.level or 0) > 0 then bits[#bits + 1] = "Level " .. prof.level end
        local race = prof.raceName or RaceName(prof.race or (posts[1] and posts[1].race))
        if race then bits[#bits + 1] = race end
        if class then bits[#bits + 1] = ClassName(class) end
        if prof.guild and prof.guild ~= "" then bits[#bits + 1] = "<" .. prof.guild .. ">" end
        if ns.Bots.Is(who) then bits[#bits + 1] = "demo person" end
        self.who:SetText(table.concat(bits, "  \194\183  "))

        local bio = prof.bio and prof.bio ~= "" and prof.bio or nil
        if self.mine then
            self.bioBox:SetShown(self.editing == true)
            self.bio:SetShown(not self.editing)
            self.bio:SetText(bio and ns.Feed.Rich(bio) or (W.Hex(C.faint) .. "No bio yet. Edit profile to add one.|r"))
            self.editButton:SetText(self.editing and "Done" or "Edit profile")
        else
            local blocked = S.Blocked(who)
            local auto = blocked and S.ShutOut(who)
            self.bio:SetText(blocked and (W.Hex(C.faint) .. (auto
                and ("Blocked by Wowstagram for cheating (" .. (ns.db.strikes[who].why or "faking things") .. "). ")
                or ("You blocked " .. ns.Display(who) .. ". ")) .. "Their pictures and comments are hidden.|r")
                or (bio and ns.Feed.Rich(bio)) or "")
            self.follow:Update(who)
            self.follow:SetShown(not blocked)
            self.block:SetText(blocked and "Unblock" or "Block")
        end

        -- Grid.
        local list = self.tab == "saved" and S.List("saved") or posts
        self.tabs:Select(self.tab)
        self.list = list
        self.scroll:Refresh()
        local none = #list == 0
        if self.tab == "saved" then
            self.empty:SetText(none and "Save pictures you like with the bookmark. Only you can see what you've saved." or "")
        else
            self.empty:SetText(none and (self.mine and "Share your first picture" or "No pictures yet") or "")
        end
        self.emptyButton:SetShown(none and self.mine and self.tab == "posts")
    end

    return view
end
