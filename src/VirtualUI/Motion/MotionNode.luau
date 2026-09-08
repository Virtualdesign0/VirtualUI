--!strict

local Equality = require(script.Parent.Parent.Reactive.Equality)
local Node = require(script.Parent.Parent.Reactive.Node)
local Observer = require(script.Parent.Parent.Reactive.Observer)
local MotionScheduler = require(script.Parent.MotionScheduler)
local ValueCodec = require(script.Parent.ValueCodec)
local ScopeModule = require(script.Parent.Parent.Lifetime.Scope)

local MotionNode = {}

export type Scope = ScopeModule.Scope

export type MotionOptions<T> = {
	Equals: ((T, T) -> boolean)?,
	Scope: ScopeModule.Scope?,
	DebugName: string?,
}

export type MotionNode<T> = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Destroyed: boolean,
	Dirty: boolean,
	Version: number,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_scope: ScopeModule.Scope?,
	_value: T,
	_target: T,
	_kind: string,
	_components: ValueCodec.Components,
	_targetComponents: ValueCodec.Components,
	_equals: (T, T) -> boolean,
	_active: boolean,
	Get: (self: MotionNode<T>) -> T,
	Peek: (self: MotionNode<T>) -> T,
	GetTarget: (self: MotionNode<T>) -> T,
	IsAnimating: (self: MotionNode<T>) -> boolean,
	Destroy: (self: MotionNode<T>) -> (),
	_invalidate: (self: MotionNode<T>, source: Node.GraphNode) -> (),
}

function MotionNode.Create<T>(
	prototype: {},
	initialValue: T,
	options: MotionOptions<T>?
): MotionNode<T>
	local resolvedOptions: MotionOptions<T> = options or {}
	local valueKind, components = ValueCodec.Encode(initialValue)
	local self = (
		setmetatable(Node.New("Motion", resolvedOptions), prototype) :: unknown
	) :: MotionNode<T>
	self._value = initialValue
	self._target = initialValue
	self._kind = valueKind
	self._components = components
	self._targetComponents = table.clone(components)
	self._equals = if resolvedOptions.Equals == nil
		then function(left: T, right: T): boolean
			return Equality.Default(left, right)
		end
		else resolvedOptions.Equals
	self._active = false

	if resolvedOptions.Scope ~= nil then
		resolvedOptions.Scope:Own(self)
	end
	return self
end

function MotionNode.Get<T>(self: MotionNode<T>): T
	Node.AssertAlive(self)
	Node.Track(self)
	return self._value
end

function MotionNode.Peek<T>(self: MotionNode<T>): T
	Node.AssertAlive(self)
	return self._value
end

function MotionNode.GetTarget<T>(self: MotionNode<T>): T
	Node.AssertAlive(self)
	return self._target
end

function MotionNode.IsAnimating<T>(self: MotionNode<T>): boolean
	return not self.Destroyed and self._active
end

function MotionNode.AssertCanMutate<T>(self: MotionNode<T>)
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
			`Motion mutation is not allowed while {observer.Kind} "{observer.DebugName or observer.Id}" is evaluating`,
			3
		)
	end
end

function MotionNode.SetActive<T>(self: MotionNode<T>, active: boolean)
	if active then
		MotionScheduler.Register(self)
	else
		MotionScheduler.Unregister(self)
	end
end

function MotionNode.SetTargetValue<T>(self: MotionNode<T>, target: T)
	self._targetComponents = ValueCodec.EncodeCompatible(target, self._kind)
	self._target = target
end

function MotionNode.PublishComponents<T>(self: MotionNode<T>, components: ValueCodec.Components)
	local value = (ValueCodec.Decode(self._kind, components) :: unknown) :: T
	self._components = components
	if self._equals(self._value, value) then
		return
	end
	self._value = value
	self.Version = (self.Version :: number) + 1
	Node.InvalidateDependents(self)
end

function MotionNode.ForcePublishComponents<T>(self: MotionNode<T>, components: ValueCodec.Components)
	local value = (ValueCodec.Decode(self._kind, components) :: unknown) :: T
	self._components = components
	if Equality.Default(self._value, value) then
		self._value = value
		return
	end
	self._value = value
	self.Version = (self.Version :: number) + 1
	Node.InvalidateDependents(self)
end

function MotionNode.SnapValue<T>(self: MotionNode<T>, value: T)
	local components = ValueCodec.EncodeCompatible(value, self._kind)
	self._target = value
	self._targetComponents = table.clone(components)
	MotionNode.ForcePublishComponents(self, components)
	MotionNode.SetActive(self, false)
end

function MotionNode.Destroy<T>(self: MotionNode<T>)
	if self.Destroyed then
		return
	end
	MotionNode.SetActive(self, false)
	Node.Destroy(self)
end

return MotionNode
