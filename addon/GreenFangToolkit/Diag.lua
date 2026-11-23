-- Diag (GF-001-D10 phase 3, D-014 point 6): the 「同步與診斷」 window.
-- Everything technical lives here so the toolkit's pages only show what
-- players use: site sync status and what waits for GF Sync, in-game sharing
-- statistics, the roster scan, versions and clock, and the roster export.
-- Opened by the small 「同步與診斷」 button on the roster page and by /gftk sync.
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
    { title = "冒險（冒險單與職工單）", text = function() return Diag.adventureText() end },
    { title = "公會名冊", text = Diag.rosterText },
    { title = "公會管理（GF-001-Q）", text = function() return ns.GuildAdmin and ns.GuildAdmin.diagText() or "" end },
    { title = "版本", text = Diag.versionText },
}

function Diag.refresh()
    if not window then return end
    for i, sec in ipairs(SECTIONS) do
        local ok, value = pcall(sec.text)
        lines[i]:SetText(ok and str(value) or "讀取失敗")
    end
    window.state:SetText(ns.Sync.shortStatus())
end

local function button(parent, text, w, x, y, fn)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function create()
    if window then return window end
    -- GF-001-D20: opaque and above the toolkit window (was see-through).
    local f = ns.popupWindow(Diag.WINDOW_NAME, 640, 700)
    f:SetPoint("CENTER", 0, 20)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.TitleText then f.TitleText:SetText("綠皮冒險工具箱｜同步與診斷") end
    f.state = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.state:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
    local y = -70
    for i, sec in ipairs(SECTIONS) do
        local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        head:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
        head:SetText(sec.title)
        local body = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", 28, y - 20)
        body:SetWidth(590)
        body:SetJustifyH("LEFT")
        lines[i] = body
        y = y - (i == 3 and 80 or 66)
    end
    Diag.exportTSVButton = button(f, "匯出名冊 TSV", 130, 20, 16, function() ns.UI.startExport("tsv") end)
    Diag.exportJSONButton = button(f, "匯出名冊 JSON", 130, 158, 16, function() ns.UI.startExport("json") end)
    Diag.refreshButton = button(f, "重新整理", 100, 296, 16, Diag.refresh)
    Diag.minimapButton = button(f, "小地圖按鈕回到預設位置", 200, 404, 16, function()
        ns.Framework.resetMinimap()
        ns.say("小地圖按鈕已回到外圈左下方；也可以按住拖曳，沿外圈調整位置。")
    end)
    f:SetScript("OnShow", Diag.refresh)
    f:Hide()
    window = f
    return f
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

-- The small 「同步與診斷」 button on the roster page.
local smallButtons = {}
function Diag.smallButton(parent, point, x, y)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    b:SetPoint(point, parent, point, x, y)
    b:SetText("同步與診斷")
    b:SetScript("OnClick", Diag.toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("同步與診斷")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    smallButtons[#smallButtons + 1] = b
    return b
end

local function onChange()
    if Diag.isShown() then ns.coalesce("diag", 1, function() if Diag.isShown() then Diag.refresh() end end) end
end
ns.Sync.onChange(onChange)
ns.Share.onUpdate(onChange)
