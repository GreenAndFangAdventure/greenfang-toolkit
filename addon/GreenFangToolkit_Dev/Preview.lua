-- GF-DEV-02: /gftkdev preview, made-up rows on the toolkit's windows so the
-- owner can look at them (the notice centre, its switches, the confirm boxes,
-- the lists) and tell us what to change. Dev AddOn only; members never see it.
--
--   /gftkdev preview              what can be shown (one line each)
--   /gftkdev preview notify       made-up notices of every kind in the real words, half unread, the list opened
--   /gftkdev preview settings     the notice switches (the list's 設定)
--   /gftkdev preview confirm      every confirm box, one at a time
--   /gftkdev preview lists [少|多] 委託 / 冒險單 / 調貨所 / 名冊 with ~5 or ~100 made-up rows
--   /gftkdev preview off          everything back to the real data
--
-- The made-up data lives only in this file's tables, in memory: nothing is
-- written to GreenFangToolkitDB, sent or uploaded. It works by swapping a
-- page's own "rows to show" function (OrdersUI.pageRows, AdventureUI.pageRows,
-- SupplyUI.listFor, UI.filterMembers) and Notify's reading functions for ones
-- that return the made-up rows; preview off (or /reload) puts the originals
-- back. A page in preview gets a cover over it: its buttons do nothing (the
-- mouse wheel still scrolls). Confirm boxes are look-alikes: no button runs
-- anything. Refused in combat; no events, no timers, no OnUpdate.
local _, D = ...
local P = {}
D.Preview = P

P.BANNER = "預覽中：畫面上是假資料，不會存檔、不會送出（/gftkdev preview off 結束）"
P.COVER_TEXT = "預覽中：這頁是假資料，按鈕暫停（滾輪可捲動）｜/gftkdev preview off 結束"
P.POPUP = "GREENFANGTOOLKITDEV_PREVIEW_CONFIRM"
P.POPUP_EDIT = "GREENFANGTOOLKITDEV_PREVIEW_EDIT"
P.FEW, P.MANY = 5, 100
P.NAMES = { "測試甲", "測試乙", "測試丙", "測試丁", "測試戊", "測試己", "測試庚", "測試辛", "測試壬", "測試癸" }
P.HELP = {
    "/gftkdev preview notify：通知中心放進每一種假通知（文字和正式通知一樣，一半未讀）並打開",
    "/gftkdev preview settings：打開通知設定（開關清單）",
    "/gftkdev preview confirm：確認視窗一個一個跳出來（按什麼都不會執行）",
    "/gftkdev preview lists 少（或 多）：委託、冒險單、調貨所、名冊顯示假資料（約 5 或 100 筆）",
    "/gftkdev preview off：全部收掉，回到真資料（/reload 也會回到真資料）",
}

local function say(text)
    if D.CatalogScan and D.CatalogScan.say then return D.CatalogScan.say(text) end
    print("|cff7fbf3fGF Dev|r " .. tostring(text))
end
P.say = say

-- The toolkit's namespace (Init.lua GreenFangToolkit_DevAccess), or nil.
local function core()
    if type(GreenFangToolkit_DevAccess) ~= "function" then return nil end
    local okCall, ns = pcall(GreenFangToolkit_DevAccess)
    return okCall and type(ns) == "table" and ns or nil
end
P.core = core

local function inCombat(ns)
    if ns and ns.inCombat then return ns.inCombat() end
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local active = {}   -- [group] = true: "notify" / "settings" / "confirm" / "lists"
P.active = active
function P.isActive() return next(active) ~= nil end

---------------------------------------------------------------------------
-- Swapped functions (put back by P.off)
---------------------------------------------------------------------------

local swaps = {}    -- { t, k, orig, group }
local function swap(group, t, k, fn)
    if type(t) ~= "table" then return false end
    for _, s in ipairs(swaps) do
        if s.t == t and s.k == k then t[k] = fn; return true end
    end
    swaps[#swaps + 1] = { t = t, k = k, orig = t[k], group = group }
    t[k] = fn
    return true
end
local function original(t, k)
    for _, s in ipairs(swaps) do if s.t == t and s.k == k then return s.orig end end
    return t[k]
end
local function unswap(group)
    for i = #swaps, 1, -1 do
        local s = swaps[i]
        if not group or s.group == group then s.t[s.k] = s.orig; table.remove(swaps, i) end
    end
end
function P.swapCount() return #swaps end

---------------------------------------------------------------------------
-- The banner over the main window (and the notice list), the page covers
---------------------------------------------------------------------------

local banners = {}  -- [frame] = font string
local function bannerOn(frame)
    if not frame then return end
    local fs = banners[frame]
    if not fs then
        fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("BOTTOM", frame, "TOP", 0, 6)
        if fs.SetTextColor then fs:SetTextColor(1, 0.35, 0.25) end
        banners[frame] = fs
    end
    fs:SetText(P.BANNER)
    fs:Show()
end
function P.updateBanner()
    local ns = core()
    local on = P.isActive()
    if on and ns then
        local win = ns.Framework and _G[ns.Framework.WINDOW_NAME]
        bannerOn(win)
        local list = ns.NotifyUI and ns.NotifyUI.list and ns.NotifyUI.list()
        if active.notify or active.settings then bannerOn(list) end
    end
    for frame, fs in pairs(banners) do
        local keep = on and (frame ~= (ns and ns.NotifyUI and ns.NotifyUI.list and ns.NotifyUI.list()) or active.notify or active.settings)
        if keep then fs:Show() else fs:Hide() end
    end
end
function P.bannerText()
    for _, fs in pairs(banners) do if fs:IsShown() then return fs:GetText() end end
    return nil
end

local covers = {}   -- [page id] = frame
P.covers = covers
local function scrollBy(sf, delta, step)
    if not (sf and sf.GetVerticalScroll and sf.SetVerticalScroll) then return end
    local cur = tonumber((sf:GetVerticalScroll())) or 0
    local max = sf.GetVerticalScrollRange and tonumber((sf:GetVerticalScrollRange())) or nil
    local v = math.max(0, cur - (delta or 0) * step)
    if max and max >= 0 then v = math.min(max, v) end
    sf:SetVerticalScroll(v)
end
local function cover(ns, page, onWheel)
    local panel = ns.Framework.panel and ns.Framework.panel(page)
    if not panel then return nil end
    local c = covers[page]
    if not c then
        c = CreateFrame("Frame", nil, panel)
        c:SetAllPoints(panel)
        local level = panel.GetFrameLevel and tonumber((panel:GetFrameLevel())) or 1
        if c.SetFrameLevel then c:SetFrameLevel(level + 60) end
        c:EnableMouse(true)
        if c.EnableMouseWheel then c:EnableMouseWheel(true) end
        c.band = c:CreateTexture(nil, "BACKGROUND")
        c.band:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        c.band:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
        c.band:SetHeight(34)
        if c.band.SetColorTexture then c.band:SetColorTexture(0, 0, 0, 0.8) end
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        c.text:SetPoint("TOP", c, "TOP", 0, -8)
        if c.text.SetTextColor then c.text:SetTextColor(1, 0.35, 0.25) end
        c.text:SetText(P.COVER_TEXT)
        c:SetScript("OnMouseWheel", function(self, delta) if self.onWheel then self.onWheel(delta) end end)
        c:SetScript("OnMouseDown", function() say("預覽中：這頁的按鈕暫停（/gftkdev preview off 結束）") end)
        covers[page] = c
    end
    c.onWheel = onWheel
    c:Show()
    return c
end

---------------------------------------------------------------------------
-- Made-up people (shown by Share.memberFor; never in the roster snapshot)
---------------------------------------------------------------------------

P.CLASSES = {
    { "WARRIOR", "戰士" }, { "MAGE", "法師" }, { "PRIEST", "牧師" }, { "ROGUE", "盜賊" }, { "DRUID", "德魯伊" },
    { "HUNTER", "獵人" }, { "WARLOCK", "術士" }, { "PALADIN", "聖騎士" }, { "SHAMAN", "薩滿" },
}
P.ZONES = { "暴風城", "艾爾文森林", "西部荒野", "赤脊山", "暮色森林", "濕地", "荊棘谷", "塵泥沼澤", "灰谷", "悲傷沼澤", "這是一個名字特別特別長、用來看會不會被切掉的區域" }
P.PROFS = { { "裁縫", "附魔" }, { "製皮", "剝皮" }, { "鍛造", "採礦" }, { "鍊金術", "草藥學" }, { "工程學", "採礦" }, {} }

function P.name(i)
    local base = P.NAMES[(i - 1) % #P.NAMES + 1]
    if i > #P.NAMES then base = base .. math.floor((i - 1) / #P.NAMES) end
    if i == 7 then base = base .. "名字特別長的角色" end
    return base
end
function P.author(i) return string.format("pv-%04d", i) end

local people = {}   -- [author] = member
P.people = people
local function person(i)
    local a = P.author(i)
    if not people[a] then
        local c = P.CLASSES[(i - 1) % #P.CLASSES + 1]
        people[a] = { name = P.name(i) .. "-預覽伺服器", class = c[2], classToken = c[1], race = "人類",
            level = 10 + (i * 7) % 51, zone = P.ZONES[(i - 1) % #P.ZONES + 1], online = i % 3 ~= 0,
            guildRank = ({ "會長", "幹部", "會員", "新進" })[(i - 1) % 4 + 1], rankIndex = (i - 1) % 4,
            professions = P.PROFS[(i - 1) % #P.PROFS + 1], professionSource = "roster", raceSource = "roster",
            guid = string.format("PV-%04d", i), gfPreview = true }
    end
    return a, people[a]
end

local function swapPeople(ns)
    local S = ns.Share
    if not S then return end
    local orig = original(S, "memberFor")
    swap("lists", S, "memberFor", function(a, ...)
        local m = people[a]
        if m then return m end
        return orig(a, ...)
    end)
end

---------------------------------------------------------------------------
-- notify: made-up notices of every kind, in the toolkit's own words
---------------------------------------------------------------------------

-- GF-UI-N (owner 0.16.12: 「各種通知有比對到、有顯示驚嘆號時的訊息」): the words
-- come from the toolkit's own text functions with made-up records (the same ones
-- that write the real notices), every kind and every variant of a reminder (the
-- ones the ❗ on a page also shows), half of them unread. Two texts are written
-- inside files this task may not touch (Adventure.lua's signup line, Bank.lua);
-- they are copied here word for word and a test checks them against those files.
P.ATTENTION = { adv_remind = true, adv_leader = true, order_remind = true } -- the ❗'s reminders
P.PEOPLE = { ["pv:a"] = "測試甲", ["pv:b"] = "測試乙", ["pv:c"] = "測試丙", ["pv:d"] = "測試丁" }
P.ITEM = { cloth = 2589, bar = 2840, potion = 929 }
P.LONG_TEXT = "這是一則特別長的假通知，用來看文字太長時會不會被切掉、按鈕會不會被擠到，請看這一行最後面有沒有出現三個點"
-- Copies (see above): Adventure.notifyScan's 報名 line, Bank.notifyKeeper's three lines.
P.SIGNUP_TEXT = "%s 報名了你的冒險單 %s%s"
P.SIGNUP_WAIT = "，等你審核"
P.BANK_TEXT = { on = "會長指定你為臨時黑箱保管人（%s）", change = "會長把你的保管範圍改成%s", off = "會長撤銷了你的臨時黑箱保管人資格" }

local function fakeDungeon(ns, i)
    local ids = { "dm", "sfk", "wc", "bfd", "stk", "rfk", "gnr", "rfc" }
    local id = ids[(i - 1) % #ids + 1]
    if ns.AdventureData and ns.AdventureData.byId and ns.AdventureData.byId[id] then return id end
    return nil
end
-- A made-up ticket the way Adventure.all() gives one (only what the text functions read).
local function fakeView(ns, i, f)
    local v = { id = "pv" .. i, dungeon = fakeDungeon(ns, i), zone = "預覽區域", quests = {}, members = {}, waitlist = {},
        pending = {}, invited = {}, kicked = {}, created = ns.now() - 3600 }
    for k, x in pairs(f or {}) do v[k] = x end
    if v.slots and not v.slotById then
        v.slotById = {}
        for _, sl in ipairs(v.slots) do v.slotById[sl.id] = sl end
    end
    return v
end

-- { { module, text, actions } } in the toolkit's own words.
function P.realNotices(ns)
    local out = {}
    local function add(module, text, actions)
        if type(text) == "string" and text ~= "" then out[#out + 1] = { module = module, text = text, actions = actions } end
    end
    local t = ns.now()
    local my = "pv:me"
    local Adv, O, S = ns.Adventure, ns.Orders, ns.Share
    -- Made-up people for the name lookups, only while the words are made.
    local member, memberFor = Adv and Adv.member, S and S.memberFor
    local function person(a) local n = P.PEOPLE[a]; return n and { name = n .. "-預覽伺服器" } or nil end
    if Adv and member then Adv.member = function(a, ...) return person(a) or member(a, ...) end end
    if S and memberFor then S.memberFor = function(a, ...) return person(a) or memberFor(a, ...) end end
    local okRun, err = pcall(function()
        local function item(id)
            local name = ns.itemInfo and ns.itemInfo(id)
            return (type(name) == "string" and name ~= "") and name or ("物品 #" .. id)
        end
        -- 調貨所 / 雷達 / 圖紙 (SupplyRadar, RecipeLink).
        local R = ns.SupplyRadar
        if R then
            add("supply", R.MATCH_TEXT.need(item(P.ITEM.cloth), 3, 1), { { key = "view", text = "查看需求" }, { key = "ignore", text = "忽略" } })
            add("supply", R.MATCH_TEXT.offer(item(P.ITEM.bar), 2, 2))
            add("supply", R.moreText("need", 4))
            add("radar", R.radarText(item(P.ITEM.bar), 12, 3), R.ACTIONS)
        end
        if ns.RecipeLink then add("recipe", ns.RecipeLink.learnedText("亞麻斗篷"), { ns.RecipeLink.END_ACTION }) end
        -- 職工單配對 (WorkerMatch).
        if ns.WorkerMatch and ns.WorkerMatch.text then
            local sl = { id = 1, s = t + 7200, d = 7200 }
            add("adventure", ns.WorkerMatch.text({ view = fakeView(ns, 1, { leader = "pv:b", slots = { sl } }), slot = sl, role = "h" }))
        end
        -- 委託 (Orders.notifyText): every code of each switch.
        if O and O.notifyText then
            local v = { id = "pvo", item = P.ITEM.potion, qty = 5 }
            local codes = {
                { "order_new", "new" }, { "order_guild", "guild" },
                { "order_status", "taken" }, { "order_status", "delivered" }, { "order_status", "returned" },
                { "order_status", "dropped" }, { "order_status", "deal-customer" }, { "order_status", "cancel-web" },
                { "order_remind", "stale-waiting", 4 }, { "order_remind", "stale-making", 7 }, { "order_remind", "close" },
            }
            for _, c in ipairs(codes) do add(c[1], O.notifyText(v, { code = c[2], who = "pv:c", n = c[3] })) end
        end
        -- 冒險 (Adventure.notifyEvents on made-up tickets).
        if Adv and Adv.notifyEvents then
            local function events(v, prev)
                local okE, list = pcall(Adv.notifyEvents, v, my, prev, t)
                for _, ev in ipairs(okE and list or {}) do add(ev.module, ev.text) end
            end
            local s1, s2 = { id = 1, s = t + 20 * 60, d = 7200 }, { id = 2, s = t + 3 * 3600, d = 7200 }
            -- My ticket: 待定案, 遞補, 候補的職工單離開 (adv_leader).
            events(fakeView(ns, 2, { leader = my, slots = { s1, s2 }, members = { { a = "pv:a", at = t - 900, refilled = t - 300 } },
                workerGone = { { a = "pv:b", at = t - 200 } } }))
            -- My ticket, 定案, in 15 minutes (adv_remind).
            local s3 = { id = 1, s = t + 14 * 60, d = 7200 }
            events(fakeView(ns, 3, { leader = my, slots = { s3 }, final = 1, slot = s3 }))
            -- I am in: 改內容, 遞補上, 定案, 60 分鐘 (adv_update, adv_result, adv_final, adv_remind).
            local s4, s5 = { id = 1, s = t + 50 * 60, d = 7200 }, { id = 2, s = t + 5 * 3600, d = 7200 }
            events(fakeView(ns, 4, { leader = "pv:c", slots = { s4, s5 }, final = 1, slot = s4, finalAt = t - 60, edited = t - 30,
                members = { { a = my, at = t - 3000, refilled = t - 100 } } }), "w")
            -- Invited; 錄取; not taken (adv_result).
            events(fakeView(ns, 5, { leader = "pv:d", slots = { s5 }, invited = { { a = my, at = t - 20 } } }))
            events(fakeView(ns, 6, { leader = "pv:d", slots = { s5 }, members = { { a = my, at = t - 50 } } }), "p")
            events(fakeView(ns, 7, { leader = "pv:d", slots = { s5 }, kicked = { [my] = t - 40 } }), "p")
            -- Cancelled, 過期 (adv_final, adv_update).
            events(fakeView(ns, 8, { leader = "pv:c", slots = { s5 }, closed = true, state = "cancel", closedAt = t - 30,
                members = { { a = my, at = t - 600 } } }))
            events(fakeView(ns, 1, { leader = "pv:c", slots = { s5 }, closed = true, state = "ended", closedAt = t - 40,
                waitlist = { { a = my, at = t - 600 } } }))
            -- 報名 (adv_signup; see P.SIGNUP_TEXT).
            local dest = Adv.notifyDest and Adv.notifyDest(fakeView(ns, 2, {})) or "冒險單"
            add("adv_signup", string.format(P.SIGNUP_TEXT, "測試甲 等 2 人", dest, P.SIGNUP_WAIT))
            add("adv_signup", string.format(P.SIGNUP_TEXT, "測試乙", dest, ""))
        end
        -- 臨時黑箱 (see P.BANK_TEXT).
        local kinds = ns.Bank and ns.Bank.KINDS_TEXT or {}
        local k1 = kinds.b or "背包"
        add("bank_keeper", string.format(P.BANK_TEXT.on, k1))
        add("bank_keeper", string.format(P.BANK_TEXT.change, k1))
        add("bank_keeper", P.BANK_TEXT.off)
    end)
    if Adv and member then Adv.member = member end
    if S and memberFor then S.memberFor = memberFor end
    if not okRun then say("預覽：有一種通知的文字做不出來（" .. tostring(err) .. "）") end
    return out
end

local notices = {}
P.notices = notices
function P.buildNotices(ns)
    local N = ns.Notify
    local t = ns.now()
    for i = #notices, 1, -1 do notices[i] = nil end
    local have = {}
    for i, r in ipairs(P.realNotices(ns)) do
        have[r.module] = true
        notices[#notices + 1] = { id = -i, gfPreview = true, module = r.module, key = "preview:" .. r.module .. ":" .. i,
            text = r.text, t = t - i * 300, unread = i % 2 == 1, count = 1, actions = r.actions, expires = t + 86400,
            attention = P.ATTENTION[r.module] or nil }
    end
    -- A switch with no text function above (a new one): its name, so nothing is missing.
    for i, m in ipairs(N.MODULES) do
        if not have[m.key] then
            notices[#notices + 1] = { id = -200 - i, gfPreview = true, module = m.key, key = "preview:" .. m.key,
                text = m.text .. "（預覽：還沒有對應的文字）", t = t - i * 60, unread = i % 2 == 0, count = 1, expires = t + 86400 }
        end
    end
    -- 「另有 N 則」: what N.push makes past N.BURST a minute (GF-014-04).
    notices[#notices + 1] = { id = -100, gfPreview = true, module = "supply", key = N.MORE_KEY, more = 12, count = 12,
        text = string.format(N.MORE_TEXT, 12, N.MODULE_TEXT.supply or "通知"), t = t - 60, unread = true, expires = t + 86400 }
    notices[#notices + 1] = { id = -101, gfPreview = true, module = "order_status", key = "preview:long", count = 3,
        text = P.LONG_TEXT, t = t - 3 * 86400, unread = false, expires = t + 86400,
        actions = { { key = "view", text = "查看" }, { key = "ignore", text = "忽略" } } }
    table.sort(notices, function(x, y) if x.t ~= y.t then return x.t > y.t end return x.id > y.id end)
    return notices
end

local function dropNotice(e)
    for i, x in ipairs(notices) do if x == e then table.remove(notices, i); return true end end
    return false
end

local function swapNotify(ns)
    local N = ns.Notify
    local get, open, action, dismiss = original(N, "get"), original(N, "open"), original(N, "action"), original(N, "dismiss")
    swap("notify", N, "list", function()
        local out = {}
        for i, e in ipairs(notices) do out[i] = e end
        return out
    end)
    swap("notify", N, "get", function(id, ...)
        for _, e in ipairs(notices) do if e.id == id then return e end end
        return get(id, ...)
    end)
    swap("notify", N, "open", function(e, ...)
        if type(e) == "table" and e.gfPreview then
            N.markRead(e)
            say("預覽：這是假通知，點了不會跳到任何頁面")
            return "preview"
        end
        return open(e, ...)
    end)
    swap("notify", N, "action", function(e, key, ...)
        if type(e) == "table" and e.gfPreview then
            if key == "ignore" then dropNotice(e) end
            e.unread = false
            say("預覽：按鈕「" .. tostring(key) .. "」不會執行")
            N.changed()
            return "preview"
        end
        return action(e, key, ...)
    end)
    swap("notify", N, "dismiss", function(e, ...)
        if type(e) == "table" and e.gfPreview then dropNotice(e); N.changed(); return end
        return dismiss(e, ...)
    end)
end

function P.notify(ns)
    P.buildNotices(ns)
    swapNotify(ns)
    active.notify = true
    local UI = ns.NotifyUI
    UI.open()
    P.updateBanner()
    UI.draw()
    local unread = 0
    for _, e in ipairs(notices) do if e.unread then unread = unread + 1 end end
    say(string.format("通知中心：%d 則假通知（%d 種都有，文字和正式通知同一個來源；%d 則未讀、%d 則已讀，另有「另有 N 則」與一則很長的）。用滾輪看下面；忽略、全部已讀只動假通知",
        #notices, #ns.Notify.MODULES, unread, #notices - unread))
    return true
end

---------------------------------------------------------------------------
-- settings: the notice switches, clicks not saved
---------------------------------------------------------------------------

local boxSets = {}  -- [box] = its set function while previewing
local function settingsBoxes(ns)
    local list = ns.NotifyUI.list and ns.NotifyUI.list()
    return list and list.settings and list.settings.boxes or {}, list
end
local function resync(ns)
    local _, list = settingsBoxes(ns)
    if list and list.settings and list.settings.sync then list.settings.sync() end
end

function P.settings(ns)
    local UI, N = ns.NotifyUI, ns.Notify
    local f = UI.open()
    active.settings = true
    local function refuse() say("預覽：設定不會儲存（/gftkdev preview off 後才能改）"); resync(ns) end
    swap("settings", N, "setEnabled", function() refuse() end)
    swap("settings", N, "setChat", function() refuse() end)
    for _, c in ipairs((settingsBoxes(ns))) do
        if c.set and not boxSets[c] then
            boxSets[c] = c.set
            c.set = function() say("預覽：設定不會儲存（/gftkdev preview off 後才能改）") end
        end
    end
    local click = f.setup and f.setup.GetScript and f.setup:GetScript("OnClick")
    if click then click(f.setup) end
    P.updateBanner()
    local boxes = settingsBoxes(ns)
    local two = false
    for _, c in ipairs(boxes) do if c.col == 1 then two = true end end
    say(string.format("通知設定：%d 列%s。勾選看得到，但不會存檔", #boxes, two and "（兩欄）" or ""))
    return true
end

local function settingsOff(ns)
    for c, set in pairs(boxSets) do c.set = set; boxSets[c] = nil end
    resync(ns)
end

---------------------------------------------------------------------------
-- confirm: every confirm box the toolkit has, one at a time, nothing runs
---------------------------------------------------------------------------

-- popup = the toolkit's StaticPopup name (its button names are read from it
-- when it was made already); widget = the toolkit's own small box (Widgets.confirm).
function P.confirmList(ns)
    local RL, SU, G = ns.RecipeLink or {}, ns.SupplyUI or {}, ns.GuildAdmin or {}
    local GP = G.POPUP or {}
    return {
        { name = "學會圖紙後：要不要結束徵求（調貨所）", popup = RL.POPUP,
            text = string.format(RL.ASK_TEXT or "%s %s x%d", "亞麻斗篷", "圖樣：亞麻斗篷", 1),
            b1 = RL.END_ACTION and RL.END_ACTION.text or "結束徵求", b2 = "先留著" },
        { name = "放棄編輯（調貨所刊登）", popup = SU.POPUP_DISCARD, text = SU.DISCARD_TEXT or "放棄未儲存的修改？", b1 = "放棄", b2 = "繼續編輯" },
        { name = "結束刊登（調貨所）", widget = true, text = "結束這筆徵求？其他職工之後不會再看到它。" },
        { name = "刪除已結束的刊登（調貨所）", widget = true, text = "刪除這筆已結束的供應？" },
        { name = "刪除冒險單", widget = true, text = "刪除：死亡礦坑（測試甲的冒險單）" },
        { name = "清除已結束和成行紀錄（冒險單）", widget = true, text = "清除已結束和成行紀錄" },
        { name = "清除已結案的委託紀錄（同步與診斷）", popup = GP.confirm,
            text = "清除已結案的訂單紀錄？\n我下的 3、我接的 2、測試 0、歷史 5", b1 = "確定", b2 = "取消" },
        { name = "名冊：降一階", popup = GP.confirm, text = "把 測試甲 降一階？", b1 = "確定", b2 = "取消" },
        { name = "名冊：踢出公會", popup = GP.confirm, text = "把 測試乙 踢出公會？", b1 = "確定", b2 = "取消" },
        { name = "名冊：公會註記（輸入框）", popup = GP.edit, edit = true, text = "測試丙 的公會註記", current = "預覽用的註記", max = 31, b1 = "確定", b2 = "取消" },
        { name = "名冊：幹部註記（輸入框）", popup = GP.edit, edit = true, text = "測試丁 的幹部註記", current = "", max = 31, b1 = "確定", b2 = "取消" },
        { name = "名冊：邀請入會（輸入框）", popup = GP.edit, edit = true, text = "邀請入會：角色名字", current = "", max = 48, b1 = "確定", b2 = "取消" },
        { name = "公會：今日訊息（輸入框）", popup = GP.edit, edit = true, text = "今日訊息", current = "（預覽）今晚 21:00 死亡礦坑門口集合，記得帶藥水", max = 128, b1 = "確定", b2 = "取消" },
        { name = "公會：公會資訊（輸入框）", popup = GP.edit, edit = true, text = "公會資訊", current = "（預覽）這是一段假的公會資訊。", max = G.INFO_MAX or 500, b1 = "確定", b2 = "取消" },
    }
end

local chain = { list = nil, i = 0, current = nil }
P.chain = chain
local hookedWidget = false

local function nextSoon()
    local ns = core()
    if ns and ns.after then ns.after(0, P.confirmNext) else P.confirmNext() end
end

local function dialogs()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    StaticPopupDialogs[P.POPUP] = StaticPopupDialogs[P.POPUP] or {
        text = "%s", button1 = "確定", button2 = "取消", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function() say("預覽：不會執行") end,
        OnCancel = function() end,
        OnHide = function() if chain.current and not chain.current.widget then nextSoon() end end,
    }
    StaticPopupDialogs[P.POPUP_EDIT] = StaticPopupDialogs[P.POPUP_EDIT] or {
        text = "%s", button1 = "確定", button2 = "取消", hasEditBox = true, maxLetters = 31,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnShow = function(self, data)
            local box = self and (self.editBox or self.EditBox)
            if box and data then
                if box.SetMaxLetters then box:SetMaxLetters(data.max or 31) end
                box:SetText(data.text or "")
                if box.HighlightText then box:HighlightText() end
            end
        end,
        OnAccept = function() say("預覽：不會儲存") end,
        OnCancel = function() end,
        EditBoxOnEnterPressed = function(box) local p = box and box:GetParent(); if p then p:Hide() end end,
        EditBoxOnEscapePressed = function(box) local p = box and box:GetParent(); if p then p:Hide() end end,
        OnHide = function() if chain.current and not chain.current.widget then nextSoon() end end,
    }
    return true
end

local function showOne(ns, item)
    if item.widget then
        local W = ns.Widgets
        local f = W.confirm(item.text, nil) -- 確定 with nothing to run
        if f and not hookedWidget and f.HookScript then
            hookedWidget = true
            f:HookScript("OnHide", function() if chain.current and chain.current.widget then nextSoon() end end)
        end
        return f
    end
    if not dialogs() then return nil end
    local name = item.edit and P.POPUP_EDIT or P.POPUP
    local def = StaticPopupDialogs[name]
    local real = item.popup and StaticPopupDialogs[item.popup]
    def.button1 = (real and real.button1) or item.b1 or "確定"
    def.button2 = (real and real.button2) or item.b2 or "取消"
    if item.edit then def.maxLetters = item.max or 31 end
    return StaticPopup_Show(name, item.text, nil, { text = item.current, max = item.max })
end

-- The next box of the chain (after the open one closed). Returns its item.
function P.confirmNext()
    local ns = core()
    if not (chain.list and ns) then return nil end
    chain.current = nil
    if inCombat(ns) then
        say("戰鬥中：確認視窗預覽先停，戰鬥後再打 /gftkdev preview confirm")
        chain.list, active.confirm = nil, nil
        P.updateBanner()
        return nil
    end
    while chain.i < #chain.list do
        chain.i = chain.i + 1
        local item = chain.list[chain.i]
        chain.current = item
        if showOne(ns, item) then
            say(string.format("確認視窗 %d/%d：%s（按什麼都不會執行；關掉後出下一個）", chain.i, #chain.list, item.name))
            return item
        end
        say(string.format("確認視窗 %d/%d：%s 叫不出來（這個用戶端沒有）", chain.i, #chain.list, item.name))
        chain.current = nil
    end
    say("確認視窗都看完了")
    chain.list, active.confirm = nil, nil
    P.updateBanner()
    return nil
end

function P.confirm(ns)
    chain.list, chain.i, chain.current = P.confirmList(ns), 0, nil
    active.confirm = true
    P.updateBanner()
    say(string.format("確認視窗共 %d 個，一次一個", #chain.list))
    return P.confirmNext() ~= nil
end

local function confirmOff(ns)
    local cur = chain.current
    chain.list, chain.current, chain.i = nil, nil, 0
    if cur then
        if cur.widget then
            local f = ns.Widgets.confirmFrame and ns.Widgets.confirmFrame()
            if f and f:IsShown() then f.onYes = nil; f:Hide() end
        elseif type(StaticPopup_Hide) == "function" then
            pcall(StaticPopup_Hide, P.POPUP); pcall(StaticPopup_Hide, P.POPUP_EDIT)
        end
    end
end

---------------------------------------------------------------------------
-- lists: made-up rows on 委託, 冒險單 (and 職工單), 調貨所, 名冊
---------------------------------------------------------------------------

P.ITEMS = { 2589, 2592, 4306, 2840, 2318, 118, 858, 2581, 3530, 2842, 765, 785 }
P.SKILLS = { 197, 165, 164, 171, 202, 185 }
P.DUNGEONS = { "dm", "wc", "sfk", "stk", "bfd", "smg", "rfc", "gnr" }
P.NOTE_LONG = "這是一段特別長的備註，用來看清單和詳細資料裡的長文字會不會被切掉、會不會擠到旁邊的欄位，最後面應該要看得到三個點或換行"

local rows = { orders = {}, adventure = {}, supply = {}, roster = {} }
P.rows = rows

local function at(t, i, step) return t - i * (step or 3600) end

-- 委託: Orders.view (the module's own merge, pure) from made-up halves.
function P.buildOrders(ns, n)
    local O, S = ns.Orders, ns.Share
    local me = S.selfAuthor()
    local t = S.serverNow()
    local received, placed = {}, {}
    -- customer half (w), crafter half (jobs): every state the page shows.
    local kinds = {
        function(w, c) return w, {} end,                                                        -- 等接單
        function(w, c) return w, { [c] = { st = "a", ac = w.cr + 600, sa = w.cr + 600 } } end,  -- 製作中
        function(w, c) return w, { [c] = { st = "d", ac = w.cr + 600, dt = w.cr + 7200, sa = w.cr + 7200, gv = w.q } } end, -- 待確認
        function(w, c) w.st, w.sa = "d", w.cr + 9000; return w, { [c] = { st = "d", ac = w.cr + 600, dt = w.cr + 7200, sa = w.cr + 7200 } } end, -- 成交
        function(w, c) w.st, w.sa = "x", w.cr + 900; return w, {} end,                          -- 取消
        function(w, c) w.rt = w.cr + 8000; return w, { [c] = { st = "d", ac = w.cr + 600, dt = w.cr + 7200, sa = w.cr + 7200 } } end, -- 退回
        function(w, c) w.st, w.sa = "p", w.cr + 7300; return w, { [c] = { st = "a", ac = w.cr + 600, sa = w.cr + 600 } } end, -- 不確定
    }
    for i = 1, n do
        local other = person(i)
        local mine = i % 2 == 0 -- even: I placed it; odd: I make it
        local w = { id = string.format("pv-o%03d", i), src = "g", cr = at(t, i, 5400), it = P.ITEMS[(i - 1) % #P.ITEMS + 1],
            sk = P.SKILLS[(i - 1) % #P.SKILLS + 1], q = (i * 3) % 40 + 1, fe = (i % 4 == 0) and 0 or (i * 2500), fq = (i % 5 == 0) and nil or 1,
            pd = (i % 6 == 0) and "1" or nil }
        local crafter = mine and other or me
        w.cf = (mine and i % 7 == 0) and "*" or crafter
        local jobs
        w, jobs = kinds[(i - 1) % #kinds + 1](w, crafter)
        if w.cf == "*" then jobs = {} end
        local okView, v = pcall(O.view, w, jobs, mine and me or other)
        if okView and v then
            v.gfPreview = true
            local okAtt, att = pcall(O.attention, v, me, ns.Data.player().guid, t, O.staleDays and O.staleDays() or 2)
            local row = { view = v, attention = okAtt and att or nil }
            if mine then placed[#placed + 1] = row else received[#received + 1] = row end
        end
    end
    local out = {}
    local GI = ns.GameIcons
    if #received > 0 then
        out[#out + 1] = { header = GI.markup("received", 16) .. " 收到的（預覽）", count = #received }
        for _, r in ipairs(received) do out[#out + 1] = r end
    end
    if #placed > 0 then
        out[#out + 1] = { header = GI.markup("placed", 16) .. " 我下的（預覽）", count = #placed }
        for _, r in ipairs(placed) do out[#out + 1] = r end
    end
    rows.orders = out
    return out
end

-- 冒險單: Adventure.view (pure) from made-up tickets; 職工單 the way Adventure.workers builds them.
local function fakeWorker(A, e, online)
    local ds, dl, qs, ql = {}, {}, {}, {}
    for d in tostring(e.ds or ""):gmatch("[^%.]+") do ds[d] = true; dl[#dl + 1] = d end
    for q in tostring(e.qs or ""):gmatch("[^%.]+") do qs[tonumber(q) or q] = true; ql[#ql + 1] = tonumber(q) or q end
    local zl = A.decodeZones(e.zs)
    local zones, whole = {}, {}
    for _, z in ipairs(zl) do zones[z] = true; whole[z] = true end
    return { entry = e, slots = A.workerSlots(e), dungeons = ds, questNames = A.decodeQuestNames(e.qn), questCount = e.qc,
        quests = qs, allQuests = false, main = e.rm, alt = e.ra ~= "" and e.ra or nil, online = online, dungeonList = dl,
        questList = ql, expires = e.ex, zoneList = zl, zones = zones, wholeZones = whole, gfPreview = true }
end

function P.buildAdventure(ns, n)
    local A, S = ns.Adventure, ns.Share
    local me = S.selfAuthor()
    local t = S.serverNow()
    local roles = { "t", "h", "d", "d", "d" }
    local states = { "o", "o", "o", "g", "x", "o", "c" }
    local open, ended = {}, {}
    local log = A.questLog and A.questLog() or {}
    for i = 1, n do
        local leaderI = i + 1
        local leader = (i % 4 == 1) and me or person(leaderI)
        local st = states[(i - 1) % #states + 1]
        local start = t + ((i % 5) - 1) * 3600
        local slots = { { id = 1, s = start, d = 7200 } }
        if i % 3 == 0 then slots[2] = { id = 2, s = start + 86400, d = 5400 } end
        local raw = { id = string.format("pv-a%03d", i), src = "g", ver = 1, cr = at(t, i, 1800),
            ds = (i % 6 == 0) and "" or P.DUNGEONS[(i - 1) % #P.DUNGEONS + 1], qs = (i % 6 == 0) and "101.102" or "",
            ts = A.encodeTimes(slots), rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = st,
            sa = (st == "o") and at(t, i, 1800) or (t - 600), sz = 5,
            nt = (i % 5 == 0) and P.NOTE_LONG or ((i % 2 == 0) and "（預覽）缺補" or ""),
            zn = (i % 6 == 0) and "西部荒野" or nil, fx = (st == "g") and 1 or nil }
        local actions = {}
        for k = 1, (i % 4) + 1 do
            local a = person(i + k + 1)
            actions[a] = { { id = raw.id, ac = "ap", at = raw.cr + k * 60, ro = roles[(k - 1) % #roles + 1], rb = "", sx = nil } }
        end
        if leader ~= me and i % 3 == 0 then actions[me] = { { id = raw.id, ac = "ap", at = raw.cr + 30, ro = "h", rb = "" } } end
        local okView, v = pcall(A.view, raw, leader, actions, { now = t })
        if okView and v then
            v.gfPreview = true
            local okAtt, att = pcall(A.attention, v, me, t, nil, log)
            local row = { view = v, attention = okAtt and att or nil }
            if v.closed then ended[#ended + 1] = row else open[#open + 1] = row end
        end
    end
    local out = {}
    -- my own worker ticket
    local mine = { dungeons = { "dm", "sfk" }, quests = {}, allQuests = false, main = "t", alt = "d",
        slots = { { id = 1, s = t + 3600, d = 7200 } }, expires = t + 86400, questNames = {}, zones = {}, gfPreview = true }
    out[#out + 1] = { header = "我的職工單（預覽）" }
    out[#out + 1] = { myWorker = mine }
    if #open > 0 then
        out[#out + 1] = { header = "冒險單（預覽）" }
        for _, r in ipairs(open) do out[#out + 1] = r end
    end
    if #ended > 0 then
        out[#out + 1] = { header = "已結束的冒險單（預覽）" }
        for _, r in ipairs(ended) do out[#out + 1] = r end
    end
    local workers = math.max(2, math.floor(n / 3))
    local ticket = open[1] and open[1].view
    local matched, others = {}, {}
    for i = 1, workers do
        local a = person(200 + i)
        local e = { ds = (i % 3 == 0) and "" or (P.DUNGEONS[(i - 1) % #P.DUNGEONS + 1] .. "." .. P.DUNGEONS[i % #P.DUNGEONS + 1]),
            qs = (i % 3 == 0) and "101.102.103" or "", rm = roles[(i - 1) % 3 + 1], ra = (i % 2 == 0) and "d" or "",
            sv = A.encodeTimes({ { id = 1, s = t + i * 1800, d = 3600 } }), ex = t + 86400,
            zs = (i % 4 == 0) and "西部荒野;暮色森林" or "", cr = t - 600 }
        local w = fakeWorker(A, e, i % 3 ~= 0)
        if ticket and i <= 2 then matched[#matched + 1] = { isWorker = true, w = w, worker = a, ticket = ticket }
        else others[#others + 1] = { otherWorker = w, worker = a } end
    end
    if #matched > 0 then
        out[#out + 1] = { header = "職工單（預覽）" }
        for _, r in ipairs(matched) do out[#out + 1] = r end
    end
    if #others > 0 then
        out[#out + 1] = { header = "全部職工（預覽）" }
        for _, r in ipairs(others) do out[#out + 1] = r end
    end
    rows.adventure = out
    return out
end

-- 調貨所: rows the way SupplyUI.listFor("mine") makes them, from made-up 刊登.
function P.buildSupply(ns, n)
    local L, S = ns.SupplyListings, ns.Share
    local t = S.serverNow()
    local cats = { "recipe", "material", "gear", "consumable" }
    local statuses = { "active", "active", "active", "closed", "cancelled", "expired" }
    local terms = { "negotiable", "free", "price", "swap" }
    local live, ended = {}, {}
    for i = 1, n do
        local l = { id = string.format("pv-s%03d", i), itemID = P.ITEMS[(i - 1) % #P.ITEMS + 1],
            direction = i % 2 == 1 and "need" or "offer", quantity = (i * 7) % 60 + 1,
            category = cats[(i - 1) % #cats + 1], status = statuses[(i - 1) % #statuses + 1],
            expiresAt = t + ((i % 9) + 1) * 86400, terms = terms[(i - 1) % #terms + 1], price = i * 1234,
            note = (i % 4 == 0) and P.NOTE_LONG or ((i % 3 == 0) and "（預覽）可以分批交" or ""), gfPreview = true }
        if l.status == "active" then live[#live + 1] = l else ended[#ended + 1] = l end
    end
    for _, l in ipairs(ended) do live[#live + 1] = l end
    local out = {}
    local UI = ns.SupplyUI
    for _, l in ipairs(live) do
        local left = (l.expiresAt or 0) - t
        local days = left > 0 and math.max(1, math.ceil(left / 86400)) or 0
        local q = L.DIRECTION_TEXT[l.direction] .. " " .. l.quantity
        local st = L.STATUS_TEXT[l.status] or ""
        local tip = { L.categoryText(l.category), "交易條件：" .. L.termsText(l.terms, l.price) }
        if (l.note or "") ~= "" then tip[#tip + 1] = "備註：" .. l.note end
        local teach = UI.teachText and UI.teachText(l.itemID) or nil
        if teach then table.insert(tip, 1, teach) end
        out[#out + 1] = { itemID = l.itemID, listing = l, qty = q, qtyShort = q, match = st, matchShort = st,
            fresh = l.status == "active" and ("剩 " .. days .. " 天") or "", ended = l.status ~= "active",
            tip = tip, hasNote = (l.note or "") ~= "", teach = teach, gfPreview = true }
    end
    rows.supply = out
    return out
end

-- 名冊: made-up members (the page's own filter and sort run on them).
function P.buildRoster(ns, n)
    local out = {}
    for i = 1, n do
        local _, m = person(i)
        out[#out + 1] = m
    end
    rows.roster = out
    return out
end

P.PAGES = {
    { id = "orders", text = "委託" },
    { id = "adventure", text = "冒險單（含職工單）" },
    { id = "supply", text = "調貨所（我的刊登）" },
    { id = "roster", text = "名冊" },
}
P.NOT_DONE = {
    { text = "臨時黑箱（保管人名單）", why = "名單直接讀黑箱模組的資料（Bank.current），那份資料也決定誰有權限；換成假的會影響真的權限判斷，所以不做。名單最多十幾位，沒有捲動" },
}

local function refreshPage(ns, id)
    local F = ns.Framework
    if not (F.panel and F.panel(id)) then return end
    local map = { orders = ns.OrdersUI, adventure = ns.AdventureUI, supply = ns.SupplyUI, roster = ns.UI }
    local UI = map[id]
    if UI and UI.refresh then pcall(UI.refresh) end
end

local function swapLists(ns)
    swapPeople(ns)
    local OU, AU, SU, RU = ns.OrdersUI, ns.AdventureUI, ns.SupplyUI, ns.UI
    if OU then swap("lists", OU, "pageRows", function() return rows.orders end) end
    if AU then swap("lists", AU, "pageRows", function() return rows.adventure end) end
    if SU then swap("lists", SU, "listFor", function() return rows.supply end) end
    if RU and RU.filterMembers then
        local orig = original(RU, "filterMembers")
        swap("lists", RU, "filterMembers", function(_, query, filters) return orig(rows.roster, query, filters) end)
    end
end

function P.lists(ns, size)
    local n = size == "many" and P.MANY or P.FEW
    for _, b in ipairs({ { "orders", P.buildOrders }, { "adventure", P.buildAdventure }, { "supply", P.buildSupply }, { "roster", P.buildRoster } }) do
        local okBuild, err = pcall(b[2], ns, n)
        if not okBuild then rows[b[1]] = {}; say("預覽資料做不出來（" .. b[1] .. "）：" .. tostring(err)) end
    end
    swapLists(ns)
    active.lists = true
    local F = ns.Framework
    local shown = {}
    for _, p in ipairs(P.PAGES) do
        local def = F.get(p.id)
        local can = def and (type(def.available) ~= "function" or def.available())
        if can then
            if not F.panel(p.id) then pcall(F.open, p.id) end
            if F.panel(p.id) then
                local wheel
                if p.id == "supply" then wheel = function(d) ns.SupplyUI.scroll(d) end
                elseif p.id == "roster" then wheel = function(d) scrollBy(ns.UI.scrollFrame and ns.UI.scrollFrame(), d, 3 * 28) end
                elseif p.id == "orders" then wheel = function(d) scrollBy(ns.OrdersUI.scrollFrame(), d, 3 * 40) end
                else wheel = function(d) scrollBy(ns.AdventureUI.scrollFrame(), d, 3 * 44) end end
                cover(ns, p.id, wheel)
                shown[#shown + 1] = p.text
            end
        end
    end
    if ns.SupplyUI and F.panel("supply") and ns.SupplyUI.setTab then pcall(ns.SupplyUI.setTab, "mine") end
    for _, p in ipairs(P.PAGES) do refreshPage(ns, p.id) end
    P.updateBanner()
    say(string.format("清單預覽（每頁約 %d 筆）：%s。用主視窗的頁籤切換頁面看", n, #shown > 0 and table.concat(shown, "、") or "沒有頁面能開（不在公會？）"))
    for _, x in ipairs(P.NOT_DONE) do say("沒做：" .. x.text .. "。" .. x.why) end
    return #shown > 0
end

---------------------------------------------------------------------------
-- off, the command
---------------------------------------------------------------------------

function P.off(quiet)
    local ns = core()
    local was = P.isActive()
    if ns then confirmOff(ns); settingsOff(ns) end
    unswap()
    for k in pairs(active) do active[k] = nil end
    for i = #notices, 1, -1 do notices[i] = nil end
    for k in pairs(people) do people[k] = nil end
    for k in pairs(rows) do rows[k] = {} end
    for _, c in pairs(covers) do c:Hide() end
    P.updateBanner()
    if ns then
        for _, p in ipairs(P.PAGES) do refreshPage(ns, p.id) end
        if ns.NotifyUI then
            local list = ns.NotifyUI.list and ns.NotifyUI.list()
            if list and list:IsShown() then list:Hide() end
            ns.NotifyUI.draw()
        end
    end
    if not quiet then say(was and "預覽已關閉，畫面回到真資料" or "目前沒有開著的預覽") end
    return was
end

function P.command(msg)
    local arg, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    arg = arg:lower()
    if arg == "" or arg == "help" then
        say("視窗預覽（只有開發用 AddOn 有；假資料不存檔、不送出）：")
        for _, l in ipairs(P.HELP) do say(l) end
        return "help"
    end
    if arg == "off" then P.off(); return "off" end
    local ns = core()
    if not ns then say("找不到綠皮冒險工具箱（正式的 AddOn 要一起開著）"); return "no-core" end
    if inCombat(ns) then say("戰鬥中不做預覽，戰鬥後再試"); return "combat" end
    if arg == "notify" then P.notify(ns); return "notify" end
    if arg == "settings" then P.settings(ns); return "settings" end
    if arg == "confirm" then P.confirm(ns); return "confirm" end
    if arg == "lists" then
        local size = (rest == "多" or rest:lower() == "many") and "many" or "few"
        P.lists(ns, size)
        return "lists"
    end
    say("不認得「" .. arg .. "」。打 /gftkdev preview 看可以用的項目")
    return "unknown"
end
