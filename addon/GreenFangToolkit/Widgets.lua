-- Widgets (GF-002-I, spec GF-002 §17.3, design review GF-UI-A §1.5 / §1.7):
-- small shared pieces that show how the toolkit decided something, without
-- sentences: a state badge (icon + 2-3 characters, colored by state), its
-- ✓✗ checklist tooltip (ReadyCheck marks, items of at most 6 characters and a
-- number), a gold 2 px frame, the list-row selection, a disabled look, and a
-- card of icons, arrows and numbers (the rules card).
--
-- Nothing here knows the rules: the checklist only draws what the caller
-- hands it (Adventure.whyState for adventure tickets).

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
    for _, g in ipairs(why.groups or {}) do
        out[#out + 1] = { text = G().markup(W.STATE_ART[g.state] or "state_open", W.CHECK_ICON) .. " " .. str(g.name),
            color = W.COLOR.gold }
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
        G().set(b.icon, W.STATE_ART[why.state] or "state_open")
        local c = W.color(why.state)
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
    local b = ns.createFrame("Button", nil, f, "UIPanelCloseButton")
    b:SetSize(W.CLOSE_SIZE, W.CLOSE_SIZE)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    if b.gfNoTemplate then
        -- No template on this client: the game's close art by hand.
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
        ns.Icons.set(b.tex, W.CLOSE_ART)
    end
    b.tip = "關閉"
    b.infoOnly = false
    b.fieldNamed = "關閉" -- an X needs no written name (the game's own)
    b:SetScript("OnClick", function() if onClose then onClose() else f:Hide() end end)
    f.gfClose = b
    return b
end
W.CLOSE_ART = "Interface\Buttons\UI-Panel-MinimizeButton-Up"

---------------------------------------------------------------------------
-- GF-002-J: a small confirmation (刪除, 清除): a short noun phrase, 確定 / 取消, the X.
-- A menu-level frame: ESC and a click outside cancel it.
---------------------------------------------------------------------------

W.CONFIRM_NAME = "GreenFangToolkit_Confirm"
local confirm
function W.confirm(text, onYes)
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
            f.onYes = nil
            f:Hide()
            if fn then fn() end
        end, 90)
        f.no = ns.OrdersUI.textButton(f, "取消", function() f.onYes = nil; f:Hide() end, 90)
        W.closeButton(f)
        f:Hide()
        confirm = f
    end
    local f = confirm
    f.text:SetText(text or "")
    f.onYes = onYes
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
