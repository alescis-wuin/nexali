using ArchUnitNET.xUnitV3;
using Xunit;
using static ArchUnitNET.Fluent.Slices.SliceRuleDefinition;

namespace Nexali.Architecture.Tests;

public sealed class ArchUnitDependencyTests
{
    [Fact]
    public void ArchitectureAssemblyCatalogMustCoverEveryProductionProject()
    {
        var graph = ProjectDependencyGraph.Load(RepositoryPaths.Root);
        var expected = graph.Projects
            .Where(project => !project.IsTest)
            .Select(project => project.Name)
            .ToHashSet(StringComparer.Ordinal);
        var actual = ArchitectureAssemblyCatalog.AssemblyNames.ToHashSet(StringComparer.Ordinal);

        Assert.True(
            expected.SetEquals(actual),
            $"Architecture assembly catalog drift detected. Missing: {string.Join(", ", expected.Except(actual).Order(StringComparer.Ordinal))}; " +
            $"extra: {string.Join(", ", actual.Except(expected).Order(StringComparer.Ordinal))}");
    }

    [Fact]
    public void ModuleNamespaceSlicesMustRemainFreeOfCycles()
    {
        var rule = Slices()
            .Matching("Nexali.Modules.(*)")
            .Should()
            .BeFreeOfCycles();

        rule.Check(ArchitectureAssemblyCatalog.Current);
    }
}
