-- A post, like Instagram's desktop post view: the picture on the left; on
-- the right who posted it (with Follow and a "..." menu), the caption, the
-- comments, the heart / comment / save row, the likes, when, every piece of
-- the outfit (hover for the item: shop the look), and "Add a comment".
-- Your own pictures can be edited or deleted from the menu.
local _, ns = ...

local W = ns.Widgets
local C = W.C
local L = ns.Look
local S = ns.Social
local PP = {}
ns.PostPage = PP

local function When(t)
    local d = ns.Now() - (t or 0)
    if d < 60 then return "JUST NOW" end
    if d < 3600 then local n = math.floor(d / 60) return n .. (n == 1 and " MINUTE AGO" or " MINUTES AGO") end
    if d < 86400 then local n = math.floor(d / 3600) return n .. (n == 1 and " HOUR AGO" or " HOURS AGO") end
    local n = math.floor(d / 86400)
    return n .. (n == 1 and " DAY AGO" or " DAYS AGO")
end

function PP.New(parent)
    local view = {}
    local UI = ns.UI
    local PW = 360
    local PH = math.floor(PW * L.ASPECT)
    local RW = UI.MAIN_W - PW

    view.pic = ns.Picture.New(parent, PW, PH, {
        badge = "full",
        onClick = function()
            local now = GetTime()
            if view.post and now - (view.lastClick or 0) < 0.35 then
                ns.Feed.DoubleLike(view.post, view.pop, function(_, bounce) view:ShowLikes(bounce) end)
                view.lastClick = 0
            else
                view.lastClick = now
            end
        end,
    })
    view.pic:SetPoint("LEFT")
    view.pop = ns.Feed.HeartPop(view.pic.over)

    local right = CreateFrame("Frame", nil, parent)
    right:SetPoint("TOPLEFT", PW, 0)
    right:SetPoint("BOTTOMRIGHT")
    local function HLine(y, fromBottom)
        local l = W.Line(right)
        l:SetPoint(fromBottom and "BOTTOMLEFT" or "TOPLEFT", 0, y)
        l:SetPoint(fromBottom and "BOTTOMRIGHT" or "TOPRIGHT", 0, y)
        return l
    end

    -- Header.
    view.face = W.Avatar(right, 32)
    view.face:SetPoint("TOPLEFT", 14, -12)
    view.name = CreateFrame("Button", nil, right)
    view.name:SetSize(150, 20)
    view.name:SetPoint("LEFT", view.face, "RIGHT", 10, 0)
    view.name.text = W.Text(view.name, 13)
    view.name.text:SetPoint("LEFT")
    view.name.text:SetWordWrap(false)
    local function Person() if view.post then UI:OpenPerson(view.post.author) end end
    view.name:SetScript("OnClick", Person)
    view.face:SetScript("OnClick", Person)
    view.follow = W.Flat(right, "Follow", 70, 24, "link", function()
        local who = view.post and view.post.author
        if who then S.Follow(who, not S.Following(who)) end
    end)
    view.follow:SetPoint("LEFT", view.name.text, "RIGHT", 4, 0)
    view.close = W.Glyph(right, "Close", 16, function() UI:Back() end)
    view.close:SetPoint("TOPRIGHT", -8, -14)
    W.Tooltip(view.close, "Close")
    view.dots = W.Glyph(right, "Dots", 18, function(self) view.menu:Toggle(self) end)
    view.dots:SetPoint("RIGHT", view.close, "LEFT", -6, 0)
    view.menu = W.Menu(right, 180)
    HLine(-56)

    -- Caption (the poster's own words, above the comments).
    view.capFace = W.Avatar(right, 28)
    view.capFace:SetPoint("TOPLEFT", 14, -68)
    view.caption = W.Text(right, 12)
    view.caption:SetPoint("TOPLEFT", view.capFace, "TOPRIGHT", 10, -2)
    view.caption:SetWidth(RW - 70)
    view.caption:SetJustifyV("TOP")
    view.capWhen = W.Text(right, 10, C.dim)
    view.capWhen:SetPoint("TOPLEFT", view.caption, "BOTTOMLEFT", 0, -4)

    -- Comments.
    local comments = CreateFrame("Frame", nil, right)
    comments:SetPoint("TOPLEFT", 0, -130)
    comments:SetPoint("BOTTOMRIGHT", 0, 178)
    view.list = W.ScrollList(comments, 30, function(row)
        row.face = W.Avatar(row, 28)
        row.face:SetPoint("TOPLEFT", 14, -4)
        row.text = W.Text(row, 12)
        row.text:SetPoint("TOPLEFT", row.face, "TOPRIGHT", 10, -2)
        row.text:SetPoint("RIGHT", -34, 0)
        row.text:SetJustifyV("TOP")
        row.when = W.Text(row, 10, C.dim)
        row.when:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
        row.del = W.Glyph(row, "Close", 10, nil, C.dim)
        row.del:SetPoint("TOPRIGHT", -12, -6)
        W.Tooltip(row.del, "Delete comment")
    end)
    view.list:Inset(0, 0, 0, 0)
    view.noComments = W.Text(comments, 12, C.faint)
    view.noComments:SetPoint("TOP", 0, -20)
    view.noComments:SetText("No comments yet. Start the conversation.")

    HLine(178, true)
    -- Heart, comment, save.
    view.heart = W.Glyph(right, "HeartOutline", 24, function()
        ns.Feed.ToggleLike(view.post, function(_, on) view:ShowLikes(on) end)
    end)
    view.heart:SetPoint("BOTTOMLEFT", 10, 140)
    view.dislike = W.Glyph(right, "ThumbDown", 23, function()
        ns.Feed.ToggleDislike(view.post, function() view:ShowLikes() end)
    end)
    view.dislike:SetPoint("LEFT", view.heart, "RIGHT", 8, 0)
    W.Tooltip(view.dislike, "Dislike", "A thumbs down. Liking it again takes the dislike back.")
    view.bubble = W.Glyph(right, "Bubble", 23, function() view.commentBox:SetFocus() end)
    view.bubble:SetPoint("LEFT", view.dislike, "RIGHT", 8, 0)
    view.save = W.Glyph(right, "Bookmark", 23, function()
        if view.post then S.Save(view.post.id, not S.Saved(view.post.id)) end
    end)
    view.save:SetPoint("BOTTOMRIGHT", -10, 140)
    view.likes = W.Text(right, 12)
    view.likes:SetPoint("BOTTOMLEFT", 14, 122)
    view.likes:SetWidth(RW - 28)
    view.likes:SetWordWrap(false)
    view.when = W.Text(right, 9, C.dim)
    view.when:SetPoint("BOTTOMLEFT", 14, 106)

    -- The outfit: every piece, with its tooltip.
    view.lookLabel = W.Text(right, 10, C.dim)
    view.lookLabel:SetPoint("BOTTOMLEFT", 14, 84)
    view.lookLabel:SetText("THE LOOK")
    -- A group picture: whose look (the poster first). Click a name.
    view.whoLook = 0
    view.lookNames = {}
    for i = 1, L.MAX_PEOPLE do
        local b = W.Flat(right, "", 60, 18, "link", function(self)
            view.whoLook = self.index
            view:Refresh()
        end, 10)
        b.index = i - 1
        b:Hide()
        view.lookNames[i] = b
    end
    view.items = {}
    for i = 1, #L.SLOTS do
        local b = CreateFrame("Button", nil, right)
        b:SetSize(22, 22)
        b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 23, 56)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local item = ns.Picture.SlotItem(self.entry)
            if item and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(item)
            else
                GameTooltip:SetText(L.SLOT[self.slot].name, 1, 1, 1)
                GameTooltip:AddLine("This client doesn't know which item this appearance comes from.", 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        -- Shift-click: link it in chat, like any item.
        b:SetScript("OnClick", function(self)
            local item = ns.Picture.SlotItem(self.entry)
            if not item then return end
            local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(item)
            if link and IsModifiedClick and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
        view.items[i] = b
    end
    view.noItems = W.Text(right, 11, C.faint)
    view.noItems:SetPoint("BOTTOMLEFT", 14, 60)
    view.noItems:SetText("Nothing on but a smile.")

    HLine(44, true)
    -- Add a comment.
    local function Send(text)
        if view.post and strtrim(text) ~= "" then
            S.Comment(view.post.id, text)
            ns.Bots.Reply(view.post)
            view.commentBox:SetText("")
            view.scrollEnd = true
        end
    end
    ns.Feed.Linkable(right)
    view.commentBox = W.Input(right, RW - 76, 30, "Add a comment...", S.MAX_COMMENT, Send)
    view.commentBox:SetPoint("BOTTOMLEFT", 10, 7)
    view.send = W.Flat(right, "Post", 50, 30, "link", function() Send(view.commentBox:GetText() or "") end)
    view.send:SetPoint("BOTTOMRIGHT", -8, 7)

    view.gone = W.Text(parent, 16, C.dim)
    view.gone:SetPoint("CENTER")
    view.gone:SetText("This picture was deleted.")

    function view:Open(id)
        self.id = id
        self.post = nil
        self.scrollEnd = false
        self.menu:Hide()
        self.list:ScrollToTop()
    end

    -- The heart and "Liked by ...", now. bounce: pop the heart (just liked).
    function view:ShowLikes(bounce)
        local post = self.post
        if not post then return end
        local liked = S.Liked(post)
        self.heart:SetIcon(liked and "Heart" or "HeartOutline", liked and C.red or C.text)
        local disliked = S.Disliked(post)
        self.dislike:SetIcon(disliked and "ThumbDownFill" or "ThumbDown", disliked and C.blue or C.text)
        local d = S.Dislikes(post)
        local dis = d > 0 and (W.Hex(C.dim) .. "  \194\183  " .. ns.Count(d) .. (d == 1 and " dislike" or " dislikes") .. "|r") or ""
        local likers = S.Likers(post)
        if #likers == 0 then
            self.likes:SetText((d > 0 and "No likes" or "Be the first to like this") .. dis)
        elseif #likers == 1 then
            self.likes:SetText("Liked by " .. ns.Display(likers[1].name) .. dis)
        else
            self.likes:SetText("Liked by " .. ns.Display(likers[1].name) .. " and " .. (#likers - 1)
                .. (#likers == 2 and " other" or " others") .. dis)
        end
        if bounce and liked then self.heart:Bounce() end
    end

    function view:Refresh()
        local post = S.Find(self.id or "")
        local was = self.post
        self.post = post
        self.gone:SetShown(post == nil)
        self.pic:SetShown(post ~= nil)
        right:SetShown(post ~= nil)
        if not post then return end
        S.Seen(post.id)
        if was ~= post or self.lookString ~= post.look then
            self.lookString = post.look
            self.pic:SetLook(post.look, post.author)
        end
        local prof = S.Profile(post.author)
        local class = post.class or prof.class
        local mine = S.IsMine(post)
        self.face:SetPlayer(post.author, class)
        self.name.text:SetText(ns.Display(post.author))
        self.follow:SetShown(not mine)
        local following = S.Following(post.author)
        self.follow:SetText("\194\183  " .. (following and "Following" or "Follow"))
        self.follow:SetStyle(following and "plain" or "link")

        self.capFace:SetPlayer(post.author, class)
        self.caption:SetText(post.caption ~= "" and ns.Feed.NameLine(post.author, class, post.caption)
            or (ns.ColorName(post.author, class) .. W.Hex(C.faint) .. "  no caption|r"))
        self.capWhen:SetText(ns.Ago(post.t) .. ((post.edited or 0) > 0 and "  \194\183  edited" or "")
            .. (post.share == "guild" and "  \194\183  guild only" or "")
            .. (post.bot and "  \194\183  demo person" or ""))

        self:ShowLikes()
        self.save:SetIcon(S.Saved(post.id) and "BookmarkFill" or "Bookmark")
        self.when:SetText(When(post.t))

        -- The menu: everyone can try the look; only you edit or delete.
        self.menu:Set({
            { "Try this look", function() ns.Studio.Remix(post, self.whoLook) end },
            { "Edit", function() ns.Studio.Edit(post) end, shown = mine },
            { "Delete", function()
                W.Confirm("Delete this picture for everyone?", function()
                    S.Delete(post.id)
                    UI:Back()
                end)
            end, danger = true, shown = mine },
            { "Go to profile", Person },
            { "Save to computer", function() ns.Picture.SaveToComputer(post) end },
            { "Block " .. ns.Display(post.author), function()
                ns.UI:ConfirmBlock(post.author)
            end, danger = true, shown = not mine },
        })
        self.remix, self.edit, self.delete = self.menu.rows[1], self.menu.rows[2], self.menu.rows[3]

        local look = L.Decode(post.look)
        -- Whose look: the poster (0) or someone else in the picture.
        if self.lookFor ~= post.id then self.lookFor, self.whoLook = post.id, 0 end
        local people = look.people or {}
        if self.whoLook > #people then self.whoLook = 0 end
        local x = 14 + (self.lookLabel.GetStringWidth and self.lookLabel:GetStringWidth() or 60) + 10
        for i, b in ipairs(self.lookNames) do
            local who = i == 1 and post.author or (people[i - 1] and people[i - 1].name)
            if #people > 0 and (i == 1 or people[i - 1]) then
                local name = who and ns.Display(who) or "?"
                name = name:match("^(%S+)") or name
                b:SetText(name)
                local tw = b.label and b.label.GetStringWidth and b.label:GetStringWidth() or (#name * 6)
                b:SetWidth(math.max(24, tw + 12))
                b:ClearAllPoints()
                b:SetPoint("LEFT", self.lookLabel, "LEFT", x - 14, 0)
                x = x + b:GetWidth() + 2
                b:SetStyle(b.index == self.whoLook and "light" or "link")
                b:Show()
            else
                b:Hide()
            end
        end
        local chosen = self.whoLook == 0 and look or people[self.whoLook]
        local n = 0
        for _, def in ipairs(L.SLOTS) do
            local s = chosen.slots[def.id]
            if s then
                n = n + 1
                local b = self.items[n]
                b.slot, b.entry = def.id, s
                b.icon:SetTexture(ns.Picture.SlotIcon(s))
                b:Show()
            end
        end
        for i = n + 1, #self.items do self.items[i]:Hide() end
        self.noItems:SetShown(n == 0)

        local list = self.list
        local comments = S.Comments(post)
        for i, c in ipairs(comments) do
            local row = list:Row(i)
            row.face:SetPlayer(c.author, c.class)
            row.text:SetText(ns.Feed.NameLine(c.author, c.class, c.text))
            row.when:SetText(ns.Ago(c.t))
            local h = row.text.GetStringHeight and row.text:GetStringHeight()
            row:SetHeight(math.max(40, (h or 14) + 26))
            row.del:SetShown(c.author == ns.Me())
            row.del:SetScript("OnClick", function() S.DeleteComment(post.id, c.author, c.t) end)
        end
        list:SetCount(#comments)
        self.noComments:SetShown(#comments == 0)
        if self.scrollEnd then
            self.scrollEnd = false
            ns.After(0, function() list:ScrollToEnd() end)
        end
    end

    return view
end
