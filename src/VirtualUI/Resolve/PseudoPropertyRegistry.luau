--!strict

local PseudoPropertyRegistry = {}

-- Pseudo-property values are intentionally heterogeneous at this public registry boundary.
export type PropertyMap = { [string]: any }
export type AliasMap = { [string]: string }
export type CoerceMap = { [string]: (value: unknown) -> unknown }
export type Descriptor = {
	ClassName: string,
	Properties: { string },
	Defaults: PropertyMap,
	Aliases: AliasMap?,
	ResolveShorthand: ((value: unknown) -> PropertyMap?)?,
	Coerce: CoerceMap?,
	Resolve: ((value: unknown) -> PropertyMap)?,
}

local registry: { [string]: Descriptor } = {}

local function propertyMap(value: unknown): PropertyMap
	return value :: PropertyMap
end

local function toUDim(value: unknown, propertyName: string): UDim
	if type(value) == "number" then
		return UDim.new(0, value)
	end
	if typeof(value) == "UDim" then
		return value :: UDim
	end
	error(`${propertyName} expects a number or UDim`, 3)
end

local function coerceUDim(propertyName: string): (unknown) -> unknown
	return function(value: unknown): unknown
		return toUDim(value, propertyName)
	end
end

local function validateOptionKeys(value: PropertyMap, name: string, allowed: { [string]: boolean })
	for optionName in value do
		if type(optionName) ~= "string" or not allowed[optionName] then
			error(`Unsupported {name} option "{tostring(optionName)}"`, 3)
		end
	end
end

local function readAlias(value: PropertyMap, nativeName: string, alias: string): unknown
	local nativeValue = value[nativeName]
	local aliasValue = value[alias]
	if nativeValue ~= nil and aliasValue ~= nil then
		error(`Options "{nativeName}" and "{alias}" cannot be supplied together`, 3)
	end
	return if nativeValue ~= nil then nativeValue else aliasValue
end

local function resolveCorner(value: unknown): PropertyMap
	if type(value) == "number" or typeof(value) == "UDim" then
		local radius = toUDim(value, "CornerRadius")
		return {
			CornerRadius = radius,
			TopLeftRadius = radius,
			TopRightRadius = radius,
			BottomRightRadius = radius,
			BottomLeftRadius = radius,
		}
	end
	if type(value) ~= "table" then
		error("CornerRadius expects a number, UDim, or configuration table", 2)
	end
	local options = value :: PropertyMap

	validateOptionKeys(options, "CornerRadius", {
		Radius = true,
		CornerRadius = true,
		TopLeft = true,
		TopLeftRadius = true,
		TopRight = true,
		TopRightRadius = true,
		BottomRight = true,
		BottomRightRadius = true,
		BottomLeft = true,
		BottomLeftRadius = true,
	})
	local baseValue = readAlias(options, "CornerRadius", "Radius")
	local radius = toUDim(if baseValue == nil then 8 else baseValue, "CornerRadius.Radius")
	local topLeft = readAlias(options, "TopLeftRadius", "TopLeft")
	local topRight = readAlias(options, "TopRightRadius", "TopRight")
	local bottomRight = readAlias(options, "BottomRightRadius", "BottomRight")
	local bottomLeft = readAlias(options, "BottomLeftRadius", "BottomLeft")
	return {
		CornerRadius = radius,
		TopLeftRadius = toUDim(if topLeft == nil then radius else topLeft, "CornerRadius.TopLeft"),
		TopRightRadius = toUDim(
			if topRight == nil then radius else topRight,
			"CornerRadius.TopRight"
		),
		BottomRightRadius = toUDim(
			if bottomRight == nil then radius else bottomRight,
			"CornerRadius.BottomRight"
		),
		BottomLeftRadius = toUDim(
			if bottomLeft == nil then radius else bottomLeft,
			"CornerRadius.BottomLeft"
		),
	}
end

local function resolvePadding(value: unknown): PropertyMap
	if type(value) == "number" or typeof(value) == "UDim" then
		local padding = toUDim(value, "Padding")
		return {
			PaddingTop = padding,
			PaddingRight = padding,
			PaddingBottom = padding,
			PaddingLeft = padding,
		}
	end
	if type(value) ~= "table" then
		error("Padding expects a number, UDim, or configuration table", 2)
	end
	local options = value :: PropertyMap

	validateOptionKeys(options, "Padding", {
		All = true,
		Horizontal = true,
		Vertical = true,
		Top = true,
		Right = true,
		Bottom = true,
		Left = true,
		PaddingTop = true,
		PaddingRight = true,
		PaddingBottom = true,
		PaddingLeft = true,
	})
	local all = if options.All == nil then 0 else options.All
	local horizontal = if options.Horizontal == nil then all else options.Horizontal
	local vertical = if options.Vertical == nil then all else options.Vertical
	local top = readAlias(options, "PaddingTop", "Top")
	local right = readAlias(options, "PaddingRight", "Right")
	local bottom = readAlias(options, "PaddingBottom", "Bottom")
	local left = readAlias(options, "PaddingLeft", "Left")
	return {
		PaddingTop = toUDim(if top == nil then vertical else top, "Padding.Top"),
		PaddingRight = toUDim(if right == nil then horizontal else right, "Padding.Right"),
		PaddingBottom = toUDim(if bottom == nil then vertical else bottom, "Padding.Bottom"),
		PaddingLeft = toUDim(if left == nil then horizontal else left, "Padding.Left"),
	}
end

local function register(name: string, descriptor: Descriptor)
	if name == "" then
		error("Pseudo-property name cannot be empty", 3)
	end
	if registry[name] ~= nil then
		error(`Pseudo-property "{name}" is already registered`, 3)
	end
	if
		descriptor.ClassName == ""
		or type(descriptor.Properties) ~= "table"
		or type(descriptor.Defaults) ~= "table"
		or (descriptor.Resolve ~= nil and type(descriptor.Resolve) ~= "function")
		or (descriptor.ResolveShorthand ~= nil and type(descriptor.ResolveShorthand) ~= "function")
		or (descriptor.Aliases ~= nil and type(descriptor.Aliases) ~= "table")
		or (descriptor.Coerce ~= nil and type(descriptor.Coerce) ~= "table")
	then
		error(`Pseudo-property "{name}" has an invalid descriptor`, 3)
	end

	local properties = table.clone(descriptor.Properties)
	local defaults = table.clone(descriptor.Defaults)
	local aliases: AliasMap = if descriptor.Aliases == nil
		then {}
		else table.clone(descriptor.Aliases)
	local coerce: CoerceMap = if descriptor.Coerce == nil
		then {}
		else table.clone(descriptor.Coerce)
	local seen: { [string]: boolean } = {}
	for _, propertyName in properties do
		if type(propertyName) ~= "string" or propertyName == "" or seen[propertyName] then
			error(`Pseudo-property "{name}" has an invalid property schema`, 3)
		end
		if defaults[propertyName] == nil then
			error(`Pseudo-property "{name}" is missing a default for {propertyName}`, 3)
		end
		seen[propertyName] = true
	end
	if next(seen) == nil then
		error(`Pseudo-property "{name}" must declare at least one host property`, 3)
	end
	for alias, propertyName in aliases do
		if type(alias) ~= "string" or alias == "" or not seen[propertyName] then
			error(`Pseudo-property "{name}" has an invalid alias "{tostring(alias)}"`, 3)
		end
	end
	for propertyName, callback in coerce do
		if not seen[propertyName] or type(callback) ~= "function" then
			error(`Pseudo-property "{name}" has an invalid coercer for {tostring(propertyName)}`, 3)
		end
	end

	local snapshot: Descriptor = {
		ClassName = descriptor.ClassName,
		Properties = properties,
		Defaults = defaults,
		Aliases = aliases,
		ResolveShorthand = descriptor.ResolveShorthand,
		Coerce = coerce,
		Resolve = descriptor.Resolve,
	}
	registry[name] = snapshot
	table.freeze(properties)
	table.freeze(defaults)
	table.freeze(aliases)
	table.freeze(coerce)
	table.freeze(snapshot)
end

function PseudoPropertyRegistry.Register(name: string, descriptor: Descriptor)
	register(name, descriptor)
end

function PseudoPropertyRegistry.Get(name: string): Descriptor?
	return registry[name]
end

function PseudoPropertyRegistry.IsRegistered(name: string): boolean
	return registry[name] ~= nil
end

function PseudoPropertyRegistry.Resolve(descriptor: Descriptor, value: unknown): PropertyMap
	local partial: PropertyMap
	if descriptor.Resolve ~= nil then
		partial = descriptor.Resolve(value)
	else
		local shorthand: PropertyMap? = nil
		if descriptor.ResolveShorthand ~= nil then
			shorthand = descriptor.ResolveShorthand(value)
		end
		local input: PropertyMap
		if shorthand == nil then
			if type(value) ~= "table" then
				error(
					`{descriptor.ClassName} pseudo-property expects a configuration table or supported shorthand`,
					3
				)
			end
			input = value :: PropertyMap
		else
			input = shorthand
		end

		partial = {}
		local aliases = descriptor.Aliases or {}
		local coerce: CoerceMap = descriptor.Coerce or {}
		local allowed: { [string]: boolean } = {}
		for _, propertyName in descriptor.Properties do
			allowed[propertyName] = true
		end
		for inputName, inputValue in input do
			if type(inputName) ~= "string" then
				error("Pseudo-property option names must be strings", 3)
			end
			local propertyName = aliases[inputName] or inputName
			if not allowed[propertyName] then
				error(`Unsupported {descriptor.ClassName} option "{inputName}"`, 3)
			end
			if partial[propertyName] ~= nil then
				error(`Pseudo-property option "{propertyName}" was supplied more than once`, 3)
			end
			local callback = coerce[propertyName]
			if callback == nil then
				partial[propertyName] = inputValue
			else
				partial[propertyName] = callback(inputValue)
			end
		end
	end

	if type(partial) ~= "table" then
		error("Pseudo-property resolver must return a property table", 3)
	end

	local allowed: { [string]: boolean } = {}
	local complete: PropertyMap = {}
	for _, propertyName in descriptor.Properties do
		allowed[propertyName] = true
		local resolved = partial[propertyName]
		complete[propertyName] = if resolved == nil
			then descriptor.Defaults[propertyName]
			else resolved
	end
	for propertyName in partial do
		if not allowed[propertyName] then
			error(`Pseudo-property resolver returned undeclared host property "{propertyName}"`, 3)
		end
	end
	return complete
end

register("CornerRadius", {
	ClassName = "UICorner",
	Properties = {
		"CornerRadius",
		"TopLeftRadius",
		"TopRightRadius",
		"BottomRightRadius",
		"BottomLeftRadius",
	},
	Defaults = {
		CornerRadius = UDim.new(0, 8),
		TopLeftRadius = UDim.new(0, 8),
		TopRightRadius = UDim.new(0, 8),
		BottomRightRadius = UDim.new(0, 8),
		BottomLeftRadius = UDim.new(0, 8),
	},
	Aliases = {
		Radius = "CornerRadius",
		TopLeft = "TopLeftRadius",
		TopRight = "TopRightRadius",
		BottomRight = "BottomRightRadius",
		BottomLeft = "BottomLeftRadius",
	},
	Resolve = resolveCorner,
})

register("Padding", {
	ClassName = "UIPadding",
	Properties = { "PaddingTop", "PaddingRight", "PaddingBottom", "PaddingLeft" },
	Defaults = {
		PaddingTop = UDim.new(0, 0),
		PaddingRight = UDim.new(0, 0),
		PaddingBottom = UDim.new(0, 0),
		PaddingLeft = UDim.new(0, 0),
	},
	Aliases = {
		Top = "PaddingTop",
		Right = "PaddingRight",
		Bottom = "PaddingBottom",
		Left = "PaddingLeft",
	},
	Resolve = resolvePadding,
})

register("Stroke", {
	ClassName = "UIStroke",
	Properties = {
		"Thickness",
		"Color",
		"Transparency",
		"Enabled",
		"ApplyStrokeMode",
		"LineJoinMode",
		"BorderOffset",
		"BorderStrokePosition",
		"StrokeSizingMode",
		"ZIndex",
	},
	Defaults = {
		Thickness = 1,
		Color = Color3.new(0, 0, 0),
		Transparency = 0,
		Enabled = true,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		BorderOffset = UDim.new(0, 0),
		BorderStrokePosition = Enum.BorderStrokePosition.Outer,
		StrokeSizingMode = Enum.StrokeSizingMode.FixedSize,
		ZIndex = 1,
	},
	ResolveShorthand = function(value: unknown): PropertyMap?
		return if type(value) == "number" then propertyMap({ Thickness = value }) else nil
	end,
	Coerce = {
		BorderOffset = coerceUDim("Stroke.BorderOffset"),
	},
})

register("Gradient", {
	ClassName = "UIGradient",
	Properties = {
		"Color",
		"Transparency",
		"Rotation",
		"Offset",
		"Enabled",
		"Scale",
		"TileMode",
		"Type",
	},
	Defaults = {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0),
		Rotation = 0,
		Offset = Vector2.new(0, 0),
		Enabled = true,
		Scale = 1,
		TileMode = Enum.GradientTileMode.Clamp,
		Type = Enum.GradientType.Linear,
	},
	Aliases = {
		GradientType = "Type",
	},
	ResolveShorthand = function(value: unknown): PropertyMap?
		return if typeof(value) == "ColorSequence" then propertyMap({ Color = value }) else nil
	end,
})

register("Shadow", {
	ClassName = "UIShadow",
	Properties = {
		"Color",
		"Transparency",
		"BlurRadius",
		"Offset",
		"Spread",
		"Enabled",
		"ZIndex",
	},
	Defaults = {
		Color = Color3.new(0, 0, 0),
		Transparency = 0,
		BlurRadius = UDim.new(0, 0),
		Offset = UDim2.fromOffset(0, 0),
		Spread = UDim2.fromOffset(0, 0),
		Enabled = true,
		ZIndex = -1,
	},
	Coerce = {
		BlurRadius = coerceUDim("Shadow.BlurRadius"),
	},
})

register("Scale", {
	ClassName = "UIScale",
	Properties = { "Scale" },
	Defaults = { Scale = 1 },
	ResolveShorthand = function(value: unknown): PropertyMap?
		return if type(value) == "number" then propertyMap({ Scale = value }) else nil
	end,
})

register("AspectRatio", {
	ClassName = "UIAspectRatioConstraint",
	Properties = { "AspectRatio", "AspectType", "DominantAxis" },
	Defaults = {
		AspectRatio = 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
	},
	Aliases = { Ratio = "AspectRatio" },
	ResolveShorthand = function(value: unknown): PropertyMap?
		return if type(value) == "number" then propertyMap({ AspectRatio = value }) else nil
	end,
})

register("SizeConstraint", {
	ClassName = "UISizeConstraint",
	Properties = { "MinSize", "MaxSize" },
	Defaults = {
		MinSize = Vector2.new(0, 0),
		MaxSize = Vector2.new(math.huge, math.huge),
	},
	Aliases = {
		Min = "MinSize",
		Max = "MaxSize",
	},
})

register("TextSizeConstraint", {
	ClassName = "UITextSizeConstraint",
	Properties = { "MinTextSize", "MaxTextSize" },
	Defaults = {
		MinTextSize = 1,
		MaxTextSize = 100,
	},
	Aliases = {
		Min = "MinTextSize",
		Max = "MaxTextSize",
	},
})

register("ListLayout", {
	ClassName = "UIListLayout",
	Properties = {
		"FillDirection",
		"HorizontalAlignment",
		"VerticalAlignment",
		"SortOrder",
		"Padding",
		"Wraps",
		"HorizontalFlex",
		"VerticalFlex",
		"ItemLineAlignment",
	},
	Defaults = {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.Name,
		Padding = UDim.new(0, 0),
		Wraps = false,
		HorizontalFlex = Enum.UIFlexAlignment.None,
		VerticalFlex = Enum.UIFlexAlignment.None,
		ItemLineAlignment = Enum.ItemLineAlignment.Automatic,
	},
	ResolveShorthand = function(value: unknown): PropertyMap?
		if type(value) == "number" or typeof(value) == "UDim" then
			return propertyMap({ Padding = toUDim(value, "ListLayout.Padding") })
		end
		return nil
	end,
	Coerce = {
		Padding = coerceUDim("ListLayout.Padding"),
	},
})

register("GridLayout", {
	ClassName = "UIGridLayout",
	Properties = {
		"CellSize",
		"CellPadding",
		"FillDirection",
		"FillDirectionMaxCells",
		"StartCorner",
		"HorizontalAlignment",
		"VerticalAlignment",
		"SortOrder",
	},
	Defaults = {
		CellSize = UDim2.fromOffset(100, 100),
		CellPadding = UDim2.fromOffset(5, 5),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 0,
		StartCorner = Enum.StartCorner.TopLeft,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.Name,
	},
})

register("TableLayout", {
	ClassName = "UITableLayout",
	Properties = {
		"FillDirection",
		"HorizontalAlignment",
		"VerticalAlignment",
		"SortOrder",
		"MajorAxis",
		"Padding",
		"FillEmptySpaceColumns",
		"FillEmptySpaceRows",
	},
	Defaults = {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.Name,
		MajorAxis = Enum.TableMajorAxis.RowMajor,
		Padding = UDim2.fromOffset(0, 0),
		FillEmptySpaceColumns = false,
		FillEmptySpaceRows = false,
	},
})

register("PageLayout", {
	ClassName = "UIPageLayout",
	Properties = {
		"FillDirection",
		"HorizontalAlignment",
		"VerticalAlignment",
		"SortOrder",
		"Padding",
		"Animated",
		"Circular",
		"EasingStyle",
		"EasingDirection",
		"TweenTime",
		"GamepadInputEnabled",
		"ScrollWheelInputEnabled",
		"TouchInputEnabled",
	},
	Defaults = {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.Name,
		Padding = UDim.new(0, 0),
		Animated = true,
		Circular = false,
		EasingStyle = Enum.EasingStyle.Back,
		EasingDirection = Enum.EasingDirection.Out,
		TweenTime = 1,
		GamepadInputEnabled = true,
		ScrollWheelInputEnabled = true,
		TouchInputEnabled = true,
	},
	Coerce = {
		Padding = coerceUDim("PageLayout.Padding"),
	},
})

register("Flex", {
	ClassName = "UIFlexItem",
	Properties = { "FlexMode", "GrowRatio", "ShrinkRatio", "ItemLineAlignment" },
	Defaults = {
		FlexMode = Enum.UIFlexMode.None,
		GrowRatio = 0,
		ShrinkRatio = 0,
		ItemLineAlignment = Enum.ItemLineAlignment.Automatic,
	},
	Aliases = {
		Mode = "FlexMode",
		Grow = "GrowRatio",
		Shrink = "ShrinkRatio",
	},
})

return PseudoPropertyRegistry
