--!strict

local PathChangeSet = {}

export type PathSegment = string | number
export type Path = { PathSegment }

export type ChangeNode = {
	Terminal: boolean,
	Children: { [PathSegment]: ChangeNode },
}

export type ChangeSet = {
	Tree: ChangeNode,
	Paths: { Path },
	TopLevel: { [PathSegment]: boolean },
	VisitedNodes: number,
}

type StateTable = { [PathSegment]: unknown }
type ActivePairs = { [StateTable]: { [StateTable]: boolean } }

local function newNode(): ChangeNode
	return {
		Terminal = false,
		Children = {},
	}
end

local function markChanged(changeSet: ChangeSet, path: Path)
	local node = changeSet.Tree
	for _, segment in path do
		local child = node.Children[segment]
		if child == nil then
			child = newNode()
			node.Children[segment] = child
		end
		node = child
	end
	node.Terminal = true

	table.insert(changeSet.Paths, table.clone(path))
	changeSet.TopLevel[if #path == 0 then "*" else path[1]] = true
end

local function visit(
	previous: unknown,
	nextValue: unknown,
	path: Path,
	changeSet: ChangeSet,
	active: ActivePairs
)
	changeSet.VisitedNodes += 1
	if previous == nextValue then
		return
	end
	if type(previous) ~= "table" or type(nextValue) ~= "table" then
		markChanged(changeSet, path)
		return
	end

	local previousTable = previous :: StateTable
	local nextTable = nextValue :: StateTable
	local previousActive = active[previousTable]
	if previousActive == nil then
		previousActive = {}
		active[previousTable] = previousActive
	elseif previousActive[nextTable] then
		-- A recursive table graph has no finite set of leaf paths. Conservatively
		-- invalidate the path that closes the cycle and stop this branch.
		markChanged(changeSet, path)
		return
	end
	previousActive[nextTable] = true

	local visitedKeys: { [PathSegment]: boolean } = {}
	for key, previousChild in previousTable do
		visitedKeys[key] = true
		path[#path + 1] = key
		visit(previousChild, nextTable[key], path, changeSet, active)
		path[#path] = nil
	end
	for key, nextChild in nextTable do
		if not visitedKeys[key] then
			path[#path + 1] = key
			visit(nil, nextChild, path, changeSet, active)
			path[#path] = nil
		end
	end

	previousActive[nextTable] = nil
	if next(previousActive) == nil then
		active[previousTable] = nil
	end
end

function PathChangeSet.Diff(previous: unknown, nextValue: unknown): ChangeSet
	local changeSet: ChangeSet = {
		Tree = newNode(),
		Paths = {},
		TopLevel = {},
		VisitedNodes = 0,
	}
	visit(previous, nextValue, {}, changeSet, {})
	return changeSet
end

function PathChangeSet.Overlaps(changeSet: ChangeSet, path: Path): boolean
	local node = changeSet.Tree
	if node.Terminal then
		return true
	end

	for _, segment in path do
		local child = node.Children[segment]
		if child == nil then
			return false
		end
		node = child
		if node.Terminal then
			return true
		end
	end

	return next(node.Children) ~= nil
end

function PathChangeSet.ClonePaths(changeSet: ChangeSet): { Path }
	local result = table.create(#changeSet.Paths) :: { Path }
	for index, path in changeSet.Paths do
		result[index] = table.clone(path)
	end
	return result
end

function PathChangeSet.TopLevelList(changeSet: ChangeSet): { PathSegment }
	local result: { PathSegment } = {}
	for branch in changeSet.TopLevel do
		table.insert(result, branch)
	end
	return result
end

return PathChangeSet
