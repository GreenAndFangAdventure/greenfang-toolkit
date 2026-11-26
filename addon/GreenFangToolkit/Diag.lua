-- Diag (GF-001-D10 phase 3, D-014 point 6): the 「同步與診斷」 window.
-- Everything technical lives here so the toolkit's pages only show what
-- players use: site sync status and what waits for GF Sync, in-game sharing
-- statistics, the roster scan, versions and clock, and the roster export.
-- Opened by the 「診斷」 button at the bottom right of the pages and by /gftk sync.
-- D-015: no switches; the minimap reset lives here (the settings page is gone).

local _, ns = ...
local str = ns.str

local Diag = {}
ns.Diag = Diag

Diag.WINDOW_NAME = "GreenFangToolkit_DiagWindow"
local window
local lines = {}

-- Pure text builders (offline tests).
function Diag.shareText()
    local Share = ns.Share
    local s = Share.store()
    local records, authors = 0, 0
    for _, groups in pairs(s and s.rec or {}) do
        authors = authors + 1
        for _ in pairs(groups) do records = records + 1 end
    end
    local st = Share.stats
    local text = string.format("記錄 %d / %d 筆（%d 位成員）｜佇列 %d 則｜等待補資料 %d 筆｜這次登入：送出 %d、收到 %d、轉傳 %d、被節流 %d、逾時丟棄 %d、空間不足刪除 %d 位",
        records, Share.maxRecords(), authors, Share.queued(), Share.waiting(), st.sent, st.received, st.relayed,
        st.throttled, st.dropped, st.evicted)
    -- GF-001-D19: a profession window with a filter keeps the saved recipes;
    -- this used to be a chat message at every login.
    local skipped = ns.Recipes and ns.Recipes.skippedFiltered() or {}
    if #skipped > 0 then
        text = text .. "｜專業視窗有篩選，配方沒有更新：" .. table.concat(skipped, "、")
    end
    return text
end

function Diag.rosterText()
    local s = ns.Roster.current()
    if not s then return ns.UI.unavailableText() or "尚無名冊報告" end
    return string.format("公會：%s｜伺服器：%s｜掃描時間：%s（本機）｜%d 位角色／%d 位掃描時在線",
        str(s.guild), str(s.realm), ns.Export.timestampText(s), s.total or #s.members, s.online or 0)
end

function Diag.versionText()
    local server = ns.num((ns.call(GetServerTime)))
    local skew = server and (server - ns.now()) or nil
    -- GF-001-D23: the realm the outbox gets, and where it came from.
    local realm = ns.realm()
    local from = ({ GetRealmName = "遊戲", saved = "存檔記住的", GetNormalizedRealmName = "遊戲（無空格）" })[ns.realmSource]
    local full = ns.Data.fullName(ns.str((ns.call(UnitGUID, "player"))))
    return string.format("工具箱 %s｜介面 %s｜伺服器 %s｜角色全名 %s｜伺服器時間和本機差 %s",
        ns.VERSION, tostring(ns.Data.interface()),
        realm ~= "" and string.format("「%s」（%s）", realm, from or "?") or "不明（暫停寫入上傳資料）",
        full and string.format("「%s」", full) or "未取得（名冊載入後補上）",
        skew and (skew .. " 秒") or "不明")
end

-- GF-006-B (R-7.5, R-7.6, R-8.4, R-8.6, spec §12 item 12): orders and prices.
-- Review 2-2 / R-7.5: 可用 only once this client produced the evidence; before that 未確認.
local STATUS = { ok = "可用", unconfirmed = "未確認", manual = "改成手動" }
local function statusOf(kind) return STATUS[ns.Delivery.status(kind)] end

function Diag.ordersText()
    local O, D = ns.Orders, ns.Delivery
    local led = O.ledger
    local views, open, closed = O.all(), 0, 0
    for _, v in pairs(views) do
        if v.state == "deal" or v.state == "cancel" then closed = closed + 1 else open = open + 1 end
    end
    local f = D.features()
    local st = led.stats
    local days = O.staleDays()
    local parts = {
        string.format("訂單 %d 張進行中、%d 張已結案｜記錄 %d 筆｜這次登入：送出 %d、收到 %d、佇列 %d",
            open, closed, led:count(), st.sent, st.received, led:queued()),
        string.format("交易判斷 %s｜寄信判斷 %s｜收信判斷 %s", statusOf("trade"), statusOf("mailSend"), statusOf("mailTake")),
        string.format("提醒天數：等接單 %d、製作中 %d、待驗收 %d（/gftk orders days <等接單> <製作中> <待驗收>）",
            days.waiting, days.making, days.checking),
    }
    local shift = ns.num(O.local_().debugShift) or 0
    if shift ~= 0 then parts[#parts + 1] = string.format("測試：訂單時間往前 %d 天", shift / 86400) end
    -- GF-UI-B: the order test mode (local only, never sent or uploaded).
    if O.testOn and O.testOn() then parts[#parts + 1] = string.format("測試模式：開，測試單 %d 張（只在這台電腦，不送出、不上傳）", O.testCount()) end
    if #(ns.missingEvents or {}) > 0 then
        parts[#parts + 1] = "客戶端沒有的事件：" .. table.concat(ns.missingEvents, "、")
    end
    local log = O.local_().trades
    local items = {}
    for i = 1, math.min(5, #log) do
        local e = log[i]
        items[#items + 1] = string.format("%s %s %s", ns.localTime(e.at), str(e.kind), str(e.code))
    end
    if #items > 0 then parts[#parts + 1] = "最近的判斷：" .. table.concat(items, "；") end
    -- GF-006-C: web orders (Inbox and import codes).
    if ns.WebOrders then parts[#parts + 1] = "網站訂單：" .. ns.WebOrders.diagText() end
    return table.concat(parts, "｜")
end

-- GF-002-B: adventure tickets.
function Diag.adventureText()
    local Adv = ns.Adventure
    local led = Adv.ledger
    local open, closed = 0, 0
    for _, v in pairs(Adv.all()) do if v.closed then closed = closed + 1 else open = open + 1 end end
    local workers = 0
    for _ in pairs(Adv.workers()) do workers = workers + 1 end
    local st = led.stats
    local invite = (type(C_PartyInfo) == "table" and type(C_PartyInfo.InviteUnit) == "function") and "C_PartyInfo.InviteUnit"
        or (type(InviteUnit) == "function" and "InviteUnit") or "沒有（一位一位邀請）"
    local log = Adv.questLog() and "可讀" or "讀不到（任務單只能手動）"
    return string.format("冒險單 %d 張進行中、%d 張已結束｜職工單 %d 張｜記錄 %d 筆｜這次登入：送出 %d、收到 %d、佇列 %d｜組隊邀請：%s｜任務日誌：%s",
        open, closed, workers, led:count(), st.sent, st.received, led:queued(), invite, log)
end

function Diag.pricesText()
    local P = ns.Prices
    local db = P.db()
    local items, keys = 0, {}
    for rk, list in pairs(db.ah) do
        local n = 0
        for _ in pairs(list) do n = n + 1 end
        items = items + n
        keys[#keys + 1] = string.format("%s %d", rk, n)
    end
    local vendor = 0
    for _ in pairs(db.vendor) do vendor = vendor + 1 end
    local last = db.scan.last
    local led = P.ledger
    local st = led.stats
    local scan = last and string.format("上次掃描 %s，%s，%d 個物品，%s 秒", ns.localTime(last.at),
        last.how == "replicate" and "整個拍賣場" or "分類瀏覽", last.items or 0, tostring(last.seconds or "?")) or "還沒有掃描"
    local ahKinds = P.canReplicate() and "整個拍賣場" or (P.canBrowse() and "分類瀏覽" or "不能掃描")
    return table.concat({
        string.format("拍賣場價格 %d 個物品（%s）｜商人價格 %d 個｜%s｜這台客戶端：%s",
            items, #keys > 0 and table.concat(keys, "、") or "無", vendor, scan, ahKinds),
        string.format("價格分享：記錄 %d 筆｜這次登入送出 %d／上限 %d、收到 %d、排隊 %d、超過上限 %d",
            led:count(), st.sent, led.cfg.maxPerSession, st.received, led:queued(), st.capped),
    }, "｜")
end

Diag.SITE_NOTE = "GF Sync 會在你下線後讀取存檔並上傳。公會網站的名冊主要由 Blizzard API 自動更新，GF Sync 只是補充來源：沒有安裝或關閉同步，網站照樣會更新。"

local SECTIONS = {
    { title = "上傳到公會網站", text = function() return ns.Sync.statusText() end },
    { title = "說明", text = function() return Diag.SITE_NOTE end },
    { title = "遊戲內分享（公會成員之間自動轉傳）", text = Diag.shareText },
    { title = "訂單（製作與訂單）", text = Diag.ordersText },
    { title = "價格（拍賣場、商人、公會分享）", text = Diag.pricesText },
    { title = "冒險（冒險單與職工單）", text = function() return Diag.adventureText() .. (ns.NativeLFG and ("｜尋求組隊：" .. ns.NativeLFG.diagText()) or "")
        -- GF-002-H: the completion log this computer keeps (R-16.19).
        .. ((ns.Adventure and ns.db and type(ns.db.adventure) == "table") and ("｜成行紀錄：" .. #ns.Adventure.myLog()) or "") end },
    { title = "公會名冊", text = Diag.rosterText },
    { title = "公會管理（GF-001-Q）", text = function() return ns.GuildAdmin and ns.GuildAdmin.diagText() or "" end },
    { title = "職責定位（GF-010）", text = function() return ns.Profile and ns.Profile.diagText() or "" end },
    { title = "名冊天賦（GF-011）", text = function() return ns.Talents and ns.Talents.diagText() or "" end },
    { title = "版本", text = Diag.versionText },
    { title = "功能探測（GF-PROBE）", text = function() return ns.Probe and ns.Probe.diagText() or "" end },
    -- GF-013: the background event record (this computer only; not uploaded yet).
    { title = "背景事件紀錄（本機）", text = function() return ns.Events and ns.Events.diagText() or "" end },
    -- GF-009: 綠皮調貨所 (automatic collection and manual listings).
    { title = "物資供需（GF-009）", text = function() return ns.Supply and ns.Supply.diagText() or "" end },
    -- GF-014: 業務通知 and the local radar (this computer only; nothing is sent).
    { title = "業務通知與需求雷達（GF-014）", text = function()
        return (ns.Notify and ns.Notify.diagText() or "") .. (ns.SupplyRadar and ("｜" .. ns.SupplyRadar.diagText()) or "") end },
    -- GF-012: 公會黑庫 phase 1 (who is guild master, the custodian list; no stock yet).
    { title = "臨時黑箱（GF-012）", text = function() return ns.Bank and ns.Bank.diagText() or "" end },
    -- GF-009-12: the 找物品 item catalog (SupplyCatalogData.lua; GF-009-13: requests, list time).
    { title = "物品目錄（GF-009-12）", text = function() return ns.SupplyCatalog and ns.SupplyCatalog.diagText() or "" end },
}

-- GF-UI-B (GF-UI-A §2.11): 16 px text (18 px state line, gold section
-- names); the sections sit in a scroll frame, each one right under the one
-- before it (its measured height + 12), so a long one never covers the next.
Diag.WIDTH, Diag.HEIGHT, Diag.BODY_W, Diag.GAP = 640, 700, 570, 12
local heads = {}

-- Place the sections one under the other; returns the content height.
function Diag.layout()
    if not window then return 0 end
    local y = 0
    for i = 1, #SECTIONS do
        local head, body = heads[i], lines[i]
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
        y = y + 22
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", window.content, "TOPLEFT", 8, -y)
        body.gfY = y
        local h = ns.textHeight(body, Diag.BODY_W)
        body.gfH = h
        body:SetHeight(h)
        y = y + h + Diag.GAP
        head.gfY = body.gfY - 22
    end
    window.content:SetHeight(math.max(1, y))
    return y
end

function Diag.refresh()
    if not window then return end
    for i, sec in ipairs(SECTIONS) do
        local ok, value = pcall(sec.text)
        lines[i]:SetText(ok and str(value) or "讀取失敗")
    end
    window.state:SetText(ns.Sync.shortStatus())
    if Diag.testCheck then Diag.testCheck.set(ns.Orders and ns.Orders.testOn() or false) end
    Diag.layout()
end

-- GF-UI-B: 30 px text buttons, 2-4 character names (GF-UI-A §2.11 item 3).
local function button(parent, text, x, fn)
    local b = ns.OrdersUI.textButton(parent, text, fn)
    b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 16)
    return b, x + b.gfWidth + 10
end

local function create()
    if window then return window end
    -- GF-001-D20: opaque and above the toolkit window (was see-through).
    local f = ns.popupWindow(Diag.WINDOW_NAME, Diag.WIDTH, Diag.HEIGHT)
    f:SetPoint("CENTER", 0, 20)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.TitleText then f.TitleText:SetText("綠皮冒險工具箱｜同步與診斷") end
    f.state = f:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT)
    f.state:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
    local scroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -66)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -40, 60)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(Diag.BODY_W + 10, 1)
    scroll:SetScrollChild(content)
    f.scroll, f.content = scroll, content
    for i, sec in ipairs(SECTIONS) do
        local head = content:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
        head:SetJustifyH("LEFT")
        head:SetText(sec.title)
        heads[i] = head
        local body = content:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
        body:SetWidth(Diag.BODY_W)
        body:SetJustifyH("LEFT")
        if body.SetJustifyV then body:SetJustifyV("TOP") end
        if body.SetWordWrap then body:SetWordWrap(true) end
        lines[i] = body
    end
    -- GF-UI-C (item 12): text only.
    -- 匯出 [TSV] [JSON]  [更新]  [小地圖]  [清除紀錄]  [ ] 測試
    f.exportLabel = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    f.exportLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 22)
    f.exportLabel:SetText("匯出")
    local x = 20 + ns.labelWidth(f.exportLabel:GetText()) + 6
    Diag.exportTSVButton, x = button(f, "TSV", x, function() ns.UI.startExport("tsv") end)
    Diag.exportJSONButton, x = button(f, "JSON", x, function() ns.UI.startExport("json") end)
    Diag.refreshButton, x = button(f, "更新", x + 6, Diag.refresh)
    Diag.minimapButton, x = button(f, "小地圖", x, function(self)
        ns.Framework.resetMinimap()
        self:SetText("已重置")
        ns.after(3, function() self:SetText("小地圖") end)
    end)
    -- GF-UI-C (owner): delete my closed orders, after the game's confirm box.
    Diag.clearButton, x = button(f, "清除紀錄", x, function() Diag.askClearOrders() end)
    Diag.minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("重置")
        GameTooltip:Show()
    end)
    Diag.minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- GF-UI-B: the order test mode (Orders.setTestMode). Off deletes the test orders.
    Diag.testCheck = ns.checkBox(f, "測試", x + 6, -(Diag.HEIGHT - 16 - 29), function(on)
        if ns.Orders then ns.Orders.setTestMode(on) end
        Diag.refresh()
        if ns.OrdersUI and ns.OrdersUI.refresh then ns.OrdersUI.refresh() end
        if ns.Recipes and ns.Framework.isModuleShown("recipes") then ns.Recipes.refresh() end
    end)
    f:SetScript("OnShow", Diag.refresh)
    f:Hide()
    window = f
    return f
end

-- 清除紀錄: the game's confirm box with how many; nothing to delete = nothing asked.
function Diag.askClearOrders()
    local O = ns.Orders
    if not O then return nil end
    local n = O.closedCounts()
    if n.total == 0 then
        if Diag.clearButton then
            Diag.clearButton:SetText("沒有紀錄")
            ns.after(3, function() Diag.clearButton:SetText("清除紀錄") end)
        end
        return nil
    end
    return ns.GuildAdmin.confirm(string.format("清除已結案的訂單紀錄？\n我下的 %d、我接的 %d、測試 %d、歷史 %d",
        n.w, n.j, n.test, n.history), function()
        O.clearClosed()
        Diag.refresh()
        if ns.OrdersUI and ns.OrdersUI.refresh then ns.OrdersUI.refresh() end
    end)
end

function Diag.open()
    create():Show()
    Diag.refresh()
    return window
end

function Diag.toggle()
    if window and window:IsShown() then window:Hide(); return false end
    Diag.open()
    return true
end

function Diag.isShown() return window ~= nil and window:IsShown() end
function Diag.lines() return lines end
function Diag.heads() return heads end
function Diag.window() return window end

-- The 「診斷」 button at the bottom right of a page (GF-UI-B, GF-UI-A §2.11
-- item 4: a gear and 2 characters, 30 px; was the 120 x 22 「同步與診斷」).
-- Its name takes the sync status colour (UI.refreshSyncIndicator).
local smallButtons = {}
Diag.BUTTON_TEXT = "診斷"
function Diag.smallButton(parent, point, x, y)
    -- GF-UI-C (owner): text only.
    local b = ns.OrdersUI.textButton(parent, Diag.BUTTON_TEXT, Diag.toggle)
    b:SetPoint(point, parent, point, x, y)
    b.label = b.GetFontString and b:GetFontString() or nil
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("同步與診斷")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    smallButtons[#smallButtons + 1] = b
    if ns.Sync and ns.Sync.statusColor and b.label and b.label.SetTextColor then
        local c = ns.Sync.statusColor()
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    return b
end
function Diag.smallButtons() return smallButtons end

local function onChange()
    -- GF-UI-B: every page's 診斷 button follows the sync status colour.
    local c = ns.Sync.statusColor and ns.Sync.statusColor()
    for _, b in ipairs(smallButtons) do
        if c and b.label and b.label.SetTextColor then b.label:SetTextColor(c[1], c[2], c[3]) end
    end
    if Diag.isShown() then ns.coalesce("diag", 1, function() if Diag.isShown() then Diag.refresh() end end) end
end
ns.Sync.onChange(onChange)
ns.Share.onUpdate(onChange)
