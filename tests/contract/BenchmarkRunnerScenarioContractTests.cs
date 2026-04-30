using Benchmark.Runner.Services;

namespace Benchmark.ContractTests;

public sealed class BenchmarkRunnerScenarioContractTests
{
    [Fact]
    public void Catalog_contains_official_scenarios_and_load_profile()
    {
        var catalog = new ScenarioCatalog();
        var scenarios = catalog.List();

        Assert.Contains(scenarios, scenario => scenario.ScenarioId == "two-hop" && scenario.MeasurementProfile.Any(stage => stage.TargetRps == 1000));
        Assert.Contains(scenarios, scenario => scenario.ScenarioId == "three-hop" && scenario.ServiceChain.Count == 3);
        Assert.All(scenarios, scenario => Assert.Equal(2, scenario.WarmupProfile.Count));
    }
}