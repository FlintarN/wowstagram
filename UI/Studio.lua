-- Create (the Studio): make a picture. It starts as you, as you look right
-- now (your transmog included). Then the four tabs, like Instagram's editor:
--   Outfit      click a slot to take that piece off (click again to put it
--               back), right-click to empty it; drop an item from your bags
--               on a slot or the picture, shift-click any item link, or type
--               an item id. Take all off / Put all on, and "Wear my current
--               outfit" to start again from what you're wearing.
--   Pose        22 poses, the framing (full, waist up, face), weapons out
--   Background  where you stand
--   Filter      over the whole picture
-- Drag the picture to turn yourself round, wheel to zoom. Then a caption,
-- and Share. Every visit starts fresh (nothing is kept from last time, or
-- over a /reload), except Edit and "Try this look", which bring a picture.
local _, ns = ...

local W = ns.Widgets
local C = W.C
local L = ns.Look
local P = ns.Picture
local S = ns.Social
local ST = {}
ns.Studio = ST

local INV = {
    [1] = "HEADSLOT", [3] = "SHOULDERSLOT", [15] = "BACKSLOT", [5] = "CHESTSLOT", [4] = "SHIRTSLOT",
    [19] = "TABARDSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [6] = "WAISTSLOT", [7] = "LEGSSLOT",
    [8] = "FEETSLOT", [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT",
}

local function EmptyIcon(slot)
    if GetInventorySlotInfo and INV[slot] then
        local ok, _, tex = pcall(GetInventorySlotInfo, INV[slot])
        if ok and tex then return tex end
    end
    return "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
end

local view -- the one Studio page

-- The person the Outfit and Pose tabs work on: 0 is you, 1.. the others.
local function Cur()
    return view.pic:Person(view.sel or 0)
end

-- A small rounded tile with a picture or colour in it and a name under it
-- (slots, backgrounds, filters). Its frame shows when it's chosen.
local function Tile(parent, size, name, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, height or size)
    b.ring = W.Rounded(b, C.text, 8, "BACKGROUND")
    b.ring:SetShown(false)
    b.inner = CreateFrame("Frame", nil, b)
    b.inner:SetPoint("CENTER")
    b.inner:SetSize(size - 4, (height or size) - 4)
    -- (Under the background art PaintBackground adds, so previews show it.)
    b.icon = b.inner:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.icon:SetAllPoints()
    b.wash = b.inner:CreateTexture(nil, "OVERLAY")
    b.wash:SetAllPoints()
    b.wash:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.name = W.Text(parent, 10, C.dim)
    b.name:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.name:SetJustifyH("CENTER")
    b.name:SetText(name or "")
    function b:SetChosen(on)
        self.ring:SetShown(on)
        local c = on and C.text or C.dim
        self.name:SetTextColor(c[1], c[2], c[3], 1)
    end
    return b
end

function ST.New(parent)
    -- stash: slots taken off with a click, to put back (one per person).
    view = { sel = 0, stashes = { [0] = {} } }
    view.stash = view.stashes[0]
    ST.view = view
    local UI = ns.UI

    -- Left: the picture.
    local PW = 300
    local PH = math.floor(PW * L.ASPECT)
    view.pic = P.New(parent, PW, PH, {
        interactive = true,
        onDrop = function(item) ST.TryOn(item) end,
        onSelect = function(i) ST.Select(i) end,
        -- Which tool is open: with Stickers or Text, dragging on the picture
        -- moves those instead of turning the person.
        mode = function() return view.pane end,
        onSticker = function() ST.Paint() end,
        place = function(x, y) return ST.PlaceSticker(x, y) end,
    })
    -- In the middle of the page (top to bottom), under a header: you, and
    -- what you're doing (a new post, or editing one).
    local HEAD_H, HINTS_H = 46, 52
    local top = math.max(16, math.floor((UI.MAIN_H - (HEAD_H + PH + HINTS_H)) / 2))
    view.me = W.Avatar(parent, 34)
    view.me:SetPoint("TOPLEFT", 18, -top)
    view.meName = W.Text(parent, 13)
    view.meName:SetPoint("TOPLEFT", view.me, "TOPRIGHT", 10, -2)
    view.meWhat = W.Text(parent, 11, C.dim)
    view.meWhat:SetPoint("TOPLEFT", view.meName, "BOTTOMLEFT", 0, -3)
    view.pic:SetPoint("TOPLEFT", 18, -(top + HEAD_H))
    local hint = W.Text(parent, 11, C.dim)
    hint:SetPoint("TOP", view.pic, "BOTTOM", 0, -10)
    hint:SetWidth(PW)
    hint:SetJustifyH("CENTER")
    hint:SetText("Drag: turn  \194\183  Right-drag: move  \194\183  Wheel: zoom")
    local hint2 = W.Text(parent, 10, C.faint)
    hint2:SetPoint("TOP", hint, "BOTTOM", 0, -4)
    hint2:SetText("Everyone sees it like this.")

    -- Middle: the tool rail (like Snapchat's camera), in groups: you, the
    -- scene, and the fun on top. One click opens a tool's panel.
    local RAIL_X, RAIL_W = 18 + PW + 12, 54
    local rail = CreateFrame("Frame", nil, parent)
    rail:SetPoint("TOPLEFT", RAIL_X, -16)
    rail:SetPoint("BOTTOMLEFT", RAIL_X, 12)
    rail:SetWidth(RAIL_W)
    view.rail = { buttons = {} }
    local y = 0
    for _, tool in ipairs(ST.TOOLS) do
        if tool == "-" then
            local line = W.Line(rail)
            line:SetPoint("TOPLEFT", 8, -y - 5)
            line:SetPoint("TOPRIGHT", -8, -y - 5)
            y = y + 10
        else
            local b = CreateFrame("Button", nil, rail)
            b:SetSize(RAIL_W, 40)
            b:SetPoint("TOP", 0, -y)
            b.bg = W.Rounded(b, C.raised, 8, "BACKGROUND")
            b.bg:SetShown(false)
            b.icon = W.Icon(b, tool.icon, 20, C.dim)
            b.icon:SetPoint("TOP", 0, -4)
            b.label = W.Text(b, 9, C.dim)
            b.label:SetPoint("TOP", b.icon, "BOTTOM", 0, -3)
            b.label:SetText(tool.label)
            b:SetScript("OnClick", function()
                W.PlaySound("U_CHAT_SCROLL_BUTTON")
                ST.Pane(tool.key)
            end)
            b:SetScript("OnEnter", function(self) if view.pane ~= tool.key then self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3], 1) end end)
            b:SetScript("OnLeave", function(self) if view.pane ~= tool.key then self.icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 1) end end)
            b.key = tool.key
            view.rail.buttons[tool.key] = b
            y = y + 43
        end
    end
    function view.rail:Select(key)
        for k, b in pairs(self.buttons) do
            local on = k == key
            b.on = on
            b.bg:SetShown(on)
            local c = on and C.text or C.dim
            b.icon:SetVertexColor(c[1], c[2], c[3], 1)
            b.label:SetTextColor(c[1], c[2], c[3], 1)
        end
    end

    -- Right: the chosen tool's panel, with its name on top.
    local RX = RAIL_X + RAIL_W + 12
    local RW = UI.MAIN_W - RX - 18
    local right = CreateFrame("Frame", nil, parent)
    right:SetPoint("TOPLEFT", RX, -16)
    right:SetPoint("BOTTOMRIGHT", -18, 12)
    view.panes = {}
    view.title = W.Text(right, 16)
    view.title:SetPoint("TOPLEFT", 0, -4)
    local tl = W.Line(right)
    tl:SetPoint("TOPLEFT", 0, -30)
    tl:SetPoint("TOPRIGHT", 0, -30)
    local function Pane(key)
        local p = CreateFrame("Frame", nil, right)
        p:SetPoint("TOPLEFT", 0, -64)
        p:SetPoint("BOTTOMRIGHT", 0, 90) -- above Guild only and the caption
        p:Hide()
        view.panes[key] = p
        return p
    end
    local outfit = Pane("outfit")

    -- One switch: Take all off (the pieces wait, greyed out on their slots),
    -- then Put all on brings them back.
    view.naked = W.Flat(outfit, "Take all off", 120, 28, "secondary", function()
        local look = Cur()
        if ST.AllOff() then
            for slot, s in pairs(view.stash) do look.slots[slot] = s end
            view.stash = {}
        else
            for slot, s in pairs(look.slots) do view.stash[slot] = s end
            look.slots = {}
        end
        ST.Redraw()
    end, 12)
    view.naked:SetPoint("TOPLEFT", 0, 0)
    -- Start again from what you're wearing (after "Try this look", say).
    view.mine = W.Flat(outfit, "Wear my current outfit", 170, 28, "link", function()
        ST.Select(0)
        ST.Selfie()
    end, 12)
    view.mine:SetPoint("LEFT", view.naked, "RIGHT", 10, 0)
    W.Tooltip(view.mine, "Wear my current outfit", "Back to what you're wearing in the game right now, transmog included.")

    view.status = W.Text(right, 11, C.dim)
    view.status:SetPoint("TOPLEFT", 0, -40)
    view.status:SetWidth(RW - 90)
    view.status:SetWordWrap(false)
    view.cancelEdit = W.Flat(right, "Cancel edit", 84, 18, "link", function() ST.Fresh() end, 11)
    view.cancelEdit:SetPoint("TOPRIGHT", 0, -36)

    local hintO = W.Text(outfit, 11, C.dim)
    hintO:SetPoint("TOPLEFT", 0, -38)
    hintO:SetText("Click: off / on   \194\183   Right-click: empty")
    view.slots = {}
    local SIZE, PER = 52, 5
    local SG = math.floor((RW - SIZE * PER) / (PER - 1))
    for i, def in ipairs(L.SLOTS) do
        local b = Tile(outfit, SIZE, def.name)
        local row, col = math.floor((i - 1) / PER), (i - 1) % PER
        b:SetPoint("TOPLEFT", col * (SIZE + SG), -58 - row * (SIZE + 24))
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.slot = def.id
        b:SetScript("OnClick", function(_, button)
            if GetCursorInfo and GetCursorInfo() == "item" then
                local _, id, link = GetCursorInfo()
                ClearCursor()
                return ST.TryOn(link or id, def.id)
            end
            local look = Cur()
            if button == "RightButton" then
                look.slots[def.id], view.stash[def.id] = nil, nil
            elseif look.slots[def.id] then
                view.stash[def.id] = look.slots[def.id]
                look.slots[def.id] = nil
            elseif view.stash[def.id] then
                look.slots[def.id] = view.stash[def.id]
                view.stash[def.id] = nil
            end
            ST.Redraw()
        end)
        b:SetScript("OnReceiveDrag", function()
            local kind, id, link = GetCursorInfo()
            if kind ~= "item" then return end
            ClearCursor()
            ST.TryOn(link or id, def.id)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local s = Cur().slots[def.id] or view.stash[def.id]
            local item = P.SlotItem(s)
            if item and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(item)
            else
                GameTooltip:SetText(def.name, 1, 1, 1)
            end
            if view.stash[def.id] and not Cur().slots[def.id] then
                GameTooltip:AddLine("Taken off. Click to put it back on.", 0.6, 0.8, 1, true)
            elseif not s then
                GameTooltip:AddLine("Empty. Drop an item here, or shift-click an item link.", 0.6, 0.8, 1, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        view.slots[i] = b
    end
    local tryLabel = W.Text(outfit, 12)
    tryLabel:SetPoint("TOPLEFT", 0, -296)
    tryLabel:SetText("Try on any item")
    view.itemBox = W.Input(outfit, RW - 96, 30, "Item id, or shift-click an item", 60, function(text) ST.TryOn(text) end)
    view.itemBox:SetPoint("TOPLEFT", 0, -316)
    local tryButton = W.Flat(outfit, "Try on", 88, 30, "secondary", function() ST.TryOn(view.itemBox:GetText()) end)
    tryButton:SetPoint("LEFT", view.itemBox, "RIGHT", 8, 0)
    local tryHint = W.Text(outfit, 11, C.faint)
    tryHint:SetPoint("TOPLEFT", 0, -354)
    tryHint:SetWidth(RW)
    tryHint:SetText("Or drop an item from your bags on the picture.")

    -- Pose: chips, then framing and weapons.
    local pose = Pane("pose")
    view.poses = {}
    local CW, CPR = math.floor((RW - 3 * 6) / 4), 4
    for i, p in ipairs(L.POSES) do
        local b = W.Flat(pose, p.name, CW, 26, "secondary", function()
            local who = Cur()
            who.pose = p.key
            if p.drawn then who.drawn = true end
            ST.Restyle()
        end)
        local row, col = math.floor((i - 1) / CPR), (i - 1) % CPR
        b:SetPoint("TOPLEFT", col * (CW + 6), -row * 32)
        b.key = p.key
        view.poses[i] = b
    end
    local frameLabel = W.Text(pose, 12)
    frameLabel:SetPoint("TOPLEFT", 0, -196)
    frameLabel:SetText("Framing")
    view.frames = {}
    for i, fr in ipairs(L.FRAMES) do
        local b = W.Flat(pose, fr.name, CW, 26, "secondary", function()
            view.look.frame = fr.key
            ST.Restyle()
        end)
        b:SetPoint("TOPLEFT", (i - 1) * (CW + 6), -216)
        b.key = fr.key
        view.frames[i] = b
    end
    local drawnLabel = W.Text(pose, 12)
    drawnLabel:SetPoint("TOPLEFT", 0, -262)
    drawnLabel:SetText("Weapons out")
    view.drawn = W.Toggle(pose, function(on)
        Cur().drawn = on and true or nil
        ST.Restyle()
    end)
    view.drawn:SetPoint("TOPLEFT", 110, -258)
    -- Hold still: the pose frozen mid-move (face filters stay put).
    local stillLabel = W.Text(pose, 12)
    stillLabel:SetPoint("TOPLEFT", 0, -294)
    stillLabel:SetText("Hold still")
    view.still = W.Toggle(pose, function(on)
        Cur().still = on and true or nil
        ST.Restyle()
    end)
    view.still:SetPoint("TOPLEFT", 110, -290)
    W.Tooltip(view.still, "Hold still", "The pose is frozen mid-move, like a photo. Face filters stay on the face.")

    -- People: who's in the picture (up to 4), and who to add. Click a row to
    -- pick whose outfit and pose you change; right-drag on the picture
    -- grabs whoever's nearest.
    do
        local pane = Pane("people")
        local head = W.Text(pane, 12)
        head:SetPoint("TOPLEFT", 0, 0)
        head:SetText("In the picture")
        view.people = {}
        for i = 0, L.MAX_PEOPLE - 1 do
            local r = CreateFrame("Button", nil, pane)
            r:SetSize(RW, 40)
            r:SetPoint("TOPLEFT", 0, -20 - i * 44)
            r.mark = W.Rounded(r, C.raised, 8)
            r.mark:SetShown(false)
            r.avatar = W.Avatar(r, 30)
            r.avatar:SetPoint("LEFT", 6, 0)
            r.avatar:EnableMouse(false)
            r.name = W.Text(r, 13)
            r.name:SetPoint("LEFT", r.avatar, "RIGHT", 10, 0)
            r.name:SetWidth(RW - 110)
            r.name:SetWordWrap(false)
            r.remove = W.Glyph(r, "Close", 11, function() ST.Remove(r.index) end, C.dim)
            r.remove:SetPoint("RIGHT", -8, 0)
            W.Tooltip(r.remove, "Take out of the picture")
            r.index = i
            r:SetScript("OnClick", function() ST.Select(i) end)
            view.people[i] = r
        end
        local addHead = W.Text(pane, 12)
        addHead:SetPoint("TOPLEFT", 0, -20 - L.MAX_PEOPLE * 44 - 10)
        addHead:SetText("Add someone")
        view.addHint = W.Text(pane, 11, C.faint)
        view.addHint:SetPoint("TOPLEFT", addHead, "BOTTOMLEFT", 0, -6)
        view.addHint:SetWidth(RW)
        view.addHint:SetWordWrap(true)
        view.addHint:SetText("Target a player or group up: only people you can see.")
        view.adds = {}
        local y0 = -20 - L.MAX_PEOPLE * 44 - 50
        for i = 1, 5 do
            local b = W.Flat(pane, "", RW, 28, "secondary", function(self) if self.unit then ST.Add(self.unit) end end, 12)
            b:SetPoint("TOPLEFT", 0, y0 - (i - 1) * 32)
            view.adds[i] = b
        end
    end

    -- Background and Filter: scrolling lists of tiles in sections. Each tile
    -- sets one field of the look (bg, filter or overlay) to its key.
    view.tiles = {}
    local function ScrollPane(key)
        local pane = Pane(key)
        local sf = CreateFrame("ScrollFrame", nil, pane)
        sf:SetPoint("TOPLEFT")
        sf:SetPoint("BOTTOMRIGHT", 0, 18)
        local content = CreateFrame("Frame", nil, sf)
        content:SetSize(RW, 1)
        sf:SetScrollChild(content)
        local sp = { pane = pane, content = content, y = 0 }
        function sp:Header(text)
            local head = W.Text(content, 12)
            head:SetPoint("TOPLEFT", 0, -self.y)
            head:SetText(text)
            self.y = self.y + 20
        end
        -- Tiles for `list`, `per` to a row; paint(tile, item) draws each.
        function sp:Tiles(list, field, per, aspect, paint)
            local tw = math.floor((RW - (per - 1) * 10) / per)
            local th = math.floor(tw * (aspect or 1))
            for i, item in ipairs(list) do
                local row, col = math.floor((i - 1) / per), (i - 1) % per
                local t = Tile(content, tw, item.name, th)
                t:SetPoint("TOPLEFT", col * (tw + 10), -(self.y + row * (th + 26)))
                t.name:SetWidth(tw + 8)
                t.name:SetWordWrap(false)
                paint(t, item)
                t:SetScript("OnClick", function()
                    if type(field) == "function" then return field(item, t) end
                    view.look[field] = item.key
                    ST.Restyle()
                end)
                W.Tooltip(t, item.name)
                t.key, t.field = item.key, type(field) == "string" and field or nil
                view.tiles[#view.tiles + 1] = t
            end
            self.y = self.y + math.ceil(#list / per) * (th + 26) + 8
        end
        -- A line of words in the list (a hint).
        function sp:Hint(text)
            local t = W.Text(content, 11, C.faint)
            t:SetPoint("TOPLEFT", 0, -self.y)
            t:SetWidth(RW)
            t:SetJustifyH("LEFT")
            if t.SetWordWrap then t:SetWordWrap(true) end
            t:SetText(text)
            self.y = self.y + 32
            return t
        end
        function sp:Finish()
            local total = self.y
            content:SetHeight(total)
            sf:EnableMouseWheel(true)
            sf:SetScript("OnMouseWheel", function(f, delta)
                local max = math.max(0, total - (f:GetHeight() or 0))
                f:SetVerticalScroll(math.max(0, math.min(max, (f:GetVerticalScroll() or 0) - delta * 60)))
            end)
            self.chosen = W.Text(pane, 12)
            self.chosen:SetPoint("BOTTOMLEFT", 0, 0)
            self.chosen:SetWidth(RW)
            self.chosen:SetWordWrap(false)
        end
        return sp
    end
    local function Group(list, group)
        local out = {}
        for _, item in ipairs(list) do
            if item.group == group then out[#out + 1] = item end
        end
        return out
    end

    -- Backgrounds: studio colours, moving ones, your own colours, the
    -- classic Dressing Rooms, and places (classic loading screens).
    do
        local sp = ScrollPane("bg")
        local function PaintBg(t, bg)
            P.PaintBackground(t.inner, t.icon, bg)
            if bg.anim == "stars" then
                ns.Fx.PreviewOverlay(t.inner, { tex = "Interface\\AddOns\\Wowstagram\\Art\\Glow", size = { 4, 6 }, add = true })
            end
        end
        sp:Header("Studio")
        sp:Tiles(Group(L.BACKGROUNDS, "studio"), "bg", 4, L.ASPECT, PaintBg)
        sp:Header("Moving")
        sp:Tiles(Group(L.BACKGROUNDS, "fun"), "bg", 4, L.ASPECT, PaintBg)
        -- Your colours: pick the top and the bottom from the palette.
        sp:Header("Your colours")
        view.swatches = {}
        local SW, PER = 26, 8
        for row, which in ipairs({ { "bgTop", "Top" }, { "bgBottom", "Bottom" } }) do
            local label = W.Text(sp.content, 11, C.dim)
            label:SetPoint("TOPLEFT", 0, -sp.y - 7)
            label:SetText(which[2])
            for i, hex in ipairs(L.PALETTE) do
                local r, c = math.floor((i - 1) / PER), (i - 1) % PER
                local b = CreateFrame("Button", nil, sp.content)
                b:SetSize(SW, SW)
                b:SetPoint("TOPLEFT", 54 + c * (SW + 6), -(sp.y + r * (SW + 6)))
                b.ring = W.Rounded(b, C.text, 6, "BACKGROUND")
                b.ring:SetShown(false)
                local col = ns.Fx.Hex(hex)
                local fill = b:CreateTexture(nil, "ARTWORK")
                fill:SetPoint("TOPLEFT", 3, -3)
                fill:SetPoint("BOTTOMRIGHT", -3, 3)
                fill:SetColorTexture(col[1], col[2], col[3], 1)
                b:SetScript("OnClick", function()
                    local look = view.look
                    if look.bg ~= "custom" then
                        look.bgTop, look.bgBottom = look.bgTop or "ff9500", look.bgBottom or "1b2a49"
                    end
                    look.bg = "custom"
                    look[which[1]] = hex
                    ST.Restyle()
                end)
                b.field, b.hex = which[1], hex
                view.swatches[#view.swatches + 1] = b
            end
            sp.y = sp.y + math.ceil(#L.PALETTE / PER) * (SW + 6) + 8
        end
        sp:Header("Ground")
        sp:Tiles(Group(L.BACKGROUNDS, "ground"), "bg", 4, L.ASPECT, PaintBg)
        sp:Header("Talent trees")
        sp:Tiles(Group(L.BACKGROUNDS, "talent"), "bg", 4, L.ASPECT, PaintBg)
        sp:Header("Books")
        sp:Tiles(Group(L.BACKGROUNDS, "book"), "bg", 4, L.ASPECT, PaintBg)
        sp:Header("Dressing rooms")
        sp:Tiles(Group(L.BACKGROUNDS, "room"), "bg", 4, L.ASPECT, PaintBg)
        sp:Header("Places")
        sp:Tiles(Group(L.BACKGROUNDS, "place"), "bg", 4, L.ASPECT, PaintBg)
        sp:Header("Maps")
        sp:Tiles(Group(L.BACKGROUNDS, "map"), "bg", 4, L.ASPECT, PaintBg)
        sp:Finish()
        view.bgPane = sp
    end

    -- Filters (on a sample backdrop, so you see what they do), moving
    -- filters, and overlays. A filter and an overlay go together.
    do
        local sp = ScrollPane("filter")
        local SAMPLE = { top = { 0.75, 0.68, 0.6 }, bottom = { 0.25, 0.32, 0.4 } }
        local function PaintFilter(t, f)
            P.Gradient(t.icon, SAMPLE, f)
            if f.wash then
                t.wash:SetColorTexture(f.wash[1], f.wash[2], f.wash[3], f.wash[4])
                t.wash:Show()
            elseif f.anim == "hue" or f.anim == "disco" then
                t.wash:SetColorTexture(1, 0.2, 0.8, 0.25)
                t.wash:Show()
            end
            ns.Fx.Layers(t.inner, f)
        end
        sp:Tiles(L.FILTERS, "filter", 4, 1, PaintFilter)
        sp:Finish()
        view.filterPane = sp
    end

    -- Motion: the picture moves (together with any filter).
    do
        local sp = ScrollPane("motion")
        sp:Hint("Goes with any filter and overlay.")
        local SAMPLE = { top = { 0.75, 0.68, 0.6 }, bottom = { 0.25, 0.32, 0.4 } }
        local COLOUR = { hue = { 1, 0.2, 0.8, 0.25 }, disco = { 0.2, 0.6, 1, 0.3 }, strobe = { 1, 1, 1, 0.35 }, glitch = { 0.2, 1, 0.6, 0.25 } }
        sp:Tiles(L.MOTIONS, "motion", 4, 1, function(t, m)
            P.Gradient(t.icon, SAMPLE)
            local c = COLOUR[m.anim or ""]
            if c then
                t.wash:SetColorTexture(c[1], c[2], c[3], c[4])
                t.wash:Show()
            end
            ns.Fx.Layers(t.inner, nil, m)
            if m.sway and t.icon.SetRotation then t.icon:SetRotation(m.sway == "dizzy" and 0.3 or 0.08) end
        end)
        sp:Finish()
        view.motionPane = sp
    end

    -- Stickers: click one to put it on the picture; drag it there, the wheel
    -- sizes it (shift + wheel turns it).
    do
        local sp = ScrollPane("sticker")
        sp:Hint("Pick a sticker, then click on the picture to put it there (up to " .. L.MAX_STICKERS
            .. "). Drag it to move it. Wheel: size. Shift + wheel: turn.")
        view.stickerRemove = W.Flat(sp.content, "Remove", 90, 26, "secondary", function()
            local i = view.pic.stickerSelected
            if i and view.look.stickers[i] then
                table.remove(view.look.stickers, i)
                view.pic.stickerSelected = #view.look.stickers > 0 and #view.look.stickers or nil
                ST.Redecor()
            end
        end, 12)
        view.stickerRemove:SetPoint("TOPLEFT", 0, -sp.y)
        view.stickerClear = W.Flat(sp.content, "Clear all", 90, 26, "secondary", function()
            view.look.stickers = {}
            view.pic.stickerSelected = nil
            ST.Redecor()
        end, 12)
        view.stickerClear:SetPoint("LEFT", view.stickerRemove, "RIGHT", 8, 0)
        sp.y = sp.y + 36
        local DARK = { top = { 0.22, 0.25, 0.35 }, bottom = { 0.06, 0.07, 0.1 } }
        sp:Tiles(L.STICKERS, function(def) ST.PickSticker(def.key) end, 5, 1, function(t, def)
            t.isSticker = true
            P.Gradient(t.icon, DARK)
            ns.Decor.PreviewSticker(t.inner, def, t.inner:GetWidth(), t.inner:GetHeight())
        end)
        sp:Finish()
        view.stickerPane = sp
    end

    -- Text: one line, in a style; drag it up or down on the picture.
    do
        local sp = ScrollPane("text")
        view.textBox = W.Input(sp.content, RW, 30, "Type something...", L.MAX_TEXT, nil, function(text)
            if view.loadingText then return end
            text = L.CleanText(text)
            if text == "" then
                view.look.text = nil
            else
                view.look.text = view.look.text or { style = view.textStyle or "bar", y = 70 }
                view.look.text.text = text
            end
            ST.Redecor()
        end)
        view.textBox:SetPoint("TOPLEFT", 0, -sp.y)
        sp.y = sp.y + 40
        sp:Hint("Drag the text up or down on the picture.")
        local DARK = { top = { 0.3, 0.32, 0.4 }, bottom = { 0.1, 0.1, 0.14 } }
        sp:Tiles(L.TEXT_STYLES, function(style)
            view.textStyle = style.key
            if view.look.text then view.look.text.style = style.key end
            ST.Redecor()
        end, 3, 0.75, function(t, style)
            P.Gradient(t.icon, DARK)
            ns.Decor.PreviewText(t.inner, style.key, t.inner:GetWidth(), t.inner:GetHeight())
            t.isText = true
        end)
        sp:Finish()
        view.textPane = sp
    end

    -- Frames around the picture.
    do
        local sp = ScrollPane("deco")
        local SAMPLE = { top = { 0.45, 0.62, 0.85 }, bottom = { 0.2, 0.3, 0.45 } }
        sp:Tiles(L.DECOS, "deco", 3, L.ASPECT, function(t, d)
            P.Gradient(t.icon, SAMPLE)
            ns.Decor.PreviewFrame(t.inner, d.key, t.inner:GetWidth(), t.inner:GetHeight())
        end)
        sp:Finish()
        view.decoPane = sp
    end

    -- Lenses: for whoever is selected (each person has their own).
    do
        local sp = ScrollPane("lens")
        sp:Hint("For whoever is selected in People: each person can have their own.")
        -- Face: drawn on the head (best with standing poses).
        sp:Header("Face")
        view.faceTiles = {}
        local SKIN = { top = { 0.32, 0.35, 0.45 }, bottom = { 0.12, 0.13, 0.18 } }
        sp:Tiles(L.FACES, function(face)
            Cur().face = face.key ~= "none" and face.key or nil
            ST.Redecor()
        end, 4, 1, function(t, face)
            P.Gradient(t.icon, SKIN)
            ns.Decor.PreviewFace(t.inner, face, t.inner:GetWidth(), t.inner:GetHeight())
            view.faceTiles[#view.faceTiles + 1] = t
        end)
        sp:Header("Body")
        view.lensTiles = {}
        local DARK = { top = { 0.25, 0.22, 0.35 }, bottom = { 0.07, 0.06, 0.1 } }
        sp:Tiles(L.LENSES, function(lens)
            Cur().lens = lens.key ~= "none" and lens.key or nil
            ST.Restyle()
        end, 4, 1, function(t, lens)
            P.Gradient(t.icon, DARK)
            if lens.icon then
                local i = t.inner:CreateTexture(nil, "ARTWORK")
                i:SetTexture(lens.icon)
                i:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                i:SetPoint("CENTER")
                local size = math.floor(t.inner:GetWidth() * 0.6)
                i:SetSize(size, size)
            end
            view.lensTiles[#view.lensTiles + 1] = t
        end)
        sp:Finish()
        view.lensPane = sp
    end

    -- Overlays: things drifting over the picture (with any filter).
    do
        local sp = ScrollPane("overlay")
        local DARK = { top = { 0.22, 0.25, 0.35 }, bottom = { 0.06, 0.07, 0.1 } }
        sp:Tiles(L.OVERLAYS, "overlay", 4, 1, function(t, o)
            P.Gradient(t.icon, DARK)
            ns.Fx.PreviewOverlay(t.inner, o)
        end)
        sp:Finish()
        view.overlayPane = sp
    end

    -- Caption and Share, at the bottom.
    local bl = W.Line(right)
    bl:SetPoint("BOTTOMLEFT", 0, 44)
    bl:SetPoint("BOTTOMRIGHT", 0, 44)
    view.caption = W.Input(right, RW - 100, 34, "Write a caption...", S.MAX_CAPTION)
    view.caption:SetPoint("BOTTOMLEFT", 0, 0)
    view.post = W.Flat(right, "Share", 92, 34, "primary", function() ST.Post() end, 13)
    view.post:SetPoint("BOTTOMRIGHT", 0, 0)
    W.Tooltip(view.post, function() return view.editing and "Save changes" or "Share" end, function()
        if not ns.db.network then return "Sharing is off (Settings), so it stays on this computer." end
        local guild = view.guildOnly:GetChecked()
        if view.editing then
            return guild and "Update your picture for your guild." or "Update your picture for everyone."
        end
        return guild and "Share this picture with your guild only."
            or "Share this picture with everyone on the realm who has Wowstagram."
    end)
    -- Who sees it: everyone, or only your guild.
    local guildLabel = W.Text(right, 12)
    guildLabel:SetPoint("BOTTOMLEFT", 0, 60)
    guildLabel:SetText("Guild only")
    view.guildLabel = guildLabel
    view.guildOnly = W.Toggle(right, function() ST.Paint() end)
    view.guildOnly:SetPoint("BOTTOMLEFT", 84, 56)
    W.Tooltip(view.guildOnly, "Guild only", function()
        if view.editing then return "Who sees a picture is set when you share it." end
        if not S.HasGuild() then return "You're not in a guild." end
        return "On: only your guild sees this picture, its likes and its comments. "
            .. "Off: everyone on the realm who has Wowstagram."
    end)

    ST.Pane("outfit")
    ST.Fresh()

    function view:Refresh()
        ST.Paint()
    end
    -- Coming to Create: a fresh start. (Edit and "Try this look" load their
    -- picture right after this.)
    function view:Open()
        ST.Fresh()
    end
    return view
end

-- The tools, top to bottom ("-": a line between groups).
ST.TOOLS = {
    { key = "people", label = "People", icon = "ToolPeople" },
    { key = "outfit", label = "Outfit", icon = "ToolOutfit" },
    { key = "pose", label = "Pose", icon = "ToolPose" },
    "-",
    { key = "bg", label = "Backdrop", icon = "ToolImage", title = "Background" },
    { key = "filter", label = "Filter", icon = "ToolFilter" },
    { key = "motion", label = "Motion", icon = "ToolMotion" },
    { key = "overlay", label = "Overlay", icon = "ToolSparkle" },
    "-",
    { key = "sticker", label = "Stickers", icon = "ToolSticker" },
    { key = "text", label = "Text", icon = "ToolText" },
    { key = "deco", label = "Frame", icon = "ToolFrame" },
    { key = "lens", label = "Lens", icon = "ToolLens" },
}

-- Stickers and text changed: just the decor, not the whole picture.
function ST.LoadText()
    view.loadingText = true
    view.textBox:SetText(view.look.text and view.look.text.text or "")
    view.loadingText = nil
    view.textStyle = view.look.text and view.look.text.style or "bar"
    view.pic.stickerSelected = nil
    view.placing = nil
    if view.ghost then ST.Ghost() end
    if view.textBox.UpdateHint then view.textBox.UpdateHint() end
end

function ST.Redecor()
    ns.Decor.Apply(view.pic)
    ST.Paint()
end

-- Pick a sticker: the next click on the picture puts it there (a ghost of
-- it follows the mouse over the picture). Pick it again to stop.
function ST.PickSticker(key)
    if #view.look.stickers >= L.MAX_STICKERS then
        ST.Status("A picture can have " .. L.MAX_STICKERS .. " stickers.")
        return
    end
    view.placing = view.placing ~= key and key or nil
    ST.Status(view.placing and "Click on the picture to put it there." or "")
    ST.Ghost()
    ST.Paint()
end

function ST.Ghost()
    if not view.ghost then
        view.ghost = view.pic.over:CreateTexture(nil, "OVERLAY")
        view.ghostFrame = CreateFrame("Frame", nil, view.pic)
    end
    local def = view.placing and L.STICKER[view.placing]
    if not def then
        view.ghost:Hide()
        view.ghostFrame:SetScript("OnUpdate", nil)
        return
    end
    view.ghost:SetTexture(def.tex)
    if def.icon then view.ghost:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif def.coords then view.ghost:SetTexCoord(def.coords[1], def.coords[2], def.coords[3], def.coords[4])
    else view.ghost:SetTexCoord(0, 1, 0, 1) end
    local c = def.color or { 1, 1, 1 }
    view.ghost:SetVertexColor(c[1], c[2], c[3], 0.6)
    local size = (view.pic:GetWidth() or 300) * 0.22
    view.ghost:SetSize(size, size)
    view.ghostFrame:SetScript("OnUpdate", function()
        local pic = view.pic
        if not (pic:IsMouseOver() and view.pane == "sticker") then return view.ghost:Hide() end
        local x, y = GetCursorPosition()
        local s = pic:GetEffectiveScale() or 1
        view.ghost:ClearAllPoints()
        view.ghost:SetPoint("CENTER", pic, "BOTTOMLEFT", x / s - (pic:GetLeft() or 0), y / s - (pic:GetBottom() or 0))
        view.ghost:Show()
    end)
end

-- A click on the picture while a sticker is picked: put it there (x, y in
-- % of the picture). True when one was placed.
function ST.PlaceSticker(x, y)
    if not view.placing then return false end
    local key = view.placing
    view.placing = nil
    ST.Ghost()
    ST.Status("")
    ST.AddSticker(key, x, y)
    return true
end

function ST.AddSticker(key, x, y)
    local list = view.look.stickers
    if #list >= L.MAX_STICKERS then
        ST.Status("A picture can have " .. L.MAX_STICKERS .. " stickers.")
        return
    end
    -- Where you clicked; else near the middle, a little apart from the last one.
    local n = #list
    table.insert(list, { key = key, x = x or (50 + ((n * 17) % 40) - 20), y = y or (35 + ((n * 23) % 30)), s = 22, r = 0 })
    view.pic.stickerSelected = #list
    W.PlaySound("U_CHAT_SCROLL_BUTTON")
    ST.Redecor()
end

function ST.Pane(key)
    if key ~= "sticker" and view.placing then
        view.placing = nil
        ST.Ghost()
    end
    view.pane = key
    view.rail:Select(key)
    for _, tool in ipairs(ST.TOOLS) do
        if type(tool) == "table" and tool.key == key then view.title:SetText(tool.title or tool.label) end
    end
    for k, p in pairs(view.panes) do p:SetShown(k == key) end
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- A fresh start: you, as you look right now, default pose, background and
-- filter, no caption, not editing anything.
function ST.Fresh()
    view.editing = nil
    view.look = L.Me(L.New())
    view.sel, view.stashes = 0, { [0] = {} }
    view.stash = view.stashes[0]
    view.caption:SetText("")
    view.caption:ClearFocus()
    view.guildOnly:SetChecked(false)
    ST.LoadText()
    ST.Status("")
    ST.Pane("outfit")
    ST.Selfie()
end

-- Pick whose outfit and pose the tabs change.
function ST.Select(i)
    if not view.look then return end
    if i ~= 0 and not view.look.people[i] then i = 0 end
    view.sel = i
    view.pic.selected = i
    view.stashes[i] = view.stashes[i] or {}
    view.stash = view.stashes[i]
    ST.Paint()
end

-- Spread everyone evenly across the picture, and step back a little for
-- each extra person.
local function Arrange()
    local look = view.look
    local all = { look }
    for _, q in ipairs(look.people) do all[#all + 1] = q end
    local n = #all
    local step = math.min(0.3, 0.8 / n)
    for k, p in ipairs(all) do
        p.mx = (k - (n + 1) / 2) * step
        p.my = 0
    end
    look.zoom = math.max(50, 100 - 14 * (n - 1))
end

-- Add the player on `unit` (your target, a party member): their body, race
-- and current outfit.
function ST.Add(unit)
    local look = view.look
    if #look.people >= L.MAX_PEOPLE - 1 then return end
    local id = ns.UnitId(unit)
    if not id or id == ns.Me() then return end
    for _, q in ipairs(look.people) do
        if q.name == id then return end
    end
    local _, _, race = UnitRace(unit)
    local _, class = UnitClass(unit)
    local q = L.NewPerson(id, race, UnitSex and UnitSex(unit), class)
    table.insert(look.people, q)
    Arrange()
    ST.Select(#look.people)
    ST.Redraw()
    ST.Status("Adding " .. ns.Display(id) .. "...")
    P.ReadOutfitOf(unit, function(slots)
        if view.look ~= look then return end
        q.slots = slots or {}
        ST.Status(ns.Display(id) .. " is in the picture")
        ST.Redraw()
    end)
end

function ST.Remove(i)
    local look = view.look
    if not (i and i > 0 and look.people[i]) then return end
    table.remove(look.people, i)
    table.remove(view.stashes, i)
    Arrange()
    ST.Select(0)
    ST.Redraw()
end

-- Who can be added right now: your target, then your group.
function ST.Candidates()
    local out, seen = {}, {}
    local function Try(unit)
        if not (UnitExists and UnitExists(unit) and (not UnitIsPlayer or UnitIsPlayer(unit))) then return end
        local id = ns.UnitId(unit)
        if not id or id == ns.Me() or seen[id] then return end
        seen[id] = true
        out[#out + 1] = { unit = unit, id = id }
    end
    Try("target")
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do Try(raid and ("raid" .. i) or ("party" .. i)) end
    return out
end

-- Clothes changed: dress the picture again.
function ST.Redraw()
    view.pic:SetLook(view.look, ns.Me())
    ST.Paint()
end

-- Pose, framing, background or filter changed.
function ST.Restyle()
    view.pic:Restyle()
    ST.Paint()
end

-- Wearing nothing, with pieces waiting to go back on.
function ST.AllOff()
    return view.look and next(Cur().slots) == nil and next(view.stash) ~= nil
end

function ST.Status(text)
    view.status:SetText(text or "")
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function ST.Selfie()
    if not view then return end
    local look = view.look and L.Copy(view.look) or L.New()
    L.Me(look)
    look.slots = P.Equipped()
    view.look = look
    view.stashes[0] = {}
    if view.sel == 0 then view.stash = view.stashes[0] end
    ST.Redraw()
    ST.Status("Reading your outfit...")
    -- Your real appearances (transmog) replace the plain item ids once the
    -- model has loaded; until then the picture shows your gear.
    view.pic:ReadOutfit("player", function(slots)
        if view.look ~= look then return end
        if slots then look.slots = slots end
        ST.Status(slots and "Wearing your current outfit" or "Wearing your current gear (this client can't read transmog)")
        ST.Redraw()
        W.PlaySound("IG_QUEST_LIST_SELECT")
    end)
end

-- Put an item on. slot: the slot it was dropped on (a one-hand weapon can
-- go in either hand); otherwise its own slot.
local pendingItem
function ST.TryOn(item, slot)
    if not view then return end
    if type(item) == "string" then item = strtrim(item) end
    if item == nil or item == "" then return end
    local own, why = P.ItemSlot(item)
    if why == "wait" then
        pendingItem = { item = item, slot = slot }
        ST.Status("Fetching that item...")
        return
    end
    if not own then
        ST.Status(W.Hex(C.red) .. "That can't be worn.|r")
        return
    end
    if slot and slot ~= own and not ((slot == 16 or slot == 17) and (own == 16 or own == 17)) then
        ST.Status(W.Hex(C.red) .. "That doesn't go there.|r")
        return
    end
    slot = slot or own
    Cur().slots[slot] = P.SlotFor(item)
    view.stash[slot] = nil
    view.itemBox:SetText("")
    ST.Status("Trying on: " .. (L.SLOT[slot] and L.SLOT[slot].name or "item"))
    ST.Redraw()
end

ns.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
    if not pendingItem then return end
    local want = P.ItemId(pendingItem.item)
    if want and id and want ~= id then return end
    local p = pendingItem
    pendingItem = nil
    if ok == false then return ST.Status(W.Hex(C.red) .. "There's no item with that id.|r") end
    ST.TryOn(p.item, p.slot)
end)

ns.On("PLAYER_TARGET_CHANGED", function() if view and view.pic:IsVisible() then ST.Paint() end end)
ns.On("GROUP_ROSTER_UPDATE", function() if view and view.pic:IsVisible() then ST.Paint() end end)

-- Shift-click on an item anywhere (chat, bags, loot) tries it on while the
-- Studio is open.
if hooksecurefunc and HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not (view and view.pic:IsVisible() and IsShiftKeyDown and IsShiftKeyDown()) then return end
        if type(link) == "string" and link:find("item:", 1, true) then ST.TryOn(link) end
    end)
end

function ST.Post()
    local look = view.look
    local caption = view.caption:GetText() or ""
    local id
    if view.editing then
        id = view.editing
        S.Edit(id, caption, L.Encode(look))
        view.editing = nil
    else
        local share = view.guildOnly:GetChecked() and S.HasGuild() and "guild" or nil
        local post = S.Post(L.Encode(look), caption, nil, share)
        id = post.id
        ns.Bots.React(post)
    end
    W.PlaySound("IG_QUEST_LIST_COMPLETE")
    ST.Fresh()
    ns.UI:OpenPost(id)
end

-- From a post: change your own post, or try someone's look on yourself.
function ST.Edit(post)
    ns.UI:Show("studio")
    view.editing = post.id
    view.look = L.Decode(post.look)
    view.sel, view.stashes = 0, { [0] = {} }
    view.stash = view.stashes[0]
    view.caption:SetText(post.caption or "")
    view.guildOnly:SetChecked(post.share == "guild")
    ST.LoadText()
    ST.Redraw()
    ST.Status("Editing your picture")
end

-- who: whose look in a group picture (0 or nil: the poster's, and you take
-- their place in the whole picture; else that person's outfit on you, in
-- the picture's pose, backdrop and effects, on your own).
function ST.Remix(post, who)
    ns.UI:Show("studio")
    view.editing = nil
    local look = L.Decode(post.look)
    local q = who and who > 0 and look.people[who]
    if q then
        look.slots = q.slots
        look.pose, look.yaw, look.drawn, look.lens, look.face, look.still = q.pose, q.yaw, q.drawn, q.lens, q.face, q.still
        look.mx, look.my = 0, 0
        look.people = {}
    end
    L.Me(look)
    view.look = look
    view.sel, view.stashes = 0, { [0] = {} }
    view.stash = view.stashes[0]
    view.caption:SetText("")
    ST.LoadText()
    ST.Redraw()
    ST.Status("Trying on " .. ns.Display(q and q.name or post.author) .. "'s look")
end

---------------------------------------------------------------------------
-- Drawing the controls
---------------------------------------------------------------------------
function ST.Paint()
    if not (view and view.look) then return end
    local look = view.look
    local who = Cur()
    for _, b in ipairs(view.slots) do
        local s = who.slots[b.slot]
        local stashed = not s and view.stash[b.slot]
        b.icon:SetTexture((s or stashed) and P.SlotIcon(s or stashed) or EmptyIcon(b.slot))
        b.icon:SetDesaturated(stashed and true or false)
        b.icon:SetAlpha(stashed and 0.4 or 1)
        b:SetChosen(s ~= nil)
    end
    -- Chips: the chosen one is white.
    for _, b in ipairs(view.poses) do b:SetStyle(b.key == who.pose and "light" or "secondary") end
    for _, b in ipairs(view.frames) do b:SetStyle(b.key == look.frame and "light" or "secondary") end
    for _, b in ipairs(view.tiles) do
        if b.field then b:SetChosen(look[b.field] == b.key) end
    end
    local lens = who.lens or "none"
    for _, b in ipairs(view.lensTiles) do b:SetChosen(b.key == lens) end
    for _, b in ipairs(view.faceTiles) do b:SetChosen(b.key == (who.face or "none")) end
    for _, b in ipairs(view.tiles) do
        if b.isText then
            b:SetChosen(b.key == ((look.text and look.text.style) or view.textStyle or "bar"))
        end
    end
    local nSt = #(look.stickers or {})
    view.stickerRemove:SetEnabled(view.pic.stickerSelected ~= nil and look.stickers[view.pic.stickerSelected] ~= nil)
    view.stickerClear:SetEnabled(nSt > 0)
    view.stickerPane.chosen:SetText(nSt == 0 and "No stickers yet" or (nSt .. " of " .. L.MAX_STICKERS .. " stickers"))
    view.textPane.chosen:SetText((L.TEXT_STYLE[(look.text and look.text.style) or view.textStyle or "bar"] or {}).name or "")
    view.decoPane.chosen:SetText((L.DECO[look.deco or "none"] or L.DECO.none).name)
    view.motionPane.chosen:SetText((L.MOTION[look.motion or "none"] or L.MOTION.none).name)
    for _, b in ipairs(view.tiles) do
        if b.isSticker then b:SetChosen(b.key == view.placing) end
    end
    local face = L.FACE[who.face or "none"] or L.FACE.none
    view.lensPane.chosen:SetText((face.key ~= "none" and (face.name .. "  +  ") or "") .. (L.LENS[lens] or L.LENS.none).name)
    for _, b in ipairs(view.swatches) do b.ring:SetShown(look.bg == "custom" and look[b.field] == b.hex) end
    local bg = L.BACKGROUND[look.bg] or L.BACKGROUND.normal
    view.bgPane.chosen:SetText(bg.name)
    local f, o = L.FILTER[look.filter] or L.FILTER.normal, L.OVERLAY[look.overlay or "none"] or L.OVERLAY.none
    view.filterPane.chosen:SetText(f.name)
    view.overlayPane.chosen:SetText(o.name)
    view.drawn:SetChecked(who.drawn and true or false)
    view.me:SetPlayer(ns.Me(), select(2, UnitClass("player")))
    view.meName:SetText(ns.Display(ns.Me()))
    view.meWhat:SetText(view.editing and "Editing your picture" or "New post")
    view.still:SetChecked(who.still and true or false)

    -- People.
    for i = 0, L.MAX_PEOPLE - 1 do
        local r = view.people[i]
        local p = i == 0 and look or look.people[i]
        if p then
            local id = i == 0 and ns.Me() or p.name
            r.avatar:SetPlayer(id, p.class)
            r.name:SetText(i == 0 and (ns.Display(ns.Me()) .. W.Hex(C.dim) .. "  (you)|r") or ns.Display(id or "?"))
            r.mark:SetShown(i == view.sel)
            r.remove:SetShown(i > 0)
            r:Show()
        else
            r:Hide()
        end
    end
    local full = #look.people >= L.MAX_PEOPLE - 1
    local inPic = {}
    for _, q in ipairs(look.people) do inPic[q.name or ""] = true end
    local cands = ST.Candidates()
    for i, b in ipairs(view.adds) do
        local c = cands[i]
        if c then
            b.unit = c.unit
            local already = inPic[c.id]
            b:SetText((already and "In the picture: " or "+ Add ") .. ns.Display(c.id)
                .. (c.unit == "target" and W.Hex(C.dim) .. "  (target)|r" or ""))
            b:SetEnabled(not already and not full)
            b:Show()
        else
            b.unit = nil
            b:Hide()
        end
    end
    view.addHint:SetText(full and "The picture is full (4 people)."
        or (#cands == 0 and "Target a player or group up: only people you can see." or ""))
    view.post:SetText(view.editing and "Save" or "Share")
    -- Guild only: greyed out with no guild, and fixed once shared.
    local canGuild = S.HasGuild() and not view.editing
    if not S.HasGuild() and not view.editing then view.guildOnly:SetChecked(false) end
    view.guildOnly:SetEnabled(canGuild)
    view.guildOnly:SetAlpha(canGuild and 1 or 0.4)
    view.guildLabel:SetAlpha(canGuild and 1 or 0.4)
    view.naked:SetText(ST.AllOff() and "Put all on" or "Take all off")
    view.naked:SetEnabled(next(look.slots) ~= nil or next(view.stash) ~= nil)
    view.cancelEdit:SetShown(view.editing ~= nil)
end
