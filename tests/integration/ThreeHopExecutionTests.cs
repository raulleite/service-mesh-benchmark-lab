namespace Benchmark.IntegrationTests;

public sealed class ThreeHopExecutionTests
{
    [Fact]
    public void Three_hop_topology_manifest_declares_expected_chain()
    {
        var manifest = File.ReadAllText(Path.Combine(Repository.Root(), "infra", "base", "apps", "three-hop-routing.yaml"));

        Assert.Contains("three-hop", manifest);
        Assert.Contains("service-entry->service-middle->service-leaf", manifest);
    }
}