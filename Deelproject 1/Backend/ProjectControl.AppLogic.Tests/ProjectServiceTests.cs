using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.AppLogic.Tests;

public class ProjectServiceTests
{
    [Fact]
    public async Task CreateAsync_SavesProject_SoItCanBeFoundAgain()
    {
        var service = new ProjectService(new FakeProjectRepository());

        var created = await service.CreateAsync("Demo Klant - D365 Sales", "Demo Klant");
        var found = await service.GetByIdAsync(created.Id);
        var allProjects = await service.GetAllAsync();

        Assert.NotNull(found);
        Assert.Equal("Demo Klant - D365 Sales", found.Name);
        Assert.Equal("Demo Klant", found.CustomerName);
        Assert.Empty(found.Milestones);
        Assert.Single(allProjects);
    }

    private class FakeProjectRepository : IProjectRepository
    {
        private readonly List<Project> _projects = new();

        public Task<IReadOnlyList<Project>> GetAllAsync()
        {
            return Task.FromResult<IReadOnlyList<Project>>(_projects);
        }

        public Task<Project?> GetByIdAsync(Guid id)
        {
            var project = _projects.FirstOrDefault(p => p.Id == id);
            return Task.FromResult(project);
        }

        public Task AddAsync(Project project)
        {
            _projects.Add(project);
            return Task.CompletedTask;
        }
    }
}
