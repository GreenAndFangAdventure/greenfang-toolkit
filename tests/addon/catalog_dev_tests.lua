-- GF-009-13: the dev-only GreenFangToolkit_Dev AddOn (/gftkdev catalogscan):
-- its own TOC and SavedVariables, the client build / locale checks, the
-- sample (success, invalid ID, timeout), counts of requests and events, and
-- waiting / retry IDs kept across logins. A small fake game client below.
-- Offline only; not checked in the Forever client.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local ROOT = ADDON_DIR:gsub("/addon/GreenFangToolkit$", "")
    local DEV_DIR = ROOT .. "/addon/GreenFangToolkit_Dev"
    local CATALOG = ADDON_DIR .. "/SupplyCatalogData.lua"

    local function readAll(path) local h = io.open(path, "rb"); if not h then return nil end local s = h:read("*a"); h:close(); return s end
    local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copy(x) end
        return out
    end
    local function tocFiles()
        local out = {}
        for line in (readAll(DEV_DIR .. "/GreenFangToolkit_Dev.toc") or ""):gmatch("[^\r\n]+") do
            if line:match("^[%w_]+%.lua$") then out[#out + 1] = line end
        end
        return out
    end
    local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
    local function b36(n)
        if n == 0 then return "0" end
        local s = ""
        while n > 0 do local r = n % 36; s = B36:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) end
        return s
    end
    local function pack(ids)
        local out, last = {}, 0
        for _, i in ipairs(ids) do out[#out + 1] = b36(i - last); last = i end
        return table.concat(out, ",")
    end

    local G
    local function install(opts)
        G = { known = {}, server = opts.server or {}, fail = opts.fail or {}, exists = opts.exists or {},
            requests = {}, coldInfo = 0, instance = false }
        local function getInfo(id)
            local it = G.known[id]
            if not it then
                G.coldInfo = G.coldInfo + 1
                G.requests[#G.requests + 1] = { id = id, t = wow.state.now, via = "info" } -- a miss asks the server
                return nil
            end
            return it.name, "link", it.quality or 1, it.ilvl or 1, 1, "", "", 20, "", it.icon or 134939, 0,
                it.classID, it.sub or 0, it.bindType or 0
        end
        GetItemInfo = getInfo -- the Forever profile (mock.lua) keeps it off _G: C_Item.GetItemInfo
        C_Item = {
            RequestLoadItemDataByID = function(id) G.requests[#G.requests + 1] = { id = id, t = wow.state.now, via = "load" } end,
            DoesItemExistByID = function(id) return G.exists[id] ~= false end,
            IsItemDataCachedByID = function(id) return G.known[id] ~= nil end,
        }
        if opts.noCachedAPI then C_Item.IsItemDataCachedByID = nil end
        if opts.forever then
            -- The owner's Forever probe (GF-009-13 field result): C_Item.GetItemInfo
            -- gives the classic 18 values (the 16th nil, a |cnIQ1: link); the
            -- global GetItemInfo gives nothing.
            local miss = getInfo
            C_Item.GetItemInfo = function(id)
                local it = G.known[id]
                if not it then return miss(id) end
                return it.name, "|cnIQ1:|Hitem:" .. id .. "::::::::27:1486:::::::::|h[" .. it.name .. "]|h|r", it.quality or 1,
                    it.ilvl or 5, 0, "商品", "布料", 20, "INVTYPE_NON_EQUIP_IGNORE", it.icon or 132889, 13, it.classID,
                    it.sub or 0, it.bindType or 0, 0, nil, true, ""
            end
            GetItemInfo = function() end
        end
        IsInInstance = function() return G.instance end
        GetBuildInfo = function() return opts.version or "1.60.1", opts.build or "71139", "Nov 1 2026", 16001 end
        GetLocale = function() return opts.locale or "zhTW" end
    end
    local function remove() GetItemInfo, C_Item, IsInInstance = nil, nil, nil; GreenFangToolkitDevDB = nil end
    local function done(fn) return function() local okRun, err = pcall(fn); remove(); if not okRun then error(err, 0) end end end

    -- Load the dev AddOn as the client does (its TOC's files, its SavedVariables).
    local function loadDev(opts)
        opts = opts or {}
        wow.reset(opts)
        install(opts)
        GreenFangToolkitDevDB = copy(opts.saved)
        local D = {}
        for _, file in ipairs(tocFiles()) do assert(loadfile(DEV_DIR .. "/" .. file))("GreenFangToolkit_Dev", D) end
        if opts.sample then D.scanData.sample = opts.sample end
        if opts.scan then D.scanData.scan = opts.scan end
        wow.fire("ADDON_LOADED", "GreenFangToolkit_Dev")
        wow.fire("PLAYER_ENTERING_WORLD")
        return D, D.CatalogScan
    end
    local function slash(msg) SlashCmdList.GFTKDEV(msg) end
    -- The fake server answers a request one second later: an item it knows,
    -- "no such item" for G.fail, nothing for the rest. G.loadEvent (the
    -- Forever client, GF-009-13 field result): a RequestLoadItemDataByID is
    -- answered with ITEM_DATA_LOAD_RESULT, a GetItemInfo miss with
    -- GET_ITEM_INFO_RECEIVED; G.silentLoad: the load answers with no event at all.
    local function serve(seconds)
        for _ = 1, seconds * 4 do
            wow.advance(0.25)
            if G.noise then wow.fire("GET_ITEM_INFO_RECEIVED", 2589 + math.floor(wow.state.now) % 7, true) end
            for _, r in ipairs(G.requests) do
                if not r.answered and wow.state.now - r.t >= 1 then
                    local ev = "GET_ITEM_INFO_RECEIVED"
                    if G.loadEvent and r.via == "load" then ev = "ITEM_DATA_LOAD_RESULT" end
                    if G.server[r.id] then
                        r.answered = true
                        G.known[r.id] = G.server[r.id]
                        if not (G.silentLoad and r.via == "load") then wow.fire(ev, r.id, true) end
                    elseif G.fail[r.id] then
                        r.answered = true
                        if not (G.silentLoad and r.via == "load") then wow.fire(ev, r.id, false) end
                    end
                end
            end
        end
    end
    local function item(i) return { name = "掃描物品" .. i, classID = 7, sub = 5, quality = 1, ilvl = 10 + i, icon = 1000 + i } end

    test("GF-009-13 dev AddOn: its own TOC and SavedVariables, /gftkdev only, a ~20 ID sample; nothing runs until typed", done(function()
        local toc = readAll(DEV_DIR .. "/GreenFangToolkit_Dev.toc")
        ok(toc and toc:find("## SavedVariables: GreenFangToolkitDevDB", 1, true), "its own SavedVariables")
        ok(not toc:find("GreenFangToolkitDB", 1, true), "not the guild AddOn's")
        eq(table.concat(tocFiles(), ","), "CatalogScanData.lua,CatalogScan.lua,TraitDump.lua,Preview.lua", "files")
        local D, S = loadDev({})
        eq(D.scanData.build, "1.60.1.71139", "list build"); eq(D.scanData.locale, "zhTW", "list locale")
        local list, sample = S.list("full"), S.list("sample")
        ok(#list > 10000, "full list: " .. #list)
        for i = 2, #list do if list[i] <= list[i - 1] then error("not sorted at " .. i) end end
        ok(#sample >= 15 and #sample <= 25, "about 20 in the sample: " .. #sample)
        local inList, catalogText = {}, readAll(CATALOG)
        for _, id in ipairs(list) do inList[id] = true end
        local kinds = { catalog = 0, scan = 0, invalid = 0 }
        for _, id in ipairs(sample) do
            if inList[id] then kinds.scan = kinds.scan + 1
            elseif id > 10000000 then kinds.invalid = kinds.invalid + 1
            elseif catalogText:find("\n" .. id .. "\t", 1, true) then kinds.catalog = kinds.catalog + 1
            else error("sample ID from nowhere: " .. id) end
        end
        ok(kinds.catalog >= 3 and kinds.scan >= 10 and kinds.invalid >= 2,
            string.format("catalog %d, scan list %d, no such item %d", kinds.catalog, kinds.scan, kinds.invalid))
        wow.advance(600)
        eq(GreenFangToolkitDevDB, nil, "nothing saved unless typed")
        eq(#G.requests, 0, "no requests")
        eq(SlashCmdList.GREENFANGTOOLKIT, nil, "the dev AddOn does not touch /gftk")
        -- The full scan is paused.
        slash("catalogscan full")
        wow.advance(30)
        eq(#G.requests, 0, "full: paused")
        eq(GreenFangToolkitDevDB, nil, "full: nothing saved")
        T.realPrint(string.format("     DEV GF-009-13: sample %d IDs (catalog %d, scan list %d, no such item %d); full list %d IDs, about %.0f minutes at 4 per second (paused)",
            #sample, kinds.catalog, kinds.scan, kinds.invalid, #list, #list / 4 / 60))
    end))

    test("GF-009-13 dev checks: the client's locale and build must match the list, and a saved run's too", done(function()
        local _, S = loadDev({ locale = "enUS" })
        ok(not S.start("sample"), "enUS: refused")
        eq(GreenFangToolkitDevDB, nil, "nothing saved")
        _, S = loadDev({ build = "71200" })
        ok(not S.start("sample"), "another build: refused")
        local text = wow.printed()[#wow.printed()]
        ok(text:find("1.60.1.71200", 1, true) and text:find("1.60.1.71139", 1, true), "says both builds: " .. text)
        -- A run saved by the right client, then the game updates: it stops after login.
        _, S = loadDev({})
        ok(S.start("sample"), "the right client starts")
        local sv = { catalogSample = copy(GreenFangToolkitDevDB.catalogSample) }
        _, S = loadDev({ saved = sv, build = "71300" })
        eq(GreenFangToolkitDevDB.catalogSample.running, false, "stopped after the update")
        wow.advance(120)
        eq(#G.requests, 0, "nothing asked by the new build")
        -- A saved run of another build cannot be continued by the list's build.
        sv.catalogSample.build = "1.60.1.70000"
        _, S = loadDev({ saved = sv })
        ok(not S.start("sample"), "an old run: reset first")
        S.reset()
        ok(S.start("sample"), "after reset")
    end))

    test("GF-009-13 dev sample: success, invalid ID (two kinds) and timeout; requests and events counted; report per ID", done(function()
        local OK, KNOWN, NOPE, GONE, SILENT = 600001, 600002, 600003, 600004, 600005
        local _, S = loadDev({ sample = pack({ OK, KNOWN, NOPE, GONE, SILENT }),
            server = { [OK] = item(1) }, fail = { [NOPE] = true }, exists = { [GONE] = false } })
        G.known[KNOWN] = item(2)
        slash("catalogscan sample")
        serve(2)
        wow.fire("GET_ITEM_INFO_RECEIVED", 123, true) -- someone else's item
        serve(120)
        local d = GreenFangToolkitDevDB.catalogSample
        ok(d and not d.running and d.finished, "finished: " .. S.statusText("sample"))
        eq(d.got[OK][1], "掃描物品1", "answered by the server")
        eq(d.got[KNOWN][1], "掃描物品2", "already in the client: no request")
        eq(d.invalid[NOPE], "answer", "the server said no such item")
        eq(d.invalid[GONE], "exist", "DoesItemExistByID said no: not even asked")
        eq(d.timeout[SILENT], 3, "no answer: timed out after 3 tries (the 2nd retry too: the queue's head had moved)")
        local c = d.counts
        eq(c.requests, 5, "requests: OK, NOPE, SILENT x3")
        eq(c.ours, 2, "answers for our IDs")
        ok(c.events >= 3, "every GET_ITEM_INFO_RECEIVED counted: " .. c.events)
        eq(c.success, 1, "success"); eq(c.failed, 1, "failed"); eq(c.invalid, 1, "invalid before asking")
        eq(c.timeouts, 3, "timeouts"); eq(c.retries, 2, "retries"); eq(c.known, 1, "known")
        eq(G.coldInfo, 2, "GetItemInfo for an item the client does not have: only the two retries (the other path)")
        eq(next(d.pending), nil, "nothing left waiting")
        local report = table.concat(S.report(), "\n")
        ok(report:find(OK .. "：成功", 1, true) and report:find(NOPE .. "：無效", 1, true)
            and report:find(GONE .. "：無效", 1, true) and report:find(SILENT .. "：逾時", 1, true), report)
        wow.clearPrinted()
        slash("catalogscan report")
        ok(#wow.printed() >= 6, "report lines in chat")
        local status = S.statusText("sample")
        ok(status:find("完成", 1, true) and status:find("請求 5 次", 1, true), status)
        -- Only item fields.
        local allowed = { v = 1, mode = 1, locale = 1, build = 1, list = 1, pos = 1, got = 1, invalid = 1, timeout = 1,
            pending = 1, running = 1, finished = 1, counts = 1 }
        for k in pairs(d) do ok(allowed[k], "only scan fields: " .. tostring(k)) end
        for _, r in pairs(d.got) do eq(#r, 7, "seven fields") end
        ok(not wow.serializeSV("GreenFangToolkitDevDB", GreenFangToolkitDevDB):find("Player%-"), "no GUIDs")
        slash("catalogscan reset")
        eq(GreenFangToolkitDevDB.catalogSample, nil, "reset forgets it")
    end))

    test("GF-009-13 dev worker: 4 per second, 8 waiting, combat / instance pause; waiting and retry IDs asked again after the next login", done(function()
        local ids, srv = {}, {}
        for i = 1, 40 do ids[i] = 700000 + i * 3; srv[ids[i]] = item(i) end
        local D, S = loadDev({ sample = pack(ids) })   -- the server says nothing yet
        slash("catalogscan sample")
        wow.advance(5)
        ok(#G.requests <= 8 and #G.requests >= 4, "8 waiting at most: " .. #G.requests)
        for i = 5, #G.requests do ok(G.requests[i].t - G.requests[i - 4].t >= 1 - 1e-6, "4 per second") end
        local n0 = #G.requests
        wow.enterCombat(); wow.advance(20); eq(#G.requests, n0, "nothing in combat"); wow.leaveCombat()
        G.instance = true; wow.advance(20); eq(#G.requests, n0, "nothing in an instance"); G.instance = false
        -- 30 s pass: the first ones time out and wait for a retry.
        wow.advance(12)
        local d = GreenFangToolkitDevDB.catalogSample
        local retrying, waiting = 0, count(d.pending)
        for _, tries in pairs(d.pending) do if tries >= 1 then retrying = retrying + 1 end end
        ok(retrying >= 1 and waiting >= 8, string.format("saved: %d waiting, %d of them for a retry", waiting, retrying))
        local pendingBefore = copy(d.pending)
        -- Log out now; the next login resumes a minute later, asking those first.
        local sv = copy(GreenFangToolkitDevDB)
        D, S = loadDev({ saved = sv, sample = pack(ids), server = srv })
        d = GreenFangToolkitDevDB.catalogSample
        ok(d.running, "still on after login")
        serve(30)
        eq(#G.requests, 0, "waits a minute after login")
        serve(40)
        local first = {}
        for i = 1, math.min(#G.requests, count(pendingBefore)) do first[G.requests[i].id] = true end
        for id in pairs(pendingBefore) do ok(first[id], "asked first after login: " .. id) end
        serve(60)
        d = GreenFangToolkitDevDB.catalogSample
        ok(not d.running and d.finished, "finished")
        eq(count(d.got), 40, "no ID lost across the login")
        eq(count(d.timeout) + count(d.invalid), 0, "none dropped")
        ok(d.counts.retries >= 1, "retries counted and kept: " .. d.counts.retries)
        -- Without IsItemDataCachedByID, GetItemInfo is the request (counted).
        D, S = loadDev({ sample = pack({ ids[1] }), server = srv, noCachedAPI = true })
        slash("catalogscan sample")
        serve(10)
        d = GreenFangToolkitDevDB.catalogSample
        ok(d.got[ids[1]], "found through GetItemInfo")
        eq(d.counts.requests, 1, "one request counted")
    end))

    test("GF-009-13 fix, Forever field result: RequestLoadItemDataByID answers with ITEM_DATA_LOAD_RESULT; other GET_ITEM_INFO_RECEIVED are noise", done(function()
        -- 0.16.4 in Forever: 0 successes; 56 requests for 20 IDs (each asked 3 times); 39 events, none ours.
        local ids, srv = {}, {}
        for i = 1, 20 do ids[i] = 800000 + i; if i ~= 20 then srv[ids[i]] = item(i) end end
        local _, S = loadDev({ sample = pack(ids), server = srv, forever = true })
        G.loadEvent, G.noise = true, true
        slash("catalogscan sample")
        serve(150)
        local d = GreenFangToolkitDevDB.catalogSample
        ok(not d.running and d.finished, "finished: " .. S.statusText("sample"))
        eq(count(d.got), 19, "every item the server knows: " .. S.statusText("sample"))
        eq(count(d.timeout), 1, "the one it does not know times out")
        ok(d.counts.loads >= 19, "ITEM_DATA_LOAD_RESULT counted: " .. tostring(d.counts.loads))
        ok(d.counts.events > 0, "the other events counted too")
        eq(d.counts.ours, 19, "the load answers matched our IDs")
        ok(d.counts.requests <= 20 + 2, "no triple asking: " .. d.counts.requests)
        ok(S.statusText("sample"):find("載入事件", 1, true), "the status line shows both kinds")
    end))

    test("GF-009-13 fix: a load with no event at all, and a client whose load path is silent: polling and the GetItemInfo retry still find them", done(function()
        local ids, srv = {}, {}
        for i = 1, 6 do ids[i] = 810000 + i; srv[ids[i]] = item(i) end
        -- The data arrives in the cache, no event: found by polling, no retry.
        local _, S = loadDev({ sample = pack(ids), server = srv, forever = true })
        G.loadEvent, G.silentLoad = true, true
        slash("catalogscan sample")
        serve(20)
        local d = GreenFangToolkitDevDB.catalogSample
        eq(count(d.got), 6, "found by polling: " .. S.statusText("sample"))
        eq(d.counts.polled, 6, "polled"); eq(d.counts.retries, 0, "no retry needed")
        -- RequestLoadItemDataByID does nothing on this client: the retry asks GetItemInfo.
        _, S = loadDev({ sample = pack(ids), server = srv, forever = true })
        C_Item.RequestLoadItemDataByID = function() end
        slash("catalogscan sample")
        serve(80)
        d = GreenFangToolkitDevDB.catalogSample
        eq(count(d.got), 6, "found through GetItemInfo on the retry: " .. S.statusText("sample"))
        eq(d.counts.viaInfo, 6, "asked once through GetItemInfo each")
        eq(count(d.timeout), 0, "no timeouts left")
    end))

    test("GF-009-13 fix, the owner's probe: C_Item.GetItemInfo's 18 values (16th nil, |cnIQ1: link), global GetItemInfo empty; a cached cloth and a cold one both succeed", done(function()
        local LINEN, COLD = 2589, 14047
        local _, S = loadDev({ sample = pack({ LINEN, COLD, 99999999 }), forever = true,
            server = { [COLD] = { name = "符文布", classID = 7, sub = 5, quality = 1, ilvl = 50 } }, fail = { [99999999] = true } })
        G.loadEvent, G.noise = true, true
        G.known[LINEN] = { name = "亞麻布", classID = 7, sub = 5, quality = 1, ilvl = 5, icon = 132889 }
        slash("catalogscan sample")
        serve(10)
        local d = GreenFangToolkitDevDB.catalogSample
        ok(not d.running and d.finished, "finished: " .. S.statusText("sample"))
        eq(d.got[LINEN] and d.got[LINEN][1], "亞麻布", "the cached cloth, no request")
        eq(table.concat(d.got[LINEN], ","), "亞麻布,7,5,0,1,5,132889", "the seven fields in the classic order")
        eq(d.got[COLD] and d.got[COLD][1], "符文布", "the cold one, answered by ITEM_DATA_LOAD_RESULT")
        eq(d.invalid[99999999], "answer", "the missing ID: a failed load result, not a timeout")
        eq(count(d.timeout), 0, "no timeouts")
        eq(d.counts.requests, 2, "one request each for the two not cached")
    end))
end
