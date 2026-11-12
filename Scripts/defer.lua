-- =============================================================================
-- ValetStand: run work on the game thread, outside any hook. A hook callback only calls run().
--
-- Real work inside a UE4SS hook has hung the game: a new game's first click on the notebook entry, while its class was not loaded yet, and Dress, while
-- equipping. ExecuteInGameThread from inside a hook deadlocked too, and ExecuteWithDelay's callbacks stopped arriving after two clicks.
-- Never LoopAsync: it is deprecated and runs Lua off the game thread. The queue and every callback stay on the game thread: hooks run there, and so
-- does tick().
-- =============================================================================
local M = {}

local POLL_MS = 50
local queue = {}

local log = function(s) print("[ValetStand] " .. tostring(s) .. "\n") end

local function tick()
    local ready, waiting = {}, {}
    for _, job in ipairs(queue) do
        job.ms = job.ms - POLL_MS
        if job.ms <= 0 then ready[#ready + 1] = job else waiting[#waiting + 1] = job end
    end
    queue = waiting
    for _, job in ipairs(ready) do
        local ok, err = pcall(job.fn)
        if not ok then log("deferred work failed: " .. tostring(err)) end
    end
end

-- fn runs on the game thread, no sooner than ms from now (default: the next tick)
function M.run(fn, ms)
    queue[#queue + 1] = { fn = fn, ms = ms or 0 }
end

function M.start()
    LoopInGameThreadWithDelay(POLL_MS, tick)
end

return M
