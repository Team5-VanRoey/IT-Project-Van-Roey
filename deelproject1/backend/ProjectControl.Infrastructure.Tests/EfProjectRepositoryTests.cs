using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using ProjectControl.Domain;

namespace ProjectControl.Infrastructure.Tests;

public class EfProjectRepositoryTests : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly DbContextOptions<ProjectControlDbContext> _options;

    public EfProjectRepositoryTests()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        _options = new DbContextOptionsBuilder<ProjectControlDbContext>()
            .UseSqlite(_connection)
            .Options;

        using var context = new ProjectControlDbContext(_options);
        context.Database.EnsureCreated();
    }

    public void Dispose()
    {
        _connection.Dispose();
        GC.SuppressFinalize(this);
    }

    [Fact]
    public async Task AddAsync_SavesProjectWithMilestones()
    {
        var project = CreateProject("Demo project");

        using (var context = new ProjectControlDbContext(_options))
        {
            await new EfProjectRepository(context).AddAsync(project);
        }

        using (var context = new ProjectControlDbContext(_options))
        {
            var found = await new EfProjectRepository(context).GetByIdAsync(project.Id);

            Assert.NotNull(found);
            Assert.Equal("Demo project", found.Name);
            Assert.Equal("Demo Klant", found.CustomerName);

            var milestone = Assert.Single(found.Milestones);
            Assert.Equal("DevBuild", milestone.Name);
            Assert.Equal(130m, milestone.UnitPrice);
            Assert.Equal(14.25m, milestone.SpentHours);
        }
    }

    [Fact]
    public async Task GetAllAsync_ReturnsAllProjects()
    {
        using (var context = new ProjectControlDbContext(_options))
        {
            var repository = new EfProjectRepository(context);
            await repository.AddAsync(CreateProject("First project"));
            await repository.AddAsync(CreateProject("Second project"));
        }

        using (var context = new ProjectControlDbContext(_options))
        {
            var projects = await new EfProjectRepository(context).GetAllAsync();

            Assert.Equal(2, projects.Count);
            Assert.All(projects, p => Assert.Single(p.Milestones));
        }
    }

    [Fact]
    public async Task GetByIdAsync_UnknownId_ReturnsNull()
    {
        using var context = new ProjectControlDbContext(_options);

        var found = await new EfProjectRepository(context).GetByIdAsync(Guid.NewGuid());

        Assert.Null(found);
    }

    [Fact]
    public async Task SnapshotRepository_SavesSnapshotWithProjects_NewestFirst()
    {
        var older = new ProjectListSnapshot(Guid.NewGuid(), new DateTime(2026, 10, 1), "oud.xlsx");
        var newer = new ProjectListSnapshot(Guid.NewGuid(), new DateTime(2026, 10, 20), "nieuw.xlsx");
        newer.Projects.Add(new SnapshotProject(Guid.NewGuid(), "Klant A", new DateOnly(2026, 12, 1)));
        newer.Projects.Add(new SnapshotProject(Guid.NewGuid(), "Klant B", null));
        newer.Projects[0].Columns["PM"] = "Els";

        using (var context = new ProjectControlDbContext(_options))
        {
            var repository = new EfProjectListSnapshotRepository(context);
            await repository.AddAsync(older);
            await repository.AddAsync(newer);
        }

        using (var context = new ProjectControlDbContext(_options))
        {
            var snapshots = await new EfProjectListSnapshotRepository(context).GetAllAsync();

            Assert.Equal(["nieuw.xlsx", "oud.xlsx"], snapshots.Select(s => s.FileName));
            Assert.Equal(DateTimeKind.Utc, snapshots[0].UploadedAt.Kind);
            Assert.Equal(2, snapshots[0].Projects.Count);
            Assert.Contains(snapshots[0].Projects, p => p.CustomerName == "Klant B" && p.GoLiveDate == null);
            Assert.Contains(snapshots[0].Projects, p => p.CustomerName == "Klant A" && p.Columns["PM"] == "Els");
        }
    }

    private static Project CreateProject(string name)
    {
        var milestones = new List<Milestone>
        {
            new(Guid.NewGuid(), "DevBuild", unitPrice: 130m, budgetHours: 130m, spentHours: 14.25m)
        };

        return new Project(Guid.NewGuid(), name, "Demo Klant", milestones);
    }
}
