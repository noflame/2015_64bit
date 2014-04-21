/*
  
Render to Texture Dialog

Revision History:
	02/06/02 - Kells Elmquist, discreet3d

	07/11/03 - Larry Minton, discreet3d
				TODO: add detection of deleted Unwrap_UVW on working nodes. Now have broadcast on del mod

	08/19/03- PFB - removed hardcoded access to the 3dsmax.ini file. Replaced with (GetMAXIniFile())	

	08/23/03 - LAM - disable radiosity recalculation after first render

	10 dec 2003, Pierre-Felix Breton, 
               added product switcher: this macroscript file can be shared with all Discreet products

	18 fevrier 2004, Pierre-Felix Breton
		cleaned messageboxes to say "Render to Texture" in the title

	24 apr 2004, Larry Minton 
		Normal Map generator additions
		
	21 may 2004, Larry Minton
		gNormal handling

	10 jun 2004, Larry Minton
		SO handling started
	
	30 nov 2004 Will Stiefel
		hid Projection Mapping Group when app=VIZ
		
	10 jan 2005 Larry Minton
		added handling for XRefObjects whose supertype is Shape.
		
	13 dec 2005 Larry Minton
		when doing net render, update bake element file names before doing submit.

	18 Oct 2005 Larry Minton
		restored non-square output
	
	April - May 2006 Chris P Johnson
		Took out activeX controls and inserted .NET controls. 
		
	March 2007 Larry Minton
		Added object presets
*/
-------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------
macroScript BakeDialog
enabledIn:#("max", "viz") --pfb: 2003.12.11 added product switch
ButtonText:"Render To Texture..."
category:"Render"
internalCategory: "Render" 
toolTip:"Render to Texture Dialog Toggle"
(

local	_debug = false -- true -- X
local	_debug2 = false -- true -- X
local	_trackMemory = false -- true -- X

-- these control behaviour of the dialog, and can be changed statically by the user
local	allowControlDisable = false			-- set to true to disable selected element UI controls when element is disabled

local	showCommonElementsOnly = false		-- set to true to show only elements present on all working objects

local	canBakeShapes = true 				-- set to false to disallow baking of shape objects

local	autoUpdateTargetMapSlotName = true	-- set to true to automatically update target slot name on elements if current 
											-- slot name is no longer valid due to change in target material. new slot name 
											-- taken from ini file. Default mappings dynamically defined based on first time 
											-- slot name is specified for combo of element type and material type

local	wipeTextureMapsOnBake = false -- set to true to delete all texturemaps in baked mtl during bake

local	alwaysCreateNewBakeMaterial = false -- set to true to always copy orig mtl to bake mtl during bake

local	use_all_mapping_channels = true		-- set to false to use only Unwrap_UVW generated mapping channels

local	use_all_Unwrap_UVWs = true -- set to false to only consider Unwrap_UVWs named 'Automatic Flatten UVs' as valid channels

local allow_manual_unwrap_when_autounwrap_off = false -- set to true to create Unwrap_UVWs when click on "Unwrap Only" even if auto unwrapping turned off

local	defaultMtlShader = #blinn -- shader type to use for new standard materials

local	defaultFileType = ".tga" -- default bitmap file extension 

local	mapPresets = #([128,128],[256,256],[512,512],[768,768],[1024,1024],[2048,2048]) -- NxM map size presets - array size must be 6

local skip_DX9_materials = true -- productAppID != #max  -- set to true to skip DX9 materials as new baked output materials
                                                   -- Skip DX9 materials, except in MAX   

local	autoDeleteExistingUnwraps = true 	-- if true, existing Automatic Flatten unwrap modifiers above "used" unwraps are deleted. Script walks down the
											-- modifier stack looking for Automatic Flatten unwrap modifiers. Each Automatic Flatten unwrap modifiers stores the
											-- map channel and whether it is an object or subObject level unwrap. If the modifier's channel doesn't match the 
											-- desired object map channel and the mod is an object level unwrap, or the channel doesn't match the desired subObject
											-- map channel and the mod is an subObject level unwrap, and a matching modifier for the modifier's object/subObj level
											-- wasn't found higher in the stack, the modifier is deleted.

local	set_selfIllum_to_100_if_CompleteMap_or_LightMap = false -- if true, when creating new mtl to place output in, set selfIllum to 100 if baking 
																-- a completemap or lightmap 

local	allow_duplicate_elements = true		-- set to true to allow duplicate element classes on an object

-- following are not to be changed by user
local	RTT_MtlName_AppData_Index   = 0x41dd73d5 -- used to store data on the material while creating shell materials. Using 5 indices starting at this value
local	RTT_UnwrapMod_AppData_Index = 0x41dd73d5 -- used to store data on the unwrap modifier. Using 1 index starting at this value. 
local	RTT_SceneData_AppData_Index = 0x41dd73d5 -- used to store data on the scene root node. Using 8 indices starting at this value. 

local	gNormalSlot1Name = "normal_map"
local	gNormalSlot2Name = "bump_map"

-------------------------------------------------------------------------------------------------

-- these are the globals
global gTextureBakeDialog	-- the shell holds one instance of each of the other rolloups
struct RTT_data_struct 
(
	overwriteFilesOk,		-- 0 == no overWrite, 1 == ok to overwrite, 2 == ok & not again
	FileOutput_FileType, 	-- output file extension
	FileOutput_FilePath, 	-- output path
	
	AutoFlatten_Obj_On, 
	AutoFlatten_Spacing,
	AutoFlatten_ThresholdAngle,
	AutoFlatten_Rotate,
	AutoFlatten_FillHoles,
	AutoFlatten_Obj_MapChannel,
	
	AutoFlatten_SubObj_On, 
	AutoFlatten_SubObj_MapChannel,
	
	AutoSize_SizeMin,
	AutoSize_SizeMax,
	AutoSize_SizeScale,
	AutoSize_SizePowersOf2,
	
	Renderer_DisplayFB,
	Renderer_NetworkRender,
	Renderer_SkipExistingFiles,
	
	OutputMapSize_AutoMapSize,
	OutputMapSize_Width,
	OutputMapSize_Height,
	
	Materials_RenderToFilesOnly,
	Materials_MapDestination,
	Materials_DuplicateSourceOrCreateNew,

	rendererErrorDisplayed, 	-- true if "renderer doesn't support texture baking" warning displayed. Set to true to not display warning
	netRenderErrorDisplayed,		-- true if "backburner not installed" warning displayed. Set to true to not display warning
	
	pmodInterface, -- used in filter for adding projection mod targets
	projectionOptionsPropsRO, -- Projection Options rollout
	selectedObjectPropsRO, -- Objects To Bake rollout
	ignoreModStackChanges, -- if true, ignore mod stack change callbacks

	exposureControlOK,		-- 0 == no render due to exposure control, 1 == ok to render, 2 == ok & not again

	emptyTargetsOk,		-- 0 == missing targets not ok, 1 == missing targets ok, 2 == missing targets ok & not again
	
	loadObjectPresetOk,		-- 0 == don't load object preset, 1 == ok - load object preset, 2 == ok & not again
	loadObjectPresetProjModOk	-- 0 == don't load object preset with proj mod, 1 == ok - load object preset with proj mod, 2 == ok & not again
)

global RTT_data		-- initialized at first execution

-- the main rollouts
local	commonBakeProps 
local	selectedObjectProps
local	selectedElementProps
local	bakedMtlProps
local	autoUnwrapMappingProps
local projectionOptionsProps

-- various object lists
local	selectedObjects = #() -- the selected objects. Contains nodes
local	displayedBakableObjects = #() -- the selected objects that are bakable. Contains bakableObjStruct instances
local	workingObjects = #() -- the current working objects. Contains bakableObjStruct instances

-- displayed bake element data
local	selectedElement -- currently selected effect if 1 and only 1, undefined otherwise
local	selectedElementIndex = 0 -- which entry in commonElements we are displaying data for
-- IMPORTANT, .NET arrays are zero based
local	selectedObjectLVIndex = -1 -- which entry in objects ListView we are displaying data for. -1 means no selection.
local	selectedElementLVIndex = -1 -- which entry in elements ListView we are displaying data for. -1 means no selection.

local	commonElements = #( ) -- array of array of bake elements with common name across working objects
local	commonElementsTargIndet = #{} -- bitarray specifying whether corresponding commonElements have indeterminate target

local	ignoreSelectionUpdates = false -- flag to ignore selection updates because a temp selection change is being made
local	ignoreMtlUpdates = false -- flag to ignore material updates because a bake is being performed

local	curBM = undefined -- the current bitmap being displayed during render

local	newBakedMtlInstance -- instances of this material will be used as new baked material. Initialized in bakedMtlProps
local	newBakedMtlTargetMapNames-- will contain the target map names for newBakedMtlInstance
local	newNodeMtlInstance -- instances of this material will be used as new node material when none exists. Initialized in gTextureBakeDialog
local	newNodeMtlTargetMapNames -- will contain the target map names for newNodeMtlInstance

local	overwriteFileName = "" -- filename used by fileOverwriteBox rollout
local	objectPresetFileName = "" -- filename used by LoadPresetOKBox rollout

--local	updateFileNames  -- stores element file names for setting element file name after rendering a sequence.

local	autoUnwrapChannel_Obj -- Object level Auto Unwrap Mapping channel. Initialized in autoUnwrapMappingProps
local	doAutoUnwrap_Obj -- true when Auto Unwrap Mapping turned on, false otherwise. Initialized in autoUnwrapMappingProps
local	autoUnwrapChannel_SubObj -- Subobject level Auto Unwrap Mapping channel. Initialized in autoUnwrapMappingProps
local	doAutoUnwrap_SubObj -- true when Auto Unwrap Mapping turned on, false otherwise. Initialized in autoUnwrapMappingProps

local	renderPresetFiles = #() -- list of render preset files. Pulled from the current .ini [RenderPresetsMruFiles] section.
local	objectPresetFiles = #() -- list of object setting preset files. Pulled from the current rtt .ini [ObjectPresetsMruFiles] section.

local	unwrapUVW_instance -- will hold instance of Unwrap_UVW modifier. Used in ObjectIsBakable. Initialized in gTextureBakeDialog 

local unwrapUVW_normalList = #([1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]) -- arg for Unwrap_UVW.flattenMap

local	cached_RadiosityPreferences_computeRadiosity

local	set_selfIllum_to_100 = false -- if true, when creating new mtl to place output in, set selfIllum to 100. Set in ApplyElementsToMtl 

local temp_stringstream_val = stringStream "" -- used by ReadValueFromString function

global DirectX_9_Shader -- will check to see if undefined - it so, no dx9....

------------------------------------------------------------------------
--
-- persistant dialog size & position, rollout states
--
local pDialogHeight
local pDialogPos
local	pFileOverwriteBoxPos
local	pMissingMapCoordsPos
local	pMissingMapTargetsPos
local	pMissingMapFilesPos
local	pAddElementsPos
local	pInvalidOutDirPos
local	pProjectionOptionsPropsPos
local	pBakeProgressPos
local	pExposureControlOKBoxPos
local pLoadPresetOKBoxPos

local	pCommonBakePropsOpen  
local	pSelectedObjectPropsOpen  
local	pSelectedElementPropsOpen 
local	pBakedMtlPropsOpen 
local	pAutoUnwrapMappingPropsOpen 

--------------------------------------------------------------------------
--
--	ini files
--
-- this is the dialog state ini file, holds persistent dialog state
local iniFile = "$plugcfg/BakeTexture.ini"

-- various structures 
-- bakableObjStruct: stores node, node name, bitArray of UVW map channels defined, texmap names for node's mtl, and whether a working object
-- if node doesn't have a mtl, default mtl is standard mtl using 'defaultMtlShader' shader
struct bakableObjStruct (node, nodeName, channels, mapSlotNames, isWorkingObject = false)

struct bakeElementStruct (element, node) -- stores element and node containing element

struct RTT_MlTypes (name, instance) -- stores name and instance of material

struct triStateValue -- tracks if variable has been set to no, one, or move than one value
(
	defined = false,  -- true if at least one value has been "set"
	indeterminate = true, -- different values have been "set"
	value = undefined,  -- current value if defined and determinate
	first_value = undefined,  -- first value specified
	function setVal val = -- use this to "set" the value
	(
		if defined then
		(
			if val != value then
			(
				indeterminate = true
				value = undefined
			)
		)
		else
		(
			indeterminate = false
			defined = true
			value = first_value = val
		)
	),
	function asTriState = -- returns value that can be used for checkBox.triState property. 'value' must be a boolean
	(	if indeterminate then 2 else if value then 1 else 0),
	function asRadioButtonState = -- returns value that can be used for radiobutton.state property.
	(	if indeterminate then 0 else value),
	function spinnerSet spinnerROC = 
	(
		spinnerROC.indeterminate = indeterminate 
		if not indeterminate then
			spinnerROC.value = value
	) 
)

struct projModListStruct (mod, target) -- used to store modifier/target name pairs for projection modifier list dropdown

struct SubObjLvlDataStruct (index, name, mtlIDs) -- used to store proj mod geomSel index, name, and mtlIDs used

struct NodeGeomSelStruct (node, geomSelIndex, eleOutSizes, bakeChannel) -- used to store a node and geomSel index to render, orig output size of bake elements, orig bake channel

local bumpSlotInfoArray = undefined -- Information about the bump slot of certain supported materials, loaded from ini

-- some forward declarations of functions
local	GetINIConfigData, SetINIConfigData, GetINIConfigDataIfExists, ReadValueFromString

-- local declarations of functions
local	ObjectIsBakable, GetMapChannel, GetNodeMapChannels, CollectAutoFlattenChannels, CollectMappedChannels, DeleteAutoFlatten, DeleteBakeMaterial,
		BatchFlatten, CheckBakeElementFileName, ClearTextures, SetShellMtlVPMtl, GetShellMtlVPMtl, SetShellMtlRenderMtl, GetShellMtlRenderMtl,
		SetNamedSubTexmap, ApplyElementsToMtl, UpdateMaterial, CollectUpdateFiles, ApplyUpdateFiles, RemoveFlatteners, RemoveBakeMaterials, OkToOverwrite,
		ResetFileOverwrite, CheckFileOverwrite, ObjHasMapConflicts, MapCoordsOK, MapFilesOK, OutputDirsOK, NodeNamesOK, BakeNodes, BatchBake, NetBatchBake,
		UpdateBakedMtls, CollectCommonElements, GetTexmapSlotNamesOfMtl, CollectTargetMapNamesForMtl, CollectTargetMapNamesForNode, CollectMtlTypes,
		UpdateDefaultMtlMapSlotMapping, GetDefaultMtlMapSlotMapping, LoadRenderPresetList, ReadDialogConfig, WriteDialogConfig, ReadSceneData, 
		WriteSceneData, ExposureControlOK, IsCompatibleWithRenderer
		
-- A struct wrapper for a .NET System.Windows.Forms.ListView control.
local	lvops = ListViewOps() --Found in \stdplugs\stdscripts\NET_ListViewWrapper.ms

-- local declarations of rollouts
local 	fileOverwriteBox, ExposureControlOKBox 

----------------------------------------------------------------------------
-- this function is used everywhere to determine if an object can be baked
function ObjectIsBakable _obj =
(
	local objClass = classof _obj
	local objSuperClass = superclassof _obj
	local baseObj = _obj.baseobject
	local baseObjClass = classof baseObj
	local tmpObj
	if (baseObjClass == XRefObject and (tmpObj = baseObj.actualBaseObject) != undefined) do
		baseObj = tmpObj
	local baseObjSuperClass = superclassof baseObj
	local isRenderableShape = (objSuperClass == shape) and (baseObjSuperClass == shape) and 
							  (hasProperty baseObj #renderable) and (hasProperty baseObj #displayRenderMesh) and
							  baseObj.renderable
	local needRenderMesh = isRenderableShape and not baseObj.displayRenderMesh
	local res = false
	local isBakable = (objSuperClass == geometryClass or (canBakeShapes and isRenderableShape)) \
			and (objClass != Spray ) \ 
			and (objClass != SuperSpray ) \ 
			and (objClass != PCloud ) \ 
			and (objClass != PArray ) \ 
			and (objClass != Snow ) \ 
			and (objClass != Blizzard ) \ 
			and (objClass != Targetobject ) \
			and (objClass != PF_Source) \
			and (objClass != ParticleGroup) \
			and ( _obj.isHidden == false ) \
			and ( _obj.isFrozen == false ) \
			and (validModifier _obj unwrapUVW_instance ) \
			and (local m = snapshotasmesh _obj renderMesh:needRenderMesh; if m != undefined do (res = m.numfaces != 0; delete m); res)
	--format "superClass = %, class = %, isBakable = % \n" (superclassof _obj) objClass isBakable
	isBakable
)

-- the unwrapper returns 0 for channel 1 (0,2,3..) for strange historical reasons
function GetMapChannel _unwrapMod =
(
	local n = _unwrapMod.getMapChannel()
	amax 1 n
)	

-- function to return bitArray of mapping channels on node
function GetNodeMapChannels _obj =
(
	local objClass = classof _obj
	local objSuperClass = superclassof _obj
	local baseObj = _obj.baseobject
	local baseObjClass = classof baseObj
	local tmpObj
	if (baseObjClass == XRefObject and (tmpObj = baseObj.actualBaseObject) != undefined) do
		baseObj = tmpObj
	local baseObjSuperClass = superclassof baseObj
	local isRenderableShape = (objSuperClass == shape) and (baseObjSuperClass == shape) and 
							  (hasProperty baseObj #renderable) and (hasProperty baseObj #displayRenderMesh) and
							  baseObj.renderable
	if _debug do 
	(
		if isRenderableShape then
			format "GetNodeMapChannels: %; %; %; %\n" _obj.name (objSuperClass == shape) baseObj.renderable baseObj.displayRenderMesh
		else
			format "GetNodeMapChannels: %; %\n" _obj.name objSuperClass
	)
	local needRenderMesh = isRenderableShape and not baseObj.displayRenderMesh
	local m = snapshotasmesh _obj renderMesh:needRenderMesh 
	local n = meshop.getNumMaps m -- includes channel 0, vertex color.
	local ba = #{}
	ba.count = n-1
	local fn_getMapSupport = meshop.getMapSupport 
	for i = 1 to (n-1) do ba[i]=fn_getMapSupport m i
	delete m
	ba
)

-- function to return bitArray of Automatic Flatten channels on node
function CollectAutoFlattenChannels _obj =
(
	local res = #{}
	for mod in _obj.modifiers where 
		(classof mod == Unwrap_UVW and (use_all_Unwrap_UVWs or mod.name == "Automatic Flatten UVs")) do
		res[(GetMapChannel mod)] = true
	res
)

-- function to return the valid mapping channels on a node
function CollectMappedChannels _obj unwrapOnly:false =
(
	if use_all_mapping_channels and not unwrapOnly then
		GetNodeMapChannels _obj
	else
		CollectAutoFlattenChannels _obj
)

-- function to delete the autoFlattener on an object
function DeleteAutoFlatten _obj =
(
	-- test each modifier on the object. Count down since we may be deleting modifiers
	for nMod = _obj.modifiers.count to 1 by -1 do
	(
		-- get the next modifier
		local unwrapMod = _obj.modifiers[ nMod ]
		
		if (classof unwrapMod) == Unwrap_UVW then
		(
			-- it's an unwrap modifier, 
			if unwrapMod.name == "Automatic Flatten UVs" then
			(
				--format "removing auto unwrapper: % \n" unwrapMod.name
				deleteModifier _obj unwrapMod
			)
		) -- end, it's an unwrapper
	) -- end, for each modifier
)

-- function to remove shell materials from an object
-- keepWhich = 1 - keep original, 2 - keep baked
function DeleteBakeMaterial _curObj keepWhich =
(
	-- if the material is a shell material, lose it
	local materialType = classof _curObj.material
	if _debug do format "\tremoving bake material on %; mtltype: %\n" _curObj.name materialType 
	-- format "material type = %\n" materialType

	if (materialType == Shell_Material) then
	(
		if _debug do format "\tDeleteBakeMaterial - _curObj: %; keepWhich: %\n" _curObj.name keepWhich

		local mtl = _curObj.material

		if (mtl.bakedMaterial != undefined) do
			showTexturemap mtl mtl.bakedMaterial false

		local origName = getAppData mtl (RTT_MtlName_AppData_Index+2)
		if ( origName == undefined) do
			origName = mtl.originalMaterial.name

		local keepWhichMaterial = if keepWhich == 1 then mtl.originalMaterial else mtl.bakedMaterial
		keepWhichMaterial.name = origName
		local old_autoMtlPropagation = instancemgr.autoMtlPropagation
		instancemgr.autoMtlPropagation = false
		_curObj.material = keepWhichMaterial 
		instancemgr.autoMtlPropagation = old_autoMtlPropagation 
		
	) -- end, has shell material
	else if (_curObj.material != undefined) then
	(
		-- not a shell material, look at each sub-material and see if it is a shell material
		-- if so, replace the shell material with the shell material's original material
		local mtl = _curObj.material
		local nmtls = getNumSubMtls mtl
		for i = 1 to nmtls do
		(	smtl = getSubMtl mtl i
			if classof smtl == Shell_Material then
			(	
				local origName = getAppData smtl (RTT_MtlName_AppData_Index+2)
				if ( origName == undefined) do
					origName = smtl.originalMaterial.name

				local keepWhichMaterial = if keepWhich == 1 then smtl.originalMaterial else smtl.bakedMaterial
				keepWhichMaterial.name = origName 
				setSubMtl mtl i keepWhichMaterial
				--format "remove bake material in %\n" mtl 
			)
		)
	) -- end, non-shell material
)

---------------------------------------------------------------------------
--
--	Function to auto-flatten the objects from a list
--
function BatchFlatten _ObjectList flattenAngle flattenSpacing flattenRotate flattenFillHoles flattenAll:false =
(
	undo "Flatten Objects" on
	(
		if _debug do format "flatten % objects \n" _ObjectList.count
		
		-- first put up the progress dialog
		rollout flattenProgress "Progress..." width:183 height:46
		(
			label lbl1 "Flattening UV's..." pos:[48,5] width:94 height:21
			progressBar pb1 "" pos:[5,21] width:174 height:17
			on flattenProgress close do
				pBakeProgressPos = GetDialogPos flattenProgress
		)
		createdialog flattenProgress pos:pBakeProgressPos -- style:#(#style_border,#style_toolwindow)
		local progressScale = 100. / (_ObjectList.count + 1)
		flattenProgress.pb1.value = progressScale 
	
		-- must be in modify mode to use flatten operator
		if (getCommandPanelTaskMode() != #modify) do setCommandPanelTaskMode #modify
		
		with redraw off
		(
			-- for each object...
			local nObj = 0
			local patchErrorDisplayed = false 
			for curObj_i in _ObjectList do
			(
				local curObj = curObj_i.node
				local bakeInterface = curObj.INodeBakeProperties
				local bakeProjInterface = curObj.INodeBakeProjProperties
				nObj += 1
				
				-- bit 1 of flag will be set to signify map channel conflict
				bakeInterface.flags = bit.set bakeInterface.flags 1 false

				if (not flattenAll and not bakeInterface.effectiveEnable()) then
				(
					if _debug do format "\tignoring object: % \n" curObj.name
					continue
				)
				
				local curClass = classof curObj
				--format "object class = % \n" curClass
				
				if not patchErrorDisplayed then -- just display warning message once
				(
					if (curClass == Editable_Patch) or (curClass == quadPatch) or (curClass == triPatch) then
					(
						messageBox "Editable patch objects not currently supported for flattening and may produce poor results." title:"Render To Texture" --LOC_NOTES: localize this
						patchErrorDisplayed = true
					)
				)
					
				local unwrapMod
				local projMod = bakeProjInterface.projectionMod
				local bakeSubObj = bakeProjInterface.enabled and bakeProjInterface.BakeSubObjLevels and projMod != undefined 
				local hasModifier_Obj = not doAutoUnwrap_Obj
				local hasModifier_SubObj = not bakeSubObj or not doAutoUnwrap_SubObj
				local skipObject = false
				local bakeChannel_Obj = bakeInterface.bakeChannel 
				local bakeChannel_SubObj = bakeProjInterface.subObjBakeChannel 
				local autoFlattenModsToDelete = #() -- collection of modifiers to delete. Need to delete after looping through modifiers
				local deleteMtl = false
				-- test each modifier on the object. 
				for nMod = 1 to curObj.modifiers.count while (not skipObject) do
				(
					-- get the modifier
					unwrapMod = curObj.modifiers[ nMod ]
					
					--format "modifier class = % \n" (classof unwrapMod)
					if (classof unwrapMod) == Unwrap_UVW then
					(
						---format "class Unwrap_UVW\n"
						
						-- it's an unwrap modifier, 
						local mapChannel = GetMapChannel unwrapMod
						local unwrapMod_level = getAppData unwrapMod RTT_UnwrapMod_AppData_Index
						unwrapMod_level = if (unwrapMod_level == undefined) then #object else (unwrapMod_level as name)
						
						if unwrapMod.name == "Automatic Flatten UVs" and ((not hasModifier_Obj) or (not hasModifier_SubObj)) then
--						(	((not hasModifier_Obj) and mapChannel == bakeChannel_Obj) or
--						  	((not hasModifier_SubObj) and mapChannel == bakeChannel_SubObj) )then
						(
							--format "has auto unwrapper: % \n" unwrapMod.name
							
							local deleteMod = false
							local deleteMtl = false
					
							local paramsMatch =	( unwrapMod.getFlattenAngle() == flattenAngle ) and
												( unwrapMod.getFlattenSpacing() == flattenSpacing ) and
												( unwrapMod.getFlattenRotate() == flattenRotate ) and
												( unwrapMod.getFlattenFillHoles() == flattenFillHoles ) 

							-- If "Prevent Reflattening" is checked in the modifier, assume its settings are correct,
							-- to avoid deleting the modifier and reflattening with a new modifer
							if ( unwrapMod.getPreventFlattening() == true ) do
							(
								paramsMatch = true
							)

							if (not hasModifier_Obj) and mapChannel == bakeChannel_Obj then 
							(
								if paramsMatch and unwrapMod_level == #object then
									hasModifier_Obj = true
								else
									deleteMod = deleteMtl = true
							)
							else if (not hasModifier_SubObj) and mapChannel == bakeChannel_SubObj then 
							(
								if paramsMatch and unwrapMod_level == #subObject then
									hasModifier_SubObj = true
								else
									deleteMod = deleteMtl = true
							)
							else
							(
								if not (hasModifier_Obj and hasModifier_SubObj) do
									deleteMtl = true
								if (autoDeleteExistingUnwraps) do
								(
									if (not hasModifier_Obj) and unwrapMod_level == #object do
										deleteMod = true
									if (not hasModifier_SubObj) and unwrapMod_level == #subObject do
										deleteMod = true
								)
							)

							if ( deleteMod) then
								append autoFlattenModsToDelete unwrapMod
	
						) -- end, has autoflatten unwrapper
						else if ( mapChannel == bakeChannel_Obj) then
						(
							-- channel match, it's a user unwrapper for this obj, leave it alone
							--format "non-automatic unwrapper found with matching channel\n"
							hasModifier_Obj = true
						) 
						else if ( mapChannel == bakeChannel_SubObj) then
						(
							-- channel match, it's a user unwrapper for this obj, leave it alone
							--format "non-automatic unwrapper found with matching channel\n"
							hasModifier_SubObj = true
						) 
						else 
						(
							--format "non-automatic unwrapper found with un-matched channel= % \n" (unwrapMod.getMapChannel())
						)	
					) -- end, is unwrap modifier
					else 
					(
						--format "object class = %\n" (classof unwrapMod)
						if (classof unwrapMod) == Uvwmap and unwrapMod.enabled then
						(
							--format "is uvwmap\n"
							-- potential mapping channel conflict
							local mapChan = unwrapMod.mapChannel
							if mapChan == 0 then mapChan = 1
							local errmsg = ""
							if( mapChan == bakeChannel_Obj and not hasModifier_Obj ) then 
							(
								append errmsg "Map Channel in UVW_Mapping modifier conflicts with the channel specified for render to texture. Select a different render to texture channel.\n"
								append errmsg ("Node: " + curObj.name + "\n")
								append errmsg ("Channel: " + bakeChannel_Obj as string)
							)
							if( mapChan == bakeChannel_SubObj and not hasModifier_SubObj ) then 
							(
								if errmsg == "" then
								(
									append errmsg "Map Channel in UVW_Mapping modifier conflicts with the channel specified for render to texture. Select a different render to texture channel.\n"
									append errmsg ("Node: " + curObj.name + "\n")
								)
								else
									append errmsg "\n"
								append errmsg ("Channel: " + bakeChannel_SubObj as string)
							)
							if errmsg != "" do
							(
								messageBox errmsg title:"Map channel conflict"
								skipObject = true
								-- set bit 1 of flag to signify conflict
								bakeInterface.flags = bit.set bakeInterface.flags 1 true
							)
						)
					)
	
				)-- end, for each modifier
				
				if deleteMtl do
					DeleteBakeMaterial curObj 1 -- keep original

				rtt_data.ignoreModStackChanges = true
				
				-- delete the unwanted modifiers
				for mod in autoFlattenModsToDelete do deleteModifier curObj mod

				if _debug do format "\tprocessing object: %; %; %; %; %; %\n" curObj.name hasModifier_Obj hasModifier_SubObj skipObject deleteMtl autoFlattenModsToDelete 

				local applyObjectUnwrap = (not hasModifier_Obj) and (not skipObject)

				local applySOUnwrap = false
				if (not hasModifier_SubObj) and (not skipObject) and bakeSubObj do
				(
					local n = projMod.numGeomSels()
					for i = 1 to n while not applySOUnwrap do
					(
						local geomSelLevel = projMod.getGeomSelLevel i
						if geomSelLevel == #face or geomSelLevel == #element then applySOUnwrap = true
					)
				)

				local restoreToGroup = false
				if applyObjectUnwrap or applySOUnwrap do
				(
					local objClass = classof curObj
					local objSuperClass = superclassof curObj
					local baseObj = curObj.baseobject
					local baseObjClass = classof baseObj
					local tmpObj
					if (baseObjClass == XRefObject and (tmpObj = baseObj.actualBaseObject) != undefined) do
						baseObj = tmpObj
					local baseObjSuperClass = superclassof baseObj
					local isRenderableShape = (objSuperClass == shape) and (baseObjSuperClass == shape) and 
											  (hasProperty baseObj #renderable) and (hasProperty baseObj #displayRenderMesh) and
											  baseObj.renderable
					if isRenderableShape and not baseObj.displayRenderMesh do
					(
						if _debug do format "\tsetting displayRenderMesh true for: %\n" _obj.name
						baseObj.displayRenderMesh = true
					)

					if (isGroupMember curObj) then
					(
						setGroupMember curObj false
						restoreToGroup = true
					)

					-- select the object to apply flatten operator
					if selection.count != 1 or not curObj.isSelected do
						with undo off select curObj
				)

				-- If the object doesn't have a object level modifier applied, create one and flatten it
				if applyObjectUnwrap then
				(
					-- create a new autoflatten unwrapper
					if _debug do format "\tCreate new object unwrap_uvw\n"
					unwrapMod = unwrap_UVW()
					
					unwrapMod.setAlwaysEdit false
					unwrapMod.setMapChannel bakeChannel_Obj
					unwrapMod.setFlattenAngle flattenAngle 
					unwrapMod.setFlattenSpacing flattenSpacing 
					unwrapMod.setFlattenNormalize true
					unwrapMod.setFlattenRotate flattenRotate 
					unwrapMod.setFlattenFillHoles flattenFillHoles 
					unwrapMod.setApplyToWholeObject true
					unwrapMod.name = "Automatic Flatten UVs"
					unwrapMod.setDebugLevel 0

					setAppData unwrapMod RTT_UnwrapMod_AppData_Index #object

					-- add it to the object
					-- add directly to the object to avoid groupness
					addModifier curObj unwrapMod
					
					-- & flatten things
					unwrapMod.flattenMapByMatID \
						flattenAngle  \
						flattenSpacing  \
						true \
						2 \
						flattenRotate  \
						flattenFillHoles 
					-- or use instead of true: autoUnwrapMappingProps.cNormalize.checked \
				) -- end, create new Object Level unwrapper
				
				-- If the object doesn't have a subobject level modifier applied, create one and flatten it
				if applySOUnwrap then
				(
					-- create a new autoflatten unwrapper
					if _debug do format "\tCreate new subobject unwrap_uvw\n"
					unwrapMod = unwrap_UVW()
					
					unwrapMod.setAlwaysEdit false
					unwrapMod.setMapChannel bakeChannel_SubObj
					unwrapMod.setFlattenAngle flattenAngle 
					unwrapMod.setFlattenSpacing flattenSpacing 
					unwrapMod.setFlattenNormalize true
					unwrapMod.setFlattenRotate flattenRotate 
					unwrapMod.setFlattenFillHoles flattenFillHoles 
					unwrapMod.setApplyToWholeObject false  -- apply to selected faces
					unwrapMod.name = "Automatic Flatten UVs"
					unwrapMod.setDebugLevel 0
					
					setAppData unwrapMod RTT_UnwrapMod_AppData_Index #subObject

					-- add it to the object
					-- add directly to the object to avoid groupness
					addModifier curObj unwrapMod
					
					local n = projMod.numGeomSels()
					for i = 1 to n do
					(
						local geomSelLevel = projMod.getGeomSelLevel i
						if geomSelLevel == #face or geomSelLevel == #element then 
						(
							-- set SO selection
							local selFaces
							projMod.getGeomSelFaces curObj i &selFaces
							unwrapMod.selectPolygons selFaces
							if _debug do format "\tflattening faces: %; % : % : % :%\n" selFaces flattenAngle flattenSpacing flattenRotate flattenFillHoles
							-- & flatten things
							unwrapMod.flattenMap \
								flattenAngle  \
								unwrapUVW_normalList \
								flattenSpacing  \
								true \
								2 \
								flattenRotate  \
								flattenFillHoles 
							-- or use instead of true: autoUnwrapMappingProps.cNormalize.checked \
						)
					)
					
				) -- end, create new SubObject Level unwrapper

				-- if it was in a group put it back
				if restoreToGroup then
					setGroupMember curObj true

				rtt_data.ignoreModStackChanges = false
	
--				if hasSubObjectSelections then
--					setFaceSelection curObj objSelections
	
				-- update the progress bar
				flattenProgress.pb1.value = progressScale * (nObj + 1)
				
				curObj_i.channels = CollectMappedChannels curObj_i.node
							
			) -- end, for each object
			with undo off if selectedObjects.count != 0 then select selectedObjects else clearSelection()	-- reselect
		) -- end, with redrawOff
		
		-- Auto Flatten endgame
		destroydialog flattenProgress
	) -- end - undo "Flatten Objects" on
) -- end -function BatchFlatten 

-------------------------------------------------
-- test the filename for the element
-- tests & sets fileUnique, default extension
-- returns filename to display
--
function CheckBakeElementFileName _obj _element _eleName _newName _defaultPath = 
(
	if _debug do format "check file name:\t%, %, %, %, %\n" _obj.name _element _eleName _newName _defaultPath
	if _debug do format "\t\t\t%, %, %, %\n" _element.elementName _element.filenameUnique _element.fileName _element.fileType
	local res = undefined
	with undo off -- no undo records for element changes...
	(
		if (_newName == undefined) or (_newName == "") then
		(
			saveName = _element.elementName -- save
			_element.elementName = _eleName	-- temporary write for makefilename
			_element.filenameUnique = false -- allow overwrite by auto file name
			_newName = RTT_methods.MakeBakeElementFileName _obj _element "" "" defaultFileType 
			_element.elementName = saveName	-- & restore
			res = _newName
		)
		else 
		(
			-- first check the path
			local pathsTheSame
			local newPath = getFilenamePath _newName
			if (newPath == "") then
				pathsTheSame = true 
			else
			(
				local defaultPath = copy _defaultPath
				local i
				while ((i=findString newPath "/") != undefined) do newPath[i]="\\"
				while ((i=findString defaultPath "/") != undefined) do defaultPath[i]="\\"
				pathsTheSame = (stricmp newPath defaultPath) == 0
			)
			if _debug do format "\tpathsTheSame: %; %, %\n" pathsTheSame newPath _defaultPath
			
			-- now check the filenames w/o path and extension
			
			local curName = getFilenameFile _newName
			-- generate the default name for the element
			local genName = RTT_methods.MakeFileNameValid (_obj.name + _eleName)
			if _debug do format "\tnames: % - % - %\n" _newName curName genName
			_element.filenameUnique = (curName != genName)
			
			-- check extension. set as new default
			local newType = getFilenameType _newName
			if (newType == "") do newType = defaultFileType
			defaultFileType = newType
			
			if pathsTheSame then
				res = curName + newType
			else
				res = (getFilenamePath _newName) + curName + newType
			if _debug do format "\tfilenameUnique: %, %\n" _element.filenameUnique res
			
		) -- end, else new name not empty 
	) -- end, undo off 
	res
) -- end - function CheckBakeElementFileName 

-- this function clears all the textures on a material and its first level subMaterials
-- if the mtl or subMtl is a shell, use shell's baked material instead
function ClearTextures mtl doSubMtls:true topMtl: =
(
	if _debug do format "ClearTextures, mtl = %\n" mtl

	if topMtl == unsupplied do topMtl = mtl
	
	if classof mtl == Shell_Material do
	(
		mtl = mtl.bakedMaterial 
		doSubMtls = false -- don't walk down 
	)

	local nmaps = getNumSubTexmaps mtl
	for i = 1 to nmaps do 
	(	local stex = getSubTexmap mtl i
		if stex != undefined do
		(
			if classof stex == gNormal then  -- special case for gNormal maps
			(
				for j = 1 to 2 do
				(
					local gntex = getSubTexmap stex j
					if gntex != undefined do
					(
						showTexturemap topMtl gntex false
						setSubTexmap stex j undefined
					)
				)
			)
			else
			(
				showTexturemap topMtl stex false
				setSubTexmap mtl i undefined
			)
		)
	)

	if doSubMtls do
	(
		local nmtls = getNumSubMtls mtl
		for i = 1 to nmtls do
		(	local smtl = getSubMtl mtl i
			if smtl != undefined do 
				ClearTextures smtl doSubMtls:false topMtl:topMtl
		) 
	)
) -- end - function ClearTextures 

-- this function sets whether Original or Baked Material is used in Viewport for shell materials. 
function SetShellMtlVPMtl mtl which doSubMtls:true topMtl: =
(
	if _debug do format "SetShellMtlVPMtl, mtl = %\n" mtl

	if topMtl == unsupplied do topMtl = mtl

	if classof mtl == Shell_Material do
	(
		if _debug do format "SetShellMtlVPMtl - which = %, mtl.viewportMtlIndex = %\n" which mtl.viewportMtlIndex 
		local amtl 
		if (mtl.viewportMtlIndex != which) do
		(
			amtl = if mtl.viewportMtlIndex == 0 then mtl.originalMaterial else mtl.bakedMaterial 
			if _debug do format "SetShellMtlVPMtl - showTexturemap 1, topMtl = %, amtl = %\n" topMtl amtl 
			if amtl != undefined do showTexturemap topMtl amtl false
			if _debug do format "SetShellMtlVPMtl - showTexturemap 1 done\n"
			mtl.viewportMtlIndex = which
			doSubMtls = false -- don't walk down 
		)
		amtl = if which == 0 then mtl.originalMaterial else mtl.bakedMaterial 
		if _debug do format "SetShellMtlVPMtl - showTexturemap 2, topMtl = %, amtl = %\n" topMtl amtl 
		if amtl != undefined do showTexturemap topMtl amtl true
		if _debug do format "SetShellMtlVPMtl - showTexturemap 2 done\n"
	)
	
	if doSubMtls do
	(
		local nmtls = getNumSubMtls mtl
		for i = 1 to nmtls do
		(	local smtl = getSubMtl mtl i
			if smtl != undefined do 
				SetShellMtlVPMtl smtl which doSubMtls:false topMtl:topMtl
		) 
	)
) -- end - function SetShellMtlVPMtl

-- this function returns whether Original or Baked Material is used in Viewport for shell materials. 
-- res is a triStateValue
function GetShellMtlVPMtl mtl res doSubMtls:true =
(
	if _debug do format "GetShellMtlVPMtl, mtl = %; res: %\n" mtl res

	if classof mtl == Shell_Material do
	(
		res.setVal mtl.viewportMtlIndex
		doSubMtls = false -- don't walk down 
	)
	
	if doSubMtls do
	(
		local nmtls = getNumSubMtls mtl
		for i = 1 to nmtls do
		(	local smtl = getSubMtl mtl i
			if smtl != undefined do 
				GetShellMtlVPMtl smtl res doSubMtls:false
		) 
	)
) -- end - function GetShellMtlVPMtl


-- this function sets whether Original or Baked Material is used in Renders for shell materials. 
function SetShellMtlRenderMtl mtl which doSubMtls:true topMtl: =
(
	if _debug do format "SetShellMtlRenderMtl, mtl = %\n" mtl

	if topMtl == unsupplied do topMtl = mtl

	if classof mtl == Shell_Material do
	(
		if _debug do format "SetShellMtlRenderMtl - which = %, mtl.renderMtlIndex = %\n" which mtl.viewportMtlIndex 
		mtl.renderMtlIndex = which
		doSubMtls = false -- don't walk down 
	)
	
	if doSubMtls do
	(
		local nmtls = getNumSubMtls mtl
		for i = 1 to nmtls do
		(	local smtl = getSubMtl mtl i
			if smtl != undefined do 
				SetShellMtlRenderMtl smtl which doSubMtls:false topMtl:topMtl
		) 
	)
) -- end - function SetShellMtlRenderMtl 

-- this function returns whether Original or Baked Material is used in Renders for shell materials. 
-- res is a triStateValue
function GetShellMtlRenderMtl mtl res doSubMtls:true =
(
	if _debug do format "GetShellMtlRenderMtl, mtl = %; res: %\n" mtl res

	if classof mtl == Shell_Material do
	(
		res.setVal mtl.renderMtlIndex
		doSubMtls = false -- don't walk down 
	)
	
	if doSubMtls do
	(
		local nmtls = getNumSubMtls mtl
		for i = 1 to nmtls do
		(	local smtl = getSubMtl mtl i
			if smtl != undefined do 
				GetShellMtlRenderMtl smtl res doSubMtls:false
		) 
	)
) -- end - function GetShellMtlRenderMtl

-- Reads the bump slot information from the ini file, returns it as an array
-- NOTE: The information is never written back to the ini file; File should not be deleted
function ReadBumpSlotInfo =
(
	local bumpSlotInfoArray = #()
	local sectionName = "BumpSlotInfo"
	local index = 1
	local done = false
	while not done do
	(	-- The keys are named Item1, Item2, and so on. The loop iterates over key names until no more are found.
		local keyName = ("Item"+(index as string))
		local str = getIniSetting iniFile sectionName keyName
		if (str != "") then
		(	-- The string contains arguments to construct a BumpSlotInfoStruct via execute().
			-- Since execute() runs at the global scope, it cannot use a struct declared here.
			-- Instead use a global helper method in RTT_Methods.
			local s = (execute ("RTT_Methods.MakeBumpSlotInfoStruct "+str))
			append bumpSlotInfoArray s
			index = index + 1
		)
		else done = true
	)
	bumpSlotInfoArray -- return value
)

-- This sets the bump amount to full, only if certain verifications are passed
-- Using the bump slot info loaded from ini, this verifies the material is supported and the target slot is a bump slot
function HandleBumpMapAmount mtl slotName =
(
	if bumpSlotInfoArray == undefined do bumpSlotInfoArray = ReadBumpSlotInfo()

	local done = false
	local mtlClass = classof mtl
	for item in bumpSlotInfoArray while not done do
	(
		if (mtlClass == item.mtlClass) do
		(
			if (slotName == item.bumpSlotName) and (isProperty mtl item.bumpAmountProperty) do
				setProperty mtl item.bumpAmountProperty item.bumpAmountMax
			done = true
		)
	)
) -- end - function GetBumpSlotAmountProperty

-- this function sets the textures on a material and its first level subMaterials given the slot name
-- if the mtl or subMtl is a shell, use shell's baked material instead
function SetNamedSubTexmap mtl theName theTexmap theNode subObjBake outputIntoNormalBump doSubMtls:true =
(
	local normalSpace_enums = #(#tangent,#local,#screen,#world)
	if _debug do format "\t\tset texture, mtl: %; name: %; texmap: %; subObjBake: %; outputIntoNormalBump: %; doSubMtls: %\n" mtl theName theTexmap subObjBake outputIntoNormalBump doSubMtls 

	if classof mtl == Shell_Material do
	(
		mtl = mtl.bakedMaterial 
		doSubMtls = false -- don't walk down 
	)
	
	if subObjBake and (classof mtl == multiMaterial) do
	(
		local bakeProjInterface = theNode.INodeBakeProjProperties
		local mtlID
		local iprojMod = bakeProjInterface.projectionMod
		local projModTarget = bakeProjInterface.projectionModTarget
		for i = 1 to iprojMod.numGeomSels() while mtlID == undefined do
		(
			if (iprojMod.getGeomSelName i) == projModTarget do
				iprojMod.getGeomSelMtlIds theNode i &mtlID
		)
		if _debug do format "\t\tsubMtl redirect 1 - projModTarget:% mtlID:%\n" projModTarget mtlID 
		if mtlID != undefined do mtlID = mtlID[1]
		if mtlID == undefined do return false
		mtl = mtl[mtlID]
		if _debug do format "\t\tsubMtl redirect 2 - _toMtl:% mtlID:%\n" mtl mtlID 
		if mtl == undefined do return false
	)

	local nmaps = getNumSubTexmaps mtl
	local notFound = true 

	-- special case code for standard materials. If putting to the ambient slot, and ambient texmap
	-- was previously not set, turn off the ambient lock flag
	local checkAmbientLockFlag = (classof mtl == standard) and (isProperty mtl #ambientMap) and (mtl.ambientMap == undefined)

	-- special case code for standard materials. If not putting to Source material, turn off basic parameter flags
	if (classof mtl == standard) and (bakedMtlProps.rbDestination.state == 2) do
	(
		mtl.wire = mtl.twoSided = mtl.faceted = mtl.faceMap = off
		if (set_selfIllum_to_100 and isProperty mtl #selfIllumAmount) do mtl.selfIllumAmount = 100 -- not present for Strauss shader
	)

	-- special case code for Architectural materials. If not putting to Source material, set Raw Diffuse Texture on
	if (classof mtl == Architectural) and (bakedMtlProps.rbDestination.state == 2) do
		mtl.rawDiffuseTexture = on
	
	local targSlotName = theName
	local targIsGNormal = false
	local gNormalSubMapIndex = 0
	local j

	if _debug do format "\t\ttesting texture slot name: %\n" targSlotName

	if (j = findString targSlotName ".NormalBump.") != undefined then
	(
		if _debug do format "\t\ttesting gNormal texture slot name: %; %\n" targSlotName (subString targSlotName (j+9) -1)
		targIsGNormal = true
		if (subString targSlotName (j+12) -1) == gNormalSlot1Name then -- 12 takes us past '.NormalBump.'
			gNormalSubMapIndex = 1
		else 
			gNormalSubMapIndex = 2
		targSlotName = subString targSlotName 1 (j-1)
		if _debug do format "\t\ttarg texture slot name updated: %\n" targSlotName
	)
	else if (j = findString targSlotName ".gNormal.") != undefined do
	(
		if _debug do format "\t\ttesting gNormal texture slot name: %; %\n" targSlotName (subString targSlotName (j+9) -1)
		targIsGNormal = true
		if (subString targSlotName (j+9) -1) == gNormalSlot1Name then -- 9 takes us past '.gNormal.'
			gNormalSubMapIndex = 1
		else 
			gNormalSubMapIndex = 2
		targSlotName = subString targSlotName 1 (j-1)
		if _debug do format "\t\ttarg texture slot name updated: %\n" targSlotName
	)
	if (not targIsGNormal) and outputIntoNormalBump do
	(
		-- We're applying Normal Bump to a slot that did not already have a Normal Bump.
		-- Create the Normal Bump texture					
		local newTexMap = Normal_Bump normal_map:theTexmap
		newTexMap.method = (findItem normalSpace_enums theNode.INodeBakeProjProperties.normalSpace)-1
		theTexmap = newTexMap 
		outputIntoNormalBump = false

		-- If this is the bump slot, set the bump amount to 100
		HandleBumpMapAmount mtl targSlotName
	)
	
	
	for i = 1 to nmaps while notFound do
	( 
		if ((stricmp (getSubTexmapSlotName mtl i) targSlotName) == 0) do 
		(
			if _debug do format "\t\tset texture slot: %; targIsGNormal: %; gNormalSubMapIndex:% \n" targSlotName targIsGNormal gNormalSubMapIndex 
			local oldMap = getSubTexmap mtl i 
			if (targIsGNormal and classof oldMap == Normal_Bump) then
			(
				local oldSubMap = getSubTexmap oldMap gNormalSubMapIndex 
				if oldSubMap != undefined do showTexturemap mtl oldSubMap false
				setSubTexmap oldMap gNormalSubMapIndex theTexmap
				oldMap.method = (findItem normalSpace_enums theNode.INodeBakeProjProperties.normalSpace)-1
				if _debug do format "\t\tset gNormal: %; gNormalSubMapIndex:%; method: % \n" oldMap gNormalSubMapIndex oldMap.method
			)
			else
			(
				if oldMap != undefined do showTexturemap mtl oldMap false
				setSubTexmap mtl i theTexmap
			)
			notFound = false
		)
	)

	if checkAmbientLockFlag and mtl.ambientMap != undefined and mtl.adTextureLock do 
		mtl.adTextureLock = false

	if doSubMtls do
	(
		local nmtls = getNumSubMtls mtl
		for i = 1 to nmtls do
		(	local smtl = getSubMtl mtl i
			if smtl != undefined do 
				SetNamedSubTexmap smtl theName theTexmap theNode subObjBake outputIntoNormalBump doSubMtls:false
		) 
	)
) -- end - function SetNamedSubTexmap 

-- this applies maps, via the element-to-mapChannel mapping specified in the element, to the given material,
function ApplyElementsToMtl _obj _toMtl subObjBake =
(	
	if _debug do format "\tapplyElementsToMtl _obj:% _toMtl:% subObjBake:%\n" _obj _toMtl subObjBake

	-- for each possible bake element
	local bakeInterface = _obj.INodeBakeProperties
	local nBakeElements = bakeInterface.NumBakeElements()

	set_selfIllum_to_100 = false
	if set_selfIllum_to_100_if_CompleteMap_or_LightMap do
	(
		for nEle = 1 to nBakeElements do
		(
			local theElementType = classof (bakeInterface.GetBakeElement nEle)
			if theElementType == CompleteMap or theElementType == LightMap do set_selfIllum_to_100 = true
		)
	)
	
	for nEle = 1 to nBakeElements do
	(
		local theElement = bakeInterface.GetBakeElement nEle 
		local target_name = theElement.targetMapSlotName

		if theElement.enabled and target_name != "" and target_name != " " then -- skip disabled elements and elements w/o target slots
		(	
			local fname = theElement.fileType
			if fname == undefined or fname == "" then
			(
				fname = commonBakeProps.GetFilePath() + theElement.fileName
			)
			local theTexmap = bitmapTexture filename:fname name:(_toMtl.name + "_" + (classof theElement) as string)

			theTexmap.coords.mapChannel = bakeInterface.bakeChannel 
			local outputIntoNormalBump = false
			if classOf theElement == NormalsMap do
				outputIntoNormalBump = (bakeInterface.paramValue theElement 1) == 1 -- "Output into Normal Bump"
			SetNamedSubTexmap _toMtl target_name theTexmap _obj subObjBake outputIntoNormalBump
		)
		
	) -- end, for each element
) -- end, function ApplyElementsToMtl 

------------------------------------------------------------------
--
--	Function to update the output material & create shells if needed
--
function UpdateMaterial _obj allowCreateMtl subObjBake =
(
	if _debug do format "updateMaterial - node: % allowCreateMtl: % subObjBake: % \n" _obj.name allowCreateMtl subObjBake
	
	local mtl = _obj.material
	
	if mtl == undefined and not allowCreateMtl do return false
	
	local projInterface = _obj.INodeBakeProjProperties
	
	local useObjBake = projInterface.useObjectBakeForMtl or (not projInterface.enabled) 
	local useSubObjBake = projInterface.enabled and projInterface.BakeSubObjLevels and (not projInterface.useObjectBakeForMtl)
	
	local projMod = projInterface.projectionMod

	local SubObjLvlDataArray, usedMatIDs, matIDName
	
	if useSubObjBake do
	(
		SubObjLvlDataArray = #()

		if projMod == undefined do --LOC_NOTES: localize following
		(
			local errmsg = "Attempted to update mtl for node " + obj.name + "\nbased on Sub-Object Level rendering, but no Projection Modifier found"
			messageBox errmsg title:"Render To Texture" 
			return false
		)
		local iprojMod = projMod.projectionModOps
		local n = iprojMod.numGeomSels()
		local mtlIDs
		
		for i = 1 to n do
		(
			local geomSelLevel = iprojMod.getGeomSelLevel i
			if geomSelLevel == #face or geomSelLevel == #element then 
			(
				local soLvlData = SubObjLvlDataStruct i (iprojMod.getGeomSelName i) (iprojMod.getGeomSelMtlIds _obj i &mtlIDs;mtlIDs)
				append SubObjLvlDataArray soLvlData 
			)
		)

		-- build arrays of used matIDs and the name of the geomSel used in, keep arrays is sorted order based on mtlID
		usedMatIDs = #()
		matIDName = #()
		for soLvlData in SubObjLvlDataArray do  
		(
			mtlIDs = soLvlData.mtlIDs
			for mtlID in mtlIDs do
			(
				local k = findItem usedMatIDs mtlID
				if k == 0 then
				(
					local inserted = false
					for i = 1 to usedMatIDs.count while not inserted do
					(
						if (mtlID < usedMatIDs[i]) do
						(
							insertItem mtlID usedMatIDs i
							insertItem soLvlData.name matIDName i
							inserted = true
						)
					)
					if not inserted do
					(
						append usedMatIDs mtlID
						matIDName[usedMatIDs.count] = soLvlData.name
					)
				)
				else
					matIDName[k] = "multiple GeomSels"
			)
		)
	if _debug do format "\tSubObjLvlDataArray: %\n\tusedMatIDs: %\n\tmatIDName: %\n" SubObjLvlDataArray usedMatIDs matIDName 
	)
	
	if mtl == undefined do -- no material on node. Create new default material 
	(
		-- check to see if should use object level or subObject level bake output
		-- if subObject, create a MultiMaterial with N subMaterials, and set ID and name for
		-- each subMaterial to the mtlID and name for the subObject
		
		if useObjBake then
		(
			local old_autoMtlPropagation = instancemgr.autoMtlPropagation
			instancemgr.autoMtlPropagation = false
			mtl = _obj.material = copy newNodeMtlInstance
			instancemgr.autoMtlPropagation = old_autoMtlPropagation 
			if classof mtl == StandardMaterial do mtl.diffuse=_obj.wireColor
			mtl.name = _obj.name + "_mtl"
			setAppData mtl RTT_MtlName_AppData_Index mtl.name
			setAppData mtl (RTT_MtlName_AppData_Index+1) "N"
			if _debug do format "\t\tapplied new material at object level: %\n" mtl
		)
		else if useSubObjBake do
		(
			-- build and apply a MultiMaterial
			local n = usedMatIDs.count
			mtl = multimaterial numSubs:n
			for i = 1 to n do
			(
				local subMtl = if (classof newNodeMtlInstance) != multiMaterial then copy newNodeMtlInstance else StandardMaterial()
				if classof subMtl == StandardMaterial do subMtl.diffuse=_obj.wireColor
				subMtl.name = _obj.name + "_" + matIDName[i] + "_mtl"
				mtl.materialList[i] = subMtl
				mtl.names[i] = matIDName[i]
				mtl.materialIDList[i] = usedMatIDs[i]
				if _debug do format "\t\tapplied new submaterial: % : % : %\n" usedMatIDs[i] matIDName[i] subMtl 
			)
			
			local old_autoMtlPropagation = instancemgr.autoMtlPropagation
			instancemgr.autoMtlPropagation = false
			_obj.material = mtl
			instancemgr.autoMtlPropagation = old_autoMtlPropagation 
			mtl.name = _obj.name + "_mtl"
			setAppData mtl RTT_MtlName_AppData_Index mtl.name
			setAppData mtl (RTT_MtlName_AppData_Index+1) "N"
			if _debug do format "\t\tapplied new material at object level: %\n" mtl
		)
	)
	
	local materialType = classof mtl
	
	local nmtls = getNumSubMtls mtl
	if _debug do format "\tMaterial Type: %; nmtls: %; dest: %; opt: %\n" materialType nmtls bakedMtlProps.rbDestination.state bakedMtlProps.rbShellOption.state

	if (bakedMtlProps.rbDestination.state == 2) then -- Save Source (Create Shell)
	(
		if (materialType != Shell_Material) then -- wrap existing material in a shell if not already a shell
		(
			local newMaterial = Shell_Material()
			newMaterial.name = getAppData mtl RTT_MtlName_AppData_Index
			setAppData newMaterial (RTT_MtlName_AppData_Index+2) newMaterial.name 
			newMaterial.name += (" [" + _obj.name + "]")
			if (getAppData mtl (RTT_MtlName_AppData_Index+1) == "N") do
			(
				setAppData mtl (RTT_MtlName_AppData_Index+1) "Y"
			)
			if _debug do format "\t\tapplied new shell material: % : %\n" newMaterial mtl
			newMaterial.originalMaterial = mtl
			newMaterial.bakedMaterial = undefined
			local old_autoMtlPropagation = instancemgr.autoMtlPropagation
			instancemgr.autoMtlPropagation = false
			mtl = _obj.material = newMaterial
			instancemgr.autoMtlPropagation = old_autoMtlPropagation 
		)
		else
		(
			if mtl.originalMaterial == undefined do
			(
				mtl.originalMaterial = copy newNodeMtlInstance
			)
		)
		
		local origName = getAppData mtl (RTT_MtlName_AppData_Index+2)
		if ( origName == undefined) do
		(
			origName = mtl.originalMaterial.name
			setAppData mtl (RTT_MtlName_AppData_Index+2)  origName
		)
		
		local bakeTarget = mtl.bakedMaterial
		-- always create bakedMaterial if it doesn't exist, otherwise just optionally
		if (alwaysCreateNewBakeMaterial or bakeTarget == undefined) and allowCreateMtl then
		(
			if (bakedMtlProps.rbShellOption.state == 1) then -- Duplicate Source to Baked
			(
				-- copy mtl from orig to baked, optionally delete texmaps from baked
				bakeTarget = copy mtl.originalMaterial
				if wipeTextureMapsOnBake do 
					ClearTextures bakeTarget
				if _debug do format "\t\tcopy mtl from orig to baked\n"
			)
			else -- Create New Baked
			(
				bakeTarget = copy newBakedMtlInstance
				if classof bakeTarget == StandardMaterial do bakeTarget.diffuse=_obj.wireColor
				if _debug do format "\t\tcreated new baked\n"
			)
			bakeTarget.name = "baked_" + origName
		)
		else
		(
			if _debug do format "\t\tbaked already exists: %\n" bakeTarget
			-- optionally delete texmaps from baked
			if wipeTextureMapsOnBake do 
				ClearTextures bakeTarget
		)
		
		if useSubObjBake and allowCreateMtl and subObjBake do
		(
			if (classof bakeTarget) != multiMaterial do
			(
				local nameCleanup = (substring bakeTarget.name (bakeTarget.name.count-3) -1) == "_mtl"
				if _debug do format "\t\t% : % : % : %\n" bakeTarget.name (substring bakeTarget.name (bakeTarget.name.count-3) -1) \
									(substring bakeTarget.name 1 (bakeTarget.name.count-4)) nameCleanup
				-- build and apply a MultiMaterial
				local n = usedMatIDs.count
				local tmpMtl2 = multimaterial numSubs:n
				tmpMtl2.name = bakeTarget.name
				if nameCleanup  do
					bakeTarget.name = substring bakeTarget.name 1 (bakeTarget.name.count-4)
				for i = 1 to n do
				(
					local subMtl = copy bakeTarget
					subMtl.name = bakeTarget.name + "_" + matIDName[i] + (if nameCleanup then "_mtl" else "")
					tmpMtl2.materialList[i] = subMtl
					tmpMtl2.names[i] = matIDName[i]
					tmpMtl2.materialIDList[i] = usedMatIDs[i]
					if _debug do format "\t\tapplied new submaterial: % : % : %\n" usedMatIDs[i] matIDName[i] subMtl 
				)
				bakeTarget = tmpMtl2
				if _debug do format "\t\tapplied new material at shell bakedMaterial: %\n" tmpMtl2
			)
		)
		-- apply the element bitmaps to the baked mtl and assign
		ApplyElementsToMtl _obj bakeTarget subObjBake
		if mtl.bakedMaterial != bakeTarget do mtl.bakedMaterial = bakeTarget
		
		if allowCreateMtl do -- optimization. If false, have already processed the mtl and done the following
		(
			-- which material do we use for the viewport
			local which = gTextureBakeDialog.rOrigOrBaked.state
			if which == 0 do which = 2 -- if indeterminate, use Baked
			SetShellMtlVPMtl mtl (which-1)
	
			-- which material do we use for the rendering
			which = gTextureBakeDialog.rOrigOrBaked2.state
			if which == 0 do which = 1 -- if indeterminate, use Original
			SetShellMtlRenderMtl mtl (which-1)
		)
	)
	else -- Output Into Source
	(
		if _debug do format "\t\tOutput Into Source\n"
		ApplyElementsToMtl _obj mtl subObjBake
	)
	
	if _debug do format "\tend update material\n"
	true
) -- end - function UpdateMaterial

----------------------------------------------------------------------------
--
-- these routines collect the file names for a frame & then applys them
-- prior to material updating
--
function CollectUpdateFiles _obj _updateFileNames subObjBake =
(
	if _debug do format "CollectUpdateFiles: % : % " _obj.name subObjBake 
	local bakeInterface = _obj.INodeBakeProperties
	local bakeProjInterface = _obj.INodeBakeProjProperties
	local nElements = bakeInterface.numBakeElements()
	for i = 1 to nElements do
	(
		-- get the element
		local ele = bakeInterface.getBakeElement i
		
		-- save the file name,
		if _updateFileNames[ i ] == undefined do _updateFileNames[ i ] = #()
		append (_updateFileNames[ i ]) ele.fileType
	)
	if _debug do format ";	save filenames = %\n" _updateFileNames
	ok
) -- end - function CollectUpdateFiles 

-- apply collected filenames to object elements
function ApplyUpdateFiles _obj _updateFileNames subObjBake =
(
	if _debug do format "ApplyUpdateFiles: % : % : %\n" _obj.name _updateFileNames subObjBake 
	local bakeInterface = _obj.INodeBakeProperties
	local bakeProjInterface = _obj.INodeBakeProjProperties
	local nElements = bakeInterface.numBakeElements()
	local geomSelName = if subObjBake then ("_" + bakeProjInterface.projectionModTarget + "_") else ""
	with undo off -- no undo records for element changes...
	(
		for i = 1 to nElements do
		(
			-- get the element
			local ele = bakeInterface.getBakeElement i
			
			-- restore the file name,
			local outfileArray = _updateFileNames[ i ]
			if outfileArray.count != 1 then
			(	
				local path = getFilenamePath (outfileArray[1])
				local theName
				if (ele.filenameUnique) and ( ele.filename != "" ) then
				(
					-- unique name
					theName = getFilenameFile ele.filename
				) 
				else 
				(
					-- it's a non-unique name, generate it
					theName = RTT_methods.MakeFileNameValid (_obj.name + geomSelName + ele.elementName)
				)
				if _debug do format "\t: % : %\n" ele theName
				theName = path + theName + ".ifl"
				outfile = openfile theName mode:"w"
				for f in outfileArray do 
					format "%\n" (filenameFromPath f) to:outfile
				close outfile
				
				ele.fileType = theName 
			)
			else
				ele.fileType = outfileArray[1] 
		
			-- format "	restore filename = %\n" ele.fileType
		)
	)
) -- end - function ApplyUpdateFiles 

-----------------------------------------------------------------------------
--
--	these functions remove the flatteners, shell & baked materials from a scene
--	reattaching the original materials to the nodes
--
function RemoveFlatteners =
(
	--format "remove flatteners\n"
	undo "Clear Unwrappers" on
	(
		for obj in workingObjects do
			DeleteAutoFlatten obj.node
	)
) -- end - function RemoveFlatteners

-- keepWhich = 1 - keep original, 2 - keep baked
function RemoveBakeMaterials keepWhich =
(
	--format "remove bake materials\n"
	undo "Clear Shell Mtls" on
	(
		for obj in workingObjects do
			DeleteBakeMaterial obj.node keepWhich
	)
	
) -- end - function RemoveBakeMaterials 


----------------------------------------------------------------------------
--
--	Routines to handle file checking
--
-- message box to confirm overwrite of existing files
rollout fileOverwriteBox "File Exists" width:400 height:113
(
	local buttonWidth = 90
	button bCancel "Cancel Render" pos:[202,63] width:buttonWidth height:24
	button bOverwriteFiles "Overwrite Files" pos:[99,63] width:buttonWidth height:24
	checkbox cNotAgain "Don't show this message again" pos:[10,90] checked:false 
	groupBox gFile "Confirm File Overwrite:" pos:[3,8] width:393 height:50
	edittext eFileName "" pos:[4,27] width:387 height:22 enabled:false

	on fileOverwriteBox open do
	(
		local curTextExtent = eFileName.width
		local requiredTextExtent = ((getTextExtent  overwriteFileName).x) + 10
		local addExtent = requiredTextExtent - curTextExtent
		if addExtent>0 do
		(
			-- Expand the dialog, the text field, and the group surrounding the field
			fileOverwriteBox.width+= addExtent
			gFile.width += addExtent
			eFileName.width += addExtent
			
			-- Recenter the OK and Cancel buttons, placing each 8 units left/right of center
			local center = ((fileOverwriteBox.width) / 2)
			bOverwriteFiles.pos.x = center - (buttonWidth + 8)  -- Leftmost control, relative to its left side (must add the control's width)
			bCancel.pos.x = center + 8  -- Rightmost control, relative to its left side (do not add the control's width)
			
		)
		-- format "conflicted filename = %,   val = % \n" overwriteFileName overwriteVal 
		eFilename.text = overwriteFileName 
	)
	
	on fileOverwriteBox close do
	(	
		pFileOverwriteBoxPos = GetDialogPos fileOverwriteBox 
	)
	on bCancel pressed do 
	(
		RTT_data.overwriteFilesOk = 0
		destroydialog fileOverwriteBox
	)
	on bOverwriteFiles pressed do
	(
		RTT_data.overwriteFilesOk= if cNotAgain.checked then 2 else 1
		destroydialog fileOverwriteBox
	)
	
) -- end, file overwrite dialog


-- returns true if ok to overwrite 
function OkToOverwrite _fileName =
(
	if RTT_data.overwriteFilesOk < 2 then -- if 0 or 1 ...
	(
		overwriteFileName = _fileName
		createDialog  fileOverwriteBox  modal:true pos:pFileOverwriteBoxPos
	)		
	RTT_data.overwriteFilesOk > 0
) -- end - function OkToOverwrite 

-- resets the "don't ask again" flag
function ResetFileOverwrite = 
( 
	RTT_data.overwriteFilesOk = 0 
)

-- function to see if files to be created by node's elements already exist, then check if ok to over write it.
function CheckFileOverwrite _obj =
(
	local bakeInterface = _obj.INodeBakeProperties
	local nElements = bakeInterface.numBakeElements()
	res = true
	for i = 1 to nElements while res and (RTT_data.overwriteFilesOk != 2) do
	(
		-- get the element
		local ele = bakeInterface.getBakeElement i
		
		-- see if the file exists
		if ele.enabled and (doesFileExist ele.fileType) then
		(
			--format "file exists: % \n" (ele.fileType)
			-- it exists, what do we do?
			if OkToOverwrite ele.fileType then
			(
				--format "ok to overwrite file\n"
			) else (
				--format "cancel\n"
				res = false -- cancel render
			)
				
		) -- end, file exists
	) -- end, for each element
	
	res
) -- end - function CheckFileOverwrite 

-------------- function to skip objects w/ map conflicts
function ObjHasMapConflicts _obj =
(
	bit.get _obj.INodeBakeProperties.flags 1
)

-- function to check to make sure needed UVW coords are present
-- returns true if ok to render, false if not
--
function MapCoordsOK _ObjectList =
(
	local missingMapCoordsRO 
	rollout missingMapCoordsRO "Missing Map Coordinates - RTT" width:300
	(
		local itemList = #()
		group ""
		(	label lbl1 "The following objects require map coordinates and" align:#left offset:[0,-10]
			label lbl2 "may not render correctly:" align:#left offset:[0,-5]
		)
		multiListBox mlAvailableElements "" width:293 height:20  offset:[-10,0]-- height is measured in Lines, not pixels
		button bContinue "Continue" across:3 offset:[-18,0]
		button bCancel "Cancel" offset:[-40,0]
		checkbox bDontShow "Don't display this message again" offset:[-45,3]
		
		-- prepare the class list
		on missingMapCoordsRO open do
		(
			for ele in gTextureBakeDialog.missingDataList do
				append itemList ("(UVW " + ele[2] as string + "): " + ele[1].name)
			mlAvailableElements.items = itemList 
		)
		
		on missingMapCoordsRO close do
		(
			pMissingMapCoordsPos = GetDialogPos missingMapCoordsRO
			gTextureBakeDialog.missingDataList = undefined
		)
		
		-- Continue handler
		on bContinue pressed do
		(
			-- set flag in gTextureBakeDialog to continue
			gTextureBakeDialog.cancelRender = false
			-- and destroy the dialog
			destroydialog missingMapCoordsRO 
		)
		-- Cancel handler
		on bCancel pressed do
		(
			-- set flag in gTextureBakeDialog to cancel
			gTextureBakeDialog.cancelRender = true
			-- and destroy the dialog
			destroydialog missingMapCoordsRO 
		)
		-- russom - 02/02/04 - 545034
		-- DontShow handler
		on bDontShow changed theState do
		(
			local strSetting = "0"
			if bDontShow.checked do strSetting = "1"
			setinisetting (GetMAXIniFile()) "Renderer" "DontShowMissingUVWarning" strSetting
		)
	)
	
	if _debug do format "in MapCoordsOK : %\n" _ObjectList
	
	-- russom - 02/02/04 - 545034
	local strSetting = getinisetting (GetMAXIniFile()) "Renderer" "DontShowMissingUVWarning"
	if strSetting == "1" do return true
	
	local mapChannelChangeDetected = false
	gTextureBakeDialog.missingDataList = #()
	for obj_i in _ObjectList do
	(
		local obj = obj_i.node
		local bakeInterface = obj.INodeBakeProperties
		local bakeProjInterface = obj.INodeBakeProjProperties
		if _debug do format "MapCoordsOK test: % : % : % : % : %\n" obj (bakeInterface.effectiveEnable()) (ObjHasMapConflicts obj) bakeInterface.bakeChannel obj_i.channels
		if (bakeInterface.effectiveEnable()) and not (ObjHasMapConflicts obj) then
		(	
			-- refresh map channels available in case user deleted UVW mods
			local oldChannels = obj_i.channels
			obj_i.channels = CollectMappedChannels obj_i.node
			if not mapChannelChangeDetected do mapChannelChangeDetected = (oldChannels*obj_i.channels).count == oldChannels.count

			if bakeInterface.bakeEnabled and not obj_i.channels[bakeInterface.bakeChannel] do
				append gTextureBakeDialog.missingDataList #(obj,bakeInterface.bakeChannel)
			-- If the object doesn't have a proj mod, or has not subobject geomSels, ignore SO bake channel
			local projMod = bakeProjInterface.projectionMod 
			local bakeSubObj = bakeProjInterface.enabled and bakeProjInterface.BakeSubObjLevels and projMod != undefined 
			if _debug do format "\tSO test: % : % : % : %\n" projMod bakeProjInterface.enabled bakeProjInterface.BakeSubObjLevels bakeProjInterface.subObjBakeChannel
			if bakeSubObj and not obj_i.channels[bakeProjInterface.subObjBakeChannel] do
			(
				local bakeSubObj = false
				if projMod != undefined do
				(
					local n = projMod.numGeomSels()
					for i = 1 to n while not bakeSubObj do
					(
						local geomSelLevel = projMod.getGeomSelLevel i
						if geomSelLevel == #face or geomSelLevel == #element then bakeSubObj = true
					)
				)
				if bakeSubObj do
					append gTextureBakeDialog.missingDataList #(obj,bakeProjInterface.subObjBakeChannel)
			)
		)
	)
	
	gTextureBakeDialog.cancelRender = false
	if gTextureBakeDialog.missingDataList.count != 0 do
	(	
		createDialog missingMapCoordsRO modal:true pos:pMissingMapCoordsPos 
	)

	if mapChannelChangeDetected do
	(
		selectedObjectProps.UpdateObjectSettings()
--		selectedObjectProps.RefreshObjectsLV workingObjectsOnly:true-- no point in this, still displays "old" map channel
	)
	
	(not gTextureBakeDialog.cancelRender)
) -- end - function MapCoordsOK

-- function to check to make sure Target Map Slot Names are specified for each element
-- returns true if ok to render, false if not
--
function MapTargetsOK _ObjectList =
(
	rollout missingMapTargetsRO "Missing Map Targets" width:300
	(
		local itemList = #()
		group ""
		(	label lbl1 "The following elements do not specify a Target Map slot:" align:#left offset:[0,-10]
		)
		multiListBox mlAvailableElements "" width:293 height:20  offset:[-10,0]-- height is measured in Lines, not pixels
		button bContinue "Continue" across:2
		button bCancel "Cancel" 
		checkbox cNotAgain "Don't display this message again" align:#left
		
		-- prepare the class list
		on missingMapTargetsRO open do
		(
			for ele in gTextureBakeDialog.missingDataList do
				append itemList (ele.node.name + ": " + ele.element.elementName)
			mlAvailableElements.items = itemList 
		)
		
		on missingMapTargetsRO close do
		(
			pMissingMapTargetsPos = GetDialogPos missingMapTargetsRO 
			gTextureBakeDialog.missingDataList = undefined
		)
		
		-- Continue handler
		on bContinue pressed do
		(
			RTT_data.emptyTargetsOk = if cNotAgain.checked then 2 else 1
			-- and destroy the dialog
			destroydialog missingMapTargetsRO 
		)
		-- Cancel handler
		on bCancel pressed do
		(
			RTT_data.emptyTargetsOk = 0
			-- and destroy the dialog
			destroydialog missingMapTargetsRO 
		)
	)
	
	if _debug do format "in MapTargetsOK : %\n" _ObjectList

	if RTT_data.emptyTargetsOk < 2 then -- if 0 or 1 ...
	(
		RTT_data.emptyTargetsOk = 1
		gTextureBakeDialog.missingDataList = #()
		for obj_i in _ObjectList do
		(
			local obj = obj_i.node
			local bakeInterface = obj.INodeBakeProperties
			if (bakeInterface.effectiveEnable()) and not (ObjHasMapConflicts obj) then
			(	
				local nElements = bakeInterface.NumBakeElements()
				for i = 1 to nElements do
				(
					local myElement = bakeInterface.GetBakeElement i 
					if myElement.enabled and (myElement.targetMapSlotName == "" or myElement.targetMapSlotName == " ") do
						append gTextureBakeDialog.missingDataList (bakeElementStruct myElement obj)
				)
			)
		)
		
		if gTextureBakeDialog.missingDataList.count != 0 do
		(	
			createDialog missingMapTargetsRO modal:true pos:pMissingMapTargetsPos
		)
	)
	(RTT_data.emptyTargetsOk != 0)
) -- end - function MapTargetsOK

-- function to check to make sure there are no missing map files
-- returns true if ok to render, false if not
--
function MapFilesOK _ObjectList =
(
	local missingMapFilesRO 
	rollout missingMapFilesRO "Missing Map Files" width:500
	(
		local itemList = #()
		group ""
		(	label lbl1 "The following nodes are missing map files and may not render correctly:" align:#left offset:[0,-10]
		)
		multiListBox mlAvailableElements "" width:493 height:20  offset:[-10,0]-- height is measured in Lines, not pixels
		button bContinue "Continue" across:2
		button bCancel "Cancel" 
		
		-- prepare the class list
		on missingMapFilesRO open do
		(
			for ele in gTextureBakeDialog.missingDataList do
			(
				append itemList (ele[1].name + ": ")
				local maps = ele[2]
				for m in maps do
					append itemList ("   "+m)
			)
			mlAvailableElements.items = itemList 
		)
		
		on missingMapFilesRO close do
		(
			pMissingMapFilesPos = GetDialogPos missingMapFilesRO
			gTextureBakeDialog.missingDataList = undefined
		)
		
		-- Continue handler
		on bContinue pressed do
		(
			-- set flag in gTextureBakeDialog to continue
			gTextureBakeDialog.cancelRender = false
			-- and destroy the dialog
			destroydialog missingMapFilesRO
		)
		-- Cancel handler
		on bCancel pressed do
		(
			-- set flag in gTextureBakeDialog to cancel
			gTextureBakeDialog.cancelRender = true
			-- and destroy the dialog
			destroydialog missingMapFilesRO
		)
	)
	
	if _debug do format "in MapFilesOK : %\n" _ObjectList
	
	local missingMapsForNodes = #()
	for obj in _ObjectList do
	(
		local missingMaps=#()
		function addmap mapfile missingMaps = 
		(
			local found = false
			for m in missingMaps while not found do
				if (stricmp m mapfile) == 0 do found = true
			if not found do append missingMaps mapfile
		)

		-- force render to use original material for baking
		local saveRenderMtlIndex = -1
		local materialType = classof obj.material
		if (materialType == Shell_Material) then
		(
			saveRenderMtlIndex = obj.material.renderMtlIndex
			with undo off obj.material.renderMtlIndex = 0
		)

		enumerateFiles obj addmap missingMaps #missing #render #skipVPRender
		
		if saveRenderMtlIndex != -1 do
			with undo off obj.material.renderMtlIndex = saveRenderMtlIndex
		
		if missingMaps.count != 0 do
		(
			sort missingMaps
			append missingMapsForNodes #(obj,missingMaps)
		)
	)
	gTextureBakeDialog.missingDataList = missingMapsForNodes
	
	gTextureBakeDialog.cancelRender = false
	if missingMapsForNodes.count != 0 do
	(	
		createDialog missingMapFilesRO modal:true pos:pMissingMapFilesPos 
	)
	
	(not gTextureBakeDialog.cancelRender)
) -- end - function MapFilesOK

function OutputDirsOK _ObjectList =
(
	local invalidOutDirRO 
	rollout invalidOutDirRO "Invalid Output Directories" width:500
	(
		local itemList = #()
		group ""
		(	label lbl1 "The following nodes output to invalid directories and will not be rendered:" align:#left offset:[0,-10]
		)
		multiListBox mlAvailableElements "" width:493 height:20  offset:[-10,0]-- height is measured in Lines, not pixels
		button bContinue "Continue" across:2
		button bCancel "Cancel" 
		
		-- prepare the class list
		on invalidOutDirRO open do
		(
			for ele in gTextureBakeDialog.missingDataList do
			(
				append itemList (ele[1].name + ": ")
				local maps = ele[2]
				for m in maps do
					append itemList ("   "+m)
			)
			mlAvailableElements.items = itemList 
		)
		
		on invalidOutDirRO close do
		(
			pInvalidOutDirPos = GetDialogPos invalidOutDirRO 
			gTextureBakeDialog.missingDataList = undefined
		)
		
		-- Continue handler
		on bContinue pressed do
		(
			-- set flag in gTextureBakeDialog to continue
			gTextureBakeDialog.cancelRender = false
			-- and destroy the dialog
			destroydialog invalidOutDirRO
		)
		-- Cancel handler
		on bCancel pressed do
		(
			-- set flag in gTextureBakeDialog to cancel
			gTextureBakeDialog.cancelRender = true
			-- and destroy the dialog
			destroydialog invalidOutDirRO
		)
	)
	
	if _debug do format "in OutputDirsOK: %\n" _ObjectList
	
	local invalidOutDirForNodes = #()
	local defaultPath = commonBakeProps.GetFilePath()
	
	pushprompt "validating and creating output directories"
	
	for obj in _ObjectList do
	(
		local invalidOutDir=#()
		function addDir missingDirs dir = 
		(
			local found = false
			for m in missingDirs while not found do
				if (stricmp m dir) == 0 do found = true
			if not found do append missingDirs dir
		)

		RTT_methods.UpdateBitmapFilenames obj "" defaultPath defaultFileType 

		local bakeInterface = obj.INodeBakeProperties
		local nElements = bakeInterface.numBakeElements()
		for i = 1 to nElements do
		(
			-- get the element
			local ele = bakeInterface.getBakeElement i
			
			if ele.enabled do
			(
				-- see if the directory exists or can be created
				local theDir = getFilenamePath ele.fileType
				local res = RTT_methods.ValidateDirectory theDir
				if not res do addDir invalidOutDir theDir 
			)
		) -- end, for each element

		if invalidOutDir.count != 0 do
			append invalidOutDirForNodes #(obj,invalidOutDir)
	)
	gTextureBakeDialog.missingDataList = invalidOutDirForNodes 

	popprompt()
	
	gTextureBakeDialog.cancelRender = false
	if invalidOutDirForNodes.count != 0 do
	(	
		createDialog invalidOutDirRO modal:true pos:pInvalidOutDirPos 
		
		if (not gTextureBakeDialog.cancelRender) do
			for ele in invalidOutDirForNodes do
				deleteItem _ObjectList (findItem _ObjectList ele[1])
	)
	 
	(not gTextureBakeDialog.cancelRender)
) -- end - function OutputDirsOK 


------------------------------------------------------------------
--
--	Function to ensure that the set of objects have unique names
--
function NodeNamesOK _ObjectList =
(
	local res = true
	local nodeNames = #()
	local noDupes = true
	for o in _ObjectList do
	(
		if noDupes do noDupes = (findItem nodeNames o.name) == 0
		append nodeNames o.name
	)
	if _debug do format "in NodeNamesOK: %\n" nodeNames 
	if _debug do format "in NodeNamesOK: %\n" noDupes
	
	if not noDupes do
	(
		local duplicateNodeNameErrorText = "Duplicate node names exist for the nodes to bake.\r"+
			"This will result in multiple nodes writing to the same bitmap output files, giving incorrect results.\r\r"+
			"Permanently rename nodes to make unique (Yes), render with current names (No),\r"+
			"or cancel render (Cancel)?"
		res = yesNoCancelBox duplicateNodeNameErrorText  title:"Rename Duplicate Node Names?"
		
		if res == #Cancel then
			res = false
		else if res == #yes then
		(
			for i = 1 to _ObjectList.count do
			(
				nodeNames[i] = &undefined
				local k
				while ((k = findItem nodeNames _ObjectList[i].name) != 0) do
					_ObjectList[k].name = nodeNames[k] = uniqueName (_ObjectList[k].name+"_")
			)
--			selectedObjectProps.RefreshObjectsLV workingObjectsOnly:true 
			res = true
		)
		else
			res = true
	)
	res
) -- end - function NodeNamesOK 


------------------------------------------------------------------
--
--	Function to display Continue/Cancel w/Don't try again checkbox. Up to 10 lines of message
--
-- results: 0 - cancel, 1- ok, 2 - ok, don't show again
function DisplayOKCancelDontShowAgainDialog title msg continueButtonText:"Continue" cancelButtonText:"Cancel" &pos: =
(
	struct DisplayOKCancelDontShowAgainDialogData_sdef (title, msg, pos, continueButtonText, cancelButtonText, res=1, myrollout, msgLines)
	::DisplayOKCancelDontShowAgainDialogDataInstance = DisplayOKCancelDontShowAgainDialogData_sdef title msg pos continueButtonText cancelButtonText
	rollout OKCancelDontShowAgainDialog "" width:240 height:0
	(
		local data
		local thisRollout
		label msgTxt01 "" align:#center
		label msgTxt02 "" align:#center
		label msgTxt03 "" align:#center
		label msgTxt04 "" align:#center
		label msgTxt05 "" align:#center
		label msgTxt06 "" align:#center
		label msgTxt07 "" align:#center
		label msgTxt08 "" align:#center
		label msgTxt09 "" align:#center
		label msgTxt10 "" align:#center
		button bContinue "Continue" width:95 height:24 across:2 align:#right offset:[-10,2]
		button bCancel "Cancel" width:95 height:24 align:#left offset:[10,2]
		checkbox cNotAgain "Don't show this message again" checked:false 
		function setMsgText text = 
		(
			local msgLines = DisplayOKCancelDontShowAgainDialogDataInstance.msgLines
			local txtHeight = 0
			local nlines = amin msgLines.count 10
			for i = 1 to  nlines do 
			(
				local txt = msgLines[i]
				OKCancelDontShowAgainDialog.controls[i].text = txt
				if txt == "" do txt = "X"
				local extents = getTextExtent txt
				txtHeight += extents.y + 5
			)
			
			local buttonLineY = msgTxt01.pos.y + txtHeight + 10
			local dotShowLineY = 29 + buttonLineY
			bContinue.pos = [ OKCancelDontShowAgainDialog.width/2 - 10 - 95, buttonLineY ]
			bCancel.pos = [ OKCancelDontShowAgainDialog.width/2 + 10, buttonLineY ]
			cNotAgain.pos =[10, dotShowLineY]
			OKCancelDontShowAgainDialog.height = 52 + buttonLineY
		)

		on OKCancelDontShowAgainDialog open do
		(	
			data = DisplayOKCancelDontShowAgainDialogDataInstance
			data.myrollout = OKCancelDontShowAgainDialog
			OKCancelDontShowAgainDialog.title = data.title
			setMsgText data.msg
			bContinue.text = data.continueButtonText
			bCancel.text = data.cancelButtonText
		)
		on OKCancelDontShowAgainDialog close do
		(	
			data.pos = GetDialogPos OKCancelDontShowAgainDialog
		)
		on bCancel pressed do 
		(
			data.res = 0
			destroydialog OKCancelDontShowAgainDialog
		)
		on bContinue pressed do
		(
			data.res = if cNotAgain.checked then 2 else 1
			destroydialog OKCancelDontShowAgainDialog
		)

	)	

	local dialogPos = pos

	local msgLines = filterString msg "\n" splitEmptyTokens:true
	DisplayOKCancelDontShowAgainDialogDataInstance.msgLines = msgLines
	local txtWidth = 200
	local nlines = amin msgLines.count 10
	for i = 1 to nlines do 
	(
		local txt = msgLines[i]
		local extents = getTextExtent txt
		txtWidth = amax txtWidth extents.x
	)
	local dialogWidth = txtWidth + 40

	createDialog OKCancelDontShowAgainDialog modal:true pos:dialogPos width:dialogWidth -- style:#(#style_titlebar, #style_border)
	try (pos = DisplayOKCancelDontShowAgainDialogDataInstance.pos)
	catch()
	local res = DisplayOKCancelDontShowAgainDialogDataInstance.res
--	DisplayOKCancelDontShowAgainDialogDataInstance = undefined
	res
)

----------------------------------------------------------------------------
--
--	Routine to handle checking of exposure control
--
-- returns true if ok to render based on exposure control 
function ExposureControlOK =
(
	local expc = SceneExposureControl.exposureControl
	local expc_class = classof expc
	if ((expc_class == Automatic_Exposure_Control) or (expc_class == Linear_Exposure_Control)) and 
		expc.active then
	(
		if RTT_data.exposureControlOK < 2 then -- if 0 or 1 ...
		(
			local expc_class = classof SceneExposureControl.exposureControl
			--LOC_NOTES: localize following
			local msg = "Warning: You are using " +  expc_class.localizedname + "."
			msg += "\nThis exposure control calculates the exposure of each object separately, "
			msg +=  "\nwhich is not desirable because each object will have a different"
			msg +=  "\nexposure and things will never render correctly when put together."
			RTT_data.exposureControlOK = DisplayOKCancelDontShowAgainDialog "ExposureControl Warning" msg cancelButtonText:"Cancel Render" pos:&pExposureControlOKBoxPos
		)
		RTT_data.exposureControlOK > 0 -- return value
	)
	else
		true -- return value
) -- end - function OkToOverwrite fn ExposureControlOK = 

	
------------------------------------------------------------------
--
--	Function to determine if a given bake element class can be used with a given renderer class
--		
function IsCompatibleWithRenderer _ElementClass _RendererClass =
(
	-- Ambient Occlusion shader not supported in Scanline Renderer
	-- Currently there's no other script-exposed method to check for compatibility
	(_ElementClass != AmbientOcclusionBakeElement) or (_RendererClass != Default_Scanline_Renderer)
)
	
------------------------------------------------------------------
--
--	Function to bake a set of textures on each of a set of objects
--
--  returns #cancel if render cancelled, ok otherwise
function BakeNodes _NodesList _ProgressScale _NodeIndex _BakeProgress allowCreateMtl subObjBake =
(
	if _debug do format "in BakeNodes _NodesList: % _ProgressScale: % _NodeIndex: % _BakeProgress: % allowCreateMtl: % subObjBake: %\n" \
						_NodesList _ProgressScale _NodeIndex _BakeProgress allowCreateMtl subObjBake
	local vfbOn = commonBakeProps.cDisplayFB.checked
	local defaultPath = commonBakeProps.GetFilePath()
	local progressScale = _ProgressScale
	local nodeIndex = _NodeIndex
	local bakeProgress = _BakeProgress
	
	-- bake the object
	local w = _NodesList[1].renderWidth()
	local h = _NodesList[1].renderHeight()		
	if _debug do format "bake object % to % x % \n" (_NodesList[1].name) w h
	
	if (curBM == undefined) or (curBM.width != w ) or (curBM.height != h) then
	(	
		-- create new bm
		if curBM != undefined then 
			close curBM -- close the VFB and free bitmap's memory
		curBM = bitmap w h
	)
	
	local updateFileNamesArray = #() -- stores element output file name for each frame
	for i = 1 to _NodesList.count do
		append updateFileNamesArray #()
	
	-- local restoreToGroup = false
	local restoreToGroupArray = #{}
	for i = 1 to _NodesList.count do
	(	
		local obj = _NodesList[i]	
		if isGroupMember obj then
		(
			setGroupMember obj false
			restoreToGroupArray[i]=true
		)
	)
	
	-- local saveRenderMtlIndex = -1
	local saveRenderMtlIndices = #()
	local clearNodeMaterial = #()
	with undo off 
	(
		--  select the objects
		select _NodesList
		
		for i = 1 to _NodesList.count do
		(	
			local obj = _NodesList[i]
			if _debug do format "rendering: % : % : %\n" obj.name obj.INodeBakeProjProperties.enabled  obj.INodeBakeProjProperties.projectionModTarget
			-- force render to use original material for baking
			local materialType = classof obj.material
			if (materialType == Shell_Material and obj.material.renderMtlIndex != 0) then
			(
				-- saveRenderMtlIndex = obj.material.renderMtlIndex
				append saveRenderMtlIndices obj.material.renderMtlIndex
				obj.material.renderMtlIndex = 0
			)
			else
			(
				append saveRenderMtlIndices -1
			)
			-- if no material on node, set to standard material. This is needed in order for supersampling to operate correctly.
			local noMtl = obj.material == undefined
			append clearNodeMaterial noMtl 
			if noMtl do
				obj.material = standard shaderType:5 diffuseColor:obj.wirecolor specularcolor:(color 51 51 51) specularLevel:100 glossiness:20 soften:0
		) -- end, for each object
	)

	-- for each frame
	local frameCount = 0
	local renderFrameList = RTT_methods.GetRenderFrames()
	local numFrames = renderFrameList.count
	for nFrame in renderFrameList do
	(
		frameCount += 1
		-- update the bitmap names
		local n = if (rendTimeType == 2) or (rendTimeType == 3) then 
					(nFrame + rendFileNumberBase) 
					else nFrame
					
		for i = 1 to _NodesList.count do
		(	
			local obj = _NodesList[i]
			local geomSelName = if subObjBake then obj.INodeBakeProjProperties.projectionModTarget else ""
			RTT_methods.UpdateBitmapFilenames obj n defaultPath defaultFileType subObjectName:geomSelName
		)
		
		-- update the progress bar
		bakeProgress.pb1.value = progressScale * ( ((nodeIndex-1) * numFrames) + ((frameCount - 1) * _NodesList.count))
		if _debug do format "\trender status: % : % : % : % : % : %\n" bakeProgress.pb1.value progressScale nodeIndex numFrames nFrame frameCount 

		local skipRender = false
		if (commonBakeProps.cSkipExistingFiles.checked) then
		(	
			for i = 1 to _NodesList.count do
			(	
				local obj = _NodesList[i]				
				if (RTT_methods.CheckAllBakeElementOutputFilesExist obj) do deselect obj
			)
			if $selection.count == 0 do skipRender = true
		)
		else
		(
			for nodeIndex = 1 to _NodesList.count do
			(	
				local obj = _NodesList[nodeIndex]		
					
				-- check if the files already exist
				if not (CheckFileOverwrite obj) then
				(
					-- don't overwrite files, boot
					--format "can't overwrite files\n"
					destroydialog bakeProgress 

					with undo off 
					(
						for i = 1 to _NodesList.count do
						(	
							local obj = _NodesList[i]				
							if	restoreToGroupArray[i] do
								setGroupMember obj true
							if saveRenderMtlIndices[i] >= 0 do
								obj.material.renderMtlIndex = saveRenderMtlIndices[i] 
							if clearNodeMaterial[i] do
								obj.material = undefined
						)
						if selectedObjects.count != 0 then select selectedObjects else clearSelection()	-- reselect
					)
					
					return #cancel	-- cancel
				)
			)
		)
	
		-- render the texture elements
		if _debug do format "\trender frame % \n" nFrame
		local wasCanceled = false
		local oldsilentmode = setSilentMode true
		
		try
		(
			if (not skipRender) do 
			(
				if _debug do 
				(
					for obj in selection do
					(
						local inbp = obj.INodeBakeProperties
						local inbpp = obj.INodeBakeProjProperties
						format "rendering node: % : % : % : % : %\n" obj.name inbpp.enabled inbpp.projectionMod inbpp.projectionModTarget inbp.bakeChannel
					)
				)
				render rendertype:#bakeSelected frame:nFrame to:curBM vfb:vfbOn cancelled:&wasCanceled disableBitmapProxies:true
				if (cached_RadiosityPreferences_computeRadiosity == undefined) do
				(
					cached_RadiosityPreferences_computeRadiosity = RadiosityPreferences.computeRadiosity
					RadiosityPreferences.computeRadiosity = false
				)
			)
			setSilentMode oldsilentmode 
		)
		catch
		(
			destroydialog bakeProgress 

			with undo off 
			(
				for i = 1 to _NodesList.count do
				(	
					local obj = _NodesList[i]				
					if	restoreToGroupArray[i] do
						setGroupMember obj true
					if saveRenderMtlIndices[i] >= 0 do
						obj.material.renderMtlIndex = saveRenderMtlIndices[i] 
					if clearNodeMaterial[i] do
						obj.material = undefined
				)
				if selectedObjects.count != 0 then select selectedObjects else clearSelection()	-- reselect
			)

			setSilentMode oldsilentmode 
			messageBox "System exception occurred during render" title:"Render To Texture" --LOC_NOTES: localize this

			return #cancel	-- cancel
		)
	
		if (  wasCanceled ) then
		(
			destroydialog bakeProgress 

			with undo off 
			(
				for i = 1 to _NodesList.count do
				(	
					local obj = _NodesList[i]				
					if	restoreToGroupArray[i] do
						setGroupMember obj true
					if saveRenderMtlIndices[i] >= 0 do
						obj.material.renderMtlIndex = saveRenderMtlIndices[i] 
					if clearNodeMaterial[i] do
						obj.material = undefined
				)
				if selectedObjects.count != 0 then select selectedObjects else clearSelection()	-- reselect
			)

			setSilentMode oldsilentmode 
			messageBox "Render Failed or Cancelled by User" title:"Render To Texture" --LOC_NOTES: localize this

			return #cancel	-- cancel
		)
		
		--format "collect files for frame = %\n" nFrame
		for i = 1 to _NodesList.count do
		(	
			local obj = _NodesList[i]
			local inbpp = obj.INodeBakeProjProperties
			local useObjBakeForMtl = (not inbpp.enabled) or (inbpp.BakeObjectLevel and inbpp.useObjectBakeForMtl)
			local useSubObjBakeForMtl = inbpp.enabled and inbpp.BakeSubObjLevels and (not inbpp.useObjectBakeForMtl)
			if _debug do 
				format	"conditional for CollectUpdateFiles - obj material undefined:%; allowCreateMtl:%; useObjBakeForMtl:%; useSubObjBakeForMtl:%; subObjBake:%\n" \
						clearNodeMaterial[i] allowCreateMtl useObjBakeForMtl useSubObjBakeForMtl subObjBake
			if ((not clearNodeMaterial[i]) or allowCreateMtl) and ((useObjBakeForMtl and (not subObjBake)) or (useSubObjBakeForMtl and subObjBake)) do
				CollectUpdateFiles obj updateFileNamesArray[i] subObjBake
		)
		
		-- update height buffer vals in Projection Options dialog
		if RTT_data.projectionOptionsPropsRO != undefined do
			RTT_data.projectionOptionsPropsRO.UpdateHeightBufferDisplay()

		if _trackMemory do
		(	r1 = sysinfo.getMAXMemoryInfo()
			r2 = sysinfo.getSystemMemoryInfo()
			format "% : % : % : %\n" _NodesList[1].name nFrame r1 r2
		)
	
	) -- end, for each frame
	
	for i = 1 to _NodesList.count do
	(	
		local obj = _NodesList[i]	
		
		with undo off 
		(
			-- restore object to the group
			if	restoreToGroupArray[i] do
				setGroupMember obj true
	
			-- clear the material if we set it for the render
			if clearNodeMaterial[i] do
				obj.material = undefined
		)
		
		-- prepare baked materials?
		local inbpp = obj.INodeBakeProjProperties
		local useObjBakeForMtl = (not inbpp.enabled) or (inbpp.BakeObjectLevel and inbpp.useObjectBakeForMtl)
		local useSubObjBakeForMtl = inbpp.enabled and inbpp.BakeSubObjLevels and (not inbpp.useObjectBakeForMtl)
		if _debug do format "conditional for ApplyUpdateFiles/UpdateMaterial - obj.material:%; allowCreateMtl:%; useObjBakeForMtl:%; useSubObjBakeForMtl:%; subObjBake:%\n" obj.material allowCreateMtl useObjBakeForMtl useSubObjBakeForMtl subObjBake
		if (obj.material != undefined or allowCreateMtl) and ((useObjBakeForMtl and (not subObjBake)) or (useSubObjBakeForMtl and subObjBake)) do
		(
			ApplyUpdateFiles obj updateFileNamesArray[i] subObjBake
			if ( not bakedMtlProps.cbRenderToFilesOnly.checked ) then
				UpdateMaterial obj allowCreateMtl subObjBake
		)
	)	
		
	with undo off 
	(
		for i = 1 to _NodesList.count do
		(	
			if saveRenderMtlIndices[i] >= 0 do
			(
				local obj = _NodesList[i]				
				obj.material.renderMtlIndex = saveRenderMtlIndices[i] 
			)
		)		
	)

	if _debug do format "end of bake object\n"

	ok
)

------------------------------------------------------------------
--
--	Function to bake a set of textures on each of a set of objects
--
function BatchBake _ObjectList = 
(
	undo "Bake Objects" on 
	(
		if _debug do format "bake % objects; selection count: % : %\n"  _ObjectList.count selectedObjects.count selection.count
		
	    -- commit the render scene dialog if it's still up	
		if renderSceneDialog.isOpen() do
		(	
			renderSceneDialog.commit()
			setFocus gTextureBakeDialog
		)
		
		if not renderers.current.supportsTexureBaking do
		(	
			messageBox "Current renderer does not support texture baking" title:"Render To Texture" --LOC_NOTES: localize this
			return 0
		)
		
		local using_MR_Renderer = (classof renderers.current == mental_ray_renderer)
		
		local renderFrameList = RTT_methods.GetRenderFrames()
		if renderFrameList.count == 0 do return 0	
		
		-- collect nodes we will actually render
		local nodesToRender = #()
		for i = 1 to _ObjectList.count do
		(
			local obj = _ObjectList[i].node
			local w = obj.renderWidth()
			local h = obj.renderHeight()
			if (not obj.INodeBakeProperties.effectiveEnable()) or (ObjHasMapConflicts obj) or w <= 0 or h <= 0 then
				if _debug do format "skipping: %: % % : % %\n" obj.name (obj.effectiveEnable()) (ObjHasMapConflicts obj) w h
			else
				append nodesToRender obj 
		)
		if nodesToRender.count == 0 do return 0
		
		-- check for missing maps
		if not (MapFilesOK nodesToRender) do return 0
		
		-- check for bad output directories
		if not (OutputDirsOK nodesToRender) do return 0
		
		-- check for duplicate node names
		if not (NodeNamesOK nodesToRender) do return 0
		
		cached_RadiosityPreferences_computeRadiosity = undefined
		
		if ( not bakedMtlProps.cbRenderToFilesOnly.checked ) then
		(
			local mtl
			for n in nodesToRender where (mtl = n.material) != undefined do
			(
				setAppData mtl RTT_MtlName_AppData_Index mtl.name
				setAppData mtl (RTT_MtlName_AppData_Index+1) "N"
			)
		)

		local renderPassNodes = #(#())

		with redraw off 
		(
			local numFrames = renderFrameList.count
			local nObjAndSOCount = 0
			local maxNumSOLevels = 0
			for i = 1 to nodesToRender.count do
			(
				local theNode = nodesToRender[i]
				local inbpp = theNode.INodeBakeProjProperties
				local projMod = inbpp.projectionMod 

				if projMod != undefined and (classof projMod) != projection do
					inbpp.projectionMod = projMod = undefined
				if projMod != undefined do
				(
					local notFound = true
					for mod in theNode.modifiers while notFound do notFound = projMod != mod
					if notFound do
						inbpp.projectionMod = undefined
				)

				if projMod == undefined then
					inbpp.enabled = false
				else
					inbpp.projectionModTarget = ""

				-- render object level?
				if (not inbpp.enabled) or inbpp.BakeObjectLevel do
				(
					nObjAndSOCount += 1
					append renderPassNodes[1] theNode 

					if projMod != undefined then
					(
						local n = projMod.numGeomSels()
						local found = false
						for i = 1 to n while not found do 
						(
							local geomSelLevel = projMod.getGeomSelLevel i
							if geomSelLevel == #object do 
							(
								inbpp.projectionModTarget = projMod.getGeomSelName i
								found = true
							)
						)
					)
				)				
				-- render sub-object levels?
				if inbpp.enabled and inbpp.BakeSubObjLevels do
				(
					local numSOLevels = 0
					local n = projMod.numGeomSels()
					for i = 1 to n do 
					(
						local geomSelLevel = projMod.getGeomSelLevel i
						if geomSelLevel == #face or geomSelLevel == #element then 
						(
							nObjAndSOCount += 1
							numSOLevels += 1
							if using_MR_Renderer do
							(
								if renderPassNodes[numSOLevels+1] == undefined do renderPassNodes[numSOLevels+1] = #()
								append renderPassNodes[numSOLevels+1] (NodeGeomSelStruct theNode i)
							)
						)
						else if geomSelLevel == #object do inbpp.projectionModTarget = projMod.getGeomSelName i
					)
					maxNumSOLevels = amax maxNumSOLevels numSOLevels 
				)
			)
			if _debug do format "\tnumFrames: %; nObjAndSOCount: %; maxNumSOLevels: %; \n" numFrames nObjAndSOCount maxNumSOLevels 
				
			-- create the bake progress dialog
			local progressScale = 100. / (nObjAndSOCount * numFrames)
			if _debug do format "\tprogressScale: %; numFrames: %\n" progressScale numFrames 
		
			rollout bakeProgress "Progress..." width:183 height:48
			(
				label lbl1 "Baking Textures..." pos:[48,6] width:94 height:21
				progressBar pb1 "" pos:[5,22] width:174 height:17
				on bakeProgress close do
					pBakeProgressPos = GetDialogPos bakeProgress  
			)
			-- & put it up
			createdialog bakeProgress  pos:pBakeProgressPos
			bakeProgress.pb1.value = 0 
			
			-- Render Pass 1 - render object level 
			local res = ok
			if using_MR_Renderer then			
			(
				-- bake all objects at once
				if renderPassNodes[1].count > 0 do
					res = BakeNodes renderPassNodes[1] progressScale 1 bakeProgress true false -- allowCreateMtl:true subObjBake:false
			)
			else 
			(				
				-- bake each object in turn
				local nodesList = #(undefined)
				local renderPass1Nodes = renderPassNodes[1]
				for i = 1 to renderPass1Nodes.count while res == ok do
				(
					nodesList[1] = renderPass1Nodes[i]
					res = BakeNodes nodesList progressScale i bakeProgress true false -- allowCreateMtl:true subObjBake:false
				) -- end, for each object
			)
			
			local progressCount = renderPassNodes[1].count 
			renderPassNodes[1] = undefined
			
			-- Render Pass 2 - render subobject level 
			-- split for MR again? In M nodes each have N geomSels, we should be able to just do N MR renders instead of MxN
			if using_MR_Renderer then			
			(
				local firstSORender = true

				-- bake all objects at once
				for soLevel = 1 to maxNumSOLevels while res == ok do
				(
					local nodesList = #()
					local renderPassData = renderPassNodes[soLevel+1]
					nodesList.count = renderPassData.count
					for i = 1 to renderPassData.count do
					(
						local renderPassNodeData = renderPassData[i]
						local theNode = renderPassNodeData.node
						nodesList[i] = theNode
						local inbpp = theNode.INodeBakeProjProperties
						local inbp = theNode.INodeBakeProperties
						local projMod = inbpp.projectionMod 
						local geomSelIndex = renderPassNodeData.geomSelIndex
						local geomSelName = projMod.getGeomSelName geomSelIndex
						inbpp.projectionModTarget = geomSelName 
						if inbpp.proportionalOutput do
						(
							local totalSurfArea = projMod.getGeomSelFaceArea theNode 0
							local geomSelSurfArea = projMod.getGeomSelFaceArea theNode geomSelIndex
							local geomSelSurfAreaFrac = if totalSurfArea > 1e-10 then (sqrt geomSelSurfArea)/(sqrt totalSurfArea) else 1.
							geomSelSurfAreaFrac *= projMod.getGeomSelMapProportion geomSelIndex
							local elementOutSizes
							elementOutSizes = renderPassNodeData.eleOutSizes = #()
							local numBakeElements = inbp.numBakeElements()
							elementOutSizes.count = numBakeElements 
							for j = 1 to numBakeElements do
							(
								local ele = inbp.getBakeElement j
								local szX = ele.outputSzX
								local szY = ele.outputSzY
								elementOutSizes[j] = Point2 szX szY 
								if (szX != 0) do szX = amax (ceil szX*geomSelSurfAreaFrac) 1
								if (szY != 0) do szY = amax (ceil szY*geomSelSurfAreaFrac) 1
								ele.outputSzX = szX 
								ele.outputSzY = szY 
							)
						)
						renderPassNodeData.bakeChannel = inbp.bakeChannel
						inbp.bakeChannel = inbpp.subObjBakeChannel 
					)
					res = BakeNodes nodesList progressScale (progressCount += renderPassData.count) bakeProgress firstSORender true -- allowCreateMtl:firstSORender subObjBake:true
					firstSORender = false
					for i = 1 to renderPassData.count do
					(
						local renderPassNodeData = renderPassData[i]
						local theNode = renderPassNodeData.node
						local inbpp = theNode.INodeBakeProjProperties
						local inbp = theNode.INodeBakeProperties
						inbpp.projectionModTarget = "" 
						if inbpp.proportionalOutput do
						(
							local elementOutSizes = renderPassNodeData.eleOutSizes
							local numBakeElements = inbp.numBakeElements()
							for j = 1 to numBakeElements do
							(
								local ele = inbp.getBakeElement j
								local outputSz = elementOutSizes[j]
								ele.outputSzX = outputSz.x
								ele.outputSzY = outputSz.y
							)
						)
						inbp.bakeChannel = renderPassNodeData.bakeChannel
						renderPassNodes[soLevel+1] = undefined
					)
				)
			)
			else 
			(
				-- bake each object in turn 
				local nodesList = #(undefined)
				for i = 1 to nodesToRender.count while res == ok do
				(
					local theNode = nodesToRender[i]
					local inbpp = theNode.INodeBakeProjProperties
					local inbp = theNode.INodeBakeProperties
					if inbpp.enabled and inbpp.BakeSubObjLevels do
					(
						local projMod = inbpp.projectionMod 
						local numGeomSels = projMod.numGeomSels()
						local firstSORender = true
						local totalSurfArea
						if inbpp.proportionalOutput do
							totalSurfArea = projMod.getGeomSelFaceArea theNode 0
						for i = 1 to numGeomSels while res == ok do 
						(
							local geomSelLevel = projMod.getGeomSelLevel i
							if geomSelLevel == #face or geomSelLevel == #element do
							(
								local geomSelName = projMod.getGeomSelName i
								inbpp.projectionModTarget = geomSelName 
								nodesList[1] = theNode
								local elementOutSizes 
								local numBakeElements
								if inbpp.proportionalOutput do
								(
									local geomSelSurfArea = projMod.getGeomSelFaceArea theNode i
									local geomSelSurfAreaFrac = if totalSurfArea > 1e-10 then (sqrt geomSelSurfArea)/(sqrt totalSurfArea) else 1.
									geomSelSurfAreaFrac *= projMod.getGeomSelMapProportion i
									elementOutSizes = #()
									numBakeElements = inbp.numBakeElements()
									elementOutSizes.count = numBakeElements 
									for j = 1 to numBakeElements do
									(
										local ele = inbp.getBakeElement j
										local szX = ele.outputSzX
										local szY = ele.outputSzY
										elementOutSizes[j] = Point2 szX szY 
										if (szX != 0) do szX = amax (ceil szX*geomSelSurfAreaFrac) 1
										if (szY != 0) do szY = amax (ceil szY*geomSelSurfAreaFrac) 1
										ele.outputSzX = szX 
										ele.outputSzY = szY 
									)
								)
								local mapChannel_Obj = inbp.bakeChannel
								inbp.bakeChannel = inbpp.subObjBakeChannel 
								res = BakeNodes nodesList progressScale (progressCount+=1) bakeProgress firstSORender true -- allowCreateMtl:firstSORender subObjBake:true
								inbp.bakeChannel = mapChannel_Obj
								if inbpp.proportionalOutput do
								(
									for j = 1 to numBakeElements do
									(
										local ele = inbp.getBakeElement j
										local elementOutSize = elementOutSizes[j] 
										ele.outputSzX = elementOutSize.x
										ele.outputSzY = elementOutSize.y
									)
								)
								firstSORender = false
							)
						)
						inbpp.projectionModTarget = "" 
					)
				)
			)
			
			-- toss the progress dialog
			destroydialog bakeProgress
			
			-- reselect
			with undo off if selectedObjects.count != 0 then select selectedObjects else clearSelection()
		
			if (cached_RadiosityPreferences_computeRadiosity != undefined) do
				RadiosityPreferences.computeRadiosity = cached_RadiosityPreferences_computeRadiosity

			if ( not bakedMtlProps.cbRenderToFilesOnly.checked ) then
			(
				local mtl
				for n in nodesToRender where (mtl = n.material) != undefined do
				(
					deleteAppData mtl RTT_MtlName_AppData_Index
					deleteAppData mtl (RTT_MtlName_AppData_Index+1)
				)
			)

		) -- end, with redraw off

	) -- end, undo "Batch Bake"	

	if _debug do format "bake exit; selection count: % : %\n"  selectedObjects.count selection.count
) -- end, function BatchBake 

------------------------------------------------------------------
--
--	Function to send a set of objects to the net renderer for baking
--
function NetBatchBake _ObjectList = 
(
	if _debug do format "net bake % objects; selection count: % : %\n"  _ObjectList.count selectedObjects.count selection.count
	
    -- commit the render scene dialog if it's still up		
	if renderSceneDialog.isOpen() do
	(	
		renderSceneDialog.commit()
		setFocus gTextureBakeDialog
	)
	
	-- select the settings to use
--	renderer = if (commonBakeProps.rDraftOrProduction.state == 1) then #production else #draft
	
	-- cache the renderer's skip render frames and Show VFB settings. We will replace them with the local setting
	local old_skipRenderedFrames = skipRenderedFrames 
	local old_rendShowVFB = rendShowVFB
	local defaultPath = commonBakeProps.GetFilePath()
	
	-- collect nodes we will actually render
	local nodesToRender = #()
	for i = 1 to _ObjectList.count do
	(
		local obj = _ObjectList[i].node
		local w = obj.renderWidth()
		local h = obj.renderHeight()
		if (not obj.INodeBakeProperties.effectiveEnable()) or (ObjHasMapConflicts obj) or w <= 0 or h <= 0 then
			if _debug do format "skipping: %: % % : % %\n" obj.name (obj.effectiveEnable()) (ObjHasMapConflicts obj) w h
		else
		(
			append nodesToRender obj 
			local inbpp = obj.INodeBakeProjProperties
			local projMod = inbpp.projectionMod 

			if projMod != undefined and (classof projMod) != projection do
				inbpp.projectionMod = projMod = undefined
			if projMod != undefined do
			(
				local notFound = true
				for mod in obj.modifiers while notFound do notFound = projMod != mod
				if notFound do
					inbpp.projectionMod = undefined
			)

			if projMod == undefined then
				inbpp.enabled = false
			else
				inbpp.projectionModTarget = ""

			RTT_methods.UpdateBitmapFilenames obj "" defaultPath defaultFileType 
		)
	)
	if nodesToRender.count == 0 do return 0
	
	-- check for missing maps
	if not (MapFilesOK nodesToRender) do return 0
	
	-- check for duplicate node names
	if not (NodeNamesOK nodesToRender) do return 0

	if nodesToRender.count != 0 do
	(
		skipRenderedFrames = commonBakeProps.cSkipExistingFiles.checked
		rendShowVFB = commonBakeProps.cDisplayFB.checked
		fileproperties.addproperty #custom "RTT_Default_Path" defaultPath 
		fileproperties.addproperty #custom "RTT_Default_FileType" defaultFileType 
		fileproperties.addproperty #custom "RTT_RenderTimeType" rendTimeType
		
		local res = NetworkRTT nodesToRender
		if not res do messagebox "net render submission failed" title:"Render To Texture" --LOC_NOTES: localize this

		fileproperties.deleteproperty #custom "RTT_Default_Path" 
		fileproperties.deleteproperty #custom "RTT_Default_FileType"
		fileproperties.deleteproperty #custom "RTT_RenderTimeType"
		skipRenderedFrames = old_skipRenderedFrames
		rendShowVFB = old_rendShowVFB
	)
			
	if _debug do format "net bake exit; selection count: % : %\n"  selectedObjects.count selection.count
) -- end, function NetBatchBake 

------------------------------------------------------------------
--
--	Function to update the baked materials on each of a set of objects. 
--  Same as a bake without doing the actual rendering
--
function UpdateBakedMtls _ObjectList = 
(
	undo "Update Baked Mtls" on 
	(
		if _debug do format "Update Baked Mtls - % objects\n"  _ObjectList.count
		
	    -- commit the render scene dialog if it's still up		
		if renderSceneDialog.isOpen() do
		(	
			renderSceneDialog.commit()
			setFocus gTextureBakeDialog
		)
		
		local renderFrameList = RTT_methods.GetRenderFrames()
		if renderFrameList.count == 0 do return 0	

		local defaultPath = commonBakeProps.GetFilePath()

		-- collect nodes we will actually render
		local nodesToRender = #()
		for i = 1 to _ObjectList.count do
		(
			local obj = _ObjectList[i].node
			local w = obj.renderWidth()
			local h = obj.renderHeight()
			if (not obj.INodeBakeProperties.effectiveEnable()) or (ObjHasMapConflicts obj) or w <= 0 or h <= 0 then
				if _debug do format "skipping: %: % % : % %\n" obj.name (obj.effectiveEnable()) (ObjHasMapConflicts obj) w h
			else
				append nodesToRender obj 
		)
		if nodesToRender.count == 0 do return 0

		local mtl
		for n in nodesToRender where (mtl = n.material) != undefined do
		(
			setAppData mtl RTT_MtlName_AppData_Index mtl.name
			setAppData mtl (RTT_MtlName_AppData_Index+1) "N"
		)

		-- pseudo-bake each object in turn
		-- render pass 1
		for i = 1 to nodesToRender.count do
		(
			local obj = nodesToRender[i]
			local inbpp = obj.INodeBakeProjProperties
			local inbp = obj.INodeBakeProperties
			local projMod = inbpp.projectionMod 

			if projMod != undefined and (classof projMod) != projection do
				inbpp.projectionMod = projMod = undefined
			if projMod != undefined do
			(
				local notFound = true
				for mod in obj.modifiers while notFound do notFound = projMod != mod
				if notFound do
					inbpp.projectionMod = undefined
			)

			if projMod == undefined then
				inbpp.enabled = false
			else
				inbpp.projectionModTarget = ""

			-- use render object level output?
			local useObjBakeForMtl = (not inbpp.enabled) or (inbpp.BakeObjectLevel and inbpp.useObjectBakeForMtl)
			if _debug do format "useObjBakeForMtl:% : % : % : %\n" useObjBakeForMtl inbpp.enabled inbpp.BakeObjectLevel inbpp.useObjectBakeForMtl
			if useObjBakeForMtl do
			(
				-- update the bitmap names and the material
				if _debug do format "update bake mtl on object - render pass 1: %\n" obj.name
						
				local updateFileNamesArray = #() -- stores element output file name for each frame
				for nFrame in renderFrameList do
				(
					-- find the frame number for the bitmap file
					local n = if (rendTimeType == 2) or (rendTimeType == 3) then 
								(nFrame + rendFileNumberBase) 
							  else nFrame
					
					RTT_methods.UpdateBitmapFilenames obj n defaultPath defaultFileType subObjectName:""
					CollectUpdateFiles obj updateFileNamesArray false
				)
					
				ApplyUpdateFiles obj updateFileNamesArray false
				UpdateMaterial obj true false
				if _debug do format "end of render pass 1 update bake mtl on object\n"
			)
		) -- end, for each object

		-- render pass 2
		for i = 1 to nodesToRender.count do
		(
			local obj = nodesToRender[i]
			local inbpp = obj.INodeBakeProjProperties
			local inbp = obj.INodeBakeProperties
			-- use render sub-object level output?
			local useSubObjBakeForMtl = inbpp.enabled and inbpp.BakeSubObjLevels and (not inbpp.useObjectBakeForMtl)
			if _debug do format "useSubObjBakeForMtl:% : % : % : %\n" useSubObjBakeForMtl inbpp.enabled inbpp.BakeSubObjLevels inbpp.useObjectBakeForMtl
			if useSubObjBakeForMtl do
			(
				if _debug do format "update bake mtl on object - render pass 2: %\n" obj.name
				local projMod = inbpp.projectionMod 
				local n = projMod.numGeomSels()
				local firstSORender = true
				for i = 1 to n do 
				(
					local geomSelLevel = projMod.getGeomSelLevel i
					if geomSelLevel == #face or geomSelLevel == #element do
					(
						local geomSelName = projMod.getGeomSelName i
						inbpp.projectionModTarget = geomSelName 
						
						-- update the bitmap names and the material
							
						local updateFileNamesArray = #() -- stores element output file name for each frame
						for nFrame in renderFrameList do
						(
							-- find the frame number for the bitmap file
							local n = if (rendTimeType == 2) or (rendTimeType == 3) then 
										(nFrame + rendFileNumberBase) 
									  else nFrame
							
							RTT_methods.UpdateBitmapFilenames obj n defaultPath defaultFileType subObjectName:inbpp.projectionModTarget
							CollectUpdateFiles obj updateFileNamesArray true
						)
							
						ApplyUpdateFiles obj updateFileNamesArray true
						UpdateMaterial obj firstSORender true
						firstSORender = false
					)
				)
				inbpp.projectionModTarget = ""
				if _debug do format "end of render pass 2 update bake mtl on object\n"
			)
			
		) -- end, for each object
		
		for n in nodesToRender where (mtl = n.material) != undefined do
		(
			deleteAppData mtl RTT_MtlName_AppData_Index
			deleteAppData mtl (RTT_MtlName_AppData_Index+1)
		)
		
	) -- end, undo "Batch Bake"	
	if _debug do format "Update Baked Mtls exit\n"
) -- end, function UpdateBakedMtls 


------------------------------------------------------------------
--
--	Function to return array of elements that are common to all the input arrays
--
function CollectCommonElements arrayList =
(
	local res = #()
	if arrayList.count == 1 then -- just return first array
		res = arrayList[1]
	else if arrayList.count > 1 do -- initialize with copy of first array
		res = copy arrayList[1] #nomap
	for i = 2 to arrayList.count while res.count != 0 do
	(
		local theArray = arrayList[i]
		for j = res.count to 1 by -1 do  -- for each element remaining in output list
		(	local index = findItem theArray res[j] -- see if it exists in input array
			if index == 0 do deleteItem res j -- if not, remove from output list
		)
	)
	res
) -- end - function CollectCommonElements

-- function returns array of the non-blank texmap slot names for material
function GetTexmapSlotNamesOfMtl mtl =
(	local nmaps = getNumSubTexmaps mtl
	local res = #()
	for i = 1 to nmaps do 
	(	
		local sname = getSubTexmapSlotName mtl i
		if sname.count != 0 do
		(
			append res sname
			local tmap = getSubTexmap mtl i
			if tmap != undefined and classof tmap == gNormal then
			(
				append res (sname + ".NormalBump." + gNormalSlot1Name)
				append res (sname + ".NormalBump." + gNormalSlot2Name)
			)
		)
	)
	res
) -- end - function GetTexmapSlotNamesOfMtl 

-- function to collect available target map names for material. 
-- If mtl has no subMaterials, return texmap slot names
-- If mtl has subMaterials, return texmap slot names present for all existing subMaterials
-- plus the mtl's texmap slot names.
-- if mtl or submtl is a Shell material, process the mtl in Original Material slot instead
-- of the Shell material
-- only walk one subMaterial level down.
function CollectTargetMapNamesForMtl mtl =
(	
	local res
	if classof mtl == Shell_Material do
		mtl = mtl.originalMaterial
	local nmtls = getNumSubMtls mtl
	if (nmtls != 0) then
	(	
		local subRes = #()
		for i = 1 to nmtls do
		(	smtl = getSubMtl mtl i
			if classof smtl == Shell_Material do
				smtl = smtl.originalMaterial
			if smtl != undefined do
				append subRes (GetTexmapSlotNamesOfMtl smtl)
		)
		res = CollectCommonElements subRes
	)
	else
		res = #()
	join res (GetTexmapSlotNamesOfMtl mtl)
	res
) -- end - function CollectTargetMapNamesForMtl

-- function to collect common available target map names for a node's material. 
function CollectTargetMapNamesForNode theNode =
(
	local res =
		if ((bakedMtlProps.rbDestination.state == 1) or (bakedMtlProps.rbShellOption.state == 1)) then
		(
			if theNode.material != undefined then
		   		CollectTargetMapNamesForMtl theNode.material
			else
				newNodeMtlTargetMapNames
		)
		else 
		(
			newBakedMtlTargetMapNames 
		)
--	if _debug do format "CollectTargetMapNamesForNode: % : %\n" theNode res
	res
) -- end - function CollectTargetMapNamesForNode

--	Function to return array of material names (localized) and instances that can be used as a RTT target mtl
function CollectMtlTypes =
(
	if _debug do format "in CollectMtlTypes - time:%\n" (timestamp())
	local mtlInstance
	local mtllist = #()
	-- collect flavors of standard material
	for i = 0 to 7 do 
	(
		mtlInstance = standard shaderType:i
		if _debug do format "\tmtlInstance: %; shaderType:% - time:%\n" mtlInstance i (timestamp())
		append mtllist (RTT_MlTypes (standard.localizedName + ":" + mtlInstance.shaderByName) mtlInstance)
	)
	-- collect creatable materials other than standard, shell, DX9
	for mtl in material.classes where mtl.creatable and mtl != standard and mtl != Shell_Material and mtl != DirectX_9_Shader do
	(
		try
		(	
			mtlInstance = mtl()
			if _debug do format "\tmtlInstance: % - time:%\n" mtlInstance (timestamp())
			if mtlInstance != undefined do
				append mtllist (RTT_MlTypes mtl.localizedName mtlInstance)
		)
		catch ()
	)
	
	if not (skip_DX9_materials or DirectX_9_Shader == undefined) do 
	(
		-- look for .fx files in the map directories and, if it exists, the fx directory in each of those directories
		-- the map directories
		local nMapPaths = mapPaths.count()
		local mapPathDirs = for i = 1 to nMapPaths collect (mapPaths.get i)
		if _debug do format "\tmapPathDirs: % : %\n" nMapPaths mapPathDirs 
		-- the fx subdirectories. Add only if not already present
		for i = 1 to nMapPaths do 
		(
			local tPath = mapPathDirs[i]+"\\fx"
			if findItem mapPathDirs tPath == 0 do append mapPathDirs tPath 
		)
		local dx9Files = #()
		for mapPath in mapPathDirs do
		(
			local fxFiles = getFiles (mapPath+"\\*.fx")
			for fxFile in fxFiles do
			(
	--			try
				(
					local fName = getFilenameFile fxFile
					local fName2 = fName as name
					if findItem dx9Files fName2 == 0 do -- only 1 instance per name, regardless of directory
					(
						append dx9Files fName2
						mtlInstance = DirectX_9_Shader effectFile:fxFile
						if _debug do format "\tmtlInstance: %; effectFile: % - time:%\n" mtlInstance fName (timestamp())
						append mtllist (RTT_MlTypes (DirectX_9_Shader.localizedName + ":" + fName) mtlInstance)
					)
				)
	--			catch()
			)
		)
	)
	mtllist -- return value
)

------------------------------------------------------------------
--
-- function for setting the default map slot name for combination of material and bake element to the ini file
-- if the default mapping doesn't already exist in the ini file
-- argument is a bakeElementStruct instance
--
function UpdateDefaultMtlMapSlotMapping ele =
(
	if _debug do format "UpdateDefaultMtlMapSlotMapping ele: %\n" ele
	local theMtl =	if ((bakedMtlProps.rbDestination.state == 1) or (bakedMtlProps.rbShellOption.state == 1)) then
					(
						local tmpMtl = ele.node.material
						if classof tmpMtl == Shell_Material do tmpMtl = tmpMtl.originalMaterial
						if tmpMtl != undefined then
					   		tmpMtl 
						else
							newNodeMtlInstance
					)
					else 
						newBakedMtlInstance
	local theMtlClass = classof theMtl
	local keyName = theMtlClass as string
	if theMtlClass == StandardMaterial then
		append keyName (":"+theMtl.shaderByName)
	else if theMtlClass == DirectX_9_Shader then
		append keyName (":"+getFilenameFile theMtl.effectFile)
	keyName = RTT_methods.MakeFileNameValid keyName 
	local sectionName = RTT_methods.MakeFileNameValid ((classof ele.element) as string)
	local targetMapSlot = ele.element.targetMapSlotName
	if _debug do format "\t% % '%' '%'\n" keyName sectionName targetMapSlot (getIniSetting iniFile keyName sectionName)
	if (getIniSetting iniFile keyName sectionName) == "" do
		setIniSetting iniFile keyName sectionName targetMapSlot 
)

------------------------------------------------------------------
--
-- function for getting the default map slot name for combination of material and bake element from the ini file
-- argument is a bakeElementStruct instance
--
function GetDefaultMtlMapSlotMapping ele =
(
	if _debug do format "GetDefaultMtlMapSlotMapping ele: %\n" ele
	local theMtl =	if ((bakedMtlProps.rbDestination.state == 1) or (bakedMtlProps.rbShellOption.state == 1)) then
					(
						local tmpMtl = ele.node.material
						if classof tmpMtl == Shell_Material do tmpMtl = tmpMtl.originalMaterial
						if tmpMtl != undefined then
					   		tmpMtl 
						else
							newNodeMtlInstance
					)
					else 
						newBakedMtlInstance
	local theMtlClass = classof theMtl
	local keyName = theMtlClass as string
	if theMtlClass == StandardMaterial then
		append keyName (":"+theMtl.shaderByName)
	else if theMtlClass == DirectX_9_Shader then
		append keyName (":"+getFilenameFile theMtl.effectFile)
	keyName = RTT_methods.MakeFileNameValid keyName 
	local sectionName = RTT_methods.MakeFileNameValid ((classof ele.element) as string)
	if _debug do format "\t% % '%'\n" keyName sectionName (getIniSetting iniFile keyName sectionName)
	getIniSetting iniFile keyName sectionName
)

------------------------------------------------------------------
--
-- function for building a list of render presets. Pulled from current ini file [RenderPresetsMruFiles] section.
function LoadRenderPresetList =
(	
	renderPresetFiles = #() 
	-- get key names for [RenderPresetsMruFiles] section 
	local keys = getinisetting (GetMAXIniFile()) "RenderPresetsMruFiles"
	for k in keys do
	(
		local filename = getinisetting (GetMAXIniFile()) "RenderPresetsMruFiles" k
		if filename != "" and (doesFileExist filename) do
			append renderPresetFiles filename
	)
	renderPresetFiles
)

------------------------------------------------------------------
--
--	utility functions for reading/writing .ini files
--
function GetINIConfigData filename section key default isString:false = 
(
	local res = getINISetting filename section key
	if res == "" then default
	else if isString then res
	else ReadValueFromString res ignoreStringEscapes:true
) -- end - function GetINIConfigData

-- reads value from ini file if the key exists
function GetINIConfigDataIfExists filename section key &value isString:false = 
(
	if (hasINISetting filename section key) then
	(
		local res = getINISetting filename section key
		if not isString do res = ReadValueFromString res ignoreStringEscapes:true
		value = res
		true
	)
	else
	(
		value = unsupplied
		false
	)
) -- end - function GetINIConfigDataIfExists

function SetINIConfigData filename section key value =
(
	local valueClass = classof value
	if valueClass == name then
		setINISetting filename section key ("#" + value)
	else if valueClass == BooleanClass then
		setINISetting filename section key (value as string)
	else
	(
		local outString = formattedprint value
		if outString == "" do
			outString = value as string
		setINISetting filename section key outString
	)
) -- end - function SetINIConfigData

-- function to read a value from a string. Re-uses a stringstream so that a lot of new stringstream values and
-- their parsers aren't created
function ReadValueFromString string ignoreStringEscapes:false =
(
	seek temp_stringstream_val 0
	format "%" string to:temp_stringstream_val
	seek temp_stringstream_val 0
	readValue temp_stringstream_val ignoreStringEscapes:ignoreStringEscapes
) -- end - function ReadValueFromString

-- Functions for reading/writing dialog info to .ini file
function ReadDialogConfig =
(
	pDialogHeight = GetINIConfigData iniFile "Dialog" "DialogHeight " 526
	pDialogPos = GetINIConfigData iniFile "Dialog" "DialogPos" [120,100]
	pFileOverwriteBoxPos = GetINIConfigData iniFile "FileOverwriteBox" "Pos" [-1,-1]
	pMissingMapCoordsPos = GetINIConfigData iniFile "MissingMapCoords" "Pos" [-1,-1]
	pMissingMapTargetsPos = GetINIConfigData iniFile "MissingMapTargets" "Pos" [-1,-1]
	pMissingMapFilesPos = GetINIConfigData iniFile "MissingMapFiles" "Pos" [-1,-1]
	pAddElementsPos = GetINIConfigData iniFile "AddElements" "Pos" [-1,-1]
	pInvalidOutDirPos = GetINIConfigData iniFile "InvalidOutputDirs" "Pos" [-1,-1]
	pProjectionOptionsPropsPos = GetINIConfigData iniFile "ProjectionOptionsProps" "Pos" [-1,-1]
	pBakeProgressPos = GetINIConfigData iniFile "BakeProgress" "Pos" [-1,-1]
	pExposureControlOKBoxPos = GetINIConfigData iniFile "ExposureControlOKBox" "Pos" [-1,-1]
	pLoadPresetOKBoxPos = GetINIConfigData iniFile "LoadPresetOKBox" "Pos" [-1,-1]

	pCommonBakePropsOpen = GetINIConfigData iniFile "Dialog" "CommonBakePropsOpen" false
	pSelectedObjectPropsOpen = GetINIConfigData iniFile "Dialog" "SelectedObjectPropsOpen" true
	pSelectedElementPropsOpen = GetINIConfigData iniFile "Dialog" "SelectedElementPropsOpen" true
	pBakedMtlPropsOpen = GetINIConfigData iniFile "Dialog" "BakedMtlPropsOpen" false
	pAutoUnwrapMappingPropsOpen = GetINIConfigData iniFile "Dialog" "AutoUnwrapMappingPropsOpen" false
	
	RTT_data.AutoFlatten_Obj_On = GetINIConfigData iniFile "Initialization" "AutoFlatten Object" RTT_data.AutoFlatten_Obj_On
	RTT_data.AutoFlatten_SubObj_On = GetINIConfigData iniFile "Initialization" "AutoFlatten SubObject" RTT_data.AutoFlatten_SubObj_On
	RTT_data.FileOutput_FilePath = GetINIConfigData iniFile "Initialization" "FileOutput_FilePath" RTT_data.FileOutput_FilePath isString:true
	RTT_data.Renderer_DisplayFB = GetINIConfigData iniFile "Initialization" "Renderer_DisplayFB" RTT_data.Renderer_DisplayFB 
	RTT_data.Renderer_NetworkRender = GetINIConfigData iniFile "Initialization" "Renderer_NetworkRender" RTT_data.Renderer_NetworkRender 
	RTT_data.Renderer_SkipExistingFiles = GetINIConfigData iniFile "Initialization" "Renderer_SkipExistingFiles" RTT_data.Renderer_SkipExistingFiles 
	
) -- end - function ReadDialogConfig

function WriteDialogConfig =
(
	--format "write dialog height = % \n" pDialogHeight
	SetINIConfigData iniFile "Dialog" "DialogHeight" pDialogHeight
	SetINIConfigData iniFile "Dialog" "DialogPos" pDialogPos
	SetINIConfigData iniFile "FileOverwriteBox" "Pos" pFileOverwriteBoxPos
	SetINIConfigData iniFile "MissingMapCoords" "Pos" pMissingMapCoordsPos
	SetINIConfigData iniFile "MissingMapTargets" "Pos" pMissingMapTargetsPos
	SetINIConfigData iniFile "MissingMapFiles" "Pos" pMissingMapFilesPos
	SetINIConfigData iniFile "AddElements" "Pos" pAddElementsPos
	SetINIConfigData iniFile "InvalidOutputDirs" "Pos" pInvalidOutDirPos
	SetINIConfigData iniFile "ProjectionOptionsProps" "Pos" pProjectionOptionsPropsPos
	SetINIConfigData iniFile "BakeProgress" "Pos" pBakeProgressPos 
	SetINIConfigData iniFile "ExposureControlOKBox" "Pos" pExposureControlOKBoxPos 
	SetINIConfigData iniFile "LoadPresetOKBox" "Pos" pLoadPresetOKBoxPos

	pCommonBakePropsOpen = commonBakeProps.open
	pSelectedObjectPropsOpen = selectedObjectProps.open
	pSelectedElementPropsOpen = selectedElementProps.open
	pBakedMtlPropsOpen = bakedMtlProps.open
	pAutoUnwrapMappingPropsOpen = autoUnwrapMappingProps.open
	
	SetINIConfigData iniFile "Dialog" "CommonBakePropsOpen" pCommonBakePropsOpen 
	SetINIConfigData iniFile "Dialog" "SelectedObjectPropsOpen" pSelectedObjectPropsOpen 
	SetINIConfigData iniFile "Dialog" "SelectedElementPropsOpen" pSelectedElementPropsOpen 
	SetINIConfigData iniFile "Dialog" "BakedMtlPropsOpen" pBakedMtlPropsOpen 
	SetINIConfigData iniFile "Dialog" "AutoUnwrapMappingPropsOpen" pAutoUnwrapMappingPropsOpen 

	SetINIConfigData iniFile "Initialization" "AutoFlatten Object" RTT_data.AutoFlatten_Obj_On
	SetINIConfigData iniFile "Initialization" "AutoFlatten SubObject" RTT_data.AutoFlatten_SubObj_On
	
	SetINIConfigData iniFile "Initialization" "FileOutput_FilePath" RTT_data.FileOutput_FilePath 
	SetINIConfigData iniFile "Initialization" "Renderer_DisplayFB" RTT_data.Renderer_DisplayFB 
	SetINIConfigData iniFile "Initialization" "Renderer_NetworkRender" RTT_data.Renderer_NetworkRender 
	SetINIConfigData iniFile "Initialization" "Renderer_SkipExistingFiles" RTT_data.Renderer_SkipExistingFiles 
) -- end - function WriteDialogConfig

-- Functions for reading/writing dialog info to scene (mapping coordinates settings)
function ReadSceneData =
(
	local autoFlatten_Obj_On, autoFlatten_Obj_MapChannel, autoFlatten_SubObj_On, autoFlatten_SubObj_MapChannel 
	autoFlatten_Obj_On = getAppData rootNode (RTT_SceneData_AppData_Index+0)
	if autoFlatten_Obj_On != undefined do RTT_data.AutoFlatten_Obj_On = autoFlatten_Obj_On as BooleanClass
	autoFlatten_Obj_MapChannel = getAppData rootNode (RTT_SceneData_AppData_Index+1)
	if autoFlatten_Obj_MapChannel != undefined do RTT_data.AutoFlatten_Obj_MapChannel = autoFlatten_Obj_MapChannel as integer
	autoFlatten_SubObj_On = getAppData rootNode (RTT_SceneData_AppData_Index+2)
	if autoFlatten_SubObj_On != undefined do RTT_data.AutoFlatten_SubObj_On = autoFlatten_SubObj_On as BooleanClass
	autoFlatten_SubObj_MapChannel = getAppData rootNode (RTT_SceneData_AppData_Index+3)
	if autoFlatten_SubObj_MapChannel != undefined do RTT_data.AutoFlatten_SubObj_MapChannel = autoFlatten_SubObj_MapChannel as integer
	if _debug do format "ReadSceneData: % : % : % : % - time:%\n" autoFlatten_Obj_On autoFlatten_Obj_MapChannel autoFlatten_SubObj_On autoFlatten_SubObj_MapChannel (timestamp())

	local fileOutput_FilePath, renderer_DisplayFB, renderer_NetworkRender, renderer_SkipExistingFiles 
	fileOutput_FilePath = getAppData rootNode (RTT_SceneData_AppData_Index+4)
	if fileOutput_FilePath != undefined do RTT_data.FileOutput_FilePath = fileOutput_FilePath
	renderer_DisplayFB = getAppData rootNode (RTT_SceneData_AppData_Index+5)
	if renderer_DisplayFB != undefined do RTT_data.Renderer_DisplayFB = renderer_DisplayFB as BooleanClass
	renderer_NetworkRender = getAppData rootNode (RTT_SceneData_AppData_Index+6)
	if renderer_NetworkRender != undefined do RTT_data.Renderer_NetworkRender = renderer_NetworkRender as BooleanClass
	renderer_SkipExistingFiles = getAppData rootNode (RTT_SceneData_AppData_Index+7)
	if renderer_SkipExistingFiles != undefined do RTT_data.Renderer_SkipExistingFiles = renderer_SkipExistingFiles as BooleanClass
	renderer_RenderToFilesOnly = getAppData rootNode (RTT_SceneData_AppData_Index+8)
	if renderer_RenderToFilesOnly != undefined do RTT_data.Materials_RenderToFilesOnly = renderer_RenderToFilesOnly as BooleanClass
	if _debug do format "ReadSceneData: % : % : % : % : % - time:%\n" \
		RTT_data.FileOutput_FilePath RTT_data.Renderer_DisplayFB RTT_data.Renderer_NetworkRender \
		RTT_data.Renderer_SkipExistingFiles RTT_data.Materials_RenderToFilesOnly (timestamp())
) -- end - function ReadSceneData 

function WriteSceneData =
(
	setAppData rootNode (RTT_SceneData_AppData_Index+0) (doAutoUnwrap_Obj as string)
	setAppData rootNode (RTT_SceneData_AppData_Index+1) (autoUnwrapChannel_Obj as string)
	setAppData rootNode (RTT_SceneData_AppData_Index+2) (doAutoUnwrap_SubObj as string)
	setAppData rootNode (RTT_SceneData_AppData_Index+3) (autoUnwrapChannel_SubObj as string)
	if _debug do format "WriteSceneData: % : % : % : %\n" doAutoUnwrap_Obj autoUnwrapChannel_Obj doAutoUnwrap_SubObj autoUnwrapChannel_SubObj 

	setAppData rootNode (RTT_SceneData_AppData_Index+4) RTT_data.FileOutput_FilePath
	setAppData rootNode (RTT_SceneData_AppData_Index+5) (RTT_data.Renderer_DisplayFB as string)
	setAppData rootNode (RTT_SceneData_AppData_Index+6) (RTT_data.Renderer_NetworkRender as string)
	setAppData rootNode (RTT_SceneData_AppData_Index+7) (RTT_data.Renderer_SkipExistingFiles as string)
	setAppData rootNode (RTT_SceneData_AppData_Index+8) (RTT_data.Materials_RenderToFilesOnly as string)
	if _debug do format "WriteSceneData: % : % : % : % : % - time:%\n" \
		RTT_data.FileOutput_FilePath RTT_data.Renderer_DisplayFB RTT_data.Renderer_NetworkRender \
		RTT_data.Renderer_SkipExistingFiles RTT_data.Materials_RenderToFilesOnly (timestamp())
) -- end - function WriteSceneData 


------------------------------------------------------------------
--
--	Main Texture Baking Shell Rollout
--
rollout gTextureBakeDialog "Render To Texture" 
	width:345 height:485
(
	-- local functions
	local OnObjectSelectionChangeEvent, OnObjectSelectionChange, OnReset, OnNodeRenamed, ReadConfigData, WriteConfigData, 
		  OnNodeMtlChanged, OnNodeMTlSubAnimChanged
	
	-- local variables used for data exchange with Missing Map Coords dialog and Missing Map Targets dialog
	local missingDataList = #()
	local cancelRender = false
	
	local nodeSelectionEventRegistered = false 
	
	local isClosing = false -- set to true when dialog is closing so toolbar button updates correctly
	
	-- sub rollout for selected object porperties
	SubRollout rollouts "" pos:[1,2] width:342 height:483
	
	-- the "do it" buttons

	button bRender "Render" width:66 height:24 align:#left enabled:true offset:[-6,0]
	button bMapOnly "Unwrap Only" width:70 height:24 align:#left enabled:true offset:[67,-24]
	button bClose "Close" width:50 height:24 align:#left enabled:true offset:[144,-24]
	label l1 "Views  Render" align:#left enabled:true offset:[247,0]
	label l2 "Original:" align:#left enabled:true offset:[205,0]
	label l3 "Baked:" align:#left enabled:true offset:[205,0]
	radiobuttons rOrigOrBaked ""  labels:#("", "") default:2 align:#left columns:1 offset:[256,-24]
	radiobuttons rOrigOrBaked2 "" labels:#("", "") default:1 align:#left columns:1 offset:[291,-24]
			
	-------------------------------------------------------------
	--	
	--	Bake Texture Button Pressed
	--	
	on bRender pressed do if workingObjects.count != 0 do
	(
		selectedObjectProps.CloseWorkingObjects()  -- capture changes
		selectedElementProps.CloseSelectedElement()  -- capture changes
--		selectedElementProps.OnObjectSelectionChange() -- reselect elements

		-- flatten everybody
		ignoreSelectionUpdates = true
		local old_autoBackup_enabled = autoBackup.enabled
		autoBackup.enabled = false

		try
		(
			if _debug do format "doAutoUnwrap_Obj: %; autoUnwrapChannel_Obj: %; \n" doAutoUnwrap_Obj autoUnwrapChannel_Obj
			if _debug do format "doAutoUnwrap_SubObj: %; autoUnwrapChannel_SubObj: %; \n" doAutoUnwrap_SubObj autoUnwrapChannel_SubObj 
			if doAutoUnwrap_Obj or doAutoUnwrap_SubObj do 
			(
				undo "Flatten Objects" on
				(
					-- update bake channel on nodes
					for obj_i in workingObjects do
					(
						if doAutoUnwrap_Obj do 
							obj_i.node.INodeBakeProperties.bakeChannel = autoUnwrapChannel_Obj
						if doAutoUnwrap_SubObj do 
							obj_i.node.INodeBakeProjProperties.subObjBakeChannel = autoUnwrapChannel_SubObj
					)
					BatchFlatten workingObjects autoUnwrapMappingProps.sThresholdAngle.value autoUnwrapMappingProps.sSpacing.value \
								 autoUnwrapMappingProps.cRotate.checked autoUnwrapMappingProps.cFillHoles.checked
				)
			)
		)
		catch
		(
			ignoreSelectionUpdates = false
			autoBackup.enabled = old_autoBackup_enabled
			throw
		)
		ignoreSelectionUpdates = false
		
		if _debug do format "bRender pressed - starting test\n"

		try
		(
			if ExposureControlOK() and (MapCoordsOK workingObjects ) and ((bakedMtlProps.cbRenderToFilesOnly.checked) or (MapTargetsOK workingObjects)) do
			(
				if _debug do format "bRender pressed - passed test\n"
		
				-- then bake the textures
				ignoreSelectionUpdates = true
				ignoreMtlUpdates = true	
				if _debug do format "bRender pressed - calling batchBake\n"
				if commonBakeProps.cNetworkRender.checked then
					NetBatchBake workingObjects
				else
				(
					BatchBake workingObjects 
					displayTempPrompt "Texture baking completed" 5000
				)
				ignoreSelectionUpdates = false
				ignoreMtlUpdates = false	
			)
		)
		catch
		(
			autoBackup.enabled = old_autoBackup_enabled
			throw
		)
		autoBackup.enabled = old_autoBackup_enabled
	)
		
	-------------------------------------------------------------
	--	
	--	Just do mapping, no render
	--	
	on bMapOnly pressed do if workingObjects.count != 0 do
	(
		selectedObjectProps.CloseWorkingObjects()  -- capture changes
		selectedElementProps.CloseSelectedElement()  -- capture changes

		-- flatten everybody
		ignoreSelectionUpdates = true
		local old_autoBackup_enabled = autoBackup.enabled
		autoBackup.enabled = false

		try
		(
			if allow_manual_unwrap_when_autounwrap_off or doAutoUnwrap_Obj or doAutoUnwrap_SubObj do 
			(
				undo "Flatten Objects" on
				(
					-- update bake channel on nodes
					for obj_i in workingObjects do
					(
						if doAutoUnwrap_Obj do 
							obj_i.node.INodeBakeProperties.bakeChannel = autoUnwrapChannel_Obj
						if doAutoUnwrap_SubObj do 
							obj_i.node.INodeBakeProjProperties.subObjBakeChannel = autoUnwrapChannel_SubObj
					)
					BatchFlatten workingObjects autoUnwrapMappingProps.sThresholdAngle.value autoUnwrapMappingProps.sSpacing.value \
								 autoUnwrapMappingProps.cRotate.checked autoUnwrapMappingProps.cFillHoles.checked flattenAll:true
				)
			)
		)
		catch
		(
			ignoreSelectionUpdates = false
			autoBackup.enabled = old_autoBackup_enabled
			throw
		)
		
		ignoreSelectionUpdates = false
		autoBackup.enabled = old_autoBackup_enabled
	)

	-------------------------------------------------------------
	--	
	--	Set which submaterial in shell materials to use in viewport for working objects
	on rOrigOrBaked changed state do
	(	
		state -= 1 -- property is 0-based
		for wo in workingObjects do
		(	
			local mtl = wo.node.material
			if mtl != undefined do 
				SetShellMtlVPMtl mtl state
		) 
	)
	
	-------------------------------------------------------------
	--	
	--	Set which submaterial in shell materials to use in renders for working objects
	on rOrigOrBaked2 changed state do
	(	
		state -= 1 -- property is 0-based
		for wo in workingObjects do
		(	
			local mtl = wo.node.material
			if mtl != undefined do 
				SetShellMtlRenderMtl mtl state
		) 
	)
	
	-------------------------------------------------------------
	--	
	--	Close Button pressed 
	--
	on bClose pressed do
	(
		-- format "close button\n"
		-- & close the dialog, save handled by on ... close event
		destroydialog gTextureBakeDialog
	)
		
	-------------------------------------------------------------
	--	
	--	dialog is opening 
	--
	on gTextureBakeDialog open do
	(
		if _debug do format "in gTextureBakeDialog.open - time:%\n" (timestamp())
		isClosing = false

		bRender.enabled = renderers.current.supportsTexureBaking
		newNodeMtlInstance = StandardMaterial shaderByName:defaultMtlShader 
		newNodeMtlTargetMapNames = CollectTargetMapNamesForMtl newNodeMtlInstance 
		
		unwrapUVW_instance = Unwrap_UVW() 

		-- add new callbacks
		callbacks.addScript #selectionSetChanged "gTextureBakeDialog.OnObjectSelectionChangeEvent()" id:#bakeSelectionHandler 
		callbacks.addScript #systemPreReset "gTextureBakeDialog.OnReset #systemPreReset" id:#bakeResetHandler 
		callbacks.addScript #systemPreNew "gTextureBakeDialog.OnReset #systemPreNew" id:#bakeNewHandler 
		callbacks.addScript #filePreOpen "gTextureBakeDialog.OnReset #filePreOpen" id:#bakeFileOpenHandler 
		callbacks.addScript #postRendererChange "gTextureBakeDialog.OnRendererChanged()" id:#bakeRendererChangedHandler 
		callbacks.addScript #nodePostMaterial "gTextureBakeDialog.OnNodeMtlChanged()" id:#bakeRendererChangedHandler 
		
		if _debug do format "exit gTextureBakeDialog.open - time:%\n" (timestamp())
	)

	-------------------------------------------------------------
	--	
	--	dialog is being closed. only hook for X Button pressed 
	--
	on gTextureBakeDialog close do
	(
		if _debug do format "close gTextureBakeDialog - begin\n"
		
		isClosing = true
		
		-- remove the various callbacks
		callbacks.removeScripts id:#bakeSelectionHandler 
		callbacks.removeScripts id:#bakeResetHandler 
		callbacks.removeScripts id:#bakeNewHandler 
		callbacks.removeScripts id:#bakeFileOpenHandler  
		deleteAllChangeHandlers id:#bakeNodeRenamedHandler
		deleteAllChangeHandlers id:#bakeNodeMtlChangeHandler
		callbacks.removeScripts id:#bakeRendererChangedHandler 

		-- format "    save open object \n"
		-- save things to the selected object
		selectedObjectProps.CloseWorkingObjects()
		selectedElementProps.CloseSelectedElement()

		if projectionOptionsProps.isDisplayed do 
			destroyDialog projectionOptionsProps

		-- close any vfbs
		if curBM != undefined then 
			unDisplay( curBM )
		
		if gTextureBakeDialog.placement != #minimized do
			pDialogPos = GetDialogPos( gTextureBakeDialog )
		WriteDialogConfig()
		
		--format "dialog pos = ( %, %) \n" pDialogPos.x pDialogPos.y
		-- & close the dialog if it's not already
		
		if _debug do format "close gTextureBakeDialog - destroydialog start\n"
		destroydialog gTextureBakeDialog
		if _debug do format "close gTextureBakeDialog - end\n"
		updateToolbarButtons()
	)
	
	-------------------------------------------------------------
	--	
	--	Dialog resized 
	--
	on gTextureBakeDialog resized newSz do
	(
		-- format "resize to %, % \n" newSz.x newSz.y
		if gTextureBakeDialog.placement != #minimized do
		(
			pDialogHeight = newSz.y
	 
			-- adjust the dialog layout
			rollouts.height = pDialogHeight - 43
			buttonY = pDialogHeight - 33
			bRender.pos = [bRender.pos.x, buttonY]
			bMapOnly.pos = [bMapOnly.pos.x, buttonY]
			rOrigOrBaked.pos = [rOrigOrBaked.pos.x, buttonY+4]
			rOrigOrBaked2.pos = [rOrigOrBaked2.pos.x, buttonY+4]
			l1.pos = [l1.pos.x, buttonY-8]
			l2.pos = [l2.pos.x, buttonY+4]
			l3.pos = [l3.pos.x, buttonY+19]
			bClose.pos = [bClose.pos.x, buttonY]
		)
		if projectionOptionsProps.isDisplayed and (gTextureBakeDialog.placement != projectionOptionsProps.placement) do
			projectionOptionsProps.placement = gTextureBakeDialog.placement 
	)


	------------------------------------------------------------------
	-- function called when node selection changes. Just registers a redrawviews callback if not ignoring
	-- selection changes, and callback hasn't already been registered
	function OnObjectSelectionChangeEvent =
	(
		if not ignoreSelectionUpdates and not nodeSelectionEventRegistered do 
		(
			registerRedrawViewsCallback OnObjectSelectionChange
			nodeSelectionEventRegistered = true
		)
	)
	------------------------------------------------------------------
	-- function called at redrawviews after node selection changes. Rebuilds object lists, calls 
	-- function to update Elements rollout if needed, and update Objects listview
	function OnObjectSelectionChange =
	(
		if _debug do format "in gTextureBakeDialog.OnObjectSelectionChange: displayType:% - time:%\n" selectedObjectProps.rSceneType.state (timestamp())
		if nodeSelectionEventRegistered do
		(
			unregisterRedrawViewsCallback OnObjectSelectionChange
			nodeSelectionEventRegistered = false
		)
		if not gTextureBakeDialog.open do return()
		selectedObjects = selection as array
		local newDisplayedBakableObjects = #()
		local newWorkingObjects = #()
		local objData
		local workingObjectSetUnchanged = true
		local displayedObjectSetUnchanged = true
		local displayType = selectedObjectProps.rSceneType.state
		-- build new object lists
		if (displayType <= 2) then -- Displaying All Selected
		(
			for obj in selectedObjects where (ObjectIsBakable obj) do
			(
				objData = bakableObjStruct obj obj.name (CollectMappedChannels obj) (CollectTargetMapNamesForNode obj)
				append newDisplayedBakableObjects objData
			)
			if displayType == 1 then -- working set is Individual
			(
				-- bring across currently picked objects that are still valid
				for obj in workingObjects where (isvalidNode obj.node and obj.node.isSelected) do
				(
					-- find node in newDisplayedBakableObjects. newWorkingObjects values must be a 
					-- subset of the values in newDisplayedBakableObjects. (the same bakableObjStruct)
					-- instance must be in both
					local notFound = true
					local theNode = obj.node
					for o in newDisplayedBakableObjects while notFound where o.node == theNode do
					(
						append newWorkingObjects o
						notFound = false
					)
				)
				-- if all else fails, make first object the working object
				if newWorkingObjects.count == 0 and newDisplayedBakableObjects.count != 0 do
					append newWorkingObjects newDisplayedBakableObjects[1]
			)
			else -- working set is All Selected
				newWorkingObjects = newDisplayedBakableObjects
		)
		else -- Displaying All Prepared, working set is All Prepared
		(
			for obj in geometry where (ObjectIsBakable obj) do
			(
				local channels = CollectMappedChannels obj unwrapOnly:true
				if not channels.isEmpty do
				(
					objData = bakableObjStruct obj obj.name channels (CollectTargetMapNamesForNode obj)
					append newDisplayedBakableObjects objData
				)
			)
			newWorkingObjects = newDisplayedBakableObjects
		)

		-- perform node bake channel fixup
		-- clamp bake channel to range of 1 to 99
		-- if node's bake channel doesn't match uvw map channels, set it to first uvw map channel
		-- if no uvw map channels, leave bake channel alone
		-- turn off undo for this so don't get undo record/dirty scene just by opening RTT
		with undo off 
		(
			for obj in newDisplayedBakableObjects do
			(
				local bakeInterface = obj.node.INodeBakeProperties
				if bakeInterface.bakeChannel < 1 then bakeInterface.bakeChannel = 1
				else if bakeInterface.bakeChannel > 99 then bakeInterface.bakeChannel = 99
				local firstChannel
				for i in obj.channels while (firstChannel = i;false) do () -- quick way to get first set 
				if (not obj.channels[bakeInterface.bakeChannel]) and (not obj.channels.isEmpty) do
					bakeInterface.bakeChannel = firstChannel

				local bakeProjInterface = obj.node.INodeBakeProjProperties
				if bakeProjInterface.subObjBakeChannel < 1 then bakeProjInterface.subObjBakeChannel = 1
				else if bakeProjInterface.subObjBakeChannel > 99 then bakeProjInterface.subObjBakeChannel = 99
				if (not obj.channels[bakeProjInterface.subObjBakeChannel]) and (not obj.channels.isEmpty) do
					bakeProjInterface.subObjBakeChannel = firstChannel
			)
			if (newWorkingObjects != newDisplayedBakableObjects) do -- if both aren't the same array
			(
				for obj in newWorkingObjects do
				(
					local bakeInterface = obj.node.INodeBakeProperties
					local firstChannel
					for i in obj.channels while (firstChannel = i;false) do () -- quick way to get first set 
					if (not obj.channels[bakeInterface.bakeChannel]) and (not obj.channels.isEmpty) do
						bakeInterface.bakeChannel = firstChannel

					local bakeProjInterface = obj.node.INodeBakeProjProperties
					if (not obj.channels[bakeProjInterface.subObjBakeChannel]) and (not obj.channels.isEmpty) do
						bakeProjInterface.subObjBakeChannel = firstChannel
				)
			)
		) -- end undo off 

		if _debug do
		(	
			format "  selectedObjects: %\n" selectedObjects 
			format "  newDisplayedBakableObjects: %\n" newDisplayedBakableObjects 
			format "  newWorkingObjects: %\n" newWorkingObjects
		)
		-- check to see if the new working object list is the same as the old
		-- if so, no need to change the Elements rollout. Otherwise need to 
		-- accept any changes there and redisplay
		if newWorkingObjects.count != workingObjects.count then
			workingObjectSetUnchanged = false
		else
			for i = 1 to newWorkingObjects.count while (workingObjectSetUnchanged) do
				if newWorkingObjects[i].node != workingObjects[i].node do
					workingObjectSetUnchanged = false
		
		-- update the nodes' and elements' data if needed
		if workingObjects.count != 0 and not workingObjectSetUnchanged do
		(
			selectedObjectProps.CloseWorkingObjects()
			selectedElementProps.CloseSelectedElement()
		)
			
		-- decide whether we need to update the node listview.
		if newDisplayedBakableObjects.count != displayedBakableObjects.count then
			displayedObjectSetUnchanged = false
		else
			for i = 1 to newDisplayedBakableObjects.count while (displayedObjectSetUnchanged) do
				if newDisplayedBakableObjects[i].node != displayedBakableObjects[i].node do
					displayedObjectSetUnchanged = false
		
		displayedBakableObjects = newDisplayedBakableObjects
		workingObjects = newWorkingObjects
		for wo in workingObjects do wo.isWorkingObject = true
		
		-- update the Objects listview if needed
		if (not displayedObjectSetUnchanged) then
			selectedObjectProps.RebuildObjectsLV()
	
		-- update the common Object settings if needed and refresh node listview
		else if (not workingObjectSetUnchanged) do
		(
			selectedObjectProps.UpdateObjectSettings()
			selectedObjectProps.RefreshObjectsLV() -- update listview
		)
	
		-- update the Elements listview if needed
		if (not workingObjectSetUnchanged) do
			selectedElementProps.OnObjectSelectionChange() -- display elements for working object

		-- update the Views radio button if needed
		if (not workingObjectSetUnchanged) do
		(
			local res = triStateValue()
			for wo in workingObjects do
			(	
				local mtl = wo.node.material
				if mtl != undefined do 
					GetShellMtlVPMtl mtl res
			)
			if res.defined == false then
				rOrigOrBaked.state = 2
			else if res.indeterminate then 
				rOrigOrBaked.state = 0
			else
				rOrigOrBaked.state = res.value + 1 -- prop is 0-based
		)

		-- update the Render radio button if needed
		if (not workingObjectSetUnchanged) do
		(
			local res = triStateValue()
			for wo in workingObjects do
			(	
				local mtl = wo.node.material
				if mtl != undefined do 
					GetShellMtlRenderMtl mtl res
			)
			if res.defined == false then
				rOrigOrBaked2.state = 1
			else if res.indeterminate then 
				rOrigOrBaked2.state = 0
			else
				rOrigOrBaked2.state = res.value + 1 -- prop is 0-based
		)

		if (not displayedObjectSetUnchanged) then
			selectedObjectProps.RebuildObjectPresets false
		
		if (not displayedObjectSetUnchanged) then
		(
			if _debug do format "registering node rename callback\n"
			deleteAllChangeHandlers id:#bakeNodeRenamedHandler
			local nodelist = for obj in displayedBakableObjects collect obj.node
			when names nodelist change id:#bakeNodeRenamedHandler theNode do OnNodeRenamed theNode
			deleteAllChangeHandlers id:#bakeNodeMtlChangeHandler
			local mtllist = for obj in displayedBakableObjects where (obj.node.material != undefined) collect obj.node.material
			when subAnimStructure mtllist change id:#bakeNodeMtlChangeHandler do OnNodeMTlSubAnimChanged()
		)
		if _debug do format "exit gTextureBakeDialog.OnObjectSelectionChange - time:%\n" (timestamp())
	) -- end - function OnObjectSelectionChange 
			
	-----------------------------------------------------------------------------
	--
	-- this function handles reset & new event callbacks
	--
	function OnReset eventType =
	(
		-- ignore render preset loads
		if (eventType != #filePreOpen or callbacks.notificationParam() != 2) do
		(
			if curBM != undefined then
			(	close curBM
				curBM = undefined
			)
	
			-- & close the dialog if it's not already
			destroydialog gTextureBakeDialog
		)
	) -- end - function OnReset 

	function OnNodeRenamed theNode =
	(	
		-- check to make sure that an actual node name change occurred. The 'when name changed' gets
		-- triggered when the node, node modifiers', or node material's name changes.
		local wo_index
		local notFound = true
		for i = 1 to workingObjects.count while notFound where workingObjects[i].node == theNode do
		(	notFound = false
			wo_index = i
		)
		if (not notFound) and workingObjects[wo_index].nodeName != theNode.name do
		(
			if _debug do format "in OnNodeRenamed: %\n" theNode.name
			selectedObjectProps.RefreshObjectsLV() -- update listview
			if workingObjects.count == 1 and workingObjects[1].node == theNode do
			(	
				selectedElementProps.CloseSelectedElement()
				selectedElementProps.OnObjectSelectionChange()
			)
		)
	) -- end - function OnNodeRenamed 
	
	function OnRendererChanged =
	(
		bRender.enabled = renderers.current.supportsTexureBaking
		if (not renderers.current.supportsTexureBaking and not RTT_Data.rendererErrorDisplayed ) do 
		(
			messagebox "Renderer doesn't support Texture Baking, Rendering disabled\n" title:"Render To Texture" --LOC_NOTES: localize this
			RTT_Data.rendererErrorDisplayed = true
		)
		selectedElementProps.CloseSelectedElement()
		selectedElementProps.OnObjectSelectionChange()
	)
	
	function OnNodeMtlChanged =
	(
		local theNode = callbacks.notificationParam()
		if _debug do format "OnNodeMtlChanged : %\n" theNode
		local notFound = true
		for i = 1 to workingObjects.count while notFound where workingObjects[i].node == theNode do
		(
			notFound = false
			deleteAllChangeHandlers id:#bakeNodeMtlChangeHandler
			local mtllist = for obj in displayedBakableObjects where (obj.node.material != undefined) collect obj.node.material
			when subAnimStructure mtllist change id:#bakeNodeMtlChangeHandler do OnNodeMTlSubAnimChanged()
		)
		OnNodeMTlSubAnimChanged()
	)
	
	function OnNodeMTlSubAnimChanged =
	(
		if not ignoreMtlUpdates do
		(
			if _debug do format "OnNodeMTlSubAnimChanged\n"
			OnObjectSelectionChange()
			selectedElementProps.CloseSelectedElement()
			selectedElementProps.OnObjectSelectionChange() -- display elements for working object
		)
	)
	
	function ReadConfigData =
	(
		defaultFileType = RTT_data.FileOutput_FileType
	) -- end - function ReadConfigData 
	
	function WriteConfigData =
	(
		RTT_data.FileOutput_FileType = defaultFileType
	) -- end - function WriteConfigData 

) -- end - rollout gTextureBakeDialog

rollout autoUnwrapMappingProps "Automatic Mapping"
(
	-- local functions
	local UpdateFlattenEnables, ReadConfigData, WriteConfigData
	
	-- the auto flatten group
	group "Automatic Unwrap Mapping"
	(
		checkbox cRotate "Rotate Clusters" checked:true align:#left offset:[0,0] across:2
		spinner sThresholdAngle "Threshold Angle: " range:[1,100,45] type:#float align:#right offset:[0,0]
		checkbox cFillHoles "Fill Holes" checked:true align:#left offset:[0,0] across:2
		spinner sSpacing "Spacing: " range:[0,1,0.02] type:#float scale:0.001 align:#right offset:[0,0]
	)
	
-- autosize group
	group "Automatic Map Size"
	(
		spinner sSizeScale "Scale: " range:[0,1,0.01] type:#float scale:0.001 across:2 align:#left
		spinner sSizeMin "Min: " range:[1,2048,32] type:#integer align:#right
		checkbox cSizePowersOf2 "Nearest power of 2" across:2 align:#left
		spinner sSizeMax "Max:" range:[1,2048,1024] type:#integer align:#right
	)

	on cSizePowersOf2 changed _newVal do
	(
		selectedElementProps.UpdateAutoSize()
	)
	on sSizeScale changed _newVal do
	(
		selectedElementProps.UpdateAutoSize()
	)
	on sSizeMin changed _newVal do
	(
		selectedElementProps.UpdateAutoSize()
	)
	on sSizeMax changed _newVal do
	(
		selectedElementProps.UpdateAutoSize()
	)

	-- enable/disable auto-flatten controls  
	function UpdateFlattenEnables _enable_Obj _enable_SubObj=
	(
		local enabled = _enable_Obj or _enable_SubObj
		cRotate.enabled = enabled 
		sThresholdAngle.enabled = enabled 		
		cFillHoles.enabled = enabled 
		sSpacing.enabled = enabled 	
	)			
	function ReadConfigData =
	(
		-- format "load state\n"
	
		sSpacing.value = 			RTT_data.AutoFlatten_Spacing
		sThresholdAngle.value = 	RTT_data.AutoFlatten_ThresholdAngle
		cRotate.checked = 			RTT_data.AutoFlatten_Rotate
		cFillHoles.checked =		RTT_data.AutoFlatten_FillHoles
		
		sSizeMin.value = 			RTT_data.AutoSize_SizeMin
		sSizeMax.value = 			RTT_data.AutoSize_SizeMax
		sSizeScale.value = 			RTT_data.AutoSize_SizeScale
		cSizePowersOf2.checked = 	RTT_data.AutoSize_SizePowersOf2
	) -- end fn ReadConfigData 
	
	function WriteConfigData =
	(
		-- format "save state\n"
	 
		RTT_data.AutoFlatten_Spacing = sSpacing.value
		RTT_data.AutoFlatten_ThresholdAngle = sThresholdAngle.value
		RTT_data.AutoFlatten_Rotate = cRotate.checked
		RTT_data.AutoFlatten_FillHoles = cFillHoles.checked
		
		RTT_data.AutoSize_SizeMin = sSizeMin.value
		RTT_data.AutoSize_SizeMax = sSizeMax.value
		RTT_data.AutoSize_SizeScale = sSizeScale.value
		RTT_data.AutoSize_SizePowersOf2 = cSizePowersOf2.checked 
	) -- end fn WriteConfigData 
	
)
------------------------------------------------------------------
--
--	Common Settings Rollout - these apply to the whole scene
--
rollout commonBakeProps "General Settings"
(
	-- local functions
	local GetFilePath, ReadConfigData, WriteConfigData, RebuildRenderPresets
	
-- path group
	group "Output" 
	(
		edittext eFilePath "Path: " width:270 across:2 align:#left
		button bPathSelect "..." width:20 height:17 align:#right
		checkbox cSkipExistingFiles "Skip Existing Files" across:2 align:#left
		checkbox cDisplayFB "Rendered Frame Window" align:#left checked:true 
	)
	
-- Render Setting group
	group "Render Settings"
	(
--		radiobuttons rDraftOrProduction "" width:146 labels:#("Production", "Draft") columns:2 across:2
		dropdownlist dRenderPresets across:2
		button setupRenderSettingsButton "Setup..." width:60 height:20 offset:[0,0]
		checkbox cNetworkRender "Network Render" align:#left offset:[0,-3]
	)

	on commonBakeProps open do
	(
		if _debug do format "in commonBakeProps.open - time:%\n" (timestamp())
		ReadConfigData()
		RebuildRenderPresets()
		dRenderPresets.selection = renderPresetFiles.count+1
				
		cNetworkRender.enabled = classof netrender == Interface
		if not cNetworkRender.enabled do cNetworkRender.checked = false
		if _debug do format "exit commonBakeProps.open - time:%\n" (timestamp())
	)
	on commonBakeProps close do
	(
		if _debug do format "close commonBakeProps\n"
		WriteConfigData()
	)
--	on rDraftOrProduction changed _newState do
--	(
--		renderer = if (_newState == 1) then #production else #draft
--	)
	on dRenderPresets selected val do
	(
		if val <= renderPresetFiles.count then
		(
			res = renderPresets.load 0 renderPresetFiles[val] #{}
		)
		else if val == (renderPresetFiles.count+2) do
		(
			renderPresets.load 0 "" #{}
			RebuildRenderPresets()
			dRenderPresets.selection = 1
		)
	)
	on setupRenderSettingsButton pressed do
	(
		-- select the settings to use
--		renderer = if (commonBakeProps.rDraftOrProduction.state == 1) then #production else #draft
		max render scene
	)
	on cNetworkRender changed state do
	(
		bakedMtlProps.cbRenderToFilesOnly.enabled = not state
	)
	on eFilePath changed _newPath do
	(
		if _newPath == "" then
			eFilePath.text = getdir #image
	)
	on bPathSelect pressed do
	(
		path = GetSavePath caption:"Select Output Path" initialDir:(GetFilePath())
		if path != undefined then
		(
			eFilePath.text = path
			eFilePath.entered path
		)
	)

	-- return the effective file path
	function GetFilePath = 
	(
		path = eFilePath.text
		if path == "" then
		(
			path = getdir #image		-- image directory is the default
		)
		if path[ path.count ] != "\\" then
			path += "\\"

		-- format "        file path: % \n" path
		path
	)

	function ReadConfigData =
	(
		-- format "load state\n"
	
		cDisplayFB.checked = 		RTT_data.Renderer_DisplayFB
		cNetworkRender.checked = 	RTT_data.Renderer_NetworkRender
		cSkipExistingFiles.checked = RTT_data.Renderer_SkipExistingFiles
		
		eFilePath.text = 			RTT_data.FileOutput_FilePath
	) -- end fn ReadConfigData 
	
	on cDisplayFB changed state do 
	(
		RTT_data.Renderer_DisplayFB = state 
		WriteSceneData()
	)
	
	on cNetworkRender changed state do 
	(
		RTT_data.Renderer_NetworkRender = state 
		WriteSceneData()
	)

	on cSkipExistingFiles changed state do 
	(
		RTT_data.Renderer_SkipExistingFiles = state 
		WriteSceneData()
	)

	on eFilePath entered path do 
	(
		RTT_data.FileOutput_FilePath = path
		WriteSceneData()
	)

	function WriteConfigData =
	(
		-- format "save state\n"
	) -- end fn WriteConfigData 
	
	function RebuildRenderPresets = 
	(
		if _debug do format "in RebuildRenderPresets - time:%\n" (timestamp())
		LoadRenderPresetList()
		local renderPresetNames = #()
		local count = renderPresetFiles.count
		renderPresetNames.count = count+2
		if _debug do format "renderPresetFiles: %\n" renderPresetFiles
		for i = 1 to count do renderPresetNames[i] = getFilenameFile (renderPresetFiles[i])
		renderPresetNames[count+1]="-------------------------------------------------"
		renderPresetNames[count+2]="Load Preset..."
		if _debug do format "renderPresetNames: %\n" renderPresetNames 
		dRenderPresets.items = renderPresetNames
		if _debug do format "exit RebuildRenderPresets - time:%\n" (timestamp())
	) -- end fn RebuildRenderPresets 
) -- end - rollout commonBakeProps 

------------------------------------------------------------------
rollout selectedObjectProps "Objects to Bake"
(
	-- rollout local functions
	local RebuildObjectsLV, RefreshObjectsLV, UpdateObjectSettings, CloseWorkingObjects, AutoMapChannelValChanged, 
			AutoMapChannelStateChanged, UpdateFlattenEnables, ReadConfigData, WriteConfigData, OnModifierChangeEvent,
			RebuildObjectPresets, LoadObjectPresetList, LoadObjectPreset, SaveObjectPreset, ApplyObjectPreset,
			AddFileToObjectPresetsMruFiles

	local lastSceneType -- holds last display type (individual, all selected, all prepared)
	local settingsDirty -- if true, a parameter of the working object(s) was changed. 
	
	local numVisibleItems = 8 -- number of ListItems visible in lvObjects (constant)
	
	local ProjMod_List = #() -- stores projection modifiers. order is same as in dProjMaps
	
	group "Object and Output Settings"
	(
		label lPreset "Preset:" align:#left across:2 offset:[9,3]
		dropdownlist dObjectPresets align:#right width:255 
	)
	
	label l_name1 "" across:4 align:#left offset:[20,-5]
	label l_objmapchan1 "Object" align:#right offset:[43,-5]
	label l_subobjmapchan1 "Sub-Object" align:#right offset:[29,-5]
	label l_edge1 "Edge" align:#right offset:[-10,-5]
	label l_name2 "Name" across:4 align:#left offset:[20,-5]
	label l_objmapchan2 "Channel" align:#right offset:[46,-5]
	label l_subobjmapchan2 "Channel" align:#right offset:[25,-5]
	label l_edge2 "Padding" align:#right offset:[-2,-5]

	dotNetControl lvObjects "Listview" height:118 width:330 align:#left offset:[-14,-5]

	group "Selected Object Settings"
	(
		checkbox cBakeEnable "Enabled" enabled:false checked:false align:#left offset:[0,0] across:2
		spinner sDilations "Padding: " enabled:false range:[0,64,2] type:#integer fieldwidth:40 align:#left 
	)
	
	-- start of Projection Mapping group
	local projMapEnabled = productAppID == #max

	checkbox cProjMapEnable "Enabled" enabled:false checked:false align:#left offset:[0,20] across:4 visible:projMapEnabled
	dropdownlist dProjMaps "" enabled:false width:133 align:#left offset:[-10,17] visible:projMapEnabled
	button bNewTarget "Pick..." enabled:false align:#left offset:[53,17] width:40 tooltip:"Set up Projection by picking source object" visible:projMapEnabled
	checkbutton bProjMapOptions "Options..." enabled:false align:#right offset:[5,17] width:54 tooltip:"Projection Options" visible:projMapEnabled 

	checkbox cObjLevelOut "Object Level" enabled:false checked:false align:#left offset:[18,-1] across:2 visible:projMapEnabled
	checkbox cSubObjLevelOut "Sub-Object Levels" enabled:false checked:false align:#left offset:[-2,-1] visible:projMapEnabled 
	radiobuttons rb_PutToBakedMtl labels:#("Put to Baked Material  ","Put to Baked Material") columns:2 enabled:false align:#left offset:[18,-2] visible:projMapEnabled
	radiobuttons rb_SOSize labels:#("Full Size","Proportional") columns:2 enabled:false align:#left offset:[149,-2] visible:projMapEnabled

	groupBox gbPmap "Projection Mapping" width:321 height:98 offset:[-9,-98] visible:projMapEnabled

	-- start of Mapping Coordinates group
	local offsetY = if projMapEnabled then 24 else -78
	
	label l_mapCoordOpt_Obj "Object:" enabled:false align:#right across:4  offset:[-20,0+offsetY]
	radiobuttons rb_mapCoordOpt_Obj labels:#("Use Existing Channel","Use Automatic Unwrap") columns:1 enabled:false align:#left offset:[-10,-1+offsetY]
	label l_mapChannel_Obj "Channel:" enabled:false align:#left offset:[60,8+offsetY] 
	dropdownlist dUseMapChannel_Obj enabled:false width:50 align:#right offset:[6,4+offsetY]
	spinner sMapChannel_Obj range:[1,99,3] type:#integer enabled:false fieldwidth:40 align:#right offset:[0,-28]
	label l_dummy01 offset:[0,-8]

	label l_mapCoordOpt_SubObj "Sub-Objects:" enabled:false align:#right across:4 offset:[-20,0]
	radiobuttons rb_mapCoordOpt_SubObj labels:#("Use Existing Channel","Use Automatic Unwrap") columns:1 enabled:false align:#left offset:[-10,-1]
	label l_mapChannel_SubObj "Channel:" enabled:false align:#left offset:[60,8] 
	dropdownlist dUseMapChannel_SubObj enabled:false width:50 align:#right offset:[6,4]
	spinner sMapChannel_SubObj range:[1,99,3] type:#integer enabled:false fieldwidth:40 align:#right offset:[0,-28]
	label l_dummy02 offset:[0,-5]

	button bClearUnwrap "Clear Unwrappers" width:110 height:16 enabled:false align:#center offset:[0,-5]

	groupBox gbMapCoord "Mapping Coordinates" width:321 height:120 offset:[-9,-120]

	radiobuttons rSceneType "" labels:#("Individual", "All Selected    ", "All Prepared") default:2 columns:3

	------------------------------------------------------------------
	-- on open we need to initialize the list view & set things appropriately
	--
	on selectedObjectProps open do
	(
		if _debug do format "in selectedObjectProps.open - time:%\n" (timestamp())
		-- move the auto unwrap map channel spinner up and to the right of the existing map channel dropdown.
		-- enable/disable and change visibility of these as needed
		local pos = sMapChannel_Obj.pos ; pos.y=dUseMapChannel_Obj.pos.y+3 ; sMapChannel_Obj.pos=pos
		pos = sMapChannel_SubObj.pos ; pos.y=dUseMapChannel_SubObj.pos.y+3 ; sMapChannel_SubObj.pos=pos
		dUseMapChannel_SubObj.visible = dUseMapChannel_Obj.visible = false
		
		RTT_data.selectedObjectPropsRO = selectedObjectProps
 		
		ReadConfigData()
		RebuildObjectPresets true
		dObjectPresets.selection = objectPresetFiles.count+1
		
		-- initialize the .NET ListView control
		lvops.InitListView lvObjects pInitColumns: #("Name","Object Channel","Sub-Object Channel","Edge Padding") pInitColWidths:#(161,50,56,44) pCheckBoxes:false 
		lvObjects.fullRowSelect = true
		lvObjects.hideSelection = false
		lvObjects.LabelEdit = false
		lvobjects.multiselect = false
		lvops.RefreshListView lvObjects
		lastSceneType = undefined
		settingsDirty = false
		
		callbacks.addscript #preModifierAdded "RTT_data.selectedObjectPropsRO.OnModifierChangeEvent #preModifierAdded" id:#rtt_ModifierChange
		callbacks.addscript #postModifierAdded "RTT_data.selectedObjectPropsRO.OnModifierChangeEvent #postModifierAdded" id:#rtt_ModifierChange
		callbacks.addscript #preModifierDeleted "RTT_data.selectedObjectPropsRO.OnModifierChangeEvent #preModifierDeleted" id:#rtt_ModifierChange
		callbacks.addscript #postModifierDeleted "RTT_data.selectedObjectPropsRO.OnModifierChangeEvent #postModifierDeleted" id:#rtt_ModifierChange

		if _debug do format "exit selectedObjectProps.open - time:%\n" (timestamp())
	)  --end, on open

	on selectedObjectProps close do
	(
		callbacks.removeScripts id:#rtt_ModifierChange
		RTT_data.selectedObjectPropsRO = undefined
		if _debug do format "close selectedObjectProps \n"
		WriteConfigData()
	)

	on dObjectPresets selected item do
	(
		if workingObjects.count != 0 do 
		(
			if item <= objectPresetFiles.count then
			(
				local filename = objectPresetFiles[item]
				if not (ApplyObjectPreset filename) then 
					dObjectPresets.selection = objectPresetFiles.count + 1 -- display dashed line...
				else -- move up this file in the Object Presets MRU list and update the MRU dropdown
					AddFileToObjectPresetsMruFiles filename
			)
			else if item == (objectPresetFiles.count + 1) then () -- separator
			else if item == (objectPresetFiles.count + 2) then
				LoadObjectPreset()
			else 
				SaveObjectPreset()
		)
		-- reset dropdown to dashed line entry....
		dObjectPresets.selection = objectPresetFiles.count +1
	)

	-- This event is called once an item is clicked
	function OnLvObjectsClick = 
	(
		local sel = lvops.GetLvSingleSelected lvObjects 
		if _debug do format "in OnLvObjectsClick - sel:%; selectedObjectLVIndex:%\n" arg selectedObjectLVIndex
		--format "click select: % % \n" sel.text sel.index

		if sel != undefined and sel.index != -1 then
		(
			if (not (displayedBakableObjects[ sel.tag ].isWorkingObject)) do
		(
			CloseWorkingObjects() -- accept changes on working objects
			selectedElementProps.CloseSelectedElement() -- accept changes on working elements
			for wo in workingObjects do wo.isWorkingObject = false
			workingObjects = #(displayedBakableObjects[sel.tag] )
			for wo in workingObjects do wo.isWorkingObject = true
			UpdateObjectSettings() -- update working object settings
			RefreshObjectsLV() -- update listview
			selectedElementProps.OnObjectSelectionChange() -- display elements for working object
		)		
			selectedObjectLVIndex = sel.index 
		)
	)
	
	on lvObjects ItemSelectionChanged arg do
	(
		if _debug do format "in lvObjects.ItemSelectionChanged - arg:%\n" arg 
		if (rSceneType.state == 1) then
			OnLvObjectsClick() -- only if 'Individual'
		else if arg.item.selected do
			arg.item.selected = false
	)

	on lvObjects mouseup arg do
	(
		if _debug do format "in lvObjects.mouseup - arg:%; selectedObjectLVIndex:%\n" arg selectedObjectLVIndex
		if rSceneType.state == 1 and (lvops.GetLvItemCount lvObjects) > 0 do
		(
			local sel = lvops.GetSelectedIndex lvObjects 
			if sel == -1 do
	( 
				if selectedObjectLVIndex >= (lvops.GetLvItemCount lvObjects) do
					selectedObjectLVIndex = 0
				lvops.SelectLvItem lvObjects selectedObjectLVIndex
	)
		)
	)
	
	on cBakeEnable changed state do
	(
		settingsDirty = true
	)
	
	on dUseMapChannel_Obj selected val do 
	(	
		settingsDirty = true
		RefreshObjectsLV workingObjectsOnly:true
	)
	
	on dUseMapChannel_SubObj selected val do 
	(	
		settingsDirty = true
		RefreshObjectsLV workingObjectsOnly:true
	)
	
	on sDilations changed val do 
	(	
		settingsDirty = true
		RefreshObjectsLV workingObjectsOnly:true
	)

	on cProjMapEnable changed state do
	(
		settingsDirty = true
		CloseWorkingObjects() -- immediate update 
		UpdateObjectSettings()
		if RTT_data.projectionOptionsPropsRO != undefined do 
			RTT_data.projectionOptionsPropsRO.UpdateSourceName()
	)
	
	on bProjMapOptions changed state do
	(
		if state then createDialog projectionOptionsProps width:350 style:#(#style_sysmenu,#style_titlebar,#style_minimizebox) pos:pProjectionOptionsPropsPos
		else destroyDialog projectionOptionsProps 
	)
	
	on dProjMaps selected val do 
	(
		settingsDirty = true
		CloseWorkingObjects() -- immediate update 
		if RTT_data.projectionOptionsPropsRO != undefined do 
			RTT_data.projectionOptionsPropsRO.UpdateSourceName()
	) 
	
	on rb_mapCoordOpt_Obj changed _newState do
	(
		-- enable auto flatten controls
		doAutoUnwrap_Obj = _newState == 2
		UpdateFlattenEnables doAutoUnwrap_Obj doAutoUnwrap_SubObj cProjMapEnable.checked cSubObjLevelOut.checked
		AutoMapChannelStateChanged()
	)

	on sMapChannel_Obj changed val do
	(
		autoUnwrapChannel_Obj = val 
		AutoMapChannelValChanged()
	)
	
	on rb_mapCoordOpt_SubObj changed _newState do
	(
		-- enable auto flatten controls
		doAutoUnwrap_SubObj = _newState == 2
		UpdateFlattenEnables doAutoUnwrap_Obj doAutoUnwrap_SubObj cProjMapEnable.checked cSubObjLevelOut.checked
		AutoMapChannelStateChanged()
	)

	on sMapChannel_SubObj changed val do
	(
		autoUnwrapChannel_SubObj = val 
		AutoMapChannelValChanged()
	)
	
	on cObjLevelOut changed state do
	(
		settingsDirty = true
		if not state and not cSubObjLevelOut.tristate == 1 do
		(
			cSubObjLevelOut.state = true
			CloseWorkingObjects() -- accept changes on working objects
			UpdateObjectSettings()
		)
	)
	
	on cSubObjLevelOut changed state do
	(
		settingsDirty = true
		if not state and not cObjLevelOut.tristate == 1 do
			cObjLevelOut.state = true
		CloseWorkingObjects() -- accept changes on working objects
		UpdateObjectSettings()
	)
	
	on rb_PutToBakedMtl changed state do
	(
		settingsDirty = true
	)
	
	on rb_SOSize changed state do
	(
		settingsDirty = true
	)
	
	on bClearUnwrap pressed do
	(
		local old_autoBackup_enabled = autoBackup.enabled
		autoBackup.enabled = false
		try
			RemoveFlatteners ()
		catch
		(
			autoBackup.enabled = old_autoBackup_enabled
			throw
		)
		setFocus selectedObjectProps
		autoBackup.enabled = old_autoBackup_enabled
	)

	on bNewTarget pressed do 
	(
		CloseWorkingObjects() -- accept changes on working objects
		local cancelled = false
		with undo "Add Targets" on
		(
			local projModAdded = false
			local activeProjMod = undefined
			-- if no active projection modifier, add one
			if dProjMaps.enabled then -- mod
				activeProjMod = ProjMod_List[amax dProjMaps.selection 1]-- default to first modifier 
			if activeProjMod == undefined do 
			(
				activeProjMod = projection()
				for obj in workingObjects do
					addmodifier obj.node activeProjMod 
				projModAdded = true
			)
			local pmodInterface = activeProjMod.projectionModOps
			rtt_data.pmodInterface = pmodInterface 
			
			function selectFilter obj = rtt_data.pmodInterface.isValidObject obj
			local objList = selectByName title:"Add Targets" buttonText:"Add" filter:selectFilter showhidden:false single:false
			rtt_data.pmodInterface = undefined 
			if objList == undefined then
			(
				if projModAdded do theHold.cancel() -- removes added projection modifier
				cancelled = true
			)
			else
			(
				-- Disable always update cage
				local oldPanel = GetCommandPanelTaskMode()
				if oldPanel != #modify do
					SetCommandPanelTaskMode #modify
				local prevUpdateState = activeProjMod.autoWrapAlwaysUpdate
				activeProjMod.autoWrapAlwaysUpdate = false
				for objNode in objList do
					pmodInterface.AddObjectNode objNode
				pmodInterface.autowrapCage()
				activeProjMod.autoWrapAlwaysUpdate = prevUpdateState
				if projModAdded do 
					for obj in workingObjects do
						obj.node.INodeBakeProjProperties.projectionMod = activeProjMod 
				if oldPanel != #modify do
					SetCommandPanelTaskMode oldPanel 
				if not cProjMapEnable.checked do
				(					
					cProjMapEnable.checked = true
					settingsDirty = true
					CloseWorkingObjects() -- immediate update 
				)
			)
		)
		if not cancelled do
			UpdateObjectSettings()
	)
	-- enable/disable auto-flatten controls  
	function UpdateFlattenEnables _enable_Obj _enable_SubObj obj_control_enabled subobj_control_enabled =
	(
		if _debug do format "in UpdateFlattenEnables : % : % : % : %\n" _enable_Obj _enable_SubObj obj_control_enabled subobj_control_enabled
		sMapChannel_Obj.enabled = _enable_Obj and obj_control_enabled 
		sMapChannel_Obj.visible = _enable_Obj
		dUseMapChannel_Obj.enabled = (not _enable_Obj) and obj_control_enabled
		dUseMapChannel_Obj.visible = not _enable_Obj
		sMapChannel_SubObj.enabled = _enable_SubObj and subobj_control_enabled 
		sMapChannel_SubObj.visible = _enable_SubObj
		dUseMapChannel_SubObj.enabled = (not _enable_SubObj) and subobj_control_enabled 
		dUseMapChannel_SubObj.visible = not _enable_SubObj
		
		autoUnwrapMappingProps.UpdateFlattenEnables _enable_Obj _enable_SubObj
	)			

	-- handler called when changing between Individual/All Selected/All Prepared
	on rSceneType changed newState do
	(
		-- update the nodes' and elements' data if needed
		if workingObjects.count != 0 do
		(
			CloseWorkingObjects() -- accept changes on working objects
			selectedElementProps.CloseSelectedElement() -- accept changes on working elements
		)
		if newState == 1 then -- Individual
		(	
			if lastSceneType == 2 then -- was All Selected. 
			(
				if displayedBakableObjects.count != 0 do
				(	-- See if last picked node is still visible. If so, leave it as picked node. If not, find 
					-- first visible node in list and pick it
					local pickedNode = lvops.GetSelectedIndex lvObjects 
					local firstVisible = (lvObjects.TopItem).index
					-- if _debug do format "picked item test: % : % : %\n" pickedNode firstVisible (if pickedNode != 0 then lvObjects.Items.item[pickedNode].tag else "X")
					if pickedNode >= firstVisible and pickedNode < (firstVisible + numVisibleItems) then
						workingObjects = #(displayedBakableObjects[lvObjects.Items.item[pickedNode].tag])
					else
					(
						workingObjects = #(displayedBakableObjects[lvObjects.Items.item[firstVisible].tag])
						lvops.SelectLvItem lvObjects firstVisible
					)
				)
			)
			else -- was All Prepared
			(
				workingObjects = #()
				gTextureBakeDialog.OnObjectSelectionChange()
				if (displayedBakableObjects.count != 0) do
				(
					workingObjects = #(displayedBakableObjects[lvObjects.Items.item[0].tag])
					lvops.SelectLvItem lvObjects 0
				)
			)
			
			for dbo in displayedBakableObjects do dbo.isWorkingObject = false
			for wo in workingObjects do wo.isWorkingObject = true
			
			UpdateObjectSettings()
			RefreshObjectsLV()
			selectedElementProps.OnObjectSelectionChange() -- display elements for working object
		)
		else 
		(
			lvops.SelectLvItem lvObjects -1
			gTextureBakeDialog.OnObjectSelectionChange()
		)
		
		RebuildObjectPresets false
		
		lastSceneType = newState
		setFocus lvObjects
	)
	 
	-- Function to fill in LvObjects
	function RebuildObjectsLV =
	(	
		if _debug do format "in selectedObjectProps.RebuildObjectsLV \n"
		-- remove all items from the listview
		lvops.ClearLvItems lvObjects

		-- add the list items and sublist items
		local index = 0
		for obj in displayedBakableObjects do
		(
			local args = #(obj.node.name,"","","")
			lvops.AddLvItem lvObjects pTextItems:args pTag:(index += 1) --tooltips:args
		)
		
		UpdateObjectSettings() -- update Selected Object Settings 
		
		RefreshObjectsLV() -- fill in sublist item text
		
		lvops.SelectLvItem lvObjects -1 -- clear current selection
		
		if _debug do format "\trebuild wo update: % : %\n" workingObjects.count rSceneType.state 
		if workingObjects.count == 1 and rSceneType.state == 1 then
		(	
			local notFound = true
			
			if _debug do (
				local lvItems = lvops.GetLvItems lvObjects
				for li in lvItems do format "\t% : %\n" li.tag displayedBakableObjects[li.tag]
			)
			local itemArray = lvops.GetLvItems lvObjects
			for li in itemArray while notFound where displayedBakableObjects[li.tag].isWorkingObject do
			(	
				lvops.RefreshListView lvObjects -- needed to make li.EnsureVisible() work, otherwise li.index is wrong (sort doesn't occur until refresh?)
				li.selected = true
				li.EnsureVisible()
				notFound = false
				if _debug do format "\tset: % : %\n" li.tag li.index
			)
		)
				
	) -- end function RebuildObjectsLV  
	
	-- Function to refresh LvObjects
	-- Selected Object Settings UI items must have be updated before calling this method.
	function RefreshObjectsLV workingObjectsOnly:false =
	(	
		if _debug do format "in selectedObjectProps.RefreshObjectsLV - workingObjectsOnly:%\n" workingObjectsOnly
		-- For working objects: 
		-- if Automatic Unwrap Mapping is on, use the Map Channel specified there as map channel on all objects
		-- otherwise, use channel from the Channel dropdown if a channel is specified there, 
		-- otherwise, will use channel from the node if valid, blank if not
		-- For non-working objects, use channel from the node if valid, blank if not
		local s_autoUnwrapChannel_Obj, newObjChannel_string
		local useNewObjChannel_string = false
		if doAutoUnwrap_Obj then
			s_autoUnwrapChannel_Obj = autoUnwrapChannel_Obj as string
		else
		(
			newObjChannel_string = dUseMapChannel_Obj.selected 
			useNewObjChannel_string = (newObjChannel_string != "" and newObjChannel_string != undefined)
		)
		
		local s_autoUnwrapChannel_SubObj, newSubObjChannel_string
		local useNewSubObjChannel_string = false
		if doAutoUnwrap_SubObj then
			s_autoUnwrapChannel_SubObj = autoUnwrapChannel_SubObj as string
		else
		(
			newSubObjChannel_string = dUseMapChannel_SubObj.selected 
			useNewSubObjChannel_string = (newSubObjChannel_string != "" and newSubObjChannel_string != undefined)
		)
		
		-- For working objects: 
		-- use padding value from the padding spinner if a value is specified there, 
		-- otherwise, will use nDilations value from the node
		-- For non-working objects, use nDilations value from the node
		local newPadding_string
		local useNewPadding_string = not sDilations.indeterminate
		if useNewPadding_string do
			newPadding_string = sDilations.value as string
		
		local listItems = lvops.GetLvItems lvObjects
		for li in listItems do
		(	
			obj = displayedBakableObjects[li.tag]
			if (not workingObjectsOnly) or obj.isWorkingObject do -- don't update unless we are supposed to
			(
				local channel_Obj
				if doAutoUnwrap_Obj and obj.isWorkingObject then
					channel_Obj = s_autoUnwrapChannel_Obj
				else if (not doAutoUnwrap_Obj) and obj.isWorkingObject and useNewObjChannel_string then
					channel_Obj = newObjChannel_string
				else
				(	-- if no uvw map channels, just display a blank
					if (obj.channels.isEmpty) then
						channel_Obj = ""
					else
						channel_Obj = obj.node.INodeBakeProperties.bakeChannel as string
				)
				
				local projInterface = obj.node.INodeBakeProjProperties
				local doSubObjBake = projInterface.enabled and projInterface.BakeSubObjLevels
				local channel_SubObj
				if not doSubObjBake then
						channel_SubObj = ""
				else if doAutoUnwrap_SubObj and obj.isWorkingObject then
					channel_SubObj = s_autoUnwrapChannel_SubObj
				else if (not doAutoUnwrap_SubObj) and obj.isWorkingObject and useNewSubObjChannel_string then
					channel_SubObj = newSubObjChannel_string
				else
				(	-- if no uvw map channels, just display a blank
					if (obj.channels.isEmpty) then
						channel_SubObj = ""
					else
						channel_SubObj = projInterface.subObjBakeChannel as string
				)
				
				local padding
				if obj.isWorkingObject and useNewPadding_string then
					padding = newPadding_string
				else
					padding = obj.node.INodeBakeProperties.nDilations as string
				
				local theNode = obj.node
				local theName = theNode.name
				local bakeProjProperties = theNode.INodeBakeProjProperties
				if bakeProjProperties.enabled and bakeProjProperties.projectionMod != undefined do
				(
					local projMod = bakeProjProperties.projectionMod
					local n = projMod.numGeomSels()
					local count = 0
					for i = 1 to n do
					(
						local geomSelLevel = projMod.getGeomSelLevel i
						if geomSelLevel == #face or geomSelLevel == #element then count += 1
					)
					append theName " ("
					append theName (count as string)
					append theName " SO Outputs)"
				)
				
				li.SubItems.item[0].text = theName 
				li.SubItems.item[1].text = channel_Obj
				li.SubItems.item[2].text = channel_SubObj
				li.SubItems.item[3].text = padding
			)
		)
	) -- end function RefreshObjectsLV
	
	-- function to update the Selected Object Settings UI items
	function UpdateObjectSettings =
	(
		if _debug do format "in selectedObjectProps.UpdateObjectSettings - workingObjects: %\n" workingObjects
		if workingObjects.count == 0 then
		(
			cBakeEnable.state = cBakeEnable.enabled = false
			dUseMapChannel_Obj.items=#()
			dUseMapChannel_Obj.enabled = false
			dUseMapChannel_SubObj.items=#()
			dUseMapChannel_SubObj.enabled = false
			sDilations.indeterminate = true
			sDilations.enabled = false
			cProjMapEnable.state = cProjMapEnable.enabled = false
			bProjMapOptions.enabled = false
			dProjMaps.selection = 0
			dProjMaps.enabled = false
			bNewTarget.enabled = false
			bClearUnwrap.enabled = false
			cObjLevelOut.state = cObjLevelOut.enabled = false
			cSubObjLevelOut.state = cSubObjLevelOut.enabled = false
			rb_PutToBakedMtl.enabled = false
			rb_SOSize.enabled = false
			
			l_mapCoordOpt_Obj.enabled = false
			rb_mapCoordOpt_Obj.enabled = false
			l_mapChannel_Obj.enabled = false
			dUseMapChannel_Obj.enabled = false
			sMapChannel_Obj.enabled = false
					
			l_mapCoordOpt_SubObj.enabled = false
			rb_mapCoordOpt_SubObj.enabled = false
			l_mapChannel_SubObj.enabled = false
			dUseMapChannel_SubObj.enabled = false
			sMapChannel_SubObj.enabled = false

			UpdateFlattenEnables doAutoUnwrap_Obj doAutoUnwrap_SubObj false false
		)
		else
		(
			local isEnabled = triStateValue()
			local mapChannel = triStateValue()
			local dilations = triStateValue()
			local projMapEnabled = triStateValue()
			local projMod = triStateValue()
			
			local objLevelOut = triStateValue()
			local subObjLevelOut = triStateValue()
			local putToBakedMtl = triStateValue()
			local subObjSize = triStateValue()
			local subobjMapChannel = triStateValue()
				
			local modifierArrays = #() -- array containing array of Projection modifier on each node
			for obj in workingObjects do
			(
				local bakeInterface = obj.node.INodeBakeProperties
				isEnabled.setVal bakeInterface.bakeEnabled
				mapChannel.setVal bakeInterface.bakeChannel
				dilations.setVal bakeInterface.nDilations
				if _debug do format "node INodeBakeProperties: % % % : % % %\n" isEnabled mapChannel dilations bakeInterface.bakeEnabled bakeInterface.bakeChannel bakeInterface.nDilations
				local projInterface = obj.node.INodeBakeProjProperties
				projMapEnabled.setVal projInterface.enabled 
				
				local myProjMod = projInterface.projectionMod
				local modList = obj.node.modifiers
				local tmpModifierArray = for mod in modList where (classof mod == Projection) collect mod
				append modifierArrays tmpModifierArray 
				if myProjMod == undefined and tmpModifierArray.count != 0 do myProjMod = projInterface.projectionMod = tmpModifierArray[1]
				projMod.setVal myProjMod 
				
				objLevelOut.setVal projInterface.BakeObjectLevel
				subObjLevelOut.setVal projInterface.BakeSubObjLevels
				putToBakedMtl.setVal projInterface.useObjectBakeForMtl
				subObjSize.setVal projInterface.proportionalOutput 
				subobjMapChannel.setVal projInterface.subObjBakeChannel
				if _debug do format "node INodeBakeProjProperties 1: % % % : % % %\n" projMapEnabled projMod objLevelOut projInterface.enabled projInterface.projectionMod projInterface.BakeObjectLevel
				if _debug do format "node INodeBakeProjProperties 2: % % % % : % % % %\n" subObjLevelOut putToBakedMtl subObjSize subobjMapChannel projInterface.BakeSubObjLevels projInterface.useObjectBakeForMtl projInterface.proportionalOutput projInterface.subObjBakeChannel
			)
			local projModifiers = CollectCommonElements modifierArrays -- returns array of Projection modifiers that are on all nodes
			local projModNames = #("(No Projection Modifier)")
			ProjMod_List = #(undefined)
			for mod in projModifiers do 
			(	
				append projModNames mod.name
				append ProjMod_List mod
			)
			if _debug do format "projModifiers: %; projMod: %\n" projModifiers projMod
			
			if projModifiers.count == 0 then
			(
--				append projModNames "(No Projection Modifier)"
				dProjMaps.enabled = false
			)
			else
				dProjMaps.enabled = true
			
			dProjMaps.items = projModNames
			if ProjMod_List.count == 0 then
				dProjMaps.selection = 1
			else if projMod.indeterminate then
				dProjMaps.selection = 0
			else if projMod.value == undefined then
				dProjMaps.selection = 1
			else
			(
				local sel = 0
				for i = 1 to ProjMod_List.count while sel == 0 do
					if ProjMod_List[i] == projMod.value do sel = i
				dProjMaps.selection = sel
			)
			
			cBakeEnable.triState = isEnabled.asTriState()
			cProjMapEnable.triState = projMapEnabled.asTriState()

			cObjLevelOut.triState = objLevelOut.asTriState()
			cSubObjLevelOut.triState = subObjLevelOut.asTriState()
			rb_PutToBakedMtl.state = if putToBakedMtl.indeterminate then 0 else if putToBakedMtl.value then 1 else 2
			rb_SOSize.state = if subObjSize.indeterminate then 0 else if subObjSize.value then 2 else 1
			
			dilations.spinnerSet sDilations
			
			local projMappingEnabled = projMapEnabled.asTriState() != 0
			local subObjProjMappingEnabled = projMappingEnabled and cSubObjLevelOut.checked

			if _debug do format "in selectedObjectProps.UpdateObjectSettings - states: % : % : %\n" projMappingEnabled (projMapEnabled.asTriState()) subObjProjMappingEnabled
			-- if Object Automatic Unwrap Mapping is on, use the Map Channel specified there
			-- if off, find common map channels 
			if doAutoUnwrap_Obj then
			(
				dUseMapChannel_Obj.enabled = false
				dUseMapChannel_Obj.items=#()
			)
			else
			(
				dUseMapChannel_Obj.enabled = true
				local uvw_mapChannels = #{1..99}
				for obj in workingObjects do
					uvw_mapChannels *= obj.channels
				-- uvw_mapChannels contains common map channels. If we have a value for mapChannel (i.e., a single common 
				-- bake channel), see if that channel is in the common map channels. If so, make sure it is displayed,
				-- otherwise use first item.
				local selectedItem = undefined
				if (not mapChannel.indeterminate) and uvw_mapChannels[mapChannel.value] do
					selectedItem = mapChannel.value
				local uvw_mapChannels = uvw_mapChannels as array -- convert to integer array
				if selectedItem != undefined do -- have value, need index
					selectedItem = findItem uvw_mapChannels selectedItem
				for i = 1 to uvw_mapChannels.count do -- convert to text array
					uvw_mapChannels[i] = uvw_mapChannels[i] as string
				dUseMapChannel_Obj.items=uvw_mapChannels -- set the dropdown list
				if selectedItem != undefined do
					dUseMapChannel_Obj.selection = selectedItem 
			) 

			-- if SubObject Automatic Unwrap Mapping is on, use the Map Channel specified there
			-- if off, find common map channels 
			if doAutoUnwrap_SubObj or not subObjProjMappingEnabled then
			(
				dUseMapChannel_SubObj.enabled = false
				dUseMapChannel_SubObj.items=#()
			)
			else
			(
				dUseMapChannel_SubObj.enabled = true
				local uvw_mapChannels = #{1..99}
				for obj in workingObjects do
					uvw_mapChannels *= obj.channels
				-- uvw_mapChannels contains common map channels. If we have a value for mapChannel (i.e., a single common 
				-- bake channel), see if that channel is in the common map channels. If so, make sure it is displayed,
				-- otherwise use first item.
				local selectedItem = undefined
				if (not subobjMapChannel.indeterminate) and uvw_mapChannels[subobjMapChannel.value] do
					selectedItem = subobjMapChannel.value
				local uvw_mapChannels = uvw_mapChannels as array -- convert to integer array
				if selectedItem != undefined do -- have value, need index
					selectedItem = findItem uvw_mapChannels selectedItem
				for i = 1 to uvw_mapChannels.count do -- convert to text array
					uvw_mapChannels[i] = uvw_mapChannels[i] as string
				dUseMapChannel_SubObj.items=uvw_mapChannels -- set the dropdown list
				if selectedItem != undefined do
					dUseMapChannel_SubObj.selection = selectedItem 
			) 

			cBakeEnable.enabled = sDilations.enabled = true
			cProjMapEnable.enabled = bProjMapOptions.enabled = dProjMaps.enabled = true
			bNewTarget.enabled = true -- workingObjects.count == 1
			bClearUnwrap.enabled = true
			
			cObjLevelOut.enabled = cSubObjLevelOut.enabled = rb_PutToBakedMtl.enabled = projMappingEnabled

			rb_SOSize.enabled = subObjProjMappingEnabled
			
			l_mapCoordOpt_Obj.enabled = true
			rb_mapCoordOpt_Obj.enabled = true
			l_mapChannel_Obj.enabled = true
					
			l_mapCoordOpt_SubObj.enabled = subObjProjMappingEnabled
			rb_mapCoordOpt_SubObj.enabled = subObjProjMappingEnabled
			l_mapChannel_SubObj.enabled = subObjProjMappingEnabled

			UpdateFlattenEnables doAutoUnwrap_Obj doAutoUnwrap_SubObj true subObjProjMappingEnabled

		) -- workingObjects.count != 0
		
		if projectionOptionsProps.isDisplayed do projectionOptionsProps.UpdateObjectSettings()
		
	) -- end fn UpdateObjectSettings 

	-------------------------------------------------------
	-- function to close the working object & update properties for the
	-- objects. Not done on cancel
	-- called when switching objects in the UI or in listview, on Close, and when changing display types
	-- NB: switching objects writes the changes with no cancel & no undo ...
	function CloseWorkingObjects =
	(
		if settingsDirty do
		(
			if _debug do format "in selectedObjectProps.CloseWorkingObjects: \n" 
	
			-- for each object in the selection
			for obj in workingObjects where isValidNode obj.node do
			(
				local bakeInterface = obj.node.INodeBakeProperties
				local projInterface = obj.node.INodeBakeProjProperties
				if _debug do format "\tclose object: % \n" obj.node.name
				
				-- check for confused, only set un-confused elements!
				if cBakeEnable.triState != 2 then
					bakeInterface.bakeEnabled = cBakeEnable.checked
					
				if dUseMapChannel_Obj.selected != undefined and dUseMapChannel_Obj.selected != "" then
					bakeInterface.bakeChannel = dUseMapChannel_Obj.selected as integer
					
				if dUseMapChannel_SubObj.selected != undefined and dUseMapChannel_SubObj.selected != "" then
					projInterface.subObjBakeChannel = dUseMapChannel_SubObj.selected as integer
					
				if sDilations.indeterminate == false then
					bakeInterface.nDilations = sDilations.value

				if _debug do format "CloseWorkingObjects - cProjMapEnable.triState : %\n" cProjMapEnable.triState 
				if cProjMapEnable.triState != 2 then
					projInterface.enabled = cProjMapEnable.checked

				if dProjMaps.enabled and dProjMaps.selection != 0 then
					projInterface.projectionMod = ProjMod_List[dProjMaps.selection]
					
				if cObjLevelOut.enabled and cObjLevelOut.triState != 2 then
					projInterface.BakeObjectLevel = cObjLevelOut.checked

				if cSubObjLevelOut.enabled and cSubObjLevelOut.triState != 2 then
					projInterface.BakeSubObjLevels = cSubObjLevelOut.checked

				if rb_PutToBakedMtl.enabled and rb_PutToBakedMtl.state != 0 then
					projInterface.useObjectBakeForMtl = rb_PutToBakedMtl.state == 1

				if rb_SOSize.enabled and rb_SOSize.state != 0 then
					projInterface.proportionalOutput = rb_SOSize.state == 2
			) 
			RefreshObjectsLV workingObjectsOnly:true
			settingsDirty = false
		)
	) -- end function CloseWorkingObjects

	function AutoMapChannelValChanged =
	(
		if doAutoUnwrap_Obj or doAutoUnwrap_SubObj do 
			RefreshObjectsLV workingObjectsOnly:true
		WriteSceneData()
	) -- end function AutoMapChannelValChanged

	function AutoMapChannelStateChanged =
	(
		UpdateObjectSettings()
		RefreshObjectsLV workingObjectsOnly:true
		WriteSceneData()
	) -- end function AutoMapChannelStateChanged 
	
	function ReadConfigData =
	(
		rb_mapCoordOpt_Obj.state =		if RTT_data.AutoFlatten_Obj_On then 2 else 1
		sMapChannel_Obj.value = 		RTT_data.AutoFlatten_Obj_MapChannel
		rb_mapCoordOpt_SubObj.state =	if RTT_data.AutoFlatten_SubObj_On then 2 else 1
		sMapChannel_SubObj.value = 		RTT_data.AutoFlatten_SubObj_MapChannel

		autoUnwrapChannel_Obj = sMapChannel_Obj.value
		doAutoUnwrap_Obj = rb_mapCoordOpt_Obj.state == 2
		autoUnwrapChannel_SubObj = sMapChannel_SubObj.value
		doAutoUnwrap_SubObj = rb_mapCoordOpt_SubObj.state == 2
		
	)

	function WriteConfigData =
	(
		RTT_data.AutoFlatten_Obj_On = 				rb_mapCoordOpt_Obj.state == 2
		RTT_data.AutoFlatten_Obj_MapChannel =		sMapChannel_Obj.value
		RTT_data.AutoFlatten_SubObj_On = 			rb_mapCoordOpt_SubObj.state == 2
		RTT_data.AutoFlatten_SubObj_MapChannel =	sMapChannel_SubObj.value
	)

	function OnModifierChangeEvent event =
	(
		if not RTT_Data.ignoreModStackChanges do
		(
			local info = callbacks.notificationParam()
			if _debug do format "in selectedObjectProps.OnModifierChangeEvent : % : %\n" event info
			local theNode = classof info[1]
			local modClass = classof info[2]
			if (isValidNode theNode) and (modClass == projection or modClass == Unwrap_UVW) do
			(
				local notFound = true
				for obj in workingObjects while notFound where isValidNode obj.node do
				(
					if theNode == obj.node do
					(
						notFound = false
						if event == #preModifierAdded or event == #preModifierDeleted then
							CloseWorkingObjects()
						else
							UpdateObjectSettings()
					)
				)
			) 
		)
	)

	function AddFileToObjectPresetsMruFiles filename = 
	(
		if _debug do format "AddFileToObjectPresetsMruFiles: % \n" filename 

		-- add filename to the Object Presets MRU list if it isn't already in list and update the MRU dropdown
		-- if filename is in list, move it to the top
		local sectionName = "ObjectPresetsMruFiles" 
		delinisetting iniFile sectionName -- clear section -- do not localize this
		if _debug do format "\tobjectPresetFiles: % \n" objectPresetFiles 
		for i = objectPresetFiles.count to 1 by -1 do
			if (stricmp filename objectPresetFiles[i]) == 0 do
				deleteItem objectPresetFiles i
		insertItem filename objectPresetFiles 1
		if objectPresetFiles.count > 10 do objectPresetFiles.count = 10
		if _debug do format "\tobjectPresetFiles: % \n" objectPresetFiles 
		for i = 1 to objectPresetFiles.count do
		(
			local keyName = "ObjectPresetsMruFile" + (i as string) -- do not localize this
			SetINIConfigData iniFile sectionName keyName objectPresetFiles[i]
		)
		RebuildObjectPresets true
		dObjectPresets.selection = 1
	)
	
	function LoadObjectPresetList =
	(
		if _debug do format "in LoadObjectPresetList\n"
		objectPresetFiles = #() 
		-- get key names for [ObjectPresetsMruFiles] section 
		local keys = getinisetting iniFile "ObjectPresetsMruFiles"
		if _debug do format "\tkeys: % \n" keys 
		for k in keys do
		(
			local filename = getinisetting iniFile "ObjectPresetsMruFiles" k
			if _debug do format "\tkey, filename: %; % \n" k filename
			if filename != "" and (doesFileExist filename) do
				append objectPresetFiles filename
		)
		objectPresetFiles
	)

	function RebuildObjectPresets loadObjectPresetFiles = 
	(
		if _debug do format "in RebuildObjectPresets - loadObjectPresetFiles:%; iniFile:%; \n" loadObjectPresetFiles iniFile
		if _debug do format "\tobjectPresetFiles:%; getdir #plugcfg:% \n" objectPresetFiles (getdir #plugcfg)
		if (loadObjectPresetFiles) do 
			LoadObjectPresetList()
		if workingObjects.count != 0 then
		(
			local objectPresetNames = #()
			local count = objectPresetFiles.count
			objectPresetNames.count = count+1
			if _debug do format "objectPresetFiles: %\n" objectPresetFiles
			for i = 1 to count do objectPresetNames[i] = getFilenameFile (objectPresetFiles[i])
			objectPresetNames[count+1]="-----------------------------------------------------------------------------------------"
			objectPresetNames[count+2]="Load Object Preset..."
			if workingObjects.count == 1 do
				objectPresetNames[count+3]="Save Object Preset..."
			if _debug do format "objectPresetNames: %\n" objectPresetNames 
			dObjectPresets.items = objectPresetNames
			dObjectPresets.selection = count+1
		)
		else
		(
			dObjectPresets.items = #("-----------------------------------------------------------------------------------------")
			dObjectPresets.selection = 1
		)
		
		if _debug do format "exit RebuildObjectPresets - objectPresetFiles:%\n" objectPresetFiles
	) -- end fn RebuildObjectPresets 
	
	function LoadObjectPreset =
	(
		local filename = getOpenFileName caption:"Render To Texture Object Presets Open" filename:(getDir #renderPresets + @"\") types:"Object Preset(*.rtp)|*.rtp" historyCategory:"RTTObjectPresets" --LOC_NOTES: localize this
		if filename == undefined do return false
		if not (ApplyObjectPreset filename noWarn:true) do return false

		if _debug do format "add file to the Object Presets MRU list: %\n" filename

		-- add this file to the Object Presets MRU list and update the MRU dropdown
		AddFileToObjectPresetsMruFiles filename
		true
	)
	
	function SaveObjectPreset =
	(
		if workingObjects.count != 1 do
		(	
			messageBox "There must be a single working object in order to save object presets." title:"Render To Texture" --LOC_NOTES: localize this
			return false;
		)
		-- get the .rtp file to save to. The .rtp file is handled as a .ini file.
		local filename = undefined
		while (filename == undefined) do
		(
			filename = getSaveFileName caption:"Render To Texture Object Presets Save" filename:(getDir #renderPresets + @"\") types:"Object Preset(*.rtp)|*.rtp" historyCategory:"RTTObjectPresets"--LOC_NOTES: localize this
			if filename == undefined do return false
			if doesFileExist filename do
			(
				deleteFile filename
				if doesFileExist filename do
				(
					messageBox "Could not delete file. Most likely a read-only file." title:"Render To Texture" --LOC_NOTES: localize this
					filename = undefined
				)
			)
		)
		
		selectedObjectProps.CloseWorkingObjects()
		selectedElementProps.CloseSelectedElement()
		
		local workingObject = workingObjects[1]
		local bakeInterface = workingObject.node.INodeBakeProperties
		local projInterface = workingObject.node.INodeBakeProjProperties
		
		local sectionName = "Object Settings" -- do not localize this
		SetINIConfigData filename sectionName "BakeEnable" bakeInterface.bakeEnabled
		SetINIConfigData filename sectionName "Padding" bakeInterface.nDilations
		
		local sectionName = "Projection Mapping Settings" -- do not localize this
		SetINIConfigData filename sectionName "ProjMapEnable" projInterface.enabled 
		SetINIConfigData filename sectionName "ObjectLevel" projInterface.BakeObjectLevel
		SetINIConfigData filename sectionName "SubObjectLevels" projInterface.BakeSubObjLevels
		SetINIConfigData filename sectionName "ObjectPutToBakedMtl" projInterface.useObjectBakeForMtl
		SetINIConfigData filename sectionName "SubObjectFullSize" projInterface.proportionalOutput 
		-- Projection Options dialog
		SetINIConfigData filename sectionName "CropAlpha" projInterface.cropAlpha 
		SetINIConfigData filename sectionName "ProjectionSpace" projInterface.projSpace 
		SetINIConfigData filename sectionName "UseCage" projInterface.useCage 
		SetINIConfigData filename sectionName "Offset" projInterface.rayOffset 
		SetINIConfigData filename sectionName "HitResolveMode" projInterface.hitResolveMode 
		SetINIConfigData filename sectionName "HitMatchMtlID" projInterface.hitMatchMtlID 
		SetINIConfigData filename sectionName "HitWorkingModel" projInterface.hitWorkingModel 
		SetINIConfigData filename sectionName "RayMissCheck" projInterface.warnRayMiss 
		SetINIConfigData filename sectionName "RayMissColor" projInterface.rayMissColor 
		SetINIConfigData filename sectionName "NormalSpace" projInterface.normalSpace 
		SetINIConfigData filename sectionName "NormalYDir" projInterface.tangentYDir 
		SetINIConfigData filename sectionName "NormalXDir" projInterface.tangentXDir 
		SetINIConfigData filename sectionName "HeightMapMin" projInterface.heightMapMin 
		SetINIConfigData filename sectionName "HeightMapMax" projInterface.heightMapMax 
		SetINIConfigData filename sectionName "HasProjectionModifier" (projInterface.ProjectionMod != undefined) 
		
		local sectionName = "Mapping Coordinates" -- do not localize this
		SetINIConfigData filename sectionName "DoObjectAutoUnwrap" RTT_data.AutoFlatten_Obj_On
		SetINIConfigData filename sectionName "ObjectChannel_Existing" bakeInterface.bakeChannel
		SetINIConfigData filename sectionName "ObjectChannel_AutoFlatten" RTT_data.AutoFlatten_Obj_MapChannel
		SetINIConfigData filename sectionName "DoSubObjectAutoUnwrap" RTT_data.AutoFlatten_SubObj_On
		SetINIConfigData filename sectionName "SubObjectChannel_Existing" projInterface.subObjBakeChannel
		SetINIConfigData filename sectionName "SubObjectChannel_AutoFlatten" RTT_data.AutoFlatten_SubObj_MapChannel

		local nElems = bakeInterface.NumBakeElements()

		local sectionName = "BakeElements" -- do not localize this
		SetINIConfigData filename sectionName "NumBakeElements" nElems
		
		for i = 1 to nElems do
		(
			local sectionName = "BakeElement_" + (i as string) -- do not localize this
			local element = bakeInterface.GetBakeElement i
			SetINIConfigData filename sectionName "Class" (classof element)
			SetINIConfigData filename sectionName "Enabled" element.enabled
			SetINIConfigData filename sectionName "ElementName" element.elementName
			local out_filename = element.fileName
			if out_filename != undefined do out_filename = filenameFromPath out_filename
			SetINIConfigData filename sectionName "FileName" out_filename
			SetINIConfigData filename sectionName "BackgroundColor" element.backgroundColor
			SetINIConfigData filename sectionName "AutoSize" element.autoSzOn
			SetINIConfigData filename sectionName "OutputSizeX" element.outputSzX
			SetINIConfigData filename sectionName "OutputSizeY" element.outputSzY
			SetINIConfigData filename sectionName "TargetMapSlotName" element.targetMapSlotName
			
			sectionName += "_Properties"  -- do not localize this
			local nParams = bakeInterface.numElementParams element
			for i = 1 to nParams do
			(
				local param_name  = bakeInterface.paramName element i
				local param_val  = bakeInterface.paramValue element i
				SetINIConfigData filename sectionName param_name param_val
			)
		)

		AddFileToObjectPresetsMruFiles filename
	)
	
	function ApplyObjectPreset filename noWarn:false=
	(
		if _debug2 do format "ApplyObjectPreset: %, noWarn: %, RTT_data.loadObjectPresetOk: %, RTT_data.loadObjectPresetProjModOk: %\n" filename noWarn RTT_data.loadObjectPresetOk RTT_data.loadObjectPresetProjModOk

		if workingObjects.count == 0 do
		(	
			messageBox "There must be at least one working object in order to apply object presets." title:"Render To Texture" --LOC_NOTES: localize this
			return false;
		)

		-- check to see if preset has proj modifier defined
		local sectionName = "Projection Mapping Settings" -- do not localize this
		GetINIConfigDataIfExists filename sectionName "HasProjectionModifier" &projInterface_uses_ProjectionMod
		local uses_ProjectionMod = false
		if projInterface_uses_ProjectionMod != unsupplied do uses_ProjectionMod = projInterface_uses_ProjectionMod

		local return_value = false
		
		local okToLoad = noWarn
		if not noWarn do
		(
			if (not uses_ProjectionMod) and RTT_data.loadObjectPresetOk < 2 then 
			(
				--LOC_NOTES: localize following
				local msg = "Loading RTT Preset\nFilename: " + filename
				RTT_data.loadObjectPresetOk = DisplayOKCancelDontShowAgainDialog "Render To Texture" msg pos:&pLoadPresetOKBoxPos
				okToLoad = RTT_data.loadObjectPresetOk > 0
			)
			else if uses_ProjectionMod and ProjMod_List.count == 2 and RTT_data.loadObjectPresetOk < 2 then
			(
				--LOC_NOTES: localize following
				local msg = "Loading RTT Preset\nFilename: " + filename
				msg += "\n\nThis preset uses the Projection Modifier."
				RTT_data.loadObjectPresetOk = DisplayOKCancelDontShowAgainDialog "Render To Texture" msg pos:&pLoadPresetOKBoxPos
				okToLoad = RTT_data.loadObjectPresetOk > 0
			)
			else if uses_ProjectionMod and ProjMod_List.count != 2 and RTT_data.loadObjectPresetProjModOk < 2 then
			(
				if _debug2 do format "workingObjects.count: %, ProjMod_List.count: %\n" workingObjects.count ProjMod_List.count
				if workingObjects.count == 1 then
				(
					-- one node - handle 2 warning cases - no proj modifer, multiple proj modifiers
					if ProjMod_List.count <= 1 then -- should always have 1 element - 'No Projection Modifier'
					(
						--LOC_NOTES: localize following
						local msg = "Loading RTT Preset\nFilename: " + filename
						msg += "\n\nThis preset requires that the selected object has a Projection Modifier."
						msg += "\n\"Pick\" will apply a Projection Modifier to the selected object."
						RTT_data.loadObjectPresetProjModOk = DisplayOKCancelDontShowAgainDialog "Render To Texture" msg pos:&pLoadPresetOKBoxPos
						okToLoad = RTT_data.loadObjectPresetProjModOk > 0
					)
					else 
					(
						--LOC_NOTES: localize following
						local msg = "Loading RTT Preset\nFilename: " + filename
						msg += "\n\nThis preset requires that the selected object has a Projection Modifier."
						msg += "\nSelect appropriate Projection Modifier from Projection Modifier dropdown list."
						RTT_data.loadObjectPresetProjModOk = DisplayOKCancelDontShowAgainDialog "Render To Texture" msg pos:&pLoadPresetOKBoxPos
						okToLoad = RTT_data.loadObjectPresetProjModOk > 0
					)
				)
				else
				(
					-- multiple nodes - handle 2 warning cases - no common proj modifer, multiple common proj modifiers
					if ProjMod_List.count <= 1 then -- should always have 1 element - 'No Projection Modifier'
					(
						-- two subcases - one or more node doesn't have a proj modifier, all nodes have a proj modifier but no common proj modifier
						local noProjModifierOnAtLeastOneNode = false
						for obj in workingObjects while not noProjModifierOnAtLeastOneNode do
						(
							local notFound = true
							local modList = obj.node.modifiers
							for mod in modList while notFound where (classof mod == Projection) do notFound = false
							if notFound do noProjModifierOnAtLeastOneNode = true
						)
						if noProjModifierOnAtLeastOneNode then
						(
							--LOC_NOTES: localize following
							local msg = "Loading RTT Preset\nFilename: " + filename
							msg += "\n\nThis preset requires that all the selected objects have Projection Modifiers."
							msg += "\nAt least one selected object does not have a Projection Modifier."
							msg += "\n\"Pick\" will apply a common Projection Modifier to the selected objects."
							RTT_data.loadObjectPresetProjModOk = DisplayOKCancelDontShowAgainDialog "Render To Texture" msg pos:&pLoadPresetOKBoxPos
							okToLoad = RTT_data.loadObjectPresetProjModOk > 0
						)
						else
						(
							--LOC_NOTES: localize following
							local msg = "Loading RTT Preset\nFilename: " + filename
							msg += "\n\nThis preset requires that the selected objects have Projection Modifiers."
							msg += "\nNo common Projection Modifier is present on all selected objects."
							msg += "\nCurrent Projection Modifier for each object will be used, or "
							msg += "\n\"Pick\" will apply a common Projection Modifier to the selected objects."
							RTT_data.loadObjectPresetProjModOk = DisplayOKCancelDontShowAgainDialog "Render To Texture" msg pos:&pLoadPresetOKBoxPos
							okToLoad = RTT_data.loadObjectPresetProjModOk > 0
						)
					)
					else 
					(
						--LOC_NOTES: localize following
						local msg = "Loading RTT Preset\nFilename: " + filename
						msg += "\n\nThis preset requires that all the selected objects have Projection Modifiers."
						msg += "\nMultiple common Projection Modifiers are present on the selected objects."
						msg += "\nSelect appropriate Projection Modifier from Projection Modifier dropdown list."
						RTT_data.loadObjectPresetProjModOk = DisplayOKCancelDontShowAgainDialog "Render To Texture" msg pos:&pLoadPresetOKBoxPos
						okToLoad = RTT_data.loadObjectPresetProjModOk > 0
					)
				)
			)
			else
				okToLoad = true
		)
	
		if okToLoad then
		(
			if _debug do format "performing ApplyObjectPreset: %\n" filename
				
			-- load all the data...
			
			local sectionName = "Object Settings" -- do not localize this
			GetINIConfigDataIfExists filename sectionName "BakeEnable" &bakeInterface_bakeEnabled
			GetINIConfigDataIfExists filename sectionName "Padding" &bakeInterface_nDilations
			
			local sectionName = "Projection Mapping Settings" -- do not localize this
			GetINIConfigDataIfExists filename sectionName "ProjMapEnable" &projInterface_enabled 
			GetINIConfigDataIfExists filename sectionName "ObjectLevel" &projInterface_BakeObjectLevel
			GetINIConfigDataIfExists filename sectionName "SubObjectLevels" &projInterface_BakeSubObjLevels
			GetINIConfigDataIfExists filename sectionName "ObjectPutToBakedMtl" &projInterface_useObjectBakeForMtl
			GetINIConfigDataIfExists filename sectionName "SubObjectFullSize" &projInterface_proportionalOutput 
			-- Projection Options dialog
			GetINIConfigDataIfExists filename sectionName "CropAlpha" &projInterface_cropAlpha 
			GetINIConfigDataIfExists filename sectionName "ProjectionSpace" &projInterface_projSpace 
			GetINIConfigDataIfExists filename sectionName "UseCage" &projInterface_useCage 
			GetINIConfigDataIfExists filename sectionName "Offset" &projInterface_rayOffset 
			GetINIConfigDataIfExists filename sectionName "HitResolveMode" &projInterface_hitResolveMode 
			GetINIConfigDataIfExists filename sectionName "HitMatchMtlID" &projInterface_hitMatchMtlID 
			GetINIConfigDataIfExists filename sectionName "HitWorkingModel" &projInterface_hitWorkingModel 
			GetINIConfigDataIfExists filename sectionName "RayMissCheck" &projInterface_warnRayMiss 
			GetINIConfigDataIfExists filename sectionName "RayMissColor" &projInterface_rayMissColor 
			GetINIConfigDataIfExists filename sectionName "NormalSpace" &projInterface_normalSpace 
			GetINIConfigDataIfExists filename sectionName "NormalYDir" &projInterface_tangentYDir 
			GetINIConfigDataIfExists filename sectionName "NormalXDir" &projInterface_tangentXDir 
			GetINIConfigDataIfExists filename sectionName "HeightMapMin" &projInterface_heightMapMin 
			GetINIConfigDataIfExists filename sectionName "HeightMapMax" &projInterface_heightMapMax 
			
			local sectionName = "Mapping Coordinates" -- do not localize this
			GetINIConfigDataIfExists filename sectionName "DoObjectAutoUnwrap" &RTT_data_AutoFlatten_Obj_On
			GetINIConfigDataIfExists filename sectionName "ObjectChannel_Existing" &bakeInterface_bakeChannel
			GetINIConfigDataIfExists filename sectionName "ObjectChannel_AutoFlatten" &RTT_data_AutoFlatten_Obj_MapChannel
			GetINIConfigDataIfExists filename sectionName "DoSubObjectAutoUnwrap" &RTT_data_AutoFlatten_SubObj_On
			GetINIConfigDataIfExists filename sectionName "SubObjectChannel_Existing" &projInterface_subObjBakeChannel
			GetINIConfigDataIfExists filename sectionName "SubObjectChannel_AutoFlatten" &RTT_data_AutoFlatten_SubObj_MapChannel

			local sectionName = "BakeElements" -- do not localize this
			local nElems = GetINIConfigData filename sectionName "NumBakeElements" 0
			if _debug do format "\tApplyObjectPreset - NumBakeElements: %\n" nElems
			
			local element_data = #()
			struct ele_data_def (class, enabled, elementName, fileName, backgroundColor, autoSzOn, outputSzX, outputSzY, targetMapSlotName, ele_param_data=#())
			struct param_name_val_def (name, value)
			for i = 1 to nElems do
			(
				local ele_data = ele_data_def()
				append element_data ele_data
				local sectionName = "BakeElement_" + (i as string) -- do not localize this
				GetINIConfigDataIfExists filename sectionName "Class" &ele_data.class
				GetINIConfigDataIfExists filename sectionName "Enabled" &ele_data.enabled
				GetINIConfigDataIfExists filename sectionName "ElementName" &ele_data.elementName isString:true
				GetINIConfigDataIfExists filename sectionName "FileName" &ele_data.filename isString:true
				GetINIConfigDataIfExists filename sectionName "BackgroundColor" &ele_data.backgroundColor
				GetINIConfigDataIfExists filename sectionName "AutoSize" &ele_data.autoSzOn
				GetINIConfigDataIfExists filename sectionName "OutputSizeX" &ele_data.outputSzX
				GetINIConfigDataIfExists filename sectionName "OutputSizeY" &ele_data.outputSzY
				GetINIConfigDataIfExists filename sectionName "TargetMapSlotName" &ele_data.targetMapSlotName isString:true

				sectionName += "_Properties"  -- do not localize this
				local paramNames = getINISetting filename sectionName
				for param_name in paramNames do
				(
					local param_name_val = param_name_val_def(param_name)
					append ele_data.ele_param_data param_name_val
					GetINIConfigDataIfExists filename sectionName param_name &param_name_val.value
				)
			)
			if _debug do format "\tApplyObjectPreset - element_data: %\n" element_data

			-- apply non-object properties
			if RTT_data_AutoFlatten_Obj_On != unsupplied do RTT_data.AutoFlatten_Obj_On = RTT_data_AutoFlatten_Obj_On
			if RTT_data_AutoFlatten_Obj_MapChannel != unsupplied do RTT_data.AutoFlatten_Obj_MapChannel = RTT_data_AutoFlatten_Obj_MapChannel
			if RTT_data_AutoFlatten_SubObj_On != unsupplied do RTT_data.AutoFlatten_SubObj_On = RTT_data_AutoFlatten_SubObj_On
			if RTT_data_AutoFlatten_SubObj_MapChannel != unsupplied do RTT_data.AutoFlatten_SubObj_MapChannel = RTT_data_AutoFlatten_SubObj_MapChannel

			-- all the data loaded, start applying to objects
			for obj in workingObjects do
			(
				local bakeInterface = obj.node.INodeBakeProperties
				local projInterface = obj.node.INodeBakeProjProperties

				if bakeInterface_bakeEnabled != unsupplied do bakeInterface.bakeEnabled = bakeInterface_bakeEnabled
				if bakeInterface_nDilations != unsupplied do bakeInterface.nDilations = bakeInterface_nDilations
				if projInterface_enabled  != unsupplied do projInterface.enabled  = projInterface_enabled 
				if projInterface_BakeObjectLevel != unsupplied do projInterface.BakeObjectLevel = projInterface_BakeObjectLevel
				if projInterface_BakeSubObjLevels != unsupplied do projInterface.BakeSubObjLevels = projInterface_BakeSubObjLevels
				if projInterface_useObjectBakeForMtl != unsupplied do projInterface.useObjectBakeForMtl = projInterface_useObjectBakeForMtl
				if projInterface_proportionalOutput  != unsupplied do projInterface.proportionalOutput  = projInterface_proportionalOutput 
				if projInterface_cropAlpha  != unsupplied do projInterface.cropAlpha  = projInterface_cropAlpha 
				if projInterface_projSpace  != unsupplied do projInterface.projSpace  = projInterface_projSpace 
				if projInterface_useCage  != unsupplied do projInterface.useCage  = projInterface_useCage 
				if projInterface_rayOffset  != unsupplied do projInterface.rayOffset  = projInterface_rayOffset 
				if projInterface_hitResolveMode  != unsupplied do projInterface.hitResolveMode  = projInterface_hitResolveMode 
				if projInterface_hitMatchMtlID  != unsupplied do projInterface.hitMatchMtlID  = projInterface_hitMatchMtlID 
				if projInterface_hitWorkingModel  != unsupplied do projInterface.hitWorkingModel  = projInterface_hitWorkingModel 
				if projInterface_warnRayMiss  != unsupplied do projInterface.warnRayMiss  = projInterface_warnRayMiss 
				if projInterface_rayMissColor  != unsupplied do projInterface.rayMissColor  = projInterface_rayMissColor 
				if projInterface_normalSpace  != unsupplied do projInterface.normalSpace  = projInterface_normalSpace 
				if projInterface_tangentYDir  != unsupplied do projInterface.tangentYDir  = projInterface_tangentYDir 
				if projInterface_tangentXDir  != unsupplied do projInterface.tangentXDir  = projInterface_tangentXDir 
				if projInterface_heightMapMin  != unsupplied do projInterface.heightMapMin  = projInterface_heightMapMin 
				if projInterface_heightMapMax  != unsupplied do projInterface.heightMapMax  = projInterface_heightMapMax 
				if bakeInterface_bakeChannel != unsupplied do bakeInterface.bakeChannel = bakeInterface_bakeChannel
				if projInterface_subObjBakeChannel != unsupplied do projInterface.subObjBakeChannel = projInterface_subObjBakeChannel
				
				-- remove any bake elements
				local nBakeElements = bakeInterface.NumBakeElements()
				for nEle = nBakeElements to 1 by -1 do 
					bakeInterface.removeBakeElementByIndex nEle

				local render_class = classof renderers.current
				for ele_data in element_data do
				(
					local element
					if  (ele_data.class != unsupplied) and 
						(IsCompatibleWithRenderer ele_data.class render_class) and 
						(element = createInstance ele_data.class) != undefined do
					(
						if ele_data.enabled != unsupplied do element.enabled = ele_data.enabled
						if ele_data.elementName != unsupplied do element.elementName = ele_data.elementName
						if ele_data.filename != unsupplied do element.filename = ele_data.filename
						if ele_data.backgroundColor != unsupplied do element.backgroundColor = ele_data.backgroundColor
						if ele_data.autoSzOn != unsupplied do element.autoSzOn = ele_data.autoSzOn
						if ele_data.outputSzX != unsupplied do element.outputSzX = ele_data.outputSzX
						if ele_data.outputSzY != unsupplied do element.outputSzY = ele_data.outputSzY
						if ele_data.targetMapSlotName != unsupplied do element.targetMapSlotName = ele_data.targetMapSlotName

						bakeInterface.addBakeElement element

						if _debug do format "\tApplyObjectPreset - ele_data.ele_param_data: %\n" ele_data.ele_param_data
						for i = 1 to ele_data.ele_param_data.count do 
						(
							local param_name_val = ele_data.ele_param_data[i]
							local param_index = bakeInterface.findParam element param_name_val.name
							if _debug do format "\t\tApplyObjectPreset - param_name_val; param_index : %; %\n" param_name_val param_index
							if (param_index != 0) do
								bakeInterface.setParamValue element param_index param_name_val.value
						)
					)
					if _debug do format "\tApplyObjectPreset - ele_data.class, element: % : %\n" ele_data.class element
				)
			)
			
			ReadConfigData() -- update AutoFlatten options
			UpdateObjectSettings() -- update working object settings
			RefreshObjectsLV() -- update listview
			selectedElementProps.OnObjectSelectionChange() -- display elements for working object
			
			if _debug do format "done ApplyObjectPreset: %\n" filename
			return_value = true
		)
		else
		(
 			if _debug do format "cancelled ApplyObjectPreset: %\n" filename
		)
		return_value
	)

) -- end - rollout selectedObjectProps 

------------------------------------------------------------------
--
--	add bake elements popup dialog
--
rollout addElementsDialog "Add Texture Elements" 
	width:177 height:239
(
	local elementClasses -- List of all available bake element plug-ins
	local creatableElementClasses -- List of all available bake element plug-ins
	
	multiListBox mlAvailableElements "Available Elements"
		pos:[9,8] width:154 height:10 -- height is measured in Lines, not pixels
	button bCancel "Cancel" 
		pos:[102,201] width:52 height:24
	button bAddSelectedElements "Add Elements" 
		pos:[14,201] width:79 height:24
		
	on mlAvailableElements doubleClicked nClicked do
	(
		bAddSelectedElements.pressed()
	)
		
	-- prepare the class list
	on addElementsDialog open do
	(
		elementsName = #()
		creatableElementClasses = #()
	
		elementClasses = BakeElement.classes
		
		if (not allow_duplicate_elements) do
		(
			-- collect element classes being used by working objects
			local eleClassesPerNode = #()
			for obj in workingObjects do
			(
				local bakeInterface = obj.node.INodeBakeProperties
				local nBakeElements = bakeInterface.NumBakeElements()
				local eleClasses = for nEle = 1 to nBakeElements collect (classof (bakeInterface.GetBakeElement nEle))
				append eleClassesPerNode eleClasses
			)
			local commonEleClasses = CollectCommonElements eleClassesPerNode 
			
			-- strip ele classes used by all working objects from elementClasses 
			for eleClass in commonEleClasses do 
			(
				local i = findItem elementClasses eleClass 
				if i != 0 do deleteItem elementClasses i
			)
		)
		
		local rendererClass = (classof renderers.current)
		
		for i in elementClasses do
		(
			-- eliminate the standin
			if i.creatable and (IsCompatibleWithRenderer i rendererClass) then
			(
				tmpEle = i()
				append elementsName tmpEle.elementName
				append creatableElementClasses i
			)
		)
		mlAvailableElements.items = elementsName
		
		-- no selection to begin
		mlAvailableElements.selection = #{}
	)
	
	on addElementsDialog close do
	(
		pAddElementsPos = GetDialogPos addElementsDialog 
	)

	-- Cancel handler
	on bCancel pressed do
	(
		-- just destroy the dialog
		destroydialog addElementsDialog 
	)
	
	-- Add the elements to the bake properties
	on bAddSelectedElements pressed do
	(
		--format "add selected: % \n" mlAvailableElements.selection
		
		-- save current edited params
		selectedElementProps.CloseSelectedElement()	
		
		-- add the selected elements
		for i in mlAvailableElements.selection do
		(
			local elementClass = creatableElementClasses [i]
			-- create an instance of the elementClass and add it to the 
			-- node's bake properties for each object in the working objects
			--format "bake element: %\n" (creatableElementClasses [ i ]) 
			for obj in workingObjects do
			(
				local bakeInterface = obj.node.INodeBakeProperties
				-- check to see if we already have an instance of the bake element class. Can have only
				-- one per node.
				local found = false
				local nBakeElements = bakeInterface.NumBakeElements()
				if (not allow_duplicate_elements) do
				(
					for nEle = 1 to nBakeElements while not found do
						if classof (bakeInterface.GetBakeElement nEle) == elementClass do found = true
				)
				
				if not found do
				(
					tmpEle = elementClass() -- new instance for every object
					tmpEle.filename = RTT_methods.MakeBakeElementFileName obj.node tmpEle "" "" defaultFileType 
					-- set the elements targetMapSlotName with the default if that slot isn't already a target
					local targetMapSlotName = GetDefaultMtlMapSlotMapping (bakeElementStruct tmpEle obj.node)
					if (findItem obj.mapSlotNames targetMapSlotName) == 0 do targetMapSlotName = ""
					if targetMapSlotName != "" do
					(
						found = false
						for nEle = 1 to nBakeElements while not found do
						(
							local ele = bakeInterface.GetBakeElement nEle
							if (stricmp ele.targetMapSlotName targetMapSlotName) == 0 do 
							(	
								targetMapSlotName = ""
								found = true
							)
						)
					)
					tmpEle.targetMapSlotName = targetMapSlotName
					bakeInterface.addBakeElement tmpEle
					if not bakeInterface.bakeEnabled do
					(
						bakeInterface.bakeEnabled = true
						selectedObjectProps.cBakeEnable.checked = true
					)
				) -- end, not found
			)-- end, for each selected object
		) -- end, item /i in selection
	
		-- destroy the dialog
		destroydialog addElementsDialog 
		
	)-- end, addSelectedElements
) -- end - rollout addElementsDialog

------------------------------------------------------------------
--
--	Output (Element) Properties Rollout
--
rollout selectedElementProps "Output" width:328 height:381
(
	-- local functions
	local	EnableElementListGroup, EnableSelectedElementGroup, AddElementToList, UpdateElementSz, 
			UpdateElementName, UpdateElementTargetMapName, UpdateElementFileName,  
			UpdateElementList, CloseSelectedElement, UpdateAutoSize, UpdateSelectedElement, 
			OnObjectSelectionChange, CheckElementFileNames, CheckElementTargetMapNames,
			GetElementPropControls, GetElementPropControlVal, SetElementPropControlVal,
			MakeElementParams, SaveElementParams, EnableElementParams, ReadConfigData, WriteConfigData,
			setElementSize 

	local	elementPropControls
	local	elementPropCheckboxes -- will contain array of the boolParamX checkboxes
	local	elementPropIntSpinners -- will contain array of the intParamX integer spinners
	local	elementPropFloatSpinners -- will contain array of the floatParamX float spinners
	local	elementPropColorSwatches -- will contain array of the colorParamX color swatches
	local	elementPropColorSwatches_Indeterminates
	
	local elementBackgroundColorSwatch_Indeterminate
	
	local	maxNumElementParams = 9 -- max number of allowed Element parameters (constant). 
	local	commonTargetMapSlots = #() -- will contain an array of the target map slots common to the working nodes
	
	-- bake elements list 
	dotNetControl lvElements "Listview" height:118 width:330 align:#left offset:[-14,-5]
	button bAddElement "Add..." width:54 height:20 enabled:false across:2
	button bDeleteElement "Delete" width:54 height:20 enabled:false

		-- selected bake element's settings
	group "Selected Element Common Settings"
	(
	--	GroupBox gElementSettings "Selected Element Common Settings" width:318 height:131 enabled:false
		checkbox cElementEnable "Enable" enabled:false checked:true align:#left
		edittext eName "Name:" fieldwidth:180 enabled:false align:#right offset:[-17,-19]
		edittext eFilename "File Name and Type:" fieldwidth:180 enabled:false align:#right offset:[-17,0]
		button bFindFile "..." enabled:false align:#right width:20 height:17 offset:[6,-22]
		label l_targMapSlot "Target Map Slot: " enabled:false across:2 align:#left offset:[23,2] 
		dropdownlist dTargMapSlot "" width:183 align:#right offset:[-13,0]
		label lbl1 "Element Type: " enabled:false align:#right offset:[-46,-3] across:2
		label lbl_ElementType "" align:#left offset:[-42,-3]
		
		colorpicker csEleBackground "Element Background: " height:18 align:#left color:gray
		
			-- the size stuff
		checkbox cAutoSz "Use Automatic Map Size" enabled:false align:#left offset:[0,0]
		spinner sWidth "Width: " width:86 height:16 enabled:false range:[0,8192,256] type:#integer fieldwidth:40 align:#right across:4 offset:[10,0]
		button bxsmall  "" width:60 height:15 enabled:false align:#right offset:[15,0]
		button bmedium  "" width:60 height:15 enabled:false align:#right offset:[10,0]
		button bxlarge  "" width:60 height:15 enabled:false align:#right offset:[5,0]
		spinner sHeight "Height: " width:89 height:16 enabled:false range:[0,8192,256] type:#integer fieldwidth:40 align:#right across:4 offset:[10,0]
		button bsmall   "" width:60 height:15 enabled:false align:#right offset:[15,0]
		button blarge   "" width:60 height:15 enabled:false align:#right offset:[10,0]
		button bxxlarge "" width:60 height:15 enabled:false align:#right offset:[5,0] 
		checkbutton sizeLock "" images:#("LockButton_i.bmp", "LockButton_a.bmp", 1, 1, 1, 1, 1) align:#left width:16 height:16 offset:[87,-21] tooltip:"Lock height to width"
	)
	
	group "Selected Element Unique Settings"
	(
		checkbox boolParam1 "" visible:false align:#left offset:[0,-2] across:3
		checkbox boolParam4 "" visible:false align:#left offset:[0,-2]
		checkbox boolParam7 "" visible:false align:#left offset:[0,-2]
		checkbox boolParam2 "" visible:false align:#left offset:[0,-2] across:3
		checkbox boolParam5 "" visible:false align:#left offset:[0,-2]
		checkbox boolParam8 "" visible:false align:#left offset:[0,-2]
		checkbox boolParam3 "" visible:false align:#left offset:[0,-2] across:3
		checkbox boolParam6 "" visible:false align:#left offset:[0,-2]
		checkbox boolParam9 "" visible:false align:#left offset:[0,-2]

		colorpicker colorParam1 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-56] across:3
		colorpicker colorParam4 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-56]
		colorpicker colorParam7 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-56]
		colorpicker colorParam2 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-2] across:3
		colorpicker colorParam5 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-2]
		colorpicker colorParam8 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-2]
		colorpicker colorParam3 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-2] across:3
		colorpicker colorParam6 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-2]
		colorpicker colorParam9 "________" visible:false fieldwidth:15 height:15 align:#left offset:[-2,-2]
		
		spinner intParam1 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-55] across:3
		spinner intParam4 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-55]
		spinner intParam7 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-55]
		spinner intParam2 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-2] across:3
		spinner intParam5 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-2]
		spinner intParam8 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-2]
		spinner intParam3 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-2] across:3
		spinner intParam6 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-2]
		spinner intParam9 "________" visible:false type:#integer fieldwidth:34 align:#left offset:[-2,-2]
		
		spinner floatParam1 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-59] across:3
		spinner floatParam4 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-59]
		spinner floatParam7 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-59]
		spinner floatParam2 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-3] across:3
		spinner floatParam5 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-3]
		spinner floatParam8 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-3]
		spinner floatParam3 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-3] across:3
		spinner floatParam6 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-3]
		spinner floatParam9 "________" visible:false type:#float fieldwidth:34 align:#left offset:[-2,-3]			
	)
		
	------------------------------------------------------------------
	-- on open we need to initialize the listview & set things appropriately
	--
	on selectedElementProps open do
	(
		if _debug do format "in selectedElementProps.open - time:%\n" (timestamp())
		ReadConfigData()
		
		lvops.InitListView lvElements pInitColumns:#("File Name","Element Name","Size", "Target Map Slot") pInitColWidths:#(100,100,100,100) pHideHeaders:false pCheckBoxes:false -- init the active x list view
		lvElements.fullRowSelect = true
		lvElements.hideSelection = false
		lvElements.LabelEdit = false
		lvElements.multiselect = false
		lvElements.sorting = (dotnetclass "System.Windows.Forms.SortOrder").none
		lvops.RefreshListView lvElements
		--elementPropControls = #(cParam1,cParam2,cParam3,cParam4,cParam5,cParam6,cParam7,cParam8,cParam9)
		elementPropCheckboxes    = #( boolParam1,  boolParam2,  boolParam3,   boolParam4,  boolParam5,  boolParam6,   boolParam7,  boolParam8,  boolParam9 )
		elementPropIntSpinners   = #( intParam1,   intParam2,   intParam3,    intParam4,   intParam5,   intParam6,    intParam7,   intParam8,   intParam9 )
		elementPropFloatSpinners = #( floatParam1, floatParam2, floatParam3,  floatParam4, floatParam5, floatParam6,  floatParam7, floatParam8, floatParam9 )
		elementPropColorSwatches = #( colorParam1, colorParam2, colorParam3,  colorParam4, colorParam5, colorParam6,  colorParam7, colorParam8, colorParam9 )
		elementPropColorSwatches_Indeterminates = #{}
		elementPropColorSwatches_Indeterminates.count = 9
		
		elementPropControls = elementPropCheckboxes + elementPropIntSpinners + elementPropFloatSpinners + elementPropColorSwatches
		elementPropControls.visible = false
		elementPropControls.enabled = false
			
		local sizeButtons = #(bxsmall,bsmall,bmedium,blarge,bxlarge,bxxlarge)
		for i = 1 to sizeButtons.count do
		(
			local sx = (mapPresets[i].x as integer) as string
			local sy = (mapPresets[i].y as integer) as string
			sizeButtons[i].caption = sx + "x" + sy
		)
		
		selectedElementLVIndex = -1
		selectedElementIndex = 0
		commonElements = #()
		commonElementsTargIndet = #{}

		if _debug do format "exit selectedElementProps.open - time:%\n" (timestamp())
	)  --end, on open
	
	on selectedElementProps close do
	(
		writeConfigData()
	)  --end, on close
	
	-------------------------------------------------
	-- Add Element Button
	--
	on bAddElement pressed do
	(
		-- format "add elements\n"
		if workingObjects.count > 0 then
		(
			-- bring up dialog w/ class list of available elements
			-- which may add to the selected nodes elements
			local startCount = lvops.GetLvItemCount lvElements
			createDialog addElementsDialog modal:true pos:pAddElementsPos 
			
			-- add new elements to listbox
			-- format "update element list ...\n"
			UpdateElementList()
			
			-- select first of the new elements, if any
			if ((lvops.GetLvItemCount lvElements) > startCount) do
				-- IMPORTANT .NET arrays are zero based!
				UpdateSelectedElement (startCount)
					
			enableAccelerators = false
		) -- end, object selected
	)
	
	
	-------------------------------------------------
	-- Delete Element Button
	--
	on bDeleteElement pressed do
	(
		-- selection 0 is no selection
		-- IMPORTANT, .NET arrays are zero based
		if selectedElementIndex > 0 and 
			selectedElementIndex <= commonElements.count then 
		(
			-- for the selected element list...
			local elementList = commonElements[ selectedElementIndex ]
				
			-- format "remove elements: %\n" (elementList as string)
			-- for each element....
			for elem in elementList do
			(
				elem.node.RemoveBakeElement elem.element
			)
			
			-- update the list 
			UpdateElementList()
			
			-- update new selected element
			selectedElement = undefined 	-- we just deleted it from all selected objects
			
			UpdateSelectedElement (lvops.GetSelectedIndex lvElements) -- ok even if we deleted last item in list
					
			enableAccelerators = false
		) -- end, if selectedElementIndex  > 0
	) -- end, delete element button
	
	-- This event is called once an item is clicked
	function OnLvElementsClick =
	(
		--enableAccelerators = false
		local sel = lvops.GetSelectedIndex lvElements
		if sel != selectedElementLVIndex do
		(
			if _debug do format "LvElements click select: %; was: %\n" sel selectedElementLVIndex 
			--Close down the old element and update using a new one
			closeSelectedElement()
			updateSelectedElement sel	
		)		
	)
	on lvElements ItemSelectionChanged arg do
	(
		--arg is System.windows.forms.ListViewItemSelectionChangedEventArgs
		-- format "lvElements ItemSelectionChanged \n"
		if arg.isselected do
		OnLvElementsClick()
	)

	on lvElements mouseup arg do
	(
		local nItems = lvops.GetLvItemCount lvElements
		if nItems > 0 do
	(
			local sel = lvops.GetSelectedIndex lvElements
			if sel == -1 do
			(
				if selectedElementLVIndex >= nItems  do
					selectedElementLVIndex = 0
				lvops.SelectLvItem lvElements selectedElementLVIndex
	)
		)
	)

	-- This event is called when a header is clicked
	on lvElements ColumnClick arg do
	(
		--arg is System.Windows.Forms.ColumnClickEventHandler
		if ((lvops.GetLvItemCount lvElements) > 1) then
		(	
			lvElements.ListViewItemSorter = dotnetobject "MXS_dotNet.ListViewItemComparer" arg.column
			lvElements.ListViewItemSorter = undefined
		)
		--enableAccelerators = false
	)

	-------------------------------------------------
	-- On autoSized checked
	--
	on cAutoSz changed newState do
	(
		--	format "Set auto size: % \n" newState 
		enableSelectedElementGroup true
		UpdateAutoSize()
		if workingObjects.count == 1 then
			UpdateElementSz sWidth.value sHeight.value
		else
			UpdateElementSz undefined undefined
	)
	
	-------------------------------------------------
	-- On  element Enable checked
	--
	on cElementEnable changed _newState do
	(
		-- format "new: %, checked: % \n" (newState)(cElementEnable.checked)
		enableSelectedElementGroup true
	)

	-------------------------------------------------
	-- On find files button pressed
	--
	on bFindFile pressed do
	(
		-- format "find element file \n"
		local seed = eFileName.text
		if (getFilenamePath seed == "") then
		(
			-- no path, add default path
			seed = commonBakeProps.GetFilePath() + eFilename.text
		)
		
		-- this is the better way....allows setting extension specific params
		local f = selectSaveBitmap \
				caption:"Select Element File Name and Type" \
				filename:seed 
		
		if f != undefined then
		(								
			-- check for unique etc.
			f = CheckBakeElementFileName workingObjects[1].node selectedElement eName.text f (commonBakeProps.getFilePath())
			-- display it
			eFilename.text = f	
			UpdateElementFileName f
		)
	) -- end, on find files pressed


	-------------------------------------------------
	-- selected objects general properties
	--
	on sWidth changed newWidth do
	(
	--	format "Set Width: % \n" newWidth 
		if sizeLock.checked do sHeight.value = newWidth 
		UpdateElementSz newWidth sHeight.value
	)
	
	on sHeight changed newHeight do
	(
	--	format "Set Width: % \n" newHeight 
		if sizeLock.checked do sWidth.value = newHeight 
		UpdateElementSz sWidth.value newHeight 
	)
	
	on sizeLock changed state do
	(
		if state do 
		(
			sHeight.value = sWidth.value 
			UpdateElementSz sWidth.value sHeight.value 
		)
	)
	
	-------------------------------------------------
	-- element name changed
	--
	on eName entered newName do
	(
		if _debug do format "change element name: % \n" newName
		UpdateElementName newName
		if (selectedElement == undefined) or (workingObjects.count > 1) then
			return 0 -- dont update filename in this case
			
		saveName = selectedElement.elementName	-- save
		selectedElement.elementName = newName			-- replace
		newName = RTT_methods.MakeBakeElementFileName workingObjects[1].node selectedElement eFilename.text "" defaultFileType 
		selectedElement.elementName = saveName			-- restore
		if _debug do format "\tset filename: % \n" newName
		eFilename.text = newName
		UpdateElementFileName newName
	)
		
	-------------------------------------------------
	-- file name changed, see if it's an extension
	-- change or a name change
	--
	on eFileName entered newName do
	(
		-- eFileName enabled only if 1 node is selected
		f = CheckBakeElementFileName workingObjects[1].node selectedElement eName.text newName (commonBakeProps.getFilePath())
		eFilename.text = f	
		UpdateElementFileName f
	) -- end, on filename changed
	
	on dTargMapSlot selected val do
	(
		UpdateElementTargetMapName dTargMapSlot.selected
	)
	
	on csEleBackground changed _val do elementBackgroundColorSwatch_Indeterminate = false
	
	-- here's the size button handlers
	function setElementSize presetIndex =
	(
		sWidth.value = mapPresets[presetIndex].x
		sHeight.value = mapPresets[presetIndex].y
		cAutoSz.checked = false
		UpdateElementSz sWidth.value sHeight.value 
	)
	
	on bxsmall pressed do setElementSize 1
	on bsmall pressed do setElementSize 2
	on bmedium pressed do setElementSize 3
	on blarge pressed do setElementSize 4
	on bxlarge pressed do setElementSize 5
	on bxxlarge pressed do setElementSize 6

	on colorParam1 changed _val do elementPropColorSwatches_Indeterminates[1] = false
	on colorParam2 changed _val do elementPropColorSwatches_Indeterminates[2] = false
	on colorParam3 changed _val do elementPropColorSwatches_Indeterminates[3] = false
	on colorParam4 changed _val do elementPropColorSwatches_Indeterminates[4] = false
	on colorParam5 changed _val do elementPropColorSwatches_Indeterminates[5] = false
	on colorParam6 changed _val do elementPropColorSwatches_Indeterminates[6] = false
	on colorParam7 changed _val do elementPropColorSwatches_Indeterminates[7] = false
	on colorParam8 changed _val do elementPropColorSwatches_Indeterminates[8] = false
	on colorParam9 changed _val do elementPropColorSwatches_Indeterminates[9] = false

	-------------------------------------------------------
	-- functions to enable/disable groups of controls
	--
	-- the elementList group contains the list box & add & delete buttons
	function EnableElementListGroup _isEnabled _clearList =
	(
		if _debug do format "in selectedElementProps.EnableElementListGroup : group = %, clear = %\n" _isEnabled _clearList
		if _isEnabled == false then
			lvops.SelectLvItem lvElements 0
		bAddElement.enabled = _isEnabled
		if _clearList then
		(	-- empty the list 
			lvops.ClearLvItems lvElements
		)
	)
			
	-- enable UI elements in the selected elements group...
	function EnableSelectedElementGroup _isEnabled =
	(
		local enabled = _isEnabled
		cElementEnable.enabled = enabled 
		bDeleteElement.enabled = enabled 
		lbl1.enabled = enabled
		
		-- enable the rest based on enabled state for this element
		if allowControlDisable and cElementEnable.triState == 0 then
			enabled = false
			
		cAutoSz.enabled = enabled 
		eName.enabled = enabled 
		if not enabled do eName.text = ""

		l_targMapSlot.enabled = enabled 
		dTargMapSlot.enabled = enabled 
		csEleBackground.enabled = enabled
		
		if (workingObjects.count != 0) and ( selectedElement != undefined ) then
		(
			nParams = workingObjects[1].node.numElementParams selectedElement 
			EnableElementParams nParams enabled
		)
		
		--can't do filenames in multiple selections
		local fileEnable = enabled
		if workingObjects.count > 1 then
		 	fileEnable = false
			
		bFindFile.enabled = fileEnable 
		eFileName.enabled = fileEnable 
		if not fileEnable do eFileName.text = ""
	
		if cAutoSz.triState == 1 then
			enabled  = false				-- disable size controls on auto size
			
	 	sWidth.enabled = enabled 
	 	sHeight.enabled = enabled
		bxsmall.enabled = enabled 
		bsmall.enabled = enabled 
		bmedium.enabled = enabled 
		blarge.enabled = enabled 
		bxlarge.enabled = enabled 
		bxxlarge.enabled = enabled 
	)
	
	function AddElementToList _on _fileName _eleName _sx _sy _target _tag=
	(
		local size
			
		if _sx == undefined then size = "Varies" 
		else size = _sx as string + "x" + _sy as string
	
		lvops.AddLvItem lvElements pTextItems: #(_fileName,_eleName,size,_target) pChecked:_on pTag:_tag
	)
	
	function UpdateElementSz _sx _sy =
	(
		local size
			
		if _sx == undefined then size = "Varies" 
		else size = _sx as string + "x" + _sy as string
		
		if _debug do format "UpdateElementSz size: %\n" size
		
		lvops.SetLvItemName lvElements (lvops.GetSelectedIndex lvElements) 2 size
	)
	
	function UpdateElementName _eleName =
	(
		lvops.SetLvItemName lvElements (lvops.GetSelectedIndex lvElements) 1 _eleName
	)
	
	function UpdateElementFileName _fileName =
	(
		lvops.SetLvItemName lvElements (lvops.GetSelectedIndex lvElements) 0 _fileName
	)
	
	function UpdateElementTargetMapName _targetMapName =
	(
		lvops.SetLvItemName lvElements (lvops.GetSelectedIndex lvElements) 3 _targetMapName 
	)
	
	function UpdateElementList = 
	(
		if _debug do format "in selectedElementProps.UpdateElementList\n" 
		lvops.ClearLvItems lvElements
		selectedElementIndex = 0 -- reset selected element index, could end up with fewer elements
		
		commonElements = #()
		commonElementsTargIndet = #{}
		local rendererClass = (classof renderers.current)
		
		if workingObjects.count > 0 then
		(
			if workingObjects.count > 1 then
			(
				local elementNames = #()
				local elementLists = #()

				-- multiple objects, find common elements
				for obj in workingObjects do
				(
					local bakeInterface = obj.node.INodeBakeProperties
					local nEles = bakeInterface.NumBakeElements()
					if _debug do format "\tnode: %; # effects: %\n" obj.node.name nEles
					
					-- for each ele of this object
					for i = 1 to nEles do
					(
						 local element = bakeInterface.GetBakeElement i
						 local match = false
						
						if (IsCompatibleWithRenderer (classof element) rendererClass) do
						(
							-- compare to current list
							local notFound = true
							local eleName = element.elementName
							local eleClass = classof element
							for j = 1 to elementNames.count while notFound do
							(	if elementNames[j] == eleName do
								(	-- name match, make sure class is same
									if classof elementLists[j][1].element == eleClass then
									( 	-- match
										--format "match ele :   %  = % \n" (element.elementName)(element as string)
										append (elementLists[ j ]) (bakeElementStruct element obj.node) -- add the ele to the list
										notFound = false
									)
								)
							)
							if notFound do -- no match
							(
								--format "no match, add ele :   %  \n" (element.elementName)
								append elementNames (element.elementName)
								elementLists[ elementNames.count ] = #(bakeElementStruct element obj.node) -- new list containing just ele
 								-- format "eles for % :   %  \n" (element.elementName) (elementLists[ elementNames.count ])
							)
						)
						
					) --end, for each ele
				) -- end, for each object
					
				
				local grayColor = ((colorman.getColor #shadow)*255) as color
				grayColor = (color grayColor.b grayColor.g grayColor.r) -- this is the BGR thing...
				-- for each possible element	
				for i = 1 to elementNames.count do
				(
					local eleList = elementLists[ i ]	-- get ele's behind the common name
					
					-- for now, only common-to-all elements are shown
					if (not showCommonElementsOnly) or (eleList.count == workingObjects.count) then	
					(
						local isOn = triStateValue()
						local szX = triStateValue()
						local szY = triStateValue()
						local target = triStateValue()
						
						for e in eleList do
						(
							local ele = e.element
							isOn.setVal ele.enabled
							szX.setVal ele.outputSzX
							szY.setVal ele.outputSzY
							target.setVal ele.targetMapSlotName 
						)
						
						-- add bake element to listbox
						local index = lvops.GetLvItemCount lvElements
						index += 1
						commonElementsTargIndet[i]= target.indeterminate and target.defined
						target = if target.indeterminate then (if target.defined then "varies" else "" )
								 else target.value
						addElementToList isOn.value "" elementNames[i] szX.value szY.value target index
						if (not showCommonElementsOnly) and (eleList.count != workingObjects.count) do
						(
							lvops.SetLvItemRowColor lvElements index grayColor
						)
						
						-- copy the common elements behind the name
						commonElements[ index ] = eleList
						-- format "common elements[ % ] = % \n" (lvElements.Items.item.count)(eleList)
						
					) --end, ele is common to all objects 
				) -- end, for each bake element
				
			) -- end, multiple selection
			else 
			(
	--->>>>>>	-- single object
				local obj = workingObjects[1].node
				local bakeInterface = obj.INodeBakeProperties
				local nElems = bakeInterface.NumBakeElements()
				if _debug do format "\tnode: %; # effects: %\n" obj.name nElems
				local index = 0
				for i = 1 to nElems do
				(
					-- add bake element to listbox
					local element = bakeInterface.GetBakeElement i
					
					if (IsCompatibleWithRenderer (classof element) rendererClass) do
					(
						-- add bake element to listbox
						local isOn = if element.enabled then 1 else 0
						index += 1
						addElementToList isOn element.fileName element.elementName element.outputSzX element.outputSzY element.targetMapSlotName index
					
						-- copy the common elements to the common element lists
						append commonElements #(bakeElementStruct element obj)
					)
				
					-- format "common elements[ % ] = % \n" commonElements.count commonElements[i]
				) -- end, for each bake element
			)-- end, single selection
				
		) -- end, some object selected
 
		-- reset the selection since we trashed the old element selection
		if _debug do format "\tcommonElementsTargIndet: %\n" commonElementsTargIndet 
		if _debug do format "\tcommonElements: %\n" commonElements
		
		lvops.SelectLvItem lvElements 0
		lvops.RefreshListView lvElements
		--lvElements.Refresh()		
	) -- end, update element list	

	-------------------------------------------------------
	-- function to close an element & update things in the
	-- element itself...not done on cancel
	-- called when switching elements in the list box &
	-- on Close for the last element
	-- NB: switching elements writes the changes with
	-- no cancel& no undo ...
	function CloseSelectedElement =
	(
		if _debug do format "Close Element\n"  
		if _debug do format "close selected elements - selectedElement: %; selectedElementIndex: %; commonElements: %\n" selectedElement selectedElementIndex commonElements
		
		if selectedElementIndex > 0 and 
			selectedElementIndex <= commonElements.count then 
		(
			-- write to all objects
			local eleList = commonElements[ selectedElementIndex ]
			for e in eleList where isValidNode e.node do
			(
				local ele = e.element
				if _debug do format "Close Element: % \n" e -- eName.text 
				if _debug do format "ele.elementName: %; eName.text: %\n" ele.elementName eName.text 
				if( ele.elementName != eName.text ) then
				(
					if _debug do format "workingObjects.count: %\n" workingObjects.count
					ele.elementName = eName.text

					if (workingObjects.count > 1) then
					(	
						-- eFileName not enabled in this case. 
						-- regenerate filename, if unique returns same w/ possible frame#
						if _debug do format "e.node: %; ele: %; ele.fileName: %; defaultFileType: %\n" e.node ele ele.fileName defaultFileType 
						ele.fileName = RTT_methods.MakeBakeElementFileName e.node ele ele.fileName "" defaultFileType 
					)
					else
					(
						if _debug do format "eFileName.text: %\n" eFileName.text
						ele.fileName = eFileName.text
					)
				)
				else
				(
					if _debug do format "workingObjects.count: %\n" workingObjects.count
					if (workingObjects.count == 1) then
					(
						if _debug do format "eFileName.text: %\n" eFileName.text
						ele.fileName = eFileName.text
					)
				)

				-- don't write indeterminates!!
				if _debug do format "cElementEnable.triState: %; cElementEnable.checked:%\n" cElementEnable.triState cElementEnable.checked
				if ( cElementEnable.triState != 2 ) then
					ele.enabled = cElementEnable.checked
				
				if _debug do format "elementBackgroundColorSwatch_Indeterminate: %; csEleBackground.color:%\n" elementBackgroundColorSwatch_Indeterminate csEleBackground.color
				if ( not elementBackgroundColorSwatch_Indeterminate) then
					ele.backgroundColor = csEleBackground.color
				
				if _debug do format "cAutoSz.triState: %; cAutoSz.checked:%\n" cAutoSz.triState cAutoSz.checked
				if ( cAutoSz.triState != 2 ) then
				(
					ele.autoSzOn = cAutoSz.checked 
					if _debug do format "sWidth.indeterminate: %; sWidth.value:%\n" sWidth.indeterminate sWidth.value
					if _debug do format "sHeight.indeterminate: %; sHeight.value:%\n" sHeight.indeterminate sHeight.value
					if ( not sWidth.indeterminate  ) then
						ele.outputSzX = sWidth.value
					if ( not sHeight.indeterminate  ) then
						ele.outputSzY = sHeight.value
				)
				
				if _debug do format "\t% : % : %\n" dTargMapSlot.enabled commonElementsTargIndet[selectedElementIndex] dTargMapSlot.selection
				
				if dTargMapSlot.selection != 0 and dTargMapSlot.enabled and not (commonElementsTargIndet[selectedElementIndex] and dTargMapSlot.selection == 1) then 
				(
					ele.targetMapSlotName = dTargMapSlot.selected
				)
				if dTargMapSlot.selection != 0 and dTargMapSlot.enabled and dTargMapSlot.selection != 1 and not (commonElementsTargIndet[selectedElementIndex] and dTargMapSlot.selection == 2) then 
				(
					UpdateDefaultMtlMapSlotMapping e
				)
				
				-- save the optional params
				saveElementParams e
					
			) -- end, for each element
		) -- end, have selected element(s)
		
	) -- end, close selected element
	
	-------------------------------------------------------
	-- update the automatic element raster size 
	-- 
	function UpdateAutoSize =
	(
		--format "Update Auto Size, triState = % \n" ( cAutoSz.triState )
		if cAutoSz.triState == 1 then 	-- only "on", not for off or confused
		(
			--format "On Objects = %\n" workingObjects
			for curObj in workingObjects do
			(
				local _obj = curObj.node
				local objClass = classof _obj
				local objSuperClass = superclassof _obj
				local baseObj = _obj.baseobject
				local baseObjClass = classof baseObj
				local tmpObj
				if (baseObjClass == XRefObject and (tmpObj = baseObj.actualBaseObject) != undefined) do
					baseObj = tmpObj
				local baseObjSuperClass = superclassof baseObj
				local isRenderableShape = (objSuperClass == shape) and (baseObjSuperClass == shape) and 
										  (hasProperty baseObj #renderable) and (hasProperty baseObj #displayRenderMesh) and
										  baseObj.renderable
				local needRenderMesh = isRenderableShape and not baseObj.displayRenderMesh
				local myMesh = snapshotAsMesh _obj renderMesh:needRenderMesh
				
				-- get the size from the mesh area
				local area = meshop.getFaceArea myMesh #all
				local nPix = 100 * (sqrt area) * autoUnwrapMappingProps.sSizeScale.value 
				--format "Update size on object = % to size = % \n" (curObj as string) nPix
				
				-- powers of 2?
				if autoUnwrapMappingProps.cSizePowersOf2.checked then 
				(
					-- modify size to closest power of 2
					local nPower = 0
					local n = nPix
					while n >= 2 do
					(
						n /= 2
						nPower += 1
					)
					-- nPix is between 2 to nPower & 2 to nPower+1, which is closer?
					if (nPix - 2 ^ nPower) <= (2 ^ (nPower+1) - nPix) then
						nPix = 2 ^ nPower
					else
						nPix = 2 ^ (nPower + 1)
				
				) -- end, power of 2
				
				-- bound it
				if nPix < autoUnwrapMappingProps.sSizeMin.value then
					nPix = autoUnwrapMappingProps.sSizeMin.value 
				if nPix > autoUnwrapMappingProps.sSizeMax.value then
					nPix = autoUnwrapMappingProps.sSizeMax.value 
					
				if( workingObjects.count > 1 ) and ( selectedElementIndex > 0 ) then
				(
					-- multiple selection, write to the object, no cancel
					local eleList = commonElements[selectedElementIndex]
					for e in eleList where (e.node == _obj) do
					(
						local ele = e.element
						--format "Close Element: % sz:  % \n" (ele)( nPix )
						ele.autoSzOn = true 
					
						ele.outputSzX = ele.outputSzY = nPix
						--format "size set to % \n" (ele.outputSzX)
					)
					-- update the list box
					UpdateElementSz undefined undefined
				) 
				else 
				(
				 	-- single selection, just put in the spinners so cancel will work
					sWidth.value = sHeight.value = nPix
					-- update the list box
					UpdateElementSz sWidth.value sHeight.value
				)
				delete myMesh
				
			) -- end, for each object
			
			sWidth.indeterminate = sHeight.indeterminate = (workingObjects.count > 1)
			
		) -- end, autosize on	
	)

	-------------------------------------------------------
	-- update things when a new element in the bakeElement 
	-- list is selected. _newSelection is an integer list view index
	function UpdateSelectedElement _newSelection =
	(
		if _debug do format "in selectedElementProps.UpdateSelectedElement _newSelection: % <%>\n" _newSelection (classof _newSelection)
		
		local name, fName, isAutoSz, szX, szY, target, allTargetsForSelection, elementBackgroundColor
		local isOn = triStateValue()
		
		lbl_ElementType.caption = ""
		-- update the element params & enable
		if (_newSelection == -1) or (workingObjects.count == 0) or ((lvops.GetLvItemCount lvElements) == 0) then
		(
			-- format "unselected element : %\n" (selectedElement as string)				
			-- nothing selected, disable all but delete button
			enableSelectedElementGroup false
			
			csEleBackground.color = gray
				
			selectedElement = undefined
			selectedElementIndex = 0
			-- IMPORTANT, .NET arrays are zero based
			selectedElementLVIndex = -1
		)
		else 
		(
			-- an item of the listview is selected, update & enable
			-- update the selected element display
			if _debug do format "\tupdate selected element to: % , # % \n" (lvops.GetLvItemName lvElements _newSelection 1) _newSelection
			-- init the state vars
			elementBackgroundColor = triStateValue()
			isAutoSz = triStateValue()
			szX = triStateValue()
			szY = triStateValue()
			target = triStateValue()
			allTargetsForSelection = #()
			
			-- IMPORTANT, .NET arrays are zero based
			if _newSelection > (lvElements.Items.count) then 
				_newSelection = (lvElements.Items.count - 1)

			-- some object is selected, multiple?
			if (workingObjects.count > 1) then
			(
				-- multiple selection
				selectedElement = undefined
				selectedElementLVIndex = _newSelection

				selectedElementIndex = lvElements.Items.item[selectedElementLVIndex].tag
	
				fName = "" -- no filename for multi selections 
				name = lvops.GetLvItemName lvElements _newSelection 1

				-- see which params are in-common & which are not
				local eleList = commonElements[ selectedElementIndex ]
				for e in eleList do
				(
					local ele = e.element
					isOn.setVal ele.enabled
					elementBackgroundColor.setVal ele.backgroundColor
					isAutoSz.setVal ele.autoSzOn
					szX.setVal ele.outputSzX
					szY.setVal ele.outputSzY 
					local target_name = ele.targetMapSlotName 
					target.setVal target_name
					if findItem allTargetsForSelection target_name == 0 do 
						append allTargetsForSelection target_name 
				) -- end, e is defined
				
				-- format"multi ele: %; isOn = %\n" name isOn.value
			) -- end, multiple selection
			else 
			(
				-- single object selected
				selectedElementLVIndex = _newSelection

				if _debug do (format "\tlvElements.Items.count: %\n" lvElements.Items.count )
				selectedElementIndex = lvElements.Items.item[selectedElementLVIndex].tag
				selectedElement = commonElements[ selectedElementIndex ][1].element

				elementBackgroundColor.setVal selectedElement.backgroundColor
				isOn.setVal selectedElement.enabled
				isAutoSz.setVal selectedElement.autoSzOn
				szX.setVal selectedElement.outputSzX
				szY.setVal selectedElement.outputSzY 
				local target_name = selectedElement.targetMapSlotName 
				target.setVal target_name 
				name = selectedElement.elementName
				fName = selectedElement.fileName
				allTargetsForSelection[1] = target_name

				-- format"single ele: %; isOn = %\n" name isOn.value
			) -- end, else single selection		
		) -- end, list box item selected
			
		-- see if anything's been set up
		if isOn.defined then
		(
			-- update the dialog box UI
			-- do these before the group enable
			cElementEnable.triState = isOn.asTriState()
			cAutoSz.triState = isAutoSz.asTriState()
			enableSelectedElementGroup true 
			
			elementBackgroundColorSwatch_Indeterminate = elementBackgroundColor.indeterminate
			csEleBackground.color = elementBackgroundColor.first_value
			
			szX.spinnerSet sWidth 
			szY.spinnerSet sHeight
			
			eName.text = name
			eFileName.text = fName

			-- make a list of all the map slot names in use by working objects other than those in 
			-- selected elements
			local usedMapSlots = #()
			local selectedElements = commonElements[ selectedElementIndex ]
			for eleList in commonElements where (eleList != selectedElements ) do
			(	for e in eleList do
				(
					local target_name = e.element.targetMapSlotName 
					if findItem usedMapSlots target_name == 0 do 
						append usedMapSlots target_name 
				) -- end, e 
			) -- end, eleList
			
			-- make a copy of the common map slots names
			local targetMapSlots = copy commonTargetMapSlots #nomap
			-- remove from list of common map slots names the names already in use other than by selected elements
			local index
			for target_name in usedMapSlots do
				if (index = findItem targetMapSlots target_name) != 0 do
					deleteItem targetMapSlots index 
			
			targetMapSlots = join #(" ") targetMapSlots
			if target.indeterminate do targetMapSlots = join #("varies") targetMapSlots 
			dTargMapSlot.items = targetMapSlots 
			if target.value == "" do target.value = " "
			if _debug do format "dTargMapSlot set: %\n" dTargMapSlot.items 
			if target.indeterminate then
			(
				dTargMapSlot.selection = 1
			)
			else
			(
				dTargMapSlot.selection = findItem targetMapSlots target.value
				if _debug do format "dTargMapSlot: % : % : %\n" dTargMapSlot.selection target.value targetMapSlots 
			)
			lbl_ElementType.caption = (classof selectedElements[1].element) as string
				
		) -- end, isOn not undefined
		
		-- put up the unique element params if any, clears old display
		makeElementParams()
		
		lvops.SelectLvItem lvElements selectedElementLVIndex
		
	) -- end, update selected element
		

	function CheckElementFileNames =
	(
		for obj_i in workingObjects do
		(	local obj = obj_i.node
			local bakeInterface = obj.INodeBakeProperties
			local nEles = bakeInterface.NumBakeElements()
					
			-- for each ele of this object
			for i = 1 to nEles do
			(
				local element = bakeInterface.GetBakeElement i
				local newName = RTT_methods.MakeBakeElementFileName obj element element.fileName "" defaultFileType 
				if (element.fileName != newName) do
				(
					if _debug do format "\tupdating element filename: node: %; element: %; old: %; new: %\n" obj.name element.elementName element.filename newname
					element.fileName = newName
				)
			)
		)
	)

	function CheckElementTargetMapNames =
	(
		for obj_i in workingObjects do
		(	local obj = obj_i.node
			local bakeInterface = obj.INodeBakeProperties
			local nEles = bakeInterface.NumBakeElements()
			local nodeTargMapNames = obj_i.mapSlotNames
					
			-- for each ele of this object
			for i = 1 to nEles do
			(
				local element = bakeInterface.GetBakeElement i
				local targMapName = element.targetMapSlotName
				if targMapName != "" and targMapName != " " and (findItem nodeTargMapNames targMapName) == 0 do 
				(
					if _debug do format "\tupdating element targetMapSlotName: node: %; element: %; old: %\n" obj.name element.elementName element.targetMapSlotName
					targMapName = element.targetMapSlotName = ""
				)
				
				if targMapName == "" and autoUpdateTargetMapSlotName do
				(
					local autoName = GetDefaultMtlMapSlotMapping (bakeElementStruct element obj)
					if (findItem nodeTargMapNames targMapName) == 0 then
						element.targetMapSlotName = ""
					else
						element.targetMapSlotName = autoName
				)
			)
		)
	)

	-----------------------------------------------------------------
	--
	--	Function to update Output rollout on a change in object selection
	--
	function OnObjectSelectionChange = 
	(
		if _debug do format "in selectedElementProps.OnObjectSelectionChange - workingObjects.count:%\n" workingObjects.count
		if workingObjects.count > 0 then
		(
			CheckElementFileNames()
			CheckElementTargetMapNames()
			UpdateElementList()
			-- IMPORTANT, .NET arrays are zero based
			local lvItemCount = lvops.GetLvItemCount lvElements
			if (lvItemCount == 0) then
				selectedElementLVIndex = -1
			else
			(
				selectedElementLVIndex = if selectedElementLVIndex > lvItemCount then (lvItemCount - 1)
										 else (lvops.GetSelectedIndex lvElements)
			)
			
			local targetMapNameList = for wo in workingObjects collect wo.mapSlotNames
			commonTargetMapSlots = CollectCommonElements targetMapNameList 
			if _debug do format "commonTargetMapSlots: %\n" commonTargetMapSlots 

			EnableElementListGroup true false
		)
		else 
		(
			-- count is 0. no object selection
			selectedElementLVIndex = -1
			-- disable list group & clear it
			EnableElementListGroup false true
		)-- end, no object selection
		
		-- update the selected element section in all cases
		UpdateSelectedElement selectedElementLVIndex 
		
		-- >>>>>>>>>
		if workingObjects.count > 0 then
			UpdateAutoSize()
	) -- end, update object selection


	-----------------------------------------------------------------------------------
	--
	--	get the array of UI control appropriate to the given param type
	--
	function GetElementPropControls _paramType =
	(
		case _paramType of
		(
			1: elementPropCheckboxes
			2: elementPropIntSpinners
			3: elementPropFloatSpinners
			4: elementPropColorSwatches
			default: #()
		)
	)
	

	-----------------------------------------------------------------------------------
	--
	--	get the UI control value appropriate to the given param type; undefined if indeterminate
	--
	function GetElementPropControlVal _paramType _index =
	(
		local _control = (GetElementPropControls _paramType)[_index]
		case _paramType of (
			1:	if _control.tristate==2   then undefined	else _control.tristate
			2:	if _control.indeterminate then undefined	else _control.value
			3:	if _control.indeterminate then undefined	else _control.value
			4:	if elementPropColorSwatches_Indeterminates[_index] then undefined
				else _control.color
		)
	)


	-----------------------------------------------------------------------------------
	--
	--	set the UI control value appropriate to the given param type; undefined for indeterminate
	--
	function SetElementPropControlVal _paramType _index _val =
	(
		local _control = (GetElementPropControls _paramType)[_index]
		case _paramType of (
			1: if _val == undefined then _control.tristate=2 else _control.state = _val
			2: if _val == undefined then _control.indeterminate=true else _control.value = _val
			3: if _val == undefined then _control.indeterminate=true else _control.value = _val
			4: (
					if _val == undefined then
						_control.color = black
					else _control.color = _val
					elementPropColorSwatches_Indeterminates[_index] = (_val==undefined)				
				)
		)		
	)	


	-----------------------------------------------------------------------------------
	--
	--	set up the element parameter checkboxes
	--
	function MakeElementParams =
	(
		if _debug do format "makeElementParams - selectedElementIndex: %\n" selectedElementIndex 

		elementPropControls.enabled = false
		elementPropControls.visible = false
		
		if selectedElementIndex > 0 do 
		(
			-- get num params from any of the elements
			local eleList = commonElements[ selectedElementIndex ]
			local ele = eleList[1]	-- any of the eles is ok, just used to get nparams
			local element = ele.element
			
			local bakeInterface = ele.node.INodeBakeProperties
			local nParams = bakeInterface.numElementParams element
			if ( nParams > 0 ) and ( nParams <= maxNumElementParams ) then
		 	(
				-- collect state on params
				local params = #()
				for i = 1 to nParams do params[i] = triStateValue()
				
				for e in eleList do
				(
					bakeInterface = e.node.INodeBakeProperties
					for i = 1 to nParams do
					(
						local type  = bakeInterface.paramType e.element i
						local val  = bakeInterface.paramValue e.element i
						if (type==1) and ((classOf val) != BooleanClass) do
							val = (val>0) --force integer to boolean
						params[i].setVal val
						
					) -- end, for each param
				) -- end, for each element
				
				--format "make % element param rollup \n" nParams
				for i = 1 to nParams do
				(
					--Set the range of the control, for spinners
					local type = bakeInterface.paramType element i
					local cb = (GetElementPropControls type)[i]
					if (type==2) or (type==3) do
					(
						local rangeMin = bakeInterface.paramValueMin element i
						local rangeMax = bakeInterface.paramValueMax element i
						cb.range = [rangeMin,rangeMax,rangeMin]
					)
					
					--Set the control value according to the param value, possibly indeterminate
					if params[i].indeterminate  then
						 SetElementPropControlVal type i undefined
					else SetElementPropControlVal type i params[i].value

					--Set the name & visibility of the control					
					cb.caption = bakeInterface.paramName element i
					cb.enabled = true
					cb.visible = true
				)
			) -- end if( nParams > 0 ) and ( nParams <= maxNumElementParams )
		) -- end if selectedElementIndex > 0 
	) -- end function MakeElementParams 
	
	
	-----------------------------------------------------------------------------------
	--
	--	save the variable params. Passed in a bakeElementStruct 
	--
	function SaveElementParams _element = 
	(
		local bakeInterface = _element.node.INodeBakeProperties
		local ele = _element.element
		--	format "save % w/ nParams = %\n"  ele.elementName ( bakeInterface.numElementParams ele )
		local nParams = bakeInterface.numElementParams ele
		for i = 1 to nParams do
		(
			local type = bakeInterface.paramType ele i
			local val = GetElementPropControlVal type i
			if val != undefined do -- only write un-confused values
				bakeInterface.setParamValue ele i val
		)
	) -- end, save element params
	
	
	-----------------------------------------------------------------------------------
	--
	--	enable the variable param rollup
	--
	function EnableElementParams _nParams _enable =
	(
		--format "enable % unique params to %\n" _nParams _enable
		for i = 1 to _nParams do
			elementPropControls[i].enabled = _enable
	) -- end, enable element params
	
	function ReadConfigData =
	(
		cAutoSz.checked = 	RTT_data.OutputMapSize_AutoMapSize
		sWidth.value = 		RTT_data.OutputMapSize_Width
		sHeight.value = 	RTT_data.OutputMapSize_Height
	) -- end fn ReadConfigData 
	
	function WriteConfigData =
	(
		RTT_data.OutputMapSize_AutoMapSize = cAutoSz.checked 
	 	RTT_data.OutputMapSize_Width = sWidth.value
	 	RTT_data.OutputMapSize_Height = sHeight.value
	) -- end fn WriteConfigData 

) -- end, selected element props

rollout bakedMtlProps "Baked Material"
(
	-- local functions
	local ReadConfigData, WriteConfigData
	local availBakedMtTypes -- contain RTT_MlTypes struct instances
	local lastNewBakedType_index
	
	group "Baked Material Settings"
	(
		radiobuttons rbDestination labels:#("Output Into Source","Save Source (Create Shell)") offset:[-5,-3] align:#left  columns:1
		radiobuttons rbShellOption labels:#("Duplicate Source to Baked","Create New Baked") align:#left offset:[10,-3] columns:1
		dropdownlist dNewBakedType "" enabled:true width:275 align:#left offset:[28,-3]
	)
	button bUpdateMtls "Update Baked Materials" across:2
	button bClearShellMtls "Clear Shell Materials"
	checkbox cbRenderToFilesOnly "Render to Files Only" across:2
	radiobuttons rbKeepWhich labels:#("Keep Source Materials","Keep Baked Materials") offset:[22,0] align:#left columns:1
	
	on cbRenderToFilesOnly changed state do
	(
		RTT_data.Materials_RenderToFilesOnly = state 
		WriteSceneData()
		
		-- don't disable. Target Map Slots depend on these settings, so need to change even
		-- if not immediately baking to mtl.
		-- rbDestination.enabled = not state
		-- rbShellOption.enabled = (not state) and rbDestination.state == 2
	)
	on rbDestination changed state do
	(
		rbShellOption.enabled = (state == 2)
		if (rbShellOption.state == 2) then -- this results in change in available target map slot names
		(
			selectedElementProps.CloseSelectedElement() -- accept changes on working elements
			for wo in workingObjects do 
				wo.mapSlotNames = CollectTargetMapNamesForNode wo.node
			selectedElementProps.OnObjectSelectionChange()
			dNewBakedType.enabled = (state == 2)
		)
		else
			dNewBakedType.enabled = false
	)
	on rbShellOption changed state do
	(
		-- this results in change in available target map slot names
		selectedElementProps.CloseSelectedElement() -- accept changes on working elements
		for wo in workingObjects do 
			wo.mapSlotNames = CollectTargetMapNamesForNode wo.node
		selectedElementProps.OnObjectSelectionChange()
		dNewBakedType.enabled = (state == 2)
	)
	on dNewBakedType selected index do
	(
		-- this results in change in available target map slot names
		selectedElementProps.CloseSelectedElement() -- accept changes on working elements
		newBakedMtlInstance = availBakedMtTypes[index].instance
		newBakedMtlTargetMapNames = CollectTargetMapNamesForMtl newBakedMtlInstance
		if _debug do format "newBakedMtlTargetMapNames: %\n" newBakedMtlTargetMapNames 
		for wo in workingObjects do 
			wo.mapSlotNames = CollectTargetMapNamesForNode wo.node
		selectedElementProps.OnObjectSelectionChange()
		lastNewBakedType_index = index
	)
	on bUpdateMtls pressed do
	(
		local old_autoBackup_enabled = autoBackup.enabled
		autoBackup.enabled = false
		try
			selectedObjectProps.CloseWorkingObjects()  -- capture changes
		catch
		(
			autoBackup.enabled = old_autoBackup_enabled
			throw
		)
		ignoreMtlUpdates = true	
		try
			UpdateBakedMtls workingObjects
		catch
		(
			ignoreMtlUpdates = false
			autoBackup.enabled = old_autoBackup_enabled
			throw
		)
		ignoreMtlUpdates = false
		autoBackup.enabled = old_autoBackup_enabled
	)
	on bClearShellMtls pressed do
	(
		local old_autoBackup_enabled = autoBackup.enabled
		autoBackup.enabled = false
		ignoreMtlUpdates = true	
		try
			RemoveBakeMaterials rbKeepWhich.state
		catch
		(
			ignoreMtlUpdates = false
			autoBackup.enabled = old_autoBackup_enabled
			throw
		)
		ignoreMtlUpdates = false
		autoBackup.enabled = old_autoBackup_enabled
	)
	on bakedMtlProps open do
	(
		if _debug do format "in bakedMtlProps open - time:%\n" (timestamp())
		ReadConfigData()
		cbRenderToFilesOnly.enabled =(not commonBakeProps.cNetworkRender.checked) -- disable if network render chosen
		availBakedMtTypes = CollectMtlTypes()
		local availBakedMtTypeNames = for m in availBakedMtTypes collect m.name
		dNewBakedType.items = availBakedMtTypeNames
		local i = 1
		local notFound = true
		for j = 1 to availBakedMtTypes.count while notFound do
			if classof availBakedMtTypes[j].instance == StandardMaterial and ((availBakedMtTypes[j].instance.shaderByName as name) == defaultMtlShader) do
			(	i = j
				notFound = false
			)
		dNewBakedType.selection = i
		rbShellOption.enabled = (rbDestination.state == 2)
		dNewBakedType.enabled = (rbShellOption.state == 2) and (rbDestination.state == 2)
		newBakedMtlInstance = availBakedMtTypes[i].instance
		lastNewBakedType_index = index
		newBakedMtlTargetMapNames = CollectTargetMapNamesForMtl newBakedMtlInstance
		if _debug do format "newBakedMtlTargetMapNames: %\n" newBakedMtlTargetMapNames 
		if _debug do format "exit bakedMtlProps open - time:%\n" (timestamp())
	)
	on bakedMtlProps close do
	(
		WriteConfigData()
	)
	
	function ReadConfigData =
	(
		cbRenderToFilesOnly.checked = 	RTT_data.Materials_RenderToFilesOnly
		rbDestination.state = 			RTT_data.Materials_MapDestination
		rbShellOption.state = 			RTT_data.Materials_DuplicateSourceOrCreateNew
	)

	function WriteConfigData =
	(
		RTT_data.Materials_MapDestination = rbDestination.state
		RTT_data.Materials_DuplicateSourceOrCreateNew = rbShellOption.state
	)
	
) -- end - rollout bakedMtlProps

rollout projectionOptionsProps "Projection Options"
(
	local UpdateObjectSettings -- function to update dialog based on the workingObjects
	local UpdateFilterSettings -- function to update dialog based on the renderer
	local RendererPropChanged -- renderer property changed callback function
	local RendererChanged -- renderer changed callback function
	local SelectionChanged -- selection changed callback function
	local ModifierChanged -- modifier changed callback function
	local SetProjProp -- function to update node INodeBakeProjProperties property
	local UpdateSourceName -- function to update display of selected source
	local UpdateHeightBufferDisplay -- function to update height buffer display
	local UpdateOrientation -- function to update orientation labels based on normal space changes
	local HeightPick -- function to pick values for the height map spinners
	local _debug = false
	local projSpace_enums = #(#raytrace,#uvw_match)
	local normalSpace_enums = #(#world,#screen,#local,#tangent)
	local tangentYDir_enums = #(#Y_Down,#Y_Up)
	local tangentXDir_enums = #(#X_Left,#X_Right)
	local rbNormalXDir, rbNormalYDir
	local hitResolveMode_enums = #(#closest,#furthest)
	local disp_bump_src_enums = #(#workingModel,#refModel)
	local rayMissColor_indeterminate = false
	local rendererCB -- renderer 'when' callback
	local heightPickVal -- current value beight picked with HeightPick

	group "Objects and Sources"
	(
		editText etSource fieldwidth:260 across:2 align:#left offset:[-4,2] readOnly:true
		button bSynchAll "Synch All" align:#right offset:[2,0]
	)
	group "Filtering Options"
	(
		checkbox cbCropAlpha "Crop Alpha" align:#left across:3
		label l_samplerType "??" align:#right offset:[60,1]
		button bSamplerSetup "Setup..." align:#right offset:[2,-3] width:45
	)
	group "Method"
	(
		radiobuttons rbProjSpace labels:#("Raytrace","UV Match") columns:2 align:#left across:3
		checkbox cbUseCage "Use Cage" align:#left offset:[40,0]
		spinner sOffset "Offset:" fieldwidth:60 align:#right type:#worldUnits range:[0,1e9,0]
	)
	group "Resolve Hit"
	(
		radiobuttons rbResolveHit labels:#("Closest    ","Furthest") columns:2 align:#left 
		checkbox cbHitMatchMtlID "Hit Only Matching Material ID" align:#left across:2
		checkbox cbRayMissCheck "Ray miss check" align:#right offset:[6,0]
		checkbox cbHitWorkingModel "Include Working Model" align:#left across:2
		colorpicker csRayMissColor "Ray miss color:" align:#right fieldwidth:15 height:15 color:black
	)
	group "Normal Map Space"
	(
		radiobuttons rbNormalSpace labels:#("World","Screen","Local XYZ    ","Tangent") columns:4 align:#left
		label l_NormalDir "Orientation:" align:#left across:5
		label l_NormalXDir "Red:" align:#left offset:[5,0]
		radiobuttons rbNormalXDirTangent labels:#("Left","Right") columns:2 offset:[-35,-1] align:#left	visible:false enabled:false
		label l_NormalYDir "Green:" offset:[-10,0]
		radiobuttons rbNormalYDirTangent labels:#("Down","Up") columns:2 offset:[-23,-1] align:#left	visible:false enabled:false
		label l_Spacer01 "" align:#left offset:[0,-20] across:5
		label l_Spacer02 "" align:#left offset:[5,-20] 
		radiobuttons rbNormalXDirWLS labels:#("-X","+X") columns:2 offset:[-35,-20] align:#left			visible:false enabled:false
		label l_Spacer03 "" offset:[-10,-20]
		radiobuttons rbNormalYDirWLS labels:#("-Y","+Y") columns:2 offset:[-23,-20] align:#left			visible:false enabled:false
	)
	group "Height Map"
	(
		spinner sHeightMin "Min Height: " fieldwidth:60 align:#left across:3 type:#worldUnits range:[-1e9,1e9,0]
		checkbutton bHeightMinPick "" width:18 height:18 offset:[-16,-1] \
			images:#("MeditTools_i.bmp", "MeditTools_a.bmp", 43,41,41,41,41, true)
		editText etBufferMinHeight "Buffer min Height: " fieldwidth:60  align:#right readOnly:true
		spinner sHeightMax "Max Height:" fieldwidth:60 align:#left across:3 type:#worldUnits range:[-1e9,1e9,0]
		checkbutton bHeightMaxPick "" width:18 height:18 offset:[-16,-1] \
			images:#("MeditTools_i.bmp", "MeditTools_a.bmp", 43,41,41,41,41, true)
		editText etBufferMaxHeight "Buffer max Height:" fieldwidth:60  align:#right readOnly:true
	)
	
	on projectionOptionsProps open do
	(
		RTT_data.projectionOptionsPropsRO = projectionOptionsProps
		heightPickVal = undefined
		rendererCB = when parameters renderers.current change do RendererPropChanged()
		callbacks.addscript #postRendererChange "RTT_data.projectionOptionsPropsRO.RendererChanged()" id:#rtt_rendererChange
		callbacks.addscript #postRendererChange "RTT_data.projectionOptionsPropsRO.RendererChanged()" id:#rtt_rendererChange
		callbacks.addScript #selectionSetChanged "RTT_data.projectionOptionsPropsRO.SelectionChanged()" id:#rtt_proj_selectionChange 
		callbacks.addscript #preModifierAdded "RTT_data.projectionOptionsPropsRO.ModifierChanged #preModifierAdded" id:#rtt_proj_modifierChange
		callbacks.addscript #preModifierDeleted "RTT_data.projectionOptionsPropsRO.ModifierChanged #preModifierDeleted" id:#rtt_proj_modifierChange		
		UpdateObjectSettings()
		UpdateFilterSettings()
	)

	function RendererChanged =
	(
		if _debug do format "RendererChanged() - %\n" renderers.current
		deleteChangeHandler rendererCB 
		rendererCB = when parameters renderers.current change do RendererPropChanged()
		UpdateObjectSettings()
		UpdateFilterSettings()
	)

	function SelectionChanged =
	(
		if _debug do format "SelectionChanged()\n"
		if bHeightMaxPick.state or bHeightMinPick.state do max select
	)

	function ModifierChanged event =
	(
		if _debug do format "ModifierChanged()\n"
		if bHeightMaxPick.state or bHeightMinPick.state do max select
	)

		
	function RendererPropChanged =
	(
		if _debug do format "RendererChanged() \n"
		UpdateFilterSettings()
	)
	
	on projectionOptionsProps close do
	(
		if bHeightMaxPick.state or bHeightMinPick.state do max select	
		deleteChangeHandler rendererCB 
		callbacks.removeScripts id:#rtt_rendererChange
		callbacks.removeScripts id:#rtt_proj_selectionChange
		callbacks.removeScripts id:#rtt_proj_modifierChange
		RTT_data.projectionOptionsPropsRO = undefined
		pProjectionOptionsPropsPos = GetDialogPos projectionOptionsProps
		selectedObjectProps.bProjMapOptions.checked = false
	)
	
	on bSynchAll pressed do 
	(
		for obj in displayedBakableObjects do
		(
			local projInterface = obj.node.INodeBakeProjProperties
			if cbHitMatchMtlID.tristate != 2 do setproperty projInterface #hitMatchMtlID cbHitMatchMtlID.state
			if cbHitWorkingModel.tristate != 2 do setproperty projInterface #hitWorkingModel cbHitWorkingModel.state
			if rbProjSpace.enabled do
				if rbProjSpace.state != 0 do setproperty projInterface #projSpace projSpace_enums[rbProjSpace.state]
			if cbUseCage.tristate != 2 do 
			(
				setproperty projInterface #useCage cbUseCage.state
				if not sOffset.indeterminate do setproperty projInterface #rayOffset sOffset.value
			)
			if rbResolveHit.state != 0 do setproperty projInterface #hitResolveMode hitResolveMode_enums[rbResolveHit.state]
			if rbNormalSpace.state != 0 do setproperty projInterface #normalSpace normalSpace_enums[rbNormalSpace.state]
			if rbNormalYDir.state != 0 do setproperty projInterface #tangentYDir tangentYDir_enums[rbNormalYDir.state]
			if rbNormalXDir.state != 0 do setproperty projInterface #tangentXDir tangentXDir_enums[rbNormalXDir.state]
			if not sHeightMin.indeterminate do setproperty projInterface #heightMapMin sHeightMin.value
			if not sHeightMax.indeterminate do setproperty projInterface #heightMapMax sHeightMax.value
			if cbCropAlpha.tristate != 2 do setproperty projInterface #cropAlpha cbCropAlpha.state
			if cbRayMissCheck.tristate != 2 do setproperty projInterface #warnRayMiss cbRayMissCheck.state
			if not rayMissColor_indeterminate do setproperty projInterface #rayMissColor csRayMissColor.color
		)
		rtt_data.selectedObjectPropsRO.RefreshObjectsLV workingObjectsOnly:true
	)
	
	on cbHitMatchMtlID changed val do SetProjProp #hitMatchMtlID val
	on cbHitWorkingModel changed val do SetProjProp #hitWorkingModel val
	on rbProjSpace changed val do SetProjProp #projSpace projSpace_enums[val]
	on cbUseCage changed val do 
	(
		SetProjProp #useCage val
		sOffset.enabled = not val
	)
	on sOffset changed val do SetProjProp #rayOffset val
	on rbResolveHit changed val do SetProjProp #hitResolveMode hitResolveMode_enums[val]
	on rbNormalSpace changed val do
	(
		SetProjProp #normalSpace normalSpace_enums[val]
		UpdateOrientation()
	)
	on rbNormalXDirTangent changed val do SetProjProp #tangentXDir tangentXDir_enums[val]
	on rbNormalYDirTangent changed val do SetProjProp #tangentYDir tangentYDir_enums[val]
	on rbNormalXDirWLS changed val do SetProjProp #tangentXDir tangentXDir_enums[val]
	on rbNormalYDirWLS changed val do SetProjProp #tangentYDir tangentYDir_enums[val]
	on sHeightMin changed val do SetProjProp #heightMapMin val
	on sHeightMax changed val do SetProjProp #heightMapMax val
	on bHeightMinPick changed val do HeightPick #heightMapMin sHeightMin val
	on bHeightMaxPick changed val do HeightPick #heightMapMax sHeightMax val
	on cbCropAlpha changed val do SetProjProp #cropAlpha val
	on cbRayMissCheck changed val do SetProjProp #warnRayMiss val
	on csRayMissColor changed val do 
	(
		SetProjProp #rayMissColor val
		rayMissColor_indeterminate = false
	)
	on bSamplerSetup pressed do 
	(
		local renderTab = undefined
		local rendererClass = classof renderers.current
		if (rendererClass == mental_ray_renderer) then
			renderTab = #(188154248, 1489465121)
		else if (rendererClass == Default_Scanline_Renderer) then
			renderTab = #(1126448576, 479530250)
		if not renderSceneDialog.isOpen() do
			renderSceneDialog.open()
		if renderTab != undefined do
			tabbeddialogs.setCurrentPage #render renderTab -- set to Renderer tab
	)

	function SetProjProp propName propVal =
	(
		for obj in workingObjects do
		(
			local projInterface = obj.node.INodeBakeProjProperties
			setproperty projInterface propName propVal
		)
	)

	function UpdateSourceName =
	(
		etSource.text = 
			if workingObjects.count == 1 then 
			(
				local theNode = workingObjects[1].node
				local theName = theNode.name
				local bakeProjProperties = theNode.INodeBakeProjProperties
				if bakeProjProperties.enabled and bakeProjProperties.projectionMod != undefined do
				(
					local projMod = bakeProjProperties.projectionMod
					local n = projMod.numGeomSels()
					local count = 0
					for i = 1 to n do
					(
						local geomSelLevel = projMod.getGeomSelLevel i
						if geomSelLevel == #face or geomSelLevel == #element then count += 1
					)
					append theName " ("
					append theName (count as string)
					append theName " SO Outputs)"
				)
				theName 
			)
			else if selectedObjectProps.rSceneType.state == 2 then "All Selected"
			else "All Prepared"
	)

	function UpdateObjectSettings =
	(
		UpdateOrientation()
		
		if _debug do format "in projectionOptionsProps.UpdateObjectSettings - workingObjects: %\n" workingObjects
		if workingObjects.count == 0 then
		(
			projectionOptionsProps.controls.enabled = false
			
			etSource.text = ""
			cbHitMatchMtlID.state = false
			cbHitWorkingModel.state = false
			rbProjSpace.state = 0
			cbUseCage.state = false
			sOffset.indeterminate = true
			rbResolveHit.state = 0
			rbNormalSpace.state = 0
			rbNormalYDir.state = 0
			rbNormalXDir.state = 0
			sHeightMin.indeterminate = true
			etBufferMinHeight.text = ""
			sHeightMax.indeterminate = true
			etBufferMaxHeight.text = ""
			cbCropAlpha.state = false
			cbRayMissCheck.state = false
		)
		else -- if workingObjects.count == 1 then
		(
			projectionOptionsProps.controls.enabled = true
			
			local hitMatchMtlID = triStateValue()
			local hitWorkingModel = triStateValue()
			local projSpace = triStateValue()
			local useCage = triStateValue()
			local offset = triStateValue()
			local resolveHit = triStateValue()
			local tolerance = triStateValue()
			local normalSpace = triStateValue()
			local normalYDir = triStateValue()
			local normalXDir = triStateValue()
			local devAngle = triStateValue()
			local heightMin = triStateValue()
			local bufferMinHeight = triStateValue()
			local heightMax = triStateValue()
			local bufferMaxHeight = triStateValue()
			local cropAlpha = triStateValue()
			local antiAliasing = triStateValue()
			local rayMissCheck = triStateValue()
			local rayMissColor = triStateValue()
				
			for obj in workingObjects do
			(
				local projInterface = obj.node.INodeBakeProjProperties
				
				hitMatchMtlID.setVal projInterface.hitMatchMtlID
				hitWorkingModel.setVal projInterface.hitWorkingModel
				projSpace.setVal (findItem projSpace_enums projInterface.projSpace)
				useCage.setVal projInterface.useCage 
				offset.setVal projInterface.rayOffset
				resolveHit.setVal (findItem hitResolveMode_enums projInterface.hitResolveMode)
				normalSpace.setVal (findItem normalSpace_enums projInterface.normalSpace)
				normalYDir.setVal (findItem tangentYDir_enums projInterface.tangentYDir)
				normalXDir.setVal (findItem tangentXDir_enums projInterface.tangentXDir)
				heightMin.setVal projInterface.heightMapMin
				bufferMinHeight.setVal projInterface.heightBufMin
				heightMax.setVal projInterface.heightMapMax 
				bufferMaxHeight.setVal projInterface.heightBufMax
				cropAlpha.setVal projInterface.cropAlpha 
				rayMissCheck.setVal projInterface.warnRayMiss 
				rayMissColor.setVal projInterface.rayMissColor 
			)

			UpdateSourceName()

			bSynchAll.enabled = workingObjects.count == 1
			cbHitMatchMtlID.triState = hitMatchMtlID.asTriState()
			cbHitWorkingModel.triState = hitWorkingModel.asTriState()
			if (classof renderers.current == mental_ray_renderer) then
			(
				rbProjSpace.state = 1
				rbProjSpace.enabled = false
			)
			else
			(
				rbProjSpace.state = projSpace.asRadioButtonState()
				rbProjSpace.enabled = true
			)
			cbUseCage.triState = useCage.asTriState()
			offset.spinnerSet sOffset
			sOffset.enabled = cbUseCage.triState != 1 -- enabled if Use Cage != true
			rbResolveHit.state = resolveHit.asRadioButtonState()
			rbNormalSpace.state = normalSpace.asRadioButtonState()
			rbNormalYDir.state = normalYDir.asRadioButtonState()
			rbNormalXDir.state = normalXDir.asRadioButtonState()			
			heightMin.spinnerSet sHeightMin
			etBufferMinHeight.text = if bufferMinHeight.indeterminate then "" else (if (abs bufferMinHeight.value) > 1e10 then bufferMinHeight.value = 0; units.formatValue bufferMinHeight.value)
			heightMax.spinnerSet sHeightMax
			etBufferMaxHeight.text = if bufferMaxHeight.indeterminate then "" else (if (abs bufferMaxHeight.value) > 1e10 then bufferMaxHeight.value = 0; units.formatValue bufferMaxHeight.value)
			cbCropAlpha.triState = cropAlpha.asTriState()
			cbRayMissCheck.triState = rayMissCheck.asTriState()
			csRayMissColor.color = if rayMissColor.indeterminate then black else rayMissColor.value
			rayMissColor_indeterminate = rayMissColor.indeterminate 
		)
	)

	function UpdateFilterSettings =
	(
		local renderer = renderers.current
		local rendererClass = classof renderer
		local txt
		if rendererClass == Default_Scanline_Renderer then
		(
			txt = "Global Supersampler: "
			if renderer.globalSamplerEnabled then
				append txt renderer.globalSamplerClassByName
			else
				append txt "None"
		)
		else if (rendererClass == mental_ray_renderer) then
		(
			txt = "Samples per pixel: "
			local n = amax renderer.MinimumSamples 0
			append txt ((4^n) as string)
		)
		else
			txt = "Unknown Renderer Type"
		l_samplerType.text = txt
	)
	
	function UpdateHeightBufferDisplay =
	(
		if workingObjects.count == 0 then
		(
			etBufferMinHeight.text = ""
			etBufferMaxHeight.text = ""
		)
		else
		(
			local bufferMinHeight = triStateValue()
			local bufferMaxHeight = triStateValue()
				
			for obj in workingObjects do
			(
				local projInterface = obj.node.INodeBakeProjProperties
				bufferMinHeight.setVal projInterface.heightBufMin
				bufferMaxHeight.setVal projInterface.heightBufMax
			)
			etBufferMinHeight.text = if bufferMinHeight.indeterminate then "" else (if (abs bufferMinHeight.value) > 1e10 then bufferMinHeight.value = 0; units.formatValue bufferMinHeight.value)
			etBufferMaxHeight.text = if bufferMaxHeight.indeterminate then "" else (if (abs bufferMaxHeight.value) > 1e10 then bufferMaxHeight.value = 0; units.formatValue bufferMaxHeight.value)
		)
	)

	function UpdateOrientation =
	(
		local normalXDirState = 0, normalYDirState = 0, useTangent = true
		for obj in workingObjects do
		(
			local projInterface = obj.node.INodeBakeProjProperties
			if ((getproperty projInterface #normalSpace) != #tangent) do
				useTangent = false
		)
		
		if (rbNormalXDir!=undefined) and (rbNormalYDir!=undefined) do
		(
			normalXDirState = rbNormalXDir.state
			normalYDirState = rbNormalYDir.state
			rbNormalXDir.visible = rbNormalXDir.enabled = false
			rbNormalYDir.visible = rbNormalYDir.enabled = false
		)
		
		rbNormalXDir = (if useTangent then rbNormalXDirTangent else rbNormalXDirWLS)
		rbNormalYDir = (if useTangent then rbNormalYDirTangent else rbNormalYDirWLS)
		
		rbNormalXDir.visible = rbNormalXDir.enabled = true
		rbNormalYDir.visible = rbNormalYDir.enabled = true
		rbNormalXDir.state = normalXDirState
		rbNormalYDir.state = normalYDirState
	)

	-- MouseTrack callback, Helper for HeightPick()
	function HeightPick_Callback msg ir obj faceNum shift ctrl alt   arg =
	(
		if ((msg==#mouseMove) or (msg==#mousePoint)) and (obj!=undefined) and (ir!=undefined) do
		(	-- arg1=projIntersectors, arg2=projNodes, arg3=propVal, arg4=propControl
			local projIntersector = (arg[1])[ findItem arg[2] obj ]
			local propVal = arg[3]
			local propControl = arg[4]

			-- Find the point to start the projection from			
			projIntersector.ClosestFace ir.pos
			local triIndex = projIntersector.GetHitFace()
			local triBary = projIntersector.GetHitBary()
			
			-- Do the projection
			local projOK = projIntersector.ProjectionFace triIndex triBary
			if projOK do
			(	-- Set the projected height value
				local projDist = projIntersector.GetHitDist()
				propControl.value = projDist
				SetProjProp propVal projDist
			)
		)
		if (msg==#mouseAbort) then false else #continue
	)

	function HeightPick propVal propControl onOff =
	(
		max select -- exit any current pick mode
		if not onOff do return() -- done; pick mode is off, nothing else to do

		-- Turn off the opposite button in case it's on (hack)
		if (propVal==#heightMapMin) do bHeightMaxPick.state=false
		if (propVal==#heightMapMax) do bHeightMinPick.state=false
		
		local projIntersectors = #()
		local projNodes = #()
				
		-- Create intersector objects for each node
		for obj in workingObjects do
		(
			local projMod = undefined
			for mod in obj.node.modifiers do (if ((classof mod)==Projection) do projMod=mod)
			if (projMod!=undefined) do
			(
				local projIntersector = MeshProjIntersect()
				projIntersector.SetNode obj.node
				projIntersector.Build()
				
				append projIntersectors projIntersector
				append projNodes obj.node
				obj.node.INodeBakeProjProperties.projectionMod = projMod
			)
		)

		-- Run the pick mode
		local arg = #( projIntersectors, projNodes, propVal, propControl )
		mouseTrack on:projNodes trackCallback:#(HeightPick_Callback,arg)
		
		for projIntersector in projIntersectors do projIntersector.Free()

		-- Turn off the button when done
		if (propVal==#heightMapMin) do bHeightMinPick.state=false
		if (propVal==#heightMapMax) do bHeightMaxPick.state=false
	)
	
) -- end - rollout projectionOptionsProps 

------------------------------------------------------------------
--
--	Create the gTextureBakeDialog dialog & assign the subrollouts
--	
on execute do 
(
	local cls = classof gTextureBakeDialog
	if (cls != RolloutClass) or gTextureBakeDialog.isDisplayed do return false
	
	-- set the command mode while undo is not disabled in case we are in the middle of a hold from a mouse proc
	toolMode.commandMode = #select

	with undo off
	(

		-- re-initialize locals
		selectedObjects = #() -- the selected objects. Contains nodes
		displayedBakableObjects = #() -- the selected objects that are bakable. Contains bakableObjStruct instances
		workingObjects = #() -- the current working objects. Contains bakableObjStruct instances
		
		-- one time init on new session. Session persistent defaults go here.
		if (RTT_data == undefined) do
		(
			RTT_data = RTT_data_struct()

			RTT_data.overwriteFilesOk = 0

			RTT_data.FileOutput_FileType = defaultFileType
			RTT_data.FileOutput_FilePath = getdir #image
			
			RTT_data.AutoFlatten_Spacing = 0.03
			RTT_data.AutoFlatten_ThresholdAngle = 45.0
			RTT_data.AutoFlatten_Rotate = true
			RTT_data.AutoFlatten_FillHoles = true
			
			RTT_data.AutoFlatten_Obj_On = true
			RTT_data.AutoFlatten_Obj_MapChannel = 3
			
			RTT_data.AutoFlatten_SubObj_On = true
			RTT_data.AutoFlatten_SubObj_MapChannel = 4
			
			RTT_data.AutoSize_SizeMin = 32
			RTT_data.AutoSize_SizeMax = 2048
			RTT_data.AutoSize_SizeScale = 0.01
			RTT_data.AutoSize_SizePowersOf2 = false 
			
			RTT_data.Renderer_DisplayFB = true
			RTT_data.Renderer_NetworkRender = false
			RTT_data.Renderer_SkipExistingFiles = false
			
			RTT_data.OutputMapSize_AutoMapSize = false 
			RTT_data.OutputMapSize_Width = mapPresets[1].x
			RTT_data.OutputMapSize_Height = mapPresets[1].y
			
			RTT_data.Materials_RenderToFilesOnly = false
			RTT_data.Materials_MapDestination = 2
			RTT_data.Materials_DuplicateSourceOrCreateNew = 1
			
			RTT_Data.rendererErrorDisplayed = false
			RTT_Data.netRenderErrorDisplayed = false
			
			RTT_Data.ignoreModStackChanges = false
			
			RTT_data.exposureControlOK = 0
			
			RTT_data.emptyTargetsOk = 0
			
			RTT_data.loadObjectPresetOk = 0
			RTT_data.loadObjectPresetProjModOk = 0
		)

		ReadDialogConfig()
		ReadSceneData() -- mapping coordinates settings
		
		CreateDialog gTextureBakeDialog \
			style:#(#style_sysmenu,#style_titlebar,#style_minimizebox,#style_resizing) \
			pos:pDialogPos lockWidth:true
			
		--format "setting height = % \n" pDialogHeight
		gTextureBakeDialog.height = pDialogHeight
		gTextureBakeDialog.width = 350

		AddSubRollout gTextureBakeDialog.rollouts commonBakeProps rolledup:(not pCommonBakePropsOpen )
		AddSubRollout gTextureBakeDialog.rollouts selectedObjectProps rolledup:(not pSelectedObjectPropsOpen )
		AddSubRollout gTextureBakeDialog.rollouts selectedElementProps rolledup:(not pSelectedElementPropsOpen )
		AddSubRollout gTextureBakeDialog.rollouts bakedMtlProps rolledup:(not pBakedMtlPropsOpen )
		AddSubRollout gTextureBakeDialog.rollouts autoUnwrapMappingProps rolledup:(not pAutoUnwrapMappingPropsOpen )

		lvops.RefreshListView selectedObjectProps.lvObjects
		lvops.RefreshListView selectedElementProps.lvElements
		
		-- & use initial node selection
		gTextureBakeDialog.OnObjectSelectionChange()

		local errormsg = ""
		if (not RTT_Data.rendererErrorDisplayed and not renderers.current.supportsTexureBaking) do 
		(
			errormsg = "Renderer doesn't support Texture Baking, Rendering disabled\n"
			RTT_Data.rendererErrorDisplayed = true
		)
		if (not RTT_Data.netRenderErrorDisplayed and classof netrender != Interface) do 
		(	
			errormsg += "Backburner interface not found - network rendering disabled\n"
			RTT_Data.netRenderErrorDisplayed = true
		)
		if errormsg != "" do messagebox errormsg title:"Render To Texture" --LOC_NOTES: localize this
	)
)

on isChecked return 
(
	local cls = classof gTextureBakeDialog
	(cls == RolloutClass) and gTextureBakeDialog.isDisplayed and (not gTextureBakeDialog.isClosing)
)
on isEnabled return
(
	local cls = classof gTextureBakeDialog
	(cls == RolloutClass)
)
on closeDialogs do with undo off
(
	local cls = classof gTextureBakeDialog
	if (cls == RolloutClass) and gTextureBakeDialog.isDisplayed do destroyDialog gTextureBakeDialog 
)

) -- end, macroscript BakeDialog
