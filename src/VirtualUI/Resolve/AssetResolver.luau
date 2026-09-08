--!strict

local AssetResolver = {}

function AssetResolver.Resolve(value: unknown): unknown
	if type(value) == "number" then
		return `rbxassetid://{value}`
	end

	if type(value) == "string" and string.match(value, "^%d+$") ~= nil then
		return `rbxassetid://{value}`
	end

	return value
end

return AssetResolver
