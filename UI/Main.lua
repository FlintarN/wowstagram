-- Main window: the game's own portrait window (ButtonFrameTemplate) with the
-- Wowstagram logo beside the camera portrait, and inside it Instagram's desktop
-- layout: a sidebar on the left (Home, Create, Notifications, Profile,
-- Settings) and the page on the right.
--
-- Pages: feed, studio, activity, profile, settings, and two that open from
-- others: post (one picture, with comments) and person (someone's profile).
local _, ns = ...

local W = ns.Widgets
local C = W.C
local UI = {}
ns.UI = UI

UI.WIDTH, UI.HEIGHT = 880, 700
UI.SIDE_W = 180
-- The page area, right of the sidebar.
UI.MAIN_W, UI.MAIN_H = UI.WIDTH - 10 - UI.SIDE_W - 1, UI.HEIGHT - 64

UI.pages = {}
UI.nav = {}

local NAV = {
    { key = "feed", label = "Home", icon = "Home", on = "HomeFill" },
    { key = "search", label = "Search", icon = "Search" },
    { key = "studio", label = "Create", icon = "Plus" },
    { key = "activity", label = "Notifications", icon = "HeartOutline", on = "Heart" },
    { key = "profile", label = "Profile", icon = "User" },
}

---------------------------------------------------------------------------
-- Pages and navigation
---------------------------------------------------------------------------
-- key: a page, or "post" (arg = post id) or "person" (arg = id).
function UI:Show(key, arg)
    self:Build()
    self.frame:Show()
    self:Select(key, arg)
end

-- Switch page without opening the window.
function UI:Select(key, arg)
    if key == "post" or key == "person" then
        if self.tab ~= key then self.back = self.tab end
    else
        self.back = nil
    end
    self.tab = key
    self.arg = arg
    if key == "activity" then ns.my.unread = 0 end
    for k, page in pairs(self.pages) do page.frame:SetShown(k == key) end
    local page = self.pages[key]
    if page.view.Open then page.view:Open(arg) end
    W.PlaySound("IG_CHARACTER_INFO_TAB")
    self:Refresh()
end

function UI:Back()
    self:Show(self.back or "feed")
end

function UI:OpenPost(id)
    self:Show("post", id)
end

-- Block someone, after asking.
function UI:ConfirmBlock(name)
    W.Confirm("Block " .. ns.Display(name) .. "? You won't see their pictures, comments, likes or dislikes anywhere. "
        .. "They aren't told. Settings can unblock them.", function()
        ns.Social.Block(name, true)
        ns.Print("Blocked " .. ns.Display(name) .. ".")
    end)
end

function UI:OpenPerson(name)
    if name == ns.Me() then return self:Show("profile") end
    self:Show("person", name)
end

-- Someone liked or commented on your picture.
function UI:Ping()
    ns.my.unread = (ns.my.unread or 0) + 1
    if self.frame and self.frame:IsShown() and self.tab == "activity" then ns.my.unread = 0 end
    W.PlaySound("IG_QUEST_LIST_SELECT")
    self:Refresh()
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------
local function NavItem(parent, item)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(UI.SIDE_W - 16, 44)
    b.hover = W.Rounded(b, C.surface, 8)
    b.hover:SetShown(false)
    if item.key == "profile" then
        b.avatar = W.Avatar(b, 26)
        b.avatar:SetPoint("LEFT", 10, 0)
        b.avatar:EnableMouse(false)
    else
        b.icon = W.Icon(b, item.icon, 24)
        b.icon:SetPoint("LEFT", 11, 0)
    end
    b.label = W.Text(b, 14, C.text)
    b.label:SetPoint("LEFT", 48, 0)
    b.label:SetText(item.label)
    -- New likes and comments: a red dot with a number.
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(18, 18)
    b.badge:SetPoint("LEFT", 26, 8)
    W.Icon(b.badge, "Circle", 18, C.red):SetAllPoints()
    b.badge.text = W.Text(b.badge, 10, { 1, 1, 1 })
    b.badge.text:SetPoint("CENTER", 0, 0)
    b.badge:Hide()
    b:SetScript("OnEnter", function(self) self.hover:SetShown(true) end)
    b:SetScript("OnLeave", function(self) self.hover:SetShown(self.selected == true) end)
    b:SetScript("OnClick", function() UI:Show(item.key) end)
    b.key = item.key
    function b:SetSelected(on)
        self.selected = on
        self.hover:SetShown(on)
        if self.icon then self.icon:SetTexture(W.ART .. ((on and item.on) or item.icon)) end
        local c = on and C.text or { 0.85, 0.85, 0.85 }
        self.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    function b:SetCount(n)
        self.badge.text:SetText(n and n > 0 and (n > 9 and "9+" or tostring(n)) or "")
        self.badge:SetShown(n ~= nil and n > 0)
    end
    return b
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
function UI:ApplyScale()
    if self.frame and not self.full then self.frame:SetScale(ns.db.scale or 1) end
    ns.Picture.RefreshAll()
end

-- Fullscreen: the window grows to fill the screen (scaled, so everything
-- keeps its place), centred, over a dark backdrop. Remembered until you
-- switch it off with the same button.
function UI:ApplyFull()
    local f = self.frame
    if not f then return end
    if not self.backdrop then
        local bd = CreateFrame("Frame", nil, UIParent)
        bd:SetAllPoints(UIParent)
        bd:SetFrameStrata("MEDIUM")
        bd:SetFrameLevel(500)
        bd:EnableMouse(true) -- no clicking the world behind it
        W.Fill(bd, C.bg, 0.92)
        bd:Hide()
        self.backdrop = bd
    end
    local on = ns.db.fullscreen == true
    self.full = on
    self.backdrop:SetShown(on and f:IsShown())
    local before = f:GetScale()
    f:ClearAllPoints()
    if on then
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        f:SetScale(math.min(sw / UI.WIDTH, sh / UI.HEIGHT) * 0.97)
        f:SetPoint("CENTER", UIParent, "CENTER")
    else
        f:SetScale(ns.db.scale or 1)
        local pos = ns.db.windowPos
        if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
    end
    if self.fullButton and self.fullButton.Sync then self.fullButton:Sync(on) end
    if math.abs(f:GetScale() - before) > 0.001 then ns.Picture.RefreshAll() end
end

function UI:ToggleFull()
    ns.db.fullscreen = not ns.db.fullscreen
    self:ApplyFull()
end

-- The two buttons top right, made to match each other (Art\RedButton, a
-- gold icon on red): fullscreen (one window, or two stacked windows to go
-- back, like a web browser) and close (a cross). The game's own close
-- button is hidden; ours takes its place.
local function RedButton(f, size, onClick)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(size, size)
    b.base = b:CreateTexture(nil, "BACKGROUND")
    b.base:SetAllPoints()
    b.base:SetTexture(W.ART .. "RedButton")
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetPoint("CENTER")
    b.glyph:SetSize(size * 0.62, size * 0.62)
    b.glyph:SetVertexColor(1, 0.82, 0.1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.18)
    b:SetScript("OnMouseDown", function(self) self.glyph:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.glyph:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", function()
        W.PlaySound("U_CHAT_SCROLL_BUTTON")
        onClick()
    end)
    return b
end

local function CornerButtons(f)
    local close = f.CloseButton or _G[(f:GetName() or "") .. "CloseButton"]
    if type(close) ~= "table" then close = nil end
    local size = close and close:GetWidth() or 24
    if not size or size < 16 then size = 24 end
    size = size - 2

    local x = RedButton(f, size, function() f:Hide() end)
    x.glyph:SetTexture(W.ART .. "Close")
    x.glyph:SetSize(size * 0.5, size * 0.5)
    if close then
        x:SetPoint("CENTER", close, "CENTER", 0, 0)
        x:SetFrameLevel(close:GetFrameLevel() + 1)
        close:Hide()
    else
        x:SetPoint("TOPRIGHT", -4, -2)
    end
    W.Tooltip(x, "Close", "Escape closes it too.")

    local full = RedButton(f, size, function() UI:ToggleFull() end)
    full:SetFrameLevel(x:GetFrameLevel())
    function full:Sync(on)
        self.glyph:SetTexture(W.ART .. (on and "WindowRestore" or "WindowMax"))
    end
    full:Sync(false)
    full:SetPoint("RIGHT", x, "LEFT", 2, 0) -- (the rims just touch)
    W.Tooltip(full, function() return ns.db.fullscreen and "Window" or "Fullscreen" end,
        function() return ns.db.fullscreen and "Back to the normal window." or "Fill the screen." end)
    return full, x
end

function UI:ResetPosition()
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER")
end

function UI:Build()
    if self.frame then return end
    local f = W.TryCreate("Frame", "WowstagramFrame", UIParent, "ButtonFrameTemplate", "BasicFrameTemplateWithInset")
    f:SetSize(UI.WIDTH, UI.HEIGHT)
    f:SetScale(ns.db.scale or 1)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not UI.full then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        if UI.full then return end
        local point, _, relPoint, x, y = s:GetPoint()
        ns.db.windowPos = { point, relPoint, x, y }
    end)
    local pos = ns.db.windowPos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
    tinsert(UISpecialFrames, "WowstagramFrame") -- Escape closes it
    f:Hide()
    f:SetScript("OnShow", function()
        W.PlaySound("IG_CHARACTER_INFO_OPEN")
        UI:ApplyFull()
        UI:Refresh()
    end)
    f:SetScript("OnHide", function()
        W.PlaySound("IG_CHARACTER_INFO_CLOSE")
        if UI.backdrop then UI.backdrop:Hide() end
    end)

    W.SetTitle(f, "")
    self.fullButton, self.closeButton = CornerButtons(f)
    W.SetPortrait(f, ns.ICON)
    -- The logo, in the space beside the portrait.
    self.logo = W.Text(f, 26, C.text, "logo")
    self.logo:SetPoint("TOPLEFT", 70, -27)
    self.logo:SetText(ns.TITLE)

    -- Black inside, like Instagram's dark theme.
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 6, -60)
    content:SetPoint("BOTTOMRIGHT", -4, 4)
    W.Fill(content, C.bg)
    if f.Inset then f.Inset:Hide() end -- (its grey would sit over the black)
    self.content = content

    -- Sidebar.
    local side = CreateFrame("Frame", nil, content)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(UI.SIDE_W)
    local edge = W.Line(side, true)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    for i, item in ipairs(NAV) do
        local b = NavItem(side, item)
        b:SetPoint("TOPLEFT", 8, -12 - (i - 1) * 48)
        self.nav[#self.nav + 1] = b
    end
    local more = NavItem(side, { key = "settings", label = "Settings", icon = "Gear" })
    more:SetPoint("BOTTOMLEFT", 8, 34)
    self.nav[#self.nav + 1] = more
    self.status = W.Text(side, 10, C.faint)
    self.status:SetPoint("BOTTOMLEFT", 14, 12)
    self.status:SetPoint("RIGHT", -10, 0)
    self.status:SetWordWrap(false)

    -- Page area.
    local main = CreateFrame("Frame", nil, content)
    main:SetPoint("TOPLEFT", UI.SIDE_W + 1, 0)
    main:SetPoint("BOTTOMRIGHT")
    self.main = main

    self.frame = f
    local views = { feed = ns.Feed, search = ns.Search, studio = ns.Studio, activity = ns.Activity, profile = ns.Profile,
        person = ns.Profile, post = ns.PostPage, settings = ns.SettingsPage }
    for _, key in ipairs({ "feed", "search", "studio", "activity", "profile", "person", "post", "settings" }) do
        local p = CreateFrame("Frame", nil, main)
        p:SetAllPoints()
        local page = { frame = p }
        page.view = views[key].New(p, key)
        self.pages[key] = page
    end
    self:Select("feed")
end

function UI:Refresh()
    if not self.frame then return end
    local on = (self.tab == "post" or self.tab == "person") and self.back or self.tab
    for _, b in ipairs(self.nav) do
        b:SetSelected(b.key == on)
        if b.key == "activity" then b:SetCount(ns.my.unread or 0) end
        if b.avatar then b.avatar:SetPlayer(ns.Me(), select(2, UnitClass("player"))) end
    end
    if not self.frame:IsShown() then return end
    if not ns.db.network then
        self.status:SetText("Sharing is off")
    elseif ns.Net.Online() then
        self.status:SetText("|cff58c322" .. "\226\128\162|r Connected to the realm")
    else
        self.status:SetText("Connecting...")
    end
    local page = self.pages[self.tab]
    if page and page.view.Refresh then page.view:Refresh() end
end

function UI:Toggle()
    self:Build()
    self.frame:SetShown(not self.frame:IsShown())
    -- Opening the window on Create starts it fresh, like going to it.
    if self.frame:IsShown() and self.tab == "studio" then self:Select("studio") end
end

ns.OnChange(function() UI:Refresh() end)
