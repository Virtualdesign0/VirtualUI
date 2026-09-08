--!strict

local MotionNode = require(script.Parent.MotionNode)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local ValueCodec = require(script.Parent.ValueCodec)

local TweenService = game:GetService("TweenService")

local Tween = {}
Tween.__index = Tween

export type TweenOptions<T> = {
	Equals: ((T, T) -> boolean)?,
	Scope: MotionNode.Scope?,
	DebugName: string?,
	Duration: number?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
}

export type TweenTargetOptions = {
	Duration: number?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
}

export type Tween<T> = MotionNode.MotionNode<T> & {
	_duration: number,
	_easingStyle: Enum.EasingStyle,
	_easingDirection: Enum.EasingDirection,
	_elapsed: number,
	_startComponents: ValueCodec.Components,
	SetTarget: (self: Tween<T>, target: T, options: TweenTargetOptions?) -> (),
	Snap: (self: Tween<T>, value: T) -> (),
}

local DEFAULT_DURATION = 0.25

function Tween.new<T>(initialValue: T, options: TweenOptions<T>?): Tween<T>
	local resolvedOptions: TweenOptions<T> = options or {}
	local duration = if resolvedOptions.Duration == nil
		then DEFAULT_DURATION
		else resolvedOptions.Duration
	if duration < 0 or duration ~= duration or duration == math.huge then
		error("Tween Duration must be a non-negative finite number", 2)
	end
	local self = MotionNode.Create(Tween, initialValue, resolvedOptions) :: Tween<T>
	self._duration = duration
	self._easingStyle = resolvedOptions.EasingStyle or Enum.EasingStyle.Quad
	self._easingDirection = resolvedOptions.EasingDirection or Enum.EasingDirection.Out
	self._elapsed = 0
	self._startComponents = table.clone(self._components)

	return self :: Tween<T>
end

Tween.Get = MotionNode.Get
Tween.Peek = MotionNode.Peek
Tween.GetTarget = MotionNode.GetTarget
Tween.IsAnimating = MotionNode.IsAnimating
Tween.Destroy = MotionNode.Destroy

function Tween.SetTarget<T>(self: Tween<T>, target: T, options: TweenTargetOptions?)
	MotionNode.AssertCanMutate(self)
	local resolvedOptions: TweenTargetOptions = options or {}
	local duration = if resolvedOptions.Duration == nil
		then self._duration
		else resolvedOptions.Duration
	if duration < 0 or duration ~= duration or duration == math.huge then
		error("Tween Duration must be a non-negative finite number", 2)
	end
	self._duration = duration
	self._easingStyle = resolvedOptions.EasingStyle or self._easingStyle
	self._easingDirection = resolvedOptions.EasingDirection or self._easingDirection
	MotionNode.SetTargetValue(self, target)
	self._startComponents = table.clone(self._components)
	self._elapsed = 0
	if self._duration == 0 then
		MotionNode.SnapValue(self, target)
		return
	end
	MotionNode.SetActive(self, true)
end

function Tween.Snap<T>(self: Tween<T>, value: T)
	MotionNode.AssertCanMutate(self)
	self._elapsed = 0
	MotionNode.SnapValue(self, value)
	self._startComponents = table.clone(self._components)
end

function Tween._step<T>(self: Tween<T>, deltaTime: number): boolean
	if self.Destroyed or not self._active then
		return false
	end

	self._elapsed = math.min(self._elapsed + deltaTime, self._duration)
	local alpha = self._elapsed / self._duration
	local easedAlpha = TweenService:GetValue(alpha, self._easingStyle, self._easingDirection)
	local nextComponents =
		ValueCodec.Lerp(self._startComponents, self._targetComponents, easedAlpha)

	if self._elapsed >= self._duration then
		nextComponents = table.clone(self._targetComponents)
		MotionNode.ForcePublishComponents(self, nextComponents)
		MotionNode.SetActive(self, false)
		Profiler.Increment("TweensCompleted")
		return false
	end

	MotionNode.PublishComponents(self, nextComponents)
	return true
end

return Tween
