--!strict

local Config = require(script.Parent.Parent.Runtime.Config)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Observer = require(script.Parent.Parent.Reactive.Observer)
local PathChangeSet = require(script.Parent.PathChangeSet)
local Scheduler = require(script.Parent.Parent.Scheduler.Scheduler)
local SelectorNode = require(script.Parent.Reactive.SelectorNode)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local Store = {}
Store.__index = Store

-- A module-private table key brands snapshots without exposing a forgeable public StoreId.
local SNAPSHOT_IDENTITY = table.freeze({})

export type Action = {
	Type: string,
}

export type StoreSnapshot<State> = {
	State: State,
	Version: number,
}

export type HistoryEntry<State, ActionType> = {
	Action: ActionType,
	Timestamp: number,
	PreviousVersion: number,
	NextVersion: number,
	PreviousState: State,
	NextState: State,
	ChangedBranches: { PathChangeSet.PathSegment },
	ChangedPaths: { PathChangeSet.Path },
	Duration: number,
}

export type HistoryTransition = {
	PreviousVersion: number,
	NextVersion: number,
}

export type HistoryDiagnostics = {
	CurrentVersion: number,
	LatestAllocatedVersion: number,
	HistoryLimit: number,
	RetainedEntryCount: number,
	RetainedVersions: { number },
	RetainedTransitions: { HistoryTransition },
	SnapshotsRequireRetainedHistory: boolean,
}

export type SelectorOptions<T> = SelectorNode.SelectorOptions<T>
export type Selector<T> = SelectorNode.Selector<T>

export type Store<State, ActionType> = {
	Version: number,
	Destroyed: boolean,
	_state: State,
	_initialState: State,
	_nextVersion: number,
	_snapshotIdentity: {},
	_reducer: (State, ActionType) -> State,
	_reducing: boolean,
	_selectors: { [{}]: boolean },
	_history: { HistoryEntry<State, ActionType> },
	_historyLimit: number,
	_dispatch: (ActionType) -> State,

	GetState: (self: Store<State, ActionType>) -> State,
	Dispatch: (self: Store<State, ActionType>, action: ActionType) -> State,
	Transaction: (self: Store<State, ActionType>, callback: () -> ()) -> (),
	Select: <T>(
		self: Store<State, ActionType>,
		selector: (State) -> T,
		options: SelectorOptions<T>?
	) -> Selector<T>,
	SelectPath: <T>(
		self: Store<State, ActionType>,
		path: string | PathChangeSet.Path,
		options: SelectorOptions<T>?
	) -> Selector<T>,
	GetHistory: (self: Store<State, ActionType>) -> { HistoryEntry<State, ActionType> },
	GetHistoryDiagnostics: (self: Store<State, ActionType>) -> HistoryDiagnostics,
	CanJumpTo: (self: Store<State, ActionType>, version: number) -> boolean,
	CanRestore: (self: Store<State, ActionType>, snapshot: unknown) -> boolean,
	Snapshot: (self: Store<State, ActionType>) -> StoreSnapshot<State>,
	Restore: (self: Store<State, ActionType>, snapshot: StoreSnapshot<State>) -> (),
	JumpTo: (self: Store<State, ActionType>, version: number) -> (),
	Destroy: (self: Store<State, ActionType>) -> (),
	_registerSelector: (self: Store<State, ActionType>, selector: {}) -> (),
	_unregisterSelector: (self: Store<State, ActionType>, selector: {}) -> (),
	_record: (
		self: Store<State, ActionType>,
		action: ActionType,
		previous: State,
		nextState: State,
		changes: PathChangeSet.ChangeSet,
		duration: number,
		previousVersion: number,
		nextVersion: number
	) -> (),
	_commit: (
		self: Store<State, ActionType>,
		nextState: State,
		action: ActionType?,
		duration: number,
		targetVersion: number?,
		recordHistory: boolean?
	) -> State,
	_reduce: (self: Store<State, ActionType>, action: ActionType) -> State,
}

export type Middleware<State, ActionType> = (
	store: Store<State, ActionType>
) -> (next: (ActionType) -> State) -> (action: ActionType) -> State

export type StoreOptions<State, ActionType> = {
	InitialState: State,
	Reducer: (State, ActionType) -> State,
	Middleware: { Middleware<State, ActionType> }?,
	HistoryLimit: number?,
	Scope: Scope.Scope?,
}

type RegisteredSelector = {
	Destroy: (self: RegisteredSelector) -> (),
	_invalidateFromStore: (self: RegisteredSelector, changes: PathChangeSet.ChangeSet) -> (),
}

local function deepFreeze(value: unknown, seen: { [unknown]: boolean }?)
	if type(value) ~= "table" then
		return
	end
	local target = value :: { [unknown]: unknown }
	if table.isfrozen(target) then
		return
	end

	local visited: { [unknown]: boolean } = seen or {}
	if visited[target] then
		return
	end
	visited[target] = true

	for _, child in target do
		deepFreeze(child, visited)
	end
	table.freeze(target)
end

local function validateAction(action: unknown)
	if type(action) ~= "table" then
		error("Store actions must be tables with a non-empty string Type", 3)
	end
	local candidate = action :: { [string]: unknown }
	if type(candidate.Type) ~= "string" or candidate.Type == "" then
		error("Store actions must be tables with a non-empty string Type", 3)
	end
end

local function isVersion(value: unknown): boolean
	return type(value) == "number" and value >= 0 and value % 1 == 0
end

function Store.new<State, ActionType>(options: StoreOptions<State, ActionType>): Store<State, ActionType>
	assert(type(options) == "table", "Store.new requires options")
	assert(type(options.Reducer) == "function", "Store.new requires a Reducer")
	local historyLimit = if options.HistoryLimit == nil
		then Config.GetHistoryLimit()
		else options.HistoryLimit
	assert(
		type(historyLimit) == "number" and historyLimit >= 0 and historyLimit % 1 == 0,
		"Store HistoryLimit must be a non-negative integer"
	)

	local self = (
		setmetatable({
			Version = 0,
			Destroyed = false,
			_state = options.InitialState,
			_initialState = options.InitialState,
			_nextVersion = 0,
			_snapshotIdentity = table.freeze({}),
			_reducer = options.Reducer,
			_reducing = false,
			_selectors = {} :: { [{}]: boolean },
			_history = {} :: { HistoryEntry<State, ActionType> },
			_historyLimit = historyLimit,
		}, Store) :: unknown
	) :: Store<State, ActionType>

	if Config.GetFreezeStoreState() then
		deepFreeze(self._state)
	end

	local dispatch: (ActionType) -> State = function(action: ActionType): State
		return self:_reduce(action)
	end

	local middleware: { Middleware<State, ActionType> } = options.Middleware or {}
	for index = #middleware, 1, -1 do
		local applyMiddleware = middleware[index]
		dispatch = applyMiddleware(self)(dispatch)
	end
	self._dispatch = dispatch

	if options.Scope ~= nil then
		options.Scope:Own(self)
	end

	return self :: Store<State, ActionType>
end

function Store.GetState<State, ActionType>(self: Store<State, ActionType>): State
	if self.Destroyed then
		error("Attempted to access a destroyed Store", 2)
	end
	return self._state
end

function Store._registerSelector<State, ActionType>(self: Store<State, ActionType>, selector: {})
	self._selectors[selector] = true
end

function Store._unregisterSelector<State, ActionType>(self: Store<State, ActionType>, selector: {})
	self._selectors[selector] = nil
end

function Store._record<State, ActionType>(
	self: Store<State, ActionType>,
	action: ActionType,
	previous: State,
	nextState: State,
	changes: PathChangeSet.ChangeSet,
	duration: number,
	previousVersion: number,
	nextVersion: number
)
	if self._historyLimit <= 0 then
		return
	end

	table.insert(self._history, {
		Action = action,
		Timestamp = os.clock(),
		PreviousVersion = previousVersion,
		NextVersion = nextVersion,
		PreviousState = previous,
		NextState = nextState,
		ChangedBranches = PathChangeSet.TopLevelList(changes),
		ChangedPaths = PathChangeSet.ClonePaths(changes),
		Duration = duration,
	})

	if #self._history > self._historyLimit then
		table.remove(self._history, 1)
	end
end

function Store._commit<State, ActionType>(
	self: Store<State, ActionType>,
	nextState: State,
	action: ActionType?,
	duration: number,
	targetVersion: number?,
	recordHistory: boolean?
): State
	local previous = self._state
	if nextState == previous then
		if targetVersion ~= nil then
			self.Version = targetVersion
			self._nextVersion = math.max(self._nextVersion, targetVersion)
		end
		return previous
	end

	if Config.GetFreezeStoreState() then
		deepFreeze(nextState)
	end

	local diffStarted = Profiler.Start()
	local changes = PathChangeSet.Diff(previous, nextState)
	Profiler.Finish("StoreDiffMs", diffStarted)
	Profiler.Increment("StoreDiffVisitedNodes", changes.VisitedNodes)
	Profiler.Increment("StoreChangedPaths", #changes.Paths)
	local previousVersion = self.Version
	local nextVersion: number
	if targetVersion == nil then
		nextVersion = self._nextVersion + 1
	else
		nextVersion = targetVersion
	end
	self._nextVersion = math.max(self._nextVersion, nextVersion)
	self._state = nextState
	self.Version = nextVersion
	if recordHistory ~= false then
		assert(action ~= nil, "Recorded Store commits require an action")
		self:_record(action, previous, nextState, changes, duration, previousVersion, nextVersion)
	end

	local selectors = self._selectors
	for selector in selectors do
		(selector :: RegisteredSelector):_invalidateFromStore(changes)
	end

	return nextState
end

function Store._reduce<State, ActionType>(self: Store<State, ActionType>, action: ActionType): State
	validateAction(action)
	local actionRecord = (action :: unknown) :: { Type: string }
	if self._reducing then
		error(
			"[Store] Dispatch attempted while reducer execution is active. Reducers must remain pure.",
			2
		)
	end

	local started = os.clock()
	self._reducing = true
	local ok, nextState = xpcall(function()
		return self._reducer(self._state, action)
	end, function(message)
		return debug.traceback(tostring(message), 2)
	end)
	self._reducing = false

	if not ok then
		error(nextState, 2)
	end
	if nextState == nil then
		error(`Reducer returned nil for action {actionRecord.Type}`, 2)
	end

	Profiler.Increment("DispatchCount")
	Profiler.Increment("ReducerRuns")
	return self:_commit(nextState, action, os.clock() - started)
end

function Store.Dispatch<State, ActionType>(self: Store<State, ActionType>, action: ActionType): State
	if self.Destroyed then
		error("Attempted to dispatch to a destroyed Store", 2)
	end
	local observer = Observer.GetCurrent()
	if
		observer ~= nil
		and (
			observer.Kind == "Computed"
			or observer.Kind == "Selector"
			or observer.Kind == "Binding"
			or observer.Kind == "Conditional"
			or observer.Kind == "KeyedCollection"
		)
	then
		error(
			`Store dispatch is not allowed while {observer.Kind} "{observer.DebugName or observer.Id}" is evaluating`,
			2
		)
	end
	return self._dispatch(action)
end

function Store.Transaction<State, ActionType>(_self: Store<State, ActionType>, callback: () -> ())
	Scheduler.Batch(callback)
end

function Store.Select<State, ActionType, T>(
	self: Store<State, ActionType>,
	selector: (State) -> T,
	options: SelectorOptions<T>?
): Selector<T>
	assert(type(selector) == "function", "Store:Select requires a selector function")
	return SelectorNode.new(self, selector, options)
end

local function normalizePath(path: string | PathChangeSet.Path): PathChangeSet.Path
	if type(path) == "table" then
		return table.clone(path)
	end
	if type(path) == "string" then
		local result = {}
		for segment in string.gmatch(path, "[^%.]+") do
			table.insert(result, segment)
		end
		return result
	end
	error("Store:SelectPath expects an array or dot-separated string", 3)
end

function Store.SelectPath<State, ActionType, T>(
	self: Store<State, ActionType>,
	path: string | PathChangeSet.Path,
	options: SelectorOptions<T>?
): Selector<T>
	local resolvedOptions: SelectorOptions<T> = {
		Equals = if options == nil then nil else options.Equals,
		DebugName = if options == nil then nil else options.DebugName,
		Scope = if options == nil then nil else options.Scope,
		Path = normalizePath(path),
	}
	return SelectorNode.new(self, nil, resolvedOptions)
end

function Store.GetHistory<State, ActionType>(self: Store<State, ActionType>): { HistoryEntry<State, ActionType> }
	return table.clone(self._history)
end

function Store.CanJumpTo<State, ActionType>(self: Store<State, ActionType>, version: number): boolean
	if self.Destroyed or not isVersion(version) then
		return false
	end
	if version == 0 or version == self.Version then
		return true
	end
	for _, entry in self._history do
		if entry.PreviousVersion == version or entry.NextVersion == version then
			return true
		end
	end
	return false
end

function Store.CanRestore<State, ActionType>(self: Store<State, ActionType>, snapshot: unknown): boolean
	if self.Destroyed or type(snapshot) ~= "table" then
		return false
	end
	local candidate = snapshot :: { [unknown]: unknown }
	return candidate[SNAPSHOT_IDENTITY] == self._snapshotIdentity and isVersion(candidate.Version)
end

function Store.GetHistoryDiagnostics<State, ActionType>(self: Store<State, ActionType>): HistoryDiagnostics
	if self.Destroyed then
		error("Attempted to inspect history for a destroyed Store", 2)
	end

	local retainedSet: { [number]: boolean } = {
		[0] = true,
		[self.Version] = true,
	}
	local transitions = table.create(#self._history) :: { HistoryTransition }
	for index, entry in self._history do
		retainedSet[entry.PreviousVersion] = true
		retainedSet[entry.NextVersion] = true
		local transition: HistoryTransition = {
			PreviousVersion = entry.PreviousVersion,
			NextVersion = entry.NextVersion,
		}
		table.freeze(transition)
		transitions[index] = transition
	end

	local versions: { number } = {}
	for version in retainedSet do
		table.insert(versions, version)
	end
	table.sort(versions)
	table.freeze(versions)
	table.freeze(transitions)

	local diagnostics: HistoryDiagnostics = {
		CurrentVersion = self.Version,
		LatestAllocatedVersion = self._nextVersion,
		HistoryLimit = self._historyLimit,
		RetainedEntryCount = #self._history,
		RetainedVersions = versions,
		RetainedTransitions = transitions,
		SnapshotsRequireRetainedHistory = false,
	}
	table.freeze(diagnostics)
	return diagnostics
end

function Store.Snapshot<State, ActionType>(self: Store<State, ActionType>): StoreSnapshot<State>
	if self.Destroyed then
		error("Attempted to snapshot a destroyed Store", 2)
	end
	local snapshot: { [unknown]: unknown } = {
		State = self._state,
		Version = self.Version,
	}
	snapshot[SNAPSHOT_IDENTITY] = self._snapshotIdentity
	table.freeze(snapshot)
	return (snapshot :: unknown) :: StoreSnapshot<State>
end

function Store.Restore<State, ActionType>(self: Store<State, ActionType>, snapshot: StoreSnapshot<State>)
	if self.Destroyed then
		error("Attempted to restore a destroyed Store", 2)
	end
	if not self:CanRestore(snapshot) then
		error("Store snapshot belongs to another Store or was not created by Store:Snapshot()", 2)
	end

	local knownState: State? = nil
	local versionKnown = false
	if snapshot.Version == self.Version then
		knownState = self._state
		versionKnown = true
	elseif snapshot.Version == 0 then
		knownState = self._initialState
		versionKnown = true
	else
		for _, entry in self._history do
			if entry.NextVersion == snapshot.Version then
				knownState = entry.NextState
				versionKnown = true
				break
			elseif entry.PreviousVersion == snapshot.Version then
				knownState = entry.PreviousState
				versionKnown = true
				break
			end
		end
	end
	if versionKnown and knownState ~= snapshot.State then
		error(`Store snapshot state does not match version {snapshot.Version}`, 2)
	end

	self:_commit(snapshot.State, nil, 0, snapshot.Version, false)
end

function Store.JumpTo<State, ActionType>(self: Store<State, ActionType>, version: number)
	if self.Destroyed then
		error("Attempted to time-travel a destroyed Store", 2)
	end
	if not isVersion(version) then
		error("Store:JumpTo expects a non-negative integer version", 2)
	end
	if version == self.Version then
		return
	end
	if version == 0 then
		self:_commit(self._initialState, nil, 0, 0, false)
		return
	end

	for _, entry in self._history do
		if entry.NextVersion == version then
			self:_commit(entry.NextState, nil, 0, entry.NextVersion, false)
			return
		elseif entry.PreviousVersion == version then
			self:_commit(entry.PreviousState, nil, 0, entry.PreviousVersion, false)
			return
		end
	end

	error(`Store history does not contain version {version}`, 2)
end

function Store.Destroy<State, ActionType>(self: Store<State, ActionType>)
	if self.Destroyed then
		return
	end

	self.Destroyed = true
	local selectors: { RegisteredSelector } = {}
	local selectorSet = self._selectors
	for selector in selectorSet do
		table.insert(selectors, selector :: RegisteredSelector)
	end
	for _, selector in selectors do
		selector:Destroy()
	end
	table.clear(self._history)
end

return Store
