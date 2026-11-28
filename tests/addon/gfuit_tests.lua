-- GF-UI-T: the owner's four points on 0.16.22 (2026-11-28): the 說明 mode shows
-- the words at once (a 「號碼對照」 panel, no mouse needed); the order form's
-- 指定工匠 has no mark on its icon (「接單中」 after the name instead); 行情 says
-- how to get prices (the auction house's 「掃描行情」 button, its name on it);
-- no price at all reads 「無法估價（沒有行情）」, never 「＞0 銅」. Offline only;
-- made-up data. Positions come from the mock's anchors, as in gfuir_tests.lua.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local SW, SH = 1920, 1080
    local function readAll(path) local h = io.open(path, "rb"); if not h then return "" end local s = h:read("*a"); h:close(); return s end

    ---------------------------------------------------------------------------
    -- Positions from the mock's anchors (screen pixels, y up)
    ---------------------------------------------------------------------------

    local resolve
    local function sizeOf(o)
        local w, h = o._w or o._fixedWidth, o._h
        if o._kind == "FontString" then
            w = (type(o._fixedWidth) == "number" and o._fixedWidth > 0) and o._fixedWidth or wow.textWidth(o._text, o._font)
            h = h or 16
        end
        return w, h
    end
    local function px(R, point)
        point = point or "CENTER"
        local x = point:find("LEFT") and R.l or point:find("RIGHT") and R.r or (R.l + R.r) / 2
        local y = point:find("TOP") and R.t or point:find("BOTTOM") and R.b or (R.t + R.b) / 2
        return x, y
    end
    resolve = function(o, depth)
        depth = depth or 0
        if o == nil or o == UIParent or depth > 40 then return { l = 0, b = 0, r = SW, t = SH } end
        local parent = o._parent or UIParent
        local pts = o._points or {}
        if #pts == 0 then return resolve(parent, depth + 1) end
        local e = {}
        for _, p in ipairs(pts) do
            local point, rel, relPoint, x, y = p[1], nil, nil, 0, 0
            if type(p[2]) == "number" then rel, relPoint, x, y = parent, point, p[2], p[3] or 0
            elseif p[2] == nil then rel, relPoint = parent, point
            else
                rel = type(p[2]) == "string" and _G[p[2]] or p[2]
                if type(p[3]) == "number" then relPoint, x, y = point, p[3], p[4] or 0
                else relPoint, x, y = p[3] or point, p[4] or 0, p[5] or 0 end
            end
            local R = resolve(rel, depth + 1)
            local ax, ay = px(R, relPoint)
            ax, ay = ax + x, ay + y
            if point:find("LEFT") then e.l = ax elseif point:find("RIGHT") then e.r = ax else e.cx = ax end
            if point:find("TOP") then e.t = ay elseif point:find("BOTTOM") then e.b = ay else e.cy = ay end
        end
        local w, h = sizeOf(o)
        w, h = w or 0, h or 0
        local l, r, t, b = e.l, e.r, e.t, e.b
        if l and not r then r = l + w elseif r and not l then l = r - w elseif not l then l = (e.cx or 0) - w / 2; r = l + w end
        if t and not b then b = t - h elseif b and not t then t = b + h elseif not t then t = (e.cy or 0) + h / 2; b = t - h end
        return { l = l, r = r, t = t, b = b }
    end
    local function rect(o)
        local r = resolve(o)
        if not r or r.r <= r.l or r.t <= r.b then return nil end
        return r
    end

    local function login()
        wow.reset()
        for _, n in ipairs({ "GreenFangToolkit_MainWindow" }) do _G[n] = nil end
        local ns = wow.login(ADDON_DIR)
        ns.Help.rectOf = rect
        wow.advance(25)
        return ns
    end
    local function main(ns) return _G[ns.Framework.WINDOW_NAME] end
    local function overlaps(a, b) return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t end
    local function inside(a, R) return a.l >= R.l - 0.01 and a.r <= R.r + 0.01 and a.b >= R.b - 0.01 and a.t <= R.t + 0.01 end
    local function has(s, sub) return tostring(s):find(sub, 1, true) ~= nil end
    local function lines()
        local out = {}
        for _, l in ipairs(GameTooltip._lines or {}) do out[#out + 1] = tostring(l.text) end
        return table.concat(out, "\n")
    end

    -- Help on root: the panel lists every number with its name and line, on
    -- screen, covering no other frame and no number.
    local function checkLegend(ns, root, what)
        local H = ns.Help
        ok(H.start(root), what .. ": help starts")
        local ov = H.active.overlay
        local lg = ov.legend
        ok(lg and lg:IsShown(), what .. ": the 號碼對照 panel shows at once")
        eq(lg.title._text, H.LEGEND_TITLE, what .. ": its title")
        local boxes, tags = {}, {}
        for _, b in ipairs(ov.boxes) do if b:IsShown() then boxes[#boxes + 1] = b end end
        for _, t in ipairs(ov.tags) do if t:IsShown() then tags[#tags + 1] = t end end
        eq(lg.count, #boxes, what .. ": one line per frame")
        for i, b in ipairs(boxes) do
            local r = lg.rows[i]
            local t = H.TEXT[b.gfKey]
            local s = r.text._text
            ok(s:find("^|cff%x%x%x%x%x%x" .. i .. " ") ~= nil, what .. ": line " .. i .. " starts with its number")
            ok(has(s, t[1]) and has(s, t[2]), what .. ": line " .. i .. " has the name and the words of " .. b.gfKey)
            eq(r.gfBox, b, what .. ": line " .. i .. " belongs to frame " .. i)
        end
        ok(lg.shown >= 1, what .. ": lines shown")
        local L = lg.gfRect
        local S = rect(UIParent)
        ok(inside(L, S), what .. ": the panel is on the screen")
        local R = rect(root)
        if lg.gfWhere == "side" then
            ok(not overlaps(L, R), what .. ": beside the window, covers nothing of it")
        elseif lg.gfWhere == "free" then
            ok(inside(L, R), what .. ": in an empty part of the window")
            local hb = root.gfHelpButton and rect(root.gfHelpButton)
            ok(not (hb and overlaps(L, hb)), what .. ": off the 說明 button")
        else
            eq(lg.gfWhere, "frame", what .. ": inside a frame (no room beside the window)")
            ok(inside(L, boxes[lg.gfHost].gfRect), what .. ": inside its host frame")
        end
        for i, b in ipairs(boxes) do
            if i ~= lg.gfHost then ok(not overlaps(L, b.gfRect), what .. ": panel off frame " .. b.gfKey) end
        end
        for _, t in ipairs(tags) do ok(not overlaps(L, t.gfRect), what .. ": panel off number " .. t.text._text) end
        -- Every line shown fits in the panel; the hidden ones scroll in.
        local y = 0
        for i = 1, lg.count do
            if lg.rows[i]:IsShown() then y = y + lg.heights[i] + H.LEGEND_ROW_GAP end
        end
        ok(y - H.LEGEND_ROW_GAP <= lg.gfH - 2 * H.LEGEND_PAD - H.LEGEND_TITLE_H + 0.5, what .. ": the lines fit")
        if lg.shown < lg.count then ok(lg.bar:IsShown(), what .. ": a long list has its scroll bar") end
        return lg
    end

    test("GF-UI-T 說明: every page and pop-up lists the words at once, nothing covered, on screen", function()
        local ns = login()
        local w = main(ns)
        ns.Framework.open("character")
        w = main(ns)
        for _, id in ipairs({ "character", "roster", "orders", "recipes", "supply", "adventure", "sleepingbag" }) do
            ns.Framework.open(id)
            checkLegend(ns, w, id)
            ns.Help.stop()
            ok(not w.gfHelpOverlay.legend:IsShown(), id .. ": the panel goes with help")
            eq(ns.Help.inUse(), 0, id .. ": all back in the pool")
        end
        ns.Framework.open("bank")
        for _, v in ipairs({ "stock", "requests", "setup", "guildbank" }) do
            ns.BankUI.setView(v)
            checkLegend(ns, w, "bank " .. v)
            ns.Help.stop()
        end
        ns.Framework.open("orders")
        ns.Prices.storeReagents(2738, { output = 2851, yield = 1, list = { { id = 2840, n = 3 } } })
        ns.OrdersUI.openOrder({ recipe = 2738, skill = 164, crafters = {} })
        local form = _G[ns.OrdersUI.POPUP_NAME]
        local lg = checkLegend(ns, form, "order form")
        eq(lg.gfWhere, "side", "order form: the panel beside the form (the screen has room)")
        ns.Help.stop(); form:Hide()
        ns.Diag.open()
        checkLegend(ns, _G[ns.Diag.WINDOW_NAME], "settings")
        ns.Help.stop()
        ns.Framework.open("adventure")
        ns.AdventureUI.openTicket()
        checkLegend(ns, _G[ns.AdventureUI.TICKET_NAME], "ticket")
        ns.Help.stop()
        local list = ns.NotifyUI.open()
        checkLegend(ns, list, "notify")
        ns.Help.stop()
    end)

    test("GF-UI-T 說明: the line under the mouse lights its frame; the wheel scrolls a long list; ESC ends only help", function()
        local ns = login()
        local H = ns.Help
        ns.Framework.open("roster")
        local w = main(ns)
        local lg = checkLegend(ns, w, "roster")
        local r1 = lg.rows[1]
        ok(r1._scripts.OnEnter and r1._scripts.OnLeave, "a line reacts to the mouse")
        r1._scripts.OnEnter(r1)
        r1._scripts.OnLeave(r1)
        -- Make the panel short: the list scrolls.
        lg.gfH = H.LEGEND_TITLE_H + 2 * H.LEGEND_PAD + lg.heights[1] + 2
        lg.offset = 0
        H.layoutLegend(lg)
        eq(lg.shown, 1, "one line fits")
        ok(lg.bar:IsShown(), "the bar shows")
        lg._scripts.OnMouseWheel(lg, -1)
        eq(lg.offset, 1, "the wheel moves one line")
        ok(not lg.rows[1]:IsShown() and lg.rows[2]:IsShown(), "the next line shows")
        for _ = 1, 60 do lg._scripts.OnMouseWheel(lg, -1) end
        ok(lg.rows[lg.count]:IsShown(), "the last line can be reached")
        eq(ns.escTop(), w.gfHelpOverlay, "ESC ends help first")
        ns.escape()
        ok(not H.isActive() and w:IsShown(), "ESC ended help, the window stays")
        ok(not lg:IsShown(), "the panel is gone")
        -- A screen no wider than the window (the owner's main window nearly fills
        -- it): the panel goes inside the largest frame, off every other frame and number.
        local rw = rect(w)
        H.rectOf = function(o) if o == UIParent then return { l = rw.l, r = rw.r, b = rw.b, t = rw.t } end return rect(o) end
        for _, id in ipairs({ "roster", "recipes", "orders", "adventure", "supply", "character" }) do
            ns.Framework.open(id)
            local p = checkLegend(ns, w, id .. " (narrow screen)")
            ok(p.gfWhere ~= "corner", id .. ": a frame holds it")
            H.stop()
        end
        H.rectOf = rect
        -- Nothing made before the first press (also the panel).
        local ns2 = login()
        eq(ns2.Help.made.legends, 0, "no panel before the first press")
    end)

    test("GF-UI-T 說明: placing the panel (pure): beside, else empty space, else the largest frame, else a corner", function()
        local ns = login()
        local H = ns.Help
        local R = { l = 100, r = 900, b = 100, t = 700 }
        local o = { w = 300, maxW = 460, share = 0.5, minW = 240, minH = 150, gap = 6, skip = 22,
            heightAt = function() return 400 end }
        local boxes = { { rect = { l = 110, r = 300, b = 650, t = 690 } }, { rect = { l = 110, r = 890, b = 110, t = 600 } } }
        local r, where = H.placeLegend(R, { l = 0, r = 1300, b = 0, t = 800 }, boxes, {}, o)
        eq(where, "side"); ok(r.l >= 906 and not overlaps(r, R), "right of the window")
        r, where = H.placeLegend(R, { l = 0, r = 950, b = 0, t = 800 }, boxes, {}, o)
        eq(where, "frame", "no room beside, below or above: the big frame")
        ok(inside(r, boxes[2].rect) and not overlaps(r, boxes[1].rect), "inside the list frame only")
        ok(r.r - r.l <= 460 and r.r - r.l >= 240, "half the frame, at most 460")
        ok(r.t <= boxes[2].rect.t - 22, "below the frame's number")
        r, where = H.placeLegend(R, { l = 0, r = 950, b = 0, t = 800 }, { boxes[1] }, { { l = 300, r = 320, b = 600, t = 620 } }, o)
        eq(where, "free", "an empty part of the window")
        ok(inside(r, R) and not overlaps(r, boxes[1].rect), "in the window, off the frame")
        ok(not overlaps(r, { l = 300, r = 320, b = 600, t = 620 }), "off the number")
        -- Small frames everywhere: no empty part, none big enough: the corner.
        local many = {}
        for x = 0, 7 do for y = 0, 5 do
            many[#many + 1] = { rect = { l = 102 + x * 100, r = 198 + x * 100, b = 102 + y * 100, t = 198 + y * 100 } }
        end end
        r, where = H.placeLegend(R, { l = 0, r = 950, b = 0, t = 800 }, many, {}, o)
        eq(where, "corner", "nothing big enough: the corner")
        ok(inside(r, R), "still in the window")
    end)

    test("GF-UI-T 說明: words; set_clear is 清除已結束委託; no arrows", function()
        local ns = login()
        local H = ns.Help
        eq(H.TEXT.set_clear[1], "清除已結束委託", "the new button name")
        ok(has(H.TEXT.form_market[2], "掃描行情"), "行情 names the button")
        ok(not has(H.LEGEND_TITLE, "\226\134"), "no arrows in the title")
        ok(has(H.legendLine(3, "recipes_search"), "3  搜尋"), "number and name")
    end)

    ---------------------------------------------------------------------------
    -- The order form
    ---------------------------------------------------------------------------

    local RECIPE, ITEM, SKILL = 2660, 2862, 164
    local ORE, STONE = 2770, 2835
    local NAMES = { [ITEM] = "測試銅錘", [ORE] = "測試銅錠", [STONE] = "測試石頭" }
    local function formLogin(prices)
        local ns = login()
        C_Item = { GetItemCount = function() return 0 end, GetItemNameByID = function(id) return NAMES[id] end }
        ns.Prices.storeReagents(RECIPE, { output = ITEM, yield = 1, list = { { id = ORE, n = 1 }, { id = STONE, n = 1 } } })
        for id, c in pairs(prices or {}) do ns.Prices.db().vendor[id] = ns.Share.b36(c) .. ".1" end
        ns.Framework.open("orders")
        local d = ns.OrdersUI.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        return ns, d, _G[ns.OrdersUI.POPUP_NAME]
    end

    test("GF-UI-T 下單: 指定工匠 has no mark on its icon; 接單中 is explained in words", function()
        local ns, _, f = formLogin()
        eq(f.namedActive, nil, "no small mark over the icon")
        ok(not f.named.badge:IsShown(), "指定工匠's corner mark hidden")
        ok(not f.guild.badge:IsShown(), "公會單 has no mark either")
        eq(ns.OrdersUI.TEXT.namedActive, "（接單中）", "the words after the name")
        f.named._scripts.OnEnter(f.named)
        ok(has(lines(), "接單中"), "the hint explains 接單中")
        ok(not has(lines(), "小錘子"), "no hammer in the words")
        local src = io.open(ADDON_DIR .. "/OrdersUI.lua", "rb"):read("*a")
        ok(not src:find("namedActive = f:CreateTexture", 1, true), "the overlay texture is gone")
        C_Item = nil
    end)

    test("GF-UI-T 下單: no price at all reads 無法估價, never 「＞0」; some prices keep the lower bound", function()
        local ns, d, f = formLogin()
        local U = ns.OrdersUI
        ok(has(f.matsCost._text, U.TEXT.noEstimate), "材料費: " .. f.matsCost._text)
        ok(has(f.matsCost._text, "測試銅錠") and has(f.matsCost._text, "測試石頭"), "names both materials")
        ok(not has(f.matsCost._text, "＞"), "no 「＞」 in 材料費")
        eq(f.total._text, U.TEXT.noEstimate, "合計 says it cannot be estimated")
        d.fee = 500
        U.drawPopup()
        eq(f.total._text, U.money(500) .. "  " .. U.TEXT.noEstimateFee, "with a fee: the fee, then the words")
        ok(not has(f.total._text, "＞"), "no 「＞」 in 合計")
        C_Item = nil
        -- One price known: the lower bound stays.
        ns, d, f = formLogin({ [STONE] = 40 })
        U = ns.OrdersUI
        ok(has(f.matsCost._text, "＞") and not has(f.matsCost._text, U.TEXT.noEstimate), "lower bound: " .. f.matsCost._text)
        ok(has(f.total._text, "＞"), "合計 lower bound")
        -- Bring the unpriced one: exact.
        U.setBring(d, ORE, 1, 1); U.drawPopup()
        eq(f.matsCost._text, U.money(40), "exact")
        -- Bring all: nothing to buy, 0 and exact (not 無法估價).
        U.setBring(d, STONE, 1, 1); U.drawPopup()
        eq(f.total._text, U.money(0), "all brought: 0")
        ok(not U.noEstimate({ noList = true, unknown = false, total = 0 }), "no list is its own text")
        C_Item = nil
    end)

    test("GF-UI-T 行情: says where the button is; the auction house button is named 掃描行情 with a plain hint", function()
        local ns, _, f = formLogin()
        local U = ns.OrdersUI
        eq(f.market._text, U.TEXT.noMarket, "no market: the words")
        ok(has(U.TEXT.noMarket, "拍賣師") and has(U.TEXT.noMarket, "「掃描行情」"), "who and which button")
        ok(not has(U.TEXT.noMarket, "掃描鈕"), "the old word is gone")
        ok(ns.labelWidth(U.TEXT.noMarket) <= 520, "one line in the form")
        f.marketIcon._scripts.OnEnter(f.marketIcon)
        local l = lines()
        ok(has(l, "拍賣師") and has(l, "掃描行情") and has(l, "自動分享"), "the hint says how, and that the guild shares")
        f.matsIcon._scripts.OnEnter(f.matsIcon)
        ok(has(lines(), "掃描行情"), "材料費 names the same button")
        local ah = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
        _G.AuctionHouseFrame = ah
        ah:SetSize(800, 500); ah:SetPoint("CENTER")
        U.auctionShown()
        local b = U.scanButton()
        ok(b and b:IsShown(), "the button by the auction house")
        eq(b.label and b.label._text, U.TEXT.scanName, "its name on it: 掃描行情")
        b._scripts.OnEnter(b)
        l = lines()
        ok(has(l, "掃描行情") and has(l, "材料費") and has(l, "還沒掃描過"), "what it does, never scanned yet: " .. l)
        U.auctionHidden()
        ok(not b:IsShown(), "goes with the auction house")
        _G.AuctionHouseFrame = nil
        C_Item = nil
    end)
end
