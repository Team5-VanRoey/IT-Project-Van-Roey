namespace ProjectControl.Domain;

public class SnapshotProject
{
    public Guid Id { get; private set; }
    public string CustomerName { get; private set; }
    public DateOnly? GoLiveDate { get; private set; }

    // Every column of the export row as shown, in export order (header -> value)
    public Dictionary<string, string> Columns { get; private set; } = new();

    public SnapshotProject(Guid id, string customerName, DateOnly? goLiveDate)
    {
        Id = id;
        CustomerName = customerName;
        GoLiveDate = goLiveDate;
    }
}
