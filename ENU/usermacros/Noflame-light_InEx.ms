rollout ExIn_rut "massive In Ex" width:162 height:147
(
	button R_Btn "Re" pos:[112,16] width:33 height:25
	button L_Btn "In" pos:[64,16] width:33 height:25
	button E_Btn "Ex" pos:[16,16] width:33 height:25
	GroupBox grp1 "使用說明" pos:[16,52] width:129 height:75
	label lbl2 "操作燈放 Light" pos:[24,77] width:112 height:15
	label lbl3 "操作物體放 Object" pos:[24,97] width:112 height:15
	on ExIn_rut open  do
	(
		if selectionSets["light"] == undefined do
		(
			selectionSets["light"]=#()
		)
		if selectionSets["object"] == undefined do
		(
			selectionSets["object"]=#()
		)

	)
	
	on R_Btn pressed do
	(
		for nowL in selectionSets["light"] do
		(
			nowL.includeList = #()
			nowL.excludeList = #()
		)

	)
	on L_Btn pressed do
	(
		for nowL in selectionSets["light"] do
		(
			nowL.includeList = nowL.includeList + selectionSets["object"]
		)

	)
	on E_Btn pressed do
	(
		for nowL in selectionSets["light"] do
		(
				nowL.excludeList = nowL.excludeList + selectionSets["object"]
		)
		
	)
)if ExIn_rut != undefined do
(
	DestroyDialog ExIn_rut
)
CreateDialog ExIn_rut