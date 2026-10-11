# Wowstagram developer notes

Not shipped (`.pkgmeta` ignores `dev/`).

## Working on it

- Tests: `node dev/run.mjs` runs simulated players offline (wasmoon + `dev/mock.lua`).
- Art: `python dev/make_art.py` draws everything in `Art/` and `dev/media/icon.png` (the CurseForge icon).
- Release: `python dev/release.py` builds `dev/release/Wowstagram-<version>.zip`.
- Picture string: `Core\Look.lua` (`Look.Encode` / `Look.Decode`), for example `1;r1;g2;cWARRIOR;pdance;belwynn;xnoir;s1=a2lrk,5=a2lrn`. Slot values are transmog appearance sources (`a<source>.<secondary>.<illusion>`) or plain item IDs (`i<item>`), in base 36.
- Drawing: `UI\Picture.lua` (a ModelScene: `SetModelByUnit`, `Undress`, `SetItemTransmogInfo` / `TryOn`), effects `UI\Fx.lua`, stickers/text/frames/face filters `UI\Decor.lua`.
- Wire: `Core\Net.lua` (from Flintar's Fun 'n' Games: chunks, the send limit, two-word names), messages in `Core\Social.lua`.

### Development commands

They only work with `ns.DEV = true` in `Core\Init.lua` (never in a release):

| Command | What it does |
| --- | --- |
| `/wgram reset` | Move the window back to the middle of the screen |
| `/wgram stats` | Traffic over the last minute, people online, and anything dropped |
| `/wgram debug` | Print addon messages sent and received |
| `/wgram wall` | Every race, men and women, side by side: Full / Waist up / Face, outfits, poses, and Tune faces (place the face filters by hand; saved, to fit `P.FACE_MODEL` again) |
| `/wgram cvars <word>` | Game settings with that word in their name, and their values |

## Architecture

| File | Role |
| --- | --- |
| `Core\Init.lua` | Namespace, event bus, change bus (`ns.Changed()` → one redraw), saved variables, slash command |
| `Core\Net.lua` | Addon messages. Copied from Flintar's Fun 'n' Games: chunks, the per-prefix send limit, sender names from the message (two-word Forever names). Realm channel `WowstagramRealm`, prefixes `Wowstagram`, `Wowstagram2`..`4` |
| `Core\Look.lua` | What a picture is: the look table, its string, and the slot, pose, framing and filter lists |
| `Core\Social.lua` | Posts, likes, comments, follows, profiles, the hello and sync, and tombstones |
| `Core\Bots.lua` | Demo people (local only, `post.bot = true`) |
| `UI\Picture.lua` | The 3D picture widget. Also has the item helpers (slot for an item, icon, equipped) |
| `UI\Widgets.lua` | The look: colours (`W.C`, Instagram's dark theme), fonts (`W.Font`, `W.Text`; the logo uses `Fonts\MORPHEUS.TTF`), `W.Rounded` (nine slices of `Art\Round`), `W.Flat` buttons (primary, secondary, light, link, plain, danger), `W.Glyph` icon buttons, `W.Avatar` (with story ring), `W.Input`, `W.Toggle`, `W.Tabs`, `W.Menu` |
| `UI\Main.lua` | The WoW window with the logo beside the portrait; a black content area; the sidebar; navigation (`UI:Show(key, arg)`; the `post` and `person` pages have Back). Page size: `UI.MAIN_W` x `UI.MAIN_H` |
| `UI\Feed.lua` (Home), `Studio.lua` (Create), `Post.lua`, `Profile.lua`, `Activity.lua` (Notifications), `Settings.lua`, `Minimap.lua` | The pages |

Pages only draw. All state lives in `ns.db`, and `ns.Changed()` redraws the page that is showing.

## Wire messages

Everything goes out on two scopes: the realm channel and `GUILD` (`Net.Send(cmd, data, scope)`; `Send` in Social.lua does both). Doubles are ignored on arrival. The Guild feed is the posts whose author is on your guild roster (`S.RefreshGuild` on `GUILD_ROSTER_UPDATE`).

Fields are separated by `\031`, which nobody can type.

| Cmd | Data | Notes |
| --- | --- | --- |
| `P` | id, author, class, race, t, edited, look, caption, likes (`name=t,...`), comments | A new post, an edit, or a sync. Likes are merged by the latest time. In a sync, field 10 carries the post's latest 20 comments (`authorclassteditedtext`, joined by `9`). |
| `C` | postId, author, class, t, edited, text | A comment. Comments are keyed by (author, t). |
| `L` | postId, name, t | A like if t > 0, an unlike if t < 0. The bigger \|t\| wins. |
| `D` | postId, deletedAt | Delete a post. Stored as a tombstone `p:<id>`. |
| `X` | postId, author, t, deletedAt | Delete a comment. Stored as a tombstone `c:<id>:<author>:<t>`. |
| `R` | class, race, level, guild, bio, t | A profile. The sender is the owner. Sent at your own hello, and by whisper when someone asks. |
| `Q` | (nothing) | A whisper: "send me your profile" (on opening someone's profile). If they're offline, the game's "No player named..." line for that name is filtered out of chat. |
| `H` | newest post time | Hello, sent on both scopes and answered on the scope it came from. Only a few answer: each does so with a chance of `S.ANSWERERS / Net.Peers(600)`, after 2–12 s. Anyone else waits 15–20 s as a backstop. Whoever hears another's relay (a `P` whose author isn't its sender) after the hello stays quiet. An answer is up to 15 posts from 2 days before that time onwards (comments inside) and up to 20 recent tombstones. |

## Staying light with many users

- **Sync:** see `H` above. A login costs about one answer, not one per person online.
- **Limits per sender per minute** (`S.RATE`, checked with `Net.Allow`): 6 own posts, 60 relayed posts, 20 comments, 40 likes, 30 deletes, 6 profiles, 4 hellos, 6 profile asks. Anything over is dropped and counted.
- **Size:** at most 24 parts and 5000 bytes per message, and a picture string of at most 800 characters. Half-finished messages are forgotten after 30 s.
- **Caps:** 300 posts (40 per author), 500 tombstones, 1000 profiles, 100 notifications, and the sync's memory of recent posts.
- **Redraws:** at most 4 a second (`ns.REDRAW_GAP`). Your own likes draw at once.
- **`/wgram stats`:** messages and KB in and out over the last minute, people heard from in 10 minutes, the send queue, and what was dropped.

## Conventions

- **Player ids** (`Core\Init.lua`): on Retail, `name .. "-" .. realm`, where the realm is normalized (no spaces or dashes), for example `Bob-ArgentDawn`. On Forever (`ns.FOREVER`: interface version under 100000, which is 16001 there and 120100 on Retail) the id is just the name, `First Last`, because Forever has no realms, only rulesets, and whatever `GetRealmName` returns there is ignored. Build ids from parts (`ns.Id(name, realm)`, `ns.UnitId(unit)`). Never cut a name at a space, and never at its first dash: a name may contain either. The only split is at the LAST dash, because realms have none. Senders write their own id into every message, so we never have to take WoW's sender string apart. Show names with `ns.Display(id)` / `ns.ColorName`: there's no realm for your own realm.
- Pictures never go inside scroll frames: 3D models don't clip there. Pages that show pictures turn pages instead of scrolling.
- Set a model again whenever it comes into view (`OnShow`) and after a scale change (`Picture.RefreshAll`).
- Only M2 models in model frames. A WMO file id crashes the client. We only use player actors, but keep this in mind for backgrounds.
- Grey out buttons that aren't usable; don't hide them or make them glow. Use switches that can be flipped back, not one-off prompts.

## Tests

`node dev/run.mjs` runs eight simulated players: Forever-style ones (two-word names, a dash in a name, WoW's sender with or without the realm) (the mock's `GetRealmName` returns a ruleset name, which must not end up in ids) and Retail ones (two Bobs on different realms, with `Name-Realm` senders and targets) on one clock, passing channel messages between them. It covers the look string, the pages, the selfie, dressing up (click, drop, shift-click, uncached and unknown items), posting, likes, comments, edits, follows, a late joiner's sync, deletes, demo people (who must never leak), sharing off, and Clear everything.

Background art is the game's own, by file id (`Core\Look.lua`): classic Dressing Room backdrops (four pieces, layout from Blizzard's classic `DressUpFrames.xml`: 256x255, 62x255, 256x128, 62x128) and classic loading screens (4:3, the middle 60% is shown). The ids come from the community listfile (github.com/wowdev/wow-listfile) and are classic-era only, so every client has them.

`dev/make_art.py` makes all of `Art\`: line icons (white, coloured in the addon), `Round` and `Pill` shapes, `Circle`, and the gradient story `Ring`.

## Lessons

- **Forever's game data is classic-era** (2026-10-09): it has no HD-baked NPC looks, and no creature display ids from later expansions (37919, 62890, ... don't load there). Forever uses `P.PLACEHOLDER_CLASSIC` (picked from wago.tools' `wow_classic_era` tables, the closest public data, since Forever's own build isn't on wago). A look the client lacks loads nothing, so always `ClearModel()` first or the last model stays.

- **Face filters** (2026-10-10): no face tracking exists; `pic:Heads()` projects each head from what Fit knows: `pic.cam` (where the camera looks, its half view height `d * tan(FOV/2)`, without the crop) and the body's height (measured, or `P.RaceHeight` for look-alikes and extras; `P.HeadSize(race, "face")` for big heads). Screen right is world +y. Turned heads shift the face parts by sin(yaw); turned away (cos < 0.3), creatures, upside-down and moving lenses get none. Animations (bob, orbit, rise, drip) run from Fx's OnUpdate via `Fx.Kick`. Poses that move the head (dance, kneel) leave the parts where a standing head would be.
- **Per character** (2026-10-10): `ns.my` = `WowstagramDB.chars[id]` holds me (bio), following, activity, unread, myComments, myLikes, since, forgotBefore (`ns.LoadCharacter`). The rest is account-wide. The old account-level copies go to the character who authored pictures here (or the first to log in if nobody did): `charsClaimed`. Your own profile is also written to `profiles[Me]` (`S.KeepOwnProfile`, at login and on bio change) so your other characters see it.
- **Safety audit** (2026-10-10): names from the network go through `ns.ValidName` (2-64 bytes, no control chars, no `|,=;:`, no edge or double spaces): authors, commenters, likers, group picture names (Look decode), X authors. Ids: `S.ValidId` (`^%w+$`, <= 24). Classes: `ns.ValidClass` (capitals, a real class). Profile guild cleaned and capped, level clamped. Comments and deletion times from the future refused/clamped. Shown text: `Feed.Rich` (captions, comments, bios, notifications), `ns.Plain` (chat lines, Save to computer). Deletions for things you don't have go to `softTombs` (never passed on; a later arrival from the owner, or the owner vouching, strikes their sender). Check requests: at most 40 items, at most 5 follow-ups. Capped: myComments/myLikes (3000), seen (only existing pictures), strikes (dropped after 7 days unless shut out), users (3000), met (500).
- **Vouching** (2026-10-10): relayed pictures, comments and likes (author/liker != sender) are stored with `unv` / `likeUnv[name]` and queued (`S.Check`) for their owner; `S.CheckTick` (every 15 s, two people at a time, 40 items each) whispers V; the owner answers W per item: 1 mine, 0 not mine (dropped, tombstoned, sender of the fake gets 2 strikes), D deleted (dropped, no blame), 2 mine but changed (dropped; the real one is whispered after), 3:<t> my like as it is, ? can't say (from before `ns.db.since` / `forgotBefore`). Owners answer from `ns.db.posts` (own posts are never pruned), `myComments` (fingerprints) and `myLikes`. Unconfirmed things are never passed on (SendAnswer, CommentsString, LikesString skip them), so a denied item was invented by whoever sent it. Things "by you" that you didn't make are refused on arrival (3 strikes). `S.Strike`: points fade one a day; at 6 the sender is blocked and `Net.Ignored` drops all their messages; Unblock clears it. Each unconfirmed thing remembers who passed it on (`unvFrom`, `likeUnv[name] = sender`); when that sender is shut out, `S.Purge` removes everything still unconfirmed they delivered, so a fake about someone never online with you goes as soon as its forger is caught through anyone else. The remaining gap: a forger who only ever fakes people who are never online with you is caught only when one of them is.
- **Dislikes are anonymous** (2026-10-10): kept and sent under `S.Anon(name)` (two salted djb2 hashes in base 36), never the name; a received N is only taken if its code is `S.Anon(sender)`. No notification. Blocked people's dislikes are left out by hashing the blocked names.
- **Recently met**: `S.ReadRecentlyMet` reads `C_RecentAllies.GetRecentAllies()` (Retail's Recent Allies) defensively at login and on RECENT_ALLIES_CACHE_UPDATE. Forever's "Recently met" may use another API: find it with ns.DEV on.
- **Feed ranking** (2026-10-10): `S.Feed()` for the Realm tab: score = closeness / (1 + age in hours / 18) * (1 + 0.15 log(1 + likes)); closeness: friend 4 (C_FriendList, BNet game accounts), following 3, guild 2, seen lately 1-1.8 (`ns.db.met`, from nameplates, target, mouseover, group, say/yell/party/raid/whisper; decays over 3 days; capped at 500), else 1 (you too). Strangers' pictures older than 3 days are left out unless the feed has under 10. Guild and Following stay newest first. Captions and comments are shown through `Feed.Rich`: `|` doubled (no one's codes run), `#tag` and `@mention` as |Hwgtag:|h / |Hwgperson:|h links (frames with `Feed.Linkable`). A new caption or comment from its author mentioning you adds a "mention" notification.
- **Face model** (2026-10-10): one placement per framing didn't carry over (a hunched head sits forward, so a close-up magnifies it and pushes it off-centre). Tune faces kept, per race/sex/framing, the camera (`half`, `camz`, `camy`), the body (`z1`, `bodyH`, `wy`) and where the face was put (`x`, `y`, `size`) in ns.db.faceObs. Per race/sex, a least-squares fit of zE + a*k = a*half + camz, yE + c*k = c*half + camy, S + b*k = b*half (a, c, b: screen offsets and size over h/2; k = forward * tan(FOV/2)) gives eye height, sideways, size and forward offset: `P.FACE_MODEL` (shares of body height). Within 0-4 px in Waist/Full, 5-15 px in Face. Refit: tune again, read faceObs from WTF SavedVariables, rerun the fit (a local research script).
- **Fun layers** (2026-10-09): scene < Fx overlays (+2) < pic.tint (filter wash, gradient, vignette; +3) < pic.decor (stickers, text, frames: UI/Decor.lua; +4) < pic.over (badge, border; +5). Look tokens: o overlay, u custom colours, d frame, k stickers (key:x:y:s:r), t text (style:y:text, `L.CleanText` strips | ; and line breaks), l lens (per person). Lens creatures are creature display ids present in both the classic-era and Retail CreatureDisplayInfo tables (checked offline against the game's data tables). A creature lens loads instead of the body (`pic.critter`), framed by its live box, no badge. Upside down = roll pi lifted by the race height.
- **Guild only** (2026-10-09, protocol 2): `post.share = "guild"`, the P message's 11th field `g`. `ScopeOf(post)` sends the post and every L/C/X/D about it on GUILD only; `SendAnswer` skips them unless answering on the guild; a P with `g` from any other chat type is dropped. Protocol 1 clients don't know the field and would relay guild pictures to the realm, hence the bump. `S.List("all")` (the Realm feed) leaves them out. Who sees a picture is fixed once it's shared (an edit keeps it).
- **The camera angle is diagonal** (2026-10-09): `SetCameraFieldOfView` sets the corner-to-corner angle, not top-to-bottom. Treating it as vertical made 4:5 pictures ~25% too close, and pictures scrolling out (wide, short scenes) zoomed in. `P.DiagFov(fov, w, h)` converts. Close-ups of big-headed races take in more (`P.HeadSize`: Gnome 1.9, Goblin 1.75, Dwarf 1.25; Gnome tuned on Zix in game, Goblin by proportion). Placeholders stand on their own spot (x, y = 0): the live box leans toward cloaks and staffs on the back, which put close-ups in their face. Full shots allow headgear up to 1.25x the race height.
- **Placeholder framing by race height** (2026-10-09): NPC looks' bounding boxes aren't the body (weapons, idle animations), so `pic:Fit` frames a placeholder by `P.RaceHeight(race, sex)`: `P.RACE_HEIGHT` (ratios to a Human man), scaled by your own measured body (`BODY[UnitId("player")..":"]`, height / your race's ratio; 2.2 before that). Feet are at z≈0 for NPC looks. `/wgram boxes` on Forever: you (NE woman) 2.35 tall, so Human man ≈ 2.22 and Gnome man ≈ 1.06, which is exactly the gnome's collision height. Placeholders are no longer measured.
- **Other people's bodies** (`/wgram racetest`, 2026-10-09): retail has no `SetCustomRace`. A bare race body file (`character/<race>/<sex>/*.m2`) takes items' shapes but renders white: nothing paints a body without appearance settings. NPC looks of player races (`SetModelByCreatureDisplayID`) have skin; separate pieces (helm, shoulders, cloak, weapons) attach in colour; body clothes don't paint, and leg/boot items break the legs' shape. Round 3 found the real answer in Blizzard's CatalogShop code: **`SetModelByUnit(unit, ..., customRaceID)`** (the 7th argument) draws a unit as another race, as a real, fully dressable player model. Its gender is the unit's own. So strangers get a stand-in (`P.StandIn`: you if you share their gender, else a player you can see of that gender, from target, focus, mouseover, group or nameplates) with `customRaceID` = their race. Only with no such body: `Picture.RaceLook` (bare NPC looks, ids from wago.tools tables) plus `P.ATTACHED` slots. `SetModelByCreatureDisplayID`'s 2nd argument, useActivePlayerCustomizations, didn't help. **The other gender has no way around a donor:** no API switches a model's gender (only `C_BarberShop.SetSelectedSex`, in the barber chair), the Shop only previews your own gender, and every player-race NPC look in CreatureDisplayInfoExtra is pre-baked (none is painted live, so none takes new clothes). Rounds 5–6 (2026-10-09, Forever too): Forever supports `customRaceID`; swapping the body file after `SetUnit` (BetterWardrobe's Worgen trick) is ignored by DressUpModel and turns white on PlayerModel and actors, so there's no gender swap. Bodies are ranked by `pic.quality`: 3 the author, 2 a stand-in, 1 a placeholder (`P.PLACEHOLDER`, dressed NPC looks per race/sex/style from wago.tools tables, from a local research script; `P.ArmorStyle` reads the chest/legs with `GetItemInfoInstant`). A picture only upgrades (`qualityFor`), and a partial one says "Target any woman/man...".
- Right-drag direction: screen right is world **+y** in our camera setup (seen in game; I'd guessed -y).

- **One picture shape everywhere (4:5, `Look.ASPECT`)**. The Studio picture used to be tall and narrow (330x636), so Face and Waist up looked wrong there (the face filled the height and overflowed the width) and different from the feed. Framing now fits both height and width (`Look.FRAMES` h and w, w measured on the bare body).

- **Scrolling 3D pictures** (`UI\Scroller.lua` + `Picture:Crop`): models don't clip to a scroll frame, so each picture is cropped by hand. Its ModelScene is shrunk to the visible part, the field of view is narrowed to the visible share (`2*atan(tan(fov/2)*visible)`), and the camera is moved up or down by the cut's offset in world units. The character stays put and is cut off cleanly at the edge. This assumes WoW's ModelScene field of view is vertical. The crop is worked out from the layout (row position + `pic.rowY`), not `GetTop`, which can lag a frame. Only the rows in view exist; they're reused.

- The send queue skipped any message with no target, and GUILD messages never have one. Every guild message was silently dropped until a test sent one with the realm channel off.
- The addon was called Hearthgram until 2026-10-08. Renaming it meant a new folder, TOCs, `WowstagramDB` (old test data is gone), prefixes, the channel and `/wgram`.

- Ids changed to `Name-Realm` in v0.1 (the saved data flag is `v2`, which wipes older test data).
- Each test VM has its own clock. A newcomer's clock must start at the others' time, or every synced post looks like it's "from the future" and gets dropped.

## Release checklist

1. Bump `## Version` in both TOCs, which must stay identical. Never add a `_Mainline.toc`: Forever loads it first and marks the addon Incompatible.
2. Update CHANGELOG, README and CURSEFORGE.
3. `node dev/run.mjs` must be green.
4. Commit, tag `vX.Y.Z`, and push the commit and the tag in one push.
