-- Picture: draws a look (Core\Look.lua) with the game's own 3D model, in a
-- ModelScene with one player actor, the same kind the game's Dressing Room
-- uses.
--
-- Whose body: the game can only draw a player's real body (race, face, hair)
-- and dress it from a unit it knows: you, your group, your target, focus or
-- mouseover. Anyone else is drawn as THEIR race and gender in their whole
-- outfit, on a stand-in body: a player the game can see, of the same
-- gender (you, if you share it), turned into their race with
-- SetModelByUnit's 7th argument, customRaceID (the in-game Shop's trick).
-- Face and hair are the stand-in's, made to fit the race. If no one of that
-- gender is around: a bare NPC look of their race, wearing only the
-- separate pieces (helm, shoulders, cloak, weapons); WoW won't paint body
-- clothes onto an NPC (see /wgram racetest).
local _, ns = ...

local W = ns.Widgets
local L = ns.Look
local P = {}
ns.Picture = P

local FOV = 0.62

-- WoW's camera angle runs corner to corner (diagonal), not top to bottom: the
-- angle to give a scene w x h pixels so it shows `fov` from top to bottom.
local function DiagFov(fov, w, h)
    if not (w and h) or h <= 0 then return fov end
    return 2 * math.atan(math.tan(fov / 2) * math.sqrt(w * w + h * h) / h)
end
P.DiagFov = DiagFov

-- A bare NPC look per race and gender (UnitRace id; 2 = male, 3 = female as
-- UnitSex gives it): skin painted, no clothes of their own. From WoW's
-- creature display tables: CreatureDisplayInfoExtra with an HD skin and no
-- NPCModelItemSlotDisplayInfo rows.
local RACE_LOOK = {
    [1] = { 37925, 37926 },  -- Human
    [2] = { 37920, 55256 },  -- Orc
    [3] = { 20317, 37918 },  -- Dwarf
    [4] = { 20318, 37919 },  -- Night Elf
    [5] = { 37923, 37924 },  -- Undead
    [6] = { 20319, 37921 },  -- Tauren
    [7] = { 37913, 20320 },  -- Gnome
    [8] = { 20321, 37922 },  -- Troll
    [9] = { 37927, 37928 },  -- Goblin
    [10] = { 37917, 20322 }, -- Blood Elf
    [11] = { 37916, 20323 }, -- Draenei
    [22] = { 37915, 37914 }, -- Worgen
}
-- Newer races look like the race they come from.
local RACE_LIKE = {
    [27] = 4, [28] = 6, [29] = 10, [30] = 11, [31] = 8, [32] = 1, [34] = 3, [35] = 9, [36] = 2, [37] = 7,
    [52] = 10, [70] = 10, [84] = 3, [85] = 3, [24] = 1, [25] = 1, [26] = 1,
}

-- On a stranger's race body only the separate pieces go on: helm,
-- shoulders, cloak and weapons attach in full colour; body clothes (chest,
-- legs, boots...) are painted onto a real player's skin, which an NPC body
-- can't do.
P.ATTACHED = { [1] = true, [3] = true, [15] = true, [16] = true, [17] = true }

-- A unit to stand in for someone of gender `sex` (UnitSex: 2 male, 3
-- female): you if you share it, else any player the game can see. nil if
-- there's none.
local DONOR_UNITS = { "target", "focus", "mouseover", "softfriend", "softinteract" }
function P.Donor(sex)
    if not sex or not UnitSex or UnitSex("player") == sex then return "player" end
    local function Ok(u)
        return UnitExists(u) and (not UnitIsPlayer or UnitIsPlayer(u)) and UnitSex(u) == sex
            and (not UnitIsConnected or UnitIsConnected(u) ~= false)
    end
    for _, u in ipairs(DONOR_UNITS) do if Ok(u) then return u end end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if Ok(u) then return u end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) and Ok(u) then return u end
    end
end

-- Dressed placeholders: NPC looks of each player race and sex, already wearing
-- robes / cloth / leather / mail / plate (pre-painted), with no helm, shoulders or
-- cloak of their own, so a stranger's real ones go on top. Picked from WoW's
-- creature display tables by the armour type of the NPC's items.
-- [race] = { [2] = male, [3] = female } (UnitSex numbers).
P.PLACEHOLDER = {
    [1] = { -- Human
        [2] = { robe = 62890, leather = 70421, mail = 87797, plate = 33373 },
        [3] = { robe = 70984, leather = 72284, mail = 82095, plate = 33984 },
    },
    [2] = { -- Orc
        [2] = { robe = 72542, cloth = 37199, leather = 54373, mail = 45261, plate = 53669 },
        [3] = { robe = 72543, cloth = 35243, leather = 72286, mail = 33145, plate = 53672 },
    },
    [3] = { -- Dwarf
        [2] = { robe = 72352, leather = 69011, mail = 1416, plate = 9969 },
        [3] = { robe = 72381, cloth = 30587, leather = 69012, mail = 33960, plate = 44223 },
    },
    [4] = { -- Night Elf
        [2] = { robe = 61268, leather = 69945, mail = 61283, plate = 91141 },
        [3] = { robe = 72347, leather = 69946, mail = 36574, plate = 91177 },
    },
    [5] = { -- Undead
        [2] = { robe = 72350, leather = 69026, mail = 1599, plate = 33988 },
        [3] = { robe = 72349, leather = 69025, mail = 33992, plate = 33993 },
    },
    [6] = { -- Tauren
        [2] = { robe = 48923, cloth = 34107, leather = 34111, mail = 32457, plate = 145207 },
        [3] = { robe = 34114, cloth = 34108, leather = 45132, mail = 65483, plate = 142109 },
    },
    [7] = { -- Gnome
        [2] = { robe = 72340, leather = 70420, mail = 33961, plate = 73688 },
        [3] = { robe = 72339, leather = 72586, plate = 77755 },
    },
    [8] = { -- Troll
        [2] = { robe = 72346, cloth = 11468, leather = 34207, mail = 11225, plate = 142101 },
        [3] = { robe = 72345, cloth = 4358, leather = 34209, mail = 43030, plate = 142106 },
    },
    [9] = { -- Goblin
        [2] = { robe = 72338, cloth = 44012, leather = 86755, mail = 86758, plate = 34953 },
        [3] = { robe = 72337, leather = 122985, mail = 34695, plate = 26245 },
    },
    [10] = { -- Blood Elf
        [2] = { robe = 136765, leather = 71236, mail = 137057, plate = 138941 },
        [3] = { robe = 136766, leather = 65392, mail = 46655, plate = 18948 },
    },
    [11] = { -- Draenei
        [2] = { robe = 72370, cloth = 53810, leather = 52294, mail = 28807, plate = 52465 },
        [3] = { robe = 65341, leather = 52473, mail = 28142, plate = 52467 },
    },
    [22] = { -- Worgen
        [2] = { robe = 72536, cloth = 34347, leather = 72293, mail = 89083, plate = 34346 },
        [3] = { robe = 72537, cloth = 34351, leather = 33551, mail = 34349, plate = 34350 },
    },
}

-- The same for WoW Forever, whose game data is classic-era: none of the HD
-- looks above exist there. Picked the same way from the classic-era tables.
P.PLACEHOLDER_CLASSIC = {
    [1] = { -- Human
        [2] = { cloth = 3563, leather = 1611, mail = 2511 },
        [3] = { robe = 1745, cloth = 6684, leather = 1612, mail = 176, plate = 3287 },
    },
    [2] = { -- Orc
        [2] = { cloth = 4376, leather = 4927, mail = 12809 },
        [3] = { robe = 1367, cloth = 4502, leather = 8479, mail = 13814, plate = 15542 },
    },
    [3] = { -- Dwarf
        [2] = { cloth = 4944, leather = 11899, mail = 1416, plate = 3088 },
        [3] = { robe = 1670, cloth = 6588, leather = 15450 },
    },
    [4] = { -- Night Elf
        [2] = { robe = 1898, cloth = 16157, leather = 4201 },
        [3] = { robe = 1730, cloth = 1915, leather = 9249, mail = 1710 },
    },
    [5] = { -- Undead
        [2] = { cloth = 1600, leather = 4008, mail = 1599 },
        [3] = { robe = 1592, cloth = 9343, leather = 4041, mail = 13816 },
    },
    [6] = { -- Tauren
        [2] = { cloth = 11773, leather = 5108, mail = 7624 },
        [3] = { cloth = 10051, leather = 15341 },
    },
    [7] = { -- Gnome
        [2] = { robe = 1930, cloth = 14529, mail = 15668 },
        [3] = { cloth = 8478, leather = 15453 },
    },
    [8] = { -- Troll
        [2] = { cloth = 11468, leather = 6508, mail = 11225 },
        [3] = { cloth = 12042, leather = 6509, mail = 11227, plate = 15466 },
    },
    [9] = { -- Goblin
        [2] = { cloth = 7209, leather = 11376, mail = 15201 },
        [3] = { cloth = 9132, leather = 10746 },
    },
}

-- This game's table: Forever's data has none of the HD looks.
function P.Placeholders()
    return ns.FOREVER and P.PLACEHOLDER_CLASSIC or P.PLACEHOLDER
end

-- When a style is missing for a race and sex, the next closest one; every
-- list ends with all five, so there's always something.
local STYLE_NEXT = {
    robe = { "robe", "cloth", "leather", "mail", "plate" }, cloth = { "cloth", "robe", "leather", "mail", "plate" },
    leather = { "leather", "cloth", "robe", "mail", "plate" }, mail = { "mail", "leather", "plate", "cloth", "robe" },
    plate = { "plate", "mail", "leather", "cloth", "robe" },
}

-- The kind of armour an outfit is: from the chest piece (a robe if it's
-- one), else the legs. Uses the instant item lookup (no waiting for data).
local SUBCLASS = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate" }
function P.ArmorStyle(slots)
    local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not Instant then return "cloth" end
    for _, slot in ipairs({ 5, 7, 8, 10 }) do
        local item = P.SlotItem(slots and slots[slot])
        if item then
            local _, _, _, equipLoc, _, classID, subclassID = Instant(item)
            if equipLoc == "INVTYPE_ROBE" then return "robe" end
            if classID == 4 and SUBCLASS[subclassID] then return SUBCLASS[subclassID] end
        end
    end
    return "cloth"
end

-- A dressed placeholder for race, sex (2 / 3) and style, or nil.
function P.Placeholder(race, sex, style)
    race = RACE_LIKE[race or 0] or race
    local all = P.Placeholders()
    local bySex = all[race or 0] or all[1]
    local set = bySex[sex == 3 and 3 or 2]
    for _, st in ipairs(STYLE_NEXT[style] or STYLE_NEXT.cloth) do
        if set[st] then return set[st], st end
    end
end

-- How to draw someone the game doesn't know: { unit, race } (a stand-in of
-- their gender, as their race) or { display } (a dressed placeholder, or
-- the plain race body if there's none).
function P.StandIn(race, sex, slots)
    local donor = P.Donor(sex)
    if donor then return { unit = donor, race = race } end
    local placeholder = P.Placeholder(race, sex, P.ArmorStyle(slots))
    if not placeholder and ns.FOREVER then placeholder = P.Placeholder(1, sex, "cloth") end
    return { display = placeholder or P.RaceLook(race, sex), placeholder = placeholder ~= nil }
end

function P.RaceLook(race, sex)
    race = RACE_LIKE[race or 0] or race
    local pair = RACE_LOOK[race or 0] or RACE_LOOK[1]
    return pair[sex == 3 and 2 or 1]
end
local all = setmetatable({}, { __mode = "k" }) -- every picture, to redress when item data arrives
-- Each body's bounding box, measured once without gear or weapons (a polearm
-- on the back made the box far taller than the person): player id -> box.
local BODY = {}

-- How tall each race stands, next to a Human man (= 1), men and women: WoW
-- reports NPC looks' outlines far taller than the body, so placeholders are
-- framed by this instead. [race] = { man, woman }.
P.RACE_HEIGHT = {
    [1] = { 1.00, 0.92 }, [2] = { 1.00, 0.92 }, [3] = { 0.68, 0.64 }, [4] = { 1.15, 1.06 },
    [5] = { 0.90, 0.88 }, [6] = { 1.25, 1.14 }, [7] = { 0.64, 0.46 }, [8] = { 1.10, 1.06 },
    [9] = { 0.56, 0.53 }, [10] = { 0.98, 0.92 }, [11] = { 1.18, 1.08 }, [22] = { 1.12, 1.00 },
}

-- A Human man's height in the scene. Worked out from your own body (measured
-- standing, without gear, like every real body) and your race's place in the
-- table; until then a typical value.
local function HumanHeight()
    local me = ns.UnitId and ns.UnitId("player")
    local body = me and BODY[me .. ":"]
    if body then
        local _, _, race = UnitRace("player")
        race = RACE_LIKE[race or 0] or race
        local row = P.RACE_HEIGHT[race or 0]
        if row then return (body[6] - body[3]) / row[UnitSex("player") == 3 and 2 or 1] end
    end
    return 2.2
end

-- How much bigger a head is for its height than a Human's (close-ups).
-- [race] = { face, waist up }.
local HEAD = { [3] = { 1.25, 1.25 }, [7] = { 1.9, 1.9 }, [9] = { 1.75, 1.75 } }
function P.HeadSize(race, frame)
    race = RACE_LIKE[race or 0] or race
    local row = HEAD[race or 0]
    return row and row[frame == "waist" and 2 or 1] or 1
end

-- Full shots, per race and sex: < 1 closer, > 1 further out.
-- [race] = { man, woman }.
local FULL_FIT = {
    [1] = { 0.9, 1 }, [3] = { 0.9, 1 }, [4] = { 0.9, 1 }, [5] = { 0.9, 1 }, [6] = { 0.9, 1.1 },
}
function P.FullFit(race, sex)
    race = RACE_LIKE[race or 0] or race
    local row = FULL_FIT[race or 0]
    return row and row[sex == 3 and 2 or 1] or 1
end

-- Face filters: where each race's face is, as shares of the body's height
-- (from its feet): ze the eyes' height, s the head's size (as the filters
-- are drawn), fwd how far forward of the body's middle the head sits (a
-- hunched Tauren's is far forward: near the camera it looks bigger and
-- further from the middle), xs sideways. Fitted from faces placed by hand
-- in three framings (Tune faces on /wgram wall), with HD character models.
P.FACE_MODEL = {
    ["1:2"] = { ze = 0.857, s = 0.125, fwd = 0.086, xs = 0.001 }, -- Human man
    ["1:3"] = { ze = 0.902, s = 0.130, fwd = 0.059, xs = -0.007 }, -- Human woman
    ["2:2"] = { ze = 0.862, s = 0.162, fwd = 0.234, xs = -0.029 }, -- Orc man
    ["2:3"] = { ze = 0.826, s = 0.121, fwd = 0.079, xs = -0.002 }, -- Orc woman
    ["3:2"] = { ze = 0.954, s = 0.194, fwd = 0.019, xs = 0.004 }, -- Dwarf man
    ["3:3"] = { ze = 0.853, s = 0.163, fwd = 0.069, xs = -0.011 }, -- Dwarf woman
    ["4:2"] = { ze = 0.884, s = 0.116, fwd = 0.080, xs = 0.001 }, -- Night Elf man
    ["4:3"] = { ze = 0.906, s = 0.124, fwd = 0.085, xs = 0.007 }, -- Night Elf woman
    ["5:2"] = { ze = 0.826, s = 0.122, fwd = 0.135, xs = -0.079 }, -- Undead man
    ["5:3"] = { ze = 0.831, s = 0.121, fwd = 0.101, xs = -0.009 }, -- Undead woman
    ["6:2"] = { ze = 0.829, s = 0.184, fwd = 0.308, xs = -0.009 }, -- Tauren man
    ["6:3"] = { ze = 0.872, s = 0.139, fwd = 0.314, xs = -0.006 }, -- Tauren woman
    ["7:2"] = { ze = 0.692, s = 0.258, fwd = 0.112, xs = 0.010 }, -- Gnome man
    ["7:3"] = { ze = 0.687, s = 0.272, fwd = 0.238, xs = 0.008 }, -- Gnome woman
    ["8:2"] = { ze = 0.849, s = 0.128, fwd = 0.323, xs = 0.015 }, -- Troll man
    ["8:3"] = { ze = 0.834, s = 0.113, fwd = 0.070, xs = -0.027 }, -- Troll woman
}
local FACE_DEFAULT = { ze = 0.86, s = 0.13, fwd = 0.1, xs = 0 }
function P.FaceModel(race, sex)
    race = RACE_LIKE[race or 0] or race
    return P.FACE_MODEL[tostring(race) .. ":" .. tostring(sex == 3 and 3 or 2)] or FACE_DEFAULT
end

-- Tune faces (/wgram wall) adds a correction on top, per race, sex and
-- framing ({ down, x, size }, in head sizes), kept in ns.db.faceTune; and
-- what the camera saw (ns.db.faceObs), to fit the model again.
function P.FaceTune(race, sex, frame)
    race = RACE_LIKE[race or 0] or race
    local key = tostring(race) .. ":" .. tostring(sex == 3 and 3 or 2) .. ":" .. (frame or "full")
    return (ns.db and ns.db.faceTune and ns.db.faceTune[key]) or {}, key
end

-- Hold still: the pose frozen (speed 0), a moment into it so a wave or a
-- cheer is caught mid-move. Everyone holds still while tuning faces.
function P.Still(person)
    return (person and person.still) or P.faceGrid
end

function P.Play(a, person)
    if not a.SetAnimation then return end
    local pose = L.POSE[person.pose or "stand"] or L.POSE.stand
    if P.Still(person) then
        a:SetAnimation(pose.anim, 0, 0, pose.anim == 0 and 0 or 0.6)
    else
        a:SetAnimation(pose.anim, 0, 1)
    end
end

-- How tall someone of this race and sex (2 / 3) stands in the scene.
function P.RaceHeight(race, sex)
    race = RACE_LIKE[race or 0] or race
    local row = P.RACE_HEIGHT[race or 0] or P.RACE_HEIGHT[1]
    return HumanHeight() * row[sex == 3 and 2 or 1]
end

---------------------------------------------------------------------------
-- Units and items
---------------------------------------------------------------------------
local function Same(unit, name)
    if not (UnitExists and UnitExists(unit)) then return false end
    if UnitIsPlayer and not UnitIsPlayer(unit) then return false end
    return ns.UnitId(unit) == name
end

-- A unit the game can draw `name` (an id, "Name-Realm") from, or nil.
function P.UnitFor(name)
    if not name then return nil end
    if name == ns.Me() then return "player" end
    for _, u in ipairs({ "target", "focus", "mouseover", "softfriend", "softinteract" }) do
        if Same(u, name) then return u end
    end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if Same(u, name) then return u end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if Same(u, name) then return u end
    end
end

-- Which slot an item goes in, from its equip location.
local EQUIP = {
    INVTYPE_HEAD = 1, INVTYPE_SHOULDER = 3, INVTYPE_CLOAK = 15, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
    INVTYPE_BODY = 4, INVTYPE_TABARD = 19, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_WEAPONOFFHAND = 17, INVTYPE_SHIELD = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 16,
    INVTYPE_RANGEDRIGHT = 16, INVTYPE_THROWN = 16,
}
P.EQUIP = EQUIP

local function GetInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if GetItemInfo then return GetItemInfo(item) end
end

-- Item id from an id, "item:123" or a full item link.
function P.ItemId(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    return tonumber(item:match("item:(%d+)")) or tonumber(item)
end

-- The slot an item goes in, or nil and "wait" while the game is still
-- fetching it (GET_ITEM_INFO_RECEIVED follows), or nil and "no" when it
-- can't be worn.
function P.ItemSlot(item)
    local id = P.ItemId(item)
    if not id then return nil, "no" end
    local name, _, _, _, _, _, _, _, equipLoc = GetInfo(id)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return nil, "wait"
    end
    local slot = EQUIP[equipLoc or ""]
    if not slot then return nil, "no" end
    return slot
end

-- A slot entry for an item: its transmog appearance when the client knows
-- it (that's what the Dressing Room uses), the plain item id otherwise.
function P.SlotFor(item)
    local id = P.ItemId(item)
    if not id then return nil end
    if C_TransmogCollection and C_TransmogCollection.GetItemInfo then
        local ok, _, source = pcall(C_TransmogCollection.GetItemInfo, item)
        if ok and source and source > 0 then return { a = source, s = 0, i = 0 } end
    end
    return { item = id }
end

-- The item behind a slot entry (for its icon and tooltip).
function P.SlotItem(s)
    if not s then return nil end
    if s.item then return s.item end
    if s.a and C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
        local ok, info = pcall(C_TransmogCollection.GetSourceInfo, s.a)
        if ok and info and info.itemID then return info.itemID end
    end
end

function P.SlotIcon(s)
    local id = P.SlotItem(s)
    if id then
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        if icon then return icon end
    end
    if s and s.a and C_TransmogCollection and C_TransmogCollection.GetSourceIcon then
        local ok, icon = pcall(C_TransmogCollection.GetSourceIcon, s.a)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- What you're wearing, slot by slot, as item ids (works on every client;
-- the Studio upgrades this to transmog appearances when it can).
function P.Equipped()
    local slots = {}
    for _, def in ipairs(L.SLOTS) do
        local id = GetInventoryItemID and GetInventoryItemID("player", def.id)
        if id then slots[def.id] = { item = id } end
    end
    return slots
end

---------------------------------------------------------------------------
-- The picture
---------------------------------------------------------------------------
-- A colour through a filter: washed towards grey, then tinted.
local function Through(c, f)
    local g = f and f.grey or 0
    local t = f and f.tint or { 1, 1, 1 }
    local lum = c[1] * 0.3 + c[2] * 0.59 + c[3] * 0.11
    local out = {}
    for i = 1, 3 do out[i] = math.min(1, (c[i] * (1 - g) + lum * g) * t[i]) end
    return out
end
P.Through = Through

-- The backdrop: a background's two colours, through a filter.
function P.Gradient(tex, bg, f)
    local top, bottom = Through(bg.top, f), Through(bg.bottom, f)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, "VERTICAL",
        CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    if not ok then tex:SetColorTexture(top[1], top[2], top[3], 1) end
end
local Gradient = P.Gradient

-- The classic Dressing Room backdrop is four pieces: 256 x 255 and 62 x 255
-- on top, 256 x 128 and 62 x 128 under them (318 x 383 in all).
local PIECES = { { 0, 0, 256, 256 }, { 256, 0, 64, 256 }, { 0, 256, 256, 128 }, { 256, 256, 64, 128 } }

-- Paint a background into `holder` (a frame): the colour gradient on
-- `gradient`, and over it the picture of a dressing room or a place, in
-- textures made once and kept on the holder. f: a filter (tint and grey).
function P.PaintBackground(holder, gradient, bg, f)
    Gradient(gradient, bg, f)
    holder.art = holder.art or {}
    local art = holder.art
    for i = 1, 12 do
        if not art[i] then
            art[i] = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
        end
        art[i]:Hide()
    end
    local t = f and f.tint or { 1, 1, 1 }
    local grey = f and f.grey or 0
    local function Tint(tex)
        tex:SetVertexColor(math.min(1, t[1]), math.min(1, t[2]), math.min(1, t[3]), 1)
        if tex.SetDesaturation then tex:SetDesaturation(grey) elseif tex.SetDesaturated then tex:SetDesaturated(grey > 0.5) end
    end
    local w, h = holder:GetWidth() or 0, holder:GetHeight() or 0
    if bg.room and w > 0 and h > 0 then
        -- Four pieces (256 and 64 wide, 256 and 128 high); the painting is
        -- the top-left cw x ch of them. Scaled to cover the picture, the
        -- middle shown, each piece cut to what's in view.
        local cw, ch = bg.cw or 318, bg.ch or 336
        local scale = math.max(w / cw, h / ch)
        local vw, vh = w / scale, h / scale
        local x0, y0 = (cw - vw) / 2, (ch - vh) / 2
        for i, part in ipairs(PIECES) do
            local px, py, tw, th = part[1], part[2], part[3], part[4]
            local l, r = math.max(px, x0), math.min(px + tw, x0 + vw)
            local t, b = math.max(py, y0), math.min(py + th, y0 + vh)
            if r > l and b > t then
                local tex = art[i]
                tex:SetTexture(bg.room[i])
                tex:SetTexCoord((l - px) / tw, (r - px) / tw, (t - py) / th, (b - py) / th)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", holder, "TOPLEFT", (l - x0) * scale, -(t - y0) * scale)
                tex:SetSize((r - l) * scale, (b - t) * scale)
                Tint(tex)
                tex:Show()
            end
        end
    elseif (bg.tile or bg.liquid) and w > 0 and h > 0 then
        -- A texture tiled over the picture (a liquid's first frame; UI\Fx.lua
        -- plays the rest).
        local tex = art[1]
        local n = bg.liquid and 2 or 3
        tex:SetTexture(bg.tile or bg.frames[1], "REPEAT", "REPEAT")
        tex:SetTexCoord(0, n, 0, n * h / w)
        tex:ClearAllPoints()
        tex:SetAllPoints(holder)
        Tint(tex)
        tex:Show()
    elseif bg.map and w > 0 and h > 0 then
        -- An old world map: 12 tiles of 256 (4 across, 3 down); the map
        -- itself is the top-left 1002 x 668. Scaled to the picture's
        -- height, the middle shown.
        local scale = h / 668
        local x0 = (1002 * scale - w) / 2
        for r = 0, 2 do
            for c = 0, 3 do
                local i = r * 4 + c + 1
                local left, top = c * 256 * scale - x0, r * 256 * scale
                local right, bottom = left + 256 * scale, top + 256 * scale
                local cl, cr = math.max(0, left), math.min(w, right)
                local ct, cb = math.max(0, top), math.min(h, bottom)
                if cr > cl and cb > ct then
                    local tex = art[i]
                    tex:SetTexture(bg.map .. i)
                    tex:SetTexCoord((cl - left) / (256 * scale), (cr - left) / (256 * scale),
                        (ct - top) / (256 * scale), (cb - top) / (256 * scale))
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", holder, "TOPLEFT", cl, -ct)
                    tex:SetSize(cr - cl, cb - ct)
                    Tint(tex)
                    tex:Show()
                end
            end
        end
    elseif bg.file then
        -- A 4 : 3 painting: show the middle, as wide as our 4 : 5 allows.
        local tex = art[1]
        tex:SetTexture(bg.file)
        local share = math.min(1, (w / math.max(1, h)) / (4 / 3))
        tex:SetTexCoord(0.5 - share / 2, 0.5 + share / 2, 0, 1)
        tex:ClearAllPoints()
        tex:SetAllPoints(holder)
        Tint(tex)
        tex:Show()
    end
end

-- opts: { interactive = true } (the Studio only) lets the mouse turn the
-- character (drag) and zoom (wheel); everywhere else a picture is shown
-- exactly as it was posted, and the wheel goes to pic.onWheel(delta) (the
-- page's scrolling). opts.onChange(look) after a turn or zoom; opts.onClick()
-- on a click without a drag; opts.onDrop(item) when an item from your bags is
-- dropped on it.
function P.New(parent, w, h, opts)
    opts = opts or {}
    local pic = CreateFrame("Frame", nil, parent)
    pic:SetSize(w, h)
    all[pic] = true

    pic.bg = pic:CreateTexture(nil, "BACKGROUND")
    pic.bg:SetAllPoints()

    local ok, scene = pcall(CreateFrame, "ModelScene", nil, pic)
    if not ok or not scene or not scene.CreateActor then scene = nil end
    local actor = scene and scene:CreateActor()
    if scene then
        scene:SetAllPoints()
        if scene.SetCameraFieldOfView then scene:SetCameraFieldOfView(FOV) end
        if scene.SetCameraNearClip then scene:SetCameraNearClip(0.1) end
        if scene.SetCameraFarClip then scene:SetCameraFarClip(200) end
    end
    pic.scene, pic.actor = scene, actor

    -- On top of the model: the border and the little labels.
    local over = CreateFrame("Frame", nil, pic)
    over:SetAllPoints()
    over:SetFrameLevel((scene and scene:GetFrameLevel() or pic:GetFrameLevel()) + 5)
    -- The filter's see-through colour, gradient and vignette: over the model
    -- and the overlays, under stickers and text (UI\Decor.lua).
    local base = scene and scene:GetFrameLevel() or pic:GetFrameLevel()
    pic.tint = CreateFrame("Frame", nil, pic)
    pic.tint:SetAllPoints()
    pic.tint:SetFrameLevel(base + 3)
    pic.wash = pic.tint:CreateTexture(nil, "BACKGROUND")
    pic.wash:SetAllPoints()
    pic.wash:Hide()
    pic.border = W.Outline(over)
    pic.note = W.Text(over, 10, { 1, 1, 1 })
    pic.note:SetPoint("BOTTOMRIGHT", -8, 7)
    pic.note:SetWidth(w - 16)
    pic.note:SetJustifyH("RIGHT")
    pic.note:SetAlpha(0.75)
    pic.empty = W.Text(over, 12, W.C.dim)
    pic.empty:SetJustifyH("CENTER")
    pic.empty:SetPoint("CENTER")
    pic.empty:SetWidth(w - 30)
    pic.over = over
    pic.interactive = opts.interactive
    ns.Fx.Setup(pic, scene)
    ns.Decor.Setup(pic, base + 4)

    -- The badge (top left): how much of this picture is the real thing.
    -- The poster's name and race, for the words below.
    local function Who()
        return pic.author and ns.Display(pic.author) or "them"
    end
    local function RaceName()
        local r = pic.look and pic.look.race
        local info = r and C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetRaceInfo(r)
        return info and info.raceName or "their race"
    end
    local STATES = {
        standin = { "Stand-in", function(her)
            local body = pic.unit == "player" and "your own character's body"
                or ("the body of " .. ns.Display(ns.UnitId(pic.unit) or "someone nearby"))
            local race = pic.look and pic.look.race and C_CreatureInfo and C_CreatureInfo.GetRaceInfo
                and C_CreatureInfo.GetRaceInfo(pic.look.race)
            return "Every item is real, on " .. body .. ", made a " .. (race and race.raceName or "member of their race")
                .. ". The face and hair aren't theirs: your game can only draw " .. her .. " own face when it can see "
                .. (her == "his" and "him" or "her") .. "." end },
        lookalike = { function() return RaceName() .. " look-alike" end, function(her, style)
            return "Not " .. Who() .. " " .. (her == "his" and "himself" or "herself") .. ": an " .. RaceName()
                .. " in the same kind of armour (" .. style .. "), wearing " .. her
                .. " real helm, shoulders, cloak and weapons. Target " .. (her == "his" and "him" or "her")
                .. ", or anyone of the same gender, to see the exact outfit, or use Try this look." end },
        loading = { "Loading...", function() return "Fetching item data from the game." end },
        missing = { "Missing data", function()
            local ids = {}
            for id in pairs(pic.missingItems or {}) do ids[#ids + 1] = tostring(id) end
            table.sort(ids)
            return "Your game doesn't have something this picture uses, so part of it can't be drawn"
                .. (#ids > 0 and (": item " .. table.concat(ids, ", ") .. ".") or " (a model).") end },
    }
    local function Pill(parent)
        local b = CreateFrame("Button", nil, parent)
        b:SetHeight(18)
        b.bg = W.Rounded(b, { 0, 0, 0 }, 9, "BACKGROUND", 0.6)
        b.text = W.Text(b, 10, { 1, 1, 1 })
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
        function b:Say(text)
            self.text:SetText(text)
            local tw = self.text.GetStringWidth and self.text:GetStringWidth() or 0
            if tw <= 0 then tw = #text * 6 end
            self:SetWidth(tw + 16)
        end
        b:Hide()
        return b
    end
    if opts.badge then
        pic.badge = Pill(over)
        pic.badge:SetPoint("TOPLEFT", 8, -8)
        W.Tooltip(pic.badge, function() return pic.badge.text:GetText() end, function()
            local st = STATES[pic.badgeState]
            local her = pic.look and pic.look.sex == 3 and "her" or "him"
            local style = pic.look and P.ArmorStyle(pic.look.slots) or "cloth"
            return st and st[2](her == "him" and "his" or "her", style)
        end)
    end

    function pic:UpdateBadge()
        local state = self.missing and "missing" or (self.waiting and "loading") or self.state
        if self.author == ns.Me() or state == "real" then state = nil end
        self.badgeState = state
        if self.badge then
            if state then
                local label = STATES[state][1]
                self.badge:Say(type(label) == "function" and label() or label)
            end
            self.badge:SetShown(state ~= nil)
        end
    end

    -- Fit the camera to the model once it has loaded (its bounding box is
    -- known only then), and keep checking for a few seconds as it settles.
    function pic:Fit()
        if not (actor and actor.GetActiveBoundingBox and self.look) or self.measure then return false end
        local lx1, ly1, lz1, lx2, ly2, lz2 = actor:GetActiveBoundingBox()
        if not lx1 or not lz2 or (lz2 - lz1) <= 0.05 then return false end
        -- Height and middle from the bare body; width from the model as it is
        -- now (arms out, lying down).
        local body = BODY[self.bodyKey or ""]
        if self.display and self.look.race then
            -- A placeholder: its race's height, standing on its own spot (its
            -- live box leans toward a cloak or a staff on the back). A full
            -- shot leaves room for a hat, up to a quarter of the height.
            local h = P.RaceHeight(self.look.race, self.look.sex)
            local top = h
            if (L.FRAME[self.look.frame] or L.FRAME.full).key == "full" then
                top = math.min(math.max(h, lz2), h * 1.25)
            end
            -- Shoulders: the model's own width (an Orc is broad), within
            -- limits so a weapon can't widen it.
            local half = math.min(math.max((ly2 - ly1) / 2, h * 0.22), h * 0.31)
            body = { -h * 0.15, -half, 0, h * 0.15, half, top }
        end
        local x1, z1, x2, z2 = lx1, lz1, lx2, lz2
        if body then x1, z1, x2, z2 = body[1], body[3], body[4], body[6] end
        local y1, y2 = ly1, ly2
        if self.display and body then y1, y2 = body[2], body[5] end
        local look = self.look
        local frame = L.FRAME[look.frame] or L.FRAME.full
        local pw, ph = self:GetWidth(), self:GetHeight()
        local ct, cb = self.cropTop or 0, self.cropBottom or 0
        local people = {}
        for _, q in ipairs(look.people or {}) do people[#people + 1] = string.format("%.3f,%.3f", q.mx or 0, q.my or 0) end
        local sig = string.format("%.2f %.2f %.2f %.2f %s %d %d %d %d %d %.3f %.3f %s", z1, z2, y1, y2, frame.key,
            look.zoom or 100, pw, ph, ct, cb, look.mx or 0, look.my or 0, table.concat(people, " "))
        if sig == self.sig then return true end
        self.sig = sig
        local hgt = z2 - z1
        local tz = z1 + hgt * frame.z
        local viewH = hgt * frame.h
        -- Gnomes, goblins and dwarves have big heads for their height: a
        -- close-up takes in more of them, from the top down.
        local head = frame.key ~= "full" and P.HeadSize(look.race, frame.key) or 1
        -- Look-alikes stand wide and keep room for a hat: a Full shot of
        -- them stays a little further out.
        if self.display and frame.key == "full" then viewH = viewH * 1.13 end
        if head ~= 1 then
            viewH = viewH * head
            -- A face stays near the top; waist up keeps its middle, so the
            -- head sits lower with room above it.
            if frame.key == "face" then tz = z2 - (z2 - tz) * head end
        end
        local d = (viewH / 2) / math.tan(FOV / 2)
        -- The width must fit too: the bare body's width for a close-up (a face
        -- is narrower than the shoulders), the model as it is now for Full
        -- (arms out, lying down).
        if ph > 0 then
            local bw = (frame.key ~= "full" and body) and (body[5] - body[2]) or (y2 - y1)
            local wide = bw * (frame.w or 1.1)
            local hfov = 2 * math.atan(math.tan(FOV / 2) * pw / ph)
            d = math.max(d, (wide / 2) / math.tan(hfov / 2))
        end
        if frame.key == "full" then d = d * P.FullFit(look.race, look.sex) end
        d = d * 100 / (look.zoom or 100)
        local ty = (y1 + y2) / 2
        scene:SetCameraOrientationByYawPitchRoll(math.pi, 0, 0)
        local fx, fy, fz = -1, 0, 0
        if scene.GetCameraForward then
            local x, y, z = scene:GetCameraForward()
            if x then fx, fy, fz = x, y, z end
        end
        -- Cropped (half scrolled out of view): the scene only covers the part
        -- you can see. A narrower lens, moved up or down, shows exactly that
        -- part of the full picture.
        local fov, shift = FOV, 0
        if (ct > 0 or cb > 0) and ph > 0 then
            local vis = math.max(0.01, (ph - ct - cb) / ph)
            fov = 2 * math.atan(math.tan(FOV / 2) * vis)
            local viewWorld = 2 * d * math.tan(FOV / 2)
            shift = ((cb - ct) / 2) / ph * viewWorld
        end
        if scene.SetCameraFieldOfView then scene:SetCameraFieldOfView(DiagFov(fov, pw, ph - ct - cb)) end
        -- Moved in the picture (right-drag in Create): the camera goes the
        -- other way. Screen right is world +y here; up is +z.
        local viewH = 2 * d * math.tan(FOV / 2)
        local viewW = ph > 0 and viewH * pw / ph or viewH
        local panY = -(look.mx or 0) * viewW
        local panZ = -(look.my or 0) * viewH
        scene:SetCameraPosition((x1 + x2) / 2 - fx * d, ty - fy * d + panY, tz - fz * d + shift + panZ)
        -- Where the camera looks, for drawing on heads (UI\Decor.lua): the
        -- whole picture's view, as if not cut off.
        self.cam = { y = ty + panY, z = tz + panZ, half = d * math.tan(FOV / 2), z1 = z1, hgt = z2 - z1, viewW = viewW, viewH = viewH }
        -- The other people, where they stand relative to you (the camera
        -- already follows you): right is +y, up is +z.
        for i, q in ipairs(look.people or {}) do
            local a = self.extras[i]
            if a and a.SetPosition then
                local y, z = ((q.mx or 0) - (look.mx or 0)) * viewW, ((q.my or 0) - (look.my or 0)) * viewH
                a.basePos = { 0, y, z }
                a:SetPosition(0, y, z + (a.lensZ or 0))
            end
        end
        ns.Decor.Apply(self)
        return true
    end

    -- Show only the part of the picture that's in view: `top` and `bottom`
    -- pixels are cut off (a scroll list does this as it moves). 3D models
    -- don't clip to a scroll frame by themselves, so the scene shrinks to the
    -- visible part and Fit moves the camera to match.
    function pic:Crop(top, bottom)
        if not scene then return end
        top, bottom = math.floor((top or 0) + 0.5), math.floor((bottom or 0) + 0.5)
        if top == (self.cropTop or 0) and bottom == (self.cropBottom or 0) and self.cropped ~= nil then return end
        self.cropTop, self.cropBottom, self.cropped = top, bottom, true
        local h = self:GetHeight() or 0
        if top + bottom >= h - 1 then
            scene:Hide()
            return
        end
        scene:Show()
        scene:ClearAllPoints()
        scene:SetPoint("TOPLEFT", 0, -top)
        scene:SetPoint("BOTTOMRIGHT", 0, bottom)
        self.sig = nil
        self:Fit()
    end

    -- Measuring a body: the model loads with no gear and no weapons, hidden,
    -- until its box stops changing; then it loads again, dressed.
    -- (A placeholder NPC is measured standing still, as it is: a pose like
    -- "laugh" makes the box taller than the body.)
    function pic:StartMeasure()
        self.measure = { t = 0, tick = 0 }
        if actor.SetAlpha then actor:SetAlpha(0) end
        if self.display then
            if actor.ClearModel then actor:ClearModel() end
            actor:SetModelByCreatureDisplayID(self.display)
        else
            actor:SetModelByUnit(self.unit, true, false, true, true, false, self.customRace)
            if actor.Undress then actor:Undress() end
        end
        if actor.SetAnimation then actor:SetAnimation(0, 0, 1) end
    end

    function pic:EndMeasure(box)
        if box then BODY[self.bodyKey] = box end
        self.measure = nil
        if not self.display then
            actor:SetModelByUnit(self.unit, not self.look.drawn, true, false, true, false, self.customRace)
        end
        if actor.SetAlpha then actor:SetAlpha(1) end
        self:Ghost()
        self.sig, self.watch, self.fitted = nil, 0, false
        self:Dress()
    end

    local function Measure(elapsed)
        local m = pic.measure
        m.t, m.tick = m.t + elapsed, m.tick + elapsed
        if m.tick < 0.1 then return end
        m.tick = 0
        local x1, y1, z1, x2, y2, z2 = actor:GetActiveBoundingBox()
        if x1 and z2 and (z2 - z1) > 0.05 then
            local sig = string.format("%.3f %.3f %.3f %.3f", x1, z1, x2, z2)
            if m.t > 0.3 and sig == m.last then return pic:EndMeasure({ x1, y1, z1, x2, y2, z2 }) end
            m.last = sig
        end
        if m.t > 2.5 then pic:EndMeasure(nil) end -- (no steady box: frame by the dressed model)
    end

    if scene then
        scene:SetScript("OnUpdate", function(_, elapsed)
            if not pic.look then return end
            if pic.measure then return Measure(elapsed) end
            pic.watch = (pic.watch or 0) + elapsed
            if pic.watch > 2.5 and not pic.missing and actor.IsLoaded and actor:IsLoaded() == false then
                pic.missing = true
                pic:UpdateBadge()
            end
            if pic.watch > 3 and pic.fitted then return end
            pic.tick = (pic.tick or 0) + elapsed
            if pic.tick < 0.1 then return end
            pic.tick = 0
            if pic:Fit() then pic.fitted = true end
        end)
    end

    -- A lens: bigger or smaller, tipped over, upside down (lifted by its
    -- height, so it hangs in the picture), or moving (spin, float: see
    -- pic:LensStep).
    local function LensActor(a, person, main)
        local lens = L.LENS[person.lens or "none"] or L.LENS.none
        local scale = lens.scale or 1
        if a.SetScale then a:SetScale(scale) end
        if a.SetRoll then a:SetRoll(lens.roll or 0) end
        a.lensZ = 0 -- (WoW turns a model round its middle: upside down stays in place)
        a.lensAnim = lens.anim
        a.lensYaw = math.rad(person.yaw or 0)
        a.lensH = P.RaceHeight(person.race or 1, person.sex)
        if main and a.SetPosition then a:SetPosition(0, 0, a.lensZ) end
    end

    local function PoseActor(a, person, main)
        P.Play(a, person)
        if a.SetYaw then a:SetYaw(math.rad(person.yaw or 0)) end
        LensActor(a, person, main)
    end

    -- Each person's head in the picture: { x, y (pixels from the top
    -- left), size (the head's height in pixels), turn (-1..1: how far the
    -- face is turned), person, name }. From the camera Fit set and each
    -- body's height (measured, or the race's); creatures, upside-down and
    -- moving lenses have none. Used by the face filters.
    -- (Where: P.FaceModel, per race and sex, with the camera's view at the
    -- head's depth; P.FaceTune adds what's tuned on /wgram wall.)
    function pic:Heads()
        local cam, look = self.cam, self.look
        if not (cam and look and cam.half > 0) then return {} end
        local w, h = self:GetWidth() or 0, self:GetHeight() or 0
        local px = (h / 2) / cam.half
        local out = {}
        local function Add(person, wy, wz, bodyH, name, a)
            local lens = L.LENS[person.lens or "none"] or L.LENS.none
            if lens.display or lens.upside or lens.anim or (a and a.critter) then return end
            bodyH = bodyH * (lens.scale or 1)
            local m = P.FaceModel(person.race, person.sex)
            local fix, key = P.FaceTune(person.race, person.sex, look.frame)
            local yaw = math.rad(person.yaw or 0)
            -- The head in the world: up from the feet, forward (turning
            -- with the body), a little sideways.
            local fwd = m.fwd * bodyH
            local zE = wz + m.ze * bodyH
            local yE = wy + m.xs * bodyH + fwd * math.sin(yaw)
            -- Nearer the camera, things look bigger: the view at the
            -- head's depth.
            local half = math.max(cam.half * 0.2, cam.half - fwd * math.cos(yaw) * math.tan(FOV / 2))
            local k = (h / 2) / half
            local base = m.s * bodyH * k
            out[#out + 1] = { x = w / 2 + (yE - cam.y) * k + (fix.x or 0) * base, y = h / 2 - (zE - cam.z) * k + (fix.down or 0) * base,
                size = base * (fix.size or 1), base = base, key = key, tuned = next(fix) ~= nil,
                turn = math.sin(yaw), back = math.cos(yaw) < 0.3, person = person, name = name,
                obs = { half = cam.half, camz = cam.z, camy = cam.y, wy = wy, z1 = wz, bodyH = bodyH, w = w, h = h },
                turn = math.sin(yaw), back = math.cos(yaw) < 0.3, person = person, name = name }
        end
        local mainH = (self.display or self.critter) and P.RaceHeight(look.race, look.sex) or cam.hgt
        if not self.critter then Add(look, 0, cam.z1 or 0, mainH, self.author, actor) end
        for i, q in ipairs(look.people or {}) do
            local a = self.extras[i]
            if a and a.basePos then
                Add(q, a.basePos[2], a.basePos[3], P.RaceHeight(q.race, q.sex), q.name, a)
            end
        end
        return out
    end

    -- Moving lenses (from the overlay's OnUpdate, UI\Fx.lua).
    function pic:HasLensAnim()
        if actor and actor.lensAnim then return true end
        for _, a in ipairs(self.extras) do
            if a.lensAnim and a.wsKey then return true end
        end
        return false
    end
    function pic:LensStep(t)
        local function Step(a, main)
            if not a.lensAnim then return end
            if a.lensAnim == "spin" and a.SetYaw then
                a:SetYaw(a.lensYaw + t * 1.6)
            elseif a.lensAnim == "float" and a.SetPosition then
                local bob = (0.5 + 0.5 * math.sin(t * 1.8)) * 0.25 * (a.lensH or 2)
                local b = main and { 0, 0, 0 } or (a.basePos or { 0, 0, 0 })
                a:SetPosition(b[1], b[2], b[3] + (a.lensZ or 0) + bob)
            end
        end
        if actor then Step(actor, true) end
        for _, a in ipairs(self.extras) do if a.wsKey then Step(a, false) end end
    end

    local function Pose()
        local look = pic.look
        PoseActor(actor, look, true)
        for i, q in ipairs(look.people or {}) do
            if pic.extras[i] then PoseActor(pic.extras[i], q) end
        end
    end
    pic.PoseAll = Pose

    -- The other people in a group picture: one actor each, made when needed.
    pic.extras = {}
    local function Extra(i)
        local a = pic.extras[i]
        if a then return a end
        a = scene:CreateActor()
        pic.extras[i] = a
        if a.SetScript then
            pcall(a.SetScript, a, "OnAnimFinished", function()
                local q = pic.look and pic.look.people and pic.look.people[i]
                local pose = q and L.POSE[q.pose]
                if pose and pose.loop and not P.Still(q) then P.Play(a, q) end
            end)
            pcall(a.SetScript, a, "OnModelLoaded", function()
                local q = pic.look and pic.look.people and pic.look.people[i]
                if q then pic:DressExtra(i) end
            end)
        end
        return a
    end

    -- A one-off emote (a wave) is started again when it ends.
    if actor and actor.SetScript then
        pcall(actor.SetScript, actor, "OnAnimFinished", function()
            local pose = pic.look and L.POSE[pic.look.pose]
            if pose and pose.loop and not P.Still(pic.look) then P.Play(actor, pic.look) end
        end)
    end

    -- Background and filter: the backdrop, the light on the character (the
    -- place's light, tinted by the filter), how grey it is, and the wash.
    local function Light()
        local bg = ns.Fx.Background(pic.look)
        local f = L.FILTER[pic.look.filter] or L.FILTER.normal
        P.PaintBackground(pic, pic.bg, bg, f)
        local wash = f.wash
        if wash then pic.wash:SetColorTexture(wash[1], wash[2], wash[3], wash[4]) end
        pic.wash:SetShown(wash ~= nil)
        local l, t = bg.light, f.tint
        local r, g, b = l[1] * t[1], l[2] * t[2], l[3] * t[3]
        ns.Fx.Apply(pic, pic.look, bg, f, { r * 0.85, g * 0.85, b * 0.85 })
        ns.Decor.Apply(pic)
        if not scene then return end
        if scene.SetLightAmbientColor then scene:SetLightAmbientColor(r * 0.8, g * 0.8, b * 0.8) end
        if scene.SetLightDiffuseColor then scene:SetLightDiffuseColor(r * 0.85, g * 0.85, b * 0.85) end
        if actor.SetDesaturation then actor:SetDesaturation(f.grey or 0) end
        for _, a in ipairs(pic.extras) do
            if a.SetDesaturation then a:SetDesaturation(f.grey or 0) end
        end
        pic:Ghost()
    end

    -- The Ghost filter: everyone see-through (not while a body is being
    -- measured, hidden).
    function pic:Ghost()
        if not actor or self.measure then return end
        local f = self.look and L.FILTER[self.look.filter]
        local a = f and f.ghost or 1
        if actor.SetAlpha then actor:SetAlpha(a) end
        for _, x in ipairs(self.extras) do
            if x.SetAlpha then x:SetAlpha(a) end
        end
    end

    -- Put clothes on an actor (after Undress, which takes everything off).
    -- only: just these slots (a stranger's race body: see P.ATTACHED).
    local function DressActor(a, slots, only)
        if a.Undress then a:Undress() end
        for _, def in ipairs(L.SLOTS) do
            local s = (not only or only[def.id]) and slots[def.id]
            local hand = def.id == 16 and "MAINHANDSLOT" or def.id == 17 and "SECONDARYHANDSLOT" or nil
            if s and s.a then
                local info = ItemUtil and ItemUtil.CreateItemTransmogInfo
                    and ItemUtil.CreateItemTransmogInfo(s.a, s.s or 0, s.i or 0)
                if not (info and a.SetItemTransmogInfo
                    and pcall(a.SetItemTransmogInfo, a, info, def.id, def.id ~= 16)) then
                    if a.TryOn then pcall(a.TryOn, a, s.a, hand) end
                end
            elseif s and s.item then
                if not GetInfo(s.item) and not (pic.missingItems and pic.missingItems[s.item]) then
                    pic.waiting = true
                    pic.waitingFor = pic.waitingFor or {}
                    pic.waitingFor[s.item] = true
                    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(s.item) end
                    -- Still nothing after 5 seconds: the game hasn't got it.
                    if not pic.waitTimer then
                        pic.waitTimer = true
                        ns.After(5, function()
                            pic.waitTimer = nil
                            if pic.waiting then
                                pic.missingItems = pic.missingItems or {}
                                for id in pairs(pic.waitingFor or {}) do pic.missingItems[id] = true end
                                pic.waiting, pic.waitingFor, pic.missing = nil, nil, true
                                pic:UpdateBadge()
                            end
                        end)
                    end
                end
                if a.TryOn then pcall(a.TryOn, a, "item:" .. s.item, hand) end
            end
        end
    end

    -- An extra person: their own outfit if the game knows them (a real
    -- body); plain race otherwise, like any stranger.
    function pic:DressExtra(i)
        local q, a = self.look and self.look.people[i], self.extras[i]
        if not (q and a) then return end
        if not a.critter then DressActor(a, q.slots, not a.wsUnit and P.ATTACHED or nil) end
        PoseActor(a, q)
    end

    -- Load (or reload) the extra people's models; hide the ones not used.
    function pic:SetupPeople()
        local people = self.look.people or {}
        for i, q in ipairs(people) do
            local a = Extra(i)
            local unit, race, display = P.UnitFor(q.name), nil, nil
            if not unit then
                local how = P.StandIn(q.race, q.sex, q.slots)
                unit, display = how.unit, how.display
                race = how.unit and q.race or nil
            end
            local critter = (L.LENS[q.lens or "none"] or L.LENS.none).display
            local key = critter and ("c" .. critter) or display and ("d" .. display)
                or ("u" .. unit .. (ns.UnitId(unit) or "") .. ":" .. (race or 0) .. ":" .. (q.drawn and 1 or 0))
            a.critter = critter
            if critter then
                if a.wsKey ~= key then
                    a.wsKey, a.wsUnit = key, nil
                    if a.SetShown then a:SetShown(true) end
                    if a.ClearModel then a:ClearModel() end
                    a:SetModelByCreatureDisplayID(critter)
                end
            elseif a.wsKey ~= key then
                a.wsKey, a.wsUnit = key, unit
                if a.SetShown then a:SetShown(true) end
                if unit then
                    a:SetModelByUnit(unit, not q.drawn, true, false, true, false, race)
                else
                    if a.ClearModel then a:ClearModel() end
                    a:SetModelByCreatureDisplayID(display)
                end
            end
            self:DressExtra(i)
        end
        for i = #people + 1, #self.extras do
            local a = self.extras[i]
            if a.wsKey then
                a.wsKey, a.wsUnit = nil, nil
                if a.ClearModel then a:ClearModel() end
                if a.SetShown then a:SetShown(false) end
            end
        end
    end

    -- Put the look's clothes on.
    function pic:Dress()
        local look = self.look
        if not (actor and look) or self.measure then return end
        self.waiting = nil
        for i in ipairs(look.people or {}) do self:DressExtra(i) end
        if not self.critter then DressActor(actor, look.slots, self.display and P.ATTACHED or nil) end
        Pose()
        self:UpdateBadge()
    end
    if actor and actor.SetScript then
        pcall(actor.SetScript, actor, "OnModelLoaded", function()
            pic:Dress()
            pic.sig, pic.watch, pic.fitted = nil, 0, false
        end)
    end

    -- look: a table or a Look string; author: whose picture it is.
    function pic:SetLook(look, author)
        if type(look) == "string" then look = L.Decode(look) end
        self.shownDisplay = nil
        self.look, self.author, self.drawnShown = look, author, look.drawn
        self.empty:SetText("")
        if not actor then
            self.empty:SetText("This game client can't draw 3D models here.")
            return
        end
        local unit = P.UnitFor(author)
        -- Someone the game doesn't know: their race and gender, plain.
        -- How good a body we can draw: 3 the author's own, 2 a stand-in of
        -- their gender (their whole outfit), 1 a placeholder. A picture of
        -- the same person upgrades when a better body turns up, and keeps the
        -- better one when it walks off.
        local who = author .. ":" .. tostring(look.race) .. ":" .. tostring(look.sex)
        local cur
        if unit then
            cur = { unit = unit, quality = 3 }
        else
            local how = P.StandIn(look.race, look.sex, look.slots)
            -- (No race given: the stand-in as they are.)
            cur = { unit = how.unit, display = how.display, race = how.unit and look.race or nil, quality = how.unit and 2 or 1 }
        end
        local best = self.bestFor == who and self.best or nil
        if best and best.quality > cur.quality then cur = best end
        self.best, self.bestFor, self.quality = cur, who, cur.quality
        unit, self.display, self.customRace = cur.unit, cur.display, cur.race
        self.state = cur.quality == 3 and "real" or cur.quality == 2 and "standin" or "lookalike"
        self.missing, self.missingItems, self.waitingFor = nil, nil, nil
        self.note:SetText("")
        local key = self.display and ("d" .. self.display)
            or (unit .. ":" .. (ns.UnitId(unit) or "") .. ":" .. (self.customRace or 0) .. ":" .. (look.drawn and 1 or 0))
        -- Turned into a creature (a lens): its model instead, framed by
        -- its own outline; no badge (nobody's body is shown).
        local critter = (L.LENS[look.lens or "none"] or L.LENS.none).display
        self.critter = critter
        if critter then
            self.display, self.customRace, self.state = nil, nil, "real"
            key = "c" .. critter
            if self.unitKey ~= key or self.unitName ~= author then
                self.unitKey, self.unitName, self.unit, self.bodyKey = key, author, nil, key
                self.sig, self.watch, self.fitted, self.measure = nil, 0, false, nil
                if actor.SetAlpha then actor:SetAlpha(1) end
                if actor.ClearModel then actor:ClearModel() end
                actor:SetModelByCreatureDisplayID(critter)
            end
        elseif self.unitKey ~= key or self.unitName ~= author then
            self.unitKey, self.unitName, self.unit = key, author, unit
            self.bodyKey = self.display and key or ((ns.UnitId(unit) or unit) .. ":" .. (self.customRace or ""))
            self.sig, self.watch, self.fitted = nil, 0, false
            if self.display then
                self.measure = nil
                if actor.SetAlpha then actor:SetAlpha(1) end
                if actor.ClearModel then actor:ClearModel() end
                actor:SetModelByCreatureDisplayID(self.display)
            elseif BODY[self.bodyKey] or not actor.GetActiveBoundingBox then
                self.measure = nil
                if actor.SetAlpha then actor:SetAlpha(1) end
                actor:SetModelByUnit(unit, not look.drawn, true, false, true, false, self.customRace)
            else
                self:StartMeasure()
            end
        end
        self:SetupPeople()
        self:Dress()
        Light()
        -- Some clients load the model without telling: dress again shortly.
        ns.After(0.15, function() if self.look == look then self:Dress() end end)
        ns.After(0.6, function() if self.look == look then self:Dress() end end)
        self.sig = nil
        self:Fit()
        self:Show()
        self:UpdateBadge()
    end

    -- Show a creature display by its id, framed like any picture (the
    -- placeholder review). Nothing put on.
    function pic:ShowDisplay(id, bg)
        if not actor then return end
        self.look = L.New()
        if bg then self.look.bg = bg end
        self.shownDisplay = id
        self.author, self.display, self.unit, self.customRace = nil, id, nil, nil
        self.unitKey, self.unitName, self.bodyKey = "d" .. id, nil, "d" .. id
        self.measure = nil
        self.note:SetText("")
        self.empty:SetText("")
        if actor.SetAlpha then actor:SetAlpha(1) end
        if actor.ClearModel then actor:ClearModel() end
        actor:SetModelByCreatureDisplayID(id)
        Light()
        self.sig, self.watch, self.fitted = nil, 0, false
        self:Fit()
        self:Show()
    end

    -- Only the pose, angle, framing or filter changed: no need to redress.
    function pic:Restyle()
        if not (actor and self.look) then return end
        local critter = (L.LENS[self.look.lens or "none"] or L.LENS.none).display
        if self.look.drawn ~= self.drawnShown or critter ~= self.critter then
            self.drawnShown = self.look.drawn
            return self:SetLook(self.look, self.author)
        end
        self:SetupPeople()
        Pose()
        Light()
        self.sig, self.watch, self.fitted = nil, 0, false
        self:Fit()
    end

    function pic:Clear(text)
        self.shownDisplay = nil
        self.state, self.missing, self.waiting = nil, nil, nil
        if self.badge then self.badge:Hide() end
        self.look, self.author, self.unitKey = nil, nil, nil
        if actor and actor.ClearModel then actor:ClearModel() end
        for _, a in ipairs(self.extras) do
            a.wsKey, a.wsUnit = nil, nil
            if a.ClearModel then a:ClearModel() end
        end
        self.measure = nil
        self.note:SetText("")
        self.empty:SetText(text or "")
        self.wash:Hide()
        ns.Fx.Stop(self)
        P.PaintBackground(self, self.bg, L.BACKGROUND.normal)
    end

    -- Read what `unit` is wearing as transmog appearances (what others see).
    -- cb(slots) is called once the model has loaded; nil if the client
    -- can't say.
    function pic:ReadOutfit(unit, cb)
        if not (actor and actor.GetItemTransmogInfoList) then return cb(nil) end
        self.measure = nil
        if actor.SetAlpha then actor:SetAlpha(1) end
        actor:SetModelByUnit(unit, true, true, false, true)
        self.unitKey = nil
        local tries = 0
        local function Try()
            tries = tries + 1
            local ok, list = pcall(actor.GetItemTransmogInfoList, actor)
            local slots, n = {}, 0
            if ok and type(list) == "table" then
                for slot, info in pairs(list) do
                    local a = type(info) == "table" and info.appearanceID
                    if L.SLOT[slot] and a and a > 0 then
                        slots[slot] = { a = a, s = info.secondaryAppearanceID or 0, i = info.illusionID or 0 }
                        n = n + 1
                    end
                end
            end
            if n > 0 then return cb(slots) end
            if tries < 8 then ns.After(0.15, Try) else cb(nil) end
        end
        ns.After(0.05, Try)
    end

    -- People: 0 is the main person (the look itself), 1.. the extra ones.
    function pic:Person(index)
        if not index or index == 0 then return self.look end
        return self.look.people[index] or self.look
    end

    -- The person nearest a point on the screen (UI units): by where they
    -- stand in the picture (left/right counts most).
    function pic:Nearest(x, y)
        local left, bottom = self:GetLeft() or 0, self:GetBottom() or 0
        local w, h = math.max(1, self:GetWidth()), math.max(1, self:GetHeight())
        local fx, fy = (x - left) / w - 0.5, (y - bottom) / h - 0.5
        local best, bestIndex, bestD = self.look, 0, math.huge
        local function Try(p, i)
            local d = math.abs(fx - (p.mx or 0)) + 0.3 * math.abs(fy - (p.my or 0))
            if d < bestD then best, bestIndex, bestD = p, i, d end
        end
        Try(self.look, 0)
        for i, q in ipairs(self.look.people or {}) do Try(q, i) end
        return best, bestIndex
    end

    -- Mouse: click (to open), and in the Studio drag to turn and wheel to
    -- zoom. The model itself never takes the mouse.
    if scene then
        scene:EnableMouse(false)
        if scene.EnableMouseWheel then scene:EnableMouseWheel(false) end
    end
    pic:EnableMouse(true)
    pic:EnableMouseWheel(true)
    -- An item on the cursor (picked up from your bags) is dropped, not dragged.
    local function DropItem()
        if not (opts.onDrop and GetCursorInfo) then return false end
        local kind, id, link = GetCursorInfo()
        if kind ~= "item" then return false end
        ClearCursor()
        opts.onDrop(link or id)
        return true
    end
    pic:SetScript("OnReceiveDrag", DropItem)
    pic:SetScript("OnMouseDown", function(self, button)
        if not self.look then return end
        -- Right-drag (Create only): move a person around the picture: the one
        -- nearest the cursor, who also becomes the selected one.
        if button == "RightButton" then
            if not opts.interactive then return end
            local x, y = GetCursorPosition()
            local s = self:GetEffectiveScale() or 1
            local person, index = self:Nearest(x / s, y / s)
            self.selected = index
            if opts.onSelect then opts.onSelect(index) end
            self.move = { x = x, y = y, mx = person.mx or 0, my = person.my or 0, person = person }
            self:SetScript("OnUpdate", function()
                local cx, cy = GetCursorPosition()
                local w, h = math.max(1, self:GetWidth()), math.max(1, self:GetHeight())
                local m = self.move
                m.person.mx = math.max(-0.5, math.min(0.5, m.mx + (cx - m.x) / s / w))
                m.person.my = math.max(-0.5, math.min(0.5, m.my + (cy - m.y) / s / h))
                self.sig = nil
                self:Fit()
            end)
            return
        end
        if button ~= "LeftButton" then return end
        if opts.onDrop and GetCursorInfo and GetCursorInfo() == "item" then return end
        if not opts.interactive then return end
        local mode = opts.mode and opts.mode()
        if mode == "sticker" or mode == "text" then
            local cx, cy = GetCursorPosition()
            local s = self:GetEffectiveScale() or 1
            local lx, ly = cx / s - (self:GetLeft() or 0), (self:GetTop() or 0) - cy / s
            local w, h = math.max(1, self:GetWidth()), math.max(1, self:GetHeight())
            local grab
            if mode == "sticker" and opts.place and opts.place(lx / w * 100, ly / h * 100) then
                return
            end
            if mode == "sticker" then
                local i = ns.Decor.StickerAt(self, lx, ly)
                if i then
                    self.stickerSelected = i
                    if opts.onSticker then opts.onSticker(i) end
                    local st = self.look.stickers[i]
                    grab = { obj = st, x = cx, y = cy, ox = st.x, oy = st.y, both = true }
                end
            elseif self.look.text then
                grab = { obj = self.look.text, x = cx, y = cy, oy = self.look.text.y or 70 }
            end
            if grab then
                self.grab = grab
                ns.Decor.Apply(self)
                self:SetScript("OnUpdate", function()
                    local nx, ny = GetCursorPosition()
                    local g = self.grab
                    if g.both then g.obj.x = math.max(0, math.min(100, g.ox + (nx - g.x) / s / w * 100)) end
                    g.obj.y = math.max(5, math.min(95, g.oy - (ny - g.y) / s / h * 100))
                    ns.Decor.Apply(self)
                end)
                return
            end
        end
        local x = GetCursorPosition()
        local who = self:Person(self.selected)
        self.drag = { x = x, yaw = who.yaw or 0, moved = false, person = who, index = self.selected or 0 }
        self:SetScript("OnUpdate", function()
            local cx = GetCursorPosition()
            local dx = (cx - self.drag.x) / (self:GetEffectiveScale() or 1)
            if math.abs(dx) > 3 then self.drag.moved = true end
            if self.drag.moved then
                local yaw = self.drag.yaw + dx * 0.8
                yaw = ((yaw + 180) % 360) - 180
                self.drag.person.yaw = yaw
                local a = self.drag.index == 0 and actor or self.extras[self.drag.index]
                if a and a.SetYaw then a:SetYaw(math.rad(yaw)) end
                ns.Decor.Apply(self)
            end
        end)
    end)
    pic:SetScript("OnMouseUp", function(self, button)
        self:SetScript("OnUpdate", nil)
        if self.grab then
            self.grab = nil
            if opts.onChange then opts.onChange(self.look) end
            return
        end
        if button == "RightButton" then
            if self.move and opts.onChange then opts.onChange(self.look) end
            self.move = nil
            return
        end
        local drag = self.drag
        self.drag = nil
        if button ~= "LeftButton" or DropItem() then return end
        if drag and drag.moved then
            if opts.onChange then opts.onChange(self.look) end
        elseif opts.onClick then
            opts.onClick()
        end
    end)
    pic:SetScript("OnMouseWheel", function(self, delta)
        if not opts.interactive then
            if self.onWheel then self.onWheel(delta) end
            return
        end
        if not self.look then return end
        local st = opts.mode and opts.mode() == "sticker" and self.look.stickers[self.stickerSelected or 0]
        if st then
            if IsShiftKeyDown and IsShiftKeyDown() then
                st.r = ((st.r or 0) + delta * 15 + 180) % 360 - 180
            else
                st.s = math.max(5, math.min(80, st.s + delta * 3))
            end
            ns.Decor.Apply(self)
            if opts.onChange then opts.onChange(self.look) end
            return
        end
        self.look.zoom = math.max(50, math.min(200, (self.look.zoom or 100) + delta * 10))
        self.sig = nil
        self:Fit()
        if opts.onChange then opts.onChange(self.look) end
    end)

    -- A model set while its frame was hidden can come up blank: set it again
    -- whenever the picture comes into view.
    pic:SetScript("OnShow", function(self)
        if self.shownDisplay then return self:ShowDisplay(self.shownDisplay) end
        if self.look then
            self.unitKey = nil
            self:SetLook(self.look, self.author)
        end
    end)

    pic:Clear()
    return pic
end

-- The window's scale changed: models don't follow by themselves (they stay
-- sized for the old scale), so every visible picture is drawn again.
function P.RefreshAll()
    for _, wait in ipairs({ 0, 0.3 }) do
        ns.After(wait, function()
            for pic in pairs(all) do
                if pic.look and pic:IsVisible() then
                    pic.unitKey = nil
                    pic:SetLook(pic.look, pic.author)
                end
            end
        end)
    end
end

-- What `unit` is wearing (transmog appearances), from a hidden model: for
-- adding someone to a group picture. cb(slots) once read; {} if it can't.
local reader
function P.ReadOutfitOf(unit, cb)
    if not reader then
        local ok, sc = pcall(CreateFrame, "ModelScene", nil, UIParent)
        if not ok or not sc or not sc.CreateActor then return cb({}) end
        sc:SetSize(2, 2)
        sc:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
        reader = { scene = sc, actor = sc:CreateActor() }
    end
    local a = reader.actor
    if not a.GetItemTransmogInfoList then return cb({}) end
    a:SetModelByUnit(unit, true, true, false, true)
    local tries = 0
    local function Try()
        tries = tries + 1
        local ok, list = pcall(a.GetItemTransmogInfoList, a)
        local slots, n = {}, 0
        if ok and type(list) == "table" then
            for slot, info in pairs(list) do
                local id = type(info) == "table" and info.appearanceID
                if L.SLOT[slot] and id and id > 0 then
                    slots[slot] = { a = id, s = info.secondaryAppearanceID or 0, i = info.illusionID or 0 }
                    n = n + 1
                end
            end
        end
        if n > 0 or tries >= 8 then return cb(slots) end
        ns.After(0.15, Try)
    end
    ns.After(0.05, Try)
end

-- Item data arrived: pictures waiting for it dress again.
ns.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
    for pic in pairs(all) do
        if pic.waiting and pic.look then
            if ok == false and id and pic.waitingFor and pic.waitingFor[id] then
                pic.missingItems = pic.missingItems or {}
                pic.missingItems[id] = true
                pic.missing = true
            end
            pic.waitingFor = nil
            pic:Dress()
        end
    end
end)

-- Your target, focus or group changed: pictures of those people can now
-- (or no longer) show their real body.
local function Recheck()
    for pic in pairs(all) do
        if pic.look and pic.author and pic.author ~= ns.Me() and pic:IsVisible() then
            -- (SetLook only reloads a model when its unit, stand-in or race changed.)
            pic:SetLook(pic.look, pic.author)
        end
    end
end
ns.On("PLAYER_TARGET_CHANGED", Recheck)
-- New players in view (nameplates): a few at a time, at most twice a second.
local plateWait = false
ns.On("NAME_PLATE_UNIT_ADDED", function()
    if plateWait then return end
    plateWait = true
    ns.After(0.5, function()
        plateWait = false
        Recheck()
    end)
end)
ns.On("GROUP_ROSTER_UPDATE", Recheck)

---------------------------------------------------------------------------
-- Save to computer: addons can't write image files, but they can take a
-- WoW screenshot. The picture is shown big on black, with who posted it and
-- the caption, the rest of the interface is hidden for a moment, and the
-- screenshot goes to WoW's Screenshots folder.
---------------------------------------------------------------------------
local shot
function P.SaveToComputer(post)
    if not (post and Screenshot) then return end
    if InCombatLockdown and InCombatLockdown() then
        return ns.Print("Not in combat: saving hides your interface for a moment.")
    end
    if shot and shot.busy then return end
    if not shot then
        -- No parent: it stays up while the interface (UIParent) is hidden.
        shot = CreateFrame("Frame", "WowstagramScreenshot", nil)
        shot:SetFrameStrata("FULLSCREEN_DIALOG")
        shot:SetAllPoints(WorldFrame)
        local bg = shot:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 1)
        shot.who = shot:CreateFontString(nil, "OVERLAY")
        shot.caption = shot:CreateFontString(nil, "OVERLAY")
        shot.brand = shot:CreateFontString(nil, "OVERLAY")
        shot.wait = shot:CreateFontString(nil, "OVERLAY")
        shot:Hide()
        ns.On("SCREENSHOT_SUCCEEDED", function() if shot.busy then shot.Done(true) end end)
        ns.On("SCREENSHOT_FAILED", function() if shot.busy then shot.Done(false) end end)
    end
    local sh = shot:GetHeight() or 0
    if sh <= 0 then sh = (GetScreenHeight and GetScreenHeight() or 768) end
    local ph = math.floor(sh * 0.8)
    local pw = math.floor(ph / L.ASPECT)
    if not shot.pic or shot.picH ~= ph then
        if shot.pic then shot.pic:Hide() end
        shot.pic = P.New(shot, pw, ph)
        shot.pic:SetPoint("CENTER", 0, sh * 0.03)
        shot.picH = ph
    end
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local size = math.max(12, math.floor(sh / 45))
    shot.who:SetFont(font, size, "")
    shot.who:SetPoint("TOPLEFT", shot.pic, "BOTTOMLEFT", 0, -size * 0.6)
    shot.who:SetText(ns.ColorName(post.author, post.class))
    shot.caption:SetFont(font, size, "")
    shot.caption:SetPoint("LEFT", shot.who, "RIGHT", size * 0.6, 0)
    shot.caption:SetPoint("RIGHT", shot.pic, "BOTTOMRIGHT", 0, 0)
    shot.caption:SetJustifyH("LEFT")
    shot.caption:SetWordWrap(false)
    shot.caption:SetTextColor(1, 1, 1)
    shot.caption:SetText(ns.Plain(post.caption))
    shot.brand:SetFont("Fonts\\MORPHEUS.TTF", size, "")
    shot.brand:SetPoint("BOTTOMRIGHT", shot.pic, "TOPRIGHT", 0, size * 0.5)
    shot.brand:SetTextColor(0.6, 0.6, 0.6)
    shot.brand:SetText("Wowstagram")
    shot.wait:SetFont(font, size, "")
    shot.wait:SetPoint("BOTTOM", 0, size)
    shot.wait:SetTextColor(0.6, 0.6, 0.6)
    shot.wait:SetText("Getting the picture ready...")
    shot.wait:Show()
    shot.pic:SetLook(post.look, post.author)
    shot:Show()
    shot.busy = true

    local uiWasShown = UIParent:IsShown()
    function shot.Done(ok)
        shot.busy = false
        shot:Hide()
        if uiWasShown then UIParent:Show() end
        ns.Print(ok and "Saved to your Screenshots folder (in your World of Warcraft folder)."
            or "The screenshot didn't work. Try again?")
    end
    -- Give the 3D model a moment to load and settle, then hide everything
    -- else and take it.
    ns.After(1.2, function()
        if not shot.busy then return end
        shot.wait:Hide()
        UIParent:Hide()
        ns.After(0.1, function()
            if not shot.busy then return end
            Screenshot()
            -- No word from the game: put everything back anyway.
            ns.After(3, function() if shot.busy then shot.Done(true) end end)
        end)
    end)
end

---------------------------------------------------------------------------
-- /wgram wall: every race, men and women, side by side, to check framing.
-- One outfit on everyone (the demo people's, in turn) and one framing.
---------------------------------------------------------------------------
local RACE_ORDER = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22 }
local RACE_NAME = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "Night Elf", [5] = "Undead", [6] = "Tauren",
    [7] = "Gnome", [8] = "Troll", [9] = "Goblin", [10] = "Blood Elf", [11] = "Draenei", [22] = "Worgen" }
local WALL_FRAMES = { "full", "waist", "face" }
function P.Wall()
    if P.wall then return P.wall:SetShown(not P.wall:IsShown()) end
    local races = {}
    for _, r in ipairs(RACE_ORDER) do
        if not ns.FOREVER or r <= 8 then races[#races + 1] = r end
    end
    -- As big as the screen allows: the rows fill its height, unless the
    -- columns would run off its sides.
    local COLS = 8
    local n = #races * 2
    local rows = math.ceil(n / COLS)
    local sw, sh = UIParent:GetWidth() or 1000, UIParent:GetHeight() or 700
    local PH = math.floor((sh * 0.94 - 90) / rows - 24)
    local PW = math.floor(PH / L.ASPECT)
    if COLS * (PW + 8) + 22 > sw * 0.98 then
        PW = math.floor((sw * 0.98 - 22) / COLS - 8)
        PH = math.floor(PW * L.ASPECT)
    end
    local f = CreateFrame("Frame", "WowstagramWall", UIParent)
    f:SetSize(COLS * (PW + 8) + 22, rows * (PH + 24) + 90)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    W.Fill(f, W.C.bg, 0.95)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local close = W.Glyph(f, "Close", 14, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    local title = W.Text(f, 14)
    title:SetPoint("TOP", 0, -12)

    local cells = {}
    local i = 0
    for _, sex in ipairs({ 2, 3 }) do
        for _, race in ipairs(races) do
            local col, row = i % COLS, math.floor(i / COLS)
            i = i + 1
            local pic = P.New(f, PW, PH, { badge = "small" })
            pic:SetPoint("TOPLEFT", 15 + col * (PW + 8), -40 - row * (PH + 24))
            local label = W.Text(f, 10, W.C.dim)
            label:SetPoint("TOP", pic, "BOTTOM", 0, -3)
            label:SetText(RACE_NAME[race] .. (sex == 3 and " woman" or " man"))
            cells[#cells + 1] = { race = race, sex = sex, pic = pic }
        end
    end

    local frame, outfit, pose = 1, 1, 1
    local people = ns.Bots.PEOPLE
    local function Show()
        local who = people[outfit]
        local set = ns.FOREVER and who.forever or who.outfit
        local ps = L.POSES[pose]
        title:SetText(P.faceGrid and "Tune faces: drag the glasses onto the eyes, wheel to size them. Right-click: undo. Saved as you go."
            or (L.FRAME[WALL_FRAMES[frame]].name .. "  -  " .. ps.name .. "  -  " .. who.name .. "'s outfit"))
        for k, c in ipairs(cells) do
            local look = L.New()
            look.race, look.sex, look.class = c.race, c.sex, who.class
            look.frame = WALL_FRAMES[frame]
            look.pose, look.drawn = ps.key, ps.drawn
            look.face = P.faceGrid and "nerd" or nil
            c.tune:SetShown(P.faceGrid and true or false)
            if c.pic.badge then c.pic.badge:SetAlpha(P.faceGrid and 0 or 1) end
            for slot, item in pairs(set) do look.slots[slot] = { item = item } end
            c.pic:SetLook(look, "Wall " .. k)
        end
    end
    local x = 15
    for k, key in ipairs(WALL_FRAMES) do
        local b = W.Flat(f, L.FRAME[key].name, 80, 26, "secondary", function()
            frame = k
            Show()
        end, 12)
        b:SetPoint("BOTTOMLEFT", x, 12)
        x = x + 88
    end
    local nextOutfit = W.Flat(f, "Next outfit", 100, 26, "primary", function()
        outfit = outfit % #people + 1
        Show()
    end, 12)
    nextOutfit:SetPoint("BOTTOMRIGHT", -15, 12)
    -- Tune faces: glasses and a grid on every head; drag the glasses onto
    -- the eyes and wheel them to size, per race and sex (saved in
    -- ns.db.faceTune on top of P.FACE_MODEL; right-click: back to the model).
    local tuneB = W.Flat(f, "Tune faces", 100, 26, "secondary", function(self)
        P.faceGrid = not P.faceGrid
        self:SetStyle(P.faceGrid and "light" or "secondary")
        Show()
    end, 12)
    local gridB = tuneB
    P.wallTune, P.wallCells = tuneB, cells
    for _, c in ipairs(cells) do
        local b = CreateFrame("Button", nil, f)
        b:SetAllPoints(c.pic)
        b:SetFrameLevel(c.pic:GetFrameLevel() + 20)
        b:RegisterForClicks("AnyUp")
        b:EnableMouseWheel(true)
        local function Head()
            local head = c.pic:Heads()[1]
            if not head then return end
            ns.db.faceTune = ns.db.faceTune or {}
            local fix = ns.db.faceTune[head.key]
            if not fix then
                fix = { down = 0, size = 1, x = 0 }
                ns.db.faceTune[head.key] = fix
            end
            return head, fix
        end
        b:SetScript("OnMouseDown", function(self, button)
            if not P.faceGrid then return end
            if button == "RightButton" then
                local head = c.pic:Heads()[1]
                if head and ns.db.faceTune then ns.db.faceTune[head.key] = nil end
                ns.Decor.Apply(c.pic)
                return
            end
            local head, fix = Head()
            if not head then return end
            local x0, y0 = GetCursorPosition()
            local s = self:GetEffectiveScale() or 1
            local d0, xx0 = fix.down, fix.x
            self:SetScript("OnUpdate", function()
                local x, y = GetCursorPosition()
                fix.down = d0 + (y0 - y) / s / head.base
                fix.x = xx0 + (x - x0) / s / head.base
                ns.Decor.Apply(c.pic)
            end)
        end)
        b:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
        b:SetScript("OnMouseWheel", function(_, delta)
            if not P.faceGrid then return end
            local head, fix = Head()
            if not head then return end
            fix.size = math.max(0.3, math.min(5, (fix.size or 1) * (1 + delta * 0.06)))
            ns.Decor.Apply(c.pic)
        end)
        b:SetShown(false)
        c.tune = b
    end
    local nextPose = W.Flat(f, "Next pose", 100, 26, "secondary", function()
        pose = pose % #L.POSES + 1
        Show()
    end, 12)
    nextPose:SetPoint("RIGHT", nextOutfit, "LEFT", -8, 0)
    gridB:SetPoint("RIGHT", nextPose, "LEFT", -8, 0)
    Show()
    P.wall = f
end
