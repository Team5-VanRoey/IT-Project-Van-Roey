using ProjectControl.Domain;

namespace ProjectControl.AppLogic;

public class ProjectService : IProjectService
{
    private readonly IProjectRepository _repository;

    public ProjectService(IProjectRepository repository)
    {
        _repository = repository;
    }

    public async Task<IReadOnlyList<Project>> GetAllAsync()
    {
        return await _repository.GetAllAsync();
    }

    public async Task<Project?> GetByIdAsync(Guid id)
    {
        return await _repository.GetByIdAsync(id);
    }

    public async Task<Project> CreateAsync(string name, string customerName)
    {
        var project = new Project(Guid.NewGuid(), name, customerName, new List<Milestone>());
        await _repository.AddAsync(project);
        return project;
    }
}
