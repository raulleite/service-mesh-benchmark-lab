using System.Text.Json;
using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class RunPersistenceService(IHostEnvironment hostEnvironment)
{
    private string RunsRoot => Path.GetFullPath(Path.Combine(hostEnvironment.ContentRootPath, "..", "..", "results", "runs"));

    public async Task SaveRunAsync(BenchmarkRun run, CancellationToken cancellationToken)
    {
        var directory = Path.Combine(RunsRoot, run.RunId);
        Directory.CreateDirectory(directory);
        await File.WriteAllTextAsync(Path.Combine(directory, "run.json"), JsonSerializer.Serialize(run, JsonOptions.Default), cancellationToken);
    }

    public async Task<BenchmarkRun?> GetRunAsync(string runId, CancellationToken cancellationToken)
    {
        var path = Path.Combine(RunsRoot, runId, "run.json");
        if (!File.Exists(path))
        {
            return null;
        }

        await using var stream = File.OpenRead(path);
        return await JsonSerializer.DeserializeAsync<BenchmarkRun>(stream, JsonOptions.Default, cancellationToken);
    }

    public async Task<IReadOnlyList<BenchmarkRun>> ListRunsAsync(CancellationToken cancellationToken)
    {
        if (!Directory.Exists(RunsRoot))
        {
            return [];
        }

        var runs = new List<BenchmarkRun>();
        foreach (var runFile in Directory.GetFiles(RunsRoot, "run.json", SearchOption.AllDirectories))
        {
            await using var stream = File.OpenRead(runFile);
            var run = await JsonSerializer.DeserializeAsync<BenchmarkRun>(stream, JsonOptions.Default, cancellationToken);
            if (run is not null)
            {
                runs.Add(run);
            }
        }

        return runs.OrderBy(run => run.StartedAt).ToArray();
    }
}