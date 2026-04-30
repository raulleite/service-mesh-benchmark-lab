FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY apps/service-middle/Service.Middle.csproj apps/service-middle/
RUN dotnet restore apps/service-middle/Service.Middle.csproj
COPY . .
RUN dotnet publish apps/service-middle/Service.Middle.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_EnableDiagnostics=0
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
EXPOSE 8080
COPY --from=build /app/publish .
RUN rm -f appsettings.Development.json web.config
ENTRYPOINT ["dotnet", "Service.Middle.dll"]