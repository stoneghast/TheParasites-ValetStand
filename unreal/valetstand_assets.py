"""Builds /Game/Mods/ValetStand from mods/ValetStand/source: the fibre part meshes, BP_ValetStand (the buildable ghost),
BP_ValetStandStation (the finished, interactive stand: a BP_MPCraftingStation child) and BP_ValetStandWidget (its panel:
16 JSIContainer garment slots). Also writes mods/ValetStand/Scripts/slots.lua (the slot order the Lua harness registers).

Inputs: source/layout.json (from blender/build_valet_stand.py: one entry per part with the game mesh path or our
SM_VS_* path, Blender transform in metres / XYZ Euler degrees), source/SM_VS_*.glb (our meshes), source/SM_VS_AxisTest.glb,
extracted/json/DataTable_Armor.json (ItemIDs per garment type for the slot filters).
Blender -> UE axis map (Anna faces -Y in Blender, +X in UE; Blender +X is her left = UE -Y):  UE = (-y, -x, z) * 100.
The AxisTest import prints its bounds: expect a long arm towards UE +X (200 cm) and a short arm towards UE -Y (100 cm).
Run after valetstand_placeholders.py + bpdump scs-guid (mods/ValetStand/build.ps1 does the whole chain):
  UnrealEditor-Cmd.exe <proj> -ExecutePythonScript=<this file> -unattended -nopause -nosplash -NullRHI
"""
import json
import math
import os
import re
from pathlib import Path
import unreal

EAL = unreal.EditorAssetLibrary
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
BEL = unreal.BlueprintEditorLibrary
MOD = Path(__file__).resolve().parents[3] / "mods" / "ValetStand"
SRC = MOD / "source"
DEST = "/Game/Mods/ValetStand"
BASE = "/Game/BuildingSystem/Blueprints/BuildingBase"
COMP = "/Game/BuildingSystem/Blueprints/Components/ABS_MeshComponent"
HOLLOW_MAT = "/Game/BuildingSystem/Materials/Hollow/BuildingMaterial_OnConstruction"
STAND_YAW = 90.0   # the game's buildables face +Y (placement arrow plane sits at +Y; worn garments in bind pose face +Y too).
                   # Applied ONCE, in blender_to_ue(). Our own FBX parts import with the bare axis map (front on +X), never
                   # with STAND_YAW: in the import AND on the component it turned the form 90 deg against the garments.
MEL = unreal.MaterialEditingLibrary
TEX_SRC = MOD / "textures"
# the woven form's textures (mods/ValetStand/textures; u runs along each strand, see blender/wicker.py)
VS_TEXTURES = {"T_VS_Vine_BC": (True, unreal.TextureCompressionSettings.TC_DEFAULT),
               "T_VS_Vine_N": (False, unreal.TextureCompressionSettings.TC_NORMALMAP),
               "T_VS_Leaf": (True, unreal.TextureCompressionSettings.TC_DEFAULT),
               "T_VS_BookEntry": (True, unreal.TextureCompressionSettings.TC_DEFAULT),   # Scripts/notebook.lua
               "T_VS_Undress": (True, unreal.TextureCompressionSettings.TC_DEFAULT),     # the panel's buttons
               "T_VS_Dress": (True, unreal.TextureCompressionSettings.TC_DEFAULT)}
UI_TEXTURES = ("T_VS_BookEntry", "T_VS_Undress", "T_VS_Dress")
# Byte VALUES of the game's ResourceType enum = position in the enum, NOT the NewEnumeratorN suffix (read live via
# UEnum:ForEachName, 2026-11-06): 0 None, 1 WoodLog, 2 WoodStick, 3 Stone, 4 Brick, 5 Branches, 6 Clay, 7 Rope, ... 25 Motor,
# 26 PlantFibers, 27 TreatedWood. The old table (Stone=1, PlantFibers=25) made the game ask for "Wood Log" and "Motor".
RESOURCE_INDEX = {"WoodLog": 1, "WoodStick": 2, "Stone": 3, "Rope": 7, "PlantFibers": 26}
# Part types paid from the player's inventory instead of carried by hand (BuildingBase.InteractItems reads CustomResourType and matches
# each type's enum name against inventory ItemIDs). Without it "Add" can never fill these parts; Easy Building hides that.
INVENTORY_RESOURCES = ["PlantFibers"]
# M_VS_Vine's look. blender/build_valet_stand.py VINE_* holds the same values: change both together.
VINE_CONTRAST = 1.25
VINE_DARKEN = 0.9
VINE_FRESH_TINT = (0.72, 0.95, 0.5)
VINE_BARE_GAIN = 1.7
VINE_WEATHER_GREY = (1.0, 1.0, 0.95)
VINE_WEATHER_WARM = (0.72, 0.52, 0.34)
VINE_MACRO_UV = 0.23       # the bark again, stretched: light and dark runs that survive at play distance
VINE_MACRO_EXP = 1.6
VINE_MACRO_GAIN = 23.5     # 1 / the texture's mean luminance at that exponent, so the layer adds contrast, not brightness

# --- station + panel (docs/build-system.md §5–§6, §13) ---
REPO = MOD.parents[1]
JIG = "/Game/JigSInventory"
STATION_PARENT = f"{JIG}/Demo/CraftingStation/BP_MPCraftingStation"
WIDGET_PARENT = f"{JIG}/Demo/CraftingStation/Widgets/BP_StationCraftingWidget"
JSIC = f"{JIG}/Jigsaw/Widgets/JSIContainer"
SOULS = f"{JIG}/Jigsaw/Widgets/JSI_Souls"
STRUCT_PATH = f"{JIG}/Jigsaw/Components/Data/S_JigCompContentSettings"
IMG_DIR = f"{JIG}/Jigsaw/Widgets/Images"
ARMOR_JSON = REPO / "extracted" / "json" / "DataTable_Armor.json"
MESH_JSON = REPO / "extracted" / "json" / "DT_EquipmentMeshData.json"   # ItemID -> worn skeletal mesh (+ socket)
STATION_HP = 25.0        # chopping damage before the stand breaks (campfire 0.5, loot box 10)
PROMPT_HEIGHT = 150.0    # the game's prompt widget sits at 67 cm (a table); ours at the shoulder bar
SLOT_PX, SLOT_GAP = 85.0, 6.0
# One row per garment slot, in the order that is (a) the component's ContainersSettings, (b) the widget's registration order
# (Lua mirrors it from slots.lua). The panel layout is LAYOUT below.
# (container name = the player's own container name, JSItemType enumerator of DataTable_Armor rows, slot texture, hover hint)
# Every garment slot the player has except gloves: with no arms on the stand they would float in mid-air.
SLOTS = [
    ("HEAD", 21, "Cap_02", "Headwear"), ("EYE", 22, "Glasses_01", "Glasses"), ("EARWEAR", 24, "T_Earrings", "Earrings"),
    ("MASK", 34, "Mask_01", "Mask"), ("ARMOR", 3, "Armor_01", "Armor"), ("UPPER", 32, "UP_Body_01", "Jacket"),
    ("BRA", 33, "Bra_01", "Bra"), ("BACKPACK", 15, "Backpack_01", "Backpack"),
    ("BELT", 26, "Belt_01", "Belt"), ("LOWER", 23, "Body_02", "Top"), ("PANTS", 5, "Legs_01", "Pants"),
    ("PANTIES", 31, "Panties_01", "Panties"), ("GARTER_BELT", 25, "TX_MW_Garter_Belt", "Garter belt"),
    ("STOCKINGS", 41, "MW_Stockings", "Stockings"), ("BOOTS", 6, "Boots_01", "Boots"), ("ACCESSORIES", 42, "T_Necklace", "Accessories"),
]
EXTRA_IDS = {"LOWER": ["Towel"]}   # mod items that are not in the game's DataTable_Armor (the Towel is a Top-layer garment)
# Panel layout: three columns like the player's own garment screen (BP_MainInventory): head row, jewellery/belt row, then the
# body block in the game's order (bra/top/jacket, garter/pants/armor, panties/stockings/backpack, boots). None leaves a cell empty.
LAYOUT = [
    ["HEAD", "MASK", "EYE"],
    ["EARWEAR", "ACCESSORIES", "BELT"],
    ["BRA", "LOWER", "UPPER"],
    ["GARTER_BELT", "PANTS", "ARMOR"],
    ["PANTIES", "STOCKINGS", "BACKPACK"],
    [None, "BOOTS"],
]
# Scripts/wardrobe.lua hooks these by widget name. (widget name, texture, tooltip, row, column): either side of the boots. The stand's panel is at the
# left of the screen and the player's at the right, so each arrow points the way the clothes go.
BUTTONS = [
    ("VS_Undress", "T_VS_Undress", "Undress: put what you are wearing on the stand", 5, 0),
    ("VS_Dress", "T_VS_Dress", "Dress: wear what is on the stand", 5, 2),
]


def log(*a):
    print("[valetstand]", *a)


# ---------------------------------------------------------------- meshes
def import_mesh(name):
    # FBX through the legacy FbxImportUI path: Interchange (glTF) crashes the headless editor after import (GAME-NOTES)
    src = SRC / (name + ".fbx")
    if not src.exists():
        log("missing", src)
        return None
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", str(src))
    task.set_editor_property("destination_path", DEST)
    task.set_editor_property("destination_name", name)
    task.set_editor_property("automated", True)
    task.set_editor_property("save", True)
    task.set_editor_property("replace_existing", True)
    ui = unreal.FbxImportUI()
    ui.set_editor_property("import_mesh", True)
    ui.set_editor_property("import_as_skeletal", False)
    ui.set_editor_property("import_materials", False)
    ui.set_editor_property("import_textures", False)
    ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_STATIC_MESH)
    ui.static_mesh_import_data.set_editor_property("combine_meshes", True)
    ui.static_mesh_import_data.set_editor_property("auto_generate_collision", False)
    ui.static_mesh_import_data.set_editor_property("convert_scene", True)
    # FBX lands Blender -Y (Anna's front) on UE +Y (SM_VS_AxisTest bounds); yaw -90 turns it to UE +X = the M map in
    # blender_to_ue(), which then adds STAND_YAW on the component, exactly as for the game meshes (sticks, stones)
    ui.static_mesh_import_data.set_editor_property("import_rotation", unreal.Rotator(0.0, 0.0, -90.0))
    ui.static_mesh_import_data.set_editor_property("normal_import_method", unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS)
    # M_VS_Vine reads wicker.py's masks from the vertex colours; set explicitly so they cannot be dropped on import
    ui.static_mesh_import_data.set_editor_property("vertex_color_import_option", unreal.VertexColorImportOption.REPLACE)
    task.set_editor_property("options", ui)
    TOOLS.import_asset_tasks([task])
    sm = EAL.load_asset(f"{DEST}/{name}")
    if sm is None:
        # Interchange may name the asset after the glTF node; pick up whatever landed in DEST that we did not know
        log("import of", name, "produced no asset at the expected path")
        return None
    if name.startswith("SM_VS_Fibre_"):
        # slots come from the Blender material names: M_VS_Vine (bark, vertex-colour driven) and M_VS_Leaf (masked card)
        mats = []
        for slot in sm.get_editor_property("static_materials"):
            s = unreal.StaticMaterial()
            s.set_editor_property("material_slot_name", slot.material_slot_name)
            s.set_editor_property("material_interface", WICKER_MATS.get(str(slot.material_slot_name), WICKER_MATS["M_VS_Vine"]))
            mats.append(s)
        sm.set_editor_property("static_materials", mats or [unreal.StaticMaterial()])
        EAL.save_asset(f"{DEST}/{name}", only_if_is_dirty=False)
    b = sm.get_bounding_box()
    log(name, "bounds min", b.min, "max", b.max, "verts", sm.get_num_vertices(0))
    if name == "SM_VS_AxisTest" and not (b.max.x > 190 and b.min.y < -90 and b.max.y < 30):
        raise RuntimeError(f"axis map broken: AxisTest front arm must lie on UE +X (200 cm), left arm on -Y (100 cm); got {b.min} .. {b.max}")
    return sm


def import_wicker_textures():
    out = {}
    for name, (srgb, comp) in VS_TEXTURES.items():
        src = TEX_SRC / (name + ".png")
        if not src.exists():
            raise RuntimeError(f"missing texture {src}")
        task = unreal.AssetImportTask()
        for k, v in (("filename", str(src)), ("destination_path", DEST), ("destination_name", name),
                     ("automated", True), ("save", True), ("replace_existing", True)):
            task.set_editor_property(k, v)
        TOOLS.import_asset_tasks([task])
        t = EAL.load_asset(f"{DEST}/{name}")
        t.set_editor_property("srgb", srgb)
        t.set_editor_property("compression_settings", comp)
        if name == "T_VS_Leaf" or name in UI_TEXTURES:
            t.set_editor_property("compression_no_alpha", False)
        if name in UI_TEXTURES:   # sharp from the first frame (a streamed texture starts blurry), at the 256 the notebook entry's brushes declare
            t.set_editor_properties({"lod_group": unreal.TextureGroup.TEXTUREGROUP_UI, "never_stream": True,
                                     "mip_gen_settings": unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS, "max_texture_size": 256})
        EAL.save_asset(f"{DEST}/{name}", only_if_is_dirty=False)
        out[name] = t
        log("texture:", name, "sRGB", srgb)
    return out


def build_wicker_materials(tex):
    """M_VS_Vine: bark texture along each strand, tinted by the vertex colour channels blender/wicker.py writes
    (R bare pale wood at snaps/tight turns, G freshness = green tint, B weathering, A tone). M_VS_Leaf: masked two-sided card.
    The VINE_* values match blender/build_valet_stand.py: change both together."""
    def new_material(name):
        if EAL.does_asset_exist(f"{DEST}/{name}"):
            EAL.delete_asset(f"{DEST}/{name}")
        return TOOLS.create_asset(name, DEST, unreal.Material, unreal.MaterialFactoryNew())

    def link(m, a, out, b, inp):
        if not MEL.connect_material_expressions(a, out, b, inp):
            raise RuntimeError(f"{m.get_name()}: cannot connect {out!r} -> {inp!r}")

    def sample(m, t, sampler, x, y):
        e = MEL.create_material_expression(m, unreal.MaterialExpressionTextureSample, x, y)
        e.set_editor_property("texture", t)
        e.set_editor_property("sampler_type", sampler)
        return e

    def const3(m, rgb, x, y):
        e = MEL.create_material_expression(m, unreal.MaterialExpressionConstant3Vector, x, y)
        e.set_editor_property("constant", unreal.LinearColor(*rgb, 1.0))
        return e

    def scalar(m, v, x, y):
        e = MEL.create_material_expression(m, unreal.MaterialExpressionConstant, x, y)
        e.set_editor_property("r", v)
        return e

    def op(m, cls, a, b, x, y, alpha=None):
        e = MEL.create_material_expression(m, cls, x, y)
        link(m, a[0], a[1], e, "A"); link(m, b[0], b[1], e, "B")
        if alpha is not None:
            link(m, alpha[0], alpha[1], e, "Alpha")
        return e

    S = unreal.MaterialSamplerType
    vine = new_material("M_VS_Vine")
    bc_raw = sample(vine, tex["T_VS_Vine_BC"], S.SAMPLERTYPE_COLOR, -1600, -200)
    nrm = sample(vine, tex["T_VS_Vine_N"], S.SAMPLERTYPE_NORMAL, -1200, 200)
    vc = MEL.create_material_expression(vine, unreal.MaterialExpressionVertexColor, -1200, 500)
    contrast = MEL.create_material_expression(vine, unreal.MaterialExpressionPower, -1400, -200)
    link(vine, bc_raw, "RGB", contrast, "Base")
    link(vine, scalar(vine, VINE_CONTRAST, -1600, 0), "", contrast, "Exp")
    dark = op(vine, unreal.MaterialExpressionMultiply, (contrast, ""), (scalar(vine, VINE_DARKEN, -1400, 0), ""), -1200, -200)
    uvs = MEL.create_material_expression(vine, unreal.MaterialExpressionTextureCoordinate, -2000, -600)
    uvs.set_editor_property("u_tiling", VINE_MACRO_UV)
    uvs.set_editor_property("v_tiling", VINE_MACRO_UV)
    macro = sample(vine, tex["T_VS_Vine_BC"], S.SAMPLERTYPE_COLOR, -1800, -600)
    link(vine, uvs, "", macro, "UVs")
    macro_pow = MEL.create_material_expression(vine, unreal.MaterialExpressionPower, -1600, -600)
    link(vine, macro, "RGB", macro_pow, "Base")
    link(vine, scalar(vine, VINE_MACRO_EXP, -1800, -400), "", macro_pow, "Exp")
    macro_grey = MEL.create_material_expression(vine, unreal.MaterialExpressionDesaturation, -1400, -600)
    link(vine, macro_pow, "", macro_grey, "")
    macro_lit = op(vine, unreal.MaterialExpressionMultiply, (macro_grey, ""), (scalar(vine, VINE_MACRO_GAIN, -1400, -400), ""), -1200, -500)
    bc = op(vine, unreal.MaterialExpressionMultiply, (dark, ""), (macro_lit, ""), -1000, -300)
    green =op(vine, unreal.MaterialExpressionMultiply, (bc, ""), (const3(vine, VINE_FRESH_TINT, -1000, -50), ""), -800, -100)
    fresh = op(vine, unreal.MaterialExpressionLinearInterpolate, (bc, ""), (green, ""), -600, -200, alpha=(vc, "G"))
    pale = op(vine, unreal.MaterialExpressionMultiply, (bc, ""), (scalar(vine, VINE_BARE_GAIN, -800, 50), ""), -600, 0)
    bare = op(vine, unreal.MaterialExpressionLinearInterpolate, (fresh, ""), (pale, ""), -400, -100, alpha=(vc, "R"))
    weather = op(vine, unreal.MaterialExpressionLinearInterpolate, (const3(vine, VINE_WEATHER_GREY, -600, 200), ""),
                 (const3(vine, VINE_WEATHER_WARM, -600, 350), ""), -400, 200, alpha=(vc, "B"))
    aged = op(vine, unreal.MaterialExpressionMultiply, (bare, ""), (weather, ""), -200, 0)
    toned = op(vine, unreal.MaterialExpressionMultiply, (aged, ""), (vc, "A"), 0, 0)
    MEL.connect_material_property(toned, "", unreal.MaterialProperty.MP_BASE_COLOR)
    MEL.connect_material_property(nrm, "RGB", unreal.MaterialProperty.MP_NORMAL)
    MEL.connect_material_property(scalar(vine, 0.85, -200, 200), "", unreal.MaterialProperty.MP_ROUGHNESS)
    MEL.recompile_material(vine)

    leaf = new_material("M_VS_Leaf")
    leaf.set_editor_property("blend_mode", unreal.BlendMode.BLEND_MASKED)
    leaf.set_editor_property("two_sided", True)
    lt = sample(leaf, tex["T_VS_Leaf"], S.SAMPLERTYPE_COLOR, -600, 0)
    MEL.connect_material_property(lt, "RGB", unreal.MaterialProperty.MP_BASE_COLOR)
    MEL.connect_material_property(lt, "A", unreal.MaterialProperty.MP_OPACITY_MASK)
    MEL.connect_material_property(scalar(leaf, 0.6, -300, 200), "", unreal.MaterialProperty.MP_ROUGHNESS)
    MEL.recompile_material(leaf)
    for n in ("M_VS_Vine", "M_VS_Leaf"):
        EAL.save_asset(f"{DEST}/{n}", only_if_is_dirty=False)
    log("materials: M_VS_Vine, M_VS_Leaf")
    return {"M_VS_Vine": vine, "M_VS_Leaf": leaf}


# ---------------------------------------------------------------- transform conversion
def blender_to_ue(loc_m, rot_deg, scale):
    """Blender (m, right-handed, faces -Y) -> UE (cm, left-handed, faces +X): UE = (-y, -x, z)."""
    rx, ry, rz = (math.radians(a) for a in rot_deg)
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    # Blender XYZ Euler = Rz * Ry * Rx
    Rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    Ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    Rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    R = mul(Rz, mul(Ry, Rx))
    M = [[0, -1, 0], [-1, 0, 0], [0, 0, 1]]          # M == M^-1
    Rue = mul(M, mul(R, M))
    # bake the stand yaw (about UE Z) so the stand faces the game's +Y front
    ya = math.radians(STAND_YAW); ca, sa = math.cos(ya), math.sin(ya)
    Yaw = [[ca, -sa, 0], [sa, ca, 0], [0, 0, 1]]
    Rue = mul(Yaw, Rue)
    # UE matrix is row-major with basis vectors as rows: row i = image of UE axis i = (Rue column i)
    rows = [[Rue[0][i], Rue[1][i], Rue[2][i], 0.0] for i in range(3)]
    tx, ty = -loc_m[1] * 100.0, -loc_m[0] * 100.0
    t = [tx * ca - ty * sa, tx * sa + ty * ca, loc_m[2] * 100.0]
    m = unreal.Matrix(rows[0], rows[1], rows[2], [t[0], t[1], t[2], 1.0])
    xf = m.transform()
    # scale: Blender (sx, sy, sz) along Blender axes -> UE axes (sy, sx, sz) on the rotated frame; keep per-axis
    xf.scale3d = unreal.Vector(scale[1], scale[0], scale[2])
    return xf


# ---------------------------------------------------------------- blueprint
def build_ghost(parts):
    path = f"{DEST}/BP_ValetStand"
    if EAL.does_asset_exist(path):
        EAL.delete_asset(path)
    base = EAL.load_asset(BASE)
    comp_bp = EAL.load_asset(COMP)
    f = unreal.BlueprintFactory()
    f.set_editor_property("parent_class", base.generated_class())
    bp = TOOLS.create_asset("BP_ValetStand", DEST, unreal.Blueprint, f)
    BEL.compile_blueprint(bp)
    sds = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    root_handles = sds.k2_gather_subobject_data_for_blueprint(bp)
    root = root_handles[0]
    comp_class = comp_bp.generated_class()
    hollow = EAL.load_asset(HOLLOW_MAT)
    made = []
    for p in parts:
        params = unreal.AddNewSubobjectParams()
        params.set_editor_property("parent_handle", root)
        params.set_editor_property("new_class", comp_class)
        params.set_editor_property("blueprint_context", bp)
        handle, fail = sds.add_new_subobject(params)
        if not fail.is_empty():
            raise RuntimeError(f"add_new_subobject {p['part']}: {fail}")
        sds.rename_subobject(handle, unreal.Text(p["part"]))
        data = sds.k2_find_subobject_data_from_handle(handle)
        comp = unreal.SubobjectDataBlueprintFunctionLibrary.get_object(data)
        mesh = EAL.load_asset(p["mesh"])   # game meshes exist as placeholders (valetstand_placeholders.py)
        if mesh is None:
            raise RuntimeError("mesh not found: " + p["mesh"])
        soft = unreal.SoftObjectPath(p["mesh"] + "." + p["mesh"].rsplit("/", 1)[-1])
        comp.set_editor_property("ResourceType", RESOURCE_INDEX[p["resource"]])
        comp.set_editor_property("TotalAmount", 1)
        for prop in ("HollowMesh", "RealMesh"):
            try:
                comp.set_editor_property(prop, soft)
            except Exception:  # placeholder declared a hard reference
                comp.set_editor_property(prop, mesh)
        comp.set_editor_property("static_mesh", mesh)
        xf = blender_to_ue(p["location_m"], p["rotation_deg"], p["scale"])
        comp.set_editor_property("relative_location", xf.translation)
        comp.set_editor_property("relative_rotation", xf.rotation.rotator())
        comp.set_editor_property("relative_scale3d", xf.scale3d)
        log(p["part"], "loc", xf.translation, "rot", xf.rotation.rotator(), "scale", xf.scale3d)
        made.append(p["part"])
    BEL.compile_blueprint(bp)
    # class defaults LAST: a compile regenerates the CDO from the Blueprint, which dropped the first build's BuildingName
    cdo = unreal.get_default_object(bp.generated_class())
    cdo.set_editor_property("BuildingName", unreal.Text("Valet Stand"))
    cdo.set_editor_property("bInteract Building", True)
    cdo.set_editor_property("CountDurability", 25.0)   # like the Meat Dryer; InitIntegrity → Current 25, Destroy 12.5 (0 = born destroyed)
    inventory_types = [RESOURCE_INDEX[r] for r in INVENTORY_RESOURCES]
    cdo.set_editor_property("CustomResourType", inventory_types)
    EAL.save_asset(path, only_if_is_dirty=False)
    cdo = unreal.get_default_object(bp.generated_class())
    log("CDO BuildingName:", cdo.get_editor_property("BuildingName"), "bInteract:", cdo.get_editor_property("bInteract Building"), "CountDurability:", cdo.get_editor_property("CountDurability"))
    saved_types = list(cdo.get_editor_property("CustomResourType"))
    if saved_types != inventory_types:
        raise RuntimeError(f"CustomResourType did not stick: {saved_types} != {inventory_types}")
    log("CDO CustomResourType:", saved_types)
    log("BP_ValetStand parts:", made)
    return bp


# ---------------------------------------------------------------- station panel
def armor_ids_by_type():
    """ItemIDs of DataTable_Armor grouped by the JSItemType enumerator number (the slot filters)."""
    rows = next(e for e in json.loads(ARMOR_JSON.read_text(encoding="utf-8")) if e.get("Type") == "DataTable")["Rows"]
    by = {}
    for item_id, row in rows.items():
        t = next((v for k, v in row.items() if k.startswith("Type_")), "")
        by.setdefault(int(t.rsplit("NewEnumerator", 1)[-1]), []).append(item_id)
    return by


def build_widget():
    """WidgetBlueprint child of the station widget placeholder: a CanvasPanel root (created by the factory from
    DefaultEditor.ini's DefaultRootWidget — Python cannot set WidgetTree.RootWidget) holding one JSIContainer per slot."""
    name = "BP_ValetStandWidget"
    f = unreal.WidgetBlueprintFactory()
    f.set_editor_property("parent_class", EAL.load_asset(WIDGET_PARENT).generated_class())
    wb = TOOLS.create_asset(name, DEST, unreal.WidgetBlueprint, f)
    tree = unreal.find_object(wb, "WidgetTree")
    root = next((w for w in unreal.ObjectIterator(unreal.PanelWidget) if w.get_outer() == tree), None)
    if root is None:
        raise RuntimeError("the widget has no root panel: Config/DefaultEditor.ini must set UMGEditorProjectSettings.DefaultRootWidget")
    jsic = EAL.load_asset(JSIC).generated_class()
    ids_by_type = armor_ids_by_type()
    for i, (slot_name, jstype, image, hint) in enumerate(SLOTS):
        w = unreal.new_object(jsic, outer=tree, name=slot_name)   # bIsVariable defaults to true: the slot becomes the class property <slot_name>
        ids = sorted(ids_by_type.get(jstype, []) + EXTRA_IDS.get(slot_name, []))
        w.set_editor_properties({
            "ContainerType": 1, "NumberOfColumns": 1, "NumberOfRows": 1, "MaxEquippedStack": 1,
            "SlotSize": unreal.Vector2D(SLOT_PX, SLOT_PX), "EquippedImageMatchesContainerSize?": True,
            "SlotImage": EAL.load_asset(f"{IMG_DIR}/{image}"), "HideSlotImageWhenEquipped?": True,
            "OnlySupportTheseIDs": ids, "CustomHintsText": unreal.Text(hint),
            # the campfire's single-item slot settings (docs §5.2): no splitting/stacking/blind adds/context menu on a garment slot
            "AllowDropToGround": False, "AutoPerformSplit": False, "AutoPerformStack": False, "AllowBlindAddItemToContainer?": False,
            "TriggerItemOverItemIfCannotAddToContainer": False, "AllowContextMenu": False, "AllowStackingEquippedItem": False,
        })
        slot = root.add_child(w)
        row, col = next((r, c) for r, names in enumerate(LAYOUT) for c, n in enumerate(names) if n == slot_name)
        slot.set_position(unreal.Vector2D(col * (SLOT_PX + SLOT_GAP), row * (SLOT_PX + SLOT_GAP)))
        slot.set_size(unreal.Vector2D(SLOT_PX, SLOT_PX))
        log(f"slot {slot_name:12} type {jstype:2} {len(ids):2} ids: {', '.join(ids[:4])}{', …' if len(ids) > 4 else ''}")
    souls = EAL.load_asset(SOULS).generated_class()
    for name, image, tip, row, col in BUTTONS:
        w = unreal.new_object(souls, outer=tree, name=name)
        w.set_editor_properties({"Image": EAL.load_asset(f"{DEST}/{image}"), "Image Size": unreal.Vector2D(SLOT_PX, SLOT_PX), "tool_tip_text": unreal.Text(tip)})
        slot = root.add_child(w)
        slot.set_position(unreal.Vector2D(col * (SLOT_PX + SLOT_GAP), row * (SLOT_PX + SLOT_GAP)))
        slot.set_size(unreal.Vector2D(SLOT_PX, SLOT_PX))
    BEL.compile_blueprint(wb)
    EAL.save_asset(f"{DEST}/{name}", only_if_is_dirty=False)
    return wb


def struct_member_names():
    """Authored member name -> real property name (`ContainerName_2_<GUID>`) of the user-defined struct. UE 5.7 Python never
    wraps user-defined structs (PyWrapperTypeRegistry: "todo: allow generation of Blueprint generated structs"): instances only
    exist as plain StructBase, which finds members by their REAL names only, and Python cannot list a struct's fields — so the
    names come from the struct package's name table."""
    uasset = unreal.Paths.convert_relative_path_to_full(
        unreal.Paths.project_content_dir() + STRUCT_PATH.removeprefix("/Game/") + ".uasset")
    found = {m.group(1).decode(): m.group(0).decode()
             for m in re.finditer(rb"(ContainerName|Columns|Rows)_\d+_[0-9A-F]{32}", Path(uasset).read_bytes())}
    if len(found) != 3:
        raise RuntimeError(f"S_JigCompContentSettings members not found in {uasset}: {found}")
    return found


def set_container_settings(jig):
    """ContainersSettings on the station's BP_JigMultiplayer override: one row per garment slot (-1 x -1 = one equip-to slot).
    Rows are made by resizing the component's own array (default-constructed elements of the real struct type) and filled
    through the real member names (see struct_member_names). Skipped, with a log line, when the hand-made struct is absent."""
    if not EAL.does_asset_exist(STRUCT_PATH):
        log("S_JigCompContentSettings MISSING: the station ships without ContainersSettings (no containers at runtime)")
        return
    names = struct_member_names()
    rows = jig.get_editor_property("ContainersSettings")
    rows.resize(len(SLOTS))
    for i, (slot_name, *_) in enumerate(SLOTS):
        row = rows[i]
        row.set_editor_property(names["ContainerName"], slot_name)
        row.set_editor_property(names["Columns"], -1)
        row.set_editor_property(names["Rows"], -1)
        rows[i] = row
    jig.set_editor_property("ContainersSettings", rows)
    back = jig.get_editor_property("ContainersSettings")
    log("ContainersSettings:", len(back), "rows:", ", ".join(str(r.get_editor_property(names["ContainerName"])) for r in back))


def inherited_template(bp, var_name):
    """The child's own override template for an inherited SCS component (created on first access, recorded in the
    InheritableComponentHandler under the parent node's GUID — hence bpdump scs-guid on the placeholder)."""
    sds = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    lib = unreal.SubobjectDataBlueprintFunctionLibrary
    for h in sds.k2_gather_subobject_data_for_blueprint(bp):
        data = sds.k2_find_subobject_data_from_handle(h)
        if str(lib.get_variable_name(data)) == var_name:
            tmpl = lib.get_object_for_blueprint(data, bp)
            if tmpl is None:
                raise RuntimeError(f"no override template for inherited component {var_name}")
            return tmpl
    raise RuntimeError(f"inherited component {var_name} not found on {bp.get_name()}")


def build_station(parts, widget_bp):
    """BP_MPCraftingStation child = the finished stand: the 14 part meshes as plain StaticMeshComponents (same transforms as the
    ghost's parts), the inherited BP_JigMultiplayer pointed at our panel with one container per garment slot, the parent's cube
    mesh cleared and the prompt widget raised. Spawned by the Lua harness when the ghost's BuiltFinished fires."""
    name = "BP_ValetStandStation"
    f = unreal.BlueprintFactory()
    f.set_editor_property("parent_class", EAL.load_asset(STATION_PARENT).generated_class())
    bp = TOOLS.create_asset(name, DEST, unreal.Blueprint, f)
    BEL.compile_blueprint(bp)
    sds = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    root = sds.k2_gather_subobject_data_for_blueprint(bp)[0]
    for p in parts:
        params = unreal.AddNewSubobjectParams()
        params.set_editor_property("parent_handle", root)
        params.set_editor_property("new_class", unreal.StaticMeshComponent)
        params.set_editor_property("blueprint_context", bp)
        handle, fail = sds.add_new_subobject(params)
        if not fail.is_empty():
            raise RuntimeError(f"add_new_subobject {p['part']}: {fail}")
        sds.rename_subobject(handle, unreal.Text(p["part"]))
        comp = unreal.SubobjectDataBlueprintFunctionLibrary.get_object(sds.k2_find_subobject_data_from_handle(handle))
        xf = blender_to_ue(p["location_m"], p["rotation_deg"], p["scale"])
        comp.set_editor_properties({"static_mesh": EAL.load_asset(p["mesh"]), "relative_location": xf.translation,
                                    "relative_rotation": xf.rotation.rotator(), "relative_scale3d": xf.scale3d})
    jig = inherited_template(bp, "BP_JigMultiplayer")
    jig.set_editor_property("InventoryWidgetClass", widget_bp.generated_class())
    set_container_settings(jig)
    inherited_template(bp, "StaticMesh").set_editor_property("static_mesh", None)
    inherited_template(bp, "Widget").set_editor_property("relative_location", unreal.Vector(0.0, 0.0, PROMPT_HEIGHT))
    BEL.compile_blueprint(bp)
    cdo = unreal.get_default_object(bp.generated_class())
    cdo.set_editor_properties({"ContainerName": unreal.Text("Valet Stand"), "HP": STATION_HP})
    EAL.save_asset(f"{DEST}/{name}", only_if_is_dirty=False)
    cdo = unreal.get_default_object(bp.generated_class())
    log("station CDO ContainerName:", cdo.get_editor_property("ContainerName"), "HP:", cdo.get_editor_property("HP"),
        "containers:", len(inherited_template(bp, "BP_JigMultiplayer").get_editor_property("ContainersSettings")))
    return bp


def write_slots_lua():
    """The slot order for the Lua harness (it registers the panel's JSIContainers with the component in this order)."""
    path = MOD / "Scripts" / "slots.lua"
    lines = ["-- GENERATED by ue/TheParasites/Scripts/valetstand_assets.py from SLOTS: the station's container / panel slot order.",
             "return {"] + [f'    "{s[0]}",' for s in SLOTS] + ["}", ""]
    path.write_text("\n".join(lines), encoding="utf-8")
    log("wrote", path)


def write_garments_lua():
    """ItemID -> the skeletal mesh the game puts on Anna for it (DT_EquipmentMeshData.EquipSkel) and, for socket-mounted items
    (hats, glasses, backpacks), the body socket (EquipSocket) and the transform relative to it (SoketLocation_Backpack, which
    BP_JigCharacter applies after attaching; it varies per item). The stand shows each slotted garment with exactly that mesh."""
    rows = next(e for e in json.loads(MESH_JSON.read_text(encoding="utf-8")) if e.get("Type") == "DataTable")["Rows"]
    def field(row, name):
        return next((v for k, v in row.items() if re.fullmatch(rf"{name}_\d+_[0-9A-F]{{32}}", k)), None)   # not EquipSocket_Chest
    def vec(v, axes="XYZ"):
        return "{ " + ", ".join(f"{a} = {v[a]:.6f}" for a in axes) + " }"
    lines = ["-- GENERATED by ue/TheParasites/Scripts/valetstand_assets.py from extracted/json/DT_EquipmentMeshData.json:",
             "-- ItemID = { mesh = <SkeletalMesh object path>, socket = <body socket> or nil, xf = <FTransform relative to the socket> or nil }",
             "return {"]
    n = 0
    for item_id, row in sorted(rows.items()):
        mesh = (field(row, "EquipSkel") or {}).get("AssetPathName", "")
        if not mesh:
            continue
        socket = field(row, "EquipSocket")
        sock = ""
        if socket and socket != "None":
            xf = field(row, "SoketLocation_Backpack")
            sock = (f', socket = "{socket}", xf = {{ Rotation = {vec(xf["Rotation"], "XYZW")}, '
                    f'Translation = {vec(xf["Translation"])}, Scale3D = {vec(xf["Scale3D"])} }}')
        lines.append(f'    ["{item_id}"] = {{ mesh = "{mesh}"{sock} }},')
        n += 1
    lines += ["}", ""]
    path = MOD / "Scripts" / "garments.lua"
    path.write_text("\n".join(lines), encoding="utf-8")
    log("wrote", path, n, "garments")


# UE 5.7 routes FBX through Interchange, whose post-import Content Browser sync asserts headless; use the legacy FBX importer
unreal.SystemLibrary.execute_console_command(None, "Interchange.FeatureFlags.Import.FBX 0")
log("Interchange FBX feature flag off")
layout = json.loads((SRC / "layout.json").read_text(encoding="utf-8"))
if EAL.does_directory_exist(DEST):
    log("clearing", DEST, EAL.delete_directory(DEST))
WICKER_MATS = build_wicker_materials(import_wicker_textures())
import_mesh("SM_VS_AxisTest")
for name in sorted({p["mesh"].rsplit("/", 1)[-1] for p in layout["parts"] if p["mesh"].startswith("/Game/Mods/")}):
    import_mesh(name)
build_ghost(layout["parts"])
widget = build_widget()
build_station(layout["parts"], widget)
write_slots_lua()
write_garments_lua()
print("SAVED:", EAL.save_directory(DEST, only_if_is_dirty=False, recursive=True))
for p in EAL.list_assets(DEST, recursive=True, include_folder=False):
    print("ASSET:", p, str(EAL.find_asset_data(p).asset_class_path.asset_name))
print("VALETSTAND_ASSETS_DONE")
