using Microsoft.EntityFrameworkCore;
using ProjectControl.Domain;

namespace ProjectControl.Infrastructure;

public class ProjectControlDbContext : DbContext
{
    public ProjectControlDbContext(DbContextOptions<ProjectControlDbContext> options) : base(options)
    {
    }

    public DbSet<Project> Projects => Set<Project>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Project>(project =>
        {
            project.Property(p => p.Id).ValueGeneratedNever();
            project.Property(p => p.Name).HasMaxLength(200);
            project.Property(p => p.CustomerName).HasMaxLength(200);
            project.HasMany(p => p.Milestones)
                .WithOne()
                .HasForeignKey("ProjectId")
                .IsRequired()
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Milestone>(milestone =>
        {
            milestone.ToTable("Milestones");
            milestone.Property(m => m.Id).ValueGeneratedNever();
            milestone.Property(m => m.Name).HasMaxLength(200);
            milestone.Property(m => m.UnitPrice).HasPrecision(18, 2);
            milestone.Property(m => m.BudgetHours).HasPrecision(18, 2);
            milestone.Property(m => m.SpentHours).HasPrecision(18, 2);
        });
    }
}
