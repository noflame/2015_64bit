rollout CopyPhtsiqueWeight_rut "Copoy Physique Weight" width:440 height:184
(
	button Copy_btn "add to copy" pos:[17,42] width:80 height:28
	button Paste_btn "add to paste" pos:[17,95] width:80 height:28
	button go_btn "Go Paste It ! " pos:[18,144] width:400 height:25
	button clearCopy_btn "clear" pos:[103,42] width:40 height:28
	button clearPaste_btn "clear" pos:[103,95] width:40 height:28
	
	edittext orgBip_edt "" pos:[77,11] width:95 height:20
	label lbl1 "Orignal Bip:" pos:[20,14] width:59 height:14
	
	label lbl4 "paste vertex:" pos:[151,102] width:64 height:14
	label lbl5 "copy vertex:" pos:[155,49] width:60 height:14
	edittext edt4 "" pos:[213,46] width:205 height:20 enabled:false
	edittext edt5 "" pos:[213,99] width:205 height:20 enabled:false
	label lbl6 "------------------------------------------------------------------------------------------------------------------------------------" pos:[19,76] 
	
	local copyV = #()
	local pasteV = #()
	local bonesArray = #()
	
	edittext tragetBip_edt "" pos:[322,11] width:95 height:20
	label lbl11 "Target Bip:" pos:[269,14] width:56 height:14
	checkbox trans_chk "Transfer" pos:[193,12] width:65 height:14
	on Copy_btn pressed do
	(
		try(s = getvertselection $)catch()
		append copyV s
		copyList_edt.text = copyV as string
	)
	on Paste_btn pressed do
	(

	)
	on go_btn pressed do
	(
		local weightTable = #()
		local bones = #()
		
		-- copy weight start --
		if (selection.count == 1) and ((classof $.baseobject == Editable_Mesh) or (classof $.baseobject == Editable_Poly)) then
		(
			if (classof $ == Editable_Mesh) then
			(
				for i in (getvertselection $) do
				(
					--取得physique資料先
					--取得bone跟weight資料
					
					bones = physiqueOps.getVertexBones $  i
					for b = 1 to bones.count do
					(
						append weightTable (physiqueOps.getVertexWeight $ gw_i b)
						format "bones:% weight:%\n" bones[b].name weightTable[b]
					)
				)
				
				 print "copy成功！"
			)
			else print "我找不到要copy的頂點喔！"
		)
		else  print "你沒選物體吧…"
		-- copy weight end --
		
		-- transfer bones start --
		
		local newBones=#()
		
		if trans_chk.checked then
		(
			for i in bones do
			(
				str = bone[i].name
				str = replace str 1 orgBip_edt.text.count traget.text
				append newBones  (getNodeByName str)
				
			)
		)
		else print "不轉換骨頭"
		-- transfer bones end --
	
	)
	on clearCopy_btn pressed do
	(
		copyV = #()
		copyList_edt.text = copyV as string
	)
	on clearPaste_btn pressed do
	(
		pasteV =#()
		pasteList_edt.text = pasteV as string
	)
)

if CopyPhtsiqueWeight_rut != undefined do
(
	DestroyDialog CopyPhtsiqueWeight_rut
)
CreateDialog CopyPhtsiqueWeight_rut