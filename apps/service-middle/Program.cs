using System.Diagnostics;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient("leaf", client =>
{
	var leafUrl = Environment.GetEnvironmentVariable("SERVICE_LEAF_URL")
		?? builder.Configuration["Downstream:ServiceLeafUrl"]
		?? "http://service-leaf:8080";
	client.BaseAddress = new Uri(leafUrl);
	client.Timeout = TimeSpan.FromSeconds(10);
});

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

app.MapGet("/healthz", () => Results.Ok(new HealthResponse("service-middle", "ready")));

app.MapGet("/work", async (string? topology, int? depth, IHttpClientFactory httpClientFactory, CancellationToken cancellationToken) =>
{
	var selectedTopology = string.Equals(topology, "three-hop", StringComparison.OrdinalIgnoreCase)
		? "three-hop"
		: "two-hop";
	var currentDepth = depth.GetValueOrDefault(1);
	var stopwatch = Stopwatch.StartNew();
	HopResponse? downstream = null;

	if (selectedTopology == "three-hop")
	{
		var client = httpClientFactory.CreateClient("leaf");
		downstream = await client.GetFromJsonAsync<HopResponse>($"/work?topology={selectedTopology}&depth={currentDepth + 1}", cancellationToken);
	}

	stopwatch.Stop();
	return Results.Ok(new HopResponse("service-middle", selectedTopology, currentDepth, stopwatch.Elapsed.TotalMilliseconds, downstream));
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
