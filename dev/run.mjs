// Runs Wowstagram outside WoW: one Lua VM per simulated player, with addon
// messages passed between them over the hidden realm channel like the server
// would. Names are two words, as on WoW Forever.
//   node dev/run.mjs
import { LuaFactory } from 'file:///E:/Projekter/WebAddonDemo/node_modules/wasmoon/dist/index.js';
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const addon = join(here, '..');
const toc = readFileSync(join(addon, 'Wowstagram.toc'), 'utf8')
  .split(/\r?\n/).filter(l => l.trim() && !l.startsWith('##'));
const factory = new LuaFactory();

let failures = 0, passes = 0;
const players = [];

// realm: the player's realm (default "Realm"). raw: how WoW names this
// player to others in CHAT_MSG_ADDON: "full" (Name-Realm, as on Retail) or
// "name" (just the name; maybe on WoW Forever's single realm).
// game: 'forever' (no realms: ids are names) or 'retail' (Name-Realm ids).
// guild: the guild's name (players in the same one hear each other on GUILD).
async function Player(name, { demo = false, realm = 'Forever', raw = 'name', game = 'forever', guild = null } = {}) {
  const lua = await factory.createEngine();
  lua.global.set('PLAYER_NAME', name);
  lua.global.set('REALM_NAME', realm);
  lua.global.set('BUILD_TOC', game === 'forever' ? 16001 : 120100);
  await lua.doString(readFileSync(join(here, 'mock.lua'), 'utf8'));
  // Everyone shares one clock (a newcomer's posts aren't "from the future").
  if (players.length) {
    await players[0].run('__ret = CLOCK');
    lua.global.set('__clock', players[0].lua.global.get('__ret'));
    await lua.doString('CLOCK = __clock');
  }
  await lua.doString('ns = {}');
  // Every new global the addon's own files create (Ketho's checker flags
  // stray ones): listed at the end.
  await lua.doString(`
    __ADDON_GLOBALS = {}
    setmetatable(_G, { __newindex = function(t, k, v)
      local info = debug.getinfo(2, "S")
      local src = info and info.source or ""
      if src:match("^@Core") or src:match("^@UI") then __ADDON_GLOBALS[k] = src end
      rawset(t, k, v)
    end })
  `);
  for (const file of toc) {
    lua.global.set('__SRC', readFileSync(join(addon, file.replace(/\\/g, '/')), 'utf8'));
    lua.global.set('__NAME', file);
    await lua.doString(`local fn, err = load(__SRC, "@" .. __NAME) if not fn then error(err) end fn("Wowstagram", ns)`);
  }
  lua.global.set('__check', (ok, label) => {
    if (ok) passes++; else { failures++; console.log(`  FAIL [${name}] ${label}`); }
  });
  await lua.doString(`
    function check(ok, label) __check(ok and true or false, label) end
    function TakeOutbox()
      local out = {}
      for _, e in ipairs(OUTBOX) do
        local parts = {}
        for i = 1, #e do parts[i] = tostring(e[i]) end
        table.insert(out, table.concat(parts, "\\2"))
      end
      OUTBOX = {}
      return table.concat(out, "\\1")
    end
    WowstagramDB = { v1 = true, demo = ${demo} }
    Fire("ADDON_LOADED", "Wowstagram")
    Fire("PLAYER_ENTERING_WORLD", true, false)
  `);
  const sender = raw === 'full' ? `${name}-${realm.replace(/[\s-]/g, '')}` : name;
  if (guild) await lua.doString('IN_GUILD = true');
  const p = { name, sender, guild, lua, run: (code) => lua.doString(code) };
  players.push(p);
  return p;
}

// Move the clock on everyone and deliver what they sent, until quiet.
async function Tick(seconds = 0.5, rounds = 1) {
  for (let r = 0; r < rounds; r++) {
    for (const p of players) await p.run(`Advance(${seconds})`);
    let any = true;
    while (any) {
      any = false;
      for (const from of players) {
        await from.run('__ret = TakeOutbox()');
        const out = from.lua.global.get('__ret');
        if (!out) continue;
        for (const line of out.split('\x01')) {
          const [kind, prefix, msg, chatType, target] = line.split('\x02');
          if (kind !== 'addon') continue;
          any = true;
          for (const to of players) {
            if (to === from) continue;
            if (chatType === 'WHISPER' && target !== to.sender) continue;
            if (chatType === 'GUILD' && (!from.guild || from.guild !== to.guild)) continue;
            if (chatType === 'CHANNEL') {
              await to.run(`__ret = CHANNELS[${JSON.stringify(target)}] ~= nil`);
              if (!to.lua.global.get('__ret')) continue;
            }
            to.lua.global.set('__msg', msg);
            to.lua.global.set('__from', from.sender);
            to.lua.global.set('__prefix', prefix);
            await to.run(`Fire("CHAT_MSG_ADDON", __prefix, __msg, ${JSON.stringify(chatType)}, __from)`);
          }
        }
      }
    }
  }
}

function section(title) { console.log(title); }

// ---------------------------------------------------------------------------
section('TOCs');
{
  const base = readFileSync(join(addon, 'Wowstagram.toc'), 'utf8');
  const forever = readFileSync(join(addon, 'Wowstagram_Forever.toc'), 'utf8');
  if (base === forever) passes++; else { failures++; console.log('  FAIL Wowstagram_Forever.toc differs from Wowstagram.toc'); }
  if (/^## Interface: 16001, 120100$/m.test(base)) passes++; else { failures++; console.log('  FAIL Interface line'); }
  let mainline = true;
  try { readFileSync(join(addon, 'Wowstagram_Mainline.toc')); } catch { mainline = false; }
  if (!mainline) passes++; else { failures++; console.log('  FAIL no _Mainline.toc allowed (Forever marks the addon Incompatible)'); }
}

section('Look strings');
const A = await Player('Flintar Stone');
await A.run(`
  local L = ns.Look
  local look = L.New()
  look.race, look.sex, look.class, look.pose, look.yaw, look.zoom = 4, 3, "DRUID", "dance", -35, 130
  look.frame, look.bg, look.filter, look.drawn = "waist", "elwynn", "noir", true
  look.slots[1] = { a = 123456, s = 0, i = 0 }
  look.slots[16] = { a = 99, s = 7, i = 5 }
  look.slots[5] = { item = 16966 }
  local s = L.Encode(look)
  check(#s < 120, "short string: " .. s)
  local back = L.Decode(s)
  check(back.race == 4 and back.sex == 3 and back.class == "DRUID", "who survives")
  check(back.pose == "dance" and back.yaw == -35 and back.zoom == 130, "pose, yaw, zoom survive")
  check(back.frame == "waist" and back.bg == "elwynn" and back.filter == "noir" and back.drawn, "frame, background, filter, weapons survive")
  check(back.slots[1].a == 123456 and back.slots[16].s == 7 and back.slots[16].i == 5, "appearances survive")
  check(back.slots[5].item == 16966, "item ids survive")
  check(L.Encode(back) == s, "round trip is stable")
  local junk = L.Decode("1;pnope;y9999;z1;s1=a0,99=a5,3=iz;xbad;cmage")
  check(junk.pose == "stand" and junk.yaw == 180 and junk.zoom == 50, "bad values are clamped or dropped")
  check(junk.slots[1] == nil and junk.slots[99] == nil and junk.slots[3].item == 35, "bad slots dropped")
  check(junk.filter == "normal" and junk.class == nil, "unknown filter and lower-case class dropped")
  check(L.Decode(nil).pose == "stand" and L.Decode(string.rep("x", 900)).pose == "stand", "garbage is a blank look")
`);

section('Window and pages');
await A.run(`
  ns.UI:Toggle()
  check(ns.UI.frame:IsShown(), "window opens")
  for _, key in ipairs({ "feed", "studio", "profile", "settings" }) do
    ns.UI:Show(key)
    check(ns.UI.tab == key and ns.UI.pages[key].frame:IsShown(), "tab " .. key .. " shows")
  end
`);

section('Fullscreen');
await A.run(`
  ns.UI:ToggleFull()
  check(ns.db.fullscreen and ns.UI.full and ns.UI.backdrop:IsShown(), "fullscreen on: backdrop behind")
  check(math.abs(ns.UI.frame:GetScale() - 1080 / 700 * 0.97) < 0.001, "window scaled up to fill the screen: " .. ns.UI.frame:GetScale())
  ns.UI:ToggleFull()
  check(not ns.UI.full and not ns.UI.backdrop:IsShown() and ns.UI.frame:GetScale() == 1, "and back")
  local fb = ns.UI.fullButton
  check(fb.glyph._tex:find("WindowMax$"), "button shows one window (fullscreen)")
  fb:GetScript("OnClick")(fb)
  check(ns.UI.full and fb.glyph._tex:find("WindowRestore$"), "fullscreen: two windows (back to the window)")
  fb:GetScript("OnClick")(fb)
  local x = ns.UI.closeButton
  check(x.glyph._tex:find("Close$") and x.base._tex:find("RedButton$"), "close: a cross on the same red button")
  x:GetScript("OnClick")(x)
  check(not ns.UI.frame:IsShown(), "close closes")
  ns.UI.frame:Show()
`);

section('Backgrounds');
await A.run(`
  local L = ns.Look
  local n = { studio = 0, room = 0, place = 0, fun = 0, custom = 0, map = 0, ground = 0, talent = 0, book = 0 }
  for _, b in ipairs(L.BACKGROUNDS) do n[b.group] = n[b.group] + 1 end
  check(n.studio == 20 and n.fun == 8 and n.custom == 1 and n.room == 6 and n.place == 32 and n.map == 48
    and n.ground == 17 and n.talent == 27 and n.book == 5,
    "20 studio, 8 moving, your colours, 17 ground, 27 talent trees, 5 books, 6 dressing rooms, 32 places, 48 maps")
  local look = L.New()
  look.bg = "dr_orc"
  check(L.Decode(L.Encode(look)).bg == "dr_orc", "dressing room survives the string")
  local pic = ns.Picture.New(UIParent, 400, 500)
  pic:SetLook(look, ns.Me())
  check(pic.art[1]._tex == 131101 and pic.art[4]._tex == 131104 and pic.art[4]:IsShown(), "four dressing room pieces")
  look.bg = "ls_mc"
  pic:Restyle()
  check(pic.art[1]._tex == 131851 and pic.art[1]:IsShown() and not pic.art[2]:IsShown(), "Molten Core loading screen")
  look.bg = "tal_magefire"
  pic:Restyle()
  check(tostring(pic.art[1]._tex):find("MageFire-TopLeft", 1, true) and pic.art[4]:IsShown(), "a talent tree: four pieces")
  look.bg = "gr_cobble"
  pic:Restyle()
  check(pic.art[1]._tex == 187099 and pic.art[1]:IsShown(), "ground: a tiled texture (by file id)")
  look.bg = "lq_lava"
  pic:Restyle()
  local first = pic.art[1]._tex
  Pump(pic.fx.layer, 0.5)
  check(first == 219795 and pic.art[1]._tex ~= first, "lava flows (its frames play)")
  look.bg = "elwynn"
  pic:Restyle()
  check(not pic.art[1]:IsShown(), "a studio colour has no picture")
`);

section('Fun: filters, moving backgrounds, overlays');
await A.run(`
  local L = ns.Look
  local look = L.New()
  look.overlay, look.filter, look.motion, look.bg, look.bgTop, look.bgBottom = "snow", "fel", "drunk", "custom", "ff0000", "0000ff"
  local back = L.Decode(L.Encode(look))
  check(back.overlay == "snow" and back.filter == "fel" and back.motion == "drunk" and back.bg == "custom" and back.bgTop == "ff0000"
    and back.bgBottom == "0000ff", "overlay, filter AND motion, and your own colours survive the string")
  check(L.Decode("1;oexplode;ubad").overlay == "none", "unknown overlays and broken colours are dropped")
  local pic = ns.Picture.New(UIParent, 356, 445)
  pic:SetLook(look, ns.Me())
  local shown = 0
  for _, s in ipairs(pic.fx.sprites) do if s.tex:IsShown() then shown = shown + 1 end end
  check(shown >= 20, "snow: flakes on the picture (" .. shown .. ")")
  check(pic.fx.layer:GetScript("OnUpdate") ~= nil, "a moving picture runs an OnUpdate")
  check(pic.tint.fxGrad:IsShown(), "Fel's colour fade, with Drunk on top")
  local y0 = pic.fx.sprites[1].y
  Pump(pic.fx.layer, 1)
  check(pic.fx.sprites[1].y ~= y0, "the flakes fall")
  check(pic.fx.swayed, "Drunk sways the camera")
  look.overlay, look.filter, look.motion, look.bg = "none", "vignette", "none", "normal"
  pic:Restyle()
  check(pic.fx.layer:GetScript("OnUpdate") == nil and not pic.fx.swayed, "still again: no OnUpdate, camera level")
  check(pic.tint.fxVig:IsShown(), "Vignette darkens the edges")
  look.filter = "ghost"
  pic:Restyle()
  Pump(pic.scene, 1) -- (your body is measured first, hidden)
  check(math.abs((pic.actor._alpha or 1) - 0.55) < 0.01, "Ghost: see-through")
  look.filter = "normal"
  pic:Restyle()
  check((pic.actor._alpha or 1) == 1, "and solid again")
  look.bg = "starfield"
  pic:Restyle()
  local stars = 0
  for _, s in ipairs(pic.fx.stars) do if s.tex:IsShown() then stars = stars + 1 end end
  check(stars > 10 and pic.fx.layer:GetScript("OnUpdate") ~= nil, "Starfield twinkles")
  pic:Clear()
  check(pic.fx.layer:GetScript("OnUpdate") == nil, "cleared: nothing moves")
`);

section('Fun: stickers, text, frames, lenses');
await A.run(`
  local L = ns.Look
  local look = L.New()
  look.stickers = { { key = "heart", x = 30, y = 40, s = 20, r = 15 }, { key = "rtskull", x = 70, y = 20, s = 12, r = 0 } }
  look.text = { text = "Died to |cffff0000Hogger|r; again", style = "achievement", y = 80 }
  look.deco, look.lens = "wanted", "tiny"
  local back = L.Decode(L.Encode(look))
  check(#back.stickers == 2 and back.stickers[1].key == "heart" and back.stickers[1].r == 15 and back.stickers[2].key == "rtskull",
    "stickers survive the string")
  check(back.text and back.text.style == "achievement" and back.text.y == 80 and back.text.text == "Died to cffff0000Hoggerr again",
    "text survives, without | codes or ;")
  check(back.deco == "wanted" and back.lens == "tiny", "frame and lens survive")
  local junk = L.Decode("1;kfake:1:1:1:1,heart:500:-9:999:900;tbad:50:hi;dnope;lexplode")
  check(#junk.stickers == 1 and junk.stickers[1].x == 100 and junk.stickers[1].y == 0 and junk.stickers[1].s == 80
    and junk.text == nil and junk.deco == "none" and junk.lens == nil, "odd stickers, text, frames and lenses are dropped or clamped")
  local copy = L.Copy(look)
  copy.stickers[1].x = 99
  copy.text.text = "changed"
  check(look.stickers[1].x == 30 and look.text.text ~= "changed", "a copy has its own stickers and text")

  -- Drawn on a picture.
  local pic = ns.Picture.New(UIParent, 356, 445)
  pic:SetLook(look, "Sticker Fan")
  local shown = 0
  for _, t in ipairs(pic.decor.dTex) do if t:IsShown() then shown = shown + 1 end end
  check(pic.stickerTex[1] and pic.stickerTex[1]:IsShown() and shown >= 6, "stickers, the achievement and the Wanted frame drawn (" .. shown .. ")")
  check(ns.Decor.StickerAt(pic, 0.3 * 356, 0.4 * 445) == 1 and ns.Decor.StickerAt(pic, 5, 440) == nil, "which sticker is under the mouse")
  check(math.abs((pic.actor._scale or 1) - 0.55) < 0.01, "Tiny: smaller")
  look.lens = "upside"
  pic:Restyle()
  check(pic.actor._roll and math.abs(pic.actor._roll - math.pi) < 0.01, "Upside down: turned over")
  look.lens = "sheep"
  pic:Restyle()
  check(pic.critter == 856 and pic.actor._display == 856, "Sheep: the sheep's model")
  look.lens = "spin"
  pic:Restyle()
  check(pic.critter == nil and pic.fx.layer:GetScript("OnUpdate") ~= nil, "Spin: back to the person, and it moves")
  Pump(pic.fx.layer, 0.5)
  look.lens = nil
  pic:Restyle()

  -- Face filters: on the head, wherever it is.
  look.lens, look.face = nil, "cat"
  local fp = ns.Picture.New(UIParent, 356, 445)
  fp:SetLook(look, "Face Fan")
  Pump(fp.scene, 1)
  local heads = fp:Heads()
  check(#heads == 1 and heads[1].size > 10 and heads[1].y > 0 and heads[1].y < 445 * 0.4 and math.abs(heads[1].x - 178) < 10,
    "the head: in the top part, in the middle (" .. (heads[1] and math.floor(heads[1].y) or "?") .. ")")
  check(ns.Look.Decode(ns.Look.Encode(look)).face == "cat", "a face filter survives the string")
  local function Count(p)
    local n = 0
    for _, t in ipairs(p.decor.dTex) do if t:IsShown() then n = n + 1 end end
    return n
  end
  local withCat = Count(fp)
  look.face = nil
  fp:Restyle()
  Pump(fp.scene, 0.2)
  check(withCat >= Count(fp) + 5, "Cat: ears and a nose drawn")
  look.face = "halo"
  fp:Restyle()
  Pump(fp.scene, 0.2)
  check(#fp.faceAnims == 1 and fp.fx.layer:GetScript("OnUpdate") ~= nil, "a halo bobs")
  look.frame = "face"
  fp:Restyle()
  Pump(fp.scene, 0.2)
  local close = fp:Heads()[1]
  check(close and close.size > heads[1].size * 1.5, "a close-up: a bigger head, a bigger halo (" .. tostring(close and math.floor(close.size)) .. " vs " .. math.floor(heads[1].size) .. ")")
  look.frame, look.face, look.lens = "full", nil, "sheep"
  fp:Restyle()
  check(#fp:Heads() == 0, "a sheep has no face to draw on")
  look.lens = nil

  -- Create: the tools.
  ns.UI:Show("studio")
  local v = ns.Studio.view
  ns.Studio.Pane("sticker")
  check(v.rail.buttons.sticker.on and v.panes.sticker:IsShown(), "the Stickers tool")
  -- Pick, then click on the picture: it goes where you clicked.
  ns.Studio.PickSticker("crown")
  check(v.placing == "crown", "a sticker picked")
  v.pic.GetLeft, v.pic.GetTop = function() return 100 end, function() return 600 end
  CURSOR_X, CURSOR_Y = 100 + 0.25 * v.pic:GetWidth(), 600 - 0.8 * v.pic:GetHeight()
  v.pic:GetScript("OnMouseDown")(v.pic, "LeftButton")
  v.pic:GetScript("OnMouseUp")(v.pic, "LeftButton")
  local st1 = v.look.stickers[1]
  check(st1 and st1.key == "crown" and math.abs(st1.x - 25) < 1 and math.abs(st1.y - 80) < 1 and v.placing == nil,
    "placed where you clicked")
  ns.Studio.AddSticker("gold")
  check(#v.look.stickers == 2 and v.pic.stickerSelected == 2 and v.stickerRemove:IsEnabled(), "stickers added, the last one selected")
  local before = v.look.stickers[2].s
  v.pic:GetScript("OnMouseWheel")(v.pic, 1)
  check(v.look.stickers[2].s > before and v.look.zoom == 100, "with Stickers open, the wheel sizes the sticker, not the zoom")
  v.stickerRemove:GetScript("OnClick")(v.stickerRemove)
  check(#v.look.stickers == 1, "Remove takes the selected sticker off")
  for i = 1, 10 do ns.Studio.AddSticker("star") end
  check(#v.look.stickers == ns.Look.MAX_STICKERS, "at most " .. ns.Look.MAX_STICKERS .. " stickers")
  v.stickerClear:GetScript("OnClick")(v.stickerClear)
  check(#v.look.stickers == 0 and not v.stickerClear:IsEnabled(), "Clear all")
  ns.Studio.Pane("text")
  v.textBox:SetText("Ding!")
  v.textBox:GetScript("OnTextChanged")(v.textBox, true)
  check(v.look.text and v.look.text.text == "Ding!" and v.look.text.style == "bar", "typing makes the text")
  for _, t in ipairs(v.tiles) do if t.isText and t.key == "levelup" then t:GetScript("OnClick")(t) end end
  check(v.look.text.style == "levelup", "a text style")
  v.textBox:SetText("")
  v.textBox:GetScript("OnTextChanged")(v.textBox, true)
  check(v.look.text == nil, "no words, no text")
  ns.Studio.Pane("motion")
  for _, t in ipairs(v.tiles) do if t.field == "motion" and t.key == "quake" then t:GetScript("OnClick")(t) end end
  for _, t in ipairs(v.tiles) do if t.field == "filter" and t.key == "noir" then t:GetScript("OnClick")(t) end end
  check(v.look.motion == "quake" and v.look.filter == "noir", "Motion and Filter together")
  for _, t in ipairs(v.tiles) do if t.field == "motion" and t.key == "none" then t:GetScript("OnClick")(t) end end
  for _, t in ipairs(v.tiles) do if t.field == "deco" and t.key == "film" then t:GetScript("OnClick")(t) end end
  check(v.look.deco == "film", "a frame")
  for _, t in ipairs(v.faceTiles) do if t.key == "bunny" then t:GetScript("OnClick")(t) end end
  check(v.look.face == "bunny", "a face filter on you")
  for _, t in ipairs(v.faceTiles) do if t.key == "none" then t:GetScript("OnClick")(t) end end
  for _, t in ipairs(v.lensTiles) do if t.key == "frog" then t:GetScript("OnClick")(t) end end
  check(v.look.lens == "frog" and v.pic.critter == 6297, "a lens on you: a frog")
  for _, t in ipairs(v.lensTiles) do if t.key == "none" then t:GetScript("OnClick")(t) end end
  check(v.look.lens == nil and v.pic.critter == nil, "and back")
  ns.Studio.Fresh()
  check(#v.look.stickers == 0 and v.look.deco == "none" and v.textBox:GetText() == "", "Create starts fresh: no stickers, text or frame")
`);

section('Dislike and block');
const BK = await Player('Block Tester');
await BK.run(`
  local S = ns.Social
  S.SetNetwork(false) -- (its pictures mustn't reach the other test players)
  local post = S.Post("1;pwave", "Rate me")
  S.Dislike(post.id, true, "Grumpy Gus")
  S.Like(post.id, true, "Happy Hal")
  check(S.Dislikes(post) == 1 and S.Likes(post) == 1, "a dislike and a like")
  local readable = false
  for key in pairs(post.dislikes) do if key:find("Grumpy", 1, true) then readable = true end end
  check(not readable, "nobody can read who disliked")
  check(ns.my.activity[1] == nil or ns.my.activity[1].kind ~= "dislike", "and nobody is told")
  S.Like(post.id, true, "Grumpy Gus")
  check(S.Dislikes(post) == 0 and S.Likes(post) == 2, "liking takes the dislike back")
  S.Dislike(post.id, true, "Happy Hal")
  check(S.Likes(post) == 1 and S.Disliked(post, "Happy Hal"), "and disliking takes the like back")
  check(ns.Feed.LikesText(post):find("1 dislike", 1, true), "the count says it: " .. ns.Feed.LikesText(post))
  -- Block: their pictures, comments, likes and dislikes go out of sight.
  local theirs = S.Store({ id = "troll1", author = "Mean Mike", t = ns.Now(), look = "1", caption = "lol", likes = {}, comments = {} })
  S.Comment(post.id, "ugly", { name = "Mean Mike", class = "ROGUE" })
  S.Dislike(post.id, true, "Mean Mike")
  local before = S.Dislikes(post)
  S.Block("Mean Mike", true)
  local seen = false
  for _, p in ipairs(S.List("all")) do if p.author == "Mean Mike" then seen = true end end
  check(not seen and #S.List("Mean Mike") == 0, "blocked: their pictures are hidden, even on their profile")
  local said = false
  for _, c in ipairs(S.Comments(post)) do if c.author == "Mean Mike" then said = true end end
  check(not said and S.Dislikes(post) == before - 1, "and their comments and dislikes")
  check(#S.BlockedList() == 1, "Settings lists them")
  S.Block("Mean Mike", false)
  check(#S.List("Mean Mike") == 1, "unblocked: back again")
  -- A dislike travels inside a picture (a sync), and on its own.
  local p2 = { id = "dz1", author = "Far Away", t = ns.Now(), look = "1", caption = "x", likes = {}, comments = {},
    dislikes = { [S.Anon("Some One")] = ns.Now() } }
  S.Store(p2)
  check(S.Dislikes(S.Find("dz1")) == 1, "dislikes stored with a picture")
`);

section('Friends, people you have seen, hashtags, mentions, search');
const FS = await Player('Feed Ranker');
await FS.run(`
  local S = ns.Social
  S.SetNetwork(false)
  local now = ns.Now()
  local function Add(id, author, hoursAgo, caption)
    S.Store({ id = id, author = author, t = now - hoursAgo * 3600, look = "1", caption = caption or "", likes = {}, comments = {} })
  end
  Add("s1", "Some Stranger", 1, "fresh #sunset")
  Add("f1", "Best Friend", 5, "with my #sunset")
  Add("m1", "Met Lately", 3, "hi")
  Add("old", "Old Stranger", 24 * 5, "ancient")
  for i = 1, 8 do Add("x" .. i, "Filler " .. i, 2 + i, "") end
  FRIENDS = { "Best Friend" }
  S.RefreshFriends()
  S.Meet("Met Lately")
  local feed = S.Feed()
  check(feed[1].id == "f1", "a friend's picture first, though five hours old: " .. tostring(feed[1].id))
  local pos = {}
  for i, p in ipairs(feed) do pos[p.id] = i end
  check(pos.m1 and pos.m1 < pos.s1 + 2, "someone you've seen lately ranks up")
  check(pos.old == nil and #S.List("Old Stranger") == 1, "a stranger's 5-day-old picture is out of the Realm feed, still on their profile")
  check(#S.List("#sunset") == 2, "a hashtag's feed")
  C_RecentAllies = { GetRecentAllies = function()
    return { { characterData = { name = "Dungeon Buddy" }, interactionData = { lastInteractionTime = now - 600 } } }
  end }
  local nRA = S.ReadRecentlyMet()
  check(nRA == 1 and S.MetLately("Dungeon Buddy") > 0.9, "the game's own recently met list counts")
  C_RecentAllies = nil
  check(ns.Feed.Rich("go #Sunset now"):find("|Hwgtag:sunset|h", 1, true), "#tags become links")
  check(ns.Feed.Rich("a |cffff0000red|r b"):find("||cffff0000", 1, true), "colour codes from others are made harmless")
  local m = S.Mentions("hey @Best Friend look")
  check(#m == 1 and m[1].id == "Best Friend", "a two-word mention")
  check(ns.Feed.Rich("hey @Best Friend look"):find("|Hwgperson:Best Friend|h", 1, true), "mentions become links")
  local r = ns.Search.Find("best")
  check(r[1] and r[1].person == "Best Friend", "search finds people by part of the name")
  S.Meet("Never Used It")
  check(#ns.Search.Find("never used") == 0, "someone you've seen who doesn't have the addon isn't listed")
  ns.Net.Receive("Has It Now", "H:97:1/1@Has It Now#" .. ns.Net.PROTO .. ":0", "CHANNEL")
  check(#ns.Search.Find("has it") == 1, "someone whose addon said hello is")
  local t = ns.Search.Find("#sun")
  check(t[1] and t[1].tag == "sunset" and t[1].n == 2, "search finds hashtags")
  -- The tag box on the wall.
  ns.UI:Show("feed")
  local fv = ns.UI.pages.feed.view
  fv.tagBox:SetFocus()
  fv.tagBox:SetText("sun")
  fv:TagList()
  check(fv.tagDrop:IsShown() and fv.tagDrop.rows[1].tag == "sunset" and not fv.tagDrop.rows[2]:IsShown(), "the wall's tag box lists matching tags")
  fv.tagDrop.rows[1]:GetScript("OnClick")(fv.tagDrop.rows[1])
  check(fv.filter == "#sunset" and fv.tagClear:IsShown() and fv.tagBox:GetText() == "#sunset", "picking one shows its pictures")
  fv.tagClear:GetScript("OnClick")(fv.tagClear)
  check(fv.filter == "all" and fv.tagBox:GetText() == "", "and X goes back to Realm")
  -- Mentioned in someone's comment: a notification.
  ns.Net.Receive("Best Friend", "P:91:1/1@Best Friend#" .. ns.Net.PROTO .. ":" .. table.concat({ "men1", "Best Friend", "", "",
    tostring(now), "0", "1", "look @Feed Ranker here", "", "" }, string.char(31)), "CHANNEL")
  local a = ns.my.activity[1]
  check(a and a.kind == "mention" and a.who == "Best Friend", "mentioned in a caption: a notification")
`);

section('The look in a group picture');
const GL = await Player('Look Tester');
await GL.run(`
  ns.Social.SetNetwork(false)
  local look = ns.Look.New()
  look.race, look.sex = 1, 2
  look.slots[1] = { item = 16963 }
  local q = ns.Look.NewPerson("Pal Friend", 4, 3, "DRUID")
  q.slots[5] = { item = 16706 }
  q.pose = "wave"
  table.insert(look.people, q)
  local post = ns.Social.Post(ns.Look.Encode(look), "Us two")
  ns.UI:Show("post", post.id)
  local v = ns.UI.pages.post.view
  check(v.lookNames[1]:IsShown() and v.lookNames[2]:IsShown() and not v.lookNames[3]:IsShown(), "a name for each person")
  check(v.items[1]:IsShown() and v.items[1].entry.item == 16963, "the poster's look first")
  v.lookNames[2]:GetScript("OnClick")(v.lookNames[2])
  check(v.items[1].entry.item == 16706 and not v.items[2]:IsShown(), "click a name: their look")
  ns.Studio.Remix(post, 1)
  local s = ns.Studio.view
  check(s.look.slots[5] and s.look.slots[5].item == 16706 and #s.look.people == 0 and s.look.pose == "wave",
    "Try this look: their outfit on you, on your own")
`);

section('Your characters: each its own bio, follows, notifications');
const ALT = await Player('Zal Arer');
await ALT.run(`
  local S = ns.Social
  S.SetNetwork(false)
  S.SetBio("Night elf, day dreamer")
  S.Follow("Some Star", true)
  S.Post("1", "Zal's picture")
  -- Log in on another character of the same account.
  PLAYER_NAME = "Trick Ky"
  ns.LoadCharacter()
  check(ns.Me() == "Trick Ky" and ns.my.me.bio == "", "Trick has his own (empty) bio, not Zal's")
  check(not S.Following("Some Star"), "and his own follows")
  local zal = S.Profile("Zal Arer")
  check(zal and zal.bio == "Night elf, day dreamer", "Zal's profile, bio and all, seen from Trick")
  check(#S.List("Zal Arer") == 1, "Zal's pictures are shared")
  PLAYER_NAME = "Zal Arer"
  ns.LoadCharacter()
  check(ns.my.me.bio == "Night elf, day dreamer" and S.Following("Some Star"), "back on Zal: all still there")
  -- An older copy kept these for the whole account: they go to the one who posted.
  ns.db.chars = nil
  ns.db.charsClaimed = nil
  ns.db.me, ns.db.following = { bio = "old bio", t = 1 }, { ["Old Follow"] = 1 }
  PLAYER_NAME = "Trick Ky"
  ns.LoadCharacter()
  check(ns.my.me.bio == "" and ns.db.me ~= nil, "an alt who never posted doesn't take the old bio")
  PLAYER_NAME = "Zal Arer"
  ns.LoadCharacter()
  check(ns.my.me.bio == "old bio" and ns.my.following["Old Follow"] and ns.db.me == nil, "the one who posted gets it")
`);

section('Selfie');
await A.run(`
  ns.UI:Show("studio")
  ns.Studio.Selfie()
  local v = ns.Studio.view
  check(v.look.slots[1] and v.look.slots[1].item == 16963, "selfie starts from equipped gear")
  check(v.look.race == 1 and v.look.class == "WARRIOR", "selfie is you")
  Advance(1)
  Pump(v.pic.scene, 1)
  check(v.look.slots[1] and v.look.slots[1].a == 116963, "selfie upgrades to transmog appearances")
  check(v.look.slots[5].a == 116966 and v.look.slots[16].a == 117076, "all worn slots read")
  check(v.pic.actor._unit == "player", "your own body")
  check(v.pic.actor._worn[1] and v.pic.actor._worn[1].appearanceID == 116963, "picture is dressed in it")
  check(ns.db.drafts == nil, "no draft is kept")
  check(v.pic.measure == nil and v.pic.actor._alpha == 1 and not v.pic.actor._bare, "body measured, then shown dressed")
  -- Face framing aims at the face of the 2-tall body, not the 3-tall box.
  v.look.frame = "face"
  v.pic:Restyle()
  Pump(v.pic.scene, 0.3)
  local cam = v.pic.scene._cam
  check(cam and math.abs(cam[3] - 2 * ns.Look.FRAME.face.z) < 0.01, "face framed on the body: " .. tostring(cam and cam[3]))
  v.look.frame = "full"
  v.pic:Restyle()
`);

section('Dress up');
await A.run(`
  local v = ns.Studio.view
  local L = ns.Look
  -- Click Head: off; click again: back on.
  v.slots[1]:GetScript("OnClick")(v.slots[1], "LeftButton")
  check(v.look.slots[1] == nil and v.stash[1], "click takes the helm off")
  v.slots[1]:GetScript("OnClick")(v.slots[1], "LeftButton")
  check(v.look.slots[1] and v.look.slots[1].a == 116963, "click puts it back")
  v.slots[1]:GetScript("OnClick")(v.slots[1], "RightButton")
  check(v.look.slots[1] == nil and v.stash[1] == nil, "right-click empties it")
  ns.Studio.TryOn("21524")
  check(v.look.slots[1] and v.look.slots[1].a == 121524, "item id tries on, as an appearance")
  TRANSMOG = false
  ns.Studio.TryOn("|cffffffff|Hitem:2575::|h[Red Linen Shirt]|h|r")
  check(v.look.slots[4] and v.look.slots[4].item == 2575, "without transmog data: plain item id")
  TRANSMOG = true
  ns.Studio.TryOn("18832", 17)
  check(v.look.slots[17] and v.look.slots[17].a == 118832, "one-hander goes in the off hand slot it was dropped on")
  ns.Studio.TryOn("16966", 1)
  check(v.status:GetText():find("doesn't go there"), "chest on the head slot refused")
  ITEMS[4540] = "" -- bread: can't be worn
  ns.Studio.TryOn("4540")
  check(v.status:GetText():find("can't be worn"), "bread refused")
  ns.Studio.TryOn("999999")
  check(v.status:GetText():find("Fetching"), "unknown id: asks the game")
  Fire("GET_ITEM_INFO_RECEIVED", 999999, false)
  check(v.status:GetText():find("no item with that id"), "and says so when there is none")
  -- Not fetched yet: waits for the game.
  ITEMS[19019] = "INVTYPE_WEAPON"
  UNCACHED[19019] = true
  ns.Studio.TryOn("19019")
  check(v.look.slots[16].a ~= 119019 and REQUESTED == 19019, "uncached item is requested first")
  UNCACHED[19019] = nil
  Fire("GET_ITEM_INFO_RECEIVED", 19019, true)
  check(v.look.slots[16].a == 119019, "and tried on when it arrives")
  -- Drop from bags onto the picture.
  CURSOR = { "item", 16963, "item:16963" }
  v.pic:GetScript("OnReceiveDrag")(v.pic)
  check(v.look.slots[1].a == 116963 and CURSOR == nil, "dropping an item on the picture tries it on")
  -- Shift-click an item link.
  SHIFT_DOWN = true
  HandleModifiedItemClick("|Hitem:21524::|h[Hat]|h")
  SHIFT_DOWN = false
  check(v.look.slots[1].a == 121524, "shift-click tries it on")
  -- Take all off, then Put all on.
  local before = ns.Look.SlotCount(v.look)
  v.naked:GetScript("OnClick")(v.naked)
  check(ns.Look.SlotCount(v.look) == 0 and v.naked:GetText() == "Put all on", "take all off: button says Put all on")
  v.naked:GetScript("OnClick")(v.naked)
  check(ns.Look.SlotCount(v.look) == before and v.naked:GetText() == "Take all off", "put all on: everything back")
  -- Coming back to Create: a fresh start.
  local saved = { pose = v.look.pose, slots = ns.Look.SlotCount(v.look) }
  v.look.pose, v.look.bg = "dance", "ls_mc"
  v.caption:SetText("old words")
  ns.UI:Show("feed")
  ns.UI:Show("studio")
  check(v.look.pose == "stand" and v.look.bg == "normal" and v.caption:GetText() == "", "Create starts fresh each visit")
  check(v.look.slots[1] and v.look.slots[1].item == 16963, "wearing what you wear now")
  Advance(1)
  -- Back to the test outfit.
  ns.Studio.TryOn("21524")
  TRANSMOG = false
  ns.Studio.TryOn("2575")
  TRANSMOG = true
  ns.Studio.Pane("pose")
  check(v.panes.pose:IsShown() and not v.panes.outfit:IsShown(), "Studio tabs switch panes")
  v.poses[2]:GetScript("OnClick")(v.poses[2])
  check(v.look.pose == "dance" and v.pic.actor._anim == 69, "pose button dances")
  v.still:GetScript("OnClick")(v.still)
  check(v.look.still and v.pic.actor._animSpeed == 0, "Hold still: the dance frozen")
  check(ns.Look.Decode(ns.Look.Encode(v.look)).still, "Hold still survives the string")
  v.still:GetScript("OnClick")(v.still)
  check(not v.look.still and v.pic.actor._animSpeed ~= 0, "and moving again")
  local function Click(field, key)
    for _, t in ipairs(v.tiles) do
      if t.field == field and t.key == key then return t:GetScript("OnClick")(t) end
    end
    error("no tile " .. field .. " " .. key)
  end
  Click("filter", "noir")
  check(v.look.filter == "noir" and v.pic.actor._grey == 1, "noir filter greys the picture")
  Click("bg", "elwynn")
  check(v.look.bg == "elwynn" and v.bgPane.chosen:GetText() == "Elwynn", "background chosen and named")
  Click("filter", "warm")
  check(v.look.filter == "warm" and v.pic.wash:IsShown(), "warm filter lays its wash over the picture")
  Click("overlay", "hearts")
  check(v.look.overlay == "hearts" and v.look.filter == "warm" and v.overlayPane.chosen:GetText() == "Hearts",
    "an overlay goes with the filter")
  ns.Studio.Pane("overlay")
  check(v.panes.overlay:IsShown() and not v.panes.filter:IsShown() and v.title:GetText() == "Overlay"
    and v.rail.buttons.overlay.on and not v.rail.buttons.filter.on, "the rail opens Overlay")
  for _, b in ipairs(v.swatches) do
    if b.field == "bgBottom" and b.hex == "ff2d92" then b:GetScript("OnClick")(b) end
  end
  check(v.look.bg == "custom" and v.look.bgBottom == "ff2d92" and v.look.bgTop ~= nil, "a swatch: your own colours")
  Click("overlay", "none")
  Click("bg", "normal")
  Click("filter", "noir")
  v.frames[3]:GetScript("OnClick")(v.frames[3])
  check(v.look.frame == "face", "framing")
  v.pic:GetScript("OnMouseWheel")(v.pic, 1)
  check(v.look.zoom == 110, "wheel zooms")
  CURSOR_X = 0
  v.pic:GetScript("OnMouseDown")(v.pic, "LeftButton")
  CURSOR_X = 50
  v.pic:GetScript("OnUpdate")(v.pic, 0.1)
  v.pic:GetScript("OnMouseUp")(v.pic, "LeftButton")
  check(math.abs(v.look.yaw - 40) < 0.01, "drag turns: " .. tostring(v.look.yaw))
  -- Right-drag moves the character (the camera goes the other way).
  local camBefore = v.pic.scene._cam and v.pic.scene._cam[2] or 0
  CURSOR_X, CURSOR_Y = 0, 0
  v.pic:GetScript("OnMouseDown")(v.pic, "RightButton")
  CURSOR_X, CURSOR_Y = 50, -25
  v.pic:GetScript("OnUpdate")(v.pic, 0.1)
  v.pic:GetScript("OnMouseUp")(v.pic, "RightButton")
  check(v.look.mx > 0 and v.look.my < 0, "right-drag moves right and down: " .. v.look.mx .. ", " .. v.look.my)
  local s = ns.Look.Encode(v.look)
  local back = ns.Look.Decode(s)
  check(math.abs(back.mx - v.look.mx) < 0.01 and math.abs(back.my - v.look.my) < 0.01, "placement survives the string")
`);

section('Post and share');
const B = await Player('Mira Dawnfeather');
await Tick(1, 8); // both join the channel and say hello
await A.run(`check(ns.Net.Online(), "A on the realm channel")`);
await B.run(`check(ns.Net.Online(), "B on the realm channel")`);
await A.run(`
  local v = ns.Studio.view
  v.caption:SetText("First picture! #wowstagram")
  ns.Studio.Post()
  check(#ns.db.posts == 1, "posted")
  check(ns.UI.tab == "post", "opens your new picture")
  POST_ID = ns.db.posts[1].id
`);
await Tick(0.5, 6);
await B.run(`
  local p = ns.db.posts[1]
  check(p and p.author == "Flintar Stone", "B got it, two-word author intact: " .. tostring(p and p.author))
  check(ns.Display(p.author) == "Flintar Stone", "shown without the realm")
  check(p and p.caption == "First picture! #wowstagram", "caption intact")
  local look = ns.Look.Decode(p.look)
  check(look.pose == "dance" and look.filter == "noir" and look.slots[1].a == 121524, "look intact")
  check(look.slots[4] and look.slots[4].item == 2575, "plain item slot intact")
  ns.UI:Toggle()
  ns.UI:Show("feed")
  local card = ns.UI.pages.feed.view.cards[1]
  check(card:IsShown() and card.post == p, "B's feed shows it")
  check(card.pic.actor._unit == "player" and card.pic.customRace == 1, "A (not nearby): B's body as A's race (a stand-in, same gender)")
  check(card.pic.note:GetText() == "", "no on-you note any more")
  -- B likes it with a double-click, and comments.
  card.pic:GetScript("OnMouseUp")(card.pic, "LeftButton")
  card.pic:GetScript("OnMouseUp")(card.pic, "LeftButton")
  check(ns.Social.Liked(p), "double-click likes")
  check(card.heart.icon._tex:find("Heart$") and card.likes.text:GetText() == "1 like", "shown at once, before any redraw")
  check(card.heart.icon._tex and card.heart.icon._tex:find("Heart$"), "heart turns red on the card: " .. tostring(card.heart.icon._tex))
  check(card.likes.text:GetText() == "1 like", "likes text says so: " .. tostring(card.likes.text:GetText()))
  ns.UI:OpenPost(p.id)
  local pv = ns.UI.pages.post.view
  -- Typing under a post survives a redraw (a like coming in).
  card.comment:SetText("half a thought")
  ns.UI:Refresh()
  check(card.comment:GetText() == "half a thought", "a redraw keeps what you're typing")
  card.comment:SetText("")
  pv.commentBox:SetText("Looking sharp!")
  pv.commentBox:GetScript("OnEnterPressed")(pv.commentBox)
  check(#p.comments == 1, "B commented")
`);
await Tick(0.5, 6);
await A.run(`
  local p = ns.Social.Find(POST_ID)
  check(ns.Social.Likes(p) == 1 and ns.Social.Liked(p, "Mira Dawnfeather"), "A sees B's like")
  check(#p.comments == 1 and p.comments[1].text == "Looking sharp!", "A sees B's comment")
  check((ns.my.unread or 0) == 0 or ns.UI.tab ~= "profile", "unread counted")
  local told = 0
  for _, line in ipairs(CHAT) do if line:find("liked your picture") or line:find("commented") then told = told + 1 end end
  check(told == 2, "A told about the like and the comment: " .. told)
`);
await B.run(`
  local p = ns.db.posts[1]
  ns.Social.Like(p.id, false)
  check(not ns.Social.Liked(p), "unlike")
`);
await Tick(0.5, 4);
await A.run(`check(ns.Social.Likes(ns.Social.Find(POST_ID)) == 0, "A sees the unlike")`);

section('Only the owner');
await B.run(`
  local p = ns.db.posts[1]
  ns.UI:OpenPost(p.id)
  local pv = ns.UI.pages.post.view
  pv:Refresh()
  check(not pv.delete:IsShown() and not pv.edit:IsShown(), "no Delete or Edit on someone else's picture")
  check(pv.list.rows[1].del:IsShown(), "Delete on your own comment")
  -- Fakes: B's addon pretends to be the owner.
  ns.Net.Send("D", p.id .. string.char(31) .. ns.Now())
  ns.Net.Send("P", table.concat({ p.id, p.author, "", "", p.t, ns.Now() + 5, p.look, "HACKED", "" }, string.char(31)))
  ns.Net.Send("L", table.concat({ p.id, "Old Tom Cobble", ns.Now() }, string.char(31)))
  ns.Social.Delete(p.id)
  check(ns.Social.Find(p.id) ~= nil, "can't delete someone else's picture here either")
`);
await Tick(0.5, 6);
await A.run(`
  local p = ns.Social.Find(POST_ID)
  check(p ~= nil, "a delete from someone else is ignored")
  check(p and p.caption ~= "HACKED", "an edit from someone else is ignored")
  check(p and not ns.Social.Liked(p, "Old Tom Cobble"), "a like in someone else's name is ignored")
  -- A can't delete B's comment on A's own picture.
  ns.UI:OpenPost(POST_ID)
  local pv = ns.UI.pages.post.view
  pv:Refresh()
  check(pv.delete:IsShown(), "Delete on your own picture")
  check(not pv.list.rows[1].del:IsShown(), "no Delete on someone else's comment, even on your picture")
  ns.Social.DeleteComment(POST_ID, p.comments[1].author, p.comments[1].t)
  check(#p.comments == 1, "and the call does nothing")
  ns.Net.Send("X", table.concat({ POST_ID, p.comments[1].author, p.comments[1].t, ns.Now() }, string.char(31)))
`);
await Tick(0.5, 6);
await B.run(`check(#ns.db.posts[1].comments == 1, "a comment delete from someone else is ignored")`);

section('Edit, comment delete, follow');
await A.run(`
  ns.Social.Edit(POST_ID, "Edited caption")
`);
await Tick(0.5, 4);
await B.run(`
  local p = ns.db.posts[1]
  check(p.caption == "Edited caption", "B sees the edit")
  ns.Social.DeleteComment(p.id, "Mira Dawnfeather", p.comments[1].t)
  check(#p.comments == 0, "B deletes own comment")
  ns.Social.Follow("Flintar Stone", true)
  check(#ns.Social.List("following") == 1, "following feed")
  ns.UI:OpenPerson("Flintar Stone")
  local pv = ns.UI.pages.person.view
  check(pv.name_ == "Flintar Stone" and pv.thumbs[1]:IsShown(), "A's profile shows the picture")
`);
await Tick(0.5, 4);
await A.run(`check(#ns.Social.Find(POST_ID).comments == 0, "A sees the comment deleted")`);

section('Group picture');
await A.run(`
  GROUP = { "Mira Dawnfeather" }
  ns.UI:Show("studio")
  local v = ns.Studio.view
  ns.Studio.Pane("people")
  check(v.panes.people:IsShown(), "People tab")
  local c = ns.Studio.Candidates()
  check(#c == 1 and c[1].unit == "party1" and c[1].id == "Mira Dawnfeather", "party member can be added")
  check(v.adds[1]:IsShown() and v.adds[1]:IsEnabled(), "an Add button for her")
  v.adds[1]:GetScript("OnClick")(v.adds[1])
  local q = v.look.people[1]
  check(q and q.name == "Mira Dawnfeather" and q.race == 1 and q.sex == 2, "she's in the picture")
  check(v.sel == 1 and v.people[1]:IsShown() and v.people[1].mark, "and selected, in the list")
  Advance(1)
  check(q.slots[1] and q.slots[1].a == 116963, "her outfit was read: " .. tostring(q.slots[1] and q.slots[1].a))
  check(v.look.mx < 0 and q.mx > 0 and v.look.zoom < 100, "spread out, one step back")
  -- The Pose tab now poses her, not you.
  v.poses[3]:GetScript("OnClick")(v.poses[3])
  check(q.pose == "wave" and v.look.pose ~= "wave", "her pose")
  check(v.pic.extras[1] and v.pic.extras[1]._anim == 67, "her figure waves")
  -- Right-drag grabs whoever is nearest: click near you, you move.
  local w = v.pic:GetWidth()
  CURSOR_X, CURSOR_Y = w * (0.5 + v.look.mx), 200
  v.pic:GetScript("OnMouseDown")(v.pic, "RightButton")
  check(v.sel == 0, "right-drag near you selects you")
  CURSOR_X = CURSOR_X - 30
  v.pic:GetScript("OnUpdate")(v.pic, 0.1)
  v.pic:GetScript("OnMouseUp")(v.pic, "RightButton")
  check(v.look.mx < -0.15, "and moves you: " .. v.look.mx)
  -- The string keeps everyone.
  local back = ns.Look.Decode(ns.Look.Encode(v.look))
  local bq = back.people[1]
  check(bq and bq.name == "Mira Dawnfeather" and bq.pose == "wave" and bq.slots[1].a == 116963, "she survives the string")
  check(math.abs(bq.mx - q.mx) < 0.01, "where she stands too")
  v.caption:SetText("Us!")
  ns.Studio.Post()
  GROUP_POST = ns.db.posts[1].id
  -- Remove: back to one.
  ns.UI:Show("studio")
  check(#v.look.people == 0, "Create fresh again: just you")
`);
await Tick(0.5, 6);
await A.run('__ret = GROUP_POST');
B.lua.global.set('GROUP_POST', A.lua.global.get('__ret'));
await B.run(`
  local p = ns.Social.Find(GROUP_POST)
  check(p and p.caption == "Us!", "B got the group picture")
  ns.UI:OpenPost(GROUP_POST)
  local pic = ns.UI.pages.post.view.pic
  check(pic.extras[1] and pic.extras[1]._unit == "player", "B is in it, drawn as B (herself)")
  check(pic.actor._unit == "player" and pic.customRace == 1, "A (a stranger to B): stand-in body, A's race")
  Pump(pic.scene, 1)
  check(pic.actor._race == 1, "measured and loaded as A's race")
  local worn = pic.actor._worn or {}
  check(worn[1] and worn[5], "in his whole outfit, chest too")
  -- Someone of the other gender, nobody of that gender around: plain race + separate pieces.
  local look = ns.Look.Decode(p.look)
  look.sex = 3
  local pic2 = ns.Picture.New(UIParent, 200, 250)
  pic2:SetLook(look, "Someone Else")
  check(ns.Picture.ArmorStyle(look.slots) == "plate", "her outfit is plate (the Wrath chest)")
  check(pic2.display == ns.Picture.Placeholder(1, 3, "plate") and pic2.display == ns.Picture.Placeholders()[1][3].plate,
    "a woman, no woman to stand in: a Human woman already in plate")
  check(ns.FOREVER and ns.Picture.Placeholders() == ns.Picture.PLACEHOLDER_CLASSIC, "Forever uses its classic-era picks")
  Pump(pic2.scene, 1)
  check(pic2.measure == nil, "placeholders aren't measured: their race's height frames them")
  -- Heights by race: a Gnome is about half a Human; calibrated on your own body (2 tall here, a Human man).
  local P = ns.Picture
  check(math.abs(P.RaceHeight(1, 2) - 2.2) < 0.01, "Human man: 2.2 until your body is measured")
  check(math.abs(P.RaceHeight(7, 2) / P.RaceHeight(1, 2) - 0.64) < 0.01, "Gnome man: about half")
  check(math.abs(math.tan(P.DiagFov(0.62, 300, 375) / 2) / math.tan(0.31) - math.sqrt(300^2 + 375^2) / 375) < 0.001,
    "the camera angle is diagonal: a 4:5 picture gets a wider angle")
  check(P.DiagFov(0.62, 300, 100) > P.DiagFov(0.62, 300, 375), "scrolled half out (wide and short): wider still, so no zooming in")
  -- Save to computer: the interface hides, a screenshot, and it comes back.
  SHOTS = 0
  local uiHidden
  Screenshot = function()
    SHOTS = SHOTS + 1
    uiHidden = not UIParent:IsShown()
    Fire("SCREENSHOT_SUCCEEDED")
  end
  local sp = { id = "shot1", author = "Shot Taker", look = ns.Look.Encode(look), caption = "Say cheese", t = 1 }
  local okSave, errSave = pcall(P.SaveToComputer, sp)
  check(okSave, "save to computer runs: " .. tostring(errSave))
  Advance(1.5)
  Advance(0.5)
  check(SHOTS == 1 and uiHidden, "save to computer: one screenshot, with the interface hidden")
  check(UIParent:IsShown() and not WowstagramScreenshot:IsShown(), "and everything back afterwards")
  P.Wall()
  check(P.wall and P.wall:IsShown(), "/wgram wall opens")
  -- Tune faces: drag moves the face filter for that race and sex, the wheel sizes it.
  local tuneB = P.wallTune
  P.wall:Show()
  tuneB:GetScript("OnClick")(tuneB)
  Pump(P.wallCells[1].pic.scene, 1)
  local cell = P.wallCells[1].tune
  check(cell ~= nil, "Tune faces: every picture can be tuned")
  cell:GetScript("OnMouseWheel")(cell, 1)
  local key, fix = next(ns.db.faceTune)
  check(key and fix.size > 1 and key:find(":full$"), "the wheel makes the face bigger, saved for that race, sex and framing (" .. tostring(key) .. ")")
  check(ns.db.faceObs[key] and ns.db.faceObs[key].half > 0, "and what the camera saw is kept")
  tuneB:GetScript("OnClick")(tuneB)
  ns.db.faceTune = {}
  P.faceGrid = true
  local gp = ns.Picture.New(UIParent, 300, 375)
  gp:SetLook(look, "Grid Test")
  Pump(gp.scene, 1)
  local lines = 0
  for _, t in ipairs(gp.decor.dTex) do if t:IsShown() then lines = lines + 1 end end
  check(lines >= 12, "the face grid draws its lines (" .. lines .. ")")
  P.faceGrid = nil
  P.Wall()
  check(P.HeadSize(7) > 1 and P.HeadSize(1) == 1, "gnome close-ups take in more")
  check(P.RaceHeight(6, 2) > P.RaceHeight(4, 2) and P.RaceHeight(4, 3) < P.RaceHeight(4, 2), "Tauren tallest; women a bit shorter")
  local w2 = pic2.actor._worn or {}
  check(w2[1] and not w2[5], "with only the separate pieces")
  -- A woman in the group: she stands in.
  GROUP = { "Ana Bell" }
  local before = UnitSex
  UnitSex = function(u) if u == "party1" then return 3 end return 2 end
  pic2:SetLook(look, "Someone Else")
  check(pic2.actor._unit == "party1" and pic2.customRace == 1 and pic2.display == nil, "a woman in the group stands in, as the poster's race")
  check(pic2.note:GetText() == "", "full outfit: no note")
  -- She leaves the group: the picture keeps the full outfit it has.
  GROUP = {}
  pic2:SetLook(look, "Someone Else")
  check(pic2.display == nil and pic2.actor._unit == "party1", "the stand-in left: the picture keeps her")
  -- A different picture of a woman, with nobody to stand in: the note says why.
  local pic3 = ns.Picture.New(UIParent, 200, 250)
  pic3:SetLook(look, "Another Woman")
  check(pic3.display and pic3.state == "lookalike", "partial outfit: a look-alike")
  -- Badges: a feed card for a woman nobody can stand in for.
  local card = ns.Picture.New(UIParent, 300, 375, { badge = "full" })
  card:SetLook(look, "Third Woman")
  check(card.badge:IsShown() and card.badge.text:GetText():find("look%-alike$"), "badge: <race> look-alike: " .. tostring(card.badge.text:GetText()))
  check(card.toggle == nil, "just the tag, no button")
  -- A model the client lacks: Missing data.
  card.actor.IsLoaded = function() return false end
  Pump(card.scene, 3)
  check(card.badge.text:GetText() == "Missing data", "a model that never loads: Missing data")
  card.actor.IsLoaded = nil
  -- An item the game doesn't have: Loading, then Missing data (not Loading forever).
  ITEMS[777001] = "INVTYPE_HEAD"
  UNCACHED[777001] = true
  local gone = ns.Look.Decode(ns.Look.Encode(look))
  gone.slots[1] = { item = 777001 }
  local lp = ns.Picture.New(UIParent, 300, 375, { badge = "full" })
  lp:SetLook(gone, "Fourth Woman")
  Pump(lp.scene, 1)
  check(lp.badge.text:GetText() == "Loading...", "an item on its way: Loading")
  Advance(6)
  check(lp.badge.text:GetText() == "Missing data" and lp.missingItems[777001], "still nothing after 5 s: Missing data")
  local lp2 = ns.Picture.New(UIParent, 300, 375, { badge = "full" })
  lp2:SetLook(gone, "Fifth Woman")
  Pump(lp2.scene, 1)
  Fire("GET_ITEM_INFO_RECEIVED", 777001, false)
  check(lp2.badge.text:GetText() == "Missing data", "the game says no such item: Missing data at once")
  UNCACHED[777001] = nil

  -- Your own picture: no badge.
  local mine = ns.Picture.New(UIParent, 300, 375, { badge = "full" })
  mine:SetLook(look, ns.Me())
  check(not mine.badge:IsShown(), "your own picture: no badge")

  -- Robes and missing styles.
  local P = ns.Picture
  check(P.Placeholder(7, 3, "mail") == P.Placeholders()[7][3].leather, "Gnome woman in mail: there's none, leather instead")
  check(P.Placeholder(6, 3, "plate") == P.Placeholders()[6][3].leather, "Tauren woman in plate, none on Forever: the next closest (leather)")
  check(P.Placeholder(10, 3, "robe") ~= nil, "a race Forever doesn't have still gets someone")
  -- The author shows up on a nameplate: the real body, and it stays after they leave.
  NAMEPLATE = { "Someone Else" }
  pic3:SetLook(look, "Someone Else")
  check(pic3.quality == 3 and pic3.actor._unit == "nameplate1", "the author on a nameplate: their real body")
  NAMEPLATE = {}
  pic3:SetLook(look, "Someone Else")
  check(pic3.quality == 3 and pic3.actor._unit == "nameplate1", "they walked off: still their real body")
  UnitSex = before
`);

section('Late joiner gets the latest pictures');
const C = await Player('Old Tom Cobble');
await Tick(1, 16);
await A.run('__ret = POST_ID');
const postId = A.lua.global.get('__ret');
for (const p of [B, C]) p.lua.global.set('POST_ID', postId);
await C.run(`
  local p = ns.Social.Find(POST_ID)
  check(p ~= nil, "C synced A's post on hello")
  check(p and p.caption == "Edited caption", "with the edit")
  check(ns.db.profiles["Flintar Stone"] == nil, "profiles aren't sent with the sync")
  ns.UI:Toggle()
  ns.UI:OpenPerson("Flintar Stone")
  local n = 0
  for _, q in ipairs(ns.db.posts) do if q.id == POST_ID then n = n + 1 end end
  check(n == 1, "no duplicates")
`);

await Tick(0.5, 6);
await C.run(`
  check(ns.db.profiles["Flintar Stone"] ~= nil, "opening A's profile asks A, and A answers")
  -- Asking someone who's offline: the game's "no such player" line stays out of chat.
  ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  ns.Social.AskProfile("Gone Fishing")
  check(ns.Social.OfflineFilter(nil, nil, "No player named 'Gone Fishing' is currently playing."), "offline line hidden")
  check(not ns.Social.OfflineFilter(nil, nil, "No player named 'Someone Else' is currently playing."), "others' still shown")
`);

section('Delete');
await A.run(`ns.Social.Delete(POST_ID) check(ns.Social.Find(POST_ID) == nil, "A deleted")`);
await Tick(0.5, 4);
await B.run(`check(ns.Social.Find(POST_ID) == nil, "gone for B")`);
await C.run(`check(ns.Social.Find(POST_ID) == nil, "gone for C")`);
await Tick(1, 12);
await C.run(`check(ns.Social.Find(POST_ID) == nil, "stays gone after more syncs")`);

section('Retail: Name-Realm');
const R1 = await Player('Bob', { realm: 'Silvermoon', raw: 'full', game: 'retail' });
const R2 = await Player('Bob', { realm: 'Argent Dawn', raw: 'full', game: 'retail' });
await Tick(1, 10);
await R1.run(`
  check(ns.Me() == "Bob-Silvermoon", "my id: " .. ns.Me())
  ns.Social.Post("1;pwave", "Hello from Silvermoon")
`);
await R2.run(`
  check(ns.Me() == "Bob-ArgentDawn", "realm without spaces: " .. ns.Me())
  ns.Social.Post("1;pdance", "Hello from Argent Dawn")
`);
await Tick(0.5, 6);
await R1.run(`
  local mine, theirs
  for _, p in ipairs(ns.db.posts) do
    if p.caption == "Hello from Silvermoon" then mine = p end
    if p.caption == "Hello from Argent Dawn" then theirs = p end
  end
  check(mine and theirs, "both Bobs' posts are here")
  check(theirs and theirs.author == "Bob-ArgentDawn", "the other Bob keeps his realm: " .. tostring(theirs and theirs.author))
  check(ns.Social.IsMine(mine) and not ns.Social.IsMine(theirs), "same name, other realm: not mine")
  check(ns.Display(mine.author) == "Bob" and ns.Display(theirs.author) == "Bob-ArgentDawn", "shown as Bob and Bob-ArgentDawn")
  ns.Social.Like(theirs.id, true)
  ns.Social.Follow(theirs.author, true)
  check(ns.Social.Following("Bob-ArgentDawn") and not ns.Social.Following("Bob-Silvermoon"), "follow is per realm")
  check(#ns.Social.List("Bob-ArgentDawn") == 1, "his profile has only his post")
  -- Target him: his picture switches to his real body.
  TARGET = { "Bob", "Argent Dawn" }
  check(ns.Picture.UnitFor("Bob-ArgentDawn") == "target", "target with a realm is found")
  check(ns.Picture.UnitFor("Bob-Silvermoon") == "player", "I am me")
  TARGET = { "Bob", nil }
  check(ns.Picture.UnitFor("Bob-ArgentDawn") == nil, "a Bob from my own realm is not him")
  TARGET = nil
  check(ns.db.profiles["Bob-ArgentDawn"] ~= nil, "his profile, by id")
  -- Race looks: every race and gender, newer races as their parent race.
  local P = ns.Picture
  check(P.RaceLook(4, 3) == 37919 and P.RaceLook(4, 2) == 20318, "Night Elf woman and man")
  check(not ns.FOREVER and P.Placeholders() == P.PLACEHOLDER and P.Placeholder(29, 3, "robe") == P.PLACEHOLDER[10][3].robe,
    "Retail uses the HD picks; a Void Elf woman in a robe is a Blood Elf one")
  check(P.RaceLook(29, 3) == P.RaceLook(10, 3), "a Void Elf looks like a Blood Elf")
  check(P.RaceLook(nil, nil) == 37925, "unknown: a Human man")
`);
await Tick(0.5, 6);
await R2.run(`
  local mine
  for _, p in ipairs(ns.db.posts) do if p.caption == "Hello from Argent Dawn" then mine = p end end
  check(ns.Social.Liked(mine, "Bob-Silvermoon") and ns.Social.Likes(mine) == 1, "like arrives from the other Bob")
  check(not ns.Social.Liked(mine, "Bob-ArgentDawn"), "and isn't counted as mine")
  local told = false
  for _, line in ipairs(CHAT) do if line:find("Bob%-Silvermoon") and line:find("liked") then told = true end end
  check(told, "told: Bob-Silvermoon liked it")
`);

section('Forever: no realms, two-word names');
const F1 = await Player('Ana Stormwhisper', { realm: 'Hardcore' });
const F2 = await Player('Jean-Luc Ashby', { realm: 'Normal', raw: 'full' });
await Tick(1, 10);
await F2.run(`
  check(ns.FOREVER and ns.Me() == "Jean-Luc Ashby", "my id is my name, no ruleset: " .. ns.Me())
  check(ns.Display(ns.Me()) == "Jean-Luc Ashby", "and shown whole")
  ns.Social.Post("1", "Dash test")
`);
await F1.run(`ns.Social.Post("1", "Space test")`);
await Tick(0.5, 6);
await F1.run(`
  local p
  for _, q in ipairs(ns.db.posts) do if q.caption == "Dash test" then p = q end end
  check(p and p.author == "Jean-Luc Ashby", "dash name arrives whole, sender had a suffix: " .. tostring(p and p.author))
  check(ns.Display(p.author) == "Jean-Luc Ashby", "shown whole")
  ns.Social.Comment(p.id, "Nice!")
  TARGET = { "Jean-Luc Ashby", "Normal" }
  check(ns.Picture.UnitFor(p.author) == "target", "his real body when targeted")
  TARGET = nil
`);
await Tick(0.5, 6);
await F2.run(`
  local p
  for _, q in ipairs(ns.db.posts) do if q.caption == "Space test" then p = q end end
  check(p and p.author == "Ana Stormwhisper", "space name arrives whole")
  check(ns.Display(p.author) == "Ana Stormwhisper", "shown as First Last")
  local mine
  for _, q in ipairs(ns.db.posts) do if q.caption == "Dash test" then mine = q end end
  check(#mine.comments == 1 and mine.comments[1].author == "Ana Stormwhisper", "comment author whole")
`);

section('Guild feed');
const G1 = await Player('Kael', { realm: 'Silvermoon', raw: 'full', game: 'retail', guild: 'Knights' });
const G2 = await Player('Lyra', { realm: 'Silvermoon', raw: 'full', game: 'retail', guild: 'Knights' });
const G3 = await Player('Moro', { realm: 'Silvermoon', raw: 'full', game: 'retail' });
for (const g of [G1, G2]) {
  await g.run(`GUILD_ROSTER = { "Kael-Silvermoon", "Lyra-Silvermoon" } Fire("GUILD_ROSTER_UPDATE")`);
}
await Tick(1, 10);
await G1.run(`ns.Social.Post("1;pwave", "Guild night!")`);
await G3.run(`ns.Social.Post("1;pdance", "Not in a guild")`);
await Tick(0.5, 6);
await G2.run(`
  local guildFeed, realmFeed = ns.Social.List("guild"), ns.Social.List("all")
  local inGuild, outsider = false, false
  for _, p in ipairs(guildFeed) do
    if p.caption == "Guild night!" then inGuild = true end
    if p.caption == "Not in a guild" then outsider = true end
  end
  check(inGuild and not outsider, "guild feed: guildmate yes, outsider no")
  local both = 0
  for _, p in ipairs(realmFeed) do
    if p.caption == "Guild night!" or p.caption == "Not in a guild" then both = both + 1 end
  end
  check(both == 2, "realm feed has both")
  local n = 0
  for _, p in ipairs(ns.db.posts) do if p.caption == "Guild night!" then n = n + 1 end end
  check(n == 1, "sent on realm and guild, stored once")
  ns.UI:Toggle()
  ns.UI:Show("feed")
  local fv = ns.UI.pages.feed.view
  fv.feedButtons[2]:GetScript("OnClick")(fv.feedButtons[2])
  check(fv.filter == "guild" and fv.cards[1].post and fv.cards[1].post.caption == "Guild night!", "Guild button shows the guild feed")
`);
await G3.run(`
  ns.UI:Toggle()
  ns.UI:Show("feed")
  local fv = ns.UI.pages.feed.view
  check(not fv.feedButtons[2]:IsEnabled(), "no guild, no demo: Guild button greyed out")
`);
// Guild only: guildmates get it (and its comments), the realm never does.
await G1.run(`ns.Social.Post("1;pwave", "Guild secret", nil, "guild")`);
await Tick(0.5, 6);
await G2.run(`
  local post
  for _, p in ipairs(ns.db.posts) do if p.caption == "Guild secret" then post = p end end
  check(post and post.share == "guild", "guild only: the guildmate gets it, marked guild only")
  local inRealm, inGuild = false, false
  for _, p in ipairs(ns.Social.List("all")) do if p == post then inRealm = true end end
  for _, p in ipairs(ns.Social.List("guild")) do if p == post then inGuild = true end end
  check(inGuild and not inRealm, "guild only: in the Guild feed, not the Realm feed")
  ns.Social.Comment(post.id, "Shh")
  ns.Social.Like(post.id, true)
`);
await Tick(0.5, 6);
await G1.run(`
  local post
  for _, p in ipairs(ns.db.posts) do if p.caption == "Guild secret" then post = p end end
  check(#post.comments == 1 and ns.Social.Liked(post, "Lyra-Silvermoon"), "guild only: comments and likes reach the author")
`);
// A sync answer on the realm channel leaves guild pictures out.
await G2.run(`ns.Social.Answer(0, "realm")`);
await Tick(1, 30);
await G3.run(`
  local got = false
  for _, p in ipairs(ns.db.posts) do if p.caption == "Guild secret" then got = true end end
  check(not got, "guild only: the outsider never gets it, not even from a sync")
`);
// A forged guild picture on the realm channel is dropped.
await G3.run(`ns.Net.Send("P", table.concat({ "fake1", "Moro-Silvermoon", "", "", ns.Now(), 0, "1", "Forged", "", "", "g" }, "\\031"), "realm")`);
await Tick(0.5, 6);
await G2.run(`
  check(ns.Social.Find("fake1") == nil, "a guild-only picture from the realm channel is dropped")
`);
// Create: the Guild only switch.
await G3.run(`
  ns.UI:Show("studio")
  local v = ns.UI.pages.studio.view
  check(not v.guildOnly:IsEnabled(), "no guild: Guild only greyed out")
`);
await G1.run(`
  ns.UI:Show("studio")
  local v = ns.UI.pages.studio.view
  check(v.guildOnly:IsEnabled() and not v.guildOnly:GetChecked(), "in a guild: Guild only can be switched on, off to start")
  v.guildOnly:GetScript("OnClick")(v.guildOnly)
  v.caption:SetText("From the switch")
  v.post:GetScript("OnClick")(v.post)
  local post
  for _, p in ipairs(ns.db.posts) do if p.caption == "From the switch" then post = p end end
  check(post and post.share == "guild", "Share with Guild only on: a guild-only picture")
  ns.UI:Show("studio")
  check(not v.guildOnly:GetChecked(), "Create starts fresh: Guild only off again")
`);

// The realm channel fails for both: the guild channel still carries it.
await G1.run(`ns.Net.Leave()`);
await G2.run(`ns.Net.Leave()`);
await G1.run(`ns.Social.Post("1", "Guild channel only")`);
await Tick(0.5, 6);
await G2.run(`
  local got = false
  for _, p in ipairs(ns.db.posts) do if p.caption == "Guild channel only" then got = true end end
  check(got, "guildmate gets it over the guild channel")
`);
await G3.run(`
  local got = false
  for _, p in ipairs(ns.db.posts) do if p.caption == "Guild channel only" then got = true end end
  check(not got, "outsider doesn't")
`);

section('Demo people');
const D = await Player('Demo Tester', { demo: true });
await Tick(1, 10);
await D.run(`
  local bots = 0
  for _, p in ipairs(ns.db.posts) do if p.bot then bots = bots + 1 end end
  check(bots >= 5, "demo posts seeded: " .. bots)
  ns.UI:Toggle()
  ns.UI:Show("feed")
  local fv = ns.UI.pages.feed.view
  local sc = fv.scroll
  local first = fv.list[1]
  check(fv.cards[1]:IsShown() and fv.cards[1].post == first, "the wall starts with the newest post")
  -- The wheel scrolls the wall (smoothly: it glides to where the wheel says).
  sc.view:GetScript("OnMouseWheel")(sc.view, -1)
  check(sc.target == 140 and sc.offset == 0, "wheel sets where to glide to")
  sc:ScrollTo(sc.target, true)
  check(sc.offset == 140, "and the wall moves")
  -- The wheel over a picture scrolls too; it doesn't zoom someone's picture.
  local pic1 = fv.cards[1].pic
  local zoom = pic1.look.zoom
  pic1:GetScript("OnMouseWheel")(pic1, -1)
  check(sc.target == 280 and pic1.look.zoom == zoom, "wheel over a picture scrolls the wall, no zoom")
  -- Dragging someone's picture doesn't turn it.
  local yaw = pic1.look.yaw
  CURSOR_X = 0
  pic1:GetScript("OnMouseDown")(pic1, "LeftButton")
  check(pic1:GetScript("OnUpdate") == nil, "no turning someone else's picture")
  pic1:GetScript("OnMouseUp")(pic1, "LeftButton")
  check(pic1.look.yaw == yaw, "shown as posted")
  sc:ScrollTo(140, true)
  -- Further down, rows are reused for later posts.
  local ROW = ns.Feed.CARD_H + 26
  sc:ScrollTo(108 + 2 * ROW, true)
  local third
  for _, row in ipairs(sc.rows) do if row:IsShown() and row.index == 3 then third = row end end
  check(third and third.card.post == fv.list[3], "scrolled down: the third post is in a row")
  -- A post half out of view: its 3D picture is cut to the part you see.
  sc:ScrollTo(108 + 42 + 200, true)
  local r1
  for _, row in ipairs(sc.rows) do if row.index == 1 then r1 = row end end
  local pic = r1.card.pic
  check(pic.cropTop == 200 and pic.cropBottom == 0, "top 200 px cut off: " .. tostring(pic.cropTop))
  check(pic.scene._points.TOPLEFT and pic.scene._points.TOPLEFT[3] == -200, "scene starts below the cut")
  Pump(pic.scene, 0.5)
  check(pic.scene._fov and pic.scene._fov < 0.62, "narrower lens for the visible part: " .. tostring(pic.scene._fov))
  sc:ScrollTo(108 + ROW * 3, true)
  check(not r1.card.pic.scene:IsShown() or r1.index ~= 1, "fully scrolled away: no 3D drawn")
  sc:Top()
  check(sc.offset == 0, "back to the top")
  -- Stories: demo people who posted today, unseen first, with a ring.
  local st = ns.Social.Stories()
  check(#st >= 2 and fv.stories[2]:IsShown(), "stories row: " .. #st)
  -- Save, and Saved on the profile.
  fv.cards[1].save:GetScript("OnClick")(fv.cards[1].save)
  check(ns.Social.Saved(first.id) and #ns.Social.List("saved") == 1, "bookmark saves it")
  ns.UI:Show("profile")
  local pv = ns.UI.pages.profile.view
  pv.tabs.buttons[2]:GetScript("OnClick")(pv.tabs.buttons[2])
  check(pv.tab == "saved" and pv.thumbs[1].post == first, "Saved tab shows it")
  -- Suggested for you: demo people you don't follow yet.
  ns.UI:Show("feed")
  check(fv.suggest[1]:IsShown() and fv.suggest[1].who ~= nil, "suggestions")
  local who = fv.suggest[1].who
  fv.suggest[1].follow:GetScript("OnClick")(fv.suggest[1].follow)
  check(ns.Social.Following(who), "Follow from the suggestions")
  local gl = ns.Social.List("guild")
  check(#gl >= 2, "demo guildmates fill the guild feed: " .. #gl)
  local valor = false
  for _, q in ipairs(ns.db.posts) do
    local s1 = q.author == "Thrag Ironhide" and ns.Look.Decode(q.look).slots[1]
    if s1 and s1.item == 16731 then valor = true end
  end
  check(valor, "on Forever, demo people wear dungeon sets (Helm of Valor)")
  for _, p in ipairs(gl) do check(ns.Bots.InGuild(p.author), "only demo guildmates in it") end
  ns.UI:Show("studio")
  ns.Studio.Post()
  MY_POST = ns.db.posts[1].id
`);
await Tick(2, 25);
await D.run(`
  local p = ns.Social.Find(MY_POST)
  check(ns.Social.Likes(p) >= 2, "demo people like your picture: " .. ns.Social.Likes(p))
  check(#p.comments >= 1, "and comment")
  check(#ns.my.activity >= 3 and (ns.my.unread or 0) >= 3, "notifications logged: " .. #ns.my.activity)
  ns.UI:Show("activity")
  local av = ns.UI.pages.activity.view
  check(ns.my.unread == 0 and av.list.rows[1]:IsShown(), "Notifications page lists them and clears the count")
  av.list.rows[1]:GetScript("OnMouseUp")(av.list.rows[1])
  check(ns.UI.tab == "post" and ns.UI.arg == MY_POST, "a notification opens the picture")
  local bot = nil
  for _, q in ipairs(ns.db.posts) do if q.bot then bot = q break end end
  ns.Social.Comment(bot.id, "Nice!")
  ns.Bots.Reply(bot)
`);
await Tick(2, 10);
await D.run(`
  local bot = nil
  for _, q in ipairs(ns.db.posts) do if q.bot then bot = q break end end
  check(bot.comments[#bot.comments].author == bot.author, "the demo person answers")
  ns.Bots.SetEnabled(false)
  for _, q in ipairs(ns.db.posts) do check(not q.bot, "demo posts removed") end
  local p = ns.Social.Find(MY_POST)
  check(ns.Social.Likes(p) == 0 and #p.comments == 0, "their likes and comments removed")
`);
for (const p of [A, B, C]) {
  await p.run(`
    local leaked = false
    for _, q in ipairs(ns.db.posts) do if ns.Bots.Is(q.author) then leaked = true end end
    check(not leaked, "no demo posts reached other players")
  `);
}

section('Scale: a login with many people online');
{
  const crowd = [];
  for (let i = 1; i <= 8; i++) crowd.push(await Player(`Crowd Member${i}`, { realm: 'Forever' }));
  await Tick(1, 8);
  for (const [i, p] of crowd.entries()) await p.run(`ns.Social.Post("1;pdance", "crowd ${i + 1}")`);
  await Tick(1, 10);
  const late = await Player('Late Arrival', { realm: 'Forever' });
  await late.run(`
    RELAYERS, RELAYS = {}, 0
    local receive = ns.Net.Receive
    ns.Net.Receive = function(raw, msg, ct)
      local cmd, said, rest = msg:match("^(%w+):%d+:%d+/%d+@([^:]*):(.*)$")
      local US = string.char(31)
      local author = rest and rest:match("^[^" .. US .. "]*" .. US .. "([^" .. US .. "]*)")
      if cmd == "P" and author and author ~= said then
        RELAYERS[raw] = true
        RELAYS = RELAYS + 1
      end
      return receive(raw, msg, ct)
    end
  `);
  await Tick(0.5, 60);
  await late.run(`
    local n = 0
    for _ in pairs(RELAYERS) do n = n + 1 end
    local got = 0
    for _, p in ipairs(ns.db.posts) do if p.caption:find("^crowd") then got = got + 1 end end
    check(got == 8, "the newcomer got every recent picture: " .. got)
    check(n >= 1 and n <= 3, "only a few of the 8+ online answered: " .. n)
  `);
  for (const p of crowd) players.splice(players.indexOf(p), 1);
  players.splice(players.indexOf(late), 1);
}

section('Scale: spam, oversized, caps, redraws');
{
  const S1 = await Player('Spam Bot', { realm: 'Forever' });
  const S2 = await Player('Patient Reader', { realm: 'Forever' });
  await Tick(1, 8);
  await S1.run(`for i = 1, 30 do ns.Social.Post("1", "spam " .. i) end`);
  await Tick(0.2, 5);
  await S2.run(`
    local got = 0
    for _, p in ipairs(ns.db.posts) do if p.caption:find("^spam") then got = got + 1 end end
    check(got <= ns.Social.RATE.post, "a burst of 30 posts from one sender: only " .. got .. " kept")
    check(ns.Net.dropped > 0, "the rest dropped and counted")
    -- Oversized and never-finished messages.
    local before = ns.Net.dropped
    ns.Net.Receive("Spam Bot", "P:1:1/99@Spam Bot#" .. ns.Net.PROTO .. ":x", "CHANNEL")
    check(ns.Net.dropped == before + 1, "a message in 99 parts is refused")
    ns.Net.Receive("Spam Bot", "P:2:1/2@Spam Bot#" .. ns.Net.PROTO .. ":" .. string.rep("x", 200), "CHANNEL")
    Advance(40)
    ns.Net.Receive("Spam Bot", "P:3:1/2@Spam Bot#" .. ns.Net.PROTO .. ":y", "CHANNEL")
    -- Protocol: another number is ignored; a newer one tells you once.
    CHAT = {}
    local d = ns.Net.dropped
    ns.Net.Receive("Future Self", "L:4:1/1@Future Self#" .. (ns.Net.PROTO + 1) .. ":x", "CHANNEL")
    ns.Net.Receive("Future Self", "L:5:1/1@Future Self#" .. (ns.Net.PROTO + 1) .. ":x", "CHANNEL")
    ns.Net.Receive("Old Timer", "L:6:1/1@Old Timer:x", "CHANNEL")
    check(ns.Net.dropped == d + 3, "other protocols and no protocol are ignored")
    local told = 0
    for _, line in ipairs(CHAT) do if line:find("newer Wowstagram") then told = told + 1 end end
    check(told == 1, "told once about a newer version")
    -- A newer but compatible version may add fields at the end: still understood.
    local before = #ns.db.posts
    ns.Net.Receive("Kind Stranger", "P:7:1/1@Kind Stranger#" .. ns.Net.PROTO .. ":" .. table.concat({ "zz1", "Kind Stranger", "MAGE", "1",
      tostring(ns.Now()), "0", "1", "hello from the future", "", "", "a new field", "another" }, string.char(31)), "CHANNEL")
    local p = ns.Social.Find("zz1")
    check(p and p.caption == "hello from the future" and #ns.db.posts == before + 1, "extra fields at the end are ignored")
    check(true, "half-finished messages are swept after a while")
    -- Who a message is from: the name in it only when it's exactly the sender.
    local from
    ns.Net.On("Z", function(sender) from = sender end)
    local function SaidBy(raw, said)
      from = nil
      ns.Net.Receive(raw, "Z:" .. math.random(9999) .. ":1/1@" .. said .. "#" .. ns.Net.PROTO .. ":x", "CHANNEL")
      return from
    end
    check(SaidBy("Best Friend", "Best Friend") == "Best Friend", "the sender's own name is taken")
    check(SaidBy("Best Friends", "Best Friend") ~= "Best Friend", "a longer name can't pose as a shorter one")
    check(SaidBy("Best", "Best Friend") ~= "Best Friend", "nor a shorter one as a longer one")
    check(SaidBy("BEST FRIEND", "Best Friend") ~= "Best Friend", "nor another spelling")
    check(SaidBy("Best Friend", "Best|Friend") ~= "Best|Friend", "a broken name is never taken")
    -- Unfinished long messages: only a few per sender at a time.
    local d0 = ns.Net.dropped
    for k = 1, ns.Net.MAX_OPEN + 3 do
      ns.Net.Receive("Slow Sender", "P:" .. (500 + k) .. ":1/2@Slow Sender#" .. ns.Net.PROTO .. ":x", "CHANNEL")
    end
    check(ns.Net.dropped == d0 + 3, "more unfinished messages than allowed are refused")
    -- Text from others: no "|" codes.
    ns.Net.Receive("Kind Stranger", "P:8:1/1@Kind Stranger#" .. ns.Net.PROTO .. ":" .. table.concat({ "zz2", "Kind Stranger", "MAGE", "1",
      tostring(ns.Now()), "0", "1", "|cffff0000red|r |Hitem:1|hlink|h", "", "" }, string.char(31)), "CHANNEL")
    local p2 = ns.Social.Find("zz2")
    check(p2 and not p2.caption:find("|", 1, true), "colour and link codes are taken out of captions")
    -- Saved pictures survive the limits; unsaved ones get a week's grace.
    local S = ns.Social
    local keepSaved, keepSlip, goOld = { id = "keep1", author = "Old Friend", t = ns.Now() - 12 * 86400, likes = {}, comments = {} },
      { id = "keep2", author = "Old Friend", t = ns.Now() - 11 * 86400, likes = {}, comments = {} },
      { id = "go1", author = "Old Friend", t = ns.Now() - 10 * 86400, likes = {}, comments = {} }
    for _, p in ipairs({ keepSaved, keepSlip, goOld }) do table.insert(ns.db.posts, p) end
    S.Save("keep1", true)
    S.Save("keep2", true)
    S.Save("keep2", false)
    S.Follow("Followed Fiona", true)
    S.Store({ id = "fol1", author = "Followed Fiona", t = 5, likes = {}, comments = {} })
    for i = 1, S.MAX_POSTS + 5 do S.Store({ id = "fill" .. i, author = "Filler " .. (i % 400), t = ns.Now() - i, likes = {}, comments = {} }) end
    check(S.Find("keep1") ~= nil, "a saved picture is never pruned")
    check(S.Find("fol1") ~= nil, "nor an old picture by someone you follow: strangers can't push it out")
    check(S.Find("keep2") ~= nil, "unsaved a moment ago: still kept, so saving it again works")
    check(S.Find("go1") == nil, "an old picture nobody saved goes")
    Advance(S.UNSAVE_GRACE + 10)
    S.Store({ id = "fill-last", author = "Filler 1", t = ns.Now(), likes = {}, comments = {} })
    check(S.Find("keep2") == nil and ns.db.unsaved["keep2"] == nil, "a week after unsaving: it can go")
    check(S.Find("keep1") ~= nil, "still saved: still kept")
    -- Deletions remembered: at most S.MAX_TOMBS.
    for i = 1, 700 do ns.db.tombs["p:old" .. i] = ns.Now() - i end
    ns.Social.Post("1", "trigger a prune")
    local n = 0
    for _ in pairs(ns.db.tombs) do n = n + 1 end
    check(n <= ns.Social.MAX_TOMBS, "deletions capped: " .. n)
    -- Redraws: 50 changes in a second make only a few redraws.
    local redraws = 0
    ns.OnChange(function() redraws = redraws + 1 end)
    Advance(1)
    redraws = 0
    for i = 1, 50 do
      ns.Changed()
      Advance(0.02)
    end
    Advance(0.5)
    check(redraws >= 2 and redraws <= 6, "50 changes in a second: " .. redraws .. " redraws")
    -- /wgram stats prints without trouble (development commands on).
    CHAT = {}
    SlashCmdList.WOWSTAGRAM("stats")
    check(#CHAT == 2 and CHAT[2]:find("/wgram demo", 1, true), "development commands are off: just the help")
    ns.DEV = true
    CHAT = {}
    SlashCmdList.WOWSTAGRAM("stats")
    check(#CHAT == 3 and CHAT[1]:find("messages in"), "stats: " .. tostring(CHAT[1]))
  `);
  players.splice(players.indexOf(S1), 1);
  players.splice(players.indexOf(S2), 1);
}

section('Vouching: made-up things are found out');
await B.run(`
  ns.Social.SetNetwork(true)
  local mine = ns.Social.Post("1;pwave", "Real one")
  MINE_ID = mine.id
`);
await Tick(0.5, 6);
const F = await Player('Forger Fred');
await Tick(1, 8);
await B.run(`MINE_ID_STR = MINE_ID`);
const mineId = await B.lua.doString('return MINE_ID');
await F.run(`
  local US = string.char(31)
  local now = ns.Now()
  -- A made-up picture "by" Flintar Stone.
  ns.Net.Send("P", table.concat({ "fake1", "Flintar Stone", "", "", tostring(now), "0", "1", "I love murlocs", "", "" }, US), "realm")
  -- Mira's real picture passed on, with a made-up like in Flintar's name.
  ns.Net.Send("P", table.concat({ "${mineId}", "Mira Dawnfeather", "", "", tostring(now - 5), "0", "1;pwave", "Real one",
    "Flintar Stone=" .. now, "" }, US), "realm")
`);
await Tick(0.5, 6);
await B.run(`
  local fake = ns.Social.Find("fake1")
  check(fake and fake.unv, "a passed-on picture shows at once, unconfirmed")
  local mine = ns.Social.Find(MINE_ID)
  check(ns.Social.Liked(mine, "Flintar Stone") and mine.likeUnv and mine.likeUnv["Flintar Stone"], "the made-up like shows too, unconfirmed")
  ns.Social.CheckTick()
`);
await Tick(0.5, 10);
await B.run(`
  check(ns.Social.Find("fake1") == nil and ns.db.tombs["p:fake1"], "Flintar's addon says it isn't his: gone for good")
  check(not ns.Social.Liked(ns.Social.Find(MINE_ID), "Flintar Stone"), "and the like he never gave is gone")
  local st = ns.db.strikes["Forger Fred"]
  check(st and st.n >= 4 and not ns.Social.ShutOut("Forger Fred"), "the forger has strikes (" .. (st and st.n or 0) .. "), not shut out yet")
  -- A fake about someone who's never online with Mira: it waits for its check...
  ns.Net.Receive("Forger Fred", "P:98:1/1@Forger Fred#" .. ns.Net.PROTO .. ":" .. table.concat({ "fake2", "Never Online", "", "",
    tostring(ns.Now()), "0", "1", "I said something awful", "", "" }, string.char(31)), "CHANNEL")
  check(ns.Social.Find("fake2") and ns.Social.Find("fake2").unv, "a fake about someone who's never on: it waits")
  ns.Social.Strike("Forger Fred", 2, "test")
  check(ns.Social.ShutOut("Forger Fred") and ns.Social.Blocked("Forger Fred"), "a few more: shut out and blocked")
  check(ns.Social.Find("fake2") == nil, "...and goes the moment its forger is caught out, without asking its owner")
  local before = #ns.db.posts
  ns.Net.Receive("Forger Fred", "P:99:1/1@Forger Fred#" .. ns.Net.PROTO .. ":" .. table.concat({ "ff1", "Forger Fred", "", "",
    tostring(ns.Now()), "0", "1", "hi", "", "" }, string.char(31)), "CHANNEL")
  check(#ns.db.posts == before, "nothing of theirs is listened to")
  ns.Social.Block("Forger Fred", false)
  check(not ns.Social.ShutOut("Forger Fred") and ns.db.strikes["Forger Fred"] == nil, "Unblock: a clean slate")
`);
await A.run(`
  check(ns.Social.Find("fake1") == nil, "Flintar's own addon never took a picture of his he didn't post")
`);

section('Profile bio');
await B.run(`
  ns.UI:Show("profile")
  local v = ns.UI.pages.profile.view
  v.editButton:GetScript("OnClick")(v.editButton)
  check(v.editing and v.bioBox:IsShown(), "Edit profile opens the bio box")
  v.bioBox:SetText("Mage by day, murloc by night")
  v.editButton:GetScript("OnClick")(v.editButton)
  check(ns.my.me.bio == "Mage by day, murloc by night" and not v.editing, "Done saves the bio")
`);
await Tick(0.5, 6);
await A.run(`
  local prof = ns.db.profiles["Mira Dawnfeather"]
  check(prof and prof.bio == "Mage by day, murloc by night", "and others get it")
`);

section('Safety: bad names, codes, ids and dates are refused');
await B.run(`
  local US = string.char(31)
  local now = ns.Now()
  local before = #ns.db.posts
  local function P(id, author, class, caption, likes, comments, t)
    ns.Net.Receive("Evil Eve", "P:" .. math.random(9999) .. ":1/1@Evil Eve#" .. ns.Net.PROTO .. ":" .. table.concat({ id, author, class or "",
      "", tostring(t or now), "0", "1", caption or "x", likes or "", comments or "" }, US), "CHANNEL")
  end
  P("bad1", "|TInterface/Icons/x:64|t Boss")
  P("bad2", "Nice Name", "|cffff0000HACKER")
  P("bad id!", "Nice Name")
  P("ok1", "Real Person", "MAGE", "fine", "|Hitem:1|h[x]|h=" .. now)
  check(ns.Social.Find("bad1") == nil and ns.Social.Find("bad id!") == nil, "a name with codes, or a bad id: refused")
  local b2 = ns.Social.Find("bad2")
  check(b2 == nil or b2.class == nil, "a made-up class is dropped")
  local ok1 = ns.Social.Find("ok1")
  local hacked = false
  for name in pairs(ok1 and ok1.likes or {}) do if name:find("|", 1, true) then hacked = true end end
  check(ok1 and not hacked, "a liker's name with codes is dropped")
  ns.Net.Receive("Evil Eve", "C:" .. math.random(9999) .. ":1/1@Evil Eve#" .. ns.Net.PROTO .. ":" .. table.concat({ "ok1", "Evil Eve", "",
    tostring(now + 99999), "0", "from the future" }, US), "CHANNEL")
  local future = false
  for _, c in ipairs(ok1.comments) do if c.text == "from the future" then future = true end end
  check(not future, "a comment from the future: refused")
  check(ns.Look.Decode("1;qn|cff00ff00Fake/r1").people[1].name == nil, "a group picture's name with codes: dropped")
  check(ns.Plain("a|cffffffffb") == "a||cffffffffb", "chat lines double the |")
  -- A made-up deletion of a picture Mira doesn't have yet...
  ns.Net.Receive("Evil Eve", "D:" .. math.random(9999) .. ":1/1@Evil Eve#" .. ns.Net.PROTO .. ":" .. "alive1" .. US .. tostring(now), "CHANNEL")
  check(ns.db.tombs["p:alive1"] == nil and ns.db.softTombs["p:alive1"], "a deletion of a picture you don't have: only provisional")
  -- ...then the picture arrives from its author: alive, and the deleter caught.
  local st0 = (ns.db.strikes["Evil Eve"] or {}).n or 0
  ns.Net.Receive("Real Person", "P:" .. math.random(9999) .. ":1/1@Real Person#" .. ns.Net.PROTO .. ":" .. table.concat({ "alive1", "Real Person", "",
    "", tostring(now), "0", "1", "still here", "", "" }, US), "CHANNEL")
  check(ns.Social.Find("alive1") ~= nil, "the picture still arrives")
  check(((ns.db.strikes["Evil Eve"] or {}).n or 0) > st0, "and whoever made up its deletion gets strikes")
`);

section('Sharing off');
await B.run(`
  ns.Social.SetNetwork(false)
  check(not ns.Net.Online(), "left the channel")
  ns.Social.Post("1", "private")
  check(#OUTBOX == 0, "nothing sent")
`);

section('Clear everything');
await D.run(`
  ns.Social.Follow("Someone Else", true)
  ns.ResetAll()
  check(#ns.db.posts == 0 and next(ns.my.following) == nil, "cleared")
  check(ns.db.demo == false and ns.db.network == true, "switches kept")
`);

// Globals: only the ones an addon needs.
{
  const allowed = new Set(['WowstagramDB', 'SLASH_WOWSTAGRAM1', 'SLASH_WOWSTAGRAM2', 'WowstagramMinimapButton',
    'WowstagramScreenshot', 'WowstagramWall']);
  const found = new Map();
  for (const p of players) {
    await p.run(`__GL = {} for k, src in pairs(__ADDON_GLOBALS) do table.insert(__GL, k .. " (" .. src .. ")") end`);
    const list = p.lua.global.get('__GL') || [];
    for (const entry of Object.values(list)) found.set(entry.split(' ')[0], entry);
  }
  const stray = [...found.keys()].filter(k => !allowed.has(k));
  console.log('Addon globals: ' + ([...found.keys()].join(', ') || 'none'));
  if (stray.length === 0) passes++; else { failures++; console.log('  FAIL stray globals: ' + stray.map(k => found.get(k)).join(', ')); }
}

console.log(`\n${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
