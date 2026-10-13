using System.IO;
using System.Text.Json;

namespace Pulgapp.Server.App.Settings;

public static class SettingsManager
{
    private static readonly string SettingsDirectory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Pulgapp");

    private static readonly string SettingsFilePath =
        Path.Combine(SettingsDirectory, "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsFilePath))
            {
                var json = File.ReadAllText(SettingsFilePath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
                if (settings is not null)
                {
                    return settings;
                }
            }
        }
        catch
        {
            // Recover safely to defaults if file is corrupted or unreadable
        }

        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(SettingsDirectory);
            var json = JsonSerializer.Serialize(settings, JsonOptions);
            File.WriteAllText(SettingsFilePath, json);
        }
        catch
        {
            // Do not crash if settings write fails (e.g. disk full or read-only)
        }
    }
}
