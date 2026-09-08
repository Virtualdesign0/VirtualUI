--!strict

local GraphInspector = {}

type InspectableNode = {
	DebugName: string?,
	Kind: string,
	Id: number,
	Destroyed: boolean,
	Dirty: boolean,
	Version: number,
	Dependents: { [InspectableNode]: boolean },
}

local function label(node: InspectableNode): string
	local name = node.DebugName or `{node.Kind}[{node.Id}]`
	local state = if node.Destroyed then "destroyed" elseif node.Dirty then "dirty" else "clean"
	return `{name} ({state}, v{node.Version})`
end

function GraphInspector.Inspect(root: unknown): string
	local lines: { string } = {}
	local visited: { [InspectableNode]: boolean } = {}

	local function visit(node: InspectableNode, prefix: string)
		table.insert(lines, prefix .. label(node))
		if visited[node] then
			table.insert(lines, prefix .. "  <already visited>")
			return
		end
		visited[node] = true

		for dependent in node.Dependents do
			visit(dependent, prefix .. "  -> ")
		end
	end

	visit(root :: InspectableNode, "")
	return table.concat(lines, "\n")
end

return GraphInspector
