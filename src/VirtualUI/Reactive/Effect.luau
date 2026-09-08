--!strict

local Node = require(script.Parent.Node)
local Scheduler = require(script.Parent.Parent.Scheduler.Scheduler)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local Effect = {}
Effect.__index = Effect

export type EffectOptions = {
	DebugName: string?,
	Scope: Scope.Scope?,
}

export type EffectCallback = () -> ...unknown

export type Effect = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Version: number,
	Dirty: boolean,
	Destroyed: boolean,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_callback: EffectCallback,
	_cleanupCallback: (() -> ())?,
	_run: (self: Effect) -> (),
	_invalidate: (self: Effect, source: Node.GraphNode) -> (),
	Destroy: (self: Effect) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

function Effect.new(callback: EffectCallback, options: EffectOptions?): Effect
	local resolvedOptions: EffectOptions = options or {}
	local self = (setmetatable(Node.New("Effect", resolvedOptions), Effect) :: unknown) :: Effect

	self.Dirty = true
	self._callback = callback
	self._cleanupCallback = nil :: (() -> ())?

	if resolvedOptions.Scope ~= nil then
		resolvedOptions.Scope:Own(self)
	end

	Scheduler.EnqueueEffect(self)
	return self
end

function Effect._run(self: Effect)
	if self.Destroyed or not self.Dirty then
		return
	end

	local previousCleanup = self._cleanupCallback
	self._cleanupCallback = nil
	self.Dirty = false
	if previousCleanup ~= nil then
		local cleanupResult = table.pack(xpcall(previousCleanup, traceback))
		if not cleanupResult[1] then
			error(cleanupResult[2], 2)
		end
	end

	Node.BeginTracking(self)
	local ok, cleanup = xpcall(self._callback, traceback)
	Node.EndTracking(self)
	Profiler.Increment("EffectRuns")

	if not ok then
		error(cleanup, 2)
	end

	if type(cleanup) == "function" then
		self._cleanupCallback = cleanup :: () -> ()
	end

	self.Version += 1
end

function Effect._invalidate(self: Effect, _source: Node.GraphNode)
	if self.Destroyed or self.Dirty then
		return
	end

	self.Dirty = true
	Scheduler.EnqueueEffect(self)
end

function Effect.Destroy(self: Effect)
	if self.Destroyed then
		return
	end

	local cleanup = self._cleanupCallback
	self._cleanupCallback = nil
	local cleanupError: unknown = nil
	if cleanup ~= nil then
		local result = table.pack(xpcall(cleanup, traceback))
		if not result[1] then
			cleanupError = result[2]
		end
	end

	Node.Destroy(self)
	if cleanupError ~= nil then
		error(cleanupError, 2)
	end
end

return Effect
