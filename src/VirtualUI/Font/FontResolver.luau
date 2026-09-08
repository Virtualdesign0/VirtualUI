--!strict

local FontResolver = {}

export type FontSource = Font | Enum.Font | string | number
export type FontOptions = {
	Weight: (Enum.FontWeight | string | number)?,
	Style: (Enum.FontStyle | string)?,
}

local weightByName: { [string]: Enum.FontWeight } = {}
local weightByNumber: { [number]: Enum.FontWeight } = {
	[100] = Enum.FontWeight.Thin,
	[200] = Enum.FontWeight.ExtraLight,
	[300] = Enum.FontWeight.Light,
	[400] = Enum.FontWeight.Regular,
	[500] = Enum.FontWeight.Medium,
	[600] = Enum.FontWeight.SemiBold,
	[700] = Enum.FontWeight.Bold,
	[800] = Enum.FontWeight.ExtraBold,
	[900] = Enum.FontWeight.Heavy,
}
local styleByName: { [string]: Enum.FontStyle } = {}
local legacyFontByName: { [string]: Enum.Font } = {}

local function normalizeName(value: string): string
	local normalized = string.gsub(value, "[%s_%-]", "")
	return string.lower(normalized)
end

for _, weight in Enum.FontWeight:GetEnumItems() do
	weightByName[normalizeName(weight.Name)] = weight
end
for _, style in Enum.FontStyle:GetEnumItems() do
	styleByName[normalizeName(style.Name)] = style
end
for _, legacyFont in Enum.Font:GetEnumItems() do
	legacyFontByName[normalizeName(legacyFont.Name)] = legacyFont
end

local function resolveWeight(value: (Enum.FontWeight | string | number)?): Enum.FontWeight?
	if value == nil then
		return nil
	end
	if typeof(value) == "EnumItem" then
		local enumValue = value :: Enum.FontWeight
		if enumValue.EnumType == Enum.FontWeight then
			return enumValue
		end
	end
	if type(value) == "string" then
		local result = weightByName[normalizeName(value)]
		if result ~= nil then
			return result
		end
	elseif type(value) == "number" then
		local result = weightByNumber[value]
		if result ~= nil then
			return result
		end
	end

	error(`Invalid font weight "{tostring(value)}"`, 3)
end

local function resolveStyle(value: (Enum.FontStyle | string)?): Enum.FontStyle?
	if value == nil then
		return nil
	end
	if typeof(value) == "EnumItem" then
		local enumValue = value :: Enum.FontStyle
		if enumValue.EnumType == Enum.FontStyle then
			return enumValue
		end
	end
	if type(value) == "string" then
		local result = styleByName[normalizeName(value)]
		if result ~= nil then
			return result
		end
	end

	error(`Invalid font style "{tostring(value)}"`, 3)
end

local function applyOverrides(base: Font, weight: Enum.FontWeight?, style: Enum.FontStyle?): Font
	if weight == nil and style == nil then
		return base
	end
	return Font.new(base.Family, weight or base.Weight, style or base.Style)
end

local function concreteWeight(weight: Enum.FontWeight?): Enum.FontWeight
	return weight or Enum.FontWeight.Regular
end

local function concreteStyle(style: Enum.FontStyle?): Enum.FontStyle
	return style or Enum.FontStyle.Normal
end

function FontResolver.Resolve(source: FontSource, options: FontOptions?): Font
	local resolvedOptions: FontOptions = options or {}
	local weight = resolveWeight(resolvedOptions.Weight)
	local style = resolveStyle(resolvedOptions.Style)
	local sourceType = typeof(source)

	if sourceType == "Font" then
		return applyOverrides(source :: Font, weight, style)
	end

	if sourceType == "EnumItem" then
		local enumFont = source :: Enum.Font
		if enumFont.EnumType ~= Enum.Font then
			error(`Expected an Enum.Font item, received {tostring(source)}`, 2)
		end
		return applyOverrides(Font.fromEnum(enumFont), weight, style)
	end

	if type(source) == "number" then
		if source <= 0 or source ~= math.floor(source) or source == math.huge then
			error("Font asset id must be a positive finite integer", 2)
		end
		return Font.fromId(source, concreteWeight(weight), concreteStyle(style))
	end

	if type(source) ~= "string" or source == "" then
		error("Font source must be a Font, Enum.Font, family name, URI, or asset id", 2)
	end

	if string.match(source, "^%d+$") ~= nil then
		local assetId = tonumber(source)
		if assetId == nil or assetId <= 0 then
			error("Font asset id must be a positive finite integer", 2)
		end
		return Font.fromId(assetId, concreteWeight(weight), concreteStyle(style))
	end

	if
		string.match(source, "^rbxasset://") ~= nil
		or string.match(source, "^rbxassetid://") ~= nil
	then
		return Font.new(source, concreteWeight(weight), concreteStyle(style))
	end

	local legacyFont = legacyFontByName[normalizeName(source)]
	if legacyFont ~= nil then
		return applyOverrides(Font.fromEnum(legacyFont), weight, style)
	end

	return Font.fromName(source, concreteWeight(weight), concreteStyle(style))
end

return FontResolver
