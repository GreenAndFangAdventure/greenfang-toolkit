-- GF-UI-R: the 「說明」 button (owner 2026-11-28: 「我希望整個介面都盡量單純，
-- 且有一個說明按鈕，按下後會標示介面功能說明」). Every page and the pop-ups
-- with help get numbered frames; frames and numbers never overlap and stay in
-- the window; they go back to the pool; nothing is made before the first
-- press; ESC, another page, closing the window, a second press and combat end
-- it. Offline only; made-up data.
--
-- The mock has no layout, so this file works out every position from the
-- SetPoint / SetSize calls (Help.rectOf is replaced; the game reads its own).

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
    local function inside(a, R) return a.l >= R.l and a.r <= R.r and a.b >= R.b and a.t <= R.t end

    -- Help on root: frames and numbers placed, none overlapping, all inside.
    local function check(ns, root, min, what)
        local H = ns.Help
        ok(H.start(root), what .. ": help starts")
        local a = H.active
        ok(a and a.root == root, what .. ": active on that window")
        local R = rect(root)
        local boxes, tags = {}, {}
        for _, b in ipairs(a.overlay.boxes) do if b:IsShown() then boxes[#boxes + 1] = b end end
        for _, t in ipairs(a.overlay.tags) do if t:IsShown() then tags[#tags + 1] = t end end
        ok(#boxes >= min, what .. ": at least " .. min .. " parts framed, got " .. #boxes)
        eq(#boxes, a.count, what .. ": count")
        for i, b in ipairs(boxes) do
            ok(H.TEXT[b.gfKey] and H.TEXT[b.gfKey][2] ~= "", what .. ": words for " .. tostring(b.gfKey))
            ok(inside(b.gfRect, R), what .. ": frame " .. b.gfKey .. " inside the window")
            for j = i + 1, #boxes do
                ok(not overlaps(b.gfRect, boxes[j].gfRect), what .. ": " .. b.gfKey .. " / " .. boxes[j].gfKey .. " overlap")
            end
        end
        for i, t in ipairs(tags) do
            ok(inside(t.gfRect, R), what .. ": number " .. t.text._text .. " inside the window")
            for j = i + 1, #tags do ok(not overlaps(t.gfRect, tags[j].gfRect), what .. ": numbers overlap") end
            for _, b in ipairs(boxes) do
                if b ~= t.gfBox then ok(not overlaps(t.gfRect, b.gfRect), what .. ": number " .. t.text._text .. " on frame " .. b.gfKey) end
            end
        end
        ok(#tags >= math.floor(#boxes * 0.8), what .. ": most frames have their number (" .. #tags .. "/" .. #boxes .. ")")
        local hb = root.gfHelpButton
        ok(hb and hb:IsVisible(), what .. ": its 說明 button shows")
        eq(hb.label._text, H.STOP_TEXT, what .. ": the button says 結束說明")
        -- The mouse on a frame: its name and line.
        local b1 = boxes[1]
        b1._scripts.OnEnter(b1)
        local l = GameTooltip._lines
        ok(l[1] and tostring(l[1].text):find(H.TEXT[b1.gfKey][1], 1, true), what .. ": tooltip has the name")
        eq(l[2] and l[2].text, H.TEXT[b1.gfKey][2], what .. ": tooltip has the line")
        b1._scripts.OnLeave(b1)
        H.stop()
        eq(H.inUse(), 0, what .. ": back in the pool")
        ok(not a.overlay:IsShown(), what .. ": the layer is gone")
        eq(hb.label._text, H.BUTTON_TEXT, what .. ": the button says 說明 again")
        return #boxes
    end

    ---------------------------------------------------------------------------
    -- Tests
    ---------------------------------------------------------------------------

    test("GF-UI-R nothing is made before the first press; no OnUpdate, timer or event", function()
        local ns = login()
        local H = ns.Help
        for _, id in ipairs({ "character", "roster", "orders", "recipes", "supply", "bank", "adventure", "sleepingbag" }) do
            ns.Framework.open(id)
        end
        ns.OrdersUI.openPicker()
        ns.AdventureUI.openCalendar()
        ns.Diag.open()
        eq(H.made.overlays, 0, "no layer"); eq(H.made.boxes, 0, "no frame"); eq(H.made.tags, 0, "no number")
        ok(H.made.buttons >= 4, "the buttons: main window, 選配方, 業務排程, 同步與診斷 (" .. H.made.buttons .. ")")
        ok(H.mainButton(), "main window button")
        local src = readAll(ADDON_DIR .. "/Help.lua") .. readAll(ADDON_DIR .. "/HelpText.lua")
        ok(not src:find("OnUpdate\"", 1, true) and not src:find("RegisterEvent", 1, true), "no OnUpdate, no event")
        ok(not src:find("C_Timer", 1, true) and not src:find("ns.after", 1, true), "no timer")
        -- Using it adds no OnUpdate either.
        H.start(main(ns))
        for _, b in ipairs(H.active.overlay.boxes) do ok(not b._scripts.OnUpdate, "no OnUpdate on a frame") end
        ok(not H.active.overlay._scripts.OnUpdate, "no OnUpdate on the layer")
        H.stop()
    end)

    test("GF-UI-R the button: title line of the main window, left of 業務通知, on every page the same", function()
        local ns = login()
        ns.Framework.open("roster")
        local b = ns.Help.mainButton()
        local bell = ns.NotifyUI.button()
        local rb, rl = rect(b), rect(bell)
        ok(rb.r <= rl.l - 6, "left of the bell")
        ok(not overlaps(rb, rl), "not on the bell")
        local w = main(ns)
        local rw = rect(w)
        ok(rb.t <= rw.t and rb.b >= rw.t - ns.Theme.TITLE_H, "in the title line")
        ok(b.icon.gfPath ~= nil, "a game icon")
        local before = rb
        ns.Framework.select("adventure")
        local after = rect(ns.Help.mainButton())
        eq(after.l, before.l, "same place on another page"); eq(after.t, before.t, "same height")
        b._scripts.OnEnter(b)
        ok(GameTooltip._lines[2] and GameTooltip._lines[2].text == ns.Help.BUTTON_TIP, "says what it does")
    end)

    test("GF-UI-R every page of the main window: numbered frames, no overlap, inside the window, back to the pool", function()
        local ns = login()
        ns.Framework.open("character")
        local w = main(ns)
        local mins = { character = 8, roster = 14, orders = 5, recipes = 7, supply = 12, adventure = 12, sleepingbag = 7 }
        for _, id in ipairs({ "character", "roster", "orders", "recipes", "supply", "adventure", "sleepingbag" }) do
            ns.Framework.open(id)
            eq(ns.Framework.current(), id, id .. " open")
            check(ns, w, mins[id], id)
        end
    end)

    test("GF-UI-R 物資調度: 我的刊登, the four 臨時黑箱 pages (庫存, 申領, 保管人, 公會銀行)", function()
        local ns = login()
        ns.Framework.open("supply")
        local w = main(ns)
        ns.SupplyUI.showTab("mine")
        check(ns, w, 10, "supply mine")
        ns.Framework.open("bank")
        local B = ns.BankUI
        for _, v in ipairs({ "stock", "requests", "setup", "guildbank" }) do
            ok(B.setView(v), "view " .. v)
            check(ns, w, 3, "bank " .. v)
        end
        -- Each view frames its own parts (the hidden views' parts are skipped).
        ns.Help.start(w)
        local keys = {}
        for _, b in ipairs(w.gfHelpOverlay.boxes) do if b:IsShown() then keys[b.gfKey] = true end end
        ok(keys.gb_list and keys.gb_money, "公會銀行 parts on its view")
        ok(not keys.bank_stock and not keys.bank_keepers, "no 庫存 / 保管人 parts on 公會銀行")
        ns.Help.stop()
        B.setView("setup")
        ns.Help.start(w)
        keys = {}
        for _, b in ipairs(w.gfHelpOverlay.boxes) do if b:IsShown() then keys[b.gfKey] = true end end
        ok(keys.bank_keepers and keys.bank_scope, "保管人與分享設定 parts")
        ok(not keys.gb_list, "no 公會銀行 parts there")
        ns.Help.stop()
    end)

    test("GF-UI-R pop-ups: 下單, 選配方, 開單, 業務排程, 同步與診斷, 業務通知 have their own button and help", function()
        local ns = login()
        ns.Framework.open("orders")
        local U = ns.OrdersUI
        local picker = U.openPicker()
        ok(picker.gfHelpButton, "選配方 button")
        check(ns, picker, 4, "picker")
        picker:Hide()
        ns.Prices.storeReagents(2738, { output = 2851, yield = 1, list = { { id = 2840, n = 3 } } })
        U.openOrder({ recipe = 2738, skill = 164, crafters = {} })
        local form = _G[U.POPUP_NAME]
        ok(form and form:IsShown() and form.gfHelpButton, "下單 button")
        check(ns, form, 6, "order form")
        form:Hide()
        ns.Framework.open("adventure")
        ns.AdventureUI.openTicket()
        local ticket = _G[ns.AdventureUI.TICKET_NAME]
        ok(ticket.gfHelpButton, "開單 button")
        check(ns, ticket, 5, "ticket")
        ticket:Hide()
        local cal = ns.AdventureUI.openCalendar()
        ok(cal.gfHelpButton, "業務排程 button")
        check(ns, cal, 4, "calendar")
        cal:Hide()
        ns.Diag.open()
        local d = _G[ns.Diag.WINDOW_NAME]
        ok(d.gfHelpButton, "同步與診斷 button")
        check(ns, d, 6, "settings")
        d:Hide()
        local list = ns.NotifyUI.open()
        ok(list and list.gfHelpButton, "業務通知 button")
        local rl, rs, rh = rect(list), rect(list.setup), rect(list.gfHelpButton)
        ok(rh.r <= rs.l and not overlaps(rh, rs) and inside(rh, rl), "left of 設定, inside the list")
        check(ns, list, 2, "notify")
        -- One look on every window: the same button size.
        eq(picker.gfHelpButton._w, ns.Help.mainButton()._w, "same width"); eq(d.gfHelpButton._h, ns.Help.mainButton()._h, "same height")
    end)

    test("GF-UI-R ESC, another page, closing the window, a second press end it; the window stays for ESC", function()
        local ns = login()
        local H = ns.Help
        ns.Framework.open("roster")
        local w = main(ns)
        ok(H.start(w), "on")
        local top = ns.escTop()
        eq(top, w.gfHelpOverlay, "ESC closes the help layer first")
        ns.escape()
        ok(not H.isActive(), "ESC ends it")
        ok(w:IsShown(), "the window stays")
        H.start(w)
        ns.Framework.select("orders")
        ok(not H.isActive(), "another page ends it")
        H.start(w)
        H.toggle(w)
        ok(not H.isActive(), "a second press ends it")
        H.start(w)
        local hb = w.gfHelpButton
        hb._scripts.OnClick(hb)

        ok(not H.isActive(), "the button's click ends it")
        H.start(w)
        w:Hide()
        ok(not H.isActive(), "closing the window ends it")
        eq(H.inUse(), 0, "all back in the pool")
    end)

    test("GF-UI-R combat: does not open, a line in chat; combat ends an open one", function()
        local ns = login()
        local H = ns.Help
        ns.Framework.open("adventure")
        local w = main(ns)
        H.start(w)
        wow.enterCombat()
        ok(not H.isActive(), "combat ends it")
        local n = #wow.state.printed
        ok(not H.start(w), "not in combat")
        local said = false
        for i = n + 1, #wow.state.printed do if tostring(wow.state.printed[i]):find("戰鬥中不能開說明", 1, true) then said = true end end
        ok(said or tostring(wow.state.printed[#wow.state.printed] or ""):find("戰鬥", 1, true), "says why")
        eq(H.made.boxes > 0 and H.inUse() or 0, 0, "nothing shown")
        wow.leaveCombat()
        ok(H.start(w), "after combat it opens")
        H.stop()
    end)

    test("GF-UI-R the layer takes the clicks and the wheel; menus close first; frames reused", function()
        local ns = login()
        local H = ns.Help
        ns.Framework.open("roster")
        local w = main(ns)
        ns.UI.skillChoice._scripts.OnClick(ns.UI.skillChoice) -- a drop-down open
        H.start(w)
        ok(not ns.menusOpen(), "the open list closed")
        local ov = w.gfHelpOverlay
        eq(ov._kind, "Button", "a button over the window")
        ok(ov._scripts.OnClick and ov._scripts.OnMouseWheel, "click and wheel stop on it")
        ok(ov.gfEscLevel > w.gfEscLevel, "above its window for ESC")
        local made = H.made.boxes
        H.stop()
        H.start(w)
        eq(H.made.boxes, made, "the same frames again")
        H.stop()
        ns.Framework.open("character")
        H.start(w)
        ok(H.made.boxes <= math.max(made, H.active.count), "a page with fewer parts reuses them")
        H.stop()
        eq(H.made.overlays, 1, "one layer for the main window")
    end)

    test("GF-UI-R the words: every part has one or two plain sentences, in one table, game-font glyphs", function()
        local ns = login()
        local H = ns.Help
        local n = 0
        for page, list in pairs(H.pages) do
            for _, e in ipairs(list) do
                local t = H.TEXT[e.key]
                ok(t and t[1] ~= "" and t[2] ~= "", page .. ": words for " .. tostring(e.key))
                local _, stops = tostring(t and t[2] or ""):gsub("。", "")
                ok(stops >= 1 and stops <= 2, e.key .. ": one or two sentences")
                n = n + 1
            end
        end
        ok(n >= 100, "parts registered: " .. n)
        for _, k in ipairs({ "frame", "character", "roster", "orders", "recipes", "orderform", "picker", "supply", "bank",
            "adventure", "ticket", "calendar", "sleepingbag", "notify", "settings" }) do
            ok(H.pages[k] and #H.pages[k] > 0, "page " .. k .. " registered")
        end
        -- No arrows or ellipsis (the run.lua glyph test checks every TOC file too).
        for k, t in pairs(H.TEXT) do
            for _, s in ipairs(t) do
                ok(not s:find("\226\134", 1, true), k .. ": no arrows")
                ok(not s:find("\226\128\166", 1, true), k .. ": no ellipsis")
            end
        end
    end)

    test("GF-UI-R placing: a frame never covers an earlier one; numbers move out of the way", function()
        local ns = login()
        local H = ns.Help
        local R = { l = 0, r = 400, b = 0, t = 300 }
        local a = { l = 10, r = 110, b = 200, t = 230 }
        local b = { l = 100, r = 200, b = 200, t = 230 } -- covers a
        local c = { l = 220, r = 320, b = 200, t = 230 }
        local entries = {
            { key = "a", get = function() return "A" end }, { key = "b", get = function() return "B" end },
            { key = "c", get = function() return "C" end },
        }
        local rects = { A = a, B = b, C = c }
        local old = H.rectOfEntry
        H.rectOfEntry = function(e) return rects[e.get()] end
        local boxes = H.placeBoxes(R, entries, 3, {})
        H.rectOfEntry = old
        eq(#boxes, 2, "b left out")
        eq(boxes[1].entry.key, "a"); eq(boxes[2].entry.key, "c")
        local tags = H.placeTags(R, boxes, { { 20, 20 }, { 20, 20 } }, 2, {})
        for i, t in pairs(tags) do
            ok(inside(t, R), "number inside")
            for j, bx in ipairs(boxes) do if j ~= i then ok(not overlaps(t, bx.rect), "number off the other frame") end end
        end
        ok(tags[1] and tags[2] and not overlaps(tags[1], tags[2]), "two numbers apart")
    end)
end
