--!strict

local Config = require(script.Parent.Parent.Runtime.Config)
local Scope = require(script.Parent.Parent.Lifetime.Scope)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Trace = require(script.Parent.Parent.Dev.Trace)
local Queue = require(script.Parent.Queue)

local Scheduler = {}

type ErrorSource = {
	Id: number,
	Kind: string,
	DebugName: string?,
}

type SchedulerJob = ErrorSource & {
	Destroyed: boolean,
	_scope: Scope.Scope?,
	_errorSource: ErrorSource?,
}

type ComputationJob = SchedulerJob & { _recompute: (self: unknown) -> () }
type StructureJob = SchedulerJob & { _apply: (self: unknown) -> () }
type BindingJob = SchedulerJob & { _apply: (self: unknown) -> () }
type EffectJob = SchedulerJob & { _run: (self: unknown) -> () }
type CleanupJob = SchedulerJob & { _cleanup: (self: unknown) -> () }

local computationQueue = Queue.new()
local structureQueue = Queue.new()
local bindingQueue = Queue.new()
local effectQueue = Queue.new()
local cleanupQueue = Queue.new()

local batchDepth = 0
local flushing = false
local scheduled = false

local function hasWork(): boolean
	return not computationQueue:IsEmpty()
		or not structureQueue:IsEmpty()
		or not bindingQueue:IsEmpty()
		or not effectQueue:IsEmpty()
		or not cleanupQueue:IsEmpty()
end

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function enqueue(queue: Queue.Queue, value: unknown)
	queue:Push(value :: {})
end

local function runQueue(
	queue: Queue.Queue,
	execute: (job: SchedulerJob) -> (),
	metricName: string
): unknown
	local started = Profiler.Start()
	local firstError: unknown = nil
	local tracing = Trace.IsEnabled()

	for _, value in queue:Drain() do
		local job = (value :: unknown) :: SchedulerJob
		if not job.Destroyed then
			local jobStarted = if tracing then Trace.Start() else nil
			local result = table.pack(xpcall(function()
				execute(job)
			end, traceback))
			local ok = result[1]
			local message = result[2]
			if tracing then
				Trace.RecordDuration("Job", jobStarted, {
					Phase = metricName,
					NodeId = job.Id,
					NodeKind = job.Kind,
					DebugName = job.DebugName,
				})
			end

			if not ok then
				local errorSource = job._errorSource or job
				job._errorSource = nil
				Trace.Record("Error", {
					Phase = metricName,
					NodeId = errorSource.Id,
					NodeKind = errorSource.Kind,
					DebugName = errorSource.DebugName,
					Message = tostring(message),
				})
				local handled, routedMessage = Scope.RouteError(job._scope, message, errorSource)
				if not handled and firstError == nil then
					firstError = routedMessage
				end
			end
		end
	end

	Profiler.Finish(metricName, started)
	return firstError
end

local function runComputation(job: SchedulerJob)
	local typed = (job :: unknown) :: ComputationJob
	typed._recompute(typed)
end

local function runStructure(job: SchedulerJob)
	local typed = (job :: unknown) :: StructureJob
	typed._apply(typed)
end

local function runBinding(job: SchedulerJob)
	local typed = (job :: unknown) :: BindingJob
	typed._apply(typed)
end

local function runEffect(job: SchedulerJob)
	local typed = (job :: unknown) :: EffectJob
	typed._run(typed)
end

local function runCleanup(job: SchedulerJob)
	local typed = (job :: unknown) :: CleanupJob
	typed._cleanup(typed)
end

function Scheduler.Flush()
	if flushing then
		return
	end

	flushing = true
	scheduled = false
	local traceToken = Trace.BeginFlush()
	local started = Profiler.Start()
	local firstError: unknown = nil
	local iterations = 0
	local maximum = Config.GetMaxFlushIterations()

	while hasWork() do
		iterations += 1
		if iterations > maximum then
			firstError = `Scheduler exceeded {maximum} flush iterations; possible reactive loop`
			break
		end

		local computationError = runQueue(computationQueue, runComputation, "ComputationMs")
		local structureError = runQueue(structureQueue, runStructure, "StructureMs")
		local bindingError = runQueue(bindingQueue, runBinding, "BindingMs")
		local effectError = runQueue(effectQueue, runEffect, "EffectMs")
		local cleanupError = runQueue(cleanupQueue, runCleanup, "CleanupMs")
		firstError = firstError
			or computationError
			or structureError
			or bindingError
			or effectError
			or cleanupError
	end

	flushing = false
	Profiler.Finish("SchedulerMs", started)
	Profiler.Increment("SchedulerFlushes")
	Trace.FinishFlush(traceToken)

	if firstError ~= nil then
		Config.ReportError(firstError, "[UI Scheduler]")
	end
end

local function requestFlush()
	if scheduled or flushing or batchDepth > 0 then
		return
	end

	scheduled = true
	Trace.PrepareFlush()
	if task ~= nil and task.defer ~= nil then
		task.defer(Scheduler.Flush)
	else
		Scheduler.Flush()
	end
end

function Scheduler.EnqueueComputation(job: unknown)
	enqueue(computationQueue, job)
	requestFlush()
end

function Scheduler.EnqueueBinding(job: unknown)
	enqueue(bindingQueue, job)
	requestFlush()
end

function Scheduler.EnqueueStructure(job: unknown)
	enqueue(structureQueue, job)
	requestFlush()
end

function Scheduler.EnqueueEffect(job: unknown)
	enqueue(effectQueue, job)
	requestFlush()
end

function Scheduler.EnqueueCleanup(job: unknown)
	enqueue(cleanupQueue, job)
	requestFlush()
end

function Scheduler.Batch(callback: () -> ...any): ...any
	batchDepth += 1
	local packed = table.pack(xpcall(callback, traceback))
	batchDepth -= 1

	if batchDepth == 0 and hasWork() then
		Scheduler.Flush()
	end

	if not packed[1] then
		error(packed[2], 2)
	end

	return table.unpack(packed, 2, packed.n)
end

function Scheduler.IsFlushing(): boolean
	return flushing
end

function Scheduler.IsBatching(): boolean
	return batchDepth > 0
end

return Scheduler
