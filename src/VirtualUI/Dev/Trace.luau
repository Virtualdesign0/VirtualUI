--!strict

local Trace = {}

export type Event = {
	Sequence: number,
	FlushId: number?,
	TimestampMs: number,
	Kind: string,
	Phase: string?,
	NodeId: number?,
	NodeKind: string?,
	DebugName: string?,
	SourceId: number?,
	SourceKind: string?,
	SourceName: string?,
	TargetId: number?,
	TargetKind: string?,
	TargetName: string?,
	Property: string?,
	Previous: string?,
	Next: string?,
	DurationMs: number?,
	Message: string?,
}

type FlushToken = {
	Id: number,
	Started: number,
}

export type Fields = {
	Phase: string?,
	NodeId: number?,
	NodeKind: string?,
	DebugName: string?,
	SourceId: number?,
	SourceKind: string?,
	SourceName: string?,
	TargetId: number?,
	TargetKind: string?,
	TargetName: string?,
	Property: string?,
	Previous: string?,
	Next: string?,
	DurationMs: number?,
	Message: string?,
}

local enabled = false
local capacity = 2_000
local events: { Event } = {}
local dropped = 0
local sequence = 0
local nextFlushId = 0
local currentFlushId: number? = nil
local epoch = os.clock()

local function optionalString(value: unknown): string?
	return if type(value) == "string" then value else nil
end

local function optionalNumber(value: unknown): number?
	return if type(value) == "number" then value else nil
end

local function copyEvent(event: Event): Event
	return {
		Sequence = event.Sequence,
		FlushId = event.FlushId,
		TimestampMs = event.TimestampMs,
		Kind = event.Kind,
		Phase = event.Phase,
		NodeId = event.NodeId,
		NodeKind = event.NodeKind,
		DebugName = event.DebugName,
		SourceId = event.SourceId,
		SourceKind = event.SourceKind,
		SourceName = event.SourceName,
		TargetId = event.TargetId,
		TargetKind = event.TargetKind,
		TargetName = event.TargetName,
		Property = event.Property,
		Previous = event.Previous,
		Next = event.Next,
		DurationMs = event.DurationMs,
		Message = event.Message,
	}
end

function Trace.SetEnabled(value: boolean)
	enabled = value
end

function Trace.IsEnabled(): boolean
	return enabled
end

function Trace.SetCapacity(value: number)
	assert(
		type(value) == "number" and value >= 1 and value % 1 == 0,
		"TraceCapacity must be a positive integer"
	)
	capacity = value
	while #events > capacity do
		table.remove(events, 1)
		dropped += 1
	end
end

function Trace.Value(value: unknown): string
	local valueType = typeof(value)
	if valueType == "string" then
		return value :: string
	end
	local rendered = table.pack(pcall(tostring, value))
	if rendered[1] then
		return rendered[2] :: string
	end
	return `<{valueType}>`
end

function Trace.PrepareFlush(): number?
	if not enabled then
		return nil
	end
	if currentFlushId == nil then
		nextFlushId += 1
		currentFlushId = nextFlushId
	end
	return currentFlushId
end

function Trace.Record(kind: string, data: Fields?)
	if not enabled then
		return
	end
	local fields: Fields = if data == nil then {} :: Fields else data
	sequence += 1
	local event: Event = {
		Sequence = sequence,
		FlushId = currentFlushId,
		TimestampMs = (os.clock() - epoch) * 1_000,
		Kind = kind,
		Phase = optionalString(fields.Phase),
		NodeId = optionalNumber(fields.NodeId),
		NodeKind = optionalString(fields.NodeKind),
		DebugName = optionalString(fields.DebugName),
		SourceId = optionalNumber(fields.SourceId),
		SourceKind = optionalString(fields.SourceKind),
		SourceName = optionalString(fields.SourceName),
		TargetId = optionalNumber(fields.TargetId),
		TargetKind = optionalString(fields.TargetKind),
		TargetName = optionalString(fields.TargetName),
		Property = optionalString(fields.Property),
		Previous = optionalString(fields.Previous),
		Next = optionalString(fields.Next),
		DurationMs = optionalNumber(fields.DurationMs),
		Message = optionalString(fields.Message),
	}
	if #events >= capacity then
		table.remove(events, 1)
		dropped += 1
	end
	table.insert(events, event)
end

function Trace.Start(): number?
	return if enabled then os.clock() else nil
end

function Trace.RecordDuration(kind: string, started: number?, data: Fields?)
	if started == nil then
		return
	end
	local fields: Fields = if data == nil then {} else table.clone(data)
	fields.DurationMs = (os.clock() - started) * 1_000
	Trace.Record(kind, fields)
end

function Trace.BeginFlush(): FlushToken?
	local id = Trace.PrepareFlush()
	if id == nil then
		return nil
	end
	local token = {
		Id = id,
		Started = os.clock(),
	}
	Trace.Record("FlushStart")
	return token
end

function Trace.FinishFlush(token: FlushToken?)
	if token == nil then
		return
	end
	Trace.Record("FlushEnd", {
		DurationMs = (os.clock() - token.Started) * 1_000,
	})
	if currentFlushId == token.Id then
		currentFlushId = nil
	end
end

function Trace.GetEvents(): { Event }
	local snapshot: { Event } = {}
	for _, event in events do
		table.insert(snapshot, copyEvent(event))
	end
	return snapshot
end

function Trace.GetDroppedCount(): number
	return dropped
end

function Trace.Reset()
	table.clear(events)
	dropped = 0
	sequence = 0
	nextFlushId = 0
	currentFlushId = nil
	epoch = os.clock()
end

function Trace.Format(snapshot: { Event }?): string
	local source = snapshot or events
	local lines: { string } = {}
	for _, event in source do
		local identity = event.DebugName or event.NodeKind
		local detail = if event.Property ~= nil
			then event.Property
			elseif identity ~= nil then identity
			else ""
		local duration = if event.DurationMs == nil
			then ""
			else string.format(" %.3f ms", event.DurationMs)
		table.insert(
			lines,
			`#{event.Sequence} flush={event.FlushId or "-"} {event.Kind} {detail}{duration}`
		)
	end
	return table.concat(lines, "\n")
end

return Trace
