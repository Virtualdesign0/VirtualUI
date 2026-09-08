--!strict

local Equality = {}

function Equality.Default<T>(a: T, b: T): boolean
	return a == b
end

function Equality.Shallow(a: unknown, b: unknown): boolean
	if a == b then
		return true
	end

	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	local left = a :: { [unknown]: unknown }
	local right = b :: { [unknown]: unknown }

	for key, value in left do
		if right[key] ~= value then
			return false
		end
	end

	for key in right do
		if left[key] == nil then
			return false
		end
	end

	return true
end

return Equality
