-- GuildBank (GF-017, owner 2026-11-28): the game's own guild bank, gold only
-- (the guild keeps no items there yet): the balance and the gold log
-- (deposits, withdrawals, repairs ...), so members who did not go to the
-- bank can see them in the toolkit. Items in the guild bank are not read.
--
-- Reading: only while I have the guild bank open myself (the interaction
-- event or GUILDBANKFRAME_OPENED; the toolkit never opens it). The money and
-- log events are registered only while it is open and unregistered when it
-- closes; nothing is read in combat (it waits for the end of combat while
-- the bank is still open). No OnUpdate, no polling: one short ns.coalesce
-- after an event.
-- Only reads: GetGuildBankMoney, GetNumGuildBankMoneyTransactions,
-- GetGuildBankMoneyTransaction, and one log request per visit
-- (QueryGuildBankLog(MAX_GUILDBANK_TABS + 1), what the game's own money log
-- tab asks). No function that moves gold, repairs, buys a tab or changes a
-- permission is ever called (an offline test checks the source).
-- API evidence (GF-017 note): names, arguments and returns from the Forever
-- client's Blizzard_GuildBankUI (Mainline) money log in reckhou/WoWBlzCode;
-- MAX_GUILDBANK_TABS = 8 in its Constants.lua. Not checked in game: every
-- call is pcall'd and checked for existence; what cannot be read is shown as
-- 讀不到, never as 0.
--
-- Times: the game gives each log line as years / months / days / hours ago.
-- It is kept as an approximate server time t with a half-width p (seconds):
-- the real time is within t - p .. t + p. Hours are whole, so p is at least
-- half an hour; a month is counted as 30 days, with 2 days of slack per
-- month and 1 per year.
--
-- Merging: the game gives only the last few dozen lines. Every read (mine or
-- a guild member's shared one) is merged into this computer's log: a line
-- matches a kept line of the same kind, name and amount whose time window
-- overlaps (|t1 - t2| <= p1 + p2 + SLACK), one to one (two equal lines in one
-- read need two kept lines); a match narrows the window, anything else is
-- added. Kept: the newest KEEP_MIN lines and every line of the last KEEP_DAYS
-- days (at most KEEP_MAX).
--
-- Sharing: one Share record group GB per member (local = true: GF Sync does
-- not upload it), GUILD only. The record's time is when that member saw the
-- bank; the newest time among guild roster members wins. Wire value:
--   1;<money b36>;<log>;<entries>
--     log      "1" the log was read, "?" not read
--     entries  newest first, at most MAX_WIRE entries, joined by "/":
--              <kind letter>,<t b36>,<p b36>,<amount b36>,<name>
-- At most MAX_VALUE bytes (measured in tests/addon/gf017_tests.lua).

local _, ns = ...
local str = ns.str

local GB = {}
ns.GuildBank = GB

GB.GROUP = "GB"
GB.FORMAT = "1"
GB.MAX_WIRE = 20          -- entries in one shared record
GB.MAX_NAME = 48          -- bytes of a name
GB.MAX_VALUE = 1600       -- bytes of a wire value; longer is refused before parsing
GB.MAX_READ = 200         -- log lines read from the game at most
GB.KEEP_MIN, GB.KEEP_DAYS, GB.KEEP_MAX = 200, 90, 1000
GB.SLACK = 600            -- seconds of clock and rounding slack when matching
GB.HOUR, GB.DAY = 3600, 86400
GB.TABS = 8               -- MAX_GUILDBANK_TABS when the client has none
GB.READ_DELAY = 0.2
GB.OPEN_READ_DELAY = 1.0  -- the first money read after opening (a 0 then waits for the money event)
GB.GUILD_BANKER = 10      -- Enum.PlayerInteractionType.GuildBanker (Forever docs)

-- The game's kinds (Blizzard_GuildBankUI money log) and our letters.
GB.LETTER = { deposit = "d", withdraw = "w", repair = "r", withdrawForTab = "t", buyTab = "b",
    depositSummary = "s", buyRename = "n", refundRename = "f" }
GB.KIND_NAME = { d = "存入", w = "領出", r = "修裝", t = "買分頁領出", b = "買分頁", s = "公會獎勵", n = "公會改名",
    f = "改名退款", o = "其他" }
GB.INCOME = { d = true, s = true, f = true }
GB.SPEND = { w = true, r = true, t = true, b = true, n = true }
GB.ICON = {
    d = "Interface\\Icons\\INV_Misc_Coin_01", s = "Interface\\Icons\\INV_Misc_Coin_02", f = "Interface\\Icons\\INV_Misc_Coin_02",
    w = "Interface\\Icons\\INV_Misc_Coin_03", t = "Interface\\Icons\\INV_Misc_Bag_10", b = "Interface\\Icons\\INV_Misc_Bag_10",
    r = "Interface\\Icons\\Trade_BlackSmithing", n = "Interface\\Icons\\INV_Misc_Note_01", o = "Interface\\Icons\\INV_Misc_QuestionMark",
}

GB.TEXT = {
    none = "你還沒有加入公會", other = "這個角色不在本公會，看不到公會銀行",
    loading = "公會資料還在載入，稍等一下",
    never = "還沒有人打開過公會銀行", neverHint = "有人在遊戲裡打開公會銀行後，這裡就會顯示存款與收支",
    noapi = "這個遊戲版本讀不到公會銀行的存款", unread = "公會銀行的存款讀不到（遊戲沒有回答）",
    logNone = "還沒有收支紀錄", logUnread = "收支紀錄讀不到（遊戲沒有回答）",
    logEmpty = "公會銀行沒有給出收支紀錄：可能是權限不夠看收支，或銀行還沒有金幣進出",
}

local stats = { opens = 0, moneyReads = 0, logReads = 0, lines = 0, added = 0, matched = 0, published = 0,
    received = 0, refused = 0, combat = 0, queries = 0, noapi = 0 }
GB.stats = stats
GB.version = 0
GB.open = false

local function S() return ns.Share end
local function bump() GB.version = GB.version + 1; if GB.onChanged then GB.onChanged() end end

---------------------------------------------------------------------------
-- Saved data: GreenFangToolkitDB.guildBank.guilds[<realm|guild>]
--   money, moneyAt   the balance I last read and when (server time)
--   logRead          "1" / "?" / "0" (read / unread / the game gave none) on my last read
--   log              { { k, t, p, a (copper), n (name) }, ... } newest first
---------------------------------------------------------------------------

local function guildData()
    local db = ns.db
    if not db or ns.guildState() ~= "target" then return nil end
    if type(db.guildBank) ~= "table" then db.guildBank = { v = 1 } end
    local root = db.guildBank
    if type(root.guilds) ~= "table" then root.guilds = {} end
    local guild = str((ns.call(GetGuildInfo, "player")))
    if guild == "" then return nil end
    local key = ns.guildKey(ns.realm(), guild)
    local g = root.guilds[key]
    if type(g) ~= "table" then g = {}; root.guilds[key] = g end
    if type(g.log) ~= "table" then g.log = {} end
    return g
end
GB.guildData = guildData

---------------------------------------------------------------------------
-- Pure helpers (offline tests)
---------------------------------------------------------------------------

local function plainNum(v)
    if type(v) ~= "number" or ns.isSecret(v) or v ~= v then return nil end
    return v
end

-- years, months, days, hours ago, seen at now -> t, p.
function GB.whenOf(now, y, m, d, h)
    y, m, d, h = plainNum(y) or 0, plainNum(m) or 0, plainNum(d) or 0, plainNum(h) or 0
    if y < 0 or m < 0 or d < 0 or h < 0 then return nil end
    local ago = ((y * 365 + m * 30 + d) * 24 + h) * GB.HOUR
    local half = GB.HOUR / 2
    local p = half + m * 2 * GB.DAY + y * GB.DAY
    return math.floor(now - ago - half), math.floor(p)
end

-- How exact a time is, in words.
function GB.precisionText(p)
    p = tonumber(p) or 0
    if p <= GB.HOUR then return "準到小時" end
    if p <= 3 * GB.DAY then return "準到天" end
    return "大約"
end

-- "約 3 小時前" / "約 2 天前" / "不到 1 小時前".
function GB.agoText(t, now)
    local s = (tonumber(now) or 0) - (tonumber(t) or 0)
    if s < GB.HOUR then return "不到 1 小時前" end
    if s < GB.DAY then return string.format("約 %d 小時前", math.floor(s / GB.HOUR)) end
    return string.format("約 %d 天前", math.floor(s / GB.DAY))
end

local function cleanName(n)
    n = ns.cleanText(n, GB.MAX_NAME):gsub("[,/;]", "")
    return n
end

local function sig(e) return e.k .. "|" .. e.a .. "|" .. ns.keyName(e.n) end

local function validEntry(e)
    return type(e) == "table" and type(e.k) == "string" and GB.KIND_NAME[e.k] ~= nil
        and type(e.t) == "number" and type(e.p) == "number" and e.p >= 0
        and type(e.a) == "number" and e.a >= 0 and type(e.n) == "string"
end

-- Narrow kept entry e with a new sighting n of the same line.
local function refine(e, n)
    local lo = math.max(e.t - e.p, n.t - n.p)
    local hi = math.min(e.t + e.p, n.t + n.p)
    if lo <= hi then
        e.t, e.p = math.floor((lo + hi) / 2), math.max(60, math.floor((hi - lo) / 2))
    elseif n.p < e.p then
        e.t, e.p = n.t, n.p
    end
end

-- Keep the newest KEEP_MIN and everything of the last KEEP_DAYS days (at most KEEP_MAX).
function GB.trim(log, now)
    table.sort(log, function(x, y) if x.t ~= y.t then return x.t > y.t end return sig(x) < sig(y) end)
    local cut = now - GB.KEEP_DAYS * GB.DAY
    for i = #log, 1, -1 do
        if i > GB.KEEP_MAX or (i > GB.KEEP_MIN and log[i].t < cut) then table.remove(log, i) end
    end
    return log
end

-- Merge a read (a list of entries) into log. Returns added, matched.
function GB.merge(log, incoming, now)
    local bySig = {}
    for _, e in ipairs(log) do
        local s = sig(e)
        bySig[s] = bySig[s] or {}
        table.insert(bySig[s], e)
    end
    local list = {}
    for _, n in ipairs(incoming or {}) do if validEntry(n) then list[#list + 1] = n end end
    table.sort(list, function(x, y) return x.t > y.t end)
    local used, added, matched = {}, 0, 0
    for _, n in ipairs(list) do
        local s = sig(n)
        local best, bestD
        for _, e in ipairs(bySig[s] or {}) do
            if not used[e] then
                local d = math.abs(e.t - n.t)
                if d <= e.p + n.p + GB.SLACK and (not best or d < bestD) then best, bestD = e, d end
            end
        end
        if best then
            used[best] = true
            refine(best, n)
            matched = matched + 1
        else
            local e = { k = n.k, t = n.t, p = n.p, a = n.a, n = n.n }
            log[#log + 1] = e
            bySig[s] = bySig[s] or {}
            table.insert(bySig[s], e)
            used[e] = true
            added = added + 1
        end
    end
    GB.trim(log, now)
    return added, matched
end

---------------------------------------------------------------------------
-- Wire value
---------------------------------------------------------------------------

function GB.encode(d)
    if type(d) ~= "table" or not plainNum(d.money) or d.money < 0 then return nil end
    local b36 = S().b36
    local parts = {}
    for i, e in ipairs(d.log or {}) do
        if i > GB.MAX_WIRE then break end
        if validEntry(e) then
            parts[#parts + 1] = e.k .. "," .. b36(math.floor(e.t)) .. "," .. b36(math.floor(e.p)) .. ","
                .. b36(math.floor(e.a)) .. "," .. cleanName(e.n)
        end
    end
    local v = GB.FORMAT .. ";" .. b36(math.floor(d.money)) .. ";" .. (d.logRead == "1" and "1" or "?") .. ";"
        .. table.concat(parts, "/")
    while #v > GB.MAX_VALUE and #parts > 0 do
        table.remove(parts)
        v = GB.FORMAT .. ";" .. b36(math.floor(d.money)) .. ";" .. (d.logRead == "1" and "1" or "?") .. ";"
            .. table.concat(parts, "/")
    end
    return v
end

-- nil for anything malformed (Share then neither stores nor relays it).
function GB.decode(_, v)
    if type(v) ~= "string" or #v > GB.MAX_VALUE then return nil end
    local m, logRead, body = v:match("^1;([0-9a-z]+);([1%?]);(.*)$")
    local unb36 = S().unb36
    local money = m and unb36(m)
    if not money then return nil end
    local d = { money = money, logRead = logRead, log = {} }
    if body ~= "" then
        local now = S().serverNow()
        for item in (body .. "/"):gmatch("([^/]*)/") do
            if #d.log >= GB.MAX_WIRE then return nil end
            local k, t, p, a, n = item:match("^(%a),([0-9a-z]+),([0-9a-z]+),([0-9a-z]+),([^,;/]*)$")
            t, p, a = t and unb36(t), p and unb36(p), a and unb36(a)
            if not k or not GB.KIND_NAME[k] or not t or not p or not a then return nil end
            if t < S().EPOCH or t > now + S().FUTURE then return nil end
            if p > 400 * GB.DAY then return nil end
            if n ~= cleanName(n) then return nil end
            d.log[#d.log + 1] = { k = k, t = t, p = p, a = a, n = n }
        end
    end
    return d
end

---------------------------------------------------------------------------
-- Reading the open guild bank
---------------------------------------------------------------------------

local function maxTabs()
    local n = plainNum(rawget(_G, "MAX_GUILDBANK_TABS"))
    return n or GB.TABS
end

local function haveApi() return type(GetGuildBankMoney) == "function" end

local moneyEvent = false -- GUILDBANK_UPDATE_MONEY came during this visit

-- Read the balance. Returns "ok", "unread", "noapi", "combat", "closed", "wait".
function GB.readMoney(fromEvent)
    if not GB.open then return "closed" end
    if ns.inCombat() then GB.pending = true; stats.combat = stats.combat + 1; return "combat" end
    if not haveApi() then stats.noapi = stats.noapi + 1; GB.lastMoney = "noapi"; return "noapi" end
    if fromEvent then moneyEvent = true end
    local ok, v = pcall(GetGuildBankMoney)
    v = ok and plainNum(v) or nil
    if not v or v < 0 then GB.lastMoney = "unread"; bump(); return "unread" end
    -- A 0 right after opening may be "not arrived yet": only taken after the money event.
    if v == 0 and not moneyEvent then GB.lastMoney = "wait"; return "wait" end
    local g = guildData()
    if not g then return "unread" end
    g.money, g.moneyAt = v, math.floor(S().serverNow())
    GB.lastMoney = "ok"
    stats.moneyReads = stats.moneyReads + 1
    GB.publish()
    bump()
    return "ok"
end

-- Ask for the money log once per visit (the game answers with GUILDBANKLOG_UPDATE).
local queried = false
function GB.query()
    if queried or not GB.open or ns.inCombat() then return false end
    if type(QueryGuildBankLog) ~= "function" then return false end
    queried = true
    stats.queries = stats.queries + 1
    pcall(QueryGuildBankLog, maxTabs() + 1)
    return true
end

-- Read the money log. Returns "ok", "empty", "unread", "noapi", "combat", "closed".
function GB.readLog()
    if not GB.open then return "closed" end
    if ns.inCombat() then GB.pending = true; stats.combat = stats.combat + 1; return "combat" end
    if type(GetNumGuildBankMoneyTransactions) ~= "function" or type(GetGuildBankMoneyTransaction) ~= "function" then
        GB.lastLog = "noapi"
        return "noapi"
    end
    local g = guildData()
    if not g then return "unread" end
    local ok, n = pcall(GetNumGuildBankMoneyTransactions)
    n = ok and plainNum(n) or nil
    if not n or n < 0 then GB.lastLog = "unread"; g.logRead = "?"; bump(); return "unread" end
    local now = math.floor(S().serverNow())
    local read = {}
    for i = 1, math.min(n, GB.MAX_READ) do
        local r = { pcall(GetGuildBankMoneyTransaction, i) }
        if r[1] then
            local kind, name, amount = r[2], r[3], plainNum(r[4])
            local letter = type(kind) == "string" and not ns.isSecret(kind) and (GB.LETTER[kind] or "o") or nil
            local t, p = GB.whenOf(now, r[5], r[6], r[7], r[8])
            local nm = (type(name) == "string" and not ns.isSecret(name)) and cleanName(name) or ""
            if letter and t and amount and amount >= 0 then
                read[#read + 1] = { k = letter, t = t, p = p, a = math.floor(amount), n = nm }
            end
        end
    end
    stats.logReads = stats.logReads + 1
    stats.lines = stats.lines + #read
    local added, matched = GB.merge(g.log, read, now)
    stats.added, stats.matched = stats.added + added, stats.matched + matched
    g.logRead = n == 0 and "0" or "1"
    g.logAt = now
    GB.lastLog = n == 0 and "empty" or "ok"
    GB.publish()
    bump()
    return GB.lastLog
end

---------------------------------------------------------------------------
-- Publishing my read, receiving the others'
---------------------------------------------------------------------------

-- My value now (only once I have read the balance), or nil.
function GB.ownValue()
    local g = guildData()
    if not g or not g.money then return nil end
    return GB.encode({ money = g.money, logRead = g.logRead == "1" and "1" or "?", log = g.log })
end

function GB.publish()
    local v = GB.ownValue()
    if not v or not S().store() then return "none" end
    local r = S().ownRecord(GB.GROUP, v)
    if r == "stored" or r == "same" then stats.published = stats.published + 1 end
    return r
end

-- A guild member's record that may be shown: decoded, from the roster (or me).
local function fromMember(a)
    if a == S().selfAuthor() then return true, nil end
    local m = S().memberFor(a)
    return m ~= nil, m
end

-- Merge a member's shared log into mine (once per value).
local mergedH = {}
function GB.absorb(a)
    if a == nil or a == S().selfAuthor() then return false end
    local rec = S().get(a, GB.GROUP)
    if not rec or mergedH[a] == rec.h then return false end
    local isMember = fromMember(a)
    local d = isMember and S().decoded(a, GB.GROUP)
    if not d then stats.refused = stats.refused + 1; return false end
    mergedH[a] = rec.h
    local g = guildData()
    if not g then return false end
    stats.received = stats.received + 1
    local added, matched = GB.merge(g.log, d.log, math.floor(S().serverNow()))
    stats.added, stats.matched = stats.added + added, stats.matched + matched
    return true
end
function GB.resetMerged() mergedH = {} end

-- The newest balance among me and the roster's members:
-- { money, at, by (short name), own, logRead } or nil when nobody has seen it.
function GB.best()
    local best
    local g = guildData()
    if g and g.money and g.moneyAt then
        best = { money = g.money, at = g.moneyAt, own = true, logRead = g.logRead }
    end
    local s = S().store()
    if s then
        local me = S().selfAuthor()
        for a, groups in pairs(s.rec) do
            local rec = groups[GB.GROUP]
            if rec and a ~= me and (not best or rec.t > best.at) then
                local isMember, m = fromMember(a)
                local d = isMember and S().decoded(a, GB.GROUP)
                if d then best = { money = d.money, at = rec.t, own = false, by = ns.shortName(m and m.name), logRead = d.logRead } end
            end
        end
    end
    if best and best.own then best.by = ns.shortName(str(ns.Data.player().name)) end
    return best
end

-- What the page shows: state ("none" / "other" / "loading" / "noapi" /
-- "never" / "ok"), the best balance, the log.
function GB.status()
    local st = ns.guildState()
    if st ~= "target" then return { state = st == "none" and "none" or st == "loading" and "loading" or "other" } end
    local g = guildData()
    local best = GB.best()
    local out = { best = best, log = g and g.log or {}, logRead = g and g.logRead }
    if best then out.state = "ok"
    elseif not haveApi() then out.state = "noapi"
    elseif GB.lastMoney == "unread" then out.state = "unread"
    else out.state = "never" end
    return out
end

-- Totals over the last days: income, spend, net, covered days (nil = enough),
-- and whether there is any log at all.
function GB.summary(log, days, now)
    local cut = now - days * GB.DAY
    local inc, out, oldest = 0, 0, nil
    for _, e in ipairs(log or {}) do
        if not oldest or e.t < oldest then oldest = e.t end
        if e.t >= cut then
            if GB.INCOME[e.k] then inc = inc + e.a elseif GB.SPEND[e.k] then out = out + e.a end
        end
    end
    local covered
    if oldest and now - oldest < days * GB.DAY then covered = math.floor((now - oldest) / GB.DAY) end
    return { income = inc, spend = out, net = inc - out, covered = covered, any = oldest ~= nil }
end

-- Filtered rows: kind "all" / "in" / "out", a name search. Cached by key.
local rowCache = {}
function GB.rows(kind, search)
    local st = GB.status()
    local key = tostring(GB.version) .. "|" .. tostring(kind) .. "|" .. str(search)
    if rowCache.key == key then return rowCache.rows end
    local q = ns.keyName(str(search):gsub("^%s+", ""):gsub("%s+$", ""))
    local out = {}
    for _, e in ipairs(st.log or {}) do
        local pass = kind == "in" and GB.INCOME[e.k] or kind == "out" and GB.SPEND[e.k] or (kind ~= "in" and kind ~= "out")
        if pass and (q == "" or ns.keyName(e.n):find(q, 1, true)) then out[#out + 1] = e end
    end
    rowCache = { key = key, rows = out }
    return out
end
function GB.invalidate() rowCache = {} end

function GB.diagText()
    local st = GB.status()
    local best = st.best
    local head
    if st.state == "ok" then
        head = string.format("存款 %d 銅，%s由%s看到", best.money, GB.agoText(best.at, S().serverNow()), best.own and "自己" or "會友")
    else
        head = (GB.TEXT[st.state] or st.state)
    end
    return string.format("%s｜本機收支 %d 筆｜開銀行 %d 次、讀存款 %d、讀紀錄 %d（%d 行，新增 %d、相符 %d）｜分享 %d、收到 %d、拒收 %d%s",
        head, #(st.log or {}), stats.opens, stats.moneyReads, stats.logReads, stats.lines, stats.added, stats.matched,
        stats.published, stats.received, stats.refused, haveApi() and "" or "｜讀不到存款函式")
end

---------------------------------------------------------------------------
-- Events. Always: the open / close events. Only while open: money, log and
-- the end of combat.
---------------------------------------------------------------------------

GB.ALWAYS = { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" }
GB.WHILE_OPEN = { "GUILDBANK_UPDATE_MONEY", "GUILDBANKLOG_UPDATE", "PLAYER_REGEN_ENABLED" }

local events = CreateFrame("Frame")
GB.events = events
for _, e in ipairs(GB.ALWAYS) do pcall(events.RegisterEvent, events, e) end

local function readSoon(what, delay)
    ns.coalesce("guildbank-" .. what, delay or GB.READ_DELAY, function()
        if what == "money" then GB.readMoney(false) else GB.readLog() end
    end)
end

function GB.setOpen(on)
    if on == GB.open then return end
    GB.open = on
    if on then
        stats.opens = stats.opens + 1
        queried, moneyEvent, GB.pending = false, false, false
        for _, e in ipairs(GB.WHILE_OPEN) do pcall(events.RegisterEvent, events, e) end
        if ns.inCombat() then GB.pending = true; stats.combat = stats.combat + 1; return end
        readSoon("money", GB.OPEN_READ_DELAY)
        GB.query()
    else
        for _, e in ipairs(GB.WHILE_OPEN) do pcall(events.UnregisterEvent, events, e) end
        GB.pending = false
    end
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if plainNum(arg1) ~= GB.GUILD_BANKER then return end
        GB.setOpen(event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    elseif event == "GUILDBANKFRAME_OPENED" then GB.setOpen(true)
    elseif event == "GUILDBANKFRAME_CLOSED" then GB.setOpen(false)
    elseif not GB.open then return
    elseif event == "GUILDBANK_UPDATE_MONEY" then
        moneyEvent = true
        readSoon("money")
    elseif event == "GUILDBANKLOG_UPDATE" then readSoon("log")
    elseif event == "PLAYER_REGEN_ENABLED" and GB.pending then
        GB.pending = false
        readSoon("money")
        if not GB.query() then readSoon("log") end
    end
end)

---------------------------------------------------------------------------
-- The share group. local = true: GF Sync does not upload it.
---------------------------------------------------------------------------

ns.Share.registerGroup({
    name = "GUILD_BANK_MONEY",
    ["local"] = true,
    match = function(g) return g == GB.GROUP end,
    encode = function(_, v) return type(v) == "string" and v or nil end,
    decode = GB.decode,
})

-- Only a change of someone's GB record (its value or time) merges and redraws.
local gbSig = {}
ns.Share.onUpdate(function(a)
    if a == nil then return end
    local rec = S().get(a, GB.GROUP)
    local sigNow = rec and (tostring(rec.h) .. "|" .. tostring(rec.t)) or false
    local old = gbSig[a]
    if old == nil then old = false end
    if old == sigNow then return end
    gbSig[a] = sigNow
    if rec and a ~= S().selfAuthor() then GB.absorb(a) end
    bump()
end)
function GB.resetSignatures() gbSig = {} end
