using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows.Forms;

internal static class TGDeskLauncher
{
    [STAThread]
    private static void Main()
    {
        try
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var exePath = Path.Combine(baseDir, "TGDesk-app.exe");
            var arguments = string.Join(
                " ",
                Environment.GetCommandLineArgs()
                    .Skip(1)
                    .Select(QuoteArgument)
            );
            Process.Start(new ProcessStartInfo(exePath)
            {
                Arguments = arguments,
                UseShellExecute = true,
                WorkingDirectory = baseDir,
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                ex.ToString(),
                "TGdesk",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        }
    }

    private static string QuoteArgument(string arg)
    {
        if (string.IsNullOrEmpty(arg))
        {
            return "\"\"";
        }

        return arg.Contains(" ") || arg.Contains("\"")
            ? "\"" + arg.Replace("\"", "\\\"") + "\""
            : arg;
    }
}
