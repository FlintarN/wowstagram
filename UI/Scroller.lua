-- Scroller: a page that scrolls smoothly with the mouse wheel, like a web
-- page: an optional header at the top (stories, a profile), then rows of
-- equal height (posts, rows of the grid). Only the few rows in view exist;
-- they're reused as you scroll.
--
-- Text, buttons and borders are clipped by the scroll frame. 3D pictures
-- aren't (WoW draws models over everything), so every picture in a row is
-- cropped to the part that's in view (Picture:Crop).
--
--   local sc = ns.Scroller.New(parent, {
--     header = frame, headerH = 120,    -- optional, built by the caller on sc.content
--     rowH = 600,
--     build = function(row) ... end,    -- make a row's widgets; put its pictures in row.pics,
--                                       -- each with pic.rowY = its distance from the row's top
--     fill = function(row, index) ... end,
--     count = function() return n end,
--   })
--   sc:Refresh()   -- the data changed
local _, ns = ...

local SC = {}
ns.Scroller = SC

local STEP = 140 -- pixels per wheel notch

function SC.New(parent, opts)
    local sc = { rows = {}, offset = 0, target = 0, opts = opts }
    local view = CreateFrame("ScrollFrame", nil, parent)
    view:SetAllPoints()
    local content = CreateFrame("Frame", nil, view)
    content:SetSize(1, 1)
    view:SetScrollChild(content)
    view:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    sc.view, sc.content = view, content

    local headerH = opts.headerH or 0
    if opts.header then
        opts.header:SetParent(content)
        opts.header:ClearAllPoints()
        opts.header:SetPoint("TOPLEFT")
        opts.header:SetPoint("TOPRIGHT")
        opts.header:SetHeight(headerH)
    end

    local function Height()
        return headerH + opts.count() * opts.rowH + (opts.bottom or 0)
    end

    local function MaxOffset()
        return math.max(0, Height() - (view:GetHeight() or 0))
    end

    -- Each picture in a row: cut off what's above or below the view. Worked
    -- out from the layout (row position + the picture's own `rowY`, its
    -- distance from the row's top), not from GetTop, which can lag a frame
    -- behind while scrolling.
    local function Crop(row)
        if not row.pics or not row.index then return end
        local top = headerH + (row.index - 1) * opts.rowH
        local vTop, vBottom = sc.offset, sc.offset + (view:GetHeight() or 0)
        for _, pic in ipairs(row.pics) do
            if pic:IsShown() then
                local pt = top + (pic.rowY or 0)
                local pb = pt + (pic:GetHeight() or 0)
                pic:Crop(math.max(0, vTop - pt), math.max(0, pb - vBottom))
            end
        end
    end

    -- Place and fill the rows in view.
    function sc:Layout(force)
        local n = opts.count()
        local h = view:GetHeight() or 0
        local first = math.max(1, math.floor((self.offset - headerH) / opts.rowH) + 1)
        local need = math.ceil(h / opts.rowH) + 1
        for k = 0, need - 1 do
            local idx = first + k
            local slot = (idx - 1) % need + 1
            local row = self.rows[slot]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetHeight(opts.rowH)
                opts.build(row)
                -- The wheel over a picture scrolls the page.
                for _, pic in ipairs(row.pics or {}) do
                    pic.onWheel = function(delta) sc:ScrollBy(-delta * STEP) end
                end
                self.rows[slot] = row
            end
            if idx <= n then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(headerH + (idx - 1) * opts.rowH))
                row:SetPoint("RIGHT", content, "RIGHT")
                if force or row.index ~= idx then
                    row.index = idx
                    opts.fill(row, idx)
                end
                row:Show()
            else
                row.index = nil
                row:Hide()
            end
        end
        for slot = need + 1, #self.rows do
            self.rows[slot].index = nil
            self.rows[slot]:Hide()
        end
        for _, row in ipairs(self.rows) do
            if row:IsShown() then Crop(row) end
        end
    end

    local function Apply()
        view:SetVerticalScroll(sc.offset)
        sc:Layout(false)
    end

    -- Smooth: the wheel moves the target, the page glides there.
    local glide = CreateFrame("Frame", nil, view)
    glide:Hide()
    glide:SetScript("OnUpdate", function(self, elapsed)
        local d = sc.target - sc.offset
        if math.abs(d) < 0.5 then
            sc.offset = sc.target
            self:Hide()
        else
            sc.offset = sc.offset + d * math.min(1, elapsed * 14)
        end
        Apply()
    end)

    function sc:ScrollTo(y, instant)
        self.target = math.max(0, math.min(MaxOffset(), y))
        if instant then
            self.offset = self.target
            glide:Hide()
            Apply()
        else
            glide:Show()
        end
    end

    function sc:ScrollBy(dy)
        self:ScrollTo(self.target + dy)
    end

    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta) sc:ScrollBy(-delta * STEP) end)
    view:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(w)
        sc:Layout(false)
    end)

    -- The data changed: new height, refill the rows in view.
    function sc:Refresh()
        content:SetHeight(math.max(1, Height()))
        if self.target > MaxOffset() then
            self.target = MaxOffset()
            self.offset = math.min(self.offset, self.target)
            view:SetVerticalScroll(self.offset)
        end
        self:Layout(true)
    end

    function sc:Top()
        self:ScrollTo(0, true)
    end

    return sc
end
