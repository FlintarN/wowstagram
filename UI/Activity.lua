-- Notifications: who liked or commented on your pictures, newest first.
-- Click a line to open the picture. Opening the page clears the red count on
-- the sidebar.
local ADDON, ns = ...

local W = ns.Widgets
local C = W.C
local A = {}
ns.Activity = A

function A.New(parent)
    local view = {}
    local UI = ns.UI

    local title = W.Text(parent, 20)
    title:SetPoint("TOPLEFT", 32, -24)
    title:SetText("Notifications")

    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", 20, -64)
    box:SetPoint("BOTTOMRIGHT", -20, 12)
    view.list = W.ScrollList(box, 56, function(row)
        row.hover = W.Rounded(row, C.surface, 8)
        row.hover:SetShown(false)
        row.face = W.Avatar(row, 40)
        row.face:SetPoint("LEFT", 12, 0)
        row.text = W.Text(row, 12)
        row.text:SetPoint("LEFT", row.face, "RIGHT", 12, 0)
        row.text:SetPoint("RIGHT", -60, 0)
        row.text:SetWordWrap(true)
        row.icon = W.Icon(row, "Heart", 20, C.red)
        row.icon:SetPoint("RIGHT", -20, 0)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self) self.hover:SetShown(true) end)
        row:SetScript("OnLeave", function(self) self.hover:SetShown(false) end)
        row:SetScript("OnMouseUp", function(self)
            if self.entry and ns.Social.Find(self.entry.id) then UI:OpenPost(self.entry.id) end
        end)
    end)
    view.list:Inset(0, 0, 0, 0)
    view.empty = W.Text(parent, 14, C.dim)
    view.empty:SetPoint("TOP", 0, -140)
    view.empty:SetJustifyH("CENTER")
    view.empty:SetText("Activity on your pictures shows up here:\nlikes and comments.")

    function view:Refresh()
        local log = ns.db.activity
        for i, e in ipairs(log) do
            local row = self.list:Row(i)
            row.entry = e
            local class = (ns.Social.Profile(e.who) or {}).class
            if not class then
                for _, p in ipairs(ns.db.posts) do
                    if p.author == e.who then class = p.class break end
                end
            end
            row.face:SetPlayer(e.who, class)
            local what = e.kind == "like" and "liked your picture." or e.kind == "mention" and ("mentioned you: " .. ns.Feed.Rich(e.text or ""))
                or ("commented: " .. ns.Feed.Rich(e.text or ""))
            row.text:SetText(ns.ColorName(e.who, class) .. " " .. what .. "  " .. W.Hex(C.dim) .. ns.Ago(e.t) .. "|r")
            row.icon:SetTexture(W.ART .. (e.kind == "like" and "Heart" or "Bubble"))
            local c = e.kind == "like" and C.red or e.kind == "mention" and C.blue or C.dim
            row.icon:SetVertexColor(c[1], c[2], c[3], 1)
        end
        self.list:SetCount(#log)
        self.empty:SetShown(#log == 0)
    end
    return view
end
