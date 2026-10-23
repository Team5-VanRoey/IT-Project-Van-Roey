namespace ProjectControl.Domain;

// One upload of the SharePoint project list, kept as it was on that date.
public class ProjectListSnapshot
{
    public Guid Id { get; private set; }
    public DateTime UploadedAt { get; private set; }
    public string FileName { get; private set; }
    public List<SnapshotProject> Projects { get; private set; } = new();

    public ProjectListSnapshot(Guid id, DateTime uploadedAt, string fileName)
    {
        Id = id;
        UploadedAt = uploadedAt;
        FileName = fileName;
    }
}
