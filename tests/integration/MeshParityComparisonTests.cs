namespace Benchmark.IntegrationTests;

public sealed class MeshParityComparisonTests
{
    [Fact]
    public void Mesh_overlays_share_the_same_base()
    {
        var root = Repository.Root();
        var istio = File.ReadAllText(Path.Combine(root, "infra", "clusters", "istio", "kustomization.yaml"));
        var linkerd = File.ReadAllText(Path.Combine(root, "infra", "clusters", "linkerd", "kustomization.yaml"));

        Assert.Contains("../../base", istio);
        Assert.Contains("../../base", linkerd);
    }
}