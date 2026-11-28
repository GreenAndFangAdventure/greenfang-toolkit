-- GF-UI-S: the owner's seven simplifications (2026-11-28): one name 臨時黑箱
-- (黑箱 only where it has to be short), 開單's 說明 named 備註, one button on
-- 調貨所 (集料項目), 關於網站 in 同步與診斷, no 診斷 buttons (the version takes
-- the sync colour), ＋下單 goes to 工匠配方 (no 選配方 window), 名冊's 更多篩選.
-- Offline only; not checked in the Forever client. Made-up data.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local shareLogin, shareFrom, rMsg, leatherWindow = T.shareLogin, T.shareFrom, T.rMsg, T.leatherWindow
    local PEER, A_PEER, A_THIRD = T.PEER, T.A_PEER, T.A_THIRD

    local function readAll(path) local h = io.open(path, "rb"); if not h then return "" end local s = h:read("*a"); h:close(); return s end
    local function has(s, sub) return tostring(s):find(sub, 1, true) ~= nil end
    local function plain(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function login()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        wow.advance(25)
        return ns
    end
    local function tipText()
        local out = {}
        for _, l in ipairs(GameTooltip._lines or {}) do out[#out + 1] = tostring(l.text) end
        return table.concat(out, "\n")
    end
    -- Every visible text under a frame (FontStrings and button texts).
    local function texts(root, acc, depth)
        acc = acc or {}
        depth = depth or 0
        if not root or depth > 12 then return acc end
        if root._text and root.IsVisible and root:IsVisible() then acc[#acc + 1] = plain(root._text) end
        for _, c in ipairs(root._children or {}) do texts(c, acc, depth + 1) end
        for _, r in ipairs(root._regions or {}) do
            if r._text and r.IsVisible and r:IsVisible() then acc[#acc + 1] = plain(r._text) end
        end
        return acc
    end
    -- The Lua lines of the AddOn that are not comments.
    local function codeLines()
        local toc = readAll(ADDON_DIR .. "/GreenFangToolkit.toc")
        local out = {}
        for file in toc:gmatch("([%w_]+%.lua)") do
            for line in readAll(ADDON_DIR .. "/" .. file):gmatch("[^\n]+") do
                if not line:match("^%s*%-%-") then out[#out + 1] = { file = file, line = line } end
            end
        end
        return out
    end

    ---------------------------------------------------------------------------
    -- 1. 臨時黑箱
    ---------------------------------------------------------------------------

    test("GF-UI-S 1 one name: 臨時黑箱; 黑箱 alone only in a column, a filter or a tag; no 臨時秘密黑箱", function()
        local ns = login()
        for _, l in ipairs(codeLines()) do
            ok(not has(l.line, "臨時秘密黑箱"), l.file .. ": 臨時秘密黑箱 left: " .. l.line)
        end
        local def = ns.Framework.get("bank")
        eq(def.title, "臨時黑箱", "the page's name (was 臨時秘密黑箱)")
        eq(def.subTitle, "臨時黑箱", "the sub-tab")
        ns.Framework.open("bank")
        local U = ns.SupplyUI
        eq(U.STOCK_NAME, "臨時黑箱", "the board's name")
        eq(U.STOCK_OWN_NAME, "我保管的臨時黑箱", "my own custody")
        eq(U.STOCK_TEXT, "黑箱", "the short word stays for the 條件 cell and the tag")
        eq(U.HEADINGS.guild[4], "黑箱", "the column keeps the short word")
        eq(U.KIND_ITEMS.guild[4].text, "黑箱", "the 種類 option keeps the short word")
        ok(has(U.EMPTY.guild, "臨時黑箱"), "the empty words")
        ok(has(U.SCOPE_TIP, "臨時黑箱"), "the 範圍 tip")
        local R = ns.BankRequests.NOTIFY_TEXT
        for k, v in pairs(R) do ok(has(v, "臨時黑箱申領"), "notice " .. k .. ": " .. v) end
        eq(ns.Notify.MODULE_TEXT.bank_keeper, "臨時黑箱保管人", "notice switch")
        eq(ns.Notify.MODULE_TEXT.bank_request, "臨時黑箱申領", "notice switch")
        -- 說明 mode: every 黑箱 is 臨時黑箱.
        for k, t in pairs(ns.Help.TEXT) do
            for _, s in ipairs(t) do
                local rest = s:gsub("臨時黑箱", "")
                ok(not has(rest, "黑箱"), "說明 " .. k .. ": " .. s)
            end
        end
        -- The detail line under an item: 「徵求 1 位｜臨時黑箱 5 個」.
        local it = { needs = { {} }, offers = {}, others = {}, onlineCount = 0, stock = { qty = 5 } }
        local oldQty = U.stockQty
        U.stockQty = function() return 5 end
        ok(has(U.boardSub(it), "臨時黑箱 5 個"), "boardSub: " .. U.boardSub(it))
        U.stockQty = oldQty
    end)

    ---------------------------------------------------------------------------
    -- 2. 開單: 備註
    ---------------------------------------------------------------------------

    test("GF-UI-S 2 開單: the field for the people signing up is 備註; saved as before (draft.note)", function()
        local ns = login()
        ns.Framework.open("adventure")
        local A = ns.AdventureUI
        eq(table.concat(A.TICKET_MAIN, ","), "活動,職責,時段,備註", "the first rows")
        A.openTicket()
        local f = _G[A.TICKET_NAME]
        ok(f.fieldStrings["備註"] and f.fieldStrings["備註"]:IsShown(), "備註 shown")
        eq(f.fieldStrings["說明"], nil, "no field named 說明")
        eq(f.note.fieldNamed, "備註", "the box's name")
        f.note:SetText("在暴風城門口集合")
        f.note._scripts.OnTextChanged(f.note)
        eq(A.draft().note, "在暴風城門口集合", "kept in the draft's note (saved and shared as before)")
        eq(ns.Help.TEXT.ticket_note[1], "備註", "說明 mode")
        -- No other 備註 on the ticket (the worker ticket has none either).
        local n = 0
        for name in pairs(f.fieldStrings) do if name == "備註" then n = n + 1 end end
        eq(n, 1, "one 備註")
        f:Hide()
    end)

    ---------------------------------------------------------------------------
    -- 3. 調貨所: one button, 集料項目
    ---------------------------------------------------------------------------

    test("GF-UI-S 3 調貨所: no 說明 by 手動刊登; 集料項目 lists the items only; the words are in 說明 mode", function()
        local ns = login()
        ns.Framework.open("supply")
        local U = ns.SupplyUI
        eq(U.manualBox.help, nil, "no 說明 button by 手動刊登")
        eq(U.autoBox.help._text, "集料項目", "renamed")
        eq(U.SWITCH_HELP.manual, nil, "no manual help")
        eq(U.openCard("manual"), nil, "no 手動刊登說明 card")
        local f = U.openCard("auto", U.autoBox.help)
        ok(f and f:IsShown(), "the card opens")
        eq(f.TitleText and f.TitleText._text or U.CARD_TITLE.auto, "集料項目", "its title")
        eq(f.sub, nil, "no subtitle")
        eq(#f.lines, 0, "no sentences")
        ok(f.itemsTitle and f.itemsTitle._text == U.CARD_ITEMS_TITLE, "the list's heading")
        ok(f.share, "分享的餘料 stays (it is a setting, not words)")
        -- The manual line reaches the right edge now.
        local X = U.SWITCH_X
        eq(U.manualBox.line._w or U.manualBox.line._fixedWidth, U.SWITCH_RIGHT - X.line, "the line uses the freed room")
        local H = ns.Help
        ok(has(H.TEXT.supply_auto[2], "預設關") and has(H.TEXT.supply_auto[2], "不公開背包"), "自動集料's main points")
        ok(has(H.TEXT.supply_manual[2], "關掉後") and has(H.TEXT.supply_manual[2], "密語"), "手動刊登's main points")
        eq(H.TEXT.supply_auto_help[1], "集料項目", "the button's name")
        eq(H.TEXT.supply_manual_help, nil, "no entry for the removed button")
        for _, e in ipairs(H.pages.supply) do ok(e.key ~= "supply_manual_help", "not registered") end
        ok(not has(U.SWITCH_TIP.auto, "說明與項目"), "the tip names the new button")
        f:Hide()
    end)

    ---------------------------------------------------------------------------
    -- 4. 同步與診斷: 關於網站
    ---------------------------------------------------------------------------

    test("GF-UI-S 4 同步與診斷: the first heading is 關於網站", function()
        local ns = login()
        ns.Diag.open()
        local found = false
        for _, h in ipairs(ns.Diag.heads()) do
            ok(plain(h._text) ~= "說明", "no heading 說明")
            if plain(h._text) == "關於網站" then found = true end
        end
        ok(found, "關於網站 (the site's words, after 上傳到公會網站)")
    end)

    ---------------------------------------------------------------------------
    -- 5. no 診斷 buttons; the version has the colour
    ---------------------------------------------------------------------------

    test("GF-UI-S 5 no 診斷 on 名冊／委託／冒險; the version takes the sync colour and says what it means", function()
        local ns = login()
        eq(ns.Diag.smallButton, nil, "no 診斷 maker")
        for _, id in ipairs({ "roster", "orders", "adventure" }) do
            ns.Framework.open(id)
            for _, t in ipairs(texts(ns.Framework.panel(id))) do ok(t ~= "診斷", id .. ": 診斷 gone") end
        end
        local F = ns.Framework
        local b = F.infoButton()
        ok(b and b:IsShown(), "the version shows")
        -- The mock's buttons have no GetFontString; the game's do.
        local fs = b:CreateFontString(nil, "ARTWORK")
        b.GetFontString = function() return fs end
        F.paintInfo()
        local c = ns.Sync.statusColor()
        eq(fs._color[1], c[1], "red"); eq(fs._color[2], c[2], "green"); eq(fs._color[3], c[3], "blue")
        b._scripts.OnEnter(b)
        local tip = tipText()
        ok(has(tip, F.SYNC_COLOR_TIP.on), "the tooltip says what green means: " .. tip)
        ok(has(tip, F.GFSYNC_CLICK), "and that a click opens 同步與診斷")
        b._scripts.OnLeave(b)
        eq(fs._color[2], c[2], "the colour is back after the mouse leaves")
        -- A sync change paints it again (no timer, no OnUpdate).
        fs:SetTextColor(1, 1, 1)
        ns.Sync.notify()
        eq(fs._color[1], c[1], "repainted on a sync change")
        ok(not b._scripts.OnUpdate, "no OnUpdate")
        b._scripts.OnClick(b)
        ok(ns.Diag.isShown(), "a click opens 同步與診斷")
    end)

    test("GF-UI-S 5 名冊's bottom row: 邀請／公會 end where 診斷 ended, nothing left in the corner", function()
        local ns = login()
        ns.Framework.open("roster")
        local U = ns.UI
        U.refreshAdminButtons()
        local right
        for _, b in ipairs({ U.inviteButton, U.infoButton }) do
            if b:IsShown() then
                local p = b._points[1]
                local r = p[4] + b.gfWidth
                if not right or r > right then right = r end
            end
        end
        if right then eq(right, ns.Framework.PANEL_WIDTH - 20, "the last button's right edge") end
        local s = readAll(ADDON_DIR .. "/OrdersUI.lua") .. readAll(ADDON_DIR .. "/AdventureUI.lua") .. readAll(ADDON_DIR .. "/UI.lua")
        ok(not has(s, "smallButton("), "no page makes one")
    end)

    ---------------------------------------------------------------------------
    -- 6. ＋下單 goes to 工匠配方
    ---------------------------------------------------------------------------

    local function recipeLogin()
        local ns = shareLogin({ tradeSkill = leatherWindow() })
        wow.fire("TRADE_SKILL_SHOW")
        local t = wow.state.now - 600
        shareFrom(ns, PEER, (rMsg(ns, A_PEER, 165, t, { 2152, 2153 })))
        shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 165, t, { 2153, 2160 })))
        local sv = ns.Orders.encodeServices({ active = { [165] = true }, fees = { [165] = 500 }, recipeFees = {}, recipeSkill = {} })
        ns.Orders.ledger:offer(A_PEER, "O", ns.Share.serverNow(), ns.Share.hash(sv), sv)
        ns.Orders.resetSession()
        return ns
    end
    local function orderRow(ns)
        for _, row in ipairs(ns.Recipes.rowFrames()) do
            if row:IsShown() and row.data and row.order:IsShown() and row.order.action == "order" then return row end
        end
        return nil
    end

    test("GF-UI-S 6 ＋下單: switches to 工匠配方 (no 選配方 window); a row's 下單 opens the order form", function()
        local ns = recipeLogin()
        local O = ns.OrdersUI
        ns.Framework.open("orders")
        eq(O.openPicker, nil, "no picker")
        eq(O.PICKER_NAME, nil, "no picker name")
        O.orderButton._scripts.OnClick(O.orderButton)
        eq(ns.Framework.current(), "recipes", "on 工匠配方")
        eq(_G.GreenFangToolkit_RecipePicker, nil, "no 選配方 window made")
        eq(ns.Recipes.state.guid, nil, "every member's recipes")
        local row = orderRow(ns)
        ok(row, "a row with 下單")
        row._scripts.OnEnter(row)
        ok(has(tipText(), ns.Recipes.ORDER_HINT), "the row says how to order")
        ok(has(tipText(), "工錢"), "and what the fee icon means")
        row._scripts.OnLeave(row)
        row.order._scripts.OnClick(row.order)
        local form = _G[O.POPUP_NAME]
        ok(form and form:IsShown(), "the order form")
        form:Hide()
    end)

    test("GF-UI-S 6 工匠配方 has what 選配方 had: 搜尋 (Enter orders the first), 專業, 會做的人, 在線, 接單中, 工錢, scrolling", function()
        local ns = recipeLogin()
        local R = ns.Recipes
        ns.OrdersUI.startOrder()
        for _, w in ipairs({ R.searchBox, R.skillChoice, R.whoChoice, R.onlineCheck, R.activeCheck, R.feeChoice }) do
            ok(w and w:IsShown(), "filter shown")
        end
        local all = #R.shownRows()
        ok(all >= 2, "rows: " .. all)
        R.activeCheck._scripts.OnClick(R.activeCheck)
        ok(#R.shownRows() < all and #R.shownRows() >= 1, "接單中 narrows the list")
        R.activeCheck._scripts.OnClick(R.activeCheck)
        R.searchBox:SetText("zzzz不存在")
        R.searchBox._scripts.OnTextChanged(R.searchBox)
        wow.advance(1)
        eq(#R.shownRows(), 0, "search narrows")
        R.searchBox:SetText("")
        R.searchBox._scripts.OnTextChanged(R.searchBox)
        wow.advance(1)
        eq(#R.shownRows(), all, "back")
        R.searchBox._scripts.OnEnterPressed(R.searchBox)
        local form = _G[ns.OrdersUI.POPUP_NAME]
        ok(form and form:IsShown(), "Enter in 搜尋 opens the first orderable row")
        form:Hide()
        -- One filter set: no second copy of the picker code.
        local src = readAll(ADDON_DIR .. "/OrdersUI.lua")
        ok(not has(src, "pickerFilter") and not has(src, "PICKER_WHO") and not has(src, "drawPicker"), "the picker code is gone")
    end)

    test("GF-UI-S 6 the other ways in still work: 下單給 on the roster, the right-click 下單, the history menu", function()
        local ns = recipeLogin()
        local O = ns.OrdersUI
        ns.Framework.open("recipes")
        local row = orderRow(ns)
        ok(row, "a row")
        local items = O.recipeMenuItems(row.data)
        ok(items[1] and items[1].text == "下單", "right-click 下單")
        items[1].fn()
        ok(_G[O.POPUP_NAME]:IsShown(), "opens the form")
        _G[O.POPUP_NAME]:Hide()
        local member
        for _, m in ipairs(ns.Roster.current().members) do if m.guid ~= ns.Data.player().guid then member = m; break end end
        if member then
            local menu = O.rosterMenuItems(member, 165)
            ok(menu[1] and has(menu[1].text, "下單給"), "下單給 on the roster")
            menu[1].fn()
            eq(ns.Framework.current(), "recipes", "goes to 工匠配方")
            eq(ns.Recipes.state.guid, member.guid, "on that member")
        end
        ok(type(O.showHistory) == "function", "history menu kept (re-orders through openOrder)")
    end)

    test("GF-UI-S 6 說明 mode: no 選配方 group; 工匠配方's frames still fit after ＋下單", function()
        local ns = recipeLogin()
        local H = ns.Help
        eq(H.pages.picker, nil, "no 選配方 group")
        for name in pairs(H.POPUP) do ok(name ~= "GreenFangToolkit_RecipePicker", "no 選配方 pop-up") end
        for _, k in ipairs({ "pick_search", "pick_skill", "pick_who", "pick_fee", "pick_list" }) do eq(H.TEXT[k], nil, k .. " gone") end
        ok(has(H.TEXT.orders_new[2], "工匠配方"), "＋下單 says where it goes")
        ok(has(H.TEXT.recipes_list[2], "下單"), "the list says how to order")
    end)

    ---------------------------------------------------------------------------
    -- 7. 名冊: 更多篩選
    ---------------------------------------------------------------------------

    test("GF-UI-S 7 名冊: 在線／接單中／工具箱／等級 in 更多篩選; several at once; the count on the button; 清除 clears", function()
        local ns = login()
        ns.Framework.open("roster")
        local U = ns.UI
        local b, menu = U.moreFilterButton, U.moreFilterMenu
        ok(b and b:IsShown(), "更多篩選 on the tool bar")
        eq(plain(b._text), "更多篩選", "nothing on")
        for _, w in ipairs({ U.onlineCheck, U.activeCheck, U.toolkitCheck, U.levelBox }) do
            eq(w._parent, menu, "inside the drop-down")
        end
        ok(not menu:IsShown(), "closed at first")
        b._scripts.OnClick(b)
        ok(menu:IsShown() and ns.menusOpen(), "opens as a drop-down")
        U.onlineCheck._scripts.OnClick(U.onlineCheck)
        U.toolkitCheck._scripts.OnClick(U.toolkitCheck)
        ok(U.filters.online and U.filters.toolkit, "two at once")
        ok(menu:IsShown(), "stays open while ticking")
        U.levelBox:SetText("60")
        U.levelBox._scripts.OnTextChanged(U.levelBox)
        eq(U.filters.minLevel, 60, "等級")
        eq(plain(b._text), "更多篩選（3）", "the count")
        eq(b.gfSelected, true, "the chosen (gold) look while on")
        ns.closeMenus()
        ok(not menu:IsShown(), "a click outside closes it")
        U.clearFilters()
        ok(not U.filters.online and not U.filters.toolkit and not U.filters.active and U.filters.minLevel == nil, "清除 clears them")
        eq(U.onlineCheck.checked, false, "box cleared"); eq(U.levelBox._text or "", "", "level cleared")
        eq(plain(b._text), "更多篩選", "the count gone")
        eq(b.gfSelected, false, "not gold")
    end)

    test("GF-UI-S 7 名冊's tool bar: 更新 搜尋 專業 職業 更多篩選 清除 in a row, one gap, nothing overlapping", function()
        local ns = login()
        ns.Framework.open("roster")
        local U = ns.UI
        local function left(w) return w._points[1][4] end
        local list = { U.skillChoice, U.classChoice, U.moreFilterButton, U.clearButton }
        for i = 2, #list do
            local a, c = list[i - 1], list[i]
            eq(left(c), left(a) + (a.gfWidth or a._w) + U.TOOLBAR_GAP, "gap " .. i)
        end
        ok(left(U.clearButton) + U.clearButton.gfWidth < U.ROW_WIDTH + 20 - 120, "room for the count on the right")
        eq(U.toolbarRight, left(U.clearButton) + U.clearButton.gfWidth + U.TOOLBAR_GAP, "toolbarRight")
    end)

    test("GF-UI-S no OnUpdate, timer or event added; the help mode is still clean on 名冊 and 工匠配方", function()
        local ns = login()
        local src = readAll(ADDON_DIR .. "/UI.lua")
        local a = src:find("function UI.buildMoreFilter", 1, true)
        local e = src:find("\nend\n", a, true)
        local body = src:sub(a, e)
        ok(not has(body, "OnUpdate") and not has(body, "RegisterEvent") and not has(body, "ns.after"), "更多篩選 has none")
        -- (gfuir_tests.lua checks every page's frames for overlap; here: the new parts resolve.)
        ns.Framework.open("roster")
        local keys = {}
        for _, e in ipairs(ns.Help.pages.roster) do keys[e.key] = e end
        ok(keys.roster_more and keys.roster_more.get() == ns.UI.moreFilterButton, "更多篩選 registered")
        ok(not keys.roster_online and not keys.roster_level and not keys.diag, "the old parts gone")
    end)
end
