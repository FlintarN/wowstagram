-- Look: what a picture is. A table, and the short string it travels as.
--
--   look = {
--     race = 1, sex = 2, class = "MAGE",   -- who is in it (UnitRace id, UnitSex)
--     pose = "dance", yaw = -20, zoom = 100, frame = "full",
--     bg = "elwynn", filter = "warm",       -- backdrop, and the photo filter on top
--     overlay = "snow",                    -- things moving over the picture (UI\Fx.lua)
--     bgTop = "ff8800", bgBottom = "220044",  -- bg = "custom": your own two colours
--     stickers = { { key = "heart", x = 50, y = 30, s = 20, r = 0 }, ... },  -- (UI\Decor.lua)
--     text = { text = "gg", style = "bar", y = 70 },  -- one line of big text
--     deco = "polaroid",                   -- a frame around the picture
--     lens = "sheep",                      -- (each person) turned into something
--     drawn = true,                        -- weapons in hand
--     mx = 0.1, my = -0.05,                -- moved right / down in the picture (share of its size)
--     people = { { name = "Bob-Realm", race, sex, class, pose, yaw, mx, my, drawn, slots }, ... },
--                                          -- up to 3 more people (a group picture)
--     slots = { [1] = { a = 1234, s = 0, i = 0 }, [16] = { item = 19019 }, ... },
--   }
--
-- A slot is either a transmog appearance (a = the appearance source id the
-- game's own dressing room uses, s = secondary, i = illusion) or a plain item
-- id, used where the client can't read appearances. A missing slot is bare.
--
-- String: "1;r1;g2;cMAGE;pdance;y-20;z100;ffull;belwynn;xwarm;w;s1=a12x,16=iez7"
-- (numbers in slots are base 36 to keep pictures short). Each extra person
-- is one token, "q" and their own fields joined by "/", with "n<name>":
-- "q nBob-Realm/r4/g3/cDRUID/pwave/m20,0/s1=a12x".
local ADDON, ns = ...

local L = {}
ns.Look = L

-- The slots you can dress, in the order the studio shows them.
L.SLOTS = {
    { id = 1, name = "Head" }, { id = 3, name = "Shoulders" }, { id = 15, name = "Back" },
    { id = 5, name = "Chest" }, { id = 4, name = "Shirt" }, { id = 19, name = "Tabard" },
    { id = 9, name = "Wrists" }, { id = 10, name = "Hands" }, { id = 6, name = "Waist" },
    { id = 7, name = "Legs" }, { id = 8, name = "Feet" }, { id = 16, name = "Main hand" },
    { id = 17, name = "Off hand" },
}
L.SLOT = {}
for _, s in ipairs(L.SLOTS) do L.SLOT[s.id] = s end

-- Poses: animation ids from the game's AnimationData. `loop`: the animation
-- ends by itself, so it's started again (a wave keeps waving).
L.POSES = {
    { key = "stand", name = "Stand", anim = 0 },
    { key = "dance", name = "Dance", anim = 69 },
    { key = "wave", name = "Wave", anim = 67, loop = true },
    { key = "cheer", name = "Cheer", anim = 68, loop = true },
    { key = "laugh", name = "Laugh", anim = 70, loop = true },
    { key = "flex", name = "Flex", anim = 82, loop = true },
    { key = "salute", name = "Salute", anim = 113, loop = true },
    { key = "bow", name = "Bow", anim = 66, loop = true },
    { key = "point", name = "Point", anim = 84, loop = true },
    { key = "roar", name = "Roar", anim = 74, loop = true },
    { key = "applaud", name = "Applaud", anim = 80, loop = true },
    { key = "kiss", name = "Kiss", anim = 76, loop = true },
    { key = "shy", name = "Shy", anim = 83, loop = true },
    { key = "rude", name = "Rude", anim = 73, loop = true },
    { key = "chicken", name = "Chicken", anim = 78, loop = true },
    { key = "cry", name = "Cry", anim = 77, loop = true },
    { key = "kneel", name = "Kneel", anim = 115 },
    { key = "sit", name = "Sit", anim = 97 },
    { key = "sleep", name = "Sleep", anim = 71 },
    { key = "ready", name = "Battle", anim = 26, drawn = true },
    { key = "cast", name = "Cast", anim = 52 },
    { key = "dead", name = "Dead", anim = 6 },
}
L.POSE = {}
for _, p in ipairs(L.POSES) do L.POSE[p.key] = p end

-- Framing: how much of the character is in the picture. `z`: where the
-- camera looks, as a share of the body's height from the feet; `h`: how
-- much of the height must fit; `w`: how much of the body's width must fit
-- (whichever is tighter wins). The body is measured without gear, so a
-- polearm on the back doesn't count: UI\Picture.lua.
L.FRAMES = {
    { key = "full", name = "Full", z = 0.5, h = 1.1, w = 1.15 },
    { key = "waist", name = "Waist up", z = 0.76, h = 0.56, w = 1.2 },
    { key = "face", name = "Face", z = 0.885, h = 0.3, w = 0.62 },
}

-- Every picture has the same shape (width : height = 4 : 5, like an
-- Instagram portrait post), so the Studio shows exactly what others see.
L.ASPECT = 1.25
L.FRAME = {}
for _, f in ipairs(L.FRAMES) do L.FRAME[f.key] = f end

-- Backgrounds: the backdrop (top and bottom colour) and the colour of the
-- light on the character, as if standing there.
L.BACKGROUNDS = {
    { key = "normal", name = "Studio", top = { 0.2, 0.2, 0.23 }, bottom = { 0.05, 0.05, 0.06 }, light = { 1, 1, 1 } },
    { key = "light", name = "Light studio", top = { 0.92, 0.92, 0.9 }, bottom = { 0.66, 0.66, 0.64 }, light = { 1, 1, 1 } },
    { key = "elwynn", name = "Elwynn", top = { 0.45, 0.66, 0.92 }, bottom = { 0.22, 0.42, 0.14 }, light = { 1, 1, 0.94 } },
    { key = "durotar", name = "Durotar", top = { 0.96, 0.56, 0.26 }, bottom = { 0.42, 0.18, 0.08 }, light = { 1, 0.84, 0.68 } },
    { key = "winterspring", name = "Winterspring", top = { 0.86, 0.93, 1 }, bottom = { 0.48, 0.58, 0.74 }, light = { 0.86, 0.93, 1.1 } },
    { key = "felwood", name = "Felwood", top = { 0.26, 0.46, 0.1 }, bottom = { 0.04, 0.11, 0.03 }, light = { 0.8, 1, 0.68 } },
    { key = "duskwood", name = "Duskwood", top = { 0.26, 0.16, 0.42 }, bottom = { 0.04, 0.02, 0.08 }, light = { 0.72, 0.7, 1 } },
    { key = "moonglade", name = "Moonglade", top = { 0.34, 0.3, 0.62 }, bottom = { 0.78, 0.5, 0.7 }, light = { 0.96, 0.86, 1 } },
    { key = "stormwind", name = "Stormwind", top = { 0.24, 0.34, 0.62 }, bottom = { 0.78, 0.62, 0.3 }, light = { 1, 0.95, 0.85 } },
    { key = "tanaris", name = "Tanaris", top = { 0.92, 0.77, 0.52 }, bottom = { 0.55, 0.4, 0.24 }, light = { 1, 0.9, 0.7 } },
}
local MORE = {
    { key = "sunset", name = "Sunset", top = { 0.98, 0.45, 0.35 }, bottom = { 0.3, 0.1, 0.35 }, light = { 1, 0.8, 0.7 } },
    { key = "ocean", name = "Ocean", top = { 0.1, 0.55, 0.75 }, bottom = { 0.02, 0.1, 0.3 }, light = { 0.8, 0.95, 1 } },
    { key = "candy", name = "Candy", top = { 1, 0.6, 0.85 }, bottom = { 0.55, 0.75, 1 }, light = { 1, 0.92, 1 } },
    { key = "mint", name = "Mint", top = { 0.7, 1, 0.85 }, bottom = { 0.25, 0.6, 0.55 }, light = { 0.92, 1, 0.95 } },
    { key = "gold", name = "Gold", top = { 1, 0.85, 0.35 }, bottom = { 0.5, 0.3, 0.05 }, light = { 1, 0.92, 0.7 } },
    { key = "lava", name = "Lava", top = { 1, 0.35, 0.05 }, bottom = { 0.25, 0.02, 0 }, light = { 1, 0.7, 0.5 } },
    { key = "void", name = "Void", top = { 0.25, 0.05, 0.4 }, bottom = { 0, 0, 0 }, light = { 0.8, 0.65, 1 } },
    { key = "blood", name = "Blood", top = { 0.6, 0.02, 0.05 }, bottom = { 0.1, 0, 0 }, light = { 1, 0.75, 0.75 } },
    { key = "sky", name = "Clear sky", top = { 0.35, 0.65, 1 }, bottom = { 0.85, 0.93, 1 }, light = { 1, 1, 1 } },
    { key = "midnight", name = "Midnight", top = { 0.05, 0.07, 0.2 }, bottom = { 0, 0, 0.02 }, light = { 0.7, 0.75, 1 } },
}
for _, b in ipairs(MORE) do table.insert(L.BACKGROUNDS, b) end
for _, b in ipairs(L.BACKGROUNDS) do b.group = "studio" end

-- Moving backgrounds (UI\Fx.lua animates them; `anim` says how).
for _, b in ipairs({
    { key = "disco", name = "Disco", anim = "disco", top = { 0.9, 0.2, 0.8 }, bottom = { 0.1, 0.1, 0.4 }, light = { 1, 0.9, 1 } },
    { key = "rainbow", name = "Rainbow", anim = "rainbow", top = { 1, 0.4, 0.4 }, bottom = { 0.4, 0.4, 1 }, light = { 1, 1, 1 } },
    { key = "aurora", name = "Aurora", anim = "aurora", top = { 0.2, 0.9, 0.6 }, bottom = { 0.02, 0.04, 0.12 }, light = { 0.85, 1, 0.95 } },
    { key = "starfield", name = "Starfield", anim = "stars", top = { 0.04, 0.05, 0.16 }, bottom = { 0, 0, 0.02 }, light = { 0.8, 0.85, 1 } },
}) do
    b.group = "fun"
    table.insert(L.BACKGROUNDS, b)
end

-- Liquids: WoW's own animated water textures (30 frames each, by file id:
-- their names don't load), tiled.
for _, b in ipairs({
    { key = "lava", name = "Lava", frames = { 219795, 219806, 219817, 219819, 219820, 219821, 219822, 219823, 219824, 219796, 219797, 219798, 219799, 219800, 219801, 219802, 219803, 219804, 219805, 219807, 219808, 219809, 219810, 219811, 219812, 219813, 219814, 219815, 219816, 219818 }, light = { 1, 0.7, 0.5 } },
    { key = "ocean", name = "Ocean waves", frames = { 219855, 219866, 219877, 219879, 219880, 219881, 219882, 219883, 219884, 219856, 219857, 219858, 219859, 219860, 219861, 219862, 219863, 219864, 219865, 219867, 219868, 219869, 219870, 219871, 219872, 219873, 219874, 219875, 219876, 219878 }, light = { 0.8, 0.95, 1 } },
    { key = "slime", name = "Slime", frames = { 219991, 220002, 220013, 220015, 220016, 220017, 220018, 220019, 220020, 219992, 219993, 219994, 219995, 219996, 219997, 219998, 219999, 220000, 220001, 220003, 220004, 220005, 220006, 220007, 220008, 220009, 220010, 220011, 220012, 220014 }, light = { 0.85, 1, 0.75 } },
    { key = "lake", name = "Lake", frames = { 219901, 219912, 219923, 219925, 219926, 219927, 219928, 219929, 219930, 219902, 219903, 219904, 219905, 219906, 219907, 219908, 219909, 219910, 219911, 219913, 219914, 219915, 219916, 219917, 219918, 219919, 219920, 219921, 219922, 219924 }, light = { 0.85, 0.95, 1 } },
}) do
    b.group, b.anim, b.liquid = "fun", "liquid", true
    b.top, b.bottom = { 0.3, 0.3, 0.35 }, { 0.1, 0.1, 0.12 }
    table.insert(L.BACKGROUNDS, b)
end

-- Ground: the classic zones' terrain textures, tiled (by file id).
for _, g in ipairs({
    { "grass", "Elwynn grass", 187126 }, { "cobble", "Cobblestones", 187099 },
    { "duskgrass", "Duskwood grass", 187084 }, { "jungle", "Jungle", 188821 },
    { "jungleroad", "Jungle road", 188817 }, { "roots", "Un'Goro roots", 188975 },
    { "moss", "Felwood moss", 188474 }, { "felslime", "Fel slime", 188465 },
    { "dirt", "Durotar dirt", 187017 }, { "beach", "Beach", 187042 },
    { "desert", "Desert", 188870 }, { "cracked", "Cracked earth", 188855 },
    { "snow", "Snow", 188573 }, { "ice", "Ice", 188561 },
    { "lavarock", "Lava rock", 186942 }, { "planks", "Wood planks", 188603 },
    { "goldwood", "Golden wood", 188607 },
}) do
    table.insert(L.BACKGROUNDS, { key = "gr_" .. g[1], name = g[2], group = "ground", tile = g[3],
        top = { 0.3, 0.3, 0.3 }, bottom = { 0.15, 0.15, 0.15 }, light = { 1, 0.97, 0.92 } })
end

-- Talent trees: the classic talent backgrounds (four pieces, laid out like
-- the dressing rooms).
for _, t in ipairs({
    { "Druid", "Balance", "Balance" }, { "Druid", "FeralCombat", "Feral" }, { "Druid", "Restoration", "Restoration" },
    { "Hunter", "BeastMastery", "Beast Mastery" }, { "Hunter", "Marksmanship", "Marksmanship" }, { "Hunter", "Survival", "Survival" },
    { "Mage", "Arcane", "Arcane" }, { "Mage", "Fire", "Fire" }, { "Mage", "Frost", "Frost" },
    { "Paladin", "Holy", "Holy" }, { "Paladin", "Protection", "Protection" }, { "Paladin", "Combat", "Retribution" },
    { "Priest", "Discipline", "Discipline" }, { "Priest", "Holy", "Holy" }, { "Priest", "Shadow", "Shadow" },
    { "Rogue", "Assassination", "Assassination" }, { "Rogue", "Combat", "Combat" }, { "Rogue", "Subtlety", "Subtlety" },
    { "Shaman", "ElementalCombat", "Elemental" }, { "Shaman", "Enhancement", "Enhancement" }, { "Shaman", "Restoration", "Restoration" },
    { "Warlock", "Curses", "Affliction" }, { "Warlock", "Summoning", "Demonology" }, { "Warlock", "Destruction", "Destruction" },
    { "Warrior", "Arms", "Arms" }, { "Warrior", "Fury", "Fury" }, { "Warrior", "Protection", "Protection" },
}) do
    local base = "Interface\\TalentFrame\\" .. t[1] .. t[2] .. "-"
    table.insert(L.BACKGROUNDS, { key = "tal_" .. (t[1] .. t[2]):lower(), name = t[3], class = t[1]:upper(), group = "talent",
        room = { base .. "TopLeft", base .. "TopRight", base .. "BottomLeft", base .. "BottomRight" }, cw = 298, ch = 330,
        top = { 0.25, 0.22, 0.2 }, bottom = { 0.1, 0.09, 0.08 }, light = { 1, 0.97, 0.92 } })
end

-- Books: the pages of in-game books and letters.
for _, b in ipairs({ { "marble", "Marble", "ItemText-Marble" },
    { "bronze", "Bronze", "ItemText-Bronze" }, { "silver", "Silver", "ItemText-Silver" }, { "stone", "Stone", "ItemText-Stone" },
    { "valentine", "Valentine", "ItemText-Valentine" } }) do
    local base = "Interface\\ItemTextFrame\\" .. b[3] .. "-"
    table.insert(L.BACKGROUNDS, { key = "bk_" .. b[1], name = b[2], group = "book",
        room = { base .. "TopLeft", base .. "TopRight", base .. "BotLeft", base .. "BotRight" }, cw = 318, ch = 355,
        top = { 0.6, 0.5, 0.35 }, bottom = { 0.35, 0.28, 0.18 }, light = { 1, 0.97, 0.9 } })
end

-- Your own: two colours from the palette (look.bgTop, look.bgBottom).
table.insert(L.BACKGROUNDS, { key = "custom", name = "Your colours", group = "custom",
    top = { 1, 0.5, 0.2 }, bottom = { 0.2, 0.1, 0.4 }, light = { 1, 1, 1 } })
L.PALETTE = { "000000", "ffffff", "7f7f7f", "ff3b30", "ff9500", "ffcc00", "34c759", "00c7be",
    "30b0ff", "007aff", "5856d6", "af52de", "ff2d92", "8b5a2b", "1b2a49", "ffd1dc" }

-- Dressing rooms: the classic Dressing Room's backdrop for each race, four
-- pieces making a 320 x 384 picture (almost exactly our 4 : 5). File ids
-- from the community listfile; classic-era files, so every client has them.
local ROOMS = {
    { "human", "Human", 131093 }, { "dwarf", "Dwarf", 131089 }, { "nightelf", "Night Elf", 131097 },
    { "orc", "Orc", 131101 }, { "scourge", "Undead", 131105 }, { "tauren", "Tauren", 131109 },
}
for _, r in ipairs(ROOMS) do
    table.insert(L.BACKGROUNDS, { key = "dr_" .. r[1], name = r[2], group = "room",
        room = { r[3], r[3] + 1, r[3] + 2, r[3] + 3 }, cw = 318, ch = 336,
        top = { 0.25, 0.22, 0.2 }, bottom = { 0.1, 0.09, 0.08 }, light = { 1, 0.97, 0.92 } })
end

-- Places: classic loading screens (4 : 3 paintings; the middle of each is
-- shown). `light`: the colour of the light on you there.
local PLACES = {
    { "ek", "Eastern Kingdoms", 131839, { 1, 0.97, 0.9 } },
    { "kalimdor", "Kalimdor", 131848, { 1, 0.95, 0.85 } },
    { "deadmines", "Deadmines", 131833, { 1, 0.9, 0.75 } },
    { "wailing", "Wailing Caverns", 131882, { 0.85, 1, 0.85 } },
    { "sfk", "Shadowfang Keep", 131869, { 0.8, 0.8, 1 } },
    { "monastery", "Scarlet Monastery", 131852, { 1, 0.88, 0.85 } },
    { "zulfarrak", "Zul'Farrak", 131885, { 1, 0.92, 0.75 } },
    { "maraudon", "Maraudon", 131850, { 0.9, 1, 0.85 } },
    { "brd", "Blackrock Depths", 131824, { 1, 0.75, 0.6 } },
    { "diremaul", "Dire Maul", 131835, { 0.9, 0.95, 1 } },
    { "scholo", "Scholomance", 131868, { 0.8, 0.9, 0.85 } },
    { "strat", "Stratholme", 131871, { 1, 0.85, 0.75 } },
    { "zg", "Zul'Gurub", 131886, { 0.85, 1, 0.85 } },
    { "mc", "Molten Core", 131851, { 1, 0.7, 0.5 } },
    { "bwl", "Blackwing Lair", 131827, { 1, 0.75, 0.7 } },
    { "aq", "Ahn'Qiraj", 131819, { 1, 0.9, 0.7 } },
    { "naxx", "Naxxramas", 131854, { 0.75, 0.9, 0.85 } },
    { "wsg", "Warsong Gulch", 131883, { 1, 0.97, 0.9 } },
    { "ab", "Arathi Basin", 131820, { 1, 0.95, 0.88 } },
    { "av", "Alterac Valley", 131861, { 0.9, 0.95, 1 } },
    { "aq20", "Ruins of Ahn'Qiraj", 131818, { 1, 0.9, 0.7 } },
    { "bfd", "Blackfathom Deeps", 131823, { 0.8, 0.9, 1 } },
    { "brs", "Blackrock Spire", 131825, { 1, 0.75, 0.6 } },
    { "gnomer", "Gnomeregan", 131841, { 0.9, 1, 0.9 } },
    { "rfc", "Ragefire Chasm", 131862, { 1, 0.75, 0.55 } },
    { "rfk", "Razorfen Kraul", 131865, { 1, 0.92, 0.8 } },
    { "rfd", "Razorfen Downs", 131864, { 0.9, 0.9, 0.95 } },
    { "stockade", "The Stockade", 131870, { 1, 0.92, 0.85 } },
    { "sunken", "Sunken Temple", 131872, { 0.85, 1, 0.9 } },
    { "uldaman", "Uldaman", 131876, { 1, 0.95, 0.85 } },
    { "dungeon", "Dungeon", 131838, { 0.95, 0.92, 0.9 } },
    { "raid", "Raid", 131863, { 1, 0.9, 0.85 } },
}
for _, p in ipairs(PLACES) do
    table.insert(L.BACKGROUNDS, { key = "ls_" .. p[1], name = p[2], group = "place", file = p[3],
        top = { 0.2, 0.2, 0.22 }, bottom = { 0.06, 0.06, 0.07 }, light = p[4] })
end

-- Maps: the old world maps (a 4 x 3 grid of tiles, "<folder>1" to
-- "<folder>12"; the folder names are Blizzard's own, typos and all).
local MAPS = {
    { "azeroth", "Eastern Kingdoms", "Azeroth" }, { "kalimdor", "Kalimdor", "Kalimdor" },
    { "elwynn", "Elwynn Forest", "Elwynn" }, { "westfall", "Westfall", "Westfall" }, { "duskwood", "Duskwood", "Duskwood" },
    { "redridge", "Redridge", "Redridge" }, { "stv", "Stranglethorn", "Stranglethorn" }, { "dunmorogh", "Dun Morogh", "DunMorogh" },
    { "lochmodan", "Loch Modan", "LochModan" }, { "wetlands", "Wetlands", "Wetlands" }, { "tirisfal", "Tirisfal", "Tirisfal" },
    { "silverpine", "Silverpine", "Silverpine" }, { "hillsbrad", "Hillsbrad", "Hilsbrad" }, { "alterac", "Alterac", "Alterac" },
    { "arathi", "Arathi", "Arathi" }, { "hinterlands", "Hinterlands", "Hinterlands" }, { "badlands", "Badlands", "Badlands" },
    { "searing", "Searing Gorge", "SearingGorge" }, { "burning", "Burning Steppes", "BurningSteppes" },
    { "deadwind", "Deadwind Pass", "DeadwindPass" }, { "swamp", "Swamp of Sorrows", "SwampOfSorrows" },
    { "blasted", "Blasted Lands", "BlastedLands" }, { "wpl", "W. Plaguelands", "WesternPlaguelands" },
    { "epl", "E. Plaguelands", "EasternPlaguelands" }, { "durotar", "Durotar", "Durotar" }, { "mulgore", "Mulgore", "Mulgore" },
    { "barrens", "The Barrens", "Barrens" }, { "teldrassil", "Teldrassil", "Teldrassil" }, { "darkshore", "Darkshore", "Darkshore" },
    { "ashenvale", "Ashenvale", "Ashenvale" }, { "stonetalon", "Stonetalon", "StonetalonMountains" },
    { "needles", "Thousand Needles", "ThousandNeedles" }, { "desolace", "Desolace", "Desolace" }, { "dustwallow", "Dustwallow", "Dustwallow" },
    { "feralas", "Feralas", "Feralas" }, { "tanaris", "Tanaris", "Tanaris" }, { "ungoro", "Un'Goro", "UngoroCrater" },
    { "felwood", "Felwood", "Felwood" }, { "azshara", "Azshara", "Aszhara" }, { "winterspring", "Winterspring", "Winterspring" },
    { "moonglade", "Moonglade", "Moonglade" }, { "silithus", "Silithus", "Silithus" },
    { "stormwind", "Stormwind", "Stormwind" }, { "ironforge", "Ironforge", "Ironforge" }, { "darnassus", "Darnassus", "Darnassis" },
    { "orgrimmar", "Orgrimmar", "Ogrimmar" }, { "thunderbluff", "Thunder Bluff", "ThunderBluff" }, { "undercity", "Undercity", "Undercity" },
}
for _, m in ipairs(MAPS) do
    table.insert(L.BACKGROUNDS, { key = "map_" .. m[1], name = m[2], group = "map", map = "Interface\\WorldMap\\" .. m[3] .. "\\" .. m[3],
        top = { 0.6, 0.5, 0.35 }, bottom = { 0.35, 0.28, 0.18 }, light = { 1, 0.95, 0.85 } })
end

L.BACKGROUND = {}
for _, b in ipairs(L.BACKGROUNDS) do L.BACKGROUND[b.key] = b end

-- Filters: a photo filter over the whole picture, background included.
-- `tint` colours the light and the backdrop, `grey` washes the colour out
-- (0 none, 1 black and white), `wash` is a see-through colour laid on top.
L.FILTERS = {
    { key = "normal", name = "Normal", tint = { 1, 1, 1 } },
    { key = "warm", name = "Warm", tint = { 1.08, 0.96, 0.82 }, wash = { 1, 0.6, 0.2, 0.08 } },
    { key = "cool", name = "Cool", tint = { 0.85, 0.95, 1.1 }, wash = { 0.3, 0.6, 1, 0.08 } },
    { key = "vivid", name = "Vivid", tint = { 1.15, 1.15, 1.15 } },
    { key = "faded", name = "Faded", tint = { 1, 1, 1 }, grey = 0.35, wash = { 1, 1, 1, 0.14 } },
    { key = "sepia", name = "Sepia", tint = { 1.05, 0.88, 0.66 }, grey = 0.8, wash = { 0.6, 0.4, 0.15, 0.12 } },
    { key = "noir", name = "Noir", tint = { 1, 1, 1 }, grey = 1 },
    { key = "night", name = "Night", tint = { 0.55, 0.62, 0.9 }, wash = { 0.05, 0.08, 0.25, 0.25 } },
    -- `grad`: a see-through colour fading from the top to the bottom colour;
    -- `vignette`: dark edges; `ghost`: the people turn see-through.
    { key = "golden", name = "Golden hour", tint = { 1.12, 0.95, 0.72 }, grad = { { 1, 0.7, 0.2, 0.05 }, { 1, 0.45, 0.1, 0.22 } }, vignette = 0.3 },
    { key = "fel", name = "Fel", tint = { 0.75, 1.15, 0.6 }, grad = { { 0.2, 1, 0.1, 0.18 }, { 0, 0.3, 0, 0.35 } }, vignette = 0.4 },
    { key = "arcane", name = "Arcane", tint = { 1, 0.8, 1.15 }, grad = { { 0.7, 0.3, 1, 0.2 }, { 0.2, 0.1, 0.6, 0.28 } } },
    { key = "bloodmoon", name = "Blood Moon", tint = { 1.15, 0.55, 0.5 }, grad = { { 1, 0, 0, 0.1 }, { 0.3, 0, 0, 0.38 } }, vignette = 0.55 },
    { key = "frozen", name = "Frozen", tint = { 0.8, 0.95, 1.2 }, grey = 0.3, wash = { 0.7, 0.9, 1, 0.16 } },
    { key = "holy", name = "Holy", tint = { 1.15, 1.1, 0.9 }, grad = { { 1, 0.95, 0.6, 0.35 }, { 1, 1, 1, 0 } } },
    { key = "shadow", name = "Shadow", tint = { 0.6, 0.5, 0.8 }, grey = 0.4, grad = { { 0.15, 0, 0.3, 0.2 }, { 0, 0, 0, 0.45 } }, vignette = 0.7 },
    { key = "ghost", name = "Ghost", tint = { 0.8, 0.95, 1.1 }, grey = 0.7, wash = { 0.6, 0.85, 1, 0.12 }, ghost = 0.55 },
    { key = "neon", name = "Neon", tint = { 1.2, 1, 1.2 }, grad = { { 1, 0, 0.8, 0.22 }, { 0, 0.9, 1, 0.22 } } },
    { key = "vapor", name = "Vaporwave", tint = { 1.1, 0.9, 1.15 }, grad = { { 1, 0.4, 0.8, 0.25 }, { 0.3, 0.8, 1, 0.25 } } },
    { key = "retro", name = "Retro", tint = { 1.05, 0.9, 0.7 }, grey = 0.5, wash = { 0.9, 0.7, 0.4, 0.12 }, vignette = 0.7 },
    { key = "dream", name = "Dream", tint = { 1.05, 1, 1.1 }, wash = { 1, 0.85, 1, 0.18 }, vignette = 0.25 },
    { key = "vignette", name = "Vignette", tint = { 1, 1, 1 }, vignette = 0.85 },
}
for _, f in ipairs(L.FILTERS) do f.group = f.group or "colour" end

-- Motion: the picture moves (with any filter). `anim` changes colours or
-- light, `sway` moves the camera (UI\Fx.lua).
L.MOTIONS = {
    { key = "none", name = "None" },
    { key = "rainbow", name = "Rainbow", anim = "hue" },
    { key = "disco", name = "Disco", anim = "disco" },
    { key = "strobe", name = "Strobe", anim = "strobe" },
    { key = "glitch", name = "Glitch", anim = "glitch", sway = "glitch" },
    { key = "drunk", name = "Drunk", sway = "drunk" },
    { key = "dizzy", name = "Dizzy", sway = "dizzy" },
    { key = "quake", name = "Earthquake", sway = "shake" },
    { key = "hype", name = "Hype", sway = "hype" },
    { key = "underwater", name = "Underwater", sway = "float", grad = { { 0.1, 0.6, 0.8, 0.2 }, { 0, 0.2, 0.4, 0.35 } } },
    { key = "heartbeat", name = "Heartbeat", anim = "pulse", vignette = 0.5 },
    { key = "spooky", name = "Spooky", anim = "flicker", vignette = 0.8 },
}
L.MOTION = {}
for _, m in ipairs(L.MOTIONS) do L.MOTION[m.key] = m end

-- Overlays: things moving over the picture (drawn by UI\Fx.lua).
-- tex: an Art file or a game texture; motion: fall, rise, twinkle, wander.
local ART = "Interface\\AddOns\\Wowstagram\\Art\\"
local ICO = "Interface\\Icons\\"
local RTI = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
L.OVERLAYS = {
    { key = "none", name = "None" },
    { key = "snow", name = "Snow", tex = ART .. "Snowflake", count = 28, size = { 6, 14 }, motion = "fall", speed = { 0.07, 0.15 }, spin = 0.6, alpha = 0.9 },
    { key = "rain", name = "Rain", tex = ART .. "Drop", count = 40, size = { 12, 20 }, thin = true, motion = "fall", speed = { 0.9, 1.3 }, colors = { { 0.7, 0.8, 1 } }, alpha = 0.55 },
    { key = "hearts", name = "Hearts", tex = ART .. "Heart", count = 16, size = { 10, 20 }, motion = "rise", speed = { 0.06, 0.12 },
      colors = { { 1, 0.25, 0.45 }, { 1, 0.5, 0.7 }, { 0.95, 0.1, 0.2 } }, wobble = true },
    { key = "confetti", name = "Confetti", tex = "Interface\\Buttons\\WHITE8X8", count = 44, size = { 5, 9 }, flat = true, motion = "fall", speed = { 0.12, 0.25 }, spin = 4,
      colors = { { 1, 0.3, 0.3 }, { 1, 0.8, 0.2 }, { 0.3, 0.85, 0.4 }, { 0.3, 0.6, 1 }, { 0.8, 0.4, 1 }, { 1, 0.5, 0.8 } } },
    { key = "sparkles", name = "Sparkles", tex = ART .. "Star", count = 22, size = { 6, 14 }, motion = "twinkle", add = true,
      colors = { { 1, 0.9, 0.5 }, { 1, 1, 1 } } },
    { key = "bubbles", name = "Bubbles", tex = ART .. "BubbleRing", count = 18, size = { 10, 26 }, motion = "rise", speed = { 0.05, 0.1 }, wobble = true,
      colors = { { 0.75, 0.9, 1 } }, alpha = 0.65 },
    { key = "gold", name = "Make it rain", tex = "Interface\\Icons\\INV_Misc_Coin_01", icon = true, count = 18, size = { 14, 22 }, motion = "fall", speed = { 0.2, 0.35 }, spin = 3 },
    { key = "stars", name = "Raid stars", tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", count = 14, size = { 14, 22 }, motion = "fall", speed = { 0.08, 0.16 }, spin = 1 },
    { key = "skulls", name = "Skulls", tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", count = 12, size = { 16, 24 }, motion = "fall", speed = { 0.1, 0.2 }, spin = 1.5 },
    { key = "embers", name = "Embers", tex = ART .. "Glow", count = 30, size = { 4, 9 }, motion = "rise", speed = { 0.1, 0.22 }, add = true, wobble = true,
      colors = { { 1, 0.55, 0.1 }, { 1, 0.3, 0.05 }, { 1, 0.85, 0.3 } } },
    { key = "fireflies", name = "Fireflies", tex = ART .. "Glow", count = 18, size = { 6, 12 }, motion = "wander", add = true,
      colors = { { 0.85, 1, 0.3 }, { 1, 0.95, 0.4 } } },
    { key = "murlocs", name = "Murlocs", tex = "Interface\\Icons\\INV_Misc_Head_Murloc_01", icon = true, count = 10, size = { 18, 26 }, motion = "fall", speed = { 0.1, 0.2 }, spin = 1.5 },
    -- (texs: a different texture for each piece; motion "blow" goes
    -- sideways, "diag" falls at a slant, "burst" is fireworks, "fountain"
    -- shoots up from the bottom, "swim" crosses, "beam" is still light,
    -- "flash" is lightning, "pop" grows and fades; grow, flap: see Fx.)
    { key = "leaves", name = "Autumn", tex = ART .. "Leaf", count = 18, size = { 9, 16 }, motion = "fall", speed = { 0.06, 0.12 }, spin = 1.5, wobble = true,
      colors = { { 0.95, 0.5, 0.1 }, { 0.85, 0.25, 0.05 }, { 0.95, 0.75, 0.2 }, { 0.6, 0.35, 0.1 } } },
    { key = "petals", name = "Blossoms", tex = ART .. "Leaf", count = 24, size = { 5, 9 }, motion = "fall", speed = { 0.05, 0.1 }, spin = 2, wobble = true,
      colors = { { 1, 0.75, 0.85 }, { 1, 0.88, 0.92 }, { 0.98, 0.6, 0.75 } } },
    { key = "butterflies", name = "Butterflies", tex = ART .. "Butterfly", count = 10, size = { 12, 18 }, motion = "wander", flap = true,
      colors = { { 0.4, 0.75, 1 }, { 1, 0.6, 0.2 }, { 1, 0.4, 0.8 }, { 0.6, 1, 0.4 } } },
    { key = "music", name = "Music", tex = ART .. "Note", count = 12, size = { 12, 20 }, motion = "rise", speed = { 0.06, 0.1 }, wobble = true,
      colors = { { 1, 1, 1 }, { 1, 0.85, 0.3 }, { 0.6, 0.9, 1 } } },
    { key = "sleepy", name = "Zzz", tex = ART .. "Zee", count = 8, size = { 10, 18 }, motion = "rise", speed = { 0.04, 0.07 }, wobble = true, grow = 1,
      colors = { { 0.8, 0.9, 1 } } },
    { key = "balloons", name = "Balloons", tex = ART .. "Balloon", count = 10, size = { 18, 28 }, motion = "rise", speed = { 0.05, 0.09 }, wobble = true,
      colors = { { 1, 0.3, 0.3 }, { 0.3, 0.6, 1 }, { 1, 0.85, 0.2 }, { 0.4, 0.9, 0.4 }, { 0.9, 0.4, 1 } } },
    { key = "bats", name = "Bats", tex = ART .. "Bat", count = 10, size = { 14, 22 }, motion = "wander", flap = true, colors = { { 0.15, 0.1, 0.2 } } },
    { key = "ghosts", name = "Ghosts", tex = ART .. "Ghost", count = 8, size = { 16, 26 }, motion = "rise", speed = { 0.04, 0.08 }, wobble = true,
      colors = { { 0.85, 0.95, 1 } }, alpha = 0.6 },
    { key = "lightning", name = "Lightning", tex = ART .. "Bolt", count = 2, size = { 60, 90 }, motion = "flash", colors = { { 0.8, 0.9, 1 } }, add = true },
    { key = "sunbeams", name = "Sunbeams", tex = ART .. "Ray", count = 5, size = { 40, 60 }, motion = "beam", colors = { { 1, 0.9, 0.6 } }, add = true },
    { key = "feathers", name = "Feathers", tex = ART .. "Feather", count = 12, size = { 12, 18 }, motion = "fall", speed = { 0.04, 0.08 }, spin = 1, wobble = true },
    { key = "fireworks", name = "Fireworks", tex = ART .. "Glow", count = 48, size = { 4, 7 }, motion = "burst", add = true,
      colors = { { 1, 0.3, 0.3 }, { 1, 0.85, 0.2 }, { 0.3, 0.7, 1 }, { 0.5, 1, 0.4 }, { 1, 0.4, 1 } } },
    { key = "cannon", name = "Confetti cannon", tex = "Interface\\Buttons\\WHITE8X8", count = 50, size = { 5, 8 }, flat = true, motion = "fountain", spin = 5,
      colors = { { 1, 0.3, 0.3 }, { 1, 0.8, 0.2 }, { 0.3, 0.85, 0.4 }, { 0.3, 0.6, 1 }, { 0.8, 0.4, 1 } } },
    { key = "meteors", name = "Meteors", tex = ART .. "Glow", count = 8, size = { 10, 18 }, motion = "diag", speed = { 0.5, 0.8 }, add = true, trail = true,
      colors = { { 1, 0.5, 0.1 }, { 1, 0.75, 0.3 } } },
    { key = "shooting", name = "Shooting stars", tex = ART .. "Star", count = 6, size = { 8, 14 }, motion = "diag", speed = { 0.7, 1.1 }, add = true, trail = true,
      colors = { { 1, 1, 0.9 } } },
    { key = "blizzard", name = "Blizzard", tex = ART .. "Snowflake", count = 50, size = { 4, 10 }, motion = "blow", speed = { 0.5, 0.9 }, spin = 3, alpha = 0.85 },
    { key = "sandstorm", name = "Sandstorm", tex = ART .. "Glow", count = 60, size = { 3, 6 }, motion = "blow", speed = { 0.6, 1 },
      colors = { { 0.95, 0.8, 0.5 }, { 0.85, 0.65, 0.35 } }, alpha = 0.8 },
    { key = "fog", name = "Fog", tex = ART .. "Glow", count = 10, size = { 120, 200 }, motion = "blow", speed = { 0.02, 0.05 }, colors = { { 0.85, 0.88, 0.92 } }, alpha = 0.35 },
    { key = "smoke", name = "Smoke", tex = ART .. "Glow", count = 14, size = { 30, 50 }, motion = "rise", speed = { 0.05, 0.1 }, wobble = true, grow = 1.5,
      colors = { { 0.55, 0.55, 0.58 } }, alpha = 0.45 },
    { key = "felfire", name = "Fel fire", tex = ART .. "Glow", count = 30, size = { 5, 10 }, motion = "rise", speed = { 0.12, 0.25 }, add = true, wobble = true,
      colors = { { 0.4, 1, 0.2 }, { 0.6, 1, 0.3 }, { 0.2, 0.8, 0.1 } } },
    { key = "frost", name = "Frost", tex = ART .. "Snowflake", count = 18, size = { 8, 16 }, motion = "twinkle", add = true, colors = { { 0.6, 0.85, 1 } } },
    { key = "arcane", name = "Arcane", tex = ART .. "Glow", count = 18, size = { 8, 16 }, motion = "wander", add = true,
      colors = { { 0.7, 0.4, 1 }, { 0.95, 0.5, 1 }, { 0.5, 0.6, 1 } } },
    { key = "holy", name = "Holy light", tex = ART .. "Star", count = 20, size = { 5, 10 }, motion = "rise", speed = { 0.06, 0.12 }, add = true, colors = { { 1, 0.9, 0.5 } } },
    { key = "shadow", name = "Shadow", tex = ART .. "Glow", count = 16, size = { 20, 36 }, motion = "rise", speed = { 0.05, 0.1 }, grow = 1,
      colors = { { 0.15, 0.05, 0.25 } }, alpha = 0.7 },
    { key = "blood", name = "Blood rain", tex = ART .. "Drop", count = 30, size = { 10, 16 }, thin = true, motion = "fall", speed = { 0.8, 1.2 }, colors = { { 0.75, 0.05, 0.05 } } },
    { key = "downpour", name = "Downpour", tex = ART .. "Drop", count = 80, size = { 14, 22 }, thin = true, motion = "fall", speed = { 1.3, 1.8 },
      colors = { { 0.7, 0.8, 1 } }, alpha = 0.45 },
    { key = "raidmarks", name = "Raid markers", texs = { RTI .. "1", RTI .. "2", RTI .. "3", RTI .. "4", RTI .. "5", RTI .. "6", RTI .. "7", RTI .. "8" },
      count = 16, size = { 14, 22 }, motion = "fall", speed = { 0.08, 0.16 }, spin = 1 },
    { key = "lootrain", name = "Loot rain", texs = { ICO .. "INV_Misc_Coin_01", ICO .. "INV_Misc_Bag_10", ICO .. "INV_Misc_Gem_Diamond_01",
      ICO .. "INV_Potion_51", ICO .. "INV_Misc_Rune_01" }, icon = true, count = 18, size = { 14, 22 }, motion = "fall", speed = { 0.15, 0.3 }, spin = 2 },
    { key = "sheep", name = "Sheep rain", tex = ICO .. "Spell_Nature_Polymorph", icon = true, count = 12, size = { 16, 24 }, motion = "fall", speed = { 0.1, 0.2 }, spin = 1.5 },
    { key = "fish", name = "Fish", tex = ICO .. "INV_Misc_Fish_02", icon = true, count = 8, size = { 16, 24 }, motion = "swim", speed = { 0.08, 0.15 } },
    { key = "bling", name = "Bling", tex = ART .. "Star", count = 14, size = { 10, 22 }, motion = "pop", add = true, colors = { { 1, 0.9, 0.4 }, { 1, 1, 1 } } },
    { key = "love", name = "Love", tex = ART .. "Heart", count = 14, size = { 10, 22 }, motion = "pop", colors = { { 1, 0.25, 0.45 }, { 1, 0.55, 0.75 } } },
    { key = "disco", name = "Disco lights", tex = ART .. "Glow", count = 8, size = { 60, 100 }, motion = "wander", add = true,
      colors = { { 1, 0.2, 0.6 }, { 0.2, 0.6, 1 }, { 0.3, 1, 0.4 }, { 1, 0.9, 0.2 } }, alpha = 0.6 },
    { key = "questions", name = "Questions", texs = { "Interface\\GossipFrame\\ActiveQuestIcon", "Interface\\GossipFrame\\AvailableQuestIcon" },
      count = 10, size = { 14, 22 }, motion = "pop" },
}
L.OVERLAY = {}
for _, o in ipairs(L.OVERLAYS) do L.OVERLAY[o.key] = o end

-- Stickers: textures that are in every client (vanilla-era files) or our
-- own art. x, y: the middle, in % of the picture; s: width in %; r: turn.
local function Icon(name) return "Interface\\Icons\\" .. name end
local RT = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
L.STICKERS = {
    { key = "heart", name = "Heart", tex = ART .. "Heart", color = { 1, 0.25, 0.4 } },
    { key = "star", name = "Star", tex = ART .. "Star", color = { 1, 0.85, 0.2 } },
    { key = "sparkle", name = "Sparkle", tex = ART .. "ToolSparkle", color = { 1, 0.95, 0.6 } },
    { key = "snowflake", name = "Snowflake", tex = ART .. "Snowflake", color = { 0.8, 0.95, 1 } },
    { key = "speech", name = "Speech", tex = ART .. "Bubble" },
    { key = "quest", name = "Quest", tex = "Interface\\GossipFrame\\AvailableQuestIcon" },
    { key = "turnin", name = "Turn in", tex = "Interface\\GossipFrame\\ActiveQuestIcon" },
    { key = "alliance", name = "Alliance", tex = "Interface\\TargetingFrame\\UI-PVP-Alliance", coords = { 0, 0.62, 0, 0.62 } },
    { key = "horde", name = "Horde", tex = "Interface\\TargetingFrame\\UI-PVP-Horde", coords = { 0, 0.62, 0, 0.62 } },
    { key = "rtstar", name = "Raid star", tex = RT .. "1" }, { key = "rtcircle", name = "Circle", tex = RT .. "2" },
    { key = "rtdiamond", name = "Diamond", tex = RT .. "3" }, { key = "rttriangle", name = "Triangle", tex = RT .. "4" },
    { key = "rtmoon", name = "Moon", tex = RT .. "5" }, { key = "rtsquare", name = "Square", tex = RT .. "6" },
    { key = "rtcross", name = "Cross", tex = RT .. "7" }, { key = "rtskull", name = "Skull", tex = RT .. "8" },
    { key = "gold", name = "Gold", tex = Icon("INV_Misc_Coin_01"), icon = true },
    { key = "murloc", name = "Murloc", tex = Icon("INV_Misc_Head_Murloc_01"), icon = true },
    { key = "hearth", name = "Hearthstone", tex = Icon("INV_Misc_Rune_01"), icon = true },
    { key = "question", name = "Question", tex = Icon("INV_Misc_QuestionMark"), icon = true },
    { key = "fire", name = "Fire", tex = Icon("Spell_Fire_Fire"), icon = true },
    { key = "bomb", name = "Bomb", tex = Icon("INV_Misc_Bomb_04"), icon = true },
    { key = "crown", name = "Crown", tex = Icon("INV_Crown_01"), icon = true },
    { key = "onyxia", name = "Onyxia", tex = Icon("INV_Misc_Head_Dragon_01"), icon = true },
    { key = "skull", name = "Skull", tex = Icon("INV_Misc_Bone_HumanSkull_01"), icon = true },
    { key = "diamond", name = "Diamond", tex = Icon("INV_Misc_Gem_Diamond_01"), icon = true },
    { key = "potion", name = "Potion", tex = Icon("INV_Potion_51"), icon = true },
    { key = "fish", name = "Fish", tex = Icon("INV_Misc_Fish_02"), icon = true },
    { key = "beer", name = "Drink", tex = Icon("INV_Drink_04"), icon = true },
    { key = "gnoll", name = "Gnoll", tex = Icon("INV_Misc_Head_Gnoll_01"), icon = true },
    { key = "heal", name = "Heal", tex = Icon("Spell_Holy_Heal"), icon = true },
    { key = "shout", name = "Battle Shout", tex = Icon("Ability_Warrior_BattleShout"), icon = true },
    { key = "loot", name = "Loot", tex = Icon("INV_Misc_Bag_10"), icon = true },
}
L.STICKER = {}
for _, s in ipairs(L.STICKERS) do L.STICKER[s.key] = s end
L.MAX_STICKERS = 8

-- Text: one line, in a style. `y`: its middle, in % from the top.
L.TEXT_STYLES = {
    { key = "bar", name = "Snap bar" },
    { key = "big", name = "Big" },
    { key = "comic", name = "Comic" },
    { key = "neon", name = "Neon" },
    { key = "fancy", name = "Fancy" },
    { key = "raid", name = "Raid warning" },
    { key = "achievement", name = "Achievement" },
    { key = "loot", name = "Epic loot" },
    { key = "levelup", name = "Level up" },
}
L.TEXT_STYLE = {}
for _, t in ipairs(L.TEXT_STYLES) do L.TEXT_STYLE[t.key] = t end
L.MAX_TEXT = 60

-- Text from anyone: no "|" (WoW's colour and texture codes), no ";" (it
-- would break the picture string), no line breaks; at most L.MAX_TEXT.
function L.CleanText(text)
    text = tostring(text or ""):gsub("[|;\r\n\t]", "")
    if #text > L.MAX_TEXT then
        text = text:sub(1, L.MAX_TEXT)
        -- (don't cut a letter in half)
        while #text > 0 and text:byte(#text) >= 128 and text:byte(#text) < 192 do text = text:sub(1, -2) end
        if #text > 0 and text:byte(#text) >= 192 then text = text:sub(1, -2) end
    end
    return text
end

-- Frames around the picture (drawn by UI\Decor.lua).
L.DECOS = {
    { key = "none", name = "None" },
    { key = "polaroid", name = "Polaroid" },
    { key = "gold", name = "Gold" },
    { key = "wanted", name = "Wanted" },
    { key = "film", name = "Film" },
    { key = "neon", name = "Neon" },
    { key = "hearts", name = "Hearts" },
    { key = "comic", name = "Comic" },
    { key = "news", name = "Breaking news" },
    { key = "magazine", name = "Magazine" },
    { key = "boss", name = "Boss fight" },
}
L.DECO = {}
for _, d in ipairs(L.DECOS) do L.DECO[d.key] = d end

-- Lenses (each person): bigger, smaller, upside down, spinning... or
-- turned into a creature (model ids that are in every client: checked in
-- the classic-era and Retail tables).
L.LENSES = {
    { key = "none", name = "None" },
    { key = "tiny", name = "Tiny", scale = 0.55, icon = Icon("Spell_Frost_FrostShock") },
    { key = "giant", name = "Giant", scale = 1.45, icon = Icon("Spell_Nature_Strength") },
    { key = "upside", name = "Upside down", roll = math.pi, upside = true, icon = Icon("Ability_Druid_Cyclone") },
    { key = "lean", name = "Lean", roll = 0.35, icon = Icon("Ability_Rogue_Sprint") },
    { key = "spin", name = "Spin", anim = "spin", icon = Icon("Spell_Nature_Tranquility") },
    { key = "float", name = "Float", anim = "float", icon = Icon("Spell_Holy_SealOfSacrifice") },
    { key = "sheep", name = "Sheep", display = 856, icon = Icon("Spell_Nature_Polymorph") },
    { key = "chicken", name = "Chicken", display = 304, icon = Icon("Spell_Magic_PolymorphChicken") },
    { key = "frog", name = "Frog", display = 6297, icon = Icon("Spell_Frost_FrostNova") },
    { key = "rabbit", name = "Rabbit", display = 328, icon = Icon("Spell_Nature_SpiritWolf") },
    { key = "squirrel", name = "Squirrel", display = 134, icon = Icon("INV_Misc_Pelt_Bear_03") },
    { key = "turtle", name = "Turtle", display = 16259, icon = Icon("Ability_Hunter_Pet_Turtle") },
    { key = "cat", name = "Cat", display = 5585, icon = Icon("Ability_Hunter_Pet_Cat") },
    { key = "murloc", name = "Murloc", display = 15393, icon = Icon("INV_Misc_Head_Murloc_01") },
    { key = "gnoll", name = "Gnoll", display = 501, icon = Icon("INV_Misc_Head_Gnoll_01") },
    { key = "kobold", name = "Kobold", display = 26, icon = Icon("INV_Misc_Head_Kobold_01") },
    { key = "skeleton", name = "Skeleton", display = 158, icon = Icon("Spell_Shadow_RaiseDead") },
    { key = "ghoul", name = "Ghoul", display = 519, icon = Icon("Spell_Shadow_AntiShadow") },
    { key = "wisp", name = "Wisp", display = 1824, icon = Icon("Spell_Nature_WispSplode") },
    { key = "snowman", name = "Snowman", display = 13610, icon = Icon("Spell_Frost_SummonWaterElemental") },
    { key = "moonkin", name = "Moonkin", display = 15374, icon = Icon("Spell_Nature_ForceOfNature") },
    { key = "infernal", name = "Infernal", display = 7029, icon = Icon("Spell_Shadow_SummonInfernal") },
    { key = "ragnaros", name = "Ragnaros", display = 11121, icon = Icon("Spell_Fire_Elemental_Totem") },
}
L.LENS = {}
for _, l in ipairs(L.LENSES) do L.LENS[l.key] = l end

-- Face filters (each person): things drawn on the head, wherever it is in
-- the picture (UI\Decor.lua works out where). A part: texture, middle
-- (x right, y down) and size (w, h) in head heights from the head's middle;
-- c colour, add (glow), rot (turn), flip (mirrored), anim (bob, orbit,
-- rise, drip), i (its place in the animation).
local PINK, BROWN, GOLD = { 1, 0.6, 0.7 }, { 0.35, 0.24, 0.16 }, { 1, 0.82, 0.25 }
local function F(name) return ART .. name end
L.FACES = {
    { key = "none", name = "None" },
    { key = "cat", name = "Cat", parts = {
        { F("FaceCatEar"), -0.3, -0.55, 0.36, 0.36, c = BROWN }, { F("FaceCatEar"), 0.3, -0.55, 0.36, 0.36, c = BROWN },
        { F("FaceCatEar"), -0.3, -0.5, 0.2, 0.2, c = PINK }, { F("FaceCatEar"), 0.3, -0.5, 0.2, 0.2, c = PINK },
        { F("Circle"), 0, 0.17, 0.09, 0.07, c = PINK } } },
    { key = "bunny", name = "Bunny", parts = {
        { F("FaceBunnyEar"), -0.17, -0.95, 0.2, 0.6, c = { 0.97, 0.95, 0.93 } }, { F("FaceBunnyEar"), 0.17, -0.95, 0.2, 0.6, c = { 0.97, 0.95, 0.93 } },
        { F("FaceBunnyEar"), -0.17, -0.93, 0.1, 0.45, c = PINK }, { F("FaceBunnyEar"), 0.17, -0.93, 0.1, 0.45, c = PINK },
        { F("Circle"), 0, 0.16, 0.08, 0.06, c = PINK } } },
    { key = "dog", name = "Dog", parts = {
        { F("FaceDogEar"), -0.42, -0.12, 0.26, 0.42, c = BROWN, rot = 0.35 }, { F("FaceDogEar"), 0.42, -0.12, 0.26, 0.42, c = BROWN, rot = -0.35 },
        { F("Circle"), 0, 0.16, 0.14, 0.11, c = { 0.08, 0.06, 0.06 } }, { F("FaceDogEar"), 0, 0.36, 0.12, 0.16, c = { 1, 0.45, 0.55 } } } },
    { key = "blush", name = "Blush", parts = {
        { F("Glow"), -0.22, 0.17, 0.3, 0.22, c = { 1, 0.35, 0.5 }, alpha = 0.75 },
        { F("Glow"), 0.22, 0.17, 0.3, 0.22, c = { 1, 0.35, 0.5 }, alpha = 0.75 } } },
    { key = "freckles", name = "Freckles", parts = {
        { F("Circle"), -0.24, 0.12, 0.03, 0.03, c = BROWN }, { F("Circle"), -0.18, 0.17, 0.03, 0.03, c = BROWN },
        { F("Circle"), -0.27, 0.19, 0.025, 0.025, c = BROWN }, { F("Circle"), -0.2, 0.1, 0.025, 0.025, c = BROWN },
        { F("Circle"), 0.24, 0.12, 0.03, 0.03, c = BROWN }, { F("Circle"), 0.18, 0.17, 0.03, 0.03, c = BROWN },
        { F("Circle"), 0.27, 0.19, 0.025, 0.025, c = BROWN }, { F("Circle"), 0.2, 0.1, 0.025, 0.025, c = BROWN } } },
    { key = "hearteyes", name = "Heart eyes", parts = {
        { F("Heart"), -0.15, 0, 0.2, 0.2, c = { 1, 0.15, 0.3 } }, { F("Heart"), 0.15, 0, 0.2, 0.2, c = { 1, 0.15, 0.3 } } } },
    { key = "shades", name = "Shades", parts = { { F("FaceShades"), 0, 0, 0.62, 0.2, c = { 0.05, 0.05, 0.06 } } } },
    { key = "nerd", name = "Glasses", parts = { { F("FaceGlasses"), 0, 0, 0.62, 0.23, c = { 0.1, 0.1, 0.1 } } } },
    { key = "clown", name = "Clown nose", parts = { { F("Circle"), 0, 0.15, 0.17, 0.17, c = { 0.95, 0.1, 0.1 } } } },
    { key = "mustache", name = "Mustache", parts = { { F("FaceMustache"), 0, 0.27, 0.5, 0.19, c = { 0.2, 0.12, 0.06 } } } },
    { key = "crown", name = "Crown", parts = { { F("FaceCrown"), 0, -0.62, 0.55, 0.34, c = GOLD } } },
    { key = "halo", name = "Halo", parts = { { F("FaceHalo"), 0, -0.78, 0.62, 0.16, c = GOLD, add = true, anim = "bob" } } },
    { key = "horns", name = "Devil horns", parts = {
        { F("FaceHorn"), -0.25, -0.58, 0.16, 0.32, c = { 0.85, 0.08, 0.08 }, rot = 0.25 },
        { F("FaceHorn"), 0.25, -0.58, 0.16, 0.32, c = { 0.85, 0.08, 0.08 }, rot = -0.25, flip = true } } },
    { key = "flowers", name = "Flower crown", parts = {
        { F("FaceFlower"), -0.36, -0.42, 0.16, 0.16, c = { 1, 0.5, 0.7 } }, { F("FaceFlower"), -0.18, -0.52, 0.17, 0.17, c = { 1, 0.85, 0.3 } },
        { F("FaceFlower"), 0, -0.56, 0.18, 0.18, c = { 0.7, 0.55, 1 } }, { F("FaceFlower"), 0.18, -0.52, 0.17, 0.17, c = { 1, 1, 1 } },
        { F("FaceFlower"), 0.36, -0.42, 0.16, 0.16, c = { 1, 0.5, 0.7 } } } },
    { key = "party", name = "Party hat", parts = {
        { F("FacePartyHat"), 0.08, -0.82, 0.36, 0.5, c = { 0.95, 0.3, 0.8 }, rot = -0.2 },
        { F("Circle"), 0.15, -1.06, 0.1, 0.1, c = { 1, 0.9, 0.2 } } } },
    { key = "tears", name = "Tears", parts = {
        { F("Drop"), -0.14, 0.12, 0.03, 0.12, c = { 0.5, 0.75, 1 }, anim = "drip", i = 0 },
        { F("Drop"), 0.14, 0.12, 0.03, 0.12, c = { 0.5, 0.75, 1 }, anim = "drip", i = 1 } } },
    { key = "dizzy", name = "Dizzy", parts = {
        { F("Star"), 0, -0.62, 0.14, 0.14, c = GOLD, add = true, anim = "orbit", i = 0 },
        { F("Star"), 0, -0.62, 0.14, 0.14, c = GOLD, add = true, anim = "orbit", i = 1 },
        { F("Star"), 0, -0.62, 0.14, 0.14, c = GOLD, add = true, anim = "orbit", i = 2 } } },
    { key = "sleepy", name = "Sleepy", parts = {
        { F("Zee"), 0.35, -0.5, 0.14, 0.14, anim = "rise", i = 0 }, { F("Zee"), 0.35, -0.5, 0.14, 0.14, anim = "rise", i = 1 },
        { F("Zee"), 0.35, -0.5, 0.14, 0.14, anim = "rise", i = 2 } } },
    { key = "quest", name = "Quest giver", parts = { { "Interface\\GossipFrame\\AvailableQuestIcon", 0, -1.15, 0.38, 0.38, anim = "bob" } } },
    { key = "turnin", name = "Quest done", parts = { { "Interface\\GossipFrame\\ActiveQuestIcon", 0, -1.15, 0.38, 0.38, anim = "bob" } } },
    { key = "skull", name = "Raid skull", parts = { { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", 0, -1.1, 0.36, 0.36 } } },
    { key = "nameplate", name = "Nameplate", nameplate = true },
}
L.FACE = {}
for _, f in ipairs(L.FACES) do L.FACE[f.key] = f end
L.FILTER = {}
for _, f in ipairs(L.FILTERS) do L.FILTER[f.key] = f end

---------------------------------------------------------------------------
-- Base 36
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function L.B36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = ""
    while n > 0 do
        local d = n % 36
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end

local function N36(s)
    return s and s ~= "" and tonumber(s, 36) or 0
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------
L.MAX_PEOPLE = 4 -- you and three more

function L.New()
    return { pose = "stand", yaw = 0, zoom = 100, frame = "full", bg = "normal", filter = "normal", overlay = "none",
        deco = "none", motion = "none", stickers = {}, slots = {},
        people = {} }
end

-- One more person: who they are (a unit's id, race, sex, class).
function L.NewPerson(name, race, sex, class)
    return { name = name, race = race, sex = sex, class = class, pose = "stand", yaw = 0, mx = 0, my = 0, slots = {} }
end

local function CopySlots(slots)
    local c = {}
    for id, s in pairs(slots or {}) do c[id] = { a = s.a, s = s.s, i = s.i, item = s.item } end
    return c
end

function L.Copy(look)
    local c = {}
    for k, v in pairs(look or {}) do c[k] = v end
    c.slots = CopySlots(look and look.slots)
    c.stickers = {}
    for i, s in ipairs(look and look.stickers or {}) do c.stickers[i] = { key = s.key, x = s.x, y = s.y, s = s.s, r = s.r } end
    if look and look.text then c.text = { text = look.text.text, style = look.text.style, y = look.text.y } end
    c.people = {}
    for i, p in ipairs(look and look.people or {}) do
        local q = {}
        for k, v in pairs(p) do q[k] = v end
        q.slots = CopySlots(p.slots)
        c.people[i] = q
    end
    return c
end

function L.SlotCount(look)
    local n = 0
    for _ in pairs(look and look.slots or {}) do n = n + 1 end
    return n
end

-- Who is in the picture: race, sex and class of the player.
function L.Me(look)
    local _, _, raceId = UnitRace("player")
    local _, class = UnitClass("player")
    look.race, look.sex, look.class = raceId, UnitSex and UnitSex("player"), class
    return look
end

---------------------------------------------------------------------------
-- String
---------------------------------------------------------------------------
local function SlotString(s)
    if s.item then return "i" .. L.B36(s.item) end
    local out = "a" .. L.B36(s.a)
    if (s.s or 0) > 0 or (s.i or 0) > 0 then out = out .. "." .. L.B36(s.s) end
    if (s.i or 0) > 0 then out = out .. "." .. L.B36(s.i) end
    return out
end

-- A person's own fields (the main person's and each extra one's).
local function PersonTokens(p, out)
    local function Add(prefix, v) if v ~= nil and v ~= "" then table.insert(out, prefix .. tostring(v)) end end
    Add("r", p.race)
    Add("g", p.sex)
    Add("c", p.class)
    Add("p", p.pose ~= "stand" and p.pose or nil)
    Add("l", p.lens ~= nil and p.lens ~= "none" and p.lens or nil)
    Add("h", p.face ~= nil and p.face ~= "none" and p.face or nil)
    Add("y", (p.yaw or 0) ~= 0 and math.floor(p.yaw + 0.5) or nil)
    if p.drawn then table.insert(out, "w") end
    if p.still then table.insert(out, "e") end
    local mx, my = math.floor((p.mx or 0) * 100 + 0.5), math.floor((p.my or 0) * 100 + 0.5)
    if mx ~= 0 or my ~= 0 then table.insert(out, "m" .. mx .. "," .. my) end
    local slots = {}
    for _, def in ipairs(L.SLOTS) do
        local s = p.slots and p.slots[def.id]
        if s then table.insert(slots, def.id .. "=" .. SlotString(s)) end
    end
    if #slots > 0 then table.insert(out, "s" .. table.concat(slots, ",")) end
end

function L.Encode(look)
    local out = { "1" }
    local function Add(prefix, v) if v ~= nil and v ~= "" then table.insert(out, prefix .. tostring(v)) end end
    Add("z", (look.zoom or 100) ~= 100 and math.floor(look.zoom + 0.5) or nil)
    Add("f", look.frame ~= "full" and look.frame or nil)
    Add("b", look.bg ~= "normal" and look.bg or nil)
    Add("x", look.filter ~= "normal" and look.filter or nil)
    Add("o", look.overlay ~= "none" and look.overlay or nil)
    Add("v", look.motion ~= nil and look.motion ~= "none" and look.motion or nil)
    if look.bg == "custom" then Add("u", (look.bgTop or "ff8033") .. (look.bgBottom or "331a66")) end
    Add("d", look.deco ~= nil and look.deco ~= "none" and look.deco or nil)
    local st = {}
    for i, s in ipairs(look.stickers or {}) do
        if i > L.MAX_STICKERS then break end
        st[#st + 1] = table.concat({ s.key, math.floor(s.x + 0.5), math.floor(s.y + 0.5), math.floor(s.s + 0.5),
            math.floor((s.r or 0) + 0.5) }, ":")
    end
    if #st > 0 then Add("k", table.concat(st, ",")) end
    if look.text and look.text.text and look.text.text ~= "" then
        Add("t", (look.text.style or "bar") .. ":" .. math.floor((look.text.y or 70) + 0.5) .. ":" .. L.CleanText(look.text.text))
    end
    PersonTokens(look, out)
    for i, p in ipairs(look.people or {}) do
        if i >= L.MAX_PEOPLE then break end
        local t = {}
        if p.name then t[1] = "n" .. p.name end
        PersonTokens(p, t)
        table.insert(out, "q" .. table.concat(t, "/"))
    end
    return table.concat(out, ";")
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Anything odd in a string from someone else is dropped, not trusted.
-- One of a person's fields. True when it was one.
local function PersonField(p, k, v)
    if k == "r" then p.race = tonumber(v)
    elseif k == "g" then p.sex = tonumber(v)
    elseif k == "c" then if v:match("^%u+$") then p.class = v end
    elseif k == "p" then if L.POSE[v] then p.pose = v end
    elseif k == "l" then if L.LENS[v] then p.lens = v end
    elseif k == "h" then if L.FACE[v] then p.face = v end
    elseif k == "y" then if tonumber(v) then p.yaw = Clamp(tonumber(v), -180, 180) end
    elseif k == "w" then p.drawn = true
    elseif k == "e" then p.still = true
    elseif k == "m" then
        local x, y = v:match("^(%-?%d+),(%-?%d+)$")
        if x then
            p.mx = Clamp(tonumber(x), -50, 50) / 100
            p.my = Clamp(tonumber(y), -50, 50) / 100
        end
    elseif k == "s" then
        for slot, val in v:gmatch("(%d+)=([%w%.]+)") do
            slot = tonumber(slot)
            if L.SLOT[slot] then
                if val:sub(1, 1) == "i" then
                    local item = N36(val:sub(2))
                    if item > 0 then p.slots[slot] = { item = item } end
                elseif val:sub(1, 1) == "a" then
                    local a, s, i = val:sub(2):match("^(%w+)%.?(%w*)%.?(%w*)$")
                    if a and N36(a) > 0 then p.slots[slot] = { a = N36(a), s = N36(s), i = N36(i) } end
                end
            end
        end
    else
        return false
    end
    return true
end

-- Anything odd in a string from someone else is dropped, not trusted.
L.MAX_STRING = 1600
function L.Decode(str)
    local look = L.New()
    if type(str) ~= "string" or #str > L.MAX_STRING then return look end
    local first = true
    for token in str:gmatch("[^;]+") do
        if first then
            first = false -- the version; 1 is the only one so far
        else
            local k, v = token:sub(1, 1), token:sub(2)
            if k == "z" then if tonumber(v) then look.zoom = Clamp(tonumber(v), 50, 200) end
            elseif k == "f" then if L.FRAME[v] then look.frame = v end
            elseif k == "b" then if L.BACKGROUND[v] then look.bg = v end
            elseif k == "o" then if L.OVERLAY[v] then look.overlay = v end
            elseif k == "v" then if L.MOTION[v] then look.motion = v end
            elseif k == "d" then if L.DECO[v] then look.deco = v end
            elseif k == "k" then
                for entry in v:gmatch("[^,]+") do
                    local key, x, y, sz, r = entry:match("^(%w+):(%-?%d+):(%-?%d+):(%d+):(%-?%d+)$")
                    if key and L.STICKER[key] and #look.stickers < L.MAX_STICKERS then
                        table.insert(look.stickers, { key = key, x = Clamp(tonumber(x), 0, 100), y = Clamp(tonumber(y), 0, 100),
                            s = Clamp(tonumber(sz), 5, 80), r = Clamp(tonumber(r), -180, 180) })
                    end
                end
            elseif k == "t" then
                local style, y, text = v:match("^(%w+):(%d+):(.*)$")
                text = text and L.CleanText(text) or ""
                if style and L.TEXT_STYLE[style] and text ~= "" then
                    look.text = { style = style, y = Clamp(tonumber(y), 5, 95), text = text }
                end
            elseif k == "u" then
                local top, bottom = v:match("^(%x%x%x%x%x%x)(%x%x%x%x%x%x)$")
                if top then look.bgTop, look.bgBottom = top:lower(), bottom:lower() end
            elseif k == "x" then
                if L.FILTER[v] then look.filter = v
                elseif L.MOTION[v] then look.motion = v -- (motions were filters at first)
                elseif L.BACKGROUND[v] then look.bg = v end -- (v0.1 had backgrounds as filters)
            elseif k == "q" then
                if #look.people < L.MAX_PEOPLE - 1 then
                    local p = L.NewPerson()
                    for t in v:gmatch("[^/]+") do
                        local pk, pv = t:sub(1, 1), t:sub(2)
                        if pk == "n" then
                            if ns.ValidName(pv) then p.name = pv end
                        else
                            PersonField(p, pk, pv)
                        end
                    end
                    table.insert(look.people, p)
                end
            else
                PersonField(look, k, v)
            end
        end
    end
    return look
end
