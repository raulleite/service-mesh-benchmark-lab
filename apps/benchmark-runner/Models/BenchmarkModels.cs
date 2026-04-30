namespace Benchmark.Runner.Models;

public sealed record LoadStage(string Phase, int TargetRps, int DurationSeconds);

public sealed record BenchmarkScenario(
    string ScenarioId,
    string Name,
    string Topology,
    IReadOnlyList<string> ServiceChain,
    IReadOnlyList<LoadStage> WarmupProfile,
    IReadOnlyList<LoadStage> MeasurementProfile,
    int ReplicaCount,
    string ResourceProfileId,
    bool Enabled);

public sealed record BenchmarkEnvironment(
    string EnvironmentId,
    string Mesh,
    string ClusterName,
    string KubernetesVersion,
    string ResourceProfileId,
    string ObservabilityProfileId,
    string Status);

public sealed record ResourceProfile(
    string ResourceProfileId,
    string AppCpuRequest,
    string AppCpuLimit,
    string AppMemoryRequest,
    string AppMemoryLimit,
    string SidecarCpuRequest,
    string SidecarCpuLimit,
    string SidecarMemoryRequest,
    string SidecarMemoryLimit);

public sealed record CreateRunRequest(string ScenarioId, string Environment, int RepetitionIndex, string? Notes);

public sealed record BenchmarkRun(
    string RunId,
    string ScenarioId,
    string Environment,
    string Topology,
    string Status,
    int RepetitionIndex,
    DateTimeOffset StartedAt,
    DateTimeOffset? FinishedAt,
    string ResultKey,
    ResetEvidence ResetEvidence,
    string LoadProfileHash,
    string ManifestBundleHash,
    string? InvalidReason,
    RunSummary? Summary);

public sealed record ResetEvidence(DateTimeOffset CapturedAt, bool ResetExecuted, string EvidencePath);

public sealed record RunSummary(double ClientP99Ms, double TotalRps, IReadOnlyList<ServiceSummary> Services);

public sealed record ServiceSummary(string Service, double CpuMillicores, double SidecarCpuMillicores);

public sealed record StageMetric(int TargetRps, double AchievedRps, double P99LatencyMs);

public sealed record RunMetricSet(
    string RunId,
    string Source,
    string ResultKey,
    IReadOnlyList<StageMetric> StageResults,
    double OverallRps,
    double P99LatencyMs,
    IReadOnlyList<ServiceSummary> CpuUsage,
    DateTimeOffset CollectedAt);

public sealed record ResultExport(
    string ExportId,
    string RunId,
    string Format,
    string ResultKey,
    IReadOnlyList<string> ArtifactPaths,
    DateTimeOffset CreatedAt,
    string Checksum);

public sealed record ExportRequest(string Format);

public sealed record ExportResponse(string ExportId, string Status, string? Path);

public sealed record ComparisonResult(string ScenarioId, string Environment, string Topology, double P99LatencyMs, double TotalRps);