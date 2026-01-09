local AutoGuard = { wantedDiveDirection = Vector3.zero }

local players = game:GetService("Players")
local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local Maid = require("utility/maid")
local Gizmos = require("utility/gizmos")
local Sheet = require("utility/sheet")
local BallNetworking = require("utility/ball_networking")

local GameMode = require(replicatedStorage:WaitForChild("Configuration"):WaitForChild("Gamemode"))
local Game = require(replicatedStorage:WaitForChild("Configuration"):WaitForChild("Game"))
local Physics = require(replicatedStorage:WaitForChild("Common"):WaitForChild("Physics"))
local Knit = require(replicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local gameController = nil

while not gameController do
	gameController = Knit.GetController("GameController")
	task.wait()
end

local autoGuardMaid = Maid.new()

local ballHistory = {}
local BALL_HISTORY_MAX_POINTS = 500

local predictedLandingHistory = {}
local PREDICTED_LANDING_MAX_POINTS = 5
local PREDICTED_LANDING_TOO_CLOSE_LIMIT = 0.5

local PREDICTION_TIME_STEP = 1 / 60
local PREDICTION_MAX_TIME = 5.0
local BALL_MAGNITUDE_LIMIT = 1023
local FLOOR_Y_LIMIT = -4.778
local COURT_TOO_LOW_THRESHOLD = 10.0

local LANDING_SPOT_DISTANCE_THRESHOLD = 12.5
local ACTION_TOO_FAR_LIMIT = 30.0
local SUPER_FAST_BALL_THRESHOLD = 75.0
local TOO_FAR_FROM_HEAD_LIMIT = 5.0
local SET_TOO_FAR_LIMIT = 20.0

local function isStateValid(state)
	for _, check in next, state.checks do
		if not check.value then
			return false
		end
	end

	return true
end

local function determineHitType(context, state)
	local landingPosition = state.predictedLandingData and state.predictedLandingData.position
	local humanoidRootPart = context.humanoidRootPart

	local distanceToLandingSpot = (landingPosition - humanoidRootPart.Position).Magnitude
	local distanceToBall = (context.ballCFrame.Position - humanoidRootPart.Position).Magnitude
	local ballSpeed = context.ballVelocity.Magnitude

	if distanceToLandingSpot > LANDING_SPOT_DISTANCE_THRESHOLD and ballSpeed > SUPER_FAST_BALL_THRESHOLD then
		return "Dive"
	end

	if distanceToBall > SET_TOO_FAR_LIMIT then
		return "Dive"
	end

	return "Set"
end

local function predictBallLanding(context)
	local position = context.ballCFrame.Position
	local velocity = context.ballVelocity
	local court = context.court

	local gravityMultiplier = context.gravityMultiplier or 1.0
	local acceleration = Vector3.zero
	local jerk = Vector3.zero

	local filter = collectionService:GetTagged("BallNoCollide")

	filter[#filter + 1] = context.ball

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filter

	local timeStep = 0

	while timeStep < PREDICTION_MAX_TIME do
		local movement = (velocity - Vector3.new(0, 1, 0)) * PREDICTION_TIME_STEP

		if movement.Magnitude > BALL_MAGNITUDE_LIMIT then
			movement = movement.Unit * BALL_MAGNITUDE_LIMIT
		end

		if movement ~= movement then
			movement = Vector3.zero
		end

		if position.Y <= FLOOR_Y_LIMIT then
			position = position + Vector3.new(0, 1, 0) * (Game.Physics.Radius + FLOOR_Y_LIMIT - position.Y)
		end

		local result = workspace:Spherecast(position, Game.Physics.Radius, movement, raycastParams)

		if result and result.Instance and result.Instance.Name == "Invisible" then
			result = nil
		end

		if result then
			return { position = result.Position, instance = result.Instance }
		end

		local gravityDelta = PREDICTION_TIME_STEP * gravityMultiplier * Game.Physics.Gravity
		local newVelocity = velocity
			- Vector3.new(0, 1, 0) * gravityDelta
			+ PREDICTION_TIME_STEP * acceleration
			+ (PREDICTION_TIME_STEP ^ 2) * 0.5 * jerk

		position = newVelocity * PREDICTION_TIME_STEP + position
		velocity = newVelocity
		timeStep = timeStep + PREDICTION_TIME_STEP

		if position.Y < court.Position.Y - COURT_TOO_LOW_THRESHOLD then
			break
		end
	end

	return nil
end

local function updateBallHistory(context)
	table.insert(ballHistory, {
		position = context.ballCFrame.Position,
		velocity = context.ballVelocity,
	})

	while #ballHistory > BALL_HISTORY_MAX_POINTS do
		table.remove(ballHistory, 1)
	end
end

local function recordPredictedLand(predictedLandingData)
	local lastPrediction = predictedLandingHistory[#predictedLandingHistory]
	local predictedLandingPosition = predictedLandingData.position

	if
		lastPrediction
		and (lastPrediction.position - predictedLandingPosition).Magnitude < PREDICTED_LANDING_TOO_CLOSE_LIMIT
	then
		return
	end

	table.insert(predictedLandingHistory, predictedLandingData)

	while #predictedLandingHistory > PREDICTED_LANDING_MAX_POINTS do
		table.remove(predictedLandingHistory, 1)
	end
end

function AutoGuard.render(context, state)
	local ballPosition = context.ballCFrame.Position
	local ballVelocity = context.ballVelocity
	local predictedLandingData = state.predictedLandingData

	Gizmos.setColor3(predictedLandingData ~= nil and Color3.new(0, 1, 0) or Color3.new(1, 0, 0))
	Gizmos.drawRay(ballPosition, ballVelocity)

	if predictedLandingData ~= nil then
		recordPredictedLand(predictedLandingData)
	end

	Gizmos.setPosition(ballPosition + Vector3.new(0, 5, 0))
	Gizmos.setColor3(state.isValid and Color3.new(0, 1, 0) or Color3.new(1, 0, 0))

	local statusSheet = Sheet.new()

	statusSheet:append("Ball speed", string.format("%.2f studs/s", ballVelocity.Magnitude))
	statusSheet:append(
		"Ball distance",
		string.format("%.2f studs", (ballPosition - context.humanoidRootPart.Position).Magnitude)
	)

	for _, check in next, state.checks do
		statusSheet:append(check.label, check.value)
	end

	Gizmos.drawText(string.format("Auto guard status (%s)", state.hitType) .. statusSheet:build())

	for _, data in next, predictedLandingHistory do
		Gizmos.setColor3(Color3.new(0, 1, 1))
		Gizmos.setPosition(data.position)
		Gizmos.setThickness(1.0)
		Gizmos.drawPoint()

		Gizmos.setPosition(data.position + Vector3.new(0, 3, 0))

		local landingSheet = Sheet.new()

		landingSheet:append(
			"Landing position",
			string.format("(%.2f, %.2f, %.2f)", data.position.X, data.position.Y, data.position.Z)
		)
		landingSheet:append(
			"Distance from you",
			string.format("%.2f studs", (context.humanoidRootPart.Position - data.position).Magnitude)
		)
		landingSheet:append("Touched instance", data.instance and data.instance.Name or "nil")

		Gizmos.drawText(landingSheet:build())
	end

	local lastHitPosition = context.lastHitPosition

	if lastHitPosition and lastHitPosition.Magnitude > 0 then
		Gizmos.setPosition(lastHitPosition)
		Gizmos.setColor3(Color3.new(1, 0, 1))
		Gizmos.setThickness(1.0)
		Gizmos.drawPoint()

		local lastHitSheet = Sheet.new()

		lastHitSheet:append(
			"Hit position",
			string.format("(%.2f, %.2f, %.2f)", lastHitPosition.X, lastHitPosition.Y, lastHitPosition.Z)
		)
		lastHitSheet:append("Last hitter", tostring(context.lastHitter))
		lastHitSheet:append("Previous hitter", tostring(context.previousHitter))
		lastHitSheet:append("Hit type", tostring(context.lastHitType))
		lastHitSheet:append("Hit time", string.format("%.2f", context.lastHitTimestamp or 0.0))

		Gizmos.setPosition(lastHitPosition + Vector3.new(0, 5, 0))
		Gizmos.drawText("Last hit sheet..." .. lastHitSheet:build())
	end

	updateBallHistory(context)

	for idx, point in ipairs(ballHistory) do
		local age = (idx - 1) / #ballHistory
		Gizmos.setColor3(Color3.new(1.0 - age * 0.5, 0.3, age * 0.7))
		Gizmos.setPosition(point.position)
		Gizmos.setThickness(0.5)
		Gizmos.drawPoint()
	end

	local nearestBoundaryPart = context.nearestBoundaryPart
	local humanoidRootPart = context.humanoidRootPart

	if nearestBoundaryPart then
		local snappedPosition =
			Vector3.new(nearestBoundaryPart.Position.X, humanoidRootPart.Position.Y, nearestBoundaryPart.Position.Z)

		Gizmos.setPosition(nearestBoundaryPart.Position)
		Gizmos.setColor3(Color3.new(1, 1, 0))
		Gizmos.drawRay(humanoidRootPart.Position, (snappedPosition - humanoidRootPart.Position).Unit)
	end
end

function AutoGuard.update()
	local savedBallHistory = ballHistory
	local savedPredictedLandingHistory = predictedLandingHistory

	ballHistory = {}
	predictedLandingHistory = {}

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

	local isInTraining = GameMode.Current() == GameMode.Types.Training
	if not isInTraining and not localPlayer.Team then
		return
	end

	local firstBall = taggedBalls[1]
	if not firstBall then
		return
	end

	local firstBallPart = firstBall:FindFirstChildWhichIsA("BasePart")
	if not firstBallPart then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	local ballNoCollide = map:FindFirstChild("BallNoCollide")
	if not ballNoCollide then
		return
	end

	local boundaries = ballNoCollide:FindFirstChild("Boundaries")
	if not boundaries then
		return
	end

	ballHistory = savedBallHistory
	predictedLandingHistory = savedPredictedLandingHistory

	local networkedBallData = BallNetworking.networkedBallData
	local context = {
		localPlayer = localPlayer,
		character = character,
		humanoidRootPart = humanoidRootPart,
		team = localPlayer.Team,
		ball = firstBall,
		ballPart = firstBallPart,
		ballCFrame = networkedBallData and networkedBallData.cframe or firstBallPart.CFrame,
		ballVelocity = networkedBallData and networkedBallData.velocity or Vector3.zero,
		---@todo: technically networked, go get it?
		gravityMultiplier = 1.0,
		---@note: this is not networked.
		acceleration = Vector3.zero,
		jerk = Vector3.zero,
		map = map,
		court = court,
		net = net,
		isInTraining = isInTraining,
		servesInRow = replicatedStorage:GetAttribute("ServesInRow") or 0,
		lastHitTimestamp = replicatedStorage:GetAttribute("LastHitTimestamp") or 0.0,
		lastHitPosition = replicatedStorage:GetAttribute("LastHitPosition") or Vector3.new(0.0, 0.0, 0.0),
		teamHitStreak = replicatedStorage:GetAttribute("TeamHitStreak") or 0,
		lastHitter = replicatedStorage:GetAttribute("LastHitter"),
		lastHitTeam = replicatedStorage:GetAttribute("LastHitTeam"),
		servedByTeam = replicatedStorage:GetAttribute("ServedByTeam"),
		previousHitter = replicatedStorage:GetAttribute("PreviousHitter"),
		lastHitType = replicatedStorage:GetAttribute("LastHitType"),
		isBallInPlay = replicatedStorage:GetAttribute("IsBallInPlay"),
	}

	local nearestBoundaryPart = nil
	local nearestBoundaryDistance = nil

	for _, part in next, boundaries:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end

		local distance = (part.Position - humanoidRootPart.Position).Magnitude

		if nearestBoundaryDistance and distance > nearestBoundaryDistance then
			continue
		end

		nearestBoundaryPart = part
		nearestBoundaryDistance = distance
	end

	context.nearestBoundaryPart = nearestBoundaryPart

	local predictedLandingData = predictBallLanding(context)

	local state = {
		predictedLandingData = predictedLandingData,
		checks = {
			isTeamValid = {
				label = "Is team valid?",
				value = (localPlayer.Team ~= nil or GameMode.Current() == GameMode.Types.Training),
			},
			isBallOnCorrectSide = {
				label = "Is ball on correct side?",
				value = Physics.isPointOnTeamSide(localPlayer, context.ballCFrame.Position, nil),
			},
			isBallInPlay = {
				label = "Is ball in play?",
				value = context.isBallInPlay,
			},
			isNotAerial = {
				label = "Is not aerial?",
				value = not gameController.IsJumping:get(),
			},
			isLastTouchValid = {
				label = "Is last touch valid?",
				value = context.lastHitTeam and context.lastHitTeam ~= localPlayer.Team.Name,
			},
			isLandingValid = {
				label = "Is landing valid?",
				value = predictedLandingData and predictedLandingData.instance.Name == "Court",
			},
			isBallInDistance = {
				label = "Is ball in distance?",
				value = (context.ballCFrame.Position - humanoidRootPart.Position).Magnitude <= ACTION_TOO_FAR_LIMIT,
			},
			isBallInVerticalDistanceFromHead = {
				label = "Is ball in vertical distance from head?",
				value = math.abs(context.ballCFrame.Position.Y - head.Position.Y) <= TOO_FAR_FROM_HEAD_LIMIT,
			},
		},
	}

	-- These checks are reliant on the current ball position and at high velocities, it can be unreliable.
	if
		predictedLandingData
		and (predictedLandingData.position - humanoidRootPart.Position).Magnitude < SET_TOO_FAR_LIMIT
		and context.ballVelocity.Magnitude > SUPER_FAST_BALL_THRESHOLD
	then
		state.checks.isBallOnCorrectSide.value = "Skipped (unreliable at high speeds)"
		state.checks.isBallInVerticalDistanceFromHead.value = "Skipped (unreliable at high speeds)"
	end

	state.isValid = isStateValid(state)
	state.hitType = determineHitType(context, state)

	if shared.water.autoGuardDebugging then
		AutoGuard.render(context, state)
	end

	if not state.isValid then
		return
	end

	-- Before calling, set thread identity so we don't error from requiring
	setthreadidentity(2)

	if shared.water.autoGuardTeleporting then
		humanoidRootPart.CFrame = CFrame.new(predictedLandingData.position + Vector3.new(0, 5, 0))
	end

	AutoGuard.wantedDiveDirection = (predictedLandingData.position - humanoidRootPart.Position).Unit

	if state.hitType == "Set" then
		gameController:DoMove("Set")
	end

	if state.hitType == "Dive" then
		gameController:Dive()
	end
end

function AutoGuard.init()
	if not shared.water.autoGuard then
		return
	end

	autoGuardMaid:mark(runService.RenderStepped:Connect(AutoGuard.update))
end

return AutoGuard
