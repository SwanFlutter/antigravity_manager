param(
  [int]$AppPid = 26324,
  [string]$TitleContains = 'antigravity_manager',
  [int]$ClickX = 1166,
  [int]$ClickY = 46,
  [int]$WaitMs = 2500,
  [string]$Out = 'C:\Users\SjjadKarimi\AppData\Local\Temp\app_clicked.png'
)

$src = @'
using System;
using System.Text;
using System.Drawing;
using System.Runtime.InteropServices;

public class Cl {
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
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool IsIconic(IntPtr h);

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
      bool iconic = IsIconic(h);
      if (!iconic && r.Right - r.Left < 400) return true;
      found = h;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static void Focus(IntPtr h) {
    if (IsIconic(h)) { ShowWindow(h, 9); System.Threading.Thread.Sleep(400); }
    SetForegroundWindow(h);
  }
  public static int O_X(IntPtr h) { POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o); return o.X; }
  public static int O_Y(IntPtr h) { POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o); return o.Y; }

  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(90);
    mouse_event(LEFTDOWN, 0, 0, 0, 0);
    System.Threading.Thread.Sleep(40);
    mouse_event(LEFTUP, 0, 0, 0, 0);
  }

  public static string Save(IntPtr h, string path) {
    RECT r; GetClientRect(h, out r);
    POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o);
    int w = r.Right - r.Left, hgt = r.Bottom - r.Top;
    var bmp = new Bitmap(w, hgt);
    using (var g = Graphics.FromImage(bmp)) { g.CopyFromScreen(o.X, o.Y, 0, 0, new Size(w, hgt)); }
    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    bmp.Dispose();
    return w + "x" + hgt + " at " + o.X + "," + o.Y;
  }
}
'@

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $src
Add-Type -AssemblyName System.Drawing

$hwnd = [Cl]::Find($AppPid, $TitleContains)
if ($hwnd -eq [IntPtr]::Zero) { "NOT_FOUND"; exit 1 }
[Cl]::Focus($hwnd) | Out-Null
Start-Sleep -Milliseconds 600
$ox = [Cl]::O_X($hwnd); $oy = [Cl]::O_Y($hwnd)
[Cl]::Click($ox + $ClickX, $oy + $ClickY)
Start-Sleep -Milliseconds $WaitMs
$info = [Cl]::Save($hwnd, $Out)
"Clicked at client ($ClickX,$ClickY) -> screen ($($ox + $ClickX),$($oy + $ClickY))"
"Saved $Out  $info"
