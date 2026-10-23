using Microsoft.EntityFrameworkCore;
using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.Infrastructure;

public class EfProjectListSnapshotRepository : IProjectListSnapshotRepository
{
    private readonly ProjectControlDbContext _context;

    public EfProjectListSnapshotRepository(ProjectControlDbContext context)
    {
        _context = context;
    }

    public async Task<IReadOnlyList<ProjectListSnapshot>> GetAllAsync()
    {
        return await _context.ProjectListSnapshots
            .Include(s => s.Projects)
            .OrderByDescending(s => s.UploadedAt)
            .ToListAsync();
    }

    public async Task AddAsync(ProjectListSnapshot snapshot)
    {
        _context.ProjectListSnapshots.Add(snapshot);
        await _context.SaveChangesAsync();
    }
}
