--!strict

local Equality = require(script.Parent.Equality)
local Node = require(script.Parent.Node)
local Observer = require(script.Parent.Observer)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Trace = require(script.Parent.Parent.Dev.Trace)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local State = {}
State.__index = State

export type StateOptions<T> = {
	Equals: ((T, T) -> boolean)?,
	DebugName: string?,
	Scope: Scope.Scope?,
}

export type State<T> = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Version: number,
	Dirty: boolean,
	Destroyed: boolean,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_value: T,
	_equals: (T, T) -> boolean,

	Get: (self: State<T>) -> T,
	Peek: (self: State<T>) -> T,
	Set: (self: State<T>, nextValue: T) -> boolean,
	Update: (self: State<T>, transform: (T) -> T) -> boolean,
	Destroy: (self: State<T>) -> (),
	_invalidate: (self: State<T>, source: Node.GraphNode) -> (),
}

function State.new<T>(initialValue: T, options: StateOptions<T>?): State<T>
	local resolvedOptions: StateOptions<T> = options or {}
	local self = (setmetatable(Node.New("State", resolvedOptions), State) :: unknown) :: State<T>

	self._value = initialValue
	self._equals = if resolvedOptions.Equals == nil
		then function(left: T, right: T): boolean
			return Equality.Default(left, right)
		end
		else resolvedOptions.Equals

	if resolvedOptions.Scope ~= nil then
		resolvedOptions.Scope:Own(self)
	end

	return self
end

function State.Get<T>(self: State<T>): T
	Node.AssertAlive(self)
	Node.Track(self)
	return self._value
end

function State.Peek<T>(self: State<T>): T
	Node.AssertAlive(self)
	return self._value
end

function State.Set<T>(self: State<T>, nextValue: T): boolean
	Node.AssertAlive(self)
	local observer = Observer.GetCurrent()
	if
		observer ~= nil
		and (
			observer.Kind == "Computed"
			or observer.Kind == "Selector"
			or observer.Kind == "Binding"
			or observer.Kind == "Conditional"
			or observer.Kind == "KeyedCollection"
		)
	then
		error(
			`State mutation is not allowed while {observer.Kind} "{observer.DebugName or observer.Id}" is evaluating`,
			2
		)
	end

	if self._equals(self._value, nextValue) then
		Profiler.Increment("StateNoOpMutations")
		return false
	end

	local previousValue = self._value
	if Trace.IsEnabled() then
		if Node.HasDependents(self) then
			Trace.PrepareFlush()
		end
		Trace.Record("StateWrite", {
			NodeId = self.Id,
			NodeKind = self.Kind,
			DebugName = self.DebugName,
			Previous = Trace.Value(previousValue),
			Next = Trace.Value(nextValue),
		})
	end
	self._value = nextValue
	self.Version = (self.Version :: number) + 1
	Profiler.Increment("StateMutations")
	Node.InvalidateDependents(self)
	return true
end

function State.Update<T>(self: State<T>, transform: (T) -> T): boolean
	Node.AssertAlive(self)
	return self:Set(transform(self._value))
end

function State.Destroy<T>(self: State<T>)
	Node.Destroy(self)
end

function State._invalidate<T>(_self: State<T>, _source: Node.GraphNode)
	-- Writable states are graph roots and cannot be invalidated by another node.
end

return State
