macroScript quickParent
	category:"noFLAME"
	toolTip:"quick Parent"
(
	if selection.count >= 2 do
	(
		for i = 1 to selection.count-1 do
		(
			selection[i].parent = selection[selection.count]			
		)
		select selection[selection.count]
	)
)
