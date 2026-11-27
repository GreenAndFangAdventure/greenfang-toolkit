-- BankUI (GF-012 phase 1, spec v2.0 §8, design GF-012-A §6): 物資調度 →
-- 公會黑庫. Shows who is guild master, the custodian list and its state, the
-- guild master's buttons (指定 / 背包 / 銀行 / 撤銷; everybody else sees them
-- disabled, never lit), a custodian's own 公產 scope (a setting only) and,
-- in place of the stock list, a state panel (GF-UI-M: 「庫存：第二階段才有」).
-- Game art only (class icons, the state panel's icons), 16 px text, button
-- names of 2-4 characters.

local _, ns = ...
local str = ns.str

local UI = {}
ns.BankUI = UI

UI.ID = "bank"
UI.ROWS, UI.ROW_H, UI.ROW_W = 8, 40, 660
UI.X, UI.RIGHT_X = 20, 720
-- GF-UI-I (owner 0.16.2: 標題和右邊的字壓到上面的分頁列): the sub-tab row's
-- line ends 29 px into the page, so everything starts UI.TOP below it.
UI.TOP = 40
UI.Y = { title = -UI.TOP, status = -UI.TOP - 32, listHead = -UI.TOP - 68, rows = -UI.TOP - 100, scopeHead = -UI.TOP - 68,
    stockHead = -UI.TOP - 484, stock = -UI.TOP - 514 }
-- GF-UI-M (owner): what the 庫存 area says in phase 1 (was 「尚未開放｜等會長實機驗證權限後開放」).
UI.STOCK_TITLE = "庫存：第二階段才有"
UI.STOCK_DETAIL = "目前只能管理保管人名單；庫存、申領、核准還在開發中"
-- GF-UI-M (owner): the list scrolls with the wheel (8 pooled rows; up to 10
-- active + 10 revoked); the same 「還有 N 位」 line as 調貨看板's detail.
UI.MORE_TEXT = "還有 %d 位，用滑鼠滾輪往下看"
UI.RESULT = {
    ["no-authority"] = "只有會長可以管理", ["not-found"] = "找不到這位職工", full = "保管人已達上限",
    same = "沒有變更", invalid = "格式不對", ["last-kind"] = "至少留一種，否則請撤銷", ok = "已更新",
    combat = "戰鬥中，結束後再選", roster = "公會名冊尚未載入",
}

local panel
local c = {}

local function B() return ns.Bank end
local function W() return ns.Widgets end

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

local function build(p)
    panel = p
    local X, Y = UI.X, UI.Y
    c.title = header(p, "臨時秘密黑箱", X, Y.title) -- owner 2026-11-25: was 公會黑庫
    c.role = text(p, ns.FIELD_FONT, X + 140, Y.title, 300)
    c.status = text(p, ns.LABEL_FONT, X, Y.status, 1040)
    c.listHead = header(p, "保管人名單", X, Y.listHead)
    c.more = text(p, ns.DISABLED_FONT, X + 140, Y.listHead, 520)
    c.offset = 0
    c.rows = {}
    for i = 1, UI.ROWS do c.rows[i] = row(p, i) end
    c.listState = W().statePanel(p, UI.ROW_W, 120)
    c.listState:SetPoint("TOPLEFT", p, "TOPLEFT", X, Y.rows - 20)
    local addY = Y.rows - UI.ROWS * UI.ROW_H - 10
    c.nameLabel = text(p, ns.FIELD_FONT, X, addY - 6)
    c.nameLabel:SetText("職工") -- GF-UI-K: 成員 = 職工 (spec §3)
    -- GF-012-FIX (owner 2026-11-27: 成員一定是公會內的人，可以用選的): the box
    -- only searches the guild roster; 選擇職工 appoints a typed name only when
    -- it is exactly one roster member, otherwise it opens the picker.
    c.name = ns.Theme.editBox(p, 200, 30)
    c.name:SetPoint("TOPLEFT", p, "TOPLEFT", X + 50, addY)
    c.appoint = ns.OrdersUI.textButton(p, "選擇職工", function()
        if B().canManage() then UI.choose(str(c.name:GetText())) end
    end, 100)
    c.appoint:SetPoint("TOPLEFT", p, "TOPLEFT", X + 260, addY)
    c.name:SetScript("OnEnterPressed", function() if not c.appoint.disabled then c.appoint:Click() end end)
    c.result = text(p, ns.LABEL_FONT, X + 372, addY - 6, 290)
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
            end)
            box.kind, box.index = kind, index
            c.scope[kind][#c.scope[kind] + 1] = box
        end
        y = y - math.ceil(#B().SCOPE[kind] / 3) * 34 - 14
    end
    c.scopeNote = text(p, ns.DISABLED_FONT, UI.RIGHT_X, y - 4, 360)
    c.scopeNote:SetText("只存在本機，不掃描")
    -- 庫存
    c.stockHead = header(p, "庫存", X, Y.stockHead)
    c.stock = W().statePanel(p, 1060, 100)
    c.stock:SetPoint("TOPLEFT", p, "TOPLEFT", X, Y.stock)
    UI.controls = c
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
            b.mark:SetText(r.custodian and "已是保管人" or "")
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
    if UI.picker then UI.picker:Hide() end
    local res = UI.say(B().appoint({ guid = ns.Share.guidOf(r.a) }))
    if res == "ok" and c.name then c.name:SetText("") end
    return res
end

function UI.openPicker(q)
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
    f:Show()
    f.search:SetText(f.query)
    UI.drawPicker()
    return f
end

function UI.refresh()
    if not panel then return end
    local Bk = B()
    local role = Bk.myRole()
    local manage = Bk.canManage()
    c.role:SetText("身分：" .. (Bk.ROLE_NAME[role] or "?"))
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
    c.stock.set("unknown", UI.STOCK_TITLE, UI.STOCK_DETAIL)
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

ns.Bank.onChanged = function() if panel and panel:IsShown() then UI.refresh() end end

ns.Framework.register({
    id = UI.ID,
    title = "臨時秘密黑箱",
    short = "黑箱",
    subTitle = "臨時黑箱",
    entry = "logistics",
    order = 17,
    create = build,
    show = UI.refresh,
})
