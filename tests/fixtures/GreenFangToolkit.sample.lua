-- 去識別化的 GreenFangToolkitDB（schemaVersion 2）樣本，給 GF Sync 測試用。
-- 由 tests/addon/run.lua --fixture 產生，請勿手改。所有角色、GUID、伺服器名稱皆為虛構。
-- 格式模仿遊戲客戶端寫入 WTF/Account/<帳號>/SavedVariables/GreenFangToolkit.lua 的樣子。
-- GF Sync 只讀 sync 區塊。roster.snapshots 是遊戲內畫面用的資料，含 zone／online，不得上傳。

GreenFangToolkitDB = {
	["addonVersion"] = "0.12.2",
	["migration"] = {
		["at"] = 1763370000,
		["from"] = "GFGuildRosterDB",
		["fromVersion"] = 3,
		["members"] = 2,
	},
	["peers"] = {
		["測試乙-測試伺服器"] = {
			["classToken"] = "WARRIOR",
			["guid"] = "Player-0000-0000000B",
			["guild"] = "綠皮與獠牙冒險事務所",
			["level"] = 61,
			["location"] = {
				["subZone"] = "力量谷",
				["zone"] = "奧格瑪",
			},
			["name"] = "測試乙-測試伺服器",
			["professions"] = {
				{
					["max"] = 300,
					["name"] = "採礦",
					["rank"] = 300,
					["skillLineID"] = 186,
				}, -- [1]
				{
					["max"] = 300,
					["name"] = "鍛造",
					["rank"] = 280,
					["skillLineID"] = 164,
				}, -- [2]
				{
					["max"] = 225,
					["name"] = "釣魚",
					["rank"] = 150,
					["skillLineID"] = 356,
				}, -- [3]
				{
					["max"] = 150,
					["name"] = "烹飪",
					["rank"] = 90,
					["skillLineID"] = 185,
				}, -- [4]
				{
					["max"] = 150,
					["name"] = "急救",
					["rank"] = 75,
					["skillLineID"] = 129,
				}, -- [5]
			},
			["realm"] = "測試伺服器",
			["receivedAt"] = 1763373610,
			["reportedAt"] = 1763373590,
		},
	},
	["roster"] = {
		["lastKey"] = "測試伺服器|綠皮與獠牙冒險事務所",
		["snapshots"] = {
			["測試伺服器|綠皮與獠牙冒險事務所"] = {
				["capturedAt"] = 1763373605,
				["capturedAtLocal"] = "2025-11-17 18:00:05",
				["capturedAtUTC"] = "2025-11-17T10:00:05Z",
				["faction"] = "Horde",
				["guild"] = "綠皮與獠牙冒險事務所",
				["members"] = {
					{
						["class"] = "獵人",
						["classToken"] = "HUNTER",
						["guid"] = "Player-0000-0000000D",
						["guildRank"] = "新進",
						["level"] = 12,
						["name"] = "測試丁-測試伺服器",
						["online"] = false,
						["professionSource"] = "missing",
						["professions"] = {
						},
						["race"] = "食人妖",
						["raceSource"] = "guid",
						["rankIndex"] = 3,
						["zone"] = "杜洛塔",
					}, -- [1]
					{
						["class"] = "法師",
						["classToken"] = "MAGE",
						["guid"] = "Player-0000-0000000C",
						["guildRank"] = "會員",
						["level"] = 25,
						["name"] = "測試丙-測試伺服器",
						["online"] = false,
						["professionSource"] = "guild",
						["professions"] = {
							"裁縫", -- [1]
							"附魔", -- [2]
						},
						["race"] = "不死族",
						["raceID"] = 5,
						["raceSource"] = "guild",
						["rankIndex"] = 2,
						["zone"] = "幽暗城",
					}, -- [2]
					{
						["class"] = "戰士",
						["classToken"] = "WARRIOR",
						["guid"] = "Player-0000-0000000B",
						["guildRank"] = "會長",
						["level"] = 60,
						["name"] = "測試乙-測試伺服器",
						["online"] = true,
						["professionSource"] = "guild",
						["professions"] = {
							"鍛造", -- [1]
							"採礦", -- [2]
						},
						["race"] = "獸人",
						["raceID"] = 2,
						["raceSource"] = "guild",
						["rankIndex"] = 0,
						["zone"] = "奧格瑪",
					}, -- [3]
					{
						["class"] = "德魯伊",
						["classToken"] = "DRUID",
						["guid"] = "Player-0000-0000000A",
						["guildRank"] = "會員",
						["level"] = 32,
						["name"] = "測試甲-測試伺服器",
						["online"] = true,
						["professionSource"] = "cached",
						["professions"] = {
							"製皮", -- [1]
							"剝皮", -- [2]
						},
						["race"] = "牛頭人",
						["raceID"] = 6,
						["raceSource"] = "cached",
						["rankIndex"] = 2,
						["zone"] = "雷霆崖",
					}, -- [4]
				},
				["online"] = 2,
				["realm"] = "測試伺服器",
				["total"] = 4,
			},
		},
	},
	["schema"] = "gf.toolkit",
	["schemaVersion"] = 2,
	["settings"] = {
		["fullNames"] = {
			["Player-0000-0000000A"] = "測試甲",
		},
		["minimapAngle"] = 123,
		["minimapLayoutVersion"] = 2,
		["realms"] = {
			["Player-0000-0000000A"] = "測試伺服器",
			["Player-0000-0000000F"] = "測試伺服器",
		},
		["sortAscending"] = false,
		["sortKey"] = "level",
	},
	["share"] = {
		["guilds"] = {
			["測試伺服器|綠皮與獠牙冒險事務所"] = {
				["gone"] = {
				},
				["idsSent"] = {
					["0000-0000000B"] = {
					},
				},
				["named"] = {
				},
				["queued"] = {
					["0000-0000000B"] = {
						["B"] = {
							["h"] = "8f9k1",
							["t"] = 1763373590,
						},
						["P"] = {
							["h"] = "3lf3t",
							["t"] = 1763373590,
						},
						["Z"] = {
							["h"] = "c9hr",
							["t"] = 1763373590,
						},
					},
				},
				["rec"] = {
					["0000-0000000B"] = {
						["B"] = {
							["fromAuthor"] = true,
							["h"] = "8f9k1",
							["heardAt"] = 1763373610,
							["t"] = 1763373590,
							["v"] = "61.WARRIOR",
							["via"] = "0000-0000000B",
						},
						["P"] = {
							["fromAuthor"] = true,
							["h"] = "3lf3t",
							["heardAt"] = 1763373610,
							["t"] = 1763373590,
							["v"] = "186,300,300/164,280,300/356,150,225/185,90,150/129,75,150",
							["via"] = "0000-0000000B",
						},
						["Z"] = {
							["fromAuthor"] = true,
							["h"] = "c9hr",
							["heardAt"] = 1763373610,
							["t"] = 1763373590,
							["v"] = "奧格瑪/力量谷",
							["via"] = "0000-0000000B",
						},
					},
				},
				["shareRefreshAt"] = 1763370010,
				["tomb"] = {
				},
			},
		},
		["seenIDs"] = {
		},
		["v"] = 1,
	},
	["sync"] = {
		["enabled"] = true,
		["noticeShown"] = true,
		["noticeVersion"] = 4,
		["outbox"] = {
			{
				["capturedAt"] = 1763370005,
				["capturedAtServer"] = 1763370005,
				["game"] = {
					["interface"] = 16001,
					["locale"] = "zhTW",
					["realm"] = "測試伺服器",
					["world"] = "forever",
				},
				["id"] = "Player-0000-0000000A:1763370005:character.self",
				["kind"] = "character.self",
				["payload"] = {
					["class"] = "德魯伊",
					["classToken"] = "DRUID",
					["level"] = 32,
					["location"] = {
						["subZone"] = "長者高地",
						["zone"] = "雷霆崖",
					},
					["professions"] = {
						{
							["max"] = 225,
							["name"] = "製皮",
							["rank"] = 151,
							["skillLineID"] = 165,
						}, -- [1]
						{
							["max"] = 225,
							["name"] = "剝皮",
							["rank"] = 160,
							["skillLineID"] = 393,
						}, -- [2]
						{
							["max"] = 150,
							["name"] = "釣魚",
							["rank"] = 75,
							["skillLineID"] = 356,
						}, -- [3]
						{
							["max"] = 150,
							["name"] = "烹飪",
							["rank"] = 60,
							["skillLineID"] = 185,
						}, -- [4]
					},
					["race"] = "牛頭人",
					["raceID"] = 6,
				},
				["uploader"] = {
					["faction"] = "Horde",
					["fullName"] = "測試甲",
					["guid"] = "Player-0000-0000000A",
					["guild"] = "綠皮與獠牙冒險事務所",
					["guildRank"] = "會員",
					["name"] = "測試甲",
					["realm"] = "測試伺服器",
				},
			}, -- [1]
			{
				["capturedAt"] = 1763373605,
				["capturedAtServer"] = 1763373605,
				["game"] = {
					["interface"] = 16001,
					["locale"] = "zhTW",
					["realm"] = "測試伺服器",
					["world"] = "forever",
				},
				["id"] = "Player-0000-0000000F:1763373605:roster.snapshot",
				["kind"] = "roster.snapshot",
				["payload"] = {
					["members"] = {
						{
							["classToken"] = "HUNTER",
							["guid"] = "Player-0000-0000000D",
							["guildRank"] = "新進",
							["level"] = 12,
							["name"] = "測試丁-測試伺服器",
							["professionSource"] = "missing",
							["professions"] = {
							},
							["race"] = "食人妖",
						}, -- [1]
						{
							["classToken"] = "MAGE",
							["guid"] = "Player-0000-0000000C",
							["guildRank"] = "會員",
							["level"] = 25,
							["name"] = "測試丙-測試伺服器",
							["professionSource"] = "guild",
							["professions"] = {
								"裁縫", -- [1]
								"附魔", -- [2]
							},
							["race"] = "不死族",
							["raceID"] = 5,
						}, -- [2]
						{
							["classToken"] = "WARRIOR",
							["guid"] = "Player-0000-0000000B",
							["guildRank"] = "會長",
							["level"] = 60,
							["name"] = "測試乙-測試伺服器",
							["professionSource"] = "guild",
							["professions"] = {
								"鍛造", -- [1]
								"採礦", -- [2]
							},
							["race"] = "獸人",
							["raceID"] = 2,
						}, -- [3]
						{
							["classToken"] = "DRUID",
							["guid"] = "Player-0000-0000000A",
							["guildRank"] = "會員",
							["level"] = 32,
							["name"] = "測試甲-測試伺服器",
							["professionSource"] = "cached",
							["professions"] = {
								"製皮", -- [1]
								"剝皮", -- [2]
							},
							["race"] = "牛頭人",
							["raceID"] = 6,
						}, -- [4]
					},
					["total"] = 4,
				},
				["uploader"] = {
					["faction"] = "Horde",
					["guid"] = "Player-0000-0000000F",
					["guild"] = "綠皮與獠牙冒險事務所",
					["guildRank"] = "會員",
					["name"] = "測試己",
					["realm"] = "測試伺服器",
				},
			}, -- [2]
			{
				["capturedAt"] = 1763373610,
				["capturedAtServer"] = 1763373610,
				["game"] = {
					["interface"] = 16001,
					["locale"] = "zhTW",
					["realm"] = "測試伺服器",
					["world"] = "forever",
				},
				["id"] = "Player-0000-0000000F:1763373610:character.self",
				["kind"] = "character.self",
				["payload"] = {
					["class"] = "薩滿",
					["classToken"] = "SHAMAN",
					["level"] = 18,
					["location"] = {
						["subZone"] = "長者高地",
						["zone"] = "雷霆崖",
					},
					["professions"] = {
						{
							["max"] = 150,
							["name"] = "採礦",
							["rank"] = 75,
							["skillLineID"] = 186,
						}, -- [1]
						{
							["max"] = 150,
							["name"] = "鍛造",
							["rank"] = 70,
							["skillLineID"] = 164,
						}, -- [2]
					},
					["race"] = "食人妖",
					["raceID"] = 8,
				},
				["uploader"] = {
					["faction"] = "Horde",
					["guid"] = "Player-0000-0000000F",
					["guild"] = "綠皮與獠牙冒險事務所",
					["guildRank"] = "會員",
					["name"] = "測試己",
					["realm"] = "測試伺服器",
				},
			}, -- [3]
			{
				["capturedAt"] = 1763373610,
				["capturedAtServer"] = 1763373610,
				["game"] = {
					["interface"] = 16001,
					["locale"] = "zhTW",
					["realm"] = "測試伺服器",
					["world"] = "forever",
				},
				["id"] = "Player-0000-0000000F:1763373610:member.share:Player-0000-0000000B",
				["kind"] = "member.share",
				["payload"] = {
					["classToken"] = {
						["recordedAt"] = 1763373590,
						["value"] = "WARRIOR",
						["via"] = "author",
					},
					["level"] = {
						["recordedAt"] = 1763373590,
						["value"] = 61,
						["via"] = "author",
					},
					["location"] = {
						["recordedAt"] = 1763373590,
						["value"] = {
							["subZone"] = "力量谷",
							["zone"] = "奧格瑪",
						},
						["via"] = "author",
					},
					["professions"] = {
						["recordedAt"] = 1763373590,
						["value"] = {
							{
								["max"] = 300,
								["name"] = "採礦",
								["rank"] = 300,
								["skillLineID"] = 186,
							}, -- [1]
							{
								["max"] = 300,
								["name"] = "鍛造",
								["rank"] = 280,
								["skillLineID"] = 164,
							}, -- [2]
							{
								["max"] = 225,
								["name"] = "釣魚",
								["rank"] = 150,
								["skillLineID"] = 356,
							}, -- [3]
							{
								["max"] = 150,
								["name"] = "烹飪",
								["rank"] = 90,
								["skillLineID"] = 185,
							}, -- [4]
							{
								["max"] = 150,
								["name"] = "急救",
								["rank"] = 75,
								["skillLineID"] = 129,
							}, -- [5]
						},
						["via"] = "author",
					},
					["subject"] = {
						["fullName"] = "測試乙",
						["guid"] = "Player-0000-0000000B",
						["name"] = "測試乙-測試伺服器",
						["realm"] = "測試伺服器",
					},
				},
				["uploader"] = {
					["faction"] = "Horde",
					["guid"] = "Player-0000-0000000F",
					["guild"] = "綠皮與獠牙冒險事務所",
					["guildRank"] = "會員",
					["name"] = "測試己",
					["realm"] = "測試伺服器",
				},
			}, -- [4]
		},
	},
}
