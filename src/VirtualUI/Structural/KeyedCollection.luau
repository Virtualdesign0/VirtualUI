--!strict

local Binding = require(script.Parent.Parent.Renderer.Binding)
local Node = require(script.Parent.Parent.Reactive.Node)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Renderer = require(script.Parent.Parent.Renderer.Renderer)
local Scheduler = require(script.Parent.Parent.Scheduler.Scheduler)
local Scope = require(script.Parent.Parent.Lifetime.Scope)
local State = require(script.Parent.Parent.Reactive.State)

local KeyedCollection = {}
KeyedCollection.__index = KeyedCollection

export type KeyedCollectionOptions<HostInstance> = {
	Parent: HostInstance,
	OrderMode: ("Automatic" | "Manual")?,
	Scope: Scope.Scope?,
	DebugName: string?,
}

export type KeyedCollection<Item, Key, HostInstance> = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Destroyed: boolean,
	Dirty: boolean,
	Version: number,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_binding: Binding.Binding<{ Item }>,
	_keyOf: (item: Item, index: number) -> Key,
	_render: (
		item: State.State<Item>,
		index: State.State<number>,
		scope: Scope.Scope
	) -> Renderer.Rendered<HostInstance>,
	_parent: HostInstance,
	_ownerScope: Scope.Scope?,
	_orderMode: "Automatic" | "Manual",
	_host: Renderer.Host<HostInstance, unknown>,
	_entries: { [Key]: Entry<Item, HostInstance> },
	_orderedEntries: { Entry<Item, HostInstance> },
	_keys: { Key },
	GetInstance: (self: KeyedCollection<Item, Key, HostInstance>, key: Key) -> HostInstance?,
	GetInstances: (self: KeyedCollection<Item, Key, HostInstance>, key: Key) -> { HostInstance },
	GetKeys: (self: KeyedCollection<Item, Key, HostInstance>) -> { Key },
	Destroy: (self: KeyedCollection<Item, Key, HostInstance>) -> (),
	_readItems: (self: KeyedCollection<Item, Key, HostInstance>) -> { Item },
	_createEntry: (
		self: KeyedCollection<Item, Key, HostInstance>,
		item: Item,
		index: number,
		key: Key
	) -> Entry<Item, HostInstance>,
	_apply: (self: KeyedCollection<Item, Key, HostInstance>) -> (),
	_invalidate: (
		self: KeyedCollection<Item, Key, HostInstance>,
		source: Node.GraphNode
	) -> (),
}

type Entry<Item, HostInstance> = {
	Scope: Scope.Scope,
	Item: State.State<Item>,
	Index: State.State<number>,
	Rendered: Renderer.Rendered<HostInstance>,
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

function KeyedCollection.new<Item, Key, HostInstance>(
	source: Binding.Source<{ Item }>,
	keyOf: (item: Item, index: number) -> Key,
	render: (
		item: State.State<Item>,
		index: State.State<number>,
		scope: Scope.Scope
	) -> Renderer.Rendered<HostInstance>,
	options: KeyedCollectionOptions<HostInstance>
): KeyedCollection<Item, Key, HostInstance>
	assert(type(keyOf) == "function", "KeyedCollection.new requires a key function")
	assert(type(render) == "function", "KeyedCollection.new requires a render function")
	assert(type(options) == "table", "KeyedCollection.new requires options")

	local self = (
		setmetatable(Node.New("KeyedCollection", options), KeyedCollection) :: unknown
	) :: KeyedCollection<Item, Key, HostInstance>
	self.Dirty = true
	self._binding = Binding.new(source)
	self._keyOf = keyOf
	self._render = render
	self._parent = options.Parent
	self._ownerScope = options.Scope
	self._orderMode = options.OrderMode or "Automatic"
	if self._orderMode ~= "Automatic" and self._orderMode ~= "Manual" then
		error('KeyedCollection OrderMode must be "Automatic" or "Manual"', 2)
	end
	self._host = Renderer.GetHost()
	self._entries = {}
	self._orderedEntries = {}
	self._keys = {}

	if options.Scope ~= nil then
		options.Scope:Own(self)
	end

	local construction = table.pack(xpcall(function()
		self:_apply()
	end, traceback))
	local ok = construction[1]
	local message = construction[2]
	if not ok then
		self:Destroy()
		error(message, 2)
	end

	return self
end

function KeyedCollection.GetInstance<Item, Key, HostInstance>(
	self: KeyedCollection<
		Item,
		Key,
		HostInstance
	>,
	key: Key
): HostInstance?
	local entry = self._entries[key]
	return if entry == nil then nil else Renderer.GetFirstRenderedInstance(entry.Rendered)
end

function KeyedCollection.GetInstances<Item, Key, HostInstance>(
	self: KeyedCollection<
		Item,
		Key,
		HostInstance
	>,
	key: Key
): { HostInstance }
	local entry = self._entries[key]
	return if entry == nil then {} else Renderer.GetRenderedInstances(entry.Rendered)
end

function KeyedCollection.GetKeys<Item, Key, HostInstance>(self: KeyedCollection<Item, Key, HostInstance>): { Key }
	return table.clone(self._keys)
end

function KeyedCollection._readItems<Item, Key, HostInstance>(self: KeyedCollection<
	Item,
	Key,
	HostInstance
>): { Item }
	Node.BeginTracking(self)
	local result = table.pack(xpcall(function()
		return Binding.Read(self._binding)
	end, traceback))
	Node.EndTracking(self)

	if not result[1] then
		error(result[2], 2)
	end
	if type(result[2]) ~= "table" then
		error("KeyedCollection source must return an array", 2)
	end
	return result[2] :: { Item }
end

function KeyedCollection._createEntry<Item, Key, HostInstance>(
	self: KeyedCollection<
		Item,
		Key,
		HostInstance
	>,
	item: Item,
	index: number,
	key: Key
): Entry<Item, HostInstance>
	local entryScope = Scope.new({
		DebugName = `{self.DebugName or self.Id}[{tostring(key)}]`,
		Parent = self._ownerScope,
	})
	local itemState = State.new(item, { Scope = entryScope })
	local indexState = State.new(index, { Scope = entryScope })
	local created = table.pack(xpcall(function()
		local rendered = self._render(itemState, indexState, entryScope)
		if rendered == nil then
			error(`KeyedCollection render returned nil for key {tostring(key)}`, 2)
		end
		Renderer.OwnRendered(entryScope, rendered, self._host)
		return rendered
	end, traceback))
	local ok = created[1]
	local rendered: unknown = created[2]

	if not ok then
		local cleanupOk, cleanupMessage = pcall(function()
			entryScope:Destroy()
		end)
		if not cleanupOk then
			rendered = `{rendered}\nEntry cleanup also failed: {cleanupMessage}`
		end
		error(rendered, 2)
	end
	return {
		Scope = entryScope,
		Item = itemState,
		Index = indexState,
		Rendered = rendered :: Renderer.Rendered<HostInstance>,
	}
end

function KeyedCollection._apply<Item, Key, HostInstance>(self: KeyedCollection<Item, Key, HostInstance>)
	if self.Destroyed or not self.Dirty then
		return
	end
	self.Dirty = false

	local items = self:_readItems()
	local indexStarted = Profiler.Start()
	local nextKeys = table.create(#items) :: { Key }
	local sameKeys = #items == #self._keys
	for index, item in items do
		local key = self._keyOf(item, index)
		if key == nil then
			error(`KeyedCollection key at index {index} is nil`, 2)
		end
		nextKeys[index] = key
		if sameKeys and self._keys[index] ~= key then
			sameKeys = false
		end
	end
	if sameKeys then
		Profiler.Finish("KeyedIndexMs", indexStarted)
		local commitStarted = Profiler.Start()
		local automaticOrder = self._orderMode == "Automatic"
		local childOrder = 1
		for index in nextKeys do
			local entry = self._orderedEntries[index]
			local nextItem = items[index]
			if entry.Item._value ~= nextItem then
				entry.Item:Set(nextItem)
			end

			if automaticOrder then
				childOrder += Renderer.OrderRendered(
					entry.Rendered,
					self._parent,
					self._host,
					childOrder
				)
			end
		end
		Profiler.Finish("KeyedCommitMs", commitStarted)
		Profiler.Increment("KeyedRetainedFastPaths")
		Profiler.Increment("KeyedScannedItems", #items)
		self.Version = (self.Version :: number) + 1
		Profiler.Increment("StructuralEvaluations")
		return
	end

	local nextIndices: { [Key]: number } = {}
	for index, key in nextKeys do
		if nextIndices[key] ~= nil then
			error(`KeyedCollection received duplicate key {tostring(key)}`, 2)
		end
		nextIndices[key] = index
	end
	Profiler.Finish("KeyedIndexMs", indexStarted)

	local created: { [Key]: Entry<Item, HostInstance> } = {}
	local nextEntries = table.create(#items) :: { Entry<Item, HostInstance> }
	local createStarted = Profiler.Start()
	local creation = table.pack(xpcall(function()
		for index, key in nextKeys do
			local entry = self._entries[key]
			if entry == nil then
				entry = self:_createEntry(items[index], index, key)
				created[key] = entry
			end
			nextEntries[index] = entry
		end
	end, traceback))
	Profiler.Finish("KeyedCreateMs", createStarted)
	local ok = creation[1]
	local createError = creation[2]
	if not ok then
		for _, entry in created do
			entry.Scope:Destroy()
		end
		error(createError, 2)
	end

	local destroyStarted = Profiler.Start()
	for key, entry in self._entries do
		if nextIndices[key] == nil then
			entry.Scope:Destroy()
			self._entries[key] = nil
			Profiler.Increment("StructuralUnmounts")
		end
	end
	Profiler.Finish("KeyedDestroyMs", destroyStarted)

	local commitStarted = Profiler.Start()
	local automaticOrder = self._orderMode == "Automatic"
	local childOrder = 1
	for index, key in nextKeys do
		local entry = nextEntries[index]
		local isNew = created[key] ~= nil
		if isNew then
			self._entries[key] = entry
			Profiler.Increment("StructuralMounts")
		else
			local nextItem = items[index]
			if entry.Item._value ~= nextItem then
				entry.Item:Set(nextItem)
			end
			if entry.Index._value ~= index then
				entry.Index:Set(index)
			end
		end

		if isNew then
			local startOrder = if automaticOrder then childOrder else nil
			local rootCount =
				Renderer.ParentRendered(entry.Rendered, self._parent, self._host, startOrder)
			if automaticOrder then
				childOrder += rootCount
			end
		elseif automaticOrder then
			childOrder += Renderer.OrderRendered(
				entry.Rendered,
				self._parent,
				self._host,
				childOrder
			)
		end
	end
	Profiler.Finish("KeyedCommitMs", commitStarted)

	self._orderedEntries = nextEntries
	self._keys = nextKeys
	self.Version = (self.Version :: number) + 1
	Profiler.Increment("KeyedScannedItems", #items)
	Profiler.Increment("StructuralEvaluations")
end

function KeyedCollection._invalidate<Item, Key, HostInstance>(
	self: KeyedCollection<
		Item,
		Key,
		HostInstance
	>,
	_source: Node.GraphNode
)
	if self.Destroyed or self.Dirty then
		return
	end
	self.Dirty = true
	Scheduler.EnqueueStructure(self)
end

function KeyedCollection.Destroy<Item, Key, HostInstance>(self: KeyedCollection<Item, Key, HostInstance>)
	if self.Destroyed then
		return
	end

	for _, entry in self._entries do
		entry.Scope:Destroy()
	end
	table.clear(self._entries)
	table.clear(self._orderedEntries)
	table.clear(self._keys)
	Node.Destroy(self)
end

return KeyedCollection
