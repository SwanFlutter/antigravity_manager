param(
  [int]$AppPid = 26324,
  [string]$TitleContains = 'antigravity_manager',
  [string]$Out = 'C:\Users\SjjadKarimi\AppData\Local\Temp\app_now.png'
)

$src = @'
using System;
using System.Text;
using System.Drawing;
using System.Runtime.InteropServices;

public class Cap {
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
  public static extern bool IsIconic(IntPtr h);

  public delegate bool EnumProc(IntPtr h, IntPtr l);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }

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

  public static string Save(IntPtr h, string path) {
    RECT r; GetClientRect(h, out r);
    POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o);
    int w = r.Right - r.Left;
    int hgt = r.Bottom - r.Top;
    var bmp = new Bitmap(w, hgt);
    using (var g = Graphics.FromImage(bmp)) {
      g.CopyFromScreen(o.X, o.Y, 0, 0, new Size(w, hgt));
    }
    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    bmp.Dispose();
    return string.Format("{0}x{1} at {2},{3}", w, hgt, o.X, o.Y);
  }
}
'@

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $src
Add-Type -AssemblyName System.Drawing

$hwnd = [Cap]::Find($AppPid, $TitleContains)
if ($hwnd -eq [IntPtr]::Zero) {
  "NOT_FOUND"
  exit 1
}
$info = [Cap]::Save($hwnd, $Out)
"Saved $Out  $info"
