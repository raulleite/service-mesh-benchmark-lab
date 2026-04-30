using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class RunCoordinator(
    ScenarioCatalog scenarioCatalog,
    ResultKeyFactory resultKeyFactory,
    EnvironmentResetService resetService,
    K6Runner k6Runner,
    MetricsCollectionService metricsCollectionService,
    RunPersistenceService persistenceService)
{
    public async Task<BenchmarkRun> ExecuteAsync(CreateRunRequest request, CancellationToken cancellationToken)
    {
        var scenario = scenarioCatalog.Find(request.ScenarioId)
            ?? throw new ArgumentException($"Scenario {request.ScenarioId} is not available.", nameof(request));
        var runId = $"run-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}-{Guid.NewGuid():N}"[..36];
        var resetEvidence = await resetService.ResetAsync(runId, cancellationToken);
        var run = new BenchmarkRun(
            runId,
            scenario.ScenarioId,
            request.Environment,
            scenario.Topology,
            "measuring",
            request.RepetitionIndex,
            DateTimeOffset.UtcNow,
            null,
            resultKeyFactory.Create(request.Environment, request.Environment, scenario.ScenarioId, "all-stages", runId),
            resetEvidence,
            k6Runner.ComputeLoadProfileHash(),
            "official-config-manifest",
            null,
            null);

        var metrics = await k6Runner.RunAsync(scenario, run, cancellationToken);
        var completedRun = run with
        {
            Status = "completed",
            FinishedAt = DateTimeOffset.UtcNow,
            Summary = metricsCollectionService.CreateSummary(metrics)
        };
        await persistenceService.SaveRunAsync(completedRun, cancellationToken);
        return completedRun;
    }
}