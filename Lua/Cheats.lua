function CheatsEnabled()
	return mapdata.GameLogic
end

function CheatMapExplore(status)
	if #g_MapSectors == 0 then
		return
	end
	SuspendPassEdits("CheatMapExplore")
	local old = IsDepositObstructed
	IsDepositObstructed = empty_func
	if status == "scan queued" then
		while #g_ExplorationQueue > 0 do
			local sector = g_ExplorationQueue[1]
			sector.scan_progress = sector.scan_progress + sector.scan_time
			UICity:ExplorationTick()
		end
	else
		for x = 1, const.SectorCount do
			for y = 1, const.SectorCount do
				g_MapSectors[x][y]:Scan(status)
			end
		end
	end
	IsDepositObstructed = old
	ResumePassEdits("CheatMapExplore")
end

function CheatSpawnPlanetaryAnomalies()
	local lat, long
	for i = 1, 20 do
		lat, long = GenerateMarsScreenPoI("anomaly")
		local obj = PlaceObject("PlanetaryAnomaly", {
			display_name = T(11234, "Planetary Anomaly"),
			longitude = long,
			latitude = lat,            
		})
	end
end

function CheatBatchSpawnPlanetaryAnomalies()
	UICity:BatchSpawnPlanetaryAnomalies()
end

local function GetCameraLookAtPassable()
	local _, lookat = GetCamera()
	return terrain.IsPassable(lookat) and lookat or GetRandomPassableAround(lookat, 100 * guim)
end

function CheatDustDevil(major, setting)
	local pos = GetCameraLookAtPassable()
	if pos then
		setting = setting or mapdata.MapSettings_DustDevils
		local data = DataInstances.MapSettings_DustDevils
		local descr = setting ~= "disabled" and data[setting] or data["DustDevils_VeryLow"]
		local devil = GenerateDustDevil(pos, descr, nil, major)
		devil:Start()
	else
		print("No passable point around camera look at")
	end
end

function CheatMeteors(meteors_type, setting)
	local pos = GetCameraLookAtPassable()
	if pos then
		setting = setting or mapdata.MapSettings_Meteor
		local data = DataInstances.MapSettings_Meteor
		local descr = setting ~= "disabled" and data[setting] or data["Meteor_VeryLow"]
		CreateGameTimeThread(function()
			MeteorsDisaster(descr, meteors_type, pos)
		end)
	end
end

function CheatStopDisaster()
	Msg("CheatStopDisaster")
end

function CheatResearchAll()
	if not UICity then return end
	for filed_id, list in sorted_pairs(UICity.tech_field) do
		if TechFields[filed_id].discoverable then
			for i=1,#list do
				UICity:SetTechResearched(list[i])
			end
		end
	end
end

function CheatResearchCurrent()
	if not UICity then return end
	UICity:SetTechResearched(false, "notify")
end

function CheatCompleteAllWiresAndPipes(list)
	SuspendTerrainInvalidations("cheat_wires_and_pipes")
	MapForEach("map", "ConstructionGroupLeader",
		function(obj)
			if obj.building_class ~= "LifeSupportGridElement" and
				obj.building_class ~= "ElectricityGridElement"
			then
				return
			end
			obj:Complete("quick_build")
		end)
	ResumeTerrainInvalidations("cheat_wires_and_pipes")
end

local function CompleteBuildConstructionSite(site)
	if not GameInitThreads[site] and (not site.construction_group or site.construction_group[1] == site) then
		site:Complete("quick_build")
	end
end
function CheatCompleteAllConstructions()
	SuspendTerrainInvalidations("cheat_all_constructions")
	CheatCompleteAllWiresAndPipes()
	--Repeat the whole procedure twice to make sure
	--buildings with second stages (domes) are completed
	for i=1,2 do
		MapForEach("map", "ConstructionSite", CompleteBuildConstructionSite)
	end
	ResumeTerrainInvalidations("cheat_all_constructions")
end

local l_add_funding = 500000000
function CheatAddFunding(funding)
	if UICity then
		UICity:ChangeFunding(funding or l_add_funding)
	end
end

function CheatChangeMap(map)
	if Platform.developer then
		CreateRealTimeThread(function()
			CloseAllDialogs()
			--wait for paradox account wizard to open the pregame menu
			Sleep(1)
			CloseMenuDialogs()
			ChangeMap(map)
			LocalStorage.last_map = map
			SaveLocalStorage()
		end)
	end
end

function CheatUnlockAllTech()
	if not UICity then return end
	for filed_id, list in sorted_pairs(UICity.tech_field) do
		if TechFields[filed_id].discoverable then
			for i=1,#list do
				UICity:SetTechDiscovered(list[i])
			end
		end
	end
end

function CheatUnlockAllBuildings()
	for _, template in pairs(BuildingTemplates) do
		local category = template.build_category
		if not BuildMenuPrerequisiteOverrides[category] then
			BuildMenuPrerequisiteOverrides[category] = true
		end
	end
end

function CheatToggleAllShifts()
	local blds = UICity.labels.ShiftsBuilding
	if #blds == 0 then return end
	local open = blds[1]:IsClosedShift(1)
	for i, bld in ipairs(blds) do
		for k = 1,bld.max_shifts do
			if open then
				bld:OpenShift(k)
			else
				bld:CloseShift(k)
			end
		end
	end
	if open then
		CheatUpdateAllWorkplaces()
	end
end

function CheatUpdateAllWorkplaces()
	UpdateWorkplaces(UICity.labels.Colonist)
end

function CheatClearForcedWorkplaces()
	for i, col in ipairs(UICity.labels.Colonist) do
		col.user_forced_workplace = nil
	end
end

function CheatUnlockBreakthroughs()
	local anomalies = 0
	local function reveal(anomaly)
		if not IsValid(anomaly) or anomaly.tech_action ~= "breakthrough" then return end
		anomaly:SetRevealed(true)
		anomaly:ScanCompleted(false)
		DoneObject(anomaly)
		anomalies = anomalies + 1
	end
	MapForEach("map", "SubsurfaceAnomalyMarker", function(marker)
			reveal(marker:PlaceDeposit())
			DoneObject(marker)
		end)
	MapForEach("map" , "SubsurfaceAnomaly", reveal)
	print(anomalies, "breakthroughs technologies have been unlocked")
end

function CheatToggleInfopanelCheats()
	config.BuildingInfopanelCheats = not config.BuildingInfopanelCheats
	ReopenSelectionXInfopanel()
end

GamepadCheatsList = {
	{ display_name = T(7790, "Research Current Tech"),      					func = CheatResearchCurrent },
	{ display_name = T(7791, "Research all Techs"),         					func = CheatResearchAll },
	{ display_name = T(7792, "Unlock all Techs"),           					func = CheatUnlockAllTech },
	{ display_name = T(7793, "Unlock all Breakthroughs"),   					func = CheatUnlockBreakthroughs },
	{ display_name = T(7794, "Construct all buildings"),    					func = CheatCompleteAllConstructions },
	{ display_name = T(7795, "Add funding ($500,000,000)"), 					func = CheatAddFunding },
	{ display_name = T(7796, "Spawn 1 Colonist"),           					func = function() CheatSpawnNColonists(1) end },
	{ display_name = T(7797, "Spawn 10 Colonists"),         					func = function() CheatSpawnNColonists(10) end },
	{ display_name = T(7798, "Spawn 100 Colonists"),        					func = function() CheatSpawnNColonists(100) end },
	{ display_name = T(12266, "Stop Disaster"),				        					func = function() CheatStopDisaster() end },
	{ display_name = T(12267, "Unlock All SponsorBuildings"),		  					func = function() CheatUnlockAllSponsorBuildings() end },
	{ display_name = T(12268, "Unlock All Buildings"),				  					func = function() CheatUnlockAllBuildings() end },
	{ display_name = T(12269, "Max All Terraforming Parameters"),	  					func = function() for param in pairs(Terraforming) do SetTerraformParamPct(param, 100) end end },
	{ display_name = T(12270, "Increase Soil Quality by 25%"),	  					func = function() dbg_ChangeSoilQuality(25) end },
	{ display_name = T(12271, "Decrease Soil Quality by 25%"),	  					func = function() dbg_ChangeSoilQuality(-25) end },
	{ display_name = T(12272, "TP Atmosphere +10%"),	  				  					func = function() SetTerraformParamPct("Atmosphere"	, 10 + GetTerraformParamPct("Atmosphere")) end },
	{ display_name = T(12273, "TP Water +10%"),	  					  					func = function() SetTerraformParamPct("Water"			, 10 + GetTerraformParamPct("Water")) end },
	{ display_name = T(12274, "TP Temperature +10%"),	 			  					func = function() SetTerraformParamPct("Temperature"	, 10 + GetTerraformParamPct("Temperature")) end },
	{ display_name = T(12275, "TP Vegetation +10%"),	  				  					func = function() SetTerraformParamPct("Vegetation"	, 10 + GetTerraformParamPct("Vegetation")) end },
	{ display_name = T(12276, "Increase all Terraforming Parameters by 10%"),	   func = function() for param in pairs(Terraforming) do SetTerraformParamPct(param, 10 + GetTerraformParamPct(param))  end end },
	{ display_name = T(12277, "Decrease all Terraforming Parameters by 10%"),	   func = function() for param in pairs(Terraforming) do SetTerraformParamPct(param, -10 + GetTerraformParamPct(param)) end end },	
	}

function OnMsg.ChangeMap(map)
	if not Platform.developer then
		if map == "Mod" then
			print("Press Enter to execute arbitrary Lua code.")
			print("Press F9 to clear this log.")
			ConsoleSetEnabled(true)
		else
			ConsoleSetEnabled(false)
		end
	end
end

function MultiCheat()
	CheatUnlockAllBuildings()
	if g_AvailableDlc["gagarin"] then
		CheatUnlockAllSponsorBuildings()
	end
	CheatMapExplore("deep scanned")
	CheatResearchAll()
end