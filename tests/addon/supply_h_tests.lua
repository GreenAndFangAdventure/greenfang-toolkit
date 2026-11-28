-- GF-UI-H: the owner's 0.16.0 report on 綠皮調貨所 — find items that are not in
-- my bags (類型 / 子類 from classID / subclassID, a search), untradeable items
-- blocked for 徵求 and 供應 and never offered, 刪除 for my ended listings, the
-- page's top rows without overlaps, and money always with the coin icons.
-- Offline only (a small fake game below); not checked in the Forever client.
-- Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A_B = "0000-0000000B"
    local PEER_B = "測試乙-測試伺服器"
    -- Items: a recipe (9/2 裁縫), cloth (7/5 布料), a potion (0/1 藥水), a BoP ring
    -- (4/0, bindType 1), a quest item (12/0, bindType 4), an AH-only herb (7/9).
    local RECIPE, CLOTH, POTION, RING, QITEM, HERB, NOCACHE = 9101, 9102, 9103, 9104, 9105, 9106, 9107
    local TYPE = { [0] = "消耗品", [4] = "護甲", [7] = "商品", [9] = "配方", [12] = "任務", [15] = "雜項" }
    local SUB = { ["9.2"] = "裁縫", ["7.5"] = "布料", ["0.1"] = "藥水", ["4.0"] = "其他", ["12.0"] = "任務", ["7.9"] = "草藥" }
    local function baseItems()
        return {
            [RECIPE] = { name = "圖樣：測試長袍", classID = 9, sub = 2 },
            [CLOTH] = { name = "測試布", classID = 7, sub = 5 },
            [POTION] = { name = "測試藥水", classID = 0, sub = 1 },
            [RING] = { name = "測試指環", classID = 4, sub = 0, bindType = 1 },
            [QITEM] = { name = "測試信件", classID = 12, sub = 0, bindType = 4 },
            [HERB] = { name = "測試草", classID = 7, sub = 9 },
        }
    end

    local G
    local function installGame(opts)
        G = { bag = opts.bag or {}, items = opts.items or baseItems(), asked = {} }
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bag[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = false, iconFileID = 134939 }
            end,
        }
        GetItemInfo = function(id)
            local it = G.items[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1,
                TYPE[it.classID] or "", SUB[it.classID .. "." .. (it.sub or 0)] or "", 20, "", 134939,
                0, it.classID, it.sub or 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.items[id] and 134939 or nil end,
            GetItemNameByID = function(id) return G.items[id] and G.items[id].name or nil end,
            RequestLoadItemDataByID = function(id) G.asked[id] = true end,
            IsItemDataCachedByID = function(id) return G.items[id] ~= nil end, -- GF-009-13
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
        -- GF-009-12: these tests are about the finder without the item catalog
        -- (tests/addon/catalog_tests.lua has the catalog).
        ns.SupplyCatalogData = nil
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(70)
        wow.state.sent = {}
        return ns
    end
    local function T0() return math.floor(wow.state.now) end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function ids(list)
        local out = {}
        for _, e in ipairs(list) do out[#out + 1] = tostring(e.itemID) end
        return table.concat(out, ",")
    end
    local function has(list, id) for _, e in ipairs(list) do if e.itemID == id then return true end end return false end
    local function lform(over)
        local f = { direction = "need", itemID = RECIPE, quantity = 1, days = 14, note = "" }
        for k, v in pairs(over or {}) do f[k] = v end
        return f
    end
    -- Known items in the price store (an AH scan) and the recipe cache.
    local function seedPrices(ns)
        local P = ns.Prices
        local p = P.db()
        p.ah["測試伺服器-horde"] = { [HERB] = "x", [NOCACHE] = "x", [RING] = "x" }
        p.reagents[12345] = P.encodeReagents({ output = POTION, yield = 1, list = { { id = HERB, n = 2 } } })
    end

    ---------------------------------------------------------------------------
    -- 1. The item finder
    ---------------------------------------------------------------------------

    test("GF-UI-H finder: 背包 = unbound bag items; 全部 adds listings, rules, recipes and the price store; never untradeable ones", done(function()
        local ns = login({ bag = { { CLOTH, 5 }, { RING, 1 }, { POTION, 2, true }, { QITEM, 1 } } })
        local L = ns.SupplyListings
        seedPrices(ns)
        -- 背包: only the cloth (the ring is 拾取綁定, the potion stack bound, the letter a quest item).
        eq(ids(L.catalog({ source = "bag" })), tostring(CLOTH), "bag source")
        eq(L.catalog({ source = "bag" })[1].count, 5, "bag count")
        -- A guild listing of the recipe (B offers it).
        local t = T0() - 60
        from(ns, PEER_B, vMsg(ns, A_B, "L", t, L.encode({ { id = 1, direction = "offer", category = "recipe", itemID = RECIPE,
            quantity = 1, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" } })))
        local all = L.catalog({ source = "all" })
        ok(has(all, RECIPE), "from a guild listing")
        ok(has(all, CLOTH), "from the bags")
        ok(has(all, POTION) and has(all, HERB), "from the recipe cache (product and reagent)")
        ok(has(all, ns.SupplyRules.list[1].order[1]) == false, "rule items without client data are left out, not guessed")
        ok(not has(all, RING) and not has(all, QITEM), "拾取綁定 and quest items never listed")
        ok(not has(all, NOCACHE), "an unknown ID from the price store is not shown")
        ok(not G.asked[NOCACHE], "and the price store never asks the server")
        -- GF-009-13 (was: the small sources ask): 全部 never asks the server about a cold item.
        ok(not G.asked[ns.SupplyRules.list[1].order[1]], "全部 never asks for missing item data")
        -- Sorted by type: 消耗品 (0) before 配方 (9).
        local pos = {}
        for i, e in ipairs(all) do pos[e.itemID] = i end
        ok(pos[POTION] < pos[CLOTH] and pos[CLOTH] < pos[RECIPE], "by classID")
    end))

    test("GF-UI-H finder: search by name, ItemID or link; 類型 and 子類 from classID / subclassID with the client's names", done(function()
        local ns = login({ bag = { { CLOTH, 5 } } })
        local L = ns.SupplyListings
        seedPrices(ns)
        eq(ids(L.catalog({ source = "all", text = "藥水" })), tostring(POTION), "name part")
        eq(ids(L.catalog({ source = "all", text = tostring(RECIPE) })), tostring(RECIPE), "an ItemID finds an item from nowhere else")
        eq(ids(L.catalog({ source = "all", text = "|cff|Hitem:" .. RECIPE .. "::|h[x]|h|r" })), tostring(RECIPE), "a link")
        eq(#L.catalog({ source = "all", text = tostring(RING) }), 0, "an untradeable ID is still refused")
        local base = L.catalog({ source = "all" })
        local classes = {}
        for _, c in ipairs(L.catalogClasses(base)) do classes[#classes + 1] = c.value .. "=" .. c.text end
        eq(table.concat(classes, ","), "0=消耗品,7=商品", "classes present, the client's names")
        local subs = {}
        for _, c in ipairs(L.catalogSubclasses(base, 7)) do subs[#subs + 1] = c.value .. "=" .. c.text end
        eq(table.concat(subs, ","), "5=布料,9=草藥", "subclasses of 商品")
        eq(ids(L.catalog({ source = "all", class = 7, subclass = 9 })), tostring(HERB), "filtered")
        eq(L.typeText(L.itemInfo(RECIPE)), "配方｜裁縫", "type line")
        -- Without client names: the toolkit's own class names.
        eq(L.className(9), "配方", "fallback class name")
    end))

    test("GF-UI-H form: 找物品 lists items not in my bags; picking one fills the form; 類型 is read, never chosen", done(function()
        local ns = login({ bag = { { CLOTH, 5 } } })
        seedPrices(ns)
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        ok(UI.openForm(), "form")
        local f = UI.form()
        ok(f.find and f.find:IsShown(), "找物品 button")
        ok(f.cats == nil, "no category choice any more")
        wow.click(f.find)
        local p = UI.picker()
        ok(p:IsShown(), "finder open")
        eq(p.title._text, "找物品", "its name")
        ok(has(UI.pickState.items, POTION), "an item not in the bags")
        -- Filters: 類型 商品, then 子類 草藥.
        UI.pickClass(7)
        for _, e in ipairs(UI.pickState.items) do eq(e.info.classID, 7, "only 商品") end
        ok(p.sub._enabled ~= false, "子類 usable once a type is chosen")
        UI.pickSubclass(9)
        eq(ids(UI.pickState.items), tostring(HERB), "草藥")
        -- The search keeps the type filter while it still has items.
        UI.pickSearch("草")
        eq(UI.pickState.class, 7, "type kept")
        -- Choose the herb: the form has it, 類型 shown, category from the class.
        ok(UI.pickChoose(1), "chosen")
        ok(not p:IsShown(), "finder closed")
        eq(UI.formState.itemID, HERB, "in the form")
        eq(f.typeText._text, "商品｜草藥", "類型 line")
        eq(UI.formState.category, "material", "category from classID 7")
        local l = UI.submitForm()
        ok(l and l.direction == "need" and l.itemID == HERB and l.category == "material", "徵求 of an item I do not have")
        -- 從背包選 opens the same window on 背包.
        UI.openForm()
        wow.click(UI.form().pick)
        eq(UI.pickState.source, "bag", "bag source")
        eq(ids(UI.pickState.items), tostring(CLOTH), "bag items only")
    end))

    ---------------------------------------------------------------------------
    -- 2. Untradeable items: both directions, the list and the received side
    ---------------------------------------------------------------------------

    test("GF-UI-H 拾取綁定: refused for 徵求 and 供應 (also a quest item), never in the finder, others' listings hidden", done(function()
        local ns = login({ bag = { { RING, 1 } } })
        local L = ns.SupplyListings
        for _, dir in ipairs({ "need", "offer" }) do
            for _, id in ipairs({ RING, QITEM }) do
                local l, why = L.create(lform({ direction = dir, itemID = id }))
                ok(not l and why:find("綁定", 1, true), dir .. " " .. id .. ": " .. tostring(why))
            end
        end
        local _, why = L.create(lform({ direction = "offer", itemID = CLOTH, bagInfo = { isBound = true } }))
        ok(why and why:find("已綁定", 1, true), "a bound bag stack: " .. tostring(why))
        ok(L.create(lform({ direction = "need", itemID = RECIPE })), "a tradeable item is fine")
        -- The finder from the form: no row for the ring.
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.openForm()
        UI.openPicker("all")
        ok(not has(UI.pickState.items, RING), "not offered")
        UI.pickSearch(tostring(RING))
        eq(#UI.pickState.items, 0, "not even by its ID")
        eq(UI.picker().empty._text, UI.PICK_EMPTY.all, "the empty words")
        -- B's client (older, or edited) lists the ring: we do not show it.
        local t = T0() - 60
        from(ns, PEER_B, vMsg(ns, A_B, "L", t, L.encode({
            { id = 1, direction = "offer", category = "gear", itemID = RING, quantity = 1, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" },
            { id = 2, direction = "offer", category = "material", itemID = CLOTH, quantity = 1, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" } })))
        local seen = {}
        for _, it in ipairs(ns.Supply.view("guild")) do seen[#seen + 1] = it.itemID end
        eq(table.concat(seen, ","), tostring(CLOTH), "調貨看板: only the cloth")
    end))

    ---------------------------------------------------------------------------
    -- 3. 刪除 my ended listings
    ---------------------------------------------------------------------------

    test("GF-UI-H 刪除: only ended listings of mine; gone for good; the id is never reused; an active one is refused", done(function()
        local ns = login({})
        local L = ns.SupplyListings
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local a = L.create(lform({ itemID = RECIPE }))
        local b = L.create(lform({ itemID = CLOTH }))
        ok(a and b, "two listings")
        local okDel, why = L.remove(a.id)
        ok(not okDel and why:find("結束", 1, true), "active: " .. tostring(why))
        ok(L.finish(a.id, "closed"), "ended")
        UI.setTab("mine")
        local idx
        for i, d in ipairs(UI.state.items) do if d.listing.id == a.id then idx = i end end
        UI.select(idx)
        ok(UI.detail.delete:IsShown() and not UI.detail.edit:IsShown() and not UI.detail.finish:IsShown(), "刪除 instead of 修改／續期／結束")
        for i, d in ipairs(UI.state.items) do if d.listing.id == b.id then UI.select(i) end end
        ok(not UI.detail.delete:IsShown() and UI.detail.finish:IsShown(), "an active one has no 刪除")
        UI.select(idx)
        wow.click(UI.detail.delete)
        local box = ns.Widgets.confirmFrame()
        ok(box and box:IsShown() and box.text._text:find("刪除", 1, true), "asks first")
        wow.click(box.yes)
        for _, d in ipairs(UI.state.items) do ok(d.listing.id ~= a.id, "gone from 我的刊登") end
        eq(L.mine().list[a.id], nil, "removed from the saved list")
        -- Time passes, the sweep and the publish run: nothing brings it back.
        wow.advance(L.SWEEP_EVERY + 5)
        L.publish()
        eq(L.mine().list[a.id], nil, "still gone")
        local mineInAll = 0
        for _, e in ipairs(L.activeAll()) do if e.own and e.id == a.id then mineInAll = mineInAll + 1 end end
        eq(mineInAll, 0, "never published again")
        -- A new listing never takes the deleted id.
        local c = L.create(lform({ itemID = POTION }))
        ok(c and c.id ~= a.id and c.id > b.id, "a fresh id")
        -- Expired ones can be deleted too.
        L.mine().list[b.id].expiresAt = T0() - 1
        L.sweep()
        eq(L.mine().list[b.id].status, "expired", "expired")
        ok(UI.deleteListing(b.id), "deleted")
        eq(L.mine().list[b.id], nil, "gone")
    end))

    ---------------------------------------------------------------------------
    -- 4. The page's top rows: nothing overlaps (UI scale 1.0 / 0.8 / 0.64
    -- scales the whole window alike, so the page coordinates decide)
    ---------------------------------------------------------------------------

    test("GF-UI-H layout: under the sub-tab row; tabs, 刊登, 收集組 and the check boxes never touch; inside the page", done(function()
        local ns = login({})
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local F = ns.Framework
        local p = F.panel("supply")
        -- The sub-tab row's line sits F.SUBTAB_Y - BUTTON_H - 4 from the window top; the page starts at -SUBTAB_H.
        local lineInPage = -(F.SUBTAB_Y - ns.BUTTON_H - 4) - F.SUBTAB_H
        ok(-UI.BAR_Y > lineInPage + 4, "first row below the sub-tab line (" .. lineInPage .. ")")
        -- No page title of its own (it sat under the sub-tab 調貨所).
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "FontString" and o._parent == p and (o._text == "綠皮調貨所" or o._text == "公會物資供需") then
                ok(false, "title text still on the page: " .. o._text)
            end
        end
        -- Rectangles in page coordinates (x from the left, y downwards).
        local function rect(o, w, h)
            local pt = o._points[1]
            return { l = pt[4], t = -pt[5], r = pt[4] + (w or o._w), b = -pt[5] + (h or o._h), name = o._text or "" }
        end
        local boxes = {}
        for _, b in ipairs(UI.tabs.buttons) do boxes[#boxes + 1] = rect(b) end
        boxes[#boxes + 1] = rect(UI.postButton)
        boxes[#boxes + 1] = rect(UI.groupButton)
        boxes[#boxes + 1] = rect(UI.groupLabel, wow.textWidth("收集組", ns.FIELD_FONT), 18)
        for _, c in ipairs({ UI.autoBox, UI.manualBox }) do
            local r = rect(c)
            r.r = r.r + 2 + wow.textWidth(c.label._text, ns.LABEL_FONT) -- the label on its right
            r.name = c.label._text
            boxes[#boxes + 1] = r
        end
        for i = 1, #boxes do
            for j = i + 1, #boxes do
                local a, b = boxes[i], boxes[j]
                local touch = a.l < b.r + 4 and b.l < a.r + 4 and a.t < b.b and b.t < a.b
                ok(not touch, "overlap or no gap: " .. a.name .. " × " .. b.name)
            end
        end
        for _, b in ipairs(boxes) do
            -- GF-UI-I: ＋刊登 sits at the list's right edge (the same 22 px margin as the left).
            ok(b.r <= F.PANEL_WIDTH - UI.LIST_X, b.name .. " keeps a margin to the right edge (" .. b.r .. ")")
            ok(b.b <= -UI.HEAD_Y, b.name .. " above the column header")
        end
        -- The tabs end before 刊登 with a real gap (they touched before).
        local last = UI.tabs.buttons[#UI.tabs.buttons]
        ok(rect(last).r + 8 <= UI.LIST_X + UI.LIST_W - UI.POST_W or rect(last).b <= -UI.TOOL_Y, "我的刊登 and 刊登 apart")
        -- The rows still fit the page.
        ok(-(UI.TOP - UI.ROWS * UI.ROW_H) <= F.PANEL_HEIGHT - 20, "the last row inside the page")
    end))

    test("GF-UI-H layout: the finder's filters, search and rows do not overlap and stay inside it", done(function()
        local ns = login({ bag = { { CLOTH, 5 } } })
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.openForm()
        local p = UI.openPicker("all")
        local P = UI.PICK_FILTER
        ok(P.searchLabel + wow.textWidth("搜尋", ns.FIELD_FONT) < P.search, "搜尋 before its box")
        ok(P.search + P.searchW + 8 <= P.class, "box before 類型")
        ok(P.class + P.filterW + 8 <= P.sub, "類型 before 子類")
        ok(P.sub + P.filterW <= UI.PICK_W - 12, "子類 inside")
        local C = UI.PICK_COL
        ok(C.name + C.nameW <= C.type and C.type + C.typeW <= UI.PICK_W - 24 - 50, "row columns apart, room for the count")
        ok(p.close, "the X")
        -- The form's buttons: item box, 從背包選, 找物品 inside the form.
        local f = UI.form()
        local x = 104 + f.itemBox._w + 10 + f.pick._w + 8 + f.find._w
        ok(x <= f._w - 12, "item row inside the form (" .. x .. ")")
        -- ESC closes the finder, the form stays.
        wow.pressEscape()
        ok(not p:IsShown() and f:IsShown(), "ESC: finder only")
    end))

    test("GF-UI-H 調貨看板: the tab's new name (key guild unchanged); automatic = 可能提供, manual = 徵求／供應", done(function()
        local ns = login({})
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local names = {}
        for _, b in ipairs(UI.tabs.buttons) do names[#names + 1] = b.key .. "=" .. tostring(b._text) end
        eq(table.concat(names, ","), "guild=調貨看板,mine=我的刊登", "tab names (GF-009-16: 我缺的／我可能有多的 are 範圍 filters)")
        UI.setTab("guild")
        eq(UI.state.tab, "guild", "same key")
        local m = { name = PEER_B, online = true }
        local _, auto = UI.personText({ member = m, direction = "offer", qty = 2, auto = true })
        eq(auto, "可能提供 2", "automatic candidate")
        local _, offer = UI.personText({ member = m, direction = "offer", qty = 1, manual = true })
        eq(offer, "供應 1", "manual offer")
        local _, need = UI.personText({ member = m, direction = "need", qty = 3, manual = true })
        eq(need, "徵求 3", "manual need")
    end))

    ---------------------------------------------------------------------------
    -- 5. Money: always the coin icons
    ---------------------------------------------------------------------------

    test("GF-UI-H money: coin icons with or without GetCoinTextureString; 工錢 filter, fee texts; no 1g 23s 45c anywhere", done(function()
        local ns = login({})
        GetCoinTextureString = nil
        local O = ns.OrdersUI
        local s = O.money(12345)
        ok(s:find("UI-GoldIcon", 1, true) and s:find("UI-SilverIcon", 1, true) and s:find("UI-CopperIcon", 1, true), s)
        local bare = s:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        eq(bare, "1 23 45", "only the numbers besides the icons, no g / s / c")
        ok(O.feeText(500):find("UI-SilverIcon", 1, true), "fee text")
        ok(O.totalText({ total = 10000, unknown = true }, 0):find("UI-GoldIcon", 1, true), "estimate")
        local withCoin = 0
        for _, o in ipairs(ns.Recipes.FEE_OPTIONS) do
            ok(not o.text:find("金", 1, true), "no 金 written out: " .. o.text)
            if o.text:find("UI-GoldIcon", 1, true) then withCoin = withCoin + 1 end
        end
        eq(withCoin, 2, "1 / 5 gold options with the coin")
        eq(ns.Recipes.FEE_PLAIN["max:10000"], "1 金以內", "the plain words kept")
        -- Every Lua file: no money written as letters or 金/銀/銅 next to a number.
        local files = { "OrdersUI.lua", "Recipes.lua", "ProfileUI.lua", "Prices.lua", "SupplyUI.lua" }
        for _, name in ipairs(files) do
            local fh = io.open(ADDON_DIR .. "/" .. name, "rb")
            local src = fh:read("*a"); fh:close()
            for line in src:gmatch("[^\n]+") do
                if not line:find("^%s*%-%-") and not line:find("FEE_PLAIN", 1, true) and not line:find("max:%d+\", text") then
                    ok(not line:find('"%s*%d+%s*金'), name .. ": " .. line)
                    ok(not line:find('%.%. *"g"') and not line:find('%.%. *"s"') and not line:find('%.%. *"c"'), name .. ": " .. line)
                end
            end
        end
    end))

    ---------------------------------------------------------------------------
    -- GF-009-14 B: notes and 交易條件 (group M) on manual listings
    ---------------------------------------------------------------------------

    local A_C, A_D = "0000-0000000C", "0000-0000000D"
    local function listing(id, dir, itemID, note, t)
        return { id = id, direction = dir, category = "material", itemID = itemID, quantity = 2,
            createdAt = t, expiresAt = t + 7 * 86400, rev = 1, note = note or "" }
    end
    local function tipOf(rows, itemID)
        for _, r in ipairs(rows) do if r.itemID == itemID then return table.concat(r.tip or {}, "\n"), r end end
        return nil
    end

    test("GF-009-14 B group M: the wire format, limits, an unknown letter, old clients still read L (9 fields)", done(function()
        local ns = login({})
        local L = ns.SupplyListings
        local t = T0() - 60
        local list = { listing(1, "offer", CLOTH, "", t), listing(2, "need", RECIPE, "", t), listing(3, "offer", POTION, "", t),
            listing(4, "need", HERB, "", t) }
        list[1].terms, list[1].price = "price", 12005
        list[2].terms = "free"; list[3].terms = "swap"; list[4].terms = "negotiable"
        local v = L.encodeTerms({ list[1], list[2], list[3], list[4] })
        eq(v, "1,1.p." .. ns.Share.b36(12005) .. ",2.f.,3.x.,4.n.", "1,<id>.<letter>.<price>")
        local m = L.decodeTerms("M", v)
        eq(m[1].terms .. m[1].price, "price12005", "訂價 and the copper"); eq(m[2].terms, "free", "免費")
        eq(m[3].terms, "swap", "交換"); eq(m[4].terms, "negotiable", "面議")
        local z = L.decodeTerms("M", "1,1.z.,2.f.")
        eq(z[1].terms, nil, "an unknown letter: that listing reads 未標示"); eq(z[2].terms, "free", "the rest kept")
        eq(L.decodeTerms("M", "2,1.f."), nil, "only version 1")
        eq(L.decodeTerms("M", "1,1.p."), nil, "訂價 without a price")
        eq(L.decodeTerms("M", "1,1.p." .. ns.Share.b36(L.PRICE_MAX + 1)), nil, "over the money cap")
        ok(L.decodeTerms("M", "1,1.p." .. ns.Share.b36(L.PRICE_MAX)) ~= nil, "the cap itself is fine")
        eq(L.decodeTerms("M", "1,1.f.5"), nil, "a price on 免費")
        eq(L.decodeTerms("M", "1,1.f.,1.n."), nil, "an id twice")
        local many = { "1" }
        for i = 1, 11 do many[#many + 1] = ns.Share.b36(i) .. ".n." end
        eq(L.decodeTerms("M", table.concat(many, ",")), nil, "more than 10")
        ok(L.decodeTerms("M", "1") ~= nil and next(L.decodeTerms("M", "1")) == nil, "an empty snapshot")
        -- L stays 9 fields: an old decoder (this one, unchanged) reads a listing with terms.
        local lv = L.encode({ list[1] })
        local fields = 0
        for _ in (lv .. "."):gmatch("([^.]*)%.") do fields = fields + 1 end
        eq(fields, 9, "L: still 9 fields")
        ok(L.decode("L", lv) and L.decode("L", lv)[1].itemID == CLOTH, "old clients keep reading L")
        ok(ns.Share.isLocalGroup("M"), "M is local (not GF Sync, not the site)")
        eq(L.termsText("price", 12005), "每個 1金 20銀 5銅", "long price")
        eq(L.termsText("price", 12005, true), "1金20銀5銅", "short price")
        eq(L.termsText(nil), "未標示", "no terms")
    end))

    test("GF-009-14 B the form: 交易條件 under 數量 (面議 for a new one), 每個 price only for 訂價, the money cap; re-editing", done(function()
        local ns = login({ bag = { { CLOTH, 5 } } })
        local L = ns.SupplyListings
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.openForm()
        local f = UI.form()
        eq(UI.formState.terms, "negotiable", "a new listing: 面議")
        ok(not f.priceRow:IsShown(), "no price row for 面議")
        UI.formFromText(tostring(CLOTH))
        f.qty:SetText("3"); f.note:SetText("可議價")
        UI.setFormTerms("price")
        ok(f.priceRow:IsShown(), "訂價 opens 金 / 銀 / 銅")
        eq(f.priceRow.each._text, "每個", "labelled 每個")
        f.gold:SetText("214749")
        local l, why = UI.submitForm()
        ok(not l and tostring(why):find("每個最多", 1, true), "over the money cap: " .. tostring(why))
        f.gold:SetText("1"); f.silver:SetText("120")
        l, why = UI.submitForm()
        ok(not l and why == UI.SILVER_MAX_TEXT, "銀 over 99")
        f.silver:SetText("20"); f.copper:SetText("5")
        l = UI.submitForm()
        ok(l and l.terms == "price" and l.price == 12005, "訂價 1金 20銀 5銅 per item")
        local tip, row = tipOf(UI.listFor("mine"), CLOTH)
        ok(tip:find("交易條件：每個 1金 20銀 5銅", 1, true) and tip:find("備註：可議價", 1, true), "我的刊登 tooltip: " .. tip)
        ok(row.hasNote, "note icon in 我的刊登")
        -- Re-edit: the form comes back with the price; then 交換 drops it.
        UI.openForm(l)
        eq(UI.formState.terms, "price", "edit: terms back"); eq(f.gold:GetText(), "1", "gold back"); eq(f.copper:GetText(), "5", "copper back")
        UI.setFormTerms("swap")
        ok(not f.priceRow:IsShown(), "交換: no price")
        f.note:SetText("換絲綢")
        local l2 = UI.submitForm()
        ok(l2 and l2.terms == "swap" and l2.price == nil, "edited to 交換, the price gone")
        ok(L.renew(l2.id, 14) and L.own()[1].terms == "swap", "續期 keeps the terms")
        local rec = ns.Share.get(ns.Share.selfAuthor(), "M")
        ok(rec and rec.v:find("%.x%.") ~= nil, "M published with the listing: " .. tostring(rec and rec.v))
        -- An old listing (no terms) edited without choosing keeps 未標示.
        local m = L.own()[1]
        m.terms, m.price = nil, nil
        UI.openForm(m)
        eq(UI.formState.terms, nil, "an old listing: nothing chosen")
        f.note:SetText("舊單改備註")
        local l3 = UI.submitForm()
        ok(l3 and l3.terms == nil and l3.note == "舊單改備註", "still 未標示, note changed")
    end))

    test("GF-009-14 B two characters: terms and full notes in 我缺的 / 我可能有多的 / 調貨看板 / 我的刊登; same item, different prices; old listings 未標示", done(function()
        local ns = login({ bag = { { CLOTH, 5 } } })
        local L = ns.SupplyListings
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        -- Mine (character A): I need cloth (面議), I offer the recipe (交換).
        local need = L.create(lform({ direction = "need", itemID = CLOTH, note = "" }))
        local offer = L.create(lform({ direction = "offer", itemID = RECIPE, terms = "swap", note = "換布料" }))
        ok(need and offer, "my two listings")
        -- What another character receives from me: my own L and M values decode there.
        local selfA = ns.Share.selfAuthor()
        local theirs = L.decodeTerms("M", ns.Share.get(selfA, "M").v)
        local seen = {}
        for _, x in ipairs(L.decode("L", ns.Share.get(selfA, "L").v)) do seen[x.itemID] = theirs[x.id] end
        eq(seen[CLOTH].terms, "negotiable", "the other side sees my 面議"); eq(seen[RECIPE].terms, "swap", "and my 交換")
        -- B, C and D offer cloth: 訂價 1金 / 免費 / an old AddOn (L only); B needs the recipe.
        local t = T0() - 60
        local bOffer, bNeed = listing(1, "offer", CLOTH, "一組二十個", t), listing(2, "need", RECIPE, "", t)
        bOffer.terms, bOffer.price, bNeed.terms = "price", 10000, "negotiable"
        local cOffer = listing(1, "offer", CLOTH, "送新人", t); cOffer.terms = "free"
        local dOffer = listing(1, "offer", CLOTH, "老版本的備註", t)
        from(ns, PEER_B, vMsg(ns, A_B, "L", t, L.encode({ bOffer, bNeed })))
        from(ns, PEER_B, vMsg(ns, A_B, "M", t, L.encodeTerms({ bOffer, bNeed })))
        from(ns, PEER_B, vMsg(ns, A_C, "L", t, L.encode({ cOffer })))
        from(ns, PEER_B, vMsg(ns, A_C, "M", t, L.encodeTerms({ cOffer })))
        from(ns, PEER_B, vMsg(ns, A_D, "L", t, L.encode({ dOffer })))
        ns.Supply.invalidate()
        -- 我缺的: cloth, three offers, each with its own terms and note.
        local tip, row = tipOf(UI.listFor("need"), CLOTH)
        ok(tip, "cloth in 我缺的")
        tip = tip or ""
        ok(tip:find("測試乙：供應 2｜交易條件：每個 1金", 1, true), "B's price: " .. tip)
        ok(tip:find("備註：一組二十個", 1, true), "B's note in full")
        ok(tip:find("測試丙：供應 2｜交易條件：免費", 1, true) and tip:find("備註：送新人", 1, true), "C: 免費 and note")
        ok(tip:find("測試丁：供應 2｜交易條件：未標示", 1, true) and tip:find("備註：老版本的備註", 1, true), "D (old AddOn): 未標示, note shown")
        ok(row and row.hasNote, "a note: the icon")
        -- The detail rows: short terms, the icon only with a note, the full text in the tooltip.
        UI.setTab("need")
        local idx
        for i, it in ipairs(UI.state.items) do if it.itemID == CLOTH then idx = i end end
        UI.select(idx)
        local conds, icons, tips = {}, 0, {}
        for _, r in ipairs(UI.detailRowList()) do
            if r:IsShown() then
                conds[#conds + 1] = r.src._text
                if r.noteIcon:IsShown() then icons = icons + 1 end
                r:GetScript("OnEnter")(r)
                for _, ln in ipairs(GameTooltip._lines) do tips[#tips + 1] = ln.text end
            end
        end
        local p = table.concat(conds, ",")
        ok(p:find("1金", 1, true) and p:find("免費", 1, true) and p:find("未標示", 1, true), "條件 column: " .. p)
        eq(icons, 3, "three listings with a note: three icons")
        ok(table.concat(tips, "\n"):find("備註：老版本的備註", 1, true), "the detail row's tooltip has the full note")
        -- 我可能有多的: B needs my recipe; no note, no icon.
        local tip2, row2 = tipOf(UI.listFor("offer"), RECIPE)
        ok(tip2 and tip2:find("測試乙：徵求 2｜交易條件：面議", 1, true), "B's need: 面議: " .. tostring(tip2))
        ok(row2 and not row2.hasNote, "no note: no icon")
        -- 調貨看板: everyone's.
        local tip3 = tipOf(UI.listFor("guild"), CLOTH) or ""
        ok(tip3:find("每個 1金", 1, true) and tip3:find("免費", 1, true) and tip3:find("送新人", 1, true), "調貨看板: " .. tip3)
        -- 我的刊登: mine.
        local tip4 = tipOf(UI.listFor("mine"), RECIPE) or ""
        ok(tip4:find("交易條件：交換", 1, true) and tip4:find("備註：換布料", 1, true), "我的刊登: " .. tip4)
        -- Automatic candidates keep 可能提供.
        local _, what = UI.personText({ direction = "offer", qty = 3, auto = 3, member = { name = "測試乙" } })
        eq(what, "可能提供 3", "自動集料 stays 可能提供")
    end))
end
