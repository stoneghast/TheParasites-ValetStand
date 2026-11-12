-- =============================================================================
-- ValetStand step 4 — show the slotted garments on the stand.
--
-- Each station's BP_JigMultiplayer keeps its slots in MainReplicatedContainers (one record per ContainersSettings row,
-- ContainerIndex = slot order of slots.lua). For every top-level slot holding an item, the station gets one
-- SkeletalMeshComponent with the item's worn mesh (garments.lua, generated from DT_EquipmentMeshData). Without an
-- AnimInstance a skeletal mesh renders in its bind pose, the pose the stand was modelled around (mods/ValetStand/blender/check_inside.py), so
-- body garments need no body: identity transform at the actor root. Socket items (hats, glasses, backpacks) attach to the
-- matching socket of one hidden Anna body component, which also holds them in bind pose.
-- A light poll compares each station's contents with what it shows; adding, removing, swapping and loading a save all go
-- through the same rebuild, no per-event bookkeeping.
-- =============================================================================
local GARMENTS = require("garments")

local M = {}

-- item IDs are FNames, which ignore case: a slot can report BACKPACK_2 for the table row Backpack_2
local GARMENT_BY_ID = {}
for id, g in pairs(GARMENTS) do GARMENT_BY_ID[id:lower()] = g end

local BODY_MESH = "/Game/Characters/Mannequins/Meshes/SKM_Anna_Mesh_00.SKM_Anna_Mesh_00"
local SKM_CLASS = "/Script/Engine.SkeletalMeshComponent"
-- member names of the game's user structs (cooked: fields match by full name)
local F = {
    containerIndex = "ContainerIndex_22_9A211B86466A9D1C57E1FC839A5B0896",
    inContainer = "InContainerUID_24_D1504ED7438699C73EA046AD734E79BF",
    items = "ContainerItems_16_16E3D87B4C0AC5D6C9C861B96B5ABA8B",
    itemInfo = "ItemInfo_25_937A083B4BD3D9B590E0A69C76A4F6F7",
    itemId = "ItemID_2_01CA27D84AF7D1014D9E2E83894C1848",
    color = "CurrentColor_31_4D9A3DC3474A96D8B5EC20991DAC2794",
    materials = "CurrentMaterials_35_B764B3CE4E24068D44BCABA5C44B6415",
    durability = "Durability_22_A3557C454274D193D47AB9B71FB0C0CA",   -- Vector2D: X current, Y max
    uid = "UniqueServerID_37_C49AE0DA449ACAE3BE4633A263303B68",
}
local POLL_MS = 1000
local GRIME_FILE = "ue4ss/Mods/ValetStand/garment_grime.txt"   -- relative to Binaries\Win64, like WetLayers' state file
-- The bind pose holds the arms out with the forearms bent forward and the stand has none, so sleeves would stick out. This slot's garments use a
-- poseable mesh with the arms hanging down, this far out from vertical: straight down pushes the cuffs into the hips (tried in Blender).
-- Other slots keep a plain skeletal mesh: a poseable mesh has no cloth simulation, which dresses in LOWER use.
local SLOTS = require("slots")
local SLEEVE_SLOT = "UPPER"
local SLEEVE_OUTWARD_DEG = 8
local SLEEVE_BONES = {   -- side: +1 for her left, which is +X in mesh space
    { bone = "upperarm_l", tip = "lowerarm_l", side = 1 },
    { bone = "lowerarm_l", tip = "hand_l", side = 1 },
    { bone = "upperarm_r", tip = "lowerarm_r", side = -1 },
    { bone = "lowerarm_r", tip = "hand_r", side = -1 },
}
local POSEABLE_CLASS = "/Script/Engine.PoseableMeshComponent"
local COMPONENT_SPACE = 1   -- EBoneSpaces

local log = function(s) print("[ValetStand] " .. tostring(s) .. "\n") end
local function valid(o) local ok, r = pcall(function() return o ~= nil and o:IsValid() end) return ok and r end

local meshCache = {}
local function mesh(path)
    local m = meshCache[path]
    if valid(m) then return m end
    m = StaticFindObject(path)
    if not valid(m) then pcall(function() m = LoadAsset(path) end) end
    if valid(m) then meshCache[path] = m return m end
    return nil
end

-- Dirt and blood belong to the wearer (BP_JigCharacter DirtMask, Blood_Mask_Opacity), one level for everything worn; items do not store
-- them. So a garment taken off and slotted keeps the level the wearer had at that moment, here, by item UID. Anything else on a stand is clean.
local grime = {}   -- item UID -> { dirt = 0..1, blood = 0..1 }
local CLEAN = { dirt = 0, blood = 0 }

local function loadGrime()
    local f = io.open(GRIME_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local uid, dirt, blood = line:match("^(%S+)\t(%S+)\t(%S+)$")
        if uid then grime[uid] = { dirt = tonumber(dirt) or 0, blood = tonumber(blood) or 0 } end
    end
    f:close()
end

local function saveGrime()
    local f = io.open(GRIME_FILE, "w")
    if not f then log("dress: cannot write " .. GRIME_FILE) return end
    for uid, g in pairs(grime) do f:write(string.format("%s\t%.4f\t%.4f\n", uid, g.dirt, g.blood)) end
    f:close()
end

local function player()
    local pc = FindFirstOf("PlayerController")
    local pawn = pc and pc.Pawn
    return valid(pawn) and pawn or nil
end

-- the skeletal meshes the player has on right now, by object path
local function wornMeshes(pawn)
    local worn = {}
    for _, e in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject(SKM_CLASS))) do
        local a = e:get():GetSkeletalMeshAsset()
        if valid(a) then worn[a:GetFullName():match("%S+$")] = true end
    end
    return worn
end

-- The garment material's Dur parameter for a durability, as BP_JigCharacter maps it: full durability -2.5, an eighth or less 3.
local function wear(durability, max)
    if max <= 0 then return nil end
    local t = (durability - max) / (max / 8 - max)
    return -2.5 + 5.5 * math.max(0, math.min(1, t))
end

-- What one item looks like. The look belongs to the item, not its mesh: EquipActorToMesh gives each material slot the item's
-- CurrentMaterials entry and tints with CurrentColor, and the item's durability drives the wear parameter.
-- `key` changes when another item, or the same ID with another look, is slotted.
local function look(item)
    local info = item[F.itemInfo]
    local u = item[F.uid]
    local l = { id = info[F.itemId]:ToString(), uid = string.format("%x-%x-%x-%x", u.A, u.B, u.C, u.D), materials = {} }
    local key = { l.id, l.uid }
    info[F.materials]:ForEach(function(i, m)
        local mat = m:get()
        l.materials[i] = mat
        key[#key + 1] = valid(mat) and mat:GetFullName() or "-"
    end)
    local c = info[F.color]
    if c.R ~= 0 or c.G ~= 0 or c.B ~= 0 or c.A ~= 0 then
        l.color = { X = c.R, Y = c.G, Z = c.B }
        key[#key + 1] = string.format("%f %f %f", c.R, c.G, c.B)
    end
    local d = info[F.durability]
    l.wear = wear(d.X, d.Y)
    if l.wear then key[#key + 1] = string.format("%.2f", l.wear) end
    l.key = table.concat(key, "|")
    return l
end

-- slot index (0-based ContainerIndex) -> look() of the item in the station's top-level slots
local function contents(station)
    local out = {}
    station.BP_JigMultiplayer.MainReplicatedContainers:ForEach(function(_, e)
        local r = e:get()
        local g = r[F.inContainer]
        if g.A ~= 0 or g.B ~= 0 or g.C ~= 0 or g.D ~= 0 then return end   -- a pocket of a slotted garment, not a stand slot
        local idx = r[F.containerIndex]
        r[F.items]:ForEach(function(_, it)
            out[idx] = look(it:get())
        end)
    end)
    return out
end

local shown = {}   -- station full name -> { body = comp, slots = { [idx] = { item = id, comp = comp } } }

local IDENTITY = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }

local function addSkm(station, name, xf, class)
    local cls = StaticFindObject(class or SKM_CLASS)
    local c = station:AddComponentByClass(cls, false, xf or IDENTITY, false)
    if not valid(c) then error("AddComponentByClass returned nothing for " .. name) end
    pcall(function() c:SetCollisionEnabled(0) end)        -- ECollisionEnabled::NoCollision: never block the interact trace
    pcall(function() c:SetCastShadow(true) end)
    return c
end

local function body(station, st)
    if valid(st.body) then return st.body end
    local m = mesh(BODY_MESH)
    if not m then error("body mesh not loadable: " .. BODY_MESH) end
    st.body = addSkm(station, "body")
    st.body:SetSkeletalMeshAsset(m)
    st.body:SetVisibility(false, false)                    -- sockets only; the stand is not a mannequin
    return st.body
end

-- Aim each arm bone down in mesh space (Anna faces +Y, her left is +X). Every rotation is worked out from the bind pose before any is set, because
-- a rotation in component space is absolute: moving a parent first would change what its child's aim is measured from.
local function lowerSleeves(c)
    local math_lib = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local out = math.rad(SLEEVE_OUTWARD_DEG)
    local function location(name)   -- a bone the mesh lacks reads as the origin, where no arm bone is
        local p = c:GetBoneLocationByName(name, COMPONENT_SPACE)
        if p.X ~= 0 or p.Y ~= 0 or p.Z ~= 0 then return p end
    end
    local aimed = {}
    for _, b in ipairs(SLEEVE_BONES) do
        local name = FName(b.bone)
        local from, to = location(name), location(FName(b.tip))
        if from and to then
            local x, y, z = to.X - from.X, to.Y - from.Y, to.Z - from.Z
            local len = math.sqrt(x * x + y * y + z * z)
            x, y, z = x / len, y / len, z / len
            local tx, tz = b.side * math.sin(out), -math.cos(out)      -- target direction; its Y is 0
            local axis = { X = y * tz, Y = z * tx - x * tz, Z = -y * tx }   -- bone direction x target
            local angle = math.deg(math.acos(math.max(-1, math.min(1, x * tx + z * tz))))
            local turn = math_lib:RotatorFromAxisAndAngle(axis, angle)
            aimed[#aimed + 1] = { name = name, rotation = math_lib:ComposeRotators(c:GetBoneRotationByName(name, COMPONENT_SPACE), turn) }
        end
    end
    if #aimed == 0 then error("no arm bones found") end
    for _, a in ipairs(aimed) do c:SetBoneRotationByName(a.name, a.rotation, COMPONENT_SPACE) end
end

local function show(station, st, idx, item)
    local g = GARMENT_BY_ID[item.id:lower()]
    if not g then log("dress: no worn mesh for " .. item.id .. " (slot " .. idx .. ")") return nil end
    local m = mesh(g.mesh)
    if not m then log("dress: mesh not loadable " .. g.mesh) return nil end
    local sleeved = SLOTS[idx + 1] == SLEEVE_SLOT
    local c = addSkm(station, item.id, g.xf, sleeved and POSEABLE_CLASS or nil)
    if sleeved then
        c:SetSkinnedAssetAndUpdate(m, false)
        local ok, err = pcall(lowerSleeves, c)
        if not ok then log("dress: could not lower the sleeves of " .. item.id .. ": " .. tostring(err)) end   -- still shown, arms out
    else
        c:SetSkeletalMeshAsset(m)
    end
    for i, mat in pairs(item.materials) do
        if valid(mat) then c:SetMaterial(i - 1, mat) end
    end
    if item.color then c:SetVectorParameterValueOnMaterials(FName("Coloring"), item.color) end
    if item.wear then c:SetScalarParameterValueOnMaterials(FName("Dur"), item.wear) end
    -- always set: left unset, the material's own dirty defaults show
    local level = grime[item.uid] or CLEAN
    c:SetScalarParameterValueOnMaterials(FName("DirtOpacity"), level.dirt)
    c:SetScalarParameterValueOnMaterials(FName("BloodOpacity"), level.blood)
    if g.socket then
        local b = body(station, st)
        -- EAttachmentRule::KeepRelative (0): the component's relative transform becomes its offset from the socket
        c:K2_AttachToComponent(b, FName(g.socket), 0, 0, 0, false)
    end
    return c
end

-- poll: pass carries what this poll needs across stations (`takenOff`, the wearer's level) and collects what it saw (`onStands`, `left`)
local function dress(station, poll)
    local key = station:GetFullName()
    local st = shown[key] or { slots = {} }
    shown[key] = st
    local want = contents(station)
    for _, item in pairs(want) do poll.onStands[item.uid] = true end
    local changed = 0
    for idx, s in pairs(st.slots) do
        -- a component that is gone went with the old world: loading a save in a running game rebuilds the stations under the same names,
        -- so the record still matches the contents while nothing shows. A slot that failed to show has no comp and is not retried.
        if not want[idx] or want[idx].key ~= s.key or (s.comp and not valid(s.comp)) then
            if valid(s.comp) then pcall(function() s.comp:K2_DestroyComponent(s.comp) end) end
            poll.left[s.uid] = true
            st.slots[idx] = nil
            changed = changed + 1
        end
    end
    for idx, item in pairs(want) do
        if not st.slots[idx] then
            local g = GARMENT_BY_ID[item.id:lower()]
            if g and not grime[item.uid] and poll.takenOff(g.mesh) then
                grime[item.uid] = poll.wearerLevel()
                poll.grimeChanged = true
            end
            local ok, c = pcall(show, station, st, idx, item)
            if not ok then log("dress error: " .. tostring(c)) end
            st.slots[idx] = { key = item.key, uid = item.uid, comp = ok and c or false }   -- remember failures too (false): no retry storm every poll
            changed = changed + 1
        end
    end
    return changed
end

local wornBefore   -- wornMeshes() at the previous poll; nil until a poll has seen the player, so a loaded stand is not "just taken off"

function M.dressAll(out)
    local stations = FindAllOf("BP_ValetStandStation_C")
    if not stations then wornBefore = nil return end
    local pawn = player()
    local wornNow = pawn and wornMeshes(pawn) or nil
    local poll = {
        onStands = {},
        left = {},
        -- worn at the last poll and not now: this garment just came off the player, not out of a bag, and not a second identical one
        takenOff = function(meshPath) return wornBefore ~= nil and wornNow ~= nil and wornBefore[meshPath] == true and not wornNow[meshPath] end,
        wearerLevel = function()
            local function level(v) return type(v) == "number" and v or 0 end
            return { dirt = level(pawn.DirtMask), blood = level(pawn.Blood_Mask_Opacity) }
        end,
    }
    local complete = true
    for _, s in ipairs(stations) do
        if valid(s) then
            local ok, n = pcall(dress, s, poll)
            if not ok then
                complete = false
                (out or log)("dress " .. s:GetFName():ToString() .. ": " .. tostring(n))
            elseif n > 0 and out then out("dress " .. s:GetFName():ToString() .. ": " .. n .. " slot change(s)") end
        end
    end
    wornBefore = wornNow
    -- off every stand now (or moved to another one, which keeps it): once worn again the game applies the wearer's own level
    if complete then
        for uid in pairs(poll.left) do
            if grime[uid] and not poll.onStands[uid] then
                grime[uid] = nil
                poll.grimeChanged = true
            end
        end
    end
    if poll.grimeChanged then saveGrime() end
end

-- what each station holds vs. shows (console: vs dress)
function M.report(out)
    for _, s in ipairs(FindAllOf("BP_ValetStandStation_C") or {}) do
        if valid(s) then
            local st = shown[s:GetFullName()] or { slots = {} }
            local ok, want = pcall(contents, s)
            out(s:GetFName():ToString() .. (ok and "" or (" contents error: " .. tostring(want))))
            for idx, item in pairs(ok and want or {}) do
                local sh = st.slots[idx]
                local level = grime[item.uid] or CLEAN
                out(string.format("   slot %2d %-18s shown=%s dirt=%.2f blood=%.2f", idx, item.id, tostring(sh and valid(sh.comp)), level.dirt, level.blood))
            end
        end
    end
end

function M.start()
    loadGrime()
    LoopInGameThreadWithDelay(POLL_MS, function()   -- not LoopAsync: see defer.lua
        local ok, err = pcall(M.dressAll, nil)
        if not ok then log("dress: poll failed: " .. tostring(err)) end
    end)
    log("dress: polling stations every " .. POLL_MS .. " ms (" .. (function() local n = 0 for _ in pairs(GARMENTS) do n = n + 1 end return n end)() .. " garments known)")
end

return M
