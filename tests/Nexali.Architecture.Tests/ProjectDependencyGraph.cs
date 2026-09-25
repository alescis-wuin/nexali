using System.Xml.Linq;

namespace Nexali.Architecture.Tests;

internal sealed record ProjectDefinition(string Role, string RelativePath)
{
    public string Name => Path.GetFileNameWithoutExtension(RelativePath);

    public bool IsTest => RelativePath.StartsWith("tests/", StringComparison.Ordinal);
}

internal sealed class ProjectDependencyGraph
{
    private readonly Dictionary<string, ProjectDefinition> _projects;
    private readonly Dictionary<string, string[]> _references;

    private ProjectDependencyGraph(
        Dictionary<string, ProjectDefinition> projects,
        Dictionary<string, string[]> references)
    {
        _projects = projects;
        _references = references;
    }

    public IReadOnlyCollection<ProjectDefinition> Projects => _projects.Values;

    public static ProjectDependencyGraph Load(string repositoryRoot)
    {
        var projects = LoadProjects(repositoryRoot);
        var references = new Dictionary<string, string[]>(StringComparer.Ordinal);

        foreach (var project in projects.Values)
        {
            references[project.RelativePath] = LoadReferences(repositoryRoot, project.RelativePath);
        }

        return new ProjectDependencyGraph(projects, references);
    }

    public ProjectDefinition[] GetReferences(ProjectDefinition source)
    {
        return _references[source.RelativePath]
            .Select(path => _projects.TryGetValue(path, out var target)
                ? target
                : throw new InvalidOperationException(
                    $"ProjectReference target is missing from eng/projects.tsv: {source.RelativePath} -> {path}"))
            .ToArray();
    }

    public string[] FindCyclicProductionProjects()
    {
        var production = _projects.Values
            .Where(project => !project.IsTest)
            .ToDictionary(project => project.RelativePath, StringComparer.Ordinal);
        var indegree = production.Keys.ToDictionary(path => path, _ => 0, StringComparer.Ordinal);
        var adjacency = production.Keys.ToDictionary(
            path => path,
            _ => new List<string>(),
            StringComparer.Ordinal);

        foreach (var source in production.Values)
        {
            foreach (var target in GetReferences(source).Where(target => !target.IsTest))
            {
                adjacency[source.RelativePath].Add(target.RelativePath);
                indegree[target.RelativePath]++;
            }
        }

        var queue = new Queue<string>(indegree.Where(pair => pair.Value == 0).Select(pair => pair.Key));
        var visited = 0;
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            visited++;
            foreach (var target in adjacency[current])
            {
                indegree[target]--;
                if (indegree[target] == 0)
                {
                    queue.Enqueue(target);
                }
            }
        }

        if (visited == production.Count)
        {
            return Array.Empty<string>();
        }

        return indegree
            .Where(pair => pair.Value > 0)
            .Select(pair => pair.Key)
            .Order(StringComparer.Ordinal)
            .ToArray();
    }

    private static Dictionary<string, ProjectDefinition> LoadProjects(string repositoryRoot)
    {
        var manifest = Path.Combine(repositoryRoot, "eng", "projects.tsv");
        var projects = new Dictionary<string, ProjectDefinition>(StringComparer.Ordinal);

        foreach (var rawLine in File.ReadLines(manifest))
        {
            if (string.IsNullOrWhiteSpace(rawLine) || rawLine.TrimStart().StartsWith('#'))
            {
                continue;
            }

            var columns = rawLine.Split('\t');
            if (columns.Length != 3)
            {
                throw new InvalidOperationException($"Invalid eng/projects.tsv row: {rawLine}");
            }

            var relativePath = Normalize(columns[2]);
            projects.Add(relativePath, new ProjectDefinition(columns[0], relativePath));
        }

        return projects;
    }

    private static string[] LoadReferences(string repositoryRoot, string relativeProjectPath)
    {
        var projectPath = Path.Combine(repositoryRoot, relativeProjectPath);
        var projectDirectory = Path.GetDirectoryName(projectPath)
            ?? throw new InvalidOperationException($"Project path has no directory: {relativeProjectPath}");
        var document = XDocument.Load(projectPath, LoadOptions.None);

        return document
            .Descendants("ProjectReference")
            .Select(element => element.Attribute("Include")?.Value)
            .Where(include => !string.IsNullOrWhiteSpace(include))
            .Select(include =>
            {
                var projectReference = include!;
                if (projectReference.Contains("$(", StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        $"MSBuild-variable ProjectReference paths are not supported by architecture tests: {relativeProjectPath} -> {projectReference}");
                }

                var targetPath = Path.GetFullPath(Path.Combine(projectDirectory, projectReference));
                return Normalize(Path.GetRelativePath(repositoryRoot, targetPath));
            })
            .Order(StringComparer.Ordinal)
            .ToArray();
    }

    private static string Normalize(string path)
    {
        return path.Replace('\\', '/');
    }
}
