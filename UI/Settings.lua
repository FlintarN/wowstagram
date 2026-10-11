-- Settings: plain rows with on/off switches, like the app's settings list.
-- Every switch can be flipped back any time.
local _, ns = ...

local W = ns.Widgets
local C = W.C
local SP = {}
ns.SettingsPage = SP

local SWITCHES = {
    { key = "network", label = "Share with the realm and guild",
      help = "Send your pictures, likes and comments to everyone with Wowstagram on your realm and in your guild, "
          .. "and get theirs. Off: everything stays on this computer.",
      set = function(on) ns.Social.SetNetwork(on) end },
    { key = "notify", label = "Tell me in chat", help = "A line in chat when someone likes or comments on your picture." },
    { key = "sound", label = "Sounds", help = "Clicks and the like sound. WoW's own volume settings apply." },
    { key = "minimap", label = "Minimap button", help = "The camera on the edge of the minimap.",
      set = function(on) ns.Minimap:SetShown(on) end },
}

function SP.New(parent)
    local view = {}
    local UI = ns.UI

    local title = W.Text(parent, 20)
    title:SetPoint("TOPLEFT", 32, -24)
    title:SetText("Settings")

    local x, w = 32, 380
    view.checks = {}
    for i, sw in ipairs(SWITCHES) do
        local y = -70 - (i - 1) * 62
        local label = W.Text(parent, 13)
        label:SetPoint("TOPLEFT", x, y)
        label:SetText(sw.label)
        local help = W.Text(parent, 11, C.dim)
        help:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
        help:SetWidth(w - 60)
        help:SetWordWrap(true)
        help:SetText(sw.help)
        local t = W.Toggle(parent, function(on)
            if sw.set then sw.set(on) else ns.db[sw.key] = on end
            ns.Changed()
        end)
        t:SetPoint("TOPLEFT", x + w - 40, y + 2)
        t.key = sw.key
        view.checks[i] = t
    end

    -- Window size.
    local y = -70 - #SWITCHES * 62
    local sizeLabel = W.Text(parent, 13)
    sizeLabel:SetPoint("TOPLEFT", x, y)
    local function Scale(d)
        ns.db.scale = math.max(0.7, math.min(1.4, (ns.db.scale or 1) + d))
        UI:ApplyScale()
        ns.Changed()
    end
    local bigger = W.Flat(parent, "+", 32, 26, "secondary", function() Scale(0.05) end, 14)
    bigger:SetPoint("TOPLEFT", x + w - 32, y + 4)
    local smaller = W.Flat(parent, "-", 32, 26, "secondary", function() Scale(-0.05) end, 14)
    smaller:SetPoint("RIGHT", bigger, "LEFT", -6, 0)
    view.sizeLabel = sizeLabel

    local clear = W.Flat(parent, "Clear everything", 140, 30, "danger", function()
        W.Confirm("Forget every picture, like, comment, profile and follow on this computer? Your posts stay with "
            .. "the people who already have them.", function() ns.ResetAll() end)
    end, 13)
    clear:SetPoint("TOPLEFT", x - 10, y - 44)

    -- Blocked people, with Unblock.
    local bTitle = W.Text(parent, 13)
    bTitle:SetPoint("TOPLEFT", x, y - 96)
    bTitle:SetText("Blocked")
    view.blockedNone = W.Text(parent, 11, C.dim)
    view.blockedNone:SetPoint("TOPLEFT", bTitle, "BOTTOMLEFT", 0, -8)
    view.blockedNone:SetText("Nobody. Block someone from the ... menu on their picture or their profile.")
    view.blockedRows = {}
    for i = 1, 6 do
        local row = W.Text(parent, 12)
        row:SetPoint("TOPLEFT", bTitle, "BOTTOMLEFT", 0, -8 - (i - 1) * 26)
        row:SetWidth(w - 90)
        row:SetWordWrap(false)
        row:SetJustifyH("LEFT")
        local un = W.Flat(parent, "Unblock", 70, 22, "link", function(self)
            if self.who then ns.Social.Block(self.who, false) end
        end, 11)
        un:SetPoint("TOPLEFT", x + w - 80, y - 114 - (i - 1) * 26) -- (level with its row)
        view.blockedRows[i] = { text = row, button = un }
    end
    view.blockedMore = W.Text(parent, 11, C.dim)
    view.blockedMore:SetPoint("TOPLEFT", bTitle, "BOTTOMLEFT", 0, -8 - 6 * 26)

    -- Right: how it works.
    local ax = x + w + 40
    local aboutTitle = W.Text(parent, 13)
    aboutTitle:SetPoint("TOPLEFT", ax, -70)
    aboutTitle:SetText("How pictures work")
    local text = W.Text(parent, 11, C.dim)
    text:SetPoint("TOPLEFT", aboutTitle, "BOTTOMLEFT", 0, -8)
    text:SetWidth(UI.MAIN_W - ax - 24)
    text:SetWordWrap(true)
    if text.SetSpacing then text:SetSpacing(3) end
    text:SetText("A Wowstagram picture isn't an image. It's a short note: which appearance is in each slot, "
        .. "the pose, the angle, the background and the filter. Everyone's game draws it again with its own 3D "
        .. "model.\n\n"
        .. "The game can only draw someone's real body (face, hair) when it can see them: you, your group, your "
        .. "target, people nearby. Anyone else is a Stand-in (their exact outfit on a body of their gender, as "
        .. "their race) or a look-alike (their race in the same kind of armour). The badge on the picture says "
        .. "which, and Try this look shows the outfit on you.\n\n"
        .. "Pictures go to everyone with Wowstagram on your realm and in your guild, or only to your guild if "
        .. "you switch on Guild only. When you log in, others send you the latest ones.\n\n"
        .. "/wgram to open.")

    function view:Refresh()
        for _, c in ipairs(self.checks) do c:SetChecked(ns.db[c.key] ~= false) end
        self.sizeLabel:SetText(string.format("Window size: %d%%", math.floor((ns.db.scale or 1) * 100 + 0.5)))
        local list = ns.Social.BlockedList()
        self.blockedNone:SetShown(#list == 0)
        for i, r in ipairs(self.blockedRows) do
            local b = list[i]
            local strikes = b and ns.db.strikes[b.name]
            r.text:SetText(b and (ns.Display(b.name) .. (strikes and strikes.out
                and (W.Hex(C.red) .. "  blocked by Wowstagram: cheating (" .. (strikes.why or "faking things") .. ")|r") or "")) or "")
            r.text:SetShown(b ~= nil)
            r.button.who = b and b.name
            r.button:SetShown(b ~= nil)
        end
        self.blockedMore:SetText(#list > #self.blockedRows and ("and " .. (#list - #self.blockedRows) .. " more") or "")
    end
    return view
end
