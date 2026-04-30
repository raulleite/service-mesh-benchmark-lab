namespace Benchmark.IntegrationTests;

public sealed class ResultExportTests
{
    [Fact]
    public void Result_directory_contains_official_export_locations()
    {
        var root = Repository.Root();

        Assert.True(Directory.Exists(Path.Combine(root, "results", "runs", "official")));
        Assert.True(File.Exists(Path.Combine(root, "results", "runs", "README.md")));
    }
}