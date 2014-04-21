macroScript selectBipePelvis
	category:"Noflame Tools"
	toolTip:"select Biped Pelvis"
(
	if classof selection[1] != undefined do  
	(
		if ((classof selection[1])as string) == "Biped_Object" do
		(
			select (biped.getNode selection[1] #horizontal)
		)
	)	
)