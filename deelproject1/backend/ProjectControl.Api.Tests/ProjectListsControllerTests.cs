using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using ProjectControl.Api.Controllers;
using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.Api.Tests;

public class ProjectListsControllerTests
{
    private readonly FakeSnapshotRepository _repository = new();
    private readonly ProjectListsController _controller;

    public ProjectListsControllerTests()
    {
        _controller = new ProjectListsController(new ProjectListService(_repository));
    }

    [Fact]
    public async Task GetAll_ReturnsAllSnapshots()
    {
        _repository.Snapshots.Add(new ProjectListSnapshot(Guid.NewGuid(), DateTime.UtcNow, "projecten.xlsx"));

        var result = await _controller.GetAll();

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        Assert.Single(Assert.IsType<IReadOnlyList<ProjectListSnapshot>>(ok.Value, exactMatch: false));
    }

    [Fact]
    public async Task Upload_WrongExtension_ReturnsBadRequest()
    {
        var result = await _controller.Upload(CreateFile("projecten.csv", "a;b"));

        AssertBadRequest(result);
    }

    [Fact]
    public async Task Upload_CorruptXlsx_ReturnsBadRequestWithMessage()
    {
        var result = await _controller.Upload(CreateFile("projecten.xlsx", "geen excel"));

        var problem = AssertBadRequest(result);
        Assert.Contains(".xlsx", problem.Detail);
        Assert.Empty(_repository.Snapshots);
    }

    private static ProblemDetails AssertBadRequest(ActionResult<ProjectListImportResult> result)
    {
        var objectResult = Assert.IsType<ObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, objectResult.StatusCode);
        return Assert.IsType<ProblemDetails>(objectResult.Value);
    }

    private static FormFile CreateFile(string fileName, string content)
    {
        var bytes = Encoding.UTF8.GetBytes(content);
        return new FormFile(new MemoryStream(bytes), 0, bytes.Length, "file", fileName);
    }

    private class FakeSnapshotRepository : IProjectListSnapshotRepository
    {
        public List<ProjectListSnapshot> Snapshots { get; } = new();

        public Task<IReadOnlyList<ProjectListSnapshot>> GetAllAsync()
        {
            return Task.FromResult<IReadOnlyList<ProjectListSnapshot>>(Snapshots);
        }

        public Task AddAsync(ProjectListSnapshot snapshot)
        {
            Snapshots.Add(snapshot);
            return Task.CompletedTask;
        }
    }
}
