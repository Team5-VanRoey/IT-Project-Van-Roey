using ProjectControl.Domain;

namespace ProjectControl.AppLogic;

public interface IProjectListSnapshotRepository
{
    Task<IReadOnlyList<ProjectListSnapshot>> GetAllAsync();
    Task AddAsync(ProjectListSnapshot snapshot);
}
