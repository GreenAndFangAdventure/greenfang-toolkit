-- BankRequests (GF-012-D, spec v2.0 §8.2 MVP, owner 2026-11-28): 臨時黑箱
-- phase 3: 申領 → 核准／拒絕 → 已交付 → 已收到. Hand-over is always by hand
-- (the custodian trades or mails it); nothing here mails, trades or pays.
-- No quotas, no automatic approval, no item classes, nothing uploaded
-- (every group is local = true: GF Sync leaves it out).
--
-- Who writes what (one Share record group per role, each author only their own):
--   KR  the requester: their own requests (申領), 取消, 已收到
--   KD  an approver (會長, the custodian asked, a 審核幹部 of Bank.officers):
--       核准 / 拒絕 (with a short reason)
--   KA  the custodian: the reservation (預留, the only real 核准 of the
--       stock), 數量不足 (the stock was not enough when it got there), 已交付
-- A record from anybody else is stored and relayed by Share (it must be), but
-- never used: a decision counts only from someone who may decide now (the
-- current guild master by the roster, the custodian asked, an enabled
-- reviewer), not older than their list entry (revoked and appointed again:
-- the old decisions stay gone), and not older than the request. An
-- allocation counts only from the custodian the request names, not older
-- than that custodian's list entry. A request to a custodian who is no
-- longer enabled (or was appointed again after it) is void.
--
-- How a request's state is worked out (the same on every computer):
--   1. the custodian's KA entry wins: r = 已核准 (reserved), s = 數量不足,
--      d = 已交付 (完成 once the requester pressed 已收到);
--   2. else 取消 by the requester;
--   3. else the earliest valid decision (ties: the smaller author id):
--      reject = 已拒絕, approve = 已核准 (not reserved yet: counted until the
--      custodian's computer turns it into r or s);
--   4. else 等待核准. 7 days without a decision (Req.EXPIRE), or 7 days
--      approved without 已交付: 已過期 (its reservation goes).
-- The custodian's computer (Req.settle) takes valid approvals in order
-- (decision time, then key) and reserves while 可申領 is enough, else writes
-- 數量不足: two approvals of 8 for a stock of 10 reserve only one.
-- 可申領 = max(0, shared − reserved), reserved = reservations and approvals
-- not delivered and not expired; a delivered one still counts until the
-- viewer holds the custodian's stock snapshot taken at 已交付 (snapT), so the
-- hand-over and the next scan are never both taken off.
-- Kept: a closed request (完成／拒絕／取消／過期／數量不足／失效) for
-- Req.KEEP (60 days) after it closed, then its author drops it.
-- Nothing runs on a timer: states are worked out when read; the custodian's
-- settle and the notices run after a record changes, at login and when the
-- page opens; never in combat (after combat instead).

local _, ns = ...
local str = ns.str

local Req = {}
ns.BankRequests = Req

Req.REQ_GROUP, Req.DEC_GROUP, Req.ALLOC_GROUP = "KR", "KD", "KA"
Req.GROUPS = { "KR", "KD", "KA" }
Req.FORMAT = "1"
Req.EXPIRE = 7 * 86400
Req.KEEP = 60 * 86400
Req.MAX_QTY = 9999
Req.NOTE_MAX = 45          -- bytes (about 15 Chinese characters)
Req.MAX_OPEN = 10          -- my requests waiting or approved at once
Req.MAX_ENTRIES = { KR = 30, KD = 60, KA = 60 }
Req.MAX_VALUE = { KR = 3200, KD = 4800, KA = 4400 }
Req.PURPOSES = { { key = "p", text = "練專業" }, { key = "d", text = "打副本" }, { key = "q", text = "解任務" },
    { key = "o", text = "其他" } }
Req.PURPOSE_NAME = {}
for _, p in ipairs(Req.PURPOSES) do Req.PURPOSE_NAME[p.key] = p.text end
Req.STATE_NAME = {
    pending = "等待核准", approved = "已核准，等保管人交付", delivered = "已交付，等申請人按已收到",
    done = "完成", rejected = "已拒絕", cancelled = "已取消", expired = "已過期",
    short = "數量不足，請重新申領", void = "保管人已撤銷，申領失效",
}
Req.OPEN = { pending = true, approved = true }
Req.CLOSED = { done = true, rejected = true, cancelled = true, expired = true, short = true, void = true }
Req.RESULT = {
    ok = "已送出", combat = "戰鬥中，結束後再按", ["no-guild"] = "不在公會或名冊還沒載入",
    keeper = "請選一位保管人", self = "不能向自己申領", qty = "數量不對", more = "超過可申領的數量",
    purpose = "請選一個用途", full = "等待中的申領太多了，請先處理舊的", ["not-found"] = "找不到這筆申領",
    state = "這筆申領現在不能這樣做", ["no-right"] = "你不能處理這筆申領", short = "可申領的數量不夠，不能核准",
    approved = "已核准", rejected = "已拒絕", delivered = "已標記為已交付", received = "完成",
    cancelled = "已取消",
}

local stats = { builds = 0, settled = 0, reserved = 0, short = 0, ignored = 0, rejected = 0, healed = 0,
    pruned = 0, pushed = 0, waited = 0 }
Req.stats = stats

local function S() return ns.Share end
local function B() return ns.Bank end
local function K() return ns.BankStock end
local function b36(n) return ns.Share.b36(n) end
local function unb36(s) return ns.Share.unb36(s) end
local function now() return math.floor(S().serverNow()) end

local function validA(a) return type(a) == "string" and a ~= "" and a:find("^[%w%-]+$") ~= nil end

-- A note or reason: the player's own words, cleaned (no |-codes, no control
-- characters, at most Req.NOTE_MAX bytes), with the wire's separators escaped.
function Req.clean(s) return ns.cleanText(str(s), Req.NOTE_MAX) end
local function esc(s)
    return (str(s):gsub("[%%;,/~]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function unesc(s) return (s:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)) end
Req.esc, Req.unesc = esc, unesc

local function timeOk(t) return t and t >= S().EPOCH and t <= S().serverNow() + S().FUTURE end

---------------------------------------------------------------------------
-- Wire values (format 1): "1;" .. entries joined by "/", fields by ",".
--   KR  <id>,<keeperA>,<itemID>,<qty>,<purpose>,<created>,<state>,<stateT>,<note>
--       state o = 申領中, c = 取消, g = 已收到; purpose p / d / q / o
--   KD  <requesterA>,<id>,<a|r>,<t>,<reason>          (a = 核准, r = 拒絕)
--   KA  <requesterA>,<id>,<r|s|d>,<itemID>,<qty>,<t>,<reservedT>,<byA>,<snapT>
--       r = 預留, s = 數量不足, d = 已交付; byA = whose approval; snapT = my
--       stock snapshot's time at 已交付 (0 otherwise)
-- Numbers base 36. A value longer than Req.MAX_VALUE, more entries than
-- Req.MAX_ENTRIES, a repeated key or any bad field: refused (never stored).
---------------------------------------------------------------------------

local function entriesOf(v, g)
    if type(v) ~= "string" or #v > Req.MAX_VALUE[g] then return nil end
    local body = v:match("^1;(.*)$")
    if not body then return nil end
    local out = {}
    if body == "" then return out end
    for item in (body .. "/"):gmatch("([^/]*)/") do
        if #out >= Req.MAX_ENTRIES[g] then return nil end
        local f = {}
        for x in (item .. ","):gmatch("([^,]*),") do f[#f + 1] = x end
        out[#out + 1] = f
    end
    return out
end

local function bad() stats.rejected = stats.rejected + 1; return nil end

function Req.decodeKR(v)
    local list = entriesOf(v, "KR")
    if not list then return bad() end
    local out, seen = {}, {}
    for _, f in ipairs(list) do
        if #f ~= 9 then return bad() end
        local e = { id = unb36(f[1]), keeper = f[2], itemID = unb36(f[3]), qty = unb36(f[4]), purpose = f[5],
            created = unb36(f[6]), state = f[7], st = unb36(f[8]) }
        if not e.id or seen[e.id] or not validA(e.keeper) or not e.itemID or e.itemID <= 0 or not e.qty
            or e.qty < 1 or e.qty > Req.MAX_QTY or not Req.PURPOSE_NAME[e.purpose] or not timeOk(e.created)
            or not (e.state == "o" or e.state == "c" or e.state == "g") or not timeOk(e.st) or e.st < e.created then
            return bad()
        end
        e.note = Req.clean(unesc(f[9]))
        seen[e.id] = true
        out[#out + 1] = e
    end
    return out
end

function Req.decodeKD(v)
    local list = entriesOf(v, "KD")
    if not list then return bad() end
    local out, seen = {}, {}
    for _, f in ipairs(list) do
        if #f ~= 5 then return bad() end
        local e = { req = f[1], id = unb36(f[2]), d = f[3], t = unb36(f[4]) }
        local key = e.id and (e.req .. ":" .. f[2])
        if not validA(e.req) or not e.id or seen[key] or not (e.d == "a" or e.d == "r") or not timeOk(e.t) then return bad() end
        e.reason = Req.clean(unesc(f[5]))
        e.key = e.req .. ":" .. b36(e.id)
        seen[key] = true
        out[#out + 1] = e
    end
    return out
end

function Req.decodeKA(v)
    local list = entriesOf(v, "KA")
    if not list then return bad() end
    local out, seen = {}, {}
    for _, f in ipairs(list) do
        if #f ~= 9 then return bad() end
        local e = { req = f[1], id = unb36(f[2]), state = f[3], itemID = unb36(f[4]), qty = unb36(f[5]),
            t = unb36(f[6]), rt = unb36(f[7]), by = f[8], snapT = unb36(f[9]) }
        if not validA(e.req) or not e.id or not (e.state == "r" or e.state == "s" or e.state == "d")
            or not e.itemID or e.itemID <= 0 or not e.qty or e.qty < 1 or e.qty > Req.MAX_QTY
            or not timeOk(e.t) or not timeOk(e.rt) or e.rt > e.t or not validA(e.by) or not e.snapT
            or (e.snapT ~= 0 and not timeOk(e.snapT)) then
            return bad()
        end
        e.key = e.req .. ":" .. b36(e.id)
        if seen[e.key] then return bad() end
        seen[e.key] = true
        out[#out + 1] = e
    end
    return out
end

function Req.decode(g, v)
    if g == "KR" then return Req.decodeKR(v) end
    if g == "KD" then return Req.decodeKD(v) end
    if g == "KA" then return Req.decodeKA(v) end
    return nil
end

local function sortedKeys(t, less)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out, less)
    return out
end

function Req.encode(g, entries)
    local parts = {}
    if g == "KR" then
        for _, id in ipairs(sortedKeys(entries)) do
            local e = entries[id]
            parts[#parts + 1] = table.concat({ b36(id), e.keeper, b36(e.itemID), b36(e.qty), e.purpose, b36(e.created),
                e.state, b36(e.st), esc(Req.clean(e.note)) }, ",")
        end
    elseif g == "KD" then
        for _, key in ipairs(sortedKeys(entries)) do
            local e = entries[key]
            parts[#parts + 1] = table.concat({ e.req, b36(e.id), e.d, b36(e.t), esc(Req.clean(e.reason)) }, ",")
        end
    elseif g == "KA" then
        for _, key in ipairs(sortedKeys(entries)) do
            local e = entries[key]
            parts[#parts + 1] = table.concat({ e.req, b36(e.id), e.state, b36(e.itemID), b36(e.qty), b36(e.t),
                b36(e.rt), e.by, b36(e.snapT or 0) }, ",")
        end
    else
        return nil
    end
    return Req.FORMAT .. ";" .. table.concat(parts, "/")
end

---------------------------------------------------------------------------
-- My own entries (the original on this computer, per character):
-- GreenFangToolkitDB.bank.guilds[<guild>].req[<my author id>] =
--   { seq = n, KR = { [id] = entry }, KD = { [key] = entry }, KA = { [key] = entry } }
---------------------------------------------------------------------------

-- peek: do not create anything (Share asks every character for its values).
function Req.mine(peek)
    local g = B().guildData()
    local a = S().selfAuthor()
    if not g or not a then return nil end
    if peek and (type(g.req) ~= "table" or type(g.req[a]) ~= "table") then return nil end
    if type(g.req) ~= "table" then g.req = {} end
    local m = g.req[a]
    if type(m) ~= "table" then m = {}; g.req[a] = m end
    if type(m.seq) ~= "number" then m.seq = 0 end
    for _, gr in ipairs(Req.GROUPS) do
        if type(m[gr]) ~= "table" then m[gr] = {} end
        for k, e in pairs(m[gr]) do if type(e) ~= "table" then m[gr][k] = nil end end
    end
    return m
end

-- My value of a group now, or nil when I have nothing and never sent it.
function Req.ownValue(g)
    local m = Req.mine(true)
    if not m then return nil end
    local a = S().selfAuthor()
    if not next(m[g]) and not S().get(a, g) then return nil end
    return Req.encode(g, m[g])
end

local function publish(g)
    local v = Req.ownValue(g)
    if not v then return "none" end
    local r = S().ownRecord(g, v)
    return r
end
Req.publish = publish

---------------------------------------------------------------------------
-- Everybody's requests (worked out from the records; kept until a record,
-- the lists, the roster or the stock changes, or the minute turns)
---------------------------------------------------------------------------

Req.version = 0
local view = {}
function Req.invalidate() view = {} end

local function keyOf(a, id) return a .. ":" .. b36(id) end
Req.keyOf = keyOf

local function viewKey()
    local cur, oc = B().current(), B().officers()
    return table.concat({ Req.version, K().dataVersion, cur.state, cur.list and cur.list.epoch or 0, tostring(cur.leader),
        oc.state, oc.list and oc.list.epoch or 0, tostring(ns.Roster.version), math.floor(now() / 60) }, "|")
end

-- The custodian holder (BankStock.holders) of author a, or nil.
local function holderOf(a)
    for _, h in ipairs((K().holders())) do if h.a == a then return h end end
    return nil
end
-- The newest time in a custodian's snapshot as I hold it (bags part, tabs).
function Req.snapOf(h)
    if not h then return 0 end
    local t = h.bagsT or 0
    for _, tab in pairs(h.tabs or {}) do if tab.t and tab.t > t then t = tab.t end end
    return t
end
-- How many of an item a custodian shares now.
function Req.shared(a, itemID)
    local h = holderOf(a)
    if not h then return 0 end
    return (h.bags[itemID] or 0) + (h.bank[itemID] or 0)
end

-- Who may decide request v now (author d, at time t): the current guild
-- master by the roster, the custodian asked (enabled, not older than the
-- entry), an enabled reviewer (not older than the entry).
local function mayDecide(d, v, t, leaderA)
    if not validA(d) then return false end
    if d == leaderA then return true end
    if d == v.keeper then
        local on, e = B().isCustodian(d)
        return on == true and t >= e.epoch
    end
    local on, e = B().isOfficer(d)
    return on == true and t >= e.epoch
end
Req.mayDecide = mayDecide

local function derive(v, t)
    local A = v.alloc
    local E = Req.EXPIRE
    if v.e.state == "g" then
        v.state, v.closedAt = "done", v.e.st
    elseif A and A.state == "d" then
        v.state, v.at = "delivered", A.t
        v.closedAt = A.t
    elseif A and A.state == "s" then
        v.state, v.closedAt = "short", A.t
    elseif A and A.state == "r" and v.e.state == "c" then
        v.state, v.closedAt = "cancelled", v.e.st
    elseif A and A.state == "r" then
        if t - A.rt >= E then v.state, v.closedAt = "expired", A.rt + E
        else v.state, v.reserved = "approved", true end
    elseif v.e.state == "c" then
        v.state, v.closedAt = "cancelled", v.e.st
    elseif v.decision and v.decision.d == "r" then
        v.state, v.closedAt = "rejected", v.decision.t
    elseif v.decision then
        if t - v.decision.t >= E then v.state, v.closedAt = "expired", v.decision.t + E
        else v.state, v.provisional = "approved", true end
    elseif t - v.e.created >= E then
        v.state, v.closedAt = "expired", v.e.created + E
    else
        v.state = "pending"
    end
    if not v.keeperOk and (v.state == "pending" or v.state == "approved") then
        v.state, v.reserved, v.provisional, v.closedAt = "void", nil, nil, v.closedAt or t
    end
end

-- { list = { request views }, byKey, reserve = { [keeper] = { [itemID] = qty } },
--   firm (reservations only, no approvals still waiting for the custodian) }.
-- A request view: { key, req, id, e (its KR entry), keeper, itemID, qty,
-- purpose, note, created, alloc, decision, state, reserved, provisional,
-- at (newest event), closedAt }.
function Req.view()
    local key = viewKey()
    if view.key == key then return view end
    stats.builds = stats.builds + 1
    local t = now()
    local s = S().store()
    local out = { key = key, list = {}, byKey = {}, reserve = {}, firm = {}, orphans = {} }
    view = out
    if not s or B().current().state ~= "ok" then return out end
    local leaderA = B().rosterLeader()
    local allocs, decs = {}, {}
    for a, groups in pairs(s.rec) do
        if groups.KR then
            for _, e in ipairs(S().decoded(a, "KR") or {}) do
                local v = { key = keyOf(a, e.id), req = a, id = e.id, e = e, keeper = e.keeper, itemID = e.itemID,
                    qty = e.qty, purpose = e.purpose, note = e.note, created = e.created, at = e.st }
                local on, ke = B().isCustodian(e.keeper)
                v.keeperOk = on == true and e.created >= ke.epoch
                v.keeperEpoch = ke and ke.epoch
                out.list[#out.list + 1] = v
                out.byKey[v.key] = v
            end
        end
        if groups.KA then
            for _, e in ipairs(S().decoded(a, "KA") or {}) do allocs[#allocs + 1] = { a = a, e = e } end
        end
        if groups.KD then
            for _, e in ipairs(S().decoded(a, "KD") or {}) do decs[#decs + 1] = { a = a, e = e } end
        end
    end
    -- Allocations: only from the custodian the request names, not older than
    -- that custodian's entry. Without the request (not here yet): counted
    -- while it holds stock, if its author is an enabled custodian.
    for _, x in ipairs(allocs) do
        local v = out.byKey[x.e.key]
        if v then
            if x.a == v.keeper and v.keeperEpoch and x.e.t >= v.keeperEpoch and x.e.itemID == v.itemID then v.alloc = x.e
            else stats.ignored = stats.ignored + 1 end
        else
            local on, ke = B().isCustodian(x.a)
            if on and x.e.t >= ke.epoch then out.orphans[#out.orphans + 1] = { keeper = x.a, e = x.e } end
        end
    end
    -- Decisions: only from someone who may decide; the earliest wins.
    for _, x in ipairs(decs) do
        local v = out.byKey[x.e.key]
        if v and x.e.t >= v.created and mayDecide(x.a, v, x.e.t, leaderA) then
            local d = v.decision
            if not d or x.e.t < d.t or (x.e.t == d.t and x.a < d.a) then
                v.decision = { a = x.a, d = x.e.d, t = x.e.t, reason = x.e.reason }
            end
        elseif v then
            stats.ignored = stats.ignored + 1
        end
    end
    local snaps = {}
    local function snapFor(a)
        if snaps[a] == nil then snaps[a] = Req.snapOf(holderOf(a)) end
        return snaps[a]
    end
    local function add(tbl, a, id, q)
        tbl[a] = tbl[a] or {}
        tbl[a][id] = (tbl[a][id] or 0) + q
    end
    for _, v in ipairs(out.list) do
        derive(v, t)
        if v.decision and v.decision.t > (v.at or 0) then v.at = v.decision.t end
        if v.alloc and v.alloc.t > (v.at or 0) then v.at = v.alloc.t end
        if v.state == "approved" then
            add(out.reserve, v.keeper, v.itemID, v.qty)
            if v.reserved then add(out.firm, v.keeper, v.itemID, v.qty) end
        elseif v.alloc and v.alloc.state == "d" and v.alloc.snapT > snapFor(v.keeper) then
            v.pendingSnap = true
            add(out.reserve, v.keeper, v.itemID, v.qty)
            add(out.firm, v.keeper, v.itemID, v.qty)
        end
    end
    for _, o in ipairs(out.orphans) do
        local e = o.e
        if (e.state == "r" and t - e.rt < Req.EXPIRE) or (e.state == "d" and e.snapT > snapFor(o.keeper)) then
            add(out.reserve, o.keeper, e.itemID, e.qty)
            add(out.firm, o.keeper, e.itemID, e.qty)
        end
    end
    table.sort(out.list, function(x, y)
        if (x.at or 0) ~= (y.at or 0) then return (x.at or 0) > (y.at or 0) end
        return x.key < y.key
    end)
    return out
end

function Req.get(key) return Req.view().byKey[key] end

-- 可申領 of one custodian: max(0, shared − reserved).
function Req.available(keeper, itemID)
    local r = Req.view().reserve[keeper]
    return math.max(0, Req.shared(keeper, itemID) - (r and r[itemID] or 0))
end
-- 可申領 of an item over every custodian (a stock row; places = its places).
function Req.itemAvailable(item)
    local n = 0
    for _, p in ipairs(item.places or {}) do n = n + Req.available(p.h.a, item.itemID) end
    return n
end

---------------------------------------------------------------------------
-- What I may do with a request now
---------------------------------------------------------------------------

local function me() return S().selfAuthor() end

-- May I decide (核准／拒絕) requests to this custodian? (the guild master by
-- both the game and the roster, the custodian asked, an enabled reviewer)
function Req.canDecide(v)
    local a = me()
    if not a or not v then return false end
    if B().authority() == "leader" then return true end
    if a == v.keeper then return (B().isCustodian(a)) == true end
    return (B().isOfficer(a)) == true
end

-- The buttons of a request for me now, in order: approve / reject /
-- deliver / received / cancel.
function Req.actions(v)
    local out = {}
    local a = me()
    if not v or not a then return out end
    if v.state == "pending" and v.req ~= a and Req.canDecide(v) then
        out[#out + 1] = "approve"; out[#out + 1] = "reject"
    end
    if v.state == "approved" and v.keeper == a and (B().isCustodian(a)) then out[#out + 1] = "deliver" end
    if v.state == "delivered" and v.req == a then out[#out + 1] = "received" end
    if (v.state == "pending" or v.state == "approved") and v.req == a then out[#out + 1] = "cancel" end
    return out
end
Req.ACTION_TEXT = { approve = "核准", reject = "拒絕", deliver = "已交付", received = "已收到", cancel = "取消" }

-- 要我處理的: requests waiting for my decision (not my own), and approved
-- ones I hand over. 我的申領: mine, newest first.
function Req.todo()
    local out, a = {}, me()
    for _, v in ipairs(Req.view().list) do
        if v.req ~= a and ((v.state == "pending" and Req.canDecide(v)) or (v.state == "approved" and v.keeper == a)) then
            out[#out + 1] = v
        end
    end
    return out
end
function Req.minelist()
    local out, a = {}, me()
    for _, v in ipairs(Req.view().list) do if v.req == a then out[#out + 1] = v end end
    return out
end
function Req.todoCount() return #Req.todo() end

---------------------------------------------------------------------------
-- Writing (each only into my own record)
---------------------------------------------------------------------------

local function changed()
    Req.version = Req.version + 1
    if Req.onChanged then Req.onChanged() end
end

local function openCount(m)
    local n = 0
    for _, v in ipairs(Req.minelist()) do if Req.OPEN[v.state] then n = n + 1 end end
    return n
end

-- Keep a group within its entry limit: drop the oldest closed first.
local function fit(m, g, closedOf)
    local keys = {}
    for k in pairs(m[g]) do keys[#keys + 1] = k end
    if #keys <= Req.MAX_ENTRIES[g] then return end
    table.sort(keys, function(x, y)
        local cx, cy = closedOf(x), closedOf(y)
        if (cx ~= nil) ~= (cy ~= nil) then return cx ~= nil end
        return (cx or 0) < (cy or 0) or ((cx or 0) == (cy or 0) and tostring(x) < tostring(y))
    end)
    for i = 1, #keys - Req.MAX_ENTRIES[g] do m[g][keys[i]] = nil; stats.pruned = stats.pruned + 1 end
end

-- opts = { keeper = a, itemID, qty, purpose = "p" | "d" | "q" | "o", note }.
function Req.create(opts)
    if ns.inCombat() then return "combat" end
    opts = opts or {}
    local m = Req.mine()
    local a = me()
    if not m or not a or B().current().state ~= "ok" then return "no-guild" end
    local keeper = opts.keeper
    if not validA(keeper) or not (B().isCustodian(keeper)) or not S().memberFor(keeper) then return "keeper" end
    if keeper == a then return "self" end
    local qty = tonumber(opts.qty)
    local itemID = tonumber(opts.itemID)
    if not itemID or itemID <= 0 or not qty or qty ~= math.floor(qty) or qty < 1 or qty > Req.MAX_QTY then return "qty" end
    if qty > Req.available(keeper, itemID) then return "more" end
    if not Req.PURPOSE_NAME[opts.purpose] then return "purpose" end
    if openCount(m) >= Req.MAX_OPEN then return "full" end
    m.seq = m.seq + 1
    local t = now()
    m.KR[m.seq] = { keeper = keeper, itemID = itemID, qty = qty, purpose = opts.purpose, created = t, state = "o", st = t,
        note = Req.clean(opts.note) }
    fit(m, "KR", function(id) local v = Req.get(keyOf(a, id)); return v and v.closedAt end)
    publish("KR")
    changed()
    return "ok", keyOf(a, m.seq)
end

local function myEntry(key)
    local m = Req.mine()
    local a, id = key:match("^(.+):([0-9a-z]+)$")
    id = id and unb36(id)
    if not m or a ~= me() or not id then return nil end
    return m.KR[id], m
end

function Req.cancel(key)
    if ns.inCombat() then return "combat" end
    local v = Req.get(key)
    local e = myEntry(key)
    if not v or not e then return "not-found" end
    if not (v.state == "pending" or v.state == "approved") then return "state" end
    e.state, e.st = "c", math.max(now(), e.created)
    publish("KR")
    changed()
    return "cancelled"
end

function Req.received(key)
    if ns.inCombat() then return "combat" end
    local v = Req.get(key)
    local e = myEntry(key)
    if not v or not e then return "not-found" end
    if v.state ~= "delivered" then return "state" end
    e.state, e.st = "g", math.max(now(), e.created)
    publish("KR")
    changed()
    return "received"
end

-- Write my allocation for request v (the custodian's computer only).
local function allocate(m, v, state, by)
    local t = now()
    local old = m.KA[v.key]
    m.KA[v.key] = { req = v.req, id = v.id, state = state, itemID = v.itemID, qty = v.qty, t = t,
        rt = old and old.rt or t, by = by, snapT = 0 }
    if state == "r" then stats.reserved = stats.reserved + 1 elseif state == "s" then stats.short = stats.short + 1 end
end

-- The custodian's computer: valid approvals of requests to me become a
-- reservation (r) while 可申領 is enough, else 數量不足 (s). In order of the
-- decision time, then key. Returns how many were written.
local pendingSettle = false
function Req.settle()
    if ns.inCombat() then pendingSettle = true; stats.waited = stats.waited + 1; return 0 end
    pendingSettle = false
    local a = me()
    if not a or not (B().isCustodian(a)) then return 0 end
    local m = Req.mine()
    if not m then return 0 end
    local v0 = Req.view()
    local wait = {}
    for _, v in ipairs(v0.list) do
        if v.keeper == a and v.provisional and not m.KA[v.key] then wait[#wait + 1] = v end
    end
    if #wait == 0 then return 0 end
    table.sort(wait, function(x, y)
        if x.decision.t ~= y.decision.t then return x.decision.t < y.decision.t end
        return x.key < y.key
    end)
    local used = {}
    for _, v in ipairs(wait) do
        local firm = v0.firm[a] and v0.firm[a][v.itemID] or 0
        local left = Req.shared(a, v.itemID) - firm - (used[v.itemID] or 0)
        if left >= v.qty then
            allocate(m, v, "r", v.decision.a)
            used[v.itemID] = (used[v.itemID] or 0) + v.qty
        else
            allocate(m, v, "s", v.decision.a)
        end
    end
    stats.settled = stats.settled + #wait
    publish("KA")
    changed()
    return #wait
end

-- 核准: the custodian reserves at once (if 可申領 is enough); the guild master
-- or a reviewer writes the decision (only when 可申領 is enough now, the
-- custodian's computer checks again).
function Req.approve(key)
    if ns.inCombat() then return "combat" end
    local v = Req.get(key)
    if not v then return "not-found" end
    if v.state ~= "pending" then return "state" end
    if v.req == me() or not Req.canDecide(v) then return "no-right" end
    local m = Req.mine()
    if not m then return "no-guild" end
    if v.keeper == me() then
        Req.settle()
        v = Req.get(key)
        if not v or v.state ~= "pending" then return "state" end
        if Req.available(v.keeper, v.itemID) < v.qty then return "short" end
        allocate(m, v, "r", me())
        publish("KA")
    else
        if Req.available(v.keeper, v.itemID) < v.qty then return "short" end
        m.KD[key] = { req = v.req, id = v.id, d = "a", t = math.max(now(), v.created), reason = "" }
        fit(m, "KD", function(k) local x = Req.get(k); return x and x.closedAt end)
        publish("KD")
    end
    changed()
    return "approved"
end

function Req.reject(key, reason)
    if ns.inCombat() then return "combat" end
    local v = Req.get(key)
    if not v then return "not-found" end
    if v.state ~= "pending" then return "state" end
    if v.req == me() or not Req.canDecide(v) then return "no-right" end
    local m = Req.mine()
    if not m then return "no-guild" end
    m.KD[key] = { req = v.req, id = v.id, d = "r", t = math.max(now(), v.created), reason = Req.clean(reason) }
    fit(m, "KD", function(k) local x = Req.get(k); return x and x.closedAt end)
    publish("KD")
    changed()
    return "rejected"
end

-- 已交付 (the custodian, after trading or mailing it): my stock is read
-- again first, so snapT is the snapshot that no longer has it.
function Req.deliver(key)
    if ns.inCombat() then return "combat" end
    local a = me()
    local v = Req.get(key)
    if not v then return "not-found" end
    if v.keeper ~= a or not (B().isCustodian(a)) then return "no-right" end
    if v.state ~= "approved" then return "state" end
    local m = Req.mine()
    if not m then return "no-guild" end
    if not m.KA[key] then
        Req.settle()
        v = Req.get(key)
        if not v or v.state ~= "approved" or not m.KA[key] or m.KA[key].state ~= "r" then return "state" end
    end
    if K().myState() == "on" then K().scan("bags") end
    local A = m.KA[key]
    A.state, A.t = "d", math.max(now(), A.rt)
    A.snapT = math.max(0, math.floor(Req.snapOf(holderOf(a))))
    publish("KA")
    changed()
    return "delivered"
end

---------------------------------------------------------------------------
-- Clean-up of my own entries (at login and when the page opens): closed for
-- Req.KEEP. A decision whose request the custodian took over (an allocation
-- exists) has done its work: the allocation names who approved it.
---------------------------------------------------------------------------

function Req.prune()
    local m = Req.mine(true)
    if not m then return 0 end
    local t = now()
    local a = me()
    local n = 0
    local dirty = {}
    for id, e in pairs(m.KR) do
        local v = Req.get(keyOf(a, id))
        if v and v.closedAt and t - v.closedAt >= Req.KEEP then m.KR[id] = nil; dirty.KR = true; n = n + 1 end
        if not v and t - (e.st or 0) >= Req.KEEP then m.KR[id] = nil; dirty.KR = true; n = n + 1 end
    end
    for key, e in pairs(m.KD) do
        local v = Req.get(key)
        if (v and v.alloc and e.d == "a") or (v and v.closedAt and t - v.closedAt >= Req.KEEP)
            or (not v and t - e.t >= Req.KEEP + Req.EXPIRE) then
            m.KD[key] = nil; dirty.KD = true; n = n + 1
        end
    end
    for key, e in pairs(m.KA) do
        local v = Req.get(key)
        if (v and v.closedAt and t - v.closedAt >= Req.KEEP) or (not v and t - e.t >= Req.KEEP + Req.EXPIRE) then
            m.KA[key] = nil; dirty.KA = true; n = n + 1
        end
    end
    for g in pairs(dirty) do publish(g) end
    if n > 0 then stats.pruned = stats.pruned + n; changed() end
    return n
end

-- Somebody sent a record under my name that is not my original: mine again.
function Req.heal()
    local a = me()
    if not a then return false end
    local done = false
    for _, g in ipairs(Req.GROUPS) do
        local rec = S().get(a, g)
        local mine = Req.ownValue(g)
        if rec and mine and rec.h ~= S().hash(mine) then
            publish(g); stats.healed = stats.healed + 1; done = true
        end
    end
    return done
end

---------------------------------------------------------------------------
-- 業務通知 bank_request (one switch): a new request for me to decide, one
-- for me to hand over, my request approved / rejected / 數量不足 / 已交付.
-- Each once per character (Notify.once), only for events after this module
-- first watched (Notify.fresh). In combat: after combat.
---------------------------------------------------------------------------

Req.NOTIFY = "bank_request"
Req.NOTIFY_TEXT = { new = "有新的黑箱申領等你核准：%s（%s）", give = "有黑箱申領等你交付：%s 給 %s", mine = "你的黑箱申領%s：%s" }
Req.NOTIFY_SAID = { approved = "已核准", rejected = "被拒絕", short = "數量不足，請重新申領", delivered = "保管人已交付，收到後請按已收到" }
local notifyPending = false

local function itemText(v)
    local name = ns.Supply and ns.Supply.itemName and ns.Supply.itemName(v.itemID) or nil
    return (name or ("物品 " .. v.itemID)) .. " " .. v.qty .. " 個"
end
local function nameOf(a)
    local m = S().memberFor(a)
    return m and ns.shortName(m.name) or "已不在公會"
end
Req.nameOf = nameOf
Req.itemText = itemText

function Req.notifyScan()
    local N = ns.Notify
    if not N then return 0 end
    if ns.inCombat() then notifyPending = true; return 0 end
    notifyPending = false
    local a = me()
    if not a or B().current().state ~= "ok" then return 0 end
    local n = 0
    local function push(key, at, text)
        if not N.once(Req.NOTIFY, key, at) then return end
        if not N.fresh(Req.NOTIFY, at) then return end
        local r = N.push({ module = Req.NOTIFY, key = key, text = text, target = { page = "bank", tab = "requests", id = key },
            overflow = true })
        if r == "stored" or r == "merged" or r == "quiet" then n = n + 1; stats.pushed = stats.pushed + 1 end
    end
    for _, v in ipairs(Req.todo()) do
        if v.state == "pending" then
            push("new|" .. v.key, v.created, string.format(Req.NOTIFY_TEXT.new, itemText(v), nameOf(v.req)))
        elseif v.state == "approved" then
            push("give|" .. v.key, v.at or v.created, string.format(Req.NOTIFY_TEXT.give, itemText(v), nameOf(v.req)))
        end
    end
    local said = Req.NOTIFY_SAID
    for _, v in ipairs(Req.minelist()) do
        local s = said[v.state]
        if s then
            push("mine|" .. v.key .. "|" .. v.state, v.at or v.created, string.format(Req.NOTIFY_TEXT.mine, s, itemText(v)))
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Changes: someone's KR / KD / KA changed → work it out again (next frame,
-- merged), settle (custodian), notices, the page.
---------------------------------------------------------------------------

function Req.run()
    Req.settle()
    Req.notifyScan()
    if Req.onChanged then Req.onChanged() end
end
function Req.soon() ns.coalesce("bank-requests", 0, Req.run) end

local sig = {}
ns.Share.onUpdate(function(a)
    if a == nil then Req.version = Req.version + 1; Req.soon(); return end
    local parts = {}
    for _, g in ipairs(Req.GROUPS) do
        local rec = S().get(a, g)
        if rec then parts[#parts + 1] = g .. ":" .. tostring(rec.h) end
    end
    local s = table.concat(parts, "|")
    if (sig[a] or "") == s then return end
    sig[a] = s
    Req.version = Req.version + 1
    if a == me() then Req.heal() end
    Req.soon()
end)

-- The stock changed (a snapshot came after 已交付, a custodian shares more).
local oldStockChanged = K().onChanged
K().onChanged = function()
    if oldStockChanged then oldStockChanged() end
    Req.soon()
end

-- At login (Supply's start, no event of its own) and after combat.
ns.Supply.watch(function(kind)
    if kind == "start" then Req.prune(); Req.soon()
    elseif kind == "combat" and (pendingSettle or notifyPending) then Req.run() end
end)
if ns.Notify and ns.Notify.onAfterCombat then
    ns.Notify.onAfterCombat(function() if pendingSettle or notifyPending then Req.run() end end)
end

ns.Share.registerGroup({
    name = "CUSTODY_REQUEST",
    ["local"] = true,
    match = function(g) return g == "KR" or g == "KD" or g == "KA" end,
    encode = function(_, v) return type(v) == "string" and v or nil end,
    decode = Req.decode,
    ownGroups = Req.GROUPS,
    own = function(g) return Req.ownValue(g) end,
})

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------

function Req.diagText()
    local v = Req.view()
    local open, mine = 0, 0
    for _, x in ipairs(v.list) do
        if Req.OPEN[x.state] then open = open + 1 end
        if x.req == me() then mine = mine + 1 end
    end
    return string.format("申領：%d 筆（進行中 %d、我的 %d、要我處理 %d）｜這次登入：預留 %d、數量不足 %d、不採用的決定 %d、拒收 %d、清除 %d、通知 %d",
        #v.list, open, mine, #Req.todo(), stats.reserved, stats.short, stats.ignored, stats.rejected, stats.pruned, stats.pushed)
end

function Req.resetSession()
    for k, x in pairs(stats) do if type(x) == "number" then stats[k] = 0 end end
    view, sig = {}, {}
    pendingSettle, notifyPending = false, false
end

-- The page and 調貨看板 (可申領) are drawn again after a change.
Req.onChanged = function()
    if ns.BankUI and ns.BankUI.requestsChanged then ns.BankUI.requestsChanged() end
    if ns.SupplyUI and ns.SupplyUI.refreshSoon then ns.SupplyUI.refreshSoon() end
end
