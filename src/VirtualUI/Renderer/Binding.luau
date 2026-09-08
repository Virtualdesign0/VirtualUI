--!strict

local Equality = require(script.Parent.Parent.Reactive.Equality)

local BindingImpl = {}
BindingImpl.__index = BindingImpl
local BINDING_BRAND = table.freeze({})

export type Readable<T> = {
	Get: (self: Readable<T>) -> T,
}

export type Source<T> = Readable<T> | (() -> T)

export type BindingOptions<Input, Output> = {
	Map: ((Input) -> Output)?,
	Equals: ((Output, Output) -> boolean)?,
	DebugName: string?,
}

export type MappedBindingOptions<Input, Output> = {
	Map: (Input) -> Output,
	Equals: ((Output, Output) -> boolean)?,
	DebugName: string?,
}

export type BindingMapOptions<T> = {
	Equals: ((T, T) -> boolean)?,
	DebugName: string?,
}

export type Binding<T> = {
	_brand: {},
	_read: () -> T,
	Equals: (T, T) -> boolean,
	DebugName: string?,
	_type: T?,
}

export type BindingModule = {
	new: <T>(source: Source<T>, options: BindingOptions<T, T>?) -> Binding<T>,
	map: <Input, Output>(
		source: Source<Input>,
		mapper: (Input) -> Output,
		options: BindingMapOptions<Output>?
	) -> Binding<Output>,
	Is: (value: unknown) -> boolean,
	Read: <T>(binding: Binding<T>) -> T,
}

local function readSource<T>(source: Source<T>): T
	if type(source) == "function" then
		return source()
	end
	return source:Get()
end

local function createBinding<T>(source: Source<T>, options: BindingOptions<T, T>?): Binding<T>
	local resolvedOptions: BindingOptions<T, T> = options or {}
	local map = resolvedOptions.Map
	local function read(): T
		local value = readSource(source)
		return if map == nil then value else map(value)
	end
	return (
		setmetatable({
			_brand = BINDING_BRAND,
			_read = read,
			Equals = if resolvedOptions.Equals == nil
				then function(left: T, right: T): boolean
					return Equality.Default(left, right)
				end
				else resolvedOptions.Equals,
			DebugName = resolvedOptions.DebugName,
			_type = nil,
		}, BindingImpl) :: unknown
	) :: Binding<T>
end

local function isBinding(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	return (value :: { [string]: unknown })._brand == BINDING_BRAND
end

local function mapBinding<Input, Output>(
	source: Source<Input>,
	mapper: (Input) -> Output,
	options: BindingMapOptions<Output>?
): Binding<Output>
	local resolvedOptions: BindingMapOptions<Output> = options or {}
	local function read(): Output
		return mapper(readSource(source))
	end
	return (
		setmetatable({
			_brand = BINDING_BRAND,
			_read = read,
			Equals = if resolvedOptions.Equals == nil
				then function(left: Output, right: Output): boolean
					return Equality.Default(left, right)
				end
				else resolvedOptions.Equals,
			DebugName = resolvedOptions.DebugName,
			_type = nil,
		}, BindingImpl) :: unknown
	) :: Binding<Output>
end

local function readBinding<T>(binding: Binding<T>): T
	return binding._read()
end

local module: BindingModule = {
	new = createBinding,
	map = mapBinding,
	Is = isBinding,
	Read = readBinding,
}

return module
