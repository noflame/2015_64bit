macroScript goToNextKey
category:"Noflame Tools"
toolTip:""
(
	fn goToNext_Key =
	(
		Next_Key = trackbar.getNextKeyTime()
		if selection.count != undefined and Next_Key != undefined do sliderTime = Next_Key
	)
	
	goToNext_Key()
)