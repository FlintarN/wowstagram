-- Search: find people and hashtags. Type a name (any part of it) or a
-- #tag. People: only those known to have Wowstagram (S.People); friends,
-- people you follow and people you've seen lately come first.
-- With nothing typed: the people you're closest to and the most used tags.
local _, ns = ...

local W = ns.Widgets
local C = W.C
local S = ns.Social
local SE = {}
ns.Search = SE

local ROWS = 12

-- Why someone is there, in a few words.
local function Why(id)
    if S.IsFriend(id) then return "Friend" end
    if S.Following(id) then return "You follow them" end
    if S.InGuild(id) then return "In your guild" end
    local t = ns.db.met[id]
    if t then return "Seen " .. ns.Ago(t) .. " ago" end
    local n = #S.List(id)
    if n > 0 then return n .. (n == 1 and " picture" or " pictures") end
    return ""
end

-- The results for a query: { { person = id } or { tag = tag, n = n } }.
function SE.Find(query)
    query = strtrim(tostring(query or "")):lower()
    local out = {}
    local tagOnly = query:sub(1, 1) == "#"
    local q = tagOnly and query:sub(2) or query
    if not tagOnly then
        local people = {}
        for _, id in ipairs(S.People()) do
            local name = ns.Display(id):lower()
            local at = q == "" and 1 or name:find(q, 1, true)
            if at then people[#people + 1] = { id = id, at = at, close = S.Closeness(id) } end
        end
        table.sort(people, function(a, b)
            if (a.at == 1) ~= (b.at == 1) then return a.at == 1 end
            if a.close ~= b.close then return a.close > b.close end
            return a.id < b.id
        end)
        for _, p in ipairs(people) do out[#out + 1] = { person = p.id } end
    end
    for _, t in ipairs(S.AllTags()) do
        if q == "" or t.tag:find(q, 1, true) then out[#out + 1] = { tag = t.tag, n = t.n } end
    end
    return out
end

function SE.New(parent)
    local view = {}
    local UI = ns.UI
    local x, w = 40, 420

    local title = W.Text(parent, 20)
    title:SetPoint("TOPLEFT", x, -24)
    title:SetText("Search")
    view.box = W.Input(parent, w, 34, "Search people or #tags", 40, nil, function() view:Refresh() end)
    view.box:SetPoint("TOPLEFT", x, -62)

    view.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, parent)
        r:SetSize(w, 40)
        r:SetPoint("TOPLEFT", x, -108 - (i - 1) * 44)
        r:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        r.avatar = W.Avatar(r, 34)
        r.avatar:SetPoint("LEFT")
        r.avatar:EnableMouse(false)
        r.tagIcon = W.Text(r, 20, { 0.35, 0.65, 1 })
        r.tagIcon:SetPoint("CENTER", r, "LEFT", 17, 0)
        r.tagIcon:SetText("#")
        r.name = W.Text(r, 13)
        r.name:SetPoint("TOPLEFT", 46, -4)
        r.why = W.Text(r, 11, C.dim)
        r.why:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        r:SetScript("OnClick", function(self)
            if self.person then
                UI:OpenPerson(self.person)
            elseif self.tag then
                UI:Show("feed")
                UI.pages.feed.view:ShowTag(self.tag)
            end
        end)
        view.rows[i] = r
    end
    view.none = W.Text(parent, 12, C.dim)
    view.none:SetPoint("TOPLEFT", x, -116)
    view.more = W.Text(parent, 11, C.faint)
    view.more:SetPoint("TOPLEFT", x, -108 - ROWS * 44)

    function view:Open()
        self.box:SetText("")
        self.box:SetFocus()
    end

    function view:Refresh()
        local query = self.box:GetText() or ""
        local results = SE.Find(query)
        for i, r in ipairs(self.rows) do
            local res = results[i]
            r.person, r.tag = res and res.person, res and res.tag
            if res and res.person then
                local prof = S.Profile(res.person)
                r.avatar:SetPlayer(res.person, prof.class)
                r.avatar:Show()
                r.tagIcon:Hide()
                r.name:SetText(ns.Display(res.person))
                r.why:SetText(Why(res.person))
                r:Show()
            elseif res then
                r.avatar:Hide()
                r.tagIcon:Show()
                r.name:SetText("#" .. res.tag)
                r.why:SetText(res.n .. (res.n == 1 and " picture" or " pictures"))
                r:Show()
            else
                r:Hide()
            end
        end
        self.none:SetText(#results == 0 and (strtrim(query) == "" and "Nobody here yet. People show up as their pictures arrive and their Wowstagram says hello."
            or "Nobody and no tag like that.") or "")
        self.more:SetText(#results > ROWS and ("and " .. (#results - ROWS) .. " more: type more of the name") or "")
    end
    return view
end
