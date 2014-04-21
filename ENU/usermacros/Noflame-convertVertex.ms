fn convertPhysiqueVertexRedToGreenFN =
(
	sel = getVertSelection $
	for i in sel do
	(
		local weightTable = #()
	
		types = physiqueOps.getVertexType $ i
		format "point:% �����A�O % \n" i  (types as string)
		if ((types as string) == "deformable_type") then
		(	--���obone��weight���		
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
			format "point:% �w�g�O��⪺�F\n" i
		)
	)
)