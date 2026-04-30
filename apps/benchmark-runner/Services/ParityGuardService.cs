using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class ParityGuardService
{
    public void Validate(BenchmarkScenario scenario, BenchmarkEnvironment environment, ResourceProfile resourceProfile)
    {
        if (scenario.ReplicaCount != 1)
        {
            throw new InvalidOperationException("Benchmark scenarios must use exactly one replica.");
        }

        if (string.IsNullOrWhiteSpace(environment.Mesh) || string.IsNullOrWhiteSpace(resourceProfile.ResourceProfileId))
        {
            throw new InvalidOperationException("Benchmark environment and resource profile must be fully declared.");
        }
    }
}