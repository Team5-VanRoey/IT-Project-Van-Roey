using Microsoft.AspNetCore.Mvc;
using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProjectListsController : ControllerBase
{
    private readonly ProjectListService _projectListService;

    public ProjectListsController(ProjectListService projectListService)
    {
        _projectListService = projectListService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<ProjectListSnapshot>>> GetAll()
    {
        return Ok(await _projectListService.GetAllAsync());
    }

    [HttpPost]
    public async Task<ActionResult<ProjectListImportResult>> Upload(IFormFile file)
    {
        if (!Path.GetExtension(file.FileName).Equals(".xlsx", StringComparison.OrdinalIgnoreCase))
        {
            return Problem("Alleen een Excel-bestand (.xlsx) kan opgeladen worden.", statusCode: StatusCodes.Status400BadRequest);
        }

        try
        {
            await using var stream = file.OpenReadStream();
            var result = await _projectListService.ImportAsync(stream, Path.GetFileName(file.FileName));
            return Ok(result);
        }
        catch (ProjectListImportException ex)
        {
            return Problem(ex.Message, statusCode: StatusCodes.Status400BadRequest);
        }
    }
}
