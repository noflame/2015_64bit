macroScript moreThanTree
	category:"noFLAME"
	toolTip:"select more than 3 bone affect vertex(physique only)"
(	
	moreThanTree = #{};

	try( -- for editable_poly
		for i = 1 to $.GetNumVertices() do
		(
			if (3 < physiqueOps.getVertexBoneCount $ i) do append moreThanTree i
		)

		$.SetSelection #Vertex moreThanTree
		)
	catch()
	try( -- for editable_mesh
		for i = 1 to $.numverts do
		(
			if (3 < physiqueOps.getVertexBoneCount $ i) do append moreThanTree i
		)

		setVertSelection $ moreThanTree
		)
	catch()
)
