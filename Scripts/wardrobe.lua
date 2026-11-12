-- =============================================================================
-- ValetStand: the panel's Undress and Dress buttons, one click moves every garment the stand has a slot for.
--
-- The buttons are the game's JSI_Souls_C, the totem panel's image button, placed in BP_ValetStandWidget by ue/TheParasites/Scripts/valetstand_assets.py. A widget built
-- from Python has no graph and Lua cannot create widgets, but JSI_Souls binds its own button to OnClicked_Event_0, which can be hooked here.
--
-- A move is what a drag does: "Jig Unhandled Event" on the destination component. Calling SERVER_RequestMoveItemToAnotherComp directly moves the
-- data but skips the widgets, and the panels show the item twice. Slots match across the two components by container name. Records come from
-- MainReplicatedContainers: the game's own readers return user structs through out params, which crash from Lua.
-- See docs/build-system.md section 5.4.
-- =============================================================================
local Defer = require("defer")

local M = {}

local BUTTON_CLASS = "/Game/JigSInventory/Jigsaw/Widgets/JSI_Souls.JSI_Souls_C"
local PANEL_CLASS = "BP_ValetStandWidget_C"
local UNDRESS, DRESS = "VS_Undress", "VS_Dress"   -- the widgets' names (valetstand_assets.py BUTTONS)
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local F = {   -- member names of the game's user structs (cooked: fields match by full name)
    containerIndex = "ContainerIndex_22_9A211B86466A9D1C57E1FC839A5B0896",
    inContainer = "InContainerUID_24_D1504ED7438699C73EA046AD734E79BF",
    replication = "ReplicationUID_23_EB27D09649B6E02591DCA98708B06332",
    items = "ContainerItems_16_16E3D87B4C0AC5D6C9C861B96B5ABA8B",
    uid = "UniqueServerID_37_C49AE0DA449ACAE3BE4633A263303B68",
    containerName = "ContainerName_13_2E875F304DF2B4B31A44F98C299C3982",
}

local log = function(s) print("[ValetStand] wardrobe: " .. tostring(s) .. "\n") end
local function valid(o) local ok, r = pcall(function() return o ~= nil and o:IsValid() end) return ok and r end
local function guid(g) return { A = g.A, B = g.B, C = g.C, D = g.D } end
local function unwrap(v)   -- out values arrive wrapped
    local x = v
    pcall(function() if type(v) == "userdata" and type(v.get) == "function" then x = v:get() end end)
    return x
end

-- lower-case container name -> { container = its Guid, item = the Guid of what it holds, or nil }. Names differ in case between components.
local function slots(comp)
    local names, out = {}, {}
    comp.ContainersSettings:ForEach(function(i, row) names[i - 1] = row:get()[F.containerName]:ToString():lower() end)
    comp.MainReplicatedContainers:ForEach(function(_, e)
        local r = e:get()
        local g = r[F.inContainer]
        if g.A ~= 0 or g.B ~= 0 or g.C ~= 0 or g.D ~= 0 then return end   -- a pocket of a garment: it travels with the garment
        local slot = { container = guid(r[F.replication]) }
        r[F.items]:ForEach(function(_, it) slot.item = guid(it:get()[F.uid]) end)
        out[names[r[F.containerIndex]]] = slot
    end)
    return out
end

local function itemWidget(comp, uid)
    local o = {}
    comp["Find Item by UID"](comp, uid, o)
    local w = unwrap(o.Found)
    if not valid(w) then error("no widget for the item") end
    return w
end

local function containerWidget(comp, uid)
    local o = {}
    comp:FindJSIContainer(uid, o, o)
    local w = unwrap(o.JSIRef)
    if not valid(w) then error("no widget for the container") end
    return w
end

local function move(from, to, item, container)
    local w = itemWidget(from, item)
    to["Jig Unhandled Event"](to, w.ContainerMother, containerWidget(to, container), 0, w, false, 0)
end

-- Both slots full. The game's own swap needs both items on one component, so the worn item waits in the player's bags. With no room there, what
-- is in the destination slot goes on the floor, and the moving item takes its place.
local function exchange(me, stand, name, from, to, slotFrom, slotTo)
    local worn, onStand = slots(me)[name], slots(stand)[name]
    local w = itemWidget(me, worn.item)
    local o = {}
    me:Context_TryUnequip(w, w.ContainerMother, o)
    if unwrap(o.Unequip) == true then
        move(stand, me, onStand.item, worn.container)
        move(me, stand, worn.item, onStand.container)
        return
    end
    log("no room in the bags, dropping what was in the " .. name .. " slot")
    local d = itemWidget(to, slotTo.item)
    me:ItemDropRequest_Event_0(d, 1, d.ContainerMother, false, true)
    move(from, to, slotFrom.item, slotTo.container)
end

-- every item on `from` whose slot also exists on `to`: the player's weapons, gloves and pockets stay where they are
local function transfer(me, stand, from, to)
    local here, there = slots(from), slots(to)
    local n = 0
    for name, source in pairs(here) do
        local target = there[name]
        if source.item and target then
            local ok, err = pcall(function()
                if target.item then exchange(me, stand, name, from, to, source, target) else move(from, to, source.item, target.container) end
            end)
            if ok then n = n + 1 else log(name .. " failed: " .. tostring(err)) end
        end
    end
    return n
end

-- the station whose component owns this open panel
local function standOf(panel)
    for _, s in ipairs(FindAllOf("BP_ValetStandStation_C") or {}) do
        if valid(s) and valid(s.BP_JigMultiplayer.InventoryWidgetRef) and s.BP_JigMultiplayer.InventoryWidgetRef:GetAddress() == panel:GetAddress() then
            return s.BP_JigMultiplayer
        end
    end
    return nil
end

local function clicked(button)
    local name = button:GetFName():ToString()
    local panel = button:GetOuter():GetOuter()
    local stand = standOf(panel)
    if not stand then log("no stand owns this panel") return end
    local me = FindFirstOf("PlayerController").Pawn.BP_JigMultiplayer
    local n
    if name == UNDRESS then n = transfer(me, stand, me, stand) else n = transfer(me, stand, stand, me) end
    log(name .. ": " .. n .. " item(s)")
end

local function onClick(ctx)
    local ok, err = pcall(function()
        local button = ctx:get()
        if not valid(button) or not button:GetFullName():find(PANEL_CLASS, 1, true) then return end   -- the totem panel uses this class too
        -- JSI_Souls stays lit after a press, as the totem's skills do
        button.Click = false
        button.Button:SetBackgroundColor(WHITE)
        Defer.run(function() if valid(button) then clicked(button) end end)
    end)
    if not ok then log("click hook failed: " .. tostring(err)) end
end

local hooked = false
local function install()
    if hooked then return end
    hooked = true
    local ok, err = pcall(RegisterHook, BUTTON_CLASS .. ":OnClicked_Event_0", onClick)
    if ok then log("hook installed") else hooked = false log("hook failed: " .. tostring(err)) end
end

function M.start()
    pcall(NotifyOnNewObject, BUTTON_CLASS, install)
    if valid(StaticFindObject(BUTTON_CLASS)) then install() end   -- already loaded
end

return M
