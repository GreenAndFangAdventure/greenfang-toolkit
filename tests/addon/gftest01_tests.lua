-- GF-TEST-01: an old save loaded by the current code. Two saves, one per
-- old version, in the shape that version wrote (0.12.6, commit 094dbf7 and
-- 0.15.1, commit 29d409e): made by running that commit's own code in that
-- commit's own mock (log in, a service, two orders (one cancelled), a closed
-- order in the history, an adventure ticket, a worker ticket, a vendor price,
-- sort and page settings, log out; two orders.seen marks were set by hand in
-- the key form that code used, one of them for an order that is gone). Made-up characters and GUIDs only (the
-- mock's 測試甲…丁); no real save file was read. Offline only.
--
-- Checked: loads without an error; the fields the current code expects are
-- there; old data (orders, tickets, history, prices, settings, roster cache,
-- outbox) is neither dropped nor read as the wrong type; every page of the
-- main window draws; loading twice gives the same result. Edges: an empty
-- save, and a save whose sub-tables have the wrong type.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local deepEq = T.deepEq

    local ME = "Player-0000-0000000A"
    local A, B = "0000-0000000A", "0000-0000000B"
    local GK = "測試伺服器|綠皮與獠牙冒險事務所"
    local TICKET = "a7lt5.t5v55u1"
    local ORDER_OPEN, ORDER_CANCELLED = "g7lt5.t5v55u1", "g7lt5.t5v55u2"
    -- A little after the old session logged out (1763370215).
    local NOW = 1763370400

    local function copy(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = copy(x) end
        return o
    end

    ---------------------------------------------------------------------------
    -- The old saves (GreenFangToolkitDB as the old client wrote it)
    ---------------------------------------------------------------------------

    local OLD = {}
    OLD["0.12.6"] = {
        addonVersion = "0.12.6",
        adventure = { logoutAt = 1763370215, reopen = { }, seen = { } },
        ledger = {
            adventure = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    rec = {
                        ["0000-0000000A"] = {
                            T = {
                                h = "9lgds",
                                t = 1763370210,
                                v = "cr=t5v55u,ds=smg,id=a7lt5.t5v55u1,lr=d,lv=w,md=a,nt=慢慢打,rd=3,rh=1,rt=1,sa=t5v55u,src=g,st=o,tg=0,tm=n,ver=1",
                            },
                            W = {
                                h = "s7zy",
                                t = 1763370210,
                                v = "cr=t5v55u,ds=smg,ex=t5wztu,id=w,qs=501,rm=h,sa=t5v55u,sl=n,st=o",
                            },
                        },
                    },
                },
            },
            orders = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    rec = {
                        ["0000-0000000A"] = {
                            O = { h = "msar", t = 1763370211, v = "a=165,f165=dw" },
                            W = {
                                h = "8ekdu",
                                t = 1763370212,
                                v = "cf=0000-0000000B,cr=t5v55u,fe=0,id=g7lt5.t5v55u1,it=27i,q=2,rc=21w,sa=t5v55u,sk=4k,src=g,st=o,ver=1/cf=%2A,cr=t5v55u,fe=0,id=g7lt5.t5v55u2,it=27j,q=1,rc=21x,sa=t5v55u,sk=4k,src=g,st=x,ver=1",
                            },
                        },
                    },
                },
            },
            prices = { ["測試伺服器|綠皮與獠牙冒險事務所"] = { rec = { } } },
        },
        orders = {
            history = {
                ["Player-0000-0000000A"] = {
                    {
                        close = "done",
                        closeHow = "trade",
                        closedAt = 1763000000,
                        closedBy = "0000-0000000A",
                        crafter = "0000-0000000B",
                        customer = "0000-0000000A",
                        fee = 300,
                        id = "h-old1",
                        item = 2862,
                        mats = "2770*4",
                        qty = 1,
                        recipe = 2660,
                        skill = 164,
                    },
                },
            },
            inbox = { noInbox = "no-loader" },
            reagents = { },
            seen = { ["g7lt5.t5v55u1|new"] = true, ["gone.order|new"] = true },
            trades = { },
            unsure = { },
        },
        peers = { },
        prices = { ah = { }, reagents = { }, scan = { }, vendor = { [2770] = "15.1763000000" } },
        roster = {
            lastKey = "測試伺服器|綠皮與獠牙冒險事務所",
            snapshots = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    capturedAt = 1763370121,
                    capturedAtLocal = "2025-11-17 17:02:01",
                    capturedAtUTC = "2025-11-17T09:02:01Z",
                    faction = "Horde",
                    guild = "綠皮與獠牙冒險事務所",
                    members = {
                        {
                            class = "獵人",
                            classToken = "HUNTER",
                            guid = "Player-0000-0000000D",
                            guildRank = "新進",
                            level = 12,
                            name = "測試丁-測試伺服器",
                            online = false,
                            professionSource = "missing",
                            professions = { },
                            race = "食人妖",
                            raceSource = "guid",
                            rankIndex = 3,
                            zone = "杜洛塔",
                        },
                        {
                            class = "法師",
                            classToken = "MAGE",
                            guid = "Player-0000-0000000C",
                            guildRank = "會員",
                            level = 25,
                            name = "測試丙-測試伺服器",
                            online = false,
                            professionSource = "guild",
                            professions = { "裁縫", "附魔" },
                            race = "不死族",
                            raceID = 5,
                            raceSource = "guild",
                            rankIndex = 2,
                            zone = "幽暗城",
                        },
                        {
                            class = "戰士",
                            classToken = "WARRIOR",
                            guid = "Player-0000-0000000B",
                            guildRank = "會長",
                            level = 60,
                            name = "測試乙-測試伺服器",
                            online = true,
                            professionSource = "guild",
                            professions = { "鍛造", "採礦" },
                            race = "獸人",
                            raceID = 2,
                            raceSource = "guild",
                            rankIndex = 0,
                            zone = "奧格瑪",
                        },
                        {
                            class = "德魯伊",
                            classToken = "DRUID",
                            guid = "Player-0000-0000000A",
                            guildRank = "會員",
                            level = 32,
                            name = "測試甲-測試伺服器",
                            online = true,
                            professionSource = "self",
                            professions = { "製皮", "剝皮" },
                            race = "牛頭人",
                            raceID = 6,
                            raceSource = "self",
                            rankIndex = 2,
                            zone = "雷霆崖",
                        },
                    },
                    online = 2,
                    realm = "測試伺服器",
                    total = 4,
                },
            },
        },
        schema = "gf.toolkit",
        schemaVersion = 2,
        settings = {
            fullNames = { ["Player-0000-0000000A"] = "測試甲" },
            lastModule = "roster",
            minimapAngle = 215,
            minimapLayoutVersion = 2,
            modules = { sleepingbag = { characters = { ["Player-0000-0000000A"] = { step = 3 } } } },
            realms = { ["Player-0000-0000000A"] = "測試伺服器" },
            sortAscending = false,
            sortKey = "level",
        },
        share = {
            guilds = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    gone = { },
                    idsSent = { },
                    named = { },
                    queued = { },
                    rec = {
                        ["0000-0000000A"] = {
                            B = {
                                fromAuthor = true,
                                h = "4f43w",
                                heardAt = 1763370021,
                                t = 1763370021,
                                v = "32.DRUID",
                                via = "0000-0000000A",
                            },
                            P = {
                                fromAuthor = true,
                                h = "g0rc",
                                heardAt = 1763370021,
                                t = 1763370021,
                                v = "165,151,225/393,160,225/356,75,150/185,60,150",
                                via = "0000-0000000A",
                            },
                            Z = {
                                fromAuthor = true,
                                h = "21on6",
                                heardAt = 1763370021,
                                t = 1763370021,
                                v = "雷霆崖/長者高地",
                                via = "0000-0000000A",
                            },
                        },
                    },
                    shareRefreshAt = 1763370215,
                    tomb = { },
                },
            },
            seenIDs = { },
            v = 1,
        },
        sync = {
            enabled = true,
            noticeShown = true,
            noticeVersion = 4,
            outbox = {
                {
                    capturedAt = 1763370121,
                    capturedAtServer = 1763370121,
                    game = { interface = 16001, locale = "zhTW", realm = "測試伺服器", world = "forever" },
                    id = "Player-0000-0000000A:1763370121:roster.snapshot",
                    kind = "roster.snapshot",
                    payload = {
                        members = {
                            {
                                classToken = "HUNTER",
                                guid = "Player-0000-0000000D",
                                guildRank = "新進",
                                level = 12,
                                name = "測試丁-測試伺服器",
                                professionSource = "missing",
                                professions = { },
                                race = "食人妖",
                            },
                            {
                                classToken = "MAGE",
                                guid = "Player-0000-0000000C",
                                guildRank = "會員",
                                level = 25,
                                name = "測試丙-測試伺服器",
                                professionSource = "guild",
                                professions = { "裁縫", "附魔" },
                                race = "不死族",
                                raceID = 5,
                            },
                            {
                                classToken = "WARRIOR",
                                guid = "Player-0000-0000000B",
                                guildRank = "會長",
                                level = 60,
                                name = "測試乙-測試伺服器",
                                professionSource = "guild",
                                professions = { "鍛造", "採礦" },
                                race = "獸人",
                                raceID = 2,
                            },
                            {
                                classToken = "DRUID",
                                guid = "Player-0000-0000000A",
                                guildRank = "會員",
                                level = 32,
                                name = "測試甲-測試伺服器",
                                professionSource = "self",
                                professions = { "製皮", "剝皮" },
                                race = "牛頭人",
                                raceID = 6,
                            },
                        },
                        total = 4,
                    },
                    uploader = {
                        faction = "Horde",
                        fullName = "測試甲",
                        guid = "Player-0000-0000000A",
                        guild = "綠皮與獠牙冒險事務所",
                        guildRank = "會員",
                        name = "測試甲",
                        realm = "測試伺服器",
                    },
                },
                {
                    capturedAt = 1763370215,
                    capturedAtServer = 1763370215,
                    game = { interface = 16001, locale = "zhTW", realm = "測試伺服器", world = "forever" },
                    id = "Player-0000-0000000A:1763370215:character.self",
                    kind = "character.self",
                    payload = {
                        adventure = {
                            tickets = {
                                recordedAt = 1763370210,
                                value = {
                                    ["a7lt5.t5v55u1"] = {
                                        admit = "direct",
                                        created = 1763370210,
                                        dungeon = "smg",
                                        note = "慢慢打",
                                        slots = { dps = 3, healer = 1, tank = 1 },
                                        src = "g",
                                        status = "open",
                                        statusAt = 1763370210,
                                        time = { mode = "now" },
                                        ver = 1,
                                    },
                                },
                            },
                            worker = {
                                recordedAt = 1763370210,
                                value = {
                                    allQuests = false,
                                    dungeons = { "smg" },
                                    expires = 1763456610,
                                    main = "healer",
                                    quests = { 501 },
                                    times = { { mode = "now" } },
                                },
                            },
                        },
                        class = "德魯伊",
                        classToken = "DRUID",
                        crafting = {
                            orders = {
                                ["g7lt5.t5v55u1"] = {
                                    w = {
                                        crafter = "Player-0000-0000000B",
                                        created = 1763370210,
                                        cst = "open",
                                        customer = "Player-0000-0000000A",
                                        fee = 0,
                                        got = 0,
                                        item = 2862,
                                        qty = 2,
                                        recipe = 2660,
                                        recordedAt = 1763370212,
                                        src = "g",
                                        ver = 1,
                                    },
                                },
                                ["g7lt5.t5v55u2"] = {
                                    w = {
                                        close = "cancel",
                                        closeHow = "manual",
                                        closedAt = 1763370210,
                                        closedBy = "customer",
                                        crafter = "*",
                                        created = 1763370210,
                                        cst = "cancel",
                                        customer = "Player-0000-0000000A",
                                        fee = 0,
                                        got = 0,
                                        item = 2863,
                                        qty = 1,
                                        recipe = 2661,
                                        recordedAt = 1763370212,
                                        src = "g",
                                        ver = 1,
                                    },
                                },
                            },
                            services = { recordedAt = 1763370211, value = { ["165"] = { active = true, fee = 500 } } },
                        },
                        level = 32,
                        location = { subZone = "長者高地", zone = "雷霆崖" },
                        professions = {
                            { max = 225, name = "製皮", rank = 151, skillLineID = 165 },
                            { max = 225, name = "剝皮", rank = 160, skillLineID = 393 },
                            { max = 150, name = "釣魚", rank = 75, skillLineID = 356 },
                            { max = 150, name = "烹飪", rank = 60, skillLineID = 185 },
                        },
                        race = "牛頭人",
                        raceID = 6,
                    },
                    uploader = {
                        faction = "Horde",
                        fullName = "測試甲",
                        guid = "Player-0000-0000000A",
                        guild = "綠皮與獠牙冒險事務所",
                        guildRank = "會員",
                        name = "測試甲",
                        realm = "測試伺服器",
                    },
                },
            },
        },
    }
    OLD["0.15.1"] = {
        addonVersion = "0.15.1",
        adventure = { deleted = { }, log = { ["0000-0000000A"] = { } }, logoutAt = 1763370215, reopen = { }, seen = { } },
        ledger = {
            adventure = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    rec = {
                        ["0000-0000000A"] = {
                            T = {
                                h = "6083z",
                                t = 1763370210,
                                v = "cr=t5v55u,ds=smg,id=a7lt5.t5v55u1,lr=d,lv=w,md=a,nt=慢慢打,rd=3,rh=1,rt=1,sa=t5v55u,src=g,st=o,tg=0,tm=n,ts=1n-t5v55u--,ver=1",
                            },
                            W = {
                                h = "6v0zl",
                                t = 1763370210,
                                v = "cr=t5v55u,ds=smg,ex=t5wztu,id=w,qs=501,rm=h,sa=t5v55u,sl=n,st=o,sv=1n-t5v55u--",
                            },
                        },
                    },
                },
            },
            orders = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    rec = {
                        ["0000-0000000A"] = {
                            O = { h = "msar", t = 1763370211, v = "a=165,f165=dw" },
                            W = {
                                h = "8ekdu",
                                t = 1763370212,
                                v = "cf=0000-0000000B,cr=t5v55u,fe=0,id=g7lt5.t5v55u1,it=27i,q=2,rc=21w,sa=t5v55u,sk=4k,src=g,st=o,ver=1/cf=%2A,cr=t5v55u,fe=0,id=g7lt5.t5v55u2,it=27j,q=1,rc=21x,sa=t5v55u,sk=4k,src=g,st=x,ver=1",
                            },
                        },
                    },
                },
            },
            prices = { ["測試伺服器|綠皮與獠牙冒險事務所"] = { rec = { } } },
        },
        orders = {
            history = {
                ["Player-0000-0000000A"] = {
                    {
                        close = "done",
                        closeHow = "trade",
                        closedAt = 1763000000,
                        closedBy = "0000-0000000A",
                        crafter = "0000-0000000B",
                        customer = "0000-0000000A",
                        fee = 300,
                        id = "h-old1",
                        item = 2862,
                        mats = "2770*4",
                        qty = 1,
                        recipe = 2660,
                        skill = 164,
                    },
                },
            },
            inbox = { noInbox = "no-loader" },
            reagents = { },
            seen = { ["g7lt5.t5v55u1|new"] = true, ["gone.order|new"] = true },
            trades = { },
            unsure = { },
        },
        peers = { },
        prices = { ah = { }, reagents = { }, scan = { }, vendor = { [2770] = "15.1763000000" } },
        roster = {
            lastKey = "測試伺服器|綠皮與獠牙冒險事務所",
            snapshots = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    capturedAt = 1763370121,
                    capturedAtLocal = "2025-11-17 17:02:01",
                    capturedAtUTC = "2025-11-17T09:02:01Z",
                    faction = "Horde",
                    guild = "綠皮與獠牙冒險事務所",
                    members = {
                        {
                            class = "獵人",
                            classToken = "HUNTER",
                            guid = "Player-0000-0000000D",
                            guildRank = "新進",
                            level = 12,
                            name = "測試丁-測試伺服器",
                            online = false,
                            professionSource = "missing",
                            professions = { },
                            race = "食人妖",
                            raceSource = "guid",
                            rankIndex = 3,
                            zone = "杜洛塔",
                        },
                        {
                            class = "法師",
                            classToken = "MAGE",
                            guid = "Player-0000-0000000C",
                            guildRank = "會員",
                            level = 25,
                            name = "測試丙-測試伺服器",
                            online = false,
                            professionSource = "guild",
                            professions = { "裁縫", "附魔" },
                            race = "不死族",
                            raceID = 5,
                            raceSource = "guild",
                            rankIndex = 2,
                            zone = "幽暗城",
                        },
                        {
                            class = "戰士",
                            classToken = "WARRIOR",
                            guid = "Player-0000-0000000B",
                            guildRank = "會長",
                            level = 60,
                            name = "測試乙-測試伺服器",
                            online = true,
                            professionSource = "guild",
                            professions = { "鍛造", "採礦" },
                            race = "獸人",
                            raceID = 2,
                            raceSource = "guild",
                            rankIndex = 0,
                            zone = "奧格瑪",
                        },
                        {
                            class = "德魯伊",
                            classToken = "DRUID",
                            guid = "Player-0000-0000000A",
                            guildRank = "會員",
                            level = 32,
                            name = "測試甲-測試伺服器",
                            online = true,
                            professionSource = "self",
                            professions = { "製皮", "剝皮" },
                            race = "牛頭人",
                            raceID = 6,
                            raceSource = "self",
                            rankIndex = 2,
                            zone = "雷霆崖",
                        },
                    },
                    online = 2,
                    realm = "測試伺服器",
                    total = 4,
                },
            },
        },
        schema = "gf.toolkit",
        schemaVersion = 2,
        settings = {
            fullNames = { ["Player-0000-0000000A"] = "測試甲" },
            lastModule = "roster",
            minimapAngle = 215,
            minimapLayoutVersion = 2,
            modules = { sleepingbag = { characters = { ["Player-0000-0000000A"] = { step = 3 } } } },
            realms = { ["Player-0000-0000000A"] = "測試伺服器" },
            sortAscending = false,
            sortKey = "level",
        },
        share = {
            guilds = {
                ["測試伺服器|綠皮與獠牙冒險事務所"] = {
                    gone = { },
                    idsSent = { },
                    named = { },
                    queued = { },
                    rec = {
                        ["0000-0000000A"] = {
                            B = {
                                fromAuthor = true,
                                h = "4f43w",
                                heardAt = 1763370021,
                                t = 1763370021,
                                v = "32.DRUID",
                                via = "0000-0000000A",
                            },
                            P = {
                                fromAuthor = true,
                                h = "g0rc",
                                heardAt = 1763370021,
                                t = 1763370021,
                                v = "165,151,225/393,160,225/356,75,150/185,60,150",
                                via = "0000-0000000A",
                            },
                            Z = {
                                fromAuthor = true,
                                h = "21on6",
                                heardAt = 1763370021,
                                t = 1763370021,
                                v = "雷霆崖/長者高地",
                                via = "0000-0000000A",
                            },
                        },
                    },
                    shareRefreshAt = 1763370215,
                    tomb = { },
                },
            },
            seenIDs = { },
            v = 1,
        },
        sync = {
            enabled = true,
            noticeShown = true,
            noticeVersion = 4,
            outbox = {
                {
                    capturedAt = 1763370121,
                    capturedAtServer = 1763370121,
                    game = { interface = 16001, locale = "zhTW", realm = "測試伺服器", world = "forever" },
                    id = "Player-0000-0000000A:1763370121:roster.snapshot",
                    kind = "roster.snapshot",
                    payload = {
                        members = {
                            {
                                classToken = "HUNTER",
                                guid = "Player-0000-0000000D",
                                guildRank = "新進",
                                level = 12,
                                name = "測試丁-測試伺服器",
                                professionSource = "missing",
                                professions = { },
                                race = "食人妖",
                            },
                            {
                                classToken = "MAGE",
                                guid = "Player-0000-0000000C",
                                guildRank = "會員",
                                level = 25,
                                name = "測試丙-測試伺服器",
                                professionSource = "guild",
                                professions = { "裁縫", "附魔" },
                                race = "不死族",
                                raceID = 5,
                            },
                            {
                                classToken = "WARRIOR",
                                guid = "Player-0000-0000000B",
                                guildRank = "會長",
                                level = 60,
                                name = "測試乙-測試伺服器",
                                professionSource = "guild",
                                professions = { "鍛造", "採礦" },
                                race = "獸人",
                                raceID = 2,
                            },
                            {
                                classToken = "DRUID",
                                guid = "Player-0000-0000000A",
                                guildRank = "會員",
                                level = 32,
                                name = "測試甲-測試伺服器",
                                professionSource = "self",
                                professions = { "製皮", "剝皮" },
                                race = "牛頭人",
                                raceID = 6,
                            },
                        },
                        total = 4,
                    },
                    uploader = {
                        faction = "Horde",
                        fullName = "測試甲",
                        guid = "Player-0000-0000000A",
                        guild = "綠皮與獠牙冒險事務所",
                        guildRank = "會員",
                        name = "測試甲",
                        realm = "測試伺服器",
                    },
                },
                {
                    capturedAt = 1763370215,
                    capturedAtServer = 1763370215,
                    game = { interface = 16001, locale = "zhTW", realm = "測試伺服器", world = "forever" },
                    id = "Player-0000-0000000A:1763370215:character.self",
                    kind = "character.self",
                    payload = {
                        adventure = {
                            tickets = {
                                recordedAt = 1763370210,
                                value = {
                                    ["a7lt5.t5v55u1"] = {
                                        admit = "direct",
                                        created = 1763370210,
                                        dungeon = "smg",
                                        note = "慢慢打",
                                        phase = "open",
                                        slots = { dps = 3, healer = 1, tank = 1 },
                                        src = "g",
                                        status = "open",
                                        statusAt = 1763370210,
                                        time = { mode = "now" },
                                        times = { { from = 1763370210, id = 1, mode = "now", to = 1763372010 } },
                                        ver = 1,
                                    },
                                },
                            },
                            worker = {
                                recordedAt = 1763370210,
                                value = {
                                    allQuests = false,
                                    dungeons = { "smg" },
                                    expires = 1763456610,
                                    main = "healer",
                                    quests = { 501 },
                                    times = { { from = 1763370210, id = 1, mode = "now" } },
                                },
                            },
                        },
                        class = "德魯伊",
                        classToken = "DRUID",
                        crafting = {
                            orders = {
                                ["g7lt5.t5v55u1"] = {
                                    w = {
                                        crafter = "Player-0000-0000000B",
                                        created = 1763370210,
                                        cst = "open",
                                        customer = "Player-0000-0000000A",
                                        fee = 0,
                                        got = 0,
                                        item = 2862,
                                        qty = 2,
                                        recipe = 2660,
                                        recordedAt = 1763370212,
                                        src = "g",
                                        ver = 1,
                                    },
                                },
                                ["g7lt5.t5v55u2"] = {
                                    w = {
                                        close = "cancel",
                                        closeHow = "manual",
                                        closedAt = 1763370210,
                                        closedBy = "customer",
                                        crafter = "*",
                                        created = 1763370210,
                                        cst = "cancel",
                                        customer = "Player-0000-0000000A",
                                        fee = 0,
                                        got = 0,
                                        item = 2863,
                                        qty = 1,
                                        recipe = 2661,
                                        recordedAt = 1763370212,
                                        src = "g",
                                        ver = 1,
                                    },
                                },
                            },
                            services = { recordedAt = 1763370211, value = { ["165"] = { active = true, fee = 500 } } },
                        },
                        level = 32,
                        location = { subZone = "長者高地", zone = "雷霆崖" },
                        professions = {
                            { max = 225, name = "製皮", rank = 151, skillLineID = 165 },
                            { max = 225, name = "剝皮", rank = 160, skillLineID = 393 },
                            { max = 150, name = "釣魚", rank = 75, skillLineID = 356 },
                            { max = 150, name = "烹飪", rank = 60, skillLineID = 185 },
                        },
                        race = "牛頭人",
                        raceID = 6,
                    },
                    uploader = {
                        faction = "Horde",
                        fullName = "測試甲",
                        guid = "Player-0000-0000000A",
                        guild = "綠皮與獠牙冒險事務所",
                        guildRank = "會員",
                        name = "測試甲",
                        realm = "測試伺服器",
                    },
                },
            },
        },
    }
    local VERSIONS = { "0.12.6", "0.15.1" }

    ---------------------------------------------------------------------------
    -- Helpers
    ---------------------------------------------------------------------------

    -- Load (ADDON_LOADED only), the same as the client at /reload before login.
    local function load(db)
        wow.reset({ now = NOW })
        return wow.loadAddon(ADDON_DIR, { GreenFangToolkitDB = db })
    end
    -- Full login: PLAYER_LOGIN and every startup step (share, orders, adventure, prices).
    local function login(db)
        local ns = load(db)
        wow.fire("PLAYER_LOGIN")
        wow.advance(200)
        return ns
    end
    local function tocVersion()
        local f = assert(io.open(ADDON_DIR .. "/GreenFangToolkit.toc", "r"))
        local text = f:read("*a"); f:close()
        return text:match("## Version:%s*([^\r\n]+)")
    end
    -- Every page the current character may open, drawn and redrawn.
    local function drawEveryPage(ns)
        local F = ns.Framework
        local ids = {}
        for _, def in ipairs(F.availableModules()) do ids[#ids + 1] = def.id end
        ok(#ids >= 5, "pages available: " .. #ids)
        for _, id in ipairs(ids) do
            local okOpen, err = pcall(F.open, id)
            ok(okOpen, "page " .. id .. " opens: " .. tostring(err))
            eq(F.current(), id, "page " .. id .. " is the current one")
            local def = F.get(id)
            if def and type(def.refresh) == "function" then
                local okR, errR = pcall(def.refresh)
                ok(okR, "page " .. id .. " redraws: " .. tostring(errR))
            end
        end
        wow.advance(1)
        return ids
    end
    -- A table, or fail saying where.
    local function tbl(v, what) ok(type(v) == "table", what .. " is a table, got " .. type(v)); return v end

    -- Init.lua runs these inside pcall, so an error there never reaches the
    -- test on its own. Here they run bare, each named on failure.
    local function exercise(ns)
        local O, Adv = ns.Orders, ns.Adventure
        local me = ns.Share.selfAuthor and ns.Share.selfAuthor() or A
        local steps = {
            { "Orders.maintain", function() O.maintain() end },
            { "Orders.rowsFor", function() O.rowsFor(me, ME) end },
            { "Orders.attentionCount", function() O.attentionCount() end },
            { "Orders.markSeen", function() O.markSeen() end },
            { "Orders.closedCounts", function() O.closedCounts() end },
            { "WebOrders.readInbox", function() ns.WebOrders.readInbox() end },
            { "Adventure.onLogin", function() Adv.onLogin() end },
            { "Adventure.maintain", function() Adv.maintain() end },
            { "Adventure.rowsFor", function() Adv.rowsFor() end },
            { "Adventure.attentionCount", function() Adv.attentionCount() end },
            { "Adventure.myLog", function() Adv.myLog() end },
            { "AdventureUI.updateBadge", function() ns.AdventureUI.updateBadge() end },
            { "OrdersUI.updateBadge", function() ns.OrdersUI.updateBadge() end },
            -- An order closing: Orders.toHistory writes the local history.
            { "Orders.toHistory", function()
                O.toHistory({ id = "gftest01-close", recipe = 2660, item = 2862, skill = 164, qty = 1,
                    customer = A, crafter = B, close = "done", closedBy = A, closeHow = "trade",
                    closedAt = NOW, fee = 0, mats = {} })
            end },
            { "Adventure.onLogout", function() Adv.onLogout() end },
        }
        local failed = {}
        for _, s in ipairs(steps) do
            local okS, err = pcall(s[2])
            if not okS then failed[#failed + 1] = s[1] .. ": " .. tostring(err) end
        end
        ok(#failed == 0, "steps that raised an error:\n       " .. table.concat(failed, "\n       "))
    end

    ---------------------------------------------------------------------------
    -- Per old version
    ---------------------------------------------------------------------------

    for _, V in ipairs(VERSIONS) do
        local P = "GF-TEST-01 " .. V .. " "

        test(P .. "the old save is the shape that version wrote", function()
            local db = OLD[V]
            eq(db.addonVersion, V, "addonVersion")
            eq(db.schemaVersion, 2, "schemaVersion")
            ok(db.events == nil and db.supply == nil and db.notify == nil and db.profile == nil
                and db.bank == nil and db.probe == nil, "no table of a later version")
            eq(type(db.adventure.log), V == "0.15.1" and "table" or "nil", "adventure.log (0.13.0 on)")
        end)

        test(P .. "loads and logs in without an error; schema and version are the current ones", function()
            local ns = login(copy(OLD[V]))
            local db = GreenFangToolkitDB
            ok(ns.db == db, "ns.db is the saved table")
            eq(db.schema, "gf.toolkit", "schema")
            eq(db.schemaVersion, 2, "schemaVersion")
            eq(db.addonVersion, tocVersion(), "addonVersion is the current TOC version")
            eq(db.sync.enabled, true, "sync.enabled")
            eq(type(db.sync.noticeShown), "boolean", "noticeShown")
            tbl(db.sync.outbox, "sync.outbox")
            eq(db.settings.minimapLayoutVersion, 2, "minimapLayoutVersion")
            eq(db.settings.minimapAngle, 215, "minimapAngle kept")
            ok(db.migration == nil, "no GFGuildRosterDB, so no migration record")
        end)

        test(P .. "old data is kept with the right types", function()
            local ns = login(copy(OLD[V]))
            local db = GreenFangToolkitDB
            -- settings
            eq(db.settings.sortKey, "level", "sortKey")
            eq(db.settings.sortAscending, false, "sortAscending")
            eq(ns.UI.sortKey, "level", "UI uses the saved sort key")
            eq(ns.UI.sortAscending, false, "UI uses the saved order")
            eq(db.settings.fullNames[ME], "測試甲", "fullNames")
            eq(db.settings.realms[ME], "測試伺服器", "realms")
            eq(db.settings.modules.sleepingbag.characters[ME].step, 3, "a module's per-character state")
            -- orders: local history, seen marks, the ledger, the views
            local O = tbl(db.orders, "orders")
            for _, k in ipairs({ "history", "seen", "trades", "unsure", "reagents" }) do tbl(O[k], "orders." .. k) end
            local h = tbl(O.history[ME], "orders.history[me]")
            eq(#h, 1, "one closed order in the history")
            eq(h[1].id, "h-old1", "history id")
            eq(h[1].mats, "2770*4", "history mats stay an encoded string")
            eq(h[1].fee, 300, "history fee is a number")
            eq(O.seen[ORDER_OPEN .. "|new"], true, "the seen mark of a live order is kept")
            eq(O.seen["gone.order|new"], nil, "the seen mark of an order that is gone is pruned (as before)")
            local rec = db.ledger.orders[GK].rec[A]
            ok(type(rec.W) == "table" and type(rec.W.v) == "string", "my order record")
            ok(type(rec.O) == "table" and rec.O.v == "a=165,f165=dw", "my service record")
            local open = ns.Orders.get(ORDER_OPEN)
            ok(open, "the open order is read back")
            eq(open.qty, 2, "qty")
            eq(open.item, 2862, "item")
            eq(open.crafter, B, "crafter")
            ok(open.state ~= "cancel" and open.state ~= "done", "still open: " .. tostring(open.state))
            local cancelled = ns.Orders.get(ORDER_CANCELLED)
            if cancelled then eq(cancelled.state, "cancel", "the cancelled one stays cancelled") end
            -- adventure: the ticket and the worker ticket
            local adv = tbl(db.adventure, "adventure")
            for _, k in ipairs({ "seen", "reopen", "log", "deleted" }) do tbl(adv[k], "adventure." .. k) end
            local t = ns.Adventure.get(TICKET)
            ok(t, "the adventure ticket is read back")
            eq(t.dungeon, "smg", "destination")
            eq(t.note, "慢慢打", "note")
            local w = ns.Adventure.myWorker()
            ok(w, "the worker ticket is read back")
            ok(w.dungeons and (w.dungeons.smg or w.dungeons[1] == "smg"), "worker destination")
            -- prices
            eq(db.prices.vendor[2770], "15.1763000000", "vendor price")
            for _, k in ipairs({ "vendor", "ah", "reagents", "scan" }) do tbl(db.prices[k], "prices." .. k) end
            -- roster cache and share
            local snap = tbl(db.roster.snapshots[GK], "roster snapshot")
            eq(#snap.members, 4, "roster members")
            eq(db.roster.lastKey, GK, "lastKey")
            tbl(db.share.guilds[GK].rec[A], "my share records")
            -- outbox: the old entries are not dropped (GF Sync reads them)
            local kinds = {}
            for _, e in ipairs(db.sync.outbox) do kinds[e.kind] = (kinds[e.kind] or 0) + 1 end
            ok((kinds["roster.snapshot"] or 0) >= 1, "old roster.snapshot kept")
            ok((kinds["character.self"] or 0) >= 1, "old character.self kept")
        end)

        test(P .. "every page of the main window draws", function()
            local ns = login(copy(OLD[V]))
            local ids = drawEveryPage(ns)
            ok(#ids > 0, "pages drawn")
            local okT = pcall(ns.Framework.toggle)
            ok(okT, "closing the window")
        end)

        test(P .. "the startup and upkeep steps Init runs inside pcall run bare without an error", function()
            local ns = login(copy(OLD[V]))
            exercise(ns)
            local h = GreenFangToolkitDB.orders.history[ME]
            eq(#h, 2, "the new closed order joins the old history")
            eq(h[1].id, "gftest01-close", "newest first")
            eq(h[2].id, "h-old1", "the old one is still there")
        end)

        test(P .. "loading twice gives the same result", function()
            -- ADDON_LOADED (initDB, migration, registering, settings) is idempotent.
            load(copy(OLD[V]))
            local once = wow.serializeSV("GreenFangToolkitDB", GreenFangToolkitDB)
            load(copy(GreenFangToolkitDB))
            local twice = wow.serializeSV("GreenFangToolkitDB", GreenFangToolkitDB)
            ok(once == twice, "same table after loading the loaded save again")
            -- A full session and log out, twice: the old data comes out the same.
            local function session(db)
                login(db)
                return wow.logout().GreenFangToolkitDB
            end
            local s1 = copy(session(copy(OLD[V])))
            local s2 = session(copy(s1))
            for _, path in ipairs({ { "settings" }, { "orders", "history" }, { "orders", "seen" },
                { "prices", "vendor" }, { "ledger", "orders", GK, "rec", A }, { "roster", "lastKey" } }) do
                local a, b = s1, s2
                for _, k in ipairs(path) do a = type(a) == "table" and a[k] or nil; b = type(b) == "table" and b[k] or nil end
                ok(a ~= nil, table.concat(path, ".") .. " present")
                ok(deepEq(a, b), table.concat(path, ".") .. " the same after a second session")
            end
            local va = s1.ledger.adventure[GK].rec[A]
            local vb = s2.ledger.adventure[GK].rec[A]
            eq(vb.T and vb.T.v, va.T and va.T.v, "adventure ticket record the same")
            eq(vb.W and vb.W.v, va.W and va.W.v, "worker ticket record the same")
        end)
    end

    ---------------------------------------------------------------------------
    -- Edges
    ---------------------------------------------------------------------------

    test("GF-TEST-01 edge: an empty save loads, logs in and draws every page", function()
        local ns = login({})
        local db = GreenFangToolkitDB
        eq(db.schema, "gf.toolkit", "schema")
        eq(db.addonVersion, tocVersion(), "addonVersion")
        tbl(db.settings, "settings"); tbl(db.roster.snapshots, "roster.snapshots"); tbl(db.sync.outbox, "sync.outbox")
        drawEveryPage(ns)
        exercise(ns)
        wow.logout()
    end)

    test("GF-TEST-01 edge: a save that is not a table (a string) starts fresh", function()
        local ns = login("壞掉的存檔")
        eq(type(GreenFangToolkitDB), "table", "replaced by a table")
        drawEveryPage(ns)
        exercise(ns)
    end)

    -- One sub-table at a time has the wrong type (a string where a table belongs).
    -- Each must load, log in, draw every page and log out without an error, and
    -- the other old data must still be there.
    local BAD = {
        { "settings" }, { "settings", "modules" }, { "settings", "modules", "sleepingbag" },
        { "settings", "fullNames" }, { "roster" }, { "roster", "snapshots" }, { "sync" },
        { "sync", "outbox" }, { "orders" }, { "orders", "history" }, { "orders", "history", ME },
        { "orders", "seen" }, { "adventure" }, { "adventure", "log" }, { "prices" },
        { "prices", "vendor" }, { "ledger" }, { "ledger", "orders" }, { "ledger", "orders", GK },
        { "share" }, { "share", "guilds" }, { "peers" },
        -- one level deeper
        { "settings", "modules", "sleepingbag", "characters" }, { "settings", "realms" },
        { "roster", "snapshots", GK }, { "roster", "snapshots", GK, "members" }, { "sync", "outbox", 1 },
        { "orders", "trades" }, { "orders", "unsure" }, { "orders", "reagents" }, { "orders", "inbox" },
        { "adventure", "seen" }, { "adventure", "reopen" }, { "adventure", "deleted" }, { "adventure", "log", A },
        { "prices", "ah" }, { "prices", "scan" }, { "prices", "reagents" },
        { "ledger", "adventure", GK, "rec" }, { "ledger", "adventure", GK, "rec", A },
        { "ledger", "orders", GK, "rec", A, "W" }, { "share", "seenIDs" }, { "share", "guilds", GK },
        { "share", "guilds", GK, "rec" }, { "share", "guilds", GK, "rec", A },
    }
    -- GF-FIX-H: the five cases GF-TEST-01 found (K1-K5) and the same kind of
    -- damage one level deeper in the same tables. The broken entry is dropped
    -- (or replaced by an empty table); everything else stays.
    for _, extra in ipairs({
        { "ledger", "orders", GK, "rec", A, "O", "t" }, { "ledger", "adventure", GK, "rec", A, "T" },
        { "share", "guilds", GK, "rec", A, "B" }, { "share", "guilds", GK, "rec", A, "P", "t" },
        { "share", "guilds", GK, "tomb", A }, { "share", "guilds", GK, "tomb" },
        { "share", "guilds", GK, "queued", A }, { "share", "guilds", GK, "idsSent", A },
        { "share", "guilds", GK, "gone", A },
        { "orders", "history", ME, 1 }, { "orders", "unsure", ORDER_OPEN },
    }) do BAD[#BAD + 1] = extra end
    -- What must still be there (or be gone) after each case, by path.
    local AFTER = {
        -- K1: the closed order still reaches the history.
        [table.concat({ "orders", "history", ME }, ".")] = function(now)
            tbl(now.orders.history[ME], "history list replaced by a table")
            eq(now.orders.history[ME][1] and now.orders.history[ME][1].id, "gftest01-close", "closed order in history")
        end,
        [table.concat({ "orders", "history", ME, 1 }, ".")] = function(now)
            eq(now.orders.history[ME][1] and now.orders.history[ME][1].id, "gftest01-close", "closed order in history")
            for _, x in ipairs(now.orders.history[ME]) do tbl(x, "history entry") end
        end,
        -- K2: the scan writes a whole snapshot again.
        [table.concat({ "roster", "snapshots", GK, "members" }, ".")] = function(now)
            tbl(now.roster.snapshots[GK].members, "members replaced by a table")
        end,
        -- K3: the author's adventure records are dropped, the order records stay.
        [table.concat({ "ledger", "adventure", GK, "rec", A }, ".")] = function(now)
            tbl(now.ledger.orders[GK].rec[A].W, "other data kept: order records")
        end,
        -- K4: the one record is dropped, the author's other record stays.
        [table.concat({ "ledger", "orders", GK, "rec", A, "W" }, ".")] = function(now)
            eq(now.ledger.orders[GK].rec[A].O and now.ledger.orders[GK].rec[A].O.h, "msar", "other record kept")
            tbl(now.ledger.adventure[GK].rec[A].T, "other data kept: adventure records")
        end,
        [table.concat({ "ledger", "orders", GK, "rec", A, "O", "t" }, ".")] = function(now)
            eq(now.ledger.orders[GK].rec[A].W and now.ledger.orders[GK].rec[A].W.h, "8ekdu", "other record kept")
        end,
        -- K5: the author's shared records are dropped, the rest of the store stays.
        [table.concat({ "share", "guilds", GK, "rec", A }, ".")] = function(now)
            tbl(now.share.guilds[GK].rec, "share rec still a table")
            tbl(now.ledger.orders[GK].rec[A].W, "other data kept: order records")
        end,
        [table.concat({ "share", "guilds", GK, "rec", A, "B" }, ".")] = function(now)
            local r = now.share.guilds[GK].rec[A]
            eq(r and r.Z and r.Z.h, "21on6", "other shared record kept")
        end,
    }
    for _, path in ipairs(BAD) do
        local name = table.concat(path, ".")
        local title = "GF-TEST-01 edge: 0.15.1 save with " .. name .. " a string"
        test(title, function()
            local db = copy(OLD["0.15.1"])
            local parent = db
            for i = 1, #path - 1 do parent = parent[path[i]] end
            parent[path[#path]] = "壞掉"
            local ns = login(db)
            drawEveryPage(ns)
            exercise(ns)
            local okOut, err = pcall(wow.logout)
            ok(okOut, "log out: " .. tostring(err))
            local now = GreenFangToolkitDB
            eq(now.schemaVersion, 2, "schemaVersion")
            if path[1] ~= "prices" then eq(now.prices.vendor[2770], "15.1763000000", "other data kept: vendor price") end
            if path[1] ~= "orders" then
                local found = false
                for _, x in ipairs(now.orders.history[ME]) do if x.id == "h-old1" then found = true end end
                ok(found, "other data kept: history")
            end
            if AFTER[name] then AFTER[name](now) end
        end)
    end
end
