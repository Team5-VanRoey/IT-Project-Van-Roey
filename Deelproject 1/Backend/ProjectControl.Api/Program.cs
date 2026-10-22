using Microsoft.EntityFrameworkCore;
using ProjectControl.AppLogic;
using ProjectControl.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

builder.Services.AddDbContext<ProjectControlDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("ProjectControl")));

builder.Services.AddScoped<IProjectRepository, EfProjectRepository>();
builder.Services.AddScoped<IProjectService, ProjectService>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    using var scope = app.Services.CreateScope();
    var dbContext = scope.ServiceProvider.GetRequiredService<ProjectControlDbContext>();
    dbContext.Database.Migrate();
}

app.UseHttpsRedirection();
app.UseAuthorization();

app.MapControllers();

app.Run();
