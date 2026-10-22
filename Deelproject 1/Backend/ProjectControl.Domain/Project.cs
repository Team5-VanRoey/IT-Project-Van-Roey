using Lombok.NET;

namespace ProjectControl.Domain;

[AllArgsConstructor(MemberType = MemberType.Property, AccessTypes = AccessTypes.Public)]
[NoArgsConstructor(ModifierType = AccessTypes.Private)]
public partial class Project
{
    public Guid Id { get; private set; }
    public string Name { get; private set; } = string.Empty;
    public string CustomerName { get; private set; } = string.Empty;
    public List<Milestone> Milestones { get; private set; } = new();
}
