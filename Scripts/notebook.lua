-- =============================================================================
-- ValetStand: the stand's entry in the notebook, so it is chosen from the Build tab like any other building.
--
-- Pages have no free layout slot and creating widgets from Lua hard-crashes this game, so this claims an entry that exists:
-- Notepad_Buildng's BP_Page_5_4, an unfinished "In progress" duplicate of the Tourist Tent (the real one is on page 4). No game asset
-- is overridden. The entry has no click binding on the page, so a hook on its button starts the build. See docs/build-system.md §4.
--
-- UE4SS runs a hook on these Blueprint functions once, AFTER the function's body, and only the first callback (seen in game):
--   CE_Load_Unload_Images (page shown)  our name, cost and "not in progress"; its setup already ran on the old values, so run it once more
--   OnLoaded_...                        our drawing on the button (the entry has just loaded its soft Image into the button's brushes)
--   its button's click event            start the build
-- Nothing that loads an asset runs inside a hook (defer.lua): the draw hook uses the drawing if it is loaded, else defers the load.
-- =============================================================================
local Defer = require("defer")
local Lang = require("lang")

local M = {}

local N_BORD = "/Game/JigSInventory/Demo/Pickups/StaticMesh/Clothes/Watch/Book/N_Bord.N_Bord_C"
-- the live widget, e.g. ...NotepadHud_C_1.WidgetTree_2.Notepad_Buildng.WidgetTree_3.BP_Page_5_4 (not the class's template, ...Notepad_Buildng_C:WidgetTree.BP_Page_5_4)
local ENTRY_PATH = "%.Notepad_Buildng%.WidgetTree_%d+%.BP_Page_5_4$"
local ICONS = "/Game/JigSInventory/Jigsaw/Widgets/Images/Notepad_Icons/"
local DRAWING = "/Game/Mods/ValetStand/T_VS_BookEntry.T_VS_BookEntry"
local COST = {   -- the recipe (mods/ValetStand/blender/build_valet_stand.py), in the notebook's own resource icons
    { "2", ICONS .. "Branch_0.Branch_0" },
    { "4", ICONS .. "Stone_0.Stone_0" },
    { "5", ICONS .. "Plant_fibers.Plant_fibers" },
}

local log = function(s) print("[ValetStand] book: " .. tostring(s) .. "\n") end
local function valid(o) local ok, r = pcall(function() return o ~= nil and o:IsValid() end) return ok and r end

local load   -- path -> object or nil; main.lua's loader, which also finds assets in our pak

local function asset(path)
    local o = load(path)
    if not valid(o) then log("asset not loadable: " .. path) return nil end
    return o
end

local function ours(ctx)
    local w = ctx:get()
    if not valid(w) then return nil end
    return w:GetFullName():find(ENTRY_PATH) and w or nil
end

local function describe(w)
    if not w.InProgress then return end   -- already ours: this is the setup running on our values
    Defer.run(function()
        if not valid(w) or not w.InProgress then return end
        w.BuildingName = FText(Lang.name())
        w.InProgress = false
        w.UnknownDrawing = false
        w.Iteam = #COST
        for i, c in ipairs(COST) do
            w["Cound_" .. i] = FText(c[1])
            local icon = asset(c[2])
            if icon then w["Icon_" .. i] = icon end
        end
        w.Translation = { X = 0, Y = 0 }
        w.Scale = { X = 1.25, Y = 1.25 }
        asset(DRAWING)   -- loaded here, so the OnLoaded hook only has to find it
        w:CE_Load_Unload_Images(true)
    end)
end

local function apply(w, tex)
    local style = w.Buton.WidgetStyle
    style.Normal.ResourceObject = tex
    style.Hovered.ResourceObject = tex
    style.Pressed.ResourceObject = tex
    style.Disabled.ResourceObject = tex
    w.Buton:SetStyle(style)   -- writing the brushes alone leaves the old picture on screen
end

-- The entry loads its own picture (the tent) each time the page is shown. Ours can be garbage collected while the notebook is
-- closed, and describe() runs only once per widget, so when it is gone load it again outside the hook, then put it on.
-- The entry in the game's current language. The notebook's widgets live for the whole session and the page-shown hook fires once
-- per entry, so a change of language in the settings is caught here, on main.lua's timer: rename and re-run the page's setup, which
-- copies the name onto the page (proven in game: Russian to Japanese on the live entry).
function M.refresh()
    for _, w in ipairs(FindAllOf("N_Bord_C") or {}) do
        if not w.InProgress and w:GetFullName():find(ENTRY_PATH) and w.BuildingName:ToString() ~= Lang.name() then
            w.BuildingName = FText(Lang.name())
            w:CE_Load_Unload_Images(true)
        end
    end
end

local function draw(w)
    local tex = StaticFindObject(DRAWING)   -- not asset(): no loading inside a hook
    if valid(tex) then apply(w, tex) return end
    Defer.run(function()
        local t = asset(DRAWING)
        if t and valid(w) then apply(w, t) end
    end)
end

local function guarded(what, fn)
    return function(ctx)
        local ok, err = pcall(function()
            local w = ours(ctx)
            if w then fn(w) end
        end)
        if not ok then log(what .. " failed: " .. tostring(err)) end
    end
end

local hooked = false
local function installHooks(startBuild)
    if hooked then return end
    hooked = true
    RegisterHook(N_BORD .. ":CE_Load_Unload_Images", guarded("setup", describe))
    RegisterHook(N_BORD .. ":OnLoaded_6ECF97044EEFAFE1C797538332E0C2F6", guarded("drawing", draw))
    RegisterHook(N_BORD .. ":BndEvt__N_Bord_Buton_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature",
        guarded("click", function() Defer.run(startBuild) end))
    log("hooks installed")
end

-- startBuild(): enter build mode for the stand, called on the game thread when the entry is clicked
-- loader(path): the asset at path, or nil
function M.start(startBuild, loader)
    load = loader
    local install = function()
        local ok, err = pcall(installHooks, startBuild)
        if not ok then hooked = false log("hook install failed: " .. tostring(err)) end
    end
    pcall(NotifyOnNewObject, N_BORD, install)
    if StaticFindObject(N_BORD) ~= nil and valid(StaticFindObject(N_BORD)) then install() end   -- already loaded (hot reload)
end

return M
