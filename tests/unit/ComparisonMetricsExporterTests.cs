using Benchmark.Runner.Services;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;

namespace Benchmark.UnitTests;

public sealed class ComparisonMetricsExporterTests
{
    [Fact]
    public async Task BuildAsync_EmitsSummaryValues_WhenTopologyIsExplicitlyActive()
    {
        using var workspace = new TemporaryBenchmarkWorkspace();
        workspace.WriteSummary(
            "run-001",
            "istio",
            "two-hop",
            DateTimeOffset.Parse("2026-04-29T12:00:00Z"),
            1250.5,
            42.7,
            17.3);
        workspace.WriteState(
            "run-001",
            "istio",
            "two-hop",
            DateTimeOffset.Parse("2026-04-29T12:00:05Z"),
            active: true);

        var exporter = new ComparisonMetricsExporter(workspace.HostEnvironment);

        var metrics = await exporter.BuildAsync(CancellationToken.None);

        Assert.Contains("benchmark_summary_rps{environment=\"istio\",topology=\"two-hop\"} 1250.5", metrics, StringComparison.Ordinal);
        Assert.Contains("benchmark_summary_p99_latency_ms{environment=\"istio\",topology=\"two-hop\"} 42.7", metrics, StringComparison.Ordinal);
        Assert.Contains("benchmark_summary_sidecar_cpu_limit_percent{environment=\"istio\",topology=\"two-hop\"} 17.3", metrics, StringComparison.Ordinal);
        Assert.Contains("benchmark_summary_active{environment=\"istio\",topology=\"two-hop\"} 1", metrics, StringComparison.Ordinal);
    }

    [Fact]
    public async Task BuildAsync_ZeroesSummaryValues_WhenTopologyIsExplicitlyIdle()
    {
        using var workspace = new TemporaryBenchmarkWorkspace();
        workspace.WriteSummary(
            "run-002",
            "linkerd",
            "three-hop",
            DateTimeOffset.Parse("2026-04-29T12:10:00Z"),
            980.2,
            63.1,
            11.4);
        workspace.WriteState(
            "run-002",
            "linkerd",
            "three-hop",
            DateTimeOffset.Parse("2026-04-29T12:10:05Z"),
            active: false);

        var exporter = new ComparisonMetricsExporter(workspace.HostEnvironment);

        var metrics = await exporter.BuildAsync(CancellationToken.None);

        Assert.Contains("benchmark_summary_rps{environment=\"linkerd\",topology=\"three-hop\"} 0", metrics, StringComparison.Ordinal);
        Assert.Contains("benchmark_summary_p99_latency_ms{environment=\"linkerd\",topology=\"three-hop\"} 0", metrics, StringComparison.Ordinal);
        Assert.Contains("benchmark_summary_sidecar_cpu_limit_percent{environment=\"linkerd\",topology=\"three-hop\"} 0", metrics, StringComparison.Ordinal);
        Assert.Contains("benchmark_summary_active{environment=\"linkerd\",topology=\"three-hop\"} 0", metrics, StringComparison.Ordinal);
    }

    private sealed class TemporaryBenchmarkWorkspace : IDisposable
    {
        private readonly string tempRoot = Path.Combine(Path.GetTempPath(), $"benchmark-exporter-tests-{Guid.NewGuid():N}");

        public TemporaryBenchmarkWorkspace()
        {
            Directory.CreateDirectory(SharedSummariesPath);
            Directory.CreateDirectory(Path.Combine(SharedSummariesPath, ".state"));
            Directory.CreateDirectory(ContentRootPath);
            Environment.SetEnvironmentVariable("BENCHMARK_SUMMARIES_PATH", SharedSummariesPath);

            HostEnvironment = new TestHostEnvironment(ContentRootPath);
        }

        public string ContentRootPath => Path.Combine(tempRoot, "apps", "benchmark-runner");

        public string SharedSummariesPath => Path.Combine(tempRoot, "shared-summaries");

        public TestHostEnvironment HostEnvironment { get; }

        public void WriteSummary(string runId, string mesh, string topology, DateTimeOffset generatedAt, double rps, double p99LatencyMs, double sidecarCpuLimitPercent)
        {
            var runDirectory = Path.Combine(SharedSummariesPath, runId);
            Directory.CreateDirectory(runDirectory);
            File.WriteAllText(
                Path.Combine(runDirectory, $"summary-{topology}.json"),
                $$"""
                {
                  "runId": "{{runId}}",
                  "mesh": "{{mesh}}",
                  "topology": "{{topology}}",
                  "targetEndpoint": "http://127.0.0.1/test",
                  "generatedAt": "{{generatedAt:O}}",
                  "rps": {{rps}},
                  "p99LatencyMs": {{p99LatencyMs}},
                  "sidecarCpuLimitPercent": {{sidecarCpuLimitPercent}}
                }
                """);
        }

        public void WriteState(string runId, string mesh, string topology, DateTimeOffset updatedAt, bool active)
        {
            File.WriteAllText(
                Path.Combine(SharedSummariesPath, ".state", $"{mesh}-{topology}.json"),
                $$"""
                {
                  "runId": "{{runId}}",
                  "mesh": "{{mesh}}",
                  "topology": "{{topology}}",
                  "targetEndpoint": "http://127.0.0.1/test",
                  "updatedAt": "{{updatedAt:O}}",
                  "active": {{active.ToString().ToLowerInvariant()}}
                }
                """);
        }

        public void Dispose()
        {
            Environment.SetEnvironmentVariable("BENCHMARK_SUMMARIES_PATH", null);

            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    private sealed class TestHostEnvironment(string contentRootPath) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "UnitTests";

        public string ApplicationName { get; set; } = "Benchmark.Runner.Tests";

        public string ContentRootPath { get; set; } = contentRootPath;

        public IFileProvider ContentRootFileProvider { get; set; } = new PhysicalFileProvider(contentRootPath);
    }
}