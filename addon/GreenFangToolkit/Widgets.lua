-- Widgets (GF-002-I, spec GF-002 §17.3, design review GF-UI-A §1.5 / §1.7):
-- small shared pieces that show how the toolkit decided something, without
-- sentences: a state badge (icon + 2-3 characters, colored by state), its
-- ✓✗ checklist tooltip (ReadyCheck marks, items of at most 6 characters and a
-- number), a gold 2 px frame, the list-row selection, a disabled look, and a
-- card of icons, arrows and numbers (the rules card).
--
-- Nothing here knows the rules: the checklist only draws what the caller
-- hands it (Adventure.whyState for adventure tickets).
--
-- GF-UI-E (spec v2.0 §4.2, appendix A §7.3): pieces for the new pages
-- (GF-009 調貨所, GF-010 職工檔案, GF-012 黑庫). How to use them:
--
--   物品列 (an item: the game's icon 36 px + its name + a count)
--     local row = ns.Widgets.itemRow(parent, 520)        -- width; height W.ITEM_ROW_H
--     row:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -80)
--     row.set(6948, "缺 1", { sub = "可能提供：2 位", stripe = i })
--     row.set(nil)                                       -- hides the row
--     -- Not cached yet: the question-mark icon and 「物品資料載入中」; the row
--     -- redraws itself on GET_ITEM_INFO_RECEIVED (no OnUpdate, no scan).
--     -- The mouse over it shows the game's item tooltip (or the name only).
--     -- Clickable only when you give it an OnClick (row:SetScript("OnClick", fn));
--     -- otherwise it never lights up (GF-UI-D2). row.right is a frame at the
--     -- row's right end for your buttons (聯絡); the name is cut before it.
--     -- Reuse rows when scrolling (one row per visible line, never one per member).
--   ns.Widgets.itemInfo(itemID) -> { id, name, icon, link, loaded }  (pure read)
--
--   空／載入／未知／過期／錯誤 (a state in place of a list)
--     local st = ns.Widgets.statePanel(parent, 600, 120)
--     st:SetPoint("TOP", parent, "TOP", 0, -140)
--     st.set("empty", "目前沒有可配對的公會物資")  -- kinds: W.STATE_KINDS; text optional
--     st.set(nil)                                   -- hides it
--     -- Always an icon and words; never a colour alone, never an error code.
--   ns.Widgets.freshness(at, now?, opts?) -> key, text, color
--     -- 近期 / 稍早 / 過期 / 未知 for list rows; the exact time goes in the tooltip.
--     -- opts = { recent = seconds, stale = seconds } (default 6 h / 3 days).
--
--   子分頁列 (tabs inside a page, e.g. 我缺的 / 我可能有多的)
--     local tabs = ns.Widgets.subTabs(parent, { { key = "need", text = "我缺的" },
--         { key = "spare", text = "我可能有多的" } }, 20, -40, function(key) redraw(key) end)
--     tabs.select("need")          -- the chosen tab is gold and cannot be pressed
--     tabs.setEnabled("spare", false); tabs.setShown("spare", false)  -- re-laid out
--   The main window's own entry / sub-tab row is Framework.lua (register entry=...).

local _, ns = ...
local str = ns.str

local W = {}
ns.Widgets = W

local function G() return ns.GameIcons end

-- Colors (design review §1.8): Core's ns.COLOR (GF-UI-B) when it is there.
W.COLOR = ns.COLOR or {
    gold = { 1, 0.82, 0 }, white = { 1, 1, 1 }, muted = { 0.72, 0.72, 0.72 }, disabled = { 0.5, 0.5, 0.5 },
    good = { 0.25, 1, 0.35 }, formed = { 0.3, 0.9, 0.85 }, warn = { 1, 0.55, 0.15 }, bad = { 1, 0.25, 0.25 },
}
-- State -> art (GameIcons.ART) and color. One texture, one meaning.
W.STATE_ART = { open = "state_open", final = "state_final", formed = "state_formed", done = "state_done",
    ended = "state_ended", unfinished = "state_unfinished", cancel = "state_cancel",
    worker = "state_worker", closed = "state_ended" }
W.STATE_COLOR = { open = "white", final = "gold", formed = "formed", done = "good", ended = "disabled",
    unfinished = "warn", cancel = "disabled", worker = "white", closed = "disabled" }
-- GF-UI-P: my own status on someone else's ticket (Adventure.myStatus): art and color.
W.MINE_ART = { i = "invite", p = "wait", m = "yes", w = "clock" }
W.MINE_COLOR = { i = "gold", p = "white", m = "good", w = "muted" }
W.BADGE_ICON, W.BADGE_W = 20, 90
W.CHECK_ICON = 16
W.ITEM_MAX = 6 -- characters of an item's name (R-17.11)

function W.color(state)
    return W.COLOR[W.STATE_COLOR[state] or "white"] or W.COLOR.white
end
local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
W.hex = hex

-- Characters in a UTF-8 string (Chinese counts 1).
function W.chars(s)
    local n = 0
    for _ in str(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- The ✓✗ checklist (pure: lines of text; the tooltip only adds them)
---------------------------------------------------------------------------

-- ok = true ✓, false ✗, nil ⏳ (not yet / cannot tell here).
function W.mark(okv)
    local key = okv == true and "yes" or okv == false and "no" or "wait"
    return G().markup(key, W.CHECK_ICON)
end

-- why = { groups = { { state, name, items = { { ok, text, value, at, span, sep } } } }, action };
-- opts = { format(item) -> extra text (times), action(key) -> "icon name" text }.
-- Returns { { text, color } }: a group's name in gold (with its state art), one item a
-- line, and the button to press last (the arrow art, the button's icon and name).
function W.checklistLines(why, opts)
    opts = opts or {}
    local out = {}
    if not why then return out end
    -- GF-UI-P: my own status first (你的狀態), then the ticket's (冒險單：…), so the two never mix.
    if why.mine then
        out[#out + 1] = { text = G().markup(W.MINE_ART[why.mine] or "person", W.CHECK_ICON) .. " " .. W.TEXT.mine .. str(why.name),
            color = W.COLOR.gold }
        if why.mineTip then out[#out + 1] = { text = "   " .. str(why.mineTip), color = W.COLOR.white } end
    end
    for gi, g in ipairs(why.groups or {}) do
        out[#out + 1] = { text = G().markup(W.STATE_ART[g.state] or "state_open", W.CHECK_ICON) .. " "
            .. ((why.mine and gi == 1) and W.TEXT.ticket or "") .. str(g.name), color = W.COLOR.gold }
        for _, it in ipairs(g.items or {}) do
            if it.sep then
                out[#out + 1] = { text = "   " .. str(it.text), color = W.COLOR.muted }
            else
                local extra = opts.format and opts.format(it) or nil
                local value = it.value or extra
                out[#out + 1] = { text = "   " .. W.mark(it.ok) .. " " .. str(it.text) .. (value and value ~= "" and (" " .. value) or ""),
                    color = it.ok == false and W.COLOR.muted or W.COLOR.white }
            end
        end
    end
    if why.action and opts.action then
        local a = opts.action(why.action)
        if a and a ~= "" then out[#out + 1] = { text = G().markup("arrow", W.CHECK_ICON) .. " " .. a, color = W.COLOR.gold } end
    end
    return out
end

function W.checklistTooltip(owner, why, opts)
    if not (owner and why) then return nil end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local lines = W.checklistLines(why, opts)
    for _, l in ipairs(lines) do GameTooltip:AddLine(l.text, l.color[1], l.color[2], l.color[3]) end
    GameTooltip:Show()
    return lines
end

---------------------------------------------------------------------------
-- The state badge: icon 20 + a 2-3 character name, colored by state;
-- the mouse over it shows the checklist (R-17.11).
---------------------------------------------------------------------------

function W.statusBadge(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(W.BADGE_W, W.BADGE_ICON + 4)
    b.gfWidth = W.BADGE_W
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(W.BADGE_ICON, W.BADGE_ICON)
    b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    b.text:SetPoint("LEFT", b, "LEFT", W.BADGE_ICON + 4, 0)
    b.text:SetJustifyH("LEFT")
    b:EnableMouse(true)
    b.infoOnly = true -- only a tooltip: the name is its own text
    b.label = b.text
    function b.set(why, opts)
        b.why, b.opts = why, opts
        if not why then b:Hide(); return end
        G().set(b.icon, (why.mine and W.MINE_ART[why.mine]) or W.STATE_ART[why.state] or "state_open")
        local c = why.mine and (W.COLOR[W.MINE_COLOR[why.mine] or "white"] or W.COLOR.white) or W.color(why.state)
        b.text:SetText(str(why.name))
        b.text:SetTextColor(c[1], c[2], c[3])
        local grey = why.state == "ended" or why.state == "cancel" or why.state == "closed"
        if b.icon.SetDesaturated then b.icon:SetDesaturated(grey) end
        b.state = why.state
        b:Show()
    end
    b:SetScript("OnEnter", function(self) W.checklistTooltip(self, self.why, self.opts) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

---------------------------------------------------------------------------
-- Frames and selection (design review §1.5, §2.8)
---------------------------------------------------------------------------

-- A gold frame of `px` around f (BORDER layer): today / the chosen day.
function W.goldFrame(f, px)
    px = px or 2
    local c = W.COLOR.gold
    local edges = {}
    local spec = {
        { "TOPLEFT", "TOPRIGHT", nil, px }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, px },
        { "TOPLEFT", "BOTTOMLEFT", px, nil }, { "TOPRIGHT", "BOTTOMRIGHT", px, nil },
    }
    for _, e in ipairs(spec) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetPoint(e[1], f, e[1], 0, 0)
        t:SetPoint(e[2], f, e[2], 0, 0)
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:Hide()
        edges[#edges + 1] = t
    end
    local frame = { edges = edges, shown = false }
    function frame.set(on)
        frame.shown = on and true or false
        for _, t in ipairs(edges) do if on then t:Show() else t:Hide() end end
    end
    return frame
end

-- The list-row selection (design review §1.5): the quest log's title highlight in
-- gold (ADD) and a 3 px gold bar on the left; never a flat yellow block.
W.ROW_SELECT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
function W.rowSelect(row)
    -- GF-UI-B: the toolkit's shared ns.rowSelect (Core.lua), with this file's set(on) API.
    if ns.rowSelect then
        local s = ns.rowSelect(row)
        local sel = { hl = s.glow, bar = s.bar, on = false, core = s }
        function sel.set(on)
            sel.on = on and true or false
            if on then s:Show() else s:Hide() end
        end
        return sel
    end
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    if not ns.Icons.set(hl, W.ROW_SELECT) then hl:SetColorTexture(1, 0.82, 0, 0.2) end
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    if hl.SetVertexColor then hl:SetVertexColor(1, 0.82, 0) end
    hl:SetAlpha(0.55)
    hl:Hide()
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    bar:SetColorTexture(1, 0.82, 0, 1)
    bar:Hide()
    local sel = { hl = hl, bar = bar, on = false }
    function sel.set(on)
        sel.on = on and true or false
        if on then hl:Show(); bar:Show() else hl:Hide(); bar:Hide() end
    end
    return sel
end

-- Can not be pressed now (design review §1.5): grey icon at half alpha, the button
-- disabled (not hidden, so nothing next to it moves).
function W.setEnabled(b, on)
    b.disabled = not on
    if on then if b.Enable then b:Enable() end else if b.Disable then b:Disable() end end
    if b.tex then
        if b.tex.SetDesaturated then b.tex:SetDesaturated(not on) end
        b.tex:SetAlpha(on and 1 or 0.5)
    end
    if b.label then b.label:SetAlpha(on and 1 or 0.5) end
end

---------------------------------------------------------------------------
-- A card of icons, arrows and numbers (R-17.13). rows = { { token, ... }, ... };
-- token = { icon = GameIcons key, text = "2-4 characters or a number" } or
-- { arrow = true } or { gap = px }. Laid out left to right by measured width.
-- A menu-level frame: ESC and a click outside close it.
---------------------------------------------------------------------------

W.CARD_ROW, W.CARD_ICON, W.CARD_ARROW, W.CARD_PAD = 44, 28, 20, 20

function W.flowCard(name, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("TOOLTIP")
    if f.SetFrameLevel then f:SetFrameLevel(60) end
    ns.makeOpaque(f, 0)
    f:EnableMouse(true)
    ns.escRegister(f, ns.ESC_LEVEL.grid)
    f.title = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT))
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", W.CARD_PAD, -14)
    f.title:SetText(title or "")
    f.icons, f.texts, f.arrows = {}, {}, {}
    f:Hide()
    return f
end

function W.drawFlow(f, rows)
    local ni, nt, na = 0, 0, 0
    local function icon()
        ni = ni + 1
        local t = f.icons[ni]
        if not t then t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(W.CARD_ICON, W.CARD_ICON); f.icons[ni] = t end
        return t
    end
    local function text()
        nt = nt + 1
        local t = f.texts[nt]
        if not t then t = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)); f.texts[nt] = t end
        return t
    end
    local function arrow()
        na = na + 1
        local t = f.arrows[na]
        if not t then t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(W.CARD_ARROW, W.CARD_ARROW); f.arrows[na] = t end
        G().set(t, "arrow")
        return t
    end
    local maxX = 0
    local top = -52
    for r, row in ipairs(rows) do
        local x = W.CARD_PAD
        local y = top - (r - 1) * W.CARD_ROW
        for _, tok in ipairs(row) do
            if tok.gap then x = x + tok.gap
            elseif tok.arrow then
                local a = arrow()
                a:ClearAllPoints(); a:SetPoint("TOPLEFT", f, "TOPLEFT", x + 6, y - (W.CARD_ICON - W.CARD_ARROW) / 2)
                a:Show()
                x = x + W.CARD_ARROW + 12
            else
                if tok.icon then
                    local t = icon()
                    G().set(t, tok.icon)
                    if t.SetDesaturated then t:SetDesaturated(tok.grey == true) end
                    t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
                    t:Show()
                    x = x + W.CARD_ICON + 4
                end
                if tok.text and tok.text ~= "" then
                    local fs = text()
                    fs:SetText(tok.text)
                    local c = tok.color and W.COLOR[tok.color] or W.COLOR.white
                    fs:SetTextColor(c[1], c[2], c[3])
                    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 6)
                    fs:Show()
                    x = x + ns.measure(fs) + 4
                end
                x = x + 6
            end
        end
        maxX = math.max(maxX, x)
    end
    for k = ni + 1, #f.icons do f.icons[k]:Hide() end
    for k = nt + 1, #f.texts do f.texts[k]:Hide() end
    for k = na + 1, #f.arrows do f.arrows[k]:Hide() end
    f:SetSize(math.max(maxX + W.CARD_PAD, ns.measure(f.title) + 2 * W.CARD_PAD), -top + #rows * W.CARD_ROW + W.CARD_PAD)
    return f
end

---------------------------------------------------------------------------
-- GF-002-J (owner 0.14.0): every sub-window and picker has an X in its top right
-- corner (as well as ESC and a click outside).
---------------------------------------------------------------------------

W.CLOSE_SIZE = 28
function W.closeButton(f, onClose)
    if f.gfClose then return f.gfClose end
    -- GF-UI-D: the theme's X (the letter in the game font, gold under the mouse).
    local b = ns.Theme.closeButton(f, onClose)
    b.infoOnly = false
    f.gfClose = b
    return b
end

---------------------------------------------------------------------------
-- GF-002-J: a small confirmation (刪除, 清除): a short noun phrase, 確定 / 取消, the X.
-- A menu-level frame: ESC and a click outside cancel it.
---------------------------------------------------------------------------

W.CONFIRM_NAME = "GreenFangToolkit_Confirm"
local confirm
-- GF-012-B: onNo (optional) runs when the box closes without 確定 (取消, the X,
-- ESC, or another confirm taking its place); callers without it are unchanged.
function W.confirm(text, onYes, onNo)
    if not confirm then
        local f = CreateFrame("Frame", W.CONFIRM_NAME, UIParent)
        f:SetFrameStrata("TOOLTIP")
        if f.SetFrameLevel then f:SetFrameLevel(70) end
        ns.makeOpaque(f, 0)
        f:EnableMouse(true)
        ns.escRegister(f, ns.ESC_LEVEL.grid)
        f.text = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -20)
        f.yes = ns.OrdersUI.textButton(f, "確定", function()
            local fn = f.onYes
            f.onYes, f.onNo = nil, nil
            f:Hide()
            if fn then fn() end
        end, 90)
        f.no = ns.OrdersUI.textButton(f, "取消", function() f.onYes = nil; f:Hide() end, 90)
        W.closeButton(f)
        local function closed()
            local fn = f.onNo
            f.onYes, f.onNo = nil, nil
            if fn then fn() end
        end
        if f.HookScript then f:HookScript("OnHide", closed) else f:SetScript("OnHide", closed) end
        f:Hide()
        confirm = f
    end
    local f = confirm
    if f:IsShown() and f.onNo then local old = f.onNo; f.onNo = nil; pcall(old) end
    f.text:SetText(text or "")
    f.onYes, f.onNo = onYes, onNo
    local w = math.max(300, ns.labelWidth(text or "") + 40 + W.CLOSE_SIZE)
    f:SetSize(w, 116)
    f.yes:ClearAllPoints(); f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    f.no:ClearAllPoints(); f.no:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20 - 90 - 12, 16)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:Show()
    return f
end
function W.confirmFrame() return confirm end

---------------------------------------------------------------------------
-- GF-UI-E: the item row (spec v2.0 §4.2, appendix A §7.3). The game's item
-- icon, square and cropped, 36 px; the localised name; a count on the right.
-- Not cached yet: the question mark and 「物品資料載入中」, never a guessed
-- name or the item ID. Redrawn on GET_ITEM_INFO_RECEIVED only.
---------------------------------------------------------------------------

W.ITEM_ICON, W.ITEM_ROW_H = 36, 44
W.ITEM_PLACEHOLDER = { "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\RaidFrame\\ReadyCheck-Waiting" }
W.TEXT = {
    mine = "你的狀態：", ticket = "冒險單：", -- GF-UI-P: the checklist's first lines
    itemLoading = "物品資料載入中",
    itemMissing = "找不到這個物品", -- GF-FIX-F: the server said no such item
    empty = "目前沒有資料", loading = "載入中", unknown = "狀態未知", stale = "資料過期", error = "暫時無法讀取",
    fresh = { recent = "近期", earlier = "稍早", stale = "過期", unknown = "未知" },
}

local function fnc(x) return type(x) == "function" end
local function try(f, ...)
    if not fnc(f) then return nil end
    local res = { pcall(f, ...) }
    if not res[1] then return nil end
    return unpack(res, 2, 11)
end

-- GF-FIX-F (review 中-16, 中-17): the toolkit's item data requests, in one
-- place. ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED come for every item
-- the game loads (auction house, other AddOns); the pages act only on items
-- asked for here. One request per item until it is answered (again after
-- REQUEST_AGAIN seconds without an answer); an item the server called
-- missing (success = false) is never asked again this session.
W.REQUEST_AGAIN = 30
local requested, failedItems = {}, {}
local requestCount = 0
W.failedItems = failedItems
-- Asks the client for itemID (or notes that the client is already loading
-- it: a GetItemInfo miss does that by itself). false for a missing item.
function W.requestItem(itemID, noCall)
    local id = tonumber(itemID)
    if not id or failedItems[id] then return false end
    local t = ns.now and ns.now() or 0
    local at = requested[id]
    if at and t - at < W.REQUEST_AGAIN then return true end
    requested[id] = t
    if noCall then return true end
    local C = type(C_Item) == "table" and C_Item or nil
    if C and fnc(C.RequestLoadItemDataByID) then
        requestCount = requestCount + 1
        pcall(C.RequestLoadItemDataByID, id)
    end
    return true
end
function W.itemRequested(itemID) return requested[tonumber(itemID) or 0] ~= nil end
function W.itemFailed(itemID) return failedItems[tonumber(itemID) or 0] == true end
function W.requestCount() return requestCount end
function W.resetRequests()
    for k in pairs(requested) do requested[k] = nil end
    for k in pairs(failedItems) do failedItems[k] = nil end
    requestCount = 0
end
-- Listeners for answers to our own requests only: fn(itemID, success).
local itemListeners = {}
function W.onItemAnswer(fn) itemListeners[#itemListeners + 1] = fn end

-- What the client knows about an item now. Asks the client to load it
-- (W.requestItem, once) when the name is not there yet; failed = the server
-- said there is no such item.
function W.itemInfo(itemID)
    local id = tonumber(itemID)
    local info = { id = id, loaded = false }
    if not id then return info end
    local C = type(C_Item) == "table" and C_Item or {}
    -- GF-FIX-F: a missing item is not read again (a GetItemInfo miss asks the server).
    if failedItems[id] then
        info.failed, info.icon = true, try(C.GetItemIconByID, id)
        return info
    end
    local name, link, quality, _, _, _, _, _, _, icon = try(ns.itemInfoFn(), id) -- GF-009-13 fix: no global GetItemInfo on Forever
    name = name or try(C.GetItemNameByID, id)
    icon = icon or try(C.GetItemIconByID, id) or try(GetItemIcon, id)
    if type(name) == "string" and name ~= "" then
        info.name, info.loaded = name, true
    elseif failedItems[id] then
        info.failed = true
    else
        W.requestItem(id)
    end
    info.icon = icon
    info.link = type(link) == "string" and link or nil
    info.quality = tonumber(quality)
    return info
end

local waiting = setmetatable({}, { __mode = "k" }) -- row -> itemID still loading
local itemEvents = CreateFrame("Frame")
pcall(itemEvents.RegisterEvent, itemEvents, "GET_ITEM_INFO_RECEIVED")
pcall(itemEvents.RegisterEvent, itemEvents, "ITEM_DATA_LOAD_RESULT") -- GF-009-13 fix: RequestLoadItemDataByID's answer
-- GF-FIX-F (中-16): an answer for an item nobody here asked for and no row
-- waits for is dropped at once (no redraw, no page work).
local itemEventStats = { seen = 0, ours = 0 }
W.itemEventStats = itemEventStats
function W.itemAnswer(itemID, success)
    local id = tonumber(itemID)
    itemEventStats.seen = itemEventStats.seen + 1
    local list = {}
    for row, wanted in pairs(waiting) do
        if id == nil or wanted == id then list[#list + 1] = row end
    end
    if id and success ~= false then failedItems[id] = nil end
    local ours = id ~= nil and requested[id] ~= nil
    if not ours and #list == 0 then return false end
    itemEventStats.ours = itemEventStats.ours + 1
    if id then
        requested[id] = nil
        if success == false then failedItems[id] = true end
    end
    for _, row in ipairs(list) do row.redraw() end
    if id then
        for _, fn in ipairs(itemListeners) do pcall(fn, id, success) end
    end
    return true
end
itemEvents:SetScript("OnEvent", function(_, _, itemID, success) W.itemAnswer(itemID, success) end)
W.itemEventFrame = itemEvents
function W.itemsWaiting()
    local n = 0
    for _ in pairs(waiting) do n = n + 1 end
    return n
end

local function setFirst(tex, list)
    for _, path in ipairs(list) do
        if ns.Icons.set(tex, path) then return path end
    end
    return nil
end

function W.itemTooltip(owner, info)
    if not (owner and info) then return end
    W.rowTip(owner) -- GF-UI-P: next to the mouse, beside the row
    local shown = false
    if info.link and fnc(GameTooltip.SetHyperlink) then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, info.link) end
    if not shown and info.loaded and info.id and fnc(GameTooltip.SetItemByID) then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, info.id)
    end
    if not shown then GameTooltip:AddLine(info.name or W.TEXT.itemLoading, 1, 1, 1) end
    GameTooltip:Show()
end

function W.itemRow(parent, w, h)
    h = h or W.ITEM_ROW_H
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(w, h)
    row.gfWidget = "itemRow"
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    if ns.stripe then ns.stripe(row.bg, 1) end
    row.gfHover = ns.Theme.fill(row, ns.Theme.C.hover, "HIGHLIGHT")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(W.ITEM_ICON, W.ITEM_ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    -- A 1 px grey line round the icon (the theme's line colour).
    local edges = {}
    local function edge(p1, rel1, x1, y1, p2, rel2, x2, y2, horizontal)
        local t = row:CreateTexture(nil, "BORDER")
        t:SetPoint(p1, row.icon, rel1, x1, y1)
        t:SetPoint(p2, row.icon, rel2, x2, y2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        ns.Theme.color(t, ns.Theme.C.line)
        edges[#edges + 1] = t
    end
    edge("BOTTOMLEFT", "TOPLEFT", -1, 0, "BOTTOMRIGHT", "TOPRIGHT", 1, 0, true)
    edge("TOPLEFT", "BOTTOMLEFT", -1, 0, "TOPRIGHT", "BOTTOMRIGHT", 1, 0, true)
    edge("TOPRIGHT", "TOPLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMLEFT", 0, 0, false)
    edge("TOPLEFT", "TOPRIGHT", 0, 0, "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, false)
    row.iconEdges = edges
    local textX = 6 + W.ITEM_ICON + 10
    row.textX = textX
    row.right = CreateFrame("Frame", nil, row)
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, 0)
    row.right:SetSize(1, h)
    row.rightW = 1 -- kept here: what GetWidth gives depends on the anchors
    row.count = ns.freeText(row:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    row.count:SetPoint("RIGHT", row.right, "LEFT", -10, 0)
    if row.count.SetJustifyH then row.count:SetJustifyH("RIGHT") end
    row.name = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.sub = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.sub:SetJustifyH("LEFT")
    if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end
    local mc = W.COLOR.muted
    row.sub:SetTextColor(mc[1], mc[2], mc[3])
    row.sub:Hide()

    -- The name (and the second line) between the icon and the count / row.right.
    function row.layout()
        local rightW = row.rightW or 0
        local countW = row.count:IsShown() and ns.measure(row.count) or 0
        local nameW = math.max(40, w - textX - rightW - countW - 26)
        local two = row.sub:IsShown()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", textX, two and 9 or 0)
        row.name:SetWidth(nameW)
        row.sub:ClearAllPoints()
        row.sub:SetPoint("LEFT", row, "LEFT", textX, -11)
        row.sub:SetWidth(nameW)
        row.nameWidth = nameW
    end
    -- Room on the right for the caller's buttons (聯絡); the name is cut before it.
    function row.setRightWidth(px)
        row.rightW = math.max(1, px or 1)
        row.right:SetWidth(row.rightW)
        row.layout()
    end

    function row.redraw()
        local info = W.itemInfo(row.itemID)
        row.info = info
        local path = info.icon and ns.Icons.set(row.icon, info.icon) and info.icon or nil
        row.placeholder = path == nil
        if row.placeholder then path = setFirst(row.icon, W.ITEM_PLACEHOLDER) end
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if row.icon.SetDesaturated then row.icon:SetDesaturated(row.placeholder) end
        row.iconPath = path
        row.loading = not info.loaded
        -- GF-UI-N: opts.name (row.set) is shown instead of the item's own name.
        row.name:SetText(row.fixedName or (info.loaded and info.name) or (info.failed and W.TEXT.itemMissing) or W.TEXT.itemLoading)
        local col = (info.loaded or row.fixedName) and W.COLOR.white or W.COLOR.muted
        row.name:SetTextColor(col[1], col[2], col[3])
        if info.loaded or info.failed then waiting[row] = nil else waiting[row] = info.id end
        row.layout()
    end

    -- itemID, count (a number or a short text such as 「缺 1」), opts:
    -- { sub = second line, countColor = W.COLOR key, stripe = list index,
    --   name = a text shown instead of the item's name (GF-UI-N) }.
    function row.set(itemID, count, opts)
        opts = opts or {}
        row.fixedName = (opts.name and opts.name ~= "") and opts.name or nil
        row.itemID = tonumber(itemID)
        if not row.itemID then waiting[row] = nil; row.info = nil; row:Hide(); return row end
        if count ~= nil and count ~= "" then
            row.count:SetText(tostring(count)); row.count:Show()
            local cc = W.COLOR[opts.countColor or "white"] or W.COLOR.white
            row.count:SetTextColor(cc[1], cc[2], cc[3])
        else
            row.count:SetText(""); row.count:Hide()
        end
        if opts.sub and opts.sub ~= "" then row.sub:SetText(opts.sub); row.sub:Show()
        else row.sub:SetText(""); row.sub:Hide() end
        if ns.stripe then ns.stripe(row.bg, opts.stripe or 1) end
        row.redraw()
        row:Show()
        return row
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) W.itemTooltip(self, self.info) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.Theme.guardHover(row) -- lights up only when the caller gives it an OnClick
    row.layout()
    return row
end

---------------------------------------------------------------------------
-- GF-UI-E: 空／載入／未知／過期／錯誤 in place of a list: the game's icon (32)
-- and words, the detail line under it in grey. Never a colour alone.
---------------------------------------------------------------------------

W.STATE_KINDS = { "empty", "loading", "unknown", "stale", "error" }
W.STATE_ICON = {
    empty = { "Interface\\Icons\\INV_Misc_Bag_08", "Interface\\Icons\\INV_Box_01" },
    loading = { "Interface\\RaidFrame\\ReadyCheck-Waiting", "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    unknown = { "Interface\\Icons\\INV_Misc_QuestionMark" },
    stale = { "Interface\\Icons\\Spell_Holy_BorrowedTime", "Interface\\Icons\\INV_Misc_PocketWatch_02" },
    error = { "Interface\\RaidFrame\\ReadyCheck-NotReady", "Interface\\Icons\\INV_Misc_QuestionMark" },
}
W.STATE_PANEL_ICON = 32

function W.statePanel(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 500, h or 100)
    f.gfWidget = "statePanel"
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(W.STATE_PANEL_ICON, W.STATE_PANEL_ICON)
    f.icon:SetPoint("TOP", f, "TOP", 0, -8)
    f.text = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    f.text:SetPoint("TOP", f.icon, "BOTTOM", 0, -8)
    f.detail = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    f.detail:SetPoint("TOP", f.text, "BOTTOM", 0, -6)
    local mc = W.COLOR.muted
    f.detail:SetTextColor(mc[1], mc[2], mc[3])
    -- kind: one of W.STATE_KINDS (nil hides it); text: the main words (else
    -- W.TEXT[kind]); detail: an optional second line.
    function f.set(kind, text, detail)
        f.kind = kind
        if not kind then f:Hide(); return f end
        f.iconPath = setFirst(f.icon, W.STATE_ICON[kind] or W.STATE_ICON.unknown)
        local square = f.iconPath and f.iconPath:find("\\Icons\\", 1, true)
        if square then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else f.icon:SetTexCoord(0, 1, 0, 1) end
        f.text:SetText(text or W.TEXT[kind] or W.TEXT.unknown)
        local col = kind == "error" and W.COLOR.warn or kind == "empty" and W.COLOR.white or W.COLOR.muted
        f.text:SetTextColor(col[1], col[2], col[3])
        if detail and detail ~= "" then f.detail:SetText(detail); f.detail:Show() else f.detail:SetText(""); f.detail:Hide() end
        f:Show()
        return f
    end
    f:Hide()
    return f
end

-- 近期 / 稍早 / 過期 / 未知 for a time (spec §4.2: no timestamps in lists).
W.FRESH_RECENT, W.FRESH_STALE = 6 * 3600, 3 * 86400
function W.freshness(at, now, opts)
    opts = opts or {}
    local t = tonumber(at)
    now = tonumber(now) or (type(time) == "function" and time()) or 0
    local key
    if not t or t <= 0 or t > now + 300 then key = "unknown"
    elseif now - t <= (opts.recent or W.FRESH_RECENT) then key = "recent"
    elseif now - t <= (opts.stale or W.FRESH_STALE) then key = "earlier"
    else key = "stale" end
    local color = key == "recent" and W.COLOR.good or key == "earlier" and W.COLOR.white or W.COLOR.disabled
    return key, W.TEXT.fresh[key], color
end

---------------------------------------------------------------------------
-- GF-UI-E: a sub-tab row inside a page. items = { { key, text, w? } }. The
-- chosen tab is gold and cannot be pressed (so it never lights up); a hidden
-- tab leaves no gap. onSelect(key) after a click.
---------------------------------------------------------------------------

function W.subTabs(parent, items, x, y, onSelect)
    local strip = { buttons = {}, key = nil, x = x or 0, y = y or 0 }
    for _, it in ipairs(items or {}) do
        local w = it.w or math.max(96, ns.labelWidth(it.text) + 28)
        local b = ns.Theme.button(parent, it.text, w, ns.BUTTON_H)
        b.key, b.gfShown, b.gfUsable, b.gfW = it.key, true, true, w
        local key = it.key
        b:SetScript("OnClick", function()
            strip.select(key)
            if onSelect then onSelect(key) end
        end)
        strip.buttons[#strip.buttons + 1] = b
    end
    function strip.layout()
        local cx = strip.x
        for _, b in ipairs(strip.buttons) do
            if b.gfShown then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, strip.y)
                b:Show()
                cx = cx + b.gfW + 8
            else
                b:Hide()
            end
        end
    end
    function strip.select(key)
        strip.key = key
        for _, b in ipairs(strip.buttons) do
            local chosen = b.key == key
            ns.Theme.setSelected(b, chosen)
            if b.SetEnabled then b:SetEnabled(b.gfUsable and not chosen) end
        end
    end
    function strip.button(key)
        for _, b in ipairs(strip.buttons) do if b.key == key then return b end end
    end
    function strip.setEnabled(key, on)
        local b = strip.button(key)
        if not b then return end
        b.gfUsable = on and true or false
        strip.select(strip.key)
    end
    function strip.setShown(key, on)
        local b = strip.button(key)
        if not b then return end
        b.gfShown = on and true or false
        strip.layout()
    end
    strip.layout()
    return strip
end

---------------------------------------------------------------------------
-- GF-UI-G: a drop-down inside a form (時段的日期、開始時間、預計長度). The
-- button shows the chosen item and the game's drop-down arrow; a click opens
-- an opaque list (the form colour) of at most W.DROP_ROWS lines that scrolls
-- with the mouse wheel or its ▲ ▼; it opens upwards when there is no room
-- below (near the bottom of the screen) and is kept on the screen. ESC, a
-- click outside, a pick, or hiding the form close it. A disabled item is
-- dimmer and never lights up.
--
--   local dd = ns.Widgets.dropdown(parent, 140, function(value) ... end)
--   dd.setItems({ { value = 0, text = "今天 11/25" }, { value = 1, text = "明天 11/26", disabled = true } })
--   dd.setValue(1)           -- the button text follows the items
--   dd.open() / dd.close() / dd.isOpen() / dd.choose(value) / dd.scroll(n)
--   dd.shownTexts()          -- the lines in view (scripts and tests)
---------------------------------------------------------------------------

W.DROP_ROW, W.DROP_ROWS, W.DROP_PAD, W.DROP_BAR = 28, 8, 4, 22

local function dropScale(b)
    local s = ns.num((b.GetEffectiveScale and b:GetEffectiveScale())) or 1
    local u = ns.num((UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())) or 1
    if s <= 0 or u <= 0 then return 1 end
    return s / u
end

function W.dropdown(parent, w, onChoose)
    local T = ns.Theme
    local b = T.button(parent, nil, w, ns.BUTTON_H)
    b.gfWidget = "dropdown"
    b.gfWidth = w
    if ns.dropArrow then ns.dropArrow(b) end
    local dd = b
    dd.items, dd.value, dd.offset, dd.onChoose = {}, nil, 0, onChoose

    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("TOOLTIP") -- above the click-outside blocker and the form
    if list.SetFrameLevel then list:SetFrameLevel(110) end
    T.formPanel(list)
    list:EnableMouse(true)
    if list.EnableMouseWheel then list:EnableMouseWheel(true) end
    if list.SetClampedToScreen then list:SetClampedToScreen(true) end
    list:Hide()
    list.rows = {}
    list.gfDropdown = dd
    dd.list = list
    ns.escRegister(list, ns.ESC_LEVEL.menu)

    local function row(i)
        local r = list.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, list)
        r:SetHeight(W.DROP_ROW)
        r:SetPoint("TOPLEFT", list, "TOPLEFT", W.DROP_PAD, -W.DROP_PAD - (i - 1) * W.DROP_ROW)
        r.sel = T.fill(r, T.C.selFill, "BACKGROUND")
        r.selBar = r:CreateTexture(nil, "BORDER")
        r.selBar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
        r.selBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
        r.selBar:SetWidth(3)
        T.color(r.selBar, T.C.selLine)
        r.gfHover = T.fill(r, T.C.hover, "HIGHLIGHT")
        r.text = ns.freeText(r:CreateFontString(nil, "ARTWORK", T.FONT.button))
        r.text:SetPoint("LEFT", r, "LEFT", 10, 0)
        r.text:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self) if self.item then dd.choose(self.item.value) end end)
        T.guardHover(r)
        list.rows[i] = r
        return r
    end
    local function arrowButton(key, name, step)
        local a = T.button(list, nil, W.DROP_BAR, W.DROP_BAR)
        a.tex = a:CreateTexture(nil, "ARTWORK"); a.tex:SetAllPoints()
        G().set(a.tex, key)
        a.fieldNamed = name
        a:SetScript("OnClick", function() dd.scroll(step) end)
        return a
    end
    list.up = arrowButton("sort_up", "上", -(W.DROP_ROWS - 1))
    list.down = arrowButton("sort_down", "下", W.DROP_ROWS - 1)
    list:SetScript("OnMouseWheel", function(_, delta) dd.scroll(-(tonumber(delta) or 0) * 3) end)

    local function indexOf(value)
        for i, it in ipairs(dd.items) do if it.value == value then return i end end
        return nil
    end
    function dd.textFor(value)
        local i = indexOf(value)
        return i and dd.items[i].text or (dd.emptyText or "")
    end
    function dd.refreshText() b:SetText(dd.textFor(dd.value)) end
    function dd.setItems(items)
        dd.items = items or {}
        dd.refreshText()
        if list:IsShown() then dd.draw() end
    end
    function dd.setValue(value)
        dd.value = value
        dd.refreshText()
        if list:IsShown() then dd.draw() end
    end
    function dd.maxOffset() return math.max(0, #dd.items - W.DROP_ROWS) end
    function dd.scroll(n)
        dd.offset = math.max(0, math.min(dd.maxOffset(), dd.offset + (n or 0)))
        dd.draw()
        return dd.offset
    end
    -- The rows in view, the chosen one marked; ▲ ▼ only when the list is longer.
    function dd.draw()
        local n = math.min(#dd.items, W.DROP_ROWS)
        local long = #dd.items > W.DROP_ROWS
        local rowW = w
        for _, it in ipairs(dd.items) do rowW = math.max(rowW, ns.labelWidth(it.text) + 24) end
        for i = 1, n do
            local it = dd.items[dd.offset + i]
            local r = row(i)
            r.item = it
            r:SetWidth(rowW)
            r.text:SetText(it.text)
            local chosen = it.value == dd.value
            r.chosen = chosen
            if chosen then r.sel:Show(); r.selBar:Show() else r.sel:Hide(); r.selBar:Hide() end
            r.text:SetFontObject(it.disabled and T.FONT.off or (chosen and T.FONT.chosen or T.FONT.button))
            r.disabled = it.disabled == true
            if r.SetEnabled then r:SetEnabled(not it.disabled) end
            r:Show()
        end
        for i = n + 1, #list.rows do list.rows[i]:Hide(); list.rows[i].item = nil end
        if long then
            list.up:ClearAllPoints(); list.up:SetPoint("TOPRIGHT", list, "TOPRIGHT", -W.DROP_PAD, -W.DROP_PAD)
            list.down:ClearAllPoints(); list.down:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -W.DROP_PAD, W.DROP_PAD)
            list.up:Show(); list.down:Show()
            list.up:SetEnabled(dd.offset > 0)
            list.down:SetEnabled(dd.offset < dd.maxOffset())
        else
            list.up:Hide(); list.down:Hide()
        end
        list:SetSize(rowW + 2 * W.DROP_PAD + (long and (W.DROP_BAR + 4) or 0), math.max(1, n) * W.DROP_ROW + 2 * W.DROP_PAD)
    end
    function dd.isOpen() return list:IsShown() end
    function dd.close() if list:IsShown() then list:Hide() end end
    -- Below the button, or above it when the screen ends first (dd.openUp).
    function dd.place()
        local h = math.min(#dd.items, W.DROP_ROWS) * W.DROP_ROW + 2 * W.DROP_PAD
        local b = dd.anchor or b -- GF-012-C: dd.openAt(frame) opens it under another frame
        local scale = dropScale(b)
        if list.SetScale then list:SetScale(scale) end
        local bottom = ns.num((b.GetBottom and b:GetBottom()))
        local top = ns.num((b.GetTop and b:GetTop()))
        local screenH = ns.num((UIParent and UIParent.GetTop and UIParent:GetTop())) or 0
        local below = bottom and bottom * scale or nil
        local above = (top and screenH > 0) and (screenH - top * scale) or nil
        list:ClearAllPoints()
        dd.openUp = below ~= nil and below < (h + 8) * scale and (above == nil or above > below)
        if dd.openUp then list:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 2)
        else list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2) end
    end
    function dd.open()
        if ns.closeMenus then ns.closeMenus() end
        local i = indexOf(dd.value) or 1
        dd.offset = math.max(0, math.min(dd.maxOffset(), i - math.floor(W.DROP_ROWS / 2)))
        dd.draw()
        dd.place()
        list:Show()
        return list
    end
    -- GF-012-C: the same list under another frame (臨時黑箱's 聯絡: one
    -- shared menu for every row; its own button stays hidden).
    function dd.openAt(frame)
        dd.anchor = frame
        local l = dd.open()
        dd.anchor = nil
        return l
    end
    function dd.toggle() if list:IsShown() then dd.close() else dd.open() end end
    -- A pick: false for a disabled or unknown item (nothing changes).
    function dd.choose(value)
        local i = indexOf(value)
        if not i or dd.items[i].disabled then return false end
        dd.value = value
        dd.refreshText()
        dd.close()
        if dd.onChoose then dd.onChoose(value) end
        return true
    end
    function dd.shownTexts()
        local out = {}
        for _, r in ipairs(list.rows) do if r:IsShown() and r.item then out[#out + 1] = r.item.text end end
        return out
    end
    b:SetScript("OnClick", function() dd.toggle() end)
    b:HookScript("OnHide", function() dd.close() end)
    return dd
end

---------------------------------------------------------------------------
-- GF-UI-P (owner 2026-11-28: 「提示離滑鼠很遠、蓋住右邊的按鈕」): one place
-- for every list row's tooltip. W.rowTip(owner) sets GameTooltip's owner and
-- anchors it next to the row the mouse is on: one edge at the cursor's x (it
-- grows to the right on the left half of the screen, to the left on the right
-- half) and just above the row on the lower half of the screen, just below it
-- on the upper half, so it never covers the row and its buttons, and turns
-- around near a screen edge. The cursor is read once, when the mouse enters:
-- nothing runs every frame. Then add lines and call GameTooltip:Show() as before.
--   row:SetScript("OnEnter", function(self) ns.Widgets.rowTip(self); GameTooltip:AddLine("…"); GameTooltip:Show() end)
---------------------------------------------------------------------------

W.TIP_GAP = 2       -- between the row and the tooltip
W.TIP_CURSOR = 12   -- the tooltip's edge this far beside the cursor's tip

local function numOf(o, method)
    local f = o and o[method]
    if type(f) ~= "function" then return nil end
    local okv, v = pcall(f, o)
    return okv and ns.num(v) or nil
end

-- Where the tooltip goes: { point, relPoint, x, y, above, right }.
function W.tipPlace(owner)
    local gap = W.TIP_GAP
    local fallback = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -gap, above = false, right = true }
    if not owner then return fallback end
    local uw, uh = numOf(UIParent, "GetWidth"), numOf(UIParent, "GetHeight")
    local l, r = numOf(owner, "GetLeft"), numOf(owner, "GetRight")
    local t, b = numOf(owner, "GetTop"), numOf(owner, "GetBottom")
    if not (uw and uh and l and r and t and b and uw >= 300 and uh >= 300 and r > l) then return fallback end
    local s = numOf(owner, "GetEffectiveScale") or 1
    local u = numOf(UIParent, "GetEffectiveScale") or 1
    local tt = (GameTooltip and numOf(GameTooltip, "GetEffectiveScale")) or u
    if s <= 0 or u <= 0 or tt <= 0 then return fallback end
    -- The row in UIParent's units; the cursor (screen pixels) in the same units.
    local L, R, T, B = l * s / u, r * s / u, t * s / u, b * s / u
    local cx
    if type(GetCursorPosition) == "function" then
        local okc, x = pcall(GetCursorPosition)
        cx = okc and ns.num(x) or nil
    end
    cx = cx and (cx / u) or (L + R) / 2
    if cx < L then cx = L elseif cx > R then cx = R end
    local above = (T + B) / 2 < uh / 2   -- lower half of the screen: above the row
    local right = cx <= uw / 2           -- left half: the tooltip grows to the right
    local vp, ownerV = above and "BOTTOM" or "TOP", above and "TOP" or "BOTTOM"
    local x = (cx - L) * u / tt + (right and W.TIP_CURSOR or -W.TIP_CURSOR)
    return { point = vp .. (right and "LEFT" or "RIGHT"), relPoint = ownerV .. "LEFT", x = x,
        y = above and gap or -gap, above = above, right = right }
end

function W.rowTip(owner)
    if not (GameTooltip and owner) then return nil end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local p = W.tipPlace(owner)
    GameTooltip:SetPoint(p.point, owner, p.relPoint, p.x, p.y)
    if GameTooltip.SetClampedToScreen then GameTooltip:SetClampedToScreen(true) end
    owner.tipPoint = p.point
    return p
end

---------------------------------------------------------------------------
-- GF-UI-P (owner 2026-11-28: 「所有可以捲動的清單都要看得到捲動條」): one
-- scroll bar for the lists that refill the same rows (臨時黑箱 庫存 / 申領 /
-- 保管人, 公會銀行, 調貨所, 通知). The game's own art, as on 業務大廳 (the
-- game's scroll frame): an up arrow, the track with the knob, a down arrow.
--   local bar = ns.Widgets.scrollBar(parent, height, function(offset) myOffset = offset; redraw() end)
--   bar:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)   -- W.SCROLL_W wide, right of the rows
--   bar.sync(offset, total, visible)                    -- at the end of every draw
-- A list within one page: the arrows and the knob go grey and do nothing
-- (as the game's scroll frames); the bar keeps its own column beside the
-- rows, never on them. The wheel stays where each list had it.
---------------------------------------------------------------------------

W.SCROLL_W = 16
W.SCROLL_ARROW = 16
W.SCROLL_ART = "Interface\\Buttons\\UI-ScrollBar-Scroll"
W.SCROLL_KNOB = "Interface\\Buttons\\UI-ScrollBar-Knob"
W.SCROLL_DIM = 0.35 -- the knob of a list that does not scroll
W.SCROLL_GAP = 6    -- between the rows' right edge and the bar (as the game's scroll frame)

local function scrollArrow(f, dir)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(W.SCROLL_ARROW, W.SCROLL_ARROW)
    local base = W.SCROLL_ART .. dir .. "Button-"
    if b.SetNormalTexture then
        b:SetNormalTexture(base .. "Up"); b:SetPushedTexture(base .. "Down")
        b:SetDisabledTexture(base .. "Disabled"); b:SetHighlightTexture(base .. "Highlight")
    end
    b.gfDir = dir
    return b
end

local function arrowEnabled(b, on)
    b.gfEnabled = on and true or false
    if on then if b.Enable then b:Enable() end elseif b.Disable then b:Disable() end
end

function W.scrollBar(parent, height, onScroll)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(W.SCROLL_W, height or 200)
    f.gfScrollBar = true
    f.offset, f.total, f.visible = 0, 0, 0
    f.up = scrollArrow(f, "Up")
    f.up:SetPoint("TOP", f, "TOP", 0, 0)
    f.down = scrollArrow(f, "Down")
    f.down:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    local bar = CreateFrame("Slider", nil, f)
    f.bar = bar
    bar:SetPoint("TOP", f.up, "BOTTOM", 0, 0)
    bar:SetPoint("BOTTOM", f.down, "TOP", 0, 0)
    bar:SetWidth(W.SCROLL_W)
    if bar.SetOrientation then bar:SetOrientation("VERTICAL") end
    if bar.SetThumbTexture then bar:SetThumbTexture(W.SCROLL_KNOB) end
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture() or nil
    if type(thumb) == "table" or type(thumb) == "userdata" then
        if thumb.SetSize then thumb:SetSize(18, 24) end
        if thumb.SetTexCoord then thumb:SetTexCoord(0.2, 0.8, 0.125, 0.875) end
        f.thumb = thumb
    end
    if bar.SetValueStep then bar:SetValueStep(1) end
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    f.track = bar:CreateTexture(nil, "BACKGROUND")
    f.track:SetAllPoints()
    f.track:SetColorTexture(0, 0, 0, 0.35)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    local function go(o)
        local max = math.max(0, (f.total or 0) - (f.visible or 0))
        o = math.max(0, math.min(max, math.floor((tonumber(o) or 0) + 0.5)))
        if o == f.offset then return false end
        f.offset = o
        if onScroll then onScroll(o) end
        return true
    end
    f.scrollTo = go
    function f.scrollBy(n) return go((f.offset or 0) + (tonumber(n) or 0)) end
    bar:SetScript("OnValueChanged", function(_, value)
        if f.syncing then return end
        go(value)
    end)
    f.up:SetScript("OnClick", function() f.scrollBy(-1) end)
    f.down:SetScript("OnClick", function() f.scrollBy(1) end)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function(_, delta) f.scrollBy(-(tonumber(delta) or 0)) end)
    function f.setHeight(h) f:SetHeight(h) end
    -- What the list shows now: the first row (0-based), how many rows, how many fit.
    function f.sync(offset, total, visible)
        f.syncing = true
        f.offset, f.total, f.visible = tonumber(offset) or 0, tonumber(total) or 0, tonumber(visible) or 0
        local max = math.max(0, f.total - f.visible)
        bar:SetMinMaxValues(0, max)
        bar:SetValue(math.min(f.offset, max))
        f.scrollable = max > 0
        arrowEnabled(f.up, f.scrollable and f.offset > 0)
        arrowEnabled(f.down, f.scrollable and f.offset < max)
        if bar.EnableMouse then bar:EnableMouse(f.scrollable) end
        if f.thumb and f.thumb.SetAlpha then f.thumb:SetAlpha(f.scrollable and 1 or W.SCROLL_DIM) end
        f.syncing = false
    end
    return f
end
