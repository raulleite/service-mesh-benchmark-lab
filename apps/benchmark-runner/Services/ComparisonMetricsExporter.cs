using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Benchmark.Runner.Services;

public sealed class ComparisonMetricsExporter(IHostEnvironment hostEnvironment)
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly string[] KnownTopologies = ["two-hop", "three-hop"];

    private IReadOnlyList<string> RunsRoots =>
    [
        Environment.GetEnvironmentVariable("BENCHMARK_SUMMARIES_PATH") ?? "/var/lib/service-mesh/benchmark-summaries",
        Path.GetFullPath(Path.Combine(hostEnvironment.ContentRootPath, "..", "..", "results", "runs"))
    ];

    public async Task<string> BuildAsync(CancellationToken cancellationToken)
    {
        var summaries = await LoadLatestSummariesAsync(cancellationToken);
        var states = await LoadExecutionStatesAsync(cancellationToken);
        var metricKeys = summaries.Keys
            .Concat(states.Keys)
            .Distinct()
            .OrderBy(key => key.Mesh)
            .ThenBy(key => key.Topology)
            .ToArray();
        var builder = new StringBuilder();

        builder.AppendLine("# HELP benchmark_summary_rps Latest achieved RPS captured by the benchmark automation for each mesh and topology.");
        builder.AppendLine("# TYPE benchmark_summary_rps gauge");
        builder.AppendLine("# HELP benchmark_summary_p99_latency_ms Latest client-side p99 latency in milliseconds captured by the benchmark automation for each mesh and topology.");
        builder.AppendLine("# TYPE benchmark_summary_p99_latency_ms gauge");
        builder.AppendLine("# HELP benchmark_summary_sidecar_cpu_limit_percent Latest average sidecar CPU usage as percentage of configured CPU limit for each mesh and topology.");
        builder.AppendLine("# TYPE benchmark_summary_sidecar_cpu_limit_percent gauge");
        builder.AppendLine("# HELP benchmark_summary_active Explicit benchmark execution state for each mesh and topology. 1 means the topology is currently under benchmark; 0 means idle.");
        builder.AppendLine("# TYPE benchmark_summary_active gauge");

        foreach (var key in metricKeys)
        {
            var isActive = states.TryGetValue(key, out var state) && state.Active;
            var summary = summaries.GetValueOrDefault(key);

            AppendGauge(builder, "benchmark_summary_rps", isActive && summary is not null ? summary.Rps : 0, key.Mesh, key.Topology);
            AppendGauge(builder, "benchmark_summary_p99_latency_ms", isActive && summary is not null ? summary.P99LatencyMs : 0, key.Mesh, key.Topology);
            AppendGauge(builder, "benchmark_summary_sidecar_cpu_limit_percent", isActive && summary is not null ? summary.SidecarCpuLimitPercent : 0, key.Mesh, key.Topology);
            AppendGauge(builder, "benchmark_summary_active", isActive ? 1 : 0, key.Mesh, key.Topology);
        }

        return builder.ToString();
    }

    private async Task<IReadOnlyDictionary<MetricKey, BenchmarkSummaryMetric>> LoadLatestSummariesAsync(CancellationToken cancellationToken)
    {
        var existingRoots = RunsRoots
            .Where(Directory.Exists)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (existingRoots.Length == 0)
        {
            return new Dictionary<MetricKey, BenchmarkSummaryMetric>();
        }

        var summaries = new List<BenchmarkSummaryMetric>();
        foreach (var runsRoot in existingRoots)
        {
            foreach (var summaryFile in Directory.GetFiles(runsRoot, "summary-*.json", SearchOption.AllDirectories))
            {
                await using var stream = File.OpenRead(summaryFile);
                var summary = await JsonSerializer.DeserializeAsync<BenchmarkSummaryMetric>(stream, JsonOptions, cancellationToken);
                if (summary is not null && !string.IsNullOrWhiteSpace(summary.Mesh) && !string.IsNullOrWhiteSpace(summary.Topology))
                {
                    summaries.Add(summary);
                }
            }
        }

        return summaries
            .GroupBy(summary => new
            {
                Mesh = summary.Mesh.ToLowerInvariant(),
                Topology = summary.Topology.ToLowerInvariant()
            })
            .Select(group => group.OrderByDescending(item => item.GeneratedAt).First())
            .ToDictionary(summary => new MetricKey(summary.Mesh.ToLowerInvariant(), summary.Topology.ToLowerInvariant()));
    }

    private async Task<IReadOnlyDictionary<MetricKey, BenchmarkExecutionState>> LoadExecutionStatesAsync(CancellationToken cancellationToken)
    {
        var states = new Dictionary<MetricKey, BenchmarkExecutionState>();

        foreach (var runsRoot in RunsRoots.Where(Directory.Exists).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var stateRoot = Path.Combine(runsRoot, ".state");
            if (!Directory.Exists(stateRoot))
            {
                continue;
            }

            foreach (var stateFile in Directory.GetFiles(stateRoot, "*.json", SearchOption.TopDirectoryOnly))
            {
                await using var stream = File.OpenRead(stateFile);
                var state = await JsonSerializer.DeserializeAsync<BenchmarkExecutionState>(stream, JsonOptions, cancellationToken);
                if (state is null || string.IsNullOrWhiteSpace(state.Mesh) || string.IsNullOrWhiteSpace(state.Topology))
                {
                    continue;
                }

                var key = new MetricKey(state.Mesh.ToLowerInvariant(), state.Topology.ToLowerInvariant());
                if (!states.TryGetValue(key, out var existingState) || state.UpdatedAt >= existingState.UpdatedAt)
                {
                    states[key] = state;
                }
            }
        }

        return states;
    }

    private static void AppendGauge(StringBuilder builder, string metricName, double value, string mesh, string topology)
    {
        builder.Append(metricName)
            .Append("{environment=\"")
            .Append(EscapeLabel(mesh))
            .Append("\",topology=\"")
            .Append(EscapeLabel(topology))
            .Append("\"} ")
            .AppendLine(value.ToString("0.########", CultureInfo.InvariantCulture));
    }

    private static string EscapeLabel(string value) => value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);

    private readonly record struct MetricKey(string Mesh, string Topology);

    private sealed record BenchmarkSummaryMetric(
        string RunId,
        string Mesh,
        string Topology,
        string TargetEndpoint,
        DateTimeOffset GeneratedAt,
        double Rps,
        double P99LatencyMs,
        double SidecarCpuLimitPercent);

    private sealed record BenchmarkExecutionState(
        string RunId,
        string Mesh,
        string Topology,
        string TargetEndpoint,
        DateTimeOffset UpdatedAt,
        bool Active);
}