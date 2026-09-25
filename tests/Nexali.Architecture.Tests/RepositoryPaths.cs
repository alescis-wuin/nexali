namespace Nexali.Architecture.Tests;

internal static class RepositoryPaths
{
    public static string Root { get; } = ResolveRoot();

    private static string ResolveRoot()
    {
        var configured = Environment.GetEnvironmentVariable("NEXALI_REPO_ROOT");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(Path.Combine(configured, "Nexali.sln")))
        {
            return Path.GetFullPath(configured);
        }

        foreach (var start in new[] { Environment.CurrentDirectory, AppContext.BaseDirectory })
        {
            DirectoryInfo? directory = new DirectoryInfo(start);
            while (directory is not null)
            {
                if (File.Exists(Path.Combine(directory.FullName, "Nexali.sln")) &&
                    File.Exists(Path.Combine(directory.FullName, "eng", "projects.tsv")))
                {
                    return directory.FullName;
                }

                directory = directory.Parent;
            }
        }

        throw new InvalidOperationException("Unable to locate the Nexali repository root.");
    }
}
