-- Events (GF-013, docs/spec/GFTK_Master_Spec_v2.0.md §9 / §9.1): a background
-- record of adventure business on this computer. Not an achievement system:
-- no page, no badge, no ranking. Only the diagnostics page shows the counts.
--
-- What it is:
--   * One logical event per fact (a ticket was created / finalized / formed /
--     done / cancelled / expired / unfinished; a worker ticket was created /
--     matched; I applied / was admitted / took part in a 成行).
--   * The event ID comes from a dedup key (adventure + type + me, or worker
--     order + adventure), so the same fact never counts twice: a step back,
--     a reopen of the same order, a resend or a repeated invite land on the
--     same event. A truly new adventure has a new adventureID: a new event.
--   * A step back revokes an event (revision + 1, status "revoked"); coming
--     back restores the same event (revision + 1). A changed role is a
--     correction (revision + 1). The first observedAt is never rewritten.
--   * Only my own facts: originGUID = participantGUID = me. No character
--     names, no officer notes, no account (GUIDs only, spec §9.1 / §11).
--   * Raids (團本): only created / applied; never formed / done (spec §9.1).
--   * Test builds (ns.isTestBuild): events are marked test and never queued.
--   * A bounded "to upload" queue (one entry per event, its latest revision):
--     pending / markSent / confirm / resend / forget and a capacity warning.
--     Not wired to GF Sync (upload-api v1.6 is not settled): no outbox entry,
--     nothing leaves this computer. Lives in GreenFangToolkitDB.events, apart
--     from the 30-day / 50-record completion log, which it never touches.
--
-- Adventure.lua calls Events.observe / onWorkerSaved / onReopen after its own
-- writes (pcall'd: a failure here never stops a ticket). Events only reads
-- Adventure's views and records.

local _, ns = ...
local str = ns.str

local Events = {}
ns.Events = Events

Events.SCHEMA_VERSION = 1
Events.MAX_EVENTS = 1000      -- per character
Events.WARN_AT = 800          -- capacity warning (80%)
Events.RESEND_AFTER = 6 * 3600
Events.KEEP_CONFIRMED_DAYS = 180
Events.KEEP_TEST = 86400
Events.MAX_SKIPPED = 50

Events.LEADER_TYPES = { "adventure_created", "adventure_finalized", "adventure_formed", "adventure_done",
    "adventure_cancelled", "adventure_expired", "adventure_unfinished" }
Events.TYPES = {
    adventure_created = true, adventure_finalized = true, adventure_formed = true, adventure_done = true,
    adventure_cancelled = true, adventure_expired = true, adventure_unfinished = true,
    worker_order_created = true, worker_order_matched = true,
    signup_applied = true, participant_admitted = true, participant_done = true,
}
Events.PATHS = { leader = true, worker_match = true, direct_signup = true }
-- The fields one event carries (and the only ones the export writes).
Events.FIELDS = { "eventID", "schemaVersion", "originGUID", "adventureID", "workerOrderID", "participantGUID",
    "participationPath", "eventType", "activityType", "destinationID", "role", "observedAt", "revision",
    "revisedAt", "status", "change", "revokedReason", "evidence", "reopenOf", "test" }

local function S() return ns.Share end
local function A() return ns.Adventure end
local function now() return S().serverNow() end

---------------------------------------------------------------------------
-- Storage: GreenFangToolkitDB.events = { schemaVersion, chars = { [author] = state } }
-- state = { events = { [eventID] = ev }, n, queue = { [eventID] = { rev, at, sent, tries } },
--           workerOrder = { id, at }, skipped = { [adventureID] = at }, stats = { overflow, noEvidence } }
-- Created only when the first event is written (no empty tables in the save file).
---------------------------------------------------------------------------

function Events.root(create)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.events) ~= "table" then
        if not create then return nil end
        db.events = { schemaVersion = Events.SCHEMA_VERSION, chars = {} }
    end
    local r = db.events
    if type(r.chars) ~= "table" then r.chars = {} end
    r.schemaVersion = r.schemaVersion or Events.SCHEMA_VERSION
    return r
end

function Events.me() return S().selfAuthor() end

function Events.state(create, a)
    a = a or Events.me()
    if not a then return nil end
    local r = Events.root(create)
    if not r then return nil end
    local s = r.chars[a]
    if type(s) ~= "table" then
        if not create then return nil end
        s = {}
        r.chars[a] = s
    end
    for _, k in ipairs({ "events", "queue", "skipped", "stats" }) do if type(s[k]) ~= "table" then s[k] = {} end end
    s.stats.overflow = s.stats.overflow or 0
    s.stats.noEvidence = s.stats.noEvidence or 0
    if type(s.n) ~= "number" then
        local n = 0
        for _ in pairs(s.events) do n = n + 1 end
        s.n = n
    end
    return s
end

function Events.isTest() return ns.isTestBuild ~= nil and ns.isTestBuild() == true end

-- The event ID of a dedup key: two independent 24-bit hashes (origin + key, key).
function Events.idFor(origin, key)
    return "e" .. S().hash(str(origin) .. "|" .. key) .. S().hash(key .. "|" .. str(origin))
end

---------------------------------------------------------------------------
-- The queue (bounded by the store: one entry per event)
---------------------------------------------------------------------------

local function enqueue(s, ev, t)
    if ev.test then return end
    local q = s.queue[ev.eventID]
    if q then q.rev, q.at, q.sent = ev.revision, t, nil -- a new revision is sent again
    else s.queue[ev.eventID] = { rev = ev.revision, at = t, tries = 0 } end
end

-- Confirmed events past KEEP_CONFIRMED_DAYS and test events past KEEP_TEST leave the store.
-- Never an unconfirmed one.
function Events.prune(s, t)
    s = s or Events.state(false)
    if not s then return 0 end
    t = t or now()
    local n = 0
    for id, ev in pairs(s.events) do
        local age = t - (ev.revisedAt or ev.observedAt or t)
        local confirmed = not s.queue[id] and (ev.ackRev or 0) >= (ev.revision or 1)
        if (ev.test and age >= Events.KEEP_TEST) or (confirmed and age >= Events.KEEP_CONFIRMED_DAYS * 86400) then
            s.events[id] = nil
            s.queue[id] = nil
            s.n = s.n - 1
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Writing (ensure / revoke)
---------------------------------------------------------------------------

-- The fields a later observation may correct (role, destination). The rest stay as first seen.
local CORRECTABLE = { "role", "destinationID", "activityType" }

-- Make sure the fact behind key is recorded and active. f = the event's fields.
-- Returns the event and what happened: "new", "restore", "correction", "same", or nil, "full".
function Events.ensure(key, f, t)
    local s = Events.state(true)
    if not s then return nil, "no-self" end
    t = t or now()
    local origin = S().guidOf(Events.me())
    local id = Events.idFor(origin, key)
    local ev = s.events[id]
    if not ev then
        if s.n >= Events.MAX_EVENTS then Events.prune(s, t) end
        if s.n >= Events.MAX_EVENTS then
            s.stats.overflow = s.stats.overflow + 1 -- refused; nothing unconfirmed is dropped
            return nil, "full"
        end
        ev = { eventID = id, schemaVersion = Events.SCHEMA_VERSION, originGUID = origin,
            participantGUID = origin, revision = 1, status = "active", change = "new",
            observedAt = f.observedAt or t, test = Events.isTest() or nil }
        for k, v in pairs(f) do if k ~= "observedAt" then ev[k] = v end end
        s.events[id] = ev
        s.n = s.n + 1
        enqueue(s, ev, t)
        return ev, "new"
    end
    if ev.status == "revoked" then
        ev.status, ev.change, ev.revokedReason = "active", "restore", nil
        for _, k in ipairs(CORRECTABLE) do if f[k] ~= nil then ev[k] = f[k] end end
        if f.evidence then ev.evidence = f.evidence end
        ev.revision, ev.revisedAt = ev.revision + 1, t
        enqueue(s, ev, t)
        return ev, "restore"
    end
    local changed = false
    for _, k in ipairs(CORRECTABLE) do
        if f[k] ~= nil and f[k] ~= ev[k] then ev[k] = f[k]; changed = true end
    end
    if changed then
        ev.change, ev.revision, ev.revisedAt = "correction", ev.revision + 1, t
        enqueue(s, ev, t)
        return ev, "correction"
    end
    return ev, "same"
end

-- Revoke the fact behind key (a step back). Returns true when it was active.
function Events.revoke(key, reason, t)
    local s = Events.state(false)
    if not s then return false end
    local ev = s.events[Events.idFor(S().guidOf(Events.me()), key)]
    if not ev or ev.status ~= "active" then return false end
    t = t or now()
    ev.status, ev.change, ev.revokedReason = "revoked", "revocation", reason or "back"
    ev.revision, ev.revisedAt = ev.revision + 1, t
    enqueue(s, ev, t)
    return true
end

function Events.get(key)
    local s = Events.state(false)
    return s and s.events[Events.idFor(S().guidOf(Events.me()), key)] or nil
end

---------------------------------------------------------------------------
-- Observing Adventure (read-only on its data)
---------------------------------------------------------------------------

-- activityType / destinationID of a ticket view. Zones are place names, not people.
function Events.destination(v)
    if v.dungeon then
        local cat = ns.AdventureData and ns.AdventureData.category(v.dungeon) or "dungeon"
        return cat == "raid" and "raid" or "dungeon", v.dungeon
    end
    if v.quests and #v.quests > 0 then
        local ids = {}
        for _, q in ipairs(v.quests) do ids[#ids + 1] = tostring(q) end
        return "quest", "q:" .. table.concat(ids, ".")
    end
    if v.zone then return "zone", "z:" .. v.zone end
    return "other", nil
end

local function findMe(list, my)
    for _, x in ipairs(list or {}) do if x.a == my then return x end end
end

local function myAction(id, my)
    for _, e in ipairs(A().listOf(my, "A")) do if e.id == id then return e end end
end

-- How I got on a ticket: worker_match (I accepted an invitation) or direct_signup.
function Events.pathOf(e)
    if not e then return nil end
    local how = (e.ac == "wd" or e.ac == "ir") and e.ak or e.ac
    if how == "ia" then return "worker_match" end
    if how == "ap" then return "direct_signup" end
    return nil
end

-- R-16.24 / R-17.3: my own proof that I took part: I saw it done in its window
-- (dt), or I saw enough accepted people with me in the party once it was
-- finalized (fp). Triggers from before a step back do not count. Nothing else
-- (a full roster, the leader's 完成, 60% of the group) proves that I was there.
function Events.memberEvidence(v, e)
    if not e then return nil end
    if e.dt and e.dt > (v.doneBack or 0) and v.slot then
        local from, to = A().autoWindow(v.slot)
        if e.dt >= from and e.dt <= to then return "self_detected" end
    end
    if e.fp and v.finalAt and e.fp >= v.finalAt and e.fp > (v.formedBack or 0) then return "self_party" end
    return nil
end

local function key(...) return table.concat({ ... }, "|") end

-- One ticket view. Called after every Adventure write and from Adventure.maintain.
function Events.observe(v, t)
    if type(v) ~= "table" or not v.id then return end
    local my = Events.me()
    if not my then return end
    t = t or now()
    local activity, dest = Events.destination(v)
    local raid = activity == "raid"
    local base = { adventureID = v.id, activityType = activity, destinationID = dest }
    local function with(extra)
        local f = {}
        for k, x in pairs(base) do f[k] = x end
        for k, x in pairs(extra) do f[k] = x end
        return f
    end
    if v.leader == my then
        local role = (v.capacity and v.capacity.any and "any") or v.leaderRole or "d"
        Events.ensure(key(v.id, "adventure_created"), with({ eventType = "adventure_created",
            participationPath = "leader", role = role, observedAt = v.created, evidence = "self" }), t)
        if raid then return end -- 團本: never formed / done (spec §9.1)
        if v.final then
            Events.ensure(key(v.id, "adventure_finalized"), with({ eventType = "adventure_finalized",
                participationPath = "leader", role = role, observedAt = v.finalAt or t, evidence = "slot" }), t)
        elseif v.state == "open" then
            Events.revoke(key(v.id, "adventure_finalized"), "back", t)
        end
        if v.formed or v.state == "done" or v.state == "unfinished" then
            Events.ensure(key(v.id, "adventure_formed"), with({ eventType = "adventure_formed",
                participationPath = "leader", role = role, observedAt = v.formedAt or t, evidence = v.formedBy or "formed" }), t)
        elseif v.state == "open" or v.state == "final" then
            Events.revoke(key(v.id, "adventure_formed"), "back", t)
        end
        if v.state == "done" then
            local ev = v.auto and "auto" or "leader_done"
            Events.ensure(key(v.id, "adventure_done"), with({ eventType = "adventure_done",
                participationPath = "leader", role = role, observedAt = v.closedAt or t, evidence = ev }), t)
            Events.ensure(key(v.id, "participant_done", my), with({ eventType = "participant_done",
                participationPath = "leader", role = role, observedAt = v.closedAt or t, evidence = ev }), t)
        else
            Events.revoke(key(v.id, "adventure_done"), "back", t)
            Events.revoke(key(v.id, "participant_done", my), "back", t)
        end
        local terminal = ({ cancel = "adventure_cancelled", ended = "adventure_expired", unfinished = "adventure_unfinished" })[v.state]
        if terminal then
            Events.ensure(key(v.id, terminal), with({ eventType = terminal, participationPath = "leader",
                role = role, observedAt = v.closedAt or t, evidence = v.closeReason or "state" }), t)
        end
        return
    end
    -- Someone else's ticket: my signup, my invitation, my seat.
    local e = myAction(v.id, my)
    local member = findMe(v.members, my)
    local invited = findMe(v.invited, my)
    local path = Events.pathOf(e)
    if e and (e.ac == "ap" or e.ak == "ap") then
        Events.ensure(key(v.id, "signup_applied", my), with({ eventType = "signup_applied",
            participationPath = "direct_signup", role = e.ro, observedAt = (e.ak == "ap" and e.ap) or e.at or t, evidence = "self" }), t)
    end
    if raid then return end
    local s = Events.state(false)
    local order = s and s.workerOrder
    if order and order.id and (invited or path == "worker_match") then
        Events.ensure(key(order.id, v.id, "worker_order_matched"), with({ eventType = "worker_order_matched",
            workerOrderID = order.id, participationPath = "worker_match", observedAt = (invited and invited.at) or (e and e.ap) or t,
            evidence = "invited" }), t)
    end
    if member then
        local role = member.role or (e and e.ro)
        local f = with({ eventType = "participant_admitted", participationPath = path or "direct_signup",
            role = role, observedAt = member.at or t, evidence = "seat" })
        if path == "worker_match" and order then f.workerOrderID = order.id end
        Events.ensure(key(v.id, "participant_admitted", my), f, t)
    end
    local doneKey = key(v.id, "participant_done", my)
    if v.state == "done" and member then
        local evidence = Events.memberEvidence(v, e)
        if evidence then
            local f = with({ eventType = "participant_done", participationPath = path or "direct_signup",
                role = member.role or (e and e.ro), observedAt = v.closedAt or t, evidence = evidence })
            local adm = Events.get(key(v.id, "participant_admitted", my))
            if adm and adm.workerOrderID then f.workerOrderID = adm.workerOrderID end
            Events.ensure(doneKey, f, t)
        elseif not Events.get(doneKey) then
            -- Unknown is not counted (spec §9.1); counted once per ticket for the diagnostics.
            local st = Events.state(true)
            if st and not st.skipped[v.id] then
                st.stats.noEvidence = st.stats.noEvidence + 1
                st.skipped[v.id] = t
                local list = {}
                for id, at in pairs(st.skipped) do list[#list + 1] = { id = id, at = at } end
                if #list > Events.MAX_SKIPPED then
                    table.sort(list, function(x, y) return x.at < y.at end)
                    for i = 1, #list - Events.MAX_SKIPPED do st.skipped[list[i].id] = nil end
                end
            end
        end
    elseif v.state ~= "done" then
        Events.revoke(doneKey, "back", t)
    end
end

function Events.observeId(id, t)
    local v = A().get(id)
    if v then Events.observe(v, t) end
end

-- Every ticket I lead or signed up for (Adventure.maintain, once a minute).
function Events.observeAll(views, t)
    local my = Events.me()
    if not my then return 0 end
    views = views or A().all()
    local mineA = {}
    for _, e in ipairs(A().listOf(my, "A")) do mineA[e.id] = true end
    local n = 0
    for id, v in pairs(views) do
        if v.leader == my or mineA[id] or findMe(v.members, my) or findMe(v.invited, my) then
            Events.observe(v, t)
            n = n + 1
        end
    end
    local s = Events.state(false)
    if s then Events.prune(s, t) end
    return n
end

-- My worker ticket was saved. prev = my W entry before (nil: there was none),
-- entry = the one saved (nil: removed). A new one is a new order; an edit or a
-- 重開 of the one that just closed is the same order (no second 建立).
function Events.onWorkerSaved(prev, entry, t)
    t = t or now()
    local my = Events.me()
    if not my then return end
    if not entry then
        local s = Events.state(false)
        if s then s.workerOrder = nil end
        return
    end
    local s = Events.state(true)
    if prev and s.workerOrder and s.workerOrder.id then return end -- edit / reopen: the same order
    local id = "w" .. S().hash(my) .. "." .. S().b36(entry.cr or t)
    s.workerOrder = { id = id, at = entry.cr or t }
    Events.ensure(key(id, "worker_order_created"), { eventType = "worker_order_created", workerOrderID = id,
        participationPath = "worker_match", activityType = "worker", role = entry.rm, observedAt = entry.cr or t,
        evidence = "self" }, t)
end

-- 重開 (R-4.7 / R-17.5): the new ticket's 建立 points at the one it replaces, so a
-- count of tickets can leave reopened ones out. It is still its own adventure.
function Events.onReopen(oldId, newId, t)
    t = t or now()
    local my = Events.me()
    if not my or not oldId then return end
    local s = Events.state(false)
    if not s then return end
    local target
    if newId then target = Events.get(key(newId, "adventure_created"))
    else
        -- From Adventure.forget (the UI's 重開): my newest ticket created in the last minute.
        for _, ev in pairs(s.events) do
            if ev.eventType == "adventure_created" and ev.adventureID ~= oldId and t - (ev.observedAt or 0) <= 60
                and (not target or (ev.observedAt or 0) > (target.observedAt or 0)) then target = ev end
        end
    end
    if target and not target.reopenOf then target.reopenOf = oldId end
end

---------------------------------------------------------------------------
-- Queue API (not wired to GF Sync yet)
---------------------------------------------------------------------------

-- The upload shape of one event: only FIELDS (no ackRev, no names).
function Events.export(ev)
    local out = {}
    for _, k in ipairs(Events.FIELDS) do out[k] = ev[k] end
    return out
end

-- Waiting events (never sent, or sent and not confirmed for RESEND_AFTER), oldest first.
function Events.pending(limit, t)
    local s = Events.state(false)
    if not s then return {} end
    t = t or now()
    local list = {}
    for id, q in pairs(s.queue) do
        local ev = s.events[id]
        if ev and (not q.sent or t - q.sent >= Events.RESEND_AFTER) then list[#list + 1] = { id = id, at = q.at } end
    end
    table.sort(list, function(x, y) if x.at ~= y.at then return x.at < y.at end return x.id < y.id end)
    local out = {}
    for i, x in ipairs(list) do
        if limit and i > limit then break end
        out[#out + 1] = Events.export(s.events[x.id])
    end
    return out
end

function Events.markSent(ids, t)
    local s = Events.state(false)
    if not s then return 0 end
    t = t or now()
    local n = 0
    for _, id in ipairs(ids or {}) do
        local q = s.queue[id]
        if q then q.sent, q.tries = t, (q.tries or 0) + 1; n = n + 1 end
    end
    return n
end

-- A receipt for one revision: the queue entry goes when that (or a later) revision is confirmed.
function Events.confirm(id, rev)
    local s = Events.state(false)
    local ev = s and s.events[id]
    if not ev then return false end
    rev = tonumber(rev) or ev.revision
    ev.ackRev = math.max(ev.ackRev or 0, rev)
    local q = s.queue[id]
    if q and rev >= q.rev then s.queue[id] = nil; return true end
    return false
end

-- Delete one event here (owner / diagnostics). It is not sent again.
function Events.forget(id)
    local s = Events.state(false)
    if not s or not s.events[id] then return false end
    s.events[id], s.queue[id] = nil, nil
    s.n = s.n - 1
    return true
end

-- Copyable JSON of the waiting events (diagnostics export).
function Events.exportJSON(limit)
    local js = ns.Export.jsonString
    local parts = {}
    for _, ev in ipairs(Events.pending(limit)) do
        local fields = {}
        for _, k in ipairs(Events.FIELDS) do
            local x = ev[k]
            if x ~= nil then
                local val = type(x) == "number" and tostring(x) or type(x) == "boolean" and tostring(x) or js(x)
                fields[#fields + 1] = js(k) .. ":" .. val
            end
        end
        parts[#parts + 1] = "{" .. table.concat(fields, ",") .. "}"
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

---------------------------------------------------------------------------
-- Counts (diagnostics / internal analysis only; spec §9.1: no public page)
---------------------------------------------------------------------------

-- Leader tickets and worker orders are counted apart (spec §12.2); a 成行 counts
-- once per adventure whatever the path (participations), split by path too.
function Events.summary(a)
    local s = Events.state(false, a)
    local out = { leader = {}, worker = { created = 0, matched = 0, admitted = 0, completed = 0 },
        direct = { applied = 0, admitted = 0, done = 0 }, participations = 0, byPath = {}, reopened = 0,
        total = 0, active = 0, revoked = 0, test = 0 }
    for _, k in ipairs(Events.LEADER_TYPES) do out.leader[k:gsub("^adventure_", "")] = 0 end
    if not s then return out end
    local doneBy = {}
    for _, ev in pairs(s.events) do
        out.total = out.total + 1
        if ev.test then out.test = out.test + 1
        elseif ev.status == "revoked" then out.revoked = out.revoked + 1
        else
            out.active = out.active + 1
            local ty = ev.eventType
            if ty:match("^adventure_") then
                local k = ty:gsub("^adventure_", "")
                out.leader[k] = out.leader[k] + 1
                if k == "created" and ev.reopenOf then out.reopened = out.reopened + 1 end
            elseif ty == "worker_order_created" then out.worker.created = out.worker.created + 1
            elseif ty == "worker_order_matched" then out.worker.matched = out.worker.matched + 1
            elseif ty == "signup_applied" then out.direct.applied = out.direct.applied + 1
            elseif ty == "participant_admitted" then
                if ev.participationPath == "worker_match" then out.worker.admitted = out.worker.admitted + 1
                else out.direct.admitted = out.direct.admitted + 1 end
            elseif ty == "participant_done" then
                if ev.participationPath == "worker_match" then out.worker.completed = out.worker.completed + 1
                elseif ev.participationPath == "direct_signup" then out.direct.done = out.direct.done + 1 end
                doneBy[ev.adventureID] = doneBy[ev.adventureID] or ev.participationPath
            end
        end
    end
    for _, p in pairs(doneBy) do
        out.participations = out.participations + 1
        out.byPath[p] = (out.byPath[p] or 0) + 1
    end
    return out
end

function Events.queueStats(t)
    local s = Events.state(false)
    local o = { queued = 0, sent = 0, due = 0, n = 0, overflow = 0, noEvidence = 0, warn = false }
    if not s then return o end
    t = t or now()
    for _, q in pairs(s.queue) do
        o.queued = o.queued + 1
        if q.sent then o.sent = o.sent + 1 end
        if not q.sent or t - q.sent >= Events.RESEND_AFTER then o.due = o.due + 1 end
    end
    o.n, o.overflow, o.noEvidence = s.n, s.stats.overflow, s.stats.noEvidence
    o.warn = s.n >= Events.WARN_AT or o.overflow > 0
    return o
end

function Events.diagText()
    local q = Events.queueStats()
    local sm = Events.summary()
    local L = sm.leader
    local parts = {
        string.format("事件 %d 筆（有效 %d、已撤銷 %d、測試 %d）", sm.total, sm.active, sm.revoked, sm.test),
        string.format("開單：建立 %d、定案 %d、成團 %d、成行 %d、取消 %d、過期 %d、未成行 %d",
            L.created, L.finalized, L.formed, L.done, L.cancelled, L.expired, L.unfinished),
        string.format("職工單：建立 %d、媒合 %d、錄取 %d、接單完成 %d", sm.worker.created, sm.worker.matched, sm.worker.admitted, sm.worker.completed),
        string.format("直接報名：報名 %d、錄取 %d、成行 %d", sm.direct.applied, sm.direct.admitted, sm.direct.done),
        string.format("本人成行 %d 次（不重複冒險）｜無證據未計 %d", sm.participations, q.noEvidence),
        string.format("待上傳 %d 筆（已送未確認 %d）｜容量 %d／%d", q.queued, q.sent, q.n, Events.MAX_EVENTS),
        "尚未接 GF Sync：只存在這台電腦",
    }
    if q.warn then
        parts[#parts + 1] = q.overflow > 0 and string.format("容量已滿，%d 筆新事件沒有記錄", q.overflow) or "容量快滿"
    end
    return table.concat(parts, "｜")
end
