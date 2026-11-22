-- Sync: the outbox GF Sync reads from GreenFangToolkitDB.sync.
-- Rules (docs/contracts/savedvariables.md):
--   * kinds: character.self (one per character), roster.snapshot (one per
--     guild), member.share (one per guild member, 0.10.0) and recipe.names
--     (one, 0.10.0). member.report is no longer written (0.10.0).
--   * outbox size follows the roster (Sync.outboxCap, §2f)
--   * never zone or online (location only where the contract allows it)
--   * nothing is scanned or written during combat

local _, ns = ...
local str = ns.str

local Sync = {}
ns.Sync = Sync

-- Outbox size (§2f, GF-001-D14): member.share is one per roster member, so
-- its cap follows the roster: max(150, roster size). Every other kind shares
-- 50 more slots. 115 members: 150 + 50 = 200 (the 0.9 contract numbers);
-- 1,000 members: 1,000 + 50. Tests may set Sync.MAX_OUTBOX to force a total.
Sync.MIN_SHARES = 150
Sync.OTHER_SLOTS = 50
Sync.MAX_OUTBOX = nil
Sync.SHARE_REFRESH = 6 * 3600   -- contract: rewrite when a field's time moved > 6 h
Sync.IDS_REFRESH = 30 * 86400   -- recipe ids are sent again after a month anyway
Sync.IDS_PER_LOGOUT = 50000     -- recipe ids in member.share per logout (about 1 MB on disk)
Sync.loadedAt = time and time() or 0 -- entries older than this survived a logout
Sync.NAMES_MAX = 500            -- recipe.names per entry
Sync.NAMES_LISTS = 60           -- recipe lists read per logout for new names
local nameless = {}             -- ids the client had no name for (this session)

local function rosterSize()
    local snap = ns.Roster and ns.Roster.current()
    if not snap then return 0 end
    return tonumber(snap.total) or #snap.members
end

-- Never above 1,200: GF Sync keeps only the newest 1,200 per file (claude-sync 7e5d84a).
Sync.MAX_SHARES = 1200
function Sync.shareCap() return math.min(Sync.MAX_SHARES, math.max(Sync.MIN_SHARES, rosterSize())) end
function Sync.outboxCap() return Sync.MAX_OUTBOX or (Sync.shareCap() + Sync.OTHER_SLOTS) end
-- Only ns.Config.guild is synced (GF-001-D4, GF-001-D5). The site rejects any
-- other uploader.guild as wrong_guild (docs/contracts/upload-api.md §3), and
-- other guilds' rosters must never leave the player's computer.
Sync.TARGET_GUILD = ns.Config.guild.name -- read-only copy; checks use ns.isTargetGuild

function Sync.otherGuildNote()
    return string.format("這個角色不在%s，不會同步", ns.targetGuildName())
end
-- Player-facing text never mentions slash commands (GF-000-B); the commands are
-- only listed in /gftk help for advanced users.
-- D-015: installing the toolkit means agreeing to share; this line informs.
Sync.NOTICE = "綠皮冒險工具箱會分享你的等級、職業、專業、配方和所在地給公會內有裝工具箱的人，並可能由他們上傳到公會網站。"
-- Bumped when the notice gains something players must hear about (0.7.0:
-- location, D-009); players who saw an older notice see the new one once.
Sync.NOTICE_VERSION = 4 -- 0.9.0: always shared and relayed, no switches (D-015)
Sync.COLOR_ON = { 0.33, 0.85, 0.55 }
Sync.COLOR_OFF = { 0.6, 0.6, 0.6 }

-- Listeners run after sync is switched or the outbox changes, so every status
-- display (roster page, settings page, minimap tooltip) updates immediately.
local listeners = {}
function Sync.onChange(fn) listeners[#listeners + 1] = fn end
function Sync.notify()
    for _, fn in ipairs(listeners) do pcall(fn) end
end
Sync.pendingSelf = false

local function state() return ns.db and ns.db.sync end

-- D-015: there is no switch any more. Kept as a function so callers stay
-- simple; true whenever the saved table is ready.
function Sync.isEnabled()
    return state() ~= nil
end

local function gameBlock(realm)
    return {
        world = ns.WORLD,
        interface = ns.Data.interface(),
        realm = realm,
        locale = GetLocale and GetLocale() or nil,
    }
end

local function uploaderBlock(p)
    return {
        guid = p.guid, name = p.name, realm = p.realm, faction = p.faction,
        guild = p.guild, guildRank = p.guildRank,
    }
end

local function sameUploaderGuild(a, b)
    return type(a) == "table" and type(b) == "table"
        and a.realm == b.realm and a.faction == b.faction and a.guild == b.guild
end

-- Deep equality, used to avoid re-queueing identical character data.
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Enforce the caps (§2f): member.share beyond its own cap loses its oldest;
-- beyond the total, old member.report goes first, then the oldest
-- member.share, then the oldest of every other kind.
local function enforceCap()
    local outbox = state().outbox
    local shareCap, total = Sync.shareCap(), Sync.outboxCap()
    local shares = 0
    for _, e in ipairs(outbox) do if e.kind == "member.share" then shares = shares + 1 end end
    while #outbox > total or shares > shareCap do
        local best = {}
        for i, e in ipairs(outbox) do
            local at = type(e.capturedAt) == "number" and e.capturedAt or 0
            local k = e.kind == "member.report" and "report" or e.kind == "member.share" and "share" or "other"
            if not best[k] or at < best[k].at then best[k] = { i = i, at = at } end
        end
        local pick
        if #outbox > total then pick = best.report or best.share or best.other
        else pick = best.share end
        if outbox[pick.i].kind == "member.share" then shares = shares - 1 end
        table.remove(outbox, pick.i)
    end
end

-- GF-001-D23: entries queued with an empty realm (0.9.x since 2026-11-21)
-- get the realm now known, when they are this guild's. Returns how many.
function Sync.repairRealms(realm, guild)
    local s = state()
    realm = str(realm)
    if not s or type(s.outbox) ~= "table" or realm == "" then return 0 end
    local fixed = 0
    for _, e in ipairs(s.outbox) do
        if type(e) == "table" and type(e.uploader) == "table" and e.uploader.guild == guild then
            local changed = false
            if str(e.uploader.realm) == "" then e.uploader.realm = realm; changed = true end
            if type(e.game) == "table" and str(e.game.realm) == "" then e.game.realm = realm; changed = true end
            if changed then fixed = fixed + 1 end
        end
    end
    return fixed
end

-- Remove matching entries, append the new one, then enforce the cap.
local function put(entry, matches)
    local outbox = state().outbox
    -- Once per session and realm: new entries never have an empty realm.
    local u = entry.uploader
    local key = u and (str(u.realm) .. "|" .. str(u.guild))
    if key and key ~= Sync.repairedFor then
        Sync.repairRealms(u.realm, u.guild)
        if str(u.realm) ~= "" then Sync.repairedFor = key end
    end
    for i = #outbox, 1, -1 do
        local e = outbox[i]
        if type(e) ~= "table" or matches(e) then table.remove(outbox, i) end
    end
    outbox[#outbox + 1] = entry
    enforceCap()
    Sync.notify()
    return entry
end

local function serverNow()
    return ns.num((ns.call(GetServerTime)))
end

local function makeEntry(kind, p, capturedAt, payload)
    return {
        id = str(p.guid) .. ":" .. tostring(capturedAt) .. ":" .. kind,
        kind = kind,
        capturedAt = capturedAt,
        capturedAtServer = serverNow(), -- 0.10.0: the site compares with this first
        game = gameBlock(p.realm),
        uploader = uploaderBlock(p),
        payload = payload,
    }
end

function Sync.find(kind, match)
    local s = state()
    if not s then return nil end
    for _, e in ipairs(s.outbox) do
        if type(e) == "table" and e.kind == kind and match(e) then return e end
    end
    return nil
end

-- character.self: the player's own level, class, race and professions.
-- force=true on login (contract: one per login); otherwise only when changed.
-- Returns entry or nil, reason.
---------------------------------------------------------------------------
-- Guild of the logged-in character, remembered for this session only (Lua
-- state, nothing saved). The client can briefly report no guild while the
-- character is in one: early in login, at PLAYER_LOGOUT and around /reload.
-- An entry written in that moment would lose uploader.guild/guildRank and be
-- rejected by the site as wrong_guild (GF-001-B). So the last guild seen this
-- session is used whenever the client says "none", until the character
-- really leaves (Sync.forgetGuild, called by Init after PLAYER_GUILD_UPDATE).
---------------------------------------------------------------------------

local sessionGuild = {} -- [guid] = { guild = ..., rank = ... }

function Sync.rememberGuild(guid, guild, rank)
    if type(guid) ~= "string" or str(guild) == "" then return end
    local known = sessionGuild[guid]
    if known and known.guild == guild then
        if str(rank) ~= "" then known.rank = rank end
    else
        sessionGuild[guid] = { guild = guild, rank = str(rank) ~= "" and rank or nil }
    end
end

function Sync.forgetGuild(guid)
    if guid then sessionGuild[guid] = nil end
end

function Sync.knownGuild(guid)
    return guid and sessionGuild[guid] or nil
end

-- Data.player() plus the session's guild when the client reports none.
function Sync.player()
    local p = ns.Data.player()
    if not p.guid then return p end
    if p.guild then
        Sync.rememberGuild(p.guid, p.guild, p.guildRank)
        local known = sessionGuild[p.guid]
        if not p.guildRank and known and known.guild == p.guild then p.guildRank = known.rank end
    else
        local known = sessionGuild[p.guid]
        if known then p.guild, p.guildRank = known.guild, known.rank end
    end
    return p
end

-- Nothing is written unless the character is in TARGET_GUILD.
-- Without opts.allowNoGuild an unknown guild is "waiting-guild" (guild info may
-- still be loading, Init retries); with it (end of the login wait, logout,
-- later updates) it is "no-guild". Neither writes anything: allowNoGuild only
-- ends the wait, it never lets a guildless character into the outbox.
function Sync.recordSelf(force, opts)
    if not Sync.isEnabled() then return nil, "disabled" end
    if ns.inCombat() then Sync.pendingSelf = true; return nil, "combat" end
    local p = Sync.player()
    if not p.guid then return nil, "no-guid" end
    if not p.guild then
        if not (opts and opts.allowNoGuild) then return nil, "waiting-guild" end
        return nil, "no-guild"
    end
    if not ns.isTargetGuild(p.guild, p.realm) then return nil, "other-guild" end
    if p.realm == "" then Sync.pendingSelf = true; return nil, "waiting-realm" end -- GF-001-D23
    local professions = {}
    for i, prof in ipairs((ns.Data.ownProfessionsDetailed())) do
        -- Contract fields only (the icon is for the in-game window).
        professions[i] = { name = prof.name, skillLineID = prof.skillLineID, rank = prof.rank, max = prof.max }
    end
    local payload = {
        level = type(p.level) == "number" and p.level or nil,
        class = p.class, classToken = p.classToken,
        race = p.race, raceID = p.raceID,
        professions = professions,
        -- Always shared (D-015). Named location, never zone: GF Sync strips
        -- every zone field.
        location = Sync.shareLocation() and ns.Data.location() or nil,
        recipes = Sync.ownRecipes(),
    }
    local existing = Sync.find("character.self", function(e)
        return type(e.uploader) == "table" and e.uploader.guid == p.guid
    end)
    -- GF-001-D23: professions listed but unreadable -> not "none". Keep the
    -- last known ones, or leave the field out (the site keeps what it has).
    if #professions == 0 and (ns.Data.unreadableProfessions or 0) > 0 then
        local before = existing and type(existing.payload) == "table" and existing.payload.professions
        payload.professions = (type(before) == "table" and #before > 0) and ns.copy(before) or nil
    end
    if not force and existing and same(existing.payload, payload)
        and same(existing.uploader, uploaderBlock(p)) then
        return nil, "unchanged"
    end
    Sync.pendingSelf = false
    local entry = makeEntry("character.self", p, ns.now(), payload)
    return put(entry, function(e)
        return e.kind == "character.self" and type(e.uploader) == "table"
            and e.uploader.guid == p.guid
    end)
end

-- Fields allowed in roster.snapshot members. zone and online are NOT here.
Sync.ROSTER_MEMBER_FIELDS = {
    "name", "guid", "level", "classToken", "race", "raceID", "guildRank",
    "professions", "professionSource",
}

function Sync.publicMember(m)
    local out = {}
    for _, f in ipairs(Sync.ROSTER_MEMBER_FIELDS) do
        local v = m[f]
        -- Unknown stays nil: the site keeps known values when a field is empty (D-008),
        -- so never send "" or a 0 level as if it were data.
        if (f == "race" or f == "classToken" or f == "guildRank") and v == "" then v = nil end
        if f == "level" and v == 0 then v = nil end
        out[f] = ns.copy(v)
    end
    return out
end

-- roster.snapshot from a complete display snapshot made by Roster.collect().
function Sync.recordRoster(snapshot)
    if not Sync.isEnabled() then return nil, "disabled" end
    if ns.inCombat() then return nil, "combat" end
    if type(snapshot) ~= "table" or type(snapshot.members) ~= "table"
        or #snapshot.members == 0 or #snapshot.members ~= snapshot.total then
        return nil, "incomplete"
    end
    if not ns.isTargetGuild(snapshot.guild, snapshot.realm) then return nil, "other-guild" end
    local p = Sync.player()
    if not p.guid or p.guild ~= snapshot.guild then return nil, "no-guild" end
    if p.realm == "" then return nil, "waiting-realm" end -- GF-001-D23
    local members = {}
    for i, m in ipairs(snapshot.members) do members[i] = Sync.publicMember(m) end
    local entry = makeEntry("roster.snapshot", p, snapshot.capturedAt or ns.now(), {
        total = snapshot.total,
        members = members,
    })
    return put(entry, function(e)
        return e.kind == "roster.snapshot" and sameUploaderGuild(e.uploader, entry.uploader)
    end)
end

---------------------------------------------------------------------------
-- Phase 4 (GF-001-D14, D-014 point 3): relayed data goes to the site too.
-- member.report (0.8.x, D-011) is no longer written; member.share carries
-- every field with the author's own server time (savedvariables §member.share).
-- Written at logout only: the client writes SavedVariables then anyway, and
-- GF Sync uploads what changed after that.
---------------------------------------------------------------------------

-- character.self.recipes: own R<skillLineID> records, string keys (§2a.4).
function Sync.ownRecipes()
    local Share = ns.Share
    local a = Share and Share.selfAuthor()
    local out
    for g, r in pairs(a and Share.records(a) or {}) do
        local skill = g:match("^R(%d+)$")
        local ids = skill and Share.decoded(a, g)
        if ids and #ids > 0 then
            out = out or {}
            out[skill] = { recordedAt = r.t, hash = r.h, ids = ns.copy(ids) }
        end
    end
    return out
end

local function via(r) return r.fromAuthor and "author" or "relay" end
local function field(r, value) return { value = value, recordedAt = r.t, via = via(r) } end

-- payload of one subject's member.share; idsFor(g, r) says whether a recipe
-- list carries its ids. Empty tables are left out (§2a.3).
local function sharePayload(m, a, recs, tombs, realm, idsFor)
    local Share = ns.Share
    local payload = {
        subject = { guid = m.guid, name = m.name, realm = m.name:match("^.-%-(.+)$") or realm },
    }
    if recs.B then
        local b = Share.decoded(a, "B")
        if b then
            payload.level = field(recs.B, b.level)
            if b.classToken then payload.classToken = field(recs.B, b.classToken) end
        end
    end
    if recs.P then
        local list = {}
        for _, prof in ipairs(Share.decoded(a, "P") or {}) do
            list[#list + 1] = { skillLineID = prof.skillLineID, rank = prof.rank, max = prof.max,
                name = ns.Data.skillName(nil, prof.skillLineID) }
        end
        if #list > 0 then payload.professions = field(recs.P, list) end
    end
    if recs.Z then
        local z = Share.decoded(a, "Z")
        if z then payload.location = field(recs.Z, { zone = z.zone, subZone = z.subZone }) end
    end
    for g, r in pairs(recs) do
        local skill = g:match("^R(%d+)$")
        if skill then
            local item = { recordedAt = r.t, via = via(r), hash = r.h }
            if idsFor(g, r) then
                local ids = Share.decoded(a, g)
                if ids and #ids > 0 then item.ids = ns.copy(ids) end
            end
            payload.recipes = payload.recipes or {}
            payload.recipes[skill] = item
        end
    end
    for g, t in pairs(tombs) do
        local skill = g:match("^R(%d+)$")
        if skill then
            payload.withdrawn = payload.withdrawn or { recipes = {} }
            payload.withdrawn.recipes[skill] = t
        end
    end
    return payload
end

-- What this subject's records look like now: [g] = { t, h } (tombstones h = "x").
local function fieldState(recs, tombs)
    local out = {}
    for g, r in pairs(recs) do out[g] = { t = r.t, h = r.h } end
    for g, t in pairs(tombs) do out[g] = { t = t, h = "x" } end
    return out
end

-- "changed": a value, a tombstone or the set of fields differs from what we
-- last wrote, or a time moved more than SHARE_REFRESH; "newer": only times
-- moved; nil: nothing new.
local function compareState(now, last)
    if not last then return "changed" end
    local newer = false
    for g, f in pairs(now) do
        local w = last[g]
        if not w or w.h ~= f.h then return "changed" end
        if f.t > w.t then
            if f.t - w.t > Sync.SHARE_REFRESH then return "changed" end
            newer = true
        end
    end
    for g in pairs(last) do if not now[g] then return "changed" end end
    return newer and "newer" or nil
end
Sync.compareState = compareState

local function hasIDs(e)
    for _, item in pairs(type(e.payload) == "table" and type(e.payload.recipes) == "table" and e.payload.recipes or {}) do
        if type(item) == "table" and item.ids then return true end
    end
    return false
end

-- member.share for every roster member we know something new about (EVAL
-- §3.6, settled with claude-pm): a subject is written when one of its fields
-- changed since this client last wrote it, or moved forward more than 6 h;
-- once every 6 h also every subject whose times moved at all. Unchanged
-- subjects keep their entry. Recipe ids only when the list (hash) differs
-- from the one this client last wrote with ids, or that was IDS_REFRESH ago.
-- Size (GF-001-D14, 1,000 members): at most IDS_PER_LOGOUT ids per logout,
-- newest lists first; a list left out is tried again at the next logout. An
-- entry whose ids were written at an earlier logout (GF Sync has had its
-- chance) is rewritten without them, so the outbox does not keep every list.
-- Returns the number written.
function Sync.recordShares()
    if not Sync.isEnabled() then return 0, "disabled" end
    if ns.inCombat() then return 0, "combat" end
    local Share = ns.Share
    local p = Sync.player()
    if not p.guid then return 0, "no-guid" end
    if not ns.isTargetGuild(p.guild, p.realm) then return 0, "other-guild" end
    if p.realm == "" then return 0, "waiting-realm" end -- GF-001-D23
    local s, snap = Share.store(), ns.Roster.current()
    if not s or not snap then return 0, "no-data" end
    local nowServer = Share.serverNow()
    local refresh = nowServer - (s.shareRefreshAt or 0) >= Sync.SHARE_REFRESH
    local outbox = state().outbox
    local existing = {}
    for _, e in ipairs(outbox) do
        if e.kind == "member.share" and type(e.payload) == "table" and type(e.payload.subject) == "table"
            and e.payload.subject.guid then
            existing[e.payload.subject.guid] = e
        end
    end
    local selfA = Share.selfAuthor()
    local now = ns.now()
    -- 1. Who is written this time.
    local todo = {}
    for _, m in ipairs(snap.members) do
        local a = m.guid and Share.authorOf(m.guid)
        local recs, tombs = a and s.rec[a] or {}, a and s.tomb[a] or {}
        if a and a ~= selfA and (next(recs) or next(tombs)) then
            local current = fieldState(recs, tombs)
            local diff = compareState(current, s.queued[a])
            local old = existing[m.guid]
            if not old and s.queued[a] then diff = "changed" end
            local strip = old and type(old.capturedAt) == "number" and old.capturedAt < Sync.loadedAt and hasIDs(old)
            if diff == "changed" or (diff == "newer" and refresh) or strip then
                todo[#todo + 1] = { m = m, a = a, recs = recs, tombs = tombs, current = current, old = old }
            end
        end
    end
    -- 2. Which recipe lists carry their ids: newest first, within the budget.
    local wants = {}
    for _, job in ipairs(todo) do
        local sent = s.idsSent[job.a] or {}
        for g, r in pairs(job.recs) do
            if g:match("^R%d+$") then
                local last = sent[g]
                if not last or last.h ~= r.h or nowServer - last.at >= Sync.IDS_REFRESH then
                    -- Count without decoding: ids are "."-separated on the wire.
                    local n = r.v == "" and 0 or select(2, r.v:gsub("%.", "")) + 1
                    wants[#wants + 1] = { key = job.a .. "|" .. g, t = r.t, n = n }
                end
            end
        end
    end
    table.sort(wants, function(x, y)
        if x.t ~= y.t then return x.t > y.t end
        return x.key < y.key
    end)
    local allowed, budget = {}, Sync.IDS_PER_LOGOUT
    for _, w in ipairs(wants) do
        if w.n <= budget then allowed[w.key] = true; budget = budget - w.n
        else allowed[w.key] = false end
    end
    -- 3. Write them.
    local written, replaced = {}, {}
    for _, job in ipairs(todo) do
        local a, m = job.a, job.m
        local sent = s.idsSent[a] or {}
        local payload = sharePayload(m, a, job.recs, job.tombs, p.realm, function(g)
            return allowed[a .. "|" .. g] == true
        end)
        for skill, item in pairs(payload.recipes or {}) do
            if item.ids then sent["R" .. skill] = { h = item.hash, at = nowServer } end
        end
        s.idsSent[a] = sent
        -- A list left out of the budget makes the next logout write it again.
        for g, f in pairs(job.current) do
            if allowed[a .. "|" .. g] == false then job.current[g] = { t = f.t, h = "pending" } end
        end
        local at = now
        local old = job.old
        if old and type(old.capturedAt) == "number" and old.capturedAt >= at then at = old.capturedAt + 1 end
        local entry = makeEntry("member.share", p, at, payload)
        entry.id = entry.id .. ":" .. m.guid
        written[#written + 1] = entry
        replaced[m.guid] = true
        s.queued[a] = job.current
    end
    if refresh then s.shareRefreshAt = nowServer end
    if #written == 0 then return 0, "unchanged" end
    for i = #outbox, 1, -1 do
        local e = outbox[i]
        if e.kind == "member.share" and type(e.payload) == "table" and type(e.payload.subject) == "table"
            and replaced[e.payload.subject.guid] then
            table.remove(outbox, i)
        end
    end
    for _, e in ipairs(written) do outbox[#outbox + 1] = e end
    enforceCap()
    Sync.notify()
    return #written
end

-- recipe.names: names of recipe IDs this computer has not put in an entry
-- yet (at most NAMES_MAX at a time). New names come first; the rest of the
-- previous entry fills the remaining room. Records already looked at are
-- remembered by hash, so a logout only reads recipe lists that changed.
function Sync.recordRecipeNames()
    if not Sync.isEnabled() then return nil, "disabled" end
    if ns.inCombat() then return nil, "combat" end
    local Share = ns.Share
    local p = Sync.player()
    if not p.guid then return nil, "no-guid" end
    if not ns.isTargetGuild(p.guild, p.realm) then return nil, "other-guild" end
    if p.realm == "" then return nil, "waiting-realm" end -- GF-001-D23
    local s = Share.store()
    if not s or not ns.Recipes then return nil, "no-data" end
    local seen = ns.db.share.seenIDs
    local names, count, full = {}, 0, false
    local lists = 0
    for a, groups in pairs(s.rec) do
        for g, r in pairs(groups) do
            local key = a .. "|" .. g
            if not full and g:match("^R%d+$") and s.named[key] ~= r.h then
                -- Bounded work per logout (a client that lacks many names
                -- must not read every list every time).
                lists = lists + 1
                if lists > Sync.NAMES_LISTS then full = true; break end
                local complete = true
                for _, id in ipairs(Share.decoded(a, g) or {}) do
                    if not seen[id] and not names[id] then
                        if count >= Sync.NAMES_MAX then complete, full = false, true; break end
                        local name = not nameless[id] and ns.Recipes.knownName(id) or nil
                        if name then names[id] = name; count = count + 1
                        else nameless[id] = true; complete = false end
                    end
                end
                if complete then s.named[key] = r.h end
            end
        end
        if full then break end
    end
    if count == 0 then return nil, "none" end
    local out = {}
    for id, name in pairs(names) do out[tostring(id)] = name; seen[id] = true end
    local old = Sync.find("recipe.names", function() return true end)
    if old and type(old.payload) == "table" and type(old.payload.names) == "table" then
        for k, v in pairs(old.payload.names) do
            if count >= Sync.NAMES_MAX then break end
            if not out[k] then out[k] = v; count = count + 1 end
        end
    end
    local at = ns.now()
    if old and type(old.capturedAt) == "number" and old.capturedAt >= at then at = old.capturedAt + 1 end
    local entry = makeEntry("recipe.names", p, at, { locale = GetLocale and GetLocale() or nil, names = out })
    return put(entry, function(e) return e.kind == "recipe.names" end)
end

-- Remove outbox entries the site would reject as wrong_guild: entries without
-- uploader.guild or from another guild (left by AddOn 0.6.4 and earlier).
-- Called once at load. Returns how many were removed.
function Sync.purgeForeign()
    local s = state()
    if not s or type(s.outbox) ~= "table" then return 0 end
    local removed = 0
    for i = #s.outbox, 1, -1 do
        local e = s.outbox[i]
        if type(e) ~= "table" or type(e.uploader) ~= "table"
            or not ns.isTargetGuild(e.uploader.guild, e.uploader.realm) then
            table.remove(s.outbox, i)
            removed = removed + 1
        end
    end
    if removed > 0 then Sync.notify() end
    return removed
end

-- Note for a character whose data is not synced, else nil. Unknown guild
-- while the client still reports being in one = still loading, no note.
function Sync.guildNote()
    local p = Sync.player()
    if ns.isTargetGuild(p.guild, p.realm) then return nil end
    if not p.guild and ns.isInGuild() then return nil end
    return Sync.otherGuildNote()
end

-- Location is always shared (D-015).
function Sync.shareLocation() return true end

-- Number of entries waiting for GF Sync.
function Sync.pending()
    local s = state()
    return s and #s.outbox or 0
end

-- One short line for the status indicator and the minimap tooltip.
function Sync.shortStatus()
    if not state() then return "同步：尚未就緒" end
    return string.format("待上傳 %d 筆（下線後由 GF Sync 上傳）", Sync.pending())
end

function Sync.statusColor() return Sync.COLOR_ON end

function Sync.showNoticeOnce()
    local s = state()
    if not s then return false end
    if s.noticeShown and (s.noticeVersion or 1) >= Sync.NOTICE_VERSION then return false end
    ns.say(Sync.NOTICE)
    s.noticeShown = true
    s.noticeVersion = Sync.NOTICE_VERSION
    return true
end

function Sync.statusText()
    local s = state()
    if not s then return "尚未初始化" end
    local counts = { ["character.self"] = 0, ["roster.snapshot"] = 0, ["member.report"] = 0,
        ["member.share"] = 0, ["recipe.names"] = 0 }
    local latest = 0
    for _, e in ipairs(s.outbox) do
        if type(e) == "table" then
            counts[e.kind] = (counts[e.kind] or 0) + 1
            if type(e.capturedAt) == "number" and e.capturedAt > latest then latest = e.capturedAt end
        end
    end
    local text = string.format("待上傳 %d 筆（上限 %d；角色 %d、名冊 %d、公會成員 %d、配方名稱 %d）｜最新資料：%s｜GF Sync 會在你下線後讀取。",
        #s.outbox, Sync.outboxCap(), counts["character.self"], counts["roster.snapshot"],
        counts["member.share"] + counts["member.report"], counts["recipe.names"],
        latest > 0 and ns.localTime(latest) or "無")
    local note = Sync.guildNote()
    if note then text = note .. "。" .. text end
    return text
end

-- /gftk sync: the status line and the 「同步與診斷」 window (no on/off, D-015).
function Sync.command()
    ns.say(Sync.statusText())
    if ns.Diag then ns.Diag.open() end
end
