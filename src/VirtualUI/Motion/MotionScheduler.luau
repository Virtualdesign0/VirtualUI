--!strict

local Config = require(script.Parent.Parent.Runtime.Config)
local Scope = require(script.Parent.Parent.Lifetime.Scope)
local Profiler = require(script.Parent.Parent.Dev.Profiler)

local MotionScheduler = {}

type ScheduledNode = {
	Destroyed: boolean,
	_active: boolean,
	_scope: Scope.Scope?,
	_step: (self: unknown, deltaTime: number) -> boolean?,
}

local activeNodes: { [ScheduledNode]: boolean } = {}
local activeCount = 0
local autoStepEnabled = true
local heartbeatConnection: RBXScriptConnection? = nil
local stepping = false

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function asScheduledNode(node: unknown): ScheduledNode
	return node :: ScheduledNode
end

local function disconnectHeartbeat()
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function ensureHeartbeat()
	if not autoStepEnabled or heartbeatConnection ~= nil or activeCount == 0 then
		return
	end
	heartbeatConnection = game:GetService("RunService").Heartbeat
		:Connect(function(deltaTime: number)
			MotionScheduler.Step(deltaTime)
		end)
end

function MotionScheduler.Register(value: unknown)
	local node = asScheduledNode(value)
	node._active = true
	if activeNodes[node] then
		return
	end
	activeNodes[node] = true
	activeCount += 1
	ensureHeartbeat()
end

function MotionScheduler.Unregister(value: unknown)
	local node = asScheduledNode(value)
	node._active = false
	if not activeNodes[node] then
		return
	end
	activeNodes[node] = nil
	activeCount -= 1
	if activeCount == 0 and not stepping then
		disconnectHeartbeat()
	end
end

function MotionScheduler.Step(deltaTime: number)
	if deltaTime < 0 then
		error("Motion deltaTime cannot be negative", 2)
	end
	if stepping then
		return
	end

	local started = Profiler.Start()
	stepping = true
	local firstError: unknown = nil
	local snapshot: { ScheduledNode } = {}
	for node in activeNodes do
		table.insert(snapshot, node)
	end

	for _, node in snapshot do
		if activeNodes[node] and not node.Destroyed then
			local stepped = table.pack(xpcall(function()
				return node._step(node, deltaTime)
			end, traceback))
			if not stepped[1] then
				MotionScheduler.Unregister(node)
				local handled, routedMessage = Scope.RouteError(node._scope, stepped[2], node)
				if not handled then
					firstError = firstError or routedMessage
				end
			elseif stepped[2] == false then
				MotionScheduler.Unregister(node)
			end
		end
	end

	stepping = false
	if activeCount == 0 then
		disconnectHeartbeat()
	end
	Profiler.Finish("MotionMs", started)
	Profiler.Increment("MotionFrames")
	Profiler.Increment("MotionNodesStepped", #snapshot)

	if firstError ~= nil then
		Config.ReportError(firstError, "[UI Motion]")
	end
end

function MotionScheduler.SetAutoStepEnabled(enabled: boolean)
	autoStepEnabled = enabled
	if enabled then
		ensureHeartbeat()
	else
		disconnectHeartbeat()
	end
end

function MotionScheduler.IsAutoStepEnabled(): boolean
	return autoStepEnabled
end

function MotionScheduler.GetActiveCount(): number
	return activeCount
end

return MotionScheduler
