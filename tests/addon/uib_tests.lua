-- GF-UI-B (0.13.1): batch 1 of the UI design review (docs/research GF-UI-A
-- §3 「第一批」 items 1-11) outside the adventure page, the roster click
-- (a profession icon opens that member's recipes), and the order test mode
-- (an order to myself that never reaches guild addon messages or the
-- upload). Made-up names and GUIDs only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B = "0000-0000000A", "0000-0000000B"
    local RECIPE, ITEM, SKILL = 2660, 2862, 164

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession()
        return ns
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function visible(o)
        local f = o
        while f do
            if f._shown == false then return false end
            f = f._parent
        end
        return true
    end
    local function inside(o, root)
        local f = o
        while f do
            if f == root then return true end
            f = f._parent
        end
        return false
    end
    local function fontSize(fs)
        local f = fs._font
        local obj = type(f) == "string" and rawget(_G, f) or f
        if type(obj) == "table" and obj._fontSize then return obj._fontSize end
        if tostring(f):find("Large") then return 18 end
        if tostring(f):find("Small") then return 10 end
        return 13
    end
    -- Shown objects of kind under root.
    local function shownUnder(root, kind)
        local out = {}
        for _, o in ipairs(wow.allObjects()) do
            if (not kind or o._kind == kind) and inside(o, root) and visible(o) then out[#out + 1] = o end
        end
        return out
    end
    local function cjk(text)
        local n = 0
        for ch in plain(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do if #ch > 1 then n = n + 1 end end
        return n
    end
    local function rowOf(ns, name)
        for _, r in ipairs(ns.UI.rows()) do if r:IsShown() and r.memberName == name then return r end end
    end

    -- Rectangles of the parts anchored to win (TOPLEFT / BOTTOMLEFT of win, or
    -- LEFT of another part's RIGHT); y grows downwards.
    local function sizeOf(o)
        if o._kind == "FontString" then return wow.textWidth(o._text, o._font), fontSize(o) end
        return o._w or 0, o._h or 0
    end
    local function rectOf(o, win, depth)
        depth = depth or 0
        if depth > 4 or not o._points or not o._points[1] then return nil end
        local p = o._points[1]
        local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0
        local w, h = sizeOf(o)
        if rel == win and point == "TOPLEFT" and relPoint == "TOPLEFT" then return x, -y, x + w, -y + h end
        if rel == win and point == "BOTTOMLEFT" and relPoint == "BOTTOMLEFT" then
            local bottom = win._h - y
            return x, bottom - h, x + w, bottom
        end
        if rel == win and point == "BOTTOMRIGHT" and relPoint == "BOTTOMRIGHT" then
            local bottom = win._h - y
            return win._w + x - w, bottom - h, win._w + x, bottom
        end
        if rel and rel ~= win and point == "LEFT" and relPoint == "RIGHT" then
            local l, t, r, b = rectOf(rel, win, depth + 1)
            if not l then return nil end
            local cy = (t + b) / 2
            return r + x, cy - h / 2 - y, r + x + w, cy + h / 2 - y
        end
        return nil
    end
    local function overlaps(win, filter)
        local list = {}
        for _, o in ipairs(wow.allObjects()) do
            local direct = o._parent == win
            local k = o._kind
            local wanted = k == "Button" or k == "EditBox" or k == "CheckButton" or (k == "FontString" and plain(o._text) ~= "")
                or (k == "Texture" and o._texture)
            if direct and wanted and visible(o) and (not filter or filter(o)) then
                local l, t, r, b = rectOf(o, win)
                if l then list[#list + 1] = { o = o, l = l, t = t, r = r, b = b } end
            end
        end
        local out = {}
        for i = 1, #list do
            for j = i + 1, #list do
                local a, b = list[i], list[j]
                if a.l < b.r - 1 and b.l < a.r - 1 and a.t < b.b - 1 and b.t < a.b - 1 then
                    out[#out + 1] = plain(a.o._text) .. "(" .. a.o._kind .. ") × " .. plain(b.o._text) .. "(" .. b.o._kind .. ")"
                end
            end
        end
        local outside = {}
        for _, p in ipairs(list) do
            if p.l < 0 or p.t < 0 or p.r > win._w + 1 or p.b > win._h + 1 then outside[#outside + 1] = plain(p.o._text) .. "(" .. p.o._kind .. ")" end
        end
        return table.concat(out, " | "), #list, table.concat(outside, ",")
    end

    ---------------------------------------------------------------------------
    -- ★1 roster: 16 px, 36 px rows, 24 / 28 px icons, reflowed columns, race in the tooltip
    ---------------------------------------------------------------------------

    test("GF-UI-B ★1 roster columns: in order, apart, total ≤ 1040; 種族 gone from the columns", function()
        local ns = login()
        local cols = ns.UI.columns
        for i = 2, #cols do
            local prev, cur = cols[i - 1], cols[i]
            local prevEnd = prev.x + (prev.wSplit or prev.w)
            ok(prevEnd + 2 <= cur.x, prev.name .. " ends before " .. cur.name)
        end
        local last = cols[#cols]
        ok(last.x + last.w <= 1040, "total ≤ 1040")
        eq(cols[ns.UI.CELL.note].x + cols[ns.UI.CELL.note].w, 1040, "公會註記 reaches the end when alone")
        for _, c in ipairs(cols) do ok(c.key ~= "race", "no race column") end
    end)

    test("GF-UI-B ★1 roster rows: 36 px, 16 px text, class icon 24, professions 28, hammer and status 16; no overlap", function()
        local ns = login()
        ns.Orders.setActive(186, true) -- not my profession, harmless
        ns.Framework.open("roster")
        local panel = ns.Framework.panel("roster")
        local row = rowOf(ns, "測試乙-測試伺服器")
        ok(row, "a row")
        eq(row._h, 36, "36 px")
        eq(row.classIcon._w, 24, "class icon 24")
        eq(row.statusIcon._w, 16, "status icon 16")
        ok(row.statusIcon._texture:find("StatusIcon%-Online"), "online icon")
        eq(row.profSlots[1].icon._w, 28, "profession icon 28")
        eq(row.profSlots[1].badge._w, 16, "hammer 16")
        -- Each cell inside its column; columns apart; profession slots inside the profession column.
        local spans = {}
        for _, col in ipairs(ns.UI.columns) do
            local fs = row.cell[col.key]
            if fs:IsShown() and fs:GetText() ~= "" then spans[#spans + 1] = { col.name, fs.colX, fs.colX + fs.colW } end
        end
        spans[#spans + 1] = { "職業圖示", ns.UI.columns[ns.UI.CELL.class].x, ns.UI.columns[ns.UI.CELL.class].x + 24 }
        spans[#spans + 1] = { "狀態圖示", ns.UI.columns[ns.UI.CELL.online].x, ns.UI.columns[ns.UI.CELL.online].x + 16 }
        table.sort(spans, function(x, y) return x[2] < y[2] end)
        for i = 2, #spans do ok(spans[i - 1][3] <= spans[i][2], spans[i - 1][1] .. " / " .. spans[i][1]) end
        for _, s in ipairs(row.profSlots) do
            if s.entry then ok(s.x0 >= row.profX and s.x1 <= row.profX + row.profW, "slot inside the column") end
        end
        -- No small fonts anywhere on the roster page.
        local small = {}
        for _, fs in ipairs(shownUnder(panel, "FontString")) do
            if plain(fs._text) ~= "" and fontSize(fs) < 16 then small[#small + 1] = plain(fs._text) .. "@" .. fontSize(fs) end
        end
        eq(table.concat(small, ","), "", "no text under 16 px on the roster page")
        -- 種族 is in the member tooltip.
        ns.UI.showRowTooltip(row, nil)
        local tip = {}
        for _, l in ipairs(GameTooltip._lines) do tip[#tip + 1] = l.text end
        ok(table.concat(tip, "\n"):find("獸人", 1, true), "race in the tooltip: " .. table.concat(tip, " / "))
        ok(table.concat(tip, "\n"):find("60", 1, true), "level in the tooltip")
    end)

    test("GF-UI-B ★1 roster tool bar, header and bottom row: nothing overlaps, all inside the page", function()
        local ns = login({ guildPerms = { invite = true }, myRankIndex = 0 })
        ns.Framework.open("roster")
        local panel = ns.Framework.panel("roster")
        local text, n, outside = overlaps(panel)
        eq(text, "", "overlaps")
        eq(outside, "", "inside the page")
        ok(n >= 12, "parts measured: " .. n)
        eq(ns.UI.countText:GetText(), "4/4", "the count right on the tool bar")
        ok(ns.UI.countIcon:IsShown(), "with the person icon")
        local _, _, right = rectOf(ns.UI.clearButton, panel)
        ok(right + 8 <= 1060 - wow.textWidth("4/4", ns.LABEL_FONT) - 24, "清除 ends before the count")
        -- Header: 28 px, gold names, one sorted column white with an arrow texture.
        eq(ns.UI.header._h, 28, "header 28 px")
        local arrows = 0
        for _, e in ipairs(ns.UI.sortHeaders()) do
            if e.arrow:IsShown() then
                arrows = arrows + 1
                ok(e.arrow._texture:find("Arrow%-Up%-Up") or e.arrow._texture:find("ScrollUpButton"), "up arrow texture")
                eq(table.concat(e.label._color, ","), "1,1,1", "sorted column white")
            else
                eq(table.concat(e.label._color, ","), "1,0.82,0", "other columns gold")
            end
            ok(not e.label._text:find("▲") and not e.label._text:find("▼"), "no arrow characters")
            eq(fontSize(e.label), 16, "16 px header")
        end
        eq(arrows, 1, "one arrow")
        wow.click(ns.UI.sortHeaders()[1].heading)
        ok(ns.UI.sortHeaders()[1].arrow._texture:find("Down") , "second click: down arrow")
    end)

    ---------------------------------------------------------------------------
    -- ★2 the shared list-row selection
    ---------------------------------------------------------------------------

    test("GF-UI-B ★2 ns.rowSelect: the quest log glow in gold (ADD) and a 3 px gold bar; no flat yellow in the roster", function()
        local ns = login()
        ns.Framework.open("roster")
        local row = rowOf(ns, "測試丙-測試伺服器")
        ns.UI.select(row.member)
        row = rowOf(ns, "測試丙-測試伺服器")
        local sel = row.selected
        ok(sel:IsShown(), "chosen row selected")
        eq(sel.glow._texture, "Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "quest log title glow")
        eq(sel.glow._blend, "ADD", "ADD")
        eq(table.concat(sel.glow._vertex, ","), "1,0.82,0", "gold")
        eq(sel.glow._alpha, 0.55, "0.55")
        eq(sel.bar._fixedWidth, 3, "3 px bar")
        eq(table.concat(sel.bar._color, ","), "1,0.82,0,1", "gold bar")
        for _, r in ipairs(ns.UI.rows()) do
            if r:IsShown() and r ~= row then ok(not r.selected:IsShown(), "others not selected") end
        end
        -- The source has no flat yellow selection any more.
        for _, file in ipairs({ "UI.lua", "Recipes.lua", "OrdersUI.lua", "Framework.lua", "Diag.lua" }) do
            local f = io.open(ADDON_DIR .. "/" .. file, "r")
            local src = f:read("*a"); f:close()
            ok(not src:find("SetColorTexture(1, 0.82", 1, true), file .. ": no flat yellow")
        end
    end)

    ---------------------------------------------------------------------------
    -- ★3 / ★4 no sentences or time stamps; clickable names 2-4 characters
    ---------------------------------------------------------------------------

    test("GF-UI-B ★3 roster states: an icon and 2-4 characters in the middle; no 「。」, no scan time on the pages", function()
        local ns = login()
        ns.Framework.open("roster")
        local panel = ns.Framework.panel("roster")
        local function texts(root)
            local out = {}
            for _, fs in ipairs(shownUnder(root, "FontString")) do out[#out + 1] = plain(fs._text) end
            for _, b in ipairs(shownUnder(root, "Button")) do out[#out + 1] = plain(b._text) end
            return table.concat(out, "\n")
        end
        local all = texts(panel)
        ok(not all:find("。", 1, true), "no 「。」 on the roster: " .. all)
        ok(not all:find("%d%d%d%d%-%d%d%-%d%d"), "no date on the roster")
        ok(not all:find("點一列", 1, true), "no 點一列選成員")
        ok(not all:find("更新名冊", 1, true), "更新 (was 更新名冊)")
        -- Nothing matched: an icon and 沒有.
        ns.UI.searchBox:SetText("沒有這個人"); ns.UI.refresh(true)
        eq(ns.UI.emptyKey, "noMatch", "no rows")
        ok(ns.UI.emptyIcon:IsShown() and ns.UI.emptyIcon._w == 48, "48 px icon")
        eq(ns.UI.emptyLabel:GetText(), "沒有", "沒有")
        ns.UI.searchBox:SetText(""); ns.UI.refresh(true)
        eq(ns.UI.emptyKey, nil, "rows again")
        ok(not ns.UI.emptyIcon:IsShown(), "icon gone")
        -- Not in a guild / loading / no roster yet.
        for state, want in pairs({ none = "未入會", loading = "讀取中" }) do
            ns.UI.drawEmpty(state)
            eq(ns.UI.emptyLabel:GetText(), want, state)
        end
        ns.UI.drawEmpty("noRoster")
        ok(ns.UI.emptyUpdate:IsShown(), "no roster: the 更新 button in the middle")
        ok(ns.UI.emptyIcon._texture:find("RefreshButton"), "with the refresh icon")
        -- Recipes and orders pages.
        ns.Framework.open("recipes")
        local rtexts = texts(ns.Framework.panel("recipes"))
        ok(not rtexts:find("。", 1, true), "no 「。」 on the recipe page: " .. rtexts)
        ns.Framework.open("orders")
        ok(not texts(ns.Framework.panel("orders")):find("。", 1, true), "no 「。」 on the orders page")
        -- The scan time is in 同步與診斷.
        ok(ns.Diag.rosterText():find("掃描時間", 1, true), "scan time in 同步與診斷")
    end)

    test("GF-UI-B ★4 clickable names are 2-4 characters (roster, recipes, orders, 同步與診斷, module list)", function()
        local ns = login({ guildPerms = { invite = true, viewOfficer = true }, myRankIndex = 0 })
        local function check(root, what)
            for _, b in ipairs(shownUnder(root, "Button")) do
                local t = b._text ~= "" and b._text or (b.label and b.label._text) or ""
                if plain(t) ~= "" and b.gfTheme == "button" then
                    ok(cjk(t) <= 4, what .. ": " .. plain(t))
                end
            end
            for _, c in ipairs(shownUnder(root, "CheckButton")) do
                if c.label then ok(cjk(c.label._text) <= 4, what .. " check: " .. plain(c.label._text)) end
            end
        end
        ns.Framework.open("roster"); check(ns.Framework.panel("roster"), "roster")
        ns.Framework.open("recipes"); check(ns.Framework.panel("recipes"), "recipes")
        ns.Recipes.show(ns.Data.player().guid)
        ok(ns.Recipes.clearFilterButton:IsShown(), "全部 shown for one member")
        eq(plain(ns.Recipes.clearFilterButton:GetText()), "全部", "全部 (was 看全部的人)")
        ns.Framework.open("orders"); check(ns.Framework.panel("orders"), "orders")
        ns.Diag.open(); check(ns.Diag.window(), "同步與診斷")
        local names = {}
        for _, b in ipairs(ns.Framework.navButtons()) do
            -- GF-UI-E (spec v2.0 §3): the six entries have 4-character names (was 2).
            if b:IsShown() then names[#names + 1] = b:GetText(); eq(cjk(b:GetText()), 4, "entry name: " .. b:GetText()); eq(b._h, 30, "30 px") end
        end
        ok(table.concat(names, ","):find("職工名冊,委託業務", 1, true), "職工名冊, 委託業務: " .. table.concat(names, ","))
        ok(ns.Framework.isShown(), "window open")
        eq(_G.GreenFangToolkit_MainWindow.TitleText:GetText(), "綠皮冒險工具箱｜訂單", "the window title keeps the full name")
    end)

    ---------------------------------------------------------------------------
    -- ★5 inline icons ≥ 16; ★6 arrows and check boxes as textures; ★7 30 px; ★8 stripes
    ---------------------------------------------------------------------------

    test("GF-UI-B ★5 every |T…:N|t on the roster, recipes, orders and 同步與診斷 is at least 16 px", function()
        local ns = login()
        ns.Orders.setActive(SKILL, true)
        local bad = {}
        local function scan(root, what)
            for _, o in ipairs(shownUnder(root)) do
                for n in tostring(o._text or ""):gmatch("|T[^|]-:(%d+)[:|]") do
                    if tonumber(n) < 16 then bad[#bad + 1] = what .. ":" .. plain(o._text) .. "@" .. n end
                end
            end
        end
        ns.Framework.open("roster"); scan(ns.Framework.panel("roster"), "roster")
        ns.Framework.open("recipes"); scan(ns.Framework.panel("recipes"), "recipes")
        ns.Framework.open("orders"); scan(ns.Framework.panel("orders"), "orders")
        ns.Diag.open(); scan(ns.Diag.window(), "diag")
        eq(table.concat(bad, ","), "", "no inline icon under 16 px")
        eq(ns.OrdersUI.tex("online"), "|TInterface\\FriendsFrame\\StatusIcon-Online:18|t", "default 18")
        eq(ns.OrdersUI.tex("online", 10), "|TInterface\\FriendsFrame\\StatusIcon-Online:16|t", "never under 16")
    end)

    test("GF-UI-B ★6 drop-downs: a texture arrow, text left; multi-select lists draw ticked and empty boxes", function()
        local ns = login()
        ns.Framework.open("roster")
        local b = ns.UI.skillChoice
        ok(b.arrow and b.arrow:IsShown(), "arrow texture")
        ok(b.arrow._texture:find("UI%-ChatIcon%-ScrollDown%-Up"), "the chat scroll-down arrow")
        eq(b.arrow._w, 24, "24 px")
        ok(not b:GetText():find("▼", 1, true), "no ▼ character")
        for _, file in ipairs({ "UI.lua", "Recipes.lua", "OrdersUI.lua", "Framework.lua", "Diag.lua" }) do
            local f = io.open(ADDON_DIR .. "/" .. file, "r")
            local src = f:read("*a"); f:close()
            ok(not src:find("▼", 1, true) and not src:find("▲", 1, true), file .. ": no arrow characters")
        end
        ns.Framework.open("recipes")
        local w = ns.Recipes.whoChoice
        w.toggle("others")
        wow.click(w)
        local boxes = {}
        for _, it in ipairs(w.menu.items) do
            if it:IsShown() and it.isOption then
                ok(it.check:IsShown(), "box drawn: " .. it.label._text)
                eq(it.check._texture, "Interface\\Common\\UI-DropDownRadioChecks", "drop-down check sheet")
                boxes[#boxes + 1] = it.label._text .. (it.checked and "[x]" or "[ ]") .. it.check._texCoord[1]
            end
        end
        eq(table.concat(boxes, ","), "我[x]0,別人[ ]0.5", "ticked and empty boxes")
    end)

    test("GF-UI-B ★7 text buttons 30 px (roster, 同步與診斷, the 診斷 button on every page)", function()
        local ns = login()
        local function heights(root, what)
            for _, b in ipairs(shownUnder(root, "Button")) do
                if b.gfTheme == "button" then eq(b._h, 30, what .. ": " .. plain(b._text)) end
            end
        end
        ns.Framework.open("roster"); heights(ns.Framework.panel("roster"), "roster")
        ns.Framework.open("orders"); heights(ns.Framework.panel("orders"), "orders")
        ns.Framework.open("recipes"); heights(ns.Framework.panel("recipes"), "recipes")
        ns.Diag.open(); heights(ns.Diag.window(), "diag")
        ok(#ns.Diag.smallButtons() >= 2, "診斷 on the roster and the orders page")
        for _, b in ipairs(ns.Diag.smallButtons()) do
            ok(plain(b._text):find("診斷", 1, true) and cjk(b._text) == 2, "診斷")
            ok(not b._text:find("|T", 1, true), "GF-UI-C: words only")
        end
    end)

    test("GF-UI-B ★8 ns.COLOR; the same stripe on the roster, recipes and orders rows", function()
        local ns = login()
        for _, k in ipairs({ "gold", "white", "muted", "disabled", "good", "formed", "warn", "bad", "brand", "frame", "stripe" }) do
            ok(type(ns.COLOR[k]) == "table", "ns.COLOR." .. k)
        end
        eq(table.concat(ns.COLOR.stripe, ","), "1,1,1,0.04", "stripe")
        ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        local function stripes(rows, what)
            for _, r in ipairs(rows) do
                if r:IsShown() then
                    local c = r.bg._color
                    eq(c[1] .. "," .. c[2] .. "," .. c[3], "1,1,1", what .. " stripe colour")
                    ok(c[4] == 0 or c[4] == 0.04, what .. " stripe alpha " .. tostring(c[4]))
                end
            end
        end
        ns.Framework.open("roster"); stripes(ns.UI.rows(), "roster")
        ns.Framework.open("orders"); stripes(ns.OrdersUI.rowFrames(), "orders")
    end)

    ---------------------------------------------------------------------------
    -- ★10 the 5 s undo swirl; ★11 同步與診斷 16 px and scrollable
    ---------------------------------------------------------------------------

    test("GF-UI-B ★10 取消 waits 5 s with the action bar's cooldown swirl on the button", function()
        local ns = login()
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        ns.Framework.open("orders")
        local row
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then row = r end end
        ok(row, "my order row")
        local b = row.buttons[1]
        eq(b.action, "cancel", "取消")
        eq(b.cd._template, "CooldownFrameTemplate", "a cooldown frame")
        ok(not b.cd:IsShown(), "no swirl before")
        wow.click(b)
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then row = r end end
        b = row.buttons[1]
        ok(b.cd:IsShown(), "swirl while it can be undone")
        eq(b.cd.gfDuration, 5, "5 seconds")
        eq(b.tip, "復原", "復原")
        wow.advance(5.5)
        eq(ns.Orders.get(id).state, "cancel", "cancelled after 5 s")
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do
            if r:IsShown() then for _, x in ipairs(r.buttons) do ok(not x.cd:IsShown(), "no swirl left") end end
        end
    end)

    test("GF-UI-B ★11 同步與診斷: 16 px, a scroll frame, every section right under the one before", function()
        local ns = login()
        local f = ns.Diag.open()
        eq(f.scroll._template, "UIPanelScrollFrameTemplate", "scrollable")
        eq(fontSize(f.state), 18, "state 18 px")
        local heads, lines = ns.Diag.heads(), ns.Diag.lines()
        for i, body in ipairs(lines) do
            eq(fontSize(body), 16, "body 16 px")
            eq(fontSize(heads[i]), 16, "section name 16 px")
            eq(body._parent, f.content, "inside the scroll child")
            if heads[i + 1] then
                ok(body.gfY + body.gfH + 12 <= heads[i + 1].gfY + 0.01, "section " .. i .. " ends before the next name")
            end
        end
        -- A very long section pushes the next one down instead of covering it.
        ns.Diag.SITE_NOTE = string.rep("很長的說明", 80)
        local before = heads[3].gfY
        ns.Diag.refresh()
        ok(heads[3].gfY > before, "the next section moved down")
        ok(f.content._h >= heads[#heads].gfY, "the scroll child grows")
        eq(plain(ns.Diag.exportTSVButton:GetText()), "TSV", "TSV")
        eq(plain(ns.Diag.minimapButton:GetText()), "小地圖", "小地圖")
        wow.clearPrinted()
        wow.click(ns.Diag.minimapButton)
        eq(#wow.printed(), 0, "no chat sentence after 小地圖")
        eq(ns.Diag.minimapButton:GetText(), "已重置", "GF-UI-C: words instead of a tick")
    end)

    ---------------------------------------------------------------------------
    -- Roster click (owner): icon = that member's recipes; elsewhere = select
    ---------------------------------------------------------------------------

    test("GF-UI-B roster click: a profession icon opens that member's recipes of it; elsewhere selects; right-click unchanged", function()
        local ns = login()
        ns.Framework.open("roster")
        local row = rowOf(ns, "測試丙-測試伺服器")
        local slot = row.profSlots[1]
        ok(slot.entry and slot.entry.prof, "a profession icon")
        local skill = ns.Professions.skillLineOf(slot.entry.prof)
        eq(ns.UI.rowClick(row, "LeftButton", slot), "recipes", "left click on the icon")
        ok(ns.Framework.isModuleShown("recipes"), "the recipe page")
        eq(ns.Recipes.skillChoice.selected and ns.Recipes.skillChoice.selected[skill], true, "only that profession ticked")
        ok(table.concat(wow.allTexts(), "\n"):find("只看：測試丙", 1, true), "only that member")
        eq(ns.UI.filters.skill, nil, "the roster filter is not touched")
        ns.Framework.open("roster")
        row = rowOf(ns, "測試丙-測試伺服器")
        eq(ns.UI.rowClick(row, "LeftButton", nil), "select", "left click elsewhere")
        eq(ns.UI.selected.name, "測試丙-測試伺服器", "selected")
        ok(ns.Framework.isModuleShown("roster"), "stays on the roster")
        eq(ns.UI.rowClick(row, "RightButton", slot), "order-menu", "right-click on the icon: 下單給")
        ns.closeMenus()
        eq(ns.UI.rowClick(row, "RightButton", nil), "member-menu", "right-click elsewhere: the member menu")
        ns.closeMenus()
        -- Through the row's own mouse handler.
        local real = ns.UI.cursorX
        ns.UI.cursorX = function() return slot.x0 + 2 end
        row._scripts.OnMouseUp(row, "LeftButton")
        ns.UI.cursorX = real
        ok(ns.Framework.isModuleShown("recipes"), "OnMouseUp on the icon: recipes")
    end)

    ---------------------------------------------------------------------------
    -- The order test mode (owner: test mode plus alts)
    ---------------------------------------------------------------------------

    local function testOrder(ns)
        local me = ns.Share.selfAuthor()
        local d = ns.OrdersUI.openOrder({ recipe = RECIPE, skill = SKILL,
            crafters = { { name = "測試甲-測試伺服器", guid = ns.Data.player().guid, online = true, self = true } } })
        eq(d.crafter, me, "my own recipe and nobody else: the test order to myself")
        local id = ns.OrdersUI.submit(d)
        ok(id, "placed")
        return id
    end
    local function rowFor(ns, id)
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then return r end end
    end
    local function labels(r)
        local out = {}
        for _, b in ipairs(r.buttons) do if b:IsShown() then out[#out + 1] = b.label._text end end
        return table.concat(out, ",")
    end
    local function mentions(t, id, seen)
        seen = seen or {}
        if type(t) == "string" then return t:find(id, 1, true) ~= nil end
        if type(t) ~= "table" or seen[t] then return false end
        seen[t] = true
        for k, v in pairs(t) do if mentions(k, id, seen) or mentions(v, id, seen) then return true end end
        return false
    end

    test("GF-UI-B test mode: off = no order to myself; 測試 in 同步與診斷 turns it on", function()
        local ns = login()
        local O = ns.Orders
        local me = ns.Share.selfAuthor()
        eq(O.testOn(), false, "off by default")
        local id, why = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = me })
        eq(id, nil, "no order to myself")
        eq(why, "self", "why")
        local d = ns.OrdersUI.newDraft({ recipe = RECIPE, skill = SKILL,
            crafters = { { name = "測試甲-測試伺服器", guid = ns.Data.player().guid, self = true } } })
        eq(#d.crafters, 0, "I am not in the crafter list")
        ns.Diag.open()
        wow.click(ns.Diag.testCheck)
        eq(O.testOn(), true, "on")
        ok(ns.Diag.ordersText():find("測試模式", 1, true), "said in 同步與診斷")
        eq(cjk(ns.Diag.testCheck.label._text), 2, "測試")
        ok(not ns.Diag.testCheck.label._text:find("|T", 1, true), "GF-UI-C: words only")
    end)

    test("GF-UI-B test mode: one window plays both sides: 接單 → 已交付 → 成交; marked 測試", function()
        local ns = login()
        local O = ns.Orders
        O.setTestMode(true)
        local id = testOrder(ns)
        ok(O.isTestId(id), "a test id: " .. id)
        local v = O.get(id)
        ok(v.test, "marked test")
        eq(v.customer, ns.Share.selfAuthor(), "I am the customer"); eq(v.crafter, ns.Share.selfAuthor(), "and the crafter")
        ns.Framework.open("orders")
        local r = rowFor(ns, id)
        ok(r, "on the orders page")
        eq(r.who._text, "測試", "測試 in the 對象 column")
        ok(r.cls._texture:find("EngGizmos", 1, true), "with the test icon")
        eq(table.concat(r.who._color, ","), "1,0.55,0.15", "warn colour")
        eq(labels(r), "接單,取消", "waiting: 接單 (crafter) and 取消 (customer)")
        wow.click(r.buttons[1]); r = rowFor(ns, id)
        eq(O.get(id).state, "making", "accepted")
        eq(labels(r), "已交付,取消", "making: 已交付 and 取消")
        wow.click(r.buttons[1]); r = rowFor(ns, id)
        eq(O.get(id).state, "checking", "delivered (manual)")
        eq(labels(r), "成交,退回,取消", "checking: 成交, 退回, 取消")
        wow.click(r.buttons[1])
        eq(O.get(id).state, "deal", "成交")
        eq(O.get(id).closedBy, "customer", "closed by me as the customer")
        -- A second one closed as 取消 (5 s undo, as always).
        local id2 = testOrder(ns)
        r = rowFor(ns, id2)
        wow.click(r.buttons[2]) -- 取消
        wow.advance(5.5)
        eq(O.get(id2).state, "cancel", "取消")
        -- No history for test orders.
        local key = ns.Data.player().guid
        for _, h in ipairs(O.local_().history[key] or {}) do ok(not O.isTestId(h.id), "no test order in history") end
    end)

    test("GF-UI-B test mode: test orders never reach guild addon messages, the ledger or the upload", function()
        local ns = login()
        local O = ns.Orders
        O.setTestMode(true)
        O.setActive(SKILL, true)
        wow.state.sent = {}
        local id = testOrder(ns)
        O.press(O.get(id), "accept")
        O.press(O.get(id), "deliver")
        wow.advance(120)
        for _, m in ipairs(wow.state.sent) do ok(not m.msg:find(id, 1, true), "never sent: " .. m.prefix) end
        local me = ns.Share.selfAuthor()
        for _, g in ipairs({ "W", "J" }) do
            local rec = O.ledger:get(me, g)
            ok(not (rec and rec.v:find(id, 1, true)), "not in my " .. g .. " record")
        end
        local c = O.craftingFor(me)
        ok(not (c and c.orders and c.orders[id]), "not in crafting (character.self / member.share)")
        ns.Sync.recordSelf(true)
        ns.Sync.recordShares()
        ok(not mentions(GreenFangToolkitDB.sync.outbox, id), "not in the outbox")
        -- A real order to someone else (an alt is another member) still goes out as usual.
        local real = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = B })
        ok(real and not O.isTestId(real), "a normal order: " .. tostring(real))
        ok(not O.get(real).test, "not a test order")
        ok(O.ledger:get(me, "W").v:find(real, 1, true), "in my W record")
        wow.advance(120)
        local sent = false
        for _, m in ipairs(wow.state.sent) do if m.prefix == "GFTKO" and m.msg:find(real, 1, true) then sent = true end end
        ok(sent, "and sent to the guild")
        ns.Sync.recordSelf(true)
        ok(mentions(GreenFangToolkitDB.sync.outbox, real), "and uploaded")
        ok(not mentions(GreenFangToolkitDB.sync.outbox, id), "the test order still not")
    end)

    test("GF-UI-B test mode: turning it off deletes every test order; at login they are gone too", function()
        local ns = login()
        local O = ns.Orders
        O.setTestMode(true)
        local id = testOrder(ns)
        ok(O.get(id), "there")
        eq(O.testCount(), 1, "one test order")
        ns.Diag.open()
        ns.Diag.refresh()
        wow.click(ns.Diag.testCheck)
        eq(O.testOn(), false, "off")
        eq(O.get(id), nil, "deleted")
        eq(GreenFangToolkitDB.orders.test, nil, "nothing left in the SavedVariables")
        -- On again: empty; place one and log out with the mode on: still there next login (local).
        O.setTestMode(true)
        id = testOrder(ns)
        local saved = wow.logout()
        local ns2 = wow.login(ADDON_DIR, saved)
        ok(ns2.Orders.get(id), "kept while the mode is on")
        -- Mode off in the file but test orders left (an older build): cleaned at maintain.
        GreenFangToolkitDB.orders.testMode = nil
        ns2.Orders.maintain()
        eq(GreenFangToolkitDB.orders.test, nil, "cleaned")
    end)
end
