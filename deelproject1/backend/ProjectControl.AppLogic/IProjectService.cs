using ProjectControl.Domain;

namespace ProjectControl.AppLogic;

public interface IProjectService
{
    Task<IReadOnlyList<Project>> GetAllAsync();
    Task<Project?> GetByIdAsync(Guid id);
    Task<Project> CreateAsync(string name, string customerName);
}
