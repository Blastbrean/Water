local Water = {
	hitFromAnywhere = true,
	instantSpin = true,

	---@todo: Improve this feature...
	-- Fix 'gizmos' library not drawing with correct color
	autoGuard = true,

	---@todo: Silent unlocked camera
}

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local Logger = require("utility/logger")
local Maid = require("utility/maid")
local Hooking = require("utility/hooking")
local Gizmos = require("utility/gizmos")

local Physics = require(replicatedStorage:WaitForChild("Common"):WaitForChild("Physics"))
local Knit = require(replicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local MockPlayer = require(replicatedStorage:WaitForChild("Tools"):WaitForChild("CharBot"):WaitForChild("MockPlayer"))

local gameController = nil

while not gameController do
	gameController = Knit.GetController("GameController")
	task.wait()
end

local abilityController = nil

while not abilityController do
	abilityController = Knit.GetController("AbilityController")
	task.wait()
end

local abilityService = nil

while not abilityService do
	abilityService = Knit.GetService("AbilityService")
	task.wait()
end

local oldNameCall = nil
local oldDistanceFromCharacter = nil
local oldSpin = nil

local waterMaid = Maid.new()

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
		if not part:IsA("BasePart") then
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

	data["LookVector"] = (humanoidRootPart.Position - nearestPart.Position).Unit
end

local function onInteractInvokeServer(self, ...)
	local args = { ... }
	local data = args[2]

	print(self.Name)
	if self.Name == "Interact" then
		if not checkcaller() then
			return oldNameCall(...)
		end

		if data["Move"] == "Spike" then
			data["TiltDirection"] = Vector3.new(0.0, 1.0, 1.0)
		end

		if data["Move"] == "Set" then
			onSetInteract(data)
		end
		return oldNameCall(unpack(args))
	elseif self.Name == "Serve" then
		args = { ... }
		args[3] = 1.0

		return oldNameCall(unpack(args))
	end
end

local function onNameCall(...)
	local args = { ... }
	local self = args[1]

	if getnamecallmethod() == "InvokeServer" and (self.Name == "Interact" or self.Name == "Serve") then
		return onInteractInvokeServer(self, ...)
	end

	if getnamecallmethod() == "GetPartsInPart" then
		return onGetPartsInPart(...)
	end

	return oldNameCall(...)
end

local function onSpin(...)
	local args = { ... }

	if Water.instantSpin then
		return abilityService:Roll(args[2] or false)
	end

	return oldSpin(...)
end

local function onDistanceFromCharacter(...)
	if Water.hitFromAnywhere then
		return 0.0
	end

	return oldDistanceFromCharacter(...)
end

local function onRenderStepped()
	if not Water.autoGuard then
		return
	end

	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local taggedBalls = collectionService:GetTagged("Ball")
	if not taggedBalls or #taggedBalls == 0 then
		return
	end

	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end

	local ballCollideOnly = map:FindFirstChild("BallCollideOnly")
	if not ballCollideOnly then
		return
	end

	local net = ballCollideOnly:FindFirstChild("Net")
	if not net then
		return
	end

	local court = map:FindFirstChild("Court")
	if not court then
		return
	end

	if not localPlayer.Team then
		return
	end

	for _, taggedBall in next, taggedBalls do
		local ballPart = taggedBall:FindFirstChildWhichIsA("BasePart")
		if not ballPart then
			continue
		end

		local distanceToBall = (humanoidRootPart.Position - ballPart.Position).Magnitude
		local hitType = distanceToBall <= 20 and "Set" or "Dive"
		local shouldIgnoreNetTop = false

		if gameController.IsJumping:get() then
			hitType = "Spike"
			shouldIgnoreNetTop = true
		end

		local isBallInBounds = false

		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = { ballPart }
		overlapParams.FilterType = Enum.RaycastFilterType.Include

		local partsInCourt = workspace:GetPartBoundsInBox(court.CFrame, Vector3.new(52, 50, 102), overlapParams)

		if #partsInCourt > 0 then
			isBallInBounds = true
		end

		local lastHitter = replicatedStorage:GetAttribute("LastHitter")
		local lastHitTeam = replicatedStorage:GetAttribute("LastHitTeam")
		local servedByTeam = replicatedStorage:GetAttribute("ServedByTeam")

		local isOnCorrectSide = Physics.isPointOnTeamSide(localPlayer, ballPart.Position, nil)
		local isBelowNetTop = ballPart.Position.Y <= net.Position.Y + net.Size.Y
		local isTooFar = distanceToBall <= 50
		local isBallInPlay = replicatedStorage:GetAttribute("IsBallInPlay") == true
		local isLastTouchValid = lastHitTeam and lastHitTeam ~= localPlayer.Team.Name
		local isNotAerialOnServe = not (gameController.IsJumping:get() and servedByTeam ~= nil)

		if shouldIgnoreNetTop then
			isBelowNetTop = true
		end

		local isValid = isOnCorrectSide
			and isBelowNetTop
			and isTooFar
			and isBallInPlay
			and isLastTouchValid
			and isNotAerialOnServe
			and isBallInBounds

		local status = {}

		local lastHitTimestamp = replicatedStorage:GetAttribute("LastHitTimestamp") or 0.0
		local lastHitPosition = replicatedStorage:GetAttribute("LastHitPosition") or Vector3.new(0.0, 0.0, 0.0)
		local teamHitStreak = replicatedStorage:GetAttribute("TeamHitStreak") or 0
		local servesInRow = replicatedStorage:GetAttribute("ServesInRow") or 0

		status[#status + 1] =
			{ ["Label"] = "Distance to ball", ["Value"] = string.format("%.2f studs", distanceToBall) }

		status[#status + 1] = {
			["Label"] = "Last team touch",
			["Value"] = string.format("%s (served by %s)", tostring(lastHitTeam or "?"), tostring(servedByTeam or "?")),
		}

		status[#status + 1] = {
			["Label"] = "Game touches",
			["Value"] = string.format("%i team hit streak (%i serves in row)", teamHitStreak, servesInRow),
		}

		status[#status + 1] = { ["Label"] = "On correct side?", ["Value"] = isOnCorrectSide and "✓" or "X" }
		status[#status + 1] =
			{ ["Label"] = "Below net top?", ["Value"] = shouldIgnoreNetTop and "I" or (isBelowNetTop and "✓" or "X") }

		status[#status + 1] = { ["Label"] = "Within range?", ["Value"] = isTooFar and "✓" or "X" }
		status[#status + 1] = { ["Label"] = "Ball in play?", ["Value"] = isBallInPlay and "✓" or "X" }
		status[#status + 1] = { ["Label"] = "Valid last touch?", ["Value"] = isLastTouchValid and "✓" or "X" }
		status[#status + 1] = { ["Label"] = "Not aerial on serve?", ["Value"] = isNotAerialOnServe and "✓" or "X" }
		status[#status + 1] = { ["Label"] = "Ball in bounds?", ["Value"] = isBallInBounds and "✓" or "X" }

		local text = string.format("Auto guard status (%s)", hitType)

		for _, entry in ipairs(status) do
			text = text .. "\n" .. string.format("%s: %s", entry.Label, entry.Value)
		end

		Gizmos.setPosition(ballPart.Position + Vector3.new(0, 5, 0))
		Gizmos.setColor3(isValid and Color3.new(0.0, 1.0, 0.0) or Color3.new(1.0, 0.0, 0.0))
		Gizmos.drawText(text)

		if lastHitPosition then
			Gizmos.setPosition(lastHitPosition)
			Gizmos.setColor3(Color3.new(1.0, 0.0, 1.0))
			Gizmos.drawPoint()
			Gizmos.setPosition(lastHitPosition + Vector3.new(0, 5, 0))

			local info = {}

			local previousHitter = replicatedStorage:GetAttribute("PreviousHitter")
			local lastHitType = replicatedStorage:GetAttribute("LastHitType")

			info[#info + 1] = {
				["Label"] = "Hit position",
				["Value"] = string.format(
					"(%.2f, %.2f, %.2f)",
					lastHitPosition.X,
					lastHitPosition.Y,
					lastHitPosition.Z
				),
			}

			info[#info + 1] = { ["Label"] = "Last hitter", ["Value"] = tostring(lastHitter) }
			info[#info + 1] = { ["Label"] = "Previous hitter", ["Value"] = tostring(previousHitter) }
			info[#info + 1] = { ["Label"] = "Hit type", ["Value"] = tostring(lastHitType) }
			info[#info + 1] = { ["Label"] = "Hit time", ["Value"] = string.format("%.2f", lastHitTimestamp) }

			local infoText = ""

			for _, entry in ipairs(info) do
				infoText = infoText .. "\n" .. string.format("%s: %s", entry.Label, entry.Value)
			end

			Gizmos.drawText(infoText)
		end

		if not isValid then
			continue
		end

		-- Before calling, set thread identity so we don't error from requiring
		setthreadidentity(2)

		if hitType == "Set" then
			gameController:DoMove("Set")
		end

		if hitType == "Spike" then
			gameController:DoMove("Spike")
		end

		if hitType == "Dive" then
			gameController:Dive({ Target = (ballPart.Position - humanoidRootPart.Position).Unit })
		end
	end
end

function Water.init()
	oldNameCall = hookmetamethod(game, "__namecall", onNameCall)
	oldDistanceFromCharacter = Hooking.func(MockPlayer.DistanceFromCharacter, onDistanceFromCharacter)
	oldSpin = Hooking.func(abilityController.Spin, onSpin)

	waterMaid:mark(runService.RenderStepped:Connect(onRenderStepped))

	Gizmos.init()

	Logger.warn("Water has initialized.")
end

function Water.detach()
	Maid.cleanAll()

	Logger.warn("Water has been detached.")
end

return Water
