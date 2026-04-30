using System.Diagnostics;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient("downstream", client =>
{
	var downstreamUrl = Environment.GetEnvironmentVariable("SERVICE_MIDDLE_URL")
		?? builder.Configuration["Downstream:ServiceMiddleUrl"]
		?? "http://service-middle:8080";
	client.BaseAddress = new Uri(downstreamUrl);
	client.Timeout = TimeSpan.FromSeconds(10);
});

var app = builder.Build();

app.UseRouting();
app.UseHttpMetrics(options =>
{
	options.ReduceStatusCodeCardinality();
	options.AddCustomLabel("handler", context => context.Request.Path.Value switch
	{
		"/invoke" => "invoke",
		"/healthz" => "healthz",
		"/metrics" => "metrics",
		_ => "other"
	});
	options.AddCustomLabel("topology", context => NormalizeTopology(context.Request.Query["topology"]));
	options.AddCustomLabel("phase", context => NormalizePhase(context.Request.Query["phase"]));
});

app.MapGet("/healthz", () => Results.Ok(new HealthResponse("service-entry", "ready")));

app.MapGet("/invoke", async (string? topology, IHttpClientFactory httpClientFactory, CancellationToken cancellationToken) =>
{
	var selectedTopology = string.Equals(topology, "three-hop", StringComparison.OrdinalIgnoreCase)
		? "three-hop"
		: "two-hop";

	var stopwatch = Stopwatch.StartNew();
	var client = httpClientFactory.CreateClient("downstream");
	var downstream = await client.GetFromJsonAsync<HopResponse>($"/work?topology={selectedTopology}&depth=1", cancellationToken);
	stopwatch.Stop();

	return Results.Ok(new HopResponse(
		Service: "service-entry",
		Topology: selectedTopology,
		Depth: 0,
		ElapsedMs: stopwatch.Elapsed.TotalMilliseconds,
		Downstream: downstream));
});

app.MapMetrics();
app.MapGet("/", () => Results.Redirect("/healthz"));

app.Run();

static string NormalizeTopology(string? topology) => string.Equals(topology, "three-hop", StringComparison.OrdinalIgnoreCase)
	? "three-hop"
	: string.Equals(topology, "two-hop", StringComparison.OrdinalIgnoreCase)
		? "two-hop"
		: "none";

static string NormalizePhase(string? phase) => string.Equals(phase, "measurement", StringComparison.OrdinalIgnoreCase)
	? "measurement"
	: string.Equals(phase, "warmup", StringComparison.OrdinalIgnoreCase)
		? "warmup"
		: string.Equals(phase, "ignored", StringComparison.OrdinalIgnoreCase)
			? "ignored"
			: "none";

public sealed record HealthResponse(string Service, string Status);

public sealed record HopResponse(
	string Service,
	string Topology,
	int Depth,
	double ElapsedMs,
	HopResponse? Downstream = null);
