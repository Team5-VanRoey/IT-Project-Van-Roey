using Microsoft.AspNetCore.Mvc;
using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProjectsController : ControllerBase
{
    private readonly IProjectService _projectService;

    public ProjectsController(IProjectService projectService)
    {
        _projectService = projectService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<Project>>> GetAll()
    {
        var projects = await _projectService.GetAllAsync();
        return Ok(projects);
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<Project>> GetById(Guid id)
    {
        var project = await _projectService.GetByIdAsync(id);

        if (project == null)
        {
            return NotFound();
        }

        return Ok(project);
    }

    [HttpPost]
    public async Task<ActionResult<Project>> Create(CreateProjectRequest request)
    {
        var project = await _projectService.CreateAsync(request.Name, request.CustomerName);
        return CreatedAtAction(nameof(GetById), new { id = project.Id }, project);
    }
}

public record CreateProjectRequest(string Name, string CustomerName);
