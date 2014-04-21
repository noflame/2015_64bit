macroScript ShowPhysiqueWeight
	category:"noFLAME"
	buttontext:"ShowPhysiqueV"
	toolTip:"Show selected vertices' physique weight in the viewport"
(
	local VertexPhyShow = false
	local lastviewport
	global Laca_callbacks
	global redrawscr_laca()
	
	fn redrawscr_laca = gw.updatescreen()

	fn VertexShow = (
		try (
			if viewport.activeViewport != lastviewport do (
				completeredraw()
				lastViewport = viewport.activeViewport 
			)
			if (selection.count == 1) and ((classof $.baseobject == Editable_Mesh) or (classof $.baseobject == Editable_Poly)) then
			(
				gw.setTransform (matrix3 1) --to get a world-space to screen-space conversion
				if (classof $ == Editable_Mesh) then
					for gw_i in (getvertselection $) do
					(
						--取得physique資料先
						-- 取得bone跟weight資料
						weightTable = #()
						bones = physiqueOps.getVertexBones $ i
						for b = 1 to bones.count do
						(
							append weightTable (physiqueOps.getVertexWeight $ i b)
							format "bones:% weight:%\n" bones[b].name weightTable[b]
						)
						--印出
						for p =1 to bones.count do
						(
							stg = (bones[p].name as string) + ":" + (weightTable[p] as string)
							gw.wtext ((gw.wTransPoint (getvert $ gw_i)) + [10,(-10*p),0]) stg color:[231,217,55]
						)
						
					)
				else
					for gw_i in (polyop.getvertselection $.baseobject) do
						gw.wtext ((gw.wTransPoint (polyop.getvert $ gw_i)) + [5,-5,0]) (gw_i as string) color:[231,217,55]
				gw.enlargeupdaterect #whole
			)
		)
		catch()
	)
	
	on ischecked return VertexPhyShow
	
	on Execute do (
		if VertexPhyShow then (
			Laca_callbacks -= 1
			unregisterRedrawviewscallback VertexShow
			if Laca_callbacks == 0 then unregisterRedrawViewsCallback redrawscr_laca
		)
		else (
			if Laca_callbacks != undefined then Laca_callbacks += 1
			if Laca_callbacks == undefined then Laca_callbacks = 1
			registerRedrawviewscallback VertexShow
			unregisterRedrawViewsCallback redrawscr_laca
			registerRedrawviewsCallback redrawscr_laca
		)
		VertexPhyShow = not VertexPhyShow
		forcecompleteredraw()
		updateToolbarbuttons()
	)
)
