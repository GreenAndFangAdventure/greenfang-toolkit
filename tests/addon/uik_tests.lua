-- GF-UI-K: interface tidy-up (owner, 0.16.6): the personnel file (配方 N 個 off
-- the bar, 已取消 after the live ones, 未設定 chosen, no lone tab, the race
-- head), 我的刊登 (刊登 without ＋ at the list's edge, 啟用：, 類型／數量,
-- ended listings last and faded, no + / -, the terms aligned), one window
-- title per entry, the same first view in both quest pickers.
-- Offline only (a small fake game below); not checked in the Forever client.
-- Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function title() return _G.GreenFangToolkit_MainWindow.TitleText:GetText() end
    local function shownTabs(F)
        local n = 0
        for _, b in ipairs(F.subTabButtons()) do if b:IsShown() then n = n + 1 end end
        return n
    end

    ---------------------------------------------------------------------------
    -- A. 職工檔案
    ---------------------------------------------------------------------------

    test("GF-UI-K A1 「配方 N 個」 right of the bar, on its middle line, inside the row", function()
        local ns = login()
        local Ch = ns.Character
        ns.Data.ownProfessionsDetailed = function()
            return { { name = "裁縫", rank = 120, max = 150, skillLine = 197 } }
        end
        SlashCmdList.GREENFANGTOOLKIT("character")
        Ch.refresh()
        local row = Ch.profRows[1]
        ok(row and row:IsShown(), "a profession row")
        local pt = row.recipes._points[1]
        eq(pt[1] .. ">" .. pt[3], "LEFT>RIGHT", "anchored right of something")
        eq(pt[2], row.bar, "right of the bar")
        eq(pt[4], Ch.RECIPE_GAP, "a gap after the bar"); eq(pt[5], 0, "the bar's middle line")
        ok(46 + row.bar._w + Ch.RECIPE_GAP + Ch.RECIPE_W <= row._w, "inside the 560 px row")
    end)

    test("GF-UI-K A2 我的業務: 已取消 / 已成交 read as states; ended ones after the live ones", function()
        local ns = login()
        local P = ns.Profile
        eq(P.ORDER_STATE.cancel, "已取消", "取消 → 已取消"); eq(P.ORDER_STATE.deal, "已成交", "成交 → 已成交")
        eq(ns.OrdersUI.STATE_NAME.cancel, "已取消", "the order page says the same")
        eq(ns.Adventure.STATE_NAME.cancel, "已取消", "adventures too"); eq(ns.Adventure.STATE_NAME.ended, "已過期", "已過期")
        local me = ns.Share.selfAuthor()
        ns.Orders.rowsFor = function()
            return {}, { { view = { id = "o1", customer = me, state = "cancel", created = 300 } },
                { view = { id = "o2", customer = me, state = "waiting", created = 100 } } }
        end
        ns.Adventure.all = function()
            return { a1 = { id = "a1", leader = me, state = "cancel", created = 400 },
                a2 = { id = "a2", leader = me, state = "open", created = 200 } }
        end
        local items = P.myBusiness()
        eq(#items, 4, "four records")
        eq(items[1].id .. "," .. items[2].id, "a2,o2", "the live ones first (newest first)")
        ok(items[3].closed and items[4].closed, "then the ended ones")
        eq(items[3].stateName, "已取消", "a cancelled adventure: 已取消 (closed by its state)")
    end)

    test("GF-UI-K A3 主職責 未設定 is the chosen look when no main role is set", function()
        local ns = login()
        SlashCmdList.GREENFANGTOOLKIT("character")
        local c = ns.ProfileUI.controls
        ns.Profile.setMain(nil); ns.ProfileUI.refresh()
        ok(c.unset.gfSelected, "未設定 chosen (gold)")
        ns.Profile.setMain("t"); ns.ProfileUI.refresh()
        ok(not c.unset.gfSelected, "not chosen once a role is set")
        eq(c.unset.gfEnabled, true, "and it can be pressed")
    end)

    test("GF-UI-K A4 職工檔案 has one page: its one tab (GF-FIX-B, owner); the title names the entry", function()
        local ns = login()
        local F = ns.Framework
        SlashCmdList.GREENFANGTOOLKIT("character")
        eq(F.current(), "character", "the personnel file")
        eq(shownTabs(F), 1, "GF-FIX-B: the tab row stays for one page")
        eq(title(), "綠皮冒險工具箱｜職工檔案", "title")
    end)

    test("GF-UI-K A5 the race head: orc for a man, 天裔精靈 for a woman, else the class icon", function()
        local ns = login()
        local I, Ch = ns.Icons, ns.Character
        local have = {}
        local oldCT, oldSex, oldCI = rawget(_G, "C_Texture"), rawget(_G, "UnitSex"), rawget(_G, "C_CreatureInfo")
        local sex = 2
        local okRun, err = pcall(function()
            C_Texture = { GetAtlasInfo = function(n) return have[n] and { width = 128 } or nil end }
            UnitSex = function(unit) if unit == "player" then return sex end end
            C_CreatureInfo = { GetRaceInfo = function(id)
                if id == 96 then return { raceName = "塑風者天裔精靈", clientFileString = "TestSkyElf" } end
                return nil
            end }
            SlashCmdList.GREENFANGTOOLKIT("character")
            local tex = Ch.portraitTexture
            tex.SetAtlas = function(self, n) self._atlas = n; return true end
            -- No atlas in the client: the class icon stays.
            Ch.refresh()
            eq(Ch.portrait, "class", "nothing to show: class icon")
            -- A man: the orc head first.
            have["raceicon128-orc-male"], have["raceicon128-goblin-male"] = true, true
            Ch.refresh()
            eq(Ch.portrait, "atlas", "atlas"); eq(tex._atlas, "raceicon128-orc-male", "the orc head")
            -- A woman: the 天裔精靈 head, its file name from the client (raceID 96).
            sex = 3
            Ch.refresh()
            eq(Ch.portrait, "class", "the elf atlas is missing: class icon")
            have["raceicon128-testskyelf-female"] = true
            Ch.refresh()
            eq(tex._atlas, "raceicon128-testskyelf-female", "the 天裔精靈 head")
            eq(I.portraitAtlases(3)[1], "raceicon128-testskyelf-female", "built from clientFileString")
            eq(#I.portraitAtlases(nil), 0, "unknown sex: nothing (class icon)")
            -- /gftk probe lists them.
            local pr = ns.Probe.portraits()
            eq(pr.sex, "3", "sex"); eq(pr.race96, "testskyelf", "race file"); eq(pr.race95, "nil", "95 unknown here")
            eq(pr["raceicon128-orc-male"], "yes", "orc yes"); eq(pr["raceicon-orc-male"], "no", "small orc no")
        end)
        C_Texture, UnitSex, C_CreatureInfo = oldCT, oldSex, oldCI
        if not okRun then error(err, 0) end
    end)

    ---------------------------------------------------------------------------
    -- C. One window title per entry (spec v2.0 §3)
    ---------------------------------------------------------------------------

    test("GF-UI-K C1 the window title is 「綠皮冒險工具箱｜<主入口名>」 on every page", function()
        local ns = login()
        local F = ns.Framework
        local want = { roster = "職工名冊", recipes = "委託業務", orders = "委託業務", adventure = "冒險業務",
            character = "職工檔案", supply = "物資調度", bank = "物資調度" }
        for id, entry in pairs(want) do
            if F.get(id) and F.select(id) then
                ok(title():find("^綠皮冒險工具箱｜" .. entry), id .. ": " .. title())
            end
        end
        F.select("supply")
        eq(title(), "綠皮冒險工具箱｜物資調度", "調貨所: no third name")
        eq(F.pageTitle(F.get("supply")), "綠皮調貨所", "the sub-tab carries the owner's name 綠皮調貨所")
        eq(F.pageTitle(F.get("bank")), "臨時黑箱", "臨時黑箱 kept")
        eq(shownTabs(F), 2, "物資調度 has two pages: two tabs")
    end)

    ---------------------------------------------------------------------------
    -- D3. Both quest pickers open on the zones
    ---------------------------------------------------------------------------

    test("GF-UI-K D3 adventure and worker quest pickers both open on the zone list; the worker one adds 全區 / 日誌全部", function()
        local ns = login()
        local U = ns.AdventureUI
        local rows = { { isHeader = true, title = "貧瘠之地" }, { questID = 3001, title = "測試任務 甲", level = 20 },
            { questID = 3002, title = "測試任務 乙", level = 20 }, { isHeader = true, title = "灰谷" },
            { questID = 4001, title = "測試任務 丙", level = 22 } }
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 0 end, GetInfo = function(i) return rows[i] end }
        local okRun, err = pcall(function()
            local function zones(qp)
                local out = {}
                for _, z in ipairs(qp.zoneRows) do if z:IsShown() then out[#out + 1] = z.zone end end
                table.sort(out)
                return table.concat(out, ",")
            end
            local function questRows(qp)
                local n = 0
                for _, r in ipairs(qp.rows) do if r:IsShown() then n = n + 1 end end
                return n
            end
            U.openTicket()
            local qp = U.pickQuests(UIParent)
            local adventureZones = zones(qp)
            ok(adventureZones:find("灰谷", 1, true) and adventureZones:find("貧瘠之地", 1, true), "adventure ticket: zones first: " .. adventureZones)
            eq(questRows(qp), 0, "no quests yet")
            ok(not qp.all:IsShown(), "no 日誌全部 on the adventure ticket")
            qp:Hide()
            U.openWorker()
            local wq = U.pickWorkerQuests(UIParent)
            eq(zones(wq), adventureZones, "worker ticket: the same zones first"); eq(questRows(wq), 0, "no quests yet")
            ok(wq.all:IsShown(), "日誌全部 on top")
            local checks = {}
            for _, b in ipairs(wq.wholes) do if b:IsShown() then checks[b.zone] = b end end
            ok(checks["貧瘠之地"] and checks["灰谷"], "全區 on every zone row")
            wow.click(checks["灰谷"])
            local wd = U.workerDraft and U.workerDraft() or nil
            ok(checks["灰谷"].selected, "全區 灰谷 on")
            if wd then eq(wd.zones and wd.zones[1], "灰谷", "saved in the draft") end
            for _, z in ipairs(wq.zoneRows) do if z:IsShown() and z.zone == "貧瘠之地" then wow.click(z) end end
            eq(questRows(wq), 2, "the zone's quests"); ok(wq.back:IsShown(), "區域 goes back")
            wow.click(wq.back)
            eq(questRows(wq), 0, "back on the zones")
        end)
        C_QuestLog = nil
        if not okRun then error(err, 0) end
    end)

    ---------------------------------------------------------------------------
    -- B. 調貨所「我的刊登」 (the fake game of uii_tests.lua, cut down)
    ---------------------------------------------------------------------------

    local PATTERN, CLOTH = 9201, 9203
    local function installGame()
        local items = { [PATTERN] = { name = "圖樣：測試長袍", classID = 9, sub = 2 }, [CLOTH] = { name = "測試布", classID = 7, sub = 5 } }
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
        GetItemInfo = function(id)
            local it = items[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1, "", "", 20, "", 134939,
                0, it.classID, it.sub or 0, 0
        end
        C_Item = {
            GetItemIconByID = function(id) return items[id] and 134939 or nil end,
            GetItemNameByID = function(id) return items[id] and items[id].name or nil end,
            RequestLoadItemDataByID = function() end,
            DoesItemExistByID = function() return true end,
            IsItemDataCachedByID = function(id) return items[id] ~= nil end,
        }
    end
    local function removeGame() C_QuestLog, C_Container, GetItemInfo, C_Item = nil, nil, nil, nil end
    local function supplyLogin()
        wow.reset({})
        installGame()
        local ns = wow.loadAddon(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN"); wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(70)
        return ns
    end
    local function withGame(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    test("GF-UI-K B1-B6 我的刊登: 刊登 without ＋ at the list's edge, 啟用：, 類型／數量, ended last and faded, no + / -, terms aligned", withGame(function()
        local ns = supplyLogin()
        local L = ns.SupplyListings
        local first = L.create({ direction = "need", itemID = PATTERN, quantity = 1, days = 14, note = "" })
        local second = L.create({ direction = "offer", itemID = CLOTH, quantity = 3, days = 14, note = "" })
        ok(first and second, "two listings")
        L.finish(first.id, "closed")
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.setTab("mine")
        -- B1
        eq(UI.postButton._text, "刊登", "no ＋")
        local pt = UI.postButton._points[1]
        eq(pt[4] .. "," .. pt[5], UI.LIST_X .. "," .. UI.TOOL_Y, "at the list's left edge, right over the header")
        ok(-pt[5] + UI.postButton._h <= -UI.HEAD_Y, "above the column header")
        -- B2
        -- GF-FIX-F: 「啟用：」 + two boxes became two switch rows (開／關 in words).
        eq(UI.autoBox.label._text, "自動集料", "自動集料"); eq(UI.manualBox.label._text, "手動刊登", "手動刊登")
        ok(UI.SWITCH_X.name + ns.labelWidth("自動集料") <= UI.SWITCH_X.button, "the name ends before its switch")
        -- B3
        eq(UI.header.cells[2]._text, "類型／數量", "the column says what the cell shows")
        -- B4: the live one first, the ended one after and faded.
        eq(#UI.state.items, 2, "two rows")
        eq(UI.state.items[1].listing.id, second.id, "live first"); eq(UI.state.items[2].listing.id, first.id, "ended after")
        local rows = {}
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "Button" and o.expand and o:IsShown() and o._parent == ns.Framework.panel("supply") then rows[o.index] = o end
        end
        ok(rows[1] and rows[2], "both rows drawn")
        ok((rows[1]._alpha or 1) == 1, "live: full"); eq(rows[2]._alpha, UI.ENDED_ALPHA, "ended: faded")
        -- B5: no + / - on any row.
        ok(not rows[1].expand._shown and not rows[2].expand._shown, "no + / -")
        -- B6: 交易條件 where the hidden header would be; the value right after its label.
        UI.select(1)
        local r
        for _, o in ipairs(wow.allObjects()) do
            if o.gfListing == true and o:IsShown() and o.name and o.name._text == "交易條件" then r = o end
        end
        ok(r, "交易條件 line")
        eq(r._points[1][5], UI.DETAIL_HEAD_Y, "in the header's place")
        eq(r.what._points[1][4], UI.LISTING_VALUE_X, "the value right after the label")
        ok(4 + ns.labelWidth("交易條件") <= UI.LISTING_VALUE_X, "no overlap with the label")
        -- D: the form's buttons in the order of every other dialog: 取消 left, 刊登 right.
        UI.openForm()
        local f = _G[UI.FORM_NAME]
        ok(f and f:IsShown(), "form open")
        ok(f.save._points[1][4] > f.cancel._points[1][4], "刊登 right of 取消")
        f:Hide()
    end))
end
