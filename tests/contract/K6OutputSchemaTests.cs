namespace Benchmark.ContractTests;

public sealed class K6OutputSchemaTests
{
    [Fact]
    public void K6_script_exports_summary_and_uses_official_stages()
    {
        var root = Repository.Root();
        var script = File.ReadAllText(Path.Combine(root, "load", "k6", "mesh-benchmark.js"));
        var scenarios = File.ReadAllText(Path.Combine(root, "load", "k6", "scenarios.js"));

        Assert.Contains("K6_SUMMARY_EXPORT", script);
        Assert.Contains("TARGET_ENDPOINT", script);
        foreach (var rps in new[] { "10", "100", "250", "500", "750", "1000" })
        {
            Assert.Contains($"target: {rps}", scenarios);
        }
    }
}