param(
  [int]$AppPid = 0,
  [string]$TitleContains = 'antigravity_manager',
  [int]$WaitMs = 1200
)

$src = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Foc {
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
  public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern void SwitchToThisWindow(IntPtr h, bool alt);

  public delegate bool EnumProc(IntPtr h, IntPtr l);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }

  public const int SW_RESTORE = 9;
  public const uint SWP_SHOWWINDOW = 0x0040;
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOMOVE = 0x0002;
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
  public static readonly IntPtr HWND_TOP = new IntPtr(0);

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

  public static string Info(IntPtr h) {
    RECT r; GetClientRect(h, out r);
    POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o);
    return string.Format("client {0}x{1} at {2},{3}", r.Right - r.Left, r.Bottom - r.Top, o.X, o.Y);
  }

  public static void Focus(IntPtr h) {
    ShowWindow(h, SW_RESTORE);
    SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetForegroundWindow(h);
    BringWindowToTop(h);
    SwitchToThisWindow(h, true);
    SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  }
}
'@

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition $src

$hwnd = [Foc]::Find($AppPid, $TitleContains)
if ($hwnd -eq [IntPtr]::Zero) {
  "NOT_FOUND pid=$AppPid title=$TitleContains"
  exit 1
}
[Foc]::Focus($hwnd)
Start-Sleep -Milliseconds $WaitMs
"Focused hwnd=$hwnd pid=$AppPid"
[Foc]::Info($hwnd)
"foreground=$([Foc]::GetForegroundWindow())"
