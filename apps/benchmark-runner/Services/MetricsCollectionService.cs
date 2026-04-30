using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class MetricsCollectionService
{
    public RunSummary CreateSummary(RunMetricSet metricSet) =>
        new(metricSet.P99LatencyMs, metricSet.OverallRps, metricSet.CpuUsage);

    public object Reconcile(RunMetricSet clientMetricSet, RunMetricSet prometheusMetricSet) => new
    {
        clientMetricSet.RunId,
        clientMetricSet.ResultKey,
        latencySourceOfTruth = "k6",
        rpsDelta = Math.Abs(clientMetricSet.OverallRps - prometheusMetricSet.OverallRps),
        p99DeltaMs = Math.Abs(clientMetricSet.P99LatencyMs - prometheusMetricSet.P99LatencyMs)
    };
}