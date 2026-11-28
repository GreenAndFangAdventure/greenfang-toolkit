-- Help (GF-UI-R, owner 2026-11-28: 「我希望整個介面都盡量單純，且有一個說明
-- 按鈕，按下後會標示介面功能說明」): one 「說明」 button in the title line of
-- the main window (left of 業務通知) and of the pop-ups that have help
-- (下單, 開單, 業務排程, 同步與診斷, the 業務通知 list). A press puts a
-- dim layer over that window; every registered part shown there gets a gold
-- frame and a number, and the mouse on it says in a line or two what it is
-- for. Press 「結束說明」 again, ESC, another page, closing the window or
-- combat ends it. The layer takes every click, so nothing under it is pressed.
--
-- GF-UI-T (owner, 0.16.22: 「按下說明應說明文字要直接有」): the words are on
-- screen at once, no mouse needed: a 「號碼對照」 panel lists every number with
-- its name and line (「1 搜尋：打配方或物品的名字…」). It sits beside the window
-- when the screen has room; else in an empty part of the window; else inside
-- the largest frame (right part, below that frame's number), so it never
-- covers another part or number. A long list
-- scrolls (wheel or bar); the mouse on a line lights its frame.
--
-- What each page has: HelpText.lua (H.TEXT the words, H.register the parts),
-- one table per page; a part not on screen at that moment is skipped.
--
-- Cost: nothing until the button is pressed. The layer, the frames and the
-- numbers are made the first time (one pool per window) and reused; no event,
-- no timer, no OnUpdate. Placing reads each part's position once. Not in combat.
-- Game art only: the round "i" of the friends list (then the question mark).

local _, ns = ...
local str = ns.str

local H = {}
ns.Help = H

H.BUTTON_TEXT, H.STOP_TEXT = "說明", "結束說明"
H.BUTTON_TIP = "標出這個視窗每個功能，旁邊直接列出每個號碼的說明"
H.STOP_TIP = "再按一次、按 ESC 或切換頁面都會結束說明"
H.COMBAT_TEXT = "戰鬥中不能開說明，脫離戰鬥後再按一次「說明」。"
H.ICONS = { "Interface\\FriendsFrame\\InformationIcon", "Interface\\Common\\help-i", "Interface\\Icons\\INV_Misc_QuestionMark" }
H.ICON = 16
H.BUTTON_H = 24
H.PAD = 3          -- the frame sits this far outside the part
H.TAG_H = 20       -- the number's box
H.TAG_GAP = 2      -- a number outside its frame keeps this gap
H.DIM = 0.45       -- the dark layer's alpha
H.LEVEL = 200      -- the layer is this many levels above its window (above the page's own buttons)
-- GF-UI-T: the 「號碼對照」 panel.
H.LEGEND_TITLE = "號碼對照（每個框上的號碼是什麼）"
H.LEGEND_W = 300       -- beside the window
H.LEGEND_MAX_W = 460   -- inside a frame: at most this wide, at most LEGEND_SHARE of the frame
H.LEGEND_SHARE = 0.5
H.LEGEND_MIN_W = 240
H.LEGEND_MIN_H = 150
H.LEGEND_GAP = 6       -- from the window / inside the frame
H.LEGEND_PAD = 8
H.LEGEND_TITLE_H = 24
H.LEGEND_ROW_GAP = 6

H.pages = {}       -- page key -> { { key = text key, get = function, area = function, when = function } }
H.TEXT = H.TEXT or {} -- text key -> { name, line } (HelpText.lua)
H.POPUP = {}       -- pop-up frame name -> page key (HelpText.lua)
H.made = { buttons = 0, overlays = 0, boxes = 0, tags = 0, legends = 0 } -- frames ever made (tests: none until used)
H.active = nil     -- { root, key, boxes = { ... } } while help is shown

-- Add parts to a page (several calls add up). entry: key = H.TEXT key;
-- get() -> one frame / font string / texture, or a table of them (nested
-- tables too; the visible ones are framed together); or area() -> anchor,
-- x, y, w, h (a rectangle from the anchor's top left, y downwards negative);
-- when() -> false skips it.
function H.register(page, entries)
    local list = H.pages[page] or {}
    H.pages[page] = list
    for _, e in ipairs(entries or {}) do list[#list + 1] = e end
    return list
end

---------------------------------------------------------------------------
-- Positions (screen pixels). Tests replace H.rectOf (the mock has no layout).
---------------------------------------------------------------------------

local function num(v) return type(v) == "number" and v or nil end

function H.rectOf(o)
    if not (o and type(o.GetLeft) == "function") then return nil end
    local ok, l, r, t, b = pcall(function() return o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom() end)
    l, r, t, b = num(l), num(r), num(t), num(b)
    if not (ok and l and r and t and b) or r <= l or t <= b then return nil end
    local s = (type(o.GetEffectiveScale) == "function" and num(o:GetEffectiveScale())) or 1
    return { l = l * s, r = r * s, t = t * s, b = b * s }
end

local function scaleOf(o) return (o and type(o.GetEffectiveScale) == "function" and num(o:GetEffectiveScale())) or 1 end

local function isObject(x) return type(x) == "table" and type(x.IsVisible) == "function" end
local function shown(o)
    if not isObject(o) then return false end
    local ok, v = pcall(o.IsVisible, o)
    return ok and v and true or false
end

local function union(a, b)
    if not a then return b end
    if not b then return a end
    return { l = math.min(a.l, b.l), r = math.max(a.r, b.r), t = math.max(a.t, b.t), b = math.min(a.b, b.b) }
end

-- The visible objects in x (an object, or tables of them), framed together.
local function collect(x, depth, acc)
    if depth > 4 or type(x) ~= "table" then return acc end
    if isObject(x) then
        if shown(x) then acc = union(acc, H.rectOf(x)) end
        return acc
    end
    for _, v in pairs(x) do acc = collect(v, depth + 1, acc) end
    return acc
end

-- The part's rectangle, or nil (not shown, no position).
function H.rectOfEntry(e)
    if type(e.when) == "function" then
        local ok, v = pcall(e.when)
        if not ok or not v then return nil end
    end
    if type(e.area) == "function" then
        local ok, anchor, x, y, w, h = pcall(e.area)
        if not (ok and shown(anchor) and num(x) and num(y) and num(w) and num(h)) or w <= 0 or h <= 0 then return nil end
        local a = H.rectOf(anchor)
        if not a then return nil end
        local s = scaleOf(anchor)
        local l, t = a.l + x * s, a.t + y * s
        return { l = l, t = t, r = l + w * s, b = t - h * s }
    end
    if type(e.get) == "function" then
        local ok, x = pcall(e.get)
        if not ok then return nil end
        return collect(x, 0, nil)
    end
    return nil
end

local function overlaps(a, b)
    return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end
H.overlaps = overlaps
local function inside(a, R) return a.l >= R.l and a.r <= R.r and a.b >= R.b and a.t <= R.t end
H.inside = inside

-- Frames for the parts, in order; one that would cover an earlier one is
-- tried without the outside padding, then left out. Pure (tests call it).
-- Returns { { entry, rect } }.
-- The space between two rectangles (0 when they touch or overlap).
local function gapBetween(a, b)
    local dx = math.max(b.l - a.r, a.l - b.r, 0)
    local dy = math.max(b.b - a.t, a.b - b.t, 0)
    return math.max(dx, dy)
end

function H.placeBoxes(R, entries, pad, obstacles)
    local out = {}
    local raw = {}
    for i, e in ipairs(entries) do raw[i] = H.rectOfEntry(e) or false end
    for i, e in ipairs(entries) do
        local r = raw[i]
        if r then
            -- Close neighbours share the gap: each frame takes at most half of it.
            local own = pad
            for j, o in ipairs(raw) do
                if j ~= i and o and gapBetween(r, o) < 2 * pad then own = math.min(own, math.max(0, gapBetween(r, o) / 2 - 0.5)) end
            end
            local placed
            for _, p in ipairs({ own, 0 }) do
                local c = { l = math.max(r.l - p, R.l + 1), r = math.min(r.r + p, R.r - 1),
                    t = math.min(r.t + p, R.t - 1), b = math.max(r.b - p, R.b + 1) }
                if c.r - c.l >= 4 and c.t - c.b >= 4 then
                    local free = true
                    for _, o in ipairs(out) do if overlaps(c, o.rect) then free = false; break end end
                    for _, o in ipairs(obstacles or {}) do if free and overlaps(c, o) then free = false end end
                    if free then placed = c; break end
                end
            end
            if placed then out[#out + 1] = { entry = e, rect = placed } end
        end
    end
    return out
end

-- Where each number goes: just left of its frame, above it, inside its top
-- left corner, right of it, below it; the first place inside the window that
-- touches no other frame, number or obstacle. Pure. Returns rects (nil = no
-- number: the frame still has its text on the mouse).
function H.placeTags(R, boxes, sizes, gap, obstacles)
    local tags = {}
    local function free(c, own)
        if not inside(c, R) then return false end
        for j, o in ipairs(boxes) do if j ~= own and overlaps(c, o.rect) then return false end end
        for _, t in pairs(tags) do if overlaps(c, t) then return false end end
        for _, o in ipairs(obstacles or {}) do if overlaps(c, o) then return false end end
        return true
    end
    for i, b in ipairs(boxes) do
        local w, h = sizes[i][1], sizes[i][2]
        local r = b.rect
        local tries = {
            { l = r.l - gap - w, t = r.t },
            { l = r.l, t = r.t + gap + h },
            { l = r.l + 1, t = r.t - 1, own = true },
            { l = r.r + gap, t = r.t },
            { l = r.l, t = r.b - gap },
        }
        for _, c in ipairs(tries) do
            local rect = { l = c.l, r = c.l + w, t = c.t, b = c.t - h }
            local ok = free(rect, i)
            if ok and c.own and not inside(rect, r) then ok = false end
            if ok and not c.own and overlaps(rect, r) then ok = false end
            if ok then tags[i] = rect; break end
        end
    end
    return tags
end

-- GF-UI-T: where the 「號碼對照」 panel goes (screen pixels). R the window, S
-- the screen (nil = unknown), boxes / tags from above; o: w (width beside the
-- window), maxW, share, minW, minH, gap, skip (the space a number takes at a
-- frame's top), heightAt(w) -> the height the panel wants at width w. Pure.
-- o.obstacles: more rects to keep clear (the 說明 button).
-- Returns rect, where ("side" | "free" | "frame" | "corner"), host (the frame's index).
function H.placeLegend(R, S, boxes, tags, o)
    local gap, minH = o.gap or 0, o.minH or 0
    -- 1. Beside the window: right, left (as tall as the window at most), then below, above.
    if S then
        local w = o.w
        local h = math.min(o.heightAt(w), R.t - R.b)
        for _, l in ipairs({ R.r + gap, R.l - gap - w }) do
            local c = { l = l, r = l + w, t = R.t, b = R.t - h }
            if inside(c, S) then return c, "side" end
        end
        local below = R.b - gap - S.b
        if below >= minH then
            local c = { l = R.l, r = R.l + w, t = R.b - gap, b = R.b - gap - math.min(h, below) }
            if inside(c, S) then return c, "side" end
        end
        local above = S.t - (R.t + gap)
        if above >= minH then
            local c = { l = R.l, r = R.l + w, b = R.t + gap, t = R.t + gap + math.min(h, above) }
            if inside(c, S) then return c, "side" end
        end
    end
    -- 2. An empty part of the window (touches no frame, number or obstacle): the
    -- tallest one (up to what the panel wants), tops and lefts taken from the edges.
    local free, freeH
    do
        local w = math.min(o.w, R.r - R.l - 2 * gap)
        local want = o.heightAt(w)
        local obs = {}
        for _, b in ipairs(boxes) do obs[#obs + 1] = b.rect end
        for _, t in pairs(tags or {}) do obs[#obs + 1] = t end
        for _, x in ipairs(o.obstacles or {}) do obs[#obs + 1] = x end
        local lefts, tops = { R.r - gap - w, R.l + gap }, { R.t - gap }
        for _, x in ipairs(obs) do
            lefts[#lefts + 1] = x.r + gap; lefts[#lefts + 1] = x.l - gap - w
            tops[#tops + 1] = x.b - gap
        end
        local best, bestH
        for _, l in ipairs(lefts) do
            if l >= R.l + gap - 0.01 and l + w <= R.r - gap + 0.01 then
                for _, t in ipairs(tops) do
                    if t <= R.t - gap + 0.01 then
                        local floor, ok = R.b + gap, true
                        for _, x in ipairs(obs) do
                            if x.l < l + w and l < x.r then
                                if x.t > t and x.b < t then ok = false; break end
                                if x.t <= t then floor = math.max(floor, x.t + gap) end
                            end
                        end
                        local h = math.min(t - floor, want)
                        if ok and h >= minH and h > (bestH or 0) + 0.5 then best, bestH = { l = l, r = l + w, t = t, b = t - h }, h end
                    end
                end
            end
        end
        free, freeH = best, bestH
        if free and freeH >= want - 0.5 then return free, "free" end
    end
    -- 3. Inside the largest frame that holds it: its right part, below its number
    -- (when the empty part found above is much shorter).
    local best, bestArea, host
    for i, b in ipairs(boxes) do
        local r = b.rect
        local inner = { l = r.l + gap, r = r.r - gap, t = r.t - gap - (o.skip or 0), b = r.b + gap }
        local iw, ih = inner.r - inner.l, inner.t - inner.b
        if iw >= o.minW and ih >= minH and iw * ih > (bestArea or 0) then best, bestArea, host = inner, iw * ih, i end
    end
    if best then
        local w = math.max(o.minW, math.min(o.maxW, (best.r - best.l) * (o.share or 1)))
        w = math.min(w, best.r - best.l)
        local h = math.min(o.heightAt(w), best.t - best.b)
        local c = { l = best.r - w, r = best.r, t = best.t, b = best.t - h }
        local clear = true
        for _, t in pairs(tags or {}) do if overlaps(c, t) then clear = false end end
        -- An empty part shows at least two thirds of what the frame would: it wins
        -- (it covers nothing).
        if free and freeH * 1.5 >= h then return free, "free" end
        if clear then return c, "frame", host end
    end
    if free then return free, "free" end
    -- 4. Last: the window's bottom right corner.
    local w = math.min(o.w, R.r - R.l - 2 * gap)
    local h = math.min(o.heightAt(w), (R.t - R.b) / 2)
    return { l = R.r - gap - w, r = R.r - gap, b = R.b + gap, t = R.b + gap + h }, "corner"
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or ns.LABEL_FONT)
    fs:SetText(text or "")
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

local function setIcon(tex)
    for _, path in ipairs(H.ICONS) do
        if ns.Icons.set(tex, path) then tex.gfPath = path; return true end
    end
    return false
end

H.BUTTON_W = H.ICON + 4 + math.max(ns.labelWidth(H.BUTTON_TEXT), ns.labelWidth(H.STOP_TEXT)) + 16

local function paintButton(b, on)
    b.label:SetText(on and H.STOP_TEXT or H.BUTTON_TEXT)
    if b.edges then b.edges.set(on and ns.Theme.C.selLine or ns.Theme.C.line) end
    if b.fill then ns.Theme.color(b.fill, on and ns.Theme.C.selFill or ns.Theme.C.fill) end
    b.gfOn = on and true or false
end

local function buttonTip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(self.gfOn and H.STOP_TEXT or H.BUTTON_TEXT, 1, 1, 1)
    GameTooltip:AddLine(self.gfOn and H.STOP_TIP or H.BUTTON_TIP, 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
end

-- Put the 「說明」 button on a window (once). place(b) anchors it; else the
-- title line, left of the X. key: the page key (nil = the main window's page).
function H.attach(root, key, place)
    if not root then return nil end
    if root.gfHelpButton then return root.gfHelpButton end
    local Th = ns.Theme
    local b = CreateFrame("Button", nil, root)
    b:SetSize(H.BUTTON_W, H.BUTTON_H)
    b.fill = Th.fill(b, Th.C.fill, "BACKGROUND")
    b.edges = Th.border(b, Th.C.line, "BORDER")
    b.gfHover = Th.fill(b, Th.C.hover, "HIGHLIGHT")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(H.ICON, H.ICON)
    b.icon:SetPoint("LEFT", b, "LEFT", 6, 0)
    setIcon(b.icon)
    b.label = label(b, H.BUTTON_TEXT, ns.LABEL_FONT)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    if type(place) == "function" then place(b)
    else b:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(Th.CLOSE_SIZE + 8), -3) end
    if b.SetFrameLevel and root.GetFrameLevel then
        local lv = num(root:GetFrameLevel())
        if lv then b:SetFrameLevel(lv + H.LEVEL + 20) end
    end
    b:SetScript("OnClick", function() H.toggle(root) end)
    b:SetScript("OnEnter", buttonTip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b.fieldNamed = H.BUTTON_TEXT
    root.gfHelpButton, root.gfHelpKey = b, key
    H.made.buttons = H.made.buttons + 1
    paintButton(b, false)
    return b
end

---------------------------------------------------------------------------
-- The layer, its frames and numbers (pooled per window)
---------------------------------------------------------------------------

local function boxEnter(self)
    if not GameTooltip then return end
    local t = H.TEXT[self.gfKey] or { self.gfKey, "" }
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local g = ns.Theme.C.gold
    GameTooltip:AddLine(tostring(self.gfNo) .. ". " .. str(t[1]), g[1], g[2], g[3])
    if str(t[2]) ~= "" then GameTooltip:AddLine(t[2], 1, 1, 1, true) end
    GameTooltip:Show()
    if self.gfLit then ns.Theme.color(self.gfLit, ns.Theme.C.gold, 0.12) end
end
local function boxLeave(self)
    if GameTooltip then GameTooltip:Hide() end
    if self.gfLit then ns.Theme.color(self.gfLit, ns.Theme.C.gold, 0) end
end

local function overlayFor(root)
    if root.gfHelpOverlay then return root.gfHelpOverlay end
    local Th = ns.Theme
    local ov = CreateFrame("Button", nil, root)
    ov:SetAllPoints(root)
    if ov.SetFrameLevel and root.GetFrameLevel then
        local lv = num(root:GetFrameLevel())
        if lv then ov:SetFrameLevel(lv + H.LEVEL) end
    end
    ov:EnableMouse(true)
    if ov.RegisterForClicks then ov:RegisterForClicks("AnyUp") end
    ov:SetScript("OnClick", function() end) -- the click stops here
    if ov.EnableMouseWheel then ov:EnableMouseWheel(true) end
    ov:SetScript("OnMouseWheel", function() end) -- and the wheel (no list scrolls under it)
    ov.dim = ov:CreateTexture(nil, "BACKGROUND")
    ov.dim:SetAllPoints(ov)
    Th.color(ov.dim, { 0, 0, 0, H.DIM })
    ov.boxes, ov.tags = {}, {}
    ov:Hide()
    ov:SetScript("OnHide", function() if H.active and H.active.root == root then H.stop() end end)
    -- ESC ends help first (above its window), without closing the window.
    ov.gfEscLevel = (root.gfEscLevel or ns.ESC_LEVEL.window) + 0.5
    ns.escRegister(ov, ov.gfEscLevel)
    root.gfHelpOverlay = ov
    H.made.overlays = H.made.overlays + 1
    return ov
end

local function boxAt(ov, i)
    local b = ov.boxes[i]
    if b then return b end
    local Th = ns.Theme
    b = CreateFrame("Frame", nil, ov)
    b.gfLit = Th.fill(b, Th.C.gold, "BACKGROUND")
    Th.color(b.gfLit, Th.C.gold, 0)
    b.edges = Th.border(b, Th.C.gold, "BORDER")
    b:EnableMouse(true)
    b:SetScript("OnEnter", boxEnter)
    b:SetScript("OnLeave", boxLeave)
    ov.boxes[i] = b
    H.made.boxes = H.made.boxes + 1
    return b
end

local function tagAt(ov, i)
    local t = ov.tags[i]
    if t then return t end
    local Th = ns.Theme
    t = CreateFrame("Frame", nil, ov)
    t.fill = Th.fill(t, Th.C.selFill, "BACKGROUND")
    t.edges = Th.border(t, Th.C.gold, "BORDER")
    t.text = t:CreateFontString(nil, "OVERLAY", Th.FONT.chosen or ns.FIELD_FONT)
    t.text:SetPoint("CENTER", t, "CENTER", 0, 0)
    t:EnableMouse(true)
    t:SetScript("OnEnter", function(self) if self.gfBox then boxEnter(self.gfBox) end end)
    t:SetScript("OnLeave", function(self) if self.gfBox then boxLeave(self.gfBox) end end)
    ov.tags[i] = t
    H.made.tags = H.made.tags + 1
    return t
end

-- GF-UI-T: the 「號碼對照」 panel (one per layer, its lines pooled).
local function legendFor(ov)
    if ov.legend then return ov.legend end
    local Th = ns.Theme
    local lg = CreateFrame("Frame", nil, ov)
    if lg.SetFrameLevel and ov.GetFrameLevel then
        local lv = num(ov:GetFrameLevel())
        if lv then lg:SetFrameLevel(lv + 10) end
    end
    lg.fill = Th.fill(lg, Th.C.form, "BACKGROUND")
    lg.edges = Th.border(lg, Th.C.gold, "BORDER")
    lg:EnableMouse(true) -- a click on it stops here too
    lg.title = label(lg, H.LEGEND_TITLE, Th.FONT.chosen or ns.FIELD_FONT)
    lg.title:SetPoint("TOPLEFT", lg, "TOPLEFT", H.LEGEND_PAD, -H.LEGEND_PAD)
    lg.rows, lg.offset = {}, 0
    lg.bar = ns.Widgets.scrollBar(lg, 100, function(o) lg.offset = o; H.layoutLegend(lg) end)
    lg.bar:SetPoint("TOPRIGHT", lg, "TOPRIGHT", -4, -(H.LEGEND_PAD + H.LEGEND_TITLE_H))
    if lg.EnableMouseWheel then lg:EnableMouseWheel(true) end
    lg:SetScript("OnMouseWheel", function(_, delta) lg.bar.scrollBy(-(tonumber(delta) or 0)) end)
    lg:Hide()
    ov.legend = lg
    H.made.legends = H.made.legends + 1
    return lg
end

local function legendRow(lg, i)
    local r = lg.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, lg)
    r.text = r:CreateFontString(nil, "OVERLAY", ns.LABEL_FONT)
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    if r.text.SetJustifyH then r.text:SetJustifyH("LEFT") end
    if r.text.SetJustifyV then r.text:SetJustifyV("TOP") end
    if r.text.SetWordWrap then r.text:SetWordWrap(true) end
    r:EnableMouse(true)
    -- The mouse on a line lights its frame.
    r:SetScript("OnEnter", function(self) if self.gfBox and self.gfBox.gfLit then ns.Theme.color(self.gfBox.gfLit, ns.Theme.C.gold, 0.18) end end)
    r:SetScript("OnLeave", function(self) if self.gfBox then boxLeave(self.gfBox) end end)
    lg.rows[i] = r
    return r
end

-- The line of number i: 「1 名稱：說明」, the number and name in gold.
function H.legendLine(i, key)
    local t = H.TEXT[key] or { key, "" }
    local line = "|cffcfb77e" .. tostring(i) .. "  " .. str(t[1]) .. "|r"
    if str(t[2]) ~= "" then line = line .. "：" .. t[2] end
    return line
end

-- Fill the lines for the shown frames; each line's height at the text width w.
local function fillLegend(lg, boxes, w)
    lg.count, lg.heights = #boxes, {}
    for i, b in ipairs(boxes) do
        local r = legendRow(lg, i)
        r.gfBox = b
        r.text:SetWidth(w)
        r.text:SetHeight(0) -- measure the whole wrapped text
        r.text:SetText(H.legendLine(i, b.gfKey))
        local h = math.ceil(ns.textHeight(r.text, w))
        r.text:SetHeight(h)
        r:SetSize(w, h)
        lg.heights[i] = h
    end
    for i = #boxes + 1, #lg.rows do lg.rows[i]:Hide(); lg.rows[i].gfBox = nil end
end

-- The panel's whole height at text width w (title and padding included).
local function legendHeight(lg, boxes, w)
    fillLegend(lg, boxes, w)
    local h = 2 * H.LEGEND_PAD + H.LEGEND_TITLE_H
    for i = 1, lg.count do h = h + lg.heights[i] + H.LEGEND_ROW_GAP end
    return h
end

local function textWidthFor(w) return w - 2 * H.LEGEND_PAD - ns.Widgets.SCROLL_W - 4 end

-- Show the lines from lg.offset that fit; the bar scrolls when they do not all fit.
function H.layoutLegend(lg)
    local room = (lg.gfH or 0) - 2 * H.LEGEND_PAD - H.LEGEND_TITLE_H
    local n = lg.count or 0
    -- The last start that still shows the end of the list.
    local maxOff, used = math.max(0, n - 1), 0 -- the last line always can be reached
    for i = n, 1, -1 do
        used = used + lg.heights[i] + H.LEGEND_ROW_GAP
        if used > room + H.LEGEND_ROW_GAP then break end
        maxOff = i - 1
    end
    lg.offset = math.max(0, math.min(lg.offset or 0, maxOff))
    local y = -(H.LEGEND_PAD + H.LEGEND_TITLE_H)
    local shown = 0
    for i = 1, n do
        local r = lg.rows[i]
        local h = lg.heights[i]
        if i > lg.offset and (i == lg.offset + 1 or (-y + h) <= (lg.gfH - H.LEGEND_PAD) + 0.5) then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", lg, "TOPLEFT", H.LEGEND_PAD, y)
            r:Show()
            y = y - h - H.LEGEND_ROW_GAP
            shown = shown + 1
        else
            r:Hide()
        end
    end
    lg.bar.setHeight(math.max(40, room))
    lg.bar.sync(lg.offset, n, n - maxOff)
    if maxOff > 0 then lg.bar:Show() else lg.bar:Hide() end
    lg.shown = shown
    return shown
end

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------

-- The page key of a window: its own (a pop-up), else the main window's page.
function H.keyOf(root)
    if root and root.gfHelpKey then return root.gfHelpKey end
    return ns.Framework and ns.Framework.current() or nil
end

-- The parts of a window: its page's, then (main window) the shared ones.
function H.entriesFor(root)
    local key = H.keyOf(root)
    local list = {}
    for _, e in ipairs(H.pages[key] or {}) do list[#list + 1] = e end
    if not (root and root.gfHelpKey) then
        for _, e in ipairs(H.pages.frame or {}) do list[#list + 1] = e end
    end
    return list, key
end

function H.isActive(root)
    return H.active ~= nil and (root == nil or H.active.root == root)
end

function H.start(root)
    if not root then return false end
    if ns.inCombat() then ns.say(H.COMBAT_TEXT); return false end
    H.stop()
    local entries, key = H.entriesFor(root)
    -- A menu or list open on the page goes first (it would sit above the layer).
    if (root.gfEscLevel or 0) < ns.ESC_LEVEL.grid and ns.closeMenus then ns.closeMenus() end
    if GameTooltip then GameTooltip:Hide() end
    if ns.UI and ns.UI.hideRosterCard then ns.UI.hideRosterCard() end
    local ov = overlayFor(root)
    ov:Show()
    local R = H.rectOf(ov) or H.rectOf(root)
    local placed, tags = {}, {}
    local s = scaleOf(ov)
    if R then
        local obstacles = {}
        local hb = root.gfHelpButton and H.rectOf(root.gfHelpButton)
        if hb then obstacles[1] = hb end
        placed = H.placeBoxes(R, entries, H.PAD * s, obstacles)
        local sizes = {}
        for i in ipairs(placed) do
            sizes[i] = { (math.max(H.TAG_H, ns.labelWidth(tostring(i)) + 10)) * s, H.TAG_H * s }
        end
        tags = H.placeTags(R, placed, sizes, H.TAG_GAP * s, obstacles)
    end
    for i, p in ipairs(placed) do
        local r = p.rect
        local b = boxAt(ov, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ov, "TOPLEFT", (r.l - R.l) / s, (r.t - R.t) / s)
        b:SetSize((r.r - r.l) / s, (r.t - r.b) / s)
        b.gfKey, b.gfNo, b.gfRect = p.entry.key, i, r
        boxLeave(b)
        b:Show()
        local tr = tags[i]
        local t = tagAt(ov, i)
        if tr then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", ov, "TOPLEFT", (tr.l - R.l) / s, (tr.t - R.t) / s)
            t:SetSize((tr.r - tr.l) / s, (tr.t - tr.b) / s)
            t.text:SetText(tostring(i))
            t.gfBox, t.gfRect = b, tr
            t:Show()
        else
            t.gfBox, t.gfRect = nil, nil
            t:Hide()
        end
    end
    for i = #placed + 1, #ov.boxes do ov.boxes[i]:Hide(); ov.boxes[i].gfRect = nil end
    for i = #placed + 1, #ov.tags do ov.tags[i]:Hide(); ov.tags[i].gfRect = nil end
    -- GF-UI-T: the words on screen at once (the 「號碼對照」 panel).
    if R and #placed > 0 then
        local lg = legendFor(ov)
        local shownBoxes = {}
        for i = 1, #placed do shownBoxes[i] = ov.boxes[i] end
        local S = H.rectOf(UIParent)
        local lr, where, host = H.placeLegend(R, S, placed, tags, {
            w = H.LEGEND_W * s, maxW = H.LEGEND_MAX_W * s, share = H.LEGEND_SHARE, minW = H.LEGEND_MIN_W * s,
            minH = H.LEGEND_MIN_H * s, gap = H.LEGEND_GAP * s, skip = (H.TAG_H + H.TAG_GAP) * s,
            heightAt = function(w) return legendHeight(lg, shownBoxes, textWidthFor(w / s)) * s end,
            obstacles = (root.gfHelpButton and H.rectOf(root.gfHelpButton)) and { H.rectOf(root.gfHelpButton) } or nil,
        })
        local lw, lh = (lr.r - lr.l) / s, (lr.t - lr.b) / s
        fillLegend(lg, shownBoxes, textWidthFor(lw))
        lg:ClearAllPoints()
        lg:SetPoint("TOPLEFT", ov, "TOPLEFT", (lr.l - R.l) / s, (lr.t - R.t) / s)
        lg:SetSize(lw, lh)
        lg.gfH, lg.gfRect, lg.gfWhere, lg.gfHost, lg.offset = lh, lr, where, host, 0
        lg:Show()
        H.layoutLegend(lg)
    elseif ov.legend then
        ov.legend:Hide()
    end
    H.active = { root = root, key = key, overlay = ov, count = #placed, window = R }
    if root.gfHelpButton then paintButton(root.gfHelpButton, true) end
    return true
end

function H.stop()
    local a = H.active
    if not a then return false end
    H.active = nil
    local ov = a.overlay
    for _, b in ipairs(ov.boxes) do b:Hide() end
    for _, t in ipairs(ov.tags) do t:Hide() end
    if ov.legend then ov.legend:Hide() end
    if ov:IsShown() then ov:Hide() end
    if a.root.gfHelpButton then paintButton(a.root.gfHelpButton, false) end
    if GameTooltip then GameTooltip:Hide() end
    return true
end

function H.toggle(root)
    if H.active and H.active.root == root then H.stop(); return false end
    return H.start(root)
end

-- Frames in use / in the pools (tests).
function H.inUse()
    local n = 0
    local a = H.active
    if a then
        for _, b in ipairs(a.overlay.boxes) do if b:IsShown() then n = n + 1 end end
        for _, t in ipairs(a.overlay.tags) do if t:IsShown() then n = n + 1 end end
        if a.overlay.legend and a.overlay.legend:IsShown() then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Hooks (nothing in the other files changes): the main window's button when
-- it first opens (after 業務通知's bell, so it sits left of it); another page,
-- combat end help; the pop-ups named in H.POPUP get their button when made.
---------------------------------------------------------------------------

local F = ns.Framework
local function mainWindow() return F and _G[F.WINDOW_NAME] end
function H.mainButton()
    local w = mainWindow()
    return w and w.gfHelpButton or nil
end

local openWindow = F.open
F.open = function(...)
    local res = openWindow(...)
    local w = mainWindow()
    if w and not w.gfHelpButton then
        H.attach(w, nil, function(b)
            local bell = ns.NotifyUI and ns.NotifyUI.button and ns.NotifyUI.button()
            if bell then b:SetPoint("RIGHT", bell, "LEFT", -8, 0)
            else b:SetPoint("TOPRIGHT", w, "TOPRIGHT", -(ns.Theme.CLOSE_SIZE + 8), -3) end
        end)
    end
    return res
end

local selectPage = F.select
F.select = function(...)
    H.stop()
    return selectPage(...)
end

local combatStart = ns.onCombatStart
ns.onCombatStart = function(...)
    H.stop()
    return combatStart(...)
end

local makePopup = ns.popupWindow
ns.popupWindow = function(name, ...)
    local f = makePopup(name, ...)
    local key = name and H.POPUP[name]
    if f and key then H.attach(f, key) end
    return f
end

-- The 業務通知 list (a menu-level frame, not a pop-up): left of its 設定.
if ns.NotifyUI and type(ns.NotifyUI.open) == "function" then
    local openList = ns.NotifyUI.open
    ns.NotifyUI.open = function(...)
        local res = openList(...)
        local l = ns.NotifyUI.list and ns.NotifyUI.list()
        if l and not l.gfHelpButton then
            H.attach(l, "notify", function(b)
                if l.setup then b:SetPoint("RIGHT", l.setup, "LEFT", -8, 0)
                else b:SetPoint("TOPRIGHT", l, "TOPRIGHT", -(ns.Theme.CLOSE_SIZE + 8), -4) end
            end)
        end
        return res
    end
end
