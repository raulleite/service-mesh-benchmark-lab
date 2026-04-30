namespace Benchmark.ContractTests;

public sealed class BenchmarkExportContractTests
{
    [Fact]
    public void OpenApi_contract_exposes_required_control_endpoints()
    {
        var contract = File.ReadAllText(Path.Combine(Repository.Root(), "specs", "001-mesh-benchmark-environment", "contracts", "benchmark-control.openapi.yaml"));

        Assert.Contains("/api/v1/scenarios", contract);
        Assert.Contains("/api/v1/runs", contract);
        Assert.Contains("/api/v1/runs/{runId}", contract);
        Assert.Contains("/api/v1/runs/{runId}/export", contract);
    }
}