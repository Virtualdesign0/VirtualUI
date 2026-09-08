--!strict

local Observer = require(script.Parent.Observer)
local Trace = require(script.Parent.Parent.Dev.Trace)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local Node = {}

local nextId = 0

export type GraphNode = Observer.Node

export type NodeOptions = {
	DebugName: string?,
	Scope: Scope.Scope?,
}

local function detachDependencies(node: GraphNode)
	for dependency in node.Dependencies do
		dependency.Dependents[node] = nil
	end
	table.clear(node.Dependencies)
end

function Node.New(kind: string, options: NodeOptions?): GraphNode
	nextId += 1
	local resolvedOptions: NodeOptions = options or {}

	return {
		Id = nextId,
		Kind = kind,
		DebugName = resolvedOptions.DebugName,
		Version = 0,
		Dirty = false,
		Destroyed = false,
		_scope = resolvedOptions.Scope,
		Dependencies = {} :: { [GraphNode]: boolean },
		Dependents = {} :: { [GraphNode]: boolean },
		_invalidate = nil,
	}
end

function Node.AssertAlive(node: GraphNode)
	if node.Destroyed then
		error(`Attempted to access destroyed {node.Kind} "{node.DebugName or node.Id}"`, 3)
	end
end

function Node.Track(dependency: GraphNode)
	local observer = Observer.GetCurrent()
	if observer == nil or observer == dependency or observer.Destroyed then
		return
	end

	if observer.Dependencies[dependency] then
		return
	end

	observer.Dependencies[dependency] = true
	dependency.Dependents[observer] = true
end

function Node.BeginTracking(node: GraphNode)
	detachDependencies(node)
	Observer.Push(node)
end

function Node.EndTracking(node: GraphNode)
	Observer.Pop(node)
end

function Node.HasDependents(node: GraphNode): boolean
	return next(node.Dependents) ~= nil
end

function Node.InvalidateDependents(node: GraphNode, skipDependent: GraphNode?)
	local tracing = Trace.IsEnabled()
	if tracing and next(node.Dependents) ~= nil then
		Trace.PrepareFlush()
	end
	for dependent in node.Dependents do
		if dependent ~= skipDependent then
			if tracing then
				Trace.Record("Invalidate", {
					SourceId = node.Id,
					SourceKind = node.Kind,
					SourceName = node.DebugName,
					TargetId = dependent.Id,
					TargetKind = dependent.Kind,
					TargetName = dependent.DebugName,
				})
			end
			local invalidate = dependent._invalidate
			if type(invalidate) ~= "function" then
				error(`Reactive node {dependent.Kind}[{dependent.Id}] cannot be invalidated`, 3)
			end
			(invalidate :: (GraphNode, GraphNode) -> ())(dependent, node)
		end
	end
end

function Node.Destroy(node: GraphNode)
	if node.Destroyed then
		return
	end

	node.Destroyed = true
	detachDependencies(node)

	for dependent in node.Dependents do
		dependent.Dependencies[node] = nil
		local invalidate = dependent._invalidate
		if type(invalidate) ~= "function" then
			error(`Reactive node {dependent.Kind}[{dependent.Id}] cannot be invalidated`, 3)
		end
		(invalidate :: (GraphNode, GraphNode) -> ())(dependent, node)
	end
	table.clear(node.Dependents)
end

return Node
