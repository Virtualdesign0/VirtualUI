--!strict

local Equality = require(script.Parent.Equality)
local Node = require(script.Parent.Node)
local Observer = require(script.Parent.Observer)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Trace = require(script.Parent.Parent.Dev.Trace)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local Computed = {}
Computed.__index = Computed

export type ComputedOptions<T> = {
	Equals: ((T, T) -> boolean)?,
	DebugName: string?,
	Scope: Scope.Scope?,
}

export type Computed<T> = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Version: number,
	Dirty: boolean,
	Destroyed: boolean,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_compute: () -> T,
	_equals: (T, T) -> boolean,
	_hasValue: boolean,
	_value: T?,
	_evaluating: boolean,
	_failure: string?,

	Get: (self: Computed<T>) -> T,
	Peek: (self: Computed<T>) -> T,
	Destroy: (self: Computed<T>) -> (),
	_evaluate: (self: Computed<T>) -> T,
	_invalidate: (self: Computed<T>, source: Node.GraphNode) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

function Computed.new<T>(compute: () -> T, options: ComputedOptions<T>?): Computed<T>
	local resolvedOptions: ComputedOptions<T> = options or {}
	local self = (
		setmetatable(Node.New("Computed", resolvedOptions), Computed) :: unknown
	) :: Computed<T>

	self.Dirty = true
	self._compute = compute
	self._equals = if resolvedOptions.Equals == nil
		then function(left: T, right: T): boolean
			return Equality.Default(left, right)
		end
		else resolvedOptions.Equals
	self._hasValue = false
	self._value = nil
	self._evaluating = false
	self._failure = nil

	if resolvedOptions.Scope ~= nil then
		resolvedOptions.Scope:Own(self)
	end

	return self
end

function Computed._evaluate<T>(self: Computed<T>): T
	if not self.Dirty then
		if self._failure ~= nil then
			error(self._failure, 3)
		end
		Profiler.Increment("ComputedCacheHits")
		return (self._value :: unknown) :: T
	end

	if self._evaluating then
		error(Observer.FormatCycle(self), 3)
	end

	self._evaluating = true
	Node.BeginTracking(self)
	local traceStarted = Trace.Start()
	local packed = table.pack(xpcall(self._compute, traceback))
	Node.EndTracking(self)
	if traceStarted ~= nil then
		Trace.RecordDuration("Evaluate", traceStarted, {
			NodeId = self.Id,
			NodeKind = self.Kind,
			DebugName = self.DebugName,
		})
	end
	self._evaluating = false
	self.Dirty = false
	Profiler.Increment("ComputedEvaluations")

	if not packed[1] then
		self._failure = tostring(packed[2])
		error(packed[2], 3)
	end

	local result = packed[2] :: T
	self._failure = nil
	if not self._hasValue or not self._equals((self._value :: unknown) :: T, result) then
		self._value = result
		self._hasValue = true
		self.Version = (self.Version :: number) + 1
	end

	return self._value :: T
end

function Computed.Get<T>(self: Computed<T>): T
	Node.AssertAlive(self)
	Node.Track(self)
	return self:_evaluate()
end

function Computed.Peek<T>(self: Computed<T>): T
	Node.AssertAlive(self)
	return self:_evaluate()
end

function Computed._invalidate<T>(self: Computed<T>, _source: Node.GraphNode)
	if self.Destroyed or self.Dirty then
		return
	end

	self.Dirty = true
	Node.InvalidateDependents(self)
end

function Computed.Destroy<T>(self: Computed<T>)
	Node.Destroy(self)
end

return Computed
