macroScript goToPrevKey
category:"Noflame Tools"
toolTip:""
(
	fn goToPrev_Key =
	(
		Previous_Key = trackbar.getPreviousKeyTime()
		if selection.count != undefined and Previous_Key != undefined do sliderTime = Previous_Key
	)
	
	goToPrev_Key()
)