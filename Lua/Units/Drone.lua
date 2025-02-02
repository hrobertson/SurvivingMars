DefineClass.Drone =
{
	__parents = { "DroneBase", "Shapeshifter", "ComponentAttach", "PinnableObject", "Demolishable", "SkinChangeable" },
	SelectionClass = "Drone",
	display_name_pl = T(517, "Drones"),
	
	properties = {
		{ category = "Drone", name = T(4388, "Drone Battery Capacity"), id = "battery_max",       default = const.DroneBatteryMax, scale = 100, editor = "number", modifiable = true },
		{ category = "Drone", name = T(666, "Freeze Time"),            id = "freeze_time", default = const.DefaultFreezeTime, editor = "number", modifiable = true },
		{ category = "Drone", name = T(667, "Freeze Heat"),            id = "freeze_heat", default = const.DefaultFreezeHeat, editor = "number", min = 0, max = const.MaxHeat, slider = true, modifiable = true },
		{ category = "Drone", name = T(4389, "Freeze Chance Die"),      id = "freeze_chance_die", default = 10, editor = "number", modifiable = true },
		{ id = "CommandCenter", editor = "object", default = false, no_edit = true },
	},
	
	entity = "DroneMaintenance",
	default_skins = { "DroneMaintenance", "DroneMiner", "DroneWorker" },
	command_center = false,
	pfclass = 2,
	radius = 120*guic,
	collision_radius = 120*guic,
	dust_max = const.MaxMaintenance,
	battery = false,
	repair_drone = false,
	follow_camera_vertical_offset = 20 * guim,
	
	move_speed = 1440,
	resource = false,
	amount = 0,
	target = false,
	s_request = false,
	d_request = false,
	w_request = false,
	picked_up_from_req = false,
	request_amount = 0,

	display_name = T(1681, "Drone"),
	description = T(4390, "An automated unit controlled by a Drone Hub, Rocket or RC Commander. Gathers resources, constructs buildings and performs maintenance."),
	display_icon = "UI/Icons/Buildings/drone.tga",
	
	-- pin section
	pin_rollover = T(4391, "<description><newline><newline>Current status: <em><ui_command></em><newline>Battery<right><power(battery,battery_max)>"),
	pin_summary1 = "",
	pin_progress_value = "battery",
	pin_progress_max = "battery_max",
	pin_on_start = false,
	is_orphan = false, --no command centr
	is_disabled = false, --disabled drones cannot be controlled by users
	is_broken = false, --broken drones put out a notification
	
	force_go_home = false,
	
	queued_at_recharger = false,
	going_to_recharger = false,
	
	rogue = false,
	rogue_target = false,
	rogue_intercepted = false,
	rogue_shoot_range = 20*guim,
	rogue_shoot_chance = 20, -- chance a defending colonist to succesfully shoot it
	
	idle_wait = false,
	encyclopedia_id = "Drone",
	
	rogue_attack_colonist_chance = 50,
	ip_template = "ipDrone",
	
	unreachable_buildings = false,
	unreachable_buildings_count = 0,
	
	fx_actor_base_class = "Drone",
	delivery_state = false,
}

GlobalGameTimeThread("OrphanedDronesNotif", function()
	HandleNewObjsNotif(g_OrphanedDrones, "OrphanedDrones")
end)

local Sleep = Sleep

function SavegameFixups.IncrementDroneSpeedByTwentyPercent()
	MapForEach(true, "Drone", 
		function(o)
					o:SetBase("move_speed", 1440)
				end)
end

function Drone:Init()
	self:SetState("idle")
	self:SetMoveSpeed(self.move_speed)
	self:SetMoveAnim("moveWalk")
	self:GenerateDustMalfunctionThreshold()
end

function Drone:GameInit()
	self:AddToLabels()

	if GetMissionSponsor().id == "SpaceY" and self.city.day < 100 and #self.city.labels.Drone >= AchievementPresets.SpaceYBuiltDrones.target then
		AchievementUnlock(XPlayerActive, "SpaceYBuiltDrones")
	end
	
	self.battery = self.battery or (self.battery_max / 2 + AsyncRand(self.battery_max / 2))
	
	if self.command_center then
		self:Gossip("new", self.command_center:GossipName(), self.command_center.handle)
	else
		--no dcc was passed during creation, supply drop most likely.
		self:Gossip("new", "no cc")
	end
	-- choose name
	if self.name == "" then
		self.name = GenerateMachineName("Drone")
	end
end

function Drone:PostLoad()
	local command_center = self.command_center
	self:SetCommandCenter(false)
	if command_center then
		self:SetCommandCenter(command_center)
	end
end

function UpdateRogueNotification()
	local list = UICity.labels.RogueDrones or empty_table
	
	if #list > 0 then
		AddOnScreenNotification("Mystery5RogueDrones", nil, {count = #list}, list)	
	else
		RemoveOnScreenNotification("Mystery5RogueDrones")
	end
end

function Drone:Done()
	self:Gossip("done")
	self:RemoveFromLabels()
	
	if self.is_orphan then
		table.remove_entry(g_OrphanedDrones, self)
	elseif self.command_center and IsValid(self.command_center) then
		local hub = self.command_center
		table.remove_entry(hub.drones, self)
		if IsKindOf(hub, "RCRover") then
			table.remove_entry(hub.attached_drones, self)
			if hub.guided_drone == self then
				hub.guided_drone = false
			end
		end
	end
	if self.is_broken then
		table.remove_entry(g_BrokenDrones, self)
	end
	
	table.remove_entry(g_DestroyedVehicles, self)
end

function Drone:RemoveFromLabels()
	self.city:RemoveFromLabel("Unit", self)
	self.city:RemoveFromLabel("Drone", self)
	assert(not table.find(self.city.labels.Drones, self), "drone still in label after removal")
	if self.rogue then
		self.city:RemoveFromLabel("RogueDrones", self)
		UpdateRogueNotification()
	end
end

function Drone:AddToLabels()
	self.city:AddToLabel("Unit", self)
	assert(not table.find(self.city.labels.Drones, self), "drone double adding to label")
	self.city:AddToLabel("Drone", self)
	if self.rogue then
		self.city:AddToLabel("RogueDrones", self)
		UpdateRogueNotification()
	end
end

function OnMsg.GatherLabels(labels)
	labels.Unit = true
	labels.Drone = true
end

function Drone:UpdateMoving()
	if #self.city.labels.Drone < 150 then
		DroneBase.UpdateMoving(self)
	else
		local fx_moving_target = self.fx_moving_target
		if fx_moving_target then
			self.fx_moving_target = false
			PlayFX("Moving", "end", self, fx_moving_target)
		end
	end
end

function Drone:TryFindNewCommandCenter()
	return MapFindNearest(self, self, "hex", const.CommandCenterMaxRadius, "DroneControl", 
								function (center, search_requestor)
									if center.working and center:CanHaveMoreDrones() and HexAxialDistance(center, search_requestor) <= center.work_radius then
										return true
									end
								end, self)
end

GlobalVar("g_OrphanedDrones", {})
GlobalVar("g_BrokenDrones", {}) --keeps track of all drones that need repair.

local DroneEntities = {
	command_center_type = {
		RCRover = "DroneMaintenance",
		DroneHub = "DroneMaintenance",
	},
	
	default = "DroneMaintenance",
}

function Drone:PickEntity()
	local new_entity = DroneEntities.default
	
	local cmd = self.command_center
	if cmd then
		new_entity = next(cmd.drones) and cmd.drones[1]:GetEntity() or DroneEntities.command_center_type[cmd.class]
	end
	
	if new_entity ~= self:GetEntity() then
		assert(IsValidEntity(new_entity))
		self:ChangeEntity(new_entity)
	end
end

function Drone:GetCommandCenter()
	return self.command_center
end

function SavegameFixups.ResetRestrictRadiusForDrones()
	MapForEach("map", "Drone", function(d)
		if d.command_center and d.command ~= "Embark" then
			d:RestrictArea(d.command_center:GetPos(), const.DroneRestrictRadius)
		end
	end)
end

function Drone:SetCommandCenter(command_center, do_not_orphan)
	local should_change_cmd = command_center and not self.command_center and self.command == "WaitingCommand"
	if command_center and not command_center[true] then -- when loading
		self.command_center = command_center
		return
	end
	if IsValid(self.command_center) then
		table.remove_entry(self.command_center.drones, self)
	elseif self.is_orphan then
		self.is_orphan = false
		table.remove_entry(g_OrphanedDrones, self)
	end
	
	self.command_center = command_center
	if command_center then
		table.insert(command_center.drones, self)
		self:RestrictArea(command_center:GetPos(), const.DroneRestrictRadius)
	elseif not self:IsDead() and not do_not_orphan then --dead drones cannot be orphans.
		--just became orphan.
		self.is_orphan = true
		table.insert(g_OrphanedDrones, self)
		self:RestrictArea(point30, 0)
	end
	
	if not self:IsDead() then
		self:PickEntity()
		assert(self:GetParent() == nil or self:GetParent() == command_center, "Drone is attached to the wrong command center")
		if should_change_cmd then
			self:SetCommand("GoHome", nil, nil, nil, "ReturningToController") --returns if in cmd thread!!
		end
	end
end

function Drone:CanBeThawed() --i.e. can be repaired when frozne
	return not g_ColdWave or GetHeatAt(self) >= const.DefaultFreezeHeat
end

function Drone:FindDroneToRepair()
	local closest_drone
	local command_center = self.command_center
	local best_dist = command_center.work_radius + 1
	local rem
	assert(command_center)
	for _, drone in ipairs(g_BrokenDrones) do
		if IsValid(drone) then
			if not drone.repair_drone --nobody is currently repairing him
				and drone.command ~= "Dead"
				and (drone.command ~= "Freeze" or drone:CanBeThawed())	then 
				local dist = HexAxialDistance(drone, self)
				if dist < best_dist then
					closest_drone = drone
					best_dist = dist
				end
			end
		else
			rem = rem or {}
			table.insert(rem, drone)
		end
	end
	
	for i = 1, #(rem or "") do
		table.remove_entry(g_BrokenDrones, rem[i])
	end
	return closest_drone
end

local DelayAfterUserCommands = {
	Goto = const.DroneTimeAfterUserGotoToRest,
	UseTunnel = const.DroneTimeAfterUserGotoToRest,
	GotoFromUser = const.DroneTimeAfterUserGotoToRest,
	PickUp = const.DroneTimeAfterUserPickUpToRest,
	DropCarriedResource = const.DroneTimeAfterUserPickUpToRest
}

-- rogue drones
function Drone:GoRogue()
	if self.rogue or self:GetParent() or self:IsDisabled() then
		return
	end
	self.city:AddToLabel("RogueDrones", self)
	UpdateRogueNotification()
	self.rogue = true

	self:SetCarriedResource(false)
	
	if IsValid(self.command_center) then
		table.remove_entry(self.command_center.drones, self)
		self.command_center = nil
	end
	
	self:SetMoveAnim("rogueWalk")
	self:SetWaitAnim("rogueIdle")
		
	local sign = AttachToObject(self, "UnitSignRogue", "Origin")
	sign:SetVisible(true)
	sign:SetScale(const.SignsOverviewCameraScaleDown)
	
	self.MoveSleep = self.RogueMoveSleep

	RebuildInfopanel(self)
end

function Drone:RogueRevertToNormal()
	if not self.rogue or self:IsDead() then
		return
	end
	self.city:RemoveFromLabel("RogueDrones", self)
	UpdateRogueNotification()
	self.rogue = nil
	self:SetMoveAnim("moveWalk")
	self:SetWaitAnim("idle")
	
	local signs = self:GetAttaches("UnitSignRogue")
	for i = 1, #signs do
		DoneObject(signs[i])
	end
	self:SetCommandCenter(false)
	RebuildInfopanel(self)
end

function Drone:RogueWander()
	local dist = self:Random(10*guim, 20*guim)
	local angle = self:Random(360*60)
	local pt = GetPassablePointNearby(RotateRadius(dist, angle, self:GetPos()), self.pfclass)
	if pt then
		self:Goto(pt)
	end
end

function IsObjectVisibleFromPoint(obj, look_pos)
	-- todo: replace with straight-line passability check
	
	local pos = obj:IsValidPos() and obj:GetVisualPos() + point(0, 0, guim)
	if pos then
		local any_collide, collision_pos, collision_obj = CollideSegmentsObj(look_pos, pos)
		if not any_collide or collision_pos == InvalidPos() or collision_obj == obj then
			return true
		end
	end
	return false
end

function CanShootRogueDrone(unit, drone, ignore_command)
	if unit:IsDying() or (not ignore_command and unit.command == "InterceptRogueDrone") then
		return false
	end
	if unit:IsVisitingBuilding() or unit:GetVisualDist2D(drone) > drone.rogue_shoot_range or GetDomeAtPoint(unit) ~= GetDomeAtPoint(drone) then
		return false
	end
	return IsObjectVisibleFromPoint(drone, unit:GetVisualPos() + point(0, 0, 180*guic))
end

function Drone:RogueAlertSecurity(target)
	if IsKindOf(target, "Colonist") and target.traits.security and CanShootRogueDrone(target, self) then
		target:SetCommand("InterceptRogueDrone", self)
	end

	local domes = self.city.labels.Dome or empty_table
	for i = 1, #domes do
		local dome = domes[i]
		local dist = dome:GetOutsideWorkplacesDist()
		
		local stations = domes[i].labels.SecurityStation or empty_table
		for j = 1, #stations do
			local station = stations[j]
			if station.working then
				-- intercept
				if not self.rogue_intercepted[dome] and HexAxialDistance(self, dome) <= dist then
					local workers = station:GetWorkingWorkers() -- workers currently in Work or WorkCycle command
					if #workers > 0 then
						local unit = self.city:TableRand(workers)						
						unit:SetCommand("InterceptRogueDrone", self, dome, dist, true)
						return
					end
				end
				
				-- additionally, check if the drone entered the line of sight of a worker
				for _, shift in ipairs(station.workers) do
					for _, unit in ipairs(shift) do
						if CanShootRogueDrone(unit, self) then
							unit:SetCommand("InterceptRogueDrone", self, dome, dist)
						end
					end
				end				
			end
		end
		
		-- additionally, check if the drone entered the line of sight of a trained security
		local security = dome.labels.security or empty_table
		for i = 1, #security do
			local unit = security[i]
			if CanShootRogueDrone(unit, self) then
				unit:SetCommand("InterceptRogueDrone", self, dome, dist)
			end
		end
	end
end

function Drone:RogueMoveSleep(...)
	DroneBase.MoveSleep(self, ...)
	local target = self.rogue_target
	self:RogueAlertSecurity(target)
	
	local is_unit = IsKindOf(target, "Colonist")
	local is_building = IsKindOf(target, "Building")
	if (is_unit and (target:IsDying() or target:IsVisitingBuilding())) or is_building and target.destroyed then
		self:SetCommand("Idle")
	end			
end

function Drone:RogueAttack(target)
	if not IsValid(target) then
		-- pick a target
		local target_label = self:Random(100) < self.rogue_attack_colonist_chance and "Colonist" or "Life-Support"
		local list = self.city.labels[target_label] or empty_table
		
		if #list == 0 then
			return self:RogueWander()
		end
		
		if target_label == "Life-Support" then
			local constructions = self.city.labels[target_label .. g_ConstructionSiteLabelSuffix]
			if #constructions >= #list then --no non constructions
				return self:RogueWander()
			end
			
			--find non construction site
			local idx = 1 + self.city:Random(#list)
			while IsKindOf(list[idx], "ConstructionSite") do
				idx = idx + 1
				if idx > #list then idx = 1 end
			end
			
			target = list[idx]
		else
			target = self.city:TableRand(list)
		end
	end
	if not IsValid(target) then
		return
	end
	self.rogue_intercepted = self.rogue_intercepted or {}
	self:StartMoving()
	self:PushDestructor(function(self)
		 self.rogue_target = nil
	end)
	self.rogue_target = target
	
	self:ExitHolder(target)
	self:Goto(target, 2*guim, 0)
	self:PopAndCallDestructor()
	
	local is_unit = IsKindOf(target, "Colonist")
	local is_building = IsKindOf(target, "Building")
	if not IsValid(target) or is_unit and target:IsDying() or is_building and target.destroyed then
		return
	end	
	
	if is_unit then
		-- sanity check: range
		if HexAxialDistance(self, target) > 1 then
			return
		end
		
		self:Face(target)
		self:SetAnim(1, "rogueAttack")
		target:SetCommand("AttackedByDrone", self)
		Sleep(self:TimeToAnimEnd())
		local current_dome = IsUnitInDome(target)
		if IsValid(current_dome) then
			current_dome:AddPanicMarker(target:GetPos(), 15*guim, 3*const.HourDuration)
		end
	else
		-- sanity check: range
		local shape = GetEntityOutlineShape(target:GetEntity())
		local in_range = false
		local angle = target:GetAngle()
		local origin = target:GetPos()
		for i = 1, #shape do
			-- calc the distance to the center of a hex, see if we're in range
			local q, r = shape[i]:xy()
			local x, y = HexToWorld(q, r)
			local dir = Rotate(point(x, y), angle)
			local pt = origin + dir						
			
			if HexAxialDistance(self, pt) < 2 then
				in_range = true
				break
			end
		end
		if not in_range then
			return
		end
	
		PlayFX("DroneExplode", "start", self)
		DestroyBuildingImmediate(target)
		self:SetCommand("Dead")
	end
end

function Drone:CanDemolish()
	return not g_Tutorial and self.can_demolish and (not self.rogue or self:IsDead())
end

function Drone:Idle()
	if self:GetParent() then
		assert(false)
		self:SetCommand("Embark")
	end
	self:ResetUnitControlInteractionState() --if we made it to idle any interaction we may have had is over.
	Sleep(10)
	local force_go_home = self.force_go_home
	self.force_go_home = false
	
	self:SetColorModifier(RGB(100, 100, 100))
	self:SetState("idle")
	
	Sleep(self.idle_wait or -1) -- -1 means immediate return
	
	if self.rogue then
		self:SetCommand("RogueAttack")
	end
	
	local command_center = self.command_center
	if not IsValid(command_center) then
		self:SetCommand("WaitingCommand")
	end
	--
	if self.resource then --we are carrying something.
		self:SetCommand("Deliver")
	else
		self.picked_up_from_req = false
	end
	-- repair command_center
	if command_center:IsMalfunctioned() and not IsKindOf(command_center, "RCRover") then
		if command_center.maintenance_phase == "demand" and command_center.maintenance_resource_request:CanAssignUnit() then
			--resource needs to be delivered.
			local req = command_center.maintenance_resource_request
			local supply_request, r_amount = command_center:FindSupplyRequest(self, req:GetResource(), req:GetTargetAmount())
			if supply_request then
				self:SetCommand("PickUp", supply_request, req, req:GetResource(), r_amount)
			end
		elseif command_center.maintenance_phase == "work" and command_center.maintenance_work_request:CanAssignUnit() then
			--work remains 2 be done
			self:SetCommand("Work", command_center.maintenance_work_request, "repair", Min(DroneResourceUnits.repair, command_center.maintenance_work_request:GetTargetAmount()))
		end
	end
	-- recharge if close to emergency power
	if self.battery <= g_Consts.DroneEmergencyPower * 2 then
		self:SetCommand("EmergencyPower")
	end
	
	if command_center.working then
		-- repair broken drones
		local nearest_broken = self:FindDroneToRepair()
		if nearest_broken then
			nearest_broken.repair_drone = self --so the next query returns a different drone
			self:SetCommand("RepairDrone", nearest_broken, g_Consts.DroneEmergencyPower) --returns
		end
		-- find work
		if GameTime() - command_center.no_requests_time > 1000 then
			local request, pair_request, resource, amount = command_center:FindTask(self)
			assert(not pair_request or request, "pair request without request")
			if request then
				assert(IsValid(request:GetBuilding(), "Request from destroyed obj!"))
				if request:IsAnyFlagSet(const.rfWork) then
					self:SetCommand("Work", request, resource, amount)
				else
					self:SetCommand("PickUp", request, pair_request, resource, amount)
				end
			elseif self.unreachable_buildings_count <= 0 then
				command_center.no_requests_time = GameTime()
			end
		end
	end
	-- stay close to the command_center
	if force_go_home or not self:IsCloser2D(command_center, command_center.distance_to_provoke_go_home_cmd) then
		self:SetCommand("GoHome", nil, nil, nil, "ReturningToController")
	end
	Sleep(2000)
	self:CleanUnreachables()
end

function Drone:GoHome(min, max, pos, ui_str_override)
	min = min or 30 * guim
	max = max or 50 * guim
	self.override_ui_status = ui_str_override
	self:PushDestructor(function(self)
		self.override_ui_status = nil
	end)	
	local command_center = self.command_center
	if SelectedObj == command_center and not HasSelectionArrow(self) then
		SelectionArrowAdd(self)
	end
	self:ExitHolder(command_center)
	pos = pos or command_center:GetPos()
	pos = self:GoToRandomPos(max, min, pos, function(...) 
														return GetPointOutsideDomes(...) and IsBuildableZone(...)
													end)
	if not pos then
		self:GoToRandomPos(max, min, pos, GetPointOutsideDomes) --go in hollow rocks
		if not pos then --stuck drone
			Sleep(1000)
		end
	end
	self:PopAndCallDestructor()
end

function SavegameFixups.ReOrphanDrones()
	MapForEach("map", "Drone", function(o)
		if o.command == "WaitingCommand" and
			not o.is_orphan then
			o.is_orphan = true
			table.insert(g_OrphanedDrones, o)
			o:SetCommand("WaitingCommand")
		end
	end)
end

function Drone:OnStartWaitingCommand()
end

function Drone:WaitingCommand() --orphanned drone command, not broken drones without command center should have this command.
	assert(self.command_center == false or not IsValid(self.command_center))
	local new_dcc = self:TryFindNewCommandCenter()
	if new_dcc then
		self:SetCommandCenter(new_dcc)
		return
	end
	self:OnStartWaitingCommand()
	self:StartFX("WaitingCommand")
	self:PushDestructor(function(self)
		if IsValid(self) and not self:IsDead() then
			self:SetColorModifier(RGB(100, 100, 100))
		end
	end)
	self:SetColorModifier(RGB(60, 60, 60))
	self:SetState("idle")
	assert(self.is_orphan)
	Halt()
end

if FirstLoad then
	DroneResourceUnits = setmetatable({}, { __index = function(self, key)
		return rawget(self, key) or const.ResourceScale
	end})
	ResourceUnits = DroneResourceUnits
end

function UpdateDroneResourceUnits()
	local rdesc = ResourceDescription
	local runits = DroneResourceUnits
	runits.construct = g_Consts.DroneConstructAmount
	runits.clean = g_Consts.DroneCleanAmount
	runits.repair = g_Consts.DroneBuildingRepairAmount
	runits.transform_to_waste_rock = g_Consts.DroneTransformWasteRockObstructorToStockpileAmount
	runits.deconstruct = g_Consts.DroneDeconstructAmount
	runits.mine = 1
	for i = 1,#rdesc do
		local desc = rdesc[i]
		runits[desc.name] = (desc.unit_amount or const.ResourceScale) * g_Consts.DroneResourceCarryAmount
	end
end

OnMsg.NewMap = UpdateDroneResourceUnits
OnMsg.ConstValueChanged = UpdateDroneResourceUnits
OnMsg.LoadGame = UpdateDroneResourceUnits

function Drone:ContinuousTask(request, amount, battery_use, anim_start, anim_idle, anim_end, fx, functor, use_spot_facing)
	local building = request:GetBuilding()
	if not IsValid(building) then return end --building got destroyed en route
	if not use_spot_facing then
		local whom_to_face = IsKindOf(building, "ConstructionGroupLeader") and FindNearestObject(building.construction_group, self:GetPos():SetInvalidZ()) or building
		self:Face(whom_to_face, 100)
	end
	self:UseBattery(battery_use)
	if fx then
		self:StartFX(fx, building)
	end
	self:PlayState(anim_start or "constructStart")
	self:SetState(anim_idle or "idle")
	while IsValid(building) do
		local subtract = request:GetActualAmount()
		if subtract <= 0 then
			break
		elseif subtract > amount then
			subtract = amount
		end
		request:AddAmount(-subtract)
		if functor then
			functor(self, request, subtract)
		end
		self:UseBattery(battery_use)
		Sleep(1000)
	end
	if fx then
		self:StopFX()
	end
	self:PlayState(anim_end or "constructEnd")
end

function Drone:ImproveDemandRequest(s_request, d_request, resource, amount, must_change)
	local command_center = self.command_center
	local d_building = d_request:GetBuilding()
	local priority, d_request2
	if IsValid(d_building) then
		priority = d_building:GetPriorityForRequest(d_request) + 1
	else
		must_change = true
	end
	if command_center and command_center.working then
		local ignore_flags = band(bnot(d_request:GetFlags()), const.rfSpecialDemandPairing + const.rfSpecialSupplyPairing)
		d_request2 = command_center:FindDemandRequest(self, resource, amount, priority, ignore_flags)
	end
	
	local req_to_improve = d_request2 or d_request
	local assigned = true
	if req_to_improve:GetResource() ~= "WasteRock" and band(req_to_improve:GetFlags(), const.rfStorageDepot) == const.rfStorageDepot 
		and (not s_request or band(s_request:GetFlags(), const.rfStorageDepot) == 0) then
		if not d_request2 then --unassign from d_req so improve storage dmnd works correctly for the depot the req belongs to
			req_to_improve:UnassignUnit(amount, false)
			assigned = false
		end
		local improved_req = ImproveStorageDemandRequest(self, amount, req_to_improve)
		
		if improved_req ~= req_to_improve then
			d_request2 = improved_req
		end
	end
	
	if d_request2 and d_request2:AssignUnit(amount) then
		if assigned then
			d_request:UnassignUnit(amount, false)
		end
		return d_request2
	end
	if must_change then
		if assigned then
			d_request:UnassignUnit(amount, false)
		end
		return
	else
		if not assigned then
			if not d_request:AssignUnit(amount) then
				return
			end
		end
		return d_request
	end
end

const.MaxUnreachablesInTable = 4 --will keep up to this much unreachables
--capture unreachable buildings with this wrapper
function Drone:ApproachWrapper(building, resource)
	if not IsValid(building) or not building:IsValidPos() then
		return
	end
	local result = building:DroneApproach(self, resource)
	if not result then
		local unreachable_buildings = self.unreachable_buildings or setmetatable({version = g_DroneUnreachablesVersion}, weak_keys_meta)
		if self.unreachable_buildings_count >= const.MaxUnreachablesInTable then
			--kick oldest
			local min_time = max_int
			local min_id = false
			for id, ts in pairs(unreachable_buildings or empty_table) do
				if not min_id or ts < min_time then
					min_id = id
					min_time = ts
				end
			end
			unreachable_buildings[min_id] = nil
			self.unreachable_buildings_count = self.unreachable_buildings_count - 1
		end
		
		unreachable_buildings[building] = GameTime()
		self.unreachable_buildings_count = self.unreachable_buildings_count + 1
		self.unreachable_buildings = unreachable_buildings
		if IsKindOf(building, "ConstructionSite") and self.command_center then
			self.command_center:UpdateConstructions()
		end
	end
	
	return IsValid(building) and result
end

GlobalVar("g_DroneUnreachablesVersion", 0)
const.UnreachablesCleanupDeltaT = const.DayDuration * 3 --about how long will a bld stay in the unreachable table

function BumpDroneUnreachablesVersion()
	g_DroneUnreachablesVersion = g_DroneUnreachablesVersion + 1
end

function Drone:ResetUnreachablesTable()
	self.unreachable_buildings = setmetatable({version = g_DroneUnreachablesVersion}, weak_keys_meta)
	self.unreachable_buildings_count = 0
end

function Drone:CleanUnreachables()
	local t = self.unreachable_buildings
	if not t then
		return
	elseif (t.version or -1) ~= g_DroneUnreachablesVersion then
		self:ResetUnreachablesTable()
		return
	end
	
	local dt = const.UnreachablesCleanupDeltaT
	local now = GameTime()
	for id, ts in pairs(t or empty_table) do
		if id ~= "version" and now - ts >= dt then
			self.unreachable_buildings[id] = nil
			self.unreachable_buildings_count = self.unreachable_buildings_count - 1
		end
	end
end

function Drone:Work(request, resource, amount)
	local building = request:GetBuilding()
	if not request:AssignUnit(amount) then
		Sleep(1000)
		return
	end
	self:PushDestructor(function(self)
		self.w_request:UnassignUnit(self.request_amount, false)
		self.w_request = false
		self.resource = false
		self.amount = false
		self.target = false
		self.override_ui_status = nil
	end)
	self.w_request = request
	self.request_amount = amount
	self.resource = resource
	self.amount = amount
	self.target = building
	self.override_ui_status = building:GetUIStatusOverrideForWorkCommand(request, self)
	RebuildInfopanel(self)
	if not self:ApproachWrapper(building, resource) or not request:Fulfill(amount) then
		self:PopAndCallDestructor()
		Sleep(1000)
		return
	end
	RebuildInfopanel(self)

	self:PopDestructor()
	self:PushDestructor(function(self)
		self.w_request:UnassignUnit(self.request_amount, true)
		self.w_request = false
		self.resource = false
		self.amount = false
		self.target = false
		self.override_ui_status = nil
	end)
	building:DroneWork(self, request, resource, amount)
	self:PopAndCallDestructor()
end

function Drone:PickUp(s_request, d_request, resource, amount, dont_chain_deliver)
	if not s_request:AssignUnit(amount) then
		Sleep(1000)
		return
	end

	if d_request and not d_request:AssignUnit(amount) then
		s_request:UnassignUnit(amount, false)
		Sleep(1000)
		return
	end

	self.s_request = s_request
	self.d_request = d_request
	self.request_amount = amount

	self:PushDestructor(function(self)
		self.s_request:UnassignUnit(self.request_amount, false)
		self.s_request = false
		local d_request = self.d_request
		if d_request then -- we never picked up the resource, free up the demand req.
			d_request:UnassignUnit(self.request_amount, false)
			self.d_request = false
		end
		self.target = false
		self.request_amount = 0
	end)

	-- go to source location & load
	local s_building = s_request:GetBuilding()
	self.target = s_building
	RebuildInfopanel(self)
	if not self:ApproachWrapper(s_building, resource) or not s_request:Fulfill(amount) then
		self:PopAndCallDestructor()
		RebuildInfopanel(self)
		Sleep(1000)
		return
	end

	self:PopDestructor()
	self:PushDestructor(function(self)
		local s_request = self.s_request
		s_request:UnassignUnit(self.request_amount, true)
		if not self.amount or not self.resource then --we fullfilled the req, but we havn't picked up the stuff..
			s_request:AddAmount(self.request_amount)
		end
		self.s_request = false

		local d_request = self.d_request
		if d_request then --we never picked up the resource, free up the demand req.
			d_request:UnassignUnit(self.request_amount, false)
			self.d_request = false
		end
		self.target = false
		self.request_amount = 0
	end)

	-- load animation
	self.target = false
	RebuildInfopanel(self)
	s_building:DroneLoadResource(self, s_request, resource, amount)

	self:PopDestructor()

	s_request:UnassignUnit(amount, true)
	self.picked_up_from_req = self.s_request
	self.s_request = false

	-- attach resource
	if not self.resource then --else drone load attached a res
		self:SetCarriedResource(resource, amount)
	end

	if not dont_chain_deliver then
		self:SetCommand("Deliver", d_request)
	end
end

function Drone:SetCarriedResource(resource, amount)
	if resource then
		if self.resource then
			self:SetCarriedResource(false)
		end
		self.resource = resource
		self.amount = amount
		for i = 1000, Max(amount, 1000), 1000 do
			local part = PlaceObject("ResourceStockpileBox", {resource = resource})
			local spot = self:GetSpotBeginIndex("Resource")
			self:Attach(part, spot)
			part:SetAttachOffset((point(0, 0, 1) * (i - 1000)/1000) * 120)
		end
		RebuildInfopanel(self)
	elseif self.resource then
		self.resource = false
		self.amount = false
		RebuildInfopanel(self)
		self:DestroyAttaches("ResourceStockpileBox")
	end
end

function FindStockpileDumpSpot(pos, resource, path_test_obj)
	local q, r = WorldToHex(pos)
	local bld = HexGetLowBuilding(q, r)
	local pipe = HexGetPipe(q, r)
	local ls_cs = GetLandscapeConstructionAt(q, r, true)
	local units = HexGetUnits(nil, nil, pos, 0, nil, resource == "WasteRock" and StockpileDumpSpotFilterForWasteRock or StockpileDumpSpotFilter, StockpileDumpQueryClasses)
	local res = false
	if bld or pipe or #units > 0 or ls_cs then
		--there is a building here.
		local obj = bld or units[1] or pipe or ls_cs
		local p_shape = GetEntityPeripheralHexShape(obj:GetEntity())
		if #p_shape == 6 then p_shape = HexSurroundingsCheckShapeLarge end --1 hex buildings can get surrounded pretty quickly so extend the search.
		if not ls_cs then
			q, r = WorldToHex(obj)
			res, q, r = TryFindStockpileDumpSpot(q, r, obj:GetAngle(), p_shape, HexGetLandscapeOrAnyObjButToxicPool, resource == "WasteRock")
		end
		if not res then
			--try again
			q, r = WorldToHex(pos)
			res, q, r = TryFindStockpileDumpSpot(q, r, 0, HexSurroundingsCheckShapeLarge, HexGetLandscapeOrAnyObjButToxicPool, resource == "WasteRock", nil, path_test_obj)
		end
	else
		res = true
	end
	return res, q, r
end

function Drone:CreateDumpingStockpile()
	local s_req = self.picked_up_from_req
	local s_bld = s_req and s_req:GetBuilding()
	local input_pos = IsKindOf(s_bld, "ResourceStockpileBase") and s_bld:GetPos() or self:GetPos()
	local mark = LandscapeCheck(input_pos, false)
	local ls = mark and Landscapes[mark]
	local site = ls and ls.site
	if site and IsKindOf(site, "LandscapeConstructionSiteBase") then
		--exit the ls b4 searching for pos
		if not self:Goto(site.drone_dests_cache) then
			Sleep(1000)
			return false
		end
		input_pos = self:GetPos()
	end
	
	local res, q, r = FindStockpileDumpSpot(input_pos, self.resource, self) --prefer stockpile pos as ref so all drones see the same positions
	
	if not res then
		local dropped = false
		if s_bld and s_req and s_req:IsAnyFlagSet(const.rfCanExecuteAlone) then
			s_bld = GetTopmostParent(s_bld)
			if s_bld:HasMember("ExecuteAloneResourceOutputBlocked") then
				dropped = s_bld:ExecuteAloneResourceOutputBlocked(self.resource, self.amount, self)
			end
		end
		
		if not dropped then
			PlaceResourcePile(GetPassablePointNearby(self), self.resource, self.amount)
		end
		
		self.resource = false
		self.amount = false
		RebuildInfopanel(self)
		self:DestroyAttaches("ResourceStockpileBox")
		Sleep(1000)
		return --failed to find a suitable location
	end
	
	local pos = point(HexToWorld(q, r))
	self:ExitHolder(pos)
	if not self:Goto(pos, const.HexSize * 3 / 4, const.HexSize * 1 / 2) or HexGetLowBuilding(q, r)
		or (self.resource == "WasteRock" and HexGetUnits(nil, nil, pos, 0, nil, StockpileDumpSpotFilterForWasteRock, StockpileDumpQueryClasses)[1]) then --someone took the spot while we traveled.
		Sleep(1000)
		return
	end
	
	--we made it
	local stock = false
	if self.resource == "WasteRock" then
		--waste rock piles are special and block construction.
		stock = PlaceObject("WasteRockStockpileUngrided", {init_with_amount = self.amount, has_demand_request = true, apply_to_grids = true, has_platform = false, snap_to_grid = true, additional_demand_flags = const.rfSpecialDemandPairing})
		stock:SetPos(pos)
	elseif self.resource then
		--create a special non waste rock pile with demand req.
		local did_create_new_stock
		stock, did_create_new_stock = PlaceResourceStockpile_Instant(pos, self.resource, self.amount, 0, true)
		if did_create_new_stock then
			--stock has passed init but not gameinit so we can mod some init vals
			stock.has_demand_request = true
			stock.priority = 2
			stock.additional_demand_flags = const.rfSpecialDemandPairing
		else
			--if it's an existng stock,
			if not stock.has_demand_request and not stock.parent_construction then
				stock:DisconnectFromCommandCenters()
				stock.has_demand_request = true
				stock.priority = 2
				stock.additional_demand_flags = const.rfSpecialDemandPairing
				stock.demand_request = stock:AddDemandRequest(stock.resource, stock:GetMax() * const.ResourceScale - stock:GetStoredAmount(), stock.additional_demand_flags)
				stock:ConnectToCommandCenters()
			end
		end
	end
	
	
	self.resource = false
	self.amount = false
	RebuildInfopanel(self)
	self:DestroyAttaches("ResourceStockpileBox")
	Sleep(1000)
end

function Drone:Deliver(d_request, do_not_improve_req)
	self.delivery_state = "approach"
	local resource = self.resource
	local amount = self.amount
	
	assert(resource and amount)
	
	if d_request then
		--req, coming from PickUp, find a better dest
		if not do_not_improve_req then
			d_request = self:ImproveDemandRequest(self.picked_up_from_req, d_request, resource, amount)
		end
	else
		--no req, coming from idle, find a dest
		local command_center = self.command_center
		if command_center and command_center.working then
			--if we are carrying sumthing and we got no req, any demand will do no matter special pairing flags.
			d_request = command_center:FindDemandRequest(self, resource, amount) --doesnt assign
			if d_request and not d_request:AssignUnit(amount) then
				Sleep(1000)
				return
			end
		end
	end
	self.d_request = d_request or false
	
	if not d_request then
		--there is nowhere to deliver :(
		self:SetCommand("CreateDumpingStockpile")
		return
	end
	
	local building = d_request:GetBuilding()
	self.target = building
	RebuildInfopanel(self)
	if self.command_center then
		local cc = self.command_center
		local uc = cc.under_construction
		if uc and uc[resource] == d_request and d_request:GetTargetAmount() == 0 and building and building:IsSupplied() then
			cc:UpdateConstructions()
		end
		
		local rt = cc.restrictor_tables
		local rrt = rt[const.rfRestrictorRocket]
		
		if rrt and rrt[resource] == d_request and d_request:GetTargetAmount() <= 0 then
			cc:UpdateRockets()
		end
	end
	local is_fulfilled = false
	self:PushDestructor(function(self)
		if d_request then
			d_request:UnassignUnit(amount, is_fulfilled) 
		end
		
		if self.delivery_state == "done" then
			--we delivered, clean up
			self.resource = false
			self.amount = false
			self.target = false
			self.picked_up_from_req = false
			RebuildInfopanel(self)
			if IsValid(self) then
				self:DestroyAttaches("ResourceStockpileBox")
			end
		end
		self.d_request = false
	end)
	
	-- keep trying to find a destination for our resource & unload
	while not self:ApproachWrapper(building, resource) or not d_request:Fulfill(amount) do
		Sleep(1000)
		self:CleanUnreachables()
		local must_change = self.unreachable_buildings and self.unreachable_buildings[d_request:GetBuilding()] and true or false --if we cannot reach requestor we should force change req, alternatively if do_not_improve is set just drop it.
		
		if not do_not_improve_req then
			d_request = self:ImproveDemandRequest(self.picked_up_from_req, d_request, resource, amount, must_change)
		elseif must_change then
			d_request:UnassignUnit(amount, false)
			d_request = nil
		end
		
		if not d_request or not IsValid(d_request:GetBuilding()) or d_request:GetTargetAmount() < 0 then
			self:PopAndCallDestructor()
			return
		end
		self.d_request = d_request
		building = d_request:GetBuilding()
		self.target = building
		RebuildInfopanel(self)
	end
	-- unload animation
	is_fulfilled = true
	self.delivery_state = "done" --this must come first because the below call can hijack our drone.
	building:DroneUnloadResource(self, d_request, resource, amount)
	
	self:PopAndCallDestructor()
	self.force_go_home = true
end

local best_charger
local best_score
function Drone:PickRechargeStation()
	self:CleanUnreachables()
	local command_center = IsValid(self.command_center) and self.command_center
	local hexradius = (command_center and command_center.work_radius or const.CommandCenterMaxRadius) * 2
	local eval = function(o, self)
		if IsValid(o) and o:IsRechargerWorking() and (not self.unreachable_buildings or not self.unreachable_buildings[o]) then
			return (o.charging_time_left or 0) * 2 + #o.drones_in_queue_to_charge * 120 + self:GetDist2D(o)/guim
		end
	end
	return MapFindMin(command_center or self, "hex", hexradius,"RechargeStationBase", eval, self )
end

function Drone:ResetEmergencyPowerCommand(new_recharger)
	if not self:IsDisabled() then
		self:SetCommand("EmergencyPower", new_recharger)
	end
end

function Drone:EmergencyPower(input_recharger)
	PlayFX("EmergencyPower", "start", self)
	self:PushDestructor( function(self)
		PlayFX("EmergencyPower", "end", self)
		if self.going_to_recharger ~= false then
			self.going_to_recharger = false
		end
		self.target = nil
	end )
	self:SetState("idle")
	local recharger
	while not IsValid(recharger) or not recharger:IsRechargerWorking() do
		while true do
			recharger = input_recharger or self:PickRechargeStation()
			input_recharger = false
			self.going_to_recharger = recharger
			self.target = recharger
			if recharger then
				recharger:QueueDrone(self)
				self:PushDestructor(function(self)
					if IsValid(recharger) then
						recharger:DroneExitQueue(self)
					end
				end)
			end
			if self:ApproachWrapper(recharger, "charge") and recharger:IsRechargerWorking() then
				break
			elseif recharger then
				self:PopAndCallDestructor()
			end
			Sleep(5000 + self:Random(5000))
		end
		
		self.going_to_recharger = false
		self.target = nil
		self:SetState("idle")
		
		while IsValid(recharger) and IsValid(recharger.drone_charged) and not recharger.drone_charged:IsDisabled() do
			Sleep(1000 + self:Random(1000))
		end
		
		self:PopAndCallDestructor()
	end
	recharger.drone_charged = self --tell the recharger we are coming in early on, so that no other drones get in in the same time.
	self:PopAndCallDestructor() -- PlayFX("EmergencyPower", "end", self)
	
	self:SetCommand("Charge", recharger)
end

function Drone:Charge(recharger)
	if not IsValid(recharger) then return end
	
	local battery_start = self.battery
	
	self:PushDestructor(function(self)
		recharger.charging_progress = 0
		recharger.charging_time_left = false
		
		if IsValid(recharger) and IsValid(self) then
			recharger:LeadOut(self)
		end
		if IsValid(recharger) and recharger:IsRechargerWorking() then
			recharger:NotifyDronesOnRechargeStationFree()
		end
	end)
	
	recharger:LeadIn(self)
	if not IsValid(recharger) then
		self:SetCommand("Idle")
	end
	self:PlayFXMoment("hooking")
	if recharger:HasMember("SetPlatformState") then recharger:SetPlatformState("chargingIdle") end
	
	local is_recharge_station = IsKindOfClasses(recharger, "RechargeStation", "NotBuildingRechargeStation")
	
	if is_recharge_station then
		self:SetState("chargingStationIdle")
	else
		self:SetState("rechargeDroneIdle")
	end

	local battery_charge = self.battery_max - battery_start
	local dust_start = self.dust

	local should_clean = g_Consts.RechargeCleansDrones > 0
	local time = g_Consts.DroneRechargeTime / 1000
	
	--There's a breakthrough that speeds up the recharging of drones
	--  only when using a recharge station (not RCRover or something else)
	if is_recharge_station then
		time = MulDivRound(time, g_Consts.RechargeStationTimeMod, 100)
	end
	
	for i = 1, time do
		if not IsValid(recharger) or not recharger:IsRechargerWorking() then
			self:SetCommand("Idle")
		end
		local charge = MulDivTrunc(i, battery_charge, time)
		self.battery = battery_start + charge
		if should_clean then
			self.dust = dust_start - MulDivTrunc(i, dust_start, time)
		end
		recharger.charging_progress = battery_charge > 0 and MulDivRound(charge, 100, battery_charge ) or 100
		recharger.charging_time_left = time - i + 1
		Sleep(1000)		
	end
	recharger.charging_time_left = 0
	recharger.charging_progress = 0
	self.battery = self.battery_max
	if should_clean then
		self.dust = 0
	end

	self:PopAndCallDestructor() -- recharger:LeadOut(self)
end

local delay_before_rogue_drones_die = 30000
function Drone:RogueDieAfterDelay()
	if not self.rogue then return end
	Sleep(delay_before_rogue_drones_die)
	if IsValid(self) then 
		DoneObject(self)	
	end
	Halt()
end

function Drone:Malfunction()
	self:StartFX("Breakdown")
	if self:GetStateText() == "noBattery" then
		self:SetState("breakDownIdle")
	else
		self:SetState("breakDown")
	end
	self:RogueDieAfterDelay()
	Halt()
end

function Drone:Dead(already_dead, meteor)
	self:PushDestructor(function(self)
		--this destructor is here to catch unintentional drone revivaval
		assert(not self.command, string.format("Drone resurected! New cmd -> %s", tostring(self.command)))
	end)
	
	self:RemoveFromLabels()
	
	if not already_dead then
		local exploded_fuel = false
		if meteor then
			local carrying_resource = self:GetCarriedResource()
			if carrying_resource == "Fuel" then --fuel explodes and will not be dropped
				exploded_fuel = true
			end
		end
		self:DropCarriedResource(false, exploded_fuel)
		RebuildInfopanel(self)
		self:StartFX("Dead")
		--stop
		self:ClearPath()
		self:SetPos(self:GetVisualPos())
		--play animations
		self:PlayState("death")
		self:SetIsNightLightPossible(false)
		--rem from command center
		self:SetCommandCenter(false)
		if not g_Tutorial then
			table.insert(g_DestroyedVehicles, self)
		end
	end

	Halt()
end

function Drone:NoBattery()
	self:StartFX("NoBattery")
	self:SetState("noBattery")

	self:PushDestructor(function(self)
		if IsValid(self) then
			self:SetIsNightLightPossible(true)
		end
	end)
	self:SetIsNightLightPossible(false)
	self:RogueDieAfterDelay()
	local max_heat = const.MaxHeat
	local freeze_progress = 0
	local delta = 5000
	local freeze_heat = self.freeze_heat
	while IsValid(self) do
		local freeze_speed
		local heat = GetHeatAt(self)
		if heat == max_heat then
			freeze_speed = -100
		elseif heat == 0 then
			freeze_speed = 100
		elseif heat > freeze_heat then
			freeze_speed = MulDivRound(100, freeze_heat - heat, max_heat - freeze_heat)
		else
			freeze_speed = MulDivRound(100, freeze_heat - heat, freeze_heat)
		end
		local time_delta = MulDivRound(delta, freeze_speed, 100)
		local freeze_delta = MulDivRound(100, time_delta, self.freeze_time)
		freeze_progress = Clamp(freeze_progress + freeze_delta, 0, 100)
		self:SetHeat(MulDivRound(const.MaxHeat, freeze_progress, 100))
		if freeze_progress == 100 then
			self:SetCommand("Freeze")
		end
		Sleep(delta)
	end
end

function Drone:Freeze()
	self:StartFX("Freeze")
	self:SetState("breakDown")
	self:SetHeat(0)
	local hour_duration = const.HourDuration
	while true do
		Sleep(hour_duration)
	end
end

function Drone:Fixed(anim)
	self:SetColorModifier(RGB(100, 100, 100))
	self:UseBattery(0)
	self:PlayState(anim)
end

function Drone:MoveSleep(time)
	Sleep(time)
	
	local battery_usage_amount = 0
	
	if self.command ~= "ExitImpassable" then
		if self.resource then
			battery_usage_amount = g_Consts.DroneCarryBatteryUse * time / 1000
		else
			battery_usage_amount = g_Consts.DroneMoveBatteryUse * time / 1000
		end
	end
	
	self:UseBattery(battery_usage_amount)
end

function Drone:UseBattery(amount)
	amount = MulDivRound(amount, 100 + self:GetColdPenalty(), 100)
	local battery = Max(self.battery - amount, 0)
	self.battery = battery
	if battery <= g_Consts.DroneEmergencyPower then
		local command = battery <= 0 and "NoBattery" or "EmergencyPower"
		local cur_command = self.command
		if cur_command ~= command 
			and cur_command ~= "DespawnAtHub" --the drone is in fact disassembled in this command so consider it dead
			and cur_command ~= "Charge" --generally visuals of entering recharge station would drain in this cmd
			and cur_command ~= "Dead" --derp..
			and (command == "NoBattery" or cur_command ~= "RecallToRover") --don't interrupt recalltorover with emergency powr.
		then
			if command == "NoBattery" then
				self:SetDisablingCommand(command)
			else
				self:SetCommand(command)
			end
		end
	end
end

function Drone:GenerateDustMalfunctionThreshold()
	local rand_percent = 50 + self:Random(101)
	self.dust_max = MulDivRound(const.MaxMaintenance, rand_percent, 100)
end

function Drone:Reset(delay)
	self:ClearPath()
	self:SetPos(self:GetVisualPos2D())
	self:StartFX("Reset")
	Sleep(delay or 2000)
end

function Drone:Embark() --while in transin in rover
	--make drone as if inside the rover
	self.accumulate_dust = false
	self:StopFX()
	self:ClearPath()
	self:SetState("idle", const.eDontCrossfade)
	self:ClearEnumFlags(const.efPathExecObstacle + const.efResting + const.efSelectable) --resting so it does not interfere with rover pathing.
	self:PushDestructor(function(self)
		if not IsValid(self) then return end
		self.accumulate_dust = true
		self:SetEnumFlags(const.efPathExecObstacle + const.efResting + const.efSelectable)
	end)
	Halt()
end

function Drone:RecallToRover(rover)
	assert(self.command_center == rover)
	
	--drop res if carrying any
	if self.resource then
		PlaceResourcePile(GetPassablePointNearby(self), self.resource, self.amount) --TODO: need rover spots for best results.
		self.resource = false
		self.amount = false
		self:DestroyAttaches("ResourceStockpileBox")
	end
	
	self:PushDestructor(function(self)
		--should notify rover we cant make it.
		if IsValid(rover) and self.command ~= "Embark" then
			if rover.guided_drone == self then
				rover.guided_drone = false
			end
			if IsValid(self) then
				self:SetEnumFlags(const.efPathExecObstacle)
			end

			table.remove_entry(rover.drones_waiting_to_embark, self)
			rover:DroneFailedToRecall(self)
		end
	end)
	
	self:ExitHolder(rover)
	local go_to_pos = rover:GetSpotLoc(rover:GetSpotBeginIndex(rover.drone_entry_spot))
	local function did_rover_move()
		return go_to_pos ~= rover:GetSpotLoc(rover:GetSpotBeginIndex(rover.drone_entry_spot))
	end
	local my_rad = self:GetRadius()
	
	--get sort of close with collision
	if go_to_pos:Dist2D2(self:GetPos()) > (my_rad * 3) * (my_rad * 3) then
		if not self:Goto(go_to_pos, my_rad * 5, my_rad * 3) or (not IsValid(self) or not IsValid(rover) or did_rover_move()) then
			self.command = "Idle" --hack, in general self.command is the next command due to setcommand setting it, however returning from here our next command is "Idle", yet self.command ~= "Idle", hence this hack.
			self:PopAndCallDestructor() --fail
			Sleep(1000)
			return
		end
	end
	--rem collision
	self:ClearEnumFlags(const.efPathExecObstacle)

	--get closer.
	if rover.guided_drone ~= self then --else we are already there or close.
		if (not self:Goto(go_to_pos, my_rad * 3, my_rad * 1) or (not IsValid(self) or not IsValid(rover) or did_rover_move())) 
			and (not self:Goto_NoDestlock(go_to_pos, my_rad * 3, my_rad * 1) or (not IsValid(self) or not IsValid(rover) or did_rover_move())) then
			self.command = "Idle" --hack, in general self.command is the next command due to setcommand setting it, however returning from here our next command is "Idle", yet self.command ~= "Idle", hence this hack.
			self:PopAndCallDestructor() --fail
			Sleep(1000)
			return
		end
	end
	
	self:SetState("idle")
	rover.drones_waiting_to_embark[#rover.drones_waiting_to_embark + 1] = self --so rover can wake us
	while rover.guided_drone and rover.guided_drone ~= self do --wait for this guy to get in
		WaitWakeup(1000)
	end
	
	if not IsValid(self) or not IsValid(rover) or did_rover_move() or (rover.siege_state_name ~= "Unsiege" and self.command ~= "DespawnAtHub") then
		self.command = "Idle" --hack, in general self.command is the next command due to setcommand setting it, however returning from here our next command is "Idle", yet self.command ~= "Idle", hence this hack.
		self:PopAndCallDestructor() --fail
		Sleep(1000)
		return
	end
	--reg as drone coming in
	assert(rover.guided_drone == false or rover.guided_drone == self)
	rover.guided_drone = self
	table.remove_entry(rover.drones_waiting_to_embark, self)

	self:Goto(go_to_pos)

	if not IsValid(self) or not IsValid(rover) or did_rover_move() then
		self:PopAndCallDestructor() --fail, this calls halt when curr_thread ~= cmd_thread
	elseif rover.siege_state_name ~= "Unsiege" and self.command ~= "DespawnAtHub" then
		self:SetCommand("Idle") --this will pop our destructor and set us in a different command
	else
		--regular schedule
		rover:DroneEnter(self, false)
		assert(false) --this line is not reachable
	end
	
	if self.command ~= "DespawnAtHub" then
		Halt()
	end
end

function Drone:ExitRover(rover)
	assert(rover == self.command_center)
	self.command_center:DroneExit(self)
end

local function TestReq(req, resource, amount) --tests whether we can assign to this request
	return req and req:CanAssignUnit() and (not resource or req:GetResource() == resource) and (not amount or req:GetTargetAmount() >= amount)
end

local function FindSupplyReq(obj, resource) --given object and resource, returns the supply request managing this resource for the object.
	for i = 1, #obj.task_requests do
		local req = obj.task_requests[i]
		if req:GetResource() == resource and req:IsAnyFlagSet(const.rfSupply) then
			--there should be only 1 supply req
			return req
		end
	end
	
	return false
end

function Drone:ShouldDeliverResourcesToBld(bld, resource, amount) --check if we need to deliver resource and amount to bld
	if not resource or not table.find(AllResourcesList, resource) or not IsKindOf(bld, "Building") then return false end
	if IsKindOf(bld, "ConstructionSite") then
		--construction site
		local request = false 
		if bld.construction_group then
			request = bld.construction_group[1].construction_resources[resource] or false
		else
			request = bld.construction_resources[resource] or false
		end
		if TestReq(request, resource, amount) then
			return request
		end
	elseif TestReq(bld.maintenance_resource_request, resource, amount) then
		--maintenance resource
		return bld.maintenance_resource_request
	elseif TestReq(bld.consumption_resource_request, resource, amount) then
		--consumption resource
		return bld.consumption_resource_request
	elseif bld:HasMember("demand") and bld.demand and IsKindOfClasses(bld, "UniversalStorageDepot", "WasteRockDumpSite", "BlackCubeDumpSite") and TestReq(bld.demand[resource], resource, amount) then
		return bld.demand[resource]
	end
	
	return false
end

function Drone:SetInteractionState(val)
	SetUnitControlInteractionMode(self, val)
	if val then
		SetUnitControlFocus(true, self)
	end
end

function Drone:ToggleDemolish_Update(btn)	
	Demolishable.ToggleDemolish_Update(self,btn)
	btn:SetEnabled(self.command ~= "Embark" and self.command ~= "ExitRover" and self.command ~= "RecallToRover" and self.command ~= "DespawnAtHub")
end

function Drone:ToggleReassignInteractionMode()
	if self:IsDead() then 
		return 
	end
	if self.interaction_mode ~= "reassign" then
		self:SetInteractionState("reassign")
	else
		self:SetInteractionState(false)
	end
end

function Drone:ToggleReassignAllInteractionMode()
	if self:IsDead() then 
		return 
	end
	if self.interaction_mode ~= "reassign_all" then
		self:SetInteractionState("reassign_all")
	else
		self:SetInteractionState(false)
	end
end

function Drone:ToggleReassignInteractionMode_Update(button)
	local to_mode = self.interaction_mode ~= "reassign"
	button:SetIcon(to_mode and
		"UI/Icons/IPButtons/reassign.tga"
		or "UI/Icons/IPButtons/cancel.tga")
	local tutorial2_enable = not g_Tutorial or ((g_Tutorial.Id == "Tutorial2") and g_Tutorial.DisableReassignButtons and AreAllUnassignedDronesSelected()) or false
	button:SetEnabled(self:CanBeControlled() and tutorial2_enable)
	button:SetRolloverText(T(4428, "Assign to target Hub, Commander or Rocket."))
	local shortcuts = GetShortcuts("actionReassignDrone")
	local hint = ""
	if shortcuts and (shortcuts[1] or shortcuts[2]) then
		hint = T(10926, " / <em><ShortcutName('actionReassignDrone', 'keyboard')></em>")
	end
	button:SetRolloverHint(to_mode and T{10925, "<left_click><hint> Select target mode", hint = hint} or T(7510, "<left_click> on target to select it  <right_click> Cancel"))
	button:SetRolloverHintGamepad(to_mode and T(7511, "<ButtonA> Select target mode") or T(7512, "<ButtonA> Cancel"))
end

function Drone:ToggleReassignAllInteractionMode_Update(button)
	local to_mode = self.interaction_mode ~= "reassign_all"
	button:SetIcon(to_mode and
		"UI/Icons/IPButtons/reassign_all.tga"
		or "UI/Icons/IPButtons/cancel.tga")
	local tutorial2_enable = not g_Tutorial or ((g_Tutorial.Id == "Tutorial2") and g_Tutorial.DisableReassignButtons and AreAllUnassignedDronesSelected()) or false
	button:SetEnabled(self:CanBeControlled() and tutorial2_enable)
	button:SetRolloverText(T(8719, "Assign as many drones to target Hub, Commander or Rocket as possible."))
	button:SetRolloverHint(to_mode and T(7509, "<left_click> Select target mode") or T(7510, "<left_click> on target to select it  <right_click> Cancel"))
	button:SetRolloverHintGamepad(to_mode and T(7511, "<ButtonA> Select target mode") or T(7512, "<ButtonA> Cancel"))
end

function Drone:GetCarriedResource()
	return self.resource and table.find(AllResourcesList, self.resource) and self.resource or false
end

function Drone:DropCarriedResourceFromUI(ui_delta)
	self:SetCommandUserInteraction("DropCarriedResource")
end

function Drone:DropCarriedResource(amount, exploded_fuel)
	local carrying_resource = self:GetCarriedResource()
	if carrying_resource then
		amount = amount and Min(amount, self.amount) or self.amount
		if not exploded_fuel then
			local passable_point = self:IsValidPos() and GetPassablePointNearby(self, self.radius*200, self.radius + 30) --somewhere near the drone, but not exactly in it
			if passable_point then
				PlaceResourcePile(passable_point, self.resource, amount)
			else
				PlaceResourcePile(self:GetPos(), self.resource, amount)
			end
		end
		self.amount = self.amount - amount
		if self.amount <= 0 then
			self.resource = false
			self.amount = false
			RebuildInfopanel(self)
			self:DestroyAttaches("ResourceStockpileBox")
		end
	end
end

function Drone:DropCarriedResourceFromUI_Update(button)
	button:SetEnabled(self:CanBeControlled() and self:GetCarriedResource())
end

function Drone:GetDropCarriedResourceFromUIDisabledRollover()
	if self:CanBeControlled() then
		if not self:GetCarriedResource() then
			--operational, no resource
			return T(8535, "No resource loaded.")
		else
			--operational, carries resources (this case should be impossible)
			return T(221351751895, "Vehicle inactive.")
		end
	else
		--upoperational
		return T(221351751895, "Vehicle inactive.")
	end
end

function Drone:DespawnAtHub()
	local hub = self.command_center
	if not hub then
		DoneObject(self)
		return
	end
	assert(IsKindOf(hub, "DroneControl"))
	self:DropCarriedResource()
	local is_rover = IsKindOf(hub, "RCRover")
	self:PushDestructor(function(self)
		if is_rover then
			table.remove_entry(hub.attached_drones, self)
			if hub.guided_drone == self then
				hub.guided_drone = false
			end
			assert(not table.find(hub.embarking_drones, self))
		end
		if IsValid(self) then
			DoneObject(self)
		end
	end)
	if is_rover then
		if not self:GetParent() then
			self:RecallToRover(hub)
		end
	else
		self:EnterBuilding(hub)
	end
	self:PopAndCallDestructor()
end

function Drone:DieNow()
	DoneObject(self)
end

function Drone:OnUnitControlActiveChanged(new_val)
	if not new_val then
		self:SetInteractionState(false)
	end
end

function Drone:CanBeControlled()
	return not self:IsDisabled() and not self.rogue and self.command ~= "Embark"
end

function Drone:ExitFactory(factory, delay)
	if delay then
		Sleep(delay)
		if not IsValid(self) then
			return
		end
	end
	assert(factory)
	local chain = factory.waypoint_chains.drone_factory_exit[1]
	assert(chain)
	self:SetPos(chain[1])
	self:PushDestructor(function(self)
		factory:LeadOut(self, chain)
		self:SetCommandCenter(false) --so it knows it's an orphan
		self:SetCommand("Start")
	end)
	self:PopAndCallDestructor()
end

function Drone:OnStrandedFallback()
	local my_pos = self:GetPos()
	local building = HexGetBuildingNoDome(WorldToHex(my_pos))
	local teleport_spot = "Workdrone"
	local teleport_pos
	if building and building:HasSpot("idle", teleport_spot) then
		local idx = building:GetNearestSpot("idle", teleport_spot, my_pos)
		local nearest_pos = building:GetSpotPos(idx)
		if terrain.IsPassable(nearest_pos, self.pfclass) and not my_pos:Equal2D(nearest_pos) then
			teleport_pos = nearest_pos
		else
			local i1, i2 = building:GetSpotRange("idle", teleport_spot)
			while not teleport_pos do
				if not self.last_spot_tried then
					self.last_spot_tried = i1
				else
					self.last_spot_tried = self.last_spot_tried + 1
				end
				
				if self.last_spot_tried <= i2 then
					local p = building:GetSpotPos(self.last_spot_tried)
					if terrain.IsPassable(p, self.pfclass) then
						teleport_pos = p
					end
				else
					break
				end
			end
		end
	end
	--[[
	if not teleport_pos then
		local cc = self.command_center
		if cc and cc:HasSpot("idle", self.work_spot_task) then
			local idx = cc:GetNearestSpot("idle", self.work_spot_task, my_pos)
			local nearest_pos = cc:GetSpotPos(idx)
			if not my_pos:Equal2D(nearest_pos) then
				teleport_pos = nearest_pos
			end
		end
	end
	--]]
	if teleport_pos then
		self:SetPos(teleport_pos)
		return true
	end
	return Unit.OnStrandedFallback(self)
end

function Drone:OnModifiableValueChanged(prop, old_val, new_val)
	if prop == "battery_max" then
		self.battery = Min(self.battery, self.battery_max)
	end
end

function GetSupplyReq(bld, resource)
	if IsKindOfClasses(bld, "SurfaceDeposit", "ResourcePile") then
		return bld.transport_request
	else
		return bld.supply_request or bld:HasMember("supply") and bld.supply[resource]
	end
end

Drone_AutoFindResourceRadius = 100 * guim
local function CanPickupResourceFrom(o, resource)
	local res = o.resource
	return res == resource or type(res) == "table" and table.find(res, resource) and true or false
end

ResourceSources_func = function(o, resource, amount, unreachables)
	if unreachables and unreachables[o] then return false end
	if IsKindOfClasses(o, "SharedStorageBaseVisualOnly", "ConsumptionResourceStockpile") then return false end
	if not CanPickupResourceFrom(o, resource) then return end
	local req = GetSupplyReq(o, resource)
	return req and req:CanAssignUnit() and req:GetActualAmount() >= amount
end

function Drone:InteractionObjTest_Construct(obj)
	return IsKindOf(obj, "ConstructionSite")
end

function Drone:InteractionObjTest_LandscapeConstruct(obj)
	return IsKindOf(obj, "LandscapeConstructionSiteBase")
end

local function parse_cs_reqs_and_find_source(self, obj, next_req)
	local source
	if not next_req then
		for res, req in pairs(obj.construction_resources) do
			if TestReq(req, nil, 1) then
				next_req = req
				break
			end
		end
	end
	if next_req then
		local resource = next_req:GetResource()
		source = MapFindNearest(self, self, Drone_AutoFindResourceRadius,
									"ResourceStockpile", "ResourcePile", "SurfaceDeposit", "StorageDepot", 
									ResourceSources_func, resource,
									Min(DroneResourceUnits[resource], next_req:GetTargetAmount()))
	end
	return next_req, source
end

function Drone:InteractionObjCheck_LandscapeConstruct(obj)
	local s = obj.state
	local txt
	local ret = false
	if s == "clean" then
		if obj.clear_obstructors_request:CanAssignUnit(const.ResourceScale)
			or obj.obstructors_supply_request:CanAssignUnit(const.ResourceScale) then
			txt = T{4398, "<UnitMoveControl('ButtonA',interaction_mode)>: Work on this construction", self}
			ret = true
		end
	elseif s == "transport" then
		if obj.supply_request:CanAssignUnit(const.ResourceScale) then
			txt = T{4398, "<UnitMoveControl('ButtonA',interaction_mode)>: Work on this construction", self}
			ret = true
		elseif obj.demand_request:GetTargetAmount() > 0 then
			local _, source = parse_cs_reqs_and_find_source(self, obj, obj.demand_request)
			if source then
				txt = T{4398, "<UnitMoveControl('ButtonA',interaction_mode)>: Work on this construction", self}
				ret = true
			else
				txt = T(11248, "Can't find the required resources")
			end
		end
	elseif s == "work" then
		local req = IsKindOf(obj, "TerrainPaintConstructionSite") and obj.work_request or obj.waste_rock_juggle_work_request
		if req:CanAssignUnit(const.ResourceScale) then
			txt = T{4398, "<UnitMoveControl('ButtonA',interaction_mode)>: Work on this construction", self}
			ret = true
		end
	end
	
	txt = not txt and T(4399, "<red>Too many Drones are already constructing this building</red>") or txt
	
	return ret, txt
end

function Drone:InteractionObjCheck_Construct(obj)
	obj = obj.construction_group and obj.construction_group[1] or obj
	local construct = obj.construction_started and obj.construct_request:GetActualAmount() > 0 and obj.construct_request:CanAssignUnit()
	local deliver = not obj.construction_started and obj:IsBlockerClearenceComplete()
	local clean = not obj.construction_started and not obj:IsBlockerClearenceComplete()
	local txt
	local ret = true
	if construct then
		txt = T{4398, "<UnitMoveControl('ButtonA',interaction_mode)>: Work on this construction", self}
	elseif deliver then
		local next_req, source = parse_cs_reqs_and_find_source(self, obj)
		
		if not next_req then
			txt = T(4399, "<red>Too many Drones are already constructing this building</red>")
			ret = false
		elseif not source then
			txt = T(11248, "Can't find the required resources")
			ret = false
		else
			txt = T{4398, "<UnitMoveControl('ButtonA',interaction_mode)>: Work on this construction", self}
		end
	elseif clean then
		--check if it can assign? it can probably assign..
		txt = T{4398, "<UnitMoveControl('ButtonA',interaction_mode)>: Work on this construction", self}
	else
		txt = T(4399, "<red>Too many Drones are already constructing this building</red>")
		ret = false
	end
	
	return ret, txt
end

function Drone:Interaction_LandscapeConstruct(obj)
	local s = obj.state
	if s == "clean" then
		if obj.clear_obstructors_request:CanAssignUnit(const.ResourceScale) then
			local r = obj.clear_obstructors_request
			local res = r:GetResource()
			self:SetCommandUserInteraction("Work", r, res, Min(DroneResourceUnits[res], r:GetActualAmount()))
		elseif obj.obstructors_supply_request:CanAssignUnit(const.ResourceScale) then
			local r = obj.obstructors_supply_request
			local res = r:GetResource()
			self:SetCommandUserInteraction("PickUp", r, nil, res, Min(DroneResourceUnits[res], r:GetTargetAmount()))
		end
	elseif s == "transport" then
		if obj.supply_request:CanAssignUnit(const.ResourceScale) then
			local r = obj.supply_request
			local res = r:GetResource()
			self:SetCommandUserInteraction("PickUp", r, nil, res, Min(DroneResourceUnits[res], r:GetTargetAmount()))
		elseif obj.demand_request:GetTargetAmount() > 0 then
			local r = obj.demand_request
			local res = r:GetResource()
			local _, source = parse_cs_reqs_and_find_source(self, obj, r)
			if source then
				local s_req = FindSupplyReq(source, res)
				self:SetCommandUserInteraction("PickUp", s_req, r, res, Min(DroneResourceUnits[res], r:GetTargetAmount()))
			end
		end
	elseif s == "work" then
		local r = IsKindOf(obj, "TerrainPaintConstructionSite") and obj.work_request or obj.waste_rock_juggle_work_request
		if r:CanAssignUnit(const.ResourceScale) then
			local res = r:GetResource()
			self:SetCommandUserInteraction("Work", r, res, Min(DroneResourceUnits[res], r:GetActualAmount()))
		end
	end
end

function Drone:Interaction_Construct(obj)
	obj = obj.construction_group and obj.construction_group[1] or obj
	local construct = obj.construction_started and obj.construct_request:GetActualAmount() > 0 and obj.construct_request:CanAssignUnit()
	local deliver = not obj.construction_started and obj:IsBlockerClearenceComplete()
	local clean = not obj.construction_started and not obj:IsBlockerClearenceComplete()
	
	if construct then
		local r = obj.construct_request
		self:SetCommandUserInteraction("Work", r, "construct", Min(DroneResourceUnits.construct, r:GetActualAmount()))
	elseif deliver then
		local next_req, source = parse_cs_reqs_and_find_source(self, obj)
		if source and next_req then
			local resource = next_req:GetResource()
			local s_req = FindSupplyReq(source, resource)
			self:SetCommandUserInteraction("PickUp", s_req, next_req, resource, Min(DroneResourceUnits[resource], s_req:GetTargetAmount(), next_req:GetActualAmount()))
		end
	elseif clean then
		local wst = obj.waste_rocks_underneath
		local wr
		for i = 1, #(wst or empty_table) do
			if TestReq(wst[i].work_req, nil, 1) then
				wr = wst[i].work_req
				break
			end
		end
		if wr then
			local resource = wr:GetResource()
			self:SetCommandUserInteraction("Work", wr, resource, Min(DroneResourceUnits[resource], wr:GetActualAmount()))
			return
		end
		local sr
		local st = obj.stockpiles_underneath
		for i = 1, #(st or empty_table) do
			if TestReq(st[i].supply_request, nil, 1) then
				sr = st[i].supply_request
				break
			end
		end
		if sr then
			local resource = sr:GetResource()
			self:SetCommandUserInteraction("PickUp", sr, nil, resource, Min(DroneResourceUnits[resource], sr:GetTargetAmount()))
		end
	end
end

function Drone:InteractionObjTest_PickupFromRCTransport(obj)
	return not self:GetCarriedResource() and IsKindOf(obj, "RCTransport")
end

function Drone:InteractionObjCheck_PickupFromRCTransport(obj)
	local result
	local txt
	if obj.command == "Dead" then
		result = false
		txt = T(11605, "<red>Transport Destroyed</red>")
	elseif obj.command == "LoadingComplete" or not obj.auto_connect then
		result = false
		txt = T(11606, "<red>Resources Reserved</red>")
	elseif obj:GetStoredAmount() <= 0 then
		result = false
		txt = T(11249, "<red>Transport Empty</red>")
	else
		result = true
		txt = T{4397, "<UnitMoveControl('ButtonA',interaction_mode)>: Get resources", self}
	end
	
	return result, txt
end

function Drone:Interaction_PickupFromRCTransport(obj)
	local stocked_types = 0
	local t = obj.stockpiled_amount
	local last = false
	for r, a in pairs(t) do
		if a > 0 then
			stocked_types = stocked_types + 1
			last = r
		end
	end
	
	if stocked_types == 1 and last then
		local sreq = obj.resource_requests[last]
		self:SetCommandUserInteraction("PickUp", sreq, nil, last, Min(DroneResourceUnits[last], sreq:GetTargetAmount()), "dontchain")
	elseif stocked_types > 1 then
		OpenResourceSelector(self, {target = obj})
		return true
	else
		return false
	end
end

local function assign_to_req_helper(self, req) --assigns with carried resource
	assert(self.resource == req:GetResource())
	local amount = self.amount
	local target_amount = req:GetTargetAmount()
	assert((amount or 0) > 0 and target_amount > 0) 
	if target_amount < amount then --assign will fail
		self:DropCarriedResource(amount - target_amount)
		amount = self.amount
	end
	return req:AssignUnit(amount)
end

function Drone:InteractionObjTest_RepairSupplyGridElement(obj)
	return not IsKindOf(obj, "ConstructionSite") and IsKindOfClasses(obj, "ElectricityGridElement", "LifeSupportGridElement") and obj:IsBroken()
end

function Drone:InteractionCheck_RepairSupplyGridElement(obj, carrying_resource)
	local r = obj.repair_resource_request
	if not r or not r:CanAssignUnit() or r:GetTargetAmount() <= 0 then
		return false --other drone working on it.
	end
	local resource = r:GetResource()
	local source
	if resource ~= carrying_resource then	
		source = MapFindNearest(self, self, Drone_AutoFindResourceRadius, "ResourceStockpile", "ResourcePile", "SurfaceDeposit", "StorageDepot", ResourceSources_func, resource, Min(DroneResourceUnits[resource], r:GetTargetAmount()))
		if not source then
			return false, T{4393, "<red>Cannot find any <resource_icon> nearby</red>", resource_icon = TLookupTag("<icon_" .. resource .. ">")}
		end
	end
	
	return true, T{9631, "<UnitMoveControl('ButtonB',interaction_mode)>: Repair this building", self}, source
end

function Drone:Interaction_RepairSupplyGridElement(obj, carrying_resource)
	local r, _, source = self:InteractionCheck_RepairSupplyGridElement(obj, carrying_resource)
	
	if source then
		local d_req = obj.repair_resource_request
		local resource = d_req:GetResource()
		local s_req = GetSupplyReq(source, resource)
		self:SetCommandUserInteraction("PickUp", s_req, d_req, resource, Min(DroneResourceUnits[resource], s_req:GetTargetAmount(), d_req:GetActualAmount()))
	elseif carrying_resource then
		local d_req = obj.repair_resource_request
		if assign_to_req_helper(self, d_req) then
			self:SetCommandUserInteraction("Deliver", d_req, true)
		end
	end
end

function Drone:CanInteractWithObject(obj)
	if self:IsDisabled() then return false, T(4392, "This Drone is disabled") end
	RebuildInfopanel(self)
	if self.interaction_mode == false or self.interaction_mode == "default" or self.interaction_mode == "move" then
		if not IsKindOfClasses(obj, "Building", "DroneBase", "ResourceStockpileBase", "SurfaceDeposit", "ResourcePile", "Tunnel", "ElectricityGridElement", "LifeSupportGridElement", "ToxicPool") then
			return false, GetUIStyleGamepad() and  T{4339, "<UnitMoveControl('ButtonA',interaction_mode)>: Move",self} or false
		end

		local carrying_resource = self:GetCarriedResource()
		local resource_demand_req = self:ShouldDeliverResourcesToBld(obj, self.resource)
		
		if resource_demand_req then --we are carrying a resource and this bld needs it, or is a storage depot that accepts it
			return true, T{4396, "<UnitMoveControl('ButtonA',interaction_mode)>: Deliver <resource(amount, resource)>", amount = self.amount, resource = self.resource, self}
		elseif IsKindOf(obj, "Tunnel") then
			if obj.working then
				return true, T{9629, "<UnitMoveControl('ButtonA',interaction_mode)>:  Use Tunnel", self}--UseTunnel
			end
		elseif IsKindOf(obj, "BaseRover") and obj:IsMalfunctioned() then
			if  obj.repair_work_request:CanAssignUnit() then
				return true, T{9720, "<UnitMoveControl('ButtonA',interaction_mode)>: Repair",self}	
			elseif IsKindOf(obj, "AttackRover") and (not UICity.mystery.enable_rover_repair or not obj.is_repair_request_initialized) then
				return false, ""
			else
				return false, T(7589, "<red>Too many Drones are repairing this vehicle</red>"), true
			end
		elseif (IsKindOf(obj, "RechargeStation") or
				(IsKindOfClasses(obj, "RechargeStationBase", "DroneHub") and obj == self.command_center)) --if we select our own command center go charge there
				and obj.working then 
			return true, T{9633, "<UnitMoveControl('ButtonA',interaction_mode)>: Recharge self", self}
		elseif obj ~= self.command_center and IsKindOf(obj, "DroneControl") and obj.can_control_drones then
			if not obj:CanHaveMoreDrones() then
				if IsKindOf(obj, "SupplyRocket") and not obj.landed then
					return false, nil, true
				else
					return false, T(4401, "<red>At full capacity</red>"), true
				end
			else
				return true, T{9632, "<UnitMoveControl('ButtonY',interaction_mode)>: Assign to this command center",self}
			end
		elseif self:InteractionObjTest_RepairSupplyGridElement(obj) then
			return self:InteractionCheck_RepairSupplyGridElement(obj, carrying_resource)
		elseif IsKindOf(obj, "Building") and (obj.maintenance_phase or obj.accumulated_maintenance_points > 0) then
			local phase = obj.maintenance_phase or "demand"
			local d_req = obj.maintenance_resource_request
			if d_req and (not d_req:CanAssignUnit() or d_req:GetTargetAmount() <= 0) then
				--don't show as interactable, if other drone is already working on it and the interaction itself does not interrupt it.
				return false
			end
			
			if phase == "demand" and carrying_resource ~= d_req:GetResource() then
				--try to find needed resource nearby.
				local source = MapFindNearest(self, self, Drone_AutoFindResourceRadius, "ResourceStockpile", "ResourcePile", "SurfaceDeposit", "StorageDepot", ResourceSources_func, d_req:GetResource(), DroneResourceUnits[d_req:GetResource()])
				if not source then
					return false, T{4393, "<red>Cannot find any <resource_icon> nearby</red>", resource_icon = TLookupTag("<icon_" .. d_req:GetResource() .. ">")}
				end
			end
			return true, T{9631, "<UnitMoveControl('ButtonB',interaction_mode)>: Repair this building", self}
		elseif not carrying_resource and IsKindOfClasses(obj,"ResourceStockpileBase", "StorageDepot", "ResourcePile") and not IsKindOfClasses(obj,"Unit") and obj:GetStoredAmount() > 0 then
			if IsKindOf(obj, "WasteRockDumpSite") and not g_WasteRockLiquefaction then
				return false --wasterock dumps don't have wasterock supply req so we cant pickup anything other then concrete when researched
			end
			local resource = type(obj.resource) == "table" and obj.resource[1] or obj.resource
			 if FindSupplyReq(obj, resource) then
				return true, T{4397, "<UnitMoveControl('ButtonA',interaction_mode)>: Get resources", self}
			end
		elseif IsKindOf(obj, "SurfaceDeposit") and TestReq(obj.transport_request, nil, 1) then
			return true, T{4402, "<UnitMoveControl('ButtonA',interaction_mode)>: Gather", self}
		elseif IsKindOf(obj, "Drone") and obj:IsDisabled() then
			if obj:IsDead() then
				return false
			elseif obj:IsLowBattery() then
				return true, T{9615, "<UnitMoveControl('ButtonA',interaction_mode)>: Transfer Power", self}
			elseif obj:IsBroken() then
				return true, T{9720, "<UnitMoveControl('ButtonA',interaction_mode)>: Repair", self}
			end	
			return false
		elseif self:InteractionObjTest_PickupFromRCTransport(obj) then
			return self:InteractionObjCheck_PickupFromRCTransport(obj)
		elseif self:InteractionObjTest_LandscapeConstruct(obj) then
			return self:InteractionObjCheck_LandscapeConstruct(obj)
		elseif self:InteractionObjTest_Construct(obj) then
			return self:InteractionObjCheck_Construct(obj)
		elseif IsKindOf(obj, "ToxicPool") and obj:CanBeCleaned() then
			return true, T{12052, "<UnitMoveControl('ButtonA',interaction_mode)>: Clean", self}
		end	
		return false, GetUIStyleGamepad() and  T{4339, "<UnitMoveControl('ButtonA',interaction_mode)>: Move",self} or false
	elseif self.interaction_mode == "reassign" or self.interaction_mode == "reassign_all" then
		if obj ~= self.command_center and IsKindOf(obj, "DroneControl") and obj.can_control_drones then
			if obj:CanHaveMoreDrones() then
				return true, T{4400, "<UnitMoveControl('ButtonA',interaction_mode)>: Assign to this command center",self}
			else
				if IsKindOf(obj, "SupplyRocket") and not obj.landed then
					return false
				else
					return false, T(4401, "<red>At full capacity</red>")
				end
			end	
		end
	elseif self.interaction_mode == "maintenance" then
		local carrying_resource = self:GetCarriedResource()
		local resource_demand_req = self:ShouldDeliverResourcesToBld(obj, self.resource)
		
		if self:InteractionObjTest_RepairSupplyGridElement(obj) then
			return self:InteractionCheck_RepairSupplyGridElement(obj, carrying_resource)
		elseif IsKindOf(obj, "Building") and obj.maintenance_phase then
			if obj.maintenance_resource_request == resource_demand_req then
				return true, T{4396, "<UnitMoveControl('ButtonA',interaction_mode)>: Deliver <resource(amount, resource)>", amount = self.amount, resource = self.resource, self}
			else
				local d_req = obj.maintenance_resource_request
				if d_req and (not d_req:CanAssignUnit() or d_req:GetTargetAmount() <= 0) then
					--don't show as interactable, if other drone is already working on it and the interaction itself does not interrupt it.
					return false
				end
				if obj.maintenance_phase == "demand" then
					local source = MapFindNearest(self, self, Drone_AutoFindResourceRadius, "ResourceStockpile", "ResourcePile", "SurfaceDeposit", "StorageDepot", ResourceSources_func, d_req:GetResource(), DroneResourceUnits[d_req:GetResource()])
					if not source then
						return false, T{4393, "<red>Cannot find any <resource_icon> nearby</red>", resource_icon = TLookupTag("<icon_" .. d_req:GetResource() .. ">")}, true
					end
				end
				
				return true, T{4394, "<UnitMoveControl('ButtonA',interaction_mode)>: Repair this building", self}
			end
		elseif IsKindOf(obj, "Drone") and obj:IsDisabled() then
			return true, T{4403, "<UnitMoveControl('ButtonA',interaction_mode)>: Repair this Drone",self}
		elseif IsKindOf(obj, "BaseRover") and obj:IsMalfunctioned() then
			if  obj.repair_work_request:CanAssignUnit() then
				return true, T{7588, "<UnitMoveControl('ButtonA',interaction_mode)>: Repair this vehicle",self}	
			elseif IsKindOf(obj, "AttackRover") and (not UICity.mystery.enable_rover_repair or not obj.is_repair_request_initialized) then
				return false, ""
			else
				return false, T(7589, "<red>Too many Drones are repairing this vehicle</red>"), true
			end
		end
	else
		print("unknown drone interaction mode.")
	end
end

function Drone:InteractWithObject(obj, interaction_mode)
	if self:IsDisabled() then return false end
	
	local carrying_resource = self:GetCarriedResource()
	local drop_resource = false
	
	if self.interaction_mode == false or self.interaction_mode == "default" or self.interaction_mode == "move" then
		--[[
		-- from 122882
		 - (if on a broken building) fix it
		- (if on a charging station) charge if it is working
		- (if carrying resource that's required by target building/construction) drop-off the resource on target
		- (if not carrying a resource and target is a storage or building) in case there are more than one resources to pick ask which resource with the current popup menu then pick-up the resource
		- (if on a construction that has all the resources) help the construction (if too many drones are constructing - give a message that it's too crowded there as an alert in the infopanel)
		- (if target is a drone hub or a rover) if it can take more drones assign itself to target if not, show a message as an alert in the infopanel
		- (if target is a position) go to there and wait a minute before becoming idle
		]]
		
		local resource_demand_req = self:ShouldDeliverResourcesToBld(obj, self.resource)
		if resource_demand_req then --we are carrying a resource and this bld needs it, or is a storage depot that accepts it
			if assign_to_req_helper(self, resource_demand_req) then
				self:SetCommandUserInteraction("Deliver", resource_demand_req, true)
			end
		elseif IsKindOf(obj, "Tunnel") then
			if obj.working then
				self:SetCommandUserInteraction("UseTunnel", obj)
				SetUnitControlInteractionMode(self, false) --toggle button
			end
		elseif IsKindOf(obj, "BaseRover") and obj:IsMalfunctioned() and obj.repair_work_request:CanAssignUnit() then
			drop_resource = true
			local request = obj.repair_work_request
			self:SetCommandUserInteraction("Work", request, "repair", Min(DroneResourceUnits.repair, request:GetTargetAmount()))
		elseif (IsKindOf(obj, "RechargeStation") or
				(IsKindOfClasses(obj, "RechargeStationBase", "DroneHub") and obj == self.command_center)) --if we select our command center go charge there
				and obj.working then 
			if IsKindOf(obj, "DroneHub") then
				obj = FindNearestObject(obj:GetAttaches("RechargeStationBase"), self)
			end
			self:SetCommandUserInteraction("EmergencyPower", obj)
		elseif obj ~= self.command_center and IsKindOf(obj, "DroneControl") and obj:CanHaveMoreDrones() then
			drop_resource = true
			self:SetCommandCenterUser(obj)
		elseif self:InteractionObjTest_RepairSupplyGridElement(obj) then
			self:Interaction_RepairSupplyGridElement(obj, carrying_resource)
		elseif IsKindOf(obj, "Building") and (obj.maintenance_phase or obj.accumulated_maintenance_points > 0) then
			if obj.maintenance_phase == "work" then
				drop_resource = true
				self:SetCommandUserInteraction("Work", obj.maintenance_work_request, "repair", Min(DroneResourceUnits.repair, obj.maintenance_work_request:GetTargetAmount()))
			else
				if not obj.maintenance_phase then
					obj:RequestMaintenance()
				end
				local d_req = obj.maintenance_resource_request
				if d_req:CanAssignUnit() and d_req:GetTargetAmount() > 0 then
					local resource = d_req:GetResource()
					if self.resource == resource then
						if assign_to_req_helper(self, d_req) then
							self:SetCommandUserInteraction("Deliver", d_req, true)
						end
					else
						drop_resource = true
						local source = MapFindNearest(self, self, Drone_AutoFindResourceRadius, "ResourceStockpile", "ResourcePile", "SurfaceDeposit", "StorageDepot", ResourceSources_func,resource, DroneResourceUnits[resource])
						if source then
							local request = GetSupplyReq(source, resource)
							self:SetCommandUserInteraction("PickUp", request, d_req, resource, Min(DroneResourceUnits[resource], request:GetTargetAmount(), obj.maintenance_resource_request:GetActualAmount()))
						end
					end
				end
			end
		elseif not carrying_resource and obj:IsKindOfClasses("ResourceStockpileBase", "StorageDepot", "ResourcePile") and not obj:IsKindOfClasses("Unit") and obj:GetStoredAmount() > 0 then
			if type(obj.resource) == "table" and #obj.resource > 1 then
				--more then one resource in this bld
				OpenResourceSelector(self, {target = obj})
			else
				local resource = type(obj.resource) == "table" and obj.resource[1] or obj.resource
				if resource == "WasteRock" and g_WasteRockLiquefaction and obj:IsKindOf("WasteRockDumpSite") then
					resource = "Concrete"
				end
				
				local request = FindSupplyReq(obj, resource)
				local interrupted = false
				
				if request and request:GetTargetAmount() <= 0 and request:GetTargetAmount() ~= request:GetActualAmount() then
					--a drone is already incoming to pick this up.
					--interrupt one
					obj:InterruptDrones(nil, function(drone)
						if not interrupted and drone.s_request == request then
							interrupted = true
							return drone
						end
					end,
					function (drone) if interrupted then return "break" end end) --early out
				end
				
				if request and (interrupted or request:GetTargetAmount() > 0) then --if we interrupted another drone, req wont be up to date yet, but it should be until cmd thread boots up.
					self:SetCommandUserInteraction("PickUp", request, false, resource, Min(DroneResourceUnits[resource], not interrupted and request:GetTargetAmount() or request:GetActualAmount()), true)
				end
			end
		elseif IsKindOf(obj, "SurfaceDeposit") and TestReq(obj.transport_request, nil, 1) then
			drop_resource = true
			local request = obj.transport_request
			local resource = request:GetResource()
			self:SetCommandUserInteraction("PickUp", request, false, resource, Min(DroneResourceUnits[resource], request:GetTargetAmount()))
		elseif IsKindOf(obj, "Drone") and obj:IsDisabled() then
			drop_resource = true
			if obj.repair_drone then
				obj.repair_drone:SetCommand("Reset")
			end
			self:SetCommand("RepairDrone", obj, g_Consts.DroneEmergencyPower)
			self:SetInteractionState(false)
		elseif self:InteractionObjTest_PickupFromRCTransport(obj) then
			return self:Interaction_PickupFromRCTransport(obj)
		elseif self:InteractionObjTest_LandscapeConstruct(obj) then
			return self:Interaction_LandscapeConstruct(obj)
		elseif self:InteractionObjTest_Construct(obj) then
			return self:Interaction_Construct(obj)
		elseif IsKindOf(obj, "ToxicPool") and obj:CanBeCleaned() then
			local request = obj.clean_request
			self:SetCommandUserInteraction("PickUp", request, false, "WasteRock", Min(DroneResourceUnits.WasteRock, request:GetTargetAmount()))
			return true
		end
	elseif self.interaction_mode == "reassign" then
		-- "Reassign" - assign to target hub/rover
		if obj ~= self.command_center and IsKindOf(obj, "DroneControl") and obj:CanHaveMoreDrones() then
			drop_resource = true
			self:SetCommandCenterUser(obj)
		end
	elseif self.interaction_mode == "reassign_all" then
		-- "Reassign All" - assign to target hub/rover all nearby drones up to controller capacity
		if obj ~= self.command_center and IsKindOf(obj, "DroneControl") and obj:CanHaveMoreDrones() then
			local count = obj:GetMaxDrones() - #obj.drones - 1
			-- add more drones
			if count>0 then
				local drones = IsValid(self.command_center)
					and self.command_center.drones
					 or MapGet(self:GetPos(), 100*guim, 
								 "Drone", function(d) 
											return d~=self 
												and d:CanBeControlled() 
												and not IsValid(d.command_center) 
												and obj ~= d.command_center 
											end)
				local i=#drones
				while count>0 and i>0 do
					local drone = drones[i]
					if drone ~= self and drone:CanBeControlled() then
						drone:SetCommandCenterUser(obj, true)
						count =  count -1
					end
					i = i - 1
				end
			end
			drop_resource = true
			self:SetCommandCenterUser(obj)
		end	
	elseif self.interaction_mode == "maintenance" then
		-- "Maintenance" - Select a target to repair, charge or perform maintenance (including drones, rovers, etc), if target is a charger, charge self (self maintenance)
		local carrying_resource = self:GetCarriedResource()
		local resource_demand_req = self:ShouldDeliverResourcesToBld(obj, self.resource, self.amount)
		
		if self:InteractionObjTest_RepairSupplyGridElement(obj) then
			self:Interaction_RepairSupplyGridElement(obj, carrying_resource)
		elseif IsKindOf(obj, "Building") and obj.maintenance_phase then
			if obj.maintenance_phase == "work" then
				drop_resource = true
				self:SetCommandUserInteraction("Work", obj.maintenance_work_request, "repair", Min(DroneResourceUnits.repair, obj.maintenance_work_request:GetTargetAmount()))
			elseif obj.maintenance_resource_request == resource_demand_req and assign_to_req_helper(self, resource_demand_req) then
				self:SetCommandUserInteraction("Deliver", resource_demand_req, true)
			else
				drop_resource = true
				local resource = obj.maintenance_resource_request:GetResource()
				local source = MapFindNearest(self, self, Drone_AutoFindResourceRadius, "ResourceStockpile", "ResourcePile", "SurfaceDeposit", "StorageDepot", ResourceSources_func, resource, DroneResourceUnits[resource])
				if source then
					local request = GetSupplyReq(source, resource)
					self:SetCommandUserInteraction("PickUp", request, obj.maintenance_resource_request, resource, Min(DroneResourceUnits[resource], request:GetTargetAmount()))
				end
			end
			
			self:SetInteractionState(false)
		elseif IsKindOf(obj, "Drone") and obj:IsDisabled() then
			drop_resource = true
			if obj.repair_drone then
				obj.repair_drone:SetCommand("Reset")
			end
			self:SetCommand("RepairDrone", obj, g_Consts.DroneEmergencyPower)
			self:SetInteractionState(false)
		elseif IsKindOf(obj, "BaseRover") and obj:IsMalfunctioned() and obj.repair_work_request:CanAssignUnit() then
			drop_resource = true
			local request = obj.repair_work_request
			self:SetCommandUserInteraction("Work", request, "repair", Min(DroneResourceUnits.repair, request:GetTargetAmount()))	
			self:SetInteractionState(false)
		end
	end
	
	if drop_resource and carrying_resource then
		self:DropCarriedResource()
	end
end

function Drone:SetCommandCenterUser(obj, drop_resource_now)
	self:SetCommandCenter(obj)
	if self.command == "WaitingCommand" then --no cmd center cmd
		self:SetCommandUserInteraction("Idle")
	elseif self:CanBeControlled() then --all other interuptable cmds
		self:SetCommandUserInteraction("Reset")
	end
	
	self:SetInteractionState(false)
	
	if drop_resource_now then
		self:DropCarriedResource()
	end
end

function Drone:ResetUnitControlInteractionState()
	SetUnitControlInteraction(false, self)
end

function Drone:GetSelectorItems(dataset)
	dataset.on_close_callback = function()
		self:ResetUnitControlInteractionState()
	end
	
	local items = {}
	
	for i=1, #AllResourcesList do
		local res_id = AllResourcesList[i]
		if not dataset.target or dataset.target:DoesAcceptResource(res_id)
									and dataset.target:GetStoredAmount(res_id) > 0 then
			local res = Resources[res_id]
			if res then
				table.insert(items, {
						name = res_id, 
						icon = res.display_icon,
						display_name = res.display_name,
						description  = T{4404, "Order the drone to load <resource_name>.", resource_name = res.display_name},
						action = function(dataset)
							local req = FindSupplyReq(dataset.target, res_id)
							if req then
								local pickup_amount = Min(DroneResourceUnits[res_id], req:GetTargetAmount())
								if TestReq(req, res_id, pickup_amount) then
									dataset.object:SetCommandUserInteraction("PickUp", req, false, res_id, pickup_amount, true)
								end
							end
						end
					})
			end
		end
	end
	
	return items
end
--[[
function Drone:Getui_control_hint()
	return GetUnitControlInteractionHint(self, T{4339, "<UnitMoveControl()>: Move"} ,T{4392, "This Drone is disabled"})
end
--]]
function Drone:OnSelected()
	SelectionArrowAdd(self)
end

function Drone:GetCommand() return Untranslated(self.command) end
function Drone:GetAmount() return self.resource and self.amount/const.ResourceScale or "" end
function Drone:GetResource() 
	if Platform.developer and (self.resource=="construct" or self.resource=="repair" or self.resource=="clean") then
		return Untranslated(self.resource)
	end	
	
	return self.resource and Resources[self.resource] and Resources[self.resource].display_name or T(720, "Nothing")
end
function Drone:GetResourceAmount() 
	return Resources[self.resource] and T(7395, "<resource(amount,resource)>") or T(720, "Nothing")
end

function Drone:GetTarget()
	local target = self.target or self.goto_target
	if IsPoint(target) then return T(7396, "Location") end
	while IsValid(target) and target:HasMember("parent") and target.parent and target.parent ~= target do
		target = target.parent
	end
	return IsValid(target) and (target:HasMember("GetDisplayName") and target:GetDisplayName() or Platform.developer and IsKindOf("Object") and Untranslated(target.class)) or ""
end

function Drone:SelectTarget()
	local target = self.target or self.goto_target
	
	while IsValid(target) and target:HasMember("parent") and target.parent and target.parent ~= target do
		target = target.parent
	end
	if IsValid(target) and target:HasMember("Select") then
		target:Select()
	end
end

function Drone:GetDestName()
	return self:GetTarget() ~= "" and T(4439, "Going to<right><h SelectTarget InfopanelSelect><Target></h>") or T(7397, "No particular destination")
end

function Drone:GetCommandCenterName()
	local obj = self.command_center
	return obj and obj:GetDisplayName() or T(6761, "None")
end

function Drone:SelectCommandCenter()
	if self.command_center then
		self.command_center:Select()
	end	
end

function Drone:CheatDespawn()
	SelectObj(false)
	if IsValid(self.command_center) then
		self.command_center:KillDrone(self)
	else
		DoneObject(self)
	end
end

function Drone:CheatDrainBattery()
	self.battery = 0
	self:SetCommand("NoBattery")
end

function Drone:CheatMalfunction()
	self.dust = self.dust_max + 10 
	self:SetCommand("Malfunction")
end

function Drone:CheatRechargeBattery()
	self.battery = self.battery_max
end

DroneCommands = {
	Goto = T(63, "Travelling"),
	GotoFromUser = T(63, "Travelling"),
	Malfunction = T(65, "Malfunctioned"),
	NoBattery = T(4406, "Out of Power"),
	Charge = T(4407, "Recharging"),
	Idle = T(6939, "Idle"),
	RepairDrone = T(4408, "Repairing Drone"),
	RechargeDrone = T(8503, "Recharging Drone"),
	Work = T(76, "Performing maintenance"),
	mine = T(4409, "Working in mine"),
	construct = T(57, "Constructing"),
	WaitingCommand = T(4410, "Waiting for tasks"),
	Deliver = T(7398, "Delivering <Resource>"),
	PickUp = T(4411, "Going to pick up <SRequestResource>"),
	Freeze = T(12298, "<red>This unit is frozen and can be fixed when the Cold Wave is over or when the area is heated.</red>"),
	Dead = T(4413, "<red>This unit has been destroyed. It can be salvaged for materials.</red>"),
	GoHome = T(4414, "Deploying"),
	ReturningToController = T(8105, "Returning to controller"), --gohome alt str
	Embark = T(9799, "Inside RC Commander"),
	RecallToRover = T(4416, "Returning to RC Commander"),
	DestroyingBlackCubes = T(4417, "Destroying Black Cubes"),
	UseTunnel = T(6723, "Going through a tunnel"),
	Dismantle = T(8106, "Dismantling target"),
	DespawnAtHub = T(8663, "Returning to Drone Hub to be dismantled into a Drone Prefab"),
	GotoAndEmbark =  T(11216, "Boarding Rocket"),
	CleanLSCS = T(12600, "Clearing Waste Rock"),
	WorkLSCS = T(12601, "Flattening site"),
	PickUpLSCS = T(12602, "Extracting Waste Rock"), --for 100 secs
	DeliverLSCS = T(12603, "Depositing Waste Rock"), --for 100 secs
	WaitingCommand = T(12549, "<red>Orphaned Drone. Assign to a Drone commander.</red>")
}

function Drone:GetSRequestResource()
	local res = Resources[self.s_request and self.s_request:GetResource()]
	return res and res.display_name or ""
end

local DisablingCommands = {
	Malfunction = true,
	NoBattery = true,
	Freeze = true,
	Dead = true,
	DespawnAtHub = true,
	DieNow = true,
}

function Drone:IsDisabled()
	return DisablingCommands[self.command] or false 
end

local BrokenCommands = {
	Malfunction = true,
	NoBattery = true,
	Freeze = true,
}

function Drone:IsLowBattery()
	return self.battery < self.battery_max / 4
end

function Drone:IsBroken()
	return BrokenCommands[self.command] or false 
end

function Drone:IsDead()
	return not IsValid(self) or self.command == "Dead" or self.command == "DespawnAtHub" or self.command == "DieNow"
end

function Drone:IsDeadUI()
	return self.command == "Dead"
end

function Drone:SetCommandUserInteraction(command, ...)
	self:SetCommand(command, ...)
	self.idle_wait = DelayAfterUserCommands[command] or false --wait == last queued cmd
end

function Drone:SaveCompatDifferentiateDisablingFromBroken()
	local in_list = self:IsDisabled()
	self.is_broken = self:IsBroken()
	
	if self.is_broken and not in_list then
		table.insert(g_BrokenDrones, self)
	elseif not self.is_broken and in_list then
		table.remove_entry(g_BrokenDrones, self)
	end
end

function Drone:SetCommand(command, ...)
	self.idle_wait = false
	local is_disabling = DisablingCommands[command]
	if not self.is_disabled and is_disabling then
		self.is_disabled = true
	elseif self.is_disabled and not is_disabling then
		self.is_disabled = false
	end
	
	local is_braking = BrokenCommands[command]
	if not self.is_broken and is_braking then
		if not self.rogue then
			table.insert(g_BrokenDrones, self)
		end
		self.is_broken = true
	elseif self.is_broken and not is_braking then
		table.remove_entry(g_BrokenDrones, self)
		self.is_broken = false
	end
	
	DroneBase.SetCommand(self, command, ...)
end

Drone.SetDisablingCommand = Drone.SetCommand

function Drone:Getui_command()
	if self:IsDeadUI() then
		return DroneCommands.Dead
	elseif (self.command_center and not self.command_center.working) then
		return T(12550, "<red>Not receiving commands. Drone commander is not working.</red>")
	elseif self.command == "Idle" then
		return T(4418, "No orders")
	else
		local resource = DroneCommands[self.override_ui_status or self.resource]
		if resource then
			return resource
		end
		local command = self.override_ui_status or self.command
		if command == "EmergencyPower" then
			return  self.going_to_recharger and 
				T(8504, "Going to recharge batteries") or
				self.queued_at_recharger and 
				T(4420, "Waiting for recharge station to become available") or 
				T(4421, "Searching for a recharge station")
		end
		
		if command == "Work" and IsKindOf(self.target, "BlackCubeStockpileBase") then
			return DroneCommands.DestroyingBlackCubes
		end
		
		return DroneCommands[command] or T(77, "Unknown")
	end
end

function Drone:GetBatteryProgress()
	return MulDivRound(self.battery, 100, self.battery_max)
end

function Drone:OnDemolish()
	local carried_resource = self:GetCarriedResource()
	local metals_amount = 1
	if carried_resource then
		if carried_resource == "Metals" then
			metals_amount = metals_amount + 1
		else
			PlaceResourceStockpile_Delayed(self:GetVisualPos(), carried_resource, self.amount, self:GetAngle(), true)
		end
	end
	PlaceResourceStockpile_Delayed(self:GetVisualPos(), "Metals", metals_amount*const.ResourceScale, self:GetAngle(), true)
end

function Drone:GetRefundResources()
	return {
		{ resource = "Metals", amount = 1 * const.ResourceScale },
	}
end

function Drone:GetDisplayName()
	return Untranslated(self.name)
end

function Drone:ChangeSkin(skin, palette)
	self:OnSkinChanged(skin, palette)
	local cc = self.command_center
	for _, drone in ipairs(cc and cc.drones or empty_table) do
		if drone ~= self then
			drone:OnSkinChanged(skin, palette)
		end
	end
end

function Drone:OnSkinChanged(skin, palette)
	self:ChangeEntity(skin)
	self:NightLightDisable()
	self:NightLightEnable()
end

function Drone:GetSkins()
	local skins = table.copy(self.default_skins)
	skins[#skins+1] = g_TrailblazerSkins.Drone -- OK if nil
	return skins
end

function Drone:GetUIWarning()
	if self.demolishing then
		return T{7399, "The Drone will be salvaged in <em><countdown></em> sec.",
			countdown = function(obj) return obj.demolishing_countdown / 1000 end, }
	end
end

function DroneClassComboItems()
	local items = { {value = false, text = ""} }
	ClassDescendants("Drone", function(classname, classdef)
		items[#items + 1] = { value = classname, text = classdef.display_name }
	end)
	return items
end

function City:CreateDrone()
	return Drone:new{ city = self }
end

----

function OnMsg.GatherFXActions(list)
	list[#list + 1] = "Spawn"
	list[#list + 1] = "Working"
	list[#list + 1] = "Breakdown"
	list[#list + 1] = "NoBattery"
	list[#list + 1] = "Moving"
	list[#list + 1] = "Repair"
	list[#list + 1] = "Recharge"
	list[#list + 1] = "EmergencyRecharge"
	list[#list + 1] = "EmergencyPower"
	list[#list + 1] = "Clean"
	list[#list + 1] = "Construct"
	list[#list + 1] = "WaitingCommand"
	list[#list + 1] = "RechargeStation"
	list[#list + 1] = "Freeze"
	list[#list + 1] = "Dead"
end

function OnMsg.GatherFXActors(list)
	list[#list + 1] = "RechargeStation"
end

----

if Platform.developer then
function dbg_DrainAllDrones()
	MapForEach("map", "Drone", function(o) o.battery = g_Consts.DroneEmergencyPower * 2 - 1 end)
end

function dbg_TestForDetached()
	for _, drone in ipairs(UICity.labels.Drone) do
		assert(drone:GetPos() ~= InvalidPos())
	end
end

function dbg_TestRockets()
	for _, rocket in ipairs(UICity.labels.SupplyRocket) do
		print(#rocket.drones_exiting, #rocket.drones_entering)
	end
end

function dbg_GetDetachedDrone()
	for _, drone in ipairs(SelectedObj.drones) do if drone:GetPos() == InvalidPos() then return drone end end
end
end

function OnMsg.PostNewMapLoaded()
	--fix poc maps
	CreateGameTimeThread(function()
		--lbl is empty out of thread
		local lbl = UICity and UICity.labels.Drone
		for i = #(lbl or ""), 1, -1 do
			local d = lbl[i]
			if not IsValid(d) then
				table.remove(lbl, i)
			elseif d:GetPos() == InvalidPos() and not d.holder and not d:GetParent() then
				if d.command_center then
					local p = d.command_center:GetPos()
					p = GetPassablePointNearby(p, d.pfclass)
					d:SetPos(p)
				else
					DoneObject(d)
					table.remove(lbl, i)
				end
			end
		end
	end)
end