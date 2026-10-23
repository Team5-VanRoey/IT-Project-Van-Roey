using System.Text;
using ClosedXML.Excel;
using ProjectControl.AppLogic;
using ProjectControl.Domain;

namespace ProjectControl.AppLogic.Tests;

public class ProjectListServiceTests
{
    private readonly FakeSnapshotRepository _repository = new();
    private readonly ProjectListService _service;

    public ProjectListServiceTests()
    {
        _service = new ProjectListService(_repository);
    }

    [Fact]
    public async Task ImportAsync_KeepsOnlyImplementationPhaseCustomers_AndSavesSnapshot()
    {
        using var file = CreateXlsx(
            ["Klant", "Status", "Geplande go-live"],
            ["Klant A", "Implementatiefase", new DateTime(2026, 12, 1)],
            ["Klant B", "Offertefase", new DateTime(2026, 11, 1)],
            ["Klant C", " implementatiefase ", "15/01/2027"],
            ["Klant D", "Implementatiefase", 46296]);

        var result = await _service.ImportAsync(file, "projecten.xlsx");

        Assert.Same(result.Snapshot, Assert.Single(_repository.Snapshots));
        Assert.Equal("projecten.xlsx", result.Snapshot.FileName);
        Assert.Collection(result.Snapshot.Projects,
            p => { Assert.Equal("Klant A", p.CustomerName); Assert.Equal(new DateOnly(2026, 12, 1), p.GoLiveDate); },
            p => { Assert.Equal("Klant C", p.CustomerName); Assert.Equal(new DateOnly(2027, 1, 15), p.GoLiveDate); },
            p => { Assert.Equal("Klant D", p.CustomerName); Assert.Equal(new DateOnly(2026, 10, 1), p.GoLiveDate); });
        Assert.Empty(result.Warnings);
    }

    [Fact]
    public async Task ImportAsync_KeepsAllColumnsInExportOrder()
    {
        using var file = CreateXlsx(
            ["Klant", "PM", "Status", "Geplande go-live"],
            ["Klant A", "Els", "Implementatiefase", 46296]);

        var result = await _service.ImportAsync(file, "projecten.xlsx");

        Assert.Equal(
            [new("Klant", "Klant A"), new("PM", "Els"), new("Status", "Implementatiefase"), new("Geplande go-live", "2026-10-01")],
            Assert.Single(result.Snapshot.Projects).Columns.ToList());
    }

    [Fact]
    public async Task ImportAsync_EachUploadIsAnExtraSnapshot()
    {
        using var first = CreateXlsx(["Klant", "Status", "Geplande go-live"]);
        using var second = CreateXlsx(["Klant", "Status", "Geplande go-live"]);

        await _service.ImportAsync(first, "a.xlsx");
        await _service.ImportAsync(second, "b.xlsx");

        Assert.Equal(2, (await _service.GetAllAsync()).Count);
    }

    [Fact]
    public async Task ImportAsync_ProjectWithoutGoLive_GivesWarning()
    {
        using var file = CreateXlsx(
            ["Klant", "Status", "Geplande go-live"],
            ["Klant A", "Implementatiefase", ""]);

        var result = await _service.ImportAsync(file, "projecten.xlsx");

        Assert.Null(Assert.Single(result.Snapshot.Projects).GoLiveDate);
        Assert.Contains("Klant A", Assert.Single(result.Warnings));
    }

    [Fact]
    public async Task ImportAsync_MissingColumn_ThrowsClearError()
    {
        using var file = CreateXlsx(["Klant", "Status"]);

        var ex = await Assert.ThrowsAsync<ProjectListImportException>(() => _service.ImportAsync(file, "projecten.xlsx"));

        Assert.Contains("Geplande go-live", ex.Message);
        Assert.Empty(_repository.Snapshots);
    }

    [Fact]
    public async Task ImportAsync_NotAnExcelFile_ThrowsClearError()
    {
        using var file = new MemoryStream(Encoding.UTF8.GetBytes("geen excel"));

        var ex = await Assert.ThrowsAsync<ProjectListImportException>(() => _service.ImportAsync(file, "projecten.xlsx"));

        Assert.Contains(".xlsx", ex.Message);
    }

    private static MemoryStream CreateXlsx(params object[][] rows)
    {
        using var workbook = new XLWorkbook();
        var sheet = workbook.AddWorksheet("Projecten");
        for (var r = 0; r < rows.Length; r++)
        {
            for (var c = 0; c < rows[r].Length; c++)
            {
                sheet.Cell(r + 1, c + 1).Value = XLCellValue.FromObject(rows[r][c]);
            }
        }

        var stream = new MemoryStream();
        workbook.SaveAs(stream);
        stream.Position = 0;
        return stream;
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
