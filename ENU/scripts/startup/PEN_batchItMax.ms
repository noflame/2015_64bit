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

Usage:
PEN_batchItMax.run()
PEN_batchItMax.closeUi()

Updated:
	Oct 04 2006
	-Updated UI to make it wider
	-Nested tool in a struct and functions so it can be called from other tools. 

Bugs:
-Escape doesn't work

ToDo:
-File has been batched. Write this data into the file properties.
*/

struct PEN_batchItMax
(
	batchUtil=undefined,
	
	fn closeUi=
	(
		if batchUtil!=undefined then
		(
			destroyDialog batchUtil
			batchUtil=undefined
		)
	),
	fn run=
	(
		--Interface
		rollout batchUtil_R "Batch It Max" width:1000
		(
			local btW = 80
				
			button browseDir_bt "Browse" width:btW align:#left across:2
			editText batchDir_et "Scripts Directory:" fieldWidth:780 align:#right
			
			button browseProcess_bt "Browse" width:btW align:#left across:2
			editText processDir_et "Process Directory:" fieldWidth:780 align:#right
			
			checkbox overWrite_cb ":Overwrite Files on Save" checked:true across:2
			checkBox dontSaveFilesCb ":Don't Save Files" offset:[-320,0]
			button browseSaveFolder_bt "Browse" width:btW  align:#left across:2
			editText saveFolder_et "Save Files To:" fieldWidth:780 align:#right
		
			multiListBox batchList_mlb "Select batch scripts to run:" width:880 height:10 align:#right
			editText search_et "Search by file name:" fieldWidth:880 align:#right
			multiListBox maxFiles_mlb "Select Max Files to Process:" width:880 height:30 align:#right
			
			label prog0_lb "0%" across:3 align:#left
			label prog50_lb "50%"
			label prog1000_lb "100%" align:#right
			progressBar progBar_pb
		
			checkBox saveLog_cb ":Save Log File" checked:true align:#left pos:[14,115]
			button setLogFile_bt "Set Log File" width:btW align:#left
			button readLog_bt "Read Log File" width:btW align:#left
			
			button getFiles_bt "Get Files"  width:btW align:#left pos:[14,300]
			checkBox recurse_cb ":Recursive" checked:true align:#left
			button selAll_bt "Select All" width:btW align:#left 
			button deSelAll_bt "Deselect All" width:btW align:#left
			button process_bt "Process" width:btW align:#left offset:[0,20]
			
			button close_bt "Close" width:btW align:#left offset:[0,230]
		
			--Sets the ini file for the interface	
			Fn setBatchIni_fn sectionStr keyStr valueStr =
			(
				logPath = (getDir #plugCfg) + "\\" + "BatchIni.ini"
				setIniSetting logPath sectionStr keyStr valueStr
			)
			
			--Gets the ini settings for the interface.
			Fn getBatchIni_fn sectionStr keyStr =
			(
				logPath = (getDir #plugCfg) + "\\" + "BatchIni.ini"
				outStr = (getIniSetting logPath sectionStr keyStr)
				return outStr
			)
			
			--Collects the scripts in the designated folder.
			Fn getScipts_fn dir =
			(
				local files = #()
				if dir != "" then 
				(
					allFiles = (getFiles (dir + "\\" + "*.ms"))
					for x in allFiles do (append files (fileNameFromPath x))
				)
				return files
			)
			
			--Collects the Max files in the designated folders with the option of recursive or not.
			Fn getMaxFiles_fn dir =
			(
				if recurse_cb.checked then
				(
					local dir1 = getDirectories (dir + "*")
					for d in dir1 do
					(
						join dir1 (getDirectories (d + "*"))
					)
					
					local files = #()
					for f in dir1 do
					(
						join files (getFiles (f + "/*.max"))
					)
					return files
				)else
				(
					files = (getFiles (dir + "\*.max"))
					return files
				)
			)
			
			-- Search max files for string
			Fn searchMaxFiles_fn str =
			(
				selArray = #()
				numFiles = maxFiles_mlb.items.count
				for x = 1 to numFiles do
				(
					fileName = fileNameFromPath maxFiles_mlb.items[x]
					fileFound = findstring fileName str
					if fileFound != undefined then (append selArray x)
				)
				return selArray
			)
			
			Fn setLogPath_fn =
			(
				if saveLog_cb.checked == true then
				(
					path = getSaveFileName caption:"Select Log File" \
							fileName:"MaxBatchLog.log" \
							types:"Log Data (*.log)|*.log"
					if path != undefined then
					(
						--Write log path to Ini file
						setBatchIni_fn "batchUtil" "LogPath" path
						logFile = createFile path
					)
				)
			)
			
			--Create and write Log file.
			--FileIn is the file path being processed
			--ScriptIn is an array of the batch scripts being run on each max file
			Fn logFile_fn fileIn scriptIn =
			(
				if saveLog_cb.checked == true then
				(
					iniEx = if (getFiles ((getDir #plugCfg) + "\\" + "BatchIni.ini")).count > 0 then (true) else (false)
					openedFile = if iniEx then (openFile (getBatchIni_fn "batchUtil" "LogPath") mode:"a+")else(undefined)
					if openedFile != undefined then
					(
						format "File: %\n" fileIn to:openedFile
						format "\tDate:\t\t%\n" localTime to:openedFile
						format "\tUser:\t\t%\n" sysInfo.userName to:openedFile
						format "\tComputer:\t%\n" sysInfo.computerName to:openedFile
						for x in scriptIn do
						(
							format "\tScript:\t\t%\n" (fileNameFromPath x) to:openedFile
						)
						format "\n" to:openedFile
						close openedFile
					)else
					(
						--Error message goes here.
					)
				)
				fileProperties.addProperty #custom "Batch Processed" ""
				fileProperties.addProperty #custom "Date:" localTime #Date
				fileProperties.addProperty #custom "User:" sysInfo.userName
				fileProperties.addProperty #custom "Computer:" sysInfo.computerName
				fileproperties.addproperty #summary "author" sysInfo.userName
		
				for x in scriptIn do
				(
					fileProperties.addProperty #custom "Script:" (fileNameFromPath x)
					curComment=try(fileProperties.getPropertyValue #summary 2)catch("")
					fileproperties.addproperty #summary "comments" (curComment+"\n"+("Batched with:\n"+(fileNameFromPath x)))
				)
				
			)
			
			--Run on opening the interface. Gets and sets the interface settings and positions the 
			--dialog to the last used position.
			on batchUtil_R open do
			(
				iniEx = if (getFiles ((getDir #plugCfg) + "\\" + "BatchIni.ini")).count > 0 then (true) else (false)
		
				batchDir_et.text = if iniEx then (getBatchIni_fn "batchUtil" "batchDir") else (getDir #scripts)
				processDir_et.text = if iniEx then (getBatchIni_fn "batchUtil" "processDir") else (getDir #scene)
				saveFolder_et.text = if iniEx then (getBatchIni_fn "batchUtil" "saveFolder") else (getDir #scene)
				overWrite_cb.checked = if iniEx then (execute (getBatchIni_fn "batchUtil" "overWrite")) else (true)
				dontSaveFilesCb.checked = if iniEx then (execute (getBatchIni_fn "batchUtil" "dontSaveFiles")) else (true)
				
				saveLog_cb.checked = if iniEx then (execute (getBatchIni_fn "batchUtil" "saveLog")) else (true)
				recurse_cb.checked = if iniEx then (execute (getBatchIni_fn "batchUtil" "recurse")) else (true)
				
				--Update the scripts list on open
				batchList_mlb.items = (getScipts_fn batchDir_et.text)
				
				--Get the position of the Dialog
				setDialogPos batchUtil_R (if iniEx then (execute (getBatchIni_fn "batchUtil" "Position")) else ([10,100]))
		
				if overWrite_cb.state then
				(
					browseSaveFolder_bt.enabled = false
					saveFolder_et.enabled = false
				)else
				(
					browseSaveFolder_bt.enabled = true
					saveFolder_et.enabled = true
				)
				if dontSaveFilesCb.state then
				(
					overWrite_cb.enabled=not dontSaveFilesCb.state
					browseSaveFolder_bt.enabled=not dontSaveFilesCb.state
					saveFolder_et.enabled=not dontSaveFilesCb.state
				)
		
			)
			--Run on closing the dialog. Saves the last used settings for the interface and dialog position.
			on batchUtil_R close do
			(
				setBatchIni_fn "batchUtil" "batchDir" batchDir_et.text
				setBatchIni_fn "batchUtil" "processDir" processDir_et.text
				setBatchIni_fn "batchUtil" "saveFolder" saveFolder_et.text
				setBatchIni_fn "batchUtil" "overWrite" (overWrite_cb.checked as string)
				setBatchIni_fn "batchUtil" "dontSaveFiles" (dontSaveFilesCb.checked as string) 
				setBatchIni_fn "batchUtil" "saveLog" (saveLog_cb.checked as string)
				setBatchIni_fn "batchUtil" "recurse" (recurse_cb.checked as string)
				
				--Save position of the dialog
				setbatchIni_fn "batchUtil" "Position" (getDialogPOs batchUtil_R as string)
			)
			
			on browseDir_bt pressed do
			(
				path = (getSavePath caption:"Choose Directory for Scripts")
				if path != undefined then
				(
					batchDir_et.text = path
					batchList_mlb.items = (getScipts_fn batchDir_et.text)
				)
			)
			
			on browseProcess_bt pressed do
			(
				path = (getSavePath caption:"Select process directory")
				if path != undefined then
				(
					processDir_et.text = path
					getMaxFiles_fn path
				)
			)
			
			on browseSaveFolder_bt pressed do
			(
				path = (getSavePath caption:"Select Save File directory")
				if path != undefined then
				(
					saveFolder_et.text = path
				)
			)
			
			on batchDir_et entered str do
			(
				batchList_mlb.items = (getScipts_fn str)
			)
			
			on processDir_et entered str do
			(
				maxFiles_mlb.items = (getMaxFiles_fn processDir_et.text)
			)
			
			on overWrite_cb changed state do
			(
				if state then
				(
					browseSaveFolder_bt.enabled = false
					saveFolder_et.enabled = false
				)else
				(
					browseSaveFolder_bt.enabled = true
					saveFolder_et.enabled = true
				)
			)
			
			on dontSaveFilesCb changed state do
			(
				overWrite_cb.enabled=not state
				browseSaveFolder_bt.enabled=not state
				saveFolder_et.enabled=not state
			)
			
			--Search for files in MLB
			on search_et entered str do
			(
				maxFiles_mlb.selection = (searchMaxFiles_fn search_et.text)
			)
			
			--Set Log File
			on setLogFile_bt pressed do
			(
				setLogPath_fn()
			)
			
			--Read log file
			on readLog_bt pressed do
			(
				edit (getBatchIni_fn "batchUtil" "LogPath")
			)
			
			on getFiles_bt pressed do
			(
				maxFiles_mlb.items = (getMaxFiles_fn processDir_et.text)
			)
			
			on recurse_cb changed state do
			(
				maxFiles_mlb.items = (getMaxFiles_fn processDir_et.text)
			)
			
			--Start the process going.
			on process_bt pressed do
			(
				escapeEnable = true
				--Check for selected scripts
				scriptSel = 0
				for x = 1 to batchList_mlb.items.count do
				(
					if batchList_mlb.selection[x] == true do (scriptSel += 1)
				)
				--check for selected files
				fileSel = 0
				for x = 1 to maxFiles_mlb.items.count do
				(
					if maxFiles_mlb.selection[x] == true do (fileSel += 1)
				)
				
				progBar_pb.value = 0
				num = 0
				--check that files and scripts have been selected.
				if (scriptSel > 0) and (fileSel > 0) then
				(
					escapeEnable = true
					--Loop through files, open and run script.
					for x in maxFiles_mlb.selection do
					(
						--Load the max file and run the selected scripts.
						loadMaxFile maxFiles_mlb.items[x] useFileUnits:true quiet:true
						scriptsIn = #() -- List of scripts run on each file. To be written to Log file.
						for s in batchList_mlb.selection do
						(
							fileIn (batchDir_et.text + "\\" + batchList_mlb.items[s])
							append scriptsIn (batchList_mlb.items[s])
						)
						
						--Write data to log.
						if (getBatchIni_fn "batchUtil" "LogPath") != "" then
						(	
							logFile_fn maxFiles_mlb.items[x] scriptsIn
						)else
						(
							setLogPath_fn()
							logFile_fn maxFiles_mlb.items[x] scriptsIn
						)
						
						--Save max file
						--Get path name
						path = ""
						if overWrite_cb.checked then
						(
							--Path if file is to be overwritten.
							path = (getFileNamePath maxFiles_mlb.items[x])
						)else
						(
							--Path if new folder is choosen
							path = (saveFolder_et.text)
						)
						--get file name
						file = (fileNameFromPath maxFiles_mlb.items[x])
						
						--Save the file to the correct path if dontSaveFilesCb is unchecked. 
						if dontSaveFilesCb.state==false then
						(
							saveMaxFile (path + "\\" + file)
						)
						
						--Update progress bar
						progBar_pb.value = ((100.0 * (num += 1)) / fileSel)
					)
				)else 
				(
					messageBox "Please select Scripts and Files to process."
				)
			)
			
			--Select all
			on selAll_bt pressed do
			(
				maxFiles_mlb.selection = #{1..maxFiles_mlb.items.count}
			)
			--Delselect all
			on deSelAll_bt pressed do
			(
				maxFiles_mlb.selection = #{}
			)
			
			--Cancel dialog
			on close_bt pressed do
			(
				destroyDialog batchUtil_R
			)
		)
		batchUtil=batchUtil_R
		createDialog batchUtil_R style:#(#style_titleBar, #style_border, #style_sysMenu, #style_minimizeBox)
	)--End Run Function
)--End Struct
PEN_batchItMax=PEN_batchItMax()














