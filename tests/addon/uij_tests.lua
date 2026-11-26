-- GF-UI-J: the owner's 0.16.2 notes on 冒險業務 — warm charcoal (no green),
-- the orc head / Horde standard / notice scroll, and the worker ticket's
-- tooltip with everything the ticket holds (a scrolling window when it is
-- taller than the screen). Offline only (MANUAL §3uij). Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B = "0000-0000000B"
    local H = 3600

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function offer(ns, a, g, list, t)
        local v = ns.Adventure.encodeList(list)
        local r = ns.Adventure.ledger:offer(a, g, t or ns.Share.serverNow(), ns.Share.hash(v), v)
        ns.Adventure.refresh()
        return r
    end
    local function rowOf(U, author)
        local sc = U.scrollFrame()
        for k = 0, #U.shownRows() do
            sc:SetVerticalScroll(k * U.ROW_HEIGHT)
            for _, r in ipairs(U.rowFrames()) do
                if r:IsShown() and r.worker == author then return r end
            end
        end
    end
    local function tipText()
        local out = {}
        for _, l in ipairs(GameTooltip._lines or {}) do out[#out + 1] = plain(type(l) == "table" and (l.text or l[1]) or l) end
        return table.concat(out, "\n")
    end
    -- B's worker ticket: 5 dungeons, a whole zone, 4 quests, 3 slots (one with a length).
    local function bigWorker(ns, extraDungeons)
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local ds = "stk.bfd.sfk.wc.dm" .. (extraDungeons or "")
        local sv = Adv.encodeTimes({ { id = 1, now = true, s = t }, { id = 2, s = t + 26 * H, d = 2 * H }, { id = 3, s = t + 50 * H } })
        offer(ns, B, "W", { { id = "w", cr = t, ds = ds, qs = "850.851.852.853",
            qn = "850:測試任務甲;851:測試任務乙;852:測試任務丙;853:測試任務丁", zs = "貧瘠之地",
            rm = "t", ra = "h", sv = sv, ex = t + 86400, st = "o", sa = t } })
        ns.Framework.open("adventure")
        ns.AdventureUI.refresh()
        return rowOf(ns.AdventureUI, B)
    end

    test("GF-UI-J palette: warm charcoal, no green in the panel, side, header, rows or the chosen fill", function()
        local ns = login()
        local C = ns.Theme.C
        local function is(c, hex, what)
            local want = ns.Theme.rgb(hex)
            for k = 1, 3 do ok(math.abs(c[k] - want[k]) < 0.002, what .. " " .. hex) end
        end
        is(C.main, "232323", "main"); is(C.side, "292724", "side"); is(C.rowA, "282624", "row 1"); is(C.rowB, "302D29", "row 2")
        is(C.form, "302C28", "pop-ups"); eq(C.form[4], 1, "opaque"); is(C.text, "E8DFD2", "text"); is(C.selLine, "B9925F", "brass frame")
        -- Green never stronger than red in any large fill.
        for _, k in ipairs({ "bg", "main", "side", "panel", "rowA", "rowB", "form", "selFill", "goldFill", "head", "input", "line" }) do
            ok(C[k][2] <= C[k][1] + 0.001, k .. " is not green")
        end
    end)

    test("GF-UI-J icons: the orc head, the Horde standard, one notice scroll for ＋職工單 and 我的職工單", function()
        local ns = login()
        local F, G, U = ns.Framework, ns.GameIcons, ns.AdventureUI
        eq(F.ENTRY_ICON.profile[1], "Interface\\Icons\\INV_Misc_Head_Orc_01", "職工檔案")
        eq(F.ENTRY_ICON.directory[1], "Interface\\Icons\\INV_BannerPVP_01", "職工名冊")
        eq(G.pick("worker")[1], "Interface\\Icons\\INV_Scroll_05", "職工單")
        for _, path in ipairs({ F.ENTRY_ICON.profile[1], F.ENTRY_ICON.directory[1], G.pick("worker")[1] }) do
            ok(path:find("^Interface\\Icons\\"), "a square game icon (no gossip mark): " .. path)
        end
        ns.Framework.open("adventure")
        ok(U.workerButton:GetText():find("INV_Scroll_05", 1, true), "＋職工單")
        local Adv = ns.Adventure
        Adv.setWorker({ dungeons = { "smg" }, quests = {}, main = "d", slots = { { now = true } } })
        U.refresh()
        local head
        for _, d in ipairs(U.shownRows()) do if d.header and d.header:find("我的職工單", 1, true) then head = d.header end end
        ok(head and head:find("INV_Scroll_05", 1, true), "我的職工單 uses the same scroll")
    end)

    test("GF-UI-J worker tooltip: the row cuts to +N, the tooltip lists everything in groups", function()
        local ns = login()
        local U = ns.AdventureUI
        local row = bigWorker(ns)
        ok(row, "B's row")
        ok(plain(row.name:GetText()):find("+2", 1, true), "the row: three dungeons and +2: " .. plain(row.name:GetText()))
        row._scripts.OnEnter(row)
        local tip = tipText()
        for _, name in ipairs({ "監獄", "黑暗深淵", "影牙城堡", "哀嚎洞穴", "死亡礦坑" }) do
            ok(tip:find(name, 1, true), "every dungeon: " .. name)
        end
        ok(tip:find("貧瘠之地 全區", 1, true), "the zone")
        for _, q in ipairs({ "測試任務甲", "測試任務乙", "測試任務丙", "測試任務丁" }) do ok(tip:find(q, 1, true), "every quest: " .. q) end
        ok(tip:find("現在", 1, true), "slot 1")
        ok(tip:find("預計 2 小時", 1, true), "the length when filled in")
        ok(tip:find("測試乙-測試伺服器", 1, true), "the full character name")
        ok(tip:find("戰士", 1, true), "the class")
        ok(tip:find("上架", 1, true), "the state")
        ok(tip:find("坦", 1, true) and tip:find("副", 1, true) and tip:find("補", 1, true), "main and support roles")
        local order = {}
        for _, g in ipairs({ "職責", "地城", "區域", "任務", "時段" }) do order[#order + 1] = tip:find("\n" .. g .. "\n", 1, true) or 0 end
        for k = 2, #order do ok(order[k] > order[k - 1], "groups in order") end
        -- Not in a slot 3 length (none filled in): no 預計 for it.
        local _, n = tip:gsub("預計", "")
        eq(n, 1, "only the slot with a length says 預計")
        ok(not row.workerTip.lines[1].text:find("+", 1, true), "no +N inside the tooltip")
    end)

    test("GF-UI-J worker tooltip: goes to the side with room; buttons keep their own tooltip", function()
        local ns = login()
        local U = ns.AdventureUI
        local row = bigWorker(ns)
        UIParent.GetWidth = function() return 1600 end
        UIParent.GetHeight = function() return 900 end
        row.GetCenter = function() return 1400, 150 end
        eq((U.tipAnchor(row)), "BOTTOMRIGHT", "right and low: the tooltip above, to the left")
        row.GetCenter = function() return 200, 800 end
        eq((U.tipAnchor(row)), "TOPLEFT", "left and high: below, to the right")
        row._scripts.OnEnter(row)
        eq(row.tipPoint, "TOPLEFT", "used for the tooltip")
        eq(GameTooltip._anchor, "ANCHOR_NONE", "placed by the toolkit")
        -- A row button is its own frame with its own tooltip.
        local b = row.buttons[1]
        if b:IsShown() then
            b._scripts.OnEnter(b)
            ok(not tipText():find("黑暗深淵", 1, true), "the button shows its own tooltip, not the ticket")
        end
        UIParent.GetWidth, UIParent.GetHeight = nil, nil
    end)

    test("GF-UI-J worker tooltip: taller than the screen -> a click opens a scrolling window with every line", function()
        local ns = login()
        local U = ns.AdventureUI
        local row = bigWorker(ns, ".gnr.rfk.smg.sml.sma")
        UIParent.GetHeight = function() return 400 end
        local max = U.workerTipMaxLines()
        ok(#row.workerTip.lines > max, "more lines than fit: " .. #row.workerTip.lines .. " > " .. max)
        row._scripts.OnEnter(row)
        eq(#GameTooltip._lines, max, "the tooltip stops at the screen")
        ok(tipText():find("點列看全部", 1, true), "and says a click shows all")
        row._scripts.OnMouseUp(row, "LeftButton")
        local f = U.workerDetailFrame()
        ok(f and f:IsShown(), "the window")
        eq(#f.lines, #row.workerTip.lines, "every line")
        local shown = 0
        for _, fs in ipairs(f.texts) do if fs:IsShown() then shown = shown + 1 end end
        eq(shown, #row.workerTip.lines, "all drawn in the scrolling content")
        ok(f.scroll and f.scroll.SetScrollChild, "a scroll frame")
        ok(f.gfForm, "opaque pop-up colour")
        ns.escape(); ok(not f:IsShown(), "ESC closes it")
        -- Short enough: a click opens nothing.
        UIParent.GetHeight = function() return 1200 end
        row._scripts.OnMouseUp(row, "LeftButton")
        ok(not f:IsShown(), "fits: no window")
        UIParent.GetHeight = nil
    end)
end
