using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class ScenarioCatalog
{
    private static readonly LoadStage[] WarmupStages =
    [
        new("warmup", 10, 30),
        new("warmup", 50, 30)
    ];

    private static readonly LoadStage[] MeasurementStages =
    [
        new("measurement", 10, 60),
        new("measurement", 100, 60),
        new("measurement", 250, 60),
        new("measurement", 500, 60),
        new("measurement", 750, 60),
        new("measurement", 1000, 60)
    ];

    private readonly BenchmarkScenario[] scenarios =
    [
        new(
            "two-hop",
            "Two-hop HTTP chain",
            "two-hop",
            ["service-entry", "service-middle"],
            WarmupStages,
            MeasurementStages,
            1,
            "default-fixed",
            true),
        new(
            "three-hop",
            "Three-hop HTTP chain",
            "three-hop",
            ["service-entry", "service-middle", "service-leaf"],
            WarmupStages,
            MeasurementStages,
            1,
            "default-fixed",
            true)
    ];

    public IReadOnlyList<BenchmarkScenario> List() => scenarios;

    public BenchmarkScenario? Find(string scenarioId) =>
        scenarios.FirstOrDefault(s => string.Equals(s.ScenarioId, scenarioId, StringComparison.OrdinalIgnoreCase));
}