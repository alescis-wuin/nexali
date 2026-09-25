using Xunit;

namespace Nexali.Architecture.Tests;

public sealed class ProjectDependencyTests
{
    private static readonly ProjectDependencyGraph _graph = ProjectDependencyGraph.Load(RepositoryPaths.Root);

    [Fact]
    public void ProductionProjectGraphMustRemainAcyclic()
    {
        var cyclicProjects = _graph.FindCyclicProductionProjects();
        Assert.True(
            cyclicProjects.Length == 0,
            $"Production project dependency cycle detected: {string.Join(", ", cyclicProjects)}");
    }

    [Fact]
    public void ModuleImplementationsMustNotReferenceOtherImplementations()
    {
        var violations = new List<string>();
        foreach (var source in _graph.Projects.Where(IsModuleImplementation))
        {
            foreach (var target in _graph.GetReferences(source).Where(IsModuleImplementation))
            {
                violations.Add($"{source.RelativePath} -> {target.RelativePath}");
            }
        }

        AssertNoViolations(violations, "Module implementations may collaborate with other modules only through explicit contract surfaces.");
    }

    [Fact]
    public void ContractProjectsMustRemainBoundaryOnly()
    {
        var forbiddenRoles = new HashSet<string>(StringComparer.Ordinal)
        {
            "server-host",
            "module",
            "future-module",
            "web-client-shell",
            "avalonia-shared-shell",
            "platform-head-shell",
            "tool",
        };
        var violations = FindRoleReferenceViolations(
            source => source.Role == "contracts",
            target => forbiddenRoles.Contains(target.Role));

        AssertNoViolations(violations, "Contract projects must not depend on implementation, host, client, or tool projects.");
    }

    [Fact]
    public void ClientProjectsMustNotReferenceServerOrModules()
    {
        var clientRoles = new HashSet<string>(StringComparer.Ordinal)
        {
            "web-client-shell",
            "avalonia-shared-shell",
            "platform-head-shell",
        };
        var forbiddenRoles = new HashSet<string>(StringComparer.Ordinal)
        {
            "server-host",
            "module",
            "future-module",
            "contracts",
        };
        var violations = FindRoleReferenceViolations(
            source => clientRoles.Contains(source.Role),
            target => forbiddenRoles.Contains(target.Role));

        AssertNoViolations(violations, "Clients must consume client/protocol libraries and never server module projects.");
    }

    [Fact]
    public void SharedLibrariesMustRemainIndependentFromServerAndModules()
    {
        var forbiddenRoles = new HashSet<string>(StringComparer.Ordinal)
        {
            "server-host",
            "module",
            "future-module",
            "contracts",
            "web-client-shell",
            "avalonia-shared-shell",
            "platform-head-shell",
            "tool",
        };
        var violations = FindRoleReferenceViolations(
            source => source.Role == "library",
            target => forbiddenRoles.Contains(target.Role));

        AssertNoViolations(violations, "Shared libraries may depend on other libraries but not on server, module, client, or tool projects.");
    }

    [Fact]
    public void OnlyServerHostMayReferenceModuleImplementations()
    {
        var violations = new List<string>();
        foreach (var source in _graph.Projects.Where(project => !project.IsTest && project.Role != "server-host"))
        {
            foreach (var target in _graph.GetReferences(source).Where(IsModuleImplementation))
            {
                violations.Add($"{source.RelativePath} -> {target.RelativePath}");
            }
        }

        AssertNoViolations(violations, "Only the server composition root may reference module implementation assemblies.");
    }

    [Fact]
    public void GenericCommonUtilityProjectsMustNotBeIntroduced()
    {
        var forbiddenSegments = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Common",
            "Utils",
            "Utilities",
            "Helpers",
        };
        var violations = _graph.Projects
            .Where(project => !project.IsTest)
            .Where(project => project.Name.Split('.').Any(forbiddenSegments.Contains))
            .Select(project => project.RelativePath)
            .Order(StringComparer.Ordinal)
            .ToArray();

        AssertNoViolations(violations, "Nexali avoids generic Common/Utils/Utilities/Helpers project buckets.");
    }

    private static List<string> FindRoleReferenceViolations(
        Func<ProjectDefinition, bool> sourcePredicate,
        Func<ProjectDefinition, bool> targetPredicate)
    {
        var violations = new List<string>();
        foreach (var source in _graph.Projects.Where(project => !project.IsTest).Where(sourcePredicate))
        {
            foreach (var target in _graph.GetReferences(source).Where(targetPredicate))
            {
                violations.Add($"{source.RelativePath} -> {target.RelativePath}");
            }
        }

        return violations;
    }

    private static bool IsModuleImplementation(ProjectDefinition project)
    {
        return project.Role is "module" or "future-module";
    }

    private static void AssertNoViolations(IReadOnlyCollection<string> violations, string rule)
    {
        Assert.True(
            violations.Count == 0,
            $"{rule}{Environment.NewLine}{string.Join(Environment.NewLine, violations)}");
    }
}
