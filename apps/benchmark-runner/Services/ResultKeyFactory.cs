namespace Benchmark.Runner.Services;

public sealed class ResultKeyFactory
{
    public string Create(string mesh, string environment, string scenario, string stage, string runId) =>
        string.Join('/', Normalize(mesh), Normalize(environment), Normalize(scenario), Normalize(stage), Normalize(runId));

    private static string Normalize(string value) =>
        value.Trim().ToLowerInvariant().Replace(' ', '-');
}