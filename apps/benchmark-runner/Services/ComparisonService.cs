using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class ComparisonService(RunPersistenceService persistenceService)
{
    public async Task<IReadOnlyList<ComparisonResult>> CompareAsync(CancellationToken cancellationToken)
    {
        var runs = await persistenceService.ListRunsAsync(cancellationToken);
        return runs
            .Where(run => run.Status == "completed" && run.Summary is not null)
            .GroupBy(run => new { run.ScenarioId, run.Environment, run.Topology })
            .Select(group => new ComparisonResult(
                group.Key.ScenarioId,
                group.Key.Environment,
                group.Key.Topology,
                group.Average(run => run.Summary!.ClientP99Ms),
                group.Average(run => run.Summary!.TotalRps)))
            .OrderBy(result => result.Environment)
            .ThenBy(result => result.Topology)
            .ToArray();
    }
}