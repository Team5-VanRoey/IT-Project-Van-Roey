using Microsoft.EntityFrameworkCore;
using Microsoft.Identity.Web;
using ProjectControl.AppLogic;
using ProjectControl.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

builder.Services.AddDbContext<ProjectControlDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("ProjectControl")));

builder.Services.AddScoped<IProjectRepository, EfProjectRepository>();
builder.Services.AddScoped<IProjectService, ProjectService>();
builder.Services.AddScoped<IProjectListSnapshotRepository, EfProjectListSnapshotRepository>();
builder.Services.AddScoped<ProjectListService>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// Development always migrates. In the DTAP environments the deployment decides
// (Database__MigrateOnStartup in deploy/compose.yml), so production can migrate deliberately.
if (app.Environment.IsDevelopment() || app.Configuration.GetValue<bool>("Database:MigrateOnStartup"))
{
    using var scope = app.Services.CreateScope();
    var dbContext = scope.ServiceProvider.GetRequiredService<ProjectControlDbContext>();
    dbContext.Database.Migrate();
}

// Behind the reverse proxy (frontend container) TLS ends at the proxy, so no redirect there
if (!app.Configuration.GetValue<bool>("BehindReverseProxy"))
{
    app.UseHttpsRedirection();
}

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapDefaultEndpoints();

app.Run();
