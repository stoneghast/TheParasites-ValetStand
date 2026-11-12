-- =============================================================================
-- Which release of The Parasites a mod was tested on. Docs: docs/mod-compatibility.md
--
-- First line of a mod's main.lua:
--   if not require("game_version").supported("MyMod", { "0.1.6.0.2.5" }) then return end
--
-- On any other release, or if the build cannot be identified, the mod stops there: no hooks, no key binds, one clear log line.
-- Installed to ue4ss/Mods/shared/, which is on every Lua mod's package.path.
-- =============================================================================
local M = {}

-- A build is identified by the exact size of the game's own pak. Mods load before the game's assets can be read (the version label in
-- DA_GlobalMenuConfig reads as nothing at that point); this file can always be read, and it also catches a patch that keeps the old label.
local GAME_PAK = "../../Content/Paks/TheParasites-Windows.pak"   -- relative to Binaries/Win64

-- One line per release: { size of GAME_PAK in bytes, release }. A new release's size is in the log line below.
local BUILDS = {
    { 23191693823, "0.1.6.0.2.5" },
}

local function gamePakSize()
    local f = io.open(GAME_PAK, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
end

-- the release, e.g. "0.1.6.0.2.5", or nil if this build is not in BUILDS; second result: the pak size
function M.current()
    local size = gamePakSize()
    for _, b in ipairs(BUILDS) do
        if b[1] == size then return b[2], size end
    end
    return nil, size
end

-- true if this game release is one of `versions`; otherwise logs why the mod is not starting
function M.supported(mod, versions)
    local current, size = M.current()
    for _, v in ipairs(versions) do
        if v == current then return true end
    end
    print(string.format("[%s] NOT STARTED: tested on game version %s, this game is %s (%s is %s bytes). Check the mod's page for an update.\n",
        mod, table.concat(versions, ", "), current or "an unknown build", GAME_PAK, tostring(size)))
    return false
end

return M
