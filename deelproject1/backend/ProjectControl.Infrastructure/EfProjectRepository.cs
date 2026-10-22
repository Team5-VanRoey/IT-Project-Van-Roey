using Microsoft.EntityFrameworkCore;
using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.Infrastructure;

public class EfProjectRepository : IProjectRepository
{
    private readonly ProjectControlDbContext _context;

    public EfProjectRepository(ProjectControlDbContext context)
    {
        _context = context;
    }

    public async Task<IReadOnlyList<Project>> GetAllAsync()
    {
        return await _context.Projects
            .Include(p => p.Milestones)
            .ToListAsync();
    }

    public async Task<Project?> GetByIdAsync(Guid id)
    {
        return await _context.Projects
            .Include(p => p.Milestones)
            .FirstOrDefaultAsync(p => p.Id == id);
    }

    public async Task AddAsync(Project project)
    {
        _context.Projects.Add(project);
        await _context.SaveChangesAsync();
    }
}
