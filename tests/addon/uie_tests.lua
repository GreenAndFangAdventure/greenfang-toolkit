-- GF-UI-E (spec v2.0 §3, §4): the six entries, the sub-tab row, 事務設定 at
-- the bottom, register() with entry / subTitle, and the shared widgets (item
-- row, states, freshness, sub-tabs).

return function(env)
    local test, eq, ok, wow, ADDON_DIR = env.test, env.eq, env.ok, env.wow, env.ADDON_DIR

    local function login()
        wow.reset()
        return wow.login(ADDON_DIR)
    end
    local function click(b) b:GetScript("OnClick")(b) end
    local function shown(list, field)
        local out = {}
        for _, b in ipairs(list) do if b:IsShown() then out[#out + 1] = b[field] end end
        return table.concat(out, ",")
    end
    local function navTexts(ns)
        local out = {}
        for _, b in ipairs(ns.Framework.navButtons()) do if b:IsShown() then out[#out + 1] = b:GetText() end end
        return table.concat(out, ",")
    end
    local function navButton(ns, key)
        for _, b in ipairs(ns.Framework.navButtons()) do if b:IsShown() and b.entryKey == key then return b end end
    end

    test("GF-UI-E six entries in spec order, 4-character names with the game's icons; empty ones hidden", function()
        local ns = login()
        SlashCmdList.GREENFANGTOOLKIT("")
        -- 0.16.0: GF-009 調貨所 fills 物資調度; an entry with no page stays hidden (spec §3).
        eq(navTexts(ns), "職工檔案,職工名冊,委託業務,物資調度,冒險業務,冒險指南", "entries")
        for _, b in ipairs(ns.Framework.navButtons()) do
            if b:IsShown() then
                ok(b.iconPath and b.iconPath:find("^Interface\\Icons\\"), "game icon on " .. b:GetText())
                eq(b._h, 30, "30 px")
            end
        end
        local s = ns.Framework.settingsButton()
        ok(s and s:IsShown(), "事務設定 at the bottom")
        eq(s:GetText(), "事務設定", "its name")
        eq(ns.Framework.NAMES, ns.NAMES, "one names table")
        -- The page keeps its 680 px under the sub-tab row.
        eq(_G[ns.Framework.WINDOW_NAME]._h, ns.Framework.PANEL_HEIGHT + ns.Framework.SUBTAB_H, "window height")
        eq(ns.Framework.panel("roster")._h, ns.Framework.PANEL_HEIGHT, "page height unchanged")
    end)

    test("GF-UI-E 委託業務 holds 配方 and 訂單 as sub-tabs; the entry reopens the last one", function()
        local ns = login()
        local F = ns.Framework
        SlashCmdList.GREENFANGTOOLKIT("roster")
        eq(F.currentEntry(), "directory", "roster is 職工名冊")
        local craft = navButton(ns, "crafting")
        click(craft)
        eq(F.current(), "recipes", "first page of 委託業務")
        local tabs = {}
        for _, b in ipairs(F.subTabButtons()) do if b:IsShown() then tabs[#tabs + 1] = b end end
        eq(#tabs, 2, "two sub-tabs")
        eq(tabs[1]:GetText() .. "," .. tabs[2]:GetText(), "工匠配方,製作委託", "sub-tab names")
        ok(tabs[1].gfSelected and not tabs[2].gfSelected, "the open page is chosen")
        eq(tabs[1].gfEnabled, false, "the chosen tab cannot be pressed (no glow)")
        click(tabs[2])
        eq(F.current(), "orders", "sub-tab switches the page")
        ok(F.panel("orders"):IsShown() and not F.panel("recipes"):IsShown(), "one page at a time")
        ok(navButton(ns, "crafting").gfSelected, "委託業務 stays chosen")
        click(navButton(ns, "directory"))
        eq(F.current(), "roster", "back to the roster")
        click(navButton(ns, "crafting"))
        eq(F.current(), "orders", "委託業務 reopens 製作委託")
        -- Old ways in still work.
        SlashCmdList.GREENFANGTOOLKIT("recipes")
        eq(F.current(), "recipes", "/gftk recipes")
        ok(F.isShown(), "window open")
        eq(_G[F.WINDOW_NAME].TitleText:GetText(), "綠皮冒險工具箱｜委託業務", "GF-UI-K: the entry name")
    end)

    test("GF-UI-E single-page entries show their one tab (GF-FIX-B); 事務設定 opens 同步與診斷", function()
        local ns = login()
        local F = ns.Framework
        SlashCmdList.GREENFANGTOOLKIT("adventure")
        local tabs = {}
        for _, b in ipairs(F.subTabButtons()) do if b:IsShown() then tabs[#tabs + 1] = b end end
        eq(#tabs, 1, "GF-FIX-B (owner): one page, its one tab")
        eq(tabs[1]:GetText(), "業務大廳", "the page's name")
        ok(tabs[1].gfSelected, "chosen (gold), like the open tab of a multi-page entry")
        eq(_G[F.WINDOW_NAME].TitleText:GetText(), "綠皮冒險工具箱｜冒險業務", "the title names the entry")
        local s = F.settingsButton()
        ok(not ns.Diag.isShown(), "closed")
        click(s)
        ok(ns.Diag.isShown(), "事務設定 opens 同步與診斷")
        click(s)
        ok(not ns.Diag.isShown(), "and closes it")
        eq(F.get("settings"), nil, "still no settings module (D-015)")
    end)

    test("GF-UI-E register(): entry / subTitle / subOrder, unknown entries and old-style pages", function()
        wow.reset()
        local ns = wow.loadAddon(ADDON_DIR)
        local F = ns.Framework
        -- A first-wave page (GF-009) with the new fields.
        F.register({ id = "supply", title = "綠皮調貨所", order = 30, entry = "logistics", subTitle = "調貨所",
            create = function() end })
        -- Same entry, no subTitle: F.NAMES.page, then short / title.
        F.register({ id = "mystuff", title = "我的物資", order = 31, entry = "logistics", subOrder = 1, create = function() end })
        -- A page by id only (GF-010 profile): its default entry.
        F.register({ id = "profile", title = "職工檔案", order = 9, create = function() end })
        -- A wrong entry string and an old page without entry: an entry of their own.
        F.register({ id = "odd", title = "奇怪", order = 80, entry = "nowhere", create = function() end })
        F.register({ id = "legacy", title = "舊頁", short = "舊頁", order = 90, create = function() end })
        wow.fire("PLAYER_LOGIN"); wow.advance(10)
        SlashCmdList.GREENFANGTOOLKIT("supply")
        eq(F.current(), "supply", "/gftk supply opens it")
        eq(F.currentEntry(), "logistics", "物資調度")
        eq(navTexts(ns), "職工檔案,職工名冊,委託業務,物資調度,冒險業務,冒險指南,奇怪,舊頁", "物資調度 shows up; others after the six")
        local pages = {}
        for _, d in ipairs(F.pagesOf("logistics")) do pages[#pages + 1] = F.pageTitle(d) end
        eq(table.concat(pages, ","), "我的物資,綠皮調貨所,臨時黑箱", "subOrder first; the real supply page (registered first) keeps F.NAMES.page (GF-UI-K: 綠皮調貨所)") -- GF-012 adds 臨時黑箱 (was 公會黑庫)
        pages = {}
        for _, d in ipairs(F.pagesOf("profile")) do pages[#pages + 1] = d.id end
        eq(table.concat(pages, ","), "profile,character", "profile and character share 職工檔案")
        eq(F.entryOf(F.get("odd")), "page:odd", "unknown entry: its own")
        eq(F.entryOf(F.get("legacy")), "page:legacy", "no entry, unknown id: its own")
        SlashCmdList.GREENFANGTOOLKIT("legacy")
        eq(F.current(), "legacy", "still opens")
        ok(navButton(ns, "page:legacy").gfSelected, "and is chosen")
    end)

    ---------------------------------------------------------------------------
    -- Widgets
    ---------------------------------------------------------------------------

    test("GF-UI-E item row: icon + name + count; loading placeholder until GET_ITEM_INFO_RECEIVED", function()
        local ns = login()
        local W = ns.Widgets
        local known = {}
        local oldInfo, oldItem = _G.GetItemInfo, _G.C_Item
        local requested = 0
        _G.GetItemInfo = function(id)
            local k = known[id]
            if not k then return nil end
            return k.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. k.name .. "]|h|r", 1, nil, nil, nil, nil, nil, nil, k.icon
        end
        _G.C_Item = { RequestLoadItemDataByID = function() requested = requested + 1 end }
        local okRun, err = pcall(function()
            local row = W.itemRow(UIParent, 520)
            row.set(2589, "缺 1", { sub = "可能提供：2 位" })
            eq(row.loading, true, "not cached")
            eq(row.name:GetText(), "物品資料載入中", "loading text, no ID, no guess")
            ok(not tostring(row.name:GetText()):find("2589"), "the ID is not shown")
            eq(row.placeholder, true, "placeholder icon")
            eq(row.iconPath, "Interface\\Icons\\INV_Misc_QuestionMark", "the game's question mark")
            eq(row.icon._w, W.ITEM_ICON, "icon 36 px")
            ok(W.ITEM_ICON >= 32 and W.ITEM_ICON <= 40, "32-40 px")
            eq(requested, 1, "asked the client once")
            eq(W.itemsWaiting(), 1, "waits for the event")
            eq(row.count:GetText(), "缺 1", "count")
            known[2589] = { name = "亞麻布", icon = "Interface\\Icons\\INV_Fabric_Linen_01" }
            wow.fire("GET_ITEM_INFO_RECEIVED", 2589, true)
            eq(row.loading, false, "loaded")
            eq(row.name:GetText(), "亞麻布", "real name")
            eq(row.iconPath, "Interface\\Icons\\INV_Fabric_Linen_01", "real icon")
            eq(W.itemsWaiting(), 0, "nothing waits")
            -- Tooltip: the item link.
            row:GetScript("OnEnter")(row)
            eq(GameTooltip:GetOwner(), row, "tooltip on the row")
            row:GetScript("OnLeave")(row)
            -- No OnClick: it never lights up (GF-UI-D2).
            eq(ns.Theme.hoverable(row), false, "info only")
            row:SetScript("OnClick", function() end)
            eq(ns.Theme.hoverable(row), true, "clickable lights up")
            -- The name is cut before the right-hand buttons.
            local before = row.nameWidth
            row.setRightWidth(120)
            ok(row.nameWidth < before, "name narrower for the buttons")
            row.set(nil)
            ok(not row:IsShown(), "nil hides it")
        end)
        _G.GetItemInfo, _G.C_Item = oldInfo, oldItem
        if not okRun then error(err, 0) end
    end)

    test("GF-UI-E states: icon and words for empty / loading / unknown / stale / error; freshness words", function()
        local ns = login()
        local W = ns.Widgets
        local st = W.statePanel(UIParent, 600, 120)
        ok(not st:IsShown(), "hidden at first")
        for _, kind in ipairs(W.STATE_KINDS) do
            st.set(kind)
            ok(st:IsShown(), kind .. " shown")
            ok(st.iconPath, kind .. " has an icon")
            eq(st.text:GetText(), W.TEXT[kind], kind .. " words")
        end
        st.set("empty", "目前沒有可配對的公會物資", "請稍後再看")
        eq(st.text:GetText(), "目前沒有可配對的公會物資", "own words")
        ok(st.detail:IsShown(), "detail line")
        st.set(nil)
        ok(not st:IsShown(), "nil hides it")
        local now = 1763380000
        eq(select(2, W.freshness(now - 60, now)), "近期", "recent")
        eq(select(2, W.freshness(now - 86400, now)), "稍早", "earlier")
        eq(select(2, W.freshness(now - 5 * 86400, now)), "過期", "stale")
        eq(select(2, W.freshness(nil, now)), "未知", "unknown")
        eq(select(2, W.freshness(now + 86400, now)), "未知", "future time: unknown")
        eq(select(2, W.freshness(now - 3600, now, { recent = 600 })), "稍早", "own thresholds")
    end)

    test("GF-UI-E sub-tabs inside a page: chosen is gold and not pressable; hide and disable re-lay out", function()
        local ns = login()
        local W = ns.Widgets
        local picked
        local tabs = W.subTabs(UIParent, { { key = "need", text = "我缺的" }, { key = "spare", text = "我可能有多的" },
            { key = "post", text = "刊登" } }, 20, -40, function(k) picked = k end)
        tabs.select("need")
        local need, spare, post = tabs.button("need"), tabs.button("spare"), tabs.button("post")
        ok(need.gfSelected and not spare.gfSelected, "chosen")
        eq(need.gfEnabled, false, "chosen not pressable")
        eq(ns.Theme.hoverable(need), false, "chosen does not light up")
        click(spare)
        eq(picked, "spare", "onSelect")
        ok(spare.gfSelected and not need.gfSelected, "moved")
        tabs.setEnabled("post", false)
        eq(ns.Theme.hoverable(post), false, "disabled does not light up")
        local x0 = post._points and post._points[1] and post._points[1][4]
        tabs.setShown("spare", false)
        ok(not spare:IsShown(), "hidden")
        local x1 = post._points and post._points[1] and post._points[1][4]
        if x0 and x1 then ok(x1 < x0, "no gap left") end
        eq(shown(tabs.buttons, "key"), "need,post", "shown tabs")
    end)
end
