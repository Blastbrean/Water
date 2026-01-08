local BallNetworking = {
	networkedBallData = nil,
}

local replicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require("utility/maid")

local ballNetworkingMaid = Maid.new()

local zapFolder = replicatedStorage:WaitForChild("ZAP")
local ballZapReliable = zapFolder:WaitForChild("BALL_ZAP_RELIABLE")

local function onBallReplication(dataBuffer)
	local readerPosition = 0

	local function zapRead(numBytes)
		local pos = readerPosition
		readerPosition = readerPosition + numBytes
		return pos
	end

	local id = buffer.readu8(dataBuffer, zapRead(1))

	if id ~= 1 then
		error("unknown event id")
	end

	local x = buffer.readf32(dataBuffer, zapRead(4))
	local y = buffer.readf32(dataBuffer, zapRead(4))
	local z = buffer.readf32(dataBuffer, zapRead(4))
	local vector = Vector3.new(x, y, z)

	local axisX = buffer.readf32(dataBuffer, zapRead(4))
	local axisY = buffer.readf32(dataBuffer, zapRead(4))
	local axisZ = buffer.readf32(dataBuffer, zapRead(4))
	local axisVector = Vector3.new(axisX, axisY, axisZ)

	local cframe = nil

	if axisVector.Magnitude ~= 0 then
		cframe = CFrame.fromAxisAngle(axisVector, axisVector.Magnitude) + vector
	else
		cframe = CFrame.new(vector)
	end

	local velocityX = buffer.readf32(dataBuffer, zapRead(4))
	local velocityY = buffer.readf32(dataBuffer, zapRead(4))
	local velocityZ = buffer.readf32(dataBuffer, zapRead(4))
	local velocityVector = Vector3.new(velocityX, velocityY, velocityZ)

	BallNetworking.networkedBallData = {
		cframe = cframe,
		velocity = velocityVector,
	}
end

function BallNetworking.init()
	ballNetworkingMaid:mark(ballZapReliable.OnClientEvent:Connect(onBallReplication))
end

return BallNetworking
