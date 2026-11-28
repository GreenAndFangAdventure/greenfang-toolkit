-- GuildBankUI (GF-017): the 公會銀行 view on the 臨時黑箱 page (one of its
-- buttons at the top, through ns.BankUI.addView when the page offers it).
--   Top: the balance in gold / silver / copper (the game's coin icons) and
--     who saw it how long ago; nobody yet: 「還沒有人打開過公會銀行」, never 0.
--   Totals: the last 7 and 30 days (deposits, spending, net); when the log
--     covers less, 「只有最近 N 天的紀錄」.
--   The log: kind icon, name, 存入 / 支出, the amount (green in, red out),
--     how long ago. Reused rows (as many as fit), the wheel, 「還有 N 筆」;
--     filters 全部 / 存入 / 支出 and a name search (redrawn at most 0.15 s late).
-- build() makes every frame once; draw() only sets text and shows / hides.
-- Game art only; sizes from the shared constants (ns.ROW_ICON, ns.BUTTON_H,
-- ns.PAGE_ROW).

local _, ns = ...
local str = ns.str

local UI = {}
ns.GuildBankUI = UI

UI.KEY, UI.TEXT, UI.ORDER = "guildbank", "公會銀行", 40
UI.W, UI.H = 1060, 560        -- used when the parent has no size yet
UI.ROW_H = ns.PAGE_ROW or 36
UI.MORE_H = 26
UI.SEARCH_DELAY = 0.15
UI.Y = { money = 0, seen = -30, sum7 = -64, sum30 = -90, filters = -124, head = -166, rows = -192 }
UI.COL = { icon = 6, name = 44, kind = 300, amount = 400, ago = 720 }
UI.HEADINGS = { { "種類", 6 }, { "角色", 44 }, { "收支", 300 }, { "金額", 400 }, { "多久前", 720 } }
UI.FILTERS = { { key = "all", text = "全部" }, { key = "in", text = "存入" }, { key = "out", text = "支出" } }
UI.MORE_TEXT = "還有 %d 筆，用滑鼠滾輪往下看"
UI.EMPTY_FILTER = "沒有符合的紀錄，換個篩選或名字試試"

local c = { built = false, offset = 0, kind = "all", search = "", draws = 0 }
UI.c = c

local function GB() return ns.GuildBank end
local function T() return ns.Theme end

local function text(parent, font, x, y, w)
    local fs = ns.freeText(parent:CreateFontString(nil, "ARTWORK", font or ns.LABEL_FONT))
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if w then fs:SetWidth(w); fs:SetJustifyH("LEFT") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

local function shown(f, on) if on then f:Show() else f:Hide() end end

-- Copper in one colour with the game's coin icons: "|cff..12|r[金] 3[銀]".
local COLOR = { good = { 0.25, 1, 0.35 }, bad = { 1, 0.25, 0.25 } }
UI.COLOR = COLOR
function UI.coins(copper, color, size)
    local cv = math.floor(math.abs(tonumber(copper) or 0))
    local g, s, cu = math.floor(cv / 10000), math.floor(cv / 100) % 100, cv % 100
    local tex = T().TEX.coin
    local n = size or 0
    local hex = color and T().hex(color) or nil
    local out = {}
    local function part(v, t)
        out[#out + 1] = (hex and (hex .. v .. "|r") or tostring(v)) .. "|T" .. t .. ":" .. n .. ":" .. n .. ":2:0|t"
    end
    if g > 0 then part(g, tex.gold) end
    if s > 0 then part(s, tex.silver) end
    if cu > 0 or #out == 0 then part(cu, tex.copper) end
    return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Build (once)
---------------------------------------------------------------------------

local function row(p, i, w)
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(w, UI.ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", 0, UI.Y.rows - (i - 1) * UI.ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    ns.stripe(r.bg, i)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(ns.ROW_ICON, ns.ROW_ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", UI.COL.icon, 0)
    local function col(x, cw)
        local fs = ns.freeText(r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        fs:SetPoint("LEFT", r, "LEFT", x, 0); fs:SetWidth(cw); fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    r.name = col(UI.COL.name, UI.COL.kind - UI.COL.name - 8)
    r.kind = col(UI.COL.kind, UI.COL.amount - UI.COL.kind - 8)
    r.amount = col(UI.COL.amount, UI.COL.ago - UI.COL.amount - 8)
    r.ago = col(UI.COL.ago, w - UI.COL.ago - 8)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    r:SetScript("OnMouseWheel", function(_, delta) UI.scroll(delta) end)
    r:Hide()
    return r
end

function UI.build(parent)
    if c.built then return c.panel end
    c.built = true
    c.panel = parent
    local w = (parent.GetWidth and ns.num(parent:GetWidth())) or 0
    local h = (parent.GetHeight and ns.num(parent:GetHeight())) or 0
    -- A parent not laid out yet (or too small to be the page) gets the page's size.
    if w < 600 then w = UI.W end
    if h < 300 then h = UI.H end
    c.w = w
    c.moneyLabel = text(parent, ns.FIELD_FONT, 0, UI.Y.money, 100)
    c.moneyLabel:SetText("目前存款")
    c.money = text(parent, ns.LABEL_FONT, 104, UI.Y.money, w - 104)
    c.seen = text(parent, ns.DISABLED_FONT, 0, UI.Y.seen, w)
    c.sum7 = text(parent, ns.LABEL_FONT, 0, UI.Y.sum7, w)
    c.sum30 = text(parent, ns.LABEL_FONT, 0, UI.Y.sum30, w)
    -- Filters: 全部 / 存入 / 支出, then the name search.
    c.filters = {}
    local x = 0
    for _, f in ipairs(UI.FILTERS) do
        local b = T().button(parent, f.text, 72, ns.BUTTON_H)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, UI.Y.filters)
        local key = f.key
        b.key = key
        b:SetScript("OnClick", function() UI.setKind(key) end)
        c.filters[#c.filters + 1] = b
        x = x + 72 + 8
    end
    c.searchLabel = text(parent, ns.FIELD_FONT, x + 16, UI.Y.filters - 6, 70)
    c.searchLabel:SetText("角色名")
    c.search = T().editBox(parent, 180, ns.BUTTON_H)
    c.search:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 86, UI.Y.filters)
    c.search:SetScript("OnTextChanged", function(self)
        c.search.gfText = str(self:GetText())
        ns.coalesce("guildbank-search", UI.SEARCH_DELAY, function()
            if c.search.gfText ~= c.searchApplied then UI.setSearch(c.search.gfText) end
        end)
    end)
    c.count = text(parent, ns.DISABLED_FONT, x + 286, UI.Y.filters - 6, 300)
    -- Column heads and the line under them.
    c.heads = {}
    for _, hd in ipairs(UI.HEADINGS) do
        local fs = text(parent, T().FONT and T().FONT.header or ns.FIELD_FONT, hd[2], UI.Y.head, 200)
        fs:SetText(hd[1])
        c.heads[#c.heads + 1] = fs
    end
    if T().hline then c.headLine = T().hline(parent, UI.Y.head - 22, 0, 0) end
    c.nRows = math.max(3, math.floor((h + UI.Y.rows - UI.MORE_H - 4) / UI.ROW_H))
    c.rows = {}
    for i = 1, c.nRows do c.rows[i] = row(parent, i, w) end
    c.empty = text(parent, ns.DISABLED_FONT, 8, UI.Y.rows - 8, w - 16)
    c.more = text(parent, ns.DISABLED_FONT, 0, UI.Y.rows - c.nRows * UI.ROW_H - 4, w)
    -- A big note for the states without data (no guild, another guild ...).
    c.note = text(parent, ns.LABEL_FONT, 0, UI.Y.seen, w)
    if parent.EnableMouseWheel then parent:EnableMouseWheel(true) end
    if parent.SetScript then parent:SetScript("OnMouseWheel", function(_, delta) UI.scroll(delta) end) end
    UI.selectFilter()
    return parent
end

---------------------------------------------------------------------------
-- Draw (any number of times; no frame is made here)
---------------------------------------------------------------------------

function UI.selectFilter()
    for _, b in ipairs(c.filters or {}) do
        local chosen = b.key == c.kind
        T().setSelected(b, chosen)
        if b.SetEnabled then b:SetEnabled(not chosen) end
    end
end

function UI.setKind(kind)
    if kind ~= "all" and kind ~= "in" and kind ~= "out" then return end
    c.kind, c.offset = kind, 0
    UI.selectFilter()
    UI.draw()
end

function UI.setSearch(s)
    c.searchApplied = str(s)
    c.offset = 0
    UI.draw()
end

function UI.scroll(delta)
    if not c.built then return end
    local rows = GB().rows(c.kind, c.searchApplied or "")
    local maxOff = math.max(0, #rows - c.nRows)
    c.offset = math.max(0, math.min(maxOff, c.offset - (tonumber(delta) or 0)))
    UI.drawRows(rows)
end

local function summaryLine(label, s, days)
    if not s.any then return label .. "：" .. GB().TEXT.logNone end
    local line = string.format("%s：存入 %s　支出 %s　淨增減 %s%s", label,
        UI.coins(s.income, COLOR.good), UI.coins(s.spend, COLOR.bad),
        s.net < 0 and "-" or (s.net > 0 and "+" or ""), UI.coins(s.net, s.net < 0 and COLOR.bad or COLOR.good))
    if s.covered then
        line = line .. "（" .. (s.covered < 1 and "只有不到 1 天的紀錄" or string.format("只有最近 %d 天的紀錄", s.covered)) .. "）"
    end
    return line
end

function UI.drawRows(rows)
    local now = ns.Share.serverNow()
    local maxOff = math.max(0, #rows - c.nRows)
    if c.offset > maxOff then c.offset = maxOff end
    for i, r in ipairs(c.rows) do
        local e = rows[c.offset + i]
        if e then
            local inc = GB().INCOME[e.k]
            local out = GB().SPEND[e.k]
            ns.Icons.set(r.icon, GB().ICON[e.k] or GB().ICON.o)
            r.name:SetText(e.n ~= "" and ns.shortName(e.n) or "（沒有名字）")
            local kindText = inc and "存入" or out and "支出" or "其他"
            local detail = GB().KIND_NAME[e.k] or ""
            r.kind:SetText(kindText .. ((detail ~= kindText and detail ~= "") and ("：" .. detail) or ""))
            r.amount:SetText((inc and "+" or out and "-" or "") .. UI.coins(e.a, inc and COLOR.good or out and COLOR.bad or nil))
            r.ago:SetText(GB().agoText(e.t, now) .. (e.p > GB().HOUR and "（大約）" or ""))
            r:Show()
        else
            r:Hide()
        end
    end
    local rest = #rows - c.offset - c.nRows
    c.more:SetText(rest > 0 and string.format(UI.MORE_TEXT, rest) or "")
end

-- What is on the page now (tests and scripts).
function UI.shown()
    local out = {}
    for _, r in ipairs(c.rows or {}) do
        if r:IsShown() then out[#out + 1] = { name = r.name:GetText(), kind = r.kind:GetText(), amount = r.amount:GetText() } end
    end
    return out
end

function UI.draw()
    if not c.built then return end
    c.draws = c.draws + 1
    local st = GB().status()
    local ok = st.state == "ok" or st.state == "never" or st.state == "noapi" or st.state == "unread"
    -- No guild / another guild / loading: one sentence, nothing else.
    local parts = { c.moneyLabel, c.money, c.seen, c.sum7, c.sum30, c.searchLabel, c.search, c.count, c.more, c.empty,
        c.headLine }
    for _, f in ipairs(parts) do if f then shown(f, ok) end end
    for _, b in ipairs(c.filters) do shown(b, ok) end
    for _, h in ipairs(c.heads) do shown(h, ok) end
    if not ok then
        c.note:SetText(GB().TEXT[st.state] or GB().TEXT.other)
        c.note:Show()
        for _, r in ipairs(c.rows) do r:Hide() end
        return
    end
    c.note:Hide()
    local now = ns.Share.serverNow()
    local TX = GB().TEXT
    if st.state == "ok" then
        c.money:SetText(UI.coins(st.best.money, nil, 16))
        c.seen:SetText(string.format("由 %s 在%s看到", st.best.by ~= "" and st.best.by or "會友", GB().agoText(st.best.at, now)))
    else
        c.money:SetText(TX[st.state])
        c.seen:SetText(st.state == "never" and TX.neverHint or "")
    end
    local log = st.log or {}
    c.sum7:SetText(summaryLine("最近 7 天", GB().summary(log, 7, now), 7))
    c.sum30:SetText(summaryLine("最近 30 天", GB().summary(log, 30, now), 30))
    local rows = GB().rows(c.kind, c.searchApplied or "")
    c.count:SetText(#log > 0 and string.format("共 %d 筆", #rows) or "")
    if #log == 0 then
        c.empty:SetText(st.logRead == "0" and TX.logEmpty or st.logRead == "?" and TX.logUnread or TX.logNone)
    elseif #rows == 0 then
        c.empty:SetText(UI.EMPTY_FILTER)
    else
        c.empty:SetText("")
    end
    UI.drawRows(rows)
end

---------------------------------------------------------------------------
-- The data changed: redraw soon, only while the view is shown.
---------------------------------------------------------------------------

function UI.changed()
    if not c.built then return end
    ns.coalesce("guildbank-draw", 0.1, function()
        if c.panel and c.panel.IsVisible and c.panel:IsVisible() then UI.draw() end
    end)
end
ns.GuildBank.onChanged = UI.changed

-- Join the 臨時黑箱 page's buttons when it offers ns.BankUI.addView (GF-012-D).
function UI.register()
    local B = ns.BankUI
    if type(B) ~= "table" or type(B.addView) ~= "function" then return false end
    if UI.registeredWith == B.addView then return false end
    UI.registeredWith = B.addView
    B.addView({ key = UI.KEY, text = UI.TEXT, order = UI.ORDER, build = UI.build, draw = UI.draw })
    return true
end
UI.register()
