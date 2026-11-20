-- Config: the guild this toolkit serves. Loaded first.
--
-- Every guild check reads ns.Config.guild: site sync (Sync.lua), the roster
-- window (UI.lua / Roster.lua) and the player-facing text that names the
-- guild. To use the toolkit for another guild, change it here (and see
-- docs/research/guild-config.md for what else must change outside the AddOn).
--
--   name  : exact in-game guild name (GetGuildInfo("player"))
--   realm : exact realm name (GetRealmName()), or nil to accept any realm

local _, ns = ...

ns.Config = {
    guild = {
        name = "綠皮與獠牙冒險事務所",
        realm = nil,
    },
}
