using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProjectControl.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSnapshotProjectColumns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Columns",
                table: "SnapshotProjects",
                type: "nvarchar(max)",
                nullable: false,
                defaultValue: "{}");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Columns",
                table: "SnapshotProjects");
        }
    }
}
