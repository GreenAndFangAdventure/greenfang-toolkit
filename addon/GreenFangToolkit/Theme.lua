-- Theme (GF-UI-D, 0.15.0): the toolkit's one look, built only from what the
-- game ships. Dark flat panels with a 1 px grey line, gold for what is chosen,
-- outlined see-through buttons (no red UIPanelButton), table headers with a
-- thin line, coins in gold / silver / copper.
--
-- Hard rule (owner): only the game's own art and fonts. Every texture here is
-- a Blizzard path or a flat colour (SetColorTexture, else the game's white
-- 8x8 tinted); every font copies a Blizzard font object. Nothing is packaged.
-- The texture table with fallbacks is tests/addon/MANUAL.md「GF-UI-D 外觀」.
--
-- Every page builds its buttons, check boxes, edit boxes, windows, headers
-- and separators here; no other file names UIPanelButtonTemplate,
-- UIPanelCloseButton, UICheckButtonTemplate, InputBoxTemplate or
-- BasicFrameTemplateWithInset (tests/addon/theme_tests.lua).

local _, ns = ...

local T = {}
ns.Theme = T

---------------------------------------------------------------------------
-- Colours (one table). r, g, b[, a].
---------------------------------------------------------------------------

T.C = {
    bg = { 0.055, 0.055, 0.065, 0.97 },   -- windows, menus, popups: near black, never see-through
    panel = { 1, 1, 1, 0.025 },           -- a panel inside a window (the module list)
    line = { 0.27, 0.27, 0.29, 1 },       -- 1 px borders and separators
    lineHover = { 0.58, 0.58, 0.6, 1 },   -- the border under the mouse
    gold = { 1, 0.82, 0, 1 },             -- chosen / active, section headers
    goldFill = { 1, 0.82, 0, 0.12 },      -- the faint fill of a chosen tab or toggle
    goldLine = { 1, 0.82, 0, 0.55 },      -- the line under a section header, a focused box
    fill = { 1, 1, 1, 0.03 },             -- a button's own fill (almost transparent)
    hover = { 1, 1, 1, 0.07 },            -- a button / row under the mouse
    head = { 1, 1, 1, 0.05 },             -- table header bar
    input = { 0, 0, 0, 0.55 },            -- edit boxes, check boxes
    text = { 0.88, 0.88, 0.88 },          -- button text
    muted = { 0.62, 0.62, 0.64 },         -- the X, not chosen
    good = { 0.25, 1, 0.35 }, bad = { 1, 0.3, 0.3 },
    coinGold = { 1, 0.82, 0 }, coinSilver = { 0.8, 0.8, 0.84 }, coinCopper = { 0.93, 0.62, 0.36 },
}

-- Game textures (each with a fallback; MANUAL「GF-UI-D 外觀」).
T.TEX = {
    flat = "Interface\\Buttons\\WHITE8X8",                       -- tinted fills and 1 px lines
    flatFallback = "Interface\\Tooltips\\UI-Tooltip-Background",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    checkFallback = "Interface\\RaidFrame\\ReadyCheck-Ready",
    rowGlow = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight", -- row hover / chosen glow
    rowGlowFallback = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    coin = { gold = "Interface\\MoneyFrame\\UI-GoldIcon", silver = "Interface\\MoneyFrame\\UI-SilverIcon",
        copper = "Interface\\MoneyFrame\\UI-CopperIcon" },
}

-- Colour a texture: a flat colour where the client can, else the game's white
-- square tinted (the tooltip background as the last resort).
function T.color(tex, c, alpha)
    if not tex then return tex end
    local a = alpha or c[4] or 1
    if tex.SetColorTexture then
        tex:SetColorTexture(c[1], c[2], c[3], a)
    else
        if not (tex.SetTexture and tex:SetTexture(T.TEX.flat) ~= false) then tex:SetTexture(T.TEX.flatFallback) end
        if tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3]) end
        if tex.SetAlpha then tex:SetAlpha(a) end
    end
    return tex
end

---------------------------------------------------------------------------
-- Fonts: copies of the game's font objects, never under 16 px.
---------------------------------------------------------------------------

local function font(name, base, size, c)
    if type(CreateFont) ~= "function" then return nil end
    local ok, f = pcall(CreateFont, name)
    if not ok or not f then return nil end
    local src = _G[base]
    if src and f.CopyFontObject then pcall(f.CopyFontObject, f, src) end
    local path, flags
    if src and src.GetFont then local p, _, fl = src:GetFont(); path, flags = p, fl end
    if not path then return nil end -- no such game font here: the caller's fallback
    if f.SetFont then pcall(f.SetFont, f, path, size, flags or "") end
    if c and f.SetTextColor then pcall(f.SetTextColor, f, c[1], c[2], c[3]) end
    return name
end
T.FONT = {
    button = font("GreenFangToolkitButton16", "GameFontHighlight", 16, T.C.text) or ns.LABEL_FONT,
    hover = font("GreenFangToolkitButtonHover16", "GameFontHighlight", 16, { 1, 1, 1 }) or ns.LABEL_FONT,
    chosen = ns.FIELD_FONT, -- gold
    header = font("GreenFangToolkitHeader16", "GameFontNormal", 16, T.C.gold) or ns.FIELD_FONT,
    close = font("GreenFangToolkitClose18", "GameFontHighlight", 18, T.C.muted) or ns.TITLE_FONT,
    closeHover = font("GreenFangToolkitCloseHover18", "GameFontNormal", 18, T.C.gold) or ns.TITLE_FONT,
    number = font("GreenFangToolkitNumber16", "NumberFontNormal", 16) or ns.LABEL_FONT,
}

---------------------------------------------------------------------------
-- Lines and panels
---------------------------------------------------------------------------

-- A 1 px frame of colour c around region f (layer, inset). Returns the edges with
-- set(c) to recolour and show(on).
function T.border(f, c, layer, inset)
    inset = inset or 0
    local spec = {
        { "TOPLEFT", inset, -inset, "TOPRIGHT", -inset, -inset, nil, 1 },
        { "BOTTOMLEFT", inset, inset, "BOTTOMRIGHT", -inset, inset, nil, 1 },
        { "TOPLEFT", inset, -inset, "BOTTOMLEFT", inset, inset, 1, nil },
        { "TOPRIGHT", -inset, -inset, "BOTTOMRIGHT", -inset, inset, 1, nil },
    }
    local edges = {}
    for _, e in ipairs(spec) do
        local t = f:CreateTexture(nil, layer or "BORDER")
        t:SetPoint(e[1], f, e[1], e[2], e[3])
        t:SetPoint(e[4], f, e[4], e[5], e[6])
        if e[7] then t:SetWidth(e[7]) else t:SetHeight(e[8]) end
        T.color(t, c)
        edges[#edges + 1] = t
    end
    function edges.set(col) for _, t in ipairs(edges) do T.color(t, col) end; edges.c = col end
    function edges.show(on) for _, t in ipairs(edges) do if on then t:Show() else t:Hide() end end end
    edges.c = c
    return edges
end

-- A flat fill over all of f.
function T.fill(f, c, layer, sub)
    local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetAllPoints(f)
    T.color(t, c)
    return t
end

-- The window / menu look: the near-black fill and a 1 px grey line. f.gfOpaque is
-- the fill (GF-001-D20: never see-through).
function T.panel(f, inset)
    if not f or f.gfOpaque then return f end
    inset = inset or 0
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    T.color(bg, T.C.bg)
    f.gfEdges = T.border(f, T.C.line, "BORDER")
    f.gfOpaque = bg
    return f
end

-- A 1 px line between two points of f: horizontal from (x1, y) to the right edge
-- minus x2, or vertical when vertical = true (x, from y1 to the bottom minus y2).
function T.hline(f, y, x1, x2, c)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetPoint("TOPLEFT", f, "TOPLEFT", x1 or 0, y)
    t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(x2 or 0), y)
    t:SetHeight(1)
    T.color(t, c or T.C.line)
    return t
end
function T.vline(f, x, y1, y2, c, fromRight)
    local t = f:CreateTexture(nil, "BORDER")
    local side = fromRight and "TOPRIGHT" or "TOPLEFT"
    t:SetPoint(side, f, side, x, -(y1 or 0))
    t:SetPoint(fromRight and "BOTTOMRIGHT" or "BOTTOMLEFT", f, fromRight and "BOTTOMRIGHT" or "BOTTOMLEFT", x, y2 or 0)
    t:SetWidth(1)
    T.color(t, c or T.C.line)
    return t
end

-- A small gold section header (16 px) with a thin gold line under it across width w.
function T.sectionHeader(parent, text, x, y, w)
    local fs = ns.freeText(parent:CreateFontString(nil, "ARTWORK", T.FONT.header))
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text or "")
    if w then
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 22)
        t:SetSize(w, 1)
        T.color(t, T.C.goldLine)
        fs.line = t
    end
    return fs
end

-- A table's column-header bar: a faint fill and a 1 px line under it.
function T.headerBar(f)
    f.gfHeadFill = T.fill(f, T.C.head, "BACKGROUND")
    local t = f:CreateTexture(nil, "BORDER")
    t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    t:SetHeight(1)
    T.color(t, T.C.line)
    f.gfHeadLine = t
    return f
end

-- A bar under a list (the roster's action bar): the panel fill and a line on top.
function T.barPanel(f)
    f.gfBarFill = T.fill(f, T.C.panel, "BACKGROUND")
    local t = f:CreateTexture(nil, "BORDER")
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    t:SetHeight(1)
    T.color(t, T.C.line)
    f.gfBarLine = t
    return f
end

---------------------------------------------------------------------------
-- The outlined button: normal / hover / chosen / disabled.
---------------------------------------------------------------------------

local function enabled(b)
    if b.IsEnabled then
        local v = b:IsEnabled()
        if v == false or v == 0 then return false end
    end
    return true
end

-- Redraw a themed button for its state.
function T.refresh(b)
    if not b or not b.gfEdges then return end
    if b.gfSelected then
        b.gfEdges.set(T.C.gold)
        T.color(b.gfFill, T.C.goldFill)
    elseif not enabled(b) then
        b.gfEdges.set({ T.C.line[1], T.C.line[2], T.C.line[3], 0.55 })
        T.color(b.gfFill, T.C.fill, 0)
    else
        b.gfEdges.set(T.C.line)
        T.color(b.gfFill, T.C.fill)
    end
end

-- A text button: see-through with a 1 px grey line; under the mouse the line
-- lightens and the text turns white; chosen = a gold line, a faint gold fill and
-- gold text. Text goes through the button's own SetText (as UIPanelButton did).
function T.button(parent, text, w, h, name)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(w or 80, h or ns.BUTTON_H)
    b.gfTheme = "button"
    b.gfFill = T.fill(b, T.C.fill, "BACKGROUND")
    b.gfEdges = T.border(b, T.C.line, "BORDER")
    -- The HIGHLIGHT layer shows only under the mouse (the client does it).
    b.gfHover = T.fill(b, T.C.hover, "HIGHLIGHT")
    b.gfHoverEdges = T.border(b, T.C.lineHover, "HIGHLIGHT")
    -- Its own text from the start, so a drop-down can move it left before any SetText.
    if b.SetFontString and b.CreateFontString then
        local fs = b:CreateFontString(nil, "ARTWORK", T.FONT.button)
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        pcall(b.SetFontString, b, fs)
    end
    if b.SetNormalFontObject then pcall(b.SetNormalFontObject, b, T.FONT.button) end
    if b.SetHighlightFontObject then pcall(b.SetHighlightFontObject, b, T.FONT.hover) end
    if b.SetDisabledFontObject then pcall(b.SetDisabledFontObject, b, ns.DISABLED_FONT) end
    if b.SetPushedTextOffset then pcall(b.SetPushedTextOffset, b, 1, -1) end
    if b.HookScript then
        b:HookScript("OnEnable", T.refresh)
        b:HookScript("OnDisable", T.refresh)
    end
    -- Pages mark a chosen tab with LockHighlight (the grid tabs, the time picker):
    -- on a theme button that is the chosen look.
    b.LockHighlight = function(self) T.setSelected(self, true) end
    b.UnlockHighlight = function(self) T.setSelected(self, false) end
    if text then b:SetText(text) end
    return b
end

-- Chosen (a tab, a toggle, the current module): gold line, faint gold fill, gold text.
function T.setSelected(b, on)
    b.gfSelected = on and true or false
    local f = on and T.FONT.chosen or T.FONT.button
    if b.SetNormalFontObject then pcall(b.SetNormalFontObject, b, f) end
    if b.SetHighlightFontObject then pcall(b.SetHighlightFontObject, b, on and T.FONT.chosen or T.FONT.hover) end
    if b.SetDisabledFontObject then pcall(b.SetDisabledFontObject, b, on and T.FONT.chosen or ns.DISABLED_FONT) end
    T.refresh(b)
end

-- A row of tabs (buttons of the same height, 8 px apart); onSelect(key).
-- items = { { key, text, w } }. Returns the strip with select(key).
function T.tabStrip(parent, items, x, y, onSelect)
    local strip = { buttons = {}, key = nil }
    local cx = x
    for _, it in ipairs(items) do
        local w = it.w or (ns.labelWidth(it.text) + 28)
        local b = T.button(parent, it.text, w, ns.BUTTON_H)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y)
        b.key = it.key
        b:SetScript("OnClick", function() strip.select(it.key); if onSelect then onSelect(it.key) end end)
        strip.buttons[#strip.buttons + 1] = b
        cx = cx + w + 8
    end
    function strip.select(key)
        strip.key = key
        for _, b in ipairs(strip.buttons) do T.setSelected(b, b.key == key) end
    end
    return strip
end

-- The X in a window's top right corner: the letter in the game font, grey, gold
-- under the mouse; no red button.
T.CLOSE_SIZE = 28
function T.closeButton(f, onClose)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(T.CLOSE_SIZE, T.CLOSE_SIZE)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    b.gfTheme = "close"
    b.gfHover = T.fill(b, T.C.hover, "HIGHLIGHT")
    if b.SetNormalFontObject then pcall(b.SetNormalFontObject, b, T.FONT.close) end
    if b.SetHighlightFontObject then pcall(b.SetHighlightFontObject, b, T.FONT.closeHover) end
    b:SetText("X")
    b.tip = "關閉"
    b.fieldNamed = "關閉" -- an X needs no written name
    b:SetScript("OnClick", function() if onClose then onClose() else f:Hide() end end)
    return b
end

---------------------------------------------------------------------------
-- Check box, edit box, window
---------------------------------------------------------------------------

-- A check box: a dark 18 px box with a grey line inside a 28 px hit area; the
-- game's check mark when ticked, a lighter line under the mouse.
T.CHECK_BOX = 18
function T.checkBox(parent, size)
    size = size or 28
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(size, size)
    c.gfTheme = "check"
    local inset = math.floor((size - T.CHECK_BOX) / 2)
    local box = c:CreateTexture(nil, "BACKGROUND")
    box:SetPoint("TOPLEFT", c, "TOPLEFT", inset, -inset)
    box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -inset, inset)
    T.color(box, T.C.input)
    c.gfBox = box
    c.gfEdges = T.border(c, T.C.line, "BORDER", inset)
    c.gfHoverEdges = T.border(c, T.C.lineHover, "HIGHLIGHT", inset)
    if c.SetCheckedTexture then
        local ok = pcall(c.SetCheckedTexture, c, T.TEX.check)
        if not ok then pcall(c.SetCheckedTexture, c, T.TEX.checkFallback) end
        local t = c.GetCheckedTexture and c:GetCheckedTexture()
        if t and t.ClearAllPoints then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", c, "TOPLEFT", inset - 3, -(inset - 3))
            t:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -(inset - 3), inset - 3)
        end
    end
    return c
end

-- An edit box: dark fill, 1 px grey line, gold line while typing in it; the
-- toolkit's 16 px font; ESC leaves it.
function T.editBox(parent, w, h, name)
    local e = CreateFrame("EditBox", name, parent)
    e:SetSize(w or 120, h or 30)
    e.gfTheme = "edit"
    if e.SetFontObject then pcall(e.SetFontObject, e, ns.LABEL_FONT) end
    if e.SetTextInsets then e:SetTextInsets(6, 6, 0, 0) end
    if e.SetAutoFocus then e:SetAutoFocus(false) end
    e.gfFill = T.fill(e, T.C.input, "BACKGROUND")
    e.gfEdges = T.border(e, T.C.line, "BORDER")
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if e.HookScript then
        e:HookScript("OnEditFocusGained", function(self) self.gfEdges.set(T.C.goldLine) end)
        e:HookScript("OnEditFocusLost", function(self) self.gfEdges.set(T.C.line) end)
    end
    return e
end

-- A window: the panel look, a gold title on the left, a line under the title
-- and the X. f.TitleText and f.CloseButton as the game's framed windows had them.
T.TITLE_H = 30
function T.window(name, parent, w, h)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(w, h)
    f.gfTheme = "window"
    T.panel(f)
    f.TitleText = ns.freeText(f:CreateFontString(nil, "OVERLAY", ns.TITLE_FONT))
    f.TitleText:SetPoint("TOP", f, "TOP", 0, -7)
    f.gfTitleLine = T.hline(f, -T.TITLE_H, 1, 1)
    f.CloseButton = T.closeButton(f)
    f.gfClose = f.CloseButton
    return f
end

---------------------------------------------------------------------------
-- Coins: numbers in gold / silver / copper with the game's coin icons.
---------------------------------------------------------------------------

local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
T.hex = hex
function T.coinText(copper, size)
    local c = math.floor(tonumber(copper) or 0)
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local n = size or 0
    local out = {}
    local function part(v, col, tex) out[#out + 1] = hex(col) .. v .. "|r|T" .. tex .. ":" .. n .. ":" .. n .. ":2:0|t" end
    if g > 0 then part(g, T.C.coinGold, T.TEX.coin.gold) end
    if s > 0 then part(s, T.C.coinSilver, T.TEX.coin.silver) end
    if cu > 0 or #out == 0 then part(cu, T.C.coinCopper, T.TEX.coin.copper) end
    return table.concat(out, " ")
end
