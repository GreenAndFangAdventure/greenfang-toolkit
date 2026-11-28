-- GF-UI-F: three pages after the GPT review of 0.16.0 — the 職工名冊 entry
-- icon, 人力盤點 above the column header, the 調貨所 column header / + - /
-- 收集組 / state panel, and the listing form asking before it drops unsaved
-- changes. Offline only (MANUAL §3uif has the in-game screenshot steps).
-- Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A_B = "0000-0000000B"
    local PEER_B = "測試乙-測試伺服器"
    local LONG_ITEM = "荊棘谷的青山第一章殘頁" -- 11 characters + 「頁」 below = 12
    local LONG_ITEM12 = LONG_ITEM .. "頁"
    local function page(n) return 2724 + n end

    -- A small fake game (quests, bag 0, item cache), as in supply_tests.lua.
    local G
    local function installGame(opts)
        opts = opts or {}
        G = { quests = opts.quests or {}, bag = opts.bag or {}, items = opts.items or {}, bagError = false }
        for n = 1, 27 do
            if not G.items[page(n)] then G.items[page(n)] = { name = "荊棘谷的青山第" .. n .. "頁", classID = 15, bindType = 0 } end
        end
        C_QuestLog = {
            IsQuestFlaggedCompleted = function(id) return G.quests[id] == "done" end,
            IsOnQuest = function(id) return G.quests[id] == "active" end,
        }
        C_Container = {
            GetContainerNumSlots = function(bag) if G.bagError then error("boom") end return bag == 0 and 20 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bag[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = false, iconFileID = 134939 }
            end,
        }
        GetItemInfo = function(id)
            local it = G.items[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1, "", "", 20, "", 134939,
                0, it.classID or 15, 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.items[id] and 134939 or nil end,
            GetItemNameByID = function(id) return G.items[id] and G.items[id].name or nil end,
            RequestLoadItemDataByID = function() end,
        }
        ChatFrame_SendTellWithMessage = function() end
    end
    local function removeGame()
        C_QuestLog, C_Container, GetItemInfo, C_Item, ChatFrame_SendTellWithMessage = nil, nil, nil, nil, nil
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        if opts.auto ~= false then ns.Supply.setAuto(true) end
        wow.advance(40)
        wow.state.sent = {}
        return ns
    end
    local function T0() return math.floor(wow.state.now) end
    local function rule(ns) return ns.SupplyRules.byID("green_hills_pages") end
    local function cval(ns, missing, surplus)
        return ns.Supply.encode(rule(ns), { missing = missing or {}, surplus = surplus or {} })
    end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end

    local function visible(o)
        while o do
            if o._shown == false then return false end
            o = o._parent
        end
        return true
    end
    local function pageTexts(root)
        local out = {}
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "FontString" and o._text ~= "" and visible(o) then
                local p = o
                while p and p ~= root do p = p._parent end
                if p == root then out[#out + 1] = o._text end
            end
        end
        return out
    end
    local function has(list, text) for _, t in ipairs(list) do if t == text then return true end end return false end
    -- The y (from the page top, downwards) of a widget anchored TOPLEFT to the page.
    local function topOf(o, page)
        local p = o._points and o._points[1]
        if p and p[2] == page and p[1] == "TOPLEFT" then return -(p[5] or 0) end
    end

    ---------------------------------------------------------------------------
    -- 1. 職工名冊 entry icon
    ---------------------------------------------------------------------------

    test("GF-UI-F 職工名冊 entry: the game's group icon with fallbacks, never a book (冒險指南 is the book)", function()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        local F = ns.Framework
        local list = F.ENTRY_ICON.directory
        ok(#list >= 2, "fallbacks")
        for _, path in ipairs(list) do
            ok(path:find("^Interface\\Icons\\"), "a game icon: " .. path)
            ok(not path:find("Book", 1, true), "not a book: " .. path)
        end
        SlashCmdList.GREENFANGTOOLKIT("roster")
        local b
        for _, x in ipairs(F.navButtons()) do if x:IsShown() and x.entryKey == "directory" then b = x end end
        eq(b and b.iconPath, list[1], "the group icon on the entry")
        ok(b.iconPath ~= F.ENTRY_ICON.handbook[1], "not the handbook's icon")
        ok(b.iconPath ~= F.ENTRY_ICON.logistics[1], "物資調度 keeps its box")
        eq(F.ENTRY_ICON.logistics[1], "Interface\\Icons\\INV_Box_01", "the box")
        -- A client without the first file falls back to the guild tabard.
        wow.reset({ missingFiles = { [list[1]] = true } })
        ns = wow.login(ADDON_DIR)
        SlashCmdList.GREENFANGTOOLKIT("roster")
        for _, x in ipairs(ns.Framework.navButtons()) do if x:IsShown() and x.entryKey == "directory" then b = x end end
        eq(b.iconPath, list[2], "fallback")
    end)

    ---------------------------------------------------------------------------
    -- 2. 人力盤點 above the column header
    ---------------------------------------------------------------------------

    test("GF-UI-F roster: 人力盤點 on its own row between the tool bar and the header, ≤ 980 px, not over the list", function()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        ns.Framework.open("roster")
        local UI = ns.UI
        local page = ns.Framework.panel("roster")
        local c = UI.census
        local toolbarBottom = -UI.TOOLBAR_Y + ns.BUTTON_H
        local headerTop = -UI.HEADER_Y
        for _, r in ipairs({ "t", "h", "d" }) do
            local b = c.roles[r]
            ok(b:IsShown(), "role " .. r .. " shown")
            local y = topOf(b, page)
            ok(y and y >= toolbarBottom and y + b._h <= headerTop, "role " .. r .. " between tool bar and header: " .. tostring(y))
        end
        local uy = topOf(c.unknown, page)
        ok(uy and uy >= toolbarBottom and uy + ns.BUTTON_H <= headerTop, "未知 in the row")
        local oy = topOf(c.online, page)
        ok(oy and oy >= toolbarBottom and oy + 16 <= headerTop, "在線 in the row")
        ok(c.right and c.right <= UI.CENSUS_MAX, "≤ 980 px: " .. tostring(c.right))
        eq(UI.CENSUS_MAX, 980, "the limit")
        ok(-UI.LIST_TOP >= headerTop + UI.HEADER_H, "the list starts under the header")
        -- Nothing of the census on the bottom row any more.
        for _, b in pairs(c.roles) do eq(b._points[1][1], "TOPLEFT", "anchored from the top") end
        -- The role filter still works from the new row.
        wow.click(c.roles.h)
        ok(c.roles.h.selected, "a click on the icon filters")
        wow.click(c.roles.h)
        ok(not c.roles.h.selected, "and clears")
    end)

    ---------------------------------------------------------------------------
    -- 3. 綠皮調貨所: column header, right-aligned quantity, + / -, 收集組, 聯絡 tooltip
    ---------------------------------------------------------------------------

    local function supplyPage(ns) return ns.Framework.panel("supply") end

    test("GF-UI-F 調貨所: column names per tab, the quantity right-aligned, no footer sentence (it is the 聯絡 tooltip)", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Supply.scanNow()
        from(ns, PEER_B, vMsg(ns, A_B, "C1", T0() - 60, cval(ns, nil, { [page(1)] = 2 })))
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local function heads()
            local out = {}
            for _, fs in ipairs(UI.header.cells) do out[#out + 1] = fs._text end
            return table.concat(out, ",")
        end
        -- GF-009-16: 我缺的／我可能有多的 are 範圍 on 調貨看板 (one header): 徵求, 供應, 黑箱 apart.
        eq(heads(), "物品,徵求,供應,黑箱,在線,時效", "調貨看板 (範圍 我缺的)")
        eq(UI.header.cells[2].gfAlign, "RIGHT", "徵求 header right-aligned")
        local r = UI.rows and UI.rows() or nil
        UI.setTab("mine"); eq(heads(), "物品,類型／數量,狀態,時效,,", "我的刊登 (GF-UI-K: the cell reads 徵求 1)")
        UI.setTab("need")
        local texts = pageTexts(supplyPage(ns))
        ok(not has(texts, UI.CONTACT_TIP), "no sentence on the page")
        for _, t in ipairs(texts) do ok(not t:find("媒合", 1, true), "no footer: " .. t) end
        -- The first missing page has a provider: the detail lists 測試乙 with 聯絡.
        local first = UI.state.items[1]
        ok(first and first.mineText:find("^我缺 %d+$"), "my part on the row (GF-009-16)")
        eq(first.cells[1], "1 位", "徵求: me (GF-009-16)"); eq(first.cells[2], "1 位", "供應: the provider")
        eq(first.fresh, "近期", "時效 of the best match")
        local found
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "Button" and o._text == "聯絡" and visible(o) then found = o end
        end
        ok(found, "聯絡 shown")
        eq(found.tip, UI.CONTACT_TIP, "the sentence is the 聯絡 tooltip")
        ok(UI.detailHeader:IsShown(), "the detail has its column header")
        -- GF-009-14 B: the last column shows a manual row's 交易條件 (條件); automatic rows still say 自動.
        ok(has(pageTexts(supplyPage(ns)), "條件"), "條件 column")
        ok(has(pageTexts(supplyPage(ns)), "自動"), "自動 kept in the detail")
    end))

    test("GF-UI-F 調貨所: no + / - in front of a row (GF-UI-K); a click opens the detail on the right", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Supply.scanNow()
        from(ns, PEER_B, vMsg(ns, A_B, "C1", T0() - 60, cval(ns, nil, { [page(1)] = 2, [page(4)] = 1 })))
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local rows = {}
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "Button" and o.expand and o:IsShown() and o._parent == supplyPage(ns) then rows[#rows + 1] = o end
        end
        table.sort(rows, function(a, b) return a.index < b.index end)
        ok(#rows >= 3, "rows: " .. #rows)
        for _, r in ipairs(rows) do ok(not r.expand._shown, "no + / - on row " .. r.index) end
        local other
        for _, r in ipairs(rows) do
            if r.index ~= UI.state.selected and UI.hasDetail(UI.state.items[r.index]) then other = r end
        end
        ok(other, "a second row with a detail")
        wow.click(other)
        eq(UI.state.selected, other.index, "chosen")
        ok(other.sel and UI.detailHeader:IsShown(), "its detail is on the right")
        for _, r in ipairs(rows) do ok(not r.expand._shown, "still no + / -") end
    end))

    test("GF-UI-F 調貨所: 收集組 only on 我缺的 and 我可能有多的; it filters by the rule", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Supply.scanNow()
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local b = ns.SupplyUI.state and nil
        local label, button
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "FontString" and o._text == "收集組" and o._parent == supplyPage(ns) then label = o end
        end
        ok(label, "the 收集組 label")
        local function groupShown() return label._shown end
        local shownOn = {}
        for _, t in ipairs(UI.TABS) do
            UI.setTab(t.key)
            shownOn[#shownOn + 1] = t.key .. "=" .. tostring(groupShown())
        end
        -- GF-009-16: 收集組 is in 調貨看板's filter row (我缺的／我可能有多的 are 範圍 there now).
        eq(table.concat(shownOn, ","), "guild=true,mine=false", "where 收集組 appears")
        UI.setTab("need")
        local opts = UI.groupOptions()
        eq(opts[1].text, "全部", "全部 first")
        eq(opts[2].text, "荊棘谷書頁", "the active rule")
        local all = #UI.state.items
        ok(all > 0, "rows")
        UI.setGroup("green_hills_pages")
        eq(#UI.state.items, all, "the pages belong to the rule")
        -- A manual need outside the rule is filtered out by the rule, shown under 全部.
        local L = ns.SupplyListings
        local l = L.create({ direction = "need", itemID = page(27) + 1000, quantity = 1, days = 14, note = "", category = "other" })
        UI.setGroup(nil)
        local withAll = #UI.state.items
        UI.setGroup("green_hills_pages")
        if l then ok(#UI.state.items < withAll, "the rule leaves the other item out") end
        -- Auto off: no active rule, the selector cannot be pressed (no glow) and falls back to 全部.
        ns.Supply.setAuto(false)
        UI.refresh()
        eq(UI.state.group, nil, "back to 全部")
    end))

    ---------------------------------------------------------------------------
    -- Long names: cut, never over the next column
    ---------------------------------------------------------------------------

    test("GF-UI-F 調貨所: a 12-character item name and member name are cut inside their column, no overlap", done(function()
        local items = {}
        items[page(4)] = { name = LONG_ITEM12, classID = 15, bindType = 0 }
        local ns = login({ quests = { [339] = "active" }, items = items })
        local longMember = "超長名字的綠皮獠牙職工甲-測試伺服器"
        ns.Supply.scanNow()
        -- The roster's 測試乙 renamed to a 12-character name.
        from(ns, PEER_B, vMsg(ns, A_B, "C1", T0() - 60, cval(ns, nil, { [page(4)] = 1 })))
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local C = UI.COL
        local order = { "expand", "icon", "name", "qty", "match", "fresh" }
        for i = 2, #order do
            local a, b = C[order[i - 1]], C[order[i]]
            ok(a.x + a.w <= b.x, order[i - 1] .. " ends before " .. order[i])
        end
        local last = C[order[#order]]
        ok(last.x + last.w <= UI.LIST_W, "inside the row")
        local D = { "name", "what", "on", "fresh", "src" }
        for i = 2, #D do ok(UI.DCOL[D[i - 1]].x + UI.DCOL[D[i - 1]].w <= UI.DCOL[D[i]].x, D[i - 1] .. " before " .. D[i]) end
        ok(UI.DCOL.src.x + UI.DCOL.src.w <= UI.DETAIL_W - 72, "來源 before 聯絡")
        ok(wow.textWidth("自動＋手動", ns.DISABLED_FONT) <= UI.DCOL.src.w, "自動＋手動 fits 來源")
        -- The long item name is cut to its column (the client shows the rest in the tooltip).
        local row
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "Button" and o.expand and o:IsShown() and o.itemID == page(4) then row = o end
        end
        ok(row, "the row of the long item")
        eq(row.name._text, LONG_ITEM12, "full name kept (cut by the client)")
        ok(row.name:IsTruncated(), "12 characters are cut at " .. C.name.w .. " px")
        ok(row.name:GetStringWidth() <= C.name.w, "never wider than its column")
        eq(row.name._wordWrap, false, "one line")
        -- A long member name in the detail: cut inside 成員.
        local r = UI.detailRows and UI.detailRows() or nil
        local nameCell
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "FontString" and o._fixedWidth == UI.DCOL.name.w and visible(o) and o._text ~= "職工" then nameCell = o end
        end
        ok(nameCell, "a member cell")
        nameCell:SetText(ns.shortName(longMember))
        ok(nameCell:GetStringWidth() <= UI.DCOL.name.w and nameCell:IsTruncated(), "member name cut inside 成員")
        -- Every quantity text fits its column: 可能多 200.
        ok(wow.textWidth("可能多 200", ns.FIELD_FONT) <= C.qty.w, "可能多 200 fits 數量")
        ok(wow.textWidth("剩 30 天", ns.LABEL_FONT) <= C.fresh.w, "剩 30 天 fits 時效")
    end))

    ---------------------------------------------------------------------------
    -- The state panel: empty / loading / stale / error
    ---------------------------------------------------------------------------

    test("GF-UI-F 調貨所: the state panel shows 空, 載入中, 資料過期 and 暫時無法讀取", done(function()
        -- Loading: 自動集料 on, the first scan not done yet.
        local ns = login({ quests = { [339] = "active" }, auto = false })
        ns.Supply.db().auto = true -- turned on, nothing scanned yet (as right after /reload)
        ns.Supply.resetSession()
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        eq(UI.pageState(), "loading", "before the first scan")
        ok(UI.statePanel:IsShown() and UI.statePanel.text._text == "載入中", "載入中 shown")
        -- Error: the first scan could not read the bags (nothing older to show).
        G.bagError = true
        ns.Supply.scanNow()
        UI.refresh()
        eq(UI.pageState(), "error", "bags unreadable")
        eq(UI.statePanel.text._text, "暫時無法讀取", "暫時無法讀取")
        G.bagError = false
        -- Empty: a tab with nothing.
        ns.Supply.scanNow()
        -- GF-009-16: 調貨看板 lists my own shortages too; with 自動集料 off nothing is left.
        ns.Supply.db().auto = false
        UI.setTab("guild")
        eq(UI.pageState(), "empty", "nothing to match")
        eq(UI.statePanel.text._text, "目前沒有任何徵求、供應或臨時黑箱物品", "the empty words (GF-UI-S: 臨時黑箱)")
        UI.setTab("mine")
        eq(UI.statePanel.text._text, "還沒有刊登", "我的刊登 empty")
        -- Stale: only expired snapshots.
        UI.setTab("guild")
        local real = ns.Supply.snapshotCounts
        ns.Supply.snapshotCounts = function() return { valid = 0, expired = 2, unsupported = 0 } end
        UI.refresh()
        eq(UI.pageState(), "stale", "only old data")
        eq(UI.statePanel.text._text, "資料過期", "資料過期")
        ns.Supply.snapshotCounts = real
        ns.Supply.db().auto = true
        -- Error: the list itself failed; the page stays up.
        UI.setTab("need")
        local view = ns.Supply.view
        ns.Supply.view = function() error("boom") end
        UI.refresh()
        eq(UI.pageState(), "error", "a failed read")
        ok(UI.statePanel:IsShown(), "panel instead of a broken page")
        ns.Supply.view = view
        ns.Supply.scanNow()
        UI.refresh()
        ok(#UI.state.items > 0 and not UI.statePanel:IsShown(), "rows again, panel hidden")
    end))

    test("GF-UI-F 調貨所: /gftk supply state <kind> previews a state for screenshots; off and closing the page end it", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Supply.scanNow()
        local UI = ns.SupplyUI
        for _, kind in ipairs({ "empty", "loading", "stale", "error" }) do
            SlashCmdList.GREENFANGTOOLKIT("supply state " .. kind)
            ok(ns.Framework.isModuleShown("supply"), "page open")
            eq(UI.pageState(), kind, kind)
            ok(UI.statePanel:IsShown(), kind .. " panel")
            eq(#UI.state.items, 0, "no rows behind it")
        end
        SlashCmdList.GREENFANGTOOLKIT("supply state off")
        ok(#UI.state.items > 0, "real rows back")
        SlashCmdList.GREENFANGTOOLKIT("supply state stale")
        _G[ns.Framework.WINDOW_NAME]:Hide()
        eq(UI.state.preview, nil, "closing ends the preview")
        -- Plain /gftk supply still opens the page.
        SlashCmdList.GREENFANGTOOLKIT("supply")
        ok(ns.Framework.isModuleShown("supply"), "opens")
        ok(UI.pageState() ~= "stale", "no preview")
    end))

    ---------------------------------------------------------------------------
    -- 4. The listing form: outside stays, unsaved changes ask first
    ---------------------------------------------------------------------------

    test("GF-UI-F 刊登 form: unchanged closes at once; changed asks (the game's box) on X, ESC and 取消", done(function()
        local ns = login({ auto = false })
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        -- Unchanged: X closes at once, no box.
        UI.openForm()
        local f = UI.form()
        ok(not UI.formDirty(), "nothing changed")
        f.CloseButton._scripts.OnClick(f.CloseButton)
        ok(not f:IsShown() and not wow.popup(), "X closed it, no question")
        UI.openForm()
        wow.pressEscape()
        ok(not f:IsShown() and not wow.popup(), "ESC closed it, no question")
        -- Changed: the box, the form stays.
        UI.openForm()
        f.note:SetText("想換一點布")
        ok(UI.formDirty(), "a change")
        f.CloseButton._scripts.OnClick(f.CloseButton)
        ok(f:IsShown(), "X keeps it open")
        local p = wow.popup()
        ok(p and p.which == UI.POPUP_DISCARD, "the game's StaticPopup")
        eq(p.text, UI.DISCARD_TEXT, "short question")
        wow.cancelPopup()
        ok(f:IsShown() and f.note:GetText() == "想換一點布", "繼續編輯 keeps the text")
        wow.pressEscape()
        ok(f:IsShown() and wow.popup(), "ESC asks too")
        wow.cancelPopup()
        wow.click(f.cancel)
        ok(f:IsShown() and wow.popup(), "取消 asks too")
        ok(wow.acceptPopup(), "放棄")
        ok(not f:IsShown(), "closed after 放棄")
        -- A click outside never closes it (with or without changes).
        UI.openForm()
        f.qty:SetText("5")
        UI.openPicker()
        -- GF-009-14: the picker is a window (no click-outside layer); a click
        -- outside reaches the game, never the form.
        local blocker = ns.clickBlocker()
        ok(not (blocker and blocker:IsShown()), "no click-outside layer for the picker")
        ok(f:IsShown() and not wow.popup(), "a click outside leaves the form and asks nothing")
        -- The 刊登 button while changes are open keeps them.
        ok(not UI.openForm(), "not replaced")
        eq(f.qty:GetText(), "5", "the typed quantity stays")
        -- Saving closes without a question.
        UI.formFromText("|cff|Hitem:" .. page(2) .. "::::|h[頁]|h|r")
        local l = UI.submitForm()
        ok(l, "listed")
        ok(not f:IsShown() and not wow.popup(), "saved: closed, no question")
    end))
end
