fn convertPhysiqueVertexRedToGreenFN =
(
	sel = getVertSelection $
	for i in sel do
	(
		local weightTable = #()
	
		types = physiqueOps.getVertexType $ i
		format "point:% 的型態是 % \n" i  (types as string)
		if ((types as string) == "deformable_type") then
		(	--取得bone跟weight資料		
			bones = physiqueOps.getVertexBones $ i
			for b = 1 to bones.count do
			(
				append weightTable (physiqueOps.getVertexWeight $ i b)
				format "bones:% weight:%\n" bones[b].name weightTable[b]
			)
			-----------------------------------------------
			physiqueOps.setVertexBone $ i bones[1] weight:weightTable[1] clear:true
			for b=2 to bones.count do
			(
				physiqueOps.setVertexBone $ i bones[b] weight:weightTable[b]
			)
		
			--physiqueOps.lockVertex $ i
		
		)
		else
		(
			format "point:% 已經是綠色的了\n" i
		)
	)
)
