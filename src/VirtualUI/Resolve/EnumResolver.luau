--!strict

local EnumResolver = {}

local propertyEnums = {
	ApplyStrokeMode = "ApplyStrokeMode",
	AspectType = "AspectType",
	AutomaticSize = "AutomaticSize",
	BorderMode = "BorderMode",
	BorderStrokePosition = "BorderStrokePosition",
	ButtonStyle = "ButtonStyle",
	DominantAxis = "DominantAxis",
	EasingDirection = "EasingDirection",
	EasingStyle = "EasingStyle",
	FlexMode = "UIFlexMode",
	FillDirection = "FillDirection",
	Font = "Font",
	HorizontalAlignment = "HorizontalAlignment",
	HorizontalFlex = "UIFlexAlignment",
	ItemLineAlignment = "ItemLineAlignment",
	LineJoinMode = "LineJoinMode",
	MajorAxis = "TableMajorAxis",
	ScaleType = "ScaleType",
	ScrollingDirection = "ScrollingDirection",
	SortOrder = "SortOrder",
	StartCorner = "StartCorner",
	StrokeSizingMode = "StrokeSizingMode",
	TextDirection = "TextDirection",
	TextTruncate = "TextTruncate",
	TextXAlignment = "TextXAlignment",
	TextYAlignment = "TextYAlignment",
	VerticalAlignment = "VerticalAlignment",
	VerticalFlex = "UIFlexAlignment",
	VerticalScrollBarPosition = "VerticalScrollBarPosition",
	TileMode = "GradientTileMode",
}

local classPropertyEnums = {
	UIGradient = {
		Type = "GradientType",
	},
}

function EnumResolver.Resolve(className: string, propertyName: string, value: unknown): unknown
	if type(value) ~= "string" then
		return value
	end

	local classEnums = classPropertyEnums[className]
	local enumName = if classEnums == nil
		then propertyEnums[propertyName]
		else classEnums[propertyName]
	if enumName == nil then
		enumName = propertyEnums[propertyName]
	end
	if enumName == nil or Enum == nil then
		return value
	end

	local enumTypes = (Enum :: unknown) :: { [string]: { [string]: EnumItem } }
	local enumType = enumTypes[enumName]
	local enumValue = enumType[value]
	if enumValue == nil then
		error(`Invalid Enum.{enumName} item "{value}" for property {propertyName}`, 2)
	end

	return enumValue
end

return EnumResolver
