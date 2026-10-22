using ProjectControl.Domain;

namespace ProjectControl.Domain.Tests;

public class MilestoneTests
{
    [Fact]
    public void Milestone_CalculatesBudgetSpentAndRemaining()
    {
        var milestone = new Milestone(Guid.NewGuid(), "DevBuild", unitPrice: 130m, budgetHours: 130m, spentHours: 14.25m);

        Assert.Equal(16900m, milestone.BudgetValue);
        Assert.Equal(1852.5m, milestone.SpentValue);
        Assert.Equal(115.75m, milestone.RemainingHours);
    }
}
