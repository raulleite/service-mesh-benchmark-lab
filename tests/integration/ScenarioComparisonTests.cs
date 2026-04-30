namespace Benchmark.IntegrationTests;

public sealed class ScenarioComparisonTests
{
    [Fact]
    public void Comparison_dashboard_exists_for_mesh_and_topology_analysis()
    {
        var dashboard = File.ReadAllText(Path.Combine(Repository.Root(), "infra", "observability", "grafana", "dashboards", "comparison-overview.json"));

        Assert.Contains("Istio vs Linkerd", dashboard);
        Assert.Contains("two-hop vs three-hop", dashboard);
    }
}