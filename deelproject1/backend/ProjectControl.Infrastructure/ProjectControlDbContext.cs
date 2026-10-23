using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using ProjectControl.Domain;

namespace ProjectControl.Infrastructure;

public class ProjectControlDbContext : DbContext
{
    public ProjectControlDbContext(DbContextOptions<ProjectControlDbContext> options) : base(options)
    {
    }

    public DbSet<Project> Projects => Set<Project>();
    public DbSet<ProjectListSnapshot> ProjectListSnapshots => Set<ProjectListSnapshot>();

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

        modelBuilder.Entity<ProjectListSnapshot>(snapshot =>
        {
            snapshot.Property(s => s.Id).ValueGeneratedNever();
            snapshot.Property(s => s.FileName).HasMaxLength(260);
            // SQL Server drops DateTimeKind; mark it UTC again so the JSON gets a 'Z' and browsers show local time
            snapshot.Property(s => s.UploadedAt).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            snapshot.HasMany(s => s.Projects)
                .WithOne()
                .HasForeignKey("ProjectListSnapshotId")
                .IsRequired()
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<SnapshotProject>(project =>
        {
            project.ToTable("SnapshotProjects");
            project.Property(p => p.Id).ValueGeneratedNever();
            project.Property(p => p.CustomerName).HasMaxLength(200);
            project.Property(p => p.Columns).HasConversion(
                columns => JsonSerializer.Serialize(columns, (JsonSerializerOptions?)null),
                json => JsonSerializer.Deserialize<Dictionary<string, string>>(json, (JsonSerializerOptions?)null)!,
                new ValueComparer<Dictionary<string, string>>(
                    (a, b) => a!.SequenceEqual(b!),
                    columns => columns.Aggregate(0, (hash, pair) => HashCode.Combine(hash, pair.Key, pair.Value)),
                    columns => new Dictionary<string, string>(columns)));
        });
    }
}
