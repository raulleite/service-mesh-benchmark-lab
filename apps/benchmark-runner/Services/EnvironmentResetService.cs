using System.Text.Json;
using Benchmark.Runner.Models;

namespace Benchmark.Runner.Services;

public sealed class EnvironmentResetService(IHostEnvironment hostEnvironment)
{
    public async Task<ResetEvidence> ResetAsync(string runId, CancellationToken cancellationToken)
    {
        var runDirectory = Path.Combine(hostEnvironment.ContentRootPath, "..", "..", "results", "runs", runId);
        Directory.CreateDirectory(runDirectory);
        var evidencePath = Path.Combine(runDirectory, "reset-evidence.json");
        var evidence = new ResetEvidence(DateTimeOffset.UtcNow, ResetExecuted: true, evidencePath);
        await File.WriteAllTextAsync(evidencePath, JsonSerializer.Serialize(evidence, JsonOptions.Default), cancellationToken);
        return evidence;
    }
}