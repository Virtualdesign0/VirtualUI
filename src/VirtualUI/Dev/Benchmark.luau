--!strict

local Profiler = require(script.Parent.Profiler)

local Benchmark = {}

export type Options = {
	Name: string,
	Iterations: number,
	Run: (number) -> (),
	Warmup: number?,
	Samples: number?,
}

export type Result = {
	Name: string,
	Iterations: number,
	Warmup: number,
	Samples: number,
	TotalMs: number,
	DurationMs: number,
	AverageMs: number,
	MeanMs: number,
	MedianMs: number,
	P95Ms: number,
	P99Ms: number,
	MinMs: number,
	MaxMs: number,
	MemoryDeltaKB: number,
	SampleDurationsMs: { number },
	Metrics: { [string]: number },
}

local function assertInteger(value: number, minimum: number, message: string)
	assert(type(value) == "number" and value >= minimum and value % 1 == 0, message)
end

local function runWindow(iterations: number, callback: (number) -> ()): number
	local started = os.clock()
	for index = 1, iterations do
		callback(index)
	end
	return (os.clock() - started) * 1000
end

local function percentile(sorted: { number }, fraction: number): number
	local rank = math.max(1, math.ceil(#sorted * fraction))
	return sorted[rank]
end

function Benchmark.Run(
	optionsOrName: Options | string,
	legacyIterations: number?,
	legacyCallback: ((number) -> ())?
): Result
	local options: Options
	if type(optionsOrName) == "table" then
		options = optionsOrName :: Options
	else
		options = {
			Name = optionsOrName,
			Iterations = legacyIterations :: number,
			Run = legacyCallback :: (number) -> (),
			Warmup = 0,
			Samples = 1,
		}
	end

	local name = options.Name
	local iterations = options.Iterations
	local callback = options.Run
	local warmup = options.Warmup or 0
	local samples = options.Samples or 1

	assert(type(name) == "string" and name ~= "", "Benchmark name must be non-empty")
	assertInteger(iterations, 1, "Benchmark iterations must be a positive integer")
	assertInteger(warmup, 0, "Benchmark warmup must be a non-negative integer")
	assertInteger(samples, 1, "Benchmark samples must be a positive integer")
	assert(type(callback) == "function", "Benchmark callback must be a function")

	for _ = 1, warmup do
		runWindow(iterations, callback)
	end

	Profiler.Reset()
	local memoryBefore = gcinfo()
	local sampleDurations = table.create(samples, 0)
	local totalMs = 0
	for sample = 1, samples do
		local durationMs = runWindow(iterations, callback)
		sampleDurations[sample] = durationMs
		totalMs += durationMs
	end
	local memoryDeltaKB = gcinfo() - memoryBefore
	local sorted = table.clone(sampleDurations)
	table.sort(sorted)
	local middle = math.floor(#sorted / 2)
	local medianMs = if #sorted % 2 == 0
		then (sorted[middle] + sorted[middle + 1]) / 2
		else sorted[middle + 1]
	local p95Ms = percentile(sorted, 0.95)
	local p99Ms = percentile(sorted, 0.99)

	return {
		Name = name,
		Iterations = iterations,
		Warmup = warmup,
		Samples = samples,
		TotalMs = totalMs,
		-- DurationMs remains as the compatibility alias for the representative window.
		DurationMs = medianMs,
		AverageMs = medianMs / iterations,
		MeanMs = totalMs / samples,
		MedianMs = medianMs,
		P95Ms = p95Ms,
		P99Ms = p99Ms,
		MinMs = sorted[1],
		MaxMs = sorted[#sorted],
		MemoryDeltaKB = memoryDeltaKB,
		SampleDurationsMs = sampleDurations,
		Metrics = Profiler.GetMetrics(),
	}
end

function Benchmark.AssertWithin(result: Result, budgetMs: number)
	assert(type(budgetMs) == "number" and budgetMs >= 0, "Benchmark budget must be non-negative")
	if result.P95Ms > budgetMs then
		error(
			`Benchmark "{result.Name}" p95 was {result.P95Ms} ms, exceeding its {budgetMs} ms budget`,
			2
		)
	end
end

function Benchmark.Format(result: Result): string
	return string.format(
		"[VirtualUI Benchmark] %s | iterations=%d | warmup=%d | samples=%d | median=%.3f ms | p95=%.3f ms | p99=%.3f ms | min=%.3f ms | max=%.3f ms | average=%.6f ms | memory=%+.3f KB",
		result.Name,
		result.Iterations,
		result.Warmup,
		result.Samples,
		result.MedianMs,
		result.P95Ms,
		result.P99Ms,
		result.MinMs,
		result.MaxMs,
		result.AverageMs,
		result.MemoryDeltaKB
	)
end

return Benchmark
