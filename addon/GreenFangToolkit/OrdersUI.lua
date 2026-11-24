-- OrdersUI (GF-006-B, spec §10): the 「訂單」 page, the order popup, the fee
-- popup, the strip next to the trade window, the ⚖ scan button next to the
-- auction house, and the number on the minimap button.
--
-- R-10.1/R-10.2: icons first; no explanation lines, no time stamps; tooltips
-- are a name, a number or a very short line. Technical details are only in
-- 同步與診斷 (Diag.ordersText / Diag.pricesText).

local _, ns = ...
local str = ns.str

local UI = {}
ns.OrdersUI = UI

UI.ICON = {
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    making = "Interface\\Icons\\Trade_BlackSmithing",
    checking = "Interface\\Icons\\INV_Crate_01",
    deal = "Interface\\RaidFrame\\ReadyCheck-Ready",
    cancel = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    attention = "Interface\\GossipFrame\\AvailableQuestIcon",
    hammer = "Interface\\Icons\\INV_Hammer_20",
    hammerFallback = "Interface\\Icons\\Trade_BlackSmithing",
    guild = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    free = "Interface\\Icons\\INV_Misc_Gift_01",
    mail = "Interface\\Icons\\INV_Letter_15",
    back = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    undo = "Interface\\Buttons\\UI-RefreshButton",
    scan = "Interface\\Icons\\INV_Misc_Coin_02",
    history = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    paste = "Interface\\Icons\\INV_Scroll_03",
    bag = "Interface\\Icons\\INV_Misc_Bag_08",
    online = "Interface\\FriendsFrame\\StatusIcon-Online",
    unknown = "Interface\\Icons\\INV_Misc_QuestionMark",
}
UI.STATE_NAME = { waiting = "等接單", making = "製作中", checking = "待驗收", deal = "成交", cancel = "取消" }
UI.BUTTON = {
    accept = { icon = "deal", tip = "接單" }, decline = { icon = "cancel", tip = "不接" },
    cancel = { icon = "cancel", tip = "取消" }, deal = { icon = "deal", tip = "成交" },
    ["return"] = { icon = "back", tip = "退回" }, deliver = { icon = "mail", tip = "已交付" },
    release = { icon = "cancel", tip = "退單" }, close = { icon = "deal", tip = "工匠結案", hammer = true },
}
-- Buttons that cancel something wait 5 seconds and can be undone (R-6.7).
UI.DELAYED = { cancel = true, decline = true, release = true }

local function S() return ns.Share end
local function O() return ns.Orders end
local function P() return ns.Prices end
local Icons = ns.Icons

---------------------------------------------------------------------------
-- Pure helpers (offline tests)
---------------------------------------------------------------------------

-- 12345 -> "1g 23s 45c" with the game's coin icons (plain letters when the
-- client has no GetCoinTextureString).
function UI.money(c)
    c = math.floor(tonumber(c) or 0)
    -- GF-UI-D: where the client has the coin art, the numbers in gold / silver /
    -- copper with the game's coin icons (Theme.coinText).
    if type(GetCoinTextureString) == "function" then
        if ns.Theme then return ns.Theme.coinText(c) end
        local ok, s = pcall(GetCoinTextureString, c)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if cu > 0 or #out == 0 then out[#out + 1] = cu .. "c" end
    return table.concat(out, " ")
end

-- R-4.4: how a fee shows: "unset" (grey coin + ?), "free" (gift), "amount".
function UI.feeKind(fee)
    if fee == nil then return "unset" end
    if fee == 0 then return "free" end
    return "amount"
end

-- Text next to the estimate: "≥" when a price is missing (R-8.2.4).
function UI.totalText(est, fee)
    local t = (est and est.total or 0) + (fee or 0)
    local s = UI.money(t)
    if est and est.unknown then s = "＞" .. s end
    return s
end

---------------------------------------------------------------------------
-- Small widgets
---------------------------------------------------------------------------

-- Inline texture for menus and strings (the game fonts have no emoji).
-- GF-UI-B (GF-UI-A §1.3): 18 px by default, never under 16 next to 16 px text.
UI.INLINE = 18
function UI.tex(key, size)
    return "|T" .. (UI.ICON[key] or key) .. ":" .. tostring(math.max(16, size or UI.INLINE)) .. "|t"
end

local function setIcon(tex, key)
    local path = UI.ICON[key] or key
    if Icons.set(tex, path) then tex:Show(); return true end
    if key == "hammer" and Icons.set(tex, UI.ICON.hammerFallback) then tex:Show(); return true end
    tex:Hide()
    return false
end
UI.setIcon = setIcon

local function itemIcon(tex, itemID, skill)
    local icon
    if itemID and type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        icon = ns.call(C_Item.GetItemIconByID, itemID)
    end
    if icon and Icons.set(tex, icon) then tex:Show(); return end
    if skill and Icons.setProfessionIcon(tex, { skillLineID = skill }) then return end
    setIcon(tex, "unknown")
end
UI.itemIcon = itemIcon

-- GF-002-D: label = the short name shown right of the icon (owner: icons
-- alone cannot be understood). b.label is that FontString.
local function setLabel(b, text)
    if not text then if b.label then b.label:SetText(""); b.label:Hide() end return end
    if not b.label then
        -- GF-002-E: the normal font, no fixed width, one line (0.12.2 wrapped 「調/整」).
        -- GF-002-G: the name belongs to the button itself, so it hides with it even
        -- when the page was never shown (0.12.4 left 「邀請下一位」 on the page).
        b.label = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        b.label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.label:SetJustifyH("LEFT")
    end
    b.label:SetText(text)
    b.label:Show()
end
UI.setLabel = setLabel

-- Width of an icon button with its name (for laying buttons out in a row).
function UI.buttonSpan(b)
    local w = b.gfWidth or ns.num((b:GetWidth())) or 0
    if b.label and b.label:IsShown() and str(b.label:GetText()) ~= "" then w = w + 4 + ns.measure(b.label) end
    return w
end
-- Put buttons one after another from x (TOPLEFT of parent, or LEFT of a row), gap px apart.
function UI.flow(parent, list, x, y, gap, point)
    for _, b in ipairs(list) do
        b:ClearAllPoints()
        if point == "LEFT" then b:SetPoint("LEFT", parent, "LEFT", x, y or 0)
        else b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
        b.flowX = x
        x = x + UI.buttonSpan(b) + (gap or 14)
    end
    return x
end

local function iconButton(parent, size, key, tip, onClick, label)
    local b = CreateFrame("Button", nil, parent)
    b.labelParent = parent
    b:SetSize(size, size)
    b.gfWidth = size
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    setIcon(b.tex, key)
    b.badge = b:CreateTexture(nil, "OVERLAY")
    b.badge:SetSize(math.floor(size / 2), math.floor(size / 2))
    b.badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.badge:Hide()
    -- GF-002-G (owner: 「選取的圖標，請要用有質感的發亮，不是很俗氣全黃而已」):
    -- chosen = the action bar's glow ring (ADD blend) and a soft inner shine;
    -- not chosen = a little darker, still clear (UI.setSelected).
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetSize(math.floor(size * 1.75), math.floor(size * 1.75))
    b.sel:SetPoint("CENTER", b, "CENTER", 0, 0)
    if not Icons.set(b.sel, UI.GLOW) then b.sel:SetColorTexture(1, 0.85, 0.4, 0.35) end
    if b.sel.SetBlendMode then b.sel:SetBlendMode("ADD") end
    if b.sel.SetVertexColor then b.sel:SetVertexColor(1, 0.85, 0.45) end
    b.sel:Hide()
    b.shine = b:CreateTexture(nil, "OVERLAY")
    b.shine:SetAllPoints()
    if Icons.set(b.shine, UI.SHINE) then
        if b.shine.SetBlendMode then b.shine:SetBlendMode("ADD") end
        b.shine:SetAlpha(0.45)
    end
    b.shine:Hide()
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b.tip = tip
    b:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if onClick then b:SetScript("OnClick", onClick) end
    if label then setLabel(b, label) end
    b:HookScript("OnShow", function(self) if self.label and self.label:GetText() ~= "" then self.label:Show() end end)
    b:HookScript("OnHide", function(self) if self.label then self.label:Hide() end end)
    return b
end
UI.iconButton = iconButton

UI.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
UI.SHINE = "Interface\\Buttons\\CheckButtonHilight"
UI.DIM = 0.62 -- not chosen: the icon a little darker, never grey
function UI.setSelected(b, on)
    b.selected = on and true or false
    if on then b.sel:Show(); b.shine:Show() else b.sel:Hide(); b.shine:Hide() end
    if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end
    local c = on and 1 or UI.DIM
    if b.tex.SetVertexColor then b.tex:SetVertexColor(c, c, c) end
    b.tex:SetAlpha(1)
    b.dimmed = not on
    if b.label then
        b.label:SetAlpha(1)
        if on then b.label:SetTextColor(1, 0.95, 0.75) else b.label:SetTextColor(0.72, 0.72, 0.72) end
    end
end

-- GF-UI-C (owner: icons on the red buttons too big, with a black square):
-- an icon inside a text button is at most the button's height - 8 px, and a
-- square spell / item icon (Interface\Icons) has its dark border cropped
-- (texture coordinates 0.08 - 0.92). Applied to every text a text button
-- gets, also later ones (SetText).
UI.BUTTON_ICON_MAX = ns.BUTTON_H - 8
local CROP = { 5, 59 } -- of 64: 0.08 - 0.92
function UI.buttonText(text)
    return (tostring(text or ""):gsub("|T([^:|]+):?([^|]*)|t", function(path, rest)
        local n = tonumber(rest:match("^(%d+)")) or UI.BUTTON_ICON_MAX
        n = math.min(n, UI.BUTTON_ICON_MAX)
        if path:lower():find("^interface\\icons\\") then
            return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", path, n, n, CROP[1], CROP[2], CROP[1], CROP[2])
        end
        local box = rest:match("^%d+:%d+:%-?%d+:%-?%d+:(%d+:%d+:%d+:%d+:%d+:%d+)$")
        if box then return string.format("|T%s:%d:%d:0:0:%s|t", path, n, n, box) end
        return string.format("|T%s:%d|t", path, n)
    end))
end

-- GF-002-E: a text button as wide as its text (an icon markup counts as one).
-- GF-UI-D: the theme's outlined button (no red UIPanelButton).
function UI.textButton(parent, text, onClick, minWidth, exactWidth)
    local w = exactWidth or math.max(minWidth or 0, ns.labelWidth(text) + 28)
    local b = ns.Theme.button(parent, nil, w, ns.BUTTON_H)
    b.gfWidth, b.gfHeight = w, ns.BUTTON_H
    local set = b.SetText
    b.SetText = function(self, t) return set(self, UI.buttonText(t)) end
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function itemTooltip(owner, itemID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if itemID and type(GameTooltip.SetItemByID) == "function" then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
    end
    if not shown then GameTooltip:AddLine("#" .. tostring(itemID or "?")) end
    GameTooltip:Show()
end

local function memberOf(a) return a and S().memberFor(a) or nil end
local function shortOf(a)
    local m = memberOf(a)
    return m and ns.shortName(m.name) or "?"
end

-- Coin icon for a fee: amount, free or not filled in (grey + "?").
local function showFee(tex, label, fee)
    local kind = UI.feeKind(fee)
    if kind == "free" then
        setIcon(tex, "free"); if tex.SetDesaturated then tex:SetDesaturated(false) end
        label:SetText("")
    elseif kind == "unset" then
        setIcon(tex, "gold"); if tex.SetDesaturated then tex:SetDesaturated(true) end
        label:SetText("?")
    else
        tex:Hide()
        label:SetText(UI.money(fee))
    end
    return kind
end
UI.showFee = showFee

---------------------------------------------------------------------------
-- The orders page
---------------------------------------------------------------------------

local ROW_HEIGHT = ns.PAGE_ROW -- GF-002-F: 36
UI.ROW_WIDTH = 1030 -- GF-002-E: the wider window
local panel, scroll, content, profBar
local rowWidgets, shownRows, profButtons = {}, {}, {}
local pendingPress = {} -- [id .. button] = true while a delayed press can be undone

function UI.ownCraftSkills()
    local a = S().selfAuthor()
    local list = {}
    local profs = a and S().decoded(a, "P") or nil
    for _, p in ipairs(type(profs) == "table" and profs or {}) do
        local id = ns.num(p.skillLineID)
        if id and ns.Recipes.CRAFTS[id] then list[#list + 1] = id end
    end
    return list
end

-- The list the page draws: header rows and order rows (R-10.3: only rows in view get frames).
function UI.pageRows()
    local me = S().selfAuthor()
    if not me then return {} end
    local received, placed = O().rowsFor(me, ns.Data.player().guid)
    local out = {}
    if #received > 0 then
        out[#out + 1] = { header = ns.GameIcons.markup("received", 16) .. " 收到的", count = #received } -- GF-002-C
        for _, r in ipairs(received) do out[#out + 1] = r end
    end
    if #placed > 0 then
        out[#out + 1] = { header = ns.GameIcons.markup("placed", 16) .. " 我下的", count = #placed }
        for _, r in ipairs(placed) do out[#out + 1] = r end
    end
    return out
end

-- GF-UI-B (GF-UI-A §2.9 item 3): the clock the undo swirl runs on.
local function clock() return ns.num((ns.call(GetTime))) or ns.now() end
UI.clock = clock

local function press(row, button)
    local v = row.view
    local key = v.id .. "|" .. button
    if UI.DELAYED[button] then
        if pendingPress[key] then pendingPress[key] = nil; UI.refresh(); return "undone" end
        pendingPress[key] = clock() -- when it started (the swirl on the button)
        UI.refresh()
        ns.after(O().UNDO, function()
            if not pendingPress[key] then return end
            pendingPress[key] = nil
            O().press(v, button)
            UI.refresh()
        end)
        return "delayed"
    end
    local ok = O().press(v, button)
    UI.refresh()
    return ok and "done" or "failed"
end
UI.press = press
UI.pendingPress = pendingPress

local function newRow(i)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(UI.ROW_WIDTH, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.att = row:CreateTexture(nil, "ARTWORK"); row.att:SetSize(20, 20); row.att:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.item = iconButton(row, 32, "unknown", nil)
    row.item:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.item:SetScript("OnEnter", function(self) itemTooltip(self, self:GetParent().view and self:GetParent().view.item) end)
    row.item.infoOnly = true -- GF-002-D: shows the item on hover, nothing to click
    row.qty = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.qty:SetPoint("LEFT", row, "LEFT", 62, 0); row.qty:SetWidth(84); row.qty:SetJustifyH("LEFT"); row.qty:SetWordWrap(false)
    row.cls = row:CreateTexture(nil, "ARTWORK"); row.cls:SetSize(22, 22); row.cls:SetPoint("LEFT", row, "LEFT", 150, 0)
    row.who = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.who:SetPoint("LEFT", row, "LEFT", 176, 0); row.who:SetWidth(130); row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)
    -- GF-UI-B (GF-UI-A §2.9 item 2): materials 28 px, the coin 20 px.
    row.mats = {}
    for k = 1, 5 do
        local m = iconButton(row, ns.ROW_ICON, "unknown", nil)
        m:SetPoint("LEFT", row, "LEFT", 312 + (k - 1) * 30, 0)
        m:SetScript("OnEnter", function(self) itemTooltip(self, self.itemID) end)
        m.infoOnly = true
        row.mats[k] = m
    end
    row.coin = row:CreateTexture(nil, "ARTWORK"); row.coin:SetSize(20, 20); row.coin:SetPoint("LEFT", row, "LEFT", 466, 0)
    row.fee = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.fee:SetPoint("LEFT", row, "LEFT", 490, 0); row.fee:SetWidth(108); row.fee:SetJustifyH("LEFT"); row.fee:SetWordWrap(false)
    row.state = iconButton(row, ns.ROW_ICON, "waiting", nil)
    row.state:SetPoint("LEFT", row, "LEFT", 604, 0)
    row.buttons = {}
    -- GF-002-E: the buttons follow each other by their measured names.
    UI.ROW_BUTTON_X = 700
    for k = 1, 3 do
        local b = iconButton(row, ns.ROW_ICON, "deal", nil)
        b:SetPoint("LEFT", row, "LEFT", UI.ROW_BUTTON_X, 0)
        -- GF-UI-B: the action bar's cooldown swirl while a press can be undone (5 s).
        b.cd = ns.createFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints(b)
        if b.cd.SetReverse then pcall(b.cd.SetReverse, b.cd, false) end
        b.cd:Hide()
        row.buttons[k] = b
    end
    row.head = row:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
    row.head:SetPoint("LEFT", row, "LEFT", 6, 0)
    rowWidgets[i] = row
    return row
end

-- The swirl on a row button: started at `at` (UI.clock), O().UNDO seconds long.
function UI.setSwirl(b, at)
    local cd = b.cd
    if not cd then return end
    if at and type(cd.SetCooldown) == "function" then
        cd:Show()
        pcall(cd.SetCooldown, cd, at, O().UNDO)
        cd.gfStart, cd.gfDuration = at, O().UNDO
    else
        cd.gfStart, cd.gfDuration = nil, nil
        cd:Hide()
    end
end

local function fillRow(row, data, i)
    ns.stripe(row.bg, i) -- GF-UI-B: the shared stripe
    local parts = { row.att, row.item, row.qty, row.cls, row.who, row.coin, row.fee, row.state }
    if data.header then
        for _, w in ipairs(parts) do w:Hide() end
        for _, m in ipairs(row.mats) do m:Hide() end
        for _, b in ipairs(row.buttons) do b:Hide() end
        row.head:SetText(data.header)
        row.head:Show()
        row.view = nil
        return
    end
    row.head:Hide()
    for _, w in ipairs(parts) do w:Show() end
    local v = data.view
    row.view = v
    local me = S().selfAuthor()
    if data.attention then setIcon(row.att, "attention") else row.att:Hide() end
    itemIcon(row.item.tex, v.item, v.skill)
    local qty = "x" .. v.qty
    if v.progress > 0 and v.progress < v.qty then qty = qty .. "  " .. v.progress .. "/" .. v.qty end
    row.qty:SetText(qty)
    -- The other side: the customer (for my jobs) or the crafter (for my orders).
    local other = v.customer == me and v.crafter or v.customer
    if v.test then
        -- GF-UI-B: a test order (to myself, local only): the test icon and 測試.
        if not ns.GameIcons.set(row.cls, "test") then row.cls:Hide() end
        row.who:SetText("測試")
        ns.setTextColor(row.who, "warn")
    elseif v.customer == me and v.guild and not v.crafter then
        setIcon(row.cls, "guild")
        row.who:SetText("公會")
        row.who:SetTextColor(0.9, 0.9, 0.9)
    else
        local m = memberOf(other)
        if m and Icons.setClassIcon(row.cls, m.classToken) then row.cls:Show() else row.cls:Hide() end
        row.who:SetText(m and ns.shortName(m.name) or "?")
        local c = Icons.classColor(m and m.classToken)
        row.who:SetTextColor(c[1], c[2], c[3])
        if m and m.online then row.who:SetText(row.who:GetText() .. " " .. UI.tex("online", 16)) end
    end
    -- Materials the customer gives (ticked) and the ones the crafter gives.
    local r = v.recipe and P().cachedReagents(v.recipe)
    local k = 0
    for _, x in ipairs(r and r.list or {}) do
        k = k + 1
        local m = row.mats[k]
        if not m then break end
        itemIcon(m.tex, x.id)
        m.itemID = x.id
        if v.mats[x.id] then setIcon(m.badge, "deal") else m.badge:Hide() end
        m:Show()
    end
    for j = k + 1, #row.mats do row.mats[j]:Hide() end
    -- Review 5-3: the fee the customer wrote; at 0 the quote only says free / not filled in.
    showFee(row.coin, row.fee, v.fee > 0 and v.fee or (v.feeQuoted == nil and nil or 0))
    if v.paid then row.fee:SetText(row.fee:GetText() .. " " .. UI.tex("deal", 16)) end
    -- State icon; a crafter's close carries a small hammer, a cancel the canceller's class.
    setIcon(row.state.tex, v.state)
    row.state.badge:Hide()
    if v.state == "deal" and v.closedBy == "crafter" then setIcon(row.state.badge, "hammer") end
    if v.state == "cancel" then
        local who = v.closedBy == "crafter" and v.crafter or v.customer
        local m = memberOf(who)
        if m and Icons.setClassIcon(row.state.badge, m.classToken) then row.state.badge:Show() end
    end
    if v.uncertain and v.state == "checking" then setIcon(row.state.badge, "unknown") end
    local red = data.attention and data.attention.red
    if row.state.tex.SetVertexColor then
        if red then row.state.tex:SetVertexColor(1, 0.3, 0.3) else row.state.tex:SetVertexColor(1, 1, 1) end
    end
    local days = math.floor((S().serverNow() - (v.since or 0)) / 86400)
    row.state.tip = UI.STATE_NAME[v.state] .. (days >= 1 and ("  " .. days .. " 天") or "")
    setLabel(row.state, UI.STATE_NAME[v.state]) -- GF-002-D
    -- Buttons this viewer may press (R-6.2).
    local list = O().buttons(v, me)
    for j, b in ipairs(row.buttons) do
        local name = list[j]
        if name then
            local spec = UI.BUTTON[name]
            local key = v.id .. "|" .. name
            if pendingPress[key] then setIcon(b.tex, "undo"); b.tip = "復原"
            else setIcon(b.tex, spec.icon); b.tip = spec.tip end
            UI.setSwirl(b, pendingPress[key] and (type(pendingPress[key]) == "number" and pendingPress[key] or clock()) or nil)
            setLabel(b, b.tip)
            if spec.hammer then setIcon(b.badge, "hammer") else b.badge:Hide() end
            b:SetScript("OnClick", function() press(row, name) end)
            b.action = name
            b:Show()
        else
            b:Hide(); b.action = nil
            UI.setSwirl(b, nil)
        end
    end
    local shown = {}
    for _, b in ipairs(row.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
    UI.flow(row, shown, UI.ROW_BUTTON_X, 0, 16, "LEFT")
end

function UI.layoutRows()
    if not scroll then return end
    local offset = ns.num((scroll:GetVerticalScroll())) or 0
    local h = ns.num((scroll:GetHeight())) or 0
    if h <= 0 then h = 420 end
    local count = math.ceil(h / ROW_HEIGHT) + 1
    local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local data = k <= count and shownRows[i] or nil
        local row = rowWidgets[k] or (data and newRow(k)) or nil
        if row then
            if data then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                fillRow(row, data, i)
                row:Show()
            else
                row:Hide(); row.view = nil
            end
        end
    end
end
function UI.rowFrames() return rowWidgets end
function UI.shownRows() return shownRows end

-- GF-UI-C (owner: 「不接 / 工錢 / ?」 ran into each other): every profession
-- is one group [icon] 接單/不接 [工錢] coin amount; groups sit in even columns
-- as wide as the widest group (measured), so a long amount never reaches the
-- next profession. The label column is as wide as the longer of 接單 / 不接.
UI.PROF_GAP = 24
function UI.profGroupWidth(b)
    local labelW = math.max(ns.labelWidth("接單"), ns.labelWidth("不接"))
    local feeX = ns.ICON + 4 + labelW + 8
    local textX = feeX + b.feeButton.gfWidth + (b.feeTex:IsShown() and 26 or 6)
    return textX + ns.measure(b.feeText), feeX, textX
end
local function refreshProfBar()
    if not profBar then return end
    local skills = UI.ownCraftSkills()
    local sv = O().services(S().selfAuthor())
    for i, skill in ipairs(skills) do
        local b = profButtons[i]
        if not b then
            -- GF-002-D: [icon] 接單／不接   [工錢] coin — a click on the icon toggles, on 工錢 edits.
            b = iconButton(profBar, ns.ICON, "unknown", nil, nil, "不接")
            b.feeButton = UI.textButton(profBar, "工錢")
            b.feeTex = profBar:CreateTexture(nil, "ARTWORK"); b.feeTex:SetSize(20, 20)
            b.feeText = ns.freeText(profBar:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.feeText:SetJustifyH("LEFT")
            profButtons[i] = b
        end
        Icons.setProfessionIcon(b.tex, { skillLineID = skill })
        local on = sv.active[skill] == true
        if on then setIcon(b.badge, "hammer") else b.badge:Hide() end
        if b.tex.SetDesaturated then b.tex:SetDesaturated(not on) end
        b.skill = skill
        b.tip = (ns.Data.skillName(nil, skill) or "") .. (on and "  接單中" or "  不接單")
        setLabel(b, on and "接單" or "不接")
        if b.label.SetTextColor then if on then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.6, 0.6, 0.6) end end
        showFee(b.feeTex, b.feeText, sv.fees[skill])
        if UI.feeKind(sv.fees[skill]) == "free" then b.feeText:SetText("免費") end
        b.feeButton.skill = skill
        b.feeButton:SetScript("OnClick", function(self) UI.editFee({ skill = self.skill }) end)
        b.feeButton:Show()
        b:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then UI.editFee({ skill = self.skill })
            else O().setActive(self.skill, not O().isActive(ns.Data.player().guid, self.skill)); UI.refresh() end
        end)
        b:Show()
    end
    for i = #skills + 1, #profButtons do
        profButtons[i]:Hide(); profButtons[i].feeButton:Hide(); profButtons[i].feeTex:Hide(); profButtons[i].feeText:SetText("")
    end
    -- Place the groups: one column width for all (the widest group + a gap).
    local step = 0
    for i = 1, #skills do step = math.max(step, (UI.profGroupWidth(profButtons[i]))) end
    step = step + UI.PROF_GAP
    UI.profStep = step
    for i = 1, #skills do
        local b = profButtons[i]
        local _, feeX, textX = UI.profGroupWidth(b)
        local x = UI.PROF_X + (i - 1) * step
        b:ClearAllPoints(); b:SetPoint("LEFT", profBar, "LEFT", x, 0)
        b.feeButton:ClearAllPoints(); b.feeButton:SetPoint("LEFT", profBar, "LEFT", x + feeX, 0)
        b.feeTex:ClearAllPoints(); b.feeTex:SetPoint("LEFT", profBar, "LEFT", x + feeX + b.feeButton.gfWidth + 4, 0)
        b.feeText:ClearAllPoints(); b.feeText:SetPoint("LEFT", profBar, "LEFT", x + textX, 0)
        b.groupX, b.groupW = x, (UI.profGroupWidth(b))
    end
    if UI.profField then if #skills > 0 then UI.profField:Show() else UI.profField:Hide() end end
end
UI.profButtons = function() return profButtons end
UI.PROF_X = 60

function UI.refresh()
    UI.updateBadge()
    if not panel then return end
    refreshProfBar()
    shownRows = UI.pageRows()
    content:SetHeight(math.max(1, #shownRows * ROW_HEIGHT))
    UI.layoutRows()
    UI.emptyLine:SetText(#shownRows == 0 and "沒有訂單" or "") -- GF-002-D
    if UI.servicesPopup and UI.servicesPopup:IsShown() then UI.drawServices() end
end

local function build(p)
    -- GF-002-E (owner: 「我看不出來如何下單」「工匠設定要按右鍵不明顯」): two plain buttons on top.
    -- GF-UI-C (item 12): text buttons say it in words; no icon.
    UI.orderButton = UI.textButton(p, "＋下單", function(self) UI.openPicker() end)
    UI.orderButton:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -40)
    UI.servicesButton = UI.textButton(p, "我的服務", function() UI.openServices() end)
    UI.servicesButton:SetPoint("LEFT", UI.orderButton, "RIGHT", 12, 0)
    profBar = CreateFrame("Frame", nil, p)
    profBar:SetSize(1040, 40)
    profBar:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -80)
    UI.profField = ns.freeText(profBar:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    UI.profField:SetPoint("LEFT", profBar, "LEFT", 0, 0)
    UI.profField:SetText("專業")
    UI.emptyLine = p:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT)
    UI.emptyLine:SetPoint("TOP", p, "TOP", 0, -200)
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -128)
    scroll:SetPoint("BOTTOMRIGHT", -40, 52)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(UI.ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() UI.layoutRows() end)
    UI.historyButton = iconButton(p, ns.ICON, "history", "歷史", function() UI.showHistory() end, "歷史")
    UI.historyButton:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -250, 10)
    -- GF-006-C (R-9.4): paste a web order's import code.
    UI.pasteButton = iconButton(p, ns.ICON, "paste", "匯入碼", function() UI.openPaste() end, "匯入")
    UI.pasteButton:SetPoint("RIGHT", UI.historyButton, "LEFT", -(ns.labelWidth("匯入") + 28), 0)
    ns.Diag.smallButton(p, "BOTTOMRIGHT", -24, 10)
    panel = p
end

ns.Framework.register({
    id = "orders",
    title = "訂單",
    order = 13,
    available = function() return ns.guildState() == "target" end,
    create = build,
    show = function() O().markSeen(); UI.refresh() end,
})

---------------------------------------------------------------------------
-- Import code (GF-006-C, R-9.4): the same string as the Inbox, pasted.
---------------------------------------------------------------------------

UI.PASTE_NAME = "GreenFangToolkit_PastePopup"
local pastePopup

function UI.openPaste()
    if not pastePopup then
        local f = ns.popupWindow(UI.PASTE_NAME, 620, 230)
        f:SetPoint("CENTER", 0, 80)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("匯入") end
        UI.fieldLabel(f, "匯入碼", UI.FIELD_X, -50)
        local X = UI.controlX({ "匯入碼" })
        f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(ns.ICON, ns.ICON)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", X, -42)
        Icons.set(f.icon, UI.ICON.paste)
        local box = ns.Theme.editBox(f)
        box:SetSize(400, 30)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", X + 44, -44)
        box:SetAutoFocus(true)
        if box.SetMaxLetters then box:SetMaxLetters(0) end
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        box:SetScript("OnEnterPressed", function() UI.pasteImport() end)
        f.box = box
        f.result = ns.freeText(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"))
        f.result:SetPoint("TOPLEFT", f, "TOPLEFT", X, -96)
        f.go = UI.textButton(f, "匯入", function() UI.pasteImport() end, 110)
        f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f:Hide()
        pastePopup = f
    end
    pastePopup.box:SetText("")
    pastePopup.result:SetText("")
    pastePopup:Show()
    return pastePopup
end

-- Result as icons and numbers only (R-10.2): ✓ imported, ✗ skipped.
function UI.pasteImport(text)
    local f = pastePopup
    text = text or (f and f.box:GetText()) or ""
    local res = ns.WebOrders.import(text, "paste")
    local skipped = 0
    for _, n in pairs(res.skipped or {}) do skipped = skipped + n end
    if f then
        if res.ok then
            f.result:SetText(UI.tex("deal", 16) .. " " .. ((res.imported or 0) + (res.same or 0))
                .. (skipped > 0 and ("   " .. UI.tex("cancel", 16) .. " " .. skipped) or ""))
        else
            f.result:SetText(UI.tex("cancel", 16))
        end
    end
    UI.refresh()
    return res
end

---------------------------------------------------------------------------
-- History (R-6.10): closed orders, newest first; right-click = order again.
---------------------------------------------------------------------------

function UI.showHistory()
    local key = ns.Data.player().guid or "?"
    local list = O().local_().history[key] or {}
    local items = {}
    for i = 1, math.min(#list, 15) do
        local h = list[i]
        local name = (h.recipe and ns.Recipes.name(h.recipe)) or ("#" .. tostring(h.item or "?"))
        local mark = UI.tex(h.close == "deal" and "deal" or "cancel") .. " "
        items[#items + 1] = { text = mark .. name .. " x" .. tostring(h.qty or 1), fn = function()
            if h.recipe then UI.openOrder({ recipe = h.recipe, skill = h.skill }) end
        end }
    end
    if #items == 0 then return nil end
    return ns.showMenu(UI.historyButton, items)
end

---------------------------------------------------------------------------
-- The order popup (R-5.2)
---------------------------------------------------------------------------

UI.POPUP_NAME = "GreenFangToolkit_OrderPopup"
local popup
local draft -- { recipe, skill, item, qty, crafter (author or "*"), mats = { [id] = true }, fee, feeQuoted, crafters }

-- Prefilled draft (pure): crafters = members who know the recipe (sorted active first).
function UI.newDraft(opts)
    local recipe, skill = opts.recipe, opts.skill
    -- GF-UI-B: in the test mode I am in the list too (an order to myself is a test order).
    local test = O().testOn()
    local crafters = {}
    for _, m in ipairs(opts.crafters or {}) do if test or not m.self then crafters[#crafters + 1] = m end end
    O().sortCrafters(crafters, skill)
    local target = opts.crafter
    if not target then
        -- Never myself by default: a test order is always chosen by hand.
        for _, m in ipairs(crafters) do
            if not m.self then
                if O().isActive(m.guid, skill) then target = S().authorOf(m.guid) end
                break
            end
        end
    end
    -- My own recipe and nobody else: the test order is the only choice.
    if not target and test and #crafters > 0 then
        local others = false
        for _, m in ipairs(crafters) do if not m.self then others = true end end
        if not others then target = S().selfAuthor() end
    end
    local d = { recipe = recipe, skill = skill, qty = 1, crafter = target or "*", mats = {}, crafters = crafters }
    local r = P().reagents(recipe)
    d.reagents = r
    d.item = r and r.output or opts.item
    -- Materials I already have enough of are ticked (R-5.2).
    for _, x in ipairs(r and r.list or {}) do
        local have = ns.Delivery.countOf(x.id) or 0
        if have >= x.n then d.mats[x.id] = true end
    end
    UI.applyFee(d)
    return d
end

-- The fee field follows the chosen crafter's quote (R-4.5): nil -> 0, marked unset.
function UI.applyFee(d)
    if d.crafter == "*" then
        d.feeQuoted = O().lowestFee(d.crafters, d.skill, d.recipe)
    else
        d.feeQuoted = O().feeFor(S().guidOf(d.crafter), d.skill, d.recipe)
    end
    d.fee = d.feeQuoted or 0
    d.feeEdited = false
end

function UI.estimateOf(d)
    local rk = P().homeKey()
    local mine = {}
    for id, on in pairs(d.mats) do if on then mine[id] = true end end
    return P().estimate(d.reagents, d.qty, mine, function(id) return (P().priceOf(id, rk)) end)
end

-- Place the draft. Returns the order id.
function UI.submit(d)
    d = d or draft
    if not d then return nil end
    local mats = {}
    local crafts = d.reagents and math.ceil(d.qty / math.max(1, d.reagents.yield or 1)) or 1
    for _, x in ipairs(d.reagents and d.reagents.list or {}) do
        if d.mats[x.id] then mats[x.id] = x.n * crafts end
    end
    local est = UI.estimateOf(d)
    -- Review 5-1 (contract): no quote when it cannot be computed (no list, or a price missing).
    local quote = (not est.noList and not est.unknown) and est.total or nil
    local id, why = O().place({ recipe = d.recipe, item = d.item, skill = d.skill, qty = d.qty, crafter = d.crafter,
        mats = mats, fee = d.fee or 0, feeQuoted = d.feeQuoted, quote = quote })
    if not id then
        -- Review 1-2: never pretend; the popup stays open with a red cross.
        if popup and popup.total then popup.total:SetText(UI.tex("cancel", 16)) end
        return nil, why
    end
    if popup then popup:Hide() end
    UI.refresh()
    return id
end

-- An arrow button: the game's page arrow art, else a small text button.
function UI.arrowButton(parent, which, fallbackText)
    local up = "Interface\\Buttons\\UI-SpellbookIcon-" .. (which == "prev" and "Prev" or "Next") .. "Page-"
    if ns.GameIcons.has(up .. "Up") then
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(26, 26)
        if b.SetNormalTexture then b:SetNormalTexture(up .. "Up") end
        if b.SetPushedTexture then b:SetPushedTexture(up .. "Down") end
        if b.SetDisabledTexture then b:SetDisabledTexture(up .. "Disabled") end
        if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD") end
        b.art = up .. "Up"
        return b
    end
    return ns.Theme.button(parent, fallbackText, 26, 26)
end

local function moneyBoxes(parent, x, y, onChange)
    local boxes = {}
    for i, unit in ipairs({ "gold", "silver", "copper" }) do
        local e = ns.Theme.editBox(parent)
        e:SetSize(i == 1 and 60 or 36, 30)
        e:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * 84, y)
        e:SetAutoFocus(false)
        if e.SetNumeric then e:SetNumeric(true) end
        e:SetMaxLetters(i == 1 and 5 or 2)
        local coin = parent:CreateTexture(nil, "ARTWORK")
        coin:SetSize(18, 18)
        coin:SetPoint("LEFT", e, "RIGHT", 3, 0)
        Icons.set(coin, "Interface\\MoneyFrame\\UI-" .. (unit == "gold" and "Gold" or unit == "silver" and "Silver" or "Copper") .. "Icon")
        e:SetScript("OnTextChanged", function(_, user) if user ~= false then onChange() end end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        boxes[i] = e
    end
    -- Review 5-2: all three empty = nothing entered (nil), so 「確定」 keeps "not filled in".
    function boxes.get()
        local a, b, c = str(boxes[1]:GetText()), str(boxes[2]:GetText()), str(boxes[3]:GetText())
        if a == "" and b == "" and c == "" then return nil end
        return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
    end
    function boxes.set(c)
        c = math.floor(c or 0)
        boxes[1]:SetText(c >= 10000 and tostring(math.floor(c / 10000)) or "")
        boxes[2]:SetText((c % 10000) >= 100 and tostring(math.floor(c / 100) % 100) or "")
        boxes[3]:SetText(c % 100 > 0 and tostring(c % 100) or "")
    end
    function boxes.clear() for i = 1, 3 do boxes[i]:SetText("") end end
    return boxes
end
UI.moneyBoxes = moneyBoxes

local function drawPopup()
    if not (popup and draft) then return end
    local d = draft
    itemIcon(popup.item.tex, d.item, d.skill)
    popup.qty:SetText(tostring(d.qty))
    setIcon(popup.guild.badge, "deal")
    if d.crafter == "*" then popup.guild.badge:Show(); popup.named.badge:Hide()
    else popup.guild.badge:Hide(); setIcon(popup.named.badge, "deal") end
    local m = d.crafter ~= "*" and memberOf(d.crafter) or nil
    if m and Icons.setClassIcon(popup.named.tex, m.classToken) then popup.named.tex:Show() else setIcon(popup.named.tex, "unknown") end
    popup.named.tip = m and ns.shortName(m.name) or "指定工匠"
    popup.namedActive:Hide()
    if m and O().isActive(m.guid, d.skill) then setIcon(popup.namedActive, "hammer") end
    local est = UI.estimateOf(d)
    for i, b in ipairs(popup.mats) do
        local row = est.mats[i]
        if row then
            itemIcon(b.tex, row.id)
            b.itemID = row.id
            if row.mine then setIcon(b.badge, "bag") elseif row.unknown then setIcon(b.badge, "unknown") else b.badge:Hide() end
            setLabel(b, "x" .. row.need)
            b:Show()
        else
            b:Hide()
        end
    end
    popup.matsCost:SetText(est.noList and "" or ((est.unknown and "＞" or "") .. UI.money(est.total)))
    if not d.feeEdited then popup.fee.set(d.fee) end
    local kind = UI.feeKind(d.feeEdited and d.fee or d.feeQuoted)
    popup.feeKind:Hide()
    if kind == "unset" and not d.feeEdited then setIcon(popup.feeKind, "unknown") popup.feeKind.tip = "工匠沒有填工錢"
    elseif kind == "free" and not d.feeEdited then setIcon(popup.feeKind, "free") popup.feeKind.tip = "免費" end
    popup.total:SetText(UI.totalText(est, d.fee))
    local market = d.item and P().marketOf(d.item)
    popup.market:SetText(market and UI.money(market.price) or "")
end
UI.drawPopup = drawPopup

-- GF-002-D: a field name in front of every row (owner: icons alone are not understood).
-- GF-002-E: the normal font, no fixed width, one line.
function UI.fieldLabel(parent, text, x, y)
    local l = ns.freeText(parent:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    l:SetJustifyH("LEFT")
    l:SetText(text)
    parent.fields = parent.fields or {}
    parent.fields[#parent.fields + 1] = text
    parent.fieldStrings = parent.fieldStrings or {}
    parent.fieldStrings[text] = l
    return l
end

-- Where the controls start: after the widest field name of the window.
UI.FIELD_X, UI.ROW_STEP = 24, ns.WINDOW_ROW -- GF-002-F: 52
function UI.controlX(names)
    local w = 0
    for _, n in ipairs(names) do w = math.max(w, ns.labelWidth(n)) end
    return UI.FIELD_X + w + 18
end

-- GF-UI-C (owner: one grid): 行情 has its own row under 合計 (it is compared with it),
-- every field name at FIELD_X, every control at the same X.
UI.ORDER_FIELDS = { "成品", "數量", "對象", "材料", "材料費", "工錢", "合計", "行情" }
local function createPopup()
    if popup then return popup end
    local f = ns.popupWindow(UI.POPUP_NAME, 660, 552)
    f:SetPoint("CENTER", 0, 60)
    f:EnableMouse(true)
    ns.exclusivePopup(f)
    if f.TitleText then f.TitleText:SetText("下單") end
    local X = UI.controlX(UI.ORDER_FIELDS) -- where the controls start, after the field names
    local function y(i) return -44 - (i - 1) * UI.ROW_STEP end
    UI.fieldLabel(f, "成品", UI.FIELD_X, y(1) - 8)
    f.item = iconButton(f, ns.ICON, "unknown", nil, nil, "成品")
    f.item:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(1))
    f.item:SetScript("OnEnter", function(self) itemTooltip(self, draft and draft.item) end)
    UI.fieldLabel(f, "行情", UI.FIELD_X, y(8) - 8)
    f.marketIcon = f:CreateTexture(nil, "ARTWORK"); f.marketIcon:SetSize(20, 20)
    f.marketIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(8) - 6)
    Icons.set(f.marketIcon, UI.ICON.gold)
    f.market = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    f.market:SetPoint("LEFT", f.marketIcon, "RIGHT", 4, 0)
    -- Quantity: the game's previous / next page arrows (GF-002-C).
    UI.fieldLabel(f, "數量", UI.FIELD_X, y(2) - 8)
    f.minus = UI.arrowButton(f, "prev", "－"); f.minus:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(2)); f.minus.fieldNamed = "數量"
    f.qty = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"); f.qty:SetPoint("LEFT", f.minus, "RIGHT", 12, 0)
    f.plus = UI.arrowButton(f, "next", "＋"); f.plus:SetPoint("LEFT", f.minus, "RIGHT", 52, 0); f.plus.fieldNamed = "數量"
    local function step(n)
        local yd = draft.reagents and draft.reagents.yield or 1
        draft.qty = math.max(yd, math.min(200, draft.qty + n * yd))
        drawPopup()
    end
    f.minus:SetScript("OnClick", function() step(-1) end)
    f.plus:SetScript("OnClick", function() step(1) end)
    -- Guild order or a named crafter.
    UI.fieldLabel(f, "對象", UI.FIELD_X, y(3) - 8)
    f.guild = iconButton(f, ns.ICON, "guild", "公會單", function() draft.crafter = "*"; UI.applyFee(draft); drawPopup() end, "公會單")
    f.named = iconButton(f, ns.ICON, "unknown", "指定工匠", function(self) UI.pickCrafter(self) end, "指定工匠")
    UI.flow(f, { f.guild, f.named }, X, y(3), 28)
    f.namedActive = f:CreateTexture(nil, "OVERLAY"); f.namedActive:SetSize(14, 14)
    f.namedActive:SetPoint("TOPRIGHT", f.named, "TOPRIGHT", 4, 4)
    -- Materials: click = I give it (ticked) / you give it. The count is the name.
    UI.fieldLabel(f, "材料", UI.FIELD_X, y(4) - 8)
    f.mats = {}
    for i = 1, 6 do
        local b = iconButton(f, ns.ICON, "unknown", nil, function(self)
            draft.mats[self.itemID] = not draft.mats[self.itemID] or nil
            drawPopup()
        end, "x1")
        b:SetPoint("TOPLEFT", f, "TOPLEFT", X + (i - 1) * 86, y(4))
        b:SetScript("OnEnter", function(self) itemTooltip(self, self.itemID) end)
        b.count = b.label
        f.mats[i] = b
    end
    UI.fieldLabel(f, "材料費", UI.FIELD_X, y(5) - 8)
    f.matsIcon = f:CreateTexture(nil, "ARTWORK"); f.matsIcon:SetSize(22, 22)
    f.matsIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(5) - 6)
    Icons.set(f.matsIcon, UI.ICON.bag)
    f.matsCost = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    f.matsCost:SetPoint("LEFT", f.matsIcon, "RIGHT", 6, 0)
    UI.fieldLabel(f, "工錢", UI.FIELD_X, y(6) - 8)
    f.feeIcon = f:CreateTexture(nil, "ARTWORK"); f.feeIcon:SetSize(22, 22)
    f.feeIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(6) - 6)
    Icons.setProfessionIcon(f.feeIcon, { skillLineID = 164 })
    f.fee = UI.moneyBoxes(f, X + 54, y(6) - 2, function()
        if not draft then return end
        draft.fee, draft.feeEdited = f.fee.get() or 0, true
        popup.total:SetText(UI.totalText(UI.estimateOf(draft), draft.fee))
    end)
    f.feeKind = f:CreateTexture(nil, "OVERLAY"); f.feeKind:SetSize(16, 16)
    f.feeKind:SetPoint("LEFT", f.feeIcon, "RIGHT", 4, 0)
    UI.fieldLabel(f, "合計", UI.FIELD_X, y(7) - 8)
    f.sumIcon = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.sumIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(7) - 6); f.sumIcon:SetText("")
    f.total = ns.freeText(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"))
    f.total:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(7) - 6)
    f.send = UI.textButton(f, "下單", function() UI.submit() end, 110)
    f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    f:Hide()
    popup = f
    return f
end

-- Choose a crafter: active ones first (R-4.2), each with their fee.
function UI.pickCrafter(owner)
    if not draft then return end
    local items = {}
    for _, m in ipairs(draft.crafters) do
        local a = S().authorOf(m.guid)
        local fee = O().feeFor(m.guid, draft.skill, draft.recipe)
        local mark = O().isActive(m.guid, draft.skill) and (UI.tex("hammer") .. " ") or ""
        local feeText = fee == nil and "  ?" or (fee == 0 and "  免費" or ("  " .. UI.money(fee)))
        if m.self then mark = ns.GameIcons.markup("test", 18) .. " 測試 " end
        items[#items + 1] = { text = mark .. ns.shortName(m.name) .. (m.online and (" " .. UI.tex("online", 16)) or "") .. feeText,
            fn = function() draft.crafter = a; UI.applyFee(draft); drawPopup() end }
        if #items >= 12 then break end
    end
    return ns.showMenu(owner, items)
end

-- opts = { recipe, skill, crafters = { member... }, crafter = author or nil }.
function UI.openOrder(opts)
    if not opts or not opts.recipe then return nil end
    if not opts.crafters and ns.Recipes then
        local index = ns.Recipes.index()
        local p = index and opts.skill and index[opts.skill]
        opts.crafters = p and p.recipes[opts.recipe] or {}
    end
    draft = UI.newDraft(opts)
    createPopup():Show()
    drawPopup()
    return draft
end
function UI.draft() return draft end

---------------------------------------------------------------------------
-- Fee popup (R-4.3): profession default or one recipe; 「清除」 = not filled in.
---------------------------------------------------------------------------

UI.FEE_NAME = "GreenFangToolkit_FeePopup"
local feePopup, feeTarget

function UI.editFee(target)
    feeTarget = target
    if not feePopup then
        local f = ns.popupWindow(UI.FEE_NAME, 480, 200)
        f:SetPoint("CENTER", 0, 120)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("工錢") end
        UI.fieldLabel(f, "工錢", UI.FIELD_X, -52)
        local X = UI.controlX({ "工錢" })
        f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(ns.ICON, ns.ICON)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", X, -44)
        f.boxes = moneyBoxes(f, X + 46, -46, function() end)
        f.save = UI.textButton(f, "確定", function() UI.saveFee(f.boxes.get()) end, 96)
        f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f.free = UI.textButton(f, "免費", function() UI.saveFee(0) end, 96)
        f.free:SetPoint("RIGHT", f.save, "LEFT", -10, 0)
        f.clear = UI.textButton(f, "清除", function() UI.saveFee(nil) end, 96)
        f.clear:SetPoint("RIGHT", f.free, "LEFT", -10, 0)
        f:Hide()
        feePopup = f
    end
    local sv = O().services(S().selfAuthor())
    local current
    if target.recipe then
        current = sv.recipeFees[target.recipe]
        ns.Recipes.setIcon(feePopup.icon, target.recipe, target.skill)
    else
        current = sv.fees[target.skill]
        Icons.setProfessionIcon(feePopup.icon, { skillLineID = target.skill })
    end
    feePopup.boxes.set(current or 0)
    feePopup:Show()
    return feePopup
end

-- fee nil = not filled in (R-4.4).
function UI.saveFee(fee)
    local t = feeTarget
    if not t then return end
    if t.recipe then O().setRecipeFee(t.recipe, fee, t.skill) else O().setFee(t.skill, fee) end
    if feePopup then feePopup:Hide() end
    UI.refresh()
    if t.back == "services" then UI.openServices() end
    if ns.Recipes and ns.Framework.isModuleShown("recipes") then ns.Recipes.refresh() end
end

---------------------------------------------------------------------------
-- 我的服務 (GF-002-E, owner: 「工匠設定要按右鍵不明顯」): one window with every
-- profession I can craft for: 接單 on/off and the default fee, plus the way
-- to the per-recipe fees (the recipe page, only my recipes, 「我的工錢」).
---------------------------------------------------------------------------

UI.SERVICES_NAME = "GreenFangToolkit_ServicesPopup"
UI.SERVICES_FIELDS = { "專業", "接單", "工錢" }

function UI.feeText(fee)
    local kind = UI.feeKind(fee)
    if kind == "unset" then return "沒填" end
    if kind == "free" then return "免費" end
    return UI.money(fee)
end

function UI.drawServices()
    local f = UI.servicesPopup
    if not f then return end
    local skills = UI.ownCraftSkills()
    local sv = O().services(S().selfAuthor())
    for i, skill in ipairs(skills) do
        local r = f.rows[i]
        if not r then
            local y = -84 - (i - 1) * ns.WINDOW_ROW
            r = {}
            r.icon = f:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(ns.ICON, ns.ICON)
            r.icon:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X, y + 6)
            r.name = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            r.name:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X + 40, y - 2)
            r.active = ns.checkBox(f, "接單", f.colActive, y, function(on) O().setActive(r.skill, on); UI.refresh() end)
            r.feeTex = f:CreateTexture(nil, "ARTWORK"); r.feeTex:SetSize(18, 18)
            r.feeTex:SetPoint("TOPLEFT", f, "TOPLEFT", f.colFee, y - 4)
            r.fee = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            r.fee:SetPoint("TOPLEFT", f, "TOPLEFT", f.colFee + 24, y - 2)
            r.edit = UI.textButton(f, "工錢", function() UI.editFee({ skill = r.skill, back = "services" }) end)
            r.edit:SetPoint("TOPLEFT", f, "TOPLEFT", f.colFee + 150, y + 4)
            f.rows[i] = r
        end
        r.skill = skill
        Icons.setProfessionIcon(r.icon, { skillLineID = skill })
        r.name:SetText(ns.Data.skillName(nil, skill) or tostring(skill))
        r.active.set(sv.active[skill] == true)
        showFee(r.feeTex, r.fee, sv.fees[skill])
        r.fee:SetText(UI.feeText(sv.fees[skill]))
        for _, w in ipairs({ r.icon, r.name, r.active, r.active.label, r.fee, r.edit }) do w:Show() end
    end
    for i = #skills + 1, #f.rows do
        local r = f.rows[i]
        for _, w in ipairs({ r.icon, r.name, r.active, r.active.label, r.feeTex, r.fee, r.edit }) do w:Hide() end
    end
    f.none:SetText(#skills == 0 and "沒有可以接單的專業" or "")
    f:SetHeight(160 + math.max(1, #skills) * ns.WINDOW_ROW)
end

function UI.openServices()
    if not UI.servicesPopup then
        local f = ns.popupWindow(UI.SERVICES_NAME, 620, 260)
        f:SetPoint("CENTER", 0, 80)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("我的服務") end
        f.colActive, f.colFee = 230, 340
        UI.fieldLabel(f, "專業", UI.FIELD_X, -46)
        UI.fieldLabel(f, "接單", f.colActive, -46)
        UI.fieldLabel(f, "工錢", f.colFee, -46)
        f.rows = {}
        f.none = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.none:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X, -90)
        -- Per-recipe fees: the recipe page with only my recipes, each row has 「我的工錢」.
        f.recipeFees = UI.textButton(f, "配方工錢", function()
            f:Hide()
            UI.showMyRecipes()
        end, 120)
        f.recipeFees:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", UI.FIELD_X, 16)
        f.close = UI.textButton(f, "完成", function() f:Hide() end, 96)
        f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f:Hide()
        UI.servicesPopup = f
    end
    UI.servicesPopup:Show()
    UI.drawServices()
    return UI.servicesPopup
end

-- The recipe page on my own recipes (their fee column and 「我的工錢」 buttons).
function UI.showMyRecipes()
    local me = ns.Data.player().guid
    if not ns.Recipes then return end
    ns.Recipes.show(me)
end

---------------------------------------------------------------------------
-- ＋下單 (GF-002-E, owner: 「我看不出來如何下單」): choose a recipe (search),
-- then the order popup opens. Only recipes someone else can make.
---------------------------------------------------------------------------

UI.PICKER_NAME = "GreenFangToolkit_RecipePicker"
UI.PICKER_ROWS = 10

function UI.pickerRows(query)
    local index = ns.Recipes and ns.Recipes.index()
    if not index then return {} end
    local skills = ns.Recipes.professionsInIndex(index)
    -- GF-UI-B: in the test mode my own recipes too (a test order to myself).
    return ns.Recipes.rowsFor(index, skills, query or "", nil, { who = not O().testOn() and "others" or nil })
end

function UI.drawPicker()
    local f = UI.picker
    if not f then return end
    local rows = UI.pickerRows(f.query)
    f.list = rows
    for i = 1, UI.PICKER_ROWS do
        local b = f.rows[i]
        local r = rows[i]
        if r then
            ns.Recipes.setIcon(b.icon, r.id, r.skill)
            b.name:SetText(r.name)
            local others = {}
            for _, m in ipairs(r.crafters) do if not m.self then others[#others + 1] = m end end
            local fee = O().lowestFee(others, r.skill, r.id)
            showFee(b.feeTex, b.fee, fee)
            b.fee:SetText(UI.feeText(fee))
            b.data = r
            b:Show()
        else
            b:Hide(); b.data = nil
        end
    end
    f.empty:SetText(#rows == 0 and "找不到配方" or "")
    f.count:SetText(#rows > UI.PICKER_ROWS and ("+" .. (#rows - UI.PICKER_ROWS)) or "")
end

function UI.openPicker()
    if not UI.picker then
        local f = ns.popupWindow(UI.PICKER_NAME, 640, 540)
        f:SetPoint("CENTER", 0, 60)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("下單：選配方") end
        UI.fieldLabel(f, "搜尋", UI.FIELD_X, -46)
        local X = UI.controlX({ "搜尋" })
        local box = ns.Theme.editBox(f)
        box:SetSize(300, 30)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", X + 6, -40)
        box:SetAutoFocus(true)
        box:SetMaxLetters(60)
        box:SetScript("OnTextChanged", function(self) f.query = str(self:GetText()); UI.drawPicker() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        box:SetScript("OnEnterPressed", function() local r = f.list and f.list[1]; if r then UI.pickRecipe(r) end end)
        f.search = box
        UI.fieldLabel(f, "配方", UI.FIELD_X, -90)
        UI.fieldLabel(f, "工錢", 430, -90)
        f.rows = {}
        for i = 1, UI.PICKER_ROWS do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(590, ns.PAGE_ROW)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X, -114 - (i - 1) * (ns.PAGE_ROW + 2))
            if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(ns.ROW_ICON, ns.ROW_ICON); b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
            b.name = b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
            b.name:SetPoint("LEFT", b, "LEFT", 38, 0); b.name:SetWidth(360); b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(false)
            b.feeTex = b:CreateTexture(nil, "ARTWORK"); b.feeTex:SetSize(18, 18); b.feeTex:SetPoint("LEFT", b, "LEFT", 406, 0)
            b.fee = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)); b.fee:SetPoint("LEFT", b, "LEFT", 428, 0)
            b:SetScript("OnClick", function(self) if self.data then UI.pickRecipe(self.data) end end)
            f.rows[i] = b
        end
        f.empty = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X, -116)
        f.count = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", UI.FIELD_X, 20)
        f:Hide()
        UI.picker = f
    end
    UI.picker.query = ""
    UI.picker.search:SetText("")
    UI.picker:Show()
    UI.drawPicker()
    return UI.picker
end

-- A recipe was chosen: the order popup (it replaces the picker: one window at a time).
function UI.pickRecipe(r)
    local pick = UI.pendingCrafter
    UI.pendingCrafter, UI.pendingMark = nil, nil
    return UI.openOrder({ recipe = r.id, skill = r.skill, crafters = r.crafters, crafter = pick })
end

-- The fee a recipe row shows (GF-002-E, R-4.4): mine for my own recipe, else
-- the lowest of the crafters in the list (other members). nil = nobody filled it in.
function UI.rowFee(data, crafters)
    if data.mine and not crafters then
        return O().feeFor(ns.Data.player().guid, data.skill, data.id)
    end
    local others = {}
    for _, m in ipairs(crafters or data.crafters or {}) do if not m.self then others[#others + 1] = m end end
    if #others == 0 then return O().feeFor(ns.Data.player().guid, data.skill, data.id) end
    return O().lowestFee(others, data.skill, data.id)
end

---------------------------------------------------------------------------
-- Recipe page and roster hooks (R-4.2, R-5.1)
---------------------------------------------------------------------------

-- Extra right-click items on a recipe row.
function UI.recipeMenuItems(data)
    local items = {}
    if not data then return items end
    local others = {}
    for _, m in ipairs(data.crafters or {}) do if not m.self then others[#others + 1] = m end end
    if #others > 0 or (data.mine and O().testOn()) then
        items[#items + 1] = { text = "下單", fn = function()
            local pick = UI.pendingCrafter
        UI.pendingCrafter, UI.pendingMark = nil, nil
        UI.openOrder({ recipe = data.id, skill = data.skill, crafters = data.crafters, crafter = pick })
        end }
    end
    if data.mine then
        items[#items + 1] = { text = "我的工錢", fn = function() UI.editFee({ recipe = data.id, skill = data.skill }) end }
    end
    return items
end

-- Right-click on someone's profession icon on the roster.
function UI.rosterMenuItems(member, skill)
    if not (member and member.guid and skill) then return {} end
    if member.guid == ns.Data.player().guid then return {} end
    return { { text = "下單給 " .. ns.shortName(member.name), fn = function()
        local a = S().authorOf(member.guid)
        ns.Recipes.show(member.guid, skill)
        -- Review 7-6: used by the next 下單 only, and forgotten after two minutes.
        UI.pendingCrafter = a
        local mark = {}
        UI.pendingMark = mark
        ns.after(120, function() if UI.pendingMark == mark then UI.pendingCrafter = nil end end)
    end } }
end

---------------------------------------------------------------------------
-- Trade strip (R-7.2): only while trading with the other side of an open order.
---------------------------------------------------------------------------

local strip
function UI.tradeChanged()
    local t = ns.Delivery.current()
    if not t then if strip then strip:Hide() end return end
    if not strip then
        strip = CreateFrame("Frame", "GreenFangToolkit_TradeStrip", UIParent)
        strip:SetSize(300, 30)
        ns.makeOpaque(strip, 0)
        strip.rows = {}
    end
    local anchor = _G.TradeFrame or UIParent
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    local me = S().selfAuthor()
    local list = O().between(me, t.other)
    local got = ns.Delivery.sum(t.snap.theirs)
    local gave = ns.Delivery.sum(t.snap.mine)
    for i, v in ipairs(list) do
        local r = strip.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, strip)
            r:SetSize(296, 26)
            r:SetPoint("TOPLEFT", strip, "TOPLEFT", 2, -2 - (i - 1) * 26)
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
            r.text = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT); r.text:SetPoint("LEFT", r, "LEFT", 30, 0)
            r.state = r:CreateTexture(nil, "ARTWORK"); r.state:SetSize(18, 18); r.state:SetPoint("RIGHT", r, "RIGHT", -4, 0)
            strip.rows[i] = r
        end
        itemIcon(r.icon, v.item, v.skill)
        local moving = (v.customer == me and got[v.item] or gave[v.item]) or 0
        local done = math.min(v.qty, v.progress + moving)
        r.text:SetText("x" .. v.qty .. "  " .. done .. "/" .. v.qty .. "   " .. UI.money(v.fee))
        setIcon(r.state, done >= v.qty and "deal" or "waiting")
        r:Show()
    end
    for i = #list + 1, #strip.rows do strip.rows[i]:Hide() end
    strip:SetHeight(math.max(30, #list * 26 + 4))
    strip:Show()
end
function UI.tradeHidden() if strip then strip:Hide() end end
function UI.strip() return strip end

---------------------------------------------------------------------------
-- ⚖ next to the auction house (R-8.4)
---------------------------------------------------------------------------

local scanButton
function UI.auctionShown()
    local anchor = _G.AuctionHouseFrame or _G.AuctionFrame
    if not anchor then return end
    if not scanButton then
        scanButton = iconButton(UIParent, 32, "scan", "掃描", function(_, mouse)
            if mouse == "RightButton" then P().stopScan() else P().startScan() end
            UI.scanChanged()
        end)
        scanButton:SetFrameStrata("HIGH")
        scanButton.ring = scanButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scanButton.ring:SetPoint("CENTER")
    end
    scanButton:ClearAllPoints()
    scanButton:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, -30)
    scanButton:Show()
    UI.scanChanged()
end
function UI.auctionHidden() if scanButton then scanButton:Hide() end end

function UI.scanChanged()
    if not scanButton then return end
    local s = P().scanState()
    local last = P().db().scan.last
    if s.state == "running" then
        local pct = s.total and s.total > 0 and math.floor((s.done or 0) * 100 / s.total) or nil
        scanButton.ring:SetText(pct and (pct .. "%") or "...")
    elseif s.state == "done" then
        scanButton.ring:SetText(UI.tex("deal", 16))
    else
        scanButton.ring:SetText("")
    end
    local ago = last and last.at and math.floor((S().serverNow() - last.at) / 3600)
    scanButton.tip = "掃描" .. (ago and ("  " .. ago .. " 小時前") or "")
end
function UI.scanButton() return scanButton end

---------------------------------------------------------------------------
-- Minimap number (R-6.8)
---------------------------------------------------------------------------

function UI.updateBadge()
    local b = ns.Framework.minimapButton
    if not b then return end
    if not b.ordersBadge then
        b.ordersBadge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.ordersBadge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 2)
        b.ordersBadge:SetTextColor(1, 0.82, 0)
        -- GF-UI-B (GF-UI-A §2.12): a 1 px black outline, so it does not blur into the map.
        local fs = b.ordersBadge
        if fs.GetFont and fs.SetFont then
            local path, size = fs:GetFont()
            if path then pcall(fs.SetFont, fs, path, size, "OUTLINE") end
        end
    end
    local n = ns.guildState() == "target" and O().attentionCount() or 0
    b.ordersBadge:SetText(n > 0 and tostring(n) or "")
    UI.badgeCount = n
end

O().onChanged = function()
    ns.coalesce("orders-page", 1, function()
        UI.updateBadge()
        if ns.Framework.isModuleShown("orders") then UI.refresh() end
    end)
end
