-- Fx: the fun on top of a picture. Filters that fade a colour from top to
-- bottom, darken the edges or turn people see-through; Motion (colours that
-- cycle, flashes, a flickering light, a swaying or shaking camera);
-- backgrounds that move; and overlays (snow, hearts, fireworks...) drifting
-- over the picture. All of it is drawn by the addon (textures and the
-- scene's camera and light), so it looks the same on Retail and WoW Forever.
--
-- UI\Picture.lua calls Fx.Setup once per picture and Fx.Apply whenever the
-- look changes. Only pictures that move get an OnUpdate, and frames that
-- aren't shown don't run it.
local _, ns = ...

local Fx = {}
ns.Fx = Fx
local L = ns.Look

local ART = "Interface\\AddOns\\Wowstagram\\Art\\"

local function Rand(a, b) return a + math.random() * (b - a) end

-- "ff8800" -> { 1, 0.53, 0 }
function Fx.Hex(hex)
    hex = type(hex) == "string" and hex or "808080"
    local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return { 0.5, 0.5, 0.5 } end
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

-- Hue (0..1) to a bright colour.
local function Hue(h, s, v)
    s, v = s or 0.85, v or 1
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
    return v, p, q
end

-- The background a look uses: its own two colours for "custom".
function Fx.Background(look)
    local bg = L.BACKGROUND[look and look.bg or "normal"] or L.BACKGROUND.normal
    if bg.key == "custom" then
        local top, bottom = Fx.Hex(look.bgTop or "ff8033"), Fx.Hex(look.bgBottom or "331a66")
        local light = { 0.75 + top[1] * 0.25, 0.75 + top[2] * 0.25, 0.75 + top[3] * 0.25 }
        return { key = "custom", name = bg.name, top = top, bottom = bottom, light = light }
    end
    return bg
end

-- A see-through colour fading from top to bottom.
local function SetGrad(tex, grad)
    local top, bottom = grad[1], grad[2]
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, "VERTICAL",
        CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]), CreateColor(top[1], top[2], top[3], top[4]))
    if not ok then tex:SetColorTexture(top[1], top[2], top[3], (top[4] + bottom[4]) / 2) end
end

-- The tint layers on any frame (a picture's pic.tint, or a tile in Create):
-- gradient and vignette (from the filter, or the motion), and two layers the
-- motion colours as it goes (fxHue) and flashes (fxFlash).
function Fx.Layers(holder, f, m)
    holder.fxGrad = holder.fxGrad or holder:CreateTexture(nil, "OVERLAY", nil, 1)
    holder.fxGrad:SetAllPoints()
    holder.fxVig = holder.fxVig or holder:CreateTexture(nil, "OVERLAY", nil, 2)
    holder.fxVig:SetAllPoints()
    holder.fxVig:SetTexture(ART .. "Vignette")
    holder.fxHue = holder.fxHue or holder:CreateTexture(nil, "OVERLAY", nil, 3)
    holder.fxHue:SetAllPoints()
    holder.fxHue:Hide()
    holder.fxFlash = holder.fxFlash or holder:CreateTexture(nil, "OVERLAY", nil, 4)
    holder.fxFlash:SetAllPoints()
    holder.fxFlash:Hide()
    local grad = (f and f.grad) or (m and m.grad)
    if grad then
        SetGrad(holder.fxGrad, grad)
        holder.fxGrad:Show()
    else
        holder.fxGrad:Hide()
    end
    local vig = math.max(f and f.vignette or 0, m and m.vignette or 0)
    holder.fxVig:SetVertexColor(1, 1, 1)
    holder.fxVig:SetAlpha(vig)
    holder.fxVig:SetShown(vig > 0)
end

---------------------------------------------------------------------------
-- Sprites: the moving bits of an overlay (or the stars of Starfield).
---------------------------------------------------------------------------
local function NewSprite(sprites, parent, layer)
    -- (stars go above the backdrop, which is BACKGROUND too)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, layer == "BACKGROUND" and 2 or 0)
    local s = { tex = tex }
    sprites[#sprites + 1] = s
    return s
end

-- (Re)start a sprite: at the top for things that fall, the bottom for
-- things that rise, an edge for things that cross, anywhere for the rest.
-- anywhere: the first time (spread over the picture already).
local function Spawn(s, def, anywhere, i, n)
    local m = def.motion
    local sp = def.speed or { 0.05, 0.1 }
    s.v = Rand(sp[1], sp[2])
    s.x, s.y = math.random(), math.random()
    s.drift = Rand(-0.03, 0.03)
    s.rot = Rand(0, 6.28)
    s.vr = def.spin and Rand(-def.spin, def.spin) or 0
    s.phase = Rand(0, 6.28)
    s.rate = Rand(1.5, 3.5)
    s.vx, s.vy = Rand(-0.05, 0.05), Rand(-0.05, 0.05)
    s.life, s.delay = 0, 0
    if m == "fall" then
        if not anywhere then s.y = -0.08 end
    elseif m == "rise" then
        if not anywhere then s.y = 1.08 end
    elseif m == "blow" then
        if not anywhere then s.x = -0.1 end
    elseif m == "diag" then
        s.x, s.y = Rand(0.2, 1.4), anywhere and Rand(-0.3, 1) or Rand(-0.6, -0.1)
    elseif m == "fountain" then
        s.x, s.y = 0.5 + Rand(-0.03, 0.03), 1.02
        s.vx, s.vy = Rand(-0.35, 0.35), -Rand(1.0, 1.45)
        s.delay = anywhere and Rand(0, 1.6) or Rand(0, 0.3)
    elseif m == "swim" then
        s.dir = math.random() < 0.5 and -1 or 1
        if not anywhere then s.x = s.dir > 0 and -0.1 or 1.1 end
        s.y = Rand(0.15, 0.9)
    elseif m == "beam" then
        s.x = ((i or 1) - 0.5) / (n or 1) + Rand(-0.05, 0.05)
        s.y = 0
    elseif m == "pop" then
        s.dur = Rand(0.7, 1.3)
        s.delay = anywhere and Rand(0, 1.5) or Rand(0, 0.6)
    elseif m == "burst" then
        s.life = 99 -- waits for its burst
    end
end

-- Make an overlay's sprites on `layer` (count scaled to the picture's size).
local function BuildSprites(fx, layer, def, w, sprites, texLayer)
    for _, s in ipairs(sprites) do s.tex:Hide() end
    sprites.groups = {}
    if not def or not (def.tex or def.texs) then return 0 end
    local scale = math.max(0.35, math.min(1.6, w / 356))
    local n = math.max(def.motion == "flash" and 1 or 3, math.floor((def.count or 10) * scale + 0.5))
    if def.motion == "flash" or def.motion == "beam" then n = def.count end
    for i = 1, n do
        local s = sprites[i] or NewSprite(sprites, layer, texLayer)
        local tex = s.tex
        tex:SetTexture(def.texs and def.texs[(i - 1) % #def.texs + 1] or def.tex)
        if def.icon then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
        tex:SetBlendMode(def.add and "ADD" or "BLEND")
        local c = def.colors and def.colors[math.random(#def.colors)] or { 1, 1, 1 }
        tex:SetVertexColor(c[1], c[2], c[3])
        s.size = Rand(def.size[1], def.size[2]) * math.max(0.6, scale)
        s.alpha = def.alpha or 1
        tex:SetAlpha(s.alpha)
        if tex.SetRotation then tex:SetRotation(0) end
        Spawn(s, def, true, i, n)
        tex:ClearAllPoints()
        tex:Show()
    end
    return n
end

local function Size(s, def, k)
    local size = s.size * (k or 1)
    if def.thin then s.tex:SetSize(size * 0.2, size)
    elseif def.flat then s.tex:SetSize(size, size * 0.55)
    elseif def.trail then s.tex:SetSize(size * 3, size)
    else s.tex:SetSize(size, size) end
end

local function MoveSprites(sprites, n, def, dt, t, w, h, layer)
    local m = def.motion
    for i = 1, n do
        local s = sprites[i]
        local tex = s.tex
        local k = 1
        local show = true
        if s.delay > 0 then
            s.delay = s.delay - dt
            show = false
        elseif m == "fall" then
            s.y = s.y + s.v * dt
            s.x = s.x + (s.drift + (def.thin and 0.08 or 0)) * dt
            if def.wobble then s.x = s.x + math.sin(t * s.rate + s.phase) * 0.04 * dt end
            if s.y > 1.08 then Spawn(s, def) end
        elseif m == "rise" then
            s.y = s.y - s.v * dt
            if def.wobble then s.x = s.x + math.sin(t * s.rate + s.phase) * 0.03 * dt end
            if def.grow then k = 1 + (1 - s.y) * def.grow end
            if def.grow then tex:SetAlpha(s.alpha * math.max(0, math.min(1, s.y * 1.3))) end
            if s.y < -0.08 then Spawn(s, def) end
        elseif m == "blow" then
            s.x = s.x + s.v * dt
            s.y = s.y + (s.v * 0.25 + math.sin(t * s.rate + s.phase) * 0.05) * dt
            if s.x > 1.15 or s.y > 1.1 then Spawn(s, def); s.x, s.y = Rand(-0.2, -0.05), Rand(-0.1, 0.9) end
        elseif m == "diag" then
            s.x = s.x - s.v * 0.6 * dt
            s.y = s.y + s.v * dt
            if s.y > 1.15 or s.x < -0.2 then Spawn(s, def) end
            if tex.SetRotation then tex:SetRotation(math.atan2(1, -0.6) + math.pi) end
        elseif m == "wander" then
            s.vx = s.vx + Rand(-0.1, 0.1) * dt
            s.vy = s.vy + Rand(-0.1, 0.1) * dt
            s.vx, s.vy = math.max(-0.06, math.min(0.06, s.vx)), math.max(-0.06, math.min(0.06, s.vy))
            s.x, s.y = (s.x + s.vx * dt) % 1, (s.y + s.vy * dt) % 1
            if not def.flap then tex:SetAlpha(s.alpha * (0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * s.rate + s.phase)))) end
        elseif m == "twinkle" then
            local a = 0.5 + 0.5 * math.sin(t * s.rate + s.phase)
            tex:SetAlpha(a * s.alpha)
            if a < 0.02 then s.x, s.y = math.random(), math.random() end
        elseif m == "fountain" then
            s.vy = s.vy + 1.3 * dt
            s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
            if s.y > 1.1 then Spawn(s, def) end
        elseif m == "swim" then
            s.x = s.x + s.dir * s.v * dt
            s.y = s.y + math.sin(t * s.rate + s.phase) * 0.02 * dt
            if s.dir > 0 then tex:SetTexCoord(0.92, 0.08, 0.08, 0.92) else tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            if s.x > 1.15 or s.x < -0.15 then Spawn(s, def) end
        elseif m == "beam" then
            tex:SetAlpha(s.alpha * (0.35 + 0.3 * math.sin(t * 0.8 + s.phase)))
            tex:ClearAllPoints()
            tex:SetPoint("TOP", layer, "TOPLEFT", s.x * w, 0)
            tex:SetSize(s.size * 0.6, h * 1.05)
            if tex.SetRotation then tex:SetRotation(math.sin(t * 0.2 + s.phase) * 0.06) end
        elseif m == "pop" then
            s.life = s.life + dt
            local p = s.life / s.dur
            k = 0.3 + math.min(1, p * 3) * 0.7
            tex:SetAlpha(s.alpha * math.max(0, 1 - math.max(0, p - 0.5) * 2))
            if p >= 1 then Spawn(s, def) end
        elseif m == "burst" then
            -- Every piece belongs to a burst of 12; a burst goes off at a
            -- random spot, pieces fly out, fall a little and fade.
            local g = math.floor((i - 1) / 12) + 1
            local grp = sprites.groups[g]
            if not grp or t >= grp.next then
                grp = { next = t + Rand(1.4, 2.4), x = Rand(0.15, 0.85), y = Rand(0.12, 0.5), start = t }
                sprites.groups[g] = grp
            end
            if s.burstOf ~= grp then
                s.burstOf = grp
                local a = Rand(0, 6.28)
                local sp = Rand(0.15, 0.32)
                s.x, s.y, s.vx, s.vy = grp.x, grp.y, math.cos(a) * sp, math.sin(a) * sp
            end
            s.vy = s.vy + 0.25 * dt
            s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
            local age = t - grp.start
            tex:SetAlpha(math.max(0, 1 - age / 1.2))
        elseif m == "flash" then
            show = false -- (Fx.Step shows the bolts when lightning strikes)
        end
        if def.flap then k = k * (0.4 + 0.6 * math.abs(math.sin(t * 9 + s.phase))) end
        if m ~= "beam" and m ~= "flash" then
            if m ~= "fountain" and m ~= "burst" and m ~= "diag" then
                if s.x > 1.08 then s.x = s.x - 1.16 elseif s.x < -0.08 then s.x = s.x + 1.16 end
            end
            if s.vr ~= 0 and tex.SetRotation then
                s.rot = s.rot + s.vr * dt
                tex:SetRotation(s.rot)
            end
            if def.flap then
                tex:SetSize(s.size * k, s.size)
            else
                Size(s, def, k)
            end
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", layer, "TOPLEFT", s.x * w, -s.y * h)
        end
        if m ~= "flash" then tex:SetShown(show) end
    end
end

---------------------------------------------------------------------------
-- A picture's effects
---------------------------------------------------------------------------
-- layers: fx.layer (above the 3D model, under the tint) for overlay
-- sprites; the picture itself (under the model) for Starfield's stars;
-- pic.tint for the gradient, vignette, colour cycling and flashes.
function Fx.Setup(pic, scene)
    local fx = { sprites = {}, stars = {}, t = 0, scene = scene }
    pic.fx = fx
    local layer = CreateFrame("Frame", nil, pic)
    layer:SetAllPoints()
    layer:SetFrameLevel((scene and scene:GetFrameLevel() or pic:GetFrameLevel()) + 2)
    if layer.SetClipsChildren then layer:SetClipsChildren(true) end
    fx.layer = layer
end

-- Sway: how the camera turns (yaw, pitch, roll) at time t.
local SWAY = {
    drunk = function(t) return math.sin(t * 0.6) * 0.05, math.sin(t * 0.43) * 0.02, math.sin(t * 0.9) * 0.09 end,
    float = function(t) return math.sin(t * 0.5) * 0.02, math.sin(t * 0.7) * 0.025, math.sin(t * 0.35) * 0.04 end,
    shake = function() return Rand(-0.012, 0.012), Rand(-0.012, 0.012), Rand(-0.01, 0.01) end,
    dizzy = function(t) return math.sin(t * 0.7) * 0.06, 0, t * 0.6 end,
    hype = function(t) return 0, math.abs(math.sin(t * 5)) * 0.04 - 0.02, math.sin(t * 2.5) * 0.04 end,
    glitch = function(t)
        if (t * 7) % 1 < 0.15 then return Rand(-0.03, 0.03), Rand(-0.02, 0.02), Rand(-0.03, 0.03) end
        return 0, 0, 0
    end,
}

-- The look's background, filter, motion and overlay, onto the picture.
-- light: the scene's light colour (r, g, b) the motion flickers around.
function Fx.Apply(pic, look, bg, f, light)
    local fx = pic.fx
    if not fx then return end
    local m = L.MOTION[look and look.motion or "none"]
    if m and m.key == "none" then m = nil end
    Fx.Layers(pic.tint, f, m)
    local w, h = pic:GetWidth() or 0, pic:GetHeight() or 0
    local def = L.OVERLAY[look and look.overlay or "none"]
    fx.def = def and (def.tex or def.texs) and def or nil
    fx.n = BuildSprites(fx, fx.layer, fx.def, w, fx.sprites, "ARTWORK")
    fx.flashNext = nil
    -- Starfield: little stars behind the model.
    fx.starDef = bg and bg.anim == "stars" and { tex = ART .. "Glow", count = 40, size = { 2, 5 }, motion = "twinkle", add = true,
        colors = { { 1, 1, 1 }, { 0.8, 0.85, 1 } } } or nil
    fx.nStars = BuildSprites(fx, pic, fx.starDef, w, fx.stars, "BACKGROUND")
    fx.bg, fx.f, fx.m, fx.light = bg, f, m, light
    local moving = fx.def or (bg and bg.anim) or m or (pic.HasLensAnim and pic:HasLensAnim())
        or (pic.faceAnims and #pic.faceAnims > 0)
    if not moving then
        fx.layer:SetScript("OnUpdate", nil)
        Fx.Still(pic)
        return
    end
    if not m then Fx.Still(pic) end
    fx.layer:SetScript("OnUpdate", function(_, dt) Fx.Step(pic, math.min(dt, 0.1)) end)
    Fx.Step(pic, 0)
end

-- Something started moving outside Fx.Apply (a face filter): make sure the
-- OnUpdate runs.
function Fx.Kick(pic)
    local fx = pic.fx
    if fx and not fx.layer:GetScript("OnUpdate") then
        fx.layer:SetScript("OnUpdate", function(_, dt) Fx.Step(pic, math.min(dt, 0.1)) end)
    end
end

-- Back to still: the camera level.
function Fx.Still(pic)
    local fx = pic.fx
    if fx and fx.swayed and fx.scene and fx.scene.SetCameraOrientationByYawPitchRoll then
        fx.scene:SetCameraOrientationByYawPitchRoll(math.pi, 0, 0)
        fx.swayed = nil
    end
end

function Fx.Stop(pic)
    local fx = pic.fx
    if not fx then return end
    fx.layer:SetScript("OnUpdate", nil)
    for _, s in ipairs(fx.sprites) do s.tex:Hide() end
    for _, s in ipairs(fx.stars) do s.tex:Hide() end
    Fx.Layers(pic.tint, nil, nil)
    Fx.Still(pic)
end

-- Lightning: now and then a bolt or two and a white flash.
local function Lightning(pic, fx, t, w, h)
    local tint = pic.tint
    if not fx.flashNext then fx.flashNext = t + Rand(0.5, 2) end
    if t >= fx.flashNext then
        fx.flashAt = t
        fx.flashNext = t + Rand(1.8, 4.5)
        for i = 1, fx.n do
            local s = fx.sprites[i]
            s.tex:ClearAllPoints()
            s.tex:SetSize(s.size * (w / 356) * 0.6, s.size * (w / 356))
            s.tex:SetPoint("TOP", fx.layer, "TOPLEFT", Rand(0.15, 0.85) * w, -Rand(0, 0.15) * h)
            if s.tex.SetRotation then s.tex:SetRotation(Rand(-0.3, 0.3)) end
        end
    end
    local age = fx.flashAt and (t - fx.flashAt) or 99
    for i = 1, fx.n do fx.sprites[i].tex:SetShown(age < 0.22) end
    if age < 0.3 then
        tint.fxFlash:SetColorTexture(0.9, 0.95, 1, 0.55 * (1 - age / 0.3))
        tint.fxFlash:Show()
    elseif not (fx.m and (fx.m.anim == "strobe" or fx.m.anim == "glitch")) then
        tint.fxFlash:Hide()
    end
end

function Fx.Step(pic, dt)
    local fx = pic.fx
    fx.t = fx.t + dt
    local t = fx.t
    local w, h = pic:GetWidth() or 0, pic:GetHeight() or 0
    if fx.def then
        MoveSprites(fx.sprites, fx.n, fx.def, dt, t, w, h, fx.layer)
        if fx.def.motion == "flash" then Lightning(pic, fx, t, w, h) end
    end
    if fx.starDef then MoveSprites(fx.stars, fx.nStars, fx.starDef, dt, t, w, h, pic) end
    if pic.LensStep then pic:LensStep(t) end
    if pic.faceAnims and #pic.faceAnims > 0 then ns.Decor.StepFaces(pic, t) end
    local f, bg, m = fx.f, fx.bg, fx.m
    -- Moving backgrounds.
    if bg and bg.anim == "liquid" and pic.art and pic.art[1] then
        local frame = math.floor(t * 15) % #bg.frames + 1
        if frame ~= fx.liquidFrame then
            fx.liquidFrame = frame
            local w2, h2 = pic:GetWidth() or 1, pic:GetHeight() or 1
            pic.art[1]:SetTexture(bg.frames[frame], "REPEAT", "REPEAT")
            pic.art[1]:SetTexCoord(0, 2, 0, 2 * h2 / math.max(1, w2))
        end
    elseif bg and bg.anim and bg.anim ~= "stars" and pic.bg then
        local tr, tg, tb, br, bgc, bb
        if bg.anim == "disco" then
            local step = math.floor(t / 0.4)
            tr, tg, tb = Hue(step * 0.27, 0.9, 1)
            br, bgc, bb = Hue(step * 0.27 + 0.5, 0.9, 0.45)
        elseif bg.anim == "rainbow" then
            tr, tg, tb = Hue(t * 0.06, 0.65, 1)
            br, bgc, bb = Hue(t * 0.06 + 0.35, 0.65, 0.85)
        else -- aurora
            local k = 0.5 + 0.5 * math.sin(t * 0.4)
            tr, tg, tb = 0.1 + 0.5 * (1 - k), 0.8 * k + 0.3, 0.55 + 0.4 * (1 - k)
            br, bgc, bb = 0.02, 0.04, 0.12
        end
        local grey = f and f.grey or 0
        local function G(r, g, b)
            local lum = r * 0.3 + g * 0.59 + b * 0.11
            return r * (1 - grey) + lum * grey, g * (1 - grey) + lum * grey, b * (1 - grey) + lum * grey
        end
        tr, tg, tb = G(tr, tg, tb)
        br, bgc, bb = G(br, bgc, bb)
        pic.bg:SetColorTexture(1, 1, 1, 1)
        if CreateColor and pic.bg.SetGradient then
            pcall(pic.bg.SetGradient, pic.bg, "VERTICAL", CreateColor(br, bgc, bb, 1), CreateColor(tr, tg, tb, 1))
        end
    end
    if not m then return end
    -- Motion.
    local tint = pic.tint
    if m.anim == "hue" then
        local r, g, b = Hue(t * 0.12, 0.8, 1)
        tint.fxHue:SetColorTexture(r, g, b, 0.2)
        tint.fxHue:Show()
    elseif m.anim == "disco" then
        local step = math.floor(t / 0.35)
        local r, g, b = Hue(step * 0.31, 1, 1)
        tint.fxHue:SetColorTexture(r, g, b, 0.22)
        tint.fxHue:Show()
        if fx.scene and fx.light and fx.scene.SetLightDiffuseColor then
            local k = (step % 2 == 0) and 1.15 or 0.7
            fx.scene:SetLightDiffuseColor(fx.light[1] * k * r, fx.light[2] * k * g, fx.light[3] * k * b)
        end
    elseif m.anim == "strobe" then
        local on = (t * 6) % 1 < 0.35
        tint.fxFlash:SetColorTexture(1, 1, 1, 0.45)
        tint.fxFlash:SetShown(on)
    elseif m.anim == "glitch" then
        local on = (t * 7) % 1 < 0.15
        if on then
            local r, g, b = Hue(math.floor(t * 7) * 0.37, 1, 1)
            tint.fxFlash:SetColorTexture(r, g, b, 0.3)
        end
        tint.fxFlash:SetShown(on)
    elseif m.anim == "pulse" then
        local beat = t % 1.1
        local k = math.max(0, 1 - beat / 0.18) + math.max(0, 1 - math.abs(beat - 0.3) / 0.15) * 0.7
        tint.fxVig:SetVertexColor(1, 0.1, 0.15)
        tint.fxVig:SetAlpha(math.min(1, (m.vignette or 0.5) + 0.45 * k))
        tint.fxVig:Show()
    elseif m.anim == "flicker" then
        if fx.scene and fx.light and fx.scene.SetLightDiffuseColor then
            fx.next = fx.next or 0
            if t >= fx.next then
                local k = math.random() < 0.15 and 0.15 or Rand(0.7, 1)
                fx.next = t + Rand(0.05, 0.25)
                fx.scene:SetLightDiffuseColor(fx.light[1] * k, fx.light[2] * k, fx.light[3] * k)
            end
        end
    end
    if m.sway and fx.scene and fx.scene.SetCameraOrientationByYawPitchRoll then
        local yaw, pitch, roll = SWAY[m.sway](t)
        fx.scene:SetCameraOrientationByYawPitchRoll(math.pi + yaw, pitch, roll)
        fx.swayed = true
    end
end

---------------------------------------------------------------------------
-- Previews in Create's tiles (still pictures of what each one does).
---------------------------------------------------------------------------
-- An overlay: a dark square with a few of its bits scattered on it.
function Fx.PreviewOverlay(holder, def)
    holder.fxBits = holder.fxBits or {}
    for _, t in ipairs(holder.fxBits) do t:Hide() end
    if not def or not (def.tex or def.texs) then return end
    local w, h = holder:GetWidth() or 60, holder:GetHeight() or 60
    local spots = { { 0.25, 0.25 }, { 0.7, 0.2 }, { 0.5, 0.5 }, { 0.2, 0.72 }, { 0.75, 0.75 } }
    if def.motion == "beam" or def.motion == "flash" then spots = { { 0.35, 0.45 }, { 0.68, 0.5 } } end
    for i, p in ipairs(spots) do
        local tex = holder.fxBits[i] or holder:CreateTexture(nil, "ARTWORK")
        holder.fxBits[i] = tex
        tex:SetTexture(def.texs and def.texs[(i - 1) % #def.texs + 1] or def.tex)
        if def.icon then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
        tex:SetBlendMode(def.add and "ADD" or "BLEND")
        local c = def.colors and def.colors[(i - 1) % #def.colors + 1] or { 1, 1, 1 }
        tex:SetVertexColor(c[1], c[2], c[3])
        local size = math.min(w * 0.4, (def.size[1] + def.size[2]) / 2 * 0.9)
        if def.motion == "beam" then tex:SetSize(w * 0.25, h * 0.9)
        elseif def.motion == "flash" then tex:SetSize(w * 0.35, h * 0.6)
        elseif def.thin then tex:SetSize(size * 0.2, size)
        elseif def.flat then tex:SetSize(size, size * 0.55)
        else tex:SetSize(size, size) end
        if def.spin and tex.SetRotation then tex:SetRotation(i * 0.9) elseif tex.SetRotation then tex:SetRotation(0) end
        tex:SetAlpha(def.alpha or 1)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", holder, "TOPLEFT", p[1] * w, -p[2] * h)
        tex:Show()
    end
end
