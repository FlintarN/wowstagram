-- Minimap button: the camera logo on the minimap's edge. Click to open, drag to move.
local ADDON, ns = ...

local W = ns.Widgets
local M = {}
ns.Minimap = M

-- On the minimap's rim, whatever size the minimap is (Forever's is large).
local function Place(b)
    local a = math.rad(ns.db.minimapAngle or 220)
    local r = (Minimap:GetWidth() or 140) / 2 + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function M:SetShown(show)
    ns.db.minimap = show and true or false
    if self.button then self.button:SetShown(show and true or false) end
end

function M:Build()
    if self.button or not Minimap then return end
    local b = CreateFrame("Button", "WowstagramMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture(ns.ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function() ns.UI:Toggle() end)
    b:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            Place(s)
        end)
    end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    W.Tooltip(b, ns.TITLE, function()
        local n = ns.db.unread or 0
        return "Click to open. Drag to move this button." .. (n > 0 and ("\n|cffff6080" .. n .. " new likes and comments.|r") or "")
    end)
    Place(b)
    self.button = b
    b:SetShown(ns.db.minimap ~= false)
end
