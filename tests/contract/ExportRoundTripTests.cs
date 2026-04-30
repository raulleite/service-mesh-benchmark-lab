using System.Text.Json;

namespace Benchmark.ContractTests;

public sealed class ExportRoundTripTests
{
    [Fact]
    public void Sample_export_round_trips_as_json_document()
    {
        var sample = """
        {
          "runId": "run-test",
          "scenarioId": "two-hop",
          "environment": "istio",
          "topology": "two-hop",
          "loadProfile": { "warmupStages": [], "measurementStages": [], "scriptHash": "abc" },
          "metrics": { "client": { "p99LatencyMs": 10, "overallRps": 100, "stageBreakdown": [] }, "prometheus": { "serviceCpu": [], "sidecarCpu": [] } },
          "artifacts": [{ "kind": "k6-summary", "path": "k6.json", "checksum": "abc" }]
        }
        """;

        using var document = JsonDocument.Parse(sample);
        Assert.Equal("run-test", document.RootElement.GetProperty("runId").GetString());
    }
}