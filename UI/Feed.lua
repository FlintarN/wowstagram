-- Home: Instagram's desktop feed. In the middle, the feed tabs (Realm,
-- Guild, Following), then the wall: stories at the top and the posts under
-- each other, all scrolling smoothly with the mouse wheel (UI\Scroller.lua
-- crops the 3D pictures at the edges). On the right, you, and people to
-- follow.
local _, ns = ...

local W = ns.Widgets
local C = W.C
local S = ns.Social
local F = {}
ns.Feed = F

local COL_X, COL_W = 40, 356
local PIC_H = math.floor(COL_W * ns.Look.ASPECT) -- a post's picture (4:5)
F.CARD_H = 42 + PIC_H + 146   -- header, picture, everything under it
local ROW_H = F.CARD_H + 26   -- and the gap to the next post
local SIDE_X, SIDE_W = 456, 210

-- A big heart over the picture that grows and fades (double-click like).
function F.HeartPop(parent)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(W.ART .. "Heart")
    t:SetVertexColor(1, 1, 1)
    t:SetPoint("CENTER")
    t:Hide()
    local driver = CreateFrame("Frame", nil, parent)
    function t:Pop()
        local k = 0
        self:Show()
        driver:SetScript("OnUpdate", function(_, elapsed)
            k = k + elapsed / 0.7
            if k >= 1 then
                t:Hide()
                driver:SetScript("OnUpdate", nil)
                return
            end
            local size = 50 + 60 * math.min(1, k * 4)
            t:SetSize(size, size)
            t:SetAlpha(k < 0.5 and 0.9 or 0.9 * (1 - (k - 0.5) * 2))
        end)
    end
    return t
end

-- Text from anyone, ready to show: "|" doubled (so nobody's colour or
-- texture codes work), #tags and @mentions as links (clicked: F.Link).
local LINK = "|cff58a6ff"
function F.Rich(text)
    text = tostring(text or ""):gsub("|", "||")
    text = text:gsub("#([%w_\128-\255]+)", function(tag)
        return "|Hwgtag:" .. tag:lower() .. "|h" .. LINK .. "#" .. tag .. "|r|h"
    end)
    for _, m in ipairs(ns.Social.Mentions(text)) do
        local at = m.at:gsub("%p", "%%%0")
        text = text:gsub(at, "|Hwgperson:" .. m.id .. "|h" .. LINK .. m.at .. "|r|h", 1)
    end
    return text
end

-- A link in a caption or comment was clicked.
function F.Link(link)
    local kind, value = tostring(link):match("^(%w+):(.+)$")
    if kind == "wgtag" then
        ns.UI:Show("feed")
        ns.UI.pages.feed.view:ShowTag(value)
    elseif kind == "wgperson" then
        ns.UI:OpenPerson(value)
    end
end

-- Make a frame's text links clickable.
function F.Linkable(frame)
    if frame.SetHyperlinksEnabled then frame:SetHyperlinksEnabled(true) end
    frame:SetScript("OnHyperlinkClick", function(_, link) F.Link(link) end)
end

-- "Name  caption", the name in its class colour.
function F.NameLine(name, class, text)
    return ns.ColorName(name, class) .. "  " .. F.Rich(text)
end

-- What a heart click does everywhere: like or unlike, with the sound.
-- show(post, liked): redraw the post's heart and likes right away (the
-- page's own redraw comes a moment later).
-- The thumbs-down: dislike or take it back.
function F.ToggleDislike(post, show)
    if not post then return end
    S.Dislike(post.id, not S.Disliked(post))
    W.PlaySound("IG_QUEST_LIST_SELECT")
    if show then show(post, false) end
end

function F.ToggleLike(post, show)
    if not post then return end
    local on = not S.Liked(post)
    S.Like(post.id, on)
    W.PlaySound("IG_QUEST_LIST_SELECT")
    if show then show(post, on) end
end

-- Double-click: like it (never unlike), with the big heart.
function F.DoubleLike(post, pop, show)
    if not post then return end
    local was = S.Liked(post)
    if not was then S.Like(post.id, true) end
    pop:Pop()
    W.PlaySound("IG_QUEST_LIST_SELECT")
    if show then show(post, not was) end
end

local function LikesText(post)
    local n, d = S.Likes(post), S.Dislikes(post)
    local dis = d > 0 and ("  \194\183  " .. ns.Count(d) .. (d == 1 and " dislike" or " dislikes")) or ""
    if n == 0 then return d > 0 and (ns.Count(d) .. (d == 1 and " dislike" or " dislikes")) or "Be the first to like this" end
    return ns.Count(n) .. (n == 1 and " like" or " likes") .. dis
end
F.LikesText = LikesText

---------------------------------------------------------------------------
-- One post, Instagram style.
---------------------------------------------------------------------------
-- menuParent: where the "..." menu lives (outside the scroll area, so it
-- isn't cut off).
function F.Card(parent, w, ph, onOpen, menuParent)
    local card = CreateFrame("Frame", nil, parent)
    F.Linkable(card)
    card:SetSize(w, 42 + ph + 146)

    card.face = W.Avatar(card, 32)
    card.face:SetPoint("TOPLEFT", 0, 0)
    card.name = CreateFrame("Button", nil, card)
    card.name:SetPoint("LEFT", card.face, "RIGHT", 10, 0)
    card.name:SetSize(w - 120, 20)
    card.name.text = W.Text(card.name, 13)
    card.name.text:SetPoint("LEFT")
    card.name.text:SetWordWrap(false)
    local function Person() if card.post then ns.UI:OpenPerson(card.post.author) end end
    card.name:SetScript("OnClick", Person)
    card.face:SetScript("OnClick", Person)
    card.dots = W.Glyph(card, "Dots", 18, function(self) card.menu:Toggle(self) end)
    card.dots:SetPoint("TOPRIGHT", 0, -4)
    card.menu = W.Menu(menuParent or card, 170)

    local lastClick = 0
    card.pic = ns.Picture.New(card, w, ph, {
        badge = "full",
        onClick = function()
            local post = card.post
            if not post then return end
            local now = GetTime()
            if now - lastClick < 0.35 then
                lastClick = 0
                card.opening = nil
                F.DoubleLike(post, card.pop, function(p, bounce) card:ShowLikes(p, bounce) end)
                return
            end
            lastClick = now
            local token = {}
            card.opening = token
            ns.After(0.36, function()
                if card.opening == token and card.post == post then onOpen(post) end
            end)
        end,
    })
    card.pic:SetPoint("TOPLEFT", 0, -42)
    card.pic.rowY = 42 -- (for the scroller's cropping)
    card.pop = F.HeartPop(card.pic.over)

    -- Heart, comment, and save.
    card.heart = W.Glyph(card, "HeartOutline", 24, function()
        F.ToggleLike(card.post, function(p, on) card:ShowLikes(p, on) end)
    end)
    card.heart:SetPoint("TOPLEFT", card.pic, "BOTTOMLEFT", -3, -6)
    card.dislike = W.Glyph(card, "ThumbDown", 23, function()
        F.ToggleDislike(card.post, function(p) card:ShowLikes(p) end)
    end)
    card.dislike:SetPoint("LEFT", card.heart, "RIGHT", 8, 0)
    W.Tooltip(card.dislike, "Dislike", "A thumbs down. Liking it again takes the dislike back.")
    card.bubble = W.Glyph(card, "Bubble", 23, function() if card.post then onOpen(card.post) end end)
    card.bubble:SetPoint("LEFT", card.dislike, "RIGHT", 8, 0)
    card.save = W.Glyph(card, "Bookmark", 23, function()
        if card.post then S.Save(card.post.id, not S.Saved(card.post.id)) end
    end)
    card.save:SetPoint("TOPRIGHT", card.pic, "BOTTOMRIGHT", 3, -6)
    W.Tooltip(card.save, "Save", "Keep it in Saved on your profile. Only you see what you save.")

    card.likes = CreateFrame("Button", nil, card)
    card.likes:SetSize(w, 16)
    card.likes:SetPoint("TOPLEFT", card.pic, "BOTTOMLEFT", 0, -42)
    card.likes.text = W.Text(card.likes, 12)
    card.likes.text:SetPoint("LEFT")
    W.Tooltip(card.likes, "Likes", function()
        local post = card.post
        if not post then return nil end
        local names = {}
        for i, l in ipairs(S.Likers(post)) do
            if i > 10 then
                names[#names + 1] = "..."
                break
            end
            names[#names + 1] = ns.Display(l.name)
        end
        return #names > 0 and table.concat(names, "\n") or nil
    end)

    card.caption = W.Text(card, 12)
    card.caption:SetPoint("TOPLEFT", card.likes, "BOTTOMLEFT", 0, -5)
    card.caption:SetWidth(w)
    card.caption:SetHeight(30)
    card.caption:SetJustifyV("TOP")
    card.caption:SetWordWrap(true)

    card.more = W.Flat(card, "", 200, 16, "plain", function() if card.post then onOpen(card.post) end end, 12)
    card.more:SetPoint("TOPLEFT", card.caption, "BOTTOMLEFT", 0, -3)
    card.more.label:ClearAllPoints()
    card.more.label:SetPoint("LEFT")
    card.more.label:SetJustifyH("LEFT")
    card.more:SetStyle("plain")
    card.more.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)
    card.more:SetScript("OnLeave", function(self) self.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1) end)

    -- Add a comment, right under the post.
    local function Send(text)
        if card.post and strtrim(text) ~= "" then
            S.Comment(card.post.id, text)
            ns.Bots.Reply(card.post)
            card.comment:SetText("")
        end
    end
    card.comment = W.Input(card, w - 50, 28, "Add a comment...", S.MAX_COMMENT, Send, function(text)
        card.send:SetShown(strtrim(text) ~= "")
    end)
    card.comment:SetPoint("TOPLEFT", card.more, "BOTTOMLEFT", 0, -6)
    card.send = W.Flat(card, "Post", 46, 28, "link", function() Send(card.comment:GetText() or "") end)
    card.send:SetPoint("LEFT", card.comment, "RIGHT", 4, 0)
    card.send:Hide()

    -- The heart and the likes line, now. bounce: pop the heart (just liked).
    function card:ShowLikes(post, bounce)
        if post ~= self.post then return end
        local liked = S.Liked(post)
        self.heart:SetIcon(liked and "Heart" or "HeartOutline", liked and C.red or C.text)
        local disliked = S.Disliked(post)
        self.dislike:SetIcon(disliked and "ThumbDownFill" or "ThumbDown", disliked and C.blue or C.text)
        self.likes.text:SetText(LikesText(post))
        if bounce and liked then self.heart:Bounce() end
    end

    function card:SetPost(post)
        local changed = self.post ~= post or self.lookString ~= post.look
        self.post = post
        self.lookString = post.look
        S.Seen(post.id)
        local prof = S.Profile(post.author)
        local class = post.class or prof.class
        self.face:SetPlayer(post.author, class)
        self.name.text:SetText(ns.Display(post.author) .. W.Hex(C.dim) .. "  \194\183  " .. ns.Ago(post.t) .. "|r"
            .. (post.share == "guild" and (W.Hex(C.green or C.dim) .. "   guild only|r") or "")
            .. (post.bot and (W.Hex(C.faint) .. "   demo|r") or ""))
        self:ShowLikes(post)
        local saved = S.Saved(post.id)
        self.save:SetIcon(saved and "BookmarkFill" or "Bookmark")
        self.caption:SetText(post.caption ~= "" and F.NameLine(post.author, class, post.caption) or "")
        local n = #S.Comments(post)
        self.more:SetText(n == 0 and "No comments yet" or n == 1 and "View 1 comment" or ("View all " .. n .. " comments"))
        local mine = S.IsMine(post)
        local items = {
            { "Go to post", function() onOpen(post) end },
            { "Try this look", function() ns.Studio.Remix(post) end },
            { S.Following(post.author) and "Unfollow" or "Follow", function()
                S.Follow(post.author, not S.Following(post.author))
            end, shown = not mine, danger = S.Following(post.author) },
            { "About this account", function() ns.UI:OpenPerson(post.author) end },
            { "Block " .. ns.Display(post.author), function() ns.UI:ConfirmBlock(post.author) end, shown = not mine, danger = true },
            { "Save to computer", function() ns.Picture.SaveToComputer(post) end },
        }
        self.menu:Set(items)
        if changed then self.pic:SetLook(post.look, post.author) end
        self:Show()
    end
    return card
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
function F.New(parent)
    local view = { filter = "all" }
    local UI = ns.UI

    -- Feed tabs.
    local tabs = W.Tabs(parent, {
        { key = "all", label = "Realm" }, { key = "guild", label = "Guild" }, { key = "following", label = "Following" },
    }, function(key)
        view.filter = key
        view:Refresh()
        view.scroll:Top()
    end, { size = 13 })
    tabs.buttons[1]:SetPoint("TOPLEFT", COL_X - 10, -6)
    view.tabs = tabs
    view.feedButtons = tabs.buttons
    W.Tooltip(tabs.buttons[1], "Realm", "Everyone on the realm with Wowstagram: friends first, then people you follow, your guild, and people you've seen lately.")
    W.Tooltip(tabs.buttons[2], "Guild", function()
        return S.HasGuild() and "Only people in your guild (and you)." or "You're not in a guild."
    end)
    W.Tooltip(tabs.buttons[3], "Following", "Only the people you follow (and you).")
    -- Tags: a box at the top of the wall. Click in: the most used tags;
    -- type: the ones that match; pick one: the wall shows its pictures (the
    -- box says which, and its X goes back to Realm).
    local box = W.Input(parent, 130, 26, "#  Search tags", 30, function(text)
        local tag = strtrim(text or ""):gsub("^#", ""):lower()
        if tag ~= "" then view:ShowTag(tag) end
    end, function() view:TagList() end)
    box:SetPoint("TOPRIGHT", parent, "TOPLEFT", COL_X + COL_W, -8)
    view.tagBox = box
    view.tagClear = W.Glyph(parent, "Close", 10, function()
        view.filter = "all"
        box:SetText("")
        box:ClearFocus()
        view:Refresh()
        view.scroll:Top()
    end)
    view.tagClear:SetPoint("RIGHT", box, "RIGHT", -6, 0)
    view.tagClear:SetFrameLevel(box:GetFrameLevel() + 3)
    W.Tooltip(view.tagClear, "Back to the Realm feed")
    view.tagClear:Hide()

    local drop = CreateFrame("Frame", nil, parent)
    drop:SetFrameStrata("DIALOG")
    drop:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
    drop:SetWidth(190)
    W.Rounded(drop, C.raised, 10)
    drop:EnableMouse(true)
    drop.rows = {}
    for i = 1, 7 do
        local r = W.Flat(drop, "", 182, 26, "plain", function(self)
            if self.tag then view:ShowTag(self.tag) end
        end, 12)
        r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 28)
        drop.rows[i] = r
    end
    drop.none = W.Text(drop, 11, C.dim)
    drop.none:SetPoint("TOPLEFT", 10, -10)
    drop:Hide()
    view.tagDrop = drop

    -- The list under the box: the most used tags, or those matching.
    function view:TagList()
        if not box:HasFocus() then return drop:Hide() end
        local q = strtrim(box:GetText() or ""):gsub("^#", ""):lower()
        local n = 0
        for _, t in ipairs(S.AllTags()) do
            if n >= #drop.rows then break end
            if q == "" or t.tag:find(q, 1, true) then
                n = n + 1
                local r = drop.rows[n]
                r.tag = t.tag
                r:SetText("#" .. t.tag .. W.Hex(C.dim) .. "  9483  " .. t.n .. (t.n == 1 and " picture" or " pictures") .. "|r")
                r:Show()
            end
        end
        for i = n + 1, #drop.rows do drop.rows[i]:Hide() end
        drop.none:SetText(n == 0 and (q == "" and "No tags yet." or "No tag like that.") or "")
        drop:SetHeight(math.max(1, n) * 28 + 8)
        drop:Show()
    end
    box:HookScript("OnEditFocusGained", function() view:TagList() end)
    box:HookScript("OnEditFocusLost", function()
        -- (a moment later, so a click on the list still lands)
        ns.After(0.2, function() if not box:HasFocus() then drop:Hide() end end)
    end)

    function view:ShowTag(tag)
        self.filter = "#" .. tag
        box:SetText("#" .. tag)
        box:ClearFocus()
        drop:Hide()
        self:Refresh()
        self.scroll:Top()
    end
    local tabLine = W.Line(parent)
    tabLine:SetPoint("TOPLEFT", COL_X, -38)
    tabLine:SetWidth(COL_W)

    -- The wall: everything under the tabs scrolls.
    local wall = CreateFrame("Frame", nil, parent)
    wall:SetPoint("TOPLEFT", COL_X - 6, -39)
    wall:SetPoint("BOTTOMLEFT", COL_X - 6, 0)
    wall:SetWidth(COL_W + 12)

    -- Stories (the top of the wall): you first ("Your story" makes a
    -- picture), then everyone who posted today, the ones you haven't seen first.
    local STORIES_H = 108
    local storyBar = CreateFrame("Frame", nil, wall)
    view.stories = {}
    local SW = 58
    for i = 1, 7 do
        local s = CreateFrame("Frame", nil, storyBar)
        s:SetSize(SW, 76)
        s:SetPoint("TOPLEFT", 6 + (i - 1) * SW, -12)
        s.avatar = W.Avatar(s, 54)
        s.avatar:SetPoint("TOP")
        s.label = W.Text(s, 10, C.text)
        s.label:SetPoint("TOP", s.avatar, "BOTTOM", 0, -3)
        s.label:SetWidth(SW)
        s.label:SetJustifyH("CENTER")
        s.label:SetWordWrap(false)
        if i == 1 then
            local plus = CreateFrame("Frame", nil, s.avatar)
            plus:SetSize(18, 18)
            plus:SetPoint("BOTTOMRIGHT", 0, 0)
            W.Icon(plus, "Circle", 18, C.bg):SetAllPoints()
            local dot = W.Icon(plus, "Circle", 14, C.blue)
            dot:SetPoint("CENTER")
            local p = W.Text(plus, 12, { 1, 1, 1 })
            p:SetPoint("CENTER", 0, 1)
            p:SetText("+")
            s.avatar:SetScript("OnClick", function() UI:Show("studio") end)
            W.Tooltip(s.avatar, "Your story", "Take a picture.")
        else
            s.avatar:SetScript("OnClick", function()
                if s.story then UI:OpenPost(s.story.post.id) end
            end)
        end
        view.stories[i] = s
    end
    local storyLine = W.Line(storyBar)
    storyLine:SetPoint("BOTTOMLEFT", 6, 8)
    storyLine:SetWidth(COL_W)

    -- The posts, one under the other.
    view.cards = {}
    view.list = {}
    view.scroll = ns.Scroller.New(wall, {
        header = storyBar, headerH = STORIES_H, rowH = ROW_H, bottom = 20,
        count = function() return #view.list end,
        build = function(row)
            row.card = F.Card(row, COL_W, PIC_H, function(post) UI:OpenPost(post.id) end, parent)
            row.card:SetPoint("TOPLEFT", 6, 0)
            row.pics = { row.card.pic }
            view.cards[#view.cards + 1] = row.card
        end,
        fill = function(row, index)
            local post = view.list[index]
            if post then
                if row.card.post ~= post then row.card.comment:SetText("") end
                row.card:SetPost(post)
            end
        end,
    })

    view.empty = W.Text(parent, 14, C.dim)
    view.empty:SetPoint("TOP", parent, "TOPLEFT", COL_X + COL_W / 2, -260)
    view.empty:SetWidth(COL_W - 40)
    view.empty:SetJustifyH("CENTER")
    view.emptyButton = W.Flat(parent, "Create a picture", 150, 32, "primary", function() UI:Show("studio") end)
    view.emptyButton:SetPoint("TOP", view.empty, "BOTTOM", 0, -16)

    -- Right column: you, then people to follow.
    local side = CreateFrame("Frame", nil, parent)
    side:SetPoint("TOPLEFT", SIDE_X, -14)
    side:SetSize(SIDE_W, UI.MAIN_H - 28)
    view.me = W.Avatar(side, 44)
    view.me:SetPoint("TOPLEFT", 0, 0)
    view.me:SetScript("OnClick", function() UI:Show("profile") end)
    view.meName = W.Text(side, 13)
    view.meName:SetPoint("TOPLEFT", view.me, "TOPRIGHT", 10, -8)
    view.meName:SetWidth(SIDE_W - 60)
    view.meName:SetWordWrap(false)
    view.meWho = W.Text(side, 11, C.dim)
    view.meWho:SetPoint("TOPLEFT", view.meName, "BOTTOMLEFT", 0, -3)
    view.meWho:SetWidth(SIDE_W - 60)
    view.meWho:SetWordWrap(false)

    local sugTitle = W.Text(side, 12, C.dim)
    sugTitle:SetPoint("TOPLEFT", 0, -66)
    sugTitle:SetText("Suggested for you")
    view.suggest = {}
    for i = 1, 5 do
        local r = CreateFrame("Frame", nil, side)
        r:SetSize(SIDE_W, 44)
        r:SetPoint("TOPLEFT", 0, -88 - (i - 1) * 46)
        r.avatar = W.Avatar(r, 34)
        r.avatar:SetPoint("LEFT")
        r.name = W.Text(r, 12)
        r.name:SetPoint("TOPLEFT", r.avatar, "TOPRIGHT", 10, -4)
        r.name:SetWidth(SIDE_W - 110)
        r.name:SetWordWrap(false)
        r.why = W.Text(r, 10, C.dim)
        r.why:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        r.why:SetWidth(SIDE_W - 110)
        r.why:SetWordWrap(false)
        r.follow = W.Flat(r, "Follow", 60, 24, "link", function()
            if r.who then S.Follow(r.who, not S.Following(r.who)) end
        end)
        r.follow:SetPoint("RIGHT", 4, 0)
        r.avatar:SetScript("OnClick", function() if r.who then UI:OpenPerson(r.who) end end)
        view.suggest[i] = r
    end
    view.noSuggest = W.Text(side, 11, C.faint)
    view.noSuggest:SetPoint("TOPLEFT", 0, -90)
    view.noSuggest:SetText("You follow everyone here.")
    local foot = W.Text(side, 9, C.faint)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetWidth(SIDE_W)
    foot:SetText("About  \194\183  Help  \194\183  /wgram\n\n\194\169 2026 WOWSTAGRAM")

    function view:Open() end

    function view:Refresh()
        -- Tabs.
        if self.filter == "guild" and not S.HasGuild() then self.filter = "all" end
        tabs:Select(self.filter)
        tabs.buttons[2]:SetEnabled(S.HasGuild())

        -- Stories.
        local stories = S.Stories()
        local me = self.stories[1]
        me.avatar:SetPlayer(ns.Me(), select(2, UnitClass("player")))
        me.label:SetText("Your story")
        for i = 2, #self.stories do
            local s, st = self.stories[i], stories[i - 1]
            s.story = st
            if st then
                s.avatar:SetPlayer(st.author, st.class, st.seen and "seen" or "new")
                s.label:SetText(ns.Display(st.author):match("^(%S+)") or ns.Display(st.author))
                s.label:SetTextColor(st.seen and C.dim[1] or 1, st.seen and C.dim[2] or 1, st.seen and C.dim[3] or 1, 1)
                s:Show()
            else
                s:Hide()
            end
        end

        -- The wall: the Realm feed ranked (S.Feed), a tag's pictures, or the
        -- Guild and Following feeds newest first.
        local tag = self.filter:sub(1, 1) == "#"
        self.tagClear:SetShown(tag)
        if not tag and not self.tagBox:HasFocus() and (self.tagBox:GetText() or ""):sub(1, 1) == "#" then
            self.tagBox:SetText("")
        end
        self.list = self.filter == "all" and S.Feed() or S.List(self.filter)
        self.scroll:Refresh()
        if #self.list == 0 then
            local EMPTY = {
                following = "Nothing here yet. Follow people from their profile and their pictures show up here.",
                guild = "No pictures from your guild yet. Be the first!",
            }
            self.empty:SetText(EMPTY[self.filter] or "No pictures yet. Be the first!")
            self.empty:Show()
            self.emptyButton:SetShown(self.filter ~= "following")
        else
            self.empty:Hide()
            self.emptyButton:Hide()
        end

        -- You.
        local myClass = select(2, UnitClass("player"))
        self.me:SetPlayer(ns.Me(), myClass)
        self.meName:SetText(ns.Display(ns.Me()))
        local prof = S.MyProfile()
        self.meWho:SetText(string.format("Level %d %s", prof.level or 0, prof.raceName or ""))

        -- Suggested.
        local sug = S.Suggested(#self.suggest)
        for i, r in ipairs(self.suggest) do
            local s = sug[i]
            r.who = s and s.name
            if s then
                r.avatar:SetPlayer(s.name, s.class)
                r.name:SetText(ns.Display(s.name))
                r.why:SetText(S.InGuild(s.name) and "In your guild" or (ns.Bots.Is(s.name) and "Demo person")
                    or "Posts on the realm")
                local on = S.Following(s.name)
                r.follow:SetText(on and "Following" or "Follow")
                r.follow:SetStyle(on and "plain" or "link")
                r:Show()
            else
                r:Hide()
            end
        end
        self.noSuggest:SetShown(#sug == 0)
    end

    return view
end
