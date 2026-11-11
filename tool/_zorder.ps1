$src = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Z {
  [DllImport("user32.dll", SetLastError = true)]
  public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool GetWindowRect(IntPtr h, out RECT r);

  public const uint GW_HWNDFIRST = 0;
  public const uint GW_HWNDNEXT = 2;

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
'@

Add-Type -TypeDefinition $src

$h = [Z]::GetWindow([IntPtr]::Zero, [Z]::GW_HWNDFIRST)
$i = 0
while ($h -ne [IntPtr]::Zero -and $i -lt 25) {
  if ([Z]::IsWindowVisible($h)) {
    $pid = 0
    [Z]::GetWindowThreadProcessId($h, [ref]$pid) | Out-Null
    $sb = New-Object System.Text.StringBuilder(256)
    [Z]::GetWindowText($h, $sb, $sb.Capacity) | Out-Null
    $proc = (Get-Process -Id $pid -ErrorAction SilentlyContinue).ProcessName
    "$i hwnd=$h pid=$pid proc=$proc title=$($sb.ToString())"
  }
  $h = [Z]::GetWindow($h, [Z]::GW_HWNDNEXT)
  $i++
}
