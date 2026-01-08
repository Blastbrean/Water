local Water = {
	hitFromAnywhere = true,
	instantSpin = true,
	alwaysMaxServePower = true,
	silentUnlockedCamera = true,

	autoGuard = true,
	autoGuardDebugging = true,
	autoGuardTeleporting = false,
	autoGuardRedirectTowardsCenter = true,
}

local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local Logger = require("utility/logger")
local Maid = require("utility/maid")
local Hooking = require("utility/hooking")
local Gizmos = require("utility/gizmos")
local BallNetworking = require("utility/ball_networking")

local AutoGuard = require("auto_guard")

local Knit = require(replicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local abilityController = nil

while not abilityController do
	abilityController = Knit.GetController("AbilityController")
	task.wait()
end

local styleController = nil

while not styleController do
	styleController = Knit.GetController("StyleController")
	task.wait()
end

local abilityService = nil

while not abilityService do
	abilityService = Knit.GetService("AbilityService")
	task.wait()
end

local styleService = nil

while not styleService do
	styleService = Knit.GetService("StyleService")
	task.wait()
end

local oldNameCall = nil
local oldAbilitySpin = nil
local oldStyleSpin = nil
local oldIndex = nil

local function onGetPartsInPart(...)
	if not Water.hitFromAnywhere then
		return oldNameCall(...)
	end

	local taggedBalls = collectionService.GetTagged(collectionService, "Ball")
	if not taggedBalls or #taggedBalls == 0 then
		return oldNameCall(...)
	end

	local ballParts = {}

	for _, taggedBall in next, taggedBalls do
		local ballPart = taggedBall.FindFirstChildWhichIsA(taggedBall, "BasePart")
		if not ballPart then
			continue
		end

		table.insert(ballParts, ballPart)
	end

	return ballParts
end

local function onSetInteract(data)
	if not Water.autoGuardRedirectTowardsCenter then
		return
	end

	if not checkcaller() then
		return
	end

	local map = workspace.FindFirstChild(workspace, "Map")
	if not map then
		return
	end

	local ballNoCollide = map.FindFirstChild(map, "BallNoCollide")
	if not ballNoCollide then
		return
	end

	local boundaries = ballNoCollide.FindFirstChild(ballNoCollide, "Boundaries")
	if not boundaries then
		return
	end

	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character.FindFirstChild(character, "HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local nearestPart = nil
	local nearestDistance = nil

	for _, part in next, boundaries.GetChildren(boundaries) do
		if not game.IsA(part, "BasePart") then
			continue
		end

		local distance = (part.Position - humanoidRootPart.Position).Magnitude

		if nearestDistance and distance > nearestDistance then
			continue
		end

		nearestPart = part
		nearestDistance = distance
	end

	if not nearestPart then
		return
	end

	local snappedPosition = Vector3.new(nearestPart.Position.X, humanoidRootPart.Position.Y, nearestPart.Position.Z)

	data["LookVector"] = (snappedPosition - humanoidRootPart.Position).Unit
end

local function onInteractInvokeServer(...)
	local args = { ... }
	local data = args[2]

	if Water.silentUnlockedCamera then
		data["LookVector"] = workspace.CurrentCamera.CFrame.LookVector
	end

	if data["Move"] == "Set" then
		onSetInteract(data)
	end

	return oldNameCall(unpack(args))
end

local function onServeInvokeServer(...)
	local args = { ... }

	args[3] = Water.alwaysMaxServePower and 1.0 or args[3]

	return oldNameCall(unpack(args))
end

local function onDiveMoveDirection(...)
	if not checkcaller() then
		return oldIndex(...)
	end

	return AutoGuard.wantedDiveDirection
end

local function onIndex(...)
	local args = { ... }
	local index = args[2]

	if index == "MoveDirection" and debug.getinfo(3).name == "Dive" then
		return onDiveMoveDirection(...)
	end
	return oldIndex(...)
end

local function onNameCall(...)
	local args = { ... }
	local self = args[1]

	if getnamecallmethod() == "InvokeServer" then
		if self.name == "Interact" then
			return onInteractInvokeServer(...)
		end

		if self.Name == "Serve" then
			return onServeInvokeServer(...)
		end

		return oldNameCall(...)
	end

	if getnamecallmethod() == "DistanceFromCharacter" then
		return Water.hitFromAnywhere and 0.0 or oldNameCall(...)
	end

	if getnamecallmethod() == "GetPartsInPart" then
		return onGetPartsInPart(...)
	end

	return oldNameCall(...)
end

local function onAbilitySpin(...)
	local args = { ... }

	if Water.instantSpin then
		return abilityService:Roll(args[2] or false)
	end

	return oldAbilitySpin(...)
end

local function onStyleSpin(...)
	local args = { ... }

	if Water.instantSpin then
		return styleService:Roll(args[2] or false)
	end

	return oldStyleSpin(...)
end

function Water.init()
	oldNameCall = Hooking.metamethod(game, "__namecall", onNameCall)
	oldIndex = Hooking.metamethod(game, "__index", onIndex)
	oldAbilitySpin = Hooking.func(abilityController.Spin, onAbilitySpin)
	oldStyleSpin = Hooking.func(styleController.Spin, onStyleSpin)

	Gizmos.init()
	BallNetworking.init()
	AutoGuard.init()

	Logger.warn("Water has initialized. Hello, ServerScriptService.AnticheatService logging :)")
end

function Water.detach()
	Maid.cleanAll()

	Logger.warn("Water has been detached.")
end

return Water
