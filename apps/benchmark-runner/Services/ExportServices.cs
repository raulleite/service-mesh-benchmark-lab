using System.Security.Cryptography;
using System.Text.Json;
using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class ExportSerializer
{
    public string Serialize(BenchmarkRun run, string format) =>
        JsonSerializer.Serialize(new
        {
            run.RunId,
            run.ScenarioId,
            run.Environment,
            run.Topology,
            run.RepetitionIndex,
            run.ResultKey,
            metrics = run.Summary,
            run.ResetEvidence,
            run.LoadProfileHash,
            run.ManifestBundleHash,
            format
        }, JsonOptions.Default);
}

public sealed class ArtifactStorageService(IHostEnvironment hostEnvironment)
{
    public async Task<string> WriteAsync(string runId, string fileName, string content, CancellationToken cancellationToken)
    {
        var directory = Path.GetFullPath(Path.Combine(hostEnvironment.ContentRootPath, "..", "..", "results", "runs", runId, "exports"));
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, fileName);
        await File.WriteAllTextAsync(path, content, cancellationToken);
        return path;
    }

    public static string ComputeChecksum(string path)
    {
        using var sha = SHA256.Create();
        var hash = sha.ComputeHash(File.ReadAllBytes(path));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}

public sealed class ArtifactManifestService(ArtifactStorageService storageService)
{
    public async Task<ResultExport> CreateManifestAsync(string runId, string format, string resultKey, IReadOnlyList<string> paths, CancellationToken cancellationToken)
    {
        var exportId = $"export-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}";
        var checksum = paths.Count == 0 ? "" : ArtifactStorageService.ComputeChecksum(paths[0]);
        var export = new ResultExport(exportId, runId, format, resultKey, paths, DateTimeOffset.UtcNow, checksum);
        var manifest = JsonSerializer.Serialize(export, JsonOptions.Default);
        await storageService.WriteAsync(runId, "artifact-manifest.json", manifest, cancellationToken);
        return export;
    }
}

public sealed class ResultExportService(
    RunPersistenceService persistenceService,
    ExportSerializer serializer,
    ArtifactStorageService storageService,
    ArtifactManifestService manifestService)
{
    public async Task<ExportResponse> ExportAsync(string runId, string format, CancellationToken cancellationToken)
    {
        var run = await persistenceService.GetRunAsync(runId, cancellationToken)
            ?? throw new KeyNotFoundException($"Run {runId} was not found.");

        if (run.Status != "completed")
        {
            throw new InvalidOperationException($"Run {runId} is not ready for export.");
        }

        var content = serializer.Serialize(run, format);
        var path = await storageService.WriteAsync(runId, $"result-export.{(format == "csv-bundle" ? "json" : "json")}", content, cancellationToken);
        var export = await manifestService.CreateManifestAsync(runId, format, run.ResultKey, [path], cancellationToken);
        return new ExportResponse(export.ExportId, "completed", path);
    }
}