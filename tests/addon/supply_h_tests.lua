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
        ok(G.asked[ns.SupplyRules.list[1].order[1]], "the small sources ask for missing item data")
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
            ok(b.r <= F.PANEL_WIDTH - 40, b.name .. " keeps a margin to the right edge (" .. b.r .. ")")
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
        eq(table.concat(names, ","), "need=我缺的,offer=我可能有多的,guild=調貨看板,mine=我的刊登", "tab names")
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
end
