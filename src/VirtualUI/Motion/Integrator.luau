--!strict

local Integrator = {}

local CRITICAL_EPSILON = 1e-4

function Integrator.Spring(
	position: number,
	velocity: number,
	target: number,
	frequency: number,
	dampingRatio: number,
	deltaTime: number
): (number, number)
	if frequency <= 0 or deltaTime <= 0 then
		return if frequency <= 0 then target else position, if frequency <= 0 then 0 else velocity
	end

	local angularFrequency = 2 * math.pi * frequency
	local displacement = position - target

	if dampingRatio < 1 - CRITICAL_EPSILON then
		local dampedFrequency = angularFrequency * math.sqrt(1 - dampingRatio * dampingRatio)
		local decay = math.exp(-dampingRatio * angularFrequency * deltaTime)
		local cosine = math.cos(dampedFrequency * deltaTime)
		local sine = math.sin(dampedFrequency * deltaTime)
		local coefficient = (velocity + dampingRatio * angularFrequency * displacement)
			/ dampedFrequency
		local nextDisplacement = decay * (displacement * cosine + coefficient * sine)
		local nextVelocity = decay
			* (
				-dampingRatio * angularFrequency * (displacement * cosine + coefficient * sine)
				+ (-displacement * dampedFrequency * sine + coefficient * dampedFrequency * cosine)
			)
		return target + nextDisplacement, nextVelocity
	elseif dampingRatio > 1 + CRITICAL_EPSILON then
		local root = math.sqrt(dampingRatio * dampingRatio - 1)
		local firstRoot = -angularFrequency * (dampingRatio - root)
		local secondRoot = -angularFrequency * (dampingRatio + root)
		local firstCoefficient = (velocity - secondRoot * displacement) / (firstRoot - secondRoot)
		local secondCoefficient = displacement - firstCoefficient
		local firstDecay = math.exp(firstRoot * deltaTime)
		local secondDecay = math.exp(secondRoot * deltaTime)
		local nextDisplacement = firstCoefficient * firstDecay + secondCoefficient * secondDecay
		local nextVelocity = firstCoefficient * firstRoot * firstDecay
			+ secondCoefficient * secondRoot * secondDecay
		return target + nextDisplacement, nextVelocity
	else
		local decay = math.exp(-angularFrequency * deltaTime)
		local coefficient = velocity + angularFrequency * displacement
		local nextDisplacement = decay * (displacement + coefficient * deltaTime)
		local nextVelocity = decay * (velocity - angularFrequency * coefficient * deltaTime)
		return target + nextDisplacement, nextVelocity
	end
end

return Integrator
