FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ProjectControl.Api/ProjectControl.Api.csproj ProjectControl.Api/
COPY ProjectControl.AppLogic/ProjectControl.AppLogic.csproj ProjectControl.AppLogic/
COPY ProjectControl.Domain/ProjectControl.Domain.csproj ProjectControl.Domain/
COPY ProjectControl.Infrastructure/ProjectControl.Infrastructure.csproj ProjectControl.Infrastructure/
COPY ProjectControl.ServiceDefaults/ProjectControl.ServiceDefaults.csproj ProjectControl.ServiceDefaults/
RUN dotnet restore ProjectControl.Api/ProjectControl.Api.csproj

COPY . .
RUN dotnet publish ProjectControl.Api/ProjectControl.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "ProjectControl.Api.dll"]
