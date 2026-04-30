using System.Diagnostics;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.UseRouting();
app.UseHttpMetrics(options =>
{
	options.ReduceStatusCodeCardinality();
	options.AddCustomLabel("handler", context => context.Request.Path.Value switch
	{
		"/work" => "work",
		"/healthz" => "healthz",
		"/metrics" => "metrics",
		_ => "other"
	});
	options.AddCustomLabel("topology", context => NormalizeTopology(context.Request.Query["topology"]));
});

app.MapGet("/healthz", () => Results.Ok(new HealthResponse("service-leaf", "ready")));

app.MapGet("/work", (string? topology, int? depth) =>
{
	var stopwatch = Stopwatch.StartNew();
	var selectedTopology = string.Equals(topology, "three-hop", StringComparison.OrdinalIgnoreCase)
		? "three-hop"
		: "two-hop";
	stopwatch.Stop();

	return Results.Ok(new HopResponse("service-leaf", selectedTopology, depth.GetValueOrDefault(2), stopwatch.Elapsed.TotalMilliseconds));
});

app.MapMetrics();
app.MapGet("/", () => Results.Redirect("/healthz"));

app.Run();

static string NormalizeTopology(string? topology) => string.Equals(topology, "three-hop", StringComparison.OrdinalIgnoreCase)
	? "three-hop"
	: string.Equals(topology, "two-hop", StringComparison.OrdinalIgnoreCase)
		? "two-hop"
		: "none";

public sealed record HealthResponse(string Service, string Status);

public sealed record HopResponse(
	string Service,
	string Topology,
	int Depth,
	double ElapsedMs,
	HopResponse? Downstream = null);
