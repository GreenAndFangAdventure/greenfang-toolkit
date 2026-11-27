-- WebOrders (GF-006-C, spec R-9.4, D-018): web orders into the game.
-- Format: docs/research/GF-006-C_inbox-format.md (draft; the contract is
-- claude-pm's). Two ways in, one parser:
--   * GreenFangToolkit_Inbox: a data-only AddOn GF Sync writes; one global
--     string, read at login / /reload.
--   * The import code pasted on the 「訂單」 page (📋): the very same string.
-- What passes the checks becomes the customer's M record (Orders.lua), which
-- the order ledger relays to everyone, so members without GF Sync get it too.
--
-- D-018 point 3: the string is NEVER executed (no loadstring, load,
-- RunScript, dofile); every field is checked for type and range; an unknown
-- version is skipped whole.

local _, ns = ...
local str = ns.str

local Web = {}
ns.WebOrders = Web

Web.GLOBAL = "GreenFangToolkit_Inbox"
Web.ADDON = "GreenFangToolkit_Inbox"
Web.VERSION = "GFIN1"
Web.MAX_BYTES = 65536
Web.MAX_ORDERS = 200
Web.MAX_PER_CUSTOMER = 30
Web.MAX_AGE = 30 * 86400
Web.FUTURE = 600
Web.MAX_MATS = 12

local function S() return ns.Share end

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

-- 24-bit hash, base 36 (same as Share.hash): see the draft §3d.
function Web.sum(s) return S().hash(s) end

function Web.pctDecode(s)
    if type(s) ~= "string" or s:find("[^A-Za-z0-9._%%%-]") then return nil end
    -- Every "%" must start "%XX".
    if s:gsub("%%%x%x", ""):find("%%") then return nil end
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function Web.pctEncode(s)
    return (str(s):gsub("[^A-Za-z0-9._%-]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function intIn(v, lo, hi)
    if type(v) ~= "string" or not v:match("^%d+$") or #v > 12 then return nil end
    local n = tonumber(v)
    if n < lo or n > hi then return nil end
    return n
end

local GUID = "^Player%-%d+%-%x+$"

-- "k=v;k=v" (the leading record type already removed). nil on a repeated
-- key or a field that is not k=v.
local function fieldsOf(body)
    local f = {}
    for part in (body .. ";"):gmatch("([^;]*);") do
        if part ~= "" then
            local k, v = part:match("^([a-z]+)=(.*)$")
            if not k or f[k] ~= nil then return nil end
            f[k] = v
        end
    end
    return f
end

-- One O record -> an M entry (Orders' field names), or nil, reason.
local function orderOf(f, ctx)
    local id = f.id
    if type(id) ~= "string" or #id < 2 or #id > 64 or not id:match("^w[0-9a-z.]+$") then return nil, "bad-id" end
    for _, k in ipairs({ "cr", "cf", "rc", "q", "fe", "st", "sa" }) do
        if f[k] == nil then return nil, "missing" end
    end
    local cr = intIn(f.cr, 0, 4102444800)
    if not cr then return nil, "bad-field" end
    if cr < ctx.now - Web.MAX_AGE then return nil, "too-old" end
    if cr > ctx.now + Web.FUTURE then return nil, "future" end
    local cf
    if f.cf == "*" then cf = "*"
    elseif f.cf:match(GUID) then
        cf = ctx.member(f.cf)
        if not cf then return nil, "not-member" end
    else return nil, "bad-field" end
    local rc = intIn(f.rc, 1, 9999999)
    local q = intIn(f.q, 1, 1000)
    local fe = intIn(f.fe, 0, 1000000000)
    local sa = intIn(f.sa, 0, 4102444800)
    if not (rc and q and fe and sa) then return nil, "bad-field" end
    local it, sk, fq, qt
    if f.it ~= nil then it = intIn(f.it, 1, 9999999); if not it then return nil, "bad-field" end end
    if f.sk ~= nil then sk = intIn(f.sk, 1, 9999); if not sk then return nil, "bad-field" end end
    if f.fq ~= nil then fq = intIn(f.fq, 0, 1000000000); if not fq then return nil, "bad-field" end end
    if f.qt ~= nil then qt = intIn(f.qt, 0, 1000000000); if not qt then return nil, "bad-field" end end
    local st
    if f.st == "open" then st = "o" elseif f.st == "cancel" then st = "x" else return nil, "bad-field" end
    local mats = {}
    if f.m ~= nil and f.m ~= "" then
        local n = 0
        for part in (f.m .. "+"):gmatch("([^+]*)%+") do
            local a, b = part:match("^(%d+)%*(%d+)$")
            local mid, cnt = a and intIn(a, 1, 9999999), b and intIn(b, 1, 10000)
            if not (mid and cnt) then return nil, "bad-field" end
            n = n + 1
            if n > Web.MAX_MATS then return nil, "bad-field" end
            -- GF-FIX-E (review L-27): the same material twice = a broken order.
            if mats[mid] then return nil, "bad-field" end
            mats[mid] = cnt
        end
    end
    return { id = id, src = "w", ver = 1, cr = cr, cf = cf, rc = rc, it = it, sk = sk, q = q,
        m = ns.Orders.encodeMats(mats), fe = fe, fq = fq, qt = qt, st = st, sa = sa }
end

-- Parse the whole string. ctx = { realm, guild, now, member(guid) -> author or nil }.
-- Returns { ok, code, at, customers = { { a, t, orders } }, skipped = { [reason] = n }, total }.
function Web.parse(s, ctx)
    local res = { ok = false, customers = {}, skipped = {}, total = 0 }
    local function fail(code) res.code = code; return res end
    local function skip(reason, n) res.skipped[reason] = (res.skipped[reason] or 0) + (n or 1) end
    if type(s) ~= "string" then return fail("not-string") end
    s = s:gsub("%s+", "") -- import codes may be wrapped
    if s == "" then return fail("empty") end
    if #s > Web.MAX_BYTES then return fail("too-big") end
    if s:find("[^A-Za-z0-9*+.%%_;=~%-]") then return fail("bad-chars") end
    local version, sum, sig, rest = s:match("^([^~]*)~([^~]*)~([^~]*)~(.*)$")
    if not version then return fail(s:match("^GFIN") and "malformed" or "not-inbox") end
    if version ~= Web.VERSION then return fail("version") end
    if not sig:match("^[A-Za-z0-9_%-]+$") or #sig > 200 then return fail("malformed") end
    if Web.sum(rest) ~= sum then return fail("bad-sum") end
    local parts = {}
    for p in (rest .. "~"):gmatch("([^~]*)~") do parts[#parts + 1] = p end
    local head = parts[1] and parts[1]:match("^H;(.*)$")
    local h = head and fieldsOf(head)
    if not h then return fail("malformed") end
    local realm, guild = Web.pctDecode(h.realm), Web.pctDecode(h.guild)
    local at, n = intIn(h.at, 0, 4102444800), intIn(h.n, 0, Web.MAX_ORDERS)
    if not (realm and guild and at and n) then return fail("malformed") end
    if realm ~= ctx.realm then return fail("other-realm") end
    if guild ~= ctx.guild then return fail("other-guild") end
    if at < ctx.now - Web.MAX_AGE then return fail("too-old") end
    if at > ctx.now + Web.FUTURE then return fail("future") end
    res.at = at
    local count, current = 0, nil
    for i = 2, #parts do
        local kind, body = parts[i]:match("^([CO]);(.*)$")
        if not kind then return fail("malformed") end
        local f = fieldsOf(body)
        if not f then
            if kind == "C" then return fail("malformed") end
            skip("bad-field")
            count = count + 1
        elseif kind == "C" then
            local t = intIn(f.t, 0, 4102444800)
            if type(f.cu) ~= "string" or not f.cu:match(GUID) or not t then return fail("malformed") end
            current = { guid = f.cu, a = ctx.member(f.cu), t = t, orders = {}, skip = nil }
            if not current.a then current.skip = "not-member" end
            if t > ctx.now + Web.FUTURE then current.skip = "future" end
            res.customers[#res.customers + 1] = current
        else
            count = count + 1
            if not current then return fail("malformed") end
            if current.skip then
                skip(current.skip)
            else
                local e, why = orderOf(f, ctx)
                if e then current.orders[#current.orders + 1] = e else skip(why) end
            end
        end
    end
    if count ~= n then return fail("count") end
    local kept = {}
    for _, c in ipairs(res.customers) do
        if not c.skip then
            if #c.orders > Web.MAX_PER_CUSTOMER then
                skip("too-many", #c.orders)
            else
                table.sort(c.orders, function(x, y) return x.id < y.id end)
                kept[#kept + 1] = c
                res.total = res.total + #c.orders
            end
        end
    end
    res.customers = kept
    res.ok, res.code = true, "ok"
    return res
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------

function Web.context()
    local p = ns.Sync.player()
    return {
        realm = ns.realm(), guild = str(p.guild), now = S().serverNow(),
        member = function(guid)
            local a = S().authorOf(guid)
            return a and S().memberFor(a) and a or nil
        end,
    }
end

function Web.state()
    local o = ns.Orders.local_()
    if type(o.inbox) ~= "table" then o.inbox = {} end
    return o.inbox
end

-- Import a string from "inbox" or "paste". Returns the parse result plus
-- imported (M records stored or confirmed) and same.
-- GF-FIX-E (review M-24): the sum is no signature and the game cannot check
-- sig, so a pasted code only brings in the orders of the one pasting it
-- (customer = me); other customers' orders are skipped as "not-self". The
-- Inbox AddOn (written by GF Sync from the website) is not limited.
function Web.import(s, from)
    if ns.guildState() ~= "target" then
        local r = { ok = false, code = "other-guild", skipped = {}, total = 0 }
        Web.remember(from, r)
        return r
    end
    local res = Web.parse(s, Web.context())
    res.imported, res.same = 0, 0
    if res.ok then
        local led = ns.Orders.ledger
        local mine = from == "paste" and S().selfAuthor() or nil
        local kept = {}
        for _, c in ipairs(res.customers) do
            if from == "paste" and (not mine or c.a ~= mine) then
                res.skipped["not-self"] = (res.skipped["not-self"] or 0) + #c.orders
                res.total = res.total - #c.orders
            else
                kept[#kept + 1] = c
            end
        end
        res.customers = kept
        for _, c in ipairs(res.customers) do
            local v = ns.Orders.encodeList(c.orders)
            local r = led:offer(c.a, "M", c.t, S().hash(v), v)
            if r == "new" or r == "confirm" then
                res.imported = res.imported + #c.orders
                led:sendRecord(c.a, "M", nil, true) -- relay at once (R-9.4)
            elseif r == "same" or r == "older" then
                res.same = res.same + #c.orders
            else
                res.skipped[r] = (res.skipped[r] or 0) + #c.orders
            end
        end
    end
    Web.remember(from, res)
    return res
end

function Web.remember(from, res)
    local st = Web.state()
    st.last = { from = from, at = ns.now(), code = res.code, imported = res.imported or 0, same = res.same or 0,
        total = res.total or 0, skipped = ns.copy(res.skipped or {}) }
    if from == "inbox" then st.inboxAt = ns.now() end
end

-- Login (D-018, draft §5): the global may already be set (a normal AddOn);
-- otherwise load the LoadOnDemand AddOn. Missing or disabled: nothing.
function Web.readInbox()
    local value = _G[Web.GLOBAL]
    local how = "loaded"
    if value == nil then
        local load = (type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" and C_AddOns.LoadAddOn)
            or (type(LoadAddOn) == "function" and LoadAddOn) or nil
        if not load then
            Web.state().noInbox = "no-loader"
            return "no-loader"
        end
        local ok, loaded, reason = pcall(load, Web.ADDON)
        if not ok or not loaded then
            Web.state().noInbox = ok and str(reason) ~= "" and str(reason) or "missing"
            return "missing"
        end
        how = "on-demand"
        value = _G[Web.GLOBAL]
    end
    Web.state().noInbox = nil
    if type(value) ~= "string" then
        Web.remember("inbox", { code = "not-string", skipped = {} })
        return "not-string"
    end
    local st = Web.state()
    local sum = value:match("^[^~]*~([^~]*)~")
    if sum and st.lastSum == sum and st.last and st.last.code == "ok" then
        st.inboxAt, st.how = ns.now(), how
        return "unchanged"
    end
    local res = Web.import(value, "inbox")
    st.how = how
    if res.ok then st.lastSum = sum end
    return res.code
end

---------------------------------------------------------------------------
-- GF-UI-L: what this computer shows of GF Sync. Read only: nothing is
-- loaded, imported or saved here. GF Sync never writes the SavedVariables;
-- GreenFangToolkit_Inbox is the only thing it writes in the game folder, and
-- only in a build with the web-order switch on (off in every normal build).
---------------------------------------------------------------------------

-- Is the AddOn folder there? true / false, or nil when the client cannot say.
function Web.addonExists(name)
    local C = type(C_AddOns) == "table" and C_AddOns or nil
    local does = C and C.DoesAddOnExist
    if type(does) == "function" then
        local ok, r = pcall(does, name)
        if ok and type(r) == "boolean" then return r end
    end
    local info = (C and C.GetAddOnInfo) or rawget(_G, "GetAddOnInfo")
    if type(info) == "function" then
        local ok, n, _, _, _, reason = pcall(info, name)
        if ok then
            if str(reason) == "MISSING" then return false end
            if str(n) ~= "" then return true end
        end
    end
    return nil
end

-- H.at of an Inbox string (the time the site made the list), or nil. Only
-- the header is looked at; the whole check is Web.parse (on import).
function Web.inboxAt(s)
    if type(s) ~= "string" or #s > Web.MAX_BYTES then return nil end
    local head = s:match("^[^~]*~[^~]*~[^~]*~H;([^~]*)")
    return head and intIn((";" .. head .. ";"):match(";at=(%d+);"), 1, 4102444800) or nil
end

-- { state = "seen" | "none" | "unknown", why = "inbox" | "folder" | "no-inbox" | "no-api", at }
function Web.gfSyncSignal()
    local value = rawget(_G, Web.GLOBAL)
    if type(value) == "string" then return { state = "seen", why = "inbox", at = Web.inboxAt(value) } end
    local exists = Web.addonExists(Web.ADDON)
    if exists == true then return { state = "seen", why = "folder" } end
    if exists == false then return { state = "none", why = "no-inbox" } end
    return { state = "unknown", why = "no-api" }
end

-- One line for 同步與診斷.
function Web.diagText()
    local st = Web.state()
    local parts = {}
    if st.inboxAt then
        parts[#parts + 1] = "上次讀到 Inbox " .. ns.localTime(st.inboxAt) .. (st.how == "on-demand" and "（隨選載入）" or "")
    elseif st.noInbox then
        parts[#parts + 1] = "沒有 Inbox（" .. st.noInbox .. "）"
    else
        parts[#parts + 1] = "還沒讀過 Inbox"
    end
    local l = st.last
    if l then
        local skipped = {}
        local total = 0
        for k, n in pairs(l.skipped or {}) do skipped[#skipped + 1] = k .. " " .. n; total = total + n end
        table.sort(skipped)
        parts[#parts + 1] = string.format("最後一次（%s）：%s，匯入 %d、已經有 %d、略過 %d%s",
            l.from == "paste" and "匯入碼" or "Inbox", str(l.code), l.imported or 0, l.same or 0, total,
            #skipped > 0 and ("（" .. table.concat(skipped, "、") .. "）") or "")
    end
    return table.concat(parts, "｜")
end
