--!strict

local ValueCodec = {}

export type Components = { number }
export type Value = number | Vector2 | Vector3 | UDim | UDim2 | Color3

function ValueCodec.Encode(value: unknown): (string, Components)
	if type(value) == "number" then
		return "number", { value }
	end

	local valueType = typeof(value)
	if valueType == "Vector2" then
		local vector = value :: Vector2
		return "Vector2", { vector.X, vector.Y }
	elseif valueType == "Vector3" then
		local vector = value :: Vector3
		return "Vector3", { vector.X, vector.Y, vector.Z }
	elseif valueType == "UDim" then
		local dimension = value :: UDim
		return "UDim", { dimension.Scale, dimension.Offset }
	elseif valueType == "UDim2" then
		local dimension = value :: UDim2
		return "UDim2",
			{
				dimension.X.Scale,
				dimension.X.Offset,
				dimension.Y.Scale,
				dimension.Y.Offset,
			}
	elseif valueType == "Color3" then
		local color = value :: Color3
		return "Color3", { color.R, color.G, color.B }
	end

	error(
		`Unsupported motion value {valueType}; expected number, Vector2, Vector3, UDim, UDim2, or Color3`,
		3
	)
end

function ValueCodec.Decode(kind: string, components: Components): Value
	if kind == "number" then
		return components[1]
	elseif kind == "Vector2" then
		return Vector2.new(components[1], components[2])
	elseif kind == "Vector3" then
		return Vector3.new(components[1], components[2], components[3])
	elseif kind == "UDim" then
		return UDim.new(components[1], components[2])
	elseif kind == "UDim2" then
		return UDim2.new(components[1], components[2], components[3], components[4])
	elseif kind == "Color3" then
		return Color3.new(components[1], components[2], components[3])
	end
	error(`Unknown motion value kind {kind}`, 3)
end

function ValueCodec.EncodeCompatible(value: unknown, expectedKind: string): Components
	local kind, components = ValueCodec.Encode(value)
	if kind ~= expectedKind then
		error(`Motion target type changed from {expectedKind} to {kind}`, 3)
	end
	return components
end

function ValueCodec.Zero(count: number): Components
	local result = table.create(count, 0)
	return result :: Components
end

function ValueCodec.Lerp(from: Components, to: Components, alpha: number): Components
	local result = table.create(#from, 0) :: Components
	for index, value in from do
		result[index] = value + (to[index] - value) * alpha
	end
	return result
end

function ValueCodec.IsAtRest(
	position: Components,
	target: Components,
	velocity: Components,
	positionEpsilon: number,
	velocityEpsilon: number
): boolean
	for index, value in position do
		if math.abs(target[index] - value) > positionEpsilon then
			return false
		end
		if math.abs(velocity[index]) > velocityEpsilon then
			return false
		end
	end
	return true
end

return ValueCodec
