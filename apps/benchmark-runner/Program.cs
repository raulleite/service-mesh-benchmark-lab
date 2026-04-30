using System.Security.Cryptography;
using System.Text;
using Benchmark.Runner.Models;
using Benchmark.Runner.Services;
using Microsoft.AspNetCore.Http.HttpResults;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<ScenarioCatalog>();
builder.Services.AddSingleton<ResultKeyFactory>();
builder.Services.AddSingleton<EnvironmentResetService>();
builder.Services.AddSingleton<RunCoordinator>();
builder.Services.AddSingleton<K6Runner>();
builder.Services.AddSingleton<RunPersistenceService>();
builder.Services.AddSingleton<MetricsCollectionService>();
builder.Services.AddSingleton<ParityGuardService>();
builder.Services.AddSingleton<ComparisonService>();
builder.Services.AddSingleton<ExportSerializer>();
builder.Services.AddSingleton<ArtifactStorageService>();
builder.Services.AddSingleton<ArtifactManifestService>();
builder.Services.AddSingleton<ResultExportService>();
builder.Services.AddSingleton<ComparisonMetricsExporter>();

var app = builder.Build();

app.MapGet("/healthz", () => Results.Ok(new { service = "benchmark-runner", status = "ready" }));

app.MapGet("/api/v1/scenarios", (ScenarioCatalog catalog) => Results.Ok(new { items = catalog.List() }));

app.MapPost("/api/v1/runs", async (
	CreateRunRequest request,
	ScenarioCatalog catalog,
	ResultKeyFactory keyFactory,
	EnvironmentResetService resetService,
	K6Runner k6Runner,
	MetricsCollectionService metricsService,
	RunPersistenceService persistenceService,
	CancellationToken cancellationToken) =>
{
	var scenario = catalog.Find(request.ScenarioId);
	if (scenario is null || !scenario.Enabled)
	{
		return Results.BadRequest(new { error = $"Scenario {request.ScenarioId} is not available." });
	}

	if (request.RepetitionIndex < 1)
	{
		return Results.BadRequest(new { error = "repetitionIndex must be greater than zero." });
	}

	var runId = $"run-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}-{Guid.NewGuid():N}"[..36];
	var resultKey = keyFactory.Create(request.Environment, request.Environment, scenario.ScenarioId, "all-stages", runId);
	var resetEvidence = await resetService.ResetAsync(runId, cancellationToken);
	var run = new BenchmarkRun(
		runId,
		scenario.ScenarioId,
		request.Environment,
		scenario.Topology,
		"measuring",
		request.RepetitionIndex,
		DateTimeOffset.UtcNow,
		null,
		resultKey,
		resetEvidence,
		k6Runner.ComputeLoadProfileHash(),
		ComputeManifestHash(),
		null,
		null);

	var metrics = await k6Runner.RunAsync(scenario, run, cancellationToken);
	var completedRun = run with
	{
		Status = "completed",
		FinishedAt = DateTimeOffset.UtcNow,
		Summary = metricsService.CreateSummary(metrics)
	};

	await persistenceService.SaveRunAsync(completedRun, cancellationToken);
	return Results.Accepted($"/api/v1/runs/{completedRun.RunId}", completedRun);
});

app.MapGet("/api/v1/runs/{runId}", async (string runId, RunPersistenceService persistenceService, CancellationToken cancellationToken) =>
{
	var run = await persistenceService.GetRunAsync(runId, cancellationToken);
	return run is null ? Results.NotFound() : Results.Ok(run);
});

app.MapGet("/api/v1/comparisons", async (ComparisonService comparisonService, CancellationToken cancellationToken) =>
{
	var comparisons = await comparisonService.CompareAsync(cancellationToken);
	return Results.Ok(new { items = comparisons });
});

app.MapGet("/metrics", async Task<ContentHttpResult> (ComparisonMetricsExporter exporter, CancellationToken cancellationToken) =>
{
	var metrics = await exporter.BuildAsync(cancellationToken);
	return TypedResults.Text(metrics, "text/plain; version=0.0.4; charset=utf-8");
});

app.MapPost("/api/v1/runs/{runId}/export", async (
	string runId,
	ExportRequest request,
	ResultExportService exportService,
	CancellationToken cancellationToken) =>
{
	try
	{
		var response = await exportService.ExportAsync(runId, request.Format, cancellationToken);
		return Results.Accepted($"/api/v1/runs/{runId}/export", response);
	}
	catch (KeyNotFoundException)
	{
		return Results.NotFound();
	}
	catch (InvalidOperationException ex)
	{
		return Results.Conflict(new { error = ex.Message });
	}
});

app.MapGet("/", () => Results.Redirect("/healthz"));

app.Run();

static string ComputeManifestHash()
{
	var path = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "infra", "official-config-manifest.yaml");
	if (!File.Exists(path))
	{
		return "missing-manifest";
	}

	using var sha = SHA256.Create();
	return Convert.ToHexString(sha.ComputeHash(File.ReadAllBytes(path))).ToLowerInvariant();
}

public partial class Program;
