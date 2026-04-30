using Benchmark.Runner.Services;

namespace Benchmark.UnitTests;

public sealed class ResultKeyFactoryTests
{
    [Fact]
    public void Create_returns_canonical_composite_key()
    {
        var factory = new ResultKeyFactory();

        var key = factory.Create("Istio", "Cluster A", "two-hop", "500-rps", "run-001");

        Assert.Equal("istio/cluster-a/two-hop/500-rps/run-001", key);
    }
}