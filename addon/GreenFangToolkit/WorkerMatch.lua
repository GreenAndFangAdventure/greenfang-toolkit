-- WorkerMatch (GF-014-02, owner 2026-11-26): while my worker ticket (職工單)
-- is up, open adventure tickets of other members that fit it become one
-- 業務通知 each; a click on it opens 冒險業務 at that ticket (UI.focus), and
-- I press 申請 myself. Nothing is sent or uploaded from here: the matching
-- runs on this computer over what the ledger already holds.
--
-- What fits is Adventure.matches (the same rule the leaders' list uses):
-- the dungeon or the zone (or a shared quest), a free seat for my role, my
-- level and an overlapping slot. Ranked by how much is shared (a group /
-- elite quest, a quest, the place), then the number of shared quests, then
-- an online leader, then the earliest slot.
--
-- One notice per ticket (key "match|<ticket id>"): the next scans only push
-- again when the ticket changed (its version or its slots), so a read notice
-- does not come back every few minutes. A notice goes when the ticket no
-- longer fits (ended, cancelled, full, no seat for my role, I am in it or
-- invited), when my worker ticket is gone, when a switch turns it off, or at
-- its ttl (the end of the ticket's last slot, or my worker ticket's end).
-- GF-014's rules hold: its switch, its throttle, its burst limit, and in
-- combat the notice only waits (Notify.push queues it).
--
-- Settings, per character (事務設定 → 業務通知 → 設定, the bell's list):
--   on      the whole feature (default on: only someone who put a worker
--           ticket up gets these, and that is asking to be found)
--   alt     my support role counts too (default on; off = main role only)
--   quests  a shared quest alone counts (default on; off = the dungeon or
--           the zone must match)
--   chat    also one chat line for a new match (default off: GF-014 already
--           has its own chat line for new notices)

local _, ns = ...
local str = ns.str

local M = {}
ns.WorkerMatch = M

M.MODULE = "adventure"
M.KEY_PREFIX = "match|"
M.DEBOUNCE = 2           -- seconds after a change before the scan
M.RESCAN = 120           -- seconds between scans while my worker ticket is up (slots end by time)
M.CHAT_GAP = 60          -- at most one chat line a minute
M.MIN_TTL = 60
M.DEFAULTS = { on = true, alt = true, quests = true, chat = false }
M.OPTIONS = {
    { key = "on", text = "職工單配對", tip = "我的職工單符合別人的冒險單時通知我（只在這台電腦比對）" },
    { key = "alt", text = "副職責也算", tip = "關掉時只比對主職責", sub = true },
    { key = "quests", text = "共同任務也算", tip = "關掉時地城或區域要相同", sub = true },
    { key = "chat", text = "配對時聊天框一行", tip = "另外在聊天框留一行（最多每分鐘一次）", sub = true },
}

local function A() return ns.Adventure end
local function N() return ns.Notify end
local function now() return ns.now() end

---------------------------------------------------------------------------
-- Settings (this character; GreenFangToolkitDB.settings.modules.notify.characters)
---------------------------------------------------------------------------

function M.settings()
    local F = ns.Framework
    local cs = (ns.db and F and F.charState) and F.charState("notify") or {}
    if type(cs.workerMatch) ~= "table" then cs.workerMatch = {} end
    return cs.workerMatch
end
function M.get(key)
    local v = M.settings()[key]
    if v == nil then return M.DEFAULTS[key] end
    return v == true
end
function M.set(key, on)
    if M.DEFAULTS[key] == nil then return end
    M.settings()[key] = on and true or false
    M.scan()
end

---------------------------------------------------------------------------
-- Matching (pure over Adventure's views)
---------------------------------------------------------------------------

local function involved(v, my)
    for _, list in ipairs({ v.members or {}, v.waitlist or {}, v.pending or {}, v.invited or {} }) do
        for _, x in ipairs(list) do if x.a == my then return true end end
    end
    return false
end

-- My worker ticket as Adventure.matches takes it, after the 副職責 switch.
function M.myWorker(opts)
    local my = ns.Share.selfAuthor()
    if not my then return nil end
    local w = A().workers()[my]
    if not w then return nil end
    local useAlt = opts and opts.alt
    if useAlt == nil then useAlt = M.get("alt") end
    if useAlt then return w end
    local copy = {}
    for k, x in pairs(w) do copy[k] = x end
    copy.alt = nil
    return copy
end

local function placeHit(v, w)
    if v.dungeon and w.dungeons and w.dungeons[v.dungeon] then return true end
    if v.zone and w.zones and w.zones[v.zone] then return true end
    return false
end

-- The role I would take there: my main role when it has a seat, else my support role.
function M.roleFor(v, w)
    if v.seats.any then return "any" end
    if w.main and (v.seats[w.main] or 0) > 0 then return w.main end
    if w.alt and (v.seats[w.alt] or 0) > 0 then return w.alt end
    return nil
end

-- When the ticket is over: the end of its last slot (the finalized one only),
-- a slot without a length counting Adventure.SLACK after its start.
function M.ticketEnd(v)
    local Adv = A()
    local slots = v.slots or {}
    if v.final and v.slotById and v.slotById[v.final] then slots = { v.slotById[v.final] } end
    local last
    for _, sl in ipairs(slots) do
        local s = sl.s or v.created
        if s then
            local e = s + (sl.d or Adv.SLACK)
            if not last or e > last then last = e end
        end
    end
    return last
end

-- Every open ticket that fits my worker ticket, best first:
-- { view, score, shared, role, slot (the first overlapping one), ends }.
function M.candidates(opts)
    opts = opts or {}
    local Adv = A()
    local my = ns.Share.selfAuthor()
    local w = M.myWorker(opts)
    if not (my and w) then return {} end
    local quests = opts.quests
    if quests == nil then quests = M.get("quests") end
    local log = Adv.questLog()
    local level = Adv.myLevel()
    local out = {}
    for _, v in pairs(Adv.all()) do
        if v.leader ~= my and not v.closed and not v.departed and not involved(v, my) then
            local hit, _, score = Adv.matches(v, w, level, log)
            if hit and not quests and not placeHit(v, w) then hit = false end
            local role = hit and M.roleFor(v, w) or nil
            if hit and role then
                local shared = 0
                for _, q in ipairs(v.quests or {}) do
                    if Adv.shares(w, tonumber(q) or q, log) then shared = shared + 1 end
                end
                local ids = Adv.overlapSlots(v, w.slots or {})
                local slot
                for _, sl in ipairs(v.slots or {}) do if sl.id == ids[1] then slot = sl end end
                out[#out + 1] = { view = v, score = score or 0, shared = shared, role = role,
                    slot = slot or (v.slots or {})[1], ends = M.ticketEnd(v) }
            end
        end
    end
    table.sort(out, function(x, y)
        if x.score ~= y.score then return x.score > y.score end
        if x.shared ~= y.shared then return x.shared > y.shared end
        local ox, oy = x.view.leaderOffline and 1 or 0, y.view.leaderOffline and 1 or 0
        if ox ~= oy then return ox < oy end
        local sx, sy = (x.slot and x.slot.s) or 0, (y.slot and y.slot.s) or 0
        if sx ~= sy then return sx < sy end
        return tostring(x.view.id) < tostring(y.view.id)
    end)
    return out
end

---------------------------------------------------------------------------
-- The notice
---------------------------------------------------------------------------

local function plain(s) return (str(s):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")) end

-- "職工單配對：死亡礦坑 明天 20:00 缺坦"
function M.text(c)
    local U = ns.AdventureUI
    local v = c.view
    local dest = (U and U.destText) and plain(U.destText(v)) or str(v.dungeon or v.zone or "")
    local when = (U and U.slotText and c.slot) and plain(U.slotText(c.slot)) or ""
    local role = (U and U.ROLE_NAME and U.ROLE_NAME[c.role]) or ""
    return "職工單配對：" .. dest .. (when ~= "" and (" " .. when) or "") .. (role ~= "" and (" 缺" .. role) or "")
end

-- What makes a ticket "the same" for the memory: its version and slots.
local function signature(c)
    local v = c.view
    local parts = { tostring(v.edited or v.created or ""), tostring(v.final or "") }
    for _, sl in ipairs(v.slots or {}) do parts[#parts + 1] = tostring(sl.id) .. ":" .. tostring(sl.s) .. ":" .. tostring(sl.d) end
    parts[#parts + 1] = c.role
    return table.concat(parts, ",")
end

local function memory()
    local mem = N().memory(M.MODULE)
    if type(mem.sent) ~= "table" then mem.sent = {} end
    return mem
end

local lastChat = -math.huge
M.stats = { scans = 0, pushed = 0, cleared = 0, chat = 0 }

-- Push the new / changed matches, clear the ones that no longer fit.
-- Returns the candidates (scripts and tests).
function M.scan()
    M.stats.scans = M.stats.scans + 1
    if not (ns.db and N() and A()) then return {} end
    local mem = memory()
    local list = M.get("on") and M.candidates() or {}
    local t = now()
    local live = {}
    local myEnd
    local w = M.myWorker({ alt = true })
    if w then myEnd = w.expires end
    for _, c in ipairs(list) do
        local id = tostring(c.view.id)
        live[id] = true
        local sig = signature(c)
        if mem.sent[id] ~= sig then
            local ends = c.ends or (t + N().TTL)
            if myEnd and myEnd < ends then ends = myEnd end
            local ttl = math.max(M.MIN_TTL, ends - t)
            local res = N().push({ module = M.MODULE, key = M.KEY_PREFIX .. id, text = M.text(c),
                target = { page = "adventure", id = c.view.id }, ttl = ttl })
            if res == "stored" or res == "merged" or res == "quiet" or res == "queued" then
                mem.sent[id] = sig
                M.stats.pushed = M.stats.pushed + 1
                if res ~= "queued" and M.get("chat") and not ns.inCombat() and t - lastChat >= M.CHAT_GAP then
                    lastChat = t
                    M.stats.chat = M.stats.chat + 1
                    ns.say(M.text(c))
                end
            end
        end
    end
    -- Gone: forget them and drop their notices.
    for id in pairs(mem.sent) do if not live[id] then mem.sent[id] = nil end end
    local n = N().clear(M.MODULE, function(key)
        local id = str(key):match("^" .. M.KEY_PREFIX:gsub("|", "%%|") .. "(.+)$")
        return id ~= nil and not live[id]
    end)
    M.stats.cleared = M.stats.cleared + (n or 0)
    if w then M.rescanLater() end
    return list
end

-- After a change (the adventure ledger, my worker ticket), a little later and once.
local pending = false
function M.schedule()
    if pending then return end
    pending = true
    ns.after(M.DEBOUNCE, function() pending = false; M.scan() end)
end
local rescan = false
function M.rescanLater()
    if rescan then return end
    rescan = true
    ns.after(M.RESCAN, function() rescan = false; M.scan() end)
end

if A() and A().onChange then A().onChange(function() M.schedule() end) end
if N() and N().register then N().register(M.MODULE, {}) end

-- The rows under 業務通知 → 設定 (NotifyUI draws a module's options when it has them).
for _, m in ipairs(N() and N().MODULES or {}) do
    if m.key == M.MODULE then
        m.options = {}
        for _, o in ipairs(M.OPTIONS) do
            local key = o.key
            m.options[#m.options + 1] = { key = key, text = o.text, tip = o.tip, sub = o.sub,
                get = function() return M.get(key) end, set = function(on) M.set(key, on) end }
        end
    end
end
