-- GF-UI-C (0.14.1): fixes from the owner's in-game test of 0.14.0 on the
-- roster, guild, orders, recipes and framework. Made-up names and GUIDs only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local C, D = "測試丙-測試伺服器", "測試丁-測試伺服器"
    local C_GUID = "Player-0000-0000000C"
    local ALL = { invite = true, promote = true, demote = true, remove = true, publicNote = true, officerNote = true,
        viewOfficer = true, motd = true, info = true }
    local RECIPE, ITEM, SKILL = 2660, 2862, 164

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession()
        return ns
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("^%s+", "")) end
    local function rowFor(ns, name)
        for _, r in ipairs(ns.UI.rows()) do if r:IsShown() and r.memberName == name then return r end end
    end
    local function barKeys(ns)
        local out = {}
        for _, b in ipairs(ns.UI.actionBar.buttons) do if b:IsShown() then out[#out + 1] = b.action end end
        return table.concat(out, ",")
    end
    local function calls() return table.concat(wow.state.guildCalls, ",") end
    local function select(ns, name)
        local r = rowFor(ns, name)
        ns.UI.select(r.member)
        return r
    end

    ---------------------------------------------------------------------------
    -- 1-3: 查看, the bar keeps only everyday actions, ranks in the menu
    ---------------------------------------------------------------------------

    test("GF-UI-C 1 查看 = inspect: only when the game has a unit for the member in range; it calls InspectUnit", function()
        local ns = login()
        ns.Framework.open("roster")
        select(ns, C)
        eq(barKeys(ns), "whisper,group", "not my target, not in my group: no 查看 (never a dead button)")
        wow.state.units = { target = C_GUID }
        select(ns, C)
        eq(barKeys(ns), "whisper,group,inspect", "my target: 查看")
        local b = ns.UI.actionBar.buttons[3]
        eq(b:GetText(), "查看", "查看")
        wow.click(b)
        eq(calls(), "inspect:target", "InspectUnit(target)")
        wow.state.units = { party2 = C_GUID }
        eq(ns.GuildAdmin.unitFor(rowFor(ns, C).member), "party2", "a party member")
        wow.state.farAway = true
        select(ns, C)
        eq(barKeys(ns), "whisper,group", "out of inspect range: no 查看")
        wow.state.farAway = nil
        eq(ns.GuildAdmin.canInspect({ guid = ns.Data.player().guid, name = "測試甲-測試伺服器" }), false, "never myself")
    end)

    test("GF-UI-C 2 the bar under the list: 密語, 組隊, 查看 only; officer tools only in the right-click menu", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        ns.Framework.open("roster")
        wow.state.units = { target = C_GUID }
        select(ns, C)
        eq(barKeys(ns), "whisper,group,inspect", "everyday actions only, with every right")
        for _, b in ipairs(ns.UI.actionBar.buttons) do
            if b:IsShown() then
                eq(b.gfTheme, "button", "text buttons (GF-UI-D: the theme button)")
                eq(b._h, 30, "30 px")
                ok(not b._text:find("|T", 1, true), "no icon")
            end
        end
        local keys = {}
        for _, it in ipairs(ns.UI.memberMenuItems(rowFor(ns, C).member)) do keys[#keys + 1] = it.key or (it.header and "header") or "?" end
        eq(table.concat(keys, ","), "header,whisper,group,inspect,demote,publicNote,officerNote,remove", "the menu has the officer tools")
    end)

    test("GF-UI-C 3 the right-click menu: the current rank first, 升階 / 降階 name where they lead", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 0 })
        ns.Framework.open("roster")
        local items = ns.UI.memberMenuItems(rowFor(ns, C).member) -- 會員 (index 2)
        eq(items[1].text, "會階 3 會員", "current rank: number and name")
        ok(items[1].header, "a header")
        local texts = {}
        for _, it in ipairs(items) do texts[#texts + 1] = it.text end
        local all = table.concat(texts, "|")
        ok(all:find("升階 ＞ 2 幹部", 1, true), "promote names the rank: " .. all)
        ok(all:find("降階 ＞ 4 新進", 1, true), "demote names the rank: " .. all)
        ok(not all:find("|T", 1, true), "text only")
        local menu = ns.showMenu(UIParent, items)
        ok(menu.items[1].header and menu.items[1]._enabled == false, "the header cannot be clicked")
        eq(wow.click(menu.items[1]), "ignored", "click on the header: nothing")
        eq(menu.items[2]._enabled, true, "the actions can")
        ns.closeMenus()
    end)

    ---------------------------------------------------------------------------
    -- 4-6: multi-select filters, the bottom buttons, guild info
    ---------------------------------------------------------------------------

    test("GF-UI-C 4 roster 專業 / 職業: multi-select with ticked and empty boxes", function()
        local ns = login()
        ns.Framework.open("roster")
        local U = ns.UI
        eq(U.skillChoice:GetText(), "全部專業", "all")
        eq(U.classChoice:GetText(), "全部職業", "all")
        local function names()
            local out = {}
            for _, r in ipairs(U.rows()) do if r:IsShown() then out[#out + 1] = r.memberName end end
            table.sort(out)
            return table.concat(out, ",")
        end
        U.classChoice.setOnly("MAGE")
        eq(names(), C, "one class")
        U.classChoice.toggle("HUNTER")
        eq(names(), D .. "," .. C, "two classes at once")
        eq(U.classChoice:GetText(), "2 個職業", "summary")
        wow.click(U.classChoice)
        local boxes = 0
        for _, it in ipairs(U.classChoice.menu.items) do
            if it:IsShown() and it.isOption then
                boxes = boxes + 1
                eq(it.check._texture, "Interface\\Common\\UI-DropDownRadioChecks", "drop-down check sheet")
            end
        end
        ok(boxes >= 4, "a box for every class")
        ns.closeMenus()
        U.clearFilters()
        eq(names(), "測試丁-測試伺服器,測試丙-測試伺服器,測試乙-測試伺服器,測試甲-測試伺服器", "清除: everyone")
        U.skillChoice.setOnly(164)
        eq(names(), "測試乙-測試伺服器", "鍛造 only")
        U.skillChoice.toggle(197)
        eq(names(), "測試丙-測試伺服器,測試乙-測試伺服器", "鍛造 or 裁縫")
        U.skillChoice.selectNone()
        eq(names(), "", "nothing ticked: nobody")
        eq(U.skillChoice:GetText(), "未選", "未選")
    end)

    test("GF-UI-C 5 bottom buttons 邀請 / 公會 / 診斷: words only; no 遊戲公會", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        ns.Framework.open("roster")
        eq(ns.UI.gameGuildButton, nil, "遊戲公會 gone")
        -- GF-UI-S: 診斷 is gone (its colour is on the version).
        for _, b in ipairs({ ns.UI.inviteButton, ns.UI.infoButton }) do
            ok(b:IsShown(), plain(b._text) .. " shown")
            ok(not b._text:find("|T", 1, true), plain(b._text) .. ": no icon")
        end
        eq(ns.UI.syncIndicator, nil, "no 診斷")
    end)

    test("GF-UI-C 6 guild info: the whole text (scrolls); 編輯 opens a large multi-line editor with 儲存 / 取消", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        ns.Framework.open("roster")
        wow.state.guildInfoText = string.rep("公會規定第一條要準時。\n", 30)
        local f = ns.UI.openGuildInfo()
        eq(f.info:GetText(), wow.state.guildInfoText, "the whole text")
        ok(f.infoContent._h > 400, "as high as the text needs: " .. tostring(f.infoContent._h))
        eq(f.infoScroll._template, "UIPanelScrollFrameTemplate", "in a scroll frame")
        wow.click(f.editInfo)
        local e = _G[ns.UI.INFO_EDIT_NAME]
        ok(e and e:IsShown(), "the editor")
        eq(wow.popup(), nil, "not the one-line game box")
        ok(e.box._multiLine ~= false, "a multi-line edit box")
        ok(e.box._h >= 200, "several lines in view")
        eq(e.box._parent, e.scroll, "inside a scroll frame")
        eq(e.box:GetText(), wow.state.guildInfoText, "starts with the current text")
        eq(plain(e.save._text) .. "," .. plain(e.cancel._text), "儲存,取消", "儲存 / 取消")
        e.box:SetText("新的公會資訊\n第二行")
        wow.click(e.cancel)
        eq(calls(), "", "取消: nothing saved")
        wow.click(f.editInfo)
        e.box:SetText("新的公會資訊\n第二行")
        wow.click(e.save)
        eq(calls(), "info:新的公會資訊\n第二行", "儲存: SetGuildInfoText with both lines")
        ok(not e:IsShown() and f:IsShown(), "back to the info window")
        eq(f.info:GetText(), "新的公會資訊\n第二行", "shown")
    end)

    ---------------------------------------------------------------------------
    -- 7: the profession window
    ---------------------------------------------------------------------------

    test("GF-UI-C 7 the toolkit steps aside while a profession window is open and comes back after", function()
        local ns = login()
        local F = ns.Framework
        F.open("orders")
        ns.OrdersUI.openServices()
        local svc = _G[ns.OrdersUI.SERVICES_NAME]
        wow.fire("TRADE_SKILL_SHOW")
        ok(not F.isShown() and not svc:IsShown(), "hidden while the profession window is open")
        wow.fire("TRADE_SKILL_CLOSE")
        ok(F.isShown() and svc:IsShown(), "back, with the popup")
        eq(F.current(), "orders", "on the same page")
        -- Craft window (enchanting), both open, closed one by one.
        wow.fire("CRAFT_SHOW"); wow.fire("TRADE_SKILL_SHOW")
        wow.fire("CRAFT_CLOSE")
        ok(not F.isShown(), "still hidden while the other one is open")
        wow.fire("TRADE_SKILL_CLOSE")
        ok(F.isShown(), "back when both are closed")
        -- Not open: nothing comes back.
        F.toggle()
        wow.fire("TRADE_SKILL_SHOW"); wow.fire("TRADE_SKILL_CLOSE")
        ok(not F.isShown(), "closed before: stays closed")
        -- Opened again by the player meanwhile: not shown twice, nothing breaks.
        F.open("roster")
        wow.fire("TRADE_SKILL_SHOW")
        F.open("roster")
        wow.fire("TRADE_SKILL_CLOSE")
        ok(F.isShown(), "open")
    end)

    ---------------------------------------------------------------------------
    -- 8-9: the 專業 row on the orders page, 清除紀錄
    ---------------------------------------------------------------------------

    local function threeCrafts()
        local p = wow.defaultPlayer()
        p.professions = {
            [1] = { "鍛造", 136241, 300, 300, 0, 0, 164 },
            [2] = { "裁縫", 136249, 300, 300, 0, 0, 197 },
            [4] = { "釣魚", 136245, 75, 150, 0, 0, 356 },
            [5] = { "烹飪", 133971, 60, 150, 0, 0, 185 },
        }
        p.professionIndexes = { 1, 2, nil, 4, 5 }
        return p
    end

    test("GF-UI-C 8 orders 專業 row: [icon] 接單/不接 [工錢] amount groups in even columns, never overlapping", function()
        local ns = login({ player = threeCrafts() })
        wow.advance(30) -- my professions are shared (P) a little after login
        local O, U = ns.Orders, ns.OrdersUI
        O.setActive(164, true)
        O.setFee(164, 9876543) -- a long amount
        O.setFee(185, 0)
        ns.Framework.open("orders")
        local shown = {}
        for _, b in ipairs(U.profButtons()) do if b:IsShown() then shown[#shown + 1] = b end end
        ok(#shown >= 2, "several professions: " .. #shown)
        local prevEnd
        for i, b in ipairs(shown) do
            local w = U.profGroupWidth(b)
            ok(w > ns.ICON, "measured")
            -- Inside the group: icon, its name, 工錢, the coin and the amount one after the other.
            local feeX = b.feeButton._points[1][4] - b.groupX
            ok(feeX >= ns.ICON + 4 + wow.textWidth("不接", ns.LABEL_FONT), "工錢 right of 接單/不接")
            local textX = b.feeText._points[1][4] - b.groupX
            ok(textX >= feeX + b.feeButton.gfWidth, "the amount right of 工錢")
            if prevEnd then ok(b.groupX >= prevEnd + 8, "group " .. i .. " starts after the previous one") end
            prevEnd = b.groupX + b.groupW
            if i > 1 then eq(b.groupX - shown[i - 1].groupX, U.profStep, "even columns") end
        end
        ok(prevEnd <= 1040, "inside the bar")
        -- The top buttons are above the row, apart.
        local ob, sb = U.orderButton, U.servicesButton
        ok(ob._points[1][5] - 30 >= -80, "＋下單 above the 專業 row")
        ok(not ob._text:find("|T", 1, true) and not sb._text:find("|T", 1, true), "words only")
    end)

    test("GF-UI-C 8 recipe rows: the 工錢 amount stops before 下單", function()
        local ns = login()
        local R = ns.Recipes
        ns.Framework.open("recipes")
        for _, row in ipairs(R.rowFrames()) do
            eq(row.fee._fixedWidth, R.COL_BUTTON - R.COL_FEE - 22 - 12, "amount width")
        end
        ok(R.COL_FEE + 22 + (R.COL_BUTTON - R.COL_FEE - 22 - 12) < R.COL_BUTTON, "ends before the button")
    end)

    test("GF-UI-C 9 清除紀錄: asks first, then deletes my closed orders (test ones too); open ones stay", function()
        local ns = login()
        local O = ns.Orders
        local open = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        local gone = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        O.customer(gone, "cancel")
        local deal = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        O.customer(deal, "deal")
        O.setTestMode(true)
        local me = ns.Share.selfAuthor()
        local t1 = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = me })
        O.customer(t1, "cancel")
        local t2 = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = me })
        local key = ns.Data.player().guid
        O.local_().history[key] = { { id = "gold.1", close = "deal" } }
        local n = O.closedCounts()
        eq(n.w .. "," .. n.test .. "," .. n.history, "2,1,1", "what would go")
        ns.Diag.open()
        wow.click(ns.Diag.clearButton)
        local p = wow.popup()
        ok(p and p.text:find("清除", 1, true), "the game's confirm box first")
        wow.cancelPopup()
        ok(O.get(gone), "cancelled: kept")
        wow.click(ns.Diag.clearButton)
        wow.acceptPopup()
        eq(O.get(gone), nil, "cancelled order gone")
        eq(O.get(deal), nil, "finished order gone")
        eq(O.get(t1), nil, "the cancelled test order gone")
        ok(O.get(open) and O.get(t2), "open orders stay")
        eq(O.local_().history[key], nil, "history cleared")
        ok(not O.ledger:get(me, "W").v:find(gone, 1, true), "gone from my W record")
        wow.click(ns.Diag.clearButton)
        eq(wow.popup(), nil, "nothing left: no box")
        eq(ns.Diag.clearButton:GetText(), "沒有結案", "says so on the button")
    end)

    ---------------------------------------------------------------------------
    -- 10-12: icons on text buttons, one grid, fewer icons
    ---------------------------------------------------------------------------

    test("GF-UI-C 10 icons on text buttons: at most button height - 8, square icons cropped", function()
        local ns = login()
        local U = ns.OrdersUI
        eq(U.buttonText("|TInterface\\Icons\\INV_Misc_Map_01:32|t 冒險"),
            "|TInterface\\Icons\\INV_Misc_Map_01:22:22:0:0:64:64:5:59:5:59|t 冒險", "22 px, cropped 0.08 - 0.92")
        eq(U.buttonText("|TInterface\\RaidFrame\\ReadyCheck-Ready:18|t 完成"),
            "|TInterface\\RaidFrame\\ReadyCheck-Ready:18|t 完成", "no square border: not cropped")
        eq(U.buttonText("|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:20:20:0:0:64:64:0:19:22:41|t 坦"),
            "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:20:20:0:0:64:64:0:19:22:41|t 坦", "a box from a sheet kept")
        local b = U.textButton(UIParent, "|TInterface\\Icons\\INV_Misc_Bag_10:20|t 測試")
        ok(b._text:find(":20:20:0:0:64:64:5:59:5:59|t", 1, true), "applied at creation")
        b:SetText("|TInterface\\Icons\\INV_Misc_Bag_10:40|t 又一次")
        ok(b._text:find(":22:22:", 1, true), "and on every SetText")
        -- The adventure page's buttons get it too (shared widget).
        ns.Framework.open("adventure")
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "Button" and o.gfTheme == "button" and o._shown then
                for n in tostring(o._text):gmatch("|T[^:|]+:(%d+)") do ok(tonumber(n) <= 22, "≤ 22: " .. o._text) end
                for path in tostring(o._text):gmatch("|T([^:|]+)") do
                    if path:find("^Interface\\Icons\\") then ok(o._text:find(":5:59:5:59|t", 1, true), "cropped: " .. o._text) end
                end
            end
        end
    end)

    test("GF-UI-C 11 one grid: recipe filters in four columns, list names at one x", function()
        local ns = login()
        local R = ns.Recipes
        ns.Framework.open("recipes")
        local C, DX = R.COLS, R.CONTROL_DX
        local function x(w) return w._points[1][4] end
        eq(x(R.searchBox), C[1] + DX, "搜尋 box")
        eq(x(R.skillChoice), C[2] + DX, "專業")
        eq(x(R.whoChoice), C[3] + DX, "會做的人")
        eq(x(R.feeChoice), C[3] + DX, "工錢 under 會做的人")
        eq(x(R.onlineCheck), C[1], "在線 under 搜尋")
        eq(x(R.activeCheck), C[2], "接單中 under 專業")
        eq(R.onlineCheck._points[1][5], R.activeCheck._points[1][5], "the check boxes on one line")
        for i = 2, #C do eq(C[i] - C[i - 1], 250, "even columns") end
        wow.click(R.skillChoice)
        local xs = {}
        for _, it in ipairs(R.skillChoice.menu.items) do
            if it:IsShown() then xs[it.label._points[1][4]] = true end
        end
        local n = 0
        for _ in pairs(xs) do n = n + 1 end
        eq(n, 1, "every name in the list starts at the same x (全選, 全不選 and the options)")
        ns.closeMenus()
    end)

    test("GF-UI-C 12 fewer icons: text buttons on the roster, orders, recipes and 同步與診斷 are words only", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        local function check(root, what)
            for _, o in ipairs(wow.allObjects()) do
                local f, inside = o, false
                while f do if f == root then inside = true end f = f._parent end
                if inside and o._kind == "Button" and o.gfTheme == "button" and o._text ~= "" then
                    ok(not o._text:find("|T", 1, true), what .. ": " .. o._text)
                end
                if inside and o._kind == "CheckButton" and o.label then
                    ok(not o.label._text:find("|T", 1, true), what .. " check: " .. o.label._text)
                end
            end
        end
        ns.Framework.open("roster"); check(ns.Framework.panel("roster"), "roster")
        ns.Framework.open("orders"); check(ns.Framework.panel("orders"), "orders")
        ns.Framework.open("recipes"); check(ns.Framework.panel("recipes"), "recipes")
        ns.Diag.open(); check(ns.Diag.window(), "diag")
        ns.OrdersUI.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} }); check(_G[ns.OrdersUI.POPUP_NAME], "order")
        ns.OrdersUI.editFee({ skill = SKILL }); check(_G[ns.OrdersUI.FEE_NAME], "fee")
        ns.UI.openGuildInfo(); check(_G[ns.UI.GUILD_INFO_NAME], "guild info")
    end)
end
