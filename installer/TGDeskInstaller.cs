using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

internal static class TGDeskInstaller
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new InstallerForm());
    }
}

internal sealed class InstallerForm : Form
{
    private readonly Panel welcomePanel;
    private readonly Panel installPanel;
    private readonly TextBox passwordTextBox;
    private readonly TextBox pathTextBox;
    private readonly Button continueButton;
    private readonly Button backButton;
    private readonly Button installButton;
    private readonly Button cancelButton;
    private readonly CheckBox startMenuCheckBox;
    private readonly CheckBox desktopIconCheckBox;
    private readonly CheckBox printerCheckBox;
    private readonly Label statusLabel;
    private readonly ProgressBar progressBar;

    internal InstallerForm()
    {
        Text = "TGdesk Setup";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(560, 360);
        Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);
        BackColor = Color.White;

        welcomePanel = BuildWelcomePanel();
        installPanel = BuildInstallPanel();
        Controls.Add(welcomePanel);
        Controls.Add(installPanel);

        continueButton = CreateButton("Seguir", new Point(352, 285), HandleContinueClick);
        cancelButton = CreateButton("Cancelar", new Point(446, 285), delegate { Close(); });
        welcomePanel.Controls.Add(continueButton);
        welcomePanel.Controls.Add(cancelButton);

        backButton = CreateButton("Voltar", new Point(258, 285), HandleBackClick);
        installButton = CreateButton("Instalar", new Point(446, 285), HandleInstallClick);
        installPanel.Controls.Add(backButton);
        installPanel.Controls.Add(installButton);

        passwordTextBox = new TextBox
        {
            Location = new Point(36, 102),
            Size = new Size(488, 30),
            UseSystemPasswordChar = true,
        };
        installPanel.Controls.Add(passwordTextBox);

        pathTextBox = new TextBox
        {
            Location = new Point(36, 168),
            Size = new Size(488, 30),
            ReadOnly = true,
            Text = GetDefaultExtractionPath(),
        };
        installPanel.Controls.Add(pathTextBox);

        startMenuCheckBox = new CheckBox
        {
            Location = new Point(36, 214),
            Size = new Size(220, 24),
            Text = "Criar atalho no menu iniciar",
            Checked = true,
        };
        installPanel.Controls.Add(startMenuCheckBox);

        desktopIconCheckBox = new CheckBox
        {
            Location = new Point(36, 240),
            Size = new Size(220, 24),
            Text = "Criar icone na area de trabalho",
            Checked = true,
        };
        installPanel.Controls.Add(desktopIconCheckBox);

        printerCheckBox = new CheckBox
        {
            Location = new Point(280, 214),
            Size = new Size(180, 24),
            Text = "Instalar impressora",
            Checked = true,
        };
        installPanel.Controls.Add(printerCheckBox);

        statusLabel = new Label
        {
            Location = new Point(36, 287),
            Size = new Size(210, 24),
            ForeColor = Color.FromArgb(60, 60, 60),
        };
        installPanel.Controls.Add(statusLabel);

        progressBar = new ProgressBar
        {
            Location = new Point(36, 315),
            Size = new Size(488, 18),
            Style = ProgressBarStyle.Marquee,
            Visible = false,
        };
        installPanel.Controls.Add(progressBar);

        ShowWelcome();
    }

    private Panel BuildWelcomePanel()
    {
        Panel panel = new Panel
        {
            Dock = DockStyle.Fill,
        };

        Label title = new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 22F, FontStyle.Bold, GraphicsUnit.Point),
            Location = new Point(34, 34),
            Text = "Instalacao do TGdesk",
        };
        panel.Controls.Add(title);

        Label subtitle = new Label
        {
            Location = new Point(38, 92),
            Size = new Size(480, 120),
            Text = "Este instalador vai preparar o TGdesk no computador e registrar uma senha fixa para acesso remoto." +
                Environment.NewLine + Environment.NewLine +
                "Clique em Seguir para definir a senha e concluir a instalacao.",
        };
        panel.Controls.Add(subtitle);

        Label note = new Label
        {
            Location = new Point(38, 220),
            Size = new Size(480, 40),
            ForeColor = Color.FromArgb(100, 100, 100),
            Text = "Depois de instalado, o TGdesk vai abrir usando a senha fixa definida aqui.",
        };
        panel.Controls.Add(note);

        return panel;
    }

    private Panel BuildInstallPanel()
    {
        Panel panel = new Panel
        {
            Dock = DockStyle.Fill,
        };

        Label title = new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 20F, FontStyle.Bold, GraphicsUnit.Point),
            Location = new Point(34, 28),
            Text = "Configurar instalacao",
        };
        panel.Controls.Add(title);

        Label passwordLabel = new Label
        {
            AutoSize = true,
            Location = new Point(36, 78),
            Text = "Senha fixa",
        };
        panel.Controls.Add(passwordLabel);

        Label pathLabel = new Label
        {
            AutoSize = true,
            Location = new Point(36, 144),
            Text = "Pasta temporaria usada apenas durante a instalacao",
        };
        panel.Controls.Add(pathLabel);

        Label hintLabel = new Label
        {
            Location = new Point(36, 40),
            Size = new Size(488, 24),
            ForeColor = Color.FromArgb(90, 90, 90),
            Text = "Defina a senha fixa que sera usada pelo cliente instalado.",
        };
        panel.Controls.Add(hintLabel);

        Label pathHintLabel = new Label
        {
            Location = new Point(36, 202),
            Size = new Size(488, 18),
            ForeColor = Color.FromArgb(110, 110, 110),
            Text = "A instalacao final do programa acontece na pasta padrao do TGdesk.",
        };
        panel.Controls.Add(pathHintLabel);

        return panel;
    }

    private static Button CreateButton(string text, Point location, EventHandler onClick)
    {
        Button button = new Button
        {
            Text = text,
            Location = location,
            Size = new Size(78, 34),
        };
        button.Click += onClick;
        return button;
    }

    private static string GetDefaultExtractionPath()
    {
        string baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(baseDir, "TGdesk");
    }

    private void ShowWelcome()
    {
        welcomePanel.Visible = true;
        installPanel.Visible = false;
    }

    private void ShowInstall()
    {
        welcomePanel.Visible = false;
        installPanel.Visible = true;
        passwordTextBox.Focus();
    }

    private void HandleContinueClick(object sender, EventArgs e)
    {
        ShowInstall();
    }

    private void HandleBackClick(object sender, EventArgs e)
    {
        if (installButton.Enabled)
        {
            ShowWelcome();
        }
    }

    private async void HandleInstallClick(object sender, EventArgs e)
    {
        string password = passwordTextBox.Text.Trim();
        if (password.Length == 0)
        {
            MessageBox.Show(
                "Digite a senha fixa antes de instalar.",
                "TGdesk Setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning
            );
            passwordTextBox.Focus();
            return;
        }

        SetBusy(true, "Instalando...");

        try
        {
            await Task.Run(delegate
            {
                InstallTGdesk(password);
            });

            SetBusy(false, "Instalacao concluida");

            DialogResult result = MessageBox.Show(
                "TGdesk instalado com sucesso. Deseja abrir agora?",
                "TGdesk Setup",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information
            );

            if (result == DialogResult.Yes)
            {
                LaunchInstalledClient();
            }

            Close();
        }
        catch (Exception ex)
        {
            SetBusy(false, "Falha na instalacao");
            MessageBox.Show(
                ex.Message,
                "TGdesk Setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        }
    }

    private void SetBusy(bool busy, string status)
    {
        continueButton.Enabled = !busy;
        backButton.Enabled = !busy;
        cancelButton.Enabled = !busy;
        installButton.Enabled = !busy;
        passwordTextBox.Enabled = !busy;
        startMenuCheckBox.Enabled = !busy;
        desktopIconCheckBox.Enabled = !busy;
        printerCheckBox.Enabled = !busy;
        progressBar.Visible = busy;
        statusLabel.Text = status;
    }

    private void InstallTGdesk(string password)
    {
        string targetDir = pathTextBox.Text.Trim();
        string tempZip = Path.Combine(Path.GetTempPath(), "TGDesk-installer.zip");
        string exePath = Path.Combine(targetDir, "TGdesk.exe");

        if (Directory.Exists(targetDir))
        {
            Directory.Delete(targetDir, true);
        }

        Directory.CreateDirectory(targetDir);

        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("TGDesk.zip"))
        {
            if (input == null)
            {
                throw new InvalidOperationException("Recurso TGDesk.zip nao encontrado no instalador.");
            }

            using (FileStream output = File.Create(tempZip))
            {
                input.CopyTo(output);
            }
        }

        ZipFile.ExtractToDirectory(tempZip, targetDir);
        File.Delete(tempZip);

        if (!File.Exists(exePath))
        {
            throw new FileNotFoundException("TGdesk.exe nao foi encontrado apos a extracao.", exePath);
        }

        string installOptions = BuildInstallOptions(password);
        string encodedOptions = Convert.ToBase64String(Encoding.UTF8.GetBytes(installOptions));
        string arguments = "--silent-install --install-options-b64 \"" + encodedOptions + "\"";

        using (Process process = Process.Start(new ProcessStartInfo(exePath)
        {
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = targetDir,
        }))
        {
            if (process == null)
            {
                throw new InvalidOperationException("Nao foi possivel iniciar a instalacao do TGdesk.");
            }

            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException("A instalacao do TGdesk terminou com erro.");
            }
        }
    }

    private string BuildInstallOptions(string password)
    {
        StringBuilder builder = new StringBuilder();
        if (startMenuCheckBox.Checked)
        {
            builder.Append(" startmenu");
        }
        if (desktopIconCheckBox.Checked)
        {
            builder.Append(" desktopicon");
        }
        if (printerCheckBox.Checked)
        {
            builder.Append(" printer");
        }
        builder.Append(" fixedautopassword=");
        builder.Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(password)));
        return builder.ToString().Trim();
    }

    private void LaunchInstalledClient()
    {
        string extractedExePath = Path.Combine(pathTextBox.Text.Trim(), "TGdesk.exe");
        if (File.Exists(extractedExePath))
        {
            Process.Start(new ProcessStartInfo(extractedExePath)
            {
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(extractedExePath),
            });
        }
    }
}
