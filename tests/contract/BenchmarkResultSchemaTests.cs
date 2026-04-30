namespace Benchmark.ContractTests;

public sealed class BenchmarkResultSchemaTests
{
    [Fact]
    public void Result_schema_requires_metrics_and_artifacts()
    {
        var schema = File.ReadAllText(Path.Combine(Repository.Root(), "specs", "001-mesh-benchmark-environment", "contracts", "benchmark-result.schema.json"));

        Assert.Contains("p99LatencyMs", schema);
        Assert.Contains("overallRps", schema);
        Assert.Contains("sidecarCpu", schema);
        Assert.Contains("artifacts", schema);
    }
}