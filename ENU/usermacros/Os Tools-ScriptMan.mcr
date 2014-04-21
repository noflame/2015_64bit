macroScript ScriptMan
	category:"Os Tools"
	tooltip:"Script Manager"
	buttontext:"ScriptMan"
	
(
	rollout ro_ScriptMan "ScriptMan 0.42"
	(

		-- Global Variable Declerations
		------------------------------------
		global scriptManRootDirList


		-- Local Struct Declerations
		------------------------------------
	
		struct s_file (
			dispName,
			filename, 
			type,		-- type: #file / #dir
			
			results = undefined,
			
			fn editFile =
			(
				if type == #file and doesFileExist filename then
				(
					if ( (maxVersion())[1] < 10000 ) then
					try (
							print "N++" 
							hiddenDosCommand ("\"C:\\Program Files\\Notepad++\\notepad++.exe\" "+filename) startpath:"c:\\"
						) catch (edit filename)
					else edit filename
				)	
				
			),
			
			fn exec =
			(
				if doesFileExist filename then (
					try(
						format "Executing: %\n" filename
						filein filename
					)catch (format "Failed executing: %\n" filename)
				)
				if type == #dir then
					shellLaunch filename ""
			)
		) 
	
	
	
	-- Local Variable Devlerations
		---------------------------------
		local INIFile = getDir #scripts + "\\ScriptMan.ini"
		local rolloutHeight

		local fileList = #()
		local favorites = #()
		local favVisible = true
		local searchResults = #()
		local maxRecurseDepth = 3
		local maxDepth = maxRecurseDepth
		local historyLength = 15
	
	
		--User Interface
		------------------------
		button bn_ShadeWin "" width:(ro_ScriptMan.width+4) height:7 pos:[-2,-1] images:#((bitmap (ro_ScriptMan.width+4) 7 color:gray),undefined,1,1,1,1,1) tooltip:"Click to shade window."

		group "Root Dir: " (
			dropDownList dlRootDir "" Width:175 across:2 align:#left offset:[-5,-2] items:(if scriptManRootDirList == undefined then #() else scriptManRootDirList)
			button bnRootDirBrowse "..." height:18 width:18 align:#right offset:[6,-2] tooltip:"Browse..."
		)
		
		group "Show: " (
			checkbutton cbShowDirs "Dirs." checked:true offset:[18,0] width:45 height:16 highlightColor:(color 180 220 180) align:#left across:3 tooltip:"Show directories in the list"
			checkbutton cbShowFiles "Files" checked:true offset:[6,0] width:45 height:16 highlightColor:(color 180 220 180) align:#left tooltip:"Show files in the list"
			checkbutton cbShowSubDirs "Sub-Dirs." checked:true offset:[-6,0] width:45 height:16 highlightColor:(color 180 220 180) align:#left tooltip:"Show files and directories in sub folders"
			spinner spMaxDepth "" fieldWidth:17 type:#integer range:[1,9,maxDepth] pos:(cbShowSubDirs.pos + [45,0]) enabled:cbShowSubDirs.checked
			radioButtons rbShowResults "" labels:#("", "  Search results") columns:1 align:#left offset:[-5,-20]
		)
		
		
group "Search Text In Files: " (
			editText edSearchText "" fieldWidth:190 offset:[-8,-2]
		)
		
		listbox lbFiles "Files: " height:25 width:200 offset:[-8,0]
		button bnShowHideFav "" width:(ro_ScriptMan.width+4) height:7 images:#((bitmap (ro_ScriptMan.width+4) 7 color:gray),undefined,1,1,1,1,1) tooltip:"Click to show/hide favorites."
		listbox lbFavorites "Favorites: " height:10 width:200 offset:[-8,0] visible:favVisible
		
		
		-- Functions
		------------------------
		fn uniqueAppend &arr item byProp: =
		(
			local doAppend = true
			if byProp == unsupplied then (
				local nameArr = for a in arr collect a as name
				local itemName = item as name
				for i in nameArr where i == itemName do
					doAppend = false
			) else (
				local nameArr = for a in arr collect (getProperty a (byProp as name)) as name
				local itemName = (getProperty item (byProp as name)) as name
				for i in nameArr where i == itemName do
					doAppend = false
			)
			if doAppend then
				append arr item
		)
		
		
fn uniqueInsert &arr item n =
		(
			local nameArr = for a in arr collect a as name
			for i = 1 to nameArr.count where nameArr[i] == (item as name) do
				return i
			insertItem item arr n
			n
		)
		
		
		-- shorten the filename string to fit in a specified width.
		fn truncFileDisplay str l = (
			if (getTextExtent str).x <= l then return str
			local fName = "\\" + filenameFromPath str
			local fPath = getFilenamePath str
			local returnStr = fPath + "..." + fName
			while (((getTextExtent returnStr).x > l) AND (fPath.count > 0)) do (
				fPath = subString fPath 2 (fPath.count)
				returnStr = "..." + fPath  + fName
			)
			returnStr
		)	

		-- returns a string in lower case
		fn toLowerCase str =
		(
			local lower = "abcdefghijklmnopqrstuvwxyz"
			local upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
			local tmpStr = ""
			for i = 1 to str.count do
			(
				local n
				if (n=(findString upper str[i]))!= undefined then tmpStr += lower[n]
				else tmpStr += str[i]
			)
			tmpStr
		)

	
	-- replaces all occurrences of findStr string in str string with replaceStr string.
		fn replaceString str findStr replaceStr ignoreCase:true =
		(
			local tmpStr = if (ignoreCase == true) then (toLowerCase str) else (copy str)
			local tmpFindStr = if (ignoreCase == true) then (toLowerCase findStr) else (copy findStr)
			local outStr = ""
			local i, j = 1, n = findStr.count
			while ((i = findString tmpStr tmpFindStr) != undefined) do (
				outStr += subString str j (i - 1) + replaceStr as string
				j += i - 1 + n
				tmpStr = subString tmpStr (i + n) (tmpStr.count - (i + n) + 1)
			)
			outStr += tmpStr
			outStr
		)
	

		
		
fn getParentDir d = 
		(
			local arr = filterString d "/\\"

			local str = arr[1] + "\\"
			for i = 2 to (arr.count - 1) do
				str += arr[i] + "\\"
			str
		)
		

	
	fn getDispName f rootDir =
		(
			subString f (rootDir.count + 1)(f.count - rootDir.count - 1)
		)


		fn getFilesRecursive root pattern depth:1 maxDepth:maxDepth dirs:true files:true = 
		(
			if depth > maxDepth then return #()
			local my_files = #() 
			if root[root.count] != "\\" and root[root.count] != "/" then 
				root += "\\"
	
			if files then (
		
		for f in getFiles (root + pattern) do 
					append my_files (s_file ("     " + (getFilenameFile f)) (replaceString f "\\\\" "\\") #file)
			)
	
			local dir_array = GetDirectories (root + "*") 
	
		
for d in dir_array do (
				d = replaceString d "\\\\" "\\"
				local dname = (getDispName d dlRootDir.text)
				if dname[1] == "\\" or dname[1] == "/" then
					dname = substring dname 2 (dname.count - 1)
				dname = ("<<=  " + dname +"  =>>")
				if dirs then
					append my_files (s_file dname d #dir)
				join my_files (getFilesRecursive d pattern depth:(depth+1) dirs:dirs files:files)
			)
			
			my_files 
		)



		fn search txt rootDir =
		(
			local outFile = sysInfo.tempdir + "scriptman_search.txt"
			deleteFile outFile
			rootDir = replaceString rootDir "\\\\" "\\"
			rootDir = replaceString rootDir "/" "\\"
			if rootDir[rootDir.count] != "\\" then
				rootDir += "\\"
--			local cnd = "@for /R \"" + rootDir + "\" %i IN (*.ms) DO @find /I /C \"" + txt + "\" \"%i\" >> " + outFile
			local cmd = "@for %i IN (\"" + rootDir +"*.ms\") DO @find /I /C \"" + txt + "\" \"%i\" >> " + outFile
			dosCommand cmd
 			-- parse results
			local results = #()
			if doesFileExist outFile then (
				local f = openFile outFile mode:"r"
				while not (eof f) do (
					local l = readLine f
					try (
						if findString l "---------- " != undefined then (
							local n = findString l ": "
							local fname = subString l 12 (l.count - 12 - (l.count - n))
							local res = subString l (n + 2) (l.count - n - 1)
							res = res as integer
							if res > 0 then
								append results (s_file ("     " + (getFilenameFile fname) + " (" + res as string + ")") fname #file results:res)
						)
					)catch()
				)
				close f
			)
			
			deleteFile outFile
			results
		)



		fn addToHistory dir =
		(
			local n = uniqueInsert scriptManRootDirList dir 1
			if n != 1 then (
				deleteItem scriptManRootDirList n
				insertItem dir scriptManRootDirList 1
			)
			while scriptManRootDirList.count > historyLength do
				deleteItem scriptManRootDirList scriptManRootDirList.count
		)
		
	
		fn getFileList =
		(
			local d = dlRootDir.selected
			if d == undefined then return()
			if cbShowDirs.state then (
				local curDir = s_file (">>|  " + (truncFileDisplay d 135) + "  |<<") d #dir
				local parentDir = s_file ("<<=  ..  =>>") (getParentDir d) #dir
				fileList = #(curDir, parentDir)
			) else 
				fileList = #()
			join fileList (getFilesRecursive d "*.ms" dirs:cbShowDirs.state files:cbShowFiles.state)
		)
		
				
		fn updateUI =
		(

			spMaxDepth.enabled = cbShowSubDirs.checked
			case rbShowResults.state of (
				1: lbFiles.items = for i in fileList collect i.dispName
				2: lbFiles.items = for i in searchResults collect i.dispName
			)

			lbFavorites.items = for f in favorites collect f.dispName

		)
		
		
		fn saveToINIFile =
		(
			setINISetting INIFile "Settings" "Position" ((getDialogPos ro_ScriptMan) as string)
			setINISetting INIFile "Settings" "Shaded" ((ro_ScriptMan.height < 8) as string)
			setINISetting INIFile "Settings" "FavVisible" (favVisible as string)
			setINISetting INIFile "Settings" "HistoryItems" (historyLength as string)

			setINISetting INIFile "Settings" "ShowDirs" (cbShowDirs.state as string)
			setINISetting INIFile "Settings" "ShowFiles" (cbShowFiles.state as string)
			setINISetting INIFile "Settings" "ShowSubDirs" (cbShowSubDirs.state as string)
			setINISetting INIFile "Settings" "MaxSubDirDepth" (spMaxDepth.value as string)

			for i = 1 to scriptManRootDirList.count do
				setINISetting INIFile "History" ("Dir" + i as string) scriptManRootDirList[i]


			setINISetting INIFile "Favorites" "FavCount" (favorites.count as string)

			for i = 1 to favorites.count do
				setINISetting INIFile "Favorites" ("Fav" + i as string) (favorites[i].dispName as string + "\t" + favorites[i].filename as string + "\t" + favorites[i].type as string)	
		)
		
		fn loadFromINIFile =
		(
			try (setDialogPos ro_ScriptMan (execute (getINISetting INIFile "Settings" "Position")))catch()
			if getINISetting INIFile "Settings" "FavVisible" != "true" then bnShowHideFav.pressed()
			if getINISetting INIFile "Settings" "Shaded" == "true" then bn_ShadeWin.pressed()
			try (historyLength =  (getINISetting INIFile "Settings" "HistoryItems") as integer)catch()
			if not isKindOf historyLength integer or historyLength < 1 then 
				historyLength = 15


			try (cbShowDirs.state =  (getINISetting INIFile "Settings" "ShowDirs") != "false")catch()
			try (cbShowFiles.state =  (getINISetting INIFile "Settings" "ShowFiles") != "false")catch()
			try (cbShowSubDirs.state = ((getINISetting INIFile "Settings" "ShowSubDirs") != "false"))catch()
			cbShowSubDirs.changed cbShowSubDirs.state
			try (spMaxDepth.value =  (getINISetting INIFile "Settings" "MaxSubDirDepth") as integer)catch()

			local hist = #()
			for i = 1 to historyLength do (
				local d = getINISetting INIFile "History" ("Dir" + i as string)
				if d != "" then
					append hist d
			)

			if hist.count > 0 then
				scriptManRootDirList = hist
			
			local favCount = try((getINISetting INIFile "Favorites" "FavCount") as integer)catch(0)
			for i = 1 to favCount do (
				local f = getINISetting INIFile "Favorites" ("Fav" + i as string)
				if f != "" then (
					
f = filterString f "\t"
					if f.count > 2 then
						append favorites (s_file f[1] f[2] (f[3] as name))
				)
			)
		)
		
		
		fn init =
		(
			if scriptManRootDirList == undefined then
				scriptManRootDirList = #()
			local d = getDir #scripts + "\\"
			addToHistory d
			loadFromINIFile()
			d = scriptManRootDirList[1]
			dlRootDir.items = scriptManRootDirList
			dlRootDir.selection = findItem (for i in dlRootDir.items collect i as name) (d as name)
			getFileList()
			updateUI()
		)
		
		fn done =
		(
			saveToINIFile()
		)
			
		-- Event Handlers
		--------------------------
		on bn_ShadeWin pressed do
		(
			if ro_ScriptMan.height >= 8 then (rolloutHeight = ro_ScriptMan.height; ro_ScriptMan.height = 7)
			else ro_ScriptMan.height = rolloutHeight
		)


		

on dlRootDir selected val do (
			local d = dlRootDir.items[val]
			addToHistory d
			dlRootDir.items = scriptManRootDirList
			dlRootDir.selection = findItem (for i in dlRootDir.items collect i as name) (d as name)

			getFileList()
			updateUI()
		)
		
		on bnRootDirBrowse pressed do (
			local fname = getSavePath()
			if fname != undefined then (
				if fname[fname.count] != "\\" and fname[fname.count] != "/" then
					fname += "\\"
				addToHistory fname
				dlRootDir.items = scriptManRootDirList
				dlRootDir.selection = findItem (for i in dlRootDir.items collect i as name) (fname as name)

				getFileList()
				updateUI()
			)
		)
		
		
on cbShowDirs changed state do (
			getFileList()
			updateUI()
		)

		on cbShowFiles changed state do (
			getFileList()
			updateUI()
		)
		

		on cbShowSubDirs changed state do (
			if state then
				maxDepth = maxRecurseDepth
			else 
				maxDepth = 1
			getFileList()
			updateUI()
		)
		
		on spMaxDepth changed val do (
			maxRecurseDepth = val
			maxDepth = maxRecurseDepth
			getFileList()
			updateUI()
		)



		on edSearchText entered txt do (
			rbShowResults.state = 2 
			searchResults = search txt dlRootDir.selected
			updateUI()
		)

		
		on rbShowResults changed state do (
			updateUI()
		)

		on lbFiles doubleClicked val do (
			if keyboard.controlPressed then (
				fileList[val].exec()
			) else if keyboard.shiftPressed then (
				local f = copy fileList[val]
				f.filename = replaceString f.filename "\\\\" "\\"
				case f.type of (
					#file: f.dispName = "  " + (truncFileDisplay f.filename 175)
					#dir: f.dispName = "<<=  " + (truncFileDisplay f.filename 145) + "  =>>"
				)
				uniqueAppend &favorites f byProp:#filename
				updateUI()
			) else (
				if fileList[val].type == #file then (
					fileList[val].editFile()
				) else if fileList[val].type == #dir then (
					local d = fileList[val].filename
					addToHistory d
					dlRootDir.items = scriptManRootDirList
					dlRootDir.selection = findItem (for i in dlRootDir.items collect i as name) (d as name)
					getFileList()
					lbFiles.selection = 0
					updateUI()	
				)
			)
		)
		
		
		on 
bnShowHideFav pressed do (
			if favVisible then (
				lbFavorites.visible = false
				ro_ScriptMan.height -= 162
			) else (
				lbFavorites.visible = true
				ro_ScriptMan.height += 162
			)
			favVisible = not favVisible
		)
		
		on lbFavorites doubleClicked val do (
			if keyboard.controlPressed then (
				favorites[val].exec()
			) else if keyboard.shiftPressed then (
				deleteItem favorites val
				updateUI()
			) else (
				if favorites[val].type == #file then (
					favorites[val].editFile()
				) else if favorites[val].type == #dir then (
					local d = favorites[val].filename
					addToHistory d
					dlRootDir.items = scriptManRootDirList
					dlRootDir.selection = findItem (for i in dlRootDir.items collect i as name) (d as name)
					getFileList()
					lbFiles.selection = 0
					updateUI()	
				)
			)
		)


		on ro_ScriptMan open do init()
		on ro_ScriptMan close do done()
		
	
	) -- end of ro_ScriptMan rollout
	
	
	try (destroyDialog ro_ScriptMan) catch()
	
	createDialog ro_ScriptMan width:210 style:#(#style_border, #style_titlebar, #style_sysmenu, #style_minimizebox)

) -- end of macroScript  