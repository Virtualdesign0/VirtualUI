--!strict

local FontResolver = require(script.Parent.FontResolver)

export type FontReference = {
	Name: string,
}
export type FontSource = FontResolver.FontSource | FontReference
export type FontOptions = FontResolver.FontOptions

type Entry = {
	Source: FontSource,
	Options: FontOptions?,
}

local FontRegistry = {}
local entries: { [string]: Entry } = {}
local references: { [FontReference]: boolean } = (
	setmetatable({}, { __mode = "k" }) :: unknown
) :: { [FontReference]: boolean }
local reservedNames = {
	Resolve = true,
	Register = true,
	Unregister = true,
	IsRegistered = true,
	Ref = true,
}

local function copyOptions(options: FontOptions?): FontOptions?
	if options == nil then
		return nil
	end
	return {
		Weight = options.Weight,
		Style = options.Style,
	}
end

local function mergeOptions(defaults: FontOptions?, overrides: FontOptions?): FontOptions?
	if defaults == nil then
		return copyOptions(overrides)
	end
	if overrides == nil then
		return copyOptions(defaults)
	end
	return {
		Weight = if overrides.Weight == nil then defaults.Weight else overrides.Weight,
		Style = if overrides.Style == nil then defaults.Style else overrides.Style,
	}
end

local function getReferenceName(source: FontSource): string?
	if type(source) == "table" and references[source :: FontReference] then
		return (source :: FontReference).Name
	end
	return nil
end

local resolveEntry: (name: string, options: FontOptions?, visiting: { [string]: boolean }) -> Font

local function resolveSource(
	source: FontSource,
	options: FontOptions?,
	visiting: { [string]: boolean }
): Font
	local referenceName = getReferenceName(source)
	if referenceName ~= nil then
		return resolveEntry(referenceName, options, visiting)
	end

	return FontResolver.Resolve(source :: FontResolver.FontSource, options)
end

resolveEntry = function(name: string, options: FontOptions?, visiting: { [string]: boolean }): Font
	local entry = entries[name]
	if entry == nil then
		error(`Font alias references missing alias "{name}"`, 3)
	end
	if visiting[name] then
		error(`Font registry cycle detected at "{name}"`, 3)
	end

	visiting[name] = true
	local result = resolveSource(entry.Source, mergeOptions(entry.Options, options), visiting)
	visiting[name] = nil
	return result
end

function FontRegistry.Ref(name: string): FontReference
	if name == "" then
		error("Font reference name cannot be empty", 2)
	end
	local reference: FontReference = { Name = name }
	table.freeze(reference)
	references[reference] = true
	return reference
end

function FontRegistry.Resolve(source: FontSource, options: FontOptions?): Font
	if type(source) == "string" and entries[source] ~= nil then
		return resolveEntry(source, options, {})
	end
	return resolveSource(source, options, {})
end

function FontRegistry.Register(name: string, source: FontSource, options: FontOptions?)
	if name == "" then
		error("Font registry name cannot be empty", 2)
	end
	if reservedNames[name] then
		error(`Font registry name "{name}" is reserved`, 2)
	end
	if entries[name] ~= nil then
		error(`Font registry entry "{name}" is already registered`, 2)
	end
	entries[name] = {
		Source = source,
		Options = copyOptions(options),
	}
end

function FontRegistry.Unregister(name: string): boolean
	if entries[name] == nil then
		return false
	end
	entries[name] = nil
	return true
end

function FontRegistry.IsRegistered(name: string): boolean
	return entries[name] ~= nil
end

return FontRegistry
