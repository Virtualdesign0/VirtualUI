--!strict

local EventResolver = {}

local aliases = {
	OnActivated = "Activated",
	OnChanged = "Changed",
	OnClick = "Activated",
	OnFocusLost = "FocusLost",
	OnFocused = "Focused",
	OnInputBegan = "InputBegan",
	OnInputChanged = "InputChanged",
	OnInputEnded = "InputEnded",
	OnMouseEnter = "MouseEnter",
	OnMouseLeave = "MouseLeave",
	OnSelectionGained = "SelectionGained",
	OnSelectionLost = "SelectionLost",
}

function EventResolver.Resolve(propertyName: string): string?
	return aliases[propertyName]
end

return EventResolver
