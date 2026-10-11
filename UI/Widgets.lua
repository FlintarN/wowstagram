-- Widgets: Wowstagram's look. The outer window is the game's own (a WoW
-- frame with the camera portrait); everything inside is flat and dark like
-- Instagram's desktop site: black, thin grey lines, white text, blue for the
-- one thing to press, grey for the rest, and line icons (Art\*, made by
-- dev/make_art.py).
local _, ns = ...

local W = {}
ns.Widgets = W

W.ART = "Interface\\AddOns\\Wowstagram\\Art\\"

-- Colours (Instagram's dark theme).
W.C = {
    bg = { 0, 0, 0 },
    surface = { 0.07, 0.07, 0.07 },   -- inputs, hovered rows
    raised = { 0.15, 0.15, 0.15 },    -- secondary buttons, menus
    chip = { 0.21, 0.21, 0.21 },
    line = { 0.15, 0.15, 0.15 },
    text = { 0.96, 0.96, 0.96 },
    dim = { 0.66, 0.66, 0.66 },
    faint = { 0.45, 0.45, 0.45 },
    blue = { 0, 0.58, 0.96 },
    blueHover = { 0.1, 0.47, 0.95 },
    red = { 1, 0.19, 0.25 },
}
local C = W.C

function W.TryCreate(kind, name, parent, template, fallback)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame, true end
    return CreateFrame(kind, name, parent, fallback), false
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local FACES = {
    body = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    logo = "Fonts\\MORPHEUS.TTF",
}
local fonts = {}

-- A font object of this size and face ("body" or "logo"), made once.
function W.Font(size, face)
    face = face or "body"
    local key = face .. size
    if fonts[key] then return fonts[key] end
    local f = CreateFont("WowstagramFont_" .. key)
    if f.SetFont then
        local ok = pcall(f.SetFont, f, FACES[face], size, "")
        if not ok and face ~= "body" then pcall(f.SetFont, f, FACES.body, size, "") end
    end
    fonts[key] = f
    return f
end

-- A line of text. color: one of W.C or {r, g, b}.
function W.Text(parent, size, color, face, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(W.Font(size or 12, face))
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:SetJustifyH("LEFT")
    fs:SetText("")
    return fs
end

-- |cff... for a colour.
function W.Hex(c)
    local function B(v) return math.floor(v * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", B(c[1]), B(c[2]), B(c[3]))
end

---------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------
function W.Fill(frame, color, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

-- A 1-pixel line. Place it with SetPoint; it's horizontal unless vertical.
function W.Line(parent, vertical, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    if vertical then t:SetWidth(1) else t:SetHeight(1) end
    return t
end

-- A thin outline round a frame.
function W.Outline(frame, color, layer)
    color = color or C.line
    local parts = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, layer or "OVERLAY")
        t:SetColorTexture(color[1], color[2], color[3], 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
            t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
            t:SetWidth(1)
        end
        parts[#parts + 1] = t
    end
    return parts
end

-- A rounded rectangle filling a frame (nine slices of Art\Round, so the
-- corners stay round at any size). r: corner radius in pixels.
function W.Rounded(frame, color, r, layer, alpha)
    r = r or 8
    local tex = W.ART .. "Round"
    local q = 0.25 -- the corner is a quarter of the art
    local parts = {}
    local function Part(l, rgt, t, b, p1, x1, y1, p2, x2, y2, w, h)
        local x = frame:CreateTexture(nil, layer or "BACKGROUND")
        x:SetTexture(tex)
        x:SetTexCoord(l, rgt, t, b)
        x:SetPoint(p1, frame, p1, x1, y1)
        if p2 then x:SetPoint(p2, frame, p2, x2, y2) end
        if w then x:SetWidth(w) end
        if h then x:SetHeight(h) end
        parts[#parts + 1] = x
        return x
    end
    Part(0, q, 0, q, "TOPLEFT", 0, 0, nil, 0, 0, r, r)
    Part(1 - q, 1, 0, q, "TOPRIGHT", 0, 0, nil, 0, 0, r, r)
    Part(0, q, 1 - q, 1, "BOTTOMLEFT", 0, 0, nil, 0, 0, r, r)
    Part(1 - q, 1, 1 - q, 1, "BOTTOMRIGHT", 0, 0, nil, 0, 0, r, r)
    Part(q, 1 - q, 0, q, "TOPLEFT", r, 0, "TOPRIGHT", -r, 0, nil, r)
    Part(q, 1 - q, 1 - q, 1, "BOTTOMLEFT", r, 0, "BOTTOMRIGHT", -r, 0, nil, r)
    Part(0, q, q, 1 - q, "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r, r, nil)
    Part(1 - q, 1, q, 1 - q, "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r, r, nil)
    Part(q, 1 - q, q, 1 - q, "TOPLEFT", r, -r, "BOTTOMRIGHT", -r, r)
    local shape = { parts = parts }
    function shape:SetColor(c, a)
        for _, p in ipairs(self.parts) do p:SetVertexColor(c[1], c[2], c[3], a or alpha or 1) end
    end
    function shape:SetShown(on)
        for _, p in ipairs(self.parts) do p:SetShown(on) end
    end
    shape:SetColor(color, alpha)
    return shape
end

function W.Icon(parent, name, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(W.ART .. name)
    if size then t:SetSize(size, size) end
    color = color or C.text
    t:SetVertexColor(color[1], color[2], color[3], 1)
    return t
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- Styles: "primary" (blue), "secondary" (grey), "light" (white, for the
-- chosen chip), "link" (blue text), "plain" (white text), "danger" (red text).
local STYLES = {
    primary = { bg = C.blue, hover = C.blueHover, text = { 1, 1, 1 } },
    secondary = { bg = C.raised, hover = C.chip, text = C.text },
    light = { bg = { 0.94, 0.94, 0.94 }, hover = { 1, 1, 1 }, text = { 0, 0, 0 } },
    link = { text = C.blue, hoverText = { 0.6, 0.85, 1 } },
    plain = { text = C.text, hoverText = C.dim },
    danger = { text = C.red, hoverText = { 1, 0.5, 0.5 } },
}

function W.Flat(parent, text, w, h, style, onClick, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 30)
    b.shape = W.Rounded(b, C.raised, math.min(8, (h or 30) / 2))
    b.label = W.Text(b, size or 12, C.text)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b:SetFontString(b.label)
    b:SetText(text or "")
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    local function Paint(hover)
        local s = STYLES[b.style] or STYLES.secondary
        b.shape:SetShown(s.bg ~= nil)
        if s.bg then b.shape:SetColor(hover and s.hover or s.bg) end
        local tc = hover and s.hoverText or s.text
        b.label:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
    function b:SetStyle(style2)
        self.style = style2
        Paint(false)
    end
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then Paint(true) end end)
    b:SetScript("OnLeave", function() Paint(false) end)
    b:HookScript("OnDisable", function(self) self:SetAlpha(0.4) Paint(false) end)
    b:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
    b:SetScript("OnClick", function(...)
        W.PlaySound("U_CHAT_SCROLL_BUTTON")
        if onClick then onClick(...) end
    end)
    b:SetStyle(style or "secondary")
    return b
end

-- An icon you click. icon: an Art name; size: the icon's size.
function W.Glyph(parent, icon, size, onClick, color)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size + 6, size + 6)
    b.icon = W.Icon(b, icon, size, color)
    b.icon:SetPoint("CENTER")
    function b:SetIcon(name, c)
        self.icon:SetTexture(W.ART .. name)
        if c then
            self.icon:SetVertexColor(c[1], c[2], c[3], 1)
        end
    end
    b:SetScript("OnEnter", function(self) self.icon:SetAlpha(0.65) end)
    b:SetScript("OnLeave", function(self) self.icon:SetAlpha(1) end)
    b:SetScript("OnClick", onClick)
    -- A quick pop: the icon grows a little and settles (a like).
    local driver
    function b:Bounce()
        driver = driver or CreateFrame("Frame", nil, self)
        local k = 0
        driver:SetScript("OnUpdate", function(d, elapsed)
            k = k + elapsed / 0.3
            if k >= 1 then
                self.icon:SetSize(size, size)
                d:SetScript("OnUpdate", nil)
                return
            end
            local s = size * (1 + 0.35 * math.sin(k * math.pi))
            self.icon:SetSize(s, s)
        end)
    end
    return b
end

-- Blue/grey "Follow" / "Following" switch.
function W.FollowButton(parent, w, h, getName)
    local b
    b = W.Flat(parent, "Follow", w, h, "primary", function()
        local who = getName()
        if who then ns.Social.Follow(who, not ns.Social.Following(who)) end
    end)
    function b:Update(who)
        local on = who and ns.Social.Following(who)
        self:SetText(on and "Following" or "Follow")
        self:SetStyle(on and "secondary" or "primary")
    end
    return b
end

---------------------------------------------------------------------------
-- Avatar: a round class icon, the real face on top when the game can draw
-- it (you, your group, your target), and an optional story ring.
---------------------------------------------------------------------------
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"

function W.Avatar(parent, size)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(size, size)
    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetAllPoints()
    f.ring:SetTexture(W.ART .. "Ring")
    local gap = math.max(2, math.floor(size * 0.07))
    f.back = W.Icon(f, "Circle", nil, C.bg, "BORDER")
    f.back:SetPoint("TOPLEFT", gap, -gap)
    f.back:SetPoint("BOTTOMRIGHT", -gap, gap)
    local inner = gap + math.max(1, math.floor(size * 0.04))
    f.class = f:CreateTexture(nil, "ARTWORK")
    f.class:SetPoint("TOPLEFT", inner, -inner)
    f.class:SetPoint("BOTTOMRIGHT", -inner, inner)
    f.face = f:CreateTexture(nil, "OVERLAY")
    f.face:SetPoint("TOPLEFT", inner, -inner)
    f.face:SetPoint("BOTTOMRIGHT", -inner, inner)

    -- ring: nil (none), "new" (colourful: something new), "seen" (grey).
    function f:SetPlayer(id, class, ring)
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            self.class:SetTexture(CLASS_ICONS)
            self.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            self.class:SetTexture(W.ART .. "User")
            self.class:SetTexCoord(0, 1, 0, 1)
        end
        local unit = ns.Picture.UnitFor(id)
        if unit and SetPortraitTexture then
            SetPortraitTexture(self.face, unit)
            self.face:Show()
        else
            self.face:Hide()
        end
        self.ring:SetShown(ring ~= nil)
        self.ring:SetDesaturated(ring == "seen")
        if ring == "seen" then self.ring:SetVertexColor(0.45, 0.45, 0.45) else self.ring:SetVertexColor(1, 1, 1) end
    end
    return f
end

---------------------------------------------------------------------------
-- Input: a flat text box with grey hint text while it's empty.
-- onEnter(text) on Enter; onChange(text) as you type.
---------------------------------------------------------------------------
function W.Input(parent, w, h, hint, maxLetters, onEnter, onChange)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(w, h or 30)
    box:SetAutoFocus(false)
    box:SetFontObject(W.Font(12))
    box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    box:SetTextInsets(10, 10, 0, 0)
    if box.SetMaxLetters then box:SetMaxLetters(maxLetters or 200) end
    box.shape = W.Rounded(box, C.raised, 8)
    box.hint = W.Text(box, 12, C.faint)
    box.hint:SetPoint("LEFT", 10, 0)
    box.hint:SetText(hint or "")
    local function Hint()
        box.hint:SetShown((box:GetText() or "") == "" and not box:HasFocus())
    end
    box.UpdateHint = Hint
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s)
        if onEnter then onEnter(s:GetText() or "") end
        s:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function() box.hint:Hide() end)
    box:SetScript("OnEditFocusLost", Hint)
    box:SetScript("OnTextChanged", function(s)
        Hint()
        if onChange then onChange(s:GetText() or "") end
    end)
    return box
end

---------------------------------------------------------------------------
-- Toggle: an on/off switch. onChange(on).
---------------------------------------------------------------------------
function W.Toggle(parent, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(40, 22)
    b.track = W.Rounded(b, C.chip, 11)
    b.knob = W.Icon(b, "Circle", 18, { 1, 1, 1 }, "ARTWORK")
    function b:SetChecked(on)
        self.on = on and true or false
        self.track:SetColor(self.on and C.blue or C.chip)
        self.knob:ClearAllPoints()
        self.knob:SetPoint(self.on and "RIGHT" or "LEFT", self.on and -2 or 2, 0)
    end
    function b:GetChecked() return self.on end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.on)
        W.PlaySound("U_CHAT_SCROLL_BUTTON")
        if onChange then onChange(self.on) end
    end)
    b:SetChecked(false)
    return b
end

---------------------------------------------------------------------------
-- Tabs: words in a row; the chosen one is white with a line under it (or
-- over it: opts.top, like a profile's POSTS / SAVED).
-- items: { { key, label, icon? }, ... }; onSelect(key).
---------------------------------------------------------------------------
function W.Tabs(parent, items, onSelect, opts)
    opts = opts or {}
    local tabs = { buttons = {} }
    local prev
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, parent)
        b.label = W.Text(b, opts.size or 12, C.dim)
        b.label:SetText(item.label)
        local tw = (b.label.GetStringWidth and b.label:GetStringWidth()) or 0
        if tw <= 0 then tw = #item.label * 7 end
        local iw = item.icon and 16 or 0
        b:SetSize(opts.width or (tw + iw + (opts.pad or 24)), opts.height or 30)
        if item.icon then
            b.icon = W.Icon(b, item.icon, 13, C.dim)
            b.icon:SetPoint("CENTER", -(tw / 2) - 2, 0)
            b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        else
            b.label:SetPoint("CENTER")
        end
        b.mark = b:CreateTexture(nil, "OVERLAY")
        b.mark:SetColorTexture(C.text[1], C.text[2], C.text[3], 1)
        b.mark:SetHeight(opts.top and 1 or 2)
        b.mark:SetPoint(opts.top and "TOPLEFT" or "BOTTOMLEFT", 6, 0)
        b.mark:SetPoint(opts.top and "TOPRIGHT" or "BOTTOMRIGHT", -6, 0)
        b.mark:Hide()
        if prev then b:SetPoint("LEFT", prev, "RIGHT", opts.gap or 4, 0) end
        b.key = item.key
        if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
        b:HookScript("OnDisable", function(self) self:SetAlpha(0.35) end)
        b:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
        b:SetScript("OnClick", function()
            W.PlaySound("U_CHAT_SCROLL_BUTTON")
            tabs:Select(item.key)
            if onSelect then onSelect(item.key) end
        end)
        tabs.buttons[i] = b
        prev = b
    end
    function tabs:Select(key)
        self.key = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.dim
            b.label:SetTextColor(c[1], c[2], c[3], 1)
            if b.icon then b.icon:SetVertexColor(c[1], c[2], c[3], 1) end
            b.mark:SetShown(on)
        end
    end
    return tabs
end

---------------------------------------------------------------------------
-- Menu: a small list that drops down from a button ("..."). items:
-- { { text, fn, danger = true }, ... }. menu:Toggle(anchor) opens or closes it.
---------------------------------------------------------------------------
function W.Menu(parent, width)
    local m = CreateFrame("Frame", nil, parent)
    m:SetWidth(width or 180)
    m:SetFrameStrata("DIALOG")
    W.Rounded(m, C.raised, 10)
    m.rows = {}
    m:Hide()
    m:EnableMouse(true)
    function m:Set(items)
        for i, item in ipairs(items) do
            local r = self.rows[i]
            if not r then
                r = W.Flat(self, "", (width or 180) - 8, 30, "plain")
                r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 32)
                self.rows[i] = r
            end
            r:SetText(item[1])
            r:SetStyle(item.danger and "danger" or "plain")
            r:SetScript("OnClick", function()
                self:Hide()
                item[2]()
            end)
            r:SetShown(item.shown ~= false)
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide() end
        -- Only the shown rows, packed.
        local y = 0
        for i = 1, #items do
            local r = self.rows[i]
            if r:IsShown() then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 4, -4 - y)
                y = y + 32
            end
        end
        self:SetHeight(y + 8)
    end
    function m:Toggle(anchor)
        if self:IsShown() then return self:Hide() end
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        self:Show()
    end
    return m
end

---------------------------------------------------------------------------
-- Tooltips, titles, sounds
---------------------------------------------------------------------------
-- Hover help. Hooked rather than set, so a widget's own hover still works.
function W.Tooltip(widget, title, line)
    local function Show(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(type(title) == "function" and title(s) or title, 1, 1, 1)
        local text = type(line) == "function" and line(s) or line
        if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end
    if widget.HookScript and widget:GetScript("OnEnter") then
        widget:HookScript("OnEnter", Show)
        widget:HookScript("OnLeave", GameTooltip_Hide)
    else
        widget:SetScript("OnEnter", Show)
        widget:SetScript("OnLeave", GameTooltip_Hide)
    end
end

function W.SetPortrait(f, tex)
    if f.SetPortraitToAsset then
        f:SetPortraitToAsset(tex)
        return
    end
    local p = f.portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
    if not p then return end
    if SetPortraitToTexture then SetPortraitToTexture(p, tex) else p:SetTexture(tex) end
end

function W.SetTitle(f, text)
    if f.SetTitle then
        f:SetTitle(text)
    elseif f.TitleText then
        f.TitleText:SetText(text)
    end
end

-- Every sound goes through here, so Settings can mute the addon.
function W.PlaySound(kit)
    if ns.db and ns.db.sound == false then return end
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

---------------------------------------------------------------------------
-- "Are you sure?"
---------------------------------------------------------------------------
StaticPopupDialogs.WOWSTAGRAM_CONFIRM = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
    OnAccept = function(_, data) data.onYes() end,
}

function W.Confirm(text, onYes)
    StaticPopup_Hide("WOWSTAGRAM_CONFIRM")
    StaticPopup_Show("WOWSTAGRAM_CONFIRM", text, nil, { onYes = onYes })
end

---------------------------------------------------------------------------
-- A scrolling list of rows that the caller fills (plain frames only: 3D
-- pictures don't clip inside scroll frames, so pages with pictures page
-- instead of scrolling). Rows can have their own heights.
---------------------------------------------------------------------------
function W.ScrollList(parent, rowH, buildRow)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

    local list = { frame = sf, content = content, rows = {}, count = 0 }
    local bar = sf.ScrollBar
    if type(bar) ~= "table" then bar = nil end

    function list:Inset(left, top, right, bottom)
        self.inset = { left, top, right, bottom }
        self:Fit()
    end

    function list:Fit()
        local i = self.inset
        if not i then return end
        local h = sf:GetHeight() or 0
        local needed = h > 0 and self.height and self.height > h + 0.5
        if bar then bar:SetShown(needed and true or false) end
        if not needed then sf:SetVerticalScroll(0) end
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", i[1], i[2])
        sf:SetPoint("BOTTOMRIGHT", -((needed or not bar) and (i[3] + 20) or i[3]), i[4])
    end

    function list:Row(i)
        local row = self.rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(rowH)
        row:SetPoint("RIGHT", content, "RIGHT")
        buildRow(row)
        self.rows[i] = row
        return row
    end

    function list:SetCount(n)
        local y = 0
        for i = 1, #self.rows do
            local row = self.rows[i]
            row:SetShown(i <= n)
            if i <= n then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("RIGHT", content, "RIGHT")
                y = y + (row:GetHeight() or rowH)
            end
        end
        content:SetHeight(math.max(1, y))
        self.count, self.height = n, y
        self:Fit()
    end

    function list:ScrollToEnd()
        local max = sf.GetVerticalScrollRange and sf:GetVerticalScrollRange() or 0
        sf:SetVerticalScroll(max)
    end

    function list:ScrollToTop() sf:SetVerticalScroll(0) end

    parent:HookScript("OnSizeChanged", function() list:Fit() end)
    return list
end
