-- Offline tests for GreenFangToolkit. Run from the repo root with Lua 5.1/LuaJIT:
--   lua tests/addon/run.lua            run all tests
--   lua tests/addon/run.lua --fixture  also (re)write tests/fixtures/GreenFangToolkit.sample.lua

local ROOT = GF_ROOT or "."
local ADDON_DIR = ROOT .. "/addon/GreenFangToolkit"
local FIXTURE = ROOT .. "/tests/fixtures/GreenFangToolkit.sample.lua"
package.path = ROOT .. "/tests/addon/?.lua;" .. package.path

local realPrint = print
local wow = require("mock")
local WRITE_FIXTURE = GF_WRITE_FIXTURE
for _, a in ipairs(arg or {}) do if a == "--fixture" then WRITE_FIXTURE = true end end

---------------------------------------------------------------------------
-- Tiny test framework
---------------------------------------------------------------------------

local tests, failures = {}, {}
-- GF_ONLY (run_lupa.py --only TEXT): run only the tests whose name has TEXT.
local function test(name, fn)
    if GF_ONLY and GF_ONLY ~= "" and not name:find(GF_ONLY, 1, true) then return end
    tests[#tests + 1] = { name = name, fn = fn }
end

local function fmt(v) return type(v) == "string" and string.format("%q", v) or tostring(v) end
local function eq(actual, expected, what)
    if actual ~= expected then
        error((what or "value") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end
local function ok(cond, what) if not cond then error(what or "assertion failed", 2) end end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deepCopy(x) end
    return o
end
local function deepEq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Every key anywhere inside t (used to prove zone/online never reach the outbox).
local function allKeys(t, acc)
    acc = acc or {}
    for k, v in pairs(t) do
        acc[k] = true
        if type(v) == "table" then allKeys(v, acc) end
    end
    return acc
end
-- Keys anywhere in the outbox, leaving out payload.location of character.self
-- (D-009), member.report (D-011) and member.share (D-014): the only places a
-- zone may appear.
local function outboxKeys(list)
    local acc = {}
    for _, e in ipairs(list) do
        if type(e) == "table" then
            for k, v in pairs(e) do
                acc[k] = true
                if k == "payload" and type(v) == "table" then
                    for pk, pv in pairs(v) do
                        if not ((e.kind == "character.self" or e.kind == "member.report" or e.kind == "member.share")
                            and pk == "location") then
                            acc[pk] = true
                            if type(pv) == "table" then allKeys(pv, acc) end
                        end
                    end
                elseif type(v) == "table" then
                    allKeys(v, acc)
                end
            end
        end
    end
    return acc
end
local function allStrings(t, acc)
    acc = acc or {}
    for _, v in pairs(t) do
        if type(v) == "string" then acc[#acc + 1] = v
        elseif type(v) == "table" then allStrings(v, acc) end
    end
    return acc
end

local function outbox() return GreenFangToolkitDB.sync.outbox end
local function entriesOf(kind)
    local r = {}
    for _, e in ipairs(outbox()) do if e.kind == kind then r[#r + 1] = e end end
    return r
end
local function printedContains(text)
    for _, line in ipairs(wow.printed()) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function legacyDB()
    return {
        version = 3, guild = "綠皮與獠牙冒險事務所", realm = "測試伺服器",
        capturedAt = 1763000000, capturedAtUTC = "2025-11-13T02:13:20Z",
        capturedAtLocal = "2025-11-13 10:13:20", total = 2, online = 1,
        settings = { sortKey = "level", sortAscending = false, minimapAngle = 123,
            minimapLayoutVersion = 2 },
        members = {
            { name = "測試乙-測試伺服器", race = "獸人", raceID = 2, raceSource = "guild",
              class = "戰士", classToken = "WARRIOR", professions = { "鍛造", "採礦" },
              professionSource = "guild", level = 58, zone = "奧格瑪", online = true,
              guildRank = "會長", guid = "Player-0000-0000000B" },
            { name = "測試戊-測試伺服器", race = "食人妖", raceID = 8, raceSource = "guild",
              class = "薩滿", classToken = "SHAMAN", professions = { "草藥學" },
              professionSource = "cached", level = 40, zone = "", online = false,
              guildRank = "會員", guid = "Player-0000-0000000E" },
        },
    }
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

test("fresh install creates schema v2 defaults", function()
    wow.reset()
    wow.loadAddon(ADDON_DIR)
    local db = GreenFangToolkitDB
    eq(db.schema, "gf.toolkit", "schema")
    eq(db.schemaVersion, 2, "schemaVersion")
    eq(db.addonVersion, "0.16.6", "addonVersion")
    eq(db.sync.enabled, true, "sync.enabled default")
    eq(db.sync.noticeShown, false, "noticeShown before login")
    eq(#db.sync.outbox, 0, "outbox empty")
    eq(db.settings.minimapAngle, 215, "default minimap angle")
end)

test("version comes from the TOC metadata (GF-001-D16)", function()
    local f = assert(io.open(ADDON_DIR .. "/GreenFangToolkit.toc", "rb"))
    local toc = f:read("*a"); f:close()
    local v = toc:match("## Version:%s*([^\r\n]+)")
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    eq(ns.VERSION, v, "ns.VERSION equals the TOC Version")
    eq(GreenFangToolkitDB.addonVersion, v, "addonVersion equals the TOC Version")
    wow.reset({ noMetadata = true })
    ns = wow.loadAddon(ADDON_DIR)
    eq(ns.VERSION, "dev", "no metadata API: dev, no error")
end)

test("TOC declares the agreed names and loads every file", function()
    local f = assert(io.open(ADDON_DIR .. "/GreenFangToolkit.toc", "rb"))
    local toc = f:read("*a"); f:close()
    ok(toc:find("## Interface: 16001", 1, true), "Interface")
    ok(toc:find("## Title: 綠皮冒險工具箱", 1, true), "Title")
    ok(toc:find("## Author: 綠皮與獠牙冒險事務所", 1, true), "Author")
    ok(toc:find("## Version: 0.16.6", 1, true), "Version")
    ok(toc:find("## SavedVariables: GreenFangToolkitDB\r?\n"), "SavedVariables")
    local listed = {}
    for line in toc:gmatch("[^\r\n]+") do
        if not line:find("^##") and line:find("%.lua$") then listed[#listed + 1] = line end
    end
    eq(table.concat(listed, ","), table.concat(wow.TOC_FILES, ","), "TOC file order matches test loader")
end)

test("first login prints the one-line notice once, no window", function()
    wow.reset()
    wow.login(ADDON_DIR)
    ok(printedContains("會分享你的等級、職業、專業、配方和所在地"), "notice printed")
    eq(GreenFangToolkitDB.sync.noticeShown, true, "noticeShown")
    eq(_G.GreenFangToolkit_MainWindow, nil, "main window not created at login")
    local saved = wow.logout()
    wow.reset()
    wow.login(ADDON_DIR, saved)
    ok(not printedContains("會分享你的等級"), "notice not repeated on next login")
end)

test("character.self has level, class, race and detailed professions", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local list = entriesOf("character.self")
    eq(#list, 1, "one character.self")
    local e = list[1]
    eq(e.id, "Player-0000-0000000A:" .. e.capturedAt .. ":character.self", "id format")
    eq(e.game.world, "forever", "game.world")
    eq(e.game.interface, 16001, "game.interface")
    eq(e.game.realm, "測試伺服器", "game.realm")
    eq(e.game.locale, "zhTW", "game.locale")
    eq(e.uploader.guid, "Player-0000-0000000A", "uploader.guid")
    eq(e.uploader.name, "測試甲", "uploader.name")
    eq(e.uploader.faction, "Horde", "uploader.faction")
    eq(e.uploader.guild, "綠皮與獠牙冒險事務所", "uploader.guild")
    eq(e.uploader.guildRank, "會員", "uploader.guildRank")
    local p = e.payload
    eq(p.level, 32, "level"); eq(p.class, "德魯伊", "class"); eq(p.classToken, "DRUID", "classToken")
    eq(p.race, "牛頭人", "race"); eq(p.raceID, 6, "raceID")
    eq(#p.professions, 4, "professions incl. fishing/cooking")
    eq(p.professions[1].name, "製皮", "prof name")
    eq(p.professions[1].skillLineID, 165, "skillLineID")
    eq(p.professions[1].rank, 151, "rank")
    eq(p.professions[1].max, 225, "max")
end)

test("roster.snapshot written for a complete roster, without zone/online", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local list = entriesOf("roster.snapshot")
    eq(#list, 1, "one roster.snapshot")
    local e = list[1]
    eq(e.payload.total, 4, "total")
    eq(#e.payload.members, 4, "members")
    local keys = outboxKeys(outbox())
    ok(not keys.zone, "no zone anywhere in outbox (outside character.self location)")
    ok(not keys.online, "no online anywhere in outbox")
    for _, s in ipairs(allStrings(GreenFangToolkitDB)) do
        ok(s ~= "公開備註" and s ~= "幹部備註", "guild notes never stored")
    end
    local byName = {}
    for _, m in ipairs(e.payload.members) do byName[m.name] = m end
    local b = byName["測試乙-測試伺服器"]
    eq(b.race, "獸人", "race from club"); eq(b.raceID, 2, "raceID from club")
    eq(table.concat(b.professions, ","), "鍛造,採礦", "club professions by ID")
    eq(b.guildRank, "會長", "guildRank")
    local a = byName["測試甲-測試伺服器"]
    eq(a.professionSource, "self", "own professions used for self")
    eq(table.concat(a.professions, ","), "製皮,剝皮", "only primary professions in roster")
    eq(a.race, "牛頭人", "own race")
    eq(byName["測試丁-測試伺服器"].race, "食人妖", "race via GetPlayerInfoByGUID")
    -- The in-game display snapshot still has zone/online.
    local snap = GreenFangToolkitDB.roster.snapshots["測試伺服器|綠皮與獠牙冒險事務所"]
    ok(snap, "display snapshot stored by realm|guild")
    local shown
    for _, m in ipairs(snap.members) do if m.name == "測試乙-測試伺服器" then shown = m end end
    eq(shown.zone, "奧格瑪", "display keeps zone")
    eq(shown.online, true, "display keeps online")
end)

test("one entry per character and per guild across logins and rescans", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local firstSelf = entriesOf("character.self")[1].id
    wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
    wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
    eq(#entriesOf("roster.snapshot"), 1, "still one roster.snapshot after rescans")
    local saved = wow.logout()
    wow.reset({ now = 1763380000 })
    wow.login(ADDON_DIR, saved)
    local selfs = entriesOf("character.self")
    eq(#selfs, 1, "still one character.self after second login")
    ok(selfs[1].id ~= firstSelf, "login always writes a fresh character.self")
    eq(#entriesOf("roster.snapshot"), 1, "still one roster.snapshot after second login")
    eq(entriesOf("roster.snapshot")[1].capturedAt, 1763380005, "roster snapshot replaced by newer")
    -- An alt in the same guild replaces nothing of the first character.
    saved = wow.logout()
    local alt = wow.defaultPlayer()
    alt.guid, alt.name = "Player-0000-0000000F", "測試己"
    local roster = wow.defaultRoster() -- the alt is in the guild's roster too
    roster[#roster + 1] = { name = "測試己-測試伺服器", rank = "會員", level = 10, class = "戰士",
        classToken = "WARRIOR", zone = "奧格瑪", online = true, guid = alt.guid }
    wow.reset({ now = 1763390000, player = alt, roster = roster })
    wow.login(ADDON_DIR, saved)
    eq(#entriesOf("character.self"), 2, "two characters -> two character.self")
    eq(#entriesOf("roster.snapshot"), 1, "same guild -> one roster.snapshot")
    eq(entriesOf("roster.snapshot")[1].uploader.guid, "Player-0000-0000000F", "latest scanner wins")
end)

test("unchanged character data is not re-queued, changes are", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local id = entriesOf("character.self")[1].id
    wow.advance(30)
    wow.fire("SKILL_LINES_CHANGED"); wow.advance(3)
    eq(entriesOf("character.self")[1].id, id, "no new entry when nothing changed")
    wow.state.player.professions[1][3] = 152
    wow.fire("SKILL_LINES_CHANGED"); wow.advance(3)
    local e = entriesOf("character.self")
    eq(#e, 1, "still one entry")
    ok(e[1].id ~= id, "new entry after skill up")
    eq(e[1].payload.professions[1].rank, 152, "new rank")
    wow.state.player.level = 33
    wow.fire("PLAYER_LEVEL_UP", 33); wow.advance(3)
    eq(entriesOf("character.self")[1].payload.level, 33, "level up recorded")
end)

test("outbox is capped (150 + 50 for a small guild), oldest dropped", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    eq(ns.Sync.outboxCap(), 200, "small guild: 200 in all")
    for i = 1, 210 do
        wow.state.now = wow.state.now + 60
        wow.state.player.guid = string.format("Player-0000-%08X", 0x100 + i)
        ns.Sync.recordSelf(true)
    end
    eq(#outbox(), 200, "capped at 200")
    local oldest = math.huge
    for _, e in ipairs(outbox()) do if e.capturedAt < oldest then oldest = e.capturedAt end end
    ok(oldest > 1763370010, "the earliest entries were dropped")
    local seen = {}
    for _, e in ipairs(outbox()) do ok(not seen[e.id], "ids unique"); seen[e.id] = true end
end)

test("incomplete roster keeps the previous report and writes nothing", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local before = entriesOf("roster.snapshot")[1].id
    wow.state.missingRow = 3
    wow.state.now = wow.state.now + 100
    wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(2)
    eq(entriesOf("roster.snapshot")[1].id, before, "outbox untouched")
    eq(#GreenFangToolkitDB.roster.snapshots["測試伺服器|綠皮與獠牙冒險事務所"].members, 4,
        "display snapshot untouched")
end)

test("nothing is scanned or written during combat; catches up afterwards", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    wow.setCombat(true)
    wow.fire("PLAYER_LOGIN")
    wow.advance(10)
    wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(2)
    wow.fire("SKILL_LINES_CHANGED"); wow.advance(3)
    eq(#outbox(), 0, "no outbox writes in combat")
    eq(ns.Roster.current(), nil, "no snapshot in combat")
    wow.fire("PLAYER_LOGOUT")
    eq(#outbox(), 0, "no write at logout during combat")
    wow.setCombat(false)
    wow.fire("PLAYER_REGEN_ENABLED"); wow.advance(3)
    eq(#entriesOf("character.self"), 1, "character.self after combat")
    eq(#entriesOf("roster.snapshot"), 1, "roster.snapshot after combat")
end)

test("/gftk sync shows the status and opens the diag window; on/off are gone (D-015)", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local n = #outbox()
    ok(n > 0, "outbox filled")
    wow.clearPrinted()
    SlashCmdList.GREENFANGTOOLKIT("sync status")
    ok(printedContains("待上傳 " .. n .. " 筆"), "status printed")
    ok(ns.Diag.isShown(), "diag window opened")
    SlashCmdList.GREENFANGTOOLKIT("sync off")
    eq(GreenFangToolkitDB.sync.enabled, true, "no way to switch off")
    eq(#outbox(), n, "outbox untouched")
    eq(ns.Sync.setEnabled, nil, "no setEnabled")
    eq(ns.Sync.turnOff, nil, "no turnOff")
end)

test("/gf and /綠皮 open the window; unknown shows help", function()
    wow.reset()
    wow.login(ADDON_DIR)
    eq(SLASH_GREENFANGTOOLKIT1, "/gftk", "slash 1")
    eq(SLASH_GREENFANGTOOLKIT2, "/綠皮", "slash 2")
    SlashCmdList.GREENFANGTOOLKIT("")
    ok(_G.GreenFangToolkit_MainWindow and _G.GreenFangToolkit_MainWindow:IsShown(), "window shown")
    SlashCmdList.GREENFANGTOOLKIT("")
    ok(not _G.GreenFangToolkit_MainWindow:IsShown(), "window toggled off")
    wow.clearPrinted()
    SlashCmdList.GREENFANGTOOLKIT("whatever")
    ok(printedContains("/gftk sync：查看同步狀態"), "help shown")
end)

test("migration copies settings and last snapshot, leaves GFGuildRosterDB intact", function()
    wow.reset()
    local legacy = legacyDB()
    local pristine = deepCopy(legacy)
    local ns = wow.loadAddon(ADDON_DIR, { GFGuildRosterDB = legacy })
    local db = GreenFangToolkitDB
    eq(db.settings.sortKey, "level", "sortKey migrated")
    eq(db.settings.sortAscending, false, "sortAscending migrated")
    eq(db.settings.minimapAngle, 123, "minimap angle migrated")
    eq(ns.UI.sortKey, "level", "UI picks up migrated sort")
    local snap = db.roster.snapshots["測試伺服器|綠皮與獠牙冒險事務所"]
    ok(snap, "snapshot migrated")
    eq(#snap.members, 2, "members migrated")
    eq(snap.capturedAt, 1763000000, "capturedAt kept")
    eq(snap.members[1].guid, "Player-0000-0000000B", "guid kept")
    eq(db.migration.from, "GFGuildRosterDB", "migration recorded")
    ok(deepEq(GFGuildRosterDB, pristine), "legacy table unchanged")
    ok(GFGuildRosterDB == legacy, "legacy table not replaced")
    -- A cached member from the old snapshot fills gaps in the next scan.
    wow.state.roster[#wow.state.roster + 1] = { name = "測試戊-測試伺服器", rank = "會員", level = 41,
        class = "薩滿", classToken = "SHAMAN", zone = "", online = false, guid = "Player-0000-0000000E" }
    wow.fire("PLAYER_LOGIN"); wow.advance(10)
    local e
    for _, m in ipairs(entriesOf("roster.snapshot")[1].payload.members) do
        if m.name == "測試戊-測試伺服器" then e = m end
    end
    eq(e.race, "食人妖", "cached race from migrated snapshot")
    eq(e.professionSource, "cached", "cached professions from migrated snapshot")
    eq(e.level, 41, "fresh level")
end)

test("migration runs only once and never overrides v2 data", function()
    wow.reset()
    wow.login(ADDON_DIR, { GFGuildRosterDB = legacyDB() })
    GreenFangToolkitDB.settings.sortKey = "name"
    local saved = wow.logout()
    saved.GFGuildRosterDB.settings.sortKey = "zone"
    wow.reset({ now = 1763380000 })
    wow.login(ADDON_DIR, saved)
    eq(GreenFangToolkitDB.settings.sortKey, "name", "v2 setting kept")
end)

test("migration waits until GFGuildRosterDB is available (PLAYER_LOGIN)", function()
    wow.reset()
    wow.loadAddon(ADDON_DIR)
    eq(GreenFangToolkitDB.migration, nil, "nothing to migrate at ADDON_LOADED")
    GFGuildRosterDB = legacyDB() -- GFGuildRoster loaded after us
    wow.fire("PLAYER_LOGIN"); wow.advance(10)
    eq(GreenFangToolkitDB.migration.from, "GFGuildRosterDB", "migrated at login")
    eq(GreenFangToolkitDB.settings.sortKey, "level", "settings migrated at login")
end)

test("no legacy table: no migration record, normal start", function()
    wow.reset()
    wow.login(ADDON_DIR)
    eq(GreenFangToolkitDB.migration, nil, "no migration record")
    eq(GFGuildRosterDB, nil, "legacy table not created")
end)

test("unknown fields in an existing v2 table are preserved", function()
    wow.reset()
    wow.login(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2, addonVersion = "0.3.9",
        futureModule = { keep = true },
        sync = { enabled = false, noticeShown = true, outbox = {} },
    } })
    eq(GreenFangToolkitDB.futureModule.keep, true, "unknown field kept")
    eq(GreenFangToolkitDB.addonVersion, "0.16.6", "addonVersion updated")
    eq(GreenFangToolkitDB.sync.enabled, true, "old off ignored (D-015)")
end)

test("fallback to the skill list when GetProfessions is missing", function()
    wow.reset({ noProfessionsAPI = true, skillLines = {
        { name = "專業技能", header = true },
        { name = "採礦", rank = 120, max = 150 },
        { name = "鍛造", rank = 110, max = 150 },
        { name = "防禦", rank = 160, max = 160 },
    } })
    wow.login(ADDON_DIR)
    local p = entriesOf("character.self")[1].payload.professions
    eq(#p, 2, "only professions taken from skill list")
    eq(p[1].name, "採礦"); eq(p[1].skillLineID, 186, "skillLineID from name"); eq(p[1].rank, 120)
end)

test("no guild: nothing is synced (GF-001-D4)", function()
    wow.reset({ inGuild = false })
    wow.login(ADDON_DIR)
    wow.advance(60) -- past the 30 s guild wait (GF-001-D3)
    wow.fire("PLAYER_LOGOUT")
    eq(#entriesOf("roster.snapshot"), 0, "no roster")
    eq(#entriesOf("character.self"), 0, "no character.self for a guildless character")
end)

test("sorting and search match v0.3.1 behaviour", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local members = ns.Roster.current().members
    local list = ns.UI.sortMembers(ns.UI.filterMembers(members, ""), "level", false)
    eq(list[1].level, 60, "level desc first"); eq(list[4].level, 12, "level desc last")
    list = ns.UI.sortMembers(ns.UI.filterMembers(members, ""), "online", false)
    eq(list[1].online, true, "online first")
    eq(#ns.UI.filterMembers(members, "鍛造"), 1, "search professions")
    eq(#ns.UI.filterMembers(members, "幽暗城"), 1, "search zone")
    eq(#ns.UI.filterMembers(members, "不存在"), 0, "no match")
    members[1].race = ""
    list = ns.UI.sortMembers(ns.UI.filterMembers(members, ""), "race", true)
    eq(list[4].race, "", "missing race sorts last ascending")
    list = ns.UI.sortMembers(ns.UI.filterMembers(members, ""), "race", false)
    eq(list[4].race, "", "missing race sorts last descending")
end)

test("TSV/JSON export keep the v0.3.1 format", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local s = ns.Roster.current()
    local json = ns.Export.jsonParts(s)
    eq(#json, 1, "one part")
    ok(json[1]:find('^{"schema":"gfguildroster.report","schemaVersion":1,"addonVersion":"0.16.6"'), "json header")
    ok(json[1]:find('"part":1,"partCount":1', 1, true), "parts")
    ok(json[1]:find('"onlineAtCapture":true', 1, true), "member online in manual export")
    ok(not json[1]:find('"guid":', 1, true), "no guid in v1 export")
    local tsv = ns.Export.tsvParts(s)
    ok(tsv[1]:find("^角色\t種族\t職業\t專業技能\t等級\t位置\t掃描時狀態\t掃描時間（本機）\n"), "tsv header")
    eq(select(2, tsv[1]:gsub("\n", "")), 4, "4 member lines")
    eq(ns.Export.jsonString('a"b\\c\n\1'), '"a\\"b\\\\c\\n\\u0001"', "json escaping")
    -- Large roster splits into several parts, each valid on its own.
    for i = 1, 400 do
        s.members[#s.members + 1] = { name = "填充" .. i .. "-測試伺服器", race = "獸人", class = "戰士",
            classToken = "WARRIOR", professions = { "採礦" }, level = 10, zone = "杜洛塔", online = false,
            guildRank = "會員" }
    end
    json = ns.Export.jsonParts(s)
    ok(#json > 1, "split into parts")
    for i, part in ipairs(json) do
        ok(#part <= ns.Export.PART_LIMIT + 400, "part " .. i .. " size")
        ok(part:find('"partCount":' .. #json, 1, true), "partCount in every part")
    end
end)

test("SavedVariables survive a write/read round trip in client format", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local saved = wow.logout()
    local text = wow.serializeSV("GreenFangToolkitDB", saved.GreenFangToolkitDB)
    local env = {}
    local chunk = assert(loadstring(text))
    setfenv(chunk, env)
    chunk()
    ok(deepEq(env.GreenFangToolkitDB, saved.GreenFangToolkitDB), "round trip equal")
end)

---------------------------------------------------------------------------
-- GF-000-A framework
---------------------------------------------------------------------------

-- GF-UI-E: the entries shown on the left (keys), in order.
local function shownNav(ns)
    local ids = {}
    for _, b in ipairs(ns.Framework.navButtons()) do
        if b:IsShown() then ids[#ids + 1] = b.entryKey end
    end
    return table.concat(ids, ",")
end

test("framework: roster is the first module; no settings page", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local ids = {}
    for _, def in ipairs(ns.Framework.availableModules()) do ids[#ids + 1] = def.id end
    eq(ids[1], "roster", "roster first")
    eq(ns.Framework.get("settings"), nil, "no settings page (D-015)")
    SlashCmdList.GREENFANGTOOLKIT("")
    eq(ns.Framework.current(), "roster", "opens roster by default")
    -- GF-UI-B: the guild name in the title (it left the page).
    eq(_G.GreenFangToolkit_MainWindow.TitleText:GetText(), "綠皮冒險工具箱｜職工名冊｜綠皮與獠牙冒險事務所", "title")
    ok(ns.Framework.panel("roster"):IsShown(), "roster panel shown")
end)

test("framework: unavailable or broken modules are hidden", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    local built = false
    ns.Framework.register({ id = "soon", title = "即將推出", order = 50,
        available = function() return false end, create = function() built = true end })
    ns.Framework.register({ id = "broken", title = "壞掉", order = 60,
        available = function() error("boom") end })
    ns.Framework.register({ id = "crash", title = "建置失敗", order = 70,
        create = function() error("build failed") end })
    wow.fire("PLAYER_LOGIN"); wow.advance(10)
    SlashCmdList.GREENFANGTOOLKIT("")
    eq(shownNav(ns), "profile,directory,crafting,logistics,adventure,handbook,page:crash", "only available modules listed")
    SlashCmdList.GREENFANGTOOLKIT("soon")
    eq(ns.Framework.current(), "roster", "hidden module cannot be opened; falls back")
    eq(built, false, "hidden module never built")
    wow.clearPrinted()
    ns.Framework.select("crash")
    ok(printedContains("模組「建置失敗」載入失敗"), "build error reported in chat, no Lua error")
    eq(ns.Framework.current(), "crash", "window still works")
end)

test("framework: switching modules, remembering the last one", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("")
    local charButton
    for _, b in ipairs(ns.Framework.navButtons()) do
        if b.moduleId == "character" then charButton = b end
    end
    charButton:GetScript("OnClick")(charButton)
    eq(ns.Framework.current(), "character", "character selected")
    ok(not ns.Framework.panel("roster"):IsShown(), "roster hidden")
    ok(ns.Framework.panel("character"):IsShown(), "character shown")
    eq(GreenFangToolkitDB.settings.lastModule, "character", "remembered")
    SlashCmdList.GREENFANGTOOLKIT("")
    ok(not ns.Framework.isShown(), "toggle closes")
    local saved = wow.logout()
    wow.reset({ now = 1763380000 })
    ns = wow.login(ADDON_DIR, saved)
    SlashCmdList.GREENFANGTOOLKIT("")
    eq(ns.Framework.current(), "character", "reopens last module after relog")
    SlashCmdList.GREENFANGTOOLKIT("roster")
    eq(ns.Framework.current(), "roster", "/gf roster opens roster")
    ok(ns.Framework.isShown(), "window open")
end)

test("framework: minimap button is the single entry and opens the window", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local b = _G.GreenFangToolkit_MinimapButton
    ok(b, "minimap button")
    ok(not ns.Framework.isShown(), "nothing opens by itself at login")
    b:GetScript("OnClick")(b, "LeftButton")
    ok(ns.Framework.isShown(), "left click opens")
    GreenFangToolkitDB.settings.minimapAngle = 10
    b:GetScript("OnClick")(b, "RightButton")
    eq(GreenFangToolkitDB.settings.minimapAngle, 215, "right click resets")
end)

test("framework: per-character module state", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ns.Framework.charState("demo").step = 3
    local saved = wow.logout()
    local alt = wow.defaultPlayer()
    alt.guid, alt.name = "Player-0000-0000000F", "測試己"
    wow.reset({ now = 1763380000, player = alt })
    ns = wow.login(ADDON_DIR, saved)
    eq(ns.Framework.charState("demo").step, nil, "alt has its own state")
    ns.Framework.charState("demo").step = 1
    saved = wow.logout()
    wow.reset({ now = 1763390000 })
    ns = wow.login(ADDON_DIR, saved)
    eq(ns.Framework.charState("demo").step, 3, "first character keeps its step")
    ok(GreenFangToolkitDB.settings.modules.demo.characters["Player-0000-0000000F"], "stored under settings.modules")
    eq(GreenFangToolkitDB.sync.outbox[1].kind ~= nil, true, "sync block untouched")
end)

---------------------------------------------------------------------------
-- GF-008-A sleeping bag route
---------------------------------------------------------------------------

test("sleepingbag: Horde route data is complete and marked unverified", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    local route = ns.SleepingBagRoutes.Horde
    ok(route and #route.steps >= 8, "route has steps")
    local first3 = {}
    for _, st in ipairs(route.steps) do
        ok(type(st.id) == "string" and st.id ~= "", "id")
        ok(st.zone and st.landmark and st.action and st.travel and st.guards
            and st.noFlightPath and st.rpgHint, "required fields on " .. st.id)
        eq(st.verified, false, "unverified: " .. st.id)
        ok(st.questID == nil, "no quest IDs yet")
        if st.round == 1 and st.x and not st.approx then first3[#first3 + 1] = st.zone end -- GF-008-C: the guide's coordinates
    end
    eq(table.concat(first3, ">"), "貧瘠之地>西部荒野", "round-1 stops with coordinates start Barrens then Westfall")
    eq(route.steps[5].zone, "石爪山脈", "third stop is Stonetalon")
end)

test("sleepingbag: module visible for Horde, hidden for Alliance", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("")
    eq(shownNav(ns), "profile,directory,crafting,logistics,adventure,handbook", "Horde sees the route")
    local alliance = wow.defaultPlayer()
    alliance.faction = "Alliance"
    wow.reset({ player = alliance })
    ns = wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("")
    eq(shownNav(ns), "profile,directory,crafting,logistics,adventure", "Alliance has no route yet (冒險指南 hidden)")
end)

test("sleepingbag: RPG hides coordinates until revealed; normal shows all", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("sleepingbag")
    local SB = ns.SleepingBag
    eq(SB.state().mode, "rpg", "RPG by default")
    local text = SB.pageText("rpg") -- GF-008-B: the page shows normal mode; the RPG text still exists
    ok(text:find("南貧瘠之地", 1, true), "landmark shown")
    ok(not text:find("46, 74", 1, true), "coordinates hidden in RPG")
    ok(text:find("待實地驗證", 1, true), "unverified tag")
    SB.reveal()
    ok(SB.pageText():find("貧瘠之地（46, 74）", 1, true), "coordinates after reveal")
    SB.setMode("normal")
    text = SB.pageText()
    ok(text:find("【全部步驟】", 1, true), "full list in normal mode")
    ok(text:find("西部荒野（37, 50）", 1, true), "other steps' coordinates listed")
    ok(text:find("地圖不標位置", 1, true), "GF-008-C: a step without a pin says why")
    ok(text:find("沒有飛行點時", 1, true), "alternative route shown")
end)

test("sleepingbag: modes share progress per character and survive relog", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local SB = ns.SleepingBag
    SB.complete(); SB.complete()
    eq(SB.state().step, 3, "two steps done in RPG")
    SB.setMode("normal")
    eq(SB.state().step, 3, "same progress in normal mode")
    ok(SB.pageText():find("＞ 3.", 1, true), "current step marked")
    ok(SB.pageText():find("完成 1.", 1, true), "done step marked")
    local saved = wow.logout()
    wow.reset({ now = 1763380000 })
    ns = wow.login(ADDON_DIR, saved)
    SB = ns.SleepingBag
    eq(SB.state().step, 3, "progress kept after relog")
    eq(SB.state().mode, "normal", "mode kept after relog")
    -- Another character starts from scratch.
    saved = wow.logout()
    local alt = wow.defaultPlayer()
    alt.guid = "Player-0000-0000000F"
    wow.reset({ now = 1763390000, player = alt })
    ns = wow.login(ADDON_DIR, saved)
    eq(ns.SleepingBag.state().step, 1, "alt has own progress")
    eq(ns.SleepingBag.state().mode, "rpg", "alt has own mode")
end)

test("sleepingbag: back, finish and reset", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local SB = ns.SleepingBag
    eq(SB.back(), false, "cannot go before step 1")
    local n = #SB.route().steps
    for _ = 1, n do ok(SB.complete(), "complete") end
    ok(SB.isFinished(), "finished")
    eq(SB.complete(), false, "nothing left")
    ok(SB.pageText():find("舒適睡袋", 1, true), "reward shown")
    ok(SB.back(), "back from finished")
    eq(SB.state().step, n, "on last step again")
    SB.reset()
    eq(SB.state().step, 1, "reset")
    eq(next(SB.state().completedAt), nil, "completion times cleared")
    for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do
        ok(not allKeys(e).step, "route progress never enters the outbox")
    end
end)

test("sleepingbag: window page builds and refreshes", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("sleepingbag")
    eq(ns.Framework.current(), "sleepingbag", "opened")
    eq(_G.GreenFangToolkit_MainWindow.TitleText:GetText(), "綠皮冒險工具箱｜冒險指南", "title")
    ns.SleepingBag.toggleMode()
    eq(ns.SleepingBag.state().mode, "normal", "toggle")
end)

---------------------------------------------------------------------------
-- GF-000-B sync status without slash commands
---------------------------------------------------------------------------

local function noCommand(text, what)
    ok(not text:find("/gf", 1, true), what .. " mentions /gf: " .. text)
    ok(not text:find("/reload", 1, true), what .. " mentions /reload: " .. text)
end

test("sync status: player-facing text never mentions commands", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    noCommand(ns.Sync.NOTICE, "NOTICE")
    noCommand(ns.UI.syncLine(), "syncLine")
    noCommand(ns.Sync.statusText(), "statusText")
    noCommand(ns.Sync.shortStatus(), "shortStatus")
    SlashCmdList.GREENFANGTOOLKIT("roster")
    ns.Framework.select("sleepingbag")
    ns.Framework.select("recipes")
    ns.Framework.select("character")
    for _, t in ipairs(wow.allTexts()) do noCommand(t, "widget text") end
    for _, line in ipairs(wow.printed()) do noCommand(line, "chat line") end
    -- Advanced commands are still documented in /gftk help.
    wow.clearPrinted()
    SlashCmdList.GREENFANGTOOLKIT("help")
    ok(printedContains("/gftk sync：查看同步狀態"), "help lists the sync command")
end)

test("sync status: the roster's small 「同步與診斷」 button and the window stay current", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("roster")
    local ind = ns.UI.syncIndicator
    ok(ind, "button on the roster page")
    -- GF-UI-B: a gear and 「診斷」, 30 px.
    ok(ind:GetText():find("診斷", 1, true), "label")
    eq(ind._h, 30, "30 px")
    ind:GetScript("OnEnter")(ind)
    eq(GameTooltip._lines[1].text, "同步與診斷", "tooltip title")
    ind:GetScript("OnLeave")(ind)
    ind:GetScript("OnClick")(ind)
    ok(ns.Diag.isShown(), "window opened")
    local first = ns.Diag.lines()[1]
    local n = #outbox()
    ok(first:GetText():find("待上傳 " .. n .. " 筆", 1, true), "pending count in the window")
    GreenFangToolkitDB.sync.outbox = {}
    ns.Sync.recordSelf(true)
    wow.advance(1.2)
    ok(first:GetText():find("待上傳 1 筆", 1, true), "updated after an outbox write")
    ind:GetScript("OnClick")(ind)
    ok(not ns.Diag.isShown(), "second click closes it")
end)

test("D19 minimap tooltip: only the name; no hints, no sync status", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local b = _G.GreenFangToolkit_MinimapButton
    b:GetScript("OnEnter")(b)
    local t = {}
    for _, l in ipairs(GameTooltip._lines) do t[#t + 1] = l.text end
    eq(table.concat(t, "|"), "綠皮冒險工具箱", "name only")
    GreenFangToolkitDB.sync.outbox = {}
    ns.Sync.recordSelf(true)
    eq(#GameTooltip._lines, 1, "an outbox write does not add a status line")
    b:GetScript("OnLeave")(b)
end)

---------------------------------------------------------------------------
-- GF-000-C minimap button position and icon
---------------------------------------------------------------------------

local function textureByLayer(b, layer)
    for _, t in ipairs(b._textures or {}) do if t._layer == layer then return t end end
end

test("minimap: radius puts the button on the rim (diameter/2 + 10)", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    eq(ns.Framework.minimapOrbitRadius(), 80, "140px minimap -> 80")
    wow.state.minimapSize = 198
    eq(ns.Framework.minimapOrbitRadius(), 109, "198px (Mainline-size) minimap -> 109")
    wow.state.minimapSize = 0
    eq(ns.Framework.minimapOrbitRadius(), 80, "unknown size falls back to 140px")
end)

test("minimap: button position follows angle and radius, drag keeps it on the rim", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local b = _G.GreenFangToolkit_MinimapButton
    local p = b._points[#b._points]
    eq(p[1], "CENTER", "anchored by centre"); eq(p[3], "CENTER", "to minimap centre")
    local r = 80
    ok(math.abs(p[4] - math.cos(math.rad(215)) * r) < 1e-6, "x at 215 deg")
    ok(math.abs(p[5] - math.sin(math.rad(215)) * r) < 1e-6, "y at 215 deg")
    for _, angle in ipairs({ 0, 90, 180, 270, 359 }) do
        GreenFangToolkitDB.settings.minimapAngle = angle
        GetCursorPosition = function()
            return 100 + math.cos(math.rad(angle)) * 300, 100 + math.sin(math.rad(angle)) * 300
        end
        b:GetScript("OnDragStart")(b)
        b:GetScript("OnUpdate")(b)
        b:GetScript("OnDragStop")(b)
        p = b._points[#b._points]
        local dist = math.sqrt(p[4] * p[4] + p[5] * p[5])
        ok(math.abs(dist - r) < 1e-6, "on the rim at " .. angle .. " deg")
        ok(math.abs(GreenFangToolkitDB.settings.minimapAngle - (angle > 180 and angle - 360 or angle)) < 1e-6,
            "angle saved at " .. angle)
    end
end)

test("minimap: 31px button, border/background/icon anchored TOPLEFT", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local b = _G.GreenFangToolkit_MinimapButton
    eq(b._w, 31, "button width"); eq(b._h, 31, "button height")
    local border = textureByLayer(b, "OVERLAY")
    eq(border._texture, "Interface\\Minimap\\MiniMap-TrackingBorder", "border texture")
    eq(border._w, 53, "border size")
    local bp = border._points[1]
    eq(bp[1], "TOPLEFT", "border anchor"); eq(bp[3], "TOPLEFT", "border relative anchor")
    eq(bp[4], 0, "border x"); eq(bp[5], 0, "border y")
    local icon = textureByLayer(b, "ARTWORK")
    eq(icon._w, 17, "icon size")
    eq(icon._points[1][1], "TOPLEFT", "icon anchor")
    -- Icon centre (7 + 17/2, 6 + 17/2) sits inside the button's 31x31 area.
    eq(7 + 17 / 2, 15.5, "icon centred horizontally in the button")
    local bg = textureByLayer(b, "BACKGROUND")
    eq(bg._texture, "Interface\\Minimap\\UI-Minimap-Background", "background")
    for _, t in ipairs(b._textures) do
        for _, pt in ipairs(t._points or {}) do ok(pt[1] ~= "CENTER" or t._layer ~= "OVERLAY", "no CENTER+offset border") end
    end
end)

test("minimap: icon is the adventure bag, with INV_Misc_Bag_08 fallback", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local b = _G.GreenFangToolkit_MinimapButton
    eq(textureByLayer(b, "ARTWORK")._texture, "Interface\\Icons\\INV_Misc_Bag_10", "chosen icon")
    local f = assert(io.open(ADDON_DIR .. "/GreenFangToolkit.toc", "rb"))
    local toc = f:read("*a"); f:close()
    ok(toc:find("## IconTexture: Interface\\Icons\\INV_Misc_Bag_10", 1, true), "TOC IconTexture")
    ok(not toc:find("Book_09", 1, true), "old book icon gone from TOC")
    -- Missing file detected through GetFileIDFromPath.
    wow.reset({ fileIDs = true, missingFiles = { ["Interface\\Icons\\INV_Misc_Bag_10"] = true } })
    wow.login(ADDON_DIR)
    b = _G.GreenFangToolkit_MinimapButton
    eq(textureByLayer(b, "ARTWORK")._texture, "Interface\\Icons\\INV_Misc_Bag_08", "fallback via GetFileIDFromPath")
    -- Missing file reported by SetTexture returning false.
    wow.reset({ missingFiles = { ["Interface\\Icons\\INV_Misc_Bag_10"] = true } })
    wow.login(ADDON_DIR)
    b = _G.GreenFangToolkit_MinimapButton
    eq(textureByLayer(b, "ARTWORK")._texture, "Interface\\Icons\\INV_Misc_Bag_08", "fallback via SetTexture")
end)

test("minimap: saved angle is kept, default stays 215", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2,
        settings = { minimapAngle = 42, minimapLayoutVersion = 2 },
    } })
    eq(GreenFangToolkitDB.settings.minimapAngle, 42, "existing angle not reset")
    ns.Framework.resetMinimap()
    eq(GreenFangToolkitDB.settings.minimapAngle, 215, "reset goes to 215")
end)

---------------------------------------------------------------------------
-- GF-000-D glyphs the zhTW game font can draw
---------------------------------------------------------------------------

-- Every string literal of a Lua source (comments skipped), as raw bytes.
local function stringLiterals(src)
    local out, i, n = {}, 1, #src
    local function longBracket(at)
        local eqs = src:match("^%[(=*)%[", at)
        if not eqs then return nil end
        local close = "]" .. eqs .. "]"
        local s = at + #eqs + 2
        local e = src:find(close, s, true)
        return s, (e or n + 1) - 1, (e or n) + #close
    end
    while i <= n do
        local c = src:sub(i, i)
        if c == "-" and src:sub(i, i + 1) == "--" then
            local s, _, after = longBracket(i + 2)
            if s then i = after else i = (src:find("\n", i, true) or n) + 1 end
        elseif c == '"' or c == "'" then
            local j, buf = i + 1, {}
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1); j = j + 2
                elseif d == c then break
                else buf[#buf + 1] = d; j = j + 1 end
            end
            out[#out + 1] = table.concat(buf)
            i = j + 1
        elseif c == "[" then
            local s, e, after = longBracket(i)
            if s then out[#out + 1] = src:sub(s, e); i = after else i = i + 1 end
        else
            i = i + 1
        end
    end
    return out
end

-- Code points of a UTF-8 string (Lua 5.1 has no utf8 library).
local function codepoints(s)
    local cps, i = {}, 1
    while i <= #s do
        local b = s:byte(i)
        local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
        local cp = len == 1 and b or (b % (2 ^ (7 - len)))
        for k = 2, len do cp = cp * 64 + (s:byte(i + k - 1) or 0x80) % 64 end
        cps[#cps + 1] = cp
        i = i + len
    end
    return cps
end

-- ASCII, CJK ideographs, CJK punctuation (U+3000-303F; U+30FB is NOT in it),
-- full-width forms, plus symbols already seen working in the game.
local GLYPH_WHITELIST = { [0x25B2] = "▲", [0x25BC] = "▼" }
local function glyphAllowed(cp)
    return cp < 0x80 or (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)
        or (cp >= 0x3000 and cp <= 0x303F) or (cp >= 0xFF00 and cp <= 0xFFEF)
        or GLYPH_WHITELIST[cp] ~= nil
end

test("glyphs: the literal scanner finds strings and skips comments", function()
    local lits = stringLiterals('-- "註解→"\nlocal a = "甲→" .. \'乙\' --[[ "x→" ]] local b = [[丙]]')
    eq(table.concat(lits, "|"), "甲→|乙|丙", "literals")
    eq(#codepoints("同步，A"), 4, "utf-8 decode")
    eq(codepoints("・")[1], 0x30FB, "katakana middle dot decoded")
    ok(not glyphAllowed(0x30FB), "・ rejected"); ok(not glyphAllowed(0x2192), "→ rejected")
    ok(glyphAllowed(0xFF0C), "， allowed"); ok(glyphAllowed(0x25B2), "▲ whitelisted")
end)

test("glyphs: every string in the addon uses only glyphs the game font has", function()
    local bad = {}
    for _, file in ipairs(wow.TOC_FILES) do
        -- GF-009-12: SupplyCatalogData.lua holds the game's own item names (drawn
        -- with the game font), not text we write.
        if file == "SupplyCatalogData.lua" then file = nil end
        local f = file and assert(io.open(ADDON_DIR .. "/" .. file, "rb"))
        local src = f and f:read("*a") or ""; if f then f:close() end
        for _, lit in ipairs(stringLiterals(src)) do
            for _, cp in ipairs(codepoints(lit)) do
                if not glyphAllowed(cp) then
                    bad[#bad + 1] = string.format("%s U+%04X in %q", file, cp, lit:sub(1, 60))
                end
            end
        end
    end
    ok(#bad == 0, "unsupported glyphs:\n     " .. table.concat(bad, "\n     "))
end)

test("glyphs: runtime texts shown to players pass the same check", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("roster")
    ns.Framework.select("sleepingbag")
    ns.SleepingBag.complete(); ns.SleepingBag.setMode("normal")
    ns.Framework.select("settings")
    local texts = wow.allTexts()
    for _, l in ipairs(wow.printed()) do texts[#texts + 1] = l end
    texts[#texts + 1] = ns.Sync.shortStatus()
    for _, t in ipairs(texts) do
        for _, cp in ipairs(codepoints(t)) do
            ok(glyphAllowed(cp), string.format("U+%04X in %q", cp, t:sub(1, 60)))
        end
    end
    eq(ns.Sync.shortStatus():find("待上傳", 1, true), 1, "short status")
end)

---------------------------------------------------------------------------
-- GF-001-D3 character.self keeps guild / guildRank (GF-001-B wrong_guild)
---------------------------------------------------------------------------

local function selfEntry()
    return entriesOf("character.self")[1]
end

test("self guild: guild info empty at PLAYER_LOGOUT keeps the login entry's guild", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local before = selfEntry()
    eq(before.uploader.guild, "綠皮與獠牙冒險事務所", "login entry has guild")
    wow.state.now = wow.state.now + 5
    wow.state.guildInfoGone = true
    wow.fire("PLAYER_LOGOUT")
    local after = selfEntry()
    eq(#entriesOf("character.self"), 1, "still one entry")
    eq(after.uploader.guild, "綠皮與獠牙冒險事務所", "guild kept at logout")
    eq(after.uploader.guildRank, "會員", "rank kept at logout")
end)

test("self guild: logout with a real change and empty guild info still keeps the guild", function()
    wow.reset()
    wow.login(ADDON_DIR)
    wow.state.player.level = 33 -- changed, so logout writes a new entry
    wow.state.now = wow.state.now + 5
    wow.state.guildInfoGone = true
    wow.fire("PLAYER_LOGOUT")
    local e = selfEntry()
    eq(e.payload.level, 33, "new level recorded")
    eq(e.uploader.guild, "綠皮與獠牙冒險事務所", "guild taken from this session")
    eq(e.uploader.guildRank, "會員", "rank taken from this session")
end)

test("self guild: guild info not loaded yet at login waits instead of writing no guild", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    wow.state.guildInfoGone = true
    wow.fire("PLAYER_LOGIN")
    wow.advance(6)
    for _, e in ipairs(entriesOf("character.self")) do
        ok(e.uploader.guild ~= nil, "no guild-less character.self while guild info is loading")
    end
    wow.state.guildInfoGone = false
    wow.fire("PLAYER_GUILD_UPDATE", "player")
    wow.advance(5)
    local e = selfEntry()
    ok(e, "written once guild info arrives")
    eq(e.uploader.guild, "綠皮與獠牙冒險事務所", "with guild")
    eq(#entriesOf("character.self"), 1, "one per login")
end)

test("self guild: a guildless character gives up waiting and writes nothing", function()
    wow.reset({ inGuild = false })
    local ns = wow.login(ADDON_DIR)
    wow.advance(60)
    eq(selfEntry(), nil, "nothing written")
    local _, reason = ns.Sync.recordSelf(true, { allowNoGuild = true })
    eq(reason, "no-guild", "allowNoGuild does not let a guildless character in")
end)

test("self guild: a character that really leaves the guild drops it", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    wow.advance(30)
    wow.state.inGuild = false
    wow.fire("PLAYER_GUILD_UPDATE", "player")
    wow.advance(5)
    eq(#entriesOf("character.self"), 1, "no guild-less entry added")
    for _, e in ipairs(entriesOf("character.self")) do
        ok(e.uploader.guild ~= nil, "every pending entry still has a guild")
    end
    eq(ns.Sync.guildNote(), ns.Sync.otherGuildNote(), "remembered guild dropped after leaving")
end)

test("self guild: roster scan knowledge fills a character.self taken before guild info", function()
    -- Matches the GF-001-B evidence: roster.snapshot had the guild 5 s before character.self.
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    wow.advance(30)
    wow.state.player.professions[1][3] = 160
    wow.state.guildInfoGone = true
    ns.Sync.recordSelf(false)
    eq(selfEntry().uploader.guild, "綠皮與獠牙冒險事務所", "guild from earlier in the session")
end)

---------------------------------------------------------------------------
-- GF-001-D4 only 綠皮與獠牙冒險事務所 is synced
---------------------------------------------------------------------------

local OTHER_GUILD = "測試用其他公會"

local function otherGuildPlayer()
    local player = wow.defaultPlayer()
    player.guild = OTHER_GUILD
    return player
end

test("own guild: a character in another guild syncs nothing (GF-001-D5: and has no roster window)", function()
    wow.reset({ player = otherGuildPlayer() })
    local ns = wow.login(ADDON_DIR)
    wow.advance(60)
    wow.fire("PLAYER_LOGOUT")
    eq(#ns.db.sync.outbox, 0, "outbox empty")
    local _, reason = ns.Sync.recordSelf(true, { allowNoGuild = true })
    eq(reason, "other-guild", "recordSelf reason")
    eq(ns.Roster.current(), nil, "no roster window for another guild (GF-001-D5)")
    local snap = { guild = OTHER_GUILD, realm = "測試伺服器", total = 1,
        members = { { name = "測試戊-測試伺服器", level = 20 } } }
    local _, why = ns.Sync.recordRoster(snap)
    eq(why, "other-guild", "recordRoster reason")
end)

test("own guild: another guild's character gets the note in status and on the settings page", function()
    wow.reset({ player = otherGuildPlayer() })
    local ns = wow.login(ADDON_DIR)
    ok(ns.Sync.statusText():find("這個角色不在綠皮與獠牙冒險事務所，不會同步", 1, true), "status note")
    ns.handleSlash("sync status")
    ok(printedContains("不會同步"), "/gf sync status shows the note")
    ns.Framework.open("settings")
    local found = false
    for _, t in ipairs(wow.allTexts()) do
        if t:find("不會同步", 1, true) then found = true end
    end
    ok(found, "settings page shows the note")
end)

test("own guild: no note for a character in the guild", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    eq(ns.Sync.guildNote(), nil, "no note")
    ok(not ns.Sync.statusText():find("不會同步", 1, true), "status has no note")
end)

test("own guild: guild info loads late -> waits, then syncs once it is the guild", function()
    wow.reset()
    wow.loadAddon(ADDON_DIR)
    wow.state.guildInfoGone = true
    wow.fire("PLAYER_LOGIN")
    wow.advance(10)
    eq(#entriesOf("character.self"), 0, "nothing while guild info is loading")
    wow.state.guildInfoGone = false
    wow.fire("PLAYER_GUILD_UPDATE", "player")
    wow.fire("GUILD_ROSTER_UPDATE")
    wow.advance(5)
    eq(#entriesOf("character.self"), 1, "character.self once the guild is known")
    eq(entriesOf("character.self")[1].uploader.guild, "綠皮與獠牙冒險事務所", "with the guild")
    eq(#entriesOf("roster.snapshot"), 1, "roster.snapshot too")
end)

test("own guild: guild info loads late and it is another guild -> nothing synced", function()
    wow.reset({ player = otherGuildPlayer() })
    wow.loadAddon(ADDON_DIR)
    wow.state.guildInfoGone = true
    wow.fire("PLAYER_LOGIN")
    wow.advance(10)
    wow.state.guildInfoGone = false
    wow.fire("PLAYER_GUILD_UPDATE", "player")
    wow.fire("GUILD_ROSTER_UPDATE")
    wow.advance(40)
    wow.fire("PLAYER_LOGOUT")
    eq(#GreenFangToolkitDB.sync.outbox, 0, "outbox empty")
end)

test("own guild: a guildless character writes nothing", function()
    wow.reset({ inGuild = false })
    local ns = wow.login(ADDON_DIR)
    wow.advance(40)
    wow.fire("PLAYER_LOGOUT")
    eq(#ns.db.sync.outbox, 0, "nothing written")
end)

test("own guild: load removes old outbox entries from other guilds or without a guild", function()
    local function entry(id, kind, guild)
        return { id = id, kind = kind, capturedAt = 1763360000,
            game = { world = "forever", interface = 16001, realm = "測試伺服器" },
            uploader = { guid = "Player-0000-000000" .. id, name = "測試" .. id,
                realm = "測試伺服器", faction = "Horde", guild = guild },
            payload = { level = 20 } }
    end
    wow.reset({ inGuild = false })
    local ns = wow.loadAddon(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2, addonVersion = "0.6.4",
        settings = {}, roster = { snapshots = {} },
        sync = { enabled = true, noticeShown = true, outbox = {
            entry("1F", "character.self", "綠皮與獠牙冒險事務所"),
            entry("2F", "character.self", OTHER_GUILD),
            entry("3F", "character.self", nil),
            entry("4F", "roster.snapshot", OTHER_GUILD),
            entry("5F", "roster.snapshot", "綠皮與獠牙冒險事務所"),
            "not a table",
        } },
    } })
    local outbox = ns.db.sync.outbox
    eq(#outbox, 2, "only this guild's entries kept")
    eq(outbox[1].id, "1F", "own character.self kept")
    eq(outbox[2].id, "5F", "own roster.snapshot kept")
end)

---------------------------------------------------------------------------
-- GF-001-D5 roster window serves ns.Config.guild only; one guild setting
---------------------------------------------------------------------------

local function rosterPage(ns)
    ns.Framework.open("roster")
    return ns.UI
end

local function controlsEnabled(UI)
    local all = { UI.updateButton, UI.searchBox, UI.clearButton }
    local on, off = 0, 0
    for _, w in ipairs(all) do
        if w._enabled == false then off = off + 1 else on = on + 1 end
    end
    return on, off
end

local function pageHas(text)
    for _, t in ipairs(wow.allTexts()) do
        if t:find(text, 1, true) then return true end
    end
    return false
end

test("roster window: target guild shows the roster with every control enabled", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    eq(ns.guildState(), "target", "state")
    local UI = rosterPage(ns)
    eq(UI.unavailableText(), nil, "no message")
    ok(ns.Roster.current(), "snapshot shown")
    local on, off = controlsEnabled(UI)
    eq(off, 0, "nothing disabled"); eq(on, 3, "all enabled")
    ok(pageHas("測試乙-測試伺服器"), "member rows shown")
end)

test("roster window: another guild shows a message, no roster, controls disabled, nothing scanned", function()
    local player = wow.defaultPlayer()
    player.guild = "測試用其他公會"
    wow.reset({ player = player })
    local ns = wow.login(ADDON_DIR)
    eq(ns.guildState(), "other", "state")
    eq(wow.state.rosterRequests, 0, "no GuildRoster request")
    eq(wow.state.rosterInfoCalls or 0, 0, "no GetGuildRosterInfo call")
    local ok1, why = ns.Roster.collect()
    ok(not ok1 and why:find("綠皮與獠牙冒險事務所", 1, true), "collect refuses")
    eq(wow.state.rosterInfoCalls or 0, 0, "still no GetGuildRosterInfo call")
    eq(ns.Roster.current(), nil, "no snapshot")
    local UI = rosterPage(ns)
    eq(UI.unavailableText(), "這個角色不在綠皮與獠牙冒險事務所，無法使用職工名冊。", "message")
    -- GF-UI-B: an icon and 「非本會」 in the middle, no sentence.
    eq(UI.emptyKey, "other", "other guild shown")
    ok(pageHas("非本會"), "short name on the page")
    ok(not pageHas("這個角色不在綠皮與獠牙冒險事務所"), "no sentence on the page")
    ok(not pageHas("測試乙-測試伺服器"), "no member rows")
    local on, off = controlsEnabled(UI)
    eq(on, 0, "none enabled"); eq(off, 3, "all disabled")
    ns.UI.startExport("json")
    ok(printedContains("無法使用職工名冊"), "export refuses")
    ok(ns.Framework.get("sleepingbag"), "sleeping bag still available")
    ns.Framework.open("sleepingbag")
    eq(ns.Framework.isModuleShown("sleepingbag"), true, "sleeping bag opens")
end)

test("roster window: another guild never shows a stored snapshot of any guild", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ok(ns.Roster.current(), "target snapshot stored")
    wow.state.player.guild = "測試用其他公會"
    eq(ns.Roster.current(), nil, "stored target snapshot not shown to another guild's character")
end)

test("roster window: no guild shows its own message and scans nothing", function()
    wow.reset({ inGuild = false })
    local ns = wow.login(ADDON_DIR)
    eq(ns.guildState(), "none", "state")
    eq(wow.state.rosterRequests, 0, "no GuildRoster request")
    eq(wow.state.rosterInfoCalls or 0, 0, "no GetGuildRosterInfo call")
    local UI = rosterPage(ns)
    ok(UI.unavailableText():find("沒有加入公會", 1, true), "no-guild message")
    local _, off = controlsEnabled(UI)
    eq(off, 3, "all disabled")
end)

test("roster window: guild name still loading shows loading, not 'not in guild'", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    wow.state.guildNameLoading = true
    wow.fire("PLAYER_LOGIN")
    wow.advance(10)
    eq(ns.guildState(), "loading", "state")
    local UI = rosterPage(ns)
    eq(UI.unavailableText(), "公會資料讀取中，請稍候。", "loading message")
    ok(not pageHas("沒有加入公會"), "not shown as no guild")
    ok(not pageHas("這個角色不在"), "not shown as another guild")
    eq(wow.state.rosterInfoCalls or 0, 0, "nothing scanned while loading")
    -- name arrives
    wow.state.guildNameLoading = false
    wow.fire("PLAYER_GUILD_UPDATE", "player")
    wow.fire("GUILD_ROSTER_UPDATE")
    wow.advance(5)
    eq(ns.guildState(), "target", "state after load")
    eq(UI.unavailableText(), nil, "roster available")
    ok(ns.Roster.current(), "roster scanned")
    ok(pageHas("測試乙-測試伺服器"), "rows shown after load")
end)

test("config: one guild setting drives sync filter, roster window and text", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    ns.Config.guild.name = "測試用其他公會"
    local player = wow.state.player
    player.guild = "測試用其他公會"
    wow.fire("PLAYER_LOGIN")
    wow.advance(10)
    eq(ns.guildState(), "target", "configured guild is the target")
    eq(#entriesOf("character.self"), 1, "character.self synced for the configured guild")
    eq(#entriesOf("roster.snapshot"), 1, "roster.snapshot synced for the configured guild")
    eq(entriesOf("character.self")[1].uploader.guild, "測試用其他公會", "uploader.guild")
    -- a character of the old default guild is now "other"
    player.guild = "綠皮與獠牙冒險事務所"
    ok(ns.UI.unavailableText():find("測試用其他公會", 1, true), "text names the configured guild")
    ok(ns.Sync.otherGuildNote():find("測試用其他公會", 1, true), "sync note names the configured guild")
    local _, reason = ns.Sync.recordSelf(true)
    eq(reason, "other-guild", "old default guild filtered")
end)

test("config: a configured realm is checked too", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    ns.Config.guild.realm = "測試用其他伺服器"
    wow.fire("PLAYER_LOGIN")
    wow.advance(40)
    eq(ns.guildState(), "other", "same name on another realm is not the target")
    eq(#GreenFangToolkitDB.sync.outbox, 0, "nothing synced")
    ns.Config.guild.realm = "測試伺服器"
    eq(ns.guildState(), "target", "matching realm")
end)

test("config: no guild name is hardcoded outside Config.lua (except brand text)", function()
    -- toc Title/Notes/Author, the settings title and the chat prefix are brand
    -- text and stay as they are in this version (GF-001-D5).
    local allowed = { ["Config.lua"] = true }
    for _, file in ipairs(wow.TOC_FILES) do
        if not allowed[file] then
            local fh = io.open(ADDON_DIR .. "/" .. file, "rb")
            local src = fh:read("*a"); fh:close()
            for line in src:gmatch("[^\n]+") do
                local code = line:gsub("%-%-.*$", "")
                if code:find("綠皮與獠牙冒險事務所", 1, true) then
                    ok(file == "Settings.lua" and code:find("ns.VERSION", 1, true),
                        file .. " hardcodes the guild name: " .. code)
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- GF-001-D6 location (D-009) and graphics
---------------------------------------------------------------------------

test("location: always shared, character.self carries zone and subZone", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    eq(GreenFangToolkitDB.sync.shareLocation, nil, "no switch saved (D-015)")
    eq(ns.Sync.shareLocation(), true, "always shared")
    local loc = entriesOf("character.self")[1].payload.location
    ok(loc, "location present")
    eq(loc.zone, "雷霆崖", "zone"); eq(loc.subZone, "長者高地", "subZone")
end)

test("location: written at logout reflects where the character is then", function()
    wow.reset()
    wow.login(ADDON_DIR)
    wow.state.zone, wow.state.subZone = "杜洛塔", ""
    wow.fire("PLAYER_LOGOUT")
    local e = entriesOf("character.self")
    eq(#e, 1, "still one entry")
    eq(e[1].payload.location.zone, "杜洛塔", "zone at logout")
    eq(e[1].payload.location.subZone, nil, "empty subZone omitted")
end)

test("location: old saved switches (enabled=false, shareLocation=false) are ignored on upgrade", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2, addonVersion = "0.9.0",
        settings = {}, roster = { snapshots = {} },
        sync = { enabled = false, shareLocation = false, noticeShown = true, noticeVersion = 3, outbox = {} } } })
    eq(GreenFangToolkitDB.sync.enabled, true, "enabled forced on")
    eq(GreenFangToolkitDB.sync.shareLocation, nil, "old location switch cleared")
    local e = entriesOf("character.self")
    eq(#e, 1, "character.self written")
    ok(e[1].payload.location, "location included")
    eq(ns.Sync.toggleShareLocation, nil, "no location switch")
end)

test("location: never in roster.snapshot members; no zone/online/location there", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local snap = entriesOf("roster.snapshot")[1]
    local keys = {}
    local function walk(t) for k, v in pairs(t) do keys[k] = true; if type(v) == "table" then walk(v) end end end
    walk(snap)
    ok(not keys.location, "no location")
    ok(not keys.zone and not keys.online and not keys.subZone, "no zone/online")
    for _, m in ipairs(snap.payload.members) do eq(m.rankIndex, nil, "rankIndex stays local") end
end)

test("location: C_Map fallback when GetZoneText is missing; nothing when unknown", function()
    wow.reset({ noZoneText = true })
    local ns = wow.login(ADDON_DIR)
    eq(ns.Data.location().zone, "雷霆崖", "zone from C_Map")
    wow.reset({ zone = "", subZone = "" })
    ns = wow.login(ADDON_DIR)
    eq(ns.Data.location(), nil, "no location")
    eq(entriesOf("character.self")[1].payload.location, nil, "not written")
end)

test("location: notice mentions it, one line, shown once more to players who saw the old one", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2, addonVersion = "0.6.6",
        settings = {}, roster = { snapshots = {} },
        sync = { enabled = true, noticeShown = true, outbox = {} } } })
    ok(ns.Sync.NOTICE:find("所在地", 1, true), "notice mentions location")
    ok(not ns.Sync.NOTICE:find("\n", 1, true), "one line")
    ok(printedContains("配方和所在地給公會內"), "shown again after upgrade")
    local saved = wow.logout()
    wow.reset()
    wow.login(ADDON_DIR, saved)
    ok(not printedContains("配方和所在地給公會內"), "only once")
end)

test("location: payload professions keep contract fields only (no icon)", function()
    wow.reset()
    wow.login(ADDON_DIR)
    for _, prof in ipairs(entriesOf("character.self")[1].payload.professions) do
        eq(prof.icon, nil, "no icon in outbox")
    end
end)

test("icons: profession table covers every known profession and maps names", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    for id in pairs(ns.Data.professionNamesZH) do
        ok(ns.Icons.PROFESSION[id], "icon for skillLine " .. id)
        ok(ns.Icons.PROFESSION[id]:find("^Interface\\Icons\\"), "built-in path " .. id)
    end
    eq(ns.Icons.professionIcon("採礦"), "Interface\\Icons\\Trade_Mining", "zhTW name")
    eq(ns.Icons.professionIcon("Mining"), "Interface\\Icons\\Trade_Mining", "English name")
    eq(ns.Icons.professionIcon(164), "Interface\\Icons\\Trade_BlackSmithing", "skillLineID")
    eq(ns.Icons.professionIcon("不存在的專業"), nil, "unknown -> nil")
end)

test("icons: missing texture falls back to text; own profession uses the client icon", function()
    wow.reset({ missingFiles = { ["Interface\\Icons\\Trade_Mining"] = true } })
    local ns = wow.login(ADDON_DIR)
    local tex = CreateFrame("Frame"):CreateTexture()
    eq(ns.Icons.setProfessionIcon(tex, "採礦"), false, "missing file -> text")
    eq(ns.Icons.setProfessionIcon(tex, { name = "採礦", icon = 134708 }), true, "client icon wins")
    eq(tex._texture, 134708, "client file ID used")
    eq(ns.Icons.setProfessionIcon(tex, "不存在的專業"), false, "unknown -> text")
end)

test("icons: class colour from C_ClassColor, else built-in; class icon falls back to the sheet", function()
    wow.reset({ classColorAPI = true })
    local ns = wow.login(ADDON_DIR)
    eq(ns.Icons.classColor("DRUID")[1], 0.5, "C_ClassColor used")
    eq(ns.Icons.classColor("MAGE")[1], ns.Icons.CLASS_COLOR.MAGE[1], "built-in when API has none")
    eq(ns.Icons.classColor("")[1], ns.Icons.DEFAULT_COLOR[1], "unknown token")
    wow.reset({ missingFiles = { ["Interface\\Icons\\ClassIcon_Druid"] = true } })
    ns = wow.login(ADDON_DIR)
    local tex = CreateFrame("Frame"):CreateTexture()
    eq(ns.Icons.setClassIcon(tex, "DRUID"), true, "sheet fallback")
    eq(tex._texture, ns.Icons.CLASS_SHEET, "sheet used")
    eq(tex._texCoord[1], ns.Icons.CLASS_TCOORDS.DRUID[1], "druid coords")
    eq(ns.Icons.setClassIcon(tex, "NOPE"), false, "unknown class -> hidden")
end)

-- GF-001-D18: the professions cell as text, one entry per shown slot:
-- "<icon file name>:<points>" (just the icon name when no points), the text
-- when there is no icon, then "+N". Icon paths keep only the last part.
local function profIconName(t)
    if type(t) == "string" then return (t:match("([^\\]+)$")) end
    return tostring(t)
end

local function profCell(row)
    local list = {}
    for _, s in ipairs(row.profSlots) do
        local icon = s.icon:IsShown() and profIconName(s.icon._texture) or nil
        local text = s.label:IsShown() and s.label:GetText() or ""
        if icon and text ~= "" then list[#list + 1] = icon .. ":" .. text
        elseif icon then list[#list + 1] = icon
        elseif text ~= "" then list[#list + 1] = text end
    end
    if row.profMore:IsShown() then list[#list + 1] = row.profMore:GetText() end
    return table.concat(list, "|")
end

local function rosterRow(ns, name)
    for _, row in ipairs(ns.UI.rows()) do
        if row:IsShown() and row.memberName == name then return row end
    end
end

test("roster: rows show class icon/colour, rank column, profession names; rank sorts by index", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("roster")
    local members = ns.Roster.current().members
    local list = ns.UI.sortMembers(ns.UI.filterMembers(members, ""), "rank", true)
    eq(list[1].guildRank, "會長", "guild master first")
    eq(list[#list].guildRank, "新進", "newest last")
    local found = false
    for _, t in ipairs(wow.allTexts()) do if t == "會階" then found = true end end
    ok(found, "rank column heading")
    local textures = {}
    for _, o in ipairs(wow.allObjects()) do
        if o._texture then textures[o._texture] = true end
    end
    ok(textures["Interface\\Icons\\ClassIcon_Warrior"], "warrior class icon in the roster")
    -- GF-001-D18: the professions cell shows icons (dimmed, no points, for a
    -- member known by name only); the tooltip names them.
    ok(textures["Interface\\Icons\\Trade_Mining"], "mining icon for a member with a name only")
    local named
    for _, row in ipairs(ns.UI.rows()) do
        if row:IsShown() and row.rosterNames then named = row end
    end
    ok(named, "a row with names only")
    ok(not profCell(named):find(":", 1, true), "no points for names only: " .. profCell(named))
    named._scripts.OnEnter(named)
    local tip = ns.UI.rosterCardText() -- GF-UI-I: the member card
    ok(tip:find(named.rosterNames[1], 1, true), "tooltip names the profession")
    ok(not tip:find("技能點數未知", 1, true), "no explanation line (D19)")
end)

test("character page: icons and progress bars for own professions", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ok(ns.Framework.get("character"), "module registered")
    ns.Framework.open("character")
    eq(ns.Framework.current(), "character", "opens")
    local texts = table.concat(wow.allTexts(), "\n")
    ok(texts:find("151 / 225", 1, true), "skill text")
    ok(texts:find("所在地：雷霆崖，長者高地", 1, true), "location line")
    local bars, maxes = 0, {}
    for _, o in ipairs(wow.allObjects()) do
        if o._kind == "StatusBar" and o._max and o._max > 1 then bars = bars + 1; maxes[o._max] = true end
    end
    eq(bars, 4, "one bar per profession")
    ok(maxes[225] and maxes[150], "bar maxima from skill caps")
    eq(ns.Character.skillFraction({ rank = 75, max = 150 }), 0.5, "fraction")
    eq(ns.Character.skillFraction({ rank = 75 }), nil, "no max -> no bar")
    ok(ns.Character.locationText():find("雷霆崖", 1, true), "location line")
end)

---------------------------------------------------------------------------
-- GF-001-D7 sync-now button, in-game sharing, member.report (D-011)
---------------------------------------------------------------------------

local PEER = "測試乙-測試伺服器"

local function peerData(over)
    local d = { level = 61, classToken = "WARRIOR", capturedAt = wow.state.now,
        professions = {
            { name = "採礦", skillLineID = 186, rank = 300, max = 300 },
            { name = "鍛造", skillLineID = 164, rank = 280, max = 300 },
            { name = "釣魚", skillLineID = 356, rank = 150, max = 225 },
            { name = "烹飪", skillLineID = 185, rank = 90, max = 150 },
            { name = "急救", skillLineID = 129, rank = 75, max = 150 },
        },
        location = { zone = "奧格瑪", subZone = "力量谷" } }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

local function sendFrom(ns, sender, data, id, channel)
    local parts = ns.Comm.split(ns.Comm.encodeBody(data), id or "a1")
    for _, m in ipairs(parts) do wow.fire("CHAT_MSG_ADDON", "GFTK", m, channel or "GUILD", sender) end
    return parts
end

-- Old GFTK (D-011) messages only; GFTKS (D-014) has its own tests.
local function v1Sent()
    local list = {}
    for _, s in ipairs(wow.state.sent) do if s.prefix == "GFTK" then list[#list + 1] = s end end
    return list
end

local function sentBody()
    local parts = {}
    for _, s in ipairs(v1Sent()) do
        local chunk = s.msg:match("^1~[^~]+~%d+~%d+~(.*)$")
        parts[#parts + 1] = chunk
    end
    return table.concat(parts)
end

test("share: login broadcasts own data on GUILD, all professions, location, <= 255 bytes", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ok(wow.state.prefixes.GFTK, "prefix registered")
    ok(#v1Sent() >= 1, "sent")
    for _, s in ipairs(v1Sent()) do
        eq(s.prefix, "GFTK", "prefix"); eq(s.chatType, "GUILD", "guild channel")
        ok(#s.msg <= 255, "fits 255 bytes")
    end
    local d = ns.Comm.decodeBody(sentBody())
    eq(d.level, 32, "level"); eq(d.classToken, "DRUID", "class")
    eq(#d.professions, 4, "every profession incl. fishing and cooking")
    eq(d.professions[3].name, "釣魚", "fishing"); eq(d.professions[3].max, 150, "max")
    eq(d.location.zone, "雷霆崖", "location while sharing")
    ok(not sentBody():find("測試甲", 1, true), "no names in the message")
end)

test("share: old saved switches do not stop sharing; other guild -> nothing sent", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2, settings = {}, roster = { snapshots = {} },
        sync = { enabled = false, noticeShown = true, noticeVersion = 3, shareLocation = false, outbox = {} } } })
    wow.fire("PLAYER_LOGIN"); wow.advance(10)
    ok(#v1Sent() >= 1, "sent")
    eq(ns.Comm.decodeBody(sentBody()).location.zone, "雷霆崖", "location included")

    local player = wow.defaultPlayer()
    player.guild = "測試用其他公會"
    wow.reset({ player = player })
    wow.login(ADDON_DIR)
    wow.advance(30)
    eq(#wow.state.sent, 0, "other guild: nothing sent")
end)

test("share: throttled to one broadcast per 5 minutes, unchanged data not re-sent", function()
    wow.reset()
    wow.login(ADDON_DIR)
    local first = #v1Sent()
    ok(first >= 1, "login broadcast")
    wow.state.player.professions[1][3] = 152
    wow.fire("SKILL_LINES_CHANGED")
    wow.advance(10)
    eq(#v1Sent(), first, "throttled")
    wow.advance(300)
    eq(#v1Sent(), first * 2, "sent once after the window")
    wow.fire("SKILL_LINES_CHANGED")
    wow.advance(400)
    eq(#v1Sent(), first * 2, "unchanged data not re-sent")
end)

test("share: long data is split on UTF-8 boundaries and reassembled in any order", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local data = peerData()
    for i = 1, 6 do
        data.professions[#data.professions + 1] = { name = "很長很長的測試專業名稱" .. i, skillLineID = 900 + i, rank = 1, max = 75 }
    end
    local parts = ns.Comm.split(ns.Comm.encodeBody(data), "z9")
    ok(#parts > 1, "split into several parts")
    for _, m in ipairs(parts) do
        ok(#m <= 255, "part fits")
        local chunk = m:match("^1~z9~%d+~%d+~(.*)$")
        local b = chunk:byte(1)
        ok(not b or b < 0x80 or b >= 0xC0, "chunk starts on a character")
    end
    for i = #parts, 1, -1 do wow.fire("CHAT_MSG_ADDON", "GFTK", parts[i], "GUILD", PEER) end
    local peer = ns.Comm.peerFor(PEER)
    ok(peer, "reassembled")
    eq(#peer.professions, 11, "all professions")
    eq(peer.professions[1].name, "採礦", "names come from the receiving client (D-014)")
    eq(peer.professions[11].skillLineID, 906, "order and ids intact")
end)

test("receive: a roster member's own data is stored; member.share at logout (no member.report)", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local at = wow.state.now
    sendFrom(ns, PEER, peerData())
    local peer = ns.Comm.peerFor(PEER)
    ok(peer, "stored")
    eq(peer.level, 61, "level"); eq(peer.guid, "Player-0000-0000000B", "guid from roster")
    eq(GreenFangToolkitDB.peers[ns.keyName(PEER)].name, PEER, "account-level table")
    eq(#entriesOf("member.report"), 0, "member.report is no longer written (0.10.0)")
    eq(#entriesOf("member.share"), 0, "nothing before logout")
    wow.logout()
    local shares = entriesOf("member.share")
    eq(#shares, 1, "one member.share")
    local e = shares[1]
    eq(e.uploader.guid, "Player-0000-0000000A", "uploader is this character")
    eq(e.uploader.guild, "綠皮與獠牙冒險事務所", "uploader guild")
    eq(e.payload.subject.name, PEER, "subject is the sender")
    eq(e.payload.subject.guid, "Player-0000-0000000B", "subject guid")
    eq(e.payload.subject.realm, "測試伺服器", "subject realm")
    eq(e.payload.level.value, 61, "level"); eq(e.payload.level.recordedAt, at, "author's time")
    eq(e.payload.level.via, "author", "straight from the author")
    eq(#e.payload.professions.value, 5, "secondary skills included")
    eq(e.payload.location.value.zone, "奧格瑪", "location")
end)

test("receive: sender without a location -> no location in member.share", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    sendFrom(ns, PEER, peerData({ location = false }))
    wow.logout()
    eq(entriesOf("member.share")[1].payload.location, nil, "no location")
end)

test("receive: rejects non-members, other channels, self, unknown version, third parties", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local body = ns.Comm.encodeBody(peerData())
    local function try(text, channel, sender)
        local okStored, why = ns.Comm.onMessage("GFTK", text, channel or "GUILD", sender or PEER)
        return okStored, why
    end
    local _, why = try("1~a~1~1~" .. body, "GUILD", "陌生人-測試伺服器")
    eq(why, "not-in-roster", "sender not in the roster")
    _, why = try("1~a~1~1~" .. body, "WHISPER")
    eq(why, "channel", "not the guild channel")
    _, why = try("1~a~1~1~" .. body, "GUILD", "測試甲-測試伺服器")
    eq(why, "self", "own message ignored")
    _, why = try("2~a~1~1~" .. body)
    eq(why, "version", "unknown version ignored")
    _, why = try("1~a~1~1~N=測試丙-測試伺服器;" .. body)
    eq(why, "third-party", "message naming someone else is dropped")
    eq(ns.Comm.peerFor("測試丙-測試伺服器"), nil, "nothing stored for the named third party")
    eq(ns.Comm.peerFor(PEER), nil, "nothing stored for the sender either")
    eq(#entriesOf("member.report"), 0, "nothing relayed")
    wow.logout()
    eq(#entriesOf("member.share"), 0, "nothing for the site either")
    local before = #v1Sent()
    try("1~a~1~1~" .. body)
    eq(#v1Sent(), before, "received data is never re-broadcast")
end)

test("receive: a character outside the configured guild accepts nothing", function()
    local player = wow.defaultPlayer()
    player.guild = "測試用其他公會"
    wow.reset({ player = player })
    local ns = wow.login(ADDON_DIR)
    local _, why = ns.Comm.onMessage("GFTK", "1~a~1~1~" .. ns.Comm.encodeBody(peerData()), "GUILD", PEER)
    eq(why, "other-guild", "rejected")
end)

test("receive: one per person, newest wins (peers and outbox)", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local t = wow.state.now
    sendFrom(ns, PEER, peerData({ capturedAt = t, level = 60 }), "a1")
    sendFrom(ns, PEER, peerData({ capturedAt = t + 60, level = 61 }), "a2")
    local _, why = ns.Comm.onMessage("GFTK", "1~a3~1~1~" .. ns.Comm.encodeBody(peerData({ capturedAt = t - 60, level = 59 })), "GUILD", PEER)
    eq(why, "older", "older data ignored")
    eq(ns.Comm.peerFor(PEER).level, 61, "newest kept")
    wow.logout()
    local shares = entriesOf("member.share")
    eq(#shares, 1, "one member.share per subject")
    eq(shares[1].payload.level.value, 61, "newest in outbox")
    _, why = ns.Comm.onMessage("GFTK", "1~a4~1~1~" .. ns.Comm.encodeBody(peerData({ capturedAt = t + 3600 })), "GUILD", PEER)
    eq(why, "future", "future capturedAt rejected")
end)

test("outbox cap: old member.report first, then the oldest member.share, then the rest", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = { sync = { outbox = {
        { id = "x:1:member.report:y", kind = "member.report", capturedAt = 1763360000,
          game = { world = "forever" }, uploader = { guild = "綠皮與獠牙冒險事務所", realm = "測試伺服器" },
          payload = { subject = { name = "測試丁-測試伺服器" } } } } } } })
    ns.Sync.MAX_OUTBOX = 4
    local others = { "測試丙-測試伺服器", "測試丁-測試伺服器" }
    sendFrom(ns, PEER, peerData(), "b1")
    for i, who in ipairs(others) do
        wow.state.now = wow.state.now + 10
        sendFrom(ns, who, peerData({ capturedAt = wow.state.now }), "c" .. i)
    end
    eq(#entriesOf("member.report"), 1, "old member.report still there")
    wow.state.now = wow.state.now + 10
    eq(ns.Sync.recordShares(), 3, "three subjects")
    eq(#ns.db.sync.outbox, 4, "cap kept")
    eq(#entriesOf("member.report"), 0, "member.report dropped first")
    eq(#entriesOf("character.self"), 1, "character.self kept")
    eq(#entriesOf("roster.snapshot"), 1, "roster.snapshot kept")
    eq(#entriesOf("member.share"), 2, "then the oldest member.share")
    ns.Sync.MAX_OUTBOX = nil
    ns.Sync.MIN_SHARES = 1
    eq(ns.Sync.shareCap(), 4, "share cap follows the roster (4 members)")
    ns.Sync.MIN_SHARES = 150
end)

test("roster window: shared professions show skill points and update time", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    local member
    for _, m in ipairs(ns.Roster.current().members) do if m.name == PEER then member = m end end
    local detail = ns.UI.detailFor(member)
    ok(detail, "detail for the member who shared")
    eq(detail.source, "公會成員分享", "source")
    eq(ns.UI.skillLabel(detail.professions[3]), "釣魚 150 / 225", "label")
    eq(ns.UI.updatedText, nil, "no update time text (D19)")
    local peerCell = profCell(rosterRow(ns, PEER))
    ok(peerCell:find("^Trade_Mining:300|"), "shared skill points in the list: " .. peerCell)
    local ownCell = profCell(rosterRow(ns, "測試甲-測試伺服器"))
    ok(ownCell:find(":151", 1, true), "own row uses own skill points: " .. ownCell)
    local quiet
    for _, m in ipairs(ns.Roster.current().members) do if m.name == "測試丁-測試伺服器" then quiet = m end end
    eq(ns.UI.detailFor(quiet), nil, "members without data unchanged")
end)

test("notice: D-015 wording, shown again once (version 4)", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2, settings = {}, roster = { snapshots = {} },
        sync = { enabled = true, noticeShown = true, noticeVersion = 3, outbox = {} } } })
    eq(ns.Sync.NOTICE, "綠皮冒險工具箱會分享你的等級、職業、專業、配方和所在地給公會內有裝工具箱的人，並可能由他們上傳到公會網站。", "notice text")
    ok(printedContains("會分享你的等級、職業、專業、配方和所在地"), "shown again")
    eq(GreenFangToolkitDB.sync.noticeVersion, 4, "version 4")
    ok(not ns.Sync.NOTICE:find("設定", 1, true), "no switch to point to")
end)

test("share: works without C_ChatInfo (feature off, nothing breaks)", function()
    wow.reset({ noChatInfo = true })
    local ns = wow.login(ADDON_DIR)
    eq(ns.Comm.available(), false, "unavailable")
    eq(#entriesOf("character.self"), 1, "rest still works")
end)

---------------------------------------------------------------------------
-- GF-001-D8 profession list, own professions open windows
---------------------------------------------------------------------------

test("D8 professions: window spells by skillLineID, names from the client; no fishing/herbalism/skinning", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local P = ns.Professions
    local expect = { [164] = "鍛造", [165] = "製皮", [197] = "裁縫", [202] = "工程學", [171] = "鍊金術",
        [333] = "附魔", [185] = "烹飪", [129] = "急救", [186] = "熔煉" }
    for id, name in pairs(expect) do eq(P.windowSpell({ skillLineID = id }), name, "spell for " .. id) end
    for _, id in ipairs({ 356, 182, 393 }) do
        eq(P.windowSpell({ skillLineID = id }), nil, "no window for " .. id)
        eq(P.WINDOW_SPELL[id], nil, "never mapped: " .. id)
    end
    eq(P.windowSpell({ name = "釣魚" }), nil, "fishing by name: nothing")
    eq(P.windowSpell({ name = "鍛造" }), "鍛造", "name resolves through skillLineID")
    -- Spell names are never written in the source: only string literals checked.
    local f = assert(io.open(ADDON_DIR .. "/Professions.lua", "rb"))
    local src = f:read("*a"); f:close()
    for _, lit in ipairs(stringLiterals(src)) do
        for _, name in pairs(expect) do
            ok(not lit:find(name, 1, true), "hard-coded spell name " .. name .. " in " .. lit)
        end
    end
    wow.reset({ noSpellAPI = true })
    ns = wow.login(ADDON_DIR)
    eq(ns.Professions.windowSpell({ skillLineID = 164 }), nil, "no spell API -> no button")
end)

local function crafter()
    local p = wow.defaultPlayer()
    p.professions = {
        [1] = { "鍛造", 136241, 34, 75, 0, 0, 164 },
        [2] = { "採礦", 136248, 50, 75, 0, 0, 186 },
        [3] = { "急救", 135966, 10, 75, 0, 0, 129 },
        [4] = { "釣魚", 136245, 20, 75, 0, 0, 356 },
        [5] = { "烹飪", 133971, 1, 75, 0, 0, 185 },
    }
    p.professionIndexes = { 1, 2, 3, 4, 5 }
    return p
end

local function spellsOf(list)
    local names = {}
    for _, b in ipairs(list) do names[#names + 1] = b:GetAttribute("spell") end
    table.sort(names)
    return table.concat(names, ",")
end

test("D8 character page: secure spell buttons for professions with a window only", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("character")
    local shown = ns.Professions.shown("character")
    eq(spellsOf(shown), "急救,烹飪,熔煉,鍛造", "鍛造, 熔煉 for mining, 烹飪, 急救; not 釣魚")
    for _, b in ipairs(shown) do
        ok(b._protected, "secure")
        eq(b:GetAttribute("type"), "spell", "type=spell")
        eq(b._parent, UIParent, "parented to UIParent, not the toolkit window")
        ok(b:GetAttribute("spell") ~= "釣魚", "fishing never bound")
    end
    local smith
    for _, b in ipairs(shown) do if b:GetAttribute("spell") == "鍛造" then smith = b end end
    eq(wow.click(smith), "spell:鍛造", "click opens the window")
    eq(table.concat(wow.state.casts, ","), "鍛造", "only that spell cast")
    ok(not table.concat(wow.allTexts(), "\n"):find("點專業可以開啟技能視窗", 1, true), "no hint (D19)")
    ns.Framework.open("sleepingbag")
    eq(#ns.Professions.shown("character"), 0, "hidden with the page")
    ns.Framework.open("character")
    eq(#ns.Professions.shown("character"), 4, "back with the page")
    eq(#wow.state.blocked, 0, "nothing blocked")
end)

test("D8 combat: profession buttons hidden at combat start, untouched in lockdown, back after", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("character")
    eq(#ns.Professions.shown("character"), 4, "shown out of combat")
    wow.enterCombat()
    eq(#ns.Professions.shown("character"), 0, "hidden at PLAYER_REGEN_DISABLED")
    for _, b in ipairs(ns.Professions.sets.character) do eq(#b._points, 0, "unanchored") end
    ns.Character.refresh()                -- e.g. SKILL_LINES_CHANGED in combat
    wow.fire("SKILL_LINES_CHANGED"); wow.advance(5)
    ns.Framework.open("roster")           -- the window still works in combat
    ns.Framework.open("character")
    eq(#wow.state.blocked, 0, "no protected change during the lockdown")
    eq(#ns.Professions.shown("character"), 0, "still hidden in combat")
    for _, b in ipairs(ns.Professions.sets.character) do eq(wow.click(b), "ignored", "not clickable") end
    eq(#wow.state.casts, 0, "nothing cast in combat")
    wow.leaveCombat()
    eq(#ns.Professions.shown("character"), 4, "back after combat")
end)

local function rowFor(ns, name)
    for _, row in ipairs(ns.UI.rows()) do
        if row:IsShown() and row.memberName == name then return row end
    end
end

local rowTexts = profCell

test("D18 roster: icon + skill points, primary then secondary, － without data", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    local own = rowFor(ns, "測試甲-測試伺服器")
    -- Own icons are the file IDs GetProfessionInfo returns.
    eq(rowTexts(own), "136241:34|136248:50|135966:10|136245:20|133971:1", "own: primary first, then secondary")
    local peer = rowFor(ns, PEER)
    eq(rowTexts(peer), "Trade_Mining:300|Trade_BlackSmithing:280|Trade_Fishing:150|INV_Misc_Food_15:90|Spell_Holy_SealOfSacrifice:75",
        "peer: every profession fits as icon + points")
    eq(peer.profSlots[3].label._color[1], 0.72, "secondary points in the secondary colour")
    eq(peer._h, 36, "GF-UI-B: 36 px rows")
    eq(rowTexts(rowFor(ns, "測試丙-測試伺服器")), "Trade_Tailoring|Trade_Engraving", "names only: icons without points")
    eq(rowTexts(rowFor(ns, "測試丁-測試伺服器")), "－", "no data: a faint dash")
    eq(rowFor(ns, "測試丁-測試伺服器").profSlots[1].label._color[1], 0.42, "the dash is faint")
    peer._scripts.OnEnter(peer)
    local tip = ns.UI.rosterCardText() -- GF-UI-I: the member card
    for _, want in ipairs({ "採礦 300 / 300", "鍛造 280 / 300", "釣魚 150 / 225", "烹飪 90 / 150", "急救 75 / 150" }) do
        ok(tip:find(want, 1, true), "tooltip has " .. want)
    end
    for _, gone in ipairs({ "更新時間", "公會成員分享", "本人", "點", "分鐘前" }) do
        ok(not tip:find(gone, 1, true), "row tooltip has no " .. gone .. ": " .. tip)
    end
    for _, t in ipairs(wow.allTexts()) do ok(not t:find("…", 1, true), "no ellipsis in any text: " .. t) end
end)

test("D18 roster: a reused row measures its new text in full (the 0.9.2 「剝…」/「…」 rows)", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    local members = {}
    for _, m in ipairs(ns.Roster.current().members) do members[m.name] = m end
    local row = rowFor(ns, "測試丁-測試伺服器")
    -- Same row, longer content each time: no data -> peer -> names only -> icons missing (text).
    wow.state.missingFiles = {}
    ns.UI.fillRow(row, members[PEER])
    eq(rowTexts(row), "Trade_Mining:300|Trade_BlackSmithing:280|Trade_Fishing:150|INV_Misc_Food_15:90|Spell_Holy_SealOfSacrifice:75", "peer after no data")
    for _, path in pairs(ns.Icons.PROFESSION) do wow.state.missingFiles[path] = true end
    ns.UI.fillRow(row, members["測試丁-測試伺服器"])
    ns.UI.fillRow(row, members["測試丙-測試伺服器"])
    eq(rowTexts(row), "裁縫|附魔", "no icon in the client: the name instead")
    ns.UI.fillRow(row, members[PEER])
    -- GF-UI-B: 16 px text: four fit, 急救 is left to the tooltip.
    eq(rowTexts(row), "採礦 300|鍛造 280|釣魚 150|烹飪 90", "no icon: name and points")
    for k, s in ipairs(row.profSlots) do
        ok(not s.label:IsTruncated(), "slot " .. k .. " not cut: " .. s.label:GetText())
    end
    wow.state.missingFiles = nil
end)

test("D18 roster: secondary professions only while they fit; hidden primaries are counted", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    local peer = rowFor(ns, PEER)
    local member
    for _, m in ipairs(ns.Roster.current().members) do if m.name == PEER then member = m end end
    local width = peer.profW
    peer.profW = 120 -- GF-UI-B: 2 icons with 3 digits fit (54 + 8 + 54), a third does not
    ns.UI.fillRow(peer, member)
    eq(rowTexts(peer), "Trade_Mining:300|Trade_BlackSmithing:280", "secondaries left to the tooltip, not counted")
    sendFrom(ns, PEER, peerData({ professions = {
        { name = "採礦", skillLineID = 186, rank = 300, max = 300 },
        { name = "鍛造", skillLineID = 164, rank = 280, max = 300 },
        { name = "工程學", skillLineID = 202, rank = 5, max = 75 },
        { name = "釣魚", skillLineID = 356, rank = 150, max = 225 } } }), "a2")
    peer.profW = 80
    ns.UI.fillRow(peer, member)
    eq(rowTexts(peer), "Trade_Mining:300|+2", "room kept for +N while primaries remain")
    peer.profW = width
    ns.UI.fillRow(peer, member)
    eq(rowTexts(peer), "Trade_Mining:300|Trade_BlackSmithing:280|Trade_Engineering:5|Trade_Fishing:150", "full width again")
end)

test("D18 roster: sorting by 專業技能 still uses the profession names", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("roster")
    local list = ns.UI.sortMembers(ns.UI.filterMembers(ns.Roster.current().members, ""), "professions", true)
    local last = list[#list]
    ok(type(last.professions) ~= "table" or #last.professions == 0, "members without professions sort last")
    local names = {}
    for _, m in ipairs(list) do
        if type(m.professions) == "table" and #m.professions > 0 then names[#names + 1] = table.concat(m.professions, "、") end
    end
    ok(#names >= 2, "several members with professions")
    local desc = ns.UI.sortMembers(ns.UI.filterMembers(ns.Roster.current().members, ""), "professions", false)
    ok(type(desc[#desc].professions) ~= "table" or #desc[#desc].professions == 0, "still last when descending")
    ok(desc[1] ~= list[1] or #names == 1, "descending changes the order")
end)

test("D8 roster: own row only gets secure buttons; none for others; hidden when scrolled away", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    -- GF-UI-B: 36 px rows; a list frame of the mock's 140 px holds only 3 of them.
    wow.state.minimapSize = 400
    ns.UI.refresh(true)
    local own = rowFor(ns, "測試甲-測試伺服器")
    local shown = ns.Professions.shown("roster")
    -- D18: all five fit as icons; 釣魚 has no window, so four buttons.
    eq(spellsOf(shown), "急救,烹飪,熔煉,鍛造", "own visible professions with a window")
    for _, b in ipairs(shown) do eq(b._points[1][2], own, "anchored to the own row only") end
    ns.UI.scrollFrame():SetVerticalScroll(200)
    eq(#ns.Professions.shown("roster"), 0, "own row scrolled out of view -> hidden")
    ns.UI.scrollFrame():SetVerticalScroll(0)
    eq(#ns.Professions.shown("roster"), 4, "back in view")
    ns.Framework.open("sleepingbag")
    eq(#ns.Professions.shown("roster"), 0, "hidden with the page")
    ns.Framework.open("roster")
    eq(#ns.Professions.shown("roster"), 4, "back with the page")
    ns.Framework.toggle() -- close the toolkit window
    eq(#ns.Professions.shown("roster"), 0, "hidden when the window closes")
    eq(#wow.state.blocked, 0, "nothing blocked")
end)


---------------------------------------------------------------------------
-- GF-001-D9 (D-012): no 「同步到網站」 button; upload only after logout
---------------------------------------------------------------------------

test("D9 sync button removed: no button, dialog, /reload text or reload anywhere", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    eq(ns.syncNow, nil, "no ns.syncNow")
    eq(ns.syncDialog, nil, "no ns.syncDialog")
    eq(ns.createSyncNowButton, nil, "no button factory")
    eq(ns.refreshSyncNowButtons, nil, "no button refresh")
    eq(ns.SYNC_NOW_TEXT, nil, "no dialog text")
    for _, id in ipairs({ "character", "recipes", "roster", "sleepingbag", "character" }) do
        ns.Framework.open(id)
    end
    SlashCmdList.GREENFANGTOOLKIT("")
    SlashCmdList.GREENFANGTOOLKIT("sync status")
    eq(_G.GreenFangToolkit_SyncConfirm, nil, "no confirm dialog frame")
    eq(_G.GreenFangToolkit_SyncConfirmYes, nil, "no secure /reload button")
    eq(ns.Character.syncNowButton, nil, "character page has no sync button")
    eq(ns.Settings, nil, "no settings page (D-015)")
    for _, t in ipairs(wow.allTexts()) do
        ok(not t:find("同步到網站", 1, true), "widget text mentions the button: " .. t)
        ok(not t:find("/reload", 1, true), "widget text mentions /reload: " .. t)
        ok(not t:find("重新載入", 1, true), "widget text mentions reloading: " .. t)
    end
    for _, line in ipairs(wow.printed()) do
        ok(not line:find("同步到網站", 1, true), "chat mentions the button: " .. line)
        ok(not line:find("/reload", 1, true), "chat mentions /reload: " .. line)
    end
    for _, o in ipairs(wow.allObjects()) do
        if o._attrs then
            ok(o._attrs.type ~= "macro", "no secure macro button left")
        end
    end
    eq(wow.state.reloads, 0, "never reloads")
    eq(#wow.state.blocked, 0, "nothing blocked")
end)

test("D9 upload still happens after logout (character.self written at PLAYER_LOGOUT)", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    wow.advance(60)
    local before = #entriesOf("character.self")
    wow.logout()
    ok(#entriesOf("character.self") >= math.max(before, 1), "own record in the outbox at logout")
    eq(wow.state.reloads, 0, "no reload involved")
end)

test("D9 combat flag kept: PLAYER_REGEN_DISABLED hides profession buttons before InCombatLockdown", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("character")
    eq(#ns.Professions.shown("character"), 4, "shown out of combat")
    wow.fire("PLAYER_REGEN_DISABLED") -- lockdown not active yet (InCombatLockdown() false)
    ok(ns.inCombat(), "combat flag set by the event")
    eq(#ns.Professions.shown("character"), 0, "hidden from the first combat event")
    ns.Character.refresh()
    eq(#ns.Professions.shown("character"), 0, "refresh does not bring them back")
    wow.fire("PLAYER_REGEN_ENABLED")
    ok(not ns.inCombat(), "flag cleared")
    eq(#ns.Professions.shown("character"), 4, "back after combat")
    eq(#wow.state.blocked, 0, "nothing blocked")
end)

---------------------------------------------------------------------------
-- GF-001-D10 (D-014): GFTKS sharing and relaying
---------------------------------------------------------------------------

local A_SELF, A_PEER, A_THIRD = "0000-0000000A", "0000-0000000B", "0000-0000000C"
local THIRD = "測試丙-測試伺服器"
local function has(s, sub) return s:find(sub, 1, true) ~= nil end
local function starts(s, prefix) return s:sub(1, #prefix) == prefix end

local function shareSent(kind)
    local list = {}
    for _, s in ipairs(wow.state.sent) do
        if s.prefix == "GFTKS" and (not kind or s.msg:sub(1, #kind + 4) == "S1~" .. kind .. "~") then
            list[#list + 1] = s.msg
        end
    end
    return list
end

local function shareFrom(ns, sender, text)
    return ns.Share.onMessage("GFTKS", text, "GUILD", sender)
end

-- "S1~V~..." for a value, as its author (or a relayer) would send it.
local function vMsg(ns, a, g, t, value)
    local v = ns.Share.encodeValue(g, value)
    return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v, v
end

-- Logged in, roster loaded, past the login delay, deterministic delays.
local function shareLogin(opts)
    wow.reset(opts)
    local ns = wow.login(ADDON_DIR)
    ns.Share.rand = function(a) return a end
    wow.advance(25)
    return ns
end

test("D10 codec: base 36, id deltas, hash and values round-trip", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    local S = ns.Share
    for _, n in ipairs({ 0, 1, 35, 36, 1763370000 }) do eq(S.unb36(S.b36(n)), n, "b36 " .. n) end
    local ids = { 3115, 2660, 9785, 2661, 2662, 16960, 2660 }
    local enc = S.encodeIDs(ids)
    eq(table.concat(S.decodeIDs(enc), ","), "2660,2661,2662,3115,9785,16960", "ids sorted, duplicates dropped")
    eq(S.hash("abc"), S.hash("abc"), "hash stable")
    ok(S.hash("abc") ~= S.hash("abd"), "hash differs")
    local b = S.decodeValue("B", S.encodeValue("B", { level = 60, classToken = "WARRIOR" }))
    eq(b.level, 60, "B level"); eq(b.classToken, "WARRIOR", "B class")
    local p = S.decodeValue("P", S.encodeValue("P", { { skillLineID = 186, rank = 300, max = 300 },
        { skillLineID = 164, rank = 34, max = 75 } }))
    eq(p[1].skillLineID, 186, "P keeps the author's order"); eq(p[2].rank, 34, "P rank")
    local z = S.decodeValue("Z", S.encodeValue("Z", { zone = "奧/格.瑪~", subZone = "力量谷" }))
    eq(z.zone, "奧/格.瑪~", "Z separators escaped"); eq(z.subZone, "力量谷", "Z subZone intact")
    eq(S.encodeValue("Z", { zone = "雷霆崖", subZone = "長者高地" }), "雷霆崖/長者高地", "UTF-8 not escaped")
    eq(S.decodeValue("B", "999.X"), nil, "bad level rejected")
    eq(S.decodeValue("P", "1,2"), nil, "bad P rejected")
end)

test("D10 login: own index and a catalog request; nothing before the delay", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    eq(#shareSent(), 0, "nothing in the first seconds")
    ns.Share.rand = function(a) return a end
    wow.advance(25)
    local idx = shareSent("I")
    eq(#idx, 1, "own index")
    ok(starts(idx[1], "S1~I~" .. A_SELF .. "~"), "index of myself")
    ok(idx[1]:find("~B%.") and idx[1]:find("~P%.") and idx[1]:find("~Z%."), "B, P and Z listed")
    eq(#shareSent("Q"), 1, "one catalog request")
    local recs = ns.Share.records(A_SELF)
    eq(ns.Share.decodeValue("B", recs.B.v).level, 32, "own level recorded")
    ok(recs.B.t <= wow.state.now and recs.B.t >= wow.state.now - 25, "t is server time at observation")
    for _, m in ipairs(shareSent()) do ok(#m <= 250, "fits: " .. m) end
end)

test("D10 receive: author's value stored, roster updated, relayed data uploaded too", function()
    local ns = shareLogin()
    local t = wow.state.now - 60
    eq(shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", t, { level = 61, classToken = "WARRIOR" }))), "new", "direct value")
    eq(ns.Comm.peerFor(PEER).level, 61, "roster data")
    eq(#entriesOf("member.report"), 0, "no member.report any more (0.10.0)")
    -- Relayed: PEER sends 測試丙's professions.
    local r = shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "P", t, { { skillLineID = 197, rank = 120, max = 150 } })))
    eq(r, "new", "relayed value accepted (D-014)")
    local third = ns.Comm.peerFor(THIRD)
    ok(third, "relayed data reaches the roster")
    eq(third.professions[1].name, "裁縫", "name from the receiving client")
    eq(ns.Share.get(A_THIRD, "P").fromAuthor, nil, "marked as relayed")
    wow.logout()
    eq(#entriesOf("member.share"), 2, "direct and relayed data both go to the site (D-014 point 3)")
end)

test("D10 newest wins: older ignored and answered with ours; same hash only moves t", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", t, { level = 40, classToken = "MAGE" })))
    wow.state.sent = {}
    eq(shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", t - 100, { level = 39, classToken = "MAGE" }))), "older", "older rejected")
    eq(ns.Share.decodeValue("B", ns.Share.get(A_THIRD, "B").v).level, 40, "newer kept")
    wow.advance(3)
    local pushed = shareSent("V")
    eq(#pushed, 1, "we answer with the newer copy")
    ok(starts(pushed[1], "S1~V~" .. A_THIRD .. "~B~" .. ns.Share.b36(t) .. "~"), "author and original time kept")
    eq(shareFrom(ns, PEER, "S1~I~" .. A_THIRD .. "~1~B." .. ns.Share.b36(t + 50) .. "." .. ns.Share.get(A_THIRD, "B").h), "ok", "index")
    eq(ns.Share.get(A_THIRD, "B").t, t + 50, "same hash, newer t: confirmed without data")
    wow.advance(2)
    eq(#shareSent("G"), 0, "nothing asked for a confirmation")
end)

test("D10 rejects: bad hash, future time, unknown author, sender outside the roster", function()
    local ns = shareLogin()
    local t = wow.state.now - 60
    local m = vMsg(ns, A_THIRD, "B", t, { level = 40 })
    eq(shareFrom(ns, PEER, (m:gsub("~40%.$", "~41."))), "invalid", "hash mismatch")
    eq(shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", wow.state.now + 3600, { level = 40 }))), "future", "future")
    eq(shareFrom(ns, PEER, (vMsg(ns, "9999-99999999", "B", t, { level = 40 }))), "unknown-author", "not a guild member")
    eq(shareFrom(ns, "路人-別的伺服器", m), "not-in-roster", "sender not in the guild")
    eq(ns.Share.onMessage("GFTKS", m, "PARTY", PEER), "channel", "guild (and whisper) only")
    eq(ns.Share.onMessage("GFTKS", "S1~Q~q1~0~0~w2", "WHISPER", PEER), "channel", "only data comes by whisper")
    eq(ns.Share.get(A_THIRD, "B"), nil, "nothing stored")
end)

test("D10 long values: recipes in B+D parts, any order of D, ids intact", function()
    local ns = shareLogin()
    local ids = {}
    for i = 1, 300 do ids[i] = 2000 + i * 37 end
    local v = ns.Share.encodeValue("R164", ids)
    local t = ns.Share.b36(wow.state.now - 60)
    local head = #("S1~D~" .. A_THIRD .. "~R164~" .. t .. "~zz~")
    local parts = {}
    for i = 1, #v, 250 - head do parts[#parts + 1] = v:sub(i, i + 250 - head - 1) end
    ok(#parts >= 3, "several parts")
    eq(shareFrom(ns, PEER, "S1~B~" .. A_THIRD .. "~R164~" .. t .. "~" .. ns.Share.hash(v) .. "~" .. ns.Share.b36(#parts)), "partial", "header")
    local last
    for i = #parts, 1, -1 do
        local m = "S1~D~" .. A_THIRD .. "~R164~" .. t .. "~" .. ns.Share.b36(i) .. "~" .. parts[i]
        ok(#m <= 250, "part fits")
        last = shareFrom(ns, PEER, m)
    end
    eq(last, "new", "assembled")
    eq(#ns.Share.decodeValue("R164", ns.Share.get(A_THIRD, "R164").v), 300, "300 recipes")
    -- And we can send it on in parts ourselves.
    wow.state.sent = {}
    ns.Share.sendRecord(A_THIRD, "R164", true)
    wow.advance(10)
    eq(#shareSent("B"), 1, "relayed header"); ok(#shareSent("D") >= 3, "relayed parts")
    for _, m in ipairs(shareSent()) do ok(#m <= 250, "fits") end
end)

test("D10 index compare: ask for newer, push what they lack or have older", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", t, { level = 40 })))
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "Z", t, { zone = "幽暗城" })))
    wow.advance(10); wow.state.sent = {}
    local newP = ns.Share.encodeValue("P", { { skillLineID = 333, rank = 1, max = 75 } })
    -- Their index: B older than ours, P we do not have, Z not listed.
    shareFrom(ns, PEER, "S1~I~" .. A_THIRD .. "~2~B." .. ns.Share.b36(t - 5) .. ".abc~P." .. ns.Share.b36(t + 5) .. "." .. ns.Share.hash(newP))
    wow.advance(2)
    local g = shareSent("G")
    eq(#g, 1, "asked")
    ok(has(g[1], A_THIRD .. ".P." .. ns.Share.b36(t + 5)), "for the newer P")
    wow.advance(6)
    local v = table.concat(shareSent("V"), "\n")
    ok(has(v, "~" .. A_THIRD .. "~B~"), "pushed our newer B")
    ok(has(v, "~" .. A_THIRD .. "~Z~"), "pushed the Z they lack")
end)

test("D10 index in several messages: wait for all parts before pushing what they lack", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", t, { level = 40 })))
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "Z", t, { zone = "幽暗城" })))
    local s = ns.Share.store()
    local hB, hZ = s.rec[A_THIRD].B.h, s.rec[A_THIRD].Z.h
    wow.advance(10); wow.state.sent = {}
    shareFrom(ns, PEER, "S1~I~" .. A_THIRD .. "~2~B." .. ns.Share.b36(t) .. "." .. hB)
    wow.advance(8)
    eq(#shareSent("V"), 0, "first part only: nothing pushed yet")
    shareFrom(ns, PEER, "S1~I~" .. A_THIRD .. "~2~Z." .. ns.Share.b36(t) .. "." .. hZ)
    wow.advance(8)
    eq(#shareSent("V"), 0, "complete and equal: nothing to push")
    shareFrom(ns, PEER, "S1~I~" .. A_THIRD .. "~1~B." .. ns.Share.b36(t) .. "." .. hB)
    wow.advance(8)
    eq(#shareSent("V"), 1, "complete without Z: Z pushed")
end)

test("D10 catalog: one replier; a heard reply cancels ours; asks only what differs", function()
    local ns = shareLogin()
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", wow.state.now - 60, { level = 40 })))
    wow.state.sent = {}
    eq(shareFrom(ns, PEER, "S1~Q~q1~0~0"), "ok", "they hold nothing")
    wow.advance(10)
    local c = shareSent("C")
    ok(#c >= 1, "catalog sent")
    ok(c[1]:find("^S1~C~q1~1~1~"), "part numbering")
    ok(has(table.concat(c), A_THIRD .. "."), "lists authors")
    wow.state.sent = {}
    shareFrom(ns, PEER, "S1~Q~q2~0~0")
    shareFrom(ns, THIRD, "S1~C~q2~1~1~" .. A_THIRD .. ".abc.1")
    wow.advance(10)
    eq(#shareSent("C"), 0, "someone else answered first")
    local count, digest = ns.Share.totalDigest()
    wow.state.sent = {}
    eq(shareFrom(ns, PEER, "S1~Q~q3~" .. ns.Share.b36(count) .. "~" .. digest), "same", "same digest: silent")
end)

test("D10 our catalog request: ask indexes for differing authors, share what only we know", function()
    local ns = shareLogin()
    local q = shareSent("Q")[1]:match("^S1~Q~([^~]+)~")
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", wow.state.now - 60, { level = 40 })))
    wow.state.sent = {}
    -- Catalog from PEER: knows 測試乙 (we do not), and not 測試丙 or us.
    shareFrom(ns, PEER, "S1~C~" .. q .. "~1~1~" .. A_PEER .. ".zz." .. ns.Share.b36(wow.state.now))
    wow.advance(8)
    local asks = table.concat(shareSent("A"))
    ok(has(asks, A_PEER), "index asked for the differing author")
    local idx = table.concat(shareSent("I"), "\n")
    ok(has(idx, "S1~I~" .. A_THIRD), "authors only we know go out")
end)

test("D10 replies: A gets our index, G gets the record; the author answers first", function()
    local ns = shareLogin()
    wow.state.sent = {}
    local own = ns.Share.get(A_SELF, "B")
    shareFrom(ns, PEER, "S1~G~" .. A_SELF .. ".B." .. ns.Share.b36(own.t))
    wow.advance(1.2)
    eq(#shareSent("V"), 1, "own record within a second")
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", wow.state.now - 60, { level = 40 })))
    wow.state.sent = {}
    shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".B." .. ns.Share.b36(wow.state.now - 60))
    shareFrom(ns, THIRD, (vMsg(ns, A_THIRD, "B", wow.state.now - 60, { level = 40 })))
    wow.advance(8)
    eq(#shareSent("V"), 0, "someone else sent it first: ours cancelled")
    shareFrom(ns, PEER, "S1~A~" .. A_THIRD)
    wow.advance(8)
    eq(#shareSent("I"), 1, "index on request")
end)

test("D11 tombstones: only R<id> (profession given up); X~* and X~Z are ignored (D-015)", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "Z", t, { zone = "幽暗城" })))
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "R164", t, { 2660, 2661 })))
    eq(shareFrom(ns, PEER, "S1~X~" .. A_THIRD .. "~Z~" .. ns.Share.b36(t + 10)), "same", "X~Z ignored")
    eq(shareFrom(ns, PEER, "S1~X~" .. A_THIRD .. "~*~" .. ns.Share.b36(t + 10)), "same", "X~* ignored")
    ok(ns.Share.get(A_THIRD, "Z"), "location kept")
    eq(shareFrom(ns, PEER, "S1~X~" .. A_THIRD .. "~R164~" .. ns.Share.b36(t + 10)), "tomb", "profession given up")
    eq(ns.Share.get(A_THIRD, "R164"), nil, "recipes gone")
    eq(shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "R164", t + 5, { 2660 }))), "tomb", "older recipes refused")
    eq(shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "R164", t + 20, { 2660 }))), "new", "relearned later: accepted")
    ok(table.concat(ns.Share.indexItems(A_THIRD), ";"):find("R164%." .. ns.Share.b36(t + 10) .. "%.x"), "tombstone in the index")
    shareFrom(ns, PEER, "S1~I~" .. A_PEER .. "~2~*." .. ns.Share.b36(t) .. ".x~R197." .. ns.Share.b36(t) .. ".x")
    eq(ns.Share.store().tomb[A_PEER]["*"], nil, "* from an index ignored")
    eq(ns.Share.store().tomb[A_PEER].R197, t, "R tombstone learned from an index")
end)

test("D11 sync.enabled is always true: fresh install, upgrade from false, and at logout (contract §3.4)", function()
    -- Fresh install.
    wow.reset()
    wow.login(ADDON_DIR)
    eq(GreenFangToolkitDB.sync.enabled, true, "fresh install writes true")
    -- Upgrade: an old false (0.8.x / 0.9.0 switch) becomes true and the file uploads again.
    wow.reset()
    local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = {
        schema = "gf.toolkit", schemaVersion = 2, addonVersion = "0.8.2", settings = {}, roster = { snapshots = {} },
        sync = { enabled = false, shareLocation = false, noticeShown = true, noticeVersion = 3, outbox = {} } } })
    eq(GreenFangToolkitDB.sync.enabled, true, "old false upgraded to true")
    ok(#entriesOf("character.self") >= 1, "data written again after the upgrade")
    -- Whatever happens in the session, the saved file says true.
    GreenFangToolkitDB.sync.enabled = false
    local saved = wow.logout()
    eq(saved.GreenFangToolkitDB.sync.enabled, true, "logout writes true")
    -- Next login reads it back as true.
    wow.reset()
    wow.login(ADDON_DIR, saved)
    eq(GreenFangToolkitDB.sync.enabled, true, "still true after relog")
    ok(ns.Sync.isEnabled(), "isEnabled")
end)

test("D11 no switches: always shares, location included, never sends X~* or X~Z", function()
    local ns = shareLogin()
    eq(ns.Sync.setEnabled, nil, "no sync switch")
    eq(ns.Sync.setShareLocation, nil, "no location switch")
    eq(ns.Share.watchSettings, nil, "no withdrawal watcher")
    ok(ns.Share.get(A_SELF, "Z"), "own location shared")
    wow.advance(60)
    for _, m in ipairs(shareSent("X")) do
        ok(not m:find("~*~", 1, true) and not m:find("~Z~", 1, true), "no privacy withdrawal: " .. m)
    end
end)

test("D10 rate limit: burst of 8, then about one per second; throttle answer waits", function()
    local ns = shareLogin()
    wow.advance(10)
    wow.state.sent = {}
    for i = 1, 20 do ns.Share.enqueue("S1~A~x" .. i, "ask") end
    wow.advance(0.6)
    eq(#shareSent(), 8, "burst")
    wow.advance(5)
    local n = #shareSent()
    ok(n >= 11 and n <= 14, "refills about 0.9 per second: " .. n)
    local real = C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage = function() return 3 end
    local before = #wow.state.sent
    wow.advance(3)
    eq(#wow.state.sent, before, "throttled: nothing recorded as sent")
    ok(ns.Share.stats.throttled >= 1, "counted")
    C_ChatInfo.SendAddonMessage = real
    wow.advance(30)
    eq(ns.Share.queued(), 0, "queue drained after the throttle")
end)

test("D10 combat and instances: hold messages; restricted check only inside instances", function()
    local ns = shareLogin()
    wow.advance(10)
    wow.state.sent = {}
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
    ns.Share.enqueue("S1~A~x", "ask")
    wow.advance(1)
    eq(#shareSent(), 1, "restricted=true outside an instance is ignored (GuildForge, Forever)")
    IsInInstance = function() return true end
    ns.Share.enqueue("S1~A~y", "ask")
    wow.advance(2)
    eq(#shareSent(), 1, "held inside a restricted instance")
    IsInInstance = nil
    wow.advance(2)
    eq(#shareSent(), 2, "sent after leaving")
    wow.enterCombat()
    ns.Share.enqueue("S1~A~z", "ask")
    wow.advance(2)
    eq(#shareSent(), 2, "held in combat")
    wow.leaveCombat()
    wow.advance(2)
    eq(#shareSent(), 3, "sent after combat")
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
end)

test("D10 GFTK (0.8.x) still works and becomes records; its restricted check is fixed too", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
    wow.state.sent = {}
    ns.Comm.broadcast(true)
    eq(#v1Sent(), 1, "GFTK sent although the check says restricted (outside instances)")
    sendFrom(ns, PEER, peerData())
    local recs = ns.Share.records(A_PEER)
    ok(recs and recs.B and recs.P and recs.Z, "B, P, Z records from a GFTK message")
    eq(recs.B.t, peerData().capturedAt, "t is the sender's capturedAt")
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
end)

test("D10 prune: authors gone from the roster for 14 days are forgotten", function()
    local ns = shareLogin()
    local s = ns.Share.store()
    s.rec["7777-77777777"] = { B = { t = wow.state.now - 60, h = "x1", v = "1." } }
    ns.Share.prune()
    ok(s.rec["7777-77777777"], "kept at first")
    wow.state.now = wow.state.now + 15 * 86400
    ns.Share.prune()
    eq(s.rec["7777-77777777"], nil, "forgotten after 14 days")
    s.tomb[A_THIRD] = { Z = wow.state.now - 61 * 86400 }
    ns.Share.prune()
    eq(s.tomb[A_THIRD], nil, "old tombstones dropped")
end)

test("D10 slash: /gftk and /綠皮; /gf is not registered (GuildForge uses it)", function()
    wow.reset()
    wow.login(ADDON_DIR)
    eq(SLASH_GREENFANGTOOLKIT1, "/gftk", "/gftk")
    eq(SLASH_GREENFANGTOOLKIT2, "/綠皮", "/綠皮")
    eq(SLASH_GREENFANGTOOLKIT3, nil, "no third alias")
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^SLASH_GREENFANG") then ok(v ~= "/gf", "no /gf: " .. k) end
    end
end)

---------------------------------------------------------------------------
-- GF-001-D10 phase 2: own recipes, the 「配方」 page, roster and character page
---------------------------------------------------------------------------

local function leatherWindow(recipes, extra)
    local ts = { skillLine = 165, recipes = recipes or { [2152] = true, [2149] = true, [2153] = false } }
    for k, v in pairs(extra or {}) do ts[k] = v end
    return ts
end

local function rMsg(ns, a, skill, t, ids)
    return vMsg(ns, a, "R" .. skill, t, ids)
end

test("D10 recipes: own window read (learned only), stored as R165, sent after a while", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    wow.state.sent = {}
    wow.fire("TRADE_SKILL_SHOW")
    local rec = ns.Share.get(A_SELF, "R165")
    ok(rec, "stored")
    eq(table.concat(ns.Share.decodeValue("R165", rec.v), ","), "2149,2152", "learned recipes only")
    eq(#shareSent("V"), 0, "not sent at once")
    wow.advance(35)
    local v = shareSent("V")
    eq(#v, 1, "sent once after the delay (re-reads at 2 s and 5 s do not repeat it)")
    ok(starts(v[1], "S1~V~" .. A_SELF .. "~R165~"), "own recipe record")
end)

test("D10 recipes: someone else's window, not ready, empty list or combat are not read", function()
    for _, extra in ipairs({ { linked = true }, { guild = true }, { guildMember = true }, { ready = false } }) do
        local ns = shareLogin({ tradeSkill = leatherWindow(nil, extra) })
        eq(ns.Recipes.scan(), "not-own", "skipped")
        eq(ns.Share.get(A_SELF, "R165"), nil, "nothing stored")
    end
    local ns = shareLogin({ tradeSkill = leatherWindow({ [2152] = false }) })
    eq(ns.Recipes.scan(), "empty", "list not loaded yet")
    wow.enterCombat()
    eq(ns.Recipes.scan(), "combat", "not in combat")
    wow.leaveCombat()
    ns = shareLogin({ tradeSkill = { skillLine = 999, recipes = { [2152] = true } } })
    eq(ns.Recipes.scan(), "unknown", "unknown profession")
end)

test("D10 recipes: a filtered (smaller) list keeps the saved one; new recipes merge; same list confirms", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    eq(ns.Recipes.scan(), "stored", "first read")
    local t0 = ns.Share.get(A_SELF, "R165").t
    wow.state.tradeSkill.recipes = { [2152] = true }
    wow.clearPrinted()
    eq(ns.Recipes.scan(), "filtered", "subset")
    eq(#ns.Share.decodeValue("R165", ns.Share.get(A_SELF, "R165").v), 2, "saved list kept")
    ok(not printedContains("篩選"), "nothing in chat (D19)")
    ok(ns.Diag.shareText():find("專業視窗有篩選，配方沒有更新：製皮", 1, true), "noted in 同步與診斷")
    wow.state.tradeSkill.recipes = { [2152] = true, [2660] = true }
    eq(ns.Recipes.scan(), "stored", "new recipe")
    eq(table.concat(ns.Share.decodeValue("R165", ns.Share.get(A_SELF, "R165").v), ","), "2149,2152,2660", "union")
    wow.advance(5)
    wow.state.tradeSkill.recipes = { [2149] = true, [2152] = true, [2660] = true }
    eq(ns.Recipes.scan(), "same", "unchanged")
    ok(ns.Share.get(A_SELF, "R165").t > t0, "time moved forward")
end)

test("D10 recipes: a profession given up withdraws its recipes", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    ns.Recipes.scan()
    wow.state.player.professions[1] = nil
    wow.state.player.professionIndexes = { nil, 2, nil, 4, 5 }
    wow.state.sent = {}
    wow.fire("SKILL_LINES_CHANGED")
    wow.advance(40)
    eq(ns.Share.get(A_SELF, "R165"), nil, "recipes gone")
    local x = shareSent("X")
    ok(#x >= 1 and starts(x[1], "S1~X~" .. A_SELF .. "~R165~"), "withdrawal sent")
end)

test("D10 recipe index: who makes what, online first, search, one member", function()
    local ns = shareLogin()
    local t = wow.state.now - 3 * 86400
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, t, { 2660, 2661, 2662 })))
    shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 164, t, { 2660, 3115 })))
    local index = ns.Recipes.index()
    ok(index[164], "blacksmithing known")
    eq(#index[164].crafters, 2, "two crafters")
    local rows = ns.Recipes.rows(index, 164, "", nil)
    eq(#rows, 4, "four recipes")
    local first = rows[1]
    for _, r in ipairs(rows) do if r.id == 2660 then first = r end end
    eq(#first.crafters, 2, "both make 2660")
    eq(first.crafters[1].name, PEER, "online first")
    ok(first.crafters[2].relayed, "relayed by 測試乙")
    eq(#ns.Recipes.rows(index, 164, "砂輪", nil), 1, "search by name")
    eq(#ns.Recipes.rows(index, 164, "", "Player-0000-0000000C"), 2, "one member")
    eq(ns.Recipes.name(99999), "配方 #99999", "unknown name")
    eq(ns.Recipes.agoText(t), "3 天前", "age")
    eq(ns.Recipes.crafterText({ { name = "甲-x" }, { name = "乙-x" }, { name = "丙-x" }, { name = "丁-x" } }),
        "甲、乙、丙 +1", "crafter text")
end)

test("D10 recipe page: tabs per profession, rows, filter by member, empty text", function()
    local ns = shareLogin()
    ns.Framework.open("recipes")
    ok(ns.Framework.isModuleShown("recipes"), "page opens")
    local panel = ns.Framework.panel("recipes")
    local function texts()
        local list = {}
        for _, t in ipairs(wow.allTexts()) do list[#list + 1] = t end
        return table.concat(list, "\n")
    end
    ok(has(texts(), "沒有配方"), "empty text (GF-UI-B: no sentence)")
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, t, { 2660, 2661 })))
    shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 197, t, { 3115 })))
    wow.advance(1.2) -- the page redraws at most once a second
    ok(has(texts(), "粗製磨刀石"), "recipe listed")
    eq(table.concat(ns.Recipes.state.skills, ","), "164,197", "every profession ticked (D22)")
    ns.Recipes.show("Player-0000-0000000C")
    eq(table.concat(ns.Recipes.state.skills, ","), "197", "member's own profession")
    ok(has(texts(), "只看：測試丙"), "filter shown")
    ok(ns.Recipes.clearFilterButton:IsShown(), "clear button")
    wow.click(ns.Recipes.clearFilterButton)
    eq(ns.Recipes.state.guid, nil, "filter cleared")
    ns.Recipes.searchBox:SetText("鎖甲")
    ns.Recipes.searchBox._scripts.OnTextChanged(ns.Recipes.searchBox)
    ns.Recipes.skillChoice.setOnly(164)
    eq(#ns.Recipes.rows(ns.Recipes.index(), 164, ns.Recipes.state.query, nil), 1, "search applied")
    ok(panel, "panel exists")
end)

test("D10 roster: tooltip shows recipe counts; clicking a member opens their recipes", function()
    local ns = shareLogin()
    sendFrom(ns, PEER, peerData())
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, wow.state.now - 7200, { 2660, 2661 })))
    ns.Framework.open("roster")
    local row = rowFor(ns, PEER)
    ok(row, "row")
    row._scripts.OnEnter(row)
    local lines = ns.UI.rosterCardText() -- GF-UI-I: the member card
    ok(has(lines, "配方 2 個"), "recipe count in tooltip: " .. lines)
    ok(not has(lines, "小時前"), "no age (D19)")
    ok(not has(lines, "點一下看他的配方"), "no click hint (D19)")
    row._scripts.OnMouseUp(row, "LeftButton")
    -- GF-UI-C (owner): 配方 is in the right-click menu (the bar keeps 密語 / 組隊 / 查看).
    local recipesItem
    for _, it in ipairs(ns.UI.memberMenuItems(row.member)) do if it.key == "recipes" then recipesItem = it end end
    ok(recipesItem, "配方 in the member menu")
    recipesItem.fn()
    ok(ns.Framework.isModuleShown("recipes"), "recipe page opened")
    eq(ns.Recipes.state.guid, "Player-0000-0000000B", "filtered to that member")
    ns.Framework.open("roster")
    local other = rowFor(ns, "測試丁-測試伺服器")
    other._scripts.OnMouseUp(other, "LeftButton")
    ok(ns.Framework.isModuleShown("roster"), "no recipes: stays on the roster")
    for _, it in ipairs(ns.UI.memberMenuItems(other.member)) do ok(it.key ~= "recipes", "no 配方 item") end
end)

test("D10 character page: recipe line per craft profession", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    ns.Framework.open("character")
    local function texts() return table.concat(wow.allTexts(), "\n") end
    ok(not has(texts(), "還沒記錄配方"), "no hint before the window was opened (D19)")
    wow.fire("TRADE_SKILL_SHOW")
    wow.fire("TRADE_SKILL_CLOSE") -- GF-UI-C: the toolkit steps aside while it is open
    ok(has(texts(), "配方 2 個"), "after opening the window")
    ok(not has(texts(), "剛剛記錄"), "no time (D19)")
end)

test("D10 diag window: sections, sharing stats, export moved here, /gftk sync status opens it", function()
    local ns = shareLogin()
    eq(ns.Diag.isShown(), false, "closed at first")
    SlashCmdList.GREENFANGTOOLKIT("sync status")
    ok(ns.Diag.isShown(), "opened by the advanced command")
    local texts = {}
    for _, l in ipairs(ns.Diag.lines()) do texts[#texts + 1] = l:GetText() end
    local all = table.concat(texts, "\n")
    ok(has(all, "待上傳"), "site sync")
    ok(has(all, "GF Sync 只是補充來源"), "site note")
    ok(has(all, "記錄 ") and has(all, "這次登入：送出"), "sharing statistics")
    ok(has(all, "掃描時間："), "roster scan")
    ok(has(all, "工具箱 0.16.6"), "version")
    wow.click(ns.Diag.exportJSONButton)
    ok(_G.GreenFangToolkit_ExportWindow and _G.GreenFangToolkit_ExportWindow:IsShown(), "export from the window")
    GreenFangToolkitDB.settings.minimapAngle = 10
    wow.click(ns.Diag.minimapButton)
    eq(GreenFangToolkitDB.settings.minimapAngle, ns.DEFAULT_MINIMAP_ANGLE, "minimap reset lives here now")
end)

test("D10 simple pages: no pending counts, scan details or GF Sync text on the roster and settings pages", function()
    local ns = shareLogin()
    ns.Framework.open("roster")
    ns.Framework.open("settings")
    ns.Framework.open("recipes")
    ns.Framework.open("character")
    for _, t in ipairs(wow.allTexts()) do
        ok(not t:find("待上傳", 1, true), "pending count on a page: " .. t)
        ok(not t:find("GF Sync", 1, true), "GF Sync text on a page: " .. t)
        ok(not t:find("伺服器：", 1, true), "realm detail on a page: " .. t)
    end
end)

---------------------------------------------------------------------------
-- GF-001-D11: a 115-member guild must not slow the game (D-015 point 5)
---------------------------------------------------------------------------

local function bigRoster(n)
    local list = wow.defaultRoster()
    for i = #list + 1, n do
        list[i] = { name = string.format("成員%03d-測試伺服器", i), rank = "會員", level = 60,
            class = "戰士", classToken = "WARRIOR", zone = "奧格瑪", online = i % 3 == 0,
            guid = string.format("Player-0000-%08X", 0x100 + i) }
    end
    return list
end

GF_PERF = {}

-- Lua values GF Sync's parser counts (claude-sync 7e5d84a, limit 2,000,000):
-- counted generously as every table, every key and every value.
local function luaValues(v)
    if type(v) ~= "table" then return 1 end
    local n = 1
    for k, x in pairs(v) do n = n + 1 + luaValues(x) end
    return n
end

test("D11 performance: 115 members, every record, recipes, catalog, pages, save size", function()
    local ns = shareLogin({ roster = bigRoster(115) })
    local S = ns.Share
    local members = ns.Roster.current().members
    eq(#members, 115, "115 members")
    local t = wow.state.now - 3600
    -- A profession has about 350 recipes in all; each crafter knows 300 of them.
    local function recipeList(seed)
        local ids = {}
        for k = 1, 350 do
            if (k + seed) % 7 ~= 0 then ids[#ids + 1] = 2000 + k * 13 end
        end
        return ids
    end
    collectgarbage("collect")
    local memBefore = collectgarbage("count")
    -- Every member (but us) shares B, P, Z and three recipe lists of 300, as messages.
    local msgs = {}
    for i, m in ipairs(members) do
        local a = S.authorOf(m.guid)
        if a ~= A_SELF then
            msgs[#msgs + 1] = (vMsg(ns, a, "B", t, { level = 60, classToken = "WARRIOR" }))
            msgs[#msgs + 1] = (vMsg(ns, a, "P", t, { { skillLineID = 164, rank = 300, max = 300 },
                { skillLineID = 186, rank = 300, max = 300 }, { skillLineID = 185, rank = 300, max = 300 } }))
            msgs[#msgs + 1] = (vMsg(ns, a, "Z", t, { zone = "奧格瑪", subZone = "力量谷" }))
        end
    end
    local c0 = os.clock()
    for _, m in ipairs(msgs) do shareFrom(ns, PEER, m) end
    local small = os.clock() - c0
    -- Recipes: header + parts, like the wire.
    local parts = 0
    c0 = os.clock()
    for i, m in ipairs(members) do
        local a = S.authorOf(m.guid)
        if a ~= A_SELF then
            for _, skill in ipairs({ 164, 186, 185 }) do
                local v = S.encodeValue("R" .. skill, recipeList(i + skill))
                local tb = S.b36(t)
                local head = #("S1~D~" .. a .. "~R" .. skill .. "~" .. tb .. "~zz~")
                local chunks = {}
                for k = 1, #v, 250 - head do chunks[#chunks + 1] = v:sub(k, k + 250 - head - 1) end
                shareFrom(ns, PEER, "S1~B~" .. a .. "~R" .. skill .. "~" .. tb .. "~" .. S.hash(v) .. "~" .. S.b36(#chunks))
                for k, c in ipairs(chunks) do
                    shareFrom(ns, PEER, "S1~D~" .. a .. "~R" .. skill .. "~" .. tb .. "~" .. S.b36(k) .. "~" .. c)
                    parts = parts + 1
                end
            end
        end
    end
    local big = os.clock() - c0
    local received = #msgs + parts + 114 * 3
    -- A catalog for a newcomer.
    wow.advance(30); wow.state.sent = {}
    c0 = os.clock()
    shareFrom(ns, PEER, "S1~Q~qq~0~0")
    wow.advance(10)
    local catalogTime = os.clock() - c0
    local catalog = #shareSent("C")
    -- Data only (before any page builds frames; the mock's frames are heavy).
    wow.state.sent, wow.state.spellLookups = {}, {}
    collectgarbage("collect")
    local dataKB = collectgarbage("count") - memBefore
    -- Pages.
    c0 = os.clock()
    ns.Framework.open("roster")
    local rosterTime = os.clock() - c0
    c0 = os.clock()
    ns.Framework.open("recipes")
    local recipesTime = os.clock() - c0
    -- Save file.
    local sv = wow.serializeSV("GreenFangToolkitDB", GreenFangToolkitDB)
    local shareOnly = wow.serializeSV("share", GreenFangToolkitDB.share)
    collectgarbage("collect")
    local memKB = collectgarbage("count") - memBefore
    GF_PERF = {
        received = received, smallMs = small * 1000, bigMs = big * 1000,
        perMsgMs = (small + big) * 1000 / received, catalogMsgs = catalog, catalogMs = catalogTime * 1000,
        rosterMs = rosterTime * 1000, recipesMs = recipesTime * 1000,
        svKB = #sv / 1024, shareKB = #shareOnly / 1024, luaMemKB = memKB,
        records = select(1, S.totalDigest()), dataKB = dataKB,
    }
    io.write(string.format("     PERF: shared data in Lua memory +%.0f KB (before any page is opened)\n", dataKB))
    ok(dataKB < 8192, "shared data stays well under 8 MB of Lua memory")
    io.write(string.format("     PERF: %d messages in %.0f ms (%.3f ms each); catalog %d messages, %.0f ms; roster page %.0f ms; recipe page %.0f ms; SavedVariables %.0f KB (share %.0f KB); Lua memory +%.0f KB\n",
        received, (small + big) * 1000, GF_PERF.perMsgMs, catalog, GF_PERF.catalogMs, GF_PERF.rosterMs,
        GF_PERF.recipesMs, GF_PERF.svKB, GF_PERF.shareKB, memKB))
    eq(GF_PERF.records, 115, "every member known")
    ok(GF_PERF.perMsgMs < 2, "a message costs well under a frame (< 2 ms)")
    ok(catalog <= 20, "catalog fits in about 20 messages: " .. catalog)
    ok(GF_PERF.rosterMs < 200 and GF_PERF.recipesMs < 200, "pages draw quickly")
    ok(GF_PERF.svKB < 1024, "SavedVariables under 1 MB")
    for _, m in ipairs(shareSent()) do ok(#m <= 250, "fits") end
end)

---------------------------------------------------------------------------
-- GF-001-D12: replies by WHISPER to the requester only
---------------------------------------------------------------------------

local function sentOn(chatType, kind)
    local list = {}
    for i, s in ipairs(wow.state.sent) do
        if s.prefix == "GFTKS" and s.chatType == chatType
            and (not kind or s.msg:sub(1, #kind + 4) == "S1~" .. kind .. "~") then
            list[#list + 1] = { msg = s.msg, target = s.target, i = i }
        end
    end
    return list
end

local function withThird(ns, t)
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", t, { level = 40, classToken = "MAGE" })))
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "Z", t, { zone = "幽暗城" })))
    wow.advance(10)
    wow.state.sent = {}
end

test("D12 whisper target: a w2 request gets the data by WHISPER to Name-Realm, after a GUILD claim", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    withThird(ns, t)
    eq(shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".B." .. ns.Share.b36(t) .. "~w2"), "ok", "request")
    wow.advance(8)
    local k, v = sentOn("GUILD", "K"), sentOn("WHISPER", "V")
    eq(#k, 1, "one claim on GUILD")
    eq(k[1].msg, "S1~K~" .. A_PEER .. "~" .. A_THIRD .. ".B", "claim names the requester and the record")
    eq(#v, 1, "one whisper")
    eq(v[1].target, PEER, "to the requester, full Name-Realm from the roster")
    ok(k[1].i < v[1].i, "claim goes out before the whisper")
    eq(#sentOn("GUILD", "V"), 0, "no data on GUILD")
    ok(ns.Share.stats.whispered >= 1, "counted")
end)

test("D12 the author answers about themselves first, also by WHISPER", function()
    local ns = shareLogin()
    wow.state.sent = {}
    local own = ns.Share.get(A_SELF, "B")
    shareFrom(ns, PEER, "S1~G~" .. A_SELF .. ".B." .. ns.Share.b36(own.t) .. "~w2")
    wow.advance(1.2)
    eq(#sentOn("WHISPER", "V"), 1, "within a second")
end)

test("D12 single responder: a claim heard on GUILD cancels our reply; other targets unaffected", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    withThird(ns, t)
    shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".B." .. ns.Share.b36(t) .. "~" .. A_THIRD .. ".Z." .. ns.Share.b36(t) .. "~w2")
    eq(shareFrom(ns, THIRD, "S1~K~" .. A_PEER .. "~" .. A_THIRD .. ".B"), "claim", "someone else claims B")
    wow.advance(8)
    local v = sentOn("WHISPER", "V")
    eq(#v, 1, "only the unclaimed record")
    ok(has(v[1].msg, "~" .. A_THIRD .. "~Z~"), "Z still answered")
    local k = sentOn("GUILD", "K")
    eq(#k, 1, "our claim lists only what we send")
    ok(not has(k[1].msg, A_THIRD .. ".B"), "B not claimed again")
    -- A claim for a different requester does not cancel a reply to PEER.
    wow.state.sent = {}
    wow.advance(70)
    shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".B." .. ns.Share.b36(t) .. "~w2")
    shareFrom(ns, PEER, "S1~K~" .. A_THIRD .. "~" .. A_THIRD .. ".B")
    wow.advance(8)
    eq(#sentOn("WHISPER", "V"), 1, "claim for another member: we still answer PEER")
end)

test("D12 pushes of newer copies go by WHISPER to whoever showed the older one", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    withThird(ns, t)
    -- Their index (w2): B older than ours, Z missing.
    shareFrom(ns, PEER, "S1~I~" .. A_THIRD .. "~1~w2~B." .. ns.Share.b36(t - 50) .. ".abc")
    wow.advance(8)
    local v = sentOn("WHISPER", "V")
    eq(#v, 2, "B and Z whispered")
    for _, m in ipairs(v) do eq(m.target, PEER, "to PEER") end
    eq(#sentOn("GUILD", "K"), 1, "one claim for the batch")
    eq(#sentOn("GUILD", "V"), 0, "nothing on GUILD")
    -- An older V from a w2 member: answered by whisper too.
    wow.state.sent = {}
    wow.advance(70)
    eq(shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", t - 100, { level = 39 }))), "older", "older")
    wow.advance(8)
    eq(#sentOn("WHISPER", "V"), 1, "newer copy whispered back")
end)

test("D12 compatibility: 0.9.0/0.9.1 requests (no w2) get GUILD replies; data is taken from both channels", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    withThird(ns, t)
    shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".B." .. ns.Share.b36(t))
    wow.advance(8)
    eq(#sentOn("GUILD", "V"), 1, "old requester: GUILD reply as before")
    eq(#sentOn("WHISPER"), 0, "no whisper to an old client")
    eq(#sentOn("GUILD", "K"), 0, "no claim needed")
    -- Data by WHISPER is accepted; newest t still wins across channels.
    local m = vMsg(ns, A_THIRD, "B", t + 100, { level = 41 })
    eq(ns.Share.onMessage("GFTKS", m, "WHISPER", PEER), "new", "whispered data accepted")
    eq(ns.Share.onMessage("GFTKS", (vMsg(ns, A_THIRD, "B", t + 50, { level = 40 })), "GUILD", PEER), "older", "older on GUILD loses")
    eq(ns.Share.onMessage("GFTKS", (vMsg(ns, A_THIRD, "B", t + 200, { level = 42 })), "GUILD", PEER), "new", "newer on GUILD wins")
    -- Our own requests and indexes carry the mark; old parsers ignore it.
    wow.reset()
    ns = wow.login(ADDON_DIR)
    ns.Share.rand = function(a) return a end
    wow.advance(25)
    local q = shareSent("Q")[1]
    ok(q:sub(-3) == "~w2", "Q ends with w2: " .. q)
    ok(has(shareSent("I")[1], "~w2~"), "I carries w2")
end)

test("D12 offline target: the 'No player named' line is hidden for our whisper target only; its queue is dropped", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    withThird(ns, t)
    shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".B." .. ns.Share.b36(t) .. "~w2")
    wow.advance(8)
    eq(#sentOn("WHISPER"), 1, "whispered")
    -- More queued for PEER while we cannot send (combat).
    wow.enterCombat()
    shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".Z." .. ns.Share.b36(t) .. "~w2")
    wow.advance(8)
    ok(ns.Share.queuedFor(A_PEER) >= 1, "whispers held in combat")
    eq(wow.systemMessage("No player named '路人-別的伺服器' is currently playing."), false, "someone we did not whisper: shown")
    eq(wow.systemMessage("No player named '測試乙' is currently playing."), true, "our target (short name): hidden")
    eq(ns.Share.queuedFor(A_PEER), 0, "the rest for that member dropped (a GUILD claim may still go out)")
    wow.leaveCombat()
    wow.advance(5)
    eq(#sentOn("WHISPER"), 1, "nothing more whispered")
    eq(wow.systemMessage("No player named '測試乙' is currently playing."), false, "only once per whisper")
end)

test("D12 stale or capped targets: no whisper to someone not heard from lately; per-member cap", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    withThird(ns, t)
    wow.enterCombat()
    shareFrom(ns, PEER, "S1~G~" .. A_THIRD .. ".B." .. ns.Share.b36(t) .. "~w2")
    wow.advance(8)
    ok(ns.Share.queued() >= 1, "queued")
    wow.advance(130)
    wow.leaveCombat()
    wow.advance(5)
    eq(#sentOn("WHISPER"), 0, "not heard from for 2 minutes: dropped")
    ns.Share.MAX_PER_TARGET = 2
    wow.enterCombat()
    local items = {}
    for _, skill in ipairs({ 164, 165, 171, 197 }) do
        local ids = {}
        for k = 1, 300 do ids[k] = 2000 + k * 7 end
        local v = ns.Share.encodeValue("R" .. skill, ids)
        ns.Share.offer(A_THIRD, "R" .. skill, t, ns.Share.hash(v), v, false, A_PEER)
        items[#items + 1] = A_THIRD .. ".R" .. skill .. "." .. ns.Share.b36(t)
    end
    local before = ns.Share.stats.dropped
    shareFrom(ns, PEER, "S1~G~" .. table.concat(items, "~") .. "~w2")
    wow.advance(8)
    local queuedWhispers = 0
    ok(ns.Share.stats.dropped > before, "beyond the cap: dropped, not piled up")
    wow.leaveCombat()
    wow.advance(30)
    for _ in ipairs(sentOn("WHISPER")) do queuedWhispers = queuedWhispers + 1 end
    ok(queuedWhispers <= 2, "at most the cap went out: " .. queuedWhispers)
end)

-- Catch-up simulation: one member asks for every record; count what each
-- online member receives, with WHISPER replies (0.9.2) and as before (GUILD).
local function catchUp(n, whisper)
    local roster = wow.defaultRoster()
    for i = #roster + 1, n do
        roster[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 60,
            class = "戰士", classToken = "WARRIOR", zone = "奧格瑪", online = i % 3 == 0,
            guid = string.format("Player-0000-%08X", 0x100 + i) }
    end
    local ns = shareLogin({ roster = roster })
    local S = ns.Share
    S.MAX_RECORDS, S.MAX_QUEUE, S.MAX_PER_TARGET = 100000, 1e9, 1e9
    S.ALLOWANCE, S.REFILL = 1e9, 1e9
    local t = wow.state.now - 3600
    local items = {}
    local function put(a, g, v)
        S.offer(a, g, t, S.hash(v), v, false, A_PEER)
        items[#items + 1] = a .. "." .. g .. "." .. S.b36(t)
    end
    for i, m in ipairs(ns.Roster.current().members) do
        local a = S.authorOf(m.guid)
        if a ~= A_SELF and a ~= A_PEER then
            put(a, "B", S.encodeValue("B", { level = 60, classToken = "WARRIOR" }))
            put(a, "P", S.encodeValue("P", { { skillLineID = 164, rank = 300, max = 300 },
                { skillLineID = 186, rank = 300, max = 300 }, { skillLineID = 185, rank = 300, max = 300 } }))
            put(a, "Z", S.encodeValue("Z", { zone = "奧格瑪", subZone = "力量谷" }))
            for _, skill in ipairs({ 164, 186, 185 }) do
                local ids = {}
                for k = 1, 350 do if (k + i + skill) % 7 ~= 0 then ids[#ids + 1] = 2000 + k * 13 end end
                put(a, "R" .. skill, S.encodeValue("R" .. skill, ids))
            end
        end
    end
    wow.advance(70); wow.state.sent = {}
    local asks = 0
    for i = 1, #items, 8 do
        local chunk = {}
        for j = i, math.min(#items, i + 7) do chunk[#chunk + 1] = items[j] end
        if whisper then chunk[#chunk + 1] = "w2" end
        shareFrom(ns, PEER, "S1~G~" .. table.concat(chunk, "~"))
        asks = asks + 1
        if asks % 50 == 0 then wow.advance(1) end
    end
    wow.advance(20)
    local guild, whisp, guildBytes, whispBytes = 0, 0, 0, 0
    for _, s in ipairs(wow.state.sent) do
        if s.chatType == "WHISPER" then whisp = whisp + 1; whispBytes = whispBytes + #s.msg
        else guild = guild + 1; guildBytes = guildBytes + #s.msg end
    end
    return { records = #items, asks = asks, guild = guild, whisper = whisp,
        others = asks + guild, requester = asks + guild + whisp, guildKB = (guildBytes + asks * 200) / 1024 }
end

test("D12 catch-up simulation: messages each member receives (115 and 1000 members)", function()
    local out = {}
    for _, n in ipairs({ 115, 1000 }) do
        local new, old = catchUp(n, true), catchUp(n, false)
        out[n] = { new = new, old = old }
        io.write(string.format("     CATCHUP %d members: %d records, %d requests. Before (GUILD): every online member receives %d. Now: requester %d (%d by WHISPER), every other member %d (requests %d + claims %d)\n",
            n, new.records, new.asks, old.others, new.requester, new.whisper, new.others, new.asks, new.guild))
        ok(new.whisper > 0 and new.guild < old.guild / 4, n .. ": data moved off GUILD")
        eq(new.requester - new.others, new.whisper, n .. ": only the requester gets the data")
    end
    GF_CATCHUP = out
end)

---------------------------------------------------------------------------
-- GF-001-D14 part A: phase 4 uploads (member.share, recipe.names,
-- capturedAtServer, character.self.recipes); member.report no longer written
---------------------------------------------------------------------------

local SHARE_KEYS = { subject = true, level = true, classToken = true, professions = true,
    location = true, recipes = true, withdrawn = true }

local function sharesByName()
    local out = {}
    for _, e in ipairs(entriesOf("member.share")) do out[e.payload.subject.name] = e end
    return out
end

test("D14 member.share: per-field times and via, recipes with ids, withdrawn; no empty keys", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", t, { level = 61, classToken = "WARRIOR" })))
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", t - 100, { level = 40, classToken = "MAGE" })))
    shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 164, t - 50, { 2660, 2661 })))
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 197, t, { 3115 })))
    shareFrom(ns, PEER, "S1~X~" .. A_PEER .. "~R197~" .. ns.Share.b36(t + 10))
    eq(ns.Sync.recordShares(), 2, "two subjects")
    local by = sharesByName()
    local peer, third = by[PEER].payload, by[THIRD].payload
    eq(peer.level.value, 61, "level"); eq(peer.level.recordedAt, t, "author's time")
    eq(peer.level.via, "author", "heard from the author")
    eq(peer.classToken.value, "WARRIOR", "class")
    eq(peer.recipes, nil, "given up: no recipes")
    eq(peer.withdrawn.recipes["197"], t + 10, "tombstone with a string key")
    eq(peer.professions, nil, "unknown: key left out, never an empty table")
    eq(third.level.via, "relay", "relayed")
    local r = third.recipes["164"]
    eq(table.concat(r.ids, ","), "2660,2661", "ids sorted")
    eq(r.via, "relay", "recipes via"); eq(r.recordedAt, t - 50, "recipes time"); ok(r.hash, "hash")
    eq(third.withdrawn, nil, "no tombstone: no key")
    eq(third.subject.guid, "Player-0000-0000000C", "subject guid")
    for _, e in ipairs(entriesOf("member.share")) do
        for k in pairs(e.payload) do ok(SHARE_KEYS[k], "contract key only: " .. k) end
        eq(type(e.capturedAtServer), "number", "capturedAtServer")
        ok(has(e.id, ":member.share:" .. e.payload.subject.guid), "id per subject: " .. e.id)
        eq(e.uploader.guid, "Player-0000-0000000A", "uploader")
    end
    eq(#entriesOf("member.report"), 0, "no member.report")
end)

test("D14 member.share rewrites: only what changed, new id, ids only for a new list, 6-hour rule", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, t, { 2660, 2661 })))
    shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", t, { level = 61 })))
    eq(ns.Sync.recordShares(), 1, "first write")
    local first = entriesOf("member.share")[1]
    ok(first.payload.recipes["164"].ids, "first time with ids")
    wow.advance(60)
    eq(ns.Sync.recordShares(), 0, "nothing new: not rewritten")
    eq(entriesOf("member.share")[1].id, first.id, "same entry kept")
    -- Only a confirmation one hour later: waits for the 6-hour pass.
    shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", t + 3600 - 3000, { level = 61 })))
    eq(ns.Sync.recordShares(), 0, "times moved a little: not yet")
    -- A value changed: rewritten, recipes without ids (same list).
    shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", t + 700, { level = 62 })))
    eq(ns.Sync.recordShares(), 1, "changed")
    local list = entriesOf("member.share")
    eq(#list, 1, "still one per subject")
    local second = list[1]
    ok(second.id ~= first.id, "new id")
    eq(second.payload.level.value, 62, "new value")
    eq(second.payload.recipes["164"].ids, nil, "same list: no ids")
    eq(second.payload.recipes["164"].hash, first.payload.recipes["164"].hash, "hash still there")
    -- A recipe learned: ids again.
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, t + 720, { 2660, 2661, 2662 })))
    eq(ns.Sync.recordShares(), 1, "list changed")
    eq(#entriesOf("member.share")[1].payload.recipes["164"].ids, 3, "new list with ids")
    -- 6-hour pass: a subject whose times only moved forward is written again.
    wow.advance(7 * 3600)
    shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", wow.state.now - 60, { level = 62 })))
    eq(ns.Sync.recordShares(), 1, "time moved more than 6 h")
    eq(entriesOf("member.share")[1].payload.recipes["164"].ids, nil, "still no ids")
    -- A month later the ids go out once more, in case an upload was missed.
    wow.advance(31 * 86400)
    shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", wow.state.now - 60, { level = 62 })))
    ns.Sync.recordShares()
    eq(#entriesOf("member.share")[1].payload.recipes["164"].ids, 3, "monthly ids refresh")
end)

test("D14 member.share size: ids within a per-logout budget, newest first; dropped after a logout", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, t, { 2660, 2661 })))
    shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 164, t + 100, { 2660, 3115 })))
    local D = "0000-0000000D"
    shareFrom(ns, PEER, (rMsg(ns, D, 164, t + 50, { 2662, 3115 })))
    ns.Sync.IDS_PER_LOGOUT = 3
    eq(ns.Sync.recordShares(), 3, "three subjects")
    local by = sharesByName()
    ok(by[THIRD].payload.recipes["164"].ids, "newest list gets its ids")
    eq(by[PEER].payload.recipes["164"].ids, nil, "over the budget: hash only")
    eq(by["測試丁-測試伺服器"].payload.recipes["164"].ids, nil, "over the budget: hash only")
    -- Next logout: the lists left out are written again, newest first.
    eq(ns.Sync.recordShares(), 2, "only the subjects still waiting")
    by = sharesByName()
    ok(by["測試丁-測試伺服器"].payload.recipes["164"].ids, "next newest")
    eq(by[PEER].payload.recipes["164"].ids, nil, "still waiting")
    eq(ns.Sync.recordShares(), 1, "the last one")
    ok(sharesByName()[PEER].payload.recipes["164"].ids, "all sent in the end")
    eq(ns.Sync.recordShares(), 0, "then nothing")
    ns.Sync.IDS_PER_LOGOUT = 50000
    -- A later session: entries whose ids survived a logout are rewritten without them.
    local before = sharesByName()[THIRD].id
    ns.Sync.loadedAt = wow.state.now + 10
    wow.advance(15)
    eq(ns.Sync.recordShares(), 3, "rewritten once without ids")
    for _, e in ipairs(entriesOf("member.share")) do
        for _, item in pairs(e.payload.recipes) do eq(item.ids, nil, "no ids kept in the outbox") end
    end
    ok(sharesByName()[THIRD].id ~= before, "new id")
    eq(ns.Sync.recordShares(), 0, "and not again")
end)

test("D14 recipe.names: new IDs only, client names, one entry, new id when merged, 500 at most", function()
    local ns = shareLogin()
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, t, { 2660, 2661, 99999 })))
    ok(ns.Sync.recordRecipeNames(), "written")
    local e = entriesOf("recipe.names")
    eq(#e, 1, "one entry")
    eq(e[1].payload.names["2660"], "粗製磨刀石", "client name, string key")
    eq(e[1].payload.names["99999"], nil, "a name the client does not know waits")
    eq(e[1].payload.locale, "zhTW", "locale")
    eq(type(e[1].capturedAtServer), "number", "common fields")
    ok(e[1].game and e[1].uploader and e[1].capturedAt, "common fields")
    local id1 = e[1].id
    eq(select(2, ns.Sync.recordRecipeNames()), "none", "nothing new")
    shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 164, t, { 2662, 3115 })))
    wow.advance(2)
    ns.Sync.recordRecipeNames()
    e = entriesOf("recipe.names")
    eq(#e, 1, "still one entry")
    ok(e[1].id ~= id1, "new id when names were merged")
    ok(e[1].payload.names["2660"] and e[1].payload.names["3115"], "old and new names")
    wow.state.anySpellName = true
    local ids = {}
    for k = 1, 700 do ids[k] = 50000 + k end
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 197, t, ids)))
    wow.advance(2)
    ns.Sync.recordRecipeNames()
    local n = 0
    for _ in pairs(entriesOf("recipe.names")[1].payload.names) do n = n + 1 end
    eq(n, 500, "at most 500 in an entry")
    wow.advance(2)
    ns.Sync.recordRecipeNames()
    local seen = 0
    for k = 1, 700 do if GreenFangToolkitDB.share.seenIDs[50000 + k] then seen = seen + 1 end end
    eq(seen, 700, "the rest at the next logout")
end)

test("D14 capturedAtServer on every entry; character.self carries own recipes", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    wow.state.serverSkew = 7
    wow.fire("TRADE_SKILL_SHOW")
    wow.logout()
    for _, e in ipairs(outbox()) do eq(type(e.capturedAtServer), "number", e.kind .. " capturedAtServer") end
    local cs = entriesOf("character.self")[1]
    eq(cs.capturedAtServer - cs.capturedAt, 7, "server time, not the computer's")
    local r = cs.payload.recipes["165"]
    eq(table.concat(r.ids, ","), "2149,2152", "own recipes")
    ok(r.hash and r.recordedAt, "hash and time")
    eq(r.via, nil, "own record: no via")
end)

test("D14 outbox size follows the roster; nothing written in combat or from another guild", function()
    local ns = shareLogin({ roster = bigRoster(1000) })
    eq(ns.Sync.shareCap(), 1000, "member.share: one per member")
    eq(ns.Sync.outboxCap(), 1050, "plus 50 for the other kinds")
    shareFrom(ns, PEER, (vMsg(ns, A_PEER, "B", wow.state.now - 60, { level = 61 })))
    wow.enterCombat()
    eq(select(2, ns.Sync.recordShares()), "combat", "not in combat")
    wow.leaveCombat()
    local player = wow.defaultPlayer()
    player.guild = "測試用其他公會"
    ns = shareLogin({ player = player })
    eq(select(2, ns.Sync.recordShares()), "other-guild", "other guild")
    eq(select(2, ns.Sync.recordRecipeNames()), "other-guild", "other guild")
end)

---------------------------------------------------------------------------
-- GF-001-D14 part B: EVAL-1000 (record cap, catch-up order and pace)
---------------------------------------------------------------------------

test("D14 record cap: max(2000, roster x 10); when full, off-roster authors heard least recently go first", function()
    local ns = shareLogin()
    local S = ns.Share
    eq(S.maxRecords(), 2000, "small guild: 2000")
    local t = wow.state.now - 600
    local function put(a, g, value)
        local v = S.encodeValue(g, value)
        return S.offer(a, g, t, S.hash(v), v, false, A_PEER)
    end
    -- Two authors who left the guild, heard at different times.
    eq(put("0000-0000AAA1", "B", { level = 10 }), "new", "old member 1")
    wow.advance(100)
    eq(put("0000-0000AAA2", "B", { level = 11 }), "new", "old member 2")
    put("0000-0000AAA2", "P", { { skillLineID = 164, rank = 1, max = 75 } })
    local count = 0
    for _, groups in pairs(S.store().rec) do for _ in pairs(groups) do count = count + 1 end end
    local realMax = S.maxRecords
    S.maxRecords = function() return count end
    eq(put(A_THIRD, "B", { level = 40 }), "new", "full: a roster member's record still gets in")
    eq(S.store().rec["0000-0000AAA1"], nil, "the one heard least recently was forgotten")
    ok(S.store().rec["0000-0000AAA2"], "the other is kept")
    eq(S.stats.evicted, 1, "counted")
    S.maxRecords = function() return 0 end
    S.store().rec["0000-0000AAA2"] = nil
    eq(put(A_THIRD, "P", { { skillLineID = 197, rank = 1, max = 75 } }), "full",
        "everyone stored is on the roster: the new record waits")
    S.maxRecords = realMax
    ns = shareLogin({ roster = bigRoster(1000) })
    eq(ns.Share.maxRecords(), 10000, "1,000 members: 10,000 records")
    eq(ns.Share.maxRecordAsks(), 2000, "and 2,000 record requests per login")
    eq(ns.Share.maxIndexAsks(), 600, "and 600 index requests")
end)

test("D14 catch-up order: online members first, then the newest; requests spread over rounds", function()
    local ns = shareLogin({ roster = bigRoster(200) })
    local S = ns.Share
    local members = ns.Roster.current().members
    local base = wow.state.now - 5000
    local online, tOf = {}, {}
    wow.state.sent = {}
    for i = 5, 104 do
        local m = members[i]
        local a = S.authorOf(m.guid)
        online[a], tOf[a] = m.online == true, base + i
        shareFrom(ns, PEER, "S1~I~" .. a .. "~1~w2~B." .. S.b36(base + i) .. ".abc")
    end
    wow.advance(1.5)
    local function asked()
        local list = {}
        for _, m in ipairs(shareSent("G")) do
            for a in m:gmatch("~([^~%.]+)%.B%.") do list[#list + 1] = a end
        end
        return list
    end
    local first = asked()
    eq(#first, 48, "first round: 6 requests of 8")
    local seenOffline = false
    for i, a in ipairs(first) do
        if online[a] then ok(not seenOffline, "online before offline (" .. i .. ")")
        else seenOffline = true end
        if i > 1 and online[a] == online[first[i - 1]] then
            ok(tOf[a] < tOf[first[i - 1]], "newest first within a group")
        end
    end
    ok(S.waiting() > 0, "the rest waits")
    wow.advance(5)
    eq(#asked(), 48, "nothing more within the round's pause")
    wow.advance(30)
    eq(#asked(), 100, "everything asked over a few rounds")
    eq(S.waiting(), 0, "nothing left")
    for _, m in ipairs(shareSent()) do ok(#m <= 250, "fits") end
end)

-- Fill the store with B records for members first..last of the roster.
local function fillAuthors(ns, first, last, t)
    local S = ns.Share
    for i = first, last do
        local a = S.authorOf(ns.Roster.current().members[i].guid)
        local v = S.encodeValue("B", { level = 60, classToken = "WARRIOR" })
        S.offer(a, "B", t, S.hash(v), v, false, A_PEER)
    end
end

test("D14 bucketed catalog: a 0.10 Q carries bucket digests and fits; only differing buckets are answered", function()
    local ns = shareLogin({ roster = bigRoster(300) })
    local S = ns.Share
    local t = wow.state.now - 3600
    fillAuthors(ns, 5, 300, t)
    local count, digest = S.totalDigest()
    local theirs = S.bucketDigests()
    eq(#theirs, 192, "64 buckets x 3 characters")
    -- One author changed on our side since the requester's copy.
    local a = S.authorOf(ns.Roster.current().members[77].guid)
    local v = S.encodeValue("B", { level = 61, classToken = "WARRIOR" })
    S.offer(a, "B", t + 60, S.hash(v), v, false, A_PEER)
    local q = "S1~Q~qq~" .. S.b36(count) .. "~" .. digest .. "~b" .. theirs .. "~w2"
    ok(#q <= 250, "Q fits in one message: " .. #q)
    wow.advance(30); wow.state.sent = {}
    eq(shareFrom(ns, PEER, q), "ok", "different total: answered")
    wow.advance(10)
    local c = shareSent("C")
    eq(#c, 1, "only one bucket differs: one message")
    local mask = c[1]:match("^S1~C~qq~1~1~k([0-9a-z]+)~")
    ok(mask, "bucketed reply carries its mask: " .. c[1])
    local b = S.bucketOf(a)
    ok(S.inMask(mask, b), "the changed author's bucket")
    for other = 0, S.BUCKETS - 1 do
        if other ~= b then ok(not S.inMask(mask, other), "no other bucket") end
    end
    ok(has(c[1], "~" .. a .. "."), "the changed author is listed")
    for item in c[1]:gmatch("~([^~%.]+)%.[0-9a-z]+%.[0-9a-z]+") do
        eq(S.bucketOf(item), b, "only authors of that bucket")
    end
    -- An older client's Q (no bucket digests) gets the whole catalog, as before.
    wow.advance(70); wow.state.sent = {}
    shareFrom(ns, PEER, "S1~Q~qr~" .. S.b36(count) .. "~" .. digest .. "~w2")
    wow.advance(60)
    local full = shareSent("C")
    ok(#full >= 25, "whole catalog for 296 authors: " .. #full)
    ok(not full[1]:find("~k[0-9a-z]+~"), "no mask in a full catalog")
    for _, m in ipairs(full) do ok(#m <= 250, "fits") end
end)

test("D14 bucketed catalog: our Q has digests; a bucketed reply only prompts indexes in its buckets", function()
    local ns = shareLogin({ roster = bigRoster(120) })
    local S = ns.Share
    local q = shareSent("Q")[1]
    local qid = q:match("^S1~Q~([0-9a-z]+)~")
    ok(q:find("~b" .. string.rep("[0-9a-z]", 192) .. "~w2$"), "Q carries 192 characters of bucket digests: " .. q)
    ok(#q <= 250, "and fits")
    -- Old parsers still read fields 1-3 the same way.
    local f = {}
    for x in (q .. "~"):gmatch("([^~]*)~") do f[#f + 1] = x end
    eq(f[3], qid, "qid"); ok(S.unb36(f[4]), "count"); ok(f[5]:match("^[0-9a-z]+$"), "digest")
    local t = wow.state.now - 3600
    fillAuthors(ns, 5, 120, t)
    wow.state.sent = {}
    -- A reply covering one bucket and listing nobody: the authors we know in
    -- that bucket are missing on their side; others are not our business.
    local target = S.bucketOf(S.authorOf(ns.Roster.current().members[10].guid))
    shareFrom(ns, PEER, "S1~C~" .. qid .. "~1~1~k" .. S.maskOf({ [target] = true }))
    wow.advance(10)
    local sentFor = {}
    for _, m in ipairs(shareSent("I")) do sentFor[m:match("^S1~I~([^~]+)~")] = true end
    local inBucket = 0
    for i = 5, 120 do
        local a = S.authorOf(ns.Roster.current().members[i].guid)
        if S.bucketOf(a) == target then
            inBucket = inBucket + 1
            ok(sentFor[a], "index for an author in the covered bucket")
        else
            ok(not sentFor[a], "no index outside the covered bucket")
        end
    end
    ok(inBucket > 0, "some authors in that bucket")
end)

test("D14 catalog at 1,000 members: after a login with few changes, 1-2 buckets instead of the whole list", function()
    local ns = shareLogin({ roster = bigRoster(1000) })
    local S = ns.Share
    S.MAX_RECORDS = 100000
    local t = wow.state.now - 3600
    fillAuthors(ns, 5, 1000, t)
    local count, digest = S.totalDigest()
    local theirs = S.bucketDigests()
    local a = S.authorOf(ns.Roster.current().members[500].guid)
    local v = S.encodeValue("B", { level = 61, classToken = "WARRIOR" })
    S.offer(a, "B", t + 60, S.hash(v), v, false, A_PEER)
    wow.advance(30); wow.state.sent = {}
    shareFrom(ns, PEER, "S1~Q~qq~" .. S.b36(count) .. "~" .. digest .. "~b" .. theirs .. "~w2")
    wow.advance(10)
    local bucketed = #shareSent("C")
    wow.advance(70); wow.state.sent = {}
    shareFrom(ns, PEER, "S1~Q~qr~" .. S.b36(count) .. "~" .. digest .. "~w2")
    wow.advance(200)
    local fullCount = #shareSent("C")
    io.write(string.format("     CATALOG 1000 members, one change: bucketed %d messages, full %d messages\n", bucketed, fullCount))
    GF_CATALOG = { bucketed = bucketed, full = fullCount }
    ok(bucketed <= 4, "a few messages: " .. bucketed)
    ok(fullCount >= 100, "the whole list is long: " .. fullCount)
    S.MAX_RECORDS = 2000
end)

-- Every member but us shares three recipe lists of about 300.
local function shareRecipes(ns, t)
    local S = ns.Share
    for i, m in ipairs(ns.Roster.current().members) do
        local a = S.authorOf(m.guid)
        if a ~= A_SELF then
            for _, skill in ipairs({ 164, 186, 185 }) do
                local ids = {}
                for k = 1, 350 do if (k + i + skill) % 7 ~= 0 then ids[#ids + 1] = 2000 + k * 13 end end
                local v = S.encodeValue("R" .. skill, ids)
                S.offer(a, "R" .. skill, t, S.hash(v), v, false, A_PEER)
            end
        end
    end
end

test("D14 roster list: only rows in view have frames; scrolling refills them", function()
    local ns = shareLogin({ roster = bigRoster(300) })
    ns.Framework.open("roster")
    local rows = ns.UI.rows()
    local count = ns.UI.visibleRowCount()
    ok(#rows <= count, "frames only for the rows in view: " .. #rows .. " <= " .. count)
    local shown = 0
    for _, r in ipairs(rows) do if r:IsShown() then shown = shown + 1 end end
    eq(shown, count, "the view is full")
    local scroll = ns.UI.scrollFrame()
    local H = ns.PAGE_ROW -- GF-UI-B: 36 (was 23)
    scroll:SetVerticalScroll(149 * H)
    local top
    for _, r in ipairs(rows) do if r:IsShown() and (not top or r.index < top.index) then top = r end end
    eq(top.index, 150, "first row in view is member 150 of the list")
    eq(top._points[1][5], -149 * H, "placed where that member is")
    ok(top.memberName and top.cells[1]:GetText() == top.memberName, "filled with that member")
    eq(#ns.UI.rows(), #rows, "no new frames while scrolling")
    scroll:SetVerticalScroll(0)
    for _, r in ipairs(rows) do if r:IsShown() then ok(r.index <= count, "back at the top") end end
end)

test("D14 recipe page: index built over several frames with 整理中, then only rows in view", function()
    local ns = shareLogin({ roster = bigRoster(115) })
    shareRecipes(ns, wow.state.now - 3600)
    ns.Recipes.steps = 0
    ns.Framework.open("recipes")
    local function texts() return table.concat(wow.allTexts(), "\n") end
    ok(has(texts(), ns.Recipes.BUILDING_TEXT), "整理中 while the first index is built")
    ok(ns.Recipes.isBuilding(), "building")
    wow.advance(1)
    ok(not ns.Recipes.isBuilding(), "done")
    ok(ns.Recipes.steps > 5, "spread over frames: " .. ns.Recipes.steps)
    ok(not has(texts(), ns.Recipes.BUILDING_TEXT), "list shown")
    local frames = ns.Recipes.rowFrames()
    ok(#frames > 0 and #frames <= 10, "frames only for the rows in view: " .. #frames)
    local rows = ns.Recipes.shownRows() -- D22: every ticked profession in one list
    ok(#rows > 100, "many recipes: " .. #rows)
    eq(frames[1].data.id, rows[1].id, "first row")
    -- New data later: the finished list stays on screen while a new one is built.
    local v = ns.Share.encodeValue("R164", { 2660 })
    ns.Share.offer(A_PEER, "R164", wow.state.now - 10, ns.Share.hash(v), v, true, A_PEER)
    ns.Recipes.refresh()
    ok(not has(texts(), ns.Recipes.BUILDING_TEXT), "no 整理中 once a list exists")
end)

test("D14 performance: 1,000 members, every record as messages, pages, index, logout, save size", function()
    local N = 1000
    local ns = shareLogin({ roster = bigRoster(N) })
    local S = ns.Share
    local members = ns.Roster.current().members
    local t = wow.state.now - 3600
    collectgarbage("collect")
    local memBefore = collectgarbage("count")
    -- Every member but us: B, P, Z and three recipe lists of about 300, over the wire.
    local small, parts = 0, 0
    local c0 = os.clock()
    for i, m in ipairs(members) do
        local a = S.authorOf(m.guid)
        if a ~= A_SELF then
            shareFrom(ns, PEER, (vMsg(ns, a, "B", t, { level = 60, classToken = "WARRIOR" })))
            shareFrom(ns, PEER, (vMsg(ns, a, "P", t, { { skillLineID = 164, rank = 300, max = 300 },
                { skillLineID = 186, rank = 300, max = 300 }, { skillLineID = 185, rank = 300, max = 300 } })))
            shareFrom(ns, PEER, (vMsg(ns, a, "Z", t, { zone = "奧格瑪", subZone = "力量谷" })))
            small = small + 3
            for _, skill in ipairs({ 164, 186, 185 }) do
                local ids = {}
                for k = 1, 350 do if (k + i + skill) % 7 ~= 0 then ids[#ids + 1] = 2000 + k * 13 end end
                local v = S.encodeValue("R" .. skill, ids)
                local tb = S.b36(t)
                local head = #("S1~D~" .. a .. "~R" .. skill .. "~" .. tb .. "~zz~")
                local chunks = {}
                for k = 1, #v, 250 - head do chunks[#chunks + 1] = v:sub(k, k + 250 - head - 1) end
                shareFrom(ns, PEER, "S1~B~" .. a .. "~R" .. skill .. "~" .. tb .. "~" .. S.hash(v) .. "~" .. S.b36(#chunks))
                for k, c in ipairs(chunks) do
                    shareFrom(ns, PEER, "S1~D~" .. a .. "~R" .. skill .. "~" .. tb .. "~" .. S.b36(k) .. "~" .. c)
                    parts = parts + 1
                end
                parts = parts + 1
            end
        end
    end
    local recvMs = (os.clock() - c0) * 1000
    local received = small + parts
    local records = 0
    for _, groups in pairs(S.store().rec) do for _ in pairs(groups) do records = records + 1 end end
    ok(records >= (N - 1) * 6, "every record kept: " .. records .. " (cap " .. S.maxRecords() .. ")")
    wow.advance(30); wow.state.sent = {}
    collectgarbage("collect")
    local dataKB = collectgarbage("count") - memBefore
    -- Pages.
    c0 = os.clock()
    ns.Framework.open("roster")
    local rosterMs = (os.clock() - c0) * 1000
    c0 = os.clock()
    ns.UI.scrollFrame():SetVerticalScroll(500 * 23)
    local scrollMs = (os.clock() - c0) * 1000
    ns.Recipes.steps = 0
    c0 = os.clock()
    ns.Framework.open("recipes")
    local recipeOpenMs = (os.clock() - c0) * 1000
    c0 = os.clock()
    wow.advance(1)
    local indexMs = (os.clock() - c0) * 1000
    local steps = ns.Recipes.steps
    ok(not ns.Recipes.isBuilding(), "index finished")
    local entries = 0
    for _, p in pairs(ns.Recipes.index()) do for _, who in pairs(p.recipes) do entries = entries + #who end end
    -- Logout: member.share for everyone, recipe names, character.self.
    c0 = os.clock()
    wow.logout()
    local logoutMs = (os.clock() - c0) * 1000
    local shares = #entriesOf("member.share")
    local sv = wow.serializeSV("GreenFangToolkitDB", GreenFangToolkitDB)
    local shareOnly = wow.serializeSV("share", GreenFangToolkitDB.share)
    local outboxOnly = wow.serializeSV("outbox", GreenFangToolkitDB.sync.outbox)
    -- Later logouts (each a new session) send the lists left out of the
    -- per-logout budget. The whole file is measured after every logout; the
    -- peak is what GF Sync's parser must handle (32 MB, 2,000,000 values).
    local peak = { values = luaValues(GreenFangToolkitDB), kb = #sv / 1024, at = 1 }
    local function session()
        ns.Sync.loadedAt = wow.state.now + 1
        wow.advance(3600)
    end
    session()
    c0 = os.clock()
    local second = ns.Sync.recordShares()
    local secondMs = (os.clock() - c0) * 1000
    ok(second > 0, "lists over the budget follow at the next logout")
    local logouts = 2
    local function measure()
        local values = luaValues(GreenFangToolkitDB)
        if values > peak.values then
            peak = { values = values, kb = #wow.serializeSV("GreenFangToolkitDB", GreenFangToolkitDB) / 1024, at = logouts }
        end
    end
    measure()
    while true do
        session()
        if ns.Sync.recordShares() == 0 then break end
        logouts = logouts + 1
        measure()
        ok(logouts < 40, "ends")
    end
    session()
    c0 = os.clock()
    eq(ns.Sync.recordShares(), 0, "then nothing new: no rewrite")
    local quietMs = (os.clock() - c0) * 1000
    local steady = { values = luaValues(GreenFangToolkitDB),
        kb = #wow.serializeSV("GreenFangToolkitDB", GreenFangToolkitDB) / 1024 }
    local cacheValues = luaValues(GreenFangToolkitDB.share)
    GF_PERF1000 = {
        received = received, perMsgMs = recvMs / received, records = records, dataKB = dataKB,
        rosterMs = rosterMs, scrollMs = scrollMs, recipeOpenMs = recipeOpenMs, indexMs = indexMs,
        steps = steps, stepMs = indexMs / math.max(1, steps), entries = entries,
        logoutMs = logoutMs, secondMs = secondMs, shares = shares, logouts = logouts, quietMs = quietMs,
        svKB = #sv / 1024, shareKB = #shareOnly / 1024, outboxKB = #outboxOnly / 1024,
        peakValues = peak.values, peakKB = peak.kb, peakAt = peak.at, steadyValues = steady.values,
        steadyKB = steady.kb, cacheValues = cacheValues,
    }
    local P = GF_PERF1000
    io.write(string.format("     PERF1000: %d messages, %.3f ms each; %d records (cap %d); shared data +%.0f KB Lua memory\n",
        P.received, P.perMsgMs, P.records, S.maxRecords(), P.dataKB))
    io.write(string.format("     PERF1000: roster page %.0f ms, scroll %.1f ms; recipe page opens in %.0f ms, index %d entries in %d frames, %.0f ms in all (%.1f ms per frame)\n",
        P.rosterMs, P.scrollMs, P.recipeOpenMs, P.entries, P.steps, P.indexMs, P.stepMs))
    io.write(string.format("     PERF1000: first logout %.0f ms (%d member.share), next %.0f ms; every recipe list sent after %d logouts; quiet logout %.0f ms; SavedVariables %.0f KB (share %.0f KB, outbox %.0f KB)\n",
        P.logoutMs, P.shares, P.secondMs, P.logouts, P.quietMs, P.svKB, P.shareKB, P.outboxKB))
    io.write(string.format("     PERF1000: whole SavedVariables at peak (logout %d) %.0f KB, %d Lua values; after every list was sent %.0f KB, %d values (share cache %d)\n",
        P.peakAt, P.peakKB, P.peakValues, P.steadyKB, P.steadyValues, P.cacheValues))
    ok(P.peakValues <= 1200000, "clear margin under GF Sync's 2,000,000 values: " .. P.peakValues)
    ok(P.peakKB < 32 * 1024 / 2, "well under GF Sync's 32 MB: " .. P.peakKB)
    ok(#entriesOf("member.share") <= 1200, "within GF Sync's 1,200 member.share")
    ok(P.perMsgMs < 2, "a message stays well under a frame")
    ok(P.rosterMs < 100 and P.recipeOpenMs < 100, "pages open without a hitch")
    ok(P.stepMs < 16, "each index frame stays under a frame (16 ms)")
    eq(P.shares, N - 1, "a member.share for every member")
    ok(P.svKB < 8192, "SavedVariables stay reasonable: " .. P.svKB)
end)

---------------------------------------------------------------------------
-- 16001 fallbacks (docs/research/forever-api-16001.md)
---------------------------------------------------------------------------

test("16001: works without IsInGuild (guild detected from GetGuildInfo)", function()
    wow.reset({ noIsInGuild = true })
    local ns = wow.login(ADDON_DIR)
    eq(IsInGuild, nil, "IsInGuild really missing")
    eq(#entriesOf("roster.snapshot"), 1, "roster scanned")
    eq(entriesOf("character.self")[1].uploader.guild, "綠皮與獠牙冒險事務所", "guild known")
    ok(ns.Roster.current(), "window has a snapshot")
end)

test("16001: no IsInGuild and no guild -> treated as not in guild", function()
    wow.reset({ noIsInGuild = true, inGuild = false })
    wow.login(ADDON_DIR)
    wow.advance(30)
    eq(#entriesOf("roster.snapshot"), 0, "no roster")
    eq(#entriesOf("character.self"), 0, "not synced")
end)

test("16001: without C_Timer every delayed step runs via OnUpdate", function()
    wow.reset({ noCTimer = true })
    wow.login(ADDON_DIR)
    eq(C_Timer, nil, "C_Timer really missing")
    ok(printedContains("會分享你的等級"), "notice printed")
    eq(#entriesOf("character.self"), 1, "character.self")
    eq(#entriesOf("roster.snapshot"), 1, "roster.snapshot")
end)

test("16001: C_SkillInfo table skill list when GetProfessions is missing", function()
    wow.reset({ noProfessionsAPI = true, cSkillInfo = {
        { name = "專業", header = true },
        { name = "製皮", rank = 151, max = 225, skillID = 165 },
        { name = "Unknown Thing", rank = 1, max = 1, skillID = 99999 },
        { name = "剝皮", rank = 160, max = 225 },
        { name = "雙手斧", rank = 100, max = 160, skillID = 172 },
    } })
    wow.login(ADDON_DIR)
    local p = entriesOf("character.self")[1].payload.professions
    eq(#p, 2, "only professions")
    eq(p[1].skillLineID, 165, "skillID from table"); eq(p[1].rank, 151); eq(p[1].max, 225)
    eq(p[2].skillLineID, 393, "skillLineID from name when skillID missing")
end)

test("16001: GetProfessions with 7 returns and holes", function()
    wow.reset()
    local pl = wow.state.player
    pl.professions[7] = { "急救", 135966, 40, 75, 0, 0, 129 }
    pl.professionIndexes = { 1, nil, nil, 4, nil, nil, 7 }
    GetProfessions = function()
        local i = pl.professionIndexes
        return i[1], i[2], i[3], i[4], i[5], i[6], i[7]
    end
    local ns = wow.loadAddon(ADDON_DIR)
    GetProfessions = function()
        local i = pl.professionIndexes
        return i[1], i[2], i[3], i[4], i[5], i[6], i[7]
    end
    local list = ns.Data.ownProfessionsDetailed()
    eq(#list, 3, "three professions")
    eq(list[3].name, "急救", "seventh return read")
end)

test("16001: GetProfessionInfo errors -> empty, no Lua error", function()
    wow.reset()
    local ns = wow.loadAddon(ADDON_DIR)
    GetProfessionInfo = function() error("Usage: GetProfessionInfo(index)") end
    local list = ns.Data.ownProfessionsDetailed()
    eq(#list, 0, "nothing read")
    wow.fire("PLAYER_LOGIN"); wow.advance(10)
    -- GF-001-D23: listed but unreadable is not "none": the field is left out.
    eq(entriesOf("character.self")[1].payload.professions, nil, "entry still written, professions left out")
end)

test("16001: secret values become nil/empty, never stored", function()
    wow.reset({ secrets = { ["Horde"] = true, ["雷霆崖"] = true, ["會長"] = true } })
    wow.login(ADDON_DIR)
    local e = entriesOf("character.self")[1]
    eq(e.uploader.faction, "", "secret faction dropped")
    local snap = GreenFangToolkitDB.roster.snapshots["測試伺服器|綠皮與獠牙冒險事務所"]
    for _, s in ipairs(allStrings(GreenFangToolkitDB)) do
        ok(s ~= "Horde" and s ~= "雷霆崖" and s ~= "會長", "secret value stored: " .. s)
    end
    eq(#snap.members, 4, "scan still complete")
end)

test("16001: missing frame templates still open the window", function()
    wow.reset({ noTemplates = true })
    wow.login(ADDON_DIR)
    SlashCmdList.GREENFANGTOOLKIT("")
    ok(_G.GreenFangToolkit_MainWindow and _G.GreenFangToolkit_MainWindow:IsShown(), "window shown")
    -- GF-UI-D: the window is the theme's own frame; it needs no template at all.
    eq(_G.GreenFangToolkit_MainWindow._template, nil, "no frame template")
    eq(_G.GreenFangToolkit_MainWindow.gfTheme, "window", "the theme window")
end)

test("16001: no C_Club / C_CreatureInfo / GetPlayerInfoByGUID", function()
    wow.reset({ noClub = true })
    wow.login(ADDON_DIR)
    local e = entriesOf("roster.snapshot")[1]
    ok(e, "roster still written")
    for _, m in ipairs(e.payload.members) do
        if m.name ~= "測試甲-測試伺服器" then
            eq(m.race, nil, "unknown race is nil, not guessed")
            eq(m.professionSource, "missing", "unknown professions")
        end
    end
end)

test("16001: shifted GetGuildRosterInfo values are rejected, not stored wrong", function()
    wow.reset({ rosterOverride = function(i)
        if i > 4 then return nil end
        -- values one position off: guid lands where classToken was, etc.
        return "測試" .. i .. "-測試伺服器", 1, "會員", "戰士", 60, "奧格瑪", "", "", 0, true,
            "Player-0000-00000001", 0, 0, false, false, 4, "WARRIOR"
    end })
    wow.login(ADDON_DIR)
    local e = entriesOf("roster.snapshot")[1]
    ok(e, "snapshot written")
    local m = e.payload.members[1]
    eq(m.guid, nil, "non-GUID value not used as guid")
    eq(m.classToken, nil, "GUID not used as classToken")
    eq(m.level, nil, "non-number level dropped")
end)

---------------------------------------------------------------------------
-- Fixture for the GF Sync work line
---------------------------------------------------------------------------

local function buildFixture()
    -- Two characters of one account in the same guild; the second scans the roster.
    wow.reset({ now = 1763370000 })
    local saved = { GFGuildRosterDB = legacyDB() }
    wow.login(ADDON_DIR, saved)
    saved = wow.logout()
    local alt = wow.defaultPlayer()
    alt.guid, alt.name, alt.level, alt.class, alt.classToken = "Player-0000-0000000F", "測試己", 18, "薩滿", "SHAMAN"
    alt.race, alt.raceToken, alt.raceID = "食人妖", "Troll", 8
    alt.professions = { [1] = { "採礦", 134708, 75, 150, 0, 0, 186 }, [2] = { "鍛造", 136241, 70, 150, 0, 0, 164 } }
    alt.professionIndexes = { 1, 2 }
    wow.reset({ now = 1763373600, player = alt })
    local ns = wow.login(ADDON_DIR, saved)
    -- A guild member shares their own data in game -> member.share at logout (D-014).
    sendFrom(ns, "測試乙-測試伺服器", peerData({ capturedAt = 1763373590 }), "f1")
    saved = wow.logout()
    return saved.GreenFangToolkitDB
end

---------------------------------------------------------------------------
-- GF-001-D19: player text only, bigger icons, per-icon tooltips, filters,
-- recipe actions
---------------------------------------------------------------------------

local function tipText()
    local t = {}
    for _, l in ipairs(GameTooltip._lines) do t[#t + 1] = l.text end
    return table.concat(t, "\n")
end

test("D19 roster icons: 28 px (GF-UI-B), full colour for names only, 36 px rows", function()
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("roster")
    local named = rowFor(ns, "測試丙-測試伺服器")
    local s = named.profSlots[1]
    eq(s.icon._w, 28, "icon 28 px wide")
    eq(s.icon._h, 28, "icon 28 px high")
    eq(s.icon._alpha, 1, "names only: full colour")
    eq(named.profSlots[2].icon._alpha, 1, "second icon full colour too")
    eq(named._h, 36, "36 px rows")
end)

test("D19 roster tooltips: one profession over its icon, short member tooltip elsewhere", function()
    local ns = shareLogin({ player = crafter() })
    sendFrom(ns, PEER, peerData())
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, wow.state.now - 7200, { 2660, 2661 })))
    wow.state.minimapSize = 400 -- GF-UI-B: room for the own row (36 px rows)
    ns.Framework.open("roster")
    local peer = rowFor(ns, PEER)
    local smith = peer.profSlots[2]
    eq(ns.UI.slotAt(peer, smith.x0 + 1), smith, "cursor over the second icon")
    eq(ns.UI.slotAt(peer, smith.x1 + 3), nil, "between icons: none")
    ns.UI.showRowTooltip(peer, smith)
    eq(tipText(), "鍛造\n280 / 300\n配方 2 個", "that profession only")
    ns.UI.showRowTooltip(peer, peer.profSlots[3])
    eq(tipText(), "釣魚\n150 / 225", "fishing: name and rank / max")
    ns.UI.showRowTooltip(peer, nil)
    local tip = ns.UI.rosterCardText() -- GF-UI-I: the member tooltip is a card
    ok(tip:find("鍛造 280 / 300　配方 2 個", 1, true), "member tooltip: " .. tip)
    for _, gone in ipairs({ "更新時間", "本人", "分享", "點", "前", "技能點數未知" }) do
        ok(not tip:find(gone, 1, true), "no " .. gone)
    end
    -- Names only: the icon tooltip is the name.
    local named = rowFor(ns, "測試丙-測試伺服器")
    ns.UI.showRowTooltip(named, named.profSlots[1])
    eq(tipText(), "裁縫", "names only: just the name")
    -- Own row: the secure buttons have the same short tooltip.
    local b = ns.Professions.shown("roster")[1]
    b._scripts.OnEnter(b)
    tip = tipText()
    ok(not tip:find("點一下", 1, true), "own button: no hint: " .. tip)
    ok(tip:find(" / 75", 1, true), "own button: rank / max")
end)

test("D19 roster: the 專業 filter keeps members of that profession (GF-UI-B: the icon opens recipes)", function()
    local ns = shareLogin({ player = crafter() })
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    local peer = rowFor(ns, PEER)
    -- GF-UI-B (owner): filtering is on the filter bar only; a click on an icon opens that member's recipes.
    -- GF-UI-C: a multi-select list.
    ns.UI.skillChoice.setOnly(356)
    eq(ns.UI.filters.skills and ns.UI.filters.skills[356], true, "fishing filter")
    ok(ns.UI.skillChoice:GetText():find("釣魚", 1, true), "the profession button shows it")
    ok(ns.Framework.isModuleShown("roster"), "stays on the roster")
    local names = {}
    for _, row in ipairs(ns.UI.rows()) do if row:IsShown() then names[#names + 1] = row.memberName end end
    table.sort(names)
    eq(table.concat(names, ","), "測試乙-測試伺服器,測試甲-測試伺服器", "only members who fish")
    ns.UI.skillChoice.selectAll()
    eq(ns.UI.filters.skills, nil, "全選: cleared")
end)

test("D19 roster filters: profession (incl. secondary), class, online, minimum level, clear", function()
    local ns = shareLogin({ player = crafter() })
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    local function shown()
        local list = {}
        for _, row in ipairs(ns.UI.rows()) do if row:IsShown() then list[#list + 1] = ns.shortName(row.memberName) end end
        table.sort(list)
        return table.concat(list, ",")
    end
    eq(shown(), "測試丁,測試丙,測試乙,測試甲", "everyone")
    local opts = {}
    for _, o in ipairs(ns.UI.professionOptions()) do opts[#opts + 1] = o.text end
    eq(table.concat(opts, ","), "鍛造,採礦,裁縫,附魔,烹飪,急救,釣魚", "professions in the roster, secondary last (GF-UI-C: 全選 is in the list)")
    ns.UI.skillChoice.setOnly(197)
    eq(shown(), "測試丙", "tailoring (from the guild roster names)")
    ns.UI.skillChoice.setOnly(129)
    eq(shown(), "測試乙,測試甲", "first aid (secondary, shared)")
    ns.UI.skillChoice.selectAll()
    ns.UI.classChoice.setOnly("WARRIOR")
    eq(shown(), "測試乙", "warriors")
    ns.UI.classChoice.selectAll()
    wow.click(ns.UI.onlineCheck)
    eq(shown(), "測試乙,測試甲", "online only")
    ns.UI.levelBox:SetText("30")
    ns.UI.levelBox._scripts.OnTextChanged(ns.UI.levelBox)
    eq(shown(), "測試乙,測試甲", "online and level 30+")
    wow.click(ns.UI.onlineCheck)
    eq(shown(), "測試乙,測試甲", "level 30+")
    ns.UI.levelBox:SetText("50")
    ns.UI.levelBox._scripts.OnTextChanged(ns.UI.levelBox)
    eq(shown(), "測試乙", "level 50+")
    ns.UI.skillChoice.setOnly(197)
    eq(shown(), "", "nobody: tailoring and 50+")
    wow.click(ns.UI.clearButton)
    eq(shown(), "測試丁,測試丙,測試乙,測試甲", "清除 resets every filter")
    eq(ns.UI.filters.skill, nil, "skill cleared"); eq(ns.UI.filters.minLevel, nil, "level cleared")
    eq(ns.UI.onlineCheck.checked, false, "online cleared")
    -- The list opens with the options; GF-UI-C: a check list stays open (tick several).
    wow.click(ns.UI.classChoice)
    ok(ns.UI.classChoice.menu:IsShown(), "class list open")
    local item = ns.UI.classChoice.menu.items[3] -- the first class (after 全選, 全不選)
    wow.click(item)
    ok(ns.UI.classChoice.menu:IsShown(), "stays open after a tick")
    ok(ns.UI.filters.classes ~= nil, "a class unticked")
    wow.click(ns.UI.classChoice)
    ok(not ns.UI.classChoice.menu:IsShown(), "the button again closes it")
end)

test("D19 roster page text: footer is just the count, header time without seconds", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("roster")
    local texts = table.concat(wow.allTexts(), "\n")
    -- GF-UI-B: the count is 「4/4」 on the tool bar; the scan time only in 同步與診斷.
    eq(ns.UI.countText:GetText(), "4/4", "count")
    ok(not texts:find("點欄位標題排序", 1, true), "no sort hint")
    ok(not texts:find("點成員看他的配方", 1, true), "no recipe hint")
    local s = ns.Roster.current()
    s.capturedAtLocal = "2026-11-20 21:05:33"
    eq(ns.UI.shortTime(s), "2026-11-20 21:05", "no seconds")
    ns.UI.refresh(false)
    texts = table.concat(wow.allTexts(), "\n")
    ok(not texts:find("2026-11-20 21:05", 1, true), "no scan time on the page")
    ok(ns.Diag.rosterText():find("2026-11-20 21:05", 1, true), "it is in 同步與診斷")
end)

test("D19 player text: no hints or technical lines on the pages", function()
    local ns = shareLogin({ player = crafter(), tradeSkill = leatherWindow() })
    wow.fire("TRADE_SKILL_SHOW")
    for _, id in ipairs({ "roster", "recipes", "character", "sleepingbag" }) do ns.Framework.open(id) end
    local texts = table.concat(wow.allTexts(), "\n")
    for _, gone in ipairs({ "點一下", "點專業", "點欄位", "點成員", "戰鬥中不可用", "打開自己的專業視窗",
        "分享與轉傳", "在線的在前", "還沒記錄配方", "（點一下切換）", "剛剛記錄", "（本人）" }) do
        ok(not texts:find(gone, 1, true), "no " .. gone)
    end
    local b = ns.Diag.smallButton(UIParent, "CENTER", 0, 0)
    b._scripts.OnEnter(b)
    eq(tipText(), "同步與診斷", "diag button: name only")
end)

test("D19 recipe filters: only mine / only others, only online crafters, search", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    wow.fire("TRADE_SKILL_SHOW") -- own 製皮: 2149, 2152
    local t = wow.state.now - 600
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 165, t, { 2152, 2153 })))   -- online
    shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 165, t, { 2153, 2160 })))  -- offline
    local index = ns.Recipes.index()
    local function ids(opts)
        local list = {}
        for _, r in ipairs(ns.Recipes.rows(index, 165, "", nil, opts)) do list[#list + 1] = r.id end
        table.sort(list)
        return table.concat(list, ",")
    end
    eq(ids(nil), "2149,2152,2153,2160", "all")
    eq(ids({ who = "mine" }), "2149,2152", "only mine")
    eq(ids({ who = "others" }), "2152,2153,2160", "only others")
    eq(ids({ online = true }), "2149,2152,2153", "only online crafters (self is online)")
    eq(ids({ online = true, who = "others" }), "2152,2153", "online others")
    local row = ns.Recipes.rows(index, 165, "", nil, { online = true })
    for _, r in ipairs(row) do
        for _, m in ipairs(r.crafters) do ok(m.online, "only online crafters listed") end
    end
    -- On the page.
    ns.Recipes.show(nil, 165)
    ns.Recipes.whoChoice.toggle("others") -- only 我 left
    local shown = 0
    for _, r in ipairs(ns.Recipes.rowFrames()) do if r:IsShown() then shown = shown + 1 end end
    eq(shown, 2, "page: only mine")
    wow.click(ns.Recipes.onlineCheck)
    eq(ns.Recipes.state.online, true, "online check")
    ns.Recipes.whoChoice.selectAll()
    wow.click(ns.Recipes.onlineCheck)
    shown = 0
    for _, r in ipairs(ns.Recipes.rowFrames()) do if r:IsShown() then shown = shown + 1 end end
    eq(shown, 4, "page: all again")
end)

test("D20 recipe clicks: mine opens, others pinned, Shift links, right-click whisper menu", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    wow.fire("TRADE_SKILL_SHOW")                                          -- mine: 2149, 2152
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 165, wow.state.now - 600, { 2152, 2153 })))  -- online
    shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 165, wow.state.now - 600, { 2153 })))       -- offline
    local calls = {}
    C_TradeSkillUI.GetRecipeLink = function(id) return "|cffffd000|Henchant:" .. id .. "|h[配方" .. id .. "]|h|r" end
    C_TradeSkillUI.OpenRecipe = function(id) calls[#calls + 1] = "open:" .. id end
    ChatEdit_InsertLink = function(link) calls[#calls + 1] = "insert:" .. link; return true end
    ChatFrame_SendTellWithMessage = function(name, text) calls[#calls + 1] = "tell:" .. name .. ":" .. text end
    local pinned
    ItemRefTooltip = { SetOwner = function() end, SetHyperlink = function(_, h) pinned = h end, Show = function() end }
    local shift = false
    IsShiftKeyDown = function() return shift end
    ns.Recipes.show(nil, 165)
    local function rowOf(id)
        for _, r in ipairs(ns.Recipes.rowFrames()) do if r:IsShown() and r.data and r.data.id == id then return r end end
    end
    local mine, theirs = rowOf(2152), rowOf(2153)
    ok(mine and theirs, "rows")
    eq(ns.Recipes.actions, nil, "no hover buttons any more")
    -- Click.
    eq(ns.Recipes.click(mine, "LeftButton"), "open", "my recipe: opened in my profession window")
    eq(calls[#calls], "open:2152", "OpenRecipe")
    eq(ns.Recipes.click(theirs, "LeftButton"), "detail", "someone else's: pinned")
    eq(pinned, "enchant:2153", "pinned link")
    C_TradeSkillUI.OpenRecipe = function() error("blocked") end
    pinned = nil
    eq(ns.Recipes.click(mine, "LeftButton"), "detail", "open fails: pinned instead")
    eq(pinned, "enchant:2152", "pinned link")
    wow.enterCombat()
    pinned = nil
    eq(ns.Recipes.click(mine, "LeftButton"), "detail", "in combat: pinned, never opened")
    wow.leaveCombat()
    shift = true
    eq(ns.Recipes.click(theirs, "LeftButton"), "link", "Shift-click")
    eq(calls[#calls], "insert:|cffffd000|Henchant:2153|h[配方2153]|h|r", "link in chat")
    shift = false
    -- Right-click: one 密語 line per online crafter (not me, not offline).
    eq(ns.Recipes.click(theirs, "RightButton"), "menu", "menu")
    local menu = _G[ns.Framework.MENU_NAME]
    ok(menu and menu:IsShown(), "menu shown")
    ok(menu.gfOpaque, "menu is opaque")
    local items = {}
    for _, b in ipairs(menu.items) do if b:IsShown() then items[#items + 1] = b:GetText() end end
    -- GF-006-B (R-5.1): 「下單」 comes first, then one 密語 per online crafter.
    eq(table.concat(items, "|"), "下單|密語 測試乙", "下單, then only the online crafter")
    wow.click(menu.items[2])
    eq(calls[#calls], "tell:" .. PEER .. ":可以幫我做|cffffd000|Henchant:2153|h[配方2153]|h|r嗎？", "whisper opened")
    ok(not menu:IsShown(), "closed after the pick")
    local onlyMine = rowOf(2149)
    -- Nobody else online: no 密語 line; my own recipe still offers 「我的工錢」 (GF-006-B, R-4.3).
    eq(ns.Recipes.click(onlyMine, "RightButton"), "menu", "my recipe: fee menu")
    local mineItems = {}
    for _, b in ipairs(menu.items) do if b:IsShown() then mineItems[#mineItems + 1] = b:GetText() end end
    ok(not table.concat(mineItems, "|"):find("密語", 1, true), "no whisper line: " .. table.concat(mineItems, "|"))
    ok(table.concat(mineItems, "|"):find("我的工錢", 1, true), "fee item on my recipe")
    ns.Framework.closeMenu()
    -- The row stays shown while hovered and after the cursor leaves (0.9.4 hid it).
    theirs._scripts.OnEnter(theirs)
    ok(theirs:IsShown(), "shown while hovered")
    theirs._scripts.OnLeave(theirs)
    ok(theirs:IsShown(), "still shown after the cursor leaves")
    ns.Recipes.refresh()
    ok(rowOf(2153), "still shown after a redraw")
    eq(theirs.name:GetText() ~= "", true, "text kept")
    -- Without the newer functions: the spell link, and the chat box opened.
    C_TradeSkillUI.GetRecipeLink = nil
    C_Spell.GetSpellLink = function(id) return "|Hspell:" .. id .. "|h[x]|h" end
    ChatEdit_InsertLink = function() return false end
    local opened
    ChatFrame_OpenChat = function(text) opened = text end
    ok(ns.Recipes.insertLink(2149), "chat opened with the link")
    eq(opened, "|Hspell:2149|h[x]|h", "spell link")
    ItemRefTooltip = nil
    eq(ns.Recipes.showDetail(2149), false, "no pinned tooltip in this client: nothing happens")
    ChatEdit_InsertLink, ChatFrame_SendTellWithMessage, ChatFrame_OpenChat, IsShiftKeyDown = nil, nil, nil, nil
    eq(#wow.state.blocked, 0, "nothing blocked")
end)

test("D20 recipe filter lines: 搜尋, 專業, 會做的人 on one line, 只看在線 under 搜尋 (GF-UI-C grid); no tabs", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    wow.fire("TRADE_SKILL_SHOW")
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, wow.state.now - 600, { 2660, 2661 })))
    ns.Framework.open("recipes")
    local R = ns.Recipes
    local function y(w) return w._points[1][5] end
    eq(y(R.searchBox), -44, "search on the filter line")
    eq(y(R.skillChoice), -44, "專業 on the filter line")
    eq(y(R.whoChoice), -44, "會做的人 on the filter line")
    eq(y(R.onlineCheck), -82, "只看在線 on the second line, under 搜尋 (GF-UI-C)")
    local texts = table.concat(wow.allTexts(), "\n")
    for _, want in ipairs({ "搜尋", "專業", "會做的人", "只看在線" }) do ok(texts:find(want, 1, true), "label " .. want) end
    ok(R.skillChoice:GetText():find("全部專業", 1, true), "all ticked at first: " .. R.skillChoice:GetText())
    local opts = {}
    for _, o in ipairs(R.skillOptions()) do opts[#opts + 1] = o.text end
    eq(table.concat(opts, ","), "鍛造,製皮", "professions with recipes")
    R.skillChoice.setOnly(165)
    eq(table.concat(R.state.skills, ","), "165", "picked")
    ok(R.skillChoice:GetText():find("製皮", 1, true), "button shows it")
    ok(texts:find("個配方", 1, true), "count")
    -- No tab buttons above the list any more.
    for _, t in ipairs(wow.allTexts()) do ok(t ~= "鍛造" or false, "no tab labelled 鍛造") end
end)

test("D20 popups: 同步與診斷 and export are opaque, framed and above the toolkit window", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("roster")
    ns.Diag.open()
    local d = _G[ns.Diag.WINDOW_NAME]
    ok(d.gfOpaque, "diag: own opaque background")
    eq(d.gfOpaque._color and d.gfOpaque._color[4] or d.gfOpaque._colorTexture[4], 0.97, "diag: nearly solid")
    eq(d._strata, "FULLSCREEN_DIALOG", "diag above the toolkit window (DIALOG)")
    ns.UI.startExport("tsv")
    local e = _G.GreenFangToolkit_ExportWindow
    ok(e.gfOpaque, "export: opaque")
    eq(e._strata, "FULLSCREEN_DIALOG", "export above the toolkit window")
    ok(_G[ns.Framework.WINDOW_NAME].gfOpaque, "toolkit window: opaque too")
    wow.click(ns.UI.classChoice)
    ok(ns.UI.classChoice.menu.gfOpaque, "filter list: opaque")
    eq(ns.UI.classChoice.menu._strata, "TOOLTIP", "filter list on top (GF-002-F: above the click-outside layer)")
end)

test("D20 roster filter line: labels and boxes do not overlap", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    ns.Framework.open("roster")
    -- Left edge and width of each control on the line, in order.
    local function x(w) return w._points[1][4] end
    local list = {
        { "搜尋", x(ns.UI.searchBox), ns.UI.searchBox._w },
        { "專業", x(ns.UI.skillChoice), ns.UI.skillChoice._w },
        { "職業", x(ns.UI.classChoice), ns.UI.classChoice._w },
        { "在線", x(ns.UI.onlineCheck), 24 + 60 },
        { "等級", x(ns.UI.levelLabel), 30 },
        { "等級框", x(ns.UI.levelBox), ns.UI.levelBox._w },
        { "以上", x(ns.UI.levelSuffix), 26 },
        { "清除", x(ns.UI.clearButton), ns.UI.clearButton._w },
    }
    for i = 2, #list do
        local prev, cur = list[i - 1], list[i]
        -- Input boxes draw their border about 6 px outside their edges.
        ok(prev[2] + prev[3] + 6 <= cur[2], prev[1] .. " ends before " .. cur[1] .. " starts")
    end
    ok(ns.UI.levelBox._w >= 40, "level box wide enough for two digits")
    ok(list[#list][2] + list[#list][3] <= 1000 - 20, "fits in the page")
end)

---------------------------------------------------------------------------
-- GF-001-D21: profession filter, tooltip position, recipe icons
---------------------------------------------------------------------------

-- Cooking window that, like Forever, also lists first aid and smelting.
local function mixedCookingWindow()
    return { skillLine = 185,
        recipes = { [2538] = true, [2540] = true, [818] = true, [3275] = true, [2657] = true, [2659] = true },
        recipeSkills = { [2538] = 185, [2540] = 185, [818] = 185, [3275] = 129, [2657] = 186, [2659] = 186 } }
end

local function shownRecipeIDs(ns)
    local list = {}
    for _, r in ipairs(ns.Recipes.shownRows()) do list[#list + 1] = r.id end
    table.sort(list)
    return table.concat(list, ",")
end

test("D21 recipes: a cooking window storing first aid and smelting keeps only cooking", function()
    local ns = shareLogin({ tradeSkill = mixedCookingWindow() })
    wow.fire("TRADE_SKILL_SHOW")
    eq(table.concat(ns.Share.decodeValue("R185", ns.Share.get(A_SELF, "R185").v), ","), "818,2538,2540",
        "only cooking stored")
    eq(ns.Recipes.skillOfRecipe(3275), 129, "first aid recipe known as first aid")
    eq(ns.Recipes.inSkill(2657, 185), false, "smelting is not cooking")
    eq(ns.Recipes.inSkill(99999, 185), nil, "unknown recipe: cannot tell")
end)

test("D21 recipes: a mixed list saved by 0.9.5 is cleaned at the next read", function()
    local ns = shareLogin({ tradeSkill = mixedCookingWindow() })
    ns.Share.ownRecord("R185", ns.Share.encodeValue("R185", { 818, 2538, 2540, 2657, 2659, 3275 }))
    eq(ns.Recipes.scan(), "stored", "rewritten")
    eq(table.concat(ns.Share.decodeValue("R185", ns.Share.get(A_SELF, "R185").v), ","), "818,2538,2540", "clean")
    -- With a window filter the saved list stays, but cleaned too.
    ns.Share.ownRecord("R185", ns.Share.encodeValue("R185", { 818, 2538, 2540, 2657, 3275 }))
    wow.state.tradeSkill.recipes = { [818] = true }
    eq(ns.Recipes.scan(), "filtered", "window filter")
    eq(table.concat(ns.Share.decodeValue("R185", ns.Share.get(A_SELF, "R185").v), ","), "818,2538,2540",
        "saved list kept without the mixed-in recipes")
end)

test("D21 recipe page: 專業 = 烹飪 lists only cooking, also from members on 0.9.5; count matches", function()
    local ns = shareLogin({ tradeSkill = mixedCookingWindow() })
    wow.fire("TRADE_SKILL_SHOW")
    -- A member on 0.9.5 shared a mixed R185 and a first aid list.
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 185, wow.state.now - 600, { 2538, 2657, 3275, 4444 })))
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 129, wow.state.now - 600, { 3275 })))
    ns.Recipes.show(nil, 185)
    ns.Recipes.skillChoice.setOnly(185)
    -- 4444: the client does not say which profession -> kept.
    eq(shownRecipeIDs(ns), "818,2538,2540,4444", "cooking only (and the unknown one)")
    local texts = table.concat(wow.allTexts(), "\n")
    ok(texts:find("4 個配方", 1, true), "count matches the list")
    ns.Recipes.skillChoice.setOnly(129)
    eq(shownRecipeIDs(ns), "3275", "first aid")
    ok(table.concat(wow.allTexts(), "\n"):find("1 個配方", 1, true), "count for first aid")
    local opts = {}
    for _, o in ipairs(ns.Recipes.skillOptions()) do opts[#opts + 1] = o.text end
    eq(table.concat(opts, ","), "急救,烹飪", "no mining entry made from mixed-in recipes")
end)

test("D21 tooltips: recipe tooltip next to the row's name; roster icon tooltip over the icon", function()
    local ns = shareLogin({ tradeSkill = leatherWindow(), player = crafter() })
    wow.fire("TRADE_SKILL_SHOW")
    ns.Recipes.show(nil, 165)
    local row
    for _, r in ipairs(ns.Recipes.rowFrames()) do if r:IsShown() then row = r; break end end
    row._scripts.OnEnter(row)
    eq(GameTooltip._anchor, "ANCHOR_NONE", "not the default (screen corner) anchor")
    local pt = GameTooltip._points[1]
    eq(pt[1] .. ">" .. pt[3], "BOTTOMLEFT>TOPLEFT", "just above the row")
    eq(pt[2], row, "on the hovered row")
    eq(pt[4], 300, "next to the name, towards the middle")
    sendFrom(ns, PEER, peerData())
    ns.Framework.open("roster")
    local peer = rowFor(ns, PEER)
    local slot = peer.profSlots[2]
    ns.UI.showRowTooltip(peer, slot)
    eq(GameTooltip._points[1][4], slot.x0, "icon tooltip over that icon")
    ns.UI.showRowTooltip(peer, nil)
    -- GF-UI-I: the member card, above the row's middle (was GameTooltip ANCHOR_TOP).
    local cp = ns.UI.rosterCard()._points[1]
    eq(cp[1] .. ">" .. cp[3], "BOTTOM>TOP", "member card above the row's middle")
    eq(cp[2], peer, "on the row")
end)

test("D21 recipe icons: crafted item, else spell icon, else the profession's; cached", function()
    local ns = shareLogin({ tradeSkill = leatherWindow() })
    wow.fire("TRADE_SKILL_SHOW")              -- 2149, 2152
    local schematics = 0
    C_TradeSkillUI.GetRecipeSchematic = function(id)
        schematics = schematics + 1
        if id == 2152 then return { outputItemID = 2304 } end
        return {}
    end
    C_Item = { GetItemIconByID = function(item) return item == 2304 and 133611 or nil end }
    C_Spell.GetSpellTexture = function(id) return id == 2149 and 132539 or nil end
    eq(ns.Recipes.icon(2152), 133611, "crafted item's icon")
    eq(ns.Recipes.icon(2149), 132539, "spell icon when there is no item")
    eq(ns.Recipes.icon(2152), 133611, "again")
    eq(schematics, 2, "cached: asked once per recipe")
    eq(ns.Recipes.icon(2153), nil, "unknown")
    ns.Recipes.show(nil, 165)
    local icons = {}
    for _, r in ipairs(ns.Recipes.rowFrames()) do
        if r:IsShown() and r.data then
            icons[#icons + 1] = r.data.id .. "=" .. tostring(r.icon:IsShown() and r.icon._texture)
            eq(r.icon._w, 28, "28 px (GF-002-F: 36 px rows)")
        end
    end
    table.sort(icons)
    eq(table.concat(icons, ","), "2149=132539,2152=133611", "icons on the rows")
    local tex = CreateFrame("Frame"):CreateTexture()
    eq(ns.Recipes.setIcon(tex, 2153, 165), "Interface\\Icons\\Trade_LeatherWorking", "unknown: the profession icon")
    C_Item = nil
end)

---------------------------------------------------------------------------
-- GF-001-D22: multi-select 專業 and 會做的人 on the recipe page
---------------------------------------------------------------------------

local function recipeIDs(ns)
    local list = {}
    for _, r in ipairs(ns.Recipes.shownRows()) do list[#list + 1] = r.id end
    table.sort(list)
    return table.concat(list, ",")
end

local function multiPage()
    local ns = shareLogin({ tradeSkill = mixedCookingWindow() }) -- mine: cooking 818, 2538, 2540
    wow.fire("TRADE_SKILL_SHOW")
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 129, wow.state.now - 600, { 3275 })))         -- first aid
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 186, wow.state.now - 600, { 2657, 2659 })))   -- smelting
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 185, wow.state.now - 600, { 2538 })))          -- cooking
    ns.Framework.open("recipes")
    return ns
end

test("D22 recipe 專業: all by default, tick several, 全選 / 全不選, button summary, count", function()
    local ns = multiPage()
    local b = ns.Recipes.skillChoice
    eq(b:GetText(), "全部專業", "all ticked at first (GF-UI-B: the arrow is a texture)")
    ok(b.arrow and b.arrow._texture, "arrow texture")
    eq(recipeIDs(ns), "818,2538,2540,2657,2659,3275", "every profession in one list")
    ok(table.concat(wow.allTexts(), "\n"):find("6 個配方", 1, true), "count")
    b.toggle(186)
    eq(b:GetText(), "2 個專業", "two left")
    eq(recipeIDs(ns), "818,2538,2540,3275", "smelting unticked: gone")
    b.toggle(129)
    eq(b:GetText(), "烹飪", "one left: its name")
    eq(recipeIDs(ns), "818,2538,2540", "cooking only")
    ok(table.concat(wow.allTexts(), "\n"):find("3 個配方", 1, true), "count follows")
    b.selectNone()
    eq(b:GetText(), "未選", "none")
    eq(recipeIDs(ns), "", "nothing listed")
    ok(table.concat(wow.allTexts(), "\n"):find("未選專業", 1, true), "says so (no sentence)")
    b.toggle(129); b.toggle(185); b.toggle(186)
    eq(b:GetText(), "全部專業", "all ticked again = 全部專業")
    eq(b.selected, nil, "stored as everything (a new profession is included)")
    b.selectNone(); b.selectAll()
    eq(recipeIDs(ns), "818,2538,2540,2657,2659,3275", "全選")
    -- Rows of several professions are sorted by name, each with its own icon fallback.
    local skills = {}
    for _, r in ipairs(ns.Recipes.shownRows()) do skills[r.id] = r.skill end
    eq(skills[3275], 129, "row knows its profession"); eq(skills[2657], 186, "smelting row")
end)

test("D22 recipe 專業 list: check boxes with icons, 全選 and 全不選 first, stays open", function()
    local ns = multiPage()
    local b = ns.Recipes.skillChoice
    wow.click(b)
    ok(b.menu:IsShown(), "list open")
    ok(b.menu.gfOpaque, "opaque")
    local items = {}
    for _, it in ipairs(b.menu.items) do
        if it:IsShown() then
            items[#items + 1] = it.label:GetText() .. (it.isOption and (it.checked and "[x]" or "[ ]") or "")
                .. (it.icon:IsShown() and "+icon" or "")
        end
    end
    eq(table.concat(items, "|"), "全選|全不選|採礦[x]+icon|急救[x]+icon|烹飪[x]+icon", "entries (primary first)")
    eq(b.menu.items[4].icon._texture, "Interface\\Icons\\Spell_Holy_SealOfSacrifice", "first aid icon")
    -- GF-UI-B: the drop-down check sheet; ticked and empty boxes are both drawn.
    eq(b.menu.items[3].check._texture, "Interface\\Common\\UI-DropDownRadioChecks", "check mark")
    eq(b.menu.items[3].check._texCoord[1], 0, "ticked box")
    wow.click(b.menu.items[5]) -- 烹飪
    ok(b.menu:IsShown(), "still open: tick several")
    ok(b.menu.items[5].check:IsShown() and b.menu.items[5].check._texCoord[1] == 0.5, "unticked: the empty box")
    eq(b.menu.items[5].checked, false, "unticked")
    eq(b:GetText(), "2 個專業", "button follows")
    wow.click(b.menu.items[2]) -- 全不選
    eq(b:GetText(), "未選", "全不選")
    wow.click(b.menu.items[1]) -- 全選
    eq(b:GetText(), "全部專業", "全選")
    wow.click(b)
    ok(not b.menu:IsShown(), "button again: closed")
end)

test("D22 recipe 會做的人: 我 and 別人 as two check boxes", function()
    local ns = multiPage()
    local w = ns.Recipes.whoChoice
    eq(w:GetText(), "所有人", "both at first")
    w.toggle("others")
    eq(w:GetText(), "我的", "only me")
    eq(recipeIDs(ns), "818,2538,2540", "my recipes")
    w.toggle("me"); w.toggle("others")
    eq(w:GetText(), "別人的", "only others")
    eq(recipeIDs(ns), "2538,2657,2659,3275", "the others' recipes")
    w.toggle("others")
    eq(w:GetText(), "未選", "neither")
    eq(recipeIDs(ns), "", "nothing")
    w.selectAll()
    eq(recipeIDs(ns), "818,2538,2540,2657,2659,3275", "everyone")
    -- Together with 專業 and 只看在線.
    ns.Recipes.skillChoice.setOnly(185)
    w.toggle("me") -- only others
    eq(recipeIDs(ns), "2538", "others' cooking")
end)

test("D22 recipe page: a long list only has frames for the rows in view", function()
    local ns = multiPage()
    local ids = {}
    for i = 1, 300 do ids[i] = 20000 + i end
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, wow.state.now - 500, ids)))
    wow.advance(1.2)
    ns.Recipes.refresh()
    eq(#ns.Recipes.shownRows(), 306, "every recipe in the list")
    ok(#ns.Recipes.rowFrames() < 40, "few frames: " .. #ns.Recipes.rowFrames())
end)

---------------------------------------------------------------------------
-- GF-001-D23: never an empty realm in the outbox (invalid_realm since 2026-11-21)
---------------------------------------------------------------------------

local function noRealmPlayer(realm)
    local p = wow.defaultPlayer()
    p.realm = realm or ""
    return p
end

local function realmsIn(kind)
    local list = {}
    for _, e in ipairs(entriesOf(kind)) do
        list[#list + 1] = tostring(e.game and e.game.realm) .. "/" .. tostring(e.uploader and e.uploader.realm)
    end
    return table.concat(list, ",")
end

test("D23 realm: GetRealmName empty and nothing remembered -> no entry at all, 同步與診斷 says so", function()
    wow.reset({ player = noRealmPlayer("") })
    local ns = wow.login(ADDON_DIR)
    wow.advance(30)
    wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
    eq(#entriesOf("character.self"), 0, "no character.self with an empty realm")
    eq(#entriesOf("roster.snapshot"), 0, "no roster.snapshot with an empty realm")
    local _, why = ns.Sync.recordSelf(true, { allowNoGuild = true })
    eq(why, "waiting-realm", "waiting for the realm")
    ok(ns.Diag.versionText():find("伺服器 不明（暫停寫入上傳資料）", 1, true), "diag: " .. ns.Diag.versionText())
    wow.logout()
    for _, e in ipairs(outbox()) do
        ok(e.game.realm ~= "" and e.uploader.realm ~= "", "never an empty realm in the outbox")
    end
end)

test("D23 realm: a secret GetRealmName counts as empty", function()
    wow.reset({ secrets = { ["測試伺服器"] = true } })
    local ns = wow.login(ADDON_DIR)
    wow.advance(30)
    eq(#entriesOf("character.self"), 0, "nothing written")
    eq(ns.realm(), "", "unknown")
end)

test("D23 realm: remembered from an earlier login when GetRealmName goes empty", function()
    wow.reset()
    local ns = wow.login(ADDON_DIR)
    wow.advance(30)
    eq(GreenFangToolkitDB.settings.realms["Player-0000-0000000A"], "測試伺服器", "remembered per character")
    local saved = GreenFangToolkitDB
    GreenFangToolkitDB.sync.outbox = {}
    wow.reset({ player = noRealmPlayer("") })
    ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = saved })
    wow.advance(30)
    eq(realmsIn("character.self"), "測試伺服器/測試伺服器", "the remembered realm")
    eq(ns.realmSource, "saved", "source")
    ok(ns.Diag.versionText():find("伺服器 「測試伺服器」（存檔記住的）", 1, true), "diag: " .. ns.Diag.versionText())
end)

test("D23 realm: seeded from realms already in the SavedVariables; old empty entries repaired", function()
    wow.reset()
    wow.login(ADDON_DIR)
    wow.advance(30)
    wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
    local saved = GreenFangToolkitDB
    saved.settings.realms = nil -- a 0.9.6 file: no remembered realm
    -- 0.9.5/0.9.6 queued entries with an empty realm; the roster snapshot still has it.
    for _, e in ipairs(saved.sync.outbox) do e.game.realm = ""; e.uploader.realm = "" end
    wow.reset({ player = noRealmPlayer("") })
    local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = saved })
    wow.advance(30)
    wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
    eq(realmsIn("character.self"), "測試伺服器/測試伺服器", "realm from the saved roster snapshot")
    for _, e in ipairs(outbox()) do
        eq(e.game.realm .. "/" .. e.uploader.realm, "測試伺服器/測試伺服器", "every queued entry repaired: " .. e.kind)
    end
end)

test("D23 realm: GetNormalizedRealmName when nothing else; never a remembered realm it contradicts", function()
    wow.reset({ player = noRealmPlayer("") })
    GetNormalizedRealmName = function() return "測試伺服器2" end
    local ns = wow.login(ADDON_DIR)
    wow.advance(30)
    eq(realmsIn("character.self"), "測試伺服器2/測試伺服器2", "normalized name")
    -- Once a roster snapshot holds it, it is also "saved"; the value is what counts.
    ok(ns.realmSource == "GetNormalizedRealmName" or ns.realmSource == "saved", "source: " .. ns.realmSource)
    GreenFangToolkitDB.settings.realms["Player-0000-0000000A"] = "Other Realm"
    eq(ns.realm(), "測試伺服器2", "remembered realm of another name is not used")
    GreenFangToolkitDB.settings.realms["Player-0000-0000000A"] = "測試 伺服器2"
    eq(ns.realm(), "測試 伺服器2", "the same realm with spaces wins over the normalized one")
    GetNormalizedRealmName = nil
end)

test("D23 professions: unreadable names are not 'no professions'", function()
    -- Names the client keeps secret: listed by GetProfessions, unreadable.
    wow.reset({ player = crafter() })
    local ns = wow.login(ADDON_DIR)
    wow.advance(30)
    eq(#entriesOf("character.self")[1].payload.professions, 5, "read normally")
    for _, row in pairs(wow.state.player.professions) do wow.state.secrets[row[1]] = true end
    ns.Sync.recordSelf(true)
    eq(ns.Data.unreadableProfessions, 5, "five unreadable")
    eq(#entriesOf("character.self")[1].payload.professions, 5, "last known professions kept")
    -- None known before: the field is left out, never {}.
    GreenFangToolkitDB.sync.outbox = {}
    ns.Sync.recordSelf(true)
    eq(entriesOf("character.self")[1].payload.professions, nil, "left out")
    -- Really no professions: {} as before.
    wow.reset()
    wow.state.player.professions, wow.state.player.professionIndexes = {}, {}
    wow.login(ADDON_DIR)
    wow.advance(30)
    local list = entriesOf("character.self")[1].payload.professions
    eq(type(list) == "table" and #list, 0, "no professions: empty list")
end)

test("D23 shared data kept under an empty realm by 0.9.5/0.9.6 is merged back", function()
    local ns = shareLogin()
    shareFrom(ns, PEER, (rMsg(ns, A_PEER, 164, wow.state.now - 600, { 2660 })))
    local saved = GreenFangToolkitDB
    local guild = ns.Data.player().guild
    local realKey = ns.guildKey("測試伺服器", guild)
    ok(saved.share.guilds[realKey], "store under realm|guild")
    -- What 0.9.6 did with an empty realm: a second store under "|guild".
    saved.share.guilds["|" .. guild] = { rec = {
        [A_PEER] = { R164 = { t = wow.state.now - 60, h = "x", v = "newer" } },
        [A_THIRD] = { R197 = { t = wow.state.now - 60, h = "y", v = "only here" } },
    }, tomb = {}, gone = {} }
    saved.share.guilds[realKey].rec[A_PEER].R164.t = wow.state.now - 600
    wow.reset()
    ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = saved })
    ns.Share.rand = function(a) return a end
    wow.advance(25)
    ok(ns.Share.store(), "store")
    eq(GreenFangToolkitDB.share.guilds["|" .. guild], nil, "the empty-realm store is gone")
    eq(ns.Share.get(A_PEER, "R164").v, "newer", "newer record wins")
    eq(ns.Share.get(A_THIRD, "R197").v, "only here", "records only there are kept")
end)

-- GF-001-D24: uploader.fullName ("名字 姓氏") for the site's roster match.
local function surnameRoster()
    local roster = wow.defaultRoster()
    roster[1].name = "測試甲 長姓氏"         -- own character, as the guild roster shows it
    roster[3].name = "測試丙 長姓氏-測試伺服器"
    return roster
end

test("D24 fullName: character.self and roster.snapshot carry the roster's full name; name unchanged", function()
    wow.reset({ roster = surnameRoster() })
    local ns = wow.login(ADDON_DIR)
    local selfE = entriesOf("character.self")[1]
    ok(selfE, "character.self")
    eq(selfE.uploader.fullName, "測試甲 長姓氏", "character.self uploader.fullName")
    eq(selfE.uploader.name, "測試甲", "uploader.name stays UnitName")
    local snap = entriesOf("roster.snapshot")[1]
    eq(snap.uploader.fullName, "測試甲 長姓氏", "roster.snapshot uploader.fullName")
    eq(GreenFangToolkitDB.settings.fullNames["Player-0000-0000000A"], "測試甲 長姓氏", "remembered per character")
    ok(ns.Diag.versionText():find("角色全名 「測試甲 長姓氏」", 1, true), "diag: " .. ns.Diag.versionText())
end)

test("D24 fullName: member.share uploader and subject carry the roster's full name", function()
    local ns = shareLogin({ roster = surnameRoster() })
    shareFrom(ns, PEER, (vMsg(ns, A_THIRD, "B", wow.state.now - 600, { level = 40, classToken = "MAGE" })))
    eq(ns.Sync.recordShares(), 1, "one subject")
    local e = entriesOf("member.share")[1]
    eq(e.uploader.fullName, "測試甲 長姓氏", "uploader.fullName")
    eq(e.uploader.name, "測試甲", "uploader.name unchanged")
    eq(e.payload.subject.guid, "Player-0000-0000000C", "subject guid")
    eq(e.payload.subject.fullName, "測試丙 長姓氏", "subject fullName, no -Realm")
end)

test("D24 fullName: the login entry waits for the roster, then carries the full name", function()
    wow.reset({ roster = {} }) -- roster not loaded yet
    local ns = wow.login(ADDON_DIR)
    eq(#entriesOf("character.self"), 0, "no character.self without the full name yet")
    eq(ns.Data.player().fullName, nil, "unknown, never guessed")
    ok(ns.Diag.versionText():find("角色全名 未取得", 1, true), "diag: " .. ns.Diag.versionText())
    wow.state.roster = surnameRoster()
    wow.fire("GUILD_ROSTER_UPDATE")
    wow.advance(2)
    local list = entriesOf("character.self")
    eq(#list, 1, "written once the roster is in")
    eq(list[1].uploader.fullName, "測試甲 長姓氏", "with the full name")
    eq(entriesOf("roster.snapshot")[1].uploader.fullName, "測試甲 長姓氏", "first snapshot has it too")
end)

test("D24 fullName: roster never loads -> written without fullName after the wait, no guess", function()
    wow.reset({ roster = {} })
    wow.login(ADDON_DIR)
    wow.advance(25)
    local list = entriesOf("character.self")
    eq(#list, 1, "still one per login")
    eq(list[1].uploader.fullName, nil, "field left out")
    eq(list[1].uploader.name, "測試甲", "name as before")
end)

test("D24 fullName: a plain space between the parts; -Realm dropped; nothing else changed", function()
    wow.reset({ secrets = { ["秘密 名字"] = true } })
    local ns = wow.loadAddon(ADDON_DIR)
    eq(ns.Data.cleanFullName("測試甲\194\160長姓氏"), "測試甲 長姓氏", "no-break space")
    eq(ns.Data.cleanFullName("測試甲\227\128\128長姓氏"), "測試甲 長姓氏", "ideographic space")
    eq(ns.Data.cleanFullName("測試甲 長姓氏-測試伺服器"), "測試甲 長姓氏", "no realm")
    eq(ns.Data.cleanFullName("甲  乙"), "甲  乙", "inner spaces kept as they are")
    eq(ns.Data.cleanFullName("秘密 名字"), "", "secret -> unknown")
end)

test("D24 fullName: remembered at the next login; upgrade writes fresh entries with new ids", function()
    wow.reset({ roster = surnameRoster() })
    wow.login(ADDON_DIR)
    -- What 0.9.7 left: entries without fullName (rejected by the site).
    for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do e.uploader.fullName = nil end
    local oldSelf = entriesOf("character.self")[1].id
    local oldSnap = entriesOf("roster.snapshot")[1].id
    local saved = wow.logout()
    wow.reset({ now = wow.state.now + 3600, roster = {} }) -- roster slow this time
    local ns = wow.loadAddon(ADDON_DIR, saved)
    wow.fire("PLAYER_LOGIN")
    wow.advance(6)
    local selfE = entriesOf("character.self")[1]
    ok(selfE.id ~= oldSelf, "new character.self id")
    eq(selfE.uploader.fullName, "測試甲 長姓氏", "remembered full name used at once")
    wow.state.roster = surnameRoster()
    wow.fire("GUILD_ROSTER_UPDATE")
    wow.advance(2)
    local snap = entriesOf("roster.snapshot")[1]
    ok(snap.id ~= oldSnap, "new roster.snapshot id")
    eq(snap.uploader.fullName, "測試甲 長姓氏", "snapshot has it")
    eq(#entriesOf("character.self"), 1, "one character.self")
    eq(#entriesOf("roster.snapshot"), 1, "one roster.snapshot")
end)

test("D24 fullName: a member without a GUID gets no subject fullName", function()
    wow.reset({ roster = surnameRoster() })
    local ns = wow.login(ADDON_DIR)
    eq(ns.Data.memberFullName(nil), nil, "no guid -> nil")
    eq(ns.Data.memberFullName("Player-0000-00000099"), nil, "unknown guid -> nil")
    eq(ns.Data.memberFullName("Player-0000-0000000C"), "測試丙 長姓氏", "known guid, no -Realm")
end)

test("fixture: generated sample is up to date and free of zone/online in the outbox", function()
    local db = buildFixture()
    local header = "-- 去識別化的 GreenFangToolkitDB（schemaVersion 2）樣本，給 GF Sync 測試用。\n"
        .. "-- 由 tests/addon/run.lua --fixture 產生，請勿手改。所有角色、GUID、伺服器名稱皆為虛構。\n"
        .. "-- 格式模仿遊戲客戶端寫入 WTF/Account/<帳號>/SavedVariables/GreenFangToolkit.lua 的樣子。\n"
        .. "-- GF Sync 只讀 sync 區塊。roster.snapshots 是遊戲內畫面用的資料，含 zone／online，不得上傳。\n"
    local text = header .. wow.serializeSV("GreenFangToolkitDB", db)
    eq(#db.sync.outbox, 4, "fixture outbox: 2 character.self + 1 roster.snapshot + 1 member.share")
    local keys = outboxKeys(db.sync.outbox)
    ok(not keys.zone and not keys.online, "fixture outbox has no zone/online (outside character.self location)")
    if WRITE_FIXTURE then
        local f = assert(io.open(FIXTURE, "wb"))
        f:write(text); f:close()
        realPrint("  wrote " .. FIXTURE)
    else
        local f = io.open(FIXTURE, "rb")
        ok(f, "fixture missing; run with --fixture")
        local current = f:read("*a"); f:close()
        current = current:gsub("\r\n", "\n")
        ok(current == text, "fixture out of date; run with --fixture")
    end
end)

-- GF-006-B: crafting and orders (tests/addon/orders_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/orders_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-006-B2: fixes from the 0.11.0 review (tests/addon/fixes_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/fixes_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-006-C: web orders (tests/addon/web_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/web_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-B: adventure and worker tickets (tests/addon/adventure_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/adventure_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-C: the game's own art with fallbacks (tests/addon/icons_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/icons_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-D: names next to the icons, one window at a time (tests/addon/labels_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/labels_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-E: bigger, no wrapping, ESC, the fee column, 下單 / 我的服務 (tests/addon/usability_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/usability_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint, shareLogin = shareLogin, shareFrom = shareFrom,
    rMsg = rMsg, leatherWindow = leatherWindow, PEER = PEER, A_PEER = A_PEER, A_THIRD = A_THIRD })
-- GF-002-F: no overlaps, click outside, past midnight, the year, my worker ticket, sizes (tests/addon/layout_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/layout_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-001-Q: guild management on the roster (tests/addon/guildadmin_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/guildadmin_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-G: two-line rows, editing, one 開始, glow, the game's group finder (tests/addon/adventure_ux_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/adventure_ux_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-H: slots, 定案, 成團 / 成行, the completion log, the calendar (tests/addon/adventure_slots_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/adventure_slots_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-B: batch 1 of the UI review, the roster click, the order test mode (tests/addon/uib_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uib_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-C: the owner's 0.14.0 fixes for the roster, guild, orders, recipes and framework (tests/addon/uic_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uic_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-I: §17 simpler states, step back, worker tickets close, the badge and its checklist, data-driven destinations (tests/addon/adventure_simplify_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/adventure_simplify_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-002-J: the owner's 0.14.0 fixes and spec §17.7 zones (tests/addon/adventure_fixes_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/adventure_fixes_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-D: the theme (game art only, no red buttons) (tests/addon/theme_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/theme_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-E: six entries, sub-tabs, 事務設定, item row and states (tests/addon/uie_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uie_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-PROBE: /gftk probe (tests/addon/probe_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/probe_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-013: the background event record (tests/addon/events_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/events_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-009: 綠皮調貨所, automatic collection and manual listings (tests/addon/supply_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/supply_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-010: role positioning and the personnel file (tests/addon/profile_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/profile_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-F: 職工名冊 icon, 人力盤點 row, 調貨所 header / + - / 收集組 / states, form close (tests/addon/uif_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uif_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-014: 業務通知, the bell and the local radar (tests/addon/notify_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/notify_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-012: 公會黑庫 phase 1, guild master, custodian list, scope (tests/addon/bank_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/bank_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-H: 調貨所 item finder, untradeable items, 刪除, top rows, coin icons (tests/addon/supply_h_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/supply_h_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-I: 調貨所 width / divider / ＋刊登, 臨時黑箱 top, roster card, item box input (tests/addon/uii_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uii_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-G: the 冒險業務 sample page: palette, icons, the slot editor in the form (tests/addon/uig_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uig_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-009-12: the 找物品 item catalog, LoadOnDemand (tests/addon/catalog_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/catalog_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-J: warm charcoal, the new icons, the worker ticket tooltip (tests/addon/uij_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uij_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-014-02: 職工單配對 notices and their switches (tests/addon/workermatch_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/workermatch_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-009-13: the dev-only GreenFangToolkit_Dev AddOn, /gftkdev catalogscan (tests/addon/catalog_dev_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/catalog_dev_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-014-03: joinable slots, recheck after combat, chat, windows on the screen, drafts (tests/addon/gf01403_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/gf01403_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-011: roster talents, the T share group, 天賦連結 (tests/addon/talents_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/talents_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-011-B: 天賦樹 (the game's talent window) and 製作 on accepted orders (tests/addon/gf011b_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/gf011b_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-008-B: the sleeping-bag guide, normal mode only, the world-map pin (tests/addon/sleepingbag_map_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/sleepingbag_map_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-008-C: a map for every step, the raid target star (tests/addon/gf008c_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/gf008c_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })
-- GF-UI-K: interface tidy-up: personnel file, 我的刊登, window titles, quest pickers (tests/addon/uik_tests.lua).
assert(loadfile(ROOT .. "/tests/addon/uik_tests.lua"))()({ test = test, eq = eq, ok = ok, wow = wow,
    ADDON_DIR = ADDON_DIR, deepEq = deepEq, realPrint = realPrint })

---------------------------------------------------------------------------

local passed = 0
for _, t in ipairs(tests) do
    local okRun, err = pcall(t.fn)
    if okRun then
        passed = passed + 1
        realPrint("ok   " .. t.name)
    else
        failures[#failures + 1] = t.name
        realPrint("FAIL " .. t.name .. "\n     " .. tostring(err))
    end
end
print = realPrint
realPrint(string.format("\n%d passed, %d failed", passed, #failures))
if #failures > 0 then
    if os and os.exit then os.exit(1) end
    error("tests failed")
end
GF_TEST_RESULT = { passed = passed, failed = #failures }
