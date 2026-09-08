--!strict

local AssetResolver = require(script.Parent.AssetResolver)
local EnumResolver = require(script.Parent.EnumResolver)

local PropertyResolver = {}

local assetProperties = {
	AnimationId = true,
	Image = true,
	SoundId = true,
	Texture = true,
	TextureId = true,
	Video = true,
}

function PropertyResolver.Resolve(className: string, propertyName: string, value: unknown): unknown
	if assetProperties[propertyName] then
		return AssetResolver.Resolve(value)
	end

	return EnumResolver.Resolve(className, propertyName, value)
end

return PropertyResolver
