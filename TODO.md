# Wowstagram TODO

## Before launch
- [ ] **Friend test** (two or three players, standing together in game). Post, like and comment back and forth, then check:
  - Does each side see the other's pictures, likes and comments?
  - Does a friend who logs in later get the pictures they missed?
  - Does opening a profile fetch their pictures and bio?
  - **Guild only**: does a guildmate get it, and someone outside the guild not?
  - Forever: do two-word names work end to end? Can players on different rulesets see each other?
  - The fun travels too: stickers, text, frames, lenses, face filters, motion, overlays on each other's pictures.
  - When something doesn't arrive: `/wgram stats` on both sides, and BugSack's errors.
- [ ] CurseForge: screenshots (Save to computer), upload `dev/media/icon.png` as the project icon, categories, upload (zip, or a git remote for the packager).

## Next
- [ ] **HD / SD character models** (Forever: Options > Graphics > Character Models). Face filters are tuned on HD. Find the setting: `/wgram cvars model` with HD on, then with SD on; the line that changes is it (else try `hd`, `classic`). Then Tune faces with SD on for a second table, and pick the table by that setting.
- [ ] **Retail face table**: Tune faces on Retail (its HD bodies and look-alikes differ from Forever's).
- [ ] Retail: check `/wgram wall` for Blood Elf, Draenei, Goblin and Worgen (framing and faces; Goblin's big head is a guess).
- [ ] Full shots of look-alikes: less hat room? (12% was tried and cut helmets; maybe 18%.)

## Ideas
- [ ] **Explore**: the most-liked pictures of the week.
- [ ] Item search by name in Create (ItemTree as an optional data source, like JourneyPlanner).
- [ ] Mounts and pets in the picture.
- [ ] Direct messages.
- [ ] More backgrounds: mail stationery, skyboxes, spell textures.
- [ ] **Big group test**: sync with many real players, and the send limit on a busy channel.

## Done
- [x] 0.1.0 (2026-10-09): Create, feeds, stories, posts, likes, comments, saved, notifications, profiles, follows, demo people, fullscreen, Retail and Forever.
- [x] Strangers: real body when seen, Stand-in (`customRaceID`), dressed look-alikes, badges.
- [x] Framing: race heights, big heads, diagonal camera angle, per-race fixes tuned on `/wgram wall`.
- [x] Scale defences: few answerers, rate limits, size guards, protocol version (now 2).
- [x] Guild only pictures; demo people off by default; saved pictures never pruned; Save to computer.
- [x] Checked on Forever (2026-10-10): stickers turn (texture rotation works), #tags and @mentions click.
- [x] 1.0.3 (2026-10-16): WowstagramAPI for other addons (HearthPhone); demo off removes every trace.
- [x] 1.0.2 (2026-10-11): code review fixes and cleanup, kept compatible with 1.0.0 (see CHANGELOG).
- [x] 1.0.0 prep (2026-10-10): our own logo, release notes, /wgram and /wgram demo only; Block; Dislike; a ranked Realm feed (friends, following, guild, seen lately); hashtags, mentions, Search.
- [x] Fun (2026-10-09/10): tool rail; 150+ backgrounds (colours, moving, liquids, ground, talent trees, books, rooms, places, maps); 21 filters; 11 motions; 44 overlays; 34 stickers; 9 text styles; 10 frames; 23 lenses; 22 face filters with a per-race head model; Hold still.
