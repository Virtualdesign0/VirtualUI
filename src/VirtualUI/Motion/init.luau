--!strict

local MotionScheduler = require(script.MotionScheduler)
local MotionNode = require(script.MotionNode)
local Spring = require(script.Spring)
local Tween = require(script.Tween)

export type MotionNode<T> = MotionNode.MotionNode<T>
export type Spring<T> = Spring.Spring<T>
export type SpringOptions<T> = Spring.SpringOptions<T>
export type Tween<T> = Tween.Tween<T>
export type TweenOptions<T> = Tween.TweenOptions<T>
export type TweenTargetOptions = Tween.TweenTargetOptions

return {
	Spring = Spring,
	Tween = Tween,
	Step = MotionScheduler.Step,
	SetAutoStepEnabled = MotionScheduler.SetAutoStepEnabled,
	IsAutoStepEnabled = MotionScheduler.IsAutoStepEnabled,
	GetActiveCount = MotionScheduler.GetActiveCount,
}
