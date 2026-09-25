using System.Reflection;
using ArchUnitNET.Loader;
using ArchUnitArchitecture = ArchUnitNET.Domain.Architecture;

namespace Nexali.Architecture.Tests;

internal static class ArchitectureAssemblyCatalog
{
    private static readonly IReadOnlyList<string> _assemblyNames = Array.AsReadOnly(
        new[]
        {
            "Nexali.Api",
            "Nexali.Modules.Identity",
            "Nexali.Modules.Identity.Contracts",
            "Nexali.Modules.Workspaces",
            "Nexali.Modules.Workspaces.Contracts",
            "Nexali.Modules.Drive",
            "Nexali.Modules.Drive.Contracts",
            "Nexali.Modules.Sharing",
            "Nexali.Modules.Sharing.Contracts",
            "Nexali.Modules.Sync",
            "Nexali.Modules.Sync.Contracts",
            "Nexali.Modules.Administration",
            "Nexali.Modules.Administration.Contracts",
            "Nexali.Modules.Audit",
            "Nexali.Modules.Audit.Contracts",
            "Nexali.Modules.Calendar",
            "Nexali.Modules.Tasks",
            "Nexali.Modules.Kanban",
            "Nexali.Modules.Chat",
            "Nexali.Cryptography",
            "Nexali.Sync.Protocol",
            "Nexali.Client",
            "Nexali.Client.Sync",
            "Nexali.Web",
            "Nexali.App",
            "Nexali.Desktop",
            "Nexali.Mobile.Android",
            "Nexali.Mobile.iOS",
            "Nexali.Cli",
        });

    private static readonly Lazy<ArchUnitArchitecture> _architecture = new(CreateArchitecture);

    public static IReadOnlyList<string> AssemblyNames => _assemblyNames;

    public static ArchUnitArchitecture Current => _architecture.Value;

    private static ArchUnitArchitecture CreateArchitecture()
    {
        var assemblies = _assemblyNames.Select(Assembly.Load).ToArray();
        return new ArchLoader().LoadAssemblies(assemblies).Build();
    }
}
