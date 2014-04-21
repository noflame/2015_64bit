macroScript simpleAlign
	category:"noFLAME"
	toolTip:"simple Align"
(
	btw = ((selection[selection.count].pos - selection[1].pos ) / (selection.count - 1));
	for i = 0 to selection.count - 1 do 
	(
		selection[i+1].pos = selection[1].pos + btw * i;
	)
)
