--!strict

local Integrator = require(script.Parent.Integrator)
local MotionNode = require(script.Parent.MotionNode)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local ValueCodec = require(script.Parent.ValueCodec)

local Spring = {}
Spring.__index = Spring

export type SpringOptions<T> = {
	Equals: ((T, T) -> boolean)?,
	Scope: MotionNode.Scope?,
	DebugName: string?,
	Frequency: number?,
	DampingRatio: number?,
	RestPosition: number?,
	RestVelocity: number?,
}

export type Spring<T> = MotionNode.MotionNode<T> & {
	_frequency: number,
	_dampingRatio: number,
	_restPosition: number,
	_restVelocity: number,
	_velocity: ValueCodec.Components,
	SetTarget: (self: Spring<T>, target: T) -> (),
	Snap: (self: Spring<T>, value: T) -> (),
	GetVelocity: (self: Spring<T>) -> T,
	SetVelocity: (self: Spring<T>, velocity: T) -> (),
}

local DEFAULT_FREQUENCY = 4
local DEFAULT_DAMPING_RATIO = 1
local DEFAULT_REST_POSITION = 0.001
local DEFAULT_REST_VELOCITY = 0.001

function Spring.new<T>(initialValue: T, options: SpringOptions<T>?): Spring<T>
	local resolvedOptions: SpringOptions<T> = options or {}
	local frequency = if resolvedOptions.Frequency == nil
		then DEFAULT_FREQUENCY
		else resolvedOptions.Frequency
	local dampingRatio = if resolvedOptions.DampingRatio == nil
		then DEFAULT_DAMPING_RATIO
		else resolvedOptions.DampingRatio
	local restPosition = if resolvedOptions.RestPosition == nil
		then DEFAULT_REST_POSITION
		else resolvedOptions.RestPosition
	local restVelocity = if resolvedOptions.RestVelocity == nil
		then DEFAULT_REST_VELOCITY
		else resolvedOptions.RestVelocity
	if frequency < 0 or frequency ~= frequency or frequency == math.huge then
		error("Spring Frequency must be a non-negative finite number", 2)
	end
	if dampingRatio < 0 or dampingRatio ~= dampingRatio or dampingRatio == math.huge then
		error("Spring DampingRatio must be a non-negative finite number", 2)
	end
	if restPosition < 0 or restPosition ~= restPosition or restPosition == math.huge then
		error("Spring RestPosition must be a non-negative finite number", 2)
	end
	if restVelocity < 0 or restVelocity ~= restVelocity or restVelocity == math.huge then
		error("Spring RestVelocity must be a non-negative finite number", 2)
	end

	local self = MotionNode.Create(Spring, initialValue, resolvedOptions) :: Spring<T>
	self._frequency = frequency
	self._dampingRatio = dampingRatio
	self._restPosition = restPosition
	self._restVelocity = restVelocity
	self._velocity = ValueCodec.Zero(#self._components)

	return self :: Spring<T>
end

Spring.Get = MotionNode.Get
Spring.Peek = MotionNode.Peek
Spring.GetTarget = MotionNode.GetTarget
Spring.IsAnimating = MotionNode.IsAnimating
Spring.Destroy = MotionNode.Destroy

function Spring.SetTarget<T>(self: Spring<T>, target: T)
	MotionNode.AssertCanMutate(self)
	MotionNode.SetTargetValue(self, target)
	if self._frequency == 0 then
		MotionNode.SnapValue(self, target)
		return
	end
	MotionNode.SetActive(self, true)
end

function Spring.Snap<T>(self: Spring<T>, value: T)
	MotionNode.AssertCanMutate(self)
	self._velocity = ValueCodec.Zero(#self._components)
	MotionNode.SnapValue(self, value)
end

function Spring.GetVelocity<T>(self: Spring<T>): T
	if self.Destroyed then
		error("Attempted to access a destroyed Motion", 2)
	end
	return (ValueCodec.Decode(self._kind, self._velocity) :: unknown) :: T
end

function Spring.SetVelocity<T>(self: Spring<T>, velocity: T)
	MotionNode.AssertCanMutate(self)
	self._velocity = ValueCodec.EncodeCompatible(velocity, self._kind)
	MotionNode.SetActive(self, true)
end

function Spring._step<T>(self: Spring<T>, deltaTime: number): boolean
	if self.Destroyed or not self._active then
		return false
	end

	local nextPosition = table.create(#self._components, 0) :: ValueCodec.Components
	local nextVelocity = table.create(#self._components, 0) :: ValueCodec.Components
	for index, position in self._components do
		local steppedPosition, steppedVelocity = Integrator.Spring(
			position,
			self._velocity[index],
			self._targetComponents[index],
			self._frequency,
			self._dampingRatio,
			deltaTime
		)
		nextPosition[index] = steppedPosition
		nextVelocity[index] = steppedVelocity
	end

	self._velocity = nextVelocity
	if
		ValueCodec.IsAtRest(
			nextPosition,
			self._targetComponents,
			nextVelocity,
			self._restPosition,
			self._restVelocity
		)
	then
		self._velocity = ValueCodec.Zero(#nextVelocity)
		MotionNode.ForcePublishComponents(self, table.clone(self._targetComponents))
		MotionNode.SetActive(self, false)
		Profiler.Increment("SpringsSettled")
		return false
	end

	MotionNode.PublishComponents(self, nextPosition)
	return true
end

return Spring
