using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProjectControl.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddProjectListSnapshots : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ProjectListSnapshots",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    UploadedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    FileName = table.Column<string>(type: "nvarchar(260)", maxLength: 260, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ProjectListSnapshots", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "SnapshotProjects",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    CustomerName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    GoLiveDate = table.Column<DateOnly>(type: "date", nullable: true),
                    ProjectListSnapshotId = table.Column<Guid>(type: "uniqueidentifier", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SnapshotProjects", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SnapshotProjects_ProjectListSnapshots_ProjectListSnapshotId",
                        column: x => x.ProjectListSnapshotId,
                        principalTable: "ProjectListSnapshots",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SnapshotProjects_ProjectListSnapshotId",
                table: "SnapshotProjects",
                column: "ProjectListSnapshotId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SnapshotProjects");

            migrationBuilder.DropTable(
                name: "ProjectListSnapshots");
        }
    }
}
