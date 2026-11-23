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
    if type(GetCoinTextureString) == "function" then
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
function UI.tex(key, size)
    return "|T" .. (UI.ICON[key] or key) .. ":" .. tostring(size or 14) .. "|t"
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

local function iconButton(parent, size, key, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    setIcon(b.tex, key)
    b.badge = b:CreateTexture(nil, "OVERLAY")
    b.badge:SetSize(math.floor(size / 2), math.floor(size / 2))
    b.badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.badge:Hide()
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
    return b
end
UI.iconButton = iconButton

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

local ROW_HEIGHT = 28
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
        out[#out + 1] = { header = "收到的", count = #received }
        for _, r in ipairs(received) do out[#out + 1] = r end
    end
    if #placed > 0 then
        out[#out + 1] = { header = "我下的", count = #placed }
        for _, r in ipairs(placed) do out[#out + 1] = r end
    end
    return out
end

local function press(row, button)
    local v = row.view
    local key = v.id .. "|" .. button
    if UI.DELAYED[button] then
        if pendingPress[key] then pendingPress[key] = nil; UI.refresh(); return "undone" end
        pendingPress[key] = true
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
    row:SetSize(930, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.att = row:CreateTexture(nil, "ARTWORK"); row.att:SetSize(16, 16); row.att:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.item = iconButton(row, 22, "unknown", nil)
    row.item:SetPoint("LEFT", row, "LEFT", 22, 0)
    row.item:SetScript("OnEnter", function(self) itemTooltip(self, self:GetParent().view and self:GetParent().view.item) end)
    row.qty = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.qty:SetPoint("LEFT", row, "LEFT", 50, 0); row.qty:SetWidth(70); row.qty:SetJustifyH("LEFT")
    row.cls = row:CreateTexture(nil, "ARTWORK"); row.cls:SetSize(16, 16); row.cls:SetPoint("LEFT", row, "LEFT", 124, 0)
    row.who = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.who:SetPoint("LEFT", row, "LEFT", 144, 0); row.who:SetWidth(150); row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)
    row.mats = {}
    for k = 1, 5 do
        local m = iconButton(row, 18, "unknown", nil)
        m:SetPoint("LEFT", row, "LEFT", 300 + (k - 1) * 22, 0)
        m:SetScript("OnEnter", function(self) itemTooltip(self, self.itemID) end)
        row.mats[k] = m
    end
    row.coin = row:CreateTexture(nil, "ARTWORK"); row.coin:SetSize(14, 14); row.coin:SetPoint("LEFT", row, "LEFT", 420, 0)
    row.fee = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.fee:SetPoint("LEFT", row, "LEFT", 438, 0); row.fee:SetWidth(110); row.fee:SetJustifyH("LEFT")
    row.state = iconButton(row, 22, "waiting", nil)
    row.state:SetPoint("LEFT", row, "LEFT", 560, 0)
    row.buttons = {}
    for k = 1, 3 do
        local b = iconButton(row, 22, "deal", nil)
        b:SetPoint("LEFT", row, "LEFT", 610 + (k - 1) * 28, 0)
        row.buttons[k] = b
    end
    row.head = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.head:SetPoint("LEFT", row, "LEFT", 6, 0)
    rowWidgets[i] = row
    return row
end

local function fillRow(row, data, i)
    row.bg:SetColorTexture(0.17, 0.2, 0.18, i % 2 == 0 and 0.35 or 0.09)
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
    if v.customer == me and v.guild and not v.crafter then
        setIcon(row.cls, "guild")
        row.who:SetText("公會")
        row.who:SetTextColor(0.9, 0.9, 0.9)
    else
        local m = memberOf(other)
        if m and Icons.setClassIcon(row.cls, m.classToken) then row.cls:Show() else row.cls:Hide() end
        row.who:SetText(m and ns.shortName(m.name) or "?")
        local c = Icons.classColor(m and m.classToken)
        row.who:SetTextColor(c[1], c[2], c[3])
        if m and m.online then row.who:SetText(row.who:GetText() .. " " .. UI.tex("online", 10)) end
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
    showFee(row.coin, row.fee, v.fee > 0 and v.fee or v.feeQuoted)
    if v.paid then row.fee:SetText(row.fee:GetText() .. " " .. UI.tex("deal", 12)) end
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
    -- Buttons this viewer may press (R-6.2).
    local list = O().buttons(v, me)
    for j, b in ipairs(row.buttons) do
        local name = list[j]
        if name then
            local spec = UI.BUTTON[name]
            local key = v.id .. "|" .. name
            if pendingPress[key] then setIcon(b.tex, "undo"); b.tip = "復原"
            else setIcon(b.tex, spec.icon); b.tip = spec.tip end
            if spec.hammer then setIcon(b.badge, "hammer") else b.badge:Hide() end
            b:SetScript("OnClick", function() press(row, name) end)
            b.action = name
            b:Show()
        else
            b:Hide(); b.action = nil
        end
    end
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

local function refreshProfBar()
    if not profBar then return end
    local skills = UI.ownCraftSkills()
    local sv = O().services(S().selfAuthor())
    for i, skill in ipairs(skills) do
        local b = profButtons[i]
        if not b then
            b = iconButton(profBar, 30, "unknown", nil)
            b:SetPoint("LEFT", profBar, "LEFT", (i - 1) * 74, 0)
            b.feeTex = b:CreateTexture(nil, "ARTWORK"); b.feeTex:SetSize(12, 12)
            b.feeTex:SetPoint("LEFT", b, "RIGHT", 4, 0)
            b.feeText = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            b.feeText:SetPoint("LEFT", b, "RIGHT", 18, 0)
            profButtons[i] = b
        end
        Icons.setProfessionIcon(b.tex, { skillLineID = skill })
        local on = sv.active[skill] == true
        if on then setIcon(b.badge, "hammer") else b.badge:Hide() end
        if b.tex.SetDesaturated then b.tex:SetDesaturated(not on) end
        b.skill = skill
        b.tip = (ns.Data.skillName(nil, skill) or "") .. (on and "  接單中" or "")
        showFee(b.feeTex, b.feeText, sv.fees[skill])
        b:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then UI.editFee({ skill = self.skill })
            else O().setActive(self.skill, not O().isActive(ns.Data.player().guid, self.skill)); UI.refresh() end
        end)
        b:Show()
    end
    for i = #skills + 1, #profButtons do profButtons[i]:Hide() end
end
UI.profButtons = function() return profButtons end

function UI.refresh()
    UI.updateBadge()
    if not panel then return end
    refreshProfBar()
    shownRows = UI.pageRows()
    content:SetHeight(math.max(1, #shownRows * ROW_HEIGHT))
    UI.layoutRows()
end

local function build(p)
    profBar = CreateFrame("Frame", nil, p)
    profBar:SetSize(900, 34)
    profBar:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -40)
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -84)
    scroll:SetPoint("BOTTOMRIGHT", -40, 40)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(930, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() UI.layoutRows() end)
    UI.historyButton = iconButton(p, 24, "history", "歷史", function() UI.showHistory() end)
    UI.historyButton:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -170, 10)
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
    local crafters = {}
    for _, m in ipairs(opts.crafters or {}) do if not m.self then crafters[#crafters + 1] = m end end
    O().sortCrafters(crafters, skill)
    local target = opts.crafter
    if not target then
        local first = crafters[1]
        if first and O().isActive(first.guid, skill) then target = S().authorOf(first.guid) end
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
    local id = O().place({ recipe = d.recipe, item = d.item, skill = d.skill, qty = d.qty, crafter = d.crafter,
        mats = mats, fee = d.fee, feeQuoted = d.feeQuoted, quote = est.total })
    if popup then popup:Hide() end
    UI.refresh()
    return id
end

local function moneyBoxes(parent, x, y, onChange)
    local boxes = {}
    for i, unit in ipairs({ "gold", "silver", "copper" }) do
        local e = ns.createFrame("EditBox", nil, parent, "InputBoxTemplate")
        e:SetSize(i == 1 and 46 or 28, 20)
        e:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * 64, y)
        e:SetAutoFocus(false)
        if e.SetNumeric then e:SetNumeric(true) end
        e:SetMaxLetters(i == 1 and 5 or 2)
        local coin = parent:CreateTexture(nil, "ARTWORK")
        coin:SetSize(12, 12)
        coin:SetPoint("LEFT", e, "RIGHT", 2, 0)
        Icons.set(coin, "Interface\\MoneyFrame\\UI-" .. (unit == "gold" and "Gold" or unit == "silver" and "Silver" or "Copper") .. "Icon")
        e:SetScript("OnTextChanged", function(_, user) if user ~= false then onChange() end end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        boxes[i] = e
    end
    function boxes.get()
        local g, s, c = tonumber(boxes[1]:GetText()) or 0, tonumber(boxes[2]:GetText()) or 0, tonumber(boxes[3]:GetText()) or 0
        return g * 10000 + s * 100 + c
    end
    function boxes.set(c)
        c = math.floor(c or 0)
        boxes[1]:SetText(c >= 10000 and tostring(math.floor(c / 10000)) or "")
        boxes[2]:SetText((c % 10000) >= 100 and tostring(math.floor(c / 100) % 100) or "")
        boxes[3]:SetText(c % 100 > 0 and tostring(c % 100) or "")
    end
    return boxes
end

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
            b.count:SetText("x" .. row.need)
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

local function createPopup()
    if popup then return popup end
    local f = ns.popupWindow(UI.POPUP_NAME, 360, 250)
    f:SetPoint("CENTER", 0, 60)
    f:EnableMouse(true)
    if UISpecialFrames then table.insert(UISpecialFrames, UI.POPUP_NAME) end
    f.item = iconButton(f, 36, "unknown", nil)
    f.item:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -30)
    f.item:SetScript("OnEnter", function(self) itemTooltip(self, draft and draft.item) end)
    f.marketIcon = f:CreateTexture(nil, "ARTWORK"); f.marketIcon:SetSize(14, 14)
    f.marketIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 220, -40)
    Icons.set(f.marketIcon, UI.ICON.gold)
    f.market = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.market:SetPoint("LEFT", f.marketIcon, "RIGHT", 4, 0)
    -- Quantity
    f.minus = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.minus:SetSize(24, 22)
    f.minus:SetPoint("TOPLEFT", f, "TOPLEFT", 66, -36); f.minus:SetText("－")
    f.qty = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"); f.qty:SetPoint("LEFT", f.minus, "RIGHT", 10, 0)
    f.plus = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.plus:SetSize(24, 22)
    f.plus:SetPoint("LEFT", f.minus, "RIGHT", 40, 0); f.plus:SetText("＋")
    local function step(n)
        local y = draft.reagents and draft.reagents.yield or 1
        draft.qty = math.max(y, math.min(200, draft.qty + n * y))
        drawPopup()
    end
    f.minus:SetScript("OnClick", function() step(-1) end)
    f.plus:SetScript("OnClick", function() step(1) end)
    -- Guild order or a named crafter
    f.guild = iconButton(f, 28, "guild", "公會單", function() draft.crafter = "*"; UI.applyFee(draft); drawPopup() end)
    f.guild:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -80)
    f.named = iconButton(f, 28, "unknown", "指定工匠", function(self) UI.pickCrafter(self) end)
    f.named:SetPoint("LEFT", f.guild, "RIGHT", 16, 0)
    f.namedActive = f:CreateTexture(nil, "OVERLAY"); f.namedActive:SetSize(14, 14)
    f.namedActive:SetPoint("TOPRIGHT", f.named, "TOPRIGHT", 4, 4)
    -- Materials: click = I give it (ticked) / you give it
    f.mats = {}
    for i = 1, 6 do
        local b = iconButton(f, 26, "unknown", nil, function(self)
            draft.mats[self.itemID] = not draft.mats[self.itemID] or nil
            drawPopup()
        end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 18 + (i - 1) * 54, -124)
        b:SetScript("OnEnter", function(self) itemTooltip(self, self.itemID) end)
        b.count = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        b.count:SetPoint("LEFT", b, "RIGHT", 2, 0)
        f.mats[i] = b
    end
    f.matsIcon = f:CreateTexture(nil, "ARTWORK"); f.matsIcon:SetSize(16, 16)
    f.matsIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -162)
    Icons.set(f.matsIcon, UI.ICON.bag)
    f.matsCost = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.matsCost:SetPoint("LEFT", f.matsIcon, "RIGHT", 6, 0)
    f.feeIcon = f:CreateTexture(nil, "ARTWORK"); f.feeIcon:SetSize(16, 16)
    f.feeIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 140, -162)
    Icons.setProfessionIcon(f.feeIcon, { skillLineID = 164 })
    f.fee = moneyBoxes(f, 162, -160, function()
        if not draft then return end
        draft.fee, draft.feeEdited = f.fee.get(), true
        popup.total:SetText(UI.totalText(UI.estimateOf(draft), draft.fee))
    end)
    f.feeKind = f:CreateTexture(nil, "OVERLAY"); f.feeKind:SetSize(14, 14)
    f.feeKind:SetPoint("LEFT", f.feeIcon, "LEFT", -18, 0)
    f.sumIcon = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.sumIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -194); f.sumIcon:SetText("＝")
    f.total = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.total:SetPoint("LEFT", f.sumIcon, "RIGHT", 8, 0)
    f.send = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.send:SetSize(90, 24)
    f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14); f.send:SetText("下單")
    f.send:SetScript("OnClick", function() UI.submit() end)
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
        items[#items + 1] = { text = mark .. ns.shortName(m.name) .. (m.online and (" " .. UI.tex("online", 10)) or "") .. feeText,
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
        local f = ns.popupWindow(UI.FEE_NAME, 260, 120)
        f:SetPoint("CENTER", 0, 120)
        f:EnableMouse(true)
        if UISpecialFrames then table.insert(UISpecialFrames, UI.FEE_NAME) end
        f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(28, 28)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -30)
        f.boxes = moneyBoxes(f, 56, -34, function() end)
        f.save = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.save:SetSize(60, 22)
        f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12); f.save:SetText("確定")
        f.save:SetScript("OnClick", function() UI.saveFee(f.boxes.get()) end)
        f.clear = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.clear:SetSize(60, 22)
        f.clear:SetPoint("RIGHT", f.save, "LEFT", -8, 0); f.clear:SetText("清除")
        f.clear:SetScript("OnClick", function() UI.saveFee(nil) end)
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
    if t.recipe then O().setRecipeFee(t.recipe, fee) else O().setFee(t.skill, fee) end
    if feePopup then feePopup:Hide() end
    UI.refresh()
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
    if #others > 0 then
        items[#items + 1] = { text = "下單", fn = function()
            local pick = UI.pendingCrafter
        UI.pendingCrafter = nil
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
        UI.pendingCrafter = a
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
            r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", r, "LEFT", 30, 0)
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
