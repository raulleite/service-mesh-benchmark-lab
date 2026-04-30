namespace Benchmark.IntegrationTests;

public sealed class TwoHopExecutionTests
{
    [Fact]
    public void Two_hop_topology_manifest_declares_expected_chain()
    {
        var manifest = File.ReadAllText(Path.Combine(Repository.Root(), "infra", "base", "apps", "two-hop-routing.yaml"));

        Assert.Contains("two-hop", manifest);
        Assert.Contains("service-entry->service-middle", manifest);
    }
}