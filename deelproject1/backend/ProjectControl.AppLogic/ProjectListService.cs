using System.Globalization;
using ClosedXML.Excel;
using ProjectControl.Domain;

namespace ProjectControl.AppLogic;

public class ProjectListService
{
    public const string CustomerColumn = "Klant";
    public const string StatusColumn = "Status";
    public const string GoLiveColumn = "Geplande go-live";
    public const string ImplementationStatus = "Implementatiefase";

    private static readonly CultureInfo DutchCulture = CultureInfo.GetCultureInfo("nl-BE");

    private readonly IProjectListSnapshotRepository _repository;

    public ProjectListService(IProjectListSnapshotRepository repository)
    {
        _repository = repository;
    }

    public async Task<IReadOnlyList<ProjectListSnapshot>> GetAllAsync()
    {
        return await _repository.GetAllAsync();
    }

    public async Task<ProjectListImportResult> ImportAsync(Stream file, string fileName)
    {
        using var workbook = OpenWorkbook(file);
        var sheet = workbook.Worksheets.First();
        var header = sheet.FirstRowUsed() ?? throw new ProjectListImportException("Het bestand is leeg.");

        var columns = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var cell in header.CellsUsed())
        {
            columns.TryAdd(cell.GetString().Trim(), cell.Address.ColumnNumber);
        }

        var missing = new[] { CustomerColumn, StatusColumn, GoLiveColumn }.Where(c => !columns.ContainsKey(c)).ToList();
        if (missing.Count > 0)
        {
            throw new ProjectListImportException($"Kolom(men) ontbreken in het bestand: {string.Join(", ", missing)}.");
        }

        var snapshot = new ProjectListSnapshot(Guid.NewGuid(), DateTime.UtcNow, fileName);
        var warnings = new List<string>();

        foreach (var row in sheet.RowsUsed().Where(r => r.RowNumber() > header.RowNumber()))
        {
            var status = row.Cell(columns[StatusColumn]).GetString().Trim();
            if (!status.Equals(ImplementationStatus, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var customerName = row.Cell(columns[CustomerColumn]).GetString().Trim();
            var goLiveDate = ReadDate(row.Cell(columns[GoLiveColumn]));
            if (goLiveDate == null)
            {
                warnings.Add($"Project '{customerName}' (rij {row.RowNumber()}) heeft geen GoLive-datum.");
            }

            var project = new SnapshotProject(Guid.NewGuid(), customerName, goLiveDate);
            foreach (var (name, number) in columns)
            {
                // GoLive as the parsed date, the raw cell can be an Excel serial number
                project.Columns[name] = columns.Comparer.Equals(name, GoLiveColumn)
                    ? goLiveDate?.ToString("yyyy-MM-dd") ?? ""
                    : row.Cell(number).GetFormattedString().Trim();
            }

            snapshot.Projects.Add(project);
        }

        await _repository.AddAsync(snapshot);
        return new ProjectListImportResult(snapshot, warnings);
    }

    private static XLWorkbook OpenWorkbook(Stream file)
    {
        try
        {
            return new XLWorkbook(file);
        }
        catch (Exception ex) // ClosedXML throws many different types for a corrupt or non-xlsx file
        {
            throw new ProjectListImportException("Het bestand is geen geldig Excel-bestand (.xlsx).", ex);
        }
    }

    private static DateOnly? ReadDate(IXLCell cell)
    {
        if (cell.DataType == XLDataType.DateTime)
        {
            return DateOnly.FromDateTime(cell.GetDateTime());
        }

        // The SharePoint export formats GoLive as "mmm-yy", which ClosedXML reads as a plain Excel serial number
        if (cell.DataType == XLDataType.Number)
        {
            return DateOnly.FromDateTime(DateTime.FromOADate(cell.GetDouble()));
        }

        return DateTime.TryParse(cell.GetString(), DutchCulture, out var date) ? DateOnly.FromDateTime(date) : null;
    }
}

public record ProjectListImportResult(ProjectListSnapshot Snapshot, IReadOnlyList<string> Warnings);

public class ProjectListImportException : Exception
{
    public ProjectListImportException(string message, Exception? innerException = null) : base(message, innerException)
    {
    }
}
