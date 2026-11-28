-- BankUI (GF-012 phase 1, spec v2.0 §8, design GF-012-A §6): 物資調度 →
-- 臨時黑箱. GF-012-C (owner 2026-11-28): two buttons at the top.
--   庫存 (the default): the whole page is the guild's stock (BankStock): one
--     row per item (icon, name, total, who has it, how long ago, 聯絡), as
--     many reused rows as the page holds, the wheel, and a filter row (name,
--     item class, custodian, online only; the result is kept until the data
--     or a filter changes). 聯絡 whispers at once when one custodian has it,
--     else a small menu of the custodians (online first, the most first).
--   保管人與分享設定: who is guild master, the custodian list (8 reused rows
--     again) and its state, the guild master's buttons (指定 / 背包 / 銀行 /
--     撤銷; everybody else sees them disabled, never lit), a custodian's own
--     公產 scope, the share switch and what I share.
-- GF-012-D: the buttons come from UI.VIEWS (UI.addView adds a page from
-- another file). 申領 (BankRequests): 要我處理的 / 我的申領 with reused rows
-- and only the buttons I may press; the stock row has 申領 next to 聯絡 and
-- 可申領 N; the small 申領 form; 審核幹部 under the custodian list.
-- Game art only (class icons, item icons, the state panel's icons), 16 px
-- text, button names of 2-4 characters.

local _, ns = ...
local str = ns.str

local UI = {}
ns.BankUI = UI

UI.ID = "bank"
UI.ROWS, UI.ROW_H, UI.ROW_W = 8, 40, 660 -- GF-012-C: 8 rows again (the stock has its own view)
UI.X, UI.RIGHT_X = 20, 720
-- GF-UI-I (owner 0.16.2: 標題和右邊的字壓到上面的分頁列): the sub-tab row's
-- line ends 29 px into the page, so everything starts UI.TOP below it.
UI.TOP = 40
-- GF-012-D: the buttons at the top come from this list (order, then key);
-- other files add pages with UI.addView. The three built-in ones are built
-- with the page; an added one when it is first shown.
UI.VIEWS = { { key = "stock", text = "庫存", order = 10 }, { key = "requests", text = "申領", order = 20 },
    { key = "setup", text = "保管人與分享設定", order = 30 } }
UI.Y = { views = -UI.TOP, status = -UI.TOP - 44, listHead = -UI.TOP - 76, rows = -UI.TOP - 108, scopeHead = -UI.TOP - 76,
    filters = -UI.TOP - 44, stockHead = -UI.TOP - 86, stockRows = -UI.TOP - 118 }
-- GF-012-C: the stock list fills the page: as many 44 px rows as fit above
-- the 「還有 N 項」 line at the bottom.
-- GF-UI-P: the rows leave a column on the right for the scroll bar (Widgets.scrollBar).
UI.BAR_ROOM = ns.Widgets.SCROLL_W + ns.Widgets.SCROLL_GAP
UI.STOCK_ROW_H, UI.STOCK_W = 44, 1060 - UI.BAR_ROOM
UI.STOCK_MORE_H = 26
UI.STOCK_ROWS = math.floor(((ns.Framework.PANEL_HEIGHT or 680) + UI.Y.stockRows - UI.STOCK_MORE_H - 8) / UI.STOCK_ROW_H)
UI.STOCK_MORE = "還有 %d 項，用滑鼠滾輪往下看"
UI.STOCK_COUNT = "共 %d 項"
-- Columns right of the item name (x from the row's right edge).
UI.STOCK_COL = { who = 560, ago = 310, contact = 80, ask = 84 } -- GF-012-D: 申領 left of 聯絡
UI.STOCK_HEADINGS = { "物品", "總數", "誰有", "多久前看到" }
UI.STOCK_EMPTY = {
    nobody = { "還沒有保管人", "會長指定保管人後，這裡會列出保管人分享的物品" },
    none = { "保管人還沒分享庫存", "保管人上線並開啟分享後就會出現" },
    noscope = { "保管人還沒設定公產範圍", "保管人在「保管人與分享設定」的「我的公產範圍」勾選後就會出現" },
    unseen = { "保管人還沒打開銀行", "保管人打開銀行後才看得到銀行裡的物品" },
    empty = { "公產範圍裡沒有可交易的物品", "綁定的物品不列入" },
    list = { "還沒有保管人名單", "等會長的名單傳到" },
    search = { "找不到符合的物品", "換個名字試試" },
    filter = { "沒有符合篩選的物品", "換個分類、保管人，或取消「只看在線的保管人」" },
}
UI.SEARCH_DELAY = 0.15 -- owner: typing redraws at most this late
UI.CLASS_ALL, UI.HOLDER_ALL = "全部分類", "全部保管人"
UI.ONLINE_LABEL = "只看在線的保管人"
UI.SHARE_LABEL = "分享庫存給公會"
-- GF-UI-M (owner): the list scrolls with the wheel (8 pooled rows; up to 10
-- active + 10 revoked); the same 「還有 N 位」 line as 調貨看板's detail.
UI.MORE_TEXT = "還有 %d 位，用滑鼠滾輪往下看"
UI.RESULT = {
    ["no-authority"] = "只有會長可以管理", ["not-found"] = "找不到這位職工", full = "保管人已達上限",
    same = "沒有變更", invalid = "格式不對", ["last-kind"] = "至少留一種，否則請撤銷", ok = "已更新",
    -- (GF-012-D: 審核幹部 uses the same words; 已達上限 is 10 like custodians)
    combat = "戰鬥中，結束後再選", roster = "公會名冊尚未載入",
}
-- GF-012-C: 聯絡's menu (one for the whole toolkit, also 調貨看板's 黑箱 row).
UI.CONTACT_W = 260
UI.CONTACT_BEST = "（建議）"
UI.CONTACT_SELF = "（自己）"
UI.AVAIL_TEXT = "可申領 " -- GF-012-D

local panel
local c = {}

local function B() return ns.Bank end
local function W() return ns.Widgets end
local function K() return ns.BankStock end
local function R() return ns.BankRequests end -- GF-012-D

local function text(parent, font, x, y, w)
    local fs = ns.freeText(parent:CreateFontString(nil, "ARTWORK", font or ns.LABEL_FONT))
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if w then fs:SetWidth(w); fs:SetJustifyH("LEFT") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

local function header(p, s, x, y)
    local h = p:CreateFontString(nil, "ARTWORK", ns.Theme.FONT.header)
    h:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    h:SetText(s)
    return h
end

local function setEnabled(b, on) W().setEnabled(b, on) end
local function shown(f, on) if on then f:Show() else f:Hide() end end

-- GF-UI-P: a list's scroll bar right of its rows (rowsRight: the rows' right edge).
function UI.bar(p, rowsRight, y, h, onScroll)
    local b = W().scrollBar(p, h, onScroll)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", rowsRight + ns.Widgets.SCROLL_GAP, y)
    return b
end

local function row(p, i)
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(UI.ROW_W, UI.ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", UI.X, UI.Y.rows - (i - 1) * UI.ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    ns.stripe(r.bg, i)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    local function col(x, w)
        local fs = ns.freeText(r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        fs:SetPoint("LEFT", r, "LEFT", x, 0); fs:SetWidth(w); fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    r.name = col(38, 190)
    r.kinds = col(232, 100)
    r.state = col(336, 70)
    local O = ns.OrdersUI
    r.bags = O.textButton(r, "背包", function() UI.toggleKind(r, "bags") end, 64)
    r.bags:SetPoint("LEFT", r, "LEFT", 412, 0)
    r.bank = O.textButton(r, "銀行", function() UI.toggleKind(r, "bank") end, 64)
    r.bank:SetPoint("LEFT", r, "LEFT", 484, 0)
    r.revoke = O.textButton(r, "撤銷", function()
        if r.entry and B().canManage() then UI.say(B().revoke(r.entry.a)) end
    end, 64)
    r.revoke:SetPoint("LEFT", r, "LEFT", 576, 0)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    r:SetScript("OnMouseWheel", function(_, delta) UI.scroll(delta) end)
    return r
end

function UI.toggleKind(r, kind)
    local e = r.entry
    if not e or not B().canManage() then return end
    local has = e.kinds:find(B().KIND_LETTER[kind], 1, true) ~= nil
    UI.say(B().setKind(e.a, kind, not has))
end

function UI.say(result)
    if c.result then c.result:SetText(UI.RESULT[result] or tostring(result or "")) end
    UI.refresh()
    return result
end

-- 保管人與分享設定 (GF-012-C: its own view; was the top half of the page).
local function buildSetup(p)
    local X, Y = UI.X, UI.Y
    c.status = text(p, ns.LABEL_FONT, X, Y.status, 1040)
    c.listHead = header(p, "保管人名單", X, Y.listHead)
    c.more = text(p, ns.DISABLED_FONT, X + 140, Y.listHead, 520)
    c.offset = 0
    c.rows = {}
    for i = 1, UI.ROWS do c.rows[i] = row(p, i) end
    c.bar = UI.bar(p, UI.X + UI.ROW_W, Y.rows, UI.ROWS * UI.ROW_H, function(o) c.offset = o; UI.refresh() end)
    c.listState = W().statePanel(p, UI.ROW_W, 120)
    c.listState:SetPoint("TOPLEFT", p, "TOPLEFT", X, Y.rows - 20)
    local addY = Y.rows - UI.ROWS * UI.ROW_H - 10
    c.nameLabel = text(p, ns.FIELD_FONT, X, addY - 6)
    c.nameLabel:SetText("職工") -- GF-UI-K: 成員 = 職工 (spec §3)
    -- GF-012-FIX (owner 2026-11-27: 成員一定是公會內的人，可以用選的): the box
    -- only searches the guild roster; ＋保管人 (was 選擇職工) appoints a typed name only when
    -- it is exactly one roster member, otherwise it opens the picker.
    c.name = ns.Theme.editBox(p, 200, 30)
    c.name:SetPoint("TOPLEFT", p, "TOPLEFT", X + 50, addY)
    -- GF-UI-P (owner 2026-11-28): buttons that add one to a list start with 「＋」 (as ＋冒險單).
    c.appoint = ns.OrdersUI.textButton(p, "＋保管人", function()
        if B().canManage() then UI.choose(str(c.name:GetText())) end
    end, 100)
    c.appoint:SetPoint("TOPLEFT", p, "TOPLEFT", X + 260, addY)
    c.name:SetScript("OnEnterPressed", function() if not c.appoint.disabled then c.appoint:Click() end end)
    c.result = text(p, ns.LABEL_FONT, X + 372, addY - 6, 290)
    -- GF-012-D: 審核幹部 (chosen from the roster like a custodian; only the
    -- guild master; 3 reused rows and the wheel).
    local oy = addY - 44
    c.officerHead = header(p, "審核幹部", X, oy)
    c.officerMore = text(p, ns.DISABLED_FONT, X + 110, oy, 330)
    c.officerAdd = ns.OrdersUI.textButton(p, "＋審核幹部", function()
        if B().canManage() then UI.openPicker("", "officer") end
    end, 130)
    c.officerAdd:SetPoint("TOPLEFT", p, "TOPLEFT", X + UI.ROW_W - 130, oy + 4)
    c.officerOffset = 0
    c.officerRows = {}
    for i = 1, UI.OFFICER_ROWS do c.officerRows[i] = UI.officerRow(p, oy - 30 - (i - 1) * UI.OFFICER_ROW_H, i) end
    c.officerBar = UI.bar(p, X + UI.ROW_W, oy - 30, UI.OFFICER_ROWS * UI.OFFICER_ROW_H, function(o)
        c.officerOffset = o
        UI.drawOfficers(B().canManage())
    end)
    c.officerEmpty = text(p, ns.DISABLED_FONT, X + 6, oy - 38, 600)
    -- 我的公產範圍
    c.scopeHead = header(p, "我的公產範圍", UI.RIGHT_X, Y.scopeHead)
    c.scopeState = W().statePanel(p, 360, 120)
    c.scopeState:SetPoint("TOPLEFT", p, "TOPLEFT", UI.RIGHT_X, Y.rows - 20)
    c.scope = { bags = {}, bank = {} }
    c.scopeLabel = {}
    local y = Y.rows
    for _, kind in ipairs({ "bags", "bank" }) do
        c.scopeLabel[kind] = text(p, ns.FIELD_FONT, UI.RIGHT_X, y - 4)
        c.scopeLabel[kind]:SetText(B().KIND_NAME[kind])
        for i, it in ipairs(B().SCOPE[kind]) do
            local cx = UI.RIGHT_X + 56 + ((i - 1) % 3) * 110
            local cy = y - math.floor((i - 1) / 3) * 34
            local index = it[1]
            local box = ns.checkBox(p, it[2], cx, cy, function(on)
                UI.say(B().setScope(kind, index, on))
                if on and K() then K().askIfNeeded() end -- GF-012-B: the first tick asks once
            end)
            box.kind, box.index = kind, index
            c.scope[kind][#c.scope[kind] + 1] = box
        end
        y = y - math.ceil(#B().SCOPE[kind] / 3) * 34 - 14
    end
    c.scopeNote = text(p, ns.DISABLED_FONT, UI.RIGHT_X, y - 4, 360)
    c.scopeNote:SetText(K().SCOPE_NOTE) -- GF-012-B (was 只存在本機，不掃描)
    -- GF-012-B: the share switch (on asks first) and what I share.
    c.share = ns.checkBox(p, UI.SHARE_LABEL, UI.RIGHT_X, y - 34, function(on)
        K().toggle(on)
        UI.refresh()
    end)
    c.mine = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    c.mine:SetPoint("TOPLEFT", p, "TOPLEFT", UI.RIGHT_X, y - 72)
    c.mine:SetWidth(360); c.mine:SetJustifyH("LEFT")
    if c.mine.SetWordWrap then c.mine:SetWordWrap(true) end
end

-- 庫存 (GF-012-C: the whole view): the filter row, the column header, the rows.
local function buildStock(p)
    local X, Y = UI.X, UI.Y
    c.searchLabel = text(p, ns.FIELD_FONT, X, Y.filters - 6)
    c.searchLabel:SetText("搜尋")
    c.search = ns.Theme.editBox(p, 180, 30)
    c.search:SetPoint("TOPLEFT", p, "TOPLEFT", X + 44, Y.filters)
    if c.search.SetMaxLetters then c.search:SetMaxLetters(40) end
    c.search:SetScript("OnTextChanged", function(self)
        c.query = str(self:GetText())
        ns.Recipes.soon("bank-stock-search", UI.SEARCH_DELAY, function()
            if panel and panel:IsShown() then c.stockOffset = 0; UI.drawStock() end
        end)
    end)
    c.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    c.classLabel = text(p, ns.FIELD_FONT, X + 244, Y.filters - 6)
    c.classLabel:SetText("分類")
    c.classDrop = W().dropdown(p, 160, function(v) UI.setFilter("class", v) end)
    c.classDrop:SetPoint("TOPLEFT", p, "TOPLEFT", X + 288, Y.filters)
    c.holderLabel = text(p, ns.FIELD_FONT, X + 468, Y.filters - 6)
    c.holderLabel:SetText("保管人")
    c.holderDrop = W().dropdown(p, 180, function(v) UI.setFilter("holder", v) end)
    c.holderDrop:SetPoint("TOPLEFT", p, "TOPLEFT", X + 528, Y.filters)
    c.online = ns.checkBox(p, UI.ONLINE_LABEL, X + 730, Y.filters, function(on) UI.setFilter("online", on) end)
    c.filters = { class = "all", holder = "all", online = false }
    c.classDrop.setItems({ { value = "all", text = UI.CLASS_ALL } }); c.classDrop.setValue("all")
    c.holderDrop.setItems({ { value = "all", text = UI.HOLDER_ALL } }); c.holderDrop.setValue("all")
    -- The column header (the same faint bar as 調貨所's lists).
    c.stockHead = CreateFrame("Frame", nil, p)
    c.stockHead:SetPoint("TOPLEFT", p, "TOPLEFT", X, Y.stockHead)
    c.stockHead:SetSize(UI.STOCK_W, 28)
    ns.Theme.headerBar(c.stockHead)
    c.stockHead.cells = {}
    local cols = { { x = 52, w = 300 }, { right = UI.STOCK_COL.who + 20, w = 80 },
        { right = UI.STOCK_COL.who, w = 240 }, { right = UI.STOCK_COL.ago, w = 130 } }
    for i, col in ipairs(cols) do
        local fs = ns.freeText(c.stockHead:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        if col.x then fs:SetPoint("LEFT", c.stockHead, "LEFT", col.x, 0); fs:SetJustifyH("LEFT")
        elseif i == 2 then fs:SetPoint("RIGHT", c.stockHead, "RIGHT", -col.right, 0); fs:SetJustifyH("RIGHT")
        else fs:SetPoint("LEFT", c.stockHead, "RIGHT", -col.right, 0); fs:SetJustifyH("LEFT") end
        fs:SetWidth(col.w)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:SetText(UI.STOCK_HEADINGS[i])
        c.stockHead.cells[i] = fs
    end
    c.query, c.stockOffset = "", 0
    c.stockRows = {}
    for i = 1, UI.STOCK_ROWS do c.stockRows[i] = UI.stockRow(p, i) end
    c.stockBar = UI.bar(p, X + UI.STOCK_W, Y.stockRows, UI.STOCK_ROWS * UI.STOCK_ROW_H, function(o)
        c.stockOffset = o
        UI.closeContact()
        UI.drawStock()
    end)
    local bottom = UI.Y.stockRows - UI.STOCK_ROWS * UI.STOCK_ROW_H
    c.stockCount = text(p, ns.LABEL_FONT, X + 4, bottom - 6, 200)
    c.stockMore = text(p, ns.DISABLED_FONT, X + 220, bottom - 6, 500)
    c.stock = W().statePanel(p, UI.STOCK_W, 140)
    c.stock:SetPoint("TOPLEFT", p, "TOPLEFT", X, Y.stockRows - 20)
end

---------------------------------------------------------------------------
-- GF-012-D: the pages of 臨時黑箱 (data-driven buttons at the top).
-- UI.addView({ key, text, build = function(parent), draw = function(), order })
-- adds one: parent is a frame of the page's size (UI.VIEW_W × UI.VIEW_H,
-- its TOPLEFT is the page's TOPLEFT, y grows downwards as negative numbers;
-- the buttons take the top UI.TOP + 4 px: put things from x = UI.X,
-- y = UI.Y.status (−84) down). build is called once, the first time the page
-- is shown; draw each time it is shown and when UI.refresh runs while it is
-- shown (UI.refreshView(key) asks for that from outside).
---------------------------------------------------------------------------

UI.VIEW_W, UI.VIEW_H = ns.Framework.PANEL_WIDTH or 1100, ns.Framework.PANEL_HEIGHT or 680
UI.REQ_TAB = "申領"
UI.REQ_TAB_WIDE = "申領（99）" -- the button is this wide, so a number never moves the others

local function sortViews()
    table.sort(UI.VIEWS, function(x, y)
        if (x.order or 0) ~= (y.order or 0) then return (x.order or 0) < (y.order or 0) end
        return x.key < y.key
    end)
end
function UI.viewDef(key)
    for _, v in ipairs(UI.VIEWS) do if v.key == key then return v end end
    return nil
end

local function makeStrip()
    if c.views then for _, b in ipairs(c.views.buttons) do b:Hide() end end
    local items = {}
    for _, v in ipairs(UI.VIEWS) do
        items[#items + 1] = { key = v.key, text = v.text,
            w = v.key == "requests" and (ns.labelWidth(UI.REQ_TAB_WIDE) + 28) or nil }
    end
    c.views = ns.Theme.tabStrip(panel, items, UI.X, UI.Y.views, function(key) UI.setView(key) end)
    c.viewButton = {}
    for _, b in ipairs(c.views.buttons) do c.viewButton[b.key] = b end
    c.views.select(c.view)
end

function UI.addView(def)
    if type(def) ~= "table" or type(def.key) ~= "string" or def.key == "" or str(def.text) == "" then return false end
    if UI.viewDef(def.key) then return false end
    UI.VIEWS[#UI.VIEWS + 1] = { key = def.key, text = def.text, build = def.build, draw = def.draw,
        order = tonumber(def.order) or (100 + #UI.VIEWS) }
    sortViews()
    if panel then makeStrip(); UI.drawBadge() end
    return true
end

local function build(p)
    panel = p
    local function view()
        local v = CreateFrame("Frame", nil, p)
        v:SetAllPoints(p)
        return v
    end
    c.stockView, c.setupView, c.requestsView = view(), view(), view()
    c.viewFrames = { stock = c.stockView, setup = c.setupView, requests = c.requestsView }
    c.built = { stock = true, setup = true, requests = true }
    c.view = "stock"
    sortViews()
    makeStrip()
    c.role = text(p, ns.FIELD_FONT, UI.RIGHT_X, UI.Y.views - 6, 360)
    buildSetup(c.setupView)
    buildStock(c.stockView)
    UI.buildRequests(c.requestsView)
    c.setupView:Hide()
    c.requestsView:Hide()
    if p.HookScript then p:HookScript("OnHide", function() UI.closeContact() end) end
    UI.controls = c
end

-- Show one page (庫存 / 申領 / 保管人與分享設定 / an added one).
function UI.setView(key)
    local def = UI.viewDef(key)
    if not def then return false end
    c.view = key
    if c.views then c.views.select(key) end
    if c.viewFrames then
        if not c.built[key] then
            local f = CreateFrame("Frame", nil, panel)
            f:SetAllPoints(panel)
            c.viewFrames[key], c.built[key] = f, true
            if type(def.build) == "function" then
                local okBuild, err = pcall(def.build, f)
                if not okBuild then UI.viewError = key .. ": " .. tostring(err) end -- 同步與診斷 can show it
            end
        end
        for k, f in pairs(c.viewFrames) do shown(f, k == key) end
    end
    UI.closeContact()
    UI.refresh()
    if key == "setup" and K() then K().askIfNeeded() end
    return true
end

-- Draw an added page again when it is the one shown (from its own file).
function UI.refreshView(key)
    if panel and panel:IsShown() and c.view == key then UI.refresh(); return true end
    return false
end

-- GF-012-B / C: one stock row (Widgets.itemRow): icon, name, total; on the
-- right who has it, how long ago, 聯絡. The tooltip: each custodian's count
-- in the bags and the bank.
function UI.stockRow(p, i)
    local r = W().itemRow(p, UI.STOCK_W, UI.STOCK_ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", UI.X, UI.Y.stockRows - (i - 1) * UI.STOCK_ROW_H)
    local function col(right, w)
        local fs = ns.freeText(r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        fs:SetPoint("LEFT", r, "RIGHT", -right, 0)
        fs:SetWidth(w); fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    r.who = col(UI.STOCK_COL.who, 240)
    r.ago = col(UI.STOCK_COL.ago, 130)
    r.contact = ns.Theme.button(r, "聯絡", 72, ns.BUTTON_H)
    r.contact:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.contact:SetScript("OnClick", function(self) if self.item then UI.contact(self, self.item) end end)
    -- GF-012-D: 申領 next to 聯絡 (the small form; the custodian picked like 聯絡).
    r.ask = ns.Theme.button(r, "申領", 72, ns.BUTTON_H)
    r.ask:SetPoint("RIGHT", r, "RIGHT", -UI.STOCK_COL.ask, 0)
    r.ask:SetScript("OnClick", function(self) if self.item then UI.openRequest(self.item) end end)
    r.setRightWidth(UI.STOCK_COL.who + 4)
    r:SetScript("OnEnter", function(self)
        W().itemTooltip(self, self.info)
        if self.stockItem and GameTooltip then
            for _, line in ipairs(UI.tipLines(self.stockItem)) do GameTooltip:AddLine(line, 1, 1, 1) end
            GameTooltip:Show()
        end
    end)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    r:SetScript("OnMouseWheel", function(_, delta) UI.scrollStock(delta) end)
    r:Hide()
    return r
end

-- The tooltip lines of a stock row: one per custodian (背包 / 銀行 / when).
function UI.tipLines(item)
    local out = {}
    for _, p in ipairs(item.places) do
        local h = p.h
        local when = {}
        if p.bags > 0 and h.bagsT then when[#when + 1] = "背包 " .. ns.Recipes.agoText(h.bagsT) end
        if p.bank > 0 and h.bankT then when[#when + 1] = "銀行 " .. ns.Recipes.agoText(h.bankT) end
        out[#out + 1] = K().placeText(p) .. (K().isOnline(h) and "（在線）" or "（離線）")
            .. (#when > 0 and ("｜" .. table.concat(when, "、") .. "看到") or "")
    end
    return out
end

-- GF-012-FIX: a custodian no longer in the roster is shown as 已不在公會
-- (the list itself is the guild master's; nothing is removed here).
local function memberText(a)
    local m = ns.Share.memberFor(a)
    return m and ns.shortName(m.name) or "已不在公會", m and m.classToken or nil
end

---------------------------------------------------------------------------
-- GF-012-FIX: the member picker (the same popup as ＋下單's recipe picker:
-- a search box, 10 reused rows, the first key redraws at once and keys within
-- PICKER_DELAY make one more redraw). Rows come from the roster snapshot,
-- online and offline; nothing is read from the game while typing.
---------------------------------------------------------------------------

UI.PICKER_NAME = "GreenFangToolkit_KeeperPicker"
UI.PICKER_ROWS = 10
UI.PICKER_DELAY = 0.15

-- The box's text is resolved by the same rule as Bank.appoint (Bank.memberA):
-- exactly one roster member appoints; anything else opens the picker.
function UI.choose(q)
    q = str(q)
    if q ~= "" and ns.Roster.current() then
        local a = B().memberA(q)
        if a then
            local r = UI.say(B().appoint({ guid = ns.Share.guidOf(a) }))
            if r == "ok" then c.name:SetText("") end
            return r
        end
    end
    UI.openPicker(q)
end

function UI.drawPicker()
    local f = UI.picker
    if not f then return end
    local rows = B().candidates(f.query)
    -- GF-012-D: the same picker names 審核幹部 (f.mode = "officer").
    local officer = f.mode == "officer"
    f.list = rows
    for i = 1, UI.PICKER_ROWS do
        local b, r = f.rows[i], rows[i]
        b.data = r
        if r then
            local col = ns.Icons.classColor(r.classToken)
            if r.classToken and r.classToken ~= "" then ns.Icons.setClassIcon(b.icon, r.classToken); b.icon:Show() else b.icon:Hide() end
            b.name:SetText(r.short)
            b.name:SetTextColor(col[1], col[2], col[3])
            b.rank:SetText(r.rank)
            b.online:SetText(r.online and "在線" or "離線")
            local oc = r.online and { 1, 1, 1 } or ns.COLOR.disabled
            b.online:SetTextColor(oc[1], oc[2], oc[3])
            if officer then b.mark:SetText((B().isOfficer(r.a)) and "已是審核幹部" or "")
            else b.mark:SetText(r.custodian and "已是保管人" or "") end
            b:Show()
        else
            b:Hide()
        end
    end
    f.empty:SetText(#rows == 0 and "找不到這位職工" or "")
    f.count:SetText(#rows > UI.PICKER_ROWS and ("還有 " .. (#rows - UI.PICKER_ROWS) .. " 位，請再輸入名字縮小") or "")
end

function UI.pick(r)
    if not r or not B().canManage() then return end
    local officer = UI.picker and UI.picker.mode == "officer"
    if UI.picker then UI.picker:Hide() end
    if officer then return UI.say(B().appointOfficer({ guid = ns.Share.guidOf(r.a) })) end
    local res = UI.say(B().appoint({ guid = ns.Share.guidOf(r.a) }))
    if res == "ok" and c.name then c.name:SetText("") end
    return res
end

function UI.openPicker(q, mode)
    if ns.inCombat() then UI.say("combat"); return nil end
    if not ns.Roster.current() then UI.say("roster"); return nil end
    if not UI.picker then
        local O = ns.OrdersUI
        local f = ns.popupWindow(UI.PICKER_NAME, 640, 540)
        f:SetPoint("CENTER", 0, 60)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("指定保管人：選職工") end
        O.fieldLabel(f, "搜尋", O.FIELD_X, -46)
        local X = O.controlX({ "搜尋" })
        local box = ns.Theme.editBox(f)
        box:SetSize(300, 30)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", X + 6, -40)
        box:SetAutoFocus(true)
        box:SetMaxLetters(60)
        box:SetScript("OnTextChanged", function(self)
            f.query = str(self:GetText())
            ns.Recipes.soon("bank-picker", UI.PICKER_DELAY, function() if f:IsShown() then UI.drawPicker() end end)
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        box:SetScript("OnEnterPressed", function() if f.list and #f.list == 1 then UI.pick(f.list[1]) end end)
        f.search = box
        O.fieldLabel(f, "職工", O.FIELD_X, -90)
        O.fieldLabel(f, "階級", 290, -90)
        O.fieldLabel(f, "狀態", 420, -90)
        f.rows = {}
        for i = 1, UI.PICKER_ROWS do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(590, ns.PAGE_ROW)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", O.FIELD_X, -114 - (i - 1) * (ns.PAGE_ROW + 2))
            if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(ns.ROW_ICON, ns.ROW_ICON); b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
            local function col(x, w)
                local fs = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
                fs:SetPoint("LEFT", b, "LEFT", x, 0); fs:SetWidth(w); fs:SetJustifyH("LEFT")
                if fs.SetWordWrap then fs:SetWordWrap(false) end
                return fs
            end
            b.name = col(38, 220)
            b.rank = col(272, 120)
            b.online = col(402, 56)
            b.mark = col(462, 120)
            b:SetScript("OnClick", function(self) if self.data then UI.pick(self.data) end end)
            f.rows[i] = b
        end
        f.empty = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", O.FIELD_X, -116)
        f.count = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", O.FIELD_X, 20)
        f:Hide()
        UI.picker = f
    end
    local f = UI.picker
    f.query = str(q)
    f.mode = mode == "officer" and "officer" or "custodian"
    if f.TitleText then f.TitleText:SetText(f.mode == "officer" and "指定審核幹部：選職工" or "指定保管人：選職工") end
    f:Show()
    f.search:SetText(f.query)
    UI.drawPicker()
    return f
end

function UI.refresh()
    if not panel then return end
    local Bk = B()
    local role = Bk.myRole()
    c.role:SetText("身分：" .. (Bk.ROLE_NAME[role] or "?"))
    -- GF-012-C: the setup view is small (8 rows, nothing read from the game):
    -- drawn every time; the stock list only while it is the view shown.
    UI.drawSetup()
    if c.view == "stock" then UI.drawStock()
    elseif c.view == "requests" then UI.drawRequests()
    else
        local def = UI.viewDef(c.view)
        if def and type(def.draw) == "function" then
            local okDraw, err = pcall(def.draw)
            if not okDraw then UI.viewError = c.view .. ": " .. tostring(err) end
        end
    end
    UI.drawBadge()
end

function UI.drawSetup()
    local Bk = B()
    local manage = Bk.canManage()
    local cur = Bk.current()
    -- status line
    local active = 0
    for _, e in ipairs(cur.list and cur.list.entries or {}) do if e.enabled then active = active + 1 end end
    if cur.state == "ok" then
        c.status:SetText(string.format("名單：會長 %s 發布｜%s｜有效 %d 位", ns.shortName(str(cur.leaderName)),
            cur.direct and "直接收到" or "經轉送", active))
    elseif cur.leaderName then
        c.status:SetText("名單：" .. Bk.STATE_NAME[cur.state] .. "｜會長 " .. ns.shortName(cur.leaderName))
    else
        c.status:SetText("名單：" .. (Bk.STATE_NAME[cur.state] or cur.state))
    end
    -- rows: enabled first, then revoked
    local entries = {}
    for _, e in ipairs(cur.list and cur.list.entries or {}) do entries[#entries + 1] = e end
    table.sort(entries, function(x, y)
        if x.enabled ~= y.enabled then return x.enabled end
        return x.epoch > y.epoch
    end)
    c.total = #entries
    c.offset = math.max(0, math.min(c.offset or 0, #entries - UI.ROWS))
    if c.bar then c.bar.sync(c.offset, #entries, UI.ROWS) end
    local rest = #entries - c.offset - UI.ROWS
    c.more:SetText(rest > 0 and string.format(UI.MORE_TEXT, rest) or "")
    for i, r in ipairs(c.rows) do
        local e = entries[c.offset + i]
        r.entry = e
        if e then
            local name, token = memberText(e.a)
            r.name:SetText(name)
            if token then ns.Icons.setClassIcon(r.icon, token); r.icon:Show() else r.icon:Hide() end
            local kinds = {}
            if e.kinds:find("b", 1, true) then kinds[#kinds + 1] = Bk.KIND_NAME.bags end
            if e.kinds:find("k", 1, true) then kinds[#kinds + 1] = Bk.KIND_NAME.bank end
            r.kinds:SetText(table.concat(kinds, " "))
            r.state:SetText(e.enabled and "有效" or "已撤銷")
            local col = e.enabled and { 1, 1, 1 } or ns.COLOR.disabled
            r.name:SetTextColor(col[1], col[2], col[3]); r.state:SetTextColor(col[1], col[2], col[3])
            local canRow = manage and e.enabled
            ns.Theme.setSelected(r.bags, e.enabled and e.kinds:find("b", 1, true) ~= nil)
            ns.Theme.setSelected(r.bank, e.enabled and e.kinds:find("k", 1, true) ~= nil)
            setEnabled(r.bags, canRow); setEnabled(r.bank, canRow); setEnabled(r.revoke, canRow)
            r:Show()
        else
            r:Hide()
        end
    end
    if cur.state ~= "ok" then
        c.listState.set(cur.state == "unknown" and "unknown" or (cur.state == "none" and "empty" or "stale"),
            Bk.STATE_NAME[cur.state], cur.state == "unknown" and "名冊未載入或無法確認會長" or nil)
    elseif #entries == 0 then
        c.listState.set("empty", "尚未指定保管人")
    else
        c.listState.set(nil)
    end
    setEnabled(c.appoint, manage)
    if not manage and UI.picker and UI.picker:IsShown() then UI.picker:Hide() end
    if c.name.SetEnabled then c.name:SetEnabled(manage) end
    -- my scope
    local me = ns.Share.selfAuthor()
    local isCust = me and (Bk.isCustodian(me)) or false
    local s = Bk.scope()
    for _, kind in ipairs({ "bags", "bank" }) do
        local editable = isCust and Bk.scopeEditable(kind)
        shown(c.scopeLabel[kind], isCust)
        for _, box in ipairs(c.scope[kind]) do
            box.set(s ~= nil and s[kind][box.index] == true)
            setEnabled(box, editable)
            shown(box, isCust); shown(box.label, isCust)
        end
    end
    shown(c.scopeNote, isCust)
    if isCust then c.scopeState.set(nil) else c.scopeState.set("empty", "你不是保管人") end
    -- GF-012-B: the share switch and what I share.
    local st = K().myState()
    shown(c.share, isCust); shown(c.share.label, isCust)
    c.share.set(st == "on")
    setEnabled(c.share, isCust and st ~= "noscope")
    c.mine:SetText(isCust and K().mineText() or "")
    UI.drawOfficers(manage)
end

---------------------------------------------------------------------------
-- GF-012-C: the stock view's filters
---------------------------------------------------------------------------

-- What BankStock.filter takes from the filter row now.
function UI.filterOpts()
    local f = c.filters or {}
    return { q = c.query or "", class = f.class ~= "all" and f.class or nil,
        holder = f.holder ~= "all" and f.holder or nil, online = f.online == true }
end

function UI.setFilter(key, value)
    if not c.filters then return end
    c.filters[key] = value
    c.stockOffset = 0
    UI.closeContact()
    UI.drawStock()
end

-- The two drop-downs follow what is in stock (only classes there are; every
-- custodian shown). A choice that is gone goes back to 全部.
local function drawFilters()
    local classes = { { value = "all", text = UI.CLASS_ALL } }
    for _, o in ipairs(K().classOptions()) do classes[#classes + 1] = o end
    local holders = { { value = "all", text = UI.HOLDER_ALL } }
    for _, h in ipairs((K().holders())) do
        holders[#holders + 1] = { value = h.a, text = h.name .. (h.own and UI.CONTACT_SELF or "") }
    end
    for key, list in pairs({ class = classes, holder = holders }) do
        local found = false
        for _, o in ipairs(list) do if o.value == c.filters[key] then found = true end end
        if not found then c.filters[key] = "all" end
    end
    c.classDrop.items = classes; c.classDrop.setValue(c.filters.class)
    c.holderDrop.items = holders; c.holderDrop.setValue(c.filters.holder)
    c.online.set(c.filters.online == true)
end

-- Any filter besides the name box.
local function narrowed()
    local f = c.filters
    return f.class ~= "all" or f.holder ~= "all" or f.online == true
end

-- GF-012-B / C: the stock list (only this part is drawn on a search, a
-- filter or the wheel). Rows are reused; nothing is created here.
function UI.drawStock()
    if not panel then return end
    local cur = B().current()
    local all, why = K().rows()
    drawFilters()
    local opts = UI.filterOpts()
    local rows = K().filter(opts)
    c.stockList = rows
    c.stockTotal = #rows
    c.stockOffset = math.max(0, math.min(c.stockOffset or 0, #rows - UI.STOCK_ROWS))
    if c.stockBar then c.stockBar.sync(c.stockOffset, #rows, UI.STOCK_ROWS) end
    local rest = #rows - c.stockOffset - UI.STOCK_ROWS
    c.stockMore:SetText(rest > 0 and string.format(UI.STOCK_MORE, rest) or "")
    c.stockCount:SetText(#rows > 0 and string.format(UI.STOCK_COUNT, #rows) or "")
    for i, r in ipairs(c.stockRows) do
        local item = rows[c.stockOffset + i]
        if item then
            r.stockItem = item
            -- GF-012-D: 可申領 N (shared − reserved) under the name.
            local avail = R() and R().itemAvailable(item) or nil
            r.set(item.itemID, item.total, { stripe = c.stockOffset + i, sub = avail and (UI.AVAIL_TEXT .. avail) or nil })
            r.who:SetText(K().whoText(item))
            r.ago:SetText(item.t and ns.Recipes.agoText(item.t) or "")
            r.contact.item = item
            local e = K().contactEntry(item)
            setEnabled(r.contact, e ~= nil and ns.Supply.canContact(e))
            r.ask.item = item
            setEnabled(r.ask, avail ~= nil and UI.requestChoiceCount(item) > 0)
        else
            r.stockItem, r.contact.item, r.ask.item = nil, nil, nil
            r:Hide()
        end
    end
    if #rows > 0 then
        c.stock.set(nil)
        shown(c.stockHead, true)
    else
        local key = cur.state ~= "ok" and "list" or (#all > 0 and (narrowed() and "filter" or "search")) or why
        local t = UI.STOCK_EMPTY[key] or UI.STOCK_EMPTY.none
        c.stock.set(key == "list" and "unknown" or "empty", t[1], t[2])
        shown(c.stockHead, false)
    end
end

function UI.scrollStock(delta)
    local before = c.stockOffset or 0
    local after = math.max(0, math.min((c.stockTotal or 0) - UI.STOCK_ROWS, before - (delta or 0)))
    if after == before then return false end
    c.stockOffset = after
    UI.closeContact()
    UI.drawStock()
    return true
end

---------------------------------------------------------------------------
-- GF-012-C: 聯絡. One custodian: the whisper box at once (as before). More:
-- one shared menu (Widgets.dropdown, its own button never shown) under the
-- button: name, how many, online; the first (online first, the most) is
-- marked （建議）; my own line is grey and cannot be picked.
---------------------------------------------------------------------------

local contactMenu
function UI.contactMenu()
    if not contactMenu then
        contactMenu = W().dropdown(UIParent, UI.CONTACT_W, function(i)
            local ch = contactMenu.choices and contactMenu.choices[i]
            if ch then ns.Supply.contact(ch.entry) end
        end)
        contactMenu:Hide()
    end
    return contactMenu
end

-- The menu lines for an item (BankStock.contactChoices): { value, text, disabled }.
function UI.contactItems(item)
    local choices = K().contactChoices(item)
    local out, best = {}, nil
    for i, ch in ipairs(choices) do
        local usable = not ch.own and ch.entry.member ~= nil
        if usable and not best then best = i end
        local t = ch.name .. (ch.own and UI.CONTACT_SELF or "") .. "　" .. ch.qty .. " 個　" .. (ch.online and "在線" or "離線")
        if best == i then t = t .. UI.CONTACT_BEST end
        out[i] = { value = i, text = t, disabled = not usable }
    end
    return out, choices, best
end

-- anchor: the 聯絡 button pressed; item: a stock row (BankStock.rows()).
function UI.contact(anchor, item)
    if not item then return false end
    if K().contactCount(item) <= 1 then
        local e = K().contactEntry(item)
        return e ~= nil and ns.Supply.contact(e)
    end
    local menu = UI.contactMenu()
    local items, choices, best = UI.contactItems(item)
    menu.choices = choices
    menu.setItems(items)
    menu.setValue(best)
    menu.openAt(anchor)
    return "menu"
end
function UI.closeContact() if contactMenu then contactMenu.close() end end

-- The page shows: draw it; a custodian who has not said yes yet is asked once.
function UI.show()
    if R() then R().prune(); R().settle() end -- GF-012-D: my old closed entries, then approvals for me
    UI.refresh()
    if K() then K().askIfNeeded() end
end

-- GF-UI-M: the wheel over the list moves one row; the same 8 rows are refilled.
function UI.scroll(delta)
    local before = c.offset or 0
    local after = math.max(0, math.min((c.total or 0) - UI.ROWS, before - (delta or 0)))
    if after == before then return false end
    c.offset = after
    UI.refresh()
    return true
end

---------------------------------------------------------------------------
-- GF-012-D: 審核幹部 rows on 保管人與分享設定 (the guild master's 撤銷 only).
---------------------------------------------------------------------------

UI.OFFICER_ROWS, UI.OFFICER_ROW_H = 3, 36
UI.OFFICER_MORE = "還有 %d 位，用滑鼠滾輪往下看"

function UI.officerRow(p, y, i)
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(UI.ROW_W, UI.OFFICER_ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", UI.X, y)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    ns.stripe(r.bg, i)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    local function col(x, w)
        local fs = ns.freeText(r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        fs:SetPoint("LEFT", r, "LEFT", x, 0); fs:SetWidth(w); fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    r.name = col(38, 190)
    r.state = col(236, 160)
    r.revoke = ns.OrdersUI.textButton(r, "撤銷", function()
        if r.entry and B().canManage() then UI.say(B().revokeOfficer(r.entry.a)) end
    end, 64)
    r.revoke:SetPoint("LEFT", r, "LEFT", 576, 0)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    r:SetScript("OnMouseWheel", function(_, delta) UI.scrollOfficers(delta) end)
    r:Hide()
    return r
end

function UI.drawOfficers(manage)
    if not c.officerRows then return end
    local entries, cur = B().officerEntries()
    c.officerTotal = #entries
    c.officerOffset = math.max(0, math.min(c.officerOffset or 0, #entries - UI.OFFICER_ROWS))
    if c.officerBar then c.officerBar.sync(c.officerOffset, #entries, UI.OFFICER_ROWS) end
    local rest = #entries - c.officerOffset - UI.OFFICER_ROWS
    c.officerMore:SetText(rest > 0 and string.format(UI.OFFICER_MORE, rest) or "")
    for i, r in ipairs(c.officerRows) do
        local e = entries[c.officerOffset + i]
        r.entry = e
        if e then
            local name, token = memberText(e.a)
            r.name:SetText(name)
            if token then ns.Icons.setClassIcon(r.icon, token); r.icon:Show() else r.icon:Hide() end
            local gone = ns.Share.memberFor(e.a) == nil
            r.state:SetText(e.enabled and (gone and "有效（已不在公會）" or "有效") or "已撤銷")
            local col = (e.enabled and not gone) and { 1, 1, 1 } or ns.COLOR.disabled
            r.name:SetTextColor(col[1], col[2], col[3]); r.state:SetTextColor(col[1], col[2], col[3])
            setEnabled(r.revoke, manage and e.enabled)
            r:Show()
        else
            r:Hide()
        end
    end
    local empty = ""
    if #entries == 0 then
        empty = cur.state == "ok" and "尚未指定審核幹部" or (cur.state == "none" and "尚未指定審核幹部（會長、保管人本來就能核准）")
            or (B().STATE_NAME[cur.state] or cur.state)
    end
    c.officerEmpty:SetText(empty)
    setEnabled(c.officerAdd, manage)
end

function UI.scrollOfficers(delta)
    local before = c.officerOffset or 0
    local after = math.max(0, math.min((c.officerTotal or 0) - UI.OFFICER_ROWS, before - (delta or 0)))
    if after == before then return false end
    c.officerOffset = after
    UI.drawOfficers(B().canManage())
    return true
end

---------------------------------------------------------------------------
-- GF-012-D: the 申領 page. Top 要我處理的 (waiting for my decision, approved
-- for me to hand over), bottom 我的申領. Reused rows (Widgets.itemRow), the
-- wheel on each list; each row only the buttons I may press now.
---------------------------------------------------------------------------

UI.REQ_ROWS = 5
UI.REQ_ROW_H = 44
UI.REQ_Y = { todoHead = -UI.TOP - 44, todoRows = -UI.TOP - 74, mineHead = -UI.TOP - 318, mineRows = -UI.TOP - 348 }
-- Columns right of the item name (x from the row's right edge); buttons at the right end.
UI.REQ_COL = { who = 640, purpose = 500, state = 410, ago = 220, b1 = 76, b2 = 6 }
UI.REQ_BUTTON_W = 64
UI.REQ_MORE = "還有 %d 筆，用滑鼠滾輪往下看"
UI.REQ_EMPTY = {
    todo = { "沒有要你處理的申領", "有人向你申領、或等你核准時會出現在這裡" },
    mine = { "你還沒有申領", "在「庫存」清單按「申領」就可以申請" },
    list = { "還沒有保管人名單", "等會長的名單傳到" },
}
UI.REQ_NOTE = "交付請自己交易或郵寄給對方，給了以後再按「已交付」；收到後請按「已收到」"

local function reqRow(p, y, i, list)
    local r = W().itemRow(p, UI.STOCK_W, UI.REQ_ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", UI.X, y - (i - 1) * UI.REQ_ROW_H)
    local function col(right, w)
        local fs = ns.freeText(r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        fs:SetPoint("LEFT", r, "RIGHT", -right, 0)
        fs:SetWidth(w); fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    local C = UI.REQ_COL
    r.who = col(C.who, 134)
    r.purpose = col(C.purpose, 84)
    r.state = col(C.state, 186)
    r.ago = col(C.ago, 72)
    r.b1 = ns.Theme.button(r, "", UI.REQ_BUTTON_W, ns.BUTTON_H)
    r.b1:SetPoint("RIGHT", r, "RIGHT", -C.b1, 0)
    r.b2 = ns.Theme.button(r, "", UI.REQ_BUTTON_W, ns.BUTTON_H)
    r.b2:SetPoint("RIGHT", r, "RIGHT", -C.b2, 0)
    for _, b in ipairs({ r.b1, r.b2 }) do
        b:SetScript("OnClick", function(self) if self.act and r.req then UI.reqAction(r.req, self.act) end end)
    end
    r.setRightWidth(C.who + 4)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    r:SetScript("OnMouseWheel", function(_, delta) UI.scrollRequests(list, delta) end)
    r:Hide()
    return r
end

function UI.buildRequests(p)
    local X, Y = UI.X, UI.REQ_Y
    c.req = { todo = { rows = {}, offset = 0 }, mine = { rows = {}, offset = 0 } }
    for _, key in ipairs({ "todo", "mine" }) do
        local L = c.req[key]
        local hy, ry = Y[key .. "Head"], Y[key .. "Rows"]
        L.head = header(p, key == "todo" and "要我處理的" or "我的申領", X, hy)
        L.more = text(p, ns.DISABLED_FONT, X + 140, hy, 500)
        for i = 1, UI.REQ_ROWS do L.rows[i] = reqRow(p, ry, i, key) end
        L.bar = UI.bar(p, X + UI.STOCK_W, ry, UI.REQ_ROWS * UI.REQ_ROW_H, function(o)
            L.offset = o
            UI.drawRequests()
        end)
        L.state = W().statePanel(p, UI.STOCK_W, 90)
        L.state:SetPoint("TOPLEFT", p, "TOPLEFT", X, ry - 10)
    end
    local bottom = Y.mineRows - UI.REQ_ROWS * UI.REQ_ROW_H
    c.reqResult = text(p, ns.LABEL_FONT, X + 4, bottom - 8, 500)
    c.reqNote = text(p, ns.DISABLED_FONT, X + 4, bottom - 36, UI.STOCK_W)
    c.reqNote:SetText(UI.REQ_NOTE)
end

local function whoText(v, list)
    if list == "mine" then return "保管人 " .. R().nameOf(v.keeper) end
    return "申請人 " .. R().nameOf(v.req)
end
local function subText(v)
    if v.state == "rejected" and v.decision and v.decision.reason ~= "" then return "拒絕原因：" .. v.decision.reason end
    if (v.note or "") ~= "" then return "備註：" .. v.note end
    return nil
end

local function drawList(key, rows)
    local L = c.req[key]
    L.list = rows
    L.offset = math.max(0, math.min(L.offset or 0, #rows - UI.REQ_ROWS))
    if L.bar then L.bar.sync(L.offset, #rows, UI.REQ_ROWS) end
    local rest = #rows - L.offset - UI.REQ_ROWS
    L.more:SetText(rest > 0 and string.format(UI.REQ_MORE, rest) or "")
    for i, r in ipairs(L.rows) do
        local v = rows[L.offset + i]
        r.req = v
        if v then
            r.set(v.itemID, v.qty, { stripe = L.offset + i, sub = subText(v) })
            r.who:SetText(whoText(v, key))
            r.purpose:SetText(R().PURPOSE_NAME[v.purpose] or "")
            r.state:SetText(R().STATE_NAME[v.state] or v.state)
            local col = R().CLOSED[v.state] and ns.COLOR.disabled or { 1, 1, 1 }
            r.state:SetTextColor(col[1], col[2], col[3])
            r.ago:SetText(ns.Recipes.agoText(v.at or v.created))
            local acts = R().actions(v)
            -- Two buttons at most (核准 + 拒絕, or one): the last one is at the right end.
            local b = { r.b1, r.b2 }
            local first = #acts >= 2 and 1 or 2
            for j, btn in ipairs(b) do
                local act = acts[j - first + 1]
                if j < first then act = nil end
                btn.act = act
                if act then btn:SetText(R().ACTION_TEXT[act]); btn:Show() else btn:Hide() end
            end
        else
            r:Hide()
        end
    end
    return #rows
end

function UI.drawRequests()
    if not c.req or not R() then return end
    local cur = B().current()
    local todo, mine = R().todo(), R().minelist()
    local nTodo, nMine = drawList("todo", todo), drawList("mine", mine)
    for key, n in pairs({ todo = nTodo, mine = nMine }) do
        local L = c.req[key]
        if n > 0 then L.state.set(nil)
        elseif cur.state ~= "ok" then L.state.set("unknown", UI.REQ_EMPTY.list[1], UI.REQ_EMPTY.list[2])
        else L.state.set("empty", UI.REQ_EMPTY[key][1], UI.REQ_EMPTY[key][2]) end
    end
end

function UI.scrollRequests(key, delta)
    local L = c.req and c.req[key]
    if not L then return false end
    local before = L.offset or 0
    local after = math.max(0, math.min(#(L.list or {}) - UI.REQ_ROWS, before - (delta or 0)))
    if after == before then return false end
    L.offset = after
    drawList(key, L.list)
    return true
end

-- 申領 on the top button: the number of requests waiting for me.
function UI.drawBadge()
    local b = c.viewButton and c.viewButton.requests
    if not b or not R() then return end
    local n = R().todoCount()
    b:SetText(n > 0 and (UI.REQ_TAB .. "（" .. math.min(n, 99) .. "）") or UI.REQ_TAB)
    c.badge = n
end

function UI.reqSay(result)
    if c.reqResult then c.reqResult:SetText(R().RESULT[result] or tostring(result or "")) end
    UI.refresh()
    return result
end

-- A row's button. 拒絕 asks for a reason (may be empty); 已交付 and 取消 ask first.
function UI.reqAction(v, act)
    local Rq = R()
    if act == "approve" then return UI.reqSay(Rq.approve(v.key)) end
    if act == "received" then return UI.reqSay(Rq.received(v.key)) end
    if act == "reject" then return UI.openReason(v) end
    if act == "deliver" then
        W().confirm(string.format("確定已經把 %s 交給 %s 了嗎？", Rq.itemText(v), Rq.nameOf(v.req)),
            function() UI.reqSay(Rq.deliver(v.key)) end)
        return "confirm"
    end
    if act == "cancel" then
        W().confirm("確定要取消這筆申領嗎？（" .. Rq.itemText(v) .. "）", function() UI.reqSay(Rq.cancel(v.key)) end)
        return "confirm"
    end
    return nil
end

---------------------------------------------------------------------------
-- GF-012-D: the 申領 form (one popup, reused): the item, the custodian (the
-- same choice as 聯絡: online first, the most 可申領 first; me grey), 數量
-- (at most 可申領), 用途 (must be chosen), 備註 (one short line, may be empty).
---------------------------------------------------------------------------

UI.FORM_NAME = "GreenFangToolkit_BankRequest"
UI.FORM_W, UI.FORM_H = 560, 380
UI.PURPOSE_NONE = "請選擇"

-- Custodians of a stock row for the form: { a, name, avail, online, own, usable }.
function UI.requestChoices(item)
    local out = {}
    for _, ch in ipairs(K().contactChoices(item)) do
        local h = ch.p.h
        local avail = R().available(h.a, item.itemID)
        out[#out + 1] = { a = h.a, name = ch.name, avail = avail, online = ch.online, own = ch.own,
            usable = not ch.own and ch.entry.member ~= nil and avail > 0 }
    end
    table.sort(out, function(x, y)
        if x.usable ~= y.usable then return x.usable end
        if x.online ~= y.online then return x.online end
        if x.avail ~= y.avail then return x.avail > y.avail end
        return x.a < y.a
    end)
    return out
end
function UI.requestChoiceCount(item)
    local n = 0
    for _, ch in ipairs(UI.requestChoices(item)) do if ch.usable then n = n + 1 end end
    return n
end

local function formSay(s) if UI.form then UI.form.result:SetText(s or "") end end

local function formMax()
    local f = UI.form
    local ch = f.choices and f.choices[f.keeperDrop.value or 0]
    return ch and ch.avail or 0
end

local function drawFormMax()
    local f = UI.form
    f.max:SetText("最多 " .. formMax())
end

local function buildForm()
    local O = ns.OrdersUI
    local f = ns.popupWindow(UI.FORM_NAME, UI.FORM_W, UI.FORM_H)
    f:SetPoint("CENTER", 0, 60)
    f:EnableMouse(true)
    ns.exclusivePopup(f)
    if f.TitleText then f.TitleText:SetText("申領臨時黑箱物品") end
    local names = { "物品", "保管人", "數量", "用途", "備註" }
    local X = O.controlX(names)
    local function y(i) return -50 - (i - 1) * 50 end
    for i, n in ipairs(names) do O.fieldLabel(f, n, O.FIELD_X, y(i) - 6) end
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(ns.ROW_ICON, ns.ROW_ICON)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(1) - 1)
    f.itemName = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    f.itemName:SetPoint("TOPLEFT", f, "TOPLEFT", X + ns.ROW_ICON + 8, y(1) - 6)
    f.itemName:SetWidth(UI.FORM_W - X - ns.ROW_ICON - 40); f.itemName:SetJustifyH("LEFT")
    if f.itemName.SetWordWrap then f.itemName:SetWordWrap(false) end
    f.keeperDrop = W().dropdown(f, 340, function() drawFormMax() end)
    f.keeperDrop:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(2))
    f.qty = ns.Theme.editBox(f, 90, 30)
    f.qty:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(3))
    if f.qty.SetNumeric then f.qty:SetNumeric(true) end
    if f.qty.SetMaxLetters then f.qty:SetMaxLetters(4) end
    f.qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.max = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
    f.max:SetPoint("TOPLEFT", f, "TOPLEFT", X + 104, y(3) - 6)
    local purposes = { { value = "", text = UI.PURPOSE_NONE } }
    for _, p in ipairs(R().PURPOSES) do purposes[#purposes + 1] = { value = p.key, text = p.text } end
    f.purposeDrop = W().dropdown(f, 160, function() end)
    f.purposeDrop:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(4))
    f.purposeDrop.setItems(purposes)
    f.note = ns.Theme.editBox(f, 340, 30)
    f.note:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(5))
    if f.note.SetMaxBytes then f.note:SetMaxBytes(R().NOTE_MAX) elseif f.note.SetMaxLetters then f.note:SetMaxLetters(15) end
    f.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.result = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    f.result:SetPoint("TOPLEFT", f, "TOPLEFT", O.FIELD_X, y(6) - 6)
    f.result:SetWidth(UI.FORM_W - 48); f.result:SetJustifyH("LEFT")
    f.send = O.textButton(f, "送出", function() UI.submitRequest() end, 90)
    f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    f.cancel = O.textButton(f, "取消", function() f:Hide() end, 90)
    f.cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20 - 90 - 12, 16)
    f:Hide()
    UI.form = f
    return f
end

-- item: a stock row (BankStock.rows / filter). Returns the form or nil.
function UI.openRequest(item)
    if not item or not R() then return nil end
    if ns.inCombat() then return nil end
    local f = UI.form or buildForm()
    f.item = item
    local info = W().itemInfo(item.itemID)
    if info.icon then ns.Icons.set(f.icon, info.icon) end
    f.itemName:SetText((info.loaded and info.name) or ns.Supply.itemName(item.itemID) or ("物品 " .. item.itemID))
    local choices = UI.requestChoices(item)
    local items, best = {}, nil
    for i, ch in ipairs(choices) do
        if ch.usable and not best then best = i end
        local t = ch.name .. (ch.own and UI.CONTACT_SELF or "") .. "　可申領 " .. ch.avail .. "　" .. (ch.online and "在線" or "離線")
        if best == i then t = t .. UI.CONTACT_BEST end
        items[i] = { value = i, text = t, disabled = not ch.usable }
    end
    f.choices = choices
    f.keeperDrop.setItems(items)
    f.keeperDrop.setValue(best)
    f.purposeDrop.setValue("")
    f.qty:SetText("1")
    f.note:SetText("")
    formSay("")
    drawFormMax()
    f:Show()
    return f
end

function UI.submitRequest()
    local f = UI.form
    if not f or not f.item then return nil end
    local ch = f.choices and f.choices[f.keeperDrop.value or 0]
    if not ch or not ch.usable then formSay(R().RESULT.keeper); return "keeper" end
    local r = R().create({ keeper = ch.a, itemID = f.item.itemID, qty = tonumber(str(f.qty:GetText())),
        purpose = f.purposeDrop.value, note = f.note:GetText() })
    if r ~= "ok" then
        if r == "more" then formSay(R().RESULT.more .. "（最多 " .. formMax() .. "）") else formSay(R().RESULT[r] or r) end
        return r
    end
    f:Hide()
    UI.setView("requests")
    UI.reqSay("ok")
    return r
end

---------------------------------------------------------------------------
-- GF-012-D: 拒絕's reason (one popup, reused; the reason may be empty).
---------------------------------------------------------------------------

UI.REASON_NAME = "GreenFangToolkit_BankReason"

function UI.openReason(v)
    if ns.inCombat() or not v then return nil end
    local f = UI.reason
    if not f then
        local O = ns.OrdersUI
        f = ns.popupWindow(UI.REASON_NAME, 520, 210)
        f:SetPoint("CENTER", 0, 80)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("拒絕申領") end
        f.what = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        f.what:SetPoint("TOPLEFT", f, "TOPLEFT", O.FIELD_X, -50)
        f.what:SetWidth(470); f.what:SetJustifyH("LEFT")
        O.fieldLabel(f, "原因", O.FIELD_X, -98)
        local X = O.controlX({ "原因" })
        f.box = ns.Theme.editBox(f, 340, 30)
        f.box:SetPoint("TOPLEFT", f, "TOPLEFT", X, -92)
        if f.box.SetMaxBytes then f.box:SetMaxBytes(R().NOTE_MAX) elseif f.box.SetMaxLetters then f.box:SetMaxLetters(15) end
        f.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.hint = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", X, -128)
        f.hint:SetText("可以不填")
        f.yes = O.textButton(f, "拒絕", function()
            local key = f.key
            f:Hide()
            if key then UI.reqSay(R().reject(key, f.box:GetText())) end
        end, 90)
        f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f.no = O.textButton(f, "取消", function() f:Hide() end, 90)
        f.no:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20 - 90 - 12, 16)
        f:Hide()
        UI.reason = f
    end
    f.key = v.key
    f.what:SetText(R().itemText(v) .. "（申請人 " .. R().nameOf(v.req) .. "）")
    f.box:SetText("")
    f:Show()
    return f
end

-- A notice of 申領 opens this page on 申領.
if ns.Notify and ns.Notify.setFocus then
    ns.Notify.setFocus(UI.ID, function(_, target)
        local tab = type(target) == "table" and target.tab or nil
        if tab and UI.viewDef(tab) then UI.setView(tab); return true end
        return false
    end)
end
-- The requests changed (a record, my own action): draw again when shown.
function UI.requestsChanged() if panel and panel:IsShown() then UI.refresh() end end

ns.Bank.onChanged = function() if panel and panel:IsShown() then UI.refresh() end end
-- GF-012-B: BankStock tells only when a stock record or my sharing changed.
function UI.stockChanged() if panel and panel:IsShown() then UI.refresh() end end

ns.Framework.register({
    id = UI.ID,
    title = "臨時黑箱",
    short = "黑箱",
    subTitle = "臨時黑箱",
    entry = "logistics",
    order = 17,
    create = build,
    show = UI.show,
})
