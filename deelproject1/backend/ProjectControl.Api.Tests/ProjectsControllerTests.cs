using Microsoft.AspNetCore.Mvc;
using ProjectControl.Api.Controllers;
using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.Api.Tests;

public class ProjectsControllerTests
{
    private readonly FakeProjectService _service = new();
    private readonly ProjectsController _controller;

    public ProjectsControllerTests()
    {
        _controller = new ProjectsController(_service);
    }

    [Fact]
    public async Task GetAll_ReturnsAllProjects()
    {
        _service.Projects.Add(CreateProject("Demo project"));

        var result = await _controller.GetAll();

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var projects = Assert.IsAssignableFrom<IReadOnlyList<Project>>(ok.Value);
        Assert.Single(projects);
    }

    [Fact]
    public async Task GetById_ExistingProject_ReturnsProject()
    {
        var project = CreateProject("Demo project");
        _service.Projects.Add(project);

        var result = await _controller.GetById(project.Id);

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        Assert.Same(project, ok.Value);
    }

    [Fact]
    public async Task GetById_UnknownProject_ReturnsNotFound()
    {
        var result = await _controller.GetById(Guid.NewGuid());

        Assert.IsType<NotFoundResult>(result.Result);
    }

    [Fact]
    public async Task Create_ReturnsCreatedProjectWithLocation()
    {
        var request = new CreateProjectRequest("Demo project", "Demo Klant");

        var result = await _controller.Create(request);

        var created = Assert.IsType<CreatedAtActionResult>(result.Result);
        var project = Assert.IsType<Project>(created.Value);
        Assert.Equal(nameof(ProjectsController.GetById), created.ActionName);
        Assert.Equal(project.Id, created.RouteValues!["id"]);
        Assert.Equal("Demo project", project.Name);
        Assert.Equal("Demo Klant", project.CustomerName);
    }

    private static Project CreateProject(string name)
    {
        return new Project(Guid.NewGuid(), name, "Demo Klant", new List<Milestone>());
    }

    private class FakeProjectService : IProjectService
    {
        public List<Project> Projects { get; } = new();

        public Task<IReadOnlyList<Project>> GetAllAsync()
        {
            return Task.FromResult<IReadOnlyList<Project>>(Projects);
        }

        public Task<Project?> GetByIdAsync(Guid id)
        {
            var project = Projects.FirstOrDefault(p => p.Id == id);
            return Task.FromResult(project);
        }

        public Task<Project> CreateAsync(string name, string customerName)
        {
            var project = new Project(Guid.NewGuid(), name, customerName, new List<Milestone>());
            Projects.Add(project);
            return Task.FromResult(project);
        }
    }
}
