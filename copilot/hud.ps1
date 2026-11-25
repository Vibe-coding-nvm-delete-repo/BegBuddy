# BegBuddy Copilot — Native Windows Always-On-Top WPF HUD
# Floats cleanly in the corner over Borderless WoW. Never touches WoW or injects keys.
param([int]$Port = 4789)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$baseUrl = "http://127.0.0.1:$Port"

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="BegBuddy Copilot" Width="430" Height="590"
        Topmost="True" WindowStartupLocation="Manual" Left="40" Top="40"
        Background="#111216" Foreground="#E6E6EB" ResizeMode="CanResizeWithGrip">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" Margin="0,0,0,8">
      <TextBlock Text="BegBuddy Copilot" FontSize="15" FontWeight="Bold" Foreground="#FFD100" VerticalAlignment="Center"/>
      <Button x:Name="BtnTest" Content="Test" Width="48" Height="22" Margin="6,0,0,0" DockPanel.Dock="Right"
              Background="#22242E" Foreground="#D0D2DC" BorderBrush="#3A3D4D"/>
      <Border x:Name="StatusBadge" Background="#2D2414" CornerRadius="10" Padding="8,2" Margin="8,0,0,0" DockPanel.Dock="Right">
        <TextBlock x:Name="StatusText" Text="Starting..." FontSize="11" FontWeight="SemiBold" Foreground="#FFD100"/>
      </Border>
    </DockPanel>

    <Grid Grid.Row="1" Margin="0,0,0,6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="62"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <TextBlock Text="AI Model:" Foreground="#9A9CA8" VerticalAlignment="Center" FontSize="12"/>
      <ComboBox x:Name="ModelBox" Grid.Column="1" Background="#1A1B22" Foreground="#111216" BorderBrush="#2E313D" Padding="4,2" FontSize="11.5">
        <ComboBoxItem Tag="cf-llama-fast" Content="Cloudflare: Llama 3.1 8B Fast (~5,900 free/day)"/>
        <ComboBoxItem Tag="cf-gemma4" Content="Cloudflare: Gemma 4 26B (~4,000 free/day)"/>
        <ComboBoxItem Tag="cf-granite-micro" Content="Cloudflare: Granite 4 Micro (~17,700 free/day)"/>
        <ComboBoxItem Tag="deepseek" Content="DeepSeek Chat"/>
      </ComboBox>
    </Grid>

    <Grid Grid.Row="2" Margin="0,0,0,6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="62"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="56"/>
      </Grid.ColumnDefinitions>
      <TextBlock Text="Location:" Foreground="#9A9CA8" VerticalAlignment="Center" FontSize="12"/>
      <TextBox x:Name="LocBox" Grid.Column="1" Background="#1A1B22" Foreground="#FFFFFF" BorderBrush="#2E313D" Padding="4,2" FontSize="12"/>
      <Button x:Name="BtnSaveLoc" Grid.Column="2" Content="Save" Margin="4,0,0,0" Background="#1B4D2A" Foreground="#FFFFFF" BorderBrush="#35A858" FontSize="11" FontWeight="SemiBold"/>
    </Grid>

    <Grid Grid.Row="3" Margin="0,0,0,6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="62"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="56"/>
      </Grid.ColumnDefinitions>
      <TextBlock Text="Prompt:" Foreground="#9A9CA8" VerticalAlignment="Top" Margin="0,4,0,0" FontSize="12"/>
      <TextBox x:Name="PromptBox" Grid.Column="1" Height="46" TextWrapping="Wrap" AcceptsReturn="False"
               VerticalScrollBarVisibility="Auto" Background="#1A1B22" Foreground="#D8DAE4" BorderBrush="#2E313D" Padding="4,2" FontSize="11"/>
      <Button x:Name="BtnSavePrompt" Grid.Column="2" Content="Save" Height="24" VerticalAlignment="Top" Margin="4,0,0,0"
              Background="#1B4D2A" Foreground="#FFFFFF" BorderBrush="#35A858" FontSize="11" FontWeight="SemiBold"/>
    </Grid>

    <Grid Grid.Row="4" Margin="0,0,0,6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="62"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="56"/>
      </Grid.ColumnDefinitions>
      <TextBlock Text="API Key:" Foreground="#9A9CA8" VerticalAlignment="Center" FontSize="12"/>
      <PasswordBox x:Name="KeyBox" Grid.Column="1" Background="#1A1B22" Foreground="#FFFFFF" BorderBrush="#2E313D" Padding="4,2" FontSize="12"/>
      <Button x:Name="BtnSaveKey" Grid.Column="2" Content="Set Key" Margin="4,0,0,0" Background="#22242E" Foreground="#FFD100" BorderBrush="#5A4B20" FontSize="11" FontWeight="SemiBold"/>
    </Grid>

    <DockPanel Grid.Row="5" Margin="0,0,0,8">
      <CheckBox x:Name="ChkAutoCopy" Content="Auto-copy newest reply (R -> Ctrl+V -> Enter)" IsChecked="True"
                Foreground="#B8BAC6" FontSize="11.5" VerticalAlignment="Center"/>
      <TextBlock x:Name="KeyStatus" Text="" Foreground="#888A96" FontSize="11" DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center"/>
    </DockPanel>

    <ScrollViewer Grid.Row="6" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="DraftsPanel"/>
    </ScrollViewer>

    <TextBlock Grid.Row="7" Margin="0,6,0,0" FontSize="11" Foreground="#7A7D8A" TextWrapping="Wrap"
               Text="In WoW: click AI Copilot in BegBuddy once. When a whisper arrives, just press R -> Ctrl+V -> Enter."/>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$StatusBadge   = $win.FindName("StatusBadge")
$StatusText    = $win.FindName("StatusText")
$ModelBox      = $win.FindName("ModelBox")
$LocBox        = $win.FindName("LocBox")
$PromptBox     = $win.FindName("PromptBox")
$KeyBox        = $win.FindName("KeyBox")
$BtnSaveLoc    = $win.FindName("BtnSaveLoc")
$BtnSavePrompt = $win.FindName("BtnSavePrompt")
$BtnSaveKey    = $win.FindName("BtnSaveKey")
$BtnTest       = $win.FindName("BtnTest")
$ChkAutoCopy   = $win.FindName("ChkAutoCopy")
$KeyStatus     = $win.FindName("KeyStatus")
$DraftsPanel   = $win.FindName("DraftsPanel")

function Post-Api($path, $obj) {
  $json = ($obj | ConvertTo-Json -Depth 4 -Compress)
  Invoke-RestMethod -Method Post -Uri "$baseUrl$path" -TimeoutSec 5 -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($json))
}

$script:loadedCfg = $false
$script:lastSig = $null

function Render-State($s) {
  if ($s.status -eq "watching") {
    $StatusText.Text = "Watching /chatlog"
    $StatusText.Foreground = "#7FE07F"
    $StatusBadge.Background = "#1D2A20"
  } else {
    $StatusText.Text = "Type /chatlog in WoW"
    $StatusText.Foreground = "#FFD100"
    $StatusBadge.Background = "#2D2414"
  }
  $KeyStatus.Text = if ($s.config.apiKeySet) { "Key: $($s.config.apiKeyMasked)" } else { "No API key" }
  if (-not $script:loadedCfg) {
    $LocBox.Text = [string]$s.config.location
    $PromptBox.Text = [string]$s.config.persona
    $ChkAutoCopy.IsChecked = [bool]$s.config.autoCopy
    $wantPreset = if ($s.config.preset) { [string]$s.config.preset } else { "cf-llama-fast" }
    for ($i = 0; $i -lt $ModelBox.Items.Count; $i++) {
      if ($ModelBox.Items[$i].Tag -eq $wantPreset) { $ModelBox.SelectedIndex = $i; break }
    }
    $script:loadedCfg = $true
  }

  $sig = ($s.drafts | ForEach-Object { "$($_.id)|$($_.reply)|$($_.copied)|$($_.error)" }) -join ";"
  if ($sig -eq $script:lastSig) { return }
  $script:lastSig = $sig

  $DraftsPanel.Children.Clear()
  if (-not $s.drafts -or $s.drafts.Count -eq 0) {
    $empty = New-Object System.Windows.Controls.TextBlock
    $empty.Text = "Waiting for incoming whispers...`nClick 'Test' above to try a sample whisper right now."
    $empty.Foreground = "#7A7D8A"
    $empty.TextWrapping = "Wrap"
    $empty.Margin = "4,12,4,4"
    $DraftsPanel.Children.Add($empty) | Out-Null
    return
  }

  $shown = $s.drafts | Select-Object -First 8
  foreach ($d in $shown) {
    $border = New-Object System.Windows.Controls.Border
    $border.Background = "#181A22"
    $border.BorderBrush = if ($d.copied) { "#35A858" } else { "#2A2D3A" }
    $border.BorderThickness = "1"
    $border.CornerRadius = "6"
    $border.Padding = "8"
    $border.Margin = "0,0,0,8"

    $sp = New-Object System.Windows.Controls.StackPanel

    $hdr = New-Object System.Windows.Controls.TextBlock
    $tag = if ($d.copied) { "  [COPIED]" } elseif ($d.skip) { "  [DECLINE]" } else { "" }
    $hdr.Text = "$($d.shortName)  ($($d.source))$tag"
    $hdr.Foreground = if ($d.copied) { "#7FE07F" } else { "#5CC8FF" }
    $hdr.FontWeight = "Bold"
    $hdr.FontSize = 12
    $sp.Children.Add($hdr) | Out-Null

    $inc = New-Object System.Windows.Controls.TextBlock
    $inc.Text = "`"$($d.incoming)`""
    $inc.Foreground = "#A8ABB8"
    $inc.TextWrapping = "Wrap"
    $inc.Margin = "0,3,0,4"
    $inc.FontSize = 11.5
    $sp.Children.Add($inc) | Out-Null

    $rep = New-Object System.Windows.Controls.TextBlock
    $rep.Text = [string]$d.reply
    $rep.Foreground = "#7FE07F"
    $rep.FontWeight = "SemiBold"
    $rep.TextWrapping = "Wrap"
    $rep.FontSize = 13
    $sp.Children.Add($rep) | Out-Null

    if ($d.error) {
      $err = New-Object System.Windows.Controls.TextBlock
      $err.Text = [string]$d.error
      $err.Foreground = "#FF8080"
      $err.TextWrapping = "Wrap"
      $err.FontSize = 10.5
      $err.Margin = "0,3,0,0"
      $sp.Children.Add($err) | Out-Null
    }

    $btnRow = New-Object System.Windows.Controls.StackPanel
    $btnRow.Orientation = "Horizontal"
    $btnRow.Margin = "0,6,0,0"

    $cpBtn = New-Object System.Windows.Controls.Button
    $cpBtn.Content = "Copy Reply"
    $cpBtn.Padding = "10,3"
    $cpBtn.Background = "#1B4D2A"
    $cpBtn.Foreground = "#FFFFFF"
    $cpBtn.BorderBrush = "#35A858"
    $cpBtn.FontWeight = "SemiBold"
    $cpBtn.FontSize = 11.5
    $cpBtn.Tag = @{ id = $d.id; text = [string]$d.reply }
    $cpBtn.Add_Click({
      param($sender, $e)
      $info = $sender.Tag
      try {
        Post-Api "/api/copy" @{ id = $info.id; text = $info.text } | Out-Null
        $script:lastSig = ""
      } catch {}
    })
    $btnRow.Children.Add($cpBtn) | Out-Null

    $rgBtn = New-Object System.Windows.Controls.Button
    $rgBtn.Content = "Retry"
    $rgBtn.Padding = "8,3"
    $rgBtn.Margin = "6,0,0,0"
    $rgBtn.Background = "#22242E"
    $rgBtn.Foreground = "#D0D2DC"
    $rgBtn.BorderBrush = "#3A3D4D"
    $rgBtn.FontSize = 11.5
    $rgBtn.Tag = $d.id
    $rgBtn.Add_Click({
      param($sender, $e)
      try {
        Post-Api "/api/regenerate" @{ id = $sender.Tag } | Out-Null
        $script:lastSig = ""
      } catch {}
    })
    $btnRow.Children.Add($rgBtn) | Out-Null

    $sp.Children.Add($btnRow) | Out-Null
    $border.Child = $sp
    $DraftsPanel.Children.Add($border) | Out-Null
  }
}

$ModelBox.Add_SelectionChanged({
  if (-not $script:loadedCfg) { return }
  $item = $ModelBox.SelectedItem
  if ($item -and $item.Tag) {
    try { Post-Api "/api/config" @{ preset = [string]$item.Tag } | Out-Null } catch {}
  }
})
$BtnSaveLoc.Add_Click({
  try { Post-Api "/api/config" @{ location = $LocBox.Text } | Out-Null } catch {}
})
$BtnSavePrompt.Add_Click({
  try { Post-Api "/api/config" @{ persona = $PromptBox.Text } | Out-Null } catch {}
})
$BtnSaveKey.Add_Click({
  $k = $KeyBox.Password
  if ($k) {
    try {
      Post-Api "/api/config" @{ apiKey = $k } | Out-Null
      $KeyBox.Clear()
    } catch {}
  }
})
$ChkAutoCopy.Add_Click({
  try { Post-Api "/api/config" @{ autoCopy = [bool]$ChkAutoCopy.IsChecked } | Out-Null } catch {}
})
$BtnTest.Add_Click({
  try {
    Post-Api "/api/test-whisper" @{ sender = "Shadow Dru"; text = "lol sure where are you at?" } | Out-Null
    $script:lastSig = ""
  } catch {}
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(800)
$timer.Add_Tick({
  try {
    $s = Invoke-RestMethod -Uri "$baseUrl/api/state" -TimeoutSec 2
    Render-State $s
  } catch {}
})
$timer.Start()

$win.ShowDialog() | Out-Null
$timer.Stop()
