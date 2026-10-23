var builder = DistributedApplication.CreateBuilder(args);

var sql = builder.AddSqlServer("sql")
    .WithLifetime(ContainerLifetime.Persistent)
    .WithDataVolume();

var database = sql.AddDatabase("ProjectControl");

var api = builder.AddProject<Projects.ProjectControl_Api>("api", launchProfileName: "https")
    .WithReference(database)
    .WaitFor(database)
    .WithHttpHealthCheck("/health");

builder.AddViteApp("web", "../../frontend")
    .WithReference(api)
    .WaitFor(api)
    .WithExternalHttpEndpoints();

await builder.Build().RunAsync();
