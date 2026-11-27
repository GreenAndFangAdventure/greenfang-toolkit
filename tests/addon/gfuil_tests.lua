-- GF-UI-L: the version and the GF Sync signal at the right end of the main
-- window's sub-tab row. Offline only; made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local function login()
        wow.reset({})
        local ns = wow.login(ADDON_DIR)
        wow.advance(130)
        return ns
    end

    -- A made-up Inbox string with H.at = at (only the header matters here).
    local function inbox(at) return "GFIN1~abc~sig~H;realm=x;guild=y;at=" .. at .. ";n=0" end

    local function withInbox(value, exists, fn)
        return function()
            local oldG, oldC, oldInfo = _G.GreenFangToolkit_Inbox, C_AddOns, rawget(_G, "GetAddOnInfo")
            local okRun, err = pcall(function()
                local ns = login()
                _G.GreenFangToolkit_Inbox = value
                C_AddOns = { GetAddOnMetadata = oldC and oldC.GetAddOnMetadata }
                if exists ~= nil then
                    C_AddOns.DoesAddOnExist = function(name) return name == "GreenFangToolkit_Inbox" and exists end
                end
                fn(ns)
            end)
            _G.GreenFangToolkit_Inbox, C_AddOns, _G.GetAddOnInfo = oldG, oldC, oldInfo
            if not okRun then error(err, 0) end
        end
    end

    local function mainWindow(ns)
        for _, f in ipairs(ns.Theme.fitFrames) do if f.gfFitMain then return f end end
    end

    local function tipText()
        local all = {}
        for _, l in ipairs(GameTooltip._lines or {}) do all[#all + 1] = l.text end
        return table.concat(all, "\n")
    end

    test("GF-UI-L version: v<ns.VERSION> at the right end of the sub-tab row, on every entry", function()
        local ns = login()
        local F = ns.Framework
        ok(ns.VERSION:match("^%d"), "the TOC version")
        eq(F.versionText(), "v" .. ns.VERSION, "v + ns.VERSION")
        for _, e in ipairs(F.entries()) do
            F.open(e.pages[1].id)
            local b = F.infoButton()
            ok(b and b:IsShown(), e.key .. ": shown")
            ok(b:GetText():find("v" .. ns.VERSION, 1, true) == 1, e.key .. ": starts with the version: " .. b:GetText())
        end
        local p = F.infoButton()._points[1]
        eq(p[1], "TOPRIGHT", "anchored at the row's right end")
        eq(p[4], -F.INFO_RIGHT, "where the line under the row ends")
    end)

    test("GF-UI-L version: never overlaps the sub-tabs; shortens, then hides, when they need the room", function()
        local ns = login()
        local F = ns.Framework
        for _, e in ipairs(F.entries()) do
            F.open(e.pages[1].id)
            local right = 20
            for _, b in ipairs(F.subTabButtons()) do
                if b:IsShown() then right = math.max(right, b._points[1][4] + b._fixedWidth) end
            end
            local info = F.infoButton()
            local left = F.PANEL_WIDTH - F.INFO_RIGHT - ns.labelWidth(info:GetText())
            ok(left - right >= F.INFO_GAP, e.key .. ": a gap of 16 px (" .. left .. " vs " .. right .. ")")
        end
        -- Many tabs: the bracket goes first, then everything but the version, then all.
        local info = F.infoButton()
        info.sig = { state = "seen", why = "inbox", at = os.time() }
        local full = F.versionText() .. "｜" .. F.gfSyncText(info.sig)
        local function roomFor(text) return F.PANEL_WIDTH - F.INFO_RIGHT - F.INFO_GAP - ns.labelWidth(text) end
        local cases = {
            { roomFor(full), full },
            { roomFor(full) + 1, F.versionText() .. "｜GF Sync：已偵測到" },
            { roomFor(F.versionText() .. "｜GF Sync：已偵測到") + 1, F.versionText() },
            { roomFor(F.versionText()) + 1, "" },
        }
        local win = mainWindow(ns)
        for _, c in ipairs(cases) do
            win.subTabsRight = c[1]
            eq(F.placeInfo(), c[2], "room after the tabs at " .. c[1])
        end
        ok(not info:IsShown(), "no room at all: hidden")
    end)

    test("GF-UI-L 4:3: the text is inside the main window, so Theme.fit scales it with the tabs", function()
        local ns = login()
        local F, Th = ns.Framework, ns.Theme
        UIParent.GetWidth = function() return 1024 end
        UIParent.GetHeight = function() return 768 end
        F.open("roster")
        local win = mainWindow(ns)
        ok(win.gfFitScale and win.gfFitScale < 1, "the window is scaled down")
        local info = F.infoButton()
        local f, chain = info, {}
        while f do chain[#chain + 1] = f; f = f._parent end
        local inWindow = false
        for _, x in ipairs(chain) do if x == win then inWindow = true end end
        ok(inWindow, "a child of the main window")
        eq(info._scale, nil, "no scale of its own")
        UIParent.GetWidth, UIParent.GetHeight = nil, nil
        Th.refit()
    end)

    test("GF-UI-L GF Sync: no AddOn list on this client = 無法判斷, never 沒偵測到", withInbox(nil, nil, function(ns)
        local F = ns.Framework
        local sig = ns.WebOrders.gfSyncSignal()
        eq(sig.state, "unknown", "state")
        F.open("roster")
        eq(F.infoButton():GetText(), F.versionText() .. "｜GF Sync：無法判斷", "text")
        wow.fire("PLAYER_ENTERING_WORLD")
        F.infoButton():GetScript("OnEnter")(F.infoButton())
        local tip = tipText()
        ok(tip:find("查不到 AddOn 清單", 1, true), tip)
        ok(tip:find(F.GFSYNC_CHECK, 1, true), "where to look instead")
        ok(tip:find(F.GFSYNC_CLICK, 1, true), "says the click")
    end))

    test("GF-UI-L GF Sync: no Inbox AddOn = 沒偵測到, and the tooltip says why that is not 沒安裝", withInbox(nil, false, function(ns)
        local F = ns.Framework
        F.open("roster")
        eq(F.infoButton():GetText(), F.versionText() .. "｜GF Sync：沒偵測到", "text")
        F.infoButton():GetScript("OnEnter")(F.infoButton())
        local tip = tipText()
        ok(tip:find("沒偵測到不代表沒安裝", 1, true), tip)
        ok(tip:find("預設關閉", 1, true), "Inbox is off by default")
        ok(tip:find("綠皮冒險工具箱 v" .. ns.VERSION, 1, true), "the version on the first line")
    end))

    test("GF-UI-L GF Sync: GetAddOnInfo (older clients) MISSING = 沒偵測到; a name = 已偵測到", withInbox(nil, nil, function(ns)
        local W = ns.WebOrders
        _G.GetAddOnInfo = function(name) return name, nil, nil, false, "MISSING" end
        eq(W.gfSyncSignal().state, "none", "MISSING")
        _G.GetAddOnInfo = function(name) return name, "GreenFangToolkit Inbox", "", true, "DEMAND_LOADED" end
        eq(W.gfSyncSignal().why, "folder", "there, not loaded")
        _G.GetAddOnInfo = function() error("Invalid AddOn name") end
        eq(W.gfSyncSignal().state, "unknown", "an error = cannot tell")
    end))

    test("GF-UI-L GF Sync: the Inbox folder without a list = 已偵測到（尚無清單）, not running", withInbox(nil, true, function(ns)
        local F = ns.Framework
        F.open("roster")
        eq(F.infoButton():GetText(), F.versionText() .. "｜GF Sync：已偵測到（尚無清單）", "text")
        F.infoButton():GetScript("OnEnter")(F.infoButton())
        ok(tipText():find(F.GFSYNC_SEEN_NOTE, 1, true), "not proof that it runs now")
    end))

    test("GF-UI-L GF Sync: an Inbox string = 已偵測到 with the list time (月-日 時:分, local)", withInbox(nil, true, function(ns)
        local F, W = ns.Framework, ns.WebOrders
        local at = ns.Share.serverNow() - 3600
        _G.GreenFangToolkit_Inbox = inbox(at)
        eq(W.inboxAt(inbox(at)), at, "H.at")
        F.open("roster")
        eq(F.infoButton():GetText(), F.versionText() .. "｜GF Sync：已偵測到（清單 " .. (date or os.date)("%m-%d %H:%M", at) .. "）", "text")
        F.infoButton():GetScript("OnEnter")(F.infoButton())
        local tip = tipText()
        ok(tip:find("網站產生這份清單的時間", 1, true), "says what the time is")
        -- A header without a usable at: 已偵測到 with no time (never a made-up one).
        for _, s in ipairs({ "GFIN1~a~b~H;at=x", "garbage", "GFIN1~a~b~H;at=0", string.rep("A", 70000) }) do
            _G.GreenFangToolkit_Inbox = s
            eq(W.inboxAt(s), nil, "no at: " .. s:sub(1, 20))
            eq(F.gfSyncText(W.gfSyncSignal()), "GF Sync：已偵測到", "no time shown")
        end
    end))

    test("GF-UI-L click opens 同步與診斷, which has the same line", withInbox(nil, false, function(ns)
        local F = ns.Framework
        F.open("roster")
        ok(not ns.Diag.isShown(), "closed")
        F.infoButton():GetScript("OnClick")(F.infoButton())
        ok(ns.Diag.isShown(), "opened")
        local found
        for i, h in ipairs(ns.Diag.heads()) do
            if h:GetText() == "GF Sync 偵測" then found = ns.Diag.lines()[i]:GetText() end
        end
        ok(found and found:find("GF Sync：沒偵測到", 1, true) and found:find("沒偵測到不代表沒安裝", 1, true), tostring(found))
    end))

    test("GF-UI-L performance: read on open / hover only; no OnUpdate, no event; unchanged = no SetText", withInbox(nil, false, function(ns)
        local F = ns.Framework
        F.open("roster")
        local b = F.infoButton()
        local sets = 0
        local orig = b.SetText
        b.SetText = function(self, t) sets = sets + 1; return orig(self, t) end
        local reads = F.infoReads
        wow.advance(600)
        eq(F.infoReads, reads, "nothing read while time passes")
        F.select("recipes")
        eq(F.infoReads, reads, "switching pages does not read the signal")
        F.toggle(); F.toggle()
        eq(F.infoReads, reads + 1, "opening the window reads it once")
        eq(sets, 0, "unchanged: not set again")
        ok(b._scripts.OnUpdate == nil, "no OnUpdate")
        eq(next(b._events), nil, "no events")
        C_AddOns.DoesAddOnExist = function() return true end
        b:GetScript("OnEnter")(b)
        eq(sets, 1, "changed: set once")
        b.SetText = orig
    end))

    test("GF-UI-L privacy: the line and the tooltip have no GUID, account or path", withInbox(nil, false, function(ns)
        local F = ns.Framework
        F.open("roster")
        F.infoButton():GetScript("OnEnter")(F.infoButton())
        local all = F.infoButton():GetText() .. "\n" .. tipText() .. "\n" .. F.gfSyncDiagText()
        ok(not all:find("Player%-"), "no GUID")
        ok(not all:find("WTF", 1, true) and not all:find("Account", 1, true) and not all:find("\\", 1, true), "no path")
    end))
end
