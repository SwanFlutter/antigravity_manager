param(
  [int]$AppPid = 26324,
  [string]$TitleContains = 'antigravity_manager',
  [string]$Points = '',
  [string]$Out = 'C:\Users\SjjadKarimi\AppData\Local\Temp\probe_out.txt'
)

$src = @'
using System;
using System.Text;
using System.Drawing;
using System.Runtime.InteropServices;

public class Pr {
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern void mouse_event(uint flags, int dx, int dy, uint data, int extra);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetForegroundWindow(IntPtr h);

  public delegate bool EnumProc(IntPtr h, IntPtr l);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }

  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;

  public static IntPtr Find(uint pid, string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      uint p; GetWindowThreadProcessId(h, out p);
      if (pid != 0 && p != pid) return true;
      int len = GetWindowTextLength(h);
      if (len == 0) return true;
      var sb = new StringBuilder(len + 1);
      GetWindowText(h, sb, sb.Capacity);
      string t = sb.ToString();
      if (pid == 0 && title.Length > 0 && t.IndexOf(title, StringComparison.OrdinalIgnoreCase) < 0) return true;
      RECT r; GetClientRect(h, out r);
      if (r.Right - r.Left < 400) return true;
      found = h;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static int O_X(IntPtr h) { POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o); return o.X; }
  public static int O_Y(IntPtr h) { POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o); return o.Y; }
  public static int C_W(IntPtr h) { RECT r; GetClientRect(h, out r); return r.Right - r.Left; }
  public static int C_H(IntPtr h) { RECT r; GetClientRect(h, out r); return r.Bottom - r.Top; }

  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    mouse_event(LEFTDOWN, 0, 0, 0, 0);
    mouse_event(LEFTUP, 0, 0, 0, 0);
  }

  public static double AvgRegion(int sx, int sy, int half) {
    var bmp = new Bitmap(half * 2, half * 2);
    using (var g = Graphics.FromImage(bmp)) {
      g.CopyFromScreen(sx - half, sy - half, 0, 0, new Size(half * 2, half * 2));
    }
    double sum = 0; int n = 0;
    for (int i = 0; i < half * 2; i += 2) {
      for (int j = 0; j < half * 2; j += 2) {
        Color c = bmp.GetPixel(i, j);
        sum += c.R + c.G + c.B; n++;
      }
    }
    bmp.Dispose();
    return sum / (n * 3);
  }
}
'@

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $src
Add-Type -AssemblyName System.Drawing

$hwnd = [Pr]::Find($AppPid, $TitleContains)
if ($hwnd -eq [IntPtr]::Zero) { "NOT_FOUND"; exit 1 }
$ox = [Pr]::O_X($hwnd); $oy = [Pr]::O_Y($hwnd)
$cw = [Pr]::C_W($hwnd); $ch = [Pr]::C_H($hwnd)
[Pr]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

# neutral park point: just left of the client area, vertically centered
$nx = $ox - 8
$ny = $oy + [int]($ch / 2)

$half = 12
$results = foreach ($pair in $Points.Split(';')) {
  if ([string]::IsNullOrWhiteSpace($pair)) { continue }
  $parts = $pair.Split(',')
  $px = [int]$parts[0]; $py = [int]$parts[1]
  [Pr]::SetCursorPos($nx, $ny) | Out-Null
  Start-Sleep -Milliseconds 280
  $before = [Pr]::AvgRegion($ox + $px, $oy + $py, $half)
  [Pr]::SetCursorPos($ox + $px, $oy + $py) | Out-Null
  Start-Sleep -Milliseconds 320
  $after = [Pr]::AvgRegion($ox + $px, $oy + $py, $half)
  $delta = [math]::Round($after - $before, 1)
  "{0},{1}  delta={2}  before={3} after={4}" -f $px, $py, $delta, [math]::Round($before,1), [math]::Round($after,1)
}
$results | Set-Content -Path $Out -Encoding UTF8
"origin=$ox,$oy size=${cw}x${ch}"
$results
