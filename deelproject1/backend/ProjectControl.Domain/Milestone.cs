namespace ProjectControl.Domain;

public class Milestone
{
    public Guid Id { get; private set; }
    public string Name { get; private set; }
    public decimal UnitPrice { get; private set; }
    public decimal BudgetHours { get; private set; }
    public decimal SpentHours { get; private set; }

    public decimal BudgetValue => BudgetHours * UnitPrice;
    public decimal SpentValue => SpentHours * UnitPrice;
    public decimal RemainingHours => BudgetHours - SpentHours;

    public Milestone(Guid id, string name, decimal unitPrice, decimal budgetHours, decimal spentHours)
    {
        Id = id;
        Name = name;
        UnitPrice = unitPrice;
        BudgetHours = budgetHours;
        SpentHours = spentHours;
    }
}
