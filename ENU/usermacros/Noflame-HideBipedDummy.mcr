macroScript hideBipedDummy
	category:"noFLAME"
	toolTip:"hide biped dummy"
(
	for i in helpers where classof i.parent == Biped_Object do
	(
			freeze i;
			hide i ;
	)
)