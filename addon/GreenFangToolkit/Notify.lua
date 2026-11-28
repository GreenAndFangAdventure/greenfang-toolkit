-- Notify (GF-014, spec v2.0 §3 業務通知, §7.3, §11 通知中心): one place where
-- the pages leave a short notice for this player, and one way back to the
-- record it is about. Not a seventh main module: no page of its own, only the
-- bell on the main window (NotifyUI.lua). Each module keeps its own business
-- rules; here are only the shared parts:
--
--   ns.Notify.push({ module, key, text, target, actions, ttl })
--     module  "supply" / "radar" / ... (N.MODULES; one switch each)
--     key     what the notice is about; the same key is one notice (merged:
--             newest text and time, count + 1), never two
--     text    one short line (shown as is; no colour codes needed)
--     target  { page = "<Framework id>", id = <record id>, tab = "<tab>" }
--             a click opens that page and calls its focus(id, target)
--     actions optional { { key = "view", text = "查看需求" }, ... } (buttons;
--             the module's onAction(entry, key) handles them)
--     ttl     seconds the notice is kept (default N.TTL)
--     summary false: not counted in the chat line (the module printed its own; GF-014-03)
--     overflow true: past N.BURST a minute, merged into one "另有 N 則" notice of
--             the module (its page) instead of only counted (GF-014-04)
--   returns "stored" / "merged" / "quiet" / "queued" / "off" / "burst" / "bad"
--
-- Rules: a module the player switched off adds nothing. In combat a push only
-- waits in a small queue (merged by key); it is handled after combat. A key
-- that comes back within N.THROTTLE of its last alert merges quietly (stays
-- read when it was read). At most N.BURST new notices per module per minute;
-- the rest are counted, not stored. The chat line is at most one every
-- N.ALERT_GAP seconds and names how many notices are new. Kept: at most
-- N.MAX_KEEP, each until its ttl. Nothing here is sent anywhere: the notices
-- live in GreenFangToolkitDB.notify[<character>] on this computer only.

local _, ns = ...
local str = ns.str

local N = {}
ns.Notify = N

N.SCHEMA = 1
N.MAX_KEEP = 50
N.TTL = 3 * 86400
N.THROTTLE = 10 * 60
N.ALERT_GAP = 60
N.BURST = 10            -- new notices per module per minute
N.QUEUE_MAX = 100       -- waiting in combat (merged by key)
N.TEXT_MAX = 120        -- bytes
N.MORE_KEY = "+more"   -- GF-014-04: push({ overflow = true }) past N.BURST
N.MORE_TEXT = "另有 %d 則「%s」，請到頁面查看"

-- The modules that may notify, in the order of the switches. A module that is
-- not listed still works (switch on by default), so a page can start using
-- push() before it is named here.
N.MODULES = {
    { key = "supply", text = "調貨所配對", tip = "有人可能有你缺的，或需要你可能有多的" },
    { key = "radar", text = "需求雷達", tip = "背包裡有公會正在徵求的物品（只有你看得到）" },
    { key = "recipe", text = "圖紙學會提示", tip = "我徵求的圖紙，自己已經學會了" }, -- GF-009-10 (switch added in GF-014-04)
    { key = "adventure", text = "職工單配對", tip = "我的職工單符合別人的冒險單（WorkerMatch.lua；各角色自己的設定）" }, -- GF-014-02
    -- GF-014-04: what 委託業務 / 冒險業務 / 臨時黑箱 tell me when others act (one switch each).
    { key = "order_new", text = "有人對我下單", tip = "有人指定我做的委託（含網站下單）" },
    { key = "order_guild", text = "我會做的公會委託", tip = "預設關：公會裡有人發了我會做的公會委託（量可能很多）", default = false }, -- GF-014-05
    { key = "order_status", text = "委託狀態改變", tip = "對方接單、交貨、放棄、退回、成交或取消我的委託" },
    { key = "order_remind", text = "委託逾期／可結案", tip = "委託太久沒有進展，或交貨滿 14 天可以結案" }, -- GF-014-05
    { key = "adv_signup", text = "有人報名我的冒險單", tip = "我開的冒險單有人報名或接受邀請" },
    { key = "adv_result", text = "錄取／遞補／邀請", tip = "隊長錄取、邀請或移出我，或我從候補遞補上" },
    { key = "adv_final", text = "冒險單定案或取消", tip = "我報名的冒險單定案了時間，或被取消" },
    -- GF-014-05: the time and leader reminders the ❗ already shows.
    { key = "adv_update", text = "冒險單改內容或結束", tip = "隊長改了我報名的冒險單，或冒險單過期、未成行（成行不通知）" },
    { key = "adv_remind", text = "冒險單開打提醒", tip = "我參加的冒險單開打前 60 分鐘與 15 分鐘" },
    { key = "adv_leader", text = "我的冒險單待處理", tip = "我開的冒險單快開打還沒定案、成員遞補，或候補的職工單過期離開" },
    { key = "bank_keeper", text = "臨時黑箱保管人", tip = "會長指定我為保管人，或撤銷我的保管人資格" },
    { key = "bank_request", text = "臨時黑箱申領", tip = "有申領等我核准或交付，或我的申領被核准、拒絕、數量不足、已交付" }, -- GF-012-D
}
N.MODULE_TEXT = {}
N.DEFAULT_OFF = {} -- GF-014-05: modules that start switched off (default = false)
for _, m in ipairs(N.MODULES) do
    N.MODULE_TEXT[m.key] = m.text
    if m.default == false then N.DEFAULT_OFF[m.key] = true end
end

local stats = { pushed = 0, stored = 0, merged = 0, quiet = 0, queued = 0, off = 0, bad = 0, burst = 0,
    expired = 0, alerts = 0, opened = 0 }
N.stats = stats

local handlers = {}   -- module -> { onAction = fn, focus = { [page] = fn } }
local focusers = {}   -- page -> fn(id, target): pages without a focus() of their own
local listeners = {}
local queue, queueOrder = {}, {}
-- GF-FIX-B (review low-9): after entries were dropped from queue, drop their
-- keys from queueOrder too, so they no longer take QUEUE_MAX places (and a
-- key added again is not listed twice).
local function compactQueue()
    local keep, seen = {}, {}
    for _, qk in ipairs(queueOrder) do
        if queue[qk] and not seen[qk] then seen[qk] = true; keep[#keep + 1] = qk end
    end
    queueOrder = keep
end
local burst = {}      -- module -> { at = minute, n = count }
local combatHooks = {} -- GF-014-04: scans that waited for the end of combat
local lastAlert, alertPending, alertTimer = 0, 0, false

---------------------------------------------------------------------------
-- Saved state (this character only)
---------------------------------------------------------------------------

local function charKey()
    return ns.Framework and ns.Framework.charKey and ns.Framework.charKey() or nil
end

-- GreenFangToolkitDB.notify = { v, chars = { [char] = { seq, list, mem } } }.
-- mem is a small table the modules may keep next to their notices (what was
-- already announced, what was ignored); N.memory(module).
function N.store()
    local db = ns.db
    local key = charKey()
    if not db or not key then return nil end
    if type(db.notify) ~= "table" or db.notify.v ~= N.SCHEMA then db.notify = { v = N.SCHEMA, chars = {} } end
    if type(db.notify.chars) ~= "table" then db.notify.chars = {} end
    local s = db.notify.chars[key]
    if type(s) ~= "table" then s = { seq = 0, list = {}, mem = {} }; db.notify.chars[key] = s end
    if type(s.list) ~= "table" then s.list = {} end
    if type(s.mem) ~= "table" then s.mem = {} end
    s.seq = tonumber(s.seq) or 0
    return s
end

function N.memory(module)
    local s = N.store()
    if not s then return {} end
    if type(s.mem[module]) ~= "table" then s.mem[module] = {} end
    return s.mem[module]
end

---------------------------------------------------------------------------
-- Switches (GreenFangToolkitDB.settings.modules.notify; GF Sync ignores settings)
---------------------------------------------------------------------------

local function settings()
    if not (ns.db and ns.Framework and ns.Framework.moduleSettings) then return {} end
    local ms = ns.Framework.moduleSettings("notify")
    if type(ms.off) ~= "table" then ms.off = {} end
    return ms
end

-- off[module]: true = off, nil = its default (on; off for N.DEFAULT_OFF),
-- false = switched on (only kept for a module that starts off; GF-014-05).
function N.enabled(module)
    local off = settings().off
    local v = off and off[module]
    if v == nil then return not N.DEFAULT_OFF[module] end
    return not v
end

function N.setEnabled(module, on)
    local ms = settings()
    if not ms.off then return end
    if N.DEFAULT_OFF[module] then ms.off[module] = not on else ms.off[module] = (not on) or nil end
    if not on then
        -- Drop what is waiting for that module; the kept ones stay hidden.
        for k, e in pairs(queue) do if e.module == module then queue[k] = nil end end
        compactQueue()
    end
    N.changed()
end

function N.chatOn() return settings().chat ~= false end
function N.setChat(on) settings().chat = on and true or false end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function N.onChange(fn) listeners[#listeners + 1] = fn end
function N.changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

-- GF-014-03: recheck = function(n): a notice that waited in combat, just before
-- it shows; false drops it, else it may refresh n.text / ttl / target / summary.
-- module: { onAction = function(entry, actionKey) } (buttons other than the
-- shared 忽略), focus = function(id, target) for its own page when that page
-- has no focus() yet.
function N.register(module, def)
    handlers[module] = def or {}
end

-- A page that has no focus(id) of its own may get one here (the page's
-- public functions only; Framework.get(page).focus wins when there is one).
function N.setFocus(page, fn) focusers[page] = fn end

local function cut(s, max)
    s = str(s):gsub("[%z\1-\31]", " ")
    if #s <= max then return s end
    -- do not cut inside a UTF-8 character
    local i = max
    while i > 0 and s:byte(i + 1) and s:byte(i + 1) >= 0x80 and s:byte(i + 1) < 0xC0 do i = i - 1 end
    return s:sub(1, i) .. "..."
end

local function cleanTarget(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if type(k) == "string" and (tv == "string" or tv == "number" or tv == "boolean") then out[k] = v end
    end
    return out
end

local function cleanActions(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, a in ipairs(list) do
        if type(a) == "table" and type(a.key) == "string" and type(a.text) == "string" then
            out[#out + 1] = { key = a.key, text = a.text }
        end
        if #out >= 3 then break end
    end
    return #out > 0 and out or nil
end

local function now() return ns.now() end

-- Notices past their time go; then the oldest read ones, then the oldest.
function N.prune(s)
    s = s or N.store()
    if not s then return end
    local t = now()
    for i = #s.list, 1, -1 do
        local e = s.list[i]
        if type(e) ~= "table" or (e.expires or 0) <= t then
            table.remove(s.list, i)
            stats.expired = stats.expired + 1
        end
    end
    while #s.list > N.MAX_KEEP do
        local drop, dropScore
        for i, e in ipairs(s.list) do
            local score = (e.unread and 1e12 or 0) + (e.t or 0)
            if not dropScore or score < dropScore then drop, dropScore = i, score end
        end
        table.remove(s.list, drop)
    end
end

local function find(s, module, key)
    for i, e in ipairs(s.list) do
        if e.module == module and e.key == key then return e, i end
    end
    return nil
end

---------------------------------------------------------------------------
-- The chat line (throttled, one for many)
---------------------------------------------------------------------------

local function alertNow()
    alertTimer = false
    if alertPending <= 0 then return end
    if ns.inCombat() then return end -- after combat (N.afterCombat)
    local n = alertPending
    alertPending = 0
    lastAlert = now()
    stats.alerts = stats.alerts + 1
    if N.chatOn() then
        ns.say(n == 1 and "業務通知：有 1 則新提示，請開主視窗右上角的「業務通知」"
            or string.format("業務通知：有 %d 則新提示，請開主視窗右上角的「業務通知」", n))
    end
end

local function alert()
    alertPending = alertPending + 1
    if alertTimer then return end
    local wait = math.max(1, N.ALERT_GAP - (now() - lastAlert))
    alertTimer = true
    ns.after(wait, alertNow)
end

---------------------------------------------------------------------------
-- push
---------------------------------------------------------------------------

local function apply(n)
    local s = N.store()
    if not s then return "bad" end
    N.prune(s)
    local t = now()
    local e = find(s, n.module, n.key)
    if e then
        e.text, e.t, e.target, e.actions = n.text, t, n.target, n.actions
        e.expires = t + n.ttl
        e.count = (e.count or 1) + 1
        if e.unread then
            stats.merged = stats.merged + 1
            N.changed()
            return "merged"
        end
        if t - (e.alertAt or 0) < N.THROTTLE then
            stats.quiet = stats.quiet + 1
            N.changed()
            return "quiet"
        end
        e.unread, e.alertAt = true, t
        stats.merged = stats.merged + 1
        if n.summary ~= false then alert() end -- GF-014-03: the module printed its own line
        N.changed()
        return "merged"
    end
    local minute = math.floor(t / 60)
    local b = burst[n.module]
    if not b or b.at ~= minute then b = { at = minute, n = 0 }; burst[n.module] = b end
    if b.n >= N.BURST then
        stats.burst = stats.burst + 1
        if not n.overflow then return "burst" end
        -- GF-014-04: past the limit these merge into one "另有 N 則" notice of the module.
        local more = find(s, n.module, N.MORE_KEY)
        if more then
            more.more = (more.more or 1) + 1
            more.count = (more.count or 1) + 1
            more.text = string.format(N.MORE_TEXT, more.more, N.MODULE_TEXT[n.module] or "通知")
            more.t, more.expires = t, t + n.ttl
            if not more.unread then more.unread, more.alertAt = true, t; alert() end
            N.changed()
            return "merged"
        end
        s.seq = s.seq + 1
        s.list[#s.list + 1] = { id = s.seq, module = n.module, key = N.MORE_KEY, more = 1,
            text = string.format(N.MORE_TEXT, 1, N.MODULE_TEXT[n.module] or "通知"),
            target = n.target and n.target.page and { page = n.target.page } or nil,
            t = t, alertAt = t, expires = t + n.ttl, unread = true, count = 1 }
        N.prune(s)
        alert()
        N.changed()
        return "stored"
    end
    b.n = b.n + 1
    s.seq = s.seq + 1
    s.list[#s.list + 1] = { id = s.seq, module = n.module, key = n.key, text = n.text, target = n.target,
        actions = n.actions, t = t, alertAt = t, expires = t + n.ttl, unread = true, count = 1 }
    N.prune(s)
    stats.stored = stats.stored + 1
    if n.summary ~= false then alert() end -- GF-014-03
    N.changed()
    return "stored"
end

function N.push(n)
    stats.pushed = stats.pushed + 1
    if type(n) ~= "table" or type(n.module) ~= "string" or n.module == "" or n.key == nil or str(n.text) == "" then
        stats.bad = stats.bad + 1
        return "bad"
    end
    if not N.enabled(n.module) then stats.off = stats.off + 1; return "off" end
    local clean = {
        module = n.module, key = tostring(n.key), text = cut(n.text, N.TEXT_MAX),
        target = cleanTarget(n.target), actions = cleanActions(n.actions),
        ttl = math.max(60, math.min(tonumber(n.ttl) or N.TTL, 30 * 86400)),
        summary = n.summary ~= false, -- GF-014-03: false = not counted in the chat line
        overflow = n.overflow == true, -- GF-014-04: past N.BURST merge into one "另有 N 則"
    }
    if ns.inCombat() then
        local qk = clean.module .. "\1" .. clean.key
        if not queue[qk] then
            if #queueOrder >= N.QUEUE_MAX then stats.burst = stats.burst + 1; return "burst" end
            queueOrder[#queueOrder + 1] = qk
        end
        queue[qk] = clean
        stats.queued = stats.queued + 1
        return "queued"
    end
    return apply(clean)
end

function N.queued() return #queueOrder end

-- GF-014-04: a module whose scan was asked for in combat runs it here, right
-- after combat, before the queue (no frame or event of its own).
-- Files that load before this one leave theirs in ns.notifyHooks.
function N.onAfterCombat(fn) combatHooks[#combatHooks + 1] = fn end
for _, fn in ipairs(ns.notifyHooks or {}) do combatHooks[#combatHooks + 1] = fn end
ns.notifyHooks = nil

-- GF-014-04: one event (a fact with its own key, e.g. "<order id>|making|<time>")
-- is announced once per character, ever: kept in N.memory(module).done, so a
-- resend, a relay or the replay after /reload never notifies it again.
-- Returns true only the first time. A switched-off module still marks it.
function N.once(module, key, at)
    local mem = N.memory(module)
    if type(mem.done) ~= "table" then mem.done = {} end
    key = tostring(key)
    if mem.done[key] then return false end
    mem.done[key] = tonumber(at) or now()
    return true
end
function N.known(module, key)
    local mem = N.memory(module)
    return type(mem.done) == "table" and mem.done[tostring(key)] ~= nil
end
-- Is an event new enough to announce? Not from before this module first
-- watched on this character (mem.since: the first load with GF-014-04, so an
-- upgrade does not announce the old history) and not older than N.TTL.
local loadedAt = time and time() or 0
function N.fresh(module, at)
    local mem = N.memory(module)
    if type(mem.since) ~= "number" then mem.since = loadedAt end
    at = tonumber(at)
    if not at then return false end
    return at >= mem.since and now() - at < N.TTL
end

-- Forget the events keep(key, at) says no to (records that are gone).
function N.forget(module, keep)
    local mem = N.memory(module)
    if type(mem.done) ~= "table" then return 0 end
    local n = 0
    for k, at in pairs(mem.done) do
        if not keep(k, at) then mem.done[k] = nil; n = n + 1 end
    end
    return n
end

-- After combat: the queue in the order it came, then the chat line.
function N.afterCombat()
    if ns.inCombat() then return end
    for _, fn in ipairs(combatHooks) do pcall(fn) end -- GF-014-04
    local order = queueOrder
    queueOrder = {}
    for _, qk in ipairs(order) do
        local n = queue[qk]
        queue[qk] = nil
        -- GF-014-03: the module checks it again first (recheck(n) false = gone; it may
        -- refresh text / ttl / target / summary in n).
        local h = n and handlers[n.module]
        local keep = true
        if n and h and type(h.recheck) == "function" then
            local okCall, res = pcall(h.recheck, n)
            if okCall and res == false then keep = false; stats.dropped = (stats.dropped or 0) + 1 end
            if okCall and keep then
                n.text = cut(n.text, N.TEXT_MAX)
                n.target = cleanTarget(n.target)
                n.ttl = math.max(60, math.min(tonumber(n.ttl) or N.TTL, 30 * 86400))
            end
        end
        if n and keep and N.enabled(n.module) then apply(n) end
    end
    if alertPending > 0 and not alertTimer then
        alertTimer = true
        ns.after(math.max(1, N.ALERT_GAP - (now() - lastAlert)), alertNow)
    end
end

---------------------------------------------------------------------------
-- Reading and acting
---------------------------------------------------------------------------

-- Notices of switched-on modules, newest first.
function N.list()
    local s = N.store()
    if not s then return {} end
    N.prune(s)
    local out = {}
    for _, e in ipairs(s.list) do
        if N.enabled(e.module) then out[#out + 1] = e end
    end
    table.sort(out, function(x, y)
        if (x.t or 0) ~= (y.t or 0) then return (x.t or 0) > (y.t or 0) end
        return (x.id or 0) > (y.id or 0)
    end)
    return out
end

function N.unread()
    local n = 0
    for _, e in ipairs(N.list()) do if e.unread then n = n + 1 end end
    return n
end

function N.get(id)
    local s = N.store()
    for _, e in ipairs(s and s.list or {}) do if e.id == id then return e end end
    return nil
end

function N.find(module, key)
    local s = N.store()
    return s and (find(s, module, tostring(key))) or nil
end

function N.markRead(e)
    if e and e.unread then e.unread = false; N.changed() end
end

function N.markAllRead()
    local any = false
    for _, e in ipairs(N.list()) do if e.unread then e.unread = false; any = true end end
    if any then N.changed() end
end

function N.dismiss(e)
    local s = N.store()
    if not s or not e then return end
    for i, x in ipairs(s.list) do
        if x == e or x.id == e.id then table.remove(s.list, i); break end
    end
    N.changed()
end

-- Remove the notices of one module whose key test(key) says so (a module
-- whose reason went away: the item left the bag, the need was closed).
function N.clear(module, test)
    local s = N.store()
    if not s then return 0 end
    local n = 0
    for i = #s.list, 1, -1 do
        local e = s.list[i]
        if e.module == module and (not test or test(e.key, e)) then table.remove(s.list, i); n = n + 1 end
    end
    for k, q in pairs(queue) do
        if q.module == module and (not test or test(q.key, q)) then queue[k] = nil end
    end
    compactQueue()
    if n > 0 then N.changed() end
    return n
end

-- Open the target: the page, then its focus(id) (the page's own, else the one
-- given with N.setFocus); a page with neither only opens. Returns how far it got:
-- "focused" / "page" / "none".
function N.go(target)
    local F = ns.Framework
    if type(target) ~= "table" or type(target.page) ~= "string" or not F then return "none" end
    local def = F.get(target.page)
    if not def then return "none" end
    local shown = F.open(target.page)
    if not shown or shown.id ~= target.page then return "none" end
    local fn = type(def.focus) == "function" and def.focus or focusers[target.page]
    if fn and target.id ~= nil then
        local okCall, res = pcall(fn, target.id, target)
        if okCall and res ~= false then return "focused" end
    end
    return "page"
end

-- A click on a notice: read, then its target.
function N.open(e)
    if not e then return "none" end
    N.markRead(e)
    stats.opened = stats.opened + 1
    return N.go(e.target)
end

-- A button of a notice. "ignore" (忽略) is shared: the module hears it, then
-- the notice goes.
function N.action(e, key)
    if not e then return nil end
    local h = handlers[e.module]
    local res
    if h and type(h.onAction) == "function" then
        local okCall, r = pcall(h.onAction, e, key)
        if okCall then res = r end
    end
    if key == "ignore" then
        N.dismiss(e)
    elseif key == "view" and res == nil then
        res = N.open(e)
    else
        N.markRead(e)
    end
    return res
end

function N.diagText()
    local s = N.store()
    local q = N.queued()
    return string.format("業務通知：保存 %d 則、未讀 %d 則、戰鬥中排隊 %d 則｜這次登入新增 %d、合併 %d、節流 %d、關閉略過 %d、超量略過 %d、過期 %d",
        s and #s.list or 0, N.unread(), q, stats.stored, stats.merged, stats.quiet, stats.off, stats.burst, stats.expired)
end

function N.resetSession()
    for k in pairs(stats) do stats[k] = 0 end
    queue, queueOrder, burst = {}, {}, {}
    lastAlert, alertPending, alertTimer = 0, 0, false
end

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    -- Next frame: Init.lua clears the toolkit's combat flag after us.
    ns.after(0, N.afterCombat)
end)
