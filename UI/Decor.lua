-- Decor: what's laid on top of a picture: stickers, a line of text (in a
-- style: a Snapchat bar, comic, neon, a raid warning, an achievement, epic
-- loot...) and a frame around it (Polaroid, Wanted poster, film, breaking
-- news...). All of it is textures and text drawn here, sized from the
-- picture, so it looks the same at any size and in any client.
--
-- UI\Picture.lua makes pic.decor (above the filter, under the badge) and
-- calls Decor.Apply whenever the look changes. Create's previews use
-- Decor.DrawFrame and Decor.DrawText on their tiles.
local ADDON, ns = ...

local D = {}
ns.Decor = D
local L = ns.Look

local ART = "Interface\\AddOns\\Wowstagram\\Art\\"
local BODY_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FANCY_FONT = "Fonts\\MORPHEUS.TTF"

---------------------------------------------------------------------------
-- Pools: textures and font strings on a holder, reused on every redraw.
---------------------------------------------------------------------------
local function Begin(holder)
    holder.dTex = holder.dTex or {}
    holder.dStr = holder.dStr or {}
    for _, t in ipairs(holder.dTex) do t:Hide() end
    for _, s in ipairs(holder.dStr) do s:Hide() end
    holder.nTex, holder.nStr = 0, 0
end

local function Tex(holder, layer, sub)
    holder.nTex = holder.nTex + 1
    local t = holder.dTex[holder.nTex]
    if not t then
        t = holder:CreateTexture(nil, "ARTWORK")
        holder.dTex[holder.nTex] = t
    end
    t:SetDrawLayer(layer or "ARTWORK", sub or 0)
    t:SetTexture(nil)
    t:SetTexCoord(0, 1, 0, 1)
    t:SetVertexColor(1, 1, 1, 1)
    t:SetAlpha(1)
    t:SetBlendMode("BLEND")
    if t.SetRotation then t:SetRotation(0) end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function Rect(holder, x, y, w, h, c, layer, sub)
    local t = Tex(holder, layer, sub)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    t:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
    t:SetSize(math.max(1, w), math.max(1, h))
    return t
end

local function Str(holder, font, size, flags, color, layer)
    holder.nStr = holder.nStr + 1
    local s = holder.dStr[holder.nStr]
    if not s then
        s = holder:CreateFontString(nil, "OVERLAY")
        holder.dStr[holder.nStr] = s
    end
    s:SetDrawLayer(layer or "OVERLAY", 7)
    s:SetFont(font, math.max(6, math.floor(size + 0.5)), flags or "")
    local c = color or { 1, 1, 1 }
    s:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    s:SetShadowOffset(0, 0)
    s:SetJustifyH("CENTER")
    s:SetJustifyV("MIDDLE")
    if s.SetWordWrap then s:SetWordWrap(false) end
    s:SetWidth(0)
    s:ClearAllPoints()
    s:Show()
    return s
end

-- Text that must fit: shrinks until it's no wider than maxW (never cut
-- off), then is centred in that width.
local function Fit(s, maxW)
    if not (s.GetStringWidth and maxW and maxW > 0) then return end
    s:SetWidth(0)
    local font, size, flags = s:GetFont()
    size = size or 12
    local tries = 0
    while (s:GetStringWidth() or 0) > maxW and size > 6 and tries < 25 do
        size = size * 0.9
        s:SetFont(font, size, flags or "")
        tries = tries + 1
    end
    s:SetWidth(maxW)
end

-- A line of text at (x, y) from the top left, at most maxW wide.
local function Line(holder, font, size, flags, color, x, y, maxW, text)
    local s = Str(holder, font, size, flags, color)
    s:SetText(text)
    Fit(s, maxW)
    s:SetPoint("CENTER", holder, "TOPLEFT", x, -y)
    return s
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
-- Draw frame `key` on holder (w x h). who: a name, for the frames that
-- show one.
function D.DrawFrame(holder, key, w, h, who)
    if not key or key == "none" then return end
    local u = w / 100 -- one percent of the width
    local name = who and ns.Display(who)
    if key == "polaroid" then
        local white = { 0.97, 0.96, 0.93 }
        Rect(holder, 0, 0, w, 5 * u, white)
        Rect(holder, 0, 0, 5 * u, h, white)
        Rect(holder, w - 5 * u, 0, 5 * u, h, white)
        Rect(holder, 0, h - 18 * u, w, 18 * u, white)
        Line(holder, FANCY_FONT, 7 * u, "", { 0.25, 0.25, 0.3 }, w / 2, h - 9 * u, 86 * u, name or "Wowstagram")
    elseif key == "gold" then
        local gold, dark = { 0.86, 0.66, 0.22 }, { 0.45, 0.3, 0.08 }
        Rect(holder, 0, 0, w, 4 * u, gold); Rect(holder, 0, h - 4 * u, w, 4 * u, gold)
        Rect(holder, 0, 0, 4 * u, h, gold); Rect(holder, w - 4 * u, 0, 4 * u, h, gold)
        Rect(holder, 4 * u, 4 * u, w - 8 * u, u * 0.8, dark); Rect(holder, 4 * u, h - 4.8 * u, w - 8 * u, u * 0.8, dark)
        Rect(holder, 4 * u, 4 * u, u * 0.8, h - 8 * u, dark); Rect(holder, w - 4.8 * u, 4 * u, u * 0.8, h - 8 * u, dark)
        for _, c in ipairs({ { 0, 0 }, { w - 9 * u, 0 }, { 0, h - 9 * u }, { w - 9 * u, h - 9 * u } }) do
            Rect(holder, c[1], c[2], 9 * u, 9 * u, { 1, 0.85, 0.4 })
        end
    elseif key == "wanted" then
        local paper, ink = { 0.86, 0.74, 0.5 }, { 0.3, 0.17, 0.06 }
        Rect(holder, 0, 0, w, 24 * u, paper); Rect(holder, 0, h - 26 * u, w, 26 * u, paper)
        Rect(holder, 0, 0, 7 * u, h, paper); Rect(holder, w - 7 * u, 0, 7 * u, h, paper)
        Line(holder, FANCY_FONT, 17 * u, "", ink, w / 2, 12 * u, 86 * u, "WANTED")
        Line(holder, BODY_FONT, 6 * u, "", ink, w / 2, h - 18 * u, 86 * u, "DEAD OR ALIVE")
        Line(holder, FANCY_FONT, 7 * u, "", { 0.55, 0.1, 0.05 }, w / 2, h - 8 * u, 86 * u, "REWARD: 1,000 GOLD")
    elseif key == "film" then
        local black = { 0.03, 0.03, 0.03 }
        Rect(holder, 0, 0, 9 * u, h, black); Rect(holder, w - 9 * u, 0, 9 * u, h, black)
        local n = math.max(4, math.floor(h / (9 * u)))
        for i = 0, n - 1 do
            local y = (i + 0.25) * h / n
            Rect(holder, 2.5 * u, y, 4 * u, 4 * u, { 0.92, 0.92, 0.88 })
            Rect(holder, w - 6.5 * u, y, 4 * u, 4 * u, { 0.92, 0.92, 0.88 })
        end
    elseif key == "neon" then
        local pink, cyan = { 1, 0.2, 0.85 }, { 0.2, 0.95, 1 }
        for _, c in ipairs({ { 1.5, pink }, { 4, cyan } }) do
            local o, col = c[1] * u, c[2]
            Rect(holder, o, o, w - 2 * o, u, col); Rect(holder, o, h - o - u, w - 2 * o, u, col)
            Rect(holder, o, o, u, h - 2 * o, col); Rect(holder, w - o - u, o, u, h - 2 * o, col)
        end
    elseif key == "hearts" then
        local size = 8 * u
        local nx, ny = math.floor(w / (size * 1.25)), math.floor(h / (size * 1.25))
        local function Heart(x, y, i)
            local t = Tex(holder, "ARTWORK", 1)
            t:SetTexture(ART .. "Heart")
            local c = (i % 2 == 0) and { 1, 0.3, 0.5 } or { 1, 0.6, 0.75 }
            t:SetVertexColor(c[1], c[2], c[3])
            t:SetSize(size, size)
            t:SetPoint("CENTER", holder, "TOPLEFT", x, -y)
        end
        for i = 0, nx do
            Heart(size / 2 + i * (w - size) / nx, size / 2, i)
            Heart(size / 2 + i * (w - size) / nx, h - size / 2, i + 1)
        end
        for i = 1, ny - 1 do
            Heart(size / 2, size / 2 + i * (h - size) / ny, i)
            Heart(w - size / 2, size / 2 + i * (h - size) / ny, i + 1)
        end
    elseif key == "comic" then
        local black = { 0, 0, 0 }
        Rect(holder, 0, 0, w, 3 * u, black); Rect(holder, 0, h - 3 * u, w, 3 * u, black)
        Rect(holder, 0, 0, 3 * u, h, black); Rect(holder, w - 3 * u, 0, 3 * u, h, black)
        Rect(holder, 5 * u, 5 * u, 50 * u, 11 * u, black)
        Rect(holder, 5.8 * u, 5.8 * u, 48.4 * u, 9.4 * u, { 1, 0.9, 0.2 })
        Line(holder, BODY_FONT, 5.5 * u, "", black, 30 * u, 10.5 * u, 44 * u, "MEANWHILE...")
    elseif key == "news" then
        Rect(holder, 0, h - 15 * u, w, 15 * u, { 0.05, 0.05, 0.1, 0.92 })
        Rect(holder, 0, h - 15 * u, 42 * u, 15 * u, { 0.8, 0.05, 0.05 })
        Line(holder, BODY_FONT, 5.5 * u, "OUTLINE", { 1, 1, 1 }, 21 * u, h - 7.5 * u, 38 * u, "BREAKING NEWS")
        Line(holder, BODY_FONT, 4.5 * u, "", { 1, 1, 1 }, 71 * u, h - 7.5 * u, 54 * u, (name or "Someone") .. " spotted in Azeroth")
        Rect(holder, 5 * u, 5 * u, 14 * u, 7 * u, { 0.85, 0.05, 0.05 })
        Line(holder, BODY_FONT, 4.5 * u, "", { 1, 1, 1 }, 12 * u, 8.5 * u, 12 * u, "LIVE")
    elseif key == "magazine" then
        Line(holder, FANCY_FONT, 15 * u, "THICKOUTLINE", { 1, 1, 1 }, w / 2, 10 * u, 92 * u, "WOWSTAGRAM")
        Line(holder, BODY_FONT, 4 * u, "OUTLINE", { 1, 0.85, 0.2 }, w / 2, 19 * u, 80 * u, "THE AZEROTH ISSUE")
        local ex = Line(holder, BODY_FONT, 5 * u, "OUTLINE", { 1, 1, 1 }, 36 * u, h - 14 * u, 62 * u, "EXCLUSIVE:")
        ex:SetJustifyH("LEFT")
        local nm = Line(holder, FANCY_FONT, 8 * u, "OUTLINE", { 1, 0.85, 0.2 }, 36 * u, h - 7 * u, 62 * u, name or "You")
        nm:SetJustifyH("LEFT")
    elseif key == "boss" then
        Rect(holder, 6 * u, 4 * u, 88 * u, 12 * u, { 0, 0, 0, 0.75 })
        Rect(holder, 7 * u, 5 * u, 86 * u, 10 * u, { 0.12, 0.02, 0.02 })
        Rect(holder, 7 * u, 5 * u, 86 * u * 0.87, 10 * u, { 0.75, 0.08, 0.05 })
        local skull = Tex(holder, "ARTWORK", 3)
        skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
        skull:SetSize(9 * u, 9 * u)
        skull:SetPoint("CENTER", holder, "TOPLEFT", 12 * u, -10 * u)
        Line(holder, BODY_FONT, 5 * u, "OUTLINE", { 1, 1, 1 }, 55 * u, 10 * u, 70 * u, (name or "Boss") .. "  87%")
    end
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- Draw a line of text in a style, its middle at y (pixels from the top).
-- Long text shrinks to fit (never cut off).
function D.DrawText(holder, text, style, y, w)
    if not text or text == "" then return end
    local u = w / 100
    local mid = w / 2
    if style == "bar" then
        local bar = Rect(holder, 0, y - 5 * u, w, 10 * u, { 0, 0, 0, 0.55 })
        bar:SetDrawLayer("ARTWORK", 4)
        Line(holder, BODY_FONT, 5.5 * u, "", { 1, 1, 1 }, mid, y, w - 6 * u, text)
    elseif style == "big" then
        Line(holder, BODY_FONT, 9 * u, "THICKOUTLINE", { 1, 1, 1 }, mid, y, w - 6 * u, text)
    elseif style == "comic" then
        Line(holder, BODY_FONT, 8 * u, "THICKOUTLINE", { 1, 0.9, 0.15 }, mid, y, w - 6 * u, text)
    elseif style == "neon" then
        local glow = Tex(holder, "ARTWORK", 4)
        glow:SetTexture(ART .. "Glow")
        glow:SetVertexColor(1, 0.2, 0.85, 0.6)
        glow:SetBlendMode("ADD")
        glow:SetSize(w * 0.9, 16 * u)
        glow:SetPoint("CENTER", holder, "TOPLEFT", mid, -y)
        Line(holder, BODY_FONT, 7.5 * u, "OUTLINE", { 1, 0.75, 0.98 }, mid, y, w - 6 * u, text)
    elseif style == "fancy" then
        Line(holder, FANCY_FONT, 10 * u, "OUTLINE", { 1, 0.82, 0.1 }, mid, y, w - 6 * u, text)
    elseif style == "raid" then
        Line(holder, BODY_FONT, 7 * u, "THICKOUTLINE", { 1, 0.55, 0.05 }, mid, y, w - 6 * u, text)
    elseif style == "achievement" then
        -- WoW's "Achievement Earned" toast, drawn: a dark box with a gold
        -- edge; the shield with its points on the left; the title and your
        -- words to the right of it.
        local bw, bh = 90 * u, 20 * u
        local x0, y0 = (w - bw) / 2, y - bh / 2
        Rect(holder, x0, y0, bw, bh, { 0.75, 0.6, 0.25 }, "ARTWORK", 4)
        Rect(holder, x0 + 0.8 * u, y0 + 0.8 * u, bw - 1.6 * u, bh - 1.6 * u, { 0.07, 0.06, 0.05, 0.95 }, "ARTWORK", 5)
        local shield = Tex(holder, "ARTWORK", 6)
        shield:SetTexture(ART .. "Shield")
        shield:SetVertexColor(1, 0.8, 0.25)
        shield:SetSize(13 * u, 13 * u)
        shield:SetPoint("CENTER", holder, "TOPLEFT", x0 + 10 * u, -y)
        Line(holder, BODY_FONT, 4.2 * u, "OUTLINE", { 1, 1, 1 }, x0 + 10 * u, y, 9 * u, "10")
        local areaX, areaW = x0 + 19 * u, bw - 22 * u
        Line(holder, BODY_FONT, 4 * u, "", { 1, 0.82, 0.1 }, areaX + areaW / 2, y - 4.5 * u, areaW, "Achievement Earned")
        Line(holder, BODY_FONT, 5 * u, "", { 1, 1, 1 }, areaX + areaW / 2, y + 3.5 * u, areaW, text)
    elseif style == "loot" then
        local bw, bh = 88 * u, 15 * u
        local x0, y0 = (w - bw) / 2, y - bh / 2
        Rect(holder, x0, y0, bw, bh, { 0.64, 0.21, 0.93 }, "ARTWORK", 4)
        Rect(holder, x0 + 0.7 * u, y0 + 0.7 * u, bw - 1.4 * u, bh - 1.4 * u, { 0.03, 0.03, 0.08, 0.95 }, "ARTWORK", 5)
        local bag = Tex(holder, "ARTWORK", 6)
        bag:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        bag:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bag:SetSize(11 * u, 11 * u)
        bag:SetPoint("CENTER", holder, "TOPLEFT", x0 + 8 * u, -y)
        local areaX, areaW = x0 + 15 * u, bw - 18 * u
        Line(holder, BODY_FONT, 5.5 * u, "", { 0.75, 0.4, 1 }, areaX + areaW / 2, y, areaW, "[" .. text .. "]")
    elseif style == "levelup" then
        Line(holder, FANCY_FONT, 12 * u, "OUTLINE", { 1, 0.82, 0.1 }, mid, y - 4 * u, w - 10 * u, "LEVEL UP!")
        Line(holder, BODY_FONT, 5 * u, "OUTLINE", { 1, 1, 1 }, mid, y + 6 * u, w - 6 * u, text)
    end
end

---------------------------------------------------------------------------
-- Stickers
---------------------------------------------------------------------------
function D.DrawSticker(holder, def, x, y, size, rot)
    local t = Tex(holder, "ARTWORK", 2)
    t:SetTexture(def.tex)
    if def.icon then t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif def.coords then t:SetTexCoord(def.coords[1], def.coords[2], def.coords[3], def.coords[4]) end
    local c = def.color or { 1, 1, 1 }
    t:SetVertexColor(c[1], c[2], c[3])
    t:SetSize(size, size)
    t:SetPoint("CENTER", holder, "TOPLEFT", x, -y)
    if rot and rot ~= 0 and t.SetRotation then t:SetRotation(math.rad(rot)) end
    return t
end

---------------------------------------------------------------------------
-- A picture's decor
---------------------------------------------------------------------------
function D.Setup(pic, level)
    local f = CreateFrame("Frame", nil, pic)
    f:SetAllPoints()
    f:SetFrameLevel(level)
    if f.SetClipsChildren then f:SetClipsChildren(true) end
    pic.decor = f
end

function D.Apply(pic)
    local f = pic.decor
    if not f then return end
    Begin(f)
    local look = pic.look
    if not look then return end
    local w, h = pic:GetWidth() or 0, pic:GetHeight() or 0
    if w <= 0 or h <= 0 then return end
    pic.faceAnims = {}
    if pic.Heads then
        for _, head in ipairs(pic:Heads()) do
            local def = L.FACE[head.person.face or "none"]
            if def and def.key ~= "none" and not head.back then
                D.DrawFace(f, def, head.x, head.y, head.size, head.turn, head.name, pic.faceAnims)
            end
        end
        if #pic.faceAnims > 0 and ns.Fx.Kick then ns.Fx.Kick(pic) end
        if ns.Picture.faceGrid then
            for _, head in ipairs(pic:Heads()) do
                D.DrawGrid(f, head)
                -- Tuning: keep what the camera saw with the tuned face, to
                -- work out each race's head (dev/NOTES.md).
                if head.tuned and ns.db then
                    local o = head.obs
                    ns.db.faceObs = ns.db.faceObs or {}
                    ns.db.faceObs[head.key] = { half = o.half, camz = o.camz, camy = o.camy, wy = o.wy, z1 = o.z1,
                        bodyH = o.bodyH, w = o.w, h = o.h, x = head.x, y = head.y, size = head.size, zoom = look.zoom or 100 }
                end
            end
        end
    end
    pic.stickerTex = {}
    for i, s in ipairs(look.stickers or {}) do
        local def = L.STICKER[s.key]
        if def then
            local t = D.DrawSticker(f, def, s.x / 100 * w, s.y / 100 * h, s.s / 100 * w, s.r)
            pic.stickerTex[i] = t
            if pic.stickerSelected == i and pic.interactive then
                local ring = Tex(f, "ARTWORK", 1)
                ring:SetTexture(ART .. "Glow")
                ring:SetVertexColor(1, 1, 1, 0.5)
                ring:SetBlendMode("ADD")
                ring:SetSize(s.s / 100 * w * 1.5, s.s / 100 * w * 1.5)
                ring:SetPoint("CENTER", f, "TOPLEFT", s.x / 100 * w, -s.y / 100 * h)
            end
        end
    end
    if look.text then D.DrawText(f, look.text.text, look.text.style, (look.text.y or 70) / 100 * h, w) end
    D.DrawFrame(f, look.deco, w, h, pic.author)
end

---------------------------------------------------------------------------
-- Face filters: drawn on each head the picture says is there.
---------------------------------------------------------------------------
-- One part of a face filter at (cx, cy) for a head `H` pixels high.
local function FacePart(holder, part, cx, cy, H, turn, anims)
    local t = Tex(holder, "ARTWORK", 3)
    t:SetTexture(part[1])
    if part.flip then t:SetTexCoord(1, 0, 0, 1) end
    local c = part.c or { 1, 1, 1 }
    t:SetVertexColor(c[1], c[2], c[3])
    t:SetAlpha(part.alpha or 1)
    if part.add then t:SetBlendMode("ADD") end
    -- Things on the face move with a turned head; things above it less.
    local shift = (part[3] > -0.6 and 0.3 or 0.1) * turn * H
    local x, y = cx + part[2] * H + shift, cy + part[3] * H
    t:SetSize(part[4] * H, part[5] * H)
    t:SetPoint("CENTER", holder, "TOPLEFT", x, -y)
    if part.rot and t.SetRotation then t:SetRotation(part.rot) end
    if part.anim and anims then
        anims[#anims + 1] = { tex = t, x = x, y = y, H = H, kind = part.anim, i = part.i or 0, holder = holder }
    end
    return t
end

-- A WoW nameplate over the head: the name and a full health bar.
local function Nameplate(holder, cx, cy, H, name)
    local bw, bh = 1.7 * H, 0.16 * H
    local top = cy - 1.0 * H
    Rect(holder, cx - bw / 2 - 1, top - 1, bw + 2, bh + 2, { 0, 0, 0, 0.8 }, "ARTWORK", 3)
    Rect(holder, cx - bw / 2, top, bw, bh, { 0.1, 0.85, 0.15 }, "ARTWORK", 4)
    Line(holder, BODY_FONT, math.max(7, 0.22 * H), "OUTLINE", { 1, 1, 1 }, cx, top - 0.2 * H, 2.4 * H,
        name and ns.Display(name) or "Adventurer")
end

-- Draw face filter `def` on a head at (cx, cy), `H` pixels high.
function D.DrawFace(holder, def, cx, cy, H, turn, name, anims)
    if not def or def.key == "none" then return end
    if def.nameplate then return Nameplate(holder, cx, cy, H, name) end
    for _, part in ipairs(def.parts or {}) do FacePart(holder, part, cx, cy, H, turn or 0, anims) end
end

-- The tuning grid: lines a quarter head apart round the head (numbered,
-- + down), red through where the eyes should be, a box the head's size.
function D.DrawGrid(holder, head)
    local H, cx, cy = head.size, head.x, head.y
    for k = -4, 4 do
        local y = cy + k * 0.25 * H
        Rect(holder, cx - 0.9 * H, y, 1.8 * H, 1, k == 0 and { 1, 0.1, 0.1, 0.9 } or { 1, 1, 1, 0.35 }, "OVERLAY", 6)
        if k ~= 0 and k % 2 == 0 then
            local s = Str(holder, BODY_FONT, math.max(7, 0.13 * H), "OUTLINE", { 1, 1, 0.4 })
            s:SetPoint("LEFT", holder, "TOPLEFT", cx + 0.92 * H, -y)
            s:SetText(k > 0 and ("+" .. k) or tostring(k))
        end
    end
    Rect(holder, cx, cy - 1.0 * H, 1, 2.0 * H, { 1, 0.1, 0.1, 0.6 }, "OVERLAY", 6)
    Rect(holder, cx - 0.5 * H, cy - 0.55 * H, 1, H, { 0.3, 1, 0.3, 0.6 }, "OVERLAY", 6)
    Rect(holder, cx + 0.5 * H, cy - 0.55 * H, 1, H, { 0.3, 1, 0.3, 0.6 }, "OVERLAY", 6)
end

-- The moving parts (from UI\Fx.lua's OnUpdate).
function D.StepFaces(pic, t)
    for _, a in ipairs(pic.faceAnims or {}) do
        local tex, H = a.tex, a.H
        local x, y, alpha = a.x, a.y, 1
        if a.kind == "bob" then
            y = y + math.sin(t * 2.2) * 0.04 * H
        elseif a.kind == "orbit" then
            local ang = t * 2.2 + a.i * 2.094
            x, y = x + math.cos(ang) * 0.38 * H, y + math.sin(ang) * 0.12 * H
        elseif a.kind == "rise" then
            local p = (t * 0.35 + a.i / 3) % 1
            x, y, alpha = x + p * 0.25 * H, y - p * 0.6 * H, 1 - p
            tex:SetSize((0.1 + p * 0.12) * H, (0.1 + p * 0.12) * H)
        elseif a.kind == "drip" then
            local p = (t * 0.55 + a.i * 0.5) % 1
            y, alpha = y + p * 0.45 * H, 1 - p
        end
        tex:SetAlpha(alpha)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", a.holder, "TOPLEFT", x, -y)
    end
end

-- The sticker under (x, y) (pixels from the picture's top left), topmost
-- first: its index.
function D.StickerAt(pic, x, y)
    local look = pic.look
    local w, h = pic:GetWidth() or 1, pic:GetHeight() or 1
    for i = #(look and look.stickers or {}), 1, -1 do
        local s = look.stickers[i]
        local r = s.s / 100 * w * 0.6
        if math.abs(x - s.x / 100 * w) <= r and math.abs(y - s.y / 100 * h) <= r then return i end
    end
end

-- Previews in Create.
function D.PreviewFrame(holder, key, w, h)
    Begin(holder)
    D.DrawFrame(holder, key, w, h, nil)
end

function D.PreviewText(holder, style, w, h)
    Begin(holder)
    local sample = { bar = "gg", big = "WOW", comic = "BAM!", neon = "vibes", fancy = "Azeroth", raid = "RUN!",
        achievement = "Died to Hogger", loot = "Thunderfury", levelup = "Level 60!" }
    D.DrawText(holder, sample[style] or "Aa", style, h / 2, w)
end

function D.PreviewFace(holder, def, w, h)
    Begin(holder)
    local H = h * 0.42
    local head = Tex(holder, "ARTWORK", 0)
    head:SetTexture(ART .. "Circle")
    head:SetVertexColor(0.93, 0.76, 0.62)
    head:SetSize(H * 0.8, H)
    head:SetPoint("CENTER", holder, "TOPLEFT", w / 2, -h * 0.6)
    D.DrawFace(holder, def, w / 2, h * 0.6, H, 0, "You", nil)
end

function D.PreviewSticker(holder, def, w, h)
    Begin(holder)
    D.DrawSticker(holder, def, w / 2, h / 2, math.min(w, h) * 0.7, 0)
end
