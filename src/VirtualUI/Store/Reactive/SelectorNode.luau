--!strict

local Equality = require(script.Parent.Parent.Parent.Reactive.Equality)
local Node = require(script.Parent.Parent.Parent.Reactive.Node)
local Observer = require(script.Parent.Parent.Parent.Reactive.Observer)
local Scheduler = require(script.Parent.Parent.Parent.Scheduler.Scheduler)
local Profiler = require(script.Parent.Parent.Parent.Dev.Profiler)
local Trace = require(script.Parent.Parent.Parent.Dev.Trace)
local PathChangeSet = require(script.Parent.Parent.PathChangeSet)
local Scope = require(script.Parent.Parent.Parent.Lifetime.Scope)

local SelectorNode = {}
SelectorNode.__index = SelectorNode

type StoreProtocol<State> = {
	GetState: (self: unknown) -> State,
	_registerSelector: (self: unknown, selector: unknown) -> (),
	_unregisterSelector: (self: unknown, selector: unknown) -> (),
}

export type SelectorOptions<T> = {
	Equals: ((T, T) -> boolean)?,
	DebugName: string?,
	Scope: Scope.Scope?,
	Path: PathChangeSet.Path?,
}

export type Selector<T> = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Version: number,
	Dirty: boolean,
	Destroyed: boolean,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_compute: () -> T,
	_unregister: () -> (),
	_path: PathChangeSet.Path?,
	_equals: (T, T) -> boolean,
	_hasValue: boolean,
	_value: T?,
	_evaluating: boolean,
	_failure: string?,

	Get: (self: Selector<T>) -> T,
	Peek: (self: Selector<T>) -> T,
	Destroy: (self: Selector<T>) -> (),
	_recompute: (self: Selector<T>) -> T,
	_readStore: (self: Selector<T>) -> T,
	_dependsOn: (self: Selector<T>, changes: PathChangeSet.ChangeSet) -> boolean,
	_invalidateFromStore: (self: Selector<T>, changes: PathChangeSet.ChangeSet) -> (),
	_invalidate: (self: Selector<T>, source: Node.GraphNode) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function readPath(state: unknown, path: PathChangeSet.Path): unknown
	local current = state
	for _, segment in path do
		if current == nil then
			return nil
		end
		if type(current) ~= "table" then
			return nil
		end
		current = (current :: { [PathChangeSet.PathSegment]: unknown })[segment]
	end
	return current
end

function SelectorNode.new<State, T>(
	store: unknown,
	selector: ((State) -> T)?,
	options: SelectorOptions<T>?
): Selector<T>
	local resolvedOptions: SelectorOptions<T> = options or {}
	local dynamicStore = store :: StoreProtocol<State>
	local path = resolvedOptions.Path
	local compute: () -> T
	if path ~= nil then
		compute = function(): T
			return (readPath(dynamicStore.GetState(dynamicStore), path) :: unknown) :: T
		end
	else
		assert(selector ~= nil, "Selector requires a compute function or path")
		compute = function(): T
			return selector(dynamicStore.GetState(dynamicStore))
		end
	end
	local self = (
		setmetatable(Node.New("Selector", resolvedOptions), SelectorNode) :: unknown
	) :: Selector<T>

	self.Dirty = true
	self._compute = compute
	self._unregister = function()
		dynamicStore._unregisterSelector(dynamicStore, self)
	end
	self._path = path
	self._equals = if resolvedOptions.Equals == nil
		then function(left: T, right: T): boolean
			return Equality.Default(left, right)
		end
		else resolvedOptions.Equals
	self._hasValue = false
	self._value = nil
	self._evaluating = false
	self._failure = nil

	dynamicStore._registerSelector(dynamicStore, self)
	if resolvedOptions.Scope ~= nil then
		resolvedOptions.Scope:Own(self)
	end

	return self :: Selector<T>
end

function SelectorNode._readStore<T>(self: Selector<T>): T
	return self._compute()
end

function SelectorNode._recompute<T>(self: Selector<T>): T
	if not self.Dirty then
		if self._failure ~= nil then
			error(self._failure, 3)
		end
		Profiler.Increment("SelectorCacheHits")
		return (self._value :: unknown) :: T
	end

	if self._evaluating then
		error(Observer.FormatCycle(self), 3)
	end

	self._evaluating = true
	Node.BeginTracking(self)
	local traceStarted = Trace.Start()
	local packed = table.pack(xpcall(function()
		return self:_readStore()
	end, traceback))
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
	Profiler.Increment("SelectorEvaluations")

	if not packed[1] then
		self._failure = tostring(packed[2])
		error(packed[2], 3)
	end

	local result = packed[2] :: T
	self._failure = nil
	local changed = not self._hasValue or not self._equals(self._value :: T, result)
	if changed then
		self._value = result
		self._hasValue = true
		self.Version = (self.Version :: number) + 1
		Node.InvalidateDependents(self, Observer.GetCurrent())
	end

	return self._value :: T
end

function SelectorNode.Get<T>(self: Selector<T>): T
	Node.AssertAlive(self)
	Node.Track(self)
	return self:_recompute()
end

function SelectorNode.Peek<T>(self: Selector<T>): T
	Node.AssertAlive(self)
	return self:_recompute()
end

function SelectorNode._dependsOn<T>(self: Selector<T>, changes: PathChangeSet.ChangeSet): boolean
	local path = self._path
	if path == nil or #path == 0 then
		return true
	end
	return PathChangeSet.Overlaps(changes, path)
end

function SelectorNode._invalidateFromStore<T>(self: Selector<T>, changes: PathChangeSet.ChangeSet)
	if self.Destroyed or self.Dirty or not self:_dependsOn(changes) then
		return
	end

	self.Dirty = true
	Profiler.Increment("SelectorInvalidations")

	if Node.HasDependents(self) then
		Scheduler.EnqueueComputation(self)
	end
end

function SelectorNode._invalidate<T>(self: Selector<T>, _source: Node.GraphNode)
	if self.Destroyed or self.Dirty then
		return
	end

	self.Dirty = true
	if Node.HasDependents(self) then
		Scheduler.EnqueueComputation(self)
	end
end

function SelectorNode.Destroy<T>(self: Selector<T>)
	if self.Destroyed then
		return
	end

	self._unregister()
	Node.Destroy(self)
end

return SelectorNode
