/*
Client:PEN Productions Inc.

Created By: Paul Neale
Company: PEN Productions Inc.
E-Mail: info@paulneale.com
Site: http://paulneale.com
Start Date: unknown. 

Purpose:
Max version 5x,6x,7x,8x,9x
Batch processes Max files with Max scripts. 

Requires PEN_BatchProcessingUtil.ms to work. 
*/

macroScript BatchItMax 
	category:"PEN Tools"
	buttonText:"Batch It Max"
	toolTip:"Open/Close Batch It Max"
(
	on execute do
	(
		if ::PEN_batchItMax.batchUtil==undefined then
		(
			PEN_batchItMax.run()
		)else
		(
			PEN_batchItMax.closeUI()
		)
	)
)
