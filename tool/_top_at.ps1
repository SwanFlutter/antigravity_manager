param(
  [string]$Xs = '',
  [string]$Ys = ''
)

$xa = $Xs.Split(',') | ForEach-Object { [int]($_ -replace '[^0-9-]', '') }
$ya = $Ys.Split(',') | ForEach-Object { [int]($_ -replace '[^0-9-]', '') }

$src = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class TopAt {
  [DllImport("user32.dll", SetLastError = true)]
  public static extern IntPtr WindowFromPoint(int x, int y);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool GetWindowRect(IntPtr h, out RECT r);

  public const uint GA_ROOT = 2;

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

  public static string At(int x, int y) {
    IntPtr h = WindowFromPoint(x, y);
    if (h == IntPtr.Zero) return string.Format("({0},{1}) -> ZERO", x, y);
    IntPtr root = GetAncestor(h, GA_ROOT);
    uint pid; GetWindowThreadProcessId(root, out pid);
    var sb = new StringBuilder(256);
    GetWindowText(root, sb, sb.Capacity);
    var cb = new StringBuilder(256);
    GetClassName(root, cb, cb.Capacity);
    RECT r; GetWindowRect(root, out r);
    return string.Format("({0},{1}) -> hwnd={2} pid={3} cls={4} rect={5},{6}-{7},{8} title={9}",
      x, y, root, pid, cb.ToString(), r.Left, r.Top, r.Right, r.Bottom, sb.ToString());
  }
}
'@

Add-Type -TypeDefinition $src

for ($i = 0; $i -lt $xa.Count; $i++) {
  [TopAt]::At($xa[$i], $ya[$i])
}
